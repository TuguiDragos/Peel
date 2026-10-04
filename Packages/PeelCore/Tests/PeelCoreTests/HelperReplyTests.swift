import Foundation
@testable import PeelCore
import PeelPrivileged
import Synchronization
import Testing

/// The helper's trash method as a dishonest helper would answer it: the same selector, with replies of any kind.
@objc private protocol LooseTrashReplies {
    @objc(moveItemsToTrashWithVersion:atPaths:withReply:)
    func moveItemsToTrash(
        version: Int,
        atPaths paths: [String],
        withReply reply: @escaping (NSDictionary, NSDictionary) -> Void
    )
}

private final class Answers: NSObject, LooseTrashReplies, NSXPCListenerDelegate {
    let moved: NSDictionary

    init(moved: NSDictionary) {
        self.moved = moved
    }

    func moveItemsToTrash(
        version: Int,
        atPaths paths: [String],
        withReply reply: @escaping (NSDictionary, NSDictionary) -> Void
    ) {
        reply(moved, [:] as NSDictionary)
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: (any LooseTrashReplies).self)
        connection.exportedObject = self
        connection.resume()
        return true
    }
}

struct HelperReplyTests {
    private static let path = "/Users/x/Library/Caches/org.example.app"

    /// NSXPC checks a reply's classes where the reply is decoded, which is Peel's side, so Peel accepts from the
    /// helper only the strings its answer is made of.
    @Test func refusesAReplyThatIsNotStrings() async throws {
        #expect(await answer(to: [Self.path: NSNumber(value: 42)]) == "refused: \(NSXPCConnectionReplyInvalid)")
    }

    @Test func takesAReplyOfStrings() async throws {
        #expect(await answer(to: [Self.path: "/Users/x/.Trash/org.example.app"]) == "accepted 1")
    }

    private func answer(to moved: NSDictionary) async -> String {
        let helper = Answers(moved: moved)
        let listener = NSXPCListener.anonymous()
        listener.delegate = helper
        listener.resume()
        defer { listener.invalidate() }
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        connection.remoteObjectInterface = PrivilegedHelper.remoteInterface()
        connection.resume()
        defer { connection.invalidate() }

        let answer = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            let answered = Mutex(false)
            let finish: @Sendable (String) -> Void = { text in
                let isFirst = answered.withLock { answered in
                    defer { answered = true }
                    return !answered
                }
                if isFirst { continuation.resume(returning: text) }
            }
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                finish("refused: \((error as NSError).code)")
            } as? any PeelHelperProtocol
            proxy?.moveItemsToTrash(version: HelperIdentity.protocolVersion, atPaths: [Self.path]) { moved, _ in
                finish("accepted \(moved.count)")
            }
        }
        return answer
    }
}

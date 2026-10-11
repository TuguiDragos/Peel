import Foundation
@testable import PeelCore
import PeelPrivileged
import Synchronization
import Testing

/// The helper's version question, under the selector Peel sends.
@objc private protocol VersionQuestion {
    @objc(protocolVersionWithReply:)
    func protocolVersion(withReply reply: @escaping (Int) -> Void)
}

private final class StandInHelper: NSObject, VersionQuestion, NSXPCListenerDelegate {
    private let version: Int?
    private let listener = NSXPCListener.anonymous()
    let handledAt = Mutex<UInt32?>(nil)

    init(answering version: Int?) {
        self.version = version
        super.init()
        listener.delegate = self
        listener.resume()
    }

    var connecting: @Sendable () -> NSXPCConnection? {
        let endpoint = listener.endpoint
        return { NSXPCConnection(listenerEndpoint: endpoint) }
    }

    func stop() {
        listener.invalidate()
    }

    func protocolVersion(withReply reply: @escaping (Int) -> Void) {
        handledAt.withLock { $0 = qos_class_self().rawValue }
        if let version { reply(version) }
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: (any VersionQuestion).self)
        connection.exportedObject = self
        connection.resume()
        return true
    }
}

private final class Record<Value: Sendable>: Sendable {
    let value: Mutex<Value>

    init(_ value: Value) {
        self.value = Mutex(value)
    }
}

struct HelperAnswerTests {
    /// As long as a request waits, so only what the stand-in answers decides, however busy the suite keeps the Mac.
    private static let anyWait = PrivilegedHelper.requestWait

    @Test func theTimerThatEndsAWaitForTheHelperNeverWaitsBehindWorkOfLowerQuality() {
        #expect(PrivilegedHelper.timers.label == DispatchQueue.global(qos: .userInitiated).label)
    }

    @Test func aHelperThatNeverAnswersIsNotAnsweringOnceItsOwnWaitEnds() async {
        let helper = StandInHelper(answering: nil)
        defer { helper.stop() }
        let start = ContinuousClock.now

        #expect(await !PrivilegedHelper.isResponding(connecting: helper.connecting))
        #expect(ContinuousClock.now - start < .seconds(PrivilegedHelper.requestWait))
    }

    @Test func theHelperOfThisVersionIsAnswering() async {
        let helper = StandInHelper(answering: HelperIdentity.protocolVersion)
        defer { helper.stop() }

        #expect(await PrivilegedHelper.isResponding(connecting: helper.connecting, waitingAtMost: Self.anyWait))
    }

    @Test func aHelperOfAnotherVersionIsNotAnswering() async {
        let helper = StandInHelper(answering: HelperIdentity.protocolVersion - 1)
        defer { helper.stop() }

        #expect(await !PrivilegedHelper.isResponding(connecting: helper.connecting, waitingAtMost: Self.anyWait))
    }

    @Test func withNoConnectionThereIsNoAnswer() async {
        #expect(await !PrivilegedHelper.isResponding(connecting: { nil }))
    }

    @Test func aRequestIsNeverSentToAHelperThatDoesNotAnswer() async {
        let helper = StandInHelper(answering: nil)
        defer { helper.stop() }
        let sent = Record(false)
        let start = ContinuousClock.now

        let answer = await PrivilegedHelper.request(connecting: helper.connecting, fallback: "unanswered") {
            _, finish in
            sent.value.withLock { $0 = true }
            finish("answered")
        }

        #expect(answer == "unanswered")
        #expect(!sent.value.withLock { $0 })
        #expect(ContinuousClock.now - start < .seconds(PrivilegedHelper.requestWait))
    }

    @Test func aRequestIsSentToTheHelperOfThisVersion() async {
        let helper = StandInHelper(answering: HelperIdentity.protocolVersion)
        defer { helper.stop() }

        let answer = await PrivilegedHelper.request(
            connecting: helper.connecting, answerWait: Self.anyWait, fallback: "unanswered"
        ) { _, finish in
            finish("answered")
        }

        #expect(answer == "answered")
    }

    @Test func theHelperIsAskedAtTheQualityOfItsWaitWhateverTheTaskThatAsks() async {
        let helper = StandInHelper(answering: HelperIdentity.protocolVersion)
        defer { helper.stop() }
        let connecting = helper.connecting
        let sentAt = Record<UInt32?>(nil)

        _ = await Task.detached(priority: .background) {
            await PrivilegedHelper.request(connecting: connecting, answerWait: Self.anyWait, fallback: false) {
                _, finish in
                sentAt.value.withLock { $0 = qos_class_self().rawValue }
                finish(true)
            }
        }.value

        #expect((helper.handledAt.withLock { $0 } ?? 0) >= QOS_CLASS_USER_INITIATED.rawValue)
        #expect((sentAt.value.withLock { $0 } ?? 0) >= QOS_CLASS_USER_INITIATED.rawValue)
    }
}

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

    init(answering version: Int?) {
        self.version = version
        super.init()
        listener.delegate = self
        listener.resume()
    }

    var connection: NSXPCConnection {
        NSXPCConnection(listenerEndpoint: listener.endpoint)
    }

    func stop() {
        listener.invalidate()
    }

    func protocolVersion(withReply reply: @escaping (Int) -> Void) {
        if let version { reply(version) }
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: (any VersionQuestion).self)
        connection.exportedObject = self
        connection.resume()
        return true
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

        #expect(await !PrivilegedHelper.isResponding(over: helper.connection))
        #expect(ContinuousClock.now - start < .seconds(PrivilegedHelper.requestWait))
    }

    @Test func theHelperOfThisVersionIsAnswering() async {
        let helper = StandInHelper(answering: HelperIdentity.protocolVersion)
        defer { helper.stop() }

        #expect(await PrivilegedHelper.isResponding(over: helper.connection, waitingAtMost: Self.anyWait))
    }

    @Test func aHelperOfAnotherVersionIsNotAnswering() async {
        let helper = StandInHelper(answering: HelperIdentity.protocolVersion - 1)
        defer { helper.stop() }

        #expect(await !PrivilegedHelper.isResponding(over: helper.connection, waitingAtMost: Self.anyWait))
    }

    @Test func withNoConnectionThereIsNoAnswer() async {
        #expect(await !PrivilegedHelper.isResponding(over: nil))
    }

    @Test func aRequestIsNeverSentToAHelperThatDoesNotAnswer() async {
        let helper = StandInHelper(answering: nil)
        defer { helper.stop() }
        let sent = Mutex(false)
        let start = ContinuousClock.now

        let answer = await PrivilegedHelper.request(connecting: { helper.connection }, fallback: "unanswered") {
            _, finish in
            sent.withLock { $0 = true }
            finish("answered")
        }

        #expect(answer == "unanswered")
        #expect(!sent.withLock { $0 })
        #expect(ContinuousClock.now - start < .seconds(PrivilegedHelper.requestWait))
    }

    @Test func aRequestIsSentToTheHelperOfThisVersion() async {
        let helper = StandInHelper(answering: HelperIdentity.protocolVersion)
        defer { helper.stop() }

        let answer = await PrivilegedHelper.request(
            connecting: { helper.connection }, answerWait: Self.anyWait, fallback: "unanswered"
        ) { _, finish in
            finish("answered")
        }

        #expect(answer == "answered")
    }
}

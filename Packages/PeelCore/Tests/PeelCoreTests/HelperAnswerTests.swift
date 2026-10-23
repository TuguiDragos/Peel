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
    /// What it answers to each question in turn, the last one again once the others are given.
    private let versions: Mutex<[Int?]>
    private let listener = NSXPCListener.anonymous()
    let handledAt = Mutex<UInt32?>(nil)
    let questions = Mutex(0)

    convenience init(answering version: Int?) {
        self.init(answering: [version])
    }

    init(answering versions: [Int?]) {
        self.versions = Mutex(versions)
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
        questions.withLock { $0 += 1 }
        let version = versions.withLock { $0.count > 1 ? $0.removeFirst() : $0.first ?? nil }
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
        let connecting = helper.connecting

        let question = await timedWhereItRuns { await PrivilegedHelper.isResponding(connecting: connecting) }

        #expect(!question.value)
        #expect(question.took < .seconds(PrivilegedHelper.requestWait))
    }

    @Test func theHelperOfThisVersionIsAnswering() async {
        let helper = StandInHelper(answering: HelperIdentity.protocolVersion)
        defer { helper.stop() }

        #expect(await PrivilegedHelper.isResponding(connecting: helper.connecting, waitingAtMost: Self.anyWait))
    }

    @Test func aHelperAnUpdateLeftRunningGivesWayToTheOneOfThisVersion() async {
        let helper = StandInHelper(answering: [HelperIdentity.protocolVersion - 1, HelperIdentity.protocolVersion])
        defer { helper.stop() }
        let watched = Record<[pid_t]>([])

        let answering = await PrivilegedHelper.isResponding(
            connecting: helper.connecting, waitingAtMost: Self.anyWait
        ) { process, _ in
            watched.value.withLock { $0.append(process) }
            return true
        }

        #expect(answering)
        #expect(watched.value.withLock { $0 } == [getpid()])
    }

    @Test func aHelperOfAnotherVersionIsAskedOnceMoreOnceItsProcessEnds() async {
        let helper = StandInHelper(answering: HelperIdentity.protocolVersion - 1)
        defer { helper.stop() }

        let answering = await PrivilegedHelper.isResponding(
            connecting: helper.connecting, waitingAtMost: Self.anyWait
        ) { _, _ in true }

        #expect(!answering)
        #expect(helper.questions.withLock { $0 } == 2)
    }

    @Test func aHelperOfAnotherVersionWhoseProcessKeepsRunningIsNotAnswering() async {
        let helper = StandInHelper(answering: [HelperIdentity.protocolVersion - 1, HelperIdentity.protocolVersion])
        defer { helper.stop() }

        let answering = await PrivilegedHelper.isResponding(
            connecting: helper.connecting, waitingAtMost: Self.anyWait
        ) { _, _ in false }

        #expect(!answering)
        #expect(helper.questions.withLock { $0 } == 1)
    }

    @Test func withNoConnectionThereIsNoAnswer() async {
        #expect(await !PrivilegedHelper.isResponding(connecting: { nil }))
    }

    @Test func aRequestIsNeverSentToAHelperThatDoesNotAnswer() async {
        let helper = StandInHelper(answering: nil)
        defer { helper.stop() }
        let connecting = helper.connecting
        let sent = Record(false)

        let request = await timedWhereItRuns {
            await PrivilegedHelper.request(connecting: connecting, fallback: "unanswered") { _, finish in
                sent.value.withLock { $0 = true }
                finish("answered")
            }
        }

        #expect(request.value == "unanswered")
        #expect(!sent.value.withLock { $0 })
        #expect(request.took < .seconds(PrivilegedHelper.requestWait))
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

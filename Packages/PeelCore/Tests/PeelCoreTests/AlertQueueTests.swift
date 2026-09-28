@testable import PeelCore
import Testing

struct AlertQueueTests {
    /// A failure that comes while another is on screen waits its turn, rather than changing the alert already
    /// shown or never being told.
    @Test func showsEachInTurn() {
        var queue = AlertQueue<String>()
        #expect(queue.current == nil)

        queue.add("Stop on org.example.one")
        queue.add("Disable on org.example.two")
        #expect(queue.current == "Stop on org.example.one")

        queue.dismissCurrent()
        #expect(queue.current == "Disable on org.example.two")

        queue.dismissCurrent()
        #expect(queue.current == nil)
        queue.dismissCurrent()
        #expect(queue.current == nil)
    }
}

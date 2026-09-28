/// What waits to be told in an alert, one at a time and in the order it came.
public struct AlertQueue<Element> {
    private var waiting: [Element] = []

    public init() {}

    /// The one on screen.
    public var current: Element? { waiting.first }

    public mutating func add(_ element: Element) {
        waiting.append(element)
    }

    public mutating func dismissCurrent() {
        guard !waiting.isEmpty else { return }
        waiting.removeFirst()
    }
}

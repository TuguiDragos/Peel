extension Array where Element: Sendable {
    /// `transform` of every element, at most `width` at a time, in the elements' order. A few slow elements then
    /// hold only their own part of the wait, never the whole list's. Once the task is canceled nothing more starts,
    /// and only the results of the elements already started come back.
    func concurrentMap<Result: Sendable>(
        width: Int,
        _ transform: @escaping @Sendable (Element) async -> Result
    ) async -> [Result] {
        await withTaskGroup(of: (Int, Result).self) { group in
            var pending = enumerated().makeIterator()
            func addNext() -> Bool {
                guard !Task.isCancelled, let (index, element) = pending.next() else { return false }
                group.addTask { (index, await transform(element)) }
                return true
            }
            for _ in 0..<width where addNext() {}
            var results = [Result?](repeating: nil, count: count)
            while let (index, result) = await group.next() {
                results[index] = result
                _ = addNext()
            }
            return results.compactMap(\.self)
        }
    }
}

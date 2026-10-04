import Darwin

enum SignalDisposition {
    /// Whether `number` is ignored now, read without changing it.
    static func isIgnored(_ number: Int32) -> Bool {
        var action = sigaction()
        guard sigaction(number, nil, &action) == 0 else { return false }
        return unsafeBitCast(action.__sigaction_u.__sa_handler, to: Int.self) == unsafeBitCast(SIG_IGN, to: Int.self)
    }
}

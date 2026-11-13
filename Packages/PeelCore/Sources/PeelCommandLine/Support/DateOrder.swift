import Foundation

// The SDK of macOS 27.2 declares `Date.<=` and `Date.>=` back-deployed, which links them weakly to symbols a beta of
// 27.2 may lack. These, of this module, are what its `<=` and `>=` between two dates call, so none links to them.
extension Date {
    static func <= (lhs: Date, rhs: Date) -> Bool { !(rhs < lhs) }
    static func >= (lhs: Date, rhs: Date) -> Bool { !(lhs < rhs) }
}

import Darwin
import Testing

extension Trait where Self == ConditionTrait {
    /// For a test that takes permissions away. Root ignores them, so under root such a test would check nothing.
    static var permissionsHold: Self {
        .disabled(if: geteuid() == 0, "root ignores file permissions, which this test takes away")
    }
}

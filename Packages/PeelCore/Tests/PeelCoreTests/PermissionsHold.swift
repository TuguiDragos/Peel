import Darwin
import Testing

extension Trait where Self == ConditionTrait {
    static var permissionsHold: Self {
        .disabled(if: geteuid() == 0, "root ignores file permissions, which this test takes away")
    }
}

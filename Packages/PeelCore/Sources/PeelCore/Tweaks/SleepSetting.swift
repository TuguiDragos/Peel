import Foundation
internal import IOKit

/// Whether sleep is off altogether, the setting `pmset disablesleep` changes. It survives a restart, doesn't
/// show in System Settings, and blocks even the emergency sleep for overheating or a nearly empty battery, so
/// a Mac that never sleeps is otherwise hard to explain. Changing it needs root, so Peel only reports it.
public enum SleepSetting {
    public static let undoCommand = "sudo pmset -a disablesleep 0"

    public static func isSleepDisabled() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)
        return (value?.takeRetainedValue() as? NSNumber)?.boolValue == true
    }
}

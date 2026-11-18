internal import CoreServices
public import Foundation
internal import PeelPrivileged

/// The quit linkd sends an app it started for an intent once the intent has ended and the app is not in front: an
/// Apple Event from linkd itself, with no reason. A person quits from Peel's menu, the Dock or another app, and a
/// logout, a restart or a shutdown gives its reason.
public enum IntentIdleQuit {
    /// Where linkd is, on the sealed system volume, which nothing else can take.
    static let linkd = "/usr/libexec/linkd"

    public static func isAsked(by event: NSAppleEventDescriptor?) -> Bool {
        guard let event else { return false }
        let sender = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
        return isLinkdsQuit(event, sentBy: sender)
    }

    /// Whether `event` is a quit with no reason from linkd, as `programOf` names the program of the process `sender`.
    static func isLinkdsQuit(
        _ event: NSAppleEventDescriptor,
        sentBy sender: pid_t?,
        programOf: (pid_t) -> String? = RunningProgram.path(of:)
    ) -> Bool {
        guard event.eventClass == AEEventClass(kCoreEventClass), event.eventID == AEEventID(kAEQuitApplication),
              event.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason)) == nil,
              event.paramDescriptor(forKeyword: AEKeyword(kAEQuitReason)) == nil,
              let sender
        else { return false }
        return programOf(sender) == linkd
    }
}

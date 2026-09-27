/// The folders of a Library that Peel looks inside, one by one, and never moves whole: the uninstall and Orphaned
/// Files search them, the Plug-ins tool lists what they hold, and the app's guard and the helper both refuse them.
public enum LibraryFolder: String, CaseIterable, Sendable {
    case applicationSupport = "Application Support"
    case applicationScripts = "Application Scripts"
    case caches = "Caches"
    case containers = "Containers"
    case groupContainers = "Group Containers"
    case preferences = "Preferences"
    case preferencesByHost = "Preferences/ByHost"
    case savedApplicationState = "Saved Application State"
    case recentDocuments = "Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments"
    case logs = "Logs"
    case httpStorages = "HTTPStorages"
    case webKit = "WebKit"
    case cookies = "Cookies"
    case launchAgents = "LaunchAgents"
    case launchDaemons = "LaunchDaemons"
    case privilegedHelperTools = "PrivilegedHelperTools"
    case audioUnits = "Audio/Plug-Ins/Components"
    case audioDrivers = "Audio/Plug-Ins/HAL"
    case vst = "Audio/Plug-Ins/VST"
    case vst3 = "Audio/Plug-Ins/VST3"
    case clap = "Audio/Plug-Ins/CLAP"
    case midiDrivers = "Audio/MIDI Drivers"
    case internetPlugIns = "Internet Plug-Ins"
    case preferencePanes = "PreferencePanes"
    case quickLook = "QuickLook"
    case screenSavers = "Screen Savers"
    case spotlight = "Spotlight"
    case services = "Services"
    case inputMethods = "Input Methods"
    case colorPickers = "ColorPickers"
    case contextualMenuItems = "Contextual Menu Items"
    case mailBundles = "Mail/Bundles"

    /// The folders macOS loads plug-ins from, in each Library.
    public static let plugIns: [LibraryFolder] = [
        .audioUnits, .audioDrivers, .vst, .vst3, .clap, .midiDrivers, .internetPlugIns, .preferencePanes, .quickLook,
        .screenSavers, .spotlight, .services, .inputMethods, .colorPickers, .contextualMenuItems, .mailBundles,
    ]

    /// The folders searched in the home's Library, besides the plug-in folders.
    public static let user: [LibraryFolder] = [
        .applicationSupport, .applicationScripts, .caches, .containers, .groupContainers, .preferences,
        .preferencesByHost, .savedApplicationState, .recentDocuments, .logs, .httpStorages, .webKit, .cookies,
        .launchAgents,
    ]

    /// The folders searched in the Mac's own `/Library`, besides the plug-in folders.
    public static let local: [LibraryFolder] = [
        .applicationSupport, .caches, .preferences, .logs, .launchAgents, .launchDaemons, .privilegedHelperTools,
    ]

    public static let inTheUsersLibrary = user + plugIns
}

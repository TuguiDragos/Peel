extension Plugin.Category {
    /// Where an Intel copy of a plug-in of this kind can load on a Mac with Apple silicon. Rosetta translates a whole
    /// process, and a process never mixes Intel code with Apple silicon code ("About the Rosetta translation
    /// environment"), so a plug-in loaded into an app's own process loads only while that app runs through Rosetta.
    public enum IntelHost: Sendable, Hashable {
        /// In an Intel process macOS keeps for plug-ins of this kind (`intelHostPrograms`).
        case aProcessOfItsOwn
        /// In such a process when the app asks macOS to load it outside its own, and otherwise inside the app.
        case outsideTheAppWhenAsked
        /// Inside the app that uses it.
        case insideTheApp
        case notKnown
    }

    public var intelHost: IntelHost {
        switch self {
        case .audioDrivers, .screenSavers, .preferencePanes, .spotlight: .aProcessOfItsOwn
        case .audioUnits: .outsideTheAppWhenAsked
        case .vst, .vst3, .clap, .aax, .mas, .colorPickers, .imageUnits, .mailBundles, .contactsPlugIns: .insideTheApp
        default: .notKnown
        }
    }

    /// The Intel program macOS keeps to load plug-ins of each kind it hosts, which is what proves it.
    static let intelHostPrograms: [Plugin.Category: String] = [
        .audioDrivers: "/System/Library/Frameworks/CoreAudio.framework/Versions/A/XPCServices/com.apple.audio.Core-Audio-Driver-Service.xpc/Contents/MacOS/com.apple.audio.Core-Audio-Driver-Service",
        .screenSavers: "/System/Library/Frameworks/ScreenSaver.framework/PlugIns/legacyScreenSaver-x86_64.appex/Contents/MacOS/legacyScreenSaver-x86_64",
        .preferencePanes: "/System/Library/Frameworks/PreferencePanes.framework/Versions/A/XPCServices/legacyLoader-x86_64.xpc/Contents/MacOS/legacyLoader-x86_64",
        .spotlight: "/System/Library/Frameworks/CoreServices.framework/Frameworks/Metadata.framework/Versions/A/Support/mdworker_shared",
        .audioUnits: "/System/Library/Frameworks/AudioToolbox.framework/XPCServices/AUHostingServiceXPC.xpc/Contents/MacOS/AUHostingServiceXPC",
    ]
}

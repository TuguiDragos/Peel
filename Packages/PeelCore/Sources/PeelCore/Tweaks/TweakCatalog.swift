import Foundation

/// The settings Peel offers. On macOS 26, each key belongs to the domain it names, and removing the key gives
/// the setting back to macOS. None of them needs administrator rights or a change to a system file.
public enum TweakCatalog {
    public static let all: [Tweak] = dock + screenshots + finder + typing + windows + privacy

    static let dock: [Tweak] = [
        Tweak(
            id: "dock-autohide-delay",
            domain: "com.apple.dock",
            key: "autohide-delay",
            kind: .aSwitch(.number(0)),
            restart: .dock,
            group: .dock,
            hasASystemControl: false
        ),
        Tweak(
            id: "dock-autohide-time",
            domain: "com.apple.dock",
            key: "autohide-time-modifier",
            kind: .aSwitch(.number(0)),
            restart: .dock,
            group: .dock,
            hasASystemControl: false
        ),
        Tweak(
            id: "dock-launchanim",
            domain: "com.apple.dock",
            key: "launchanim",
            kind: .aSwitch(.boolean(false)),
            restart: .dock,
            group: .dock,
            hasASystemControl: true
        ),
        Tweak(
            id: "dock-no-bouncing",
            domain: "com.apple.dock",
            key: "no-bouncing",
            kind: .aSwitch(.boolean(true)),
            restart: .dock,
            group: .dock,
            hasASystemControl: false
        ),
        Tweak(
            id: "dock-static-only",
            domain: "com.apple.dock",
            key: "static-only",
            kind: .aSwitch(.boolean(true)),
            restart: .dock,
            group: .dock,
            hasASystemControl: false
        ),
        Tweak(
            id: "dock-show-recents",
            domain: "com.apple.dock",
            key: "show-recents",
            kind: .aSwitch(.boolean(false)),
            restart: .dock,
            group: .dock,
            hasASystemControl: true
        ),
        Tweak(
            id: "dock-minimize-to-application",
            domain: "com.apple.dock",
            key: "minimize-to-application",
            kind: .aSwitch(.boolean(true)),
            restart: .dock,
            group: .dock,
            hasASystemControl: true
        ),
        Tweak(
            id: "dock-mru-spaces",
            domain: "com.apple.dock",
            key: "mru-spaces",
            kind: .aSwitch(.boolean(false)),
            restart: .dock,
            group: .dock,
            hasASystemControl: true
        ),
    ]

    static let screenshots: [Tweak] = [
        Tweak(
            id: "screenshot-thumbnail",
            domain: "com.apple.screencapture",
            key: "show-thumbnail",
            kind: .aSwitch(.boolean(false)),
            restart: .none,
            group: .screenshots,
            hasASystemControl: true
        ),
        Tweak(
            id: "screenshot-location",
            domain: "com.apple.screencapture",
            key: "location",
            kind: .folder,
            restart: .none,
            group: .screenshots,
            hasASystemControl: true
        ),
        Tweak(
            id: "screenshot-shadow",
            domain: "com.apple.screencapture",
            key: "disable-shadow",
            kind: .aSwitch(.boolean(true)),
            restart: .none,
            group: .screenshots,
            hasASystemControl: false
        ),
        Tweak(
            id: "screenshot-date",
            domain: "com.apple.screencapture",
            key: "include-date",
            kind: .aSwitch(.boolean(false)),
            restart: .none,
            group: .screenshots,
            hasASystemControl: false
        ),
        Tweak(
            id: "screenshot-jpg",
            domain: "com.apple.screencapture",
            key: "type",
            kind: .aSwitch(.text("jpg")),
            restart: .none,
            group: .screenshots,
            hasASystemControl: false
        ),
    ]

    static let finder: [Tweak] = [
        Tweak(
            id: "finder-hidden-files",
            domain: "com.apple.finder",
            key: "AppleShowAllFiles",
            kind: .aSwitch(.boolean(true)),
            restart: .finder,
            group: .finder,
            hasASystemControl: true
        ),
        Tweak(
            id: "finder-extensions",
            domain: "NSGlobalDomain",
            key: "AppleShowAllExtensions",
            kind: .aSwitch(.boolean(true)),
            restart: .finder,
            group: .finder,
            hasASystemControl: true
        ),
        Tweak(
            id: "finder-path-bar",
            domain: "com.apple.finder",
            key: "ShowPathbar",
            kind: .aSwitch(.boolean(true)),
            restart: .finder,
            group: .finder,
            hasASystemControl: true
        ),
        Tweak(
            id: "finder-status-bar",
            domain: "com.apple.finder",
            key: "ShowStatusBar",
            kind: .aSwitch(.boolean(true)),
            restart: .finder,
            group: .finder,
            hasASystemControl: true
        ),
        Tweak(
            id: "finder-folders-first",
            domain: "com.apple.finder",
            key: "_FXSortFoldersFirst",
            kind: .aSwitch(.boolean(true)),
            restart: .finder,
            group: .finder,
            hasASystemControl: true
        ),
        Tweak(
            id: "finder-extension-warning",
            domain: "com.apple.finder",
            key: "FXEnableExtensionChangeWarning",
            kind: .aSwitch(.boolean(false)),
            restart: .finder,
            group: .finder,
            hasASystemControl: true
        ),
        Tweak(
            id: "finder-posix-title",
            domain: "com.apple.finder",
            key: "_FXShowPosixPathInTitle",
            kind: .aSwitch(.boolean(true)),
            restart: .finder,
            group: .finder,
            hasASystemControl: false
        ),
        Tweak(
            id: "finder-network-stores",
            domain: "com.apple.desktopservices",
            key: "DSDontWriteNetworkStores",
            kind: .aSwitch(.boolean(true)),
            restart: .logOut,
            group: .finder,
            hasASystemControl: false
        ),
    ]

    static let typing: [Tweak] = [
        Tweak(
            id: "typing-press-and-hold",
            domain: "NSGlobalDomain",
            key: "ApplePressAndHoldEnabled",
            kind: .aSwitch(.boolean(false)),
            restart: .relaunchApps,
            group: .typing,
            hasASystemControl: false
        ),
        Tweak(
            id: "typing-capitalisation",
            domain: "NSGlobalDomain",
            key: "NSAutomaticCapitalizationEnabled",
            kind: .aSwitch(.boolean(false)),
            restart: .relaunchApps,
            group: .typing,
            hasASystemControl: true
        ),
        Tweak(
            id: "typing-period",
            domain: "NSGlobalDomain",
            key: "NSAutomaticPeriodSubstitutionEnabled",
            kind: .aSwitch(.boolean(false)),
            restart: .relaunchApps,
            group: .typing,
            hasASystemControl: true
        ),
        Tweak(
            id: "typing-quotes",
            domain: "NSGlobalDomain",
            key: "NSAutomaticQuoteSubstitutionEnabled",
            kind: .aSwitch(.boolean(false)),
            restart: .relaunchApps,
            group: .typing,
            hasASystemControl: true
        ),
        Tweak(
            id: "typing-dashes",
            domain: "NSGlobalDomain",
            key: "NSAutomaticDashSubstitutionEnabled",
            kind: .aSwitch(.boolean(false)),
            restart: .relaunchApps,
            group: .typing,
            hasASystemControl: true
        ),
        Tweak(
            id: "typing-spelling",
            domain: "NSGlobalDomain",
            key: "NSAutomaticSpellingCorrectionEnabled",
            kind: .aSwitch(.boolean(false)),
            restart: .relaunchApps,
            group: .typing,
            hasASystemControl: true
        ),
    ]

    static let windows: [Tweak] = [
        Tweak(
            id: "windows-scrollbars",
            domain: "NSGlobalDomain",
            key: "AppleShowScrollBars",
            kind: .aSwitch(.text("Always")),
            restart: .relaunchApps,
            group: .windows,
            hasASystemControl: true
        ),
        Tweak(
            id: "windows-scroll-animation",
            domain: "NSGlobalDomain",
            key: "NSScrollAnimationEnabled",
            kind: .aSwitch(.boolean(false)),
            restart: .relaunchApps,
            group: .windows,
            hasASystemControl: false
        ),
        Tweak(
            id: "windows-resize-time",
            domain: "NSGlobalDomain",
            key: "NSWindowResizeTime",
            kind: .aSwitch(.number(0.001)),
            restart: .relaunchApps,
            group: .windows,
            hasASystemControl: false
        ),
        Tweak(
            id: "windows-drag-anywhere",
            domain: "NSGlobalDomain",
            key: "NSWindowShouldDragOnGesture",
            kind: .aSwitch(.boolean(true)),
            restart: .relaunchApps,
            group: .windows,
            hasASystemControl: false
        ),
        Tweak(
            id: "windows-tiled-margins",
            domain: "com.apple.WindowManager",
            key: "EnableTiledWindowMargins",
            kind: .aSwitch(.boolean(false)),
            restart: .windowManager,
            group: .windows,
            hasASystemControl: true
        ),
        Tweak(
            id: "windows-clock-seconds",
            domain: "com.apple.menuextra.clock",
            key: "ShowSeconds",
            kind: .aSwitch(.boolean(true)),
            restart: .controlCenter,
            group: .windows,
            hasASystemControl: true
        ),
    ]

    static let privacy: [Tweak] = [
        Tweak(
            id: "privacy-save-locally",
            domain: "NSGlobalDomain",
            key: "NSDocumentSaveNewDocumentsToCloud",
            kind: .aSwitch(.boolean(false)),
            restart: .none,
            group: .privacy,
            hasASystemControl: false
        ),
        Tweak(
            id: "privacy-personalised-ads",
            domain: "com.apple.AdLib",
            key: "allowApplePersonalizedAdvertising",
            kind: .aSwitch(.boolean(false)),
            restart: .none,
            group: .privacy,
            hasASystemControl: true
        ),
        Tweak(
            id: "privacy-crash-reporter",
            domain: "com.apple.CrashReporter",
            key: "DialogType",
            kind: .aSwitch(.text("none")),
            restart: .none,
            group: .privacy,
            hasASystemControl: false
        ),
    ]
}

import PeelCore
import SwiftUI

/// The words shown for each area of the disk: a title, a description, and, for an area that only its own app
/// should clear, a hint on how to clear it.
///
/// They live in the app, not beside the paths in PeelCore, because the package has no string catalog: a
/// `String(localized:)` there would resolve against whichever bundle loaded it.
nonisolated extension SpaceItem {
    struct Words {
        let title: LocalizedStringResource
        let detail: LocalizedStringResource
        var hint: LocalizedStringResource?
        /// What the hint does, in a circled i beside it.
        var hintNote: LocalizedStringResource?
        /// The hint while the apps that manage the area are gone from this Mac.
        var hintWithoutItsApp: LocalizedStringResource?
        /// True for an area a page of Peel's own frees, which no other app or tool manages.
        var isFreedByPeel = false
    }

    /// The words shown for this area. An area with no words here stops a Debug build, and a Release build
    /// shows its identifier instead.
    var words: Words {
        guard let found = Self.words[id] else {
            assertionFailure("no words for space item \(id)")
            let name = LocalizedStringResource(stringLiteral: id)
            return Words(title: name, detail: name)
        }
        return found
    }

    static func words(for id: String) -> Words? {
        words[id]
    }

    var howToFreeIt: LocalizedStringResource? {
        managingAppIsMissing ? words.hintWithoutItsApp ?? words.hint : words.hint
    }

    var howToFreeItNote: LocalizedStringResource? {
        managingAppIsMissing && words.hintWithoutItsApp != nil ? nil : words.hintNote
    }

    private static let words: [String: Words] = [
        "simulators": Words(
            title: "Simulators",
            detail: "Devices and runtimes Xcode keeps for testing.",
            hint: LocalizedStringResource(
                "Xcode > Settings > Components", comment: "Xcode's own menus, which are English in every language."
            ),
            hintWithoutItsApp: LocalizedStringResource(
                "Install Xcode again, then Xcode > Settings > Components",
                comment: "Xcode > Settings > Components are Xcode's own menus, which are English in every language."
            )
        ),
        "android-sdk": Words(
            title: "Android Emulators",
            detail: "System images Android Studio downloaded, and the virtual devices made from them.",
            hint: "View > Tool Windows > Device Manager, and Tools > SDK Manager, in Android Studio"
        ),
        "rust-toolchains": Words(
            title: "Rust Toolchains",
            detail: "The versions of Rust that rustup installed, each a whole compiler and standard library."
        ),
        "android-ndk": Words(
            title: LocalizedStringResource("Android NDK", comment: "A product's name, never translated."),
            detail: "The versions of the Native Development Kit that Android Studio installed, side by side.",
            hint: "Tools > SDK Manager > SDK Tools, in Android Studio"
        ),
        "unity-assets": Words(
            title: LocalizedStringResource("Unity Asset Store", comment: "A product's name, never translated."),
            detail: "Packages downloaded from your Asset Store purchases.",
            hint: "My Assets, in the Unity Editor’s Package Manager"
        ),
        "docker": Words(
            title: LocalizedStringResource("Docker Desktop", comment: "A product's name, never translated."),
            detail: "Docker’s disk image holds every image, container, and volume.",
            hint: LocalizedStringResource(
                "Docker Desktop > Settings > Resources",
                comment: "Docker Desktop's own menus, which are English in every language."
            )
        ),
        "orbstack": Words(
            title: LocalizedStringResource("OrbStack", comment: "A product's name, never translated."),
            detail: "OrbStack’s machines and images."
        ),
        "colima": Words(
            title: LocalizedStringResource("Colima", comment: "A product's name, never translated."),
            detail: "Colima’s virtual machines."
        ),
        "utm": Words(
            title: LocalizedStringResource("UTM", comment: "A product's name, never translated."),
            detail: "UTM virtual machines.",
            hint: "Delete the machine in UTM"
        ),
        "parallels": Words(
            title: LocalizedStringResource("Parallels", comment: "A product's name, never translated."),
            detail: "Parallels virtual machines.",
            hint: "Remove the machine in Parallels Desktop and choose to move its files to the Trash"
        ),
        "vmware": Words(
            title: LocalizedStringResource("VMware Fusion", comment: "A product's name, never translated."),
            detail: "VMware virtual machines.",
            hint: "Delete the machine in VMware Fusion and choose to move its files to the Trash"
        ),
        "podman": Words(
            title: LocalizedStringResource("Podman", comment: "A product's name, never translated."),
            detail: "Podman’s virtual machine and the images inside it."
        ),
        "lima": Words(
            title: LocalizedStringResource("Lima", comment: "A product's name, never translated."),
            detail: "Lima virtual machines."
        ),
        "minikube": Words(
            title: LocalizedStringResource("minikube", comment: "A product's name, never translated."),
            detail: "minikube clusters and the images they downloaded."
        ),
        "virtualbox": Words(
            title: LocalizedStringResource("VirtualBox", comment: "A product's name, never translated."),
            detail: "VirtualBox virtual machines.",
            hint: "Remove the machine in VirtualBox and choose to delete all its files"
        ),
        "vagrant": Words(
            title: "Vagrant Boxes",
            detail: "Base boxes Vagrant downloaded."
        ),
        "virtualbuddy": Words(
            title: LocalizedStringResource("VirtualBuddy", comment: "A product's name, never translated."),
            detail: "VirtualBuddy’s virtual machines, and the system images it downloaded to install them, which stay when a machine is deleted. Installers and Backups lists those images.",
            hint: "Move the machine to the Trash in VirtualBuddy’s library",
            hintWithoutItsApp: "Move what you no longer need to the Trash in Finder"
        ),
        "crossover": Words(
            title: LocalizedStringResource("CrossOver", comment: "A product's name, never translated."),
            detail: "CrossOver’s bottles, each with the Windows apps installed in it and everything they saved, and the bottles published for every account.",
            hint: "Delete the bottle in CrossOver",
            hintWithoutItsApp: "Move what you no longer need to the Trash in Finder"
        ),
        "whisky": Words(
            title: LocalizedStringResource("Whisky", comment: "A product's name, never translated."),
            detail: "Whisky’s bottles, each with the Windows apps installed in it and everything they saved.",
            hint: "Remove the bottle in Whisky and choose to delete its files from disk",
            hintWithoutItsApp: "Move what you no longer need to the Trash in Finder"
        ),
        "wine": Words(
            title: LocalizedStringResource("Wine", comment: "A product's name, never translated."),
            detail: "The Windows apps Wine installed in its default folder, with their settings and everything they saved.",
            hint: "Move the folder to the Trash in Finder once you no longer need its Windows apps"
        ),
        "tart": Words(
            title: LocalizedStringResource("Tart", comment: "A product's name, never translated."),
            detail: "Tart’s virtual machines. The images it keeps for making them are on the Developer page."
        ),
        "lume": Words(
            title: LocalizedStringResource("Lume", comment: "A product's name, never translated."),
            detail: "Lume’s virtual machines, and the images it keeps for making them."
        ),
        "anka": Words(
            title: LocalizedStringResource("Anka", comment: "A product's name, never translated."),
            detail: "Anka’s virtual machine templates and their state, and the system images it downloaded."
        ),
        "rancher-desktop": Words(
            title: LocalizedStringResource("Rancher Desktop", comment: "A product's name, never translated."),
            detail: "Rancher Desktop’s virtual machine, which holds every image, container, and volume.",
            hint: "Use Factory Reset on Rancher Desktop’s Troubleshooting page",
            hintWithoutItsApp: "Move what you no longer need to the Trash in Finder"
        ),
        "apple-container": Words(
            title: LocalizedStringResource("container", comment: "The name of Apple's command-line tool, never translated."),
            detail: "The Linux containers, images, and volumes of Apple’s container tool, and the Linux kernel it runs them on."
        ),
        "genymotion": Words(
            title: LocalizedStringResource("Genymotion", comment: "A product's name, never translated."),
            detail: "Genymotion’s virtual Android devices.",
            hint: "Delete the device in Genymotion",
            hintWithoutItsApp: "Move what you no longer need to the Trash in Finder"
        ),
        "podcasts": Words(
            title: "Podcast Downloads",
            detail: "Episodes the Podcasts app downloaded, with everything else it keeps on this Mac, so removing the downloads frees less than this.",
            hint: "Podcasts > Downloaded > Remove All Downloads"
        ),
        "tv": Words(
            title: "TV Library",
            detail: "Movies and shows the TV app keeps on this Mac, downloaded or imported.",
            hint: "TV > Library > Downloaded"
        ),
        "messages": Words(
            title: "Messages Attachments",
            detail: "Photos, videos, and files sent and received in Messages.",
            hint: LocalizedStringResource(
                "Messages > Settings > General > Keep Messages",
                comment: "The menu, settings, tab, and setting of Apple's Messages app, as macOS names them in each language."
            ),
            hintNote: "A shorter time deletes older conversations along with their attachments."
        ),
        "wallpapers": Words(
            title: "Aerial Wallpapers",
            detail: "Video wallpapers macOS downloaded.",
            hint: "System Settings > Wallpaper"
        ),
        "cloudstorage": Words(
            title: "Cloud Storage",
            detail: "Files that Dropbox, Google Drive, OneDrive, and other providers keep on this Mac.",
            hint: "Free up space from inside the provider’s app"
        ),
        "icloud": Words(
            title: "iCloud Drive",
            detail: "All that iCloud Drive keeps downloaded on this Mac, small files and files not yet uploaded included.",
            hint: "The iCloud Drive page in Peel",
            hintNote: LocalizedStringResource(
                "It removes the downloads of files of \(CloudStorage.minimumSize.formatted(.byteCount(style: .file))) or more that are already safe in iCloud.",
                comment: "%@ is a file size, such as 1 MB."
            ),
            isFreedByPeel: true
        ),
        "logs": Words(
            title: "Logs",
            detail: "Logs that apps wrote in your Library and their containers, and your crash reports, offered one by one."
        ),
        "caches": Words(
            title: "App Caches",
            detail: "What apps cached in your Library, each folder moved whole. The folders of developer tools are left to the Developer page."
        ),
        "user-caches": Words(
            title: "Hidden App Caches",
            detail: "What apps cached in a folder macOS gives your account, which Finder hides. What an open app uses stays, and the folders of developer tools are left to the Developer page."
        ),
        "container-caches": Words(
            title: "Sandboxed App Caches",
            detail: "What sandboxed apps, such as those from the App Store, cached in their containers. What an open app uses stays, and the caches of Apple apps are listed but never selected."
        ),
        "mail-downloads": Words(
            title: "Mail Downloads",
            detail: "Copies of the attachments you opened in Mail. One you edited or saved may be the only copy, so they are listed and never selected."
        ),
        "system-caches": Words(
            title: "Caches for All Users",
            detail: "What apps cached for every account on this Mac. What an open app uses, or a service wrote in the last 15 minutes, stays."
        ),
        "system-logs": Words(
            title: "Logs for All Users",
            detail: "Logs that apps and services wrote for every account, and the crash reports macOS keeps. Only the logs are offered, never their folders, and what a service wrote in the last 15 minutes stays."
        ),
        "homebrew-data": Words(
            title: "Homebrew Data",
            detail: "What Homebrew formulae keep in its var folder, such as the data of a database. Uninstalling with Homebrew leaves it, and a folder no installed formula names is marked.",
            hint: "Remove a folder in Finder once no formula needs it",
            hintNote: "Homebrew never removes it."
        ),
        "tex-live": Words(
            title: LocalizedStringResource("TeX Live", comment: "A product's name, never translated."),
            detail: "Each year of TeX Live in /usr/local/texlive, where MacTeX installs it. Installing a later year leaves the earlier ones as they were, and each year other than the one in use says so.",
            hint: "Drag a year you no longer use to the Trash in Finder",
            hintNote: "Finder asks for an administrator password. TeX Live Utility chooses the year in use."
        ),
        "dotnet-sdks": Words(
            title: ".NET SDKs",
            detail: "Each version of the .NET SDK installed on this Mac. Installing a newer one leaves the earlier ones, and Microsoft says you generally need only the newest.",
            hint: "Drag an older version to the Trash in Finder, or use the .NET Uninstall Tool",
            hintNote: "Finder asks for an administrator password for a version in /usr/local."
        ),
        "homebrew-logs": Words(
            title: "Homebrew Service Logs",
            detail: "Logs that the services Homebrew runs, such as a database, write in its folder. Only the logs are offered, never their folders."
        ),
        "battlenet-cache": Words(
            title: "Battle.net Cache",
            detail: "What the Battle.net app caches for every account. Blizzard says removing it does not affect your games. It belongs to every account, so it is never selected."
        ),
    ]
}

nonisolated extension SpaceItem.PlaceNote {
    var words: LocalizedStringResource {
        switch self {
        case .namedByNoInstalledFormula: "No installed formula names it"
        case .notTheTeXLiveInUse: "Not the year in use"
        case .aNewerSDKIsInstalled: "A newer version is installed"
        }
    }
}

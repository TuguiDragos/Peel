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
        /// The hint while the apps that manage the area are gone from this Mac.
        var hintWithoutItsApp: LocalizedStringResource?
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
        "podcasts": Words(
            title: "Podcast Downloads",
            detail: "Episodes the Podcasts app keeps on this Mac.",
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
            hint: "Messages > Settings > Keep Messages, which deletes older conversations along with their attachments"
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
            detail: "iCloud files downloaded to this Mac.",
            hint: "Peel’s own iCloud Drive page frees these, one file at a time"
        ),
        "logs": Words(
            title: "Logs",
            detail: "Logs that apps wrote in your Library."
        ),
        "caches": Words(
            title: "App Caches",
            detail: "Everything that apps cached in your Library, each folder moved whole. Developer tools’ folders are left to the Developer page, which knows which part of each is only a cache."
        ),
        "user-caches": Words(
            title: "Hidden App Caches",
            detail: "What apps cached in the folder macOS gives your account for caches, which Finder hides and macOS empties only when the Mac starts up in safe mode. What macOS keeps there for its own services isn’t listed, what an open app uses stays, and developer tools’ folders are left to the Developer page."
        ),
        "container-caches": Words(
            title: "Sandboxed App Caches",
            detail: "What sandboxed apps, such as those from the App Store, cached or left as temporary files in their own containers, and cached in the ones they share with apps from the same maker. What an open app uses stays, and the caches of Apple’s own apps are listed but never selected."
        ),
        "mail-downloads": Words(
            title: "Mail Downloads",
            detail: "Copies of the attachments you opened in Mail. Mail deletes each with its message unless you edited it, so they are listed and never selected."
        ),
        "system-caches": Words(
            title: "Caches for All Users",
            detail: "What apps cached for every account on this Mac, in the Library at the top of the disk. What macOS keeps there for its own services isn’t listed, and what an open app uses stays. What an administrator owns goes through Peel’s helper."
        ),
        "system-logs": Words(
            title: "Logs for All Users",
            detail: "Logs that apps wrote for every account on this Mac, and the crash reports macOS keeps, in the Library at the top of the disk. What macOS writes there for its own services isn’t listed, and what an open app uses stays. What an administrator owns goes through Peel’s helper."
        ),
        "battlenet-cache": Words(
            title: "Battle.net Cache",
            detail: "What the Battle.net app caches for every account on this Mac. Blizzard says removing it doesn’t affect your games, and the app makes it again. Since it belongs to every account, it is listed and never selected."
        ),
    ]
}

#if DEBUG
extension SpaceItem {
    /// Checks that every area PeelCore defines has complete words here. The app has no test target, so a Debug
    /// build runs this when its window opens. It reads the keys, not the text they resolve to, so a
    /// pseudolanguage can't trip it. `StringCatalogTests` checks the translations.
    static func checkWords() {
        for id in SpaceInventory.definitionIdentifiers {
            guard let found = words[id] else {
                assertionFailure("no words for \(id)")
                continue
            }
            assert(!found.title.key.isEmpty, "\(id) has no title")
            assert(found.detail.key.hasSuffix("."), "\(id) doesn't explain itself")
            if let hint = found.hint {
                assert(!hint.key.isEmpty, "\(id) has an empty hint")
            }
        }
        for id in SpaceInventory.managedAreaIdentifiers {
            assert(words[id]?.hintWithoutItsApp != nil, "\(id) has no hint for when its app is gone")
        }
    }
}
#endif

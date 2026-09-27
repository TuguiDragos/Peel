import PeelCore
import SwiftUI

/// The words shown for each area of the disk: a title, a description, and, for an area that only its own app
/// should clear, a hint on how to clear it.
///
/// They live in the app, not beside the paths in PeelCore, because the package has no string catalog: a
/// `String(localized:)` there would resolve against whichever bundle loaded it.
extension SpaceItem {
    struct Words {
        let title: LocalizedStringResource
        let detail: LocalizedStringResource
        var hint: LocalizedStringResource?
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

    private static let words: [String: Words] = [
        "simulators": Words(
            title: "Simulators",
            detail: "Devices and runtimes Xcode keeps for testing.",
            hint: "Xcode > Settings > Components, or xcrun simctl delete unavailable"
        ),
        "android-sdk": Words(
            title: "Android Emulators",
            detail: "System images Android Studio downloaded, and the virtual devices made from them.",
            hint: "View > Tool Windows > Device Manager, and Tools > SDK Manager, in Android Studio"
        ),
        "unity-assets": Words(
            title: "Unity Asset Store",
            detail: "Packages downloaded from your Asset Store purchases.",
            hint: "My Assets, in the Unity Editor’s Package Manager"
        ),
        "docker": Words(
            title: "Docker Desktop",
            detail: "Docker’s disk image holds every image, container, and volume.",
            hint: "docker system prune, or Docker Desktop > Settings > Resources"
        ),
        "orbstack": Words(
            title: "OrbStack",
            detail: "OrbStack’s machines and images.",
            hint: "orb delete <name> for a machine, and docker image prune -a for images nothing uses"
        ),
        "colima": Words(
            title: "Colima",
            detail: "Colima’s virtual machines.",
            hint: "colima delete --data"
        ),
        "utm": Words(
            title: "UTM",
            detail: "UTM virtual machines.",
            hint: "Delete the machine in UTM"
        ),
        "parallels": Words(
            title: "Parallels",
            detail: "Parallels virtual machines.",
            hint: "Remove the machine in Parallels Desktop and choose to move its files to the Trash"
        ),
        "vmware": Words(
            title: "VMware Fusion",
            detail: "VMware virtual machines.",
            hint: "Delete the machine in VMware Fusion and choose to move its files to the Trash"
        ),
        "podman": Words(
            title: "Podman",
            detail: "Podman’s virtual machine and the images inside it.",
            hint: "podman machine rm <name>"
        ),
        "lima": Words(
            title: "Lima",
            detail: "Lima virtual machines.",
            hint: "limactl delete <name>"
        ),
        "minikube": Words(
            title: "minikube",
            detail: "minikube clusters and the images they downloaded.",
            hint: "minikube delete --all --purge"
        ),
        "virtualbox": Words(
            title: "VirtualBox",
            detail: "VirtualBox virtual machines.",
            hint: "Remove the machine in VirtualBox and choose to delete all its files"
        ),
        "vagrant": Words(
            title: "Vagrant Boxes",
            detail: "Base boxes Vagrant downloaded.",
            hint: "vagrant box remove <name>, or vagrant box prune for old versions"
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
        "container-caches": Words(
            title: "Sandboxed App Caches",
            detail: "What sandboxed apps, such as those from the App Store, cached in their own containers. An app that is open keeps its caches, and those of Apple’s own apps are listed but never selected."
        ),
        "mail-downloads": Words(
            title: "Mail Downloads",
            detail: "Copies of the attachments you opened in Mail. Mail deletes each with its message unless you edited it, so they are listed and never selected."
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
            // Without `--data`, `colima delete` keeps the container data (images and volumes) on disk.
            if id == "colima" {
                assert(found.hint?.key.contains("--data") == true, "colima's hint must delete the runtime's data disk too")
            }
        }
    }
}
#endif

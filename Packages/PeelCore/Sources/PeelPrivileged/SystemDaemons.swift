import Foundation

/// The daemons macOS ships. Their file names prove nothing (`ssh.plist` declares `com.openssh.sshd`),
/// so the `Label` inside each one is read, and none of them is ever the helper's to stop or unload.
public enum SystemDaemons {
    static let directory = "/System/Library/LaunchDaemons"
    /// Where system updates install more of Apple's daemons, such as `com.apple.usbmuxd`.
    static let deliveredByUpdates = "/Library/Apple/System/Library/LaunchDaemons"

    /// The labels of the daemons macOS ships. Empty when the sealed folder cannot be read, whatever the second
    /// folder holds, and `allowsDaemon` then refuses every label.
    public static let shipped: Set<String> = {
        let sealed = labels(in: directory)
        return sealed.isEmpty ? [] : sealed.union(labels(in: deliveredByUpdates))
    }()

    /// Where other vendors' daemons are installed.
    public static let installed = "/Library/LaunchDaemons"

    /// The files in `directory` that declare `label`, two at most: a job is loaded only from the one file that
    /// declares it, since a file's name usually repeats its label but need not. Links are not followed.
    public static func files(declaring label: String, in directory: String = installed) -> [String] {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        let declaring = contents.lazy
            .filter { $0.hasSuffix(".plist") }
            .map { (directory as NSString).appendingPathComponent($0) }
            .filter { path in
                var info = stat()
                guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size <= 1_024 * 1_024 else {
                    return false
                }
                guard
                    let data = FileManager.default.contents(atPath: path),
                    let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
                else { return false }
                return plist["Label"] as? String == label
            }
        return Array(declaring.prefix(2))
    }

    public static func labels(in directory: String) -> Set<String> {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        return Set(contents.lazy.filter { $0.hasSuffix(".plist") }.map { name in
            let path = (directory as NSString).appendingPathComponent(name)
            var info = stat()
            guard
                lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size <= 1_024 * 1_024,
                let data = FileManager.default.contents(atPath: path),
                let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                let label = plist["Label"] as? String
            else {
                // A file that cannot be read still refuses the name it usually declares.
                return String(name.dropLast(".plist".count))
            }
            return label
        })
    }
}

/// The agents macOS ships, read the same way as its daemons. One of them, `com.openssh.ssh-agent`, has a label that
/// says nothing about Apple, so the labels are read rather than guessed from a prefix.
public enum SystemAgents {
    static let directory = "/System/Library/LaunchAgents"
    /// Where system updates install more of Apple's agents.
    static let deliveredByUpdates = "/Library/Apple/System/Library/LaunchAgents"

    /// The labels of the agents macOS ships. Empty when the sealed folder cannot be read.
    public static let shipped: Set<String> = {
        let sealed = SystemDaemons.labels(in: directory)
        return sealed.isEmpty ? [] : sealed.union(SystemDaemons.labels(in: deliveredByUpdates))
    }()
}

public import Foundation

public enum HushLogin {
    public static func url(in home: URL) -> URL {
        home.appending(path: ".hushlogin", directoryHint: .notDirectory)
    }

    public static func isOn(in home: URL) -> Bool {
        access(url(in: home).path(percentEncoded: false), F_OK) == 0
    }

    public static func turnOn(in home: URL) -> Bool {
        let descriptor = open(
            url(in: home).path(percentEncoded: false),
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            0o644
        )
        if descriptor >= 0 {
            close(descriptor)
        }
        return isOn(in: home)
    }
}

import Foundation
import PeelCore

/// The web addresses Peel opens. Each is written only here, so a change reaches every place that uses it.
enum Links {
    static let author = URL(string: "https://tuguidragos.com")!
    static let repository = URL(string: "https://github.com/TuguiDragos/Peel")!
    static let latestRelease = repository.appending(path: "releases/latest")
    static let license = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!
    static let argumentParser = URL(string: "https://github.com/apple/swift-argument-parser")!
    static let blobatar = URL(string: "https://github.com/Alain00/blobatar")!

    /// The address of a new GitHub issue on the bug report form, with Peel's environment already filled in.
    ///
    /// Nothing is sent from here: the browser opens a form the user can edit or close. Peel fills in only its
    /// version, the macOS version, and the processor type, each in the form's own field. It never adds what is
    /// installed on the Mac, because Settings > Privacy promises that only Homebrew's vulnerability scan sends that.
    static var report: URL {
        var components = URLComponents(url: repository.appending(path: "issues/new"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.yml"),
            URLQueryItem(name: "version", value: AppVersion.display),
            URLQueryItem(name: "macos", value: systemVersion),
            URLQueryItem(name: "mac", value: HostArchitecture.isAppleSilicon ? "Apple silicon" : "Intel"),
        ]
        return components?.url ?? repository
    }

    /// The macOS version and build number, written the same way in every language so that all reports read
    /// alike. `operatingSystemVersionString` is not used because it is localized.
    private static var systemVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var build = [UInt8](repeating: 0, count: size)
        sysctlbyname("kern.osversion", &build, &size, nil, 0)
        let number = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        let code = String(decoding: build.prefix { $0 != 0 }, as: UTF8.self)
        return code.isEmpty ? number : "\(number) (\(code))"
    }
}

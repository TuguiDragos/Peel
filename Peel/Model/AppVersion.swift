import Foundation

/// The app's version and build, written once so About, the sidebar, and a bug report always agree.
enum AppVersion {
    static let display: String = {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return "\(short) (\(build))"
    }()
}

import Foundation

extension URL {
    /// An address that came from outside Peel, kept only when it is a page a browser opens: the Mac would hand any
    /// other scheme to whatever app claims it.
    init?(webPage address: String) {
        guard let url = URL(string: address), url.isWebPage else { return nil }
        self = url
    }

    var isWebPage: Bool {
        ["http", "https"].contains(scheme?.lowercased())
    }
}

import Foundation

extension URL {
    /// The home as the programs Peel runs get it in `HOME`: with no slash at the end, which `"$HOME/.gitconfig"` would
    /// double in what they say.
    var pathAsHOME: String {
        (path(percentEncoded: false) as NSString).standardizingPath
    }
}

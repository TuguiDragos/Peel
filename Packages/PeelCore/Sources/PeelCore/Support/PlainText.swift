/// Text from someone else's bundle made safe to show: a name, a version or a path can hold any character, and a
/// line end in one would make a script read one row as two, while an escape sequence could rewrite on screen the
/// list the user is asked to confirm, and a direction control could show a path in another order than it has.
public enum PlainText {
    /// `text` with every control character, format character, and line or paragraph separator replaced with `?`.
    public static func of(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: isHidden) else { return text }
        return String(text.unicodeScalars.map { isHidden($0) ? "?" : Character($0) })
    }

    /// The zero width non-joiner and joiner stay: they only join the letters or emoji around them, which Persian,
    /// the Indic scripts and emoji sequences need.
    static func isHidden(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .lineSeparator, .paragraphSeparator: true
        case .format: scalar != "\u{200C}" && scalar != "\u{200D}"
        default: false
        }
    }
}

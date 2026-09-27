/// Text from someone else's bundle made safe to show: a name, a version or a path can hold any character, and a
/// line end in one would make a script read one row as two, while an escape sequence could rewrite on screen the
/// list the user is asked to confirm.
public enum PlainText {
    /// `text` with every control character replaced with `?`.
    public static func of(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: isControl) else { return text }
        return String(text.unicodeScalars.map { isControl($0) ? "?" : Character($0) })
    }

    static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value <= 0x1F || (0x7F...0x9F).contains(scalar.value)
    }
}

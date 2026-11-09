import Darwin
import Foundation
import PeelCore

/// What `peel peel` prints: Peel's face, drawn from the measurements `PeelFace` draws it with at the largest of three
/// sizes the terminal has room for, and beside it the version and what Peel has moved to the Trash, or under it when no
/// size fits beside them. Each character of the face has its tone: L lighter, O the face's orange, R deeper, D the
/// shade along the cut, C the flap, which takes the terminal's own text color so it shows on a light background as on
/// a dark one.
enum FaceArt {
    struct Drawing {
        let characters: [String]
        let tones: [String]

        var width: Int { characters.map(\.count).max() ?? 0 }

        /// The row's characters in their tones, as escape sequences a 24-bit terminal reads.
        func painted(_ row: Int) -> String {
            var line = ""
            var current: Character?
            for (character, tone) in zip(characters[row], tones[row]) {
                if tone == " " {
                    if current != nil { line += "\u{1B}[0m" }
                    current = nil
                } else if tone != current, let color = colors[tone] {
                    line += "\u{1B}[\(color)m"
                    current = tone
                }
                line.append(character)
            }
            return current == nil ? line : line + "\u{1B}[0m"
        }
    }

    /// From the largest to the smallest.
    static let drawings = [large, medium, small]

    /// 37 columns by 17 rows.
    static let large = Drawing(
        characters: [
            #"             __pqqq, `_"#,
            #"        __q@@@@@@@@b  @p_"#,
            #"      _d@@@@@@@@@@@@p `@@b_"#,
            #"    _@@@@@@@@@@@@@@@@p `@@@@_"#,
            #"   p@@@@@@@@@@@@@@@@@@b_ "@@@@p_"#,
            #"  d@@@@@@@@@@@@@@@@@@@@@p_ `@@@@p_"#,
            #" d@@@@@@@@@@@@@@@@@@@@@@@@b_ ``"d@b_"#,
            #" @@@@@@@@@@@@@@@@@@@@@@@@@@@@@p__ ```"#,
            #"`@@@@@@@@@```@@@@@```@@@@@@@@@@@@@@@q"#,
            #" @@@@@@@@@   d@@@@   |@@@@@@@@@@@@@@@"#,
            #" d@@@@@@@@   d@@@@   |@@@@@@@@@@@@@@("#,
            #"  \@@@@@@@p__d@@@@___@@@@@@@@@@@@@@@"#,
            #"   "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"#,
            #"    `@@@@@@@@@@@@@@@@@@@@@@@@@@@@`"#,
            #"      `@@@@@@@@@@@@@@@@@@@@@@@@`"#,
            #"        ``@d@@@@@@@@@@@@@@@@``"#,
            #"             ``""""""""``"#,
        ],
        tones: [
            #"             LLLLLDD CC"#,
            #"        LLLLLLLLLLDD  CCC"#,
            #"      LLLLLLLLLLLLDDD CCCCC"#,
            #"    LLLLLLLLLLLLLLLDDD CCCCCC"#,
            #"   LLLLLLLLLLLLLLLLOODDD CCCCCCC"#,
            #"  LLLLLLLLLLLLLLLOOOOODDDD CCCCCCC"#,
            #" LLLLLLLLLLLLLLOOOOOOOOODDDD CCCCCCC"#,
            #" LLLLLLLLLLLOOOOOOOOOOOOOOODDDDDD CCC"#,
            #"LLLLLLLLLLLOOOOOOOOOOOOOOOOOOOODDDDDD"#,
            #" LLLLLLLOO   OOOOO   OOOOOOOOOORRRRRR"#,
            #" LLLLLOOOO   OOOOO   OOOOOOOORRRRRRRR"#,
            #"  LOOOOOOOOOOOOOOOOOOOOOOORRRRRRRRRR"#,
            #"   OOOOOOOOOOOOOOOOOOOOORRRRRRRRRRR"#,
            #"    OOOOOOOOOOOOOOOOOORRRRRRRRRRRR"#,
            #"      OOOOOOOOOOOOOORRRRRRRRRRRR"#,
            #"        OOOOOOOOORRRRRRRRRRRRR"#,
            #"             OOORRRRRRRRR"#,
        ]
    )

    /// 26 columns by 12 rows.
    static let medium = Drawing(
        characters: [
            #"        __pqqq `_"#,
            #"    __q@@@@@@@b `@p_"#,
            #"   _d@@@@@@@@@@p `@@b_"#,
            #" _@@@@@@@@@@@@@@p `@@@p"#,
            #" @@@@@@@@@@@@@@@@b_ "@@p_"#,
            #"`@@@@@@``@@@@``@@@@@@p_ ``"#,
            #" @@@@@@  d@@@  |@@@@@@@@@q"#,
            #" d@@@@@  d@@@  |@@@@@@@@@("#,
            #"  \@@@p__d@@@__@@@@@@@@@@"#,
            #"   "@@@@@@@@@@@@@@@@@@@"#,
            #"    `@@@@@@@@@@@@@@@@`"#,
            #"        ``"""""""``"#,
        ],
        tones: [
            #"        LLLLLD CC"#,
            #"    LLLLLLLLLDD CCCC"#,
            #"   LLLLLLLLLLLDD CCCCC"#,
            #" LLLLLLLLLLLLOODD CCCCC"#,
            #" LLLLLLLLLLOOOOOODD CCCCC"#,
            #"LLLLLLLLLOOOOOOOOOOODDD CC"#,
            #" LLLLLO  OOOO  OOOOOOORRRR"#,
            #" LLLOOO  OOOO  OOOOORRRRRR"#,
            #"  OOOOOOOOOOOOOOOORRRRRRR"#,
            #"   OOOOOOOOOOOOORRRRRRR"#,
            #"    OOOOOOOOORRRRRRRRR"#,
            #"        OOOORRRRRRR"#,
        ]
    )

    /// 18 columns by 9 rows.
    static let small = Drawing(
        characters: [
            #"     _pqq, `_"#,
            #"  _d@@@@@b `@p"#,
            #" d@@@@@@@@p `@@_"#,
            #"_@@@@@@@@@@b_ "@p"#,
            #"@@@@``@@``@@@@@@@q"#,
            #"`@@@  d@  |@@@@@@("#,
            #" \@@__d@__@@@@@@@"#,
            #"  `@@@@@@@@@@@@`"#,
            #"     ``"""""``"#,
        ],
        tones: [
            #"     LLLLD CC"#,
            #"  LLLLLLLD CCC"#,
            #" LLLLLLLLOD CCCC"#,
            #"LLLLLLLOOOOOD CCC"#,
            #"LLLLLLOOOOOOOOOODD"#,
            #"LLLO  OO  OOOORRRR"#,
            #" OOOOOOOOOOORRRRR"#,
            #"  OOOOOOOORRRRRR"#,
            #"     OOORRRRRR"#,
        ]
    )

    static let colors: [Character: String] = [
        "L": "38;2;255;176;90", "O": "38;2;255;153;51", "R": "38;2;242;134;42", "D": "38;2;217;113;28", "C": "39",
    ]

    /// Colors only a terminal that says it shows 24-bit color, never a dumb one, and none while `NO_COLOR` holds
    /// anything (no-color.org).
    static func drawsInColor(environment: [String: String], isTerminal: Bool) -> Bool {
        isTerminal && (environment["NO_COLOR"] ?? "").isEmpty && environment["TERM"] != "dumb"
            && ["truecolor", "24bit"].contains(environment["COLORTERM"])
    }

    static func greeting() -> String {
        let info = Bundle.main.infoDictionary
        let isTerminal = Output.collected == nil && isatty(STDOUT_FILENO) == 1
        var size = winsize()
        let isSized = isTerminal && ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0 && size.ws_col > 0
        return text(
            colored: drawsInColor(environment: ProcessInfo.processInfo.environment, isTerminal: isTerminal),
            totals: RemovalTotals.read(),
            version: info?["CFBundleShortVersionString"] as? String ?? "",
            build: info?["CFBundleVersion"] as? String ?? "",
            columns: isSized ? Int(size.ws_col) : nil, rows: isSized && size.ws_row > 0 ? Int(size.ws_row) : nil
        )
    }

    /// The face beside its words at the largest size that fits in `columns` and `rows`, else above them at the largest
    /// that fits, else the words alone. A size not known leaves room for anything.
    static func text(
        colored: Bool, totals: RemovalTotals, version: String, build: String, columns: Int? = nil, rows: Int? = nil
    ) -> String {
        let info = words(colored: colored, totals: totals, version: version, build: build)
        let widest = words(colored: false, totals: totals, version: version, build: build).map(\.count).max() ?? 0
        let under = Array(info.reversed().drop(while: \.isEmpty).reversed())
        func fits(_ width: Int, _ height: Int) -> Bool { width <= columns ?? .max && height <= rows ?? .max }
        if let face = drawings.first(where: { fits($0.width + 4 + widest, max($0.characters.count, info.count)) }) {
            return beside(face, info, colored: colored)
        }
        let face = drawings.first { fits($0.width, $0.characters.count + 1 + under.count) }
        let shown = face.map { face in
            face.characters.indices.map { colored ? face.painted($0) : face.characters[$0] }
        }
        return ((shown.map { $0 + [""] } ?? []) + under).map { $0 + "\n" }.joined()
    }

    private static func beside(_ face: Drawing, _ info: [String], colored: Bool) -> String {
        let height = max(face.characters.count, info.count)
        let faceTop = (height - face.characters.count) / 2, infoTop = (height - info.count) / 2
        return (0..<height).map { row in
            let index = row - faceTop
            let characters = face.characters.indices.contains(index) ? face.characters[index] : ""
            var line = colored && !characters.isEmpty ? face.painted(index) : characters
            if info.indices.contains(row - infoTop), !info[row - infoTop].isEmpty {
                line += String(repeating: " ", count: face.width - characters.count + 4) + info[row - infoTop]
            }
            return line + "\n"
        }.joined()
    }

    private static func words(colored: Bool, totals: RemovalTotals, version: String, build: String) -> [String] {
        func paint(_ text: String, _ parameters: String) -> String {
            colored ? "\u{1B}[\(parameters)m\(text)\u{1B}[0m" : text
        }
        let orange = "38;2;255;153;51"
        let title = "Peel \(version) (\(build))"
        var info = [
            paint("Peel", "1;" + orange) + " \(version) (\(build))",
            paint(String(repeating: "-", count: title.count), "2"),
            paint("Moved to Trash  ", orange) + Output.size(totals.bytes),
            paint("Apps removed    ", orange) + "\(totals.apps)",
            paint("Items moved     ", orange) + "\(totals.items)",
            "",
            "Nothing left to peel.",
            "",
        ]
        let palette = ["48;2;255;153;51", "48;2;255;176;90", "48;2;255;242;224", "48;2;63;60;57"]
        info.append(colored ? palette.map { paint("   ", $0) }.joined() : "")
        return info
    }
}

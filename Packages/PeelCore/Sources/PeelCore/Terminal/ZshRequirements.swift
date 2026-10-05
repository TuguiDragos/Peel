import PeelPrivileged

/// What lines of zsh need from the zsh on this Mac: the options they set and the functions they load, read from the
/// lines themselves, so a setting is never offered to a zsh that would not take it.
enum ZshRequirements {
    static func of(_ lines: [String]) -> Set<String> {
        var needs: Set<String> = []
        for line in lines {
            let words = line.split(separator: " ").map(String.init)
            if words.first == "setopt" {
                needs.formUnion(words.dropFirst().map { "option:" + $0.lowercased().replacing("_", with: "") })
            }
            if let autoload = words.firstIndex(of: "autoload") {
                for word in words[(autoload + 1)...] where !word.hasPrefix("-") {
                    guard word.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { break }
                    needs.insert("function:" + word)
                }
            }
        }
        return needs
    }

    static var catalog: Set<String> {
        ShellSetting.allCases.reduce(into: Set<String>()) { $0.formUnion($1.requirements) }
            .union(of(Prompt.branchLines))
    }

    /// The options and functions of the catalog that the zsh on this Mac knows, or nil when it did not answer.
    static func known() async -> Set<String>? {
        let functions = catalog.filter { $0.hasPrefix("function:") }.map { String($0.dropFirst("function:".count)) }.sorted()
        let script = "print -rl -- ${(k)options}; for name in \(functions.joined(separator: " ")); do "
            + "autoload +X -Uz $name 2>/dev/null && print -r -- \"function:$name\"; done; true"
        guard case .success(let output) = await Subprocess.run("/bin/zsh", ["-f", "-c", script], environment: [:], timeout: 10),
              output.status == 0 else { return nil }
        return Set(output.text.split(separator: "\n").map { $0.hasPrefix("function:") ? String($0) : "option:" + $0 })
    }
}

extension ShellSetting {
    var requirements: Set<String> {
        ZshRequirements.of(lines + (group == .completion ? [ShellFile.completionSystem] : []))
    }

    public func isKnown(by known: Set<String>) -> Bool {
        requirements.isSubset(of: known)
    }
}

extension Prompt {
    public func isKnown(by known: Set<String>) -> Bool {
        ZshRequirements.of(lines).isSubset(of: known)
    }
}

extension ShellFile {
    public static func knownToZsh() async -> Set<String>? {
        await ZshRequirements.known()
    }
}

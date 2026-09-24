import Foundation
@testable import PeelCore
import Testing

struct DeveloperCachesTests {
    /// A scan stopped while it waits on a folder returns within a second and measures no more folders.
    @Test func aStoppedScanStops() async throws {
        let directory = try TemporaryDirectory()
        let paths = (1...30).map { "Library/Caches/Tool/\($0)" }
        for path in paths {
            try directory.directory(path)
        }
        let tool = DeveloperCaches.Definition(id: "tool", name: "Tool", systemImage: "hammer", appBundleIdentifiers: [], paths: paths.map { ($0, .cache) })
        let unanswered = Unanswered()

        let stop = try await unanswered.stop {
            _ = await DeveloperCaches.scan([tool], homeDirectory: directory.url, measure: unanswered.walk)
        }

        #expect(stop.took < .seconds(1))
        #expect(stop.askedBefore < paths.count)
        #expect(stop.askedAfter == 0)
    }

    /// A folder macOS would not let Peel open is not one that took too long: both are unknown and never selected
    /// for the user, and the page says which of the two it was.
    @Test func tellsAFolderMacOSRefusedFromOneThatDidNotAnswer() async throws {
        let directory = try TemporaryDirectory()
        try directory.file(".npm/_cacache/content/data", bytes: 80_000)
        try directory.file(".npm/_npx/package/index.js", bytes: 8_000)
        try directory.setPermissions(0o000, of: ".npm/_cacache")
        defer { try? directory.setPermissions(0o755, of: ".npm/_cacache") }

        let environments = await DeveloperCaches.scan(DeveloperCaches.definitions, homeDirectory: directory.url, exclusions: .none) { url in
            url.lastPathComponent == "_npx" ? nil : await FileSize.contents(of: url)
        }

        let npm = try #require(environments.first)
        let refused = try #require(npm.locations.first { $0.url.lastPathComponent == "_cacache" })
        let slow = try #require(npm.locations.first { $0.url.lastPathComponent == "_npx" })
        #expect(refused.size == nil)
        #expect(refused.couldNotBeRead, "a folder macOS refused reads as one that took too long")
        #expect(slow.size == nil)
        #expect(!slow.couldNotBeRead)
        #expect(!refused.isRecommended && !slow.isRecommended)
    }

    /// Xcode's caches wait on Simulator too, so the request to quit names whichever of the two is running: the
    /// environment's name would ask for Xcode while only Simulator runs, and the request would keep coming back.
    @Test func namesTheAppThatRunsRatherThanTheEnvironment() throws {
        let xcode = try #require(DeveloperCaches.definitions.first { $0.id == "xcode" })
        let environment = DeveloperEnvironment(
            id: xcode.id, name: xcode.name, systemImage: xcode.systemImage, appBundleIdentifiers: xcode.appBundleIdentifiers, locations: []
        )

        #expect(environment.runningApp { $0 == "com.apple.iphonesimulator" ? "Simulator" : nil } == "Simulator")
        #expect(environment.runningApp { $0 == "com.apple.dt.Xcode" ? "Xcode" : nil } == "Xcode")
        #expect(environment.runningApp { _ in nil } == nil)
    }

    /// Space asks about a folder however it was spelled, so another spelling of the same folder (another case, or
    /// the home folder through a link) must still find what the table lists inside it. Finding nothing, Space
    /// would move Coursier's folder whole, the JVMs beside its cache included.
    @Test func findsWhatItListsInsideAFolderSpelledAnotherWay() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("home/Library/Caches/Coursier/v1")
        try FileManager.default.createSymbolicLink(at: directory.url.appending(path: "link"), withDestinationURL: directory.url.appending(path: "home"))
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)

        let asWritten = DeveloperCaches.namesListed(inside: home.appending(path: "Library/Caches", directoryHint: .isDirectory), home: home)
        let otherCase = DeveloperCaches.namesListed(inside: home.appending(path: "library/caches", directoryHint: .isDirectory), home: home)
        let throughALink = DeveloperCaches.namesListed(inside: directory.url.appending(path: "link/Library/Caches", directoryHint: .isDirectory), home: home)

        #expect(asWritten.contains("Coursier"))
        #expect(otherCase == asWritten, "another case found \(otherCase)")
        #expect(throughALink == asWritten, "a link found \(throughALink)")
    }

    @Test func reportsOnlyExistingLocationsSortedBySize() async throws {
        let directory = try TemporaryDirectory()
        try directory.file(".npm/_cacache/content/data", bytes: 80_000)
        try directory.file(".npm/_npx/package/index.js", bytes: 8_000)
        try directory.file("Library/Developer/Xcode/DerivedData/Build/output", bytes: 20_000)
        try directory.directory("Library/Developer/Xcode/Archives/2026-09-17")

        let environments = await DeveloperCaches.scan(homeDirectory: directory.url)

        #expect(environments.map(\.id) == ["npm", "xcode"])
        let npm = try #require(environments.first)
        #expect(npm.locations.map(\.url.lastPathComponent) == ["_cacache", "_npx"])
        let xcode = try #require(environments.last)
        #expect(xcode.locations.first { $0.kind == .archives }?.isRecommended == false)
        #expect(xcode.locations.first { $0.kind == .buildData }?.isRecommended == true)
    }

    /// A large `DerivedData`, or a Gradle cache on a cold disk, may not be measured in time. Such a folder is not
    /// read as empty: it is listed first, with no size, and never selected for the user.
    @Test func aFolderThatDidNotAnswerInTimeIsNotReadAsEmpty() async throws {
        let directory = try TemporaryDirectory()
        try directory.file(".npm/_cacache/content/data", bytes: 80_000)
        try directory.file(".npm/_npx/package/index.js", bytes: 8_000)
        try directory.file("Library/Developer/Xcode/DerivedData/Build/output", bytes: 20_000)

        let environments = await DeveloperCaches.scan(DeveloperCaches.definitions, homeDirectory: directory.url, exclusions: .none) { url in
            url.lastPathComponent == "_npx" ? nil : await FileSize.contents(of: url)
        }

        let npm = try #require(environments.first)
        #expect(npm.id == "npm")
        #expect(npm.locations.map(\.url.lastPathComponent) == ["_npx", "_cacache"])
        #expect(npm.locations.first?.size == nil)
        #expect(npm.locations.first?.isRecommended == false, "what Peel could not measure is never selected for the user")
        #expect(npm.locations.last?.isRecommended == true)
        #expect(!npm.total.isComplete)
        #expect(npm.total.known >= 80_000)
        #expect(environments.last?.total.isComplete == true)
    }

    @Test func definitionsNeverPointAtWholeUserFolders() {
        let risky: Set<String> = [
            "", "Library", "Library/Caches", "Library/Application Support", "Library/Preferences", "Library/Logs",
            "Documents", "Desktop", "Downloads", "Movies", "Pictures",
            ".npm", ".cargo", ".gradle", ".m2", ".android", ".nuget", ".gem", ".bundle", ".aws", ".config", ".cache",
            ".local", ".local/share", "go", ".vscode", ".ollama", ".lmstudio", ".cache/huggingface",
        ]
        // The only top-level folders in the table, each owned outright by the one tool that made it.
        let ownedOutright: Set<String> = [".ccache", ".electron-gyp", ".node-gyp", ".virtualenvs", "nltk_data", "tensorflow_datasets"]
        for definition in DeveloperCaches.definitions {
            for (path, _) in definition.paths {
                #expect(!risky.contains(path), "\(definition.id) points at \(path)")
                #expect(!path.hasPrefix("/"), "\(definition.id) points outside the home folder")
                #expect(!path.contains(".."), "\(definition.id) climbs out of its folder")
                #expect(
                    path.split(separator: "/").count >= 2 || ownedOutright.contains(path),
                    "\(definition.id) points at the whole of \(path)"
                )
            }
        }
    }

    /// Toolchains, environments, and anything holding an account are installations or secrets, not caches.
    @Test func neverListsToolchainsOrCredentials() {
        let forbidden = [
            ".rustup", ".pyenv", ".nvm", ".sdkman", ".rbenv", ".jenv", "nix/store", ".nix-profile", ".asdf", ".volta",
            "conda/envs", "miniconda3/envs", "anaconda3/envs", ".local/pipx",
            "Library/Android/sdk", "flutter/bin", ".cocoapods/repos",
            ".aws", ".ssh", ".gnupg", ".netrc", ".docker/config", ".kube/config", ".npmrc",
            "qiskit-ibm.json", "qiskitrc", "dwave.conf", ".qcs", "xanadu-cloud", "pytket", ".qnx", "qbraidrc",
            "credentials", "token",
        ]
        // Folders that hold an account or the user's own work beside something cache-like.
        // Only their subfolders may ever be listed.
        let onlyInParts: Set<String> = [
            ".kube/cache", ".azure", ".config/gcloud", ".pulumi", ".qiskit", ".qbraid", ".expo", ".lmstudio",
            "Library/Preferences/netlify", "Library/Application Support/com.vercel.cli",
            "Library/Application Support/nomic.ai/GPT4All", "Library/Application Support/Adobe/Common",
            // Coursier keeps the JVMs `cs java` installs beside its cache; a legacy `~/.ccache` holds `ccache.conf`.
            "Library/Caches/Coursier", ".ccache",
        ]
        for definition in DeveloperCaches.definitions {
            for (path, _) in definition.paths {
                for pattern in forbidden {
                    #expect(!path.lowercased().contains(pattern.lowercased()), "\(definition.id) lists \(path)")
                }
                #expect(!onlyInParts.contains(path), "\(definition.id) lists the whole of \(path)")
            }
        }
    }

    @Test func everyDefinitionIsDistinctAndNoFolderIsCountedTwice() {
        let identifiers = DeveloperCaches.definitions.map(\.id)
        #expect(Set(identifiers).count == identifiers.count)
        #expect(Set(DeveloperCaches.definitions.map(\.name)).count == identifiers.count)

        var seen: [String: String] = [:]
        for definition in DeveloperCaches.definitions {
            #expect(!definition.name.isEmpty)
            #expect(!definition.paths.isEmpty, "\(definition.id) has no paths")
            for (path, _) in definition.paths {
                #expect(seen[path] == nil, "\(path) is listed by both \(seen[path] ?? "") and \(definition.id)")
                seen[path] = definition.id
            }
        }
    }

    /// A path inside another would count the same bytes twice, and moving the outer folder would take the inner.
    @Test func noPathIsInsideAnother() {
        let paths = DeveloperCaches.definitions.flatMap { definition in definition.paths.map { ($0.0, definition.id) } }
        for (path, owner) in paths {
            for (other, otherOwner) in paths where other != path {
                #expect(!path.hasPrefix(other + "/"), "\(owner) lists \(path) inside \(otherOwner)'s \(other)")
            }
        }
    }

    /// `~/Library/Caches/deno` is Deno's `DENO_DIR`. Besides downloads, it holds `location_data`, with
    /// `localStorage` and the database behind `Deno.openKv()`. Once a script has kept state there, the folder is
    /// more than a cache and is not offered.
    @Test func leavesDenosFolderOnceAScriptHasKeptStateInIt() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Caches/deno/deps/https/x.ts", bytes: 400_000)
        let deno = DeveloperCaches.definitions.filter { $0.id == "deno" }

        #expect(await DeveloperCaches.scan(deno, homeDirectory: directory.url).flatMap(\.locations).count == 1)
        try directory.file("Library/Caches/deno/location_data/abc/kv.sqlite3")
        #expect(await DeveloperCaches.scan(deno, homeDirectory: directory.url).isEmpty)
    }

    /// The whole table at once: every folder is found, at its own size, and nothing beside it is.
    @Test func findsEveryFolderItKnowsAndNothingElse() async throws {
        let directory = try TemporaryDirectory()
        var expected: Set<String> = []
        for definition in DeveloperCaches.definitions {
            for (path, _) in definition.paths {
                // A wildcard becomes a name it matches: `*` any folder, `[0-9a-f]` one of ccache's shards.
                let concrete = path.replacingOccurrences(of: "*", with: "match").replacingOccurrences(of: "[0-9a-f]", with: "a")
                try directory.file("\(concrete)/content", bytes: 400_000)
                expected.insert(concrete)
                try directory.file("\(concrete)/../elsewhere-\(definition.id)/content", bytes: 400_000)
            }
        }

        let environments = await DeveloperCaches.scan(homeDirectory: directory.url)
        let home = directory.url.path(percentEncoded: false)
        let found = Set(environments.flatMap(\.locations).map { String($0.url.path(percentEncoded: false).dropFirst(home.count)) })
        #expect(found == expected, "missing \(expected.subtracting(found).sorted()), extra \(found.subtracting(expected).sorted())")
        #expect(environments.count == DeveloperCaches.definitions.count)
        #expect(environments.flatMap(\.locations).allSatisfy { ($0.size ?? 0) >= 400_000 })
    }

    /// A folder the guard refuses would be offered and then fail at the last step.
    @Test func everyFolderInTheTableMayActuallyBeRemoved() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let environment = SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root"))
        let guardian = RemovalGuard(environment: environment)

        for definition in DeveloperCaches.definitions {
            for (path, _) in definition.paths {
                let url = home.appending(path: path.replacingOccurrences(of: "*", with: "match"), directoryHint: .isDirectory)
                #expect(guardian.allowsRemoval(of: url), "the guard refuses \(definition.id)'s \(path)")
            }
        }
    }

    @Test func modelsAndEnvironmentsAreListedButNeverPreselected() async throws {
        let directory = try TemporaryDirectory()
        try directory.file(".ollama/models/blobs/sha256-1", bytes: 400_000)
        try directory.file("Library/Caches/pypoetry/virtualenvs/app/bin/python", bytes: 400_000)

        let environments = await DeveloperCaches.scan(homeDirectory: directory.url)
        let locations = environments.flatMap(\.locations)
        #expect(locations.count == 2)
        #expect(locations.allSatisfy { !$0.isRecommended })
        #expect(Set(locations.map(\.kind)) == [.models, .environments])
    }

    /// Peel reads cask definitions from Homebrew's `api` folder, which `brew cleanup` leaves alone too. It is
    /// never offered: without it, the next Homebrew question would go to the network.
    @Test func leavesHomebrewsCopyOfTheCaskDefinitions() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Caches/Homebrew/api/internal/packages.jws.json", bytes: 400_000)
        try directory.file("Library/Caches/Homebrew/downloads/bottle.tar.gz", bytes: 400_000)

        let offered = await DeveloperCaches.scan(homeDirectory: directory.url).flatMap(\.locations)
        #expect(offered.map { $0.url.lastPathComponent } == ["downloads"])
        #expect(offered.allSatisfy { $0.isRecommended })
    }

    /// A store that installed packages link into is not a download cache. In setups that conda, uv, and pnpm
    /// document, clearing it leaves every installed package linking to nothing, and Yarn's Plug'n'Play projects
    /// load every package from its global cache.
    @Test func neverSelectsAStoreInstalledPackagesLinkInto() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("miniconda3/pkgs/numpy/info.json", bytes: 400_000)
        try directory.file(".cache/uv/archive-v0/wheel", bytes: 400_000)
        try directory.file("Library/pnpm/store/v10/files/00/abc", bytes: 400_000)
        try directory.file("Library/Caches/pnpm/metadata/registry.json", bytes: 400_000)
        try directory.file(".yarn/berry/cache/lodash-npm-4.17.21-6382451519-eb835a2e51.zip", bytes: 400_000)

        let locations = await DeveloperCaches.scan(homeDirectory: directory.url).flatMap(\.locations)
        let suggested = locations.filter(\.isRecommended).map(\.url).map { $0.lastPathComponent }
        #expect(locations.count == 5)
        #expect(suggested == ["pnpm"], "a store installed packages link into was suggested")
    }

    @Test func aScanOnlyEverReturnsFoldersInsideTheHomeItIsGiven() async throws {
        let directory = try TemporaryDirectory()
        let outside = try TemporaryDirectory()
        try outside.file("Library/Caches/pip/wheels/wheel", bytes: 400_000)
        try directory.file(".cache/uv/archive/file", bytes: 400_000)
        try directory.file("Documents/notes.txt", bytes: 400_000)
        try directory.file("Library/Caches/pip-not-really/file", bytes: 400_000)

        let environments = await DeveloperCaches.scan(homeDirectory: directory.url)
        let home = directory.url.path(percentEncoded: false)
        #expect(environments.map(\.id) == ["uv"])
        for url in environments.flatMap(\.locations).map(\.url) {
            #expect(url.path(percentEncoded: false).hasPrefix(home))
        }
    }

    @Test func honorsExclusions() async throws {
        let directory = try TemporaryDirectory()
        let cache = try directory.directory(".cache/uv")
        try directory.file(".cache/uv/archive/file", bytes: 400_000)

        let kept = await DeveloperCaches.scan(homeDirectory: directory.url, exclusions: Exclusions(paths: [cache]))
        #expect(kept.isEmpty)
    }

    /// A JetBrains IDE keeps the edits it recorded for an open project in `LocalHistory`, beside its caches.
    /// They are in no repository, so no offered folder may reach one. The home folder is made up, so the test
    /// works on a Mac with no such IDE installed.
    @Test func neverOffersAnIDEsLocalHistory() async throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        for folder in ["caches", "index", "tmp", "LocalHistory"] {
            try directory.file("home/Library/Caches/JetBrains/IntelliJIdea2026.1/\(folder)/file.bin", bytes: 4_096)
        }

        let offered = await DeveloperCaches.scan(homeDirectory: home).flatMap(\.locations).map { $0.url.path(percentEncoded: false) }

        #expect(!offered.isEmpty, "the fabricated IDE folders were not found at all")
        #expect(!offered.contains { $0.contains("/LocalHistory") })
        #expect(!offered.contains { FileManager.default.fileExists(atPath: $0 + "/LocalHistory") })
        #expect(offered.contains { $0.hasSuffix("/caches") })
    }

    /// A cache folder that is a link to another disk is left alone. Moving the link frees nothing, and the tool
    /// would quietly start a new folder on the internal disk.
    @Test func leavesAloneACacheFolderThatIsALink() async throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        try directory.file("elsewhere/hub/blob.bin", bytes: 400_000)
        try directory.directory("home/.cache/huggingface")
        try FileManager.default.createSymbolicLink(
            at: home.appending(path: ".cache/huggingface/hub"),
            withDestinationURL: directory.url.appending(path: "elsewhere/hub")
        )

        let offered = await DeveloperCaches.scan(homeDirectory: home).flatMap(\.locations).map { $0.url.lastPathComponent }

        #expect(!offered.contains("hub"))
    }

    /// Nothing offered may sit inside something else offered: removing the outer one would take the inner.
    @Test func offersNoPathInsideAnother() async throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        for path in ["Library/Caches/JetBrains/IntelliJIdea2026.1/caches/a", "Library/Caches/Homebrew/downloads/b", ".npm/_cacache/c"] {
            try directory.file("home/\(path)", bytes: 16)
        }

        let offered = await DeveloperCaches.scan(homeDirectory: home).flatMap(\.locations).map { PathPattern.comparablePath(of: $0.url).lowercased() }

        for path in offered {
            #expect(!offered.contains { $0 != path && path.hasPrefix($0 + "/") }, "\(path) sits inside another offered folder")
        }
    }
}

import Foundation
@testable import PeelCore
import PeelPrivileged
import Testing

struct DeveloperCachesTests {
    /// A scan stopped while it waits on a folder returns within a second and measures no more folders.
    @Test func aStoppedScanStops() async throws {
        let directory = try TemporaryDirectory()
        let paths = (1...30).map { "Library/Caches/Tool/\($0)" }
        for path in paths {
            try directory.directory(path)
        }
        let tool = DeveloperCaches.Definition(id: "tool", name: "Tool", systemImage: "hammer", appBundleIdentifiers: [], folders: paths.map { DeveloperCaches.Folder($0, .cache, source: "https://example.com") })
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
    @Test(.permissionsHold) func tellsAFolderMacOSRefusedFromOneThatDidNotAnswer() async throws {
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

    /// Xcode's caches wait on Simulator too, so the request to quit names whichever of an environment's apps is
    /// running: the environment's name would ask for Xcode while only Simulator runs, and the request would keep
    /// coming back. Finder runs on every Mac, and an identifier nobody uses stands for an app that is closed.
    @Test func namesTheAppThatRunsRatherThanTheEnvironment() throws {
        let xcode = try #require(DeveloperCaches.definitions.first { $0.id == "xcode" })
        #expect(xcode.appBundleIdentifiers.contains("com.apple.dt.Xcode"))
        #expect(xcode.appBundleIdentifiers.contains("com.apple.iphonesimulator"))
        func environment(_ apps: [String]) -> DeveloperEnvironment {
            DeveloperEnvironment(id: "tools", name: "Tools", systemImage: "hammer", appBundleIdentifiers: apps, locations: [])
        }

        #expect(environment(["org.example.closed", "com.apple.finder"]).runningApp == "Finder")
        #expect(environment(["org.example.closed"]).runningApp == nil)
    }

    /// Space asks about a folder however it was spelled, so another spelling of the same folder (another case, or
    /// the home folder through a link) must still find what the table lists inside it. Finding nothing, Space
    /// would move Coursier's folder whole, the JVMs beside its cache included.
    @Test func findsWhatItListsInsideAFolderSpelledAnotherWay() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("home/Library/Caches/Coursier/v1")
        try FileManager.default.createSymbolicLink(at: directory.url.appending(path: "link"), withDestinationURL: directory.url.appending(path: "home"))
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)

        let left = { (folder: URL) in DeveloperCaches.foldersLeftToDeveloper(inside: folder, home: home) }
        let asWritten = left(home.appending(path: "Library/Caches", directoryHint: .isDirectory))
        let otherCase = left(home.appending(path: "library/caches", directoryHint: .isDirectory))
        let throughALink = left(directory.url.appending(path: "link/Library/Caches", directoryHint: .isDirectory))

        #expect(asWritten.contains(["Coursier"]))
        #expect(otherCase == asWritten, "another case found \(otherCase)")
        #expect(throughALink == asWritten, "a link found \(throughALink)")
    }

    @Test func reportsOnlyExistingLocationsSortedBySize() async throws {
        let directory = try TemporaryDirectory()
        try directory.file(".npm/_cacache/content/data", bytes: 80_000)
        try directory.file(".npm/_npx/package/index.js", bytes: 8_000)
        try directory.file("Library/Developer/Xcode/DerivedData/ModuleCache.noindex/module.pcm", bytes: 20_000)
        try directory.directory("Library/Developer/Xcode/Archives/2026-09-17/App 17.09.2026, 10.00.xcarchive")

        let environments = await DeveloperCaches.scan(homeDirectory: directory.url)

        #expect(environments.map(\.id) == ["npm", "xcode"])
        let npm = try #require(environments.first)
        #expect(npm.locations.map(\.url.lastPathComponent) == ["_cacache", "_npx"])
        let xcode = try #require(environments.last)
        #expect(xcode.locations.first { $0.kind == .archives }?.isRecommended == false)
        #expect(xcode.locations.first { $0.kind == .buildData }?.isRecommended == true)
    }

    @Test func listsABrowsersCachesAndNothingOfWhatItKeepsForThePerson() async throws {
        let directory = try TemporaryDirectory()
        let chrome = "Library/Application Support/Google/Chrome"
        let caches = [
            "ShaderCache", "GrShaderCache", "component_crx_cache", "extensions_crx_cache", "Default/GPUCache",
            "Profile 1/DawnWebGPUCache",
        ]
        for cache in caches {
            try directory.file("\(chrome)/\(cache)/data_0", bytes: 4_096)
        }
        let kept = [
            "Default/Local Storage/leveldb/000003.log", "Default/Service Worker/CacheStorage/index", "Default/History",
        ]
        for kept in kept + ["Local State"] {
            try directory.file("\(chrome)/\(kept)", bytes: 4_096)
        }

        let environments = await DeveloperCaches.scan(homeDirectory: directory.url)

        let folder = directory.url.appending(path: chrome).path(percentEncoded: false) + "/"
        let listed = try #require(environments.first { $0.id == "chrome" }).locations.map {
            $0.url.path(percentEncoded: false).replacingOccurrences(of: folder, with: "")
        }
        #expect(Set(listed) == Set(caches))
    }

    @Test func neverListsAFolderInsideAnotherItAlreadyLists() async throws {
        let directory = try TemporaryDirectory()
        let chrome = "Library/Application Support/Google/Chrome"
        try directory.file("\(chrome)/GPUPersistentCache/GPUCache/data_0", bytes: 4_096)
        try directory.file("\(chrome)/Default/GPUCache/data_0", bytes: 4_096)

        let environments = await DeveloperCaches.scan(homeDirectory: directory.url)

        let folder = directory.url.appending(path: chrome).path(percentEncoded: false) + "/"
        let listed = try #require(environments.first { $0.id == "chrome" }).locations.map {
            $0.url.path(percentEncoded: false).replacingOccurrences(of: folder, with: "")
        }
        #expect(Set(listed) == ["GPUPersistentCache", "Default/GPUCache"])
    }

    @Test func listsABrowsersModelsWithoutSelectingThem() async throws {
        let directory = try TemporaryDirectory()
        let chrome = "Library/Application Support/Google/Chrome"
        try directory.file("\(chrome)/OptGuideOnDeviceModel/2025.8.8.1141/weights.bin", bytes: 4_096)
        try directory.file("\(chrome)/optimization_guide_model_store/2/abc/model.tflite", bytes: 4_096)

        let environments = await DeveloperCaches.scan(homeDirectory: directory.url)

        let models = try #require(environments.first { $0.id == "chrome" }).locations
        let names = models.map(\.url.lastPathComponent).sorted()
        #expect(names == ["OptGuideOnDeviceModel", "optimization_guide_model_store"])
        #expect(models.allSatisfy { $0.kind == .models && !$0.isRecommended })
    }

    @Test func listsAnElectronAppsCachesWhereItsDataCarriesLocalState() async throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let app = { (name: String, electron: Bool) throws -> InstalledApp in
            let bundle = try directory.directory("Applications/\(name).app/Contents/Frameworks")
            if electron {
                let framework = bundle.appending(path: "Electron Framework.framework")
                try FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
            }
            return InstalledApp(
                url: bundle.deletingLastPathComponent().deletingLastPathComponent(),
                bundleIdentifier: "org.example.\(name.lowercased())", name: name, bundleName: name
            )
        }
        let apps = [try app("Chat", true), try app("Notes", true), try app("Native", false), try app("Code", true)]
        for name in ["Chat", "Native", "Code"] {
            try directory.file("home/Library/Application Support/\(name)/Local State")
            try directory.file("home/Library/Application Support/\(name)/GPUCache/data_0", bytes: 4_096)
        }
        try directory.file("home/Library/Application Support/Notes/GPUCache/data_0", bytes: 4_096)
        try directory.file("home/Library/Application Support/Chat/Cache/Cache_Data/index", bytes: 4_096)
        try directory.file("home/Library/Application Support/Chat/Local Storage/leveldb/000003.log", bytes: 4_096)

        let definitions = DeveloperCaches.electronDefinitions(for: apps, home: home)
        let environments = await DeveloperCaches.scan(definitions, homeDirectory: home)

        #expect(definitions.map(\.id) == ["electron.org.example.chat"])
        let chat = try #require(environments.first)
        #expect(chat.appBundleIdentifiers == ["org.example.chat"])
        #expect(chat.locations.map(\.url.lastPathComponent).sorted() == ["Cache", "GPUCache"])
    }

    /// A large `DerivedData`, or a Gradle cache on a cold disk, may not be measured in time. Such a folder is not
    /// read as empty: it is listed first, with no size, and never selected for the user.
    @Test func aFolderThatDidNotAnswerInTimeIsNotReadAsEmpty() async throws {
        let directory = try TemporaryDirectory()
        try directory.file(".npm/_cacache/content/data", bytes: 80_000)
        try directory.file(".npm/_npx/package/index.js", bytes: 8_000)
        try directory.file("Library/Developer/Xcode/DerivedData/ModuleCache.noindex/module.pcm", bytes: 20_000)

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
        // The only top-level entries in the table, each owned outright by the one tool that made it.
        let ownedOutright: Set<String> = [
            ".ccache", ".electron-gyp", ".gitlibs", ".node-gyp", ".virtualenvs", "nltk_data", "tensorflow_datasets",
            ".zcompdump*",
        ]
        for definition in DeveloperCaches.definitions {
            for path in definition.folders.map(\.path) {
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
            ".sdkman", ".jenv", "nix/store", ".nix-profile", ".asdf", ".volta",
            "conda/envs", "miniconda3/envs", "anaconda3/envs", ".local/pipx",
            "Library/Android/sdk", "flutter/bin", ".stack/programs",
            ".aws", ".ssh", ".gnupg", ".netrc", ".docker/config", ".kube/config", ".npmrc",
            "qiskit-ibm.json", "qiskitrc", "dwave.conf", ".qcs", "xanadu-cloud", "pytket", ".qnx", "qbraidrc",
            "credentials", "token",
        ]
        // Folders that hold an account, the user's own work, or an installation beside something cache-like. Only
        // what is inside them may ever be listed, never they or a folder around them.
        let onlyInParts: Set<String> = [
            ".kube/cache", ".azure", ".config/gcloud", ".pulumi", ".qiskit", ".qbraid", ".expo", ".lmstudio",
            "Library/Preferences/netlify", "Library/Application Support/com.vercel.cli",
            "Library/Application Support/nomic.ai/GPT4All", "Library/Application Support/Adobe/Common",
            // Coursier keeps the JVMs `cs java` installs beside its cache; a legacy `~/.ccache` holds `ccache.conf`.
            "Library/Caches/Coursier", ".ccache",
            // Corepack keeps the package manager versions a person chose in `lastKnownGood.json` beside its downloads.
            ".cache/node/corepack",
            // Hex and Gleam keep a Hex account's key beside their packages; pub, RubyGems, rebar3, Stack, and opam
            // what they installed; renv each project's library; the Dart analysis server each plug-in's state.
            ".hex", "Library/Caches/gleam/hex/hexpm", ".pub-cache", ".local/share/gem", ".cache/rebar3", ".stack", ".opam",
            "Library/Caches/org.R-project.R/R/renv", ".dartServer",
            // VS Code and the editors built on it keep unsaved files in `Backups`; Zed its database and threads;
            // Neovim its swap and undo files.
            "Library/Application Support/Code", "Library/Application Support/VSCodium", "Library/Application Support/Cursor",
            "Library/Application Support/Zed", ".local/state/nvim",
            // minikube keeps its clusters' keys and the images a person added; Vagrant its machine index and key;
            // Jan its chat history; Ollama a copy of its app while it updates.
            ".minikube", ".minikube/cache/images", ".vagrant.d", "Library/Application Support/Jan/data", "Library/Caches/ollama",
            // Unity keeps its licenses beside its caches.
            "Library/Unity",
        ]
        // CocoaPods' spec repositories hold the ones a person added, which can carry unpushed work: only the CDN copy
        // of the public index, `trunk`, is a cache. nvm's, pyenv's, rbenv's and rustup's folders hold every version
        // they installed; only their download caches are caches.
        let onlyThisPart = [
            ".cocoapods/repos": ".cocoapods/repos/trunk", ".nvm": ".nvm/.cache", ".pyenv": ".pyenv/cache",
            ".rbenv": ".rbenv/cache", ".rustup": ".rustup/downloads",
        ]
        for definition in DeveloperCaches.definitions {
            for path in definition.folders.map(\.path) {
                for pattern in forbidden {
                    #expect(!path.lowercased().contains(pattern.lowercased()), "\(definition.id) lists \(path)")
                }
                for folder in onlyInParts {
                    #expect(!PathComponents.isPath(folder, atOrInside: path), "\(definition.id) lists the whole of \(folder)")
                }
                for (folder, part) in onlyThisPart where PathComponents.isPath(path, atOrInside: folder) {
                    #expect(path == part, "\(definition.id) lists \(path)")
                }
            }
        }
    }

    /// Every folder the table offers names where its tool documents it: a page, or the file inside Xcode that names
    /// it, for the folders Apple documents nowhere else.
    @Test func everyFolderNamesItsSource() {
        for definition in DeveloperCaches.definitions {
            for folder in definition.folders {
                let isAPage = folder.source.hasPrefix("https://") && URL(string: folder.source)?.host() != nil
                #expect(isAPage || folder.source.hasPrefix("Xcode 27: "), "\(definition.id)'s \(folder.path) names \(folder.source)")
            }
        }
    }

    @Test func everyOwnFolderHoldsWhatItsToolLists() {
        for definition in DeveloperCaches.definitions {
            for own in definition.ownFolders {
                let names = PathComponents.of(own)
                let holds = definition.folders.contains { PathComponents.of($0.path).starts(with: names) }
                #expect(holds, "\(definition.id)'s \(own) holds none of its folders")
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
            #expect(!definition.folders.isEmpty, "\(definition.id) has no folders")
            for path in definition.folders.map(\.path) {
                #expect(seen[path] == nil, "\(path) is listed by both \(seen[path] ?? "") and \(definition.id)")
                seen[path] = definition.id
            }
        }
    }

    /// A path inside another would count the same bytes twice, and moving the outer folder would take the inner.
    @Test func noPathIsInsideAnother() {
        let paths = DeveloperCaches.definitions.flatMap { definition in definition.folders.map { ($0.path, definition.id) } }
        for (path, owner) in paths {
            for (other, otherOwner) in paths where other != path {
                #expect(!path.hasPrefix(other + "/"), "\(owner) lists \(path) inside \(otherOwner)'s \(other)")
            }
        }
    }

    /// `~/Library/Caches/deno` is Deno's `DENO_DIR`. Beside its caches it keeps the REPL history
    /// (`deno_history.txt`) and what scripts store (`location_data`, with `localStorage` and the database behind
    /// `Deno.openKv()`), so only the caches are offered, whatever else is there.
    @Test func offersDenosCachesAndNeverItsHistoryOrWhatScriptsKept() async throws {
        let directory = try TemporaryDirectory()
        for cache in ["remote/https/deno.land/x.ts", "npm/registry.npmjs.org/chalk/5.3.0/index.js", "deps/https/x.ts",
                      "gen/file/x.js", "registries/deno.land.json", "dl/deno-2.0.0.zip", "check_cache_v2", "dep_analysis_cache_v1"] {
            try directory.file("Library/Caches/deno/\(cache)", bytes: 400_000)
        }
        try directory.file("Library/Caches/deno/deno_history.txt", bytes: 4_096)
        try directory.file("Library/Caches/deno/location_data/abc/kv.sqlite3", bytes: 4_096)
        try directory.file("Library/Caches/deno/latest.txt", bytes: 64)
        let deno = DeveloperCaches.definitions.filter { $0.id == "deno" }

        let offered = Set(await DeveloperCaches.scan(deno, homeDirectory: directory.url).flatMap(\.locations).map(\.url.lastPathComponent))

        #expect(offered == ["remote", "npm", "deps", "gen", "registries", "dl", "check_cache_v2", "dep_analysis_cache_v1"])
    }

    /// The whole table at once: every folder is found, at its own size, and nothing beside it is.
    @Test func findsEveryFolderItKnowsAndNothingElse() async throws {
        let directory = try TemporaryDirectory()
        var expected: Set<String> = []
        for definition in DeveloperCaches.definitions {
            for folder in definition.folders {
                // A wildcard becomes a name it matches: `*` any folder, `[0-9a-f]` one of ccache's shards. A pattern
                // that ends in `/` matches every folder beside, so what sits beside its match is a file.
                let concrete = folder.path.replacingOccurrences(of: "*", with: "match").replacingOccurrences(of: "[0-9a-f]", with: "a")
                let foldersOnly = concrete.hasSuffix("/")
                let entry = foldersOnly ? String(concrete.dropLast()) : concrete
                let row = entry + (0..<folder.rowsDepth).map { "/row \($0)" }.joined() + (folder.rowEnding ?? "")
                try directory.file("\(row)/content", bytes: 400_000)
                expected.insert(row)
                try directory.file("\(entry)/../elsewhere-\(definition.id)" + (foldersOnly ? "" : "/content"), bytes: 400_000)
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
            for path in definition.folders.map(\.path) {
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

    /// Xcode's hardware support installers, Unity's Asset Store packages and Vagrant's boxes are kept for the person
    /// to install again.
    @Test func downloadsKeptToInstallAgainAreListedButNeverSelected() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Developer/Packages/HardwareSupport.pkg", bytes: 400_000)
        try directory.file("Library/Unity/Asset Store-5.x/Publisher/Tools/Package.unitypackage", bytes: 400_000)
        try directory.file(".vagrant.d/boxes/hashicorp-VAGRANTSLASH-bionic64/0/virtualbox/box-disk001.vmdk", bytes: 400_000)

        let locations = await DeveloperCaches.scan(homeDirectory: directory.url).flatMap(\.locations)

        #expect(locations.count == 3)
        #expect(locations.allSatisfy { $0.kind == .keptDownloads && !$0.isRecommended })
    }

    /// The browsers and binaries test tools install are not fetched again when they are gone: `npx playwright
    /// install`, Cypress's `postinstall` and `npx puppeteer browsers install` put them back. They are listed as
    /// installed packages and never selected.
    @Test func browsersATestToolInstalledAreNeverSelected() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Caches/ms-playwright/chromium-1200/chrome-mac/Chromium.bin", bytes: 400_000)
        try directory.file("Library/Caches/ms-playwright-go/1.50.0/node", bytes: 400_000)
        try directory.file("Library/Caches/Cypress/15.0.0/Cypress.bin", bytes: 400_000)
        try directory.file(".cache/puppeteer/chrome/mac_arm-140.0/chrome.bin", bytes: 400_000)

        let locations = await DeveloperCaches.scan(homeDirectory: directory.url).flatMap(\.locations)

        #expect(locations.count == 4)
        #expect(locations.allSatisfy { $0.kind == .environments && !$0.isRecommended })
    }

    /// Xcode copies a device's symbols when the device connects. Most come back only from a device running that
    /// system version, none comes back by itself, and crash reports need them: they are listed and never selected.
    @Test func symbolsFromDevicesAreNeverSelected() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Developer/Xcode/iOS DeviceSupport/iPhone17,1 18.6 (22G86)/Symbols/dyld", bytes: 400_000)
        try directory.file("Library/Developer/Xcode/watchOS DeviceSupport/Watch7,2 11.6 (22U80)/Symbols/dyld", bytes: 400_000)

        let locations = await DeveloperCaches.scan(homeDirectory: directory.url).flatMap(\.locations)

        #expect(locations.count == 2)
        #expect(locations.allSatisfy { $0.kind == .deviceSupport && !$0.isRecommended })
    }

    @Test func listsEachSystemVersionsSymbolsOnItsOwnAndSelectsNone() async throws {
        let directory = try TemporaryDirectory()
        let support = "Library/Developer/Xcode/iOS DeviceSupport"
        try directory.file("\(support)/iPhone17,1 18.6 (22G86)/Symbols/dyld", bytes: 400_000)
        try directory.file("\(support)/iPhone17,1 26.0 (23A341)/Symbols/dyld", bytes: 400_000)
        try directory.file("\(support)/.DS_Store", bytes: 16)

        let locations = await DeveloperCaches.scan(homeDirectory: directory.url).flatMap(\.locations)

        #expect(Set(locations.map(\.url.lastPathComponent)) == ["iPhone17,1 18.6 (22G86)", "iPhone17,1 26.0 (23A341)"])
        #expect(locations.allSatisfy { $0.kind == .deviceSupport && !$0.isRecommended })
    }

    @Test func listsEachArchiveWithTheVersionItHoldsAndSelectsNone() async throws {
        let directory = try TemporaryDirectory()
        let archives = "Library/Developer/Xcode/Archives"
        let facts: [String: Any] = ["ApplicationProperties": ["CFBundleShortVersionString": "2.1", "CFBundleVersion": "45"]]
        try directory.file(
            "\(archives)/2026-09-01/App 01.09.2026, 10.00.xcarchive/Info.plist",
            contents: try PropertyListSerialization.data(fromPropertyList: facts, format: .xml, options: 0)
        )
        try directory.file("\(archives)/2026-09-02/App 02.09.2026, 11.00.xcarchive/Products/Applications/App.app/App", bytes: 400_000)
        try directory.file("\(archives)/2026-09-02/notes.txt", bytes: 16)

        let locations = await DeveloperCaches.scan(homeDirectory: directory.url).flatMap(\.locations)

        #expect(locations.count == 2)
        #expect(locations.allSatisfy { $0.kind == .archives && !$0.isRecommended })
        let first = try #require(locations.first { $0.url.lastPathComponent.hasPrefix("App 01.09") })
        #expect(first.archive == DeveloperEnvironment.Archive(version: "2.1", build: "45"))
        #expect(first.archive?.label == "2.1 (45)")
        #expect(DeveloperEnvironment.Archive(version: nil, build: "45").label == "45")
        #expect(locations.first { $0.url.lastPathComponent.hasPrefix("App 02.09") }?.archive == nil)
    }

    @Test func listsEveryArchiveHoweverManyThereAre() async throws {
        let directory = try TemporaryDirectory()
        for day in 1...130 {
            try directory.directory("Library/Developer/Xcode/Archives/day \(day)/App \(day).xcarchive")
        }

        let locations = await DeveloperCaches.scan(homeDirectory: directory.url).flatMap(\.locations)

        #expect(locations.count == 130)
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

    /// Of what Xcode keeps for previews, only the simulator devices it makes for them are offered: Xcode itself lists
    /// that folder among the simulator device sets it removes.
    @Test func offersOnlyTheSimulatorDevicesXcodeMakesForPreviews() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Developer/Xcode/UserData/Previews/Simulator Devices/device_set.plist", bytes: 400_000)
        try directory.file("Library/Developer/Xcode/UserData/Previews/other/state", bytes: 400_000)
        let xcode = DeveloperCaches.definitions.filter { $0.id == "xcode" }

        let offered = await DeveloperCaches.scan(xcode, homeDirectory: directory.url).flatMap(\.locations).map(\.url.lastPathComponent)

        #expect(offered == ["Simulator Devices"])
    }

    @Test func offersEverySimulatorDeviceSetXcodeRemovesItself() async throws {
        let directory = try TemporaryDirectory()
        let sets = [
            "Library/Developer/XCTestDevices",
            "Library/Developer/XCPGDevices",
            "Library/Developer/Xcode/UserData/IB Support/Simulator Devices",
            "Library/Developer/Xcode/UserData/Previews/Simulator Devices",
            "Library/Developer/Xcode/UserData-Tests/Previews/Simulator Devices",
            "Library/Developer/Xcode/UserData/RT Support/Simulator Devices",
        ]
        for set in sets {
            try directory.file("\(set)/device_set.plist", bytes: 400_000)
        }
        try directory.file("Library/Developer/Xcode/UserData/IB Support/other/state", bytes: 400_000)
        let xcode = DeveloperCaches.definitions.filter { $0.id == "xcode" }

        let locations = await DeveloperCaches.scan(xcode, homeDirectory: directory.url).flatMap(\.locations)

        let home = directory.url.path(percentEncoded: false)
        #expect(Set(locations.map { String($0.url.path(percentEncoded: false).dropFirst(home.count)) }) == Set(sets))
        #expect(locations.allSatisfy { $0.isRecommended })
    }

    @Test func offersTheDocumentationXcodeCaches() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Developer/Xcode/DocumentationCache/v27/index.db", bytes: 400_000)
        let xcode = DeveloperCaches.definitions.filter { $0.id == "xcode" }

        let locations = await DeveloperCaches.scan(xcode, homeDirectory: directory.url).flatMap(\.locations)

        #expect(locations.map(\.url.lastPathComponent) == ["DocumentationCache"])
        #expect(locations.first?.kind == .cache)
    }

    @Test func offersTheLogsOfTheSimulatorsAndSpaceLeavesThemToDeveloper() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Logs/CoreSimulator/CoreSimulator.log", bytes: 400_000)
        let xcode = DeveloperCaches.definitions.filter { $0.id == "xcode" }

        let locations = await DeveloperCaches.scan(xcode, homeDirectory: directory.url).flatMap(\.locations)
        let logs = directory.url.appending(path: "Library/Logs", directoryHint: .isDirectory)

        #expect(locations.map(\.url.lastPathComponent) == ["CoreSimulator"])
        #expect(locations.first?.kind == .logs)
        #expect(DeveloperCaches.foldersLeftToDeveloper(inside: logs, home: directory.url).contains(["CoreSimulator"]))
    }

    @Test func listsDerivedDataByWorkspaceAndLeavesTheOnesUsedThisWeek() async throws {
        let directory = try TemporaryDirectory()
        let derived = "Library/Developer/Xcode/DerivedData"
        func workspace(_ folder: String, path: String, lastUsed: Date) throws {
            let info: [String: Any] = ["WorkspacePath": path, "LastAccessedDate": lastUsed]
            let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try directory.file("\(derived)/\(folder)/info.plist", contents: data)
            try directory.file("\(derived)/\(folder)/Build/Products/app", bytes: 400_000)
        }
        try workspace("Notes-abcdefghijklmnopqrstuvwxyzab", path: "/Code/Notes/Notes.xcodeproj", lastUsed: .now - 30 * 86_400)
        try workspace("Chat-bcdefghijklmnopqrstuvwxyzabc", path: "/Code/Chat/Chat.xcworkspace", lastUsed: .now - 86_400)
        try directory.file("\(derived)/ModuleCache.noindex/module.pcm", bytes: 400_000)
        try directory.file("\(derived)/Notes Backup/Notes.swift", bytes: 400_000)
        let xcode = DeveloperCaches.definitions.filter { $0.id == "xcode" }

        let locations = await DeveloperCaches.scan(xcode, homeDirectory: directory.url).flatMap(\.locations)
        let byName = Dictionary(uniqueKeysWithValues: locations.map { ($0.url.lastPathComponent, $0) })

        #expect(Set(byName.keys) == [
            "Notes-abcdefghijklmnopqrstuvwxyzab", "Chat-bcdefghijklmnopqrstuvwxyzabc", "ModuleCache.noindex", "Notes Backup",
        ])
        #expect(byName["Notes-abcdefghijklmnopqrstuvwxyzab"]?.workspace?.name == "Notes")
        #expect(byName["Notes-abcdefghijklmnopqrstuvwxyzab"]?.isRecommended == true)
        #expect(byName["Chat-bcdefghijklmnopqrstuvwxyzabc"]?.workspace?.name == "Chat")
        #expect(byName["Chat-bcdefghijklmnopqrstuvwxyzabc"]?.isRecommended == false)
        #expect(byName["ModuleCache.noindex"]?.isRecommended == true)
        #expect(byName["Notes Backup"]?.isRecommended == false)
    }

    @Test func findsDerivedDataAndArchivesWhereXcodesSettingsMovedThem() async throws {
        let directory = try TemporaryDirectory()
        let info = try PropertyListSerialization.data(
            fromPropertyList: ["WorkspacePath": "/Code/Notes/Notes.xcodeproj", "LastAccessedDate": Date.now - 30 * 86_400],
            format: .xml, options: 0
        )
        try directory.file("Fast/DerivedData/Notes-abcdefghijklmnopqrstuvwxyzab/info.plist", contents: info)
        try directory.file("Fast/DerivedData/Notes-abcdefghijklmnopqrstuvwxyzab/Build/app", bytes: 400_000)
        try directory.file("Fast/DerivedData/Photos/beach.jpg", bytes: 400_000)
        try directory.directory("Fast/Archives/2026-09-17/Notes 17.09.2026, 10.00.xcarchive")
        try directory.file("Library/Developer/Xcode/DerivedData/ModuleCache.noindex/module.pcm", bytes: 400_000)
        let moved = [
            "IDECustomDerivedDataLocation": directory.url.appending(path: "Fast/DerivedData").path(percentEncoded: false),
            "IDECustomDistributionArchivesLocation": directory.url.appending(path: "Fast/Archives").path(percentEncoded: false),
        ]
        let xcode = DeveloperCaches.definitions.filter { $0.id == "xcode" }

        let locations = await DeveloperCaches.scan(xcode, homeDirectory: directory.url, preference: { moved[$0] })
            .flatMap(\.locations)
        let byName = Dictionary(uniqueKeysWithValues: locations.map { ($0.url.lastPathComponent, $0) })

        #expect(Set(byName.keys) == [
            "Notes-abcdefghijklmnopqrstuvwxyzab", "Photos", "Notes 17.09.2026, 10.00.xcarchive", "ModuleCache.noindex",
        ])
        #expect(byName["Notes-abcdefghijklmnopqrstuvwxyzab"]?.isRecommended == true)
        #expect(byName["Photos"]?.isRecommended == false)
        #expect(byName["Notes 17.09.2026, 10.00.xcarchive"]?.kind == .archives)
    }

    @Test func aSettingThatIsNotAnAbsolutePathMovesNothing() async throws {
        let directory = try TemporaryDirectory()
        let xcode = DeveloperCaches.definitions.filter { $0.id == "xcode" }

        let environments = await DeveloperCaches.scan(xcode, homeDirectory: directory.url, preference: { _ in "." })

        #expect(environments.isEmpty)
    }

    @Test func readsAnArchivesInfoOnlyWhenItIsAPlainFileOfASensibleSize() throws {
        let directory = try TemporaryDirectory()
        let facts: [String: Any] = [
            "ApplicationProperties": ["CFBundleShortVersionString": "2.1", "CFBundleVersion": "45"],
            "Padding": String(repeating: "x", count: BoundedRead.maximumBytes),
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: facts, format: .binary, options: 0)
        try directory.file("Huge.xcarchive/Info.plist", contents: data)
        let pipe = try directory.directory("Pipe.xcarchive").appending(path: "Info.plist")
        #expect(mkfifo(pipe.path(percentEncoded: false), 0o600) == 0)

        #expect(DeveloperCaches.archive(at: directory.url.appending(path: "Huge.xcarchive")) == nil)
        #expect(DeveloperCaches.archive(at: directory.url.appending(path: "Pipe.xcarchive")) == nil)
    }

    @Test func offersEveryCacheHomebrewNamesAndNeverItsCopyOfTheDefinitions() async throws {
        let directory = try TemporaryDirectory()
        for folder in ["glide_home", "api-source", "gh-actions-artifact", "go_cache", "api"] {
            try directory.file("Library/Caches/Homebrew/\(folder)/data", bytes: 400_000)
        }
        let homebrew = DeveloperCaches.definitions.filter { $0.id == "homebrew" }

        let offered = await DeveloperCaches.scan(homebrew, homeDirectory: directory.url).flatMap(\.locations)

        #expect(Set(offered.map(\.url.lastPathComponent)) == ["glide_home", "api-source", "gh-actions-artifact", "go_cache"])
    }

    @Test func offersThePrebuiltBinariesNativeModulesDownloadedIntoNpmsFolder() async throws {
        let directory = try TemporaryDirectory()
        try directory.file(".npm/_prebuilds/b1f2-better-sqlite3-v12.0.0-node-v137-darwin-arm64.tar.gz", bytes: 400_000)
        let npm = DeveloperCaches.definitions.filter { $0.id == "npm" }

        let locations = await DeveloperCaches.scan(npm, homeDirectory: directory.url).flatMap(\.locations)

        #expect(locations.map(\.url.lastPathComponent) == ["_prebuilds"])
        #expect(locations.first?.isRecommended == true)
    }

    @Test func offersThePackagesPyenvAndRbenvKeptAndNeverTheirInstalledVersions() async throws {
        let directory = try TemporaryDirectory()
        try directory.file(".pyenv/cache/Python-3.13.1.tar.xz", bytes: 400_000)
        try directory.file(".pyenv/versions/3.13.1/bin/python3", bytes: 400_000)
        try directory.file(".rbenv/cache/ruby-3.4.1.tar.gz", bytes: 400_000)
        try directory.file(".rbenv/versions/3.4.1/bin/ruby", bytes: 400_000)
        let tools = DeveloperCaches.definitions.filter { ["pyenv", "rbenv"].contains($0.id) }

        let locations = await DeveloperCaches.scan(tools, homeDirectory: directory.url).flatMap(\.locations)

        let home = directory.url.path(percentEncoded: false)
        #expect(Set(locations.map { String($0.url.path(percentEncoded: false).dropFirst(home.count)) }) == [
            ".pyenv/cache", ".rbenv/cache",
        ])
        #expect(locations.allSatisfy { $0.kind == .downloads })
    }

    @Test func offersOnlyTheBinaryCachesOfPyInstaller() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Application Support/pyinstaller/bincache00_py313_arm64/libpython.dylib", bytes: 400_000)
        try directory.file("Library/Application Support/pyinstaller/other/state", bytes: 400_000)
        let pyinstaller = DeveloperCaches.definitions.filter { $0.id == "pyinstaller" }

        let locations = await DeveloperCaches.scan(pyinstaller, homeDirectory: directory.url).flatMap(\.locations)

        #expect(locations.map(\.url.lastPathComponent) == ["bincache00_py313_arm64"])
    }

    @Test func offersTheAndroidToolsCachesAndNothingElseOfTheirFolder() async throws {
        let directory = try TemporaryDirectory()
        try directory.file(".android/cache/sdkbin-1_4b3a.xml", bytes: 400_000)
        try directory.file(".android/build-cache/3.6.1/output/classes.dex", bytes: 400_000)
        try directory.file(".android/avd/Pixel.avd/userdata.img", bytes: 400_000)
        try directory.file(".android/debug.keystore", bytes: 4_096)
        let studio = DeveloperCaches.definitions.filter { $0.id == "androidstudio" }

        let locations = await DeveloperCaches.scan(studio, homeDirectory: directory.url).flatMap(\.locations)

        #expect(Set(locations.map(\.url.lastPathComponent)) == ["cache", "build-cache"])
    }

    @Test func offersTheImagesTartKeepsAndNeverItsMachines() async throws {
        let directory = try TemporaryDirectory()
        try directory.file(".tart/cache/OCIs/ghcr.io/cirruslabs/macos/disk.img", bytes: 400_000)
        try directory.file(".tart/vms/builder/disk.img", bytes: 400_000)
        let tart = DeveloperCaches.definitions.filter { $0.id == "tart" }

        let locations = await DeveloperCaches.scan(tart, homeDirectory: directory.url).flatMap(\.locations)

        #expect(locations.map(\.url.lastPathComponent) == ["cache"])
        #expect(locations.first?.kind == .downloads)
    }

    @Test func offersZshsCompletionDumpsAndOhMyZshsCompletionsAndNotTheChoicesKeptBeside() async throws {
        let directory = try TemporaryDirectory()
        try directory.file(".zcompdump", bytes: 4_096)
        try directory.file(".zcompdump-Mac-5.9", bytes: 4_096)
        try directory.file(".oh-my-zsh/cache/completions/_gh", bytes: 4_096)
        try directory.file(".oh-my-zsh/cache/dotenv-allowed.list", bytes: 64)
        let shells = DeveloperCaches.definitions.filter { ["zsh", "ohmyzsh"].contains($0.id) }

        let locations = await DeveloperCaches.scan(shells, homeDirectory: directory.url).flatMap(\.locations)

        #expect(Set(locations.map(\.url.lastPathComponent)) == [".zcompdump", ".zcompdump-Mac-5.9", "completions"])
    }

    @Test func offersGradlesMarkersAndWorkerFolderAndNeverItsSettings() async throws {
        let directory = try TemporaryDirectory()
        try directory.file(".gradle/notifications/9.1.0/release-features.rendered", bytes: 64)
        try directory.file(".gradle/workers/classpath.jar", bytes: 400_000)
        try directory.file(".gradle/gradle.properties", bytes: 64)
        try directory.file(".gradle/init.d/mirror.gradle", bytes: 64)
        let gradle = DeveloperCaches.definitions.filter { $0.id == "gradle" }

        let locations = await DeveloperCaches.scan(gradle, homeDirectory: directory.url).flatMap(\.locations)

        #expect(Set(locations.map(\.url.lastPathComponent)) == ["notifications", "workers"])
    }

    @Test func offersWhatRustupDownloadedAndNeverItsToolchains() async throws {
        let directory = try TemporaryDirectory()
        try directory.file(".rustup/downloads/4b1c.partial", bytes: 400_000)
        try directory.file(".rustup/toolchains/stable-aarch64-apple-darwin/bin/rustc", bytes: 400_000)
        let rustup = DeveloperCaches.definitions.filter { $0.id == "rustup" }

        let locations = await DeveloperCaches.scan(rustup, homeDirectory: directory.url).flatMap(\.locations)

        #expect(locations.map(\.url.lastPathComponent) == ["downloads"])
    }

    @Test func offersCpansBuildFolderAndNeverItsPreferences() async throws {
        let directory = try TemporaryDirectory()
        try directory.file(".cpan/build/Moose-2.2207-0/Makefile", bytes: 400_000)
        try directory.file(".cpan/prefs/Moose.yml", bytes: 64)
        try directory.file(".cpan/CPAN/MyConfig.pm", bytes: 64)
        let cpan = DeveloperCaches.definitions.filter { $0.id == "cpan" }

        let locations = await DeveloperCaches.scan(cpan, homeDirectory: directory.url).flatMap(\.locations)

        #expect(locations.map(\.url.lastPathComponent) == ["build"])
    }

    @Test func listsStacksSnapshotsWithoutEverSelectingThem() async throws {
        let directory = try TemporaryDirectory()
        try directory.file(".stack/snapshots/aarch64-osx/2f1c/9.8.4/lib/package.conf", bytes: 400_000)
        let stack = DeveloperCaches.definitions.filter { $0.id == "stack" }

        let locations = await DeveloperCaches.scan(stack, homeDirectory: directory.url).flatMap(\.locations)

        #expect(locations.map(\.url.lastPathComponent) == ["snapshots"])
        #expect(locations.first?.isRecommended == false)
    }

    @Test func offersTheRegistryHexCachesAndNeverItsAccountKey() async throws {
        let directory = try TemporaryDirectory()
        try directory.file(".hex/cache.ets", bytes: 400_000)
        try directory.file(".hex/hex.config", bytes: 64)
        let hex = DeveloperCaches.definitions.filter { $0.folders.contains { $0.path.hasPrefix(".hex/") } }

        let locations = await DeveloperCaches.scan(hex, homeDirectory: directory.url).flatMap(\.locations)

        #expect(locations.map(\.url.lastPathComponent) == ["cache.ets"])
    }

    @Test func offersOpencodesCacheAndNeverItsData() async throws {
        let directory = try TemporaryDirectory()
        try directory.file(".cache/opencode/models.json", bytes: 400_000)
        try directory.file(".local/share/opencode/storage/session.json", bytes: 400_000)
        let opencode = DeveloperCaches.definitions.filter { $0.id == "opencode" }

        let locations = await DeveloperCaches.scan(opencode, homeDirectory: directory.url).flatMap(\.locations)

        #expect(locations.map(\.url.lastPathComponent) == ["opencode"])
        #expect(locations.first?.kind == .cache)
    }

    @Test func offersTheConfigurationAndProfileCachesOfEveryEditorBuiltOnVSCode() async throws {
        let directory = try TemporaryDirectory()
        for app in ["Code", "VSCodium", "Cursor"] {
            try directory.file("Library/Application Support/\(app)/CachedConfigurations/folder/key/configuration.json", bytes: 4_096)
            try directory.file("Library/Application Support/\(app)/CachedProfilesData/__default__profile__/extensions.user.cache", bytes: 4_096)
            try directory.file("Library/Application Support/\(app)/Backups/1/untitled", bytes: 4_096)
        }
        let editors = DeveloperCaches.definitions.filter { ["vscode", "vscodium", "cursor"].contains($0.id) }

        let locations = await DeveloperCaches.scan(editors, homeDirectory: directory.url).flatMap(\.locations)

        let support = directory.url.appending(path: "Library/Application Support").path(percentEncoded: false)
        #expect(Set(locations.map { String($0.url.path(percentEncoded: false).dropFirst(support.count + 1)) }) == [
            "Code/CachedConfigurations", "Code/CachedProfilesData", "VSCodium/CachedConfigurations",
            "VSCodium/CachedProfilesData", "Cursor/CachedConfigurations", "Cursor/CachedProfilesData",
        ])
    }

    /// virtualenvwrapper keeps the user's hook scripts beside the environments in `~/.virtualenvs`, so only the
    /// environments are offered, and a link among them is left where it is, never followed.
    @Test func offersVirtualenvwrappersEnvironmentsAndNotItsHooks() async throws {
        let directory = try TemporaryDirectory()
        try directory.file(".virtualenvs/web/bin/python", bytes: 400_000)
        try directory.file(".virtualenvs/postactivate", bytes: 64)
        try directory.file(".virtualenvs/hook.log", bytes: 64)
        let elsewhere = try directory.directory("Volumes/Fast/env")
        try directory.file("Volumes/Fast/env/bin/python", bytes: 400_000)
        try FileManager.default.createSymbolicLink(at: directory.url.appending(path: ".virtualenvs/fast"), withDestinationURL: elsewhere)
        let wrapper = DeveloperCaches.definitions.filter { $0.id == "virtualenvwrapper" }

        let offered = await DeveloperCaches.scan(wrapper, homeDirectory: directory.url).flatMap(\.locations).map(\.url.lastPathComponent)

        #expect(offered == ["web"])
    }

    /// Nx answers a cache hit from its database alone, so a workspace's `cache` and `databases` go together: the
    /// folder that holds both is offered as one, and nothing else in `~/.nx` is.
    @Test func offersNxsCacheAndDatabaseOnlyTogether() async throws {
        let directory = try TemporaryDirectory()
        try directory.file(".nx/5d41402abc4b2a76/cache/12345/outputs/dist.js", bytes: 400_000)
        try directory.file(".nx/5d41402abc4b2a76/databases/workspace.db", bytes: 400_000)
        try directory.file(".nx/sockets/daemon", bytes: 16)
        let nx = DeveloperCaches.definitions.filter { $0.id == "nx" }

        let offered = await DeveloperCaches.scan(nx, homeDirectory: directory.url).flatMap(\.locations).map(\.url.lastPathComponent)

        #expect(offered == ["5d41402abc4b2a76"])
    }

    /// Bun's cache is a plain download cache until its global store is turned on: then `links` inside it is what
    /// every project's `node_modules` points into, and the whole folder is listed without a checkmark. A store
    /// moved to another disk leaves `links` as a link, which projects still reach through the cache.
    @Test func bunsCacheIsSelectedOnlyWhileNoProjectLinksIntoIt() async throws {
        for (hasStore, storeIsALink) in [(false, false), (true, false), (true, true)] {
            let directory = try TemporaryDirectory()
            try directory.file(".bun/install/cache/react@18.3.1@@@1/package.json", bytes: 400_000)
            if storeIsALink {
                let elsewhere = try directory.directory("Volumes/Fast/bun-links")
                try FileManager.default.createSymbolicLink(at: directory.url.appending(path: ".bun/install/cache/links"), withDestinationURL: elsewhere)
            } else if hasStore {
                try directory.file(".bun/install/cache/links/react@18.3.1-5664d3cd670b3205/node_modules/react/index.js", bytes: 4_096)
            }

            let bun = try #require(await DeveloperCaches.scan(homeDirectory: directory.url).first { $0.id == "bun" })

            #expect(bun.locations.count == 1)
            #expect(bun.locations.first?.isRecommended == !hasStore, "links inside: \(hasStore)")
            #expect(bun.locations.first?.kind == (hasStore ? .environments : .downloads))
        }
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

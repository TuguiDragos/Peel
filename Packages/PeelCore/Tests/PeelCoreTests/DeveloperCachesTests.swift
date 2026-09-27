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

    @Test func listsABrowsersCachesAndNothingOfWhatItKeepsForThePerson() async throws {
        let directory = try TemporaryDirectory()
        let chrome = "Library/Application Support/Google/Chrome"
        let caches = [
            "ShaderCache", "GrShaderCache", "component_crx_cache", "Default/GPUCache", "Profile 1/DawnWebGPUCache",
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
        let ownedOutright: Set<String> = [
            ".ccache", ".electron-gyp", ".gitlibs", ".node-gyp", ".virtualenvs", "nltk_data", "tensorflow_datasets",
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
            ".rustup", ".pyenv", ".sdkman", ".rbenv", ".jenv", "nix/store", ".nix-profile", ".asdf", ".volta",
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
        // of the public index, `trunk`, is a cache. nvm's folder is nvm and every Node it installed; only its download
        // cache is one.
        let onlyThisPart = [".cocoapods/repos": ".cocoapods/repos/trunk", ".nvm": ".nvm/.cache"]
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
            for path in definition.folders.map(\.path) {
                // A wildcard becomes a name it matches: `*` any folder, `[0-9a-f]` one of ccache's shards. A pattern
                // that ends in `/` matches every folder beside, so what sits beside its match is a file.
                let concrete = path.replacingOccurrences(of: "*", with: "match").replacingOccurrences(of: "[0-9a-f]", with: "a")
                let foldersOnly = concrete.hasSuffix("/")
                let entry = foldersOnly ? String(concrete.dropLast()) : concrete
                try directory.file("\(entry)/content", bytes: 400_000)
                expected.insert(entry)
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

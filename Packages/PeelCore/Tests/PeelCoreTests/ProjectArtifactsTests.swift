import Foundation
@testable import PeelCore
import Synchronization
import Testing

struct ProjectArtifactsTests {
    @Test func aStoppedScanStops() async throws {
        let directory = try TemporaryDirectory()
        for index in 1...30 {
            try directory.file("Code/Project \(index)/package.json", contents: Data("{}".utf8))
            try directory.file("Code/Project \(index)/node_modules/left-pad/index.js", contents: Data("//".utf8))
        }
        let unanswered = Unanswered()

        let stop = try await unanswered.stop {
            _ = await ProjectArtifacts.scan(
                roots: [directory.url.appending(path: "Code", directoryHint: .isDirectory)],
                exclusions: .none,
                measure: unanswered.walk
            )
        }

        #expect(stop.took < .seconds(1))
        #expect(stop.askedBefore < 30)
        #expect(stop.askedAfter == 0)
    }

    @Test func aFolderThatNeverAnswersHoldsNeitherTheWalkNorItsStop() async throws {
        let directory = try TemporaryDirectory()
        let root = try directory.directory("Code")
        let never = DispatchSemaphore(value: 0)
        defer { never.signal() }
        let listing = Mutex(false)
        let clock = ContinuousClock()
        let walk = Task(priority: .userInitiated) {
            _ = await ProjectArtifacts.artifacts(in: root, exclusions: .none, measure: { _ in nil }) { _ in
                listing.withLock { $0 = true }
                never.wait()
                return nil
            }
            return clock.now
        }
        while !listing.withLock({ $0 }) { await Task.yield() }
        let stopped = clock.now

        walk.cancel()
        let returned = await walk.value

        #expect(returned - stopped < .seconds(1))
    }

    @Test func suggestsTheProjectFoldersThatExistInTheHomeFolder() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("Developer")
        try directory.directory("Code")
        try directory.file("Projects", bytes: 1)
        try directory.directory("Elsewhere/src")
        try FileManager.default.createSymbolicLink(
            atPath: directory.url.appending(path: "src").path(percentEncoded: false),
            withDestinationPath: directory.url.appending(path: "Elsewhere/src").path(percentEncoded: false)
        )

        let suggested = ProjectArtifacts.suggestedRoots(home: directory.url)

        #expect(suggested.map(\.lastPathComponent) == ["Developer", "Code"])
    }

    /// Full Disk Access does not open a folder closed by ordinary file permissions, so the scan must not ask for it.
    /// The Time Machine checkbox marks only what a build certainly makes again, and never an artifact Time
    /// Machine already leaves out through a folder above it, whose exclusion is not its own to change. A project
    /// with nothing else gives the checkbox nothing to do.
    @Test func marksForBackupsOnlyWhatABuildCertainlyMakesAgain() {
        func artifact(_ name: String, isGeneric: Bool, isEnvironment: Bool = false) -> ProjectArtifact {
            ProjectArtifact(
                url: URL(filePath: "/Users/x/Code/App/\(name)"), project: URL(filePath: "/Users/x/Code/App"), name: name,
                tool: "tool", size: 10, lastActivity: nil, hasGenericName: isGeneric, isEnvironment: isEnvironment
            )
        }
        let target = artifact("target", isGeneric: true)
        let modules = artifact("node_modules", isGeneric: false)
        let pods = artifact("Pods", isGeneric: false)
        let terraform = artifact(".terraform", isGeneric: false, isEnvironment: true)

        #expect(ProjectArtifacts.markableForBackups([target], excludedFromAbove: []).isEmpty)
        #expect(ProjectArtifacts.markableForBackups([terraform], excludedFromAbove: []).isEmpty, "no build makes it")
        #expect(
            ProjectArtifacts.markableForBackups([target, modules, pods], excludedFromAbove: [pods.url]) == [modules.url]
        )
        #expect(ProjectArtifacts.markableForBackups([modules], excludedFromAbove: [modules.url]).isEmpty)
    }

    @Test func saysWhenAProjectLastChangedOnlyWhenItKnows() {
        func artifact(_ name: String, changed: Date?, certain: Bool) -> ProjectArtifact {
            let project = URL(filePath: "/Users/x/Code/App")
            var artifact = ProjectArtifact(
                url: project.appending(path: name), project: project, name: name, tool: "tool", size: 10,
                lastActivity: changed, hasGenericName: false, isEnvironment: false
            )
            artifact.lastActivityIsCertain = certain
            return artifact
        }
        let monthsAgo = Date.now.addingTimeInterval(-90 * 86_400)
        let yesterday = Date.now.addingTimeInterval(-86_400)

        let known = artifact("build", changed: monthsAgo, certain: true)
        #expect(ProjectArtifacts.lastChange(of: [known]) == .at(monthsAgo))
        #expect(ProjectArtifacts.lastChange(of: [artifact("build", changed: monthsAgo, certain: false)]) == .notKnown)
        #expect(ProjectArtifacts.lastChange(of: [artifact("build", changed: yesterday, certain: false)]) == .recently)
        #expect(ProjectArtifacts.lastChange(of: [artifact("build", changed: nil, certain: true)]) == .none)
    }

    /// A folder ordinary permissions close is named as not read, never taken for one with nothing built in it, and
    /// Full Disk Access, which would not open it either, is not blamed.
    @Test(.permissionsHold) func saysWhichFoldersItCouldNotReadWithoutBlamingFullDiskAccess() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Code/app/package.json", bytes: 16)
        try directory.file("Work/open/package.json", bytes: 16)
        try directory.file("Work/closed/package.json", bytes: 16)
        try directory.setPermissions(0, of: "Code")
        try directory.setPermissions(0, of: "Work/closed")
        defer {
            try? directory.setPermissions(0o755, of: "Code")
            try? directory.setPermissions(0o755, of: "Work/closed")
        }
        let code = directory.url.appending(path: "Code", directoryHint: .isDirectory)
        let work = directory.url.appending(path: "Work", directoryHint: .isDirectory)

        let scan = await ProjectArtifacts.scan(roots: [code, work])

        #expect(scan.artifacts.isEmpty)
        #expect(scan.unreadableLocations.map(PathPattern.comparablePath) == [
            PathPattern.comparablePath(of: code), PathPattern.comparablePath(of: work.appending(path: "closed")),
        ])
        #expect(!scan.needsFullDiskAccess)
    }

    @Test func namesEveryChosenFolderItCouldNotSearch() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Code/app/package.json", bytes: 16)
        try directory.file("Code/app/node_modules/left-pad/index.js", bytes: 16)
        let code = directory.url.appending(path: "Code", directoryHint: .isDirectory)
        let unplugged = directory.url.appending(path: "Disk/Projects", directoryHint: .isDirectory)

        let scan = await ProjectArtifacts.scan(roots: [unplugged, code])

        #expect(scan.artifacts.map(\.name) == ["node_modules"])
        #expect(scan.refusedRoots.map(\.url) == [unplugged])
        #expect(scan.refusedRoots.map(\.reason) == [.notAFolder])
    }

    /// An editor keeps an installed extension's `package.json` beside its `node_modules`, where the walk never goes.
    @Test func refusesAFolderTheWalkNeverEnters() async throws {
        let directory = try TemporaryDirectory()
        let home = URL(filePath: "/Users/x", directoryHint: .isDirectory)
        try directory.file("Tool/.editor/extensions/org.example.sample-1.0.0/package.json")
        try directory.file("Tool/.editor/extensions/org.example.sample-1.0.0/node_modules/org-example-dep/index.js")
        let extensions = directory.url.appending(path: "Tool/.editor/extensions", directoryHint: .isDirectory)
        let installed = try directory.directory("Code/app/node_modules/org-example-dep")
        let library = try directory.directory("Work/Library/Application Support/Editor")
        let dotted = try directory.directory("Code/my.projects")
        let real = try directory.directory("Code/real")
        let linkInside = directory.url.appending(path: "Tool/.editor/real")
        try FileManager.default.createSymbolicLink(at: linkInside, withDestinationURL: real)
        let linkToExtensions = directory.url.appending(path: "Code/extensions")
        try FileManager.default.createSymbolicLink(at: linkToExtensions, withDestinationURL: extensions)

        #expect(ProjectArtifacts.refusal(for: extensions, home: home) == .neverSearched)
        #expect(ProjectArtifacts.refusal(for: installed, home: home) == .neverSearched)
        #expect(ProjectArtifacts.refusal(for: library, home: home) == .neverSearched)
        #expect(ProjectArtifacts.refusal(for: linkToExtensions, home: home) == .neverSearched)
        #expect(ProjectArtifacts.refusal(for: linkInside, home: home) == nil)
        #expect(ProjectArtifacts.refusal(for: dotted, home: home) == nil)

        let scan = await ProjectArtifacts.scan(roots: [extensions])
        #expect(scan.artifacts.isEmpty)
        #expect(scan.refusedRoots.map(\.reason) == [.neverSearched])
    }

    private struct Kind {
        let artifact: String
        let marker: String
        var markerIsAFolder = false
        let tool: String
        let isGeneric: Bool
        var isEnvironment = false
    }

    private func expectFound(_ kinds: [Kind]) async throws {
        for kind in kinds {
            let directory = try TemporaryDirectory()
            if kind.markerIsAFolder {
                try directory.directory("with/\(kind.marker)")
            } else {
                try directory.file("with/\(kind.marker)", bytes: 16)
            }
            try directory.file("with/README.md", bytes: 16)
            try directory.file("with/\(kind.artifact)/output.bin", bytes: 400_000)
            try directory.file("without/\(kind.artifact)/output.bin", bytes: 400_000)
            try age(directory.url, days: 60)

            let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts

            let projects = found.map(\.project.lastPathComponent)
            #expect(projects == ["with"], "\(kind.artifact) was found in \(projects)")
            let artifact = found.first { $0.name == kind.artifact }
            #expect(artifact?.tool == kind.tool, "\(kind.artifact)")
            #expect(artifact?.hasGenericName == kind.isGeneric, "\(kind.artifact)")
            #expect(artifact?.isEnvironment == kind.isEnvironment, "\(kind.artifact)")
            #expect(artifact?.isRecommended == (!kind.isGeneric && !kind.isEnvironment), "\(kind.artifact)")
        }
    }

    @Test func looksInsideAFolderWithAGenericNameThatNoToolMade() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Code/public/site/package.json", bytes: 16)
        try directory.file("Code/public/site/node_modules/left-pad/index.js", bytes: 400_000)
        try directory.file("Code/shop/next.config.js", bytes: 16)
        try directory.file("Code/shop/.next/cache/data", bytes: 400_000)
        try directory.file("Code/shop/public/logo.svg", bytes: 16)
        try age(directory.url, days: 60)
        try FileManager.default.setAttributes(
            [.modificationDate: Date.now],
            ofItemAtPath: directory.url.appending(path: "Code/shop/public/logo.svg").path(percentEncoded: false)
        )

        let found = await ProjectArtifacts.scan(roots: [directory.url.appending(path: "Code")]).artifacts

        #expect(found.map(\.project.lastPathComponent).sorted() == ["shop", "site"])
        let next = try #require(found.first { $0.name == ".next" })
        #expect(next.isRecentlyActive, "a change in the project's own public folder was not counted")
    }

    @Test func findsWhatJavaScriptToolsBuild() async throws {
        try await expectFound([
            Kind(artifact: ".nuxt", marker: "nuxt.config.ts", tool: "Nuxt", isGeneric: false),
            Kind(artifact: ".output", marker: "nuxt.config.mjs", tool: "Nuxt", isGeneric: false),
            Kind(artifact: ".svelte-kit", marker: "svelte.config.js", tool: "SvelteKit", isGeneric: false),
            Kind(artifact: ".angular", marker: "angular.json", tool: "Angular", isGeneric: false),
            Kind(artifact: ".turbo", marker: "turbo.json", tool: "Turborepo", isGeneric: false),
            Kind(artifact: ".parcel-cache", marker: "package.json", tool: "Parcel", isGeneric: false),
            Kind(
                artifact: "storybook-static", marker: ".storybook", markerIsAFolder: true, tool: "Storybook",
                isGeneric: false
            ),
            Kind(artifact: "dist", marker: "vite.config.ts", tool: "Vite", isGeneric: true),
            Kind(artifact: "out", marker: "next.config.js", tool: "Next.js", isGeneric: true),
            Kind(artifact: "coverage", marker: "vitest.config.mts", tool: "Vitest", isGeneric: true),
            Kind(artifact: ".cache", marker: "gatsby-config.ts", tool: "Gatsby", isGeneric: true),
            Kind(artifact: "public", marker: "gatsby-config.js", tool: "Gatsby", isGeneric: true),
        ])
    }

    @Test func findsWhatPythonToolsLeave() async throws {
        try await expectFound([
            Kind(artifact: ".pytest_cache", marker: "conftest.py", tool: "pytest", isGeneric: false),
            Kind(artifact: ".mypy_cache", marker: "mypy.ini", tool: "mypy", isGeneric: false),
            Kind(artifact: ".ruff_cache", marker: "ruff.toml", tool: "Ruff", isGeneric: false),
            Kind(artifact: "htmlcov", marker: ".coveragerc", tool: "Coverage.py", isGeneric: false),
            Kind(artifact: ".tox", marker: "tox.ini", tool: "tox", isGeneric: false, isEnvironment: true),
            Kind(artifact: ".nox", marker: "noxfile.py", tool: "Nox", isGeneric: false, isEnvironment: true),
            Kind(artifact: "dist", marker: "pyproject.toml", tool: "Python", isGeneric: true),
        ])
    }

    @Test func findsWhatGameEnginesAndDotNetBuild() async throws {
        let unity = "ProjectSettings/ProjectVersion.txt"
        try await expectFound([
            Kind(artifact: "Library", marker: unity, tool: "Unity", isGeneric: true),
            Kind(artifact: "Temp", marker: unity, tool: "Unity", isGeneric: true),
            Kind(artifact: "Logs", marker: unity, tool: "Unity", isGeneric: true),
            Kind(artifact: "obj", marker: unity, tool: "Unity", isGeneric: true),
            Kind(artifact: "Binaries", marker: "Game.uproject", tool: "Unreal Engine", isGeneric: true),
            Kind(artifact: "Intermediate", marker: "Game.uproject", tool: "Unreal Engine", isGeneric: true),
            Kind(artifact: "DerivedDataCache", marker: "Game.uproject", tool: "Unreal Engine", isGeneric: false),
            Kind(artifact: ".godot/imported", marker: "project.godot", tool: "Godot", isGeneric: false),
            Kind(artifact: ".godot/shader_cache", marker: "project.godot", tool: "Godot", isGeneric: false),
            Kind(artifact: ".import", marker: "project.godot", tool: "Godot", isGeneric: false),
            Kind(artifact: "bin", marker: "App.csproj", tool: ".NET", isGeneric: true),
            Kind(artifact: "obj", marker: "Library.fsproj", tool: ".NET", isGeneric: true),
        ])
    }

    @Test func findsWhatOtherBuildToolsLeave() async throws {
        try await expectFound([
            Kind(artifact: "build", marker: "CMakeLists.txt", tool: "CMake", isGeneric: true),
            Kind(artifact: "build", marker: "App.xcodeproj", markerIsAFolder: true, tool: "Xcode", isGeneric: true),
            Kind(artifact: "zig-out", marker: "build.zig", tool: "Zig", isGeneric: false),
            Kind(artifact: ".zig-cache", marker: "build.zig", tool: "Zig", isGeneric: false),
            Kind(artifact: "zig-cache", marker: "build.zig", tool: "Zig", isGeneric: false),
            Kind(artifact: ".cxx", marker: "build.gradle.kts", tool: "Android Gradle plugin", isGeneric: false),
            Kind(artifact: ".stack-work", marker: "stack.yaml", tool: "Stack", isGeneric: false),
            Kind(artifact: "dist-newstyle", marker: "app.cabal", tool: "Cabal", isGeneric: false),
            Kind(artifact: "_build", marker: "mix.exs", tool: "Mix", isGeneric: true),
            Kind(artifact: "deps", marker: "mix.exs", tool: "Mix", isGeneric: true, isEnvironment: true),
            Kind(artifact: ".elixir_ls", marker: "mix.exs", tool: "ElixirLS", isGeneric: false),
            Kind(artifact: "lib", marker: "shard.lock", tool: "Shards", isGeneric: true, isEnvironment: true),
            Kind(artifact: "vendor", marker: "composer.json", tool: "Composer", isGeneric: true, isEnvironment: true),
            Kind(artifact: ".terragrunt-cache", marker: "terragrunt.hcl", tool: "Terragrunt", isGeneric: false),
        ])
    }

    @Test func findsEveryBuildFolderCLionNamesForItsProfiles() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("engine/CMakeLists.txt", bytes: 16)
        try directory.file("engine/src/main.c", bytes: 16)
        try directory.file("engine/cmake-build-debug/engine", bytes: 400_000)
        try directory.file("engine/cmake-build-release-arm64/engine", bytes: 400_000)
        try directory.file("notes/cmake-build-debug/engine", bytes: 400_000)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts

        #expect(Set(found.map { "\($0.project.lastPathComponent)/\($0.name)" }) == [
            "engine/cmake-build-debug", "engine/cmake-build-release-arm64",
        ])
        #expect(found.allSatisfy { $0.tool == "CLion" && $0.isRecommended })
    }

    @Test func findsWhatSbtBuildsBesideItsBuildFileAndInItsProjectFolder() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("service/build.sbt", bytes: 16)
        try directory.file("service/src/main/scala/Main.scala", bytes: 16)
        try directory.file("service/target/scala-3.7.3/classes/Main.class", bytes: 400_000)
        try directory.file("service/project/build.properties", bytes: 16)
        try directory.file("service/project/target/config-classes/Build.class", bytes: 400_000)
        try directory.file("notes/target/report.txt", bytes: 400_000)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts

        #expect(Set(found.map { "\($0.project.lastPathComponent)/\($0.name)" }) == [
            "service/target", "service/project/target",
        ])
        #expect(found.allSatisfy { $0.tool == "sbt" })
    }

    @Test func offersGodotsCachesAndNeverItsExportCredentials() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("game/project.godot", bytes: 16)
        try directory.file("game/.godot/imported/icon.svg-org-example.ctex", bytes: 400_000)
        try directory.file("game/.godot/shader_cache/CanvasShaderRD/org-example.cache", bytes: 400_000)
        try directory.file("game/.godot/editor/filesystem_cache10", bytes: 16)
        try directory.file("game/.godot/export_credentials.cfg", bytes: 16)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts

        #expect(Set(found.map(\.name)) == [".godot/imported", ".godot/shader_cache"])
        #expect(found.allSatisfy { $0.isRecommended })
    }

    @Test func findsRailsCacheInsideItsTemporaryFolderAndOnlyThere() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("shop/config/application.rb", bytes: 16)
        try directory.file("shop/app/models/order.rb", bytes: 16)
        try directory.file("shop/tmp/cache/bootsnap/load-path", bytes: 400_000)
        try directory.file("shop/tmp/pids/server.pid", bytes: 16)
        try age(directory.url, days: 60)
        try FileManager.default.setAttributes(
            [.modificationDate: Date.now],
            ofItemAtPath: directory.url.appending(path: "shop/tmp/cache/bootsnap/load-path").path(percentEncoded: false)
        )

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts

        #expect(found.map { "\($0.project.lastPathComponent)/\($0.name)" } == ["shop/tmp/cache"])
        #expect(found.first?.tool == "Rails")
        #expect(found.first?.isRecommended == true, "the cache's own new files counted as work in the project")
    }

    @Test func findsAFolderItsToolTaggedAsACacheWhateverItIsCalled() async throws {
        let directory = try TemporaryDirectory()
        let tag = Data("Signature: 8a477f597d28d172789f06886806bc55\n# This file is a cache directory tag.\n".utf8)
        try directory.file("app/main.c", bytes: 16)
        try directory.file("app/scratch-cache/CACHEDIR.TAG", contents: tag)
        try directory.file("app/scratch-cache/objects/blob", bytes: 400_000)
        try directory.file("app/look-alike/CACHEDIR.TAG", contents: Data("not a tag".utf8))
        try directory.file("app/look-alike/notes.txt", bytes: 400_000)
        try directory.file("crate/Cargo.toml", bytes: 16)
        try directory.file("crate/target/CACHEDIR.TAG", contents: tag)
        try directory.file("crate/target/debug/crate", bytes: 400_000)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts

        #expect(Set(found.map { "\($0.project.lastPathComponent)/\($0.name)" }) == ["app/scratch-cache", "crate/target"])
        let tagged = try #require(found.first { $0.name == "scratch-cache" })
        #expect(tagged.tool == nil)
        #expect(tagged.isRecommended)
        #expect(found.first { $0.name == "target" }?.tool == "Cargo")
    }

    @Test func aUnityProjectsObjIsUnitysThoughDotNetsProjectFileSitsBesideIt() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("game/ProjectSettings/ProjectVersion.txt", bytes: 16)
        try directory.file("game/Assembly-CSharp.csproj", bytes: 16)
        try directory.file("game/obj/Debug/Assembly-CSharp.dll", bytes: 400_000)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts

        #expect(found.map(\.tool) == ["Unity"])
    }

    @Test func findsPythonsCompiledFilesOnlyWhereThatIsAllThereIs() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("tool/app.py", bytes: 16)
        try directory.file("tool/__pycache__/app.cpython-313.pyc", bytes: 400_000)
        try directory.file("notes/__pycache__/app.cpython-313.pyc", bytes: 400_000)
        try directory.file("notes/__pycache__/draft.txt", bytes: 16)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts

        #expect(found.map { "\($0.project.lastPathComponent)/\($0.name)" } == ["tool/__pycache__"])
        #expect(found.first?.tool == "Python")
        #expect(found.first?.isRecommended == true)
    }

    @Test func listsWhatEleventyFetchKeepsAndNeverSelectsItsGenericName() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("blog/eleventy.config.mjs", bytes: 16)
        try directory.file("blog/.cache/eleventy-fetch-0123abc", bytes: 400_000)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts

        #expect(found.map(\.name) == [".cache"])
        #expect(found.first?.tool == "Eleventy Fetch")
        #expect(found.first?.hasGenericName == true && found.first?.isRecommended == false)
    }

    @Test func offersTheIncrementalBuildRollupsTypeScriptPluginKeeps() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("lib/package.json", bytes: 16)
        try directory.file("lib/.rollup.cache/Users/me/lib/dist/index.js", bytes: 400_000)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts

        #expect(found.map(\.name) == [".rollup.cache"])
        #expect(found.first?.tool == "@rollup/plugin-typescript")
        #expect(found.first?.isRecommended == true)
    }

    @Test func offersTheCacheOlderTypeScriptBuildsForRollupKept() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("lib/package.json", bytes: 16)
        try directory.file("lib/.rpt2_cache/rpt2_9a7c/code/cache/0a1b", bytes: 400_000)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts

        #expect(found.map(\.name) == [".rpt2_cache"])
        #expect(found.first?.tool == "rollup-plugin-typescript2")
        #expect(found.first?.isRecommended == true)
    }

    @Test func offersWhatAnInterruptedViteSSGBuildLeft() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("site/package.json", bytes: 16)
        try directory.file("site/.vite-ssg-temp/3k2l1j0h9g/main.mjs", bytes: 400_000)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts

        #expect(found.map(\.name) == [".vite-ssg-temp"])
        #expect(found.first?.tool == "Vite SSG")
        #expect(found.first?.isRecommended == true)
    }

    @Test func offersTheBuildsSolidStartMakes() async throws {
        let directory = try TemporaryDirectory()
        for app in ["old", "new"] {
            try directory.file("\(app)/package.json", bytes: 16)
        }
        try directory.file("old/.solid/server/server.js", bytes: 400_000)
        try directory.file("new/.solid-start/client/.vite/manifest.json", bytes: 400_000)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts

        #expect(found.map { "\($0.project.lastPathComponent)/\($0.name)" }.sorted() == ["new/.solid-start", "old/.solid"])
        #expect(found.allSatisfy { $0.tool == "SolidStart" && $0.isRecommended })
    }

    @Test func offersTheCacheSWCKeepsForItsPlugins() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("web/.swcrc", bytes: 16)
        try directory.file("web/.swc/plugins/v7_macos_aarch64_0.106.0/plugin.wasm", bytes: 400_000)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts

        #expect(found.map(\.name) == [".swc"])
        #expect(found.first?.tool == "SWC")
        #expect(found.first?.isRecommended == true)
    }

    @Test func offersWhatPantsSaysIsSafeToDeleteInARepository() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("repo/pants.toml", bytes: 16)
        try directory.file("repo/.pants.d/workdir/pantsd/pantsd.log", bytes: 400_000)
        try directory.file("repo/dist/app.pex", bytes: 400_000)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts

        #expect(found.map(\.name).sorted() == [".pants.d", "dist"])
        #expect(found.allSatisfy { $0.tool == "Pants" })
        #expect(found.filter(\.isRecommended).map(\.name) == [".pants.d"])
    }

    @Test func offersWhatElixirsLanguageServersKeepInAProject() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("api/mix.exs", bytes: 16)
        try directory.file("api/.elixir-tools/_build/dev/lib/api/ebin/api.beam", bytes: 400_000)
        try directory.file("api/.elixir-tools/nextls.db", bytes: 400_000)
        try directory.file("api/.lexical/build/dev/lib/api/ebin/api.beam", bytes: 400_000)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts

        #expect(found.map { "\($0.name) \($0.tool ?? "")" }.sorted() == [".elixir-tools Next LS", ".lexical Lexical"])
        #expect(found.allSatisfy { $0.isRecommended })
    }

    @Test func offersTheBundlesTheShopifyCLIBuildsAndNeverItsCertificates() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("store/shopify.app.toml", bytes: 16)
        try directory.file("store/.shopify/deploy-bundle/manifest.json", bytes: 400_000)
        try directory.file("store/.shopify/dev-bundle/extension/dist/main.js", bytes: 400_000)
        try directory.file("store/.shopify/localhost-key.pem", bytes: 16)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts

        #expect(found.map(\.name).sorted() == [".shopify/deploy-bundle", ".shopify/dev-bundle"])
        #expect(found.allSatisfy { $0.tool == "Shopify CLI" && $0.isRecommended })
    }

    @Test func listsWhatRemixAndReactRouterBuildWithoutSelectingIt() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("classic/remix.config.js", bytes: 16)
        try directory.file("classic/.cache/browser-build/meta.json", bytes: 400_000)
        try directory.file("classic/public/build/entry.client.js", bytes: 400_000)
        try directory.file("classic/build/index.js", bytes: 400_000)
        try directory.file("framework/react-router.config.ts", bytes: 16)
        try directory.file("framework/build/server/index.js", bytes: 400_000)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts

        #expect(found.map { "\($0.project.lastPathComponent)/\($0.name)/\($0.tool ?? "")" }.sorted() == [
            "classic/.cache/Remix", "classic/build/Remix", "classic/public/build/Remix", "framework/build/React Router",
        ])
        #expect(found.allSatisfy { $0.hasGenericName && !$0.isRecommended })
    }

    @Test func offersTheTypesReactRouterGenerates() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("web/package.json", bytes: 16)
        try directory.file("web/.react-router/types/app/+types/root.d.ts", bytes: 400_000)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts

        #expect(found.map(\.name) == [".react-router"])
        #expect(found.first?.tool == "React Router")
        #expect(found.first?.isRecommended == true)
    }

    @Test func offersThePackageTheServerlessFrameworkBuilds() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("api/serverless.ts", bytes: 16)
        try directory.file("api/.serverless/api.zip", bytes: 400_000)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts

        #expect(found.map(\.name) == [".serverless"])
        #expect(found.first?.tool == "Serverless Framework")
        #expect(found.first?.isRecommended == true)
    }

    @Test func offersTheEnvironmentsPixiMakesAgainAndNeverItsSettings() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("science/pixi.toml", bytes: 16)
        try directory.file("science/.pixi/envs/default/conda-meta/pixi", bytes: 400_000)
        try directory.file("science/.pixi/config.toml", bytes: 16)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts

        #expect(found.map(\.name) == [".pixi/envs"])
        #expect(found.first?.tool == "Pixi")
        #expect(found.first?.isRecommended == true)
    }

    @Test func offersTheClasspathCacheTheClojureCLIKeepsInAProject() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("app/deps.edn", bytes: 16)
        try directory.file("app/.cpcache/1234567890.cp", bytes: 400_000)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts

        #expect(found.map(\.name) == [".cpcache"])
        #expect(found.first?.tool == "Clojure CLI")
        #expect(found.first?.isRecommended == true)
    }

    @Test func offersTheCacheAutoconfsToolsShare() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("lib/configure.ac", bytes: 16)
        try directory.file("lib/autom4te.cache/output.0", bytes: 400_000)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts

        #expect(found.map(\.name) == ["autom4te.cache"])
        #expect(found.first?.tool == "Autoconf")
        #expect(found.first?.isRecommended == true)
    }

    @Test func offersTheRawCoverageNycWrites() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("app/.nycrc.json", bytes: 16)
        try directory.file("app/.nyc_output/processinfo/index.json", bytes: 400_000)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts

        #expect(found.map(\.name) == [".nyc_output"])
        #expect(found.first?.tool == "nyc")
        #expect(found.first?.isRecommended == true)
    }

    @Test func offersWhatDocusaurusClearRemoves() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("site/docusaurus.config.mjs", bytes: 16)
        try directory.file("site/.docusaurus/client-modules.js", bytes: 400_000)
        try directory.file("site/build/index.html", bytes: 400_000)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts

        #expect(found.map(\.name).sorted() == [".docusaurus", "build"])
        #expect(found.allSatisfy { $0.tool == "Docusaurus" })
        #expect(found.filter(\.isRecommended).map(\.name) == [".docusaurus"])
    }

    @Test func offersNxsFolderOnlyWhenItHoldsWhatNxResetRemoves() async throws {
        let directory = try TemporaryDirectory()
        for project in ["reset", "plans", "cacheOnly"] {
            try directory.file("\(project)/nx.json", bytes: 16)
            try directory.file("\(project)/.nx/cache/0123/outputs/main.js", bytes: 400_000)
        }
        try directory.file("reset/.nx/workspace-data/nx.db", bytes: 400_000)
        try directory.file("plans/.nx/workspace-data/nx.db", bytes: 400_000)
        try directory.file("plans/.nx/version-plans/release.md", bytes: 16)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts

        #expect(found.map { "\($0.project.lastPathComponent)/\($0.name)" } == ["reset/.nx"])
        #expect(found.first?.tool == "Nx")
        #expect(found.first?.isRecommended == true)
    }

    @Test func findsAVirtualEnvironmentUnderAGenericNameOnlyByItsOwnFile() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("app/pyproject.toml", bytes: 16)
        try directory.file("app/env/pyvenv.cfg", bytes: 16)
        try directory.file("app/env/lib/site.py", bytes: 400_000)
        try directory.file("other/pyproject.toml", bytes: 16)
        try directory.file("other/env/production.env", bytes: 400_000)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts

        #expect(found.map(\.project.lastPathComponent) == ["app"])
        let environment = try #require(found.first)
        #expect(environment.isEnvironment && environment.hasGenericName && !environment.isRecommended)
    }

    private func age(_ url: URL, days: Int) throws {
        let date = Date.now.addingTimeInterval(-Double(days) * 24 * 60 * 60)
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else { return }
        for case let item as URL in enumerator {
            try FileManager.default.setAttributes(
                [.modificationDate: date],
                ofItemAtPath: item.path(percentEncoded: false)
            )
        }
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path(percentEncoded: false))
    }

    /// A `node_modules` folder with no `package.json` beside it is the user's own folder, not an artifact.
    @Test func findsAnArtifactOnlyBesideTheFileThatMakesIt() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Projects/site/package.json", bytes: 16)
        try directory.file("Projects/site/node_modules/left-pad/index.js", bytes: 400_000)
        try directory.file("Projects/notes/node_modules/photos/holiday.jpg", bytes: 400_000)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url.appending(path: "Projects")]).artifacts

        #expect(found.map(\.project.lastPathComponent) == ["site"])
        #expect(found.first?.name == "node_modules")
        #expect(found.first?.tool == "npm")
        #expect(try #require(found.first?.size) >= 400_000)
        #expect(found.first?.isRecommended == true)
    }

    @Test func carthageOffersItsBuildAndNeverItsCheckouts() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Projects/app/Cartfile", bytes: 16)
        try directory.file("Projects/app/Carthage/Build/Dep.xcframework/Info.plist", bytes: 16)
        try directory.file("Projects/app/Carthage/Checkouts/Dep/Sources/Dep.swift", bytes: 16)
        try directory.file("Projects/kit/Cartfile", bytes: 16)
        try directory.file("Projects/kit/Carthage/Checkouts/Dep/.git", bytes: 16)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url.appending(path: "Projects")]).artifacts

        #expect(found.map { "\($0.project.lastPathComponent)/\($0.name)" } == ["app/Carthage/Build"])
        #expect(found.first?.isRecommended == true)
    }

    /// What may exist nowhere else is never selected: a repository, or a wallet. A repository inside a folder its
    /// tool tags as a cache is the tool's own clone, which it makes again, as Swift Package Manager does for `.build`;
    /// a key is never made again, so Cargo's tag on `target` does not cover a Solana program's key inside it.
    @Test func anArtifactHoldingARepositoryOrAWalletIsNotSelected() async throws {
        let directory = try TemporaryDirectory()
        let tag = Data("Signature: 8a477f597d28d172789f06886806bc55\n# a cache directory tag\n".utf8)
        try directory.file("Projects/site/package.json", bytes: 16)
        try directory.file("Projects/site/node_modules/coin/wallet.dat", bytes: 16)
        try directory.file("Projects/tool/Package.swift", bytes: 16)
        try directory.file("Projects/tool/.build/CACHEDIR.TAG", contents: tag)
        try directory.file("Projects/tool/.build/checkouts/dep/.git/HEAD", bytes: 16)
        try directory.file("Projects/old/Package.swift", bytes: 16)
        try directory.file("Projects/old/.build/CACHEDIR.TAG", contents: Data("not a tag".utf8))
        try directory.file("Projects/old/.build/checkouts/dep/.git/HEAD", bytes: 16)
        try directory.file("Projects/program/Cargo.toml", bytes: 16)
        try directory.file("Projects/program/target/CACHEDIR.TAG", contents: tag)
        try directory.file("Projects/program/target/deploy/vault-keypair.json", bytes: 16)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url.appending(path: "Projects")]).artifacts

        let reasons = found.map { "\($0.project.lastPathComponent): \($0.heldBack.map(\.rawValue) ?? "none")" }.sorted()
        #expect(reasons == ["old: holdsRepository", "program: holdsAWallet", "site: holdsAWallet", "tool: none"])
        #expect(found.filter(\.isRecommended).map(\.project.lastPathComponent) == ["tool"])
    }

    @Test func aFolderGitTracksIsListedAndNeverSelected() async throws {
        let directory = try TemporaryDirectory()
        let git = try await GitFixture(home: directory.url.appending(path: "home"))
        for name in ["Tracked", "Ignored"] {
            try directory.file("Code/\(name)/Podfile")
            try directory.file("Code/\(name)/Pods/Foo/Foo.m")
            try directory.file("Code/\(name)/src/App.swift")
        }
        try directory.file("Code/Ignored/.gitignore", contents: Data("Pods/\n".utf8))
        for name in ["Tracked", "Ignored"] {
            let project = directory.url.appending(path: "Code/\(name)", directoryHint: .isDirectory)
            try await git.run("init", "-q", in: project)
            try await git.run("add", "-A", in: project)
        }
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url.appending(path: "Code")]).artifacts

        let reasons = found.map { "\($0.project.lastPathComponent): \($0.heldBack.map(\.rawValue) ?? "none")" }.sorted()
        #expect(reasons == ["Ignored: none", "Tracked: trackedByGit"])
        #expect(found.filter(\.isRecommended).map(\.project.lastPathComponent) == ["Ignored"])
    }

    @Test(.permissionsHold) func whatGitTracksIsNotKnownWhileItsIndexCannotBeRead() async throws {
        let directory = try TemporaryDirectory()
        let git = try await GitFixture(home: directory.url.appending(path: "home"))
        try directory.file("Code/App/Podfile")
        try directory.file("Code/App/Pods/Foo/Foo.m")
        let project = directory.url.appending(path: "Code/App", directoryHint: .isDirectory)
        try await git.run("init", "-q", in: project)
        try await git.run("add", "Podfile", in: project)
        try age(directory.url, days: 60)
        let index = project.appending(path: ".git/index")
        try directory.setPermissions(0, of: index)
        defer { try? directory.setPermissions(0o644, of: index) }

        let found = await ProjectArtifacts.scan(roots: [directory.url.appending(path: "Code")]).artifacts

        let pods = try #require(found.first)
        #expect(pods.heldBack == .gitTrackingNotKnown)
        #expect(!pods.isRecommended)
    }

    /// A large `node_modules` is the folder most likely to run out of time. Its size is then unknown, not zero,
    /// so it is listed first and never selected for the user.
    @Test func anArtifactThatDidNotAnswerInTimeIsNotReadAsEmpty() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Projects/site/package.json", bytes: 16)
        try directory.file("Projects/site/node_modules/left-pad/index.js", bytes: 400_000)
        try directory.file("Projects/tool/Package.swift", bytes: 16)
        try directory.file("Projects/tool/.build/debug/tool", bytes: 800_000)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url.appending(path: "Projects")], exclusions: .none) { url in
            url.lastPathComponent == "node_modules" ? nil : await FileSize.contents(of: url)
        }.artifacts

        #expect(found.map(\.name) == ["node_modules", ".build"])
        #expect(found.first?.size == nil)
        #expect(found.first?.isRecommended == false, "what Peel could not measure is never selected for the user")
        #expect(found.last?.isRecommended == true)
        #expect(try #require(found.last?.size) >= 800_000)
    }

    @Test func showsGenericNamesButNeverSelectsThem() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("rust/Cargo.toml", bytes: 16)
        try directory.file("rust/target/debug/app", bytes: 400_000)
        try directory.file("swift/Package.swift", bytes: 16)
        try directory.file("swift/.build/debug/app", bytes: 400_000)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts
        let target = try #require(found.first { $0.name == "target" })
        let build = try #require(found.first { $0.name == ".build" })

        #expect(target.hasGenericName)
        #expect(!target.isRecommended)
        #expect(!build.hasGenericName)
        #expect(build.isRecommended)
    }

    @Test func leavesProjectsAloneWhileSomeoneIsWorkingInThem() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("live/package.json", bytes: 16)
        try directory.file("live/node_modules/dep/index.js", bytes: 400_000)
        try directory.file("old/package.json", bytes: 16)
        try directory.file("old/node_modules/dep/index.js", bytes: 400_000)
        try age(directory.url, days: 60)
        try directory.file("live/src/main.js", bytes: 16)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts
        let live = try #require(found.first { $0.project.lastPathComponent == "live" })
        let old = try #require(found.first { $0.project.lastPathComponent == "old" })

        #expect(live.isRecentlyActive)
        #expect(!live.isRecommended)
        #expect(!old.isRecentlyActive)
        #expect(old.isRecommended)
    }

    /// Walking into `node_modules` would find thousands of nested copies and make the scan very slow.
    @Test func neverWalksIntoAnArtifactItAlreadyFound() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("app/package.json", bytes: 16)
        try directory.file("app/node_modules/dep/package.json", bytes: 16)
        try directory.file("app/node_modules/dep/node_modules/inner/index.js", bytes: 400_000)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts
        #expect(found.count == 1)
        #expect(found.first?.url.path(percentEncoded: false).hasSuffix("/app/node_modules") == true)
    }

    @Test func honorsExclusions() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("app/package.json", bytes: 16)
        let modules = try directory.directory("app/node_modules")
        try directory.file("app/node_modules/dep/index.js", bytes: 400_000)
        try age(directory.url, days: 60)

        #expect(
            await ProjectArtifacts.scan(roots: [directory.url], exclusions: Exclusions(paths: [modules]))
                .artifacts.isEmpty
        )
        #expect(await ProjectArtifacts.scan(roots: [directory.url]).artifacts.count == 1)
    }

    /// A hidden folder is a tool's own store. `~/.npm` alone can hold thousands of `node_modules`, and those
    /// belong to the Developer page.
    @Test func neverLooksInsideAHiddenFolder() async throws {
        let directory = try TemporaryDirectory()
        try directory.file(".npm/_npx/abc/package.json", bytes: 16)
        try directory.file(".npm/_npx/abc/node_modules/dep/index.js", bytes: 400_000)
        try directory.file("work/app/package.json", bytes: 16)
        try directory.file("work/app/node_modules/dep/index.js", bytes: 400_000)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts
        #expect(found.map(\.project.lastPathComponent) == ["app"])
    }

    /// A virtual environment holds installed packages, not build output, so it is never selected for the user.
    @Test func showsVirtualEnvironmentsButNeverSelectsThem() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("py/pyproject.toml", bytes: 16)
        try directory.file("py/.venv/lib/python/site.py", bytes: 400_000)
        try age(directory.url, days: 60)

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts
        let venv = try #require(found.first)
        #expect(venv.isEnvironment)
        #expect(!venv.hasGenericName)
        #expect(!venv.isRecommended)
    }

    /// `.terraform` keeps the selected workspace and the last backend configuration, which `terraform init`
    /// does not bring back.
    @Test func showsTerraformsFolderButNeverSelectsIt() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("infra/main.tf", bytes: 16)
        try directory.file("infra/.terraform/providers/registry/plugin", bytes: 400_000)
        try age(directory.url, days: 60)

        let found = try #require(await ProjectArtifacts.scan(roots: [directory.url]).artifacts.first)

        #expect(found.name == ".terraform")
        #expect(found.isEnvironment)
        #expect(!found.isRecommended)
    }

    /// Without a reason, the page would say "Nothing Built Here" about a folder it never searched.
    @Test func saysWhyAFolderCannotBeSearched() throws {
        let directory = try TemporaryDirectory()
        let home = URL(filePath: "/Users/x", directoryHint: .isDirectory)

        #expect(ProjectArtifacts.refusal(for: home, home: home) == .tooBroad)
        #expect(ProjectArtifacts.refusal(for: URL(filePath: "/Volumes/Disk"), home: home) == .tooBroad)
        #expect(ProjectArtifacts.refusal(for: home.appending(path: "Library/Mobile Documents/com~apple~CloudDocs/Code"), home: home) == .inTheCloud)
        #expect(ProjectArtifacts.refusal(for: directory.url.appending(path: "nothing-here"), home: home) == .notAFolder)
        #expect(ProjectArtifacts.refusal(for: try directory.directory("Code"), home: home) == nil)

        // The same folders under other spellings that macOS also accepts.
        #expect(ProjectArtifacts.refusal(for: URL(filePath: "/users/x"), home: home) == .tooBroad)
        #expect(ProjectArtifacts.refusal(for: URL(filePath: "/System/Volumes/Data/Users/x"), home: home) == .tooBroad)
        #expect(ProjectArtifacts.refusal(for: URL(filePath: "/System/Volumes/Data"), home: home) == .tooBroad)
        #expect(ProjectArtifacts.refusal(for: home.appending(path: "Library/CLOUDSTORAGE/Dropbox"), home: home) == .inTheCloud)
    }

    /// A cloud folder is known by its place, never by a name that only begins like one. What is inside an app or
    /// another package belongs to it, as an Electron app keeps `package.json` beside `node_modules` in its bundle.
    @Test func refusesACloudFolderByItsPlaceAndAPackageByWhatItIs() throws {
        let directory = try TemporaryDirectory()
        let home = URL(filePath: "/Users/x", directoryHint: .isDirectory)
        let kit = try directory.directory("Code/Library/CloudStorageKit")
        try directory.file("Sample.app/Contents/Resources/app/package.json")
        let app = directory.url.appending(path: "Sample.app", directoryHint: .isDirectory)

        #expect(ProjectArtifacts.refusal(for: kit, home: home) == .neverSearched)
        #expect(ProjectArtifacts.refusal(for: app, home: home) == .inAPackage)
        #expect(ProjectArtifacts.refusal(for: app.appending(path: "Contents/Resources/app"), home: home) == .inAPackage)
    }

    @Test func refusesRootsThatAreTooBroadOrNotOurs() {
        #expect(ProjectArtifacts.refusal(for: URL(filePath: "/")) == .tooBroad)
        #expect(ProjectArtifacts.refusal(for: URL(filePath: "/Users")) == .tooBroad)
        #expect(ProjectArtifacts.refusal(for: URL(filePath: "/Users/x/Library/Mobile Documents/com~apple~Pages")) == .inTheCloud)
        #expect(ProjectArtifacts.refusal(for: URL(filePath: "/Users/x/Library/CloudStorage/Dropbox")) == .inTheCloud)
        #expect(ProjectArtifacts.refusal(for: URL(filePath: "/Users/x/does-not-exist")) == .notAFolder)
    }

    @Test func findsEveryKindItKnowsInAProjectOfItsOwn() async throws {
        let directory = try TemporaryDirectory()
        var expected: [String: String] = [:]
        for (index, definition) in ProjectArtifacts.definitions.enumerated() {
            let project = "project-\(index)"
            if let marker = definition.markers.first {
                try directory.file("\(project)/\(marker.hasPrefix("*") ? "App" + marker.dropFirst() : marker)")
            }
            let name = definition.name.hasSuffix("*") ? definition.name.dropLast() + "debug" : definition.name
            let artifact = "\(project)/\(name)"
            switch definition.proof {
            case .holds(let file): try directory.file("\(artifact)/\(file)")
            case .holdsOnlyFilesEnding(let ending): try directory.file("\(artifact)/module\(ending)")
            case .holdsOnly(_, let including): try directory.file("\(artifact)/\(including)/content")
            case nil: try directory.file("\(artifact)/content")
            }
            expected[artifact] = definition.tool
        }

        let scan = await ProjectArtifacts.scan(roots: [directory.url], exclusions: .none)

        let inside = directory.url.lastPathComponent + "/"
        let found = Dictionary(
            scan.artifacts.map { artifact in
                (artifact.url.path(percentEncoded: false).components(separatedBy: inside).last ?? "", artifact.tool ?? "")
            },
            uniquingKeysWith: { first, _ in first }
        )
        let missed = expected.filter { found[$0.key] != $0.value }.map { "\($0.key) (\($0.value)): \(found[$0.key] ?? "not found")" }
        #expect(missed.isEmpty, "\(missed.sorted().joined(separator: "\n"))")
    }

    @Test func everyDefinitionNamesAMarkerAToolAndItsSource() {
        for definition in ProjectArtifacts.definitions {
            #expect(!definition.name.isEmpty)
            #expect(!definition.markers.isEmpty || definition.proof != nil, "\(definition.name) has no proof")
            #expect(!definition.tool.isEmpty)
            #expect(definition.name.split(separator: "/").count <= 2, "\(definition.name) goes deeper than one folder")
            let isAPage = definition.source.hasPrefix("https://") && URL(string: definition.source)?.host() != nil
            #expect(isAPage || definition.source.hasPrefix("Xcode 27: "), "\(definition.name) names \(definition.source)")
        }
    }

    /// `/Users/someone` and `/Volumes/Disk` have two path components each, like a real project root, so
    /// counting components alone cannot refuse them.
    @Test func refusesAHomeFolderAndAVolumeRoot() throws {
        let directory = try TemporaryDirectory()
        let home = try directory.directory("Users/someone")
        try directory.directory("Users/someone/Projects")

        #expect(ProjectArtifacts.refusal(for: URL(filePath: "/Users/someone"), home: home) == .tooBroad)
        #expect(ProjectArtifacts.refusal(for: URL(filePath: "/Volumes/Disk"), home: home) == .tooBroad)
        #expect(ProjectArtifacts.refusal(for: home, home: home) == .tooBroad)
        #expect(ProjectArtifacts.refusal(for: home.appending(path: "Projects"), home: home) == nil)
    }

    /// An Electron app ships `package.json` beside `node_modules` inside its own bundle. That matches the marker
    /// rule, but nothing inside an app may be removed.
    @Test func neverLooksInsideAnAppBundle() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Tools/Editor.app/Contents/Resources/app/package.json")
        try directory.file("Tools/Editor.app/Contents/Resources/app/node_modules/left-pad/index.js", bytes: 1_000)

        let found = await ProjectArtifacts.scan(roots: [
            directory.url.appending(path: "Tools", directoryHint: .isDirectory)
        ]).artifacts

        #expect(found.isEmpty, "part of an installed app was offered")
    }

    /// A project too big to read to the end says nothing about when it was last worked on, and what is not
    /// known is never selected for the user.
    @Test func doesNotSelectAProjectItCouldNotReadToTheEnd() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Project/package.json")
        try directory.file("Project/node_modules/left-pad/index.js", bytes: 1_000)
        for index in 0..<(ProjectArtifacts.maximumActivitySamples + 10) {
            try directory.file("Project/src/file\(index).txt", bytes: 1)
        }
        let old = Date(timeIntervalSinceNow: -60 * 24 * 60 * 60)
        var aged = ["Project", "Project/src", "Project/package.json"]
        aged += (0..<(ProjectArtifacts.maximumActivitySamples + 10)).map { "Project/src/file\($0).txt" }
        for path in aged.reversed() {
            try FileManager.default.setAttributes(
                [.modificationDate: old],
                ofItemAtPath: directory.url.appending(path: path).path(percentEncoded: false)
            )
        }

        let artifact = try #require(await ProjectArtifacts.scan(roots: [directory.url]).artifacts.first)

        #expect(!artifact.lastActivityIsCertain)
        #expect(!artifact.isRecommended)
    }

    /// Work in a hidden file, in `.github`, or in a folder of the person's own that a tool's table also names is
    /// work: only the artifacts found and what installed packages bring along are passed by.
    @Test func countsWorkInHiddenFilesAndFoldersNamedLikeArtifacts() async throws {
        let directory = try TemporaryDirectory()
        for project in ["dotenv", "workflow", "notes", "packages"] {
            try directory.file("\(project)/package.json", bytes: 16)
            try directory.file("\(project)/node_modules/dep/index.js", bytes: 400_000)
        }
        try directory.file("dotenv/.env", bytes: 16)
        try directory.file("workflow/.github/workflows/ci.yml", bytes: 16)
        try directory.file("notes/Carthage/notes.md", bytes: 16)
        try directory.file("packages/tools/node_modules/other/index.js", bytes: 16)
        try age(directory.url, days: 60)
        for recent in ["dotenv/.env", "workflow/.github/workflows/ci.yml", "notes/Carthage/notes.md",
                       "packages/tools/node_modules/other/index.js"] {
            let path = directory.url.appending(path: recent).path(percentEncoded: false)
            try FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: path)
        }

        let found = await ProjectArtifacts.scan(roots: [directory.url]).artifacts
        func isActive(_ project: String) throws -> Bool {
            try #require(found.first { $0.project.lastPathComponent == project && $0.name == "node_modules" })
                .isRecentlyActive
        }

        #expect(try isActive("dotenv"))
        #expect(try isActive("workflow"))
        #expect(try isActive("notes"))
        #expect(try !isActive("packages"), "a package install is not work on the project")
    }

    /// Every git command that changes something writes under `.git`, so three files there tell when the whole
    /// repository was last used, without reading a sample of its files.
    @Test func readsWhenTheRepositoryWasLastUsed() throws {
        let directory = try TemporaryDirectory()
        try directory.file("Project/package.json")
        let old = Date(timeIntervalSinceNow: -60 * 24 * 60 * 60)
        try FileManager.default.setAttributes(
            [.modificationDate: old],
            ofItemAtPath: try directory.file("Project/src/main.swift").path(percentEncoded: false)
        )
        try directory.file("Project/.git/index")

        let activity = ProjectArtifacts.lastActivity(
            in: directory.url.appending(path: "Project", directoryHint: .isDirectory),
            ignoring: ["node_modules"]
        )

        #expect(activity.isCertain)
        #expect(try #require(activity.date).timeIntervalSinceNow > -60)
    }
}

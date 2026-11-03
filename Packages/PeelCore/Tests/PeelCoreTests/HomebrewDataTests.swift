import Foundation
@testable import PeelCore
import Testing

@Suite struct HomebrewDataTests {
    @Test func listsWhatFormulasKeepInVarBesidesTheLogsAndHomebrewsOwn() throws {
        let directory = try TemporaryDirectory()
        for folder in ["mysql", "postgresql@16", "log", "homebrew", "redis-old"] {
            try directory.file("prefix/var/\(folder)/data", bytes: 64)
        }
        let prefix = directory.url.appending(path: "prefix", directoryHint: .isDirectory)

        #expect(HomebrewData.folders(in: prefix).map(\.lastPathComponent) == ["mysql", "postgresql@16", "redis-old"])
    }

    @Test func knowsTheFoldersInstalledFormulasNameInTheirOwnFiles() throws {
        let directory = try TemporaryDirectory()
        try directory.file(
            "prefix/Cellar/mariadb/11.8.2/.brew/mariadb.rb",
            contents: Data(#"  datadir = var/"mysql"\n  (var/"run/mariadb").mkpath\n"#.utf8)
        )
        try directory.file(
            "prefix/Cellar/postgresql@16/16.9/.brew/postgresql@16.rb",
            contents: Data("  def datadir = var/name\n  (var/\"log\").mkpath\n".utf8)
        )
        try directory.file(
            "prefix/Cellar/minio/2026.1/.brew/minio.rb", contents: Data(##"  (var/"#{name}").mkpath"##.utf8)
        )
        let prefix = directory.url.appending(path: "prefix", directoryHint: .isDirectory)

        #expect(HomebrewData.foldersNamedByInstalledFormulae(in: prefix) == [
            "mysql", "run", "postgresql@16", "log", "minio",
        ])
    }

    @Test func readsTheChosenHomebrewOptHomebrewAndUsrLocalOnlyWithItsCellar() throws {
        let directory = try TemporaryDirectory()
        let root = directory.url.appending(path: "root", directoryHint: .isDirectory)
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        try directory.directory("root/usr/local/var/postgres")
        #expect(HomebrewData.prefixes(home: home, root: root).map(\.lastPathComponent) == ["homebrew"])

        try directory.directory("root/usr/local/Cellar")
        let choice = HomebrewChoice(url: HomebrewChoice.url(inHome: home))
        #expect(choice.save(directory.url.appending(path: "custom/bin/brew")) == nil)
        #expect(HomebrewData.prefixes(home: home, root: root).map(\.lastPathComponent)
            == ["custom", "homebrew", "local"])

        #expect(choice.save(root.appending(path: "usr/local/bin/brew")) == nil)
        #expect(HomebrewData.prefixes(home: home, root: root).map(\.lastPathComponent) == ["local", "homebrew"])
    }

    @Test func notesEachHomebrewsFoldersByItsOwnFormulas() throws {
        let directory = try TemporaryDirectory()
        try directory.file("one/var/mysql/ibdata1")
        try directory.file("one/var/old/dump.rdb")
        try directory.file("one/Cellar/mariadb/11.8.2/.brew/mariadb.rb", contents: Data(#"var/"mysql""#.utf8))
        try directory.file("two/var/mysql/ibdata1")
        try directory.file("two/Cellar/redis/8.0.2/.brew/redis.rb", contents: Data(#"var/"db""#.utf8))
        try directory.file("three/var/old/dump.rdb")
        try directory.directory("three/Cellar/redis/8.0.2")
        let places = ["one", "two", "three"].flatMap {
            HomebrewData.folders(in: directory.url.appending(path: $0, directoryHint: .isDirectory))
        }

        #expect(Set(HomebrewData.notes(on: places).keys.map { PathPattern.comparablePath(of: $0) })
            == Set(["one/var/old", "two/var/mysql"].map {
                PathPattern.comparablePath(of: directory.url.appending(path: $0))
            }))
    }

    @Test func namesNoFolderUnnamedWhileAnInstalledFormulasFileIsMissing() throws {
        let directory = try TemporaryDirectory()
        try directory.file("prefix/Cellar/mariadb/11.8.2/.brew/mariadb.rb", contents: Data(#"var/"mysql""#.utf8))
        try directory.directory("prefix/Cellar/redis/8.0.2")
        let prefix = directory.url.appending(path: "prefix", directoryHint: .isDirectory)

        #expect(HomebrewData.foldersNamedByInstalledFormulae(in: prefix) == nil)
    }
}

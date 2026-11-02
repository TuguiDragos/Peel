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

    @Test func namesNoFolderUnnamedWhileAnInstalledFormulasFileIsMissing() throws {
        let directory = try TemporaryDirectory()
        try directory.file("prefix/Cellar/mariadb/11.8.2/.brew/mariadb.rb", contents: Data(#"var/"mysql""#.utf8))
        try directory.directory("prefix/Cellar/redis/8.0.2")
        let prefix = directory.url.appending(path: "prefix", directoryHint: .isDirectory)

        #expect(HomebrewData.foldersNamedByInstalledFormulae(in: prefix) == nil)
    }
}

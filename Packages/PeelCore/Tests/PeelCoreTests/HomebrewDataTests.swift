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

    // The lines that name `var` in homebrew-core's formulae at 93a821cfb9eb6a66ce39d4d55c91a0a189e7bf04.
    private static let mariadb = ##"""
          s.change_make_var! "ldata", "\"#{var}/mysql\""
          -DMYSQL_DATADIR=#{var}/mysql
        # Make sure the var/mysql directory exists
        init_data_dir "mysql", using: :mariadb, base: :var
        run [opt_bin/"mariadbd-safe", "--datadir=#{var}/mysql"]
        working_dir var
    """##
    private static let redis = ##"""
        %w[run db/redis log].each { |p| (var/p).mkpath }
          s.gsub! "/var/run/redis_6379.pid", var/"run/redis.pid"
          s.gsub! "dir ./", "dir #{var}/db/redis/"
        error_log_path var/"log/redis.log"
    """##
    private static let prometheus = ##"""
          --storage.tsdb.path #{var}/prometheus
        log_path var/"log/prometheus.log"
        error_log_path var/"log/prometheus.err.log"
    """##
    private static let postgresql = ##"""
        mkdir_p "log", base: :var
        init_data_dir formula_name, using: :postgresql, base: :var
        var/name
        var/"log/#{name}.log"
    """##

    @Test func knowsTheFoldersInstalledFormulasNameInTheirOwnFiles() throws {
        let directory = try TemporaryDirectory()
        try directory.file(
            "prefix/Cellar/postgresql@17/17.6/.brew/postgresql@17.rb", contents: Data(Self.postgresql.utf8)
        )
        try directory.file(
            "prefix/Cellar/minio/2026.1/.brew/minio.rb", contents: Data(##"  (var/"#{name}").mkpath"##.utf8)
        )
        try directory.file(
            "prefix/Cellar/prometheus/3.5.0/.brew/prometheus.rb", contents: Data(Self.prometheus.utf8)
        )
        let prefix = directory.url.appending(path: "prefix", directoryHint: .isDirectory)

        #expect(HomebrewData.foldersNamedByInstalledFormulae(in: prefix) == [
            "log", "postgresql@17", "minio", "prometheus",
        ])
    }

    @Test func knowsNoFolderUnnamedWhileAFormulaLeavesVarToItsProgram() throws {
        #expect(HomebrewData.names(in: Self.mariadb, formula: "mariadb") == nil)
        #expect(HomebrewData.names(in: Self.redis, formula: "redis") == nil)
        #expect(HomebrewData.names(in: "  system \"./configure\", \"--localstatedir=#{var}\"", formula: "tor") == nil)

        let directory = try TemporaryDirectory()
        try directory.file("prefix/var/mysql/ibdata1")
        try directory.file("prefix/Cellar/mariadb/11.8.3/.brew/mariadb.rb", contents: Data(Self.mariadb.utf8))
        let prefix = directory.url.appending(path: "prefix", directoryHint: .isDirectory)
        #expect(HomebrewData.notes(on: HomebrewData.folders(in: prefix)).isEmpty)
    }

    @Test func notesNoFolderInUsrLocalWhereOtherProgramsInstallToo() throws {
        let directory = try TemporaryDirectory()
        try directory.file("root/usr/local/var/org.example.built-by-hand/data")
        try directory.directory("root/usr/local/Cellar/git/2.51.0/.brew")
        try directory.file("root/usr/local/Cellar/git/2.51.0/.brew/git.rb", contents: Data("  url \"x\"".utf8))
        let prefix = directory.url.appending(path: "root/usr/local", directoryHint: .isDirectory)

        #expect(HomebrewData.notes(on: HomebrewData.folders(in: prefix)).isEmpty)
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

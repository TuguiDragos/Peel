import Foundation
@testable import PeelCore
import PeelPrivileged
import Testing

/// The developer tools' Git, run with a home of its own and none of this Mac's settings, so a repository a test
/// makes is the same on every Mac and no commit asks for a signature.
struct GitFixture {
    let executable: URL
    let home: URL

    init(home: URL) async throws {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        executable = try #require(await GitConfig.find(home: home)).executable
        self.home = home
    }

    func run(_ arguments: String..., in folder: URL) async throws {
        let answer = await Subprocess.run(
            executable.path(percentEncoded: false),
            [
                "-c", "user.name=Test", "-c", "user.email=test@example.org", "-c", "commit.gpgsign=false",
                "-c", "init.defaultBranch=main", "-C", folder.path(percentEncoded: false),
            ] + arguments,
            environment: [
                "HOME": home.path(percentEncoded: false), "PATH": "/usr/bin:/bin", "GIT_CONFIG_NOSYSTEM": "1",
            ],
            timeout: 60,
            errorsIntoOutput: true
        )
        guard case .success(let output) = answer, output.status == 0 else {
            let said = if case .success(let output) = answer { output.text } else { "" }
            throw CocoaError(.fileWriteUnknown, userInfo: [
                NSLocalizedDescriptionKey: "git \(arguments.joined(separator: " ")): \(said)",
            ])
        }
    }
}

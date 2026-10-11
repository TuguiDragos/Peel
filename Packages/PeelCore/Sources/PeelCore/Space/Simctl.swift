import Foundation
import PeelPrivileged

/// The simulator tool `xcrun simctl` runs. Xcode's `usr/bin/simctl` is a script that hands every call to
/// CoreSimulator's own program, first running `xcodebuild -runFirstLaunch`, which installs packages, whenever
/// CoreSimulator is missing or older than the one it expects. So Peel asks that program and never runs the script.
enum Simctl {
    static let program = URL(
        filePath: "/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/Resources/bin/simctl"
    )

    /// What `simctl help runtime` prints, which it writes to standard error. Nil when `xcrun` would find no `simctl`
    /// in the active developer folder, or the program did not answer.
    static func runtimeHelp() async -> String? {
        guard let developer = await DeveloperFolder.active(),
              FileManager.default.isExecutableFile(
                  atPath: developer.appending(path: "usr/bin/simctl").path(percentEncoded: false)
              )
        else { return nil }
        let answer = await Subprocess.run(
            program.path(percentEncoded: false), ["help", "runtime"], environment: [:], timeout: 5,
            errorsIntoOutput: true
        )
        guard case .success(let output) = answer, output.status == 0 else { return nil }
        return output.text
    }
}

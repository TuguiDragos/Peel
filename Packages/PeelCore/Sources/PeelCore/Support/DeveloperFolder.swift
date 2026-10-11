import Foundation
import PeelPrivileged

enum DeveloperFolder {
    static func active() async -> URL? {
        let answer = await Subprocess.run("/usr/bin/xcode-select", ["-p"], environment: [:], timeout: 10)
        guard case .success(let output) = answer, output.status == 0 else { return nil }
        return URL(filePath: output.text.trimmingCharacters(in: .whitespacesAndNewlines), directoryHint: .isDirectory)
    }
}

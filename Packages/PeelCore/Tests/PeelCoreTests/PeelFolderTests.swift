import Foundation
@testable import PeelCore
import Testing

struct PeelFolderTests {
    /// Remove Peel moves this one folder, so everything Peel writes has to live in it.
    @Test func everythingPeelWritesLivesInItsFolder() {
        let folder = PathPattern.comparablePath(of: PeelFolder.url)
        let written = [
            TeamRegistry.defaultURL, ExclusionStore.defaultURL, AppMemory.defaultURL,
            RemovalHistory.defaultURL, RemovalHistory.refusalsURL,
            RemovalJournal(beside: RemovalHistory.defaultURL).url,
            PreferenceBackup.defaultDirectory, DigestMemory.defaultURL,
        ]
        for url in written {
            #expect(PathPattern.comparablePath(of: url.deletingLastPathComponent()) == folder, "\(url.path(percentEncoded: false))")
        }
    }
}

import Foundation
@testable import PeelCore
import Testing

struct SystemCachesTests {
    @Test func everyNameIsCarriedByAPartOfTheSealedSystem() {
        for (name, source) in SystemCaches.named {
            #expect(FileManager.default.fileExists(atPath: source), "\(name): \(source)")
            #expect(URL(filePath: source).deletingPathExtension().lastPathComponent == name, "\(name): \(source)")
        }
    }

    @Test func knowsApplesCachesByTheirNameOrTheSystemsOwn() {
        #expect(SystemCaches.isMacOSs("com.apple.Spotlight"))
        #expect(SystemCaches.isMacOSs("CloudKit"))
        #expect(SystemCaches.isMacOSs("cloudkit"))
        #expect(!SystemCaches.isMacOSs("pip"))
        #expect(!SystemCaches.isMacOSs("org.example.app"))
    }
}

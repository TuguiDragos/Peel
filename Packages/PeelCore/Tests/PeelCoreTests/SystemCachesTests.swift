import Foundation
@testable import PeelCore
import Testing

struct SystemCachesTests {
    @Test func knowsApplesCachesByTheirNameOrTheSystemsOwn() {
        #expect(SystemCaches.isMacOSs("com.apple.Spotlight"))
        #expect(SystemCaches.isMacOSs("CloudKit"))
        #expect(SystemCaches.isMacOSs("cloudkit"))
        #expect(!SystemCaches.isMacOSs("pip"))
        #expect(!SystemCaches.isMacOSs("org.example.app"))
    }
}

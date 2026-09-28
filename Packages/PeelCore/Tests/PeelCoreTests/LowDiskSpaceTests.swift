@testable import PeelCore
import Testing

struct LowDiskSpaceTests {
    private static let gigabyte: Int64 = 1_000_000_000

    private static func disk(free: Int64, of total: Int64 = 500 * gigabyte) -> DeviceInfo.Storage {
        DeviceInfo.Storage(total: total, free: free)
    }

    @Test func tellsOnceWhenLessThanATenthIsFree() {
        #expect(LowDiskSpace.check(Self.disk(free: 60 * Self.gigabyte), told: false) == .init(tell: false, told: false))
        #expect(LowDiskSpace.check(Self.disk(free: 49 * Self.gigabyte), told: false) == .init(tell: true, told: true))
        #expect(LowDiskSpace.check(Self.disk(free: 20 * Self.gigabyte), told: true) == .init(tell: false, told: true))
    }

    @Test func tellsAgainOnlyAfterTheDiskHadRoom() {
        #expect(LowDiskSpace.check(Self.disk(free: 60 * Self.gigabyte), told: true) == .init(tell: false, told: true))
        #expect(LowDiskSpace.check(Self.disk(free: 49 * Self.gigabyte), told: true) == .init(tell: false, told: true))
        #expect(LowDiskSpace.check(Self.disk(free: 65 * Self.gigabyte), told: true) == .init(tell: false, told: false))
        #expect(LowDiskSpace.check(Self.disk(free: 49 * Self.gigabyte), told: false) == .init(tell: true, told: true))
    }

    @Test func saysNothingOfADiskWhoseSizeIsUnknown() {
        #expect(LowDiskSpace.check(Self.disk(free: 0, of: 0), told: false) == .init(tell: false, told: false))
    }
}

import Foundation
@testable import PeelCore
import Testing

struct BatchesTests {
    private struct Row {
        let batch: Int
        let date: Date
        let bytes: Int
    }

    private func encode(_ rows: [Row]) -> Data {
        Data(count: rows.reduce(0) { $0 + $1.bytes })
    }

    private func rows(batch: Int, count: Int, bytes: Int) -> [Row] {
        (0..<count).map { _ in Row(batch: batch, date: Date(timeIntervalSince1970: Double(batch)), bytes: bytes) }
    }

    @Test func fitsWithRoomForWhatComesNextAndKeepsTheNewestWhole() {
        let all = (0..<10).flatMap { rows(batch: $0, count: 3, bytes: 100) }

        let fitted = Batches.fitting(
            all, within: 2_000, batch: \.batch, date: \.date, keeping: [9], encode: encode
        )

        #expect(fitted.data.count <= 1_800)
        #expect(fitted.records.filter { $0.batch == 9 }.count == 3)
        #expect(!fitted.records.contains { $0.batch == 0 })
    }

    @Test func keepsWhatIsProtectedEvenWhenItAloneIsTooBig() {
        let all = rows(batch: 1, count: 2, bytes: 100) + rows(batch: 2, count: 30, bytes: 100)

        let fitted = Batches.fitting(all, within: 1_000, batch: \.batch, date: \.date, keeping: [2], encode: encode)

        #expect(fitted.records.map(\.batch) == Array(repeating: 2, count: 30))
    }
}

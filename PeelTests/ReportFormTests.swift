import Foundation
@testable import Peel
import Testing

struct ReportFormTests {
    private let repository = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// Help > Report an Issue fills in fields by the form's ids, so a renamed id would leave its field empty.
    @Test func everyFieldTheReportLinkFillsIsOnTheForm() throws {
        let items = try #require(URLComponents(url: Links.report, resolvingAgainstBaseURL: false)?.queryItems)
        let template = try #require(items.first { $0.name == "template" }?.value)
        let form = repository.appending(path: ".github/ISSUE_TEMPLATE").appending(path: template)
        let text = try String(contentsOf: form, encoding: .utf8)
        let ids = Set(text.split(separator: "\n").compactMap { line -> String? in
            let words = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
            return words.first == "id:" ? words.last.map(String.init) : nil
        })

        let filled = items.map(\.name).filter { $0 != "template" }
        #expect(!filled.isEmpty)
        for name in filled {
            #expect(ids.contains(name), "\(name) is not an id of \(template)")
        }
    }
}

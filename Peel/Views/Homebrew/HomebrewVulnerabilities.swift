import PeelCore
import SwiftUI

/// What the last vulnerability scan found in one formula, on its package's page: a section per severity, worst
/// first, each vulnerability with its summary whole, its identifiers, and what fixes it.
struct HomebrewVulnerabilitySections: View {
    let advisory: HomebrewAdvisory
    let package: HomebrewPackage

    var body: some View {
        Section {
            Group {
                if package.isOutdated, let latest = package.latestVersion {
                    Text("Homebrew’s scan found these in version \(advisory.version), installed on this Mac. Homebrew offers \(latest): once it is installed, scan again to see which of these it fixes.")
                } else {
                    Text("Homebrew’s scan found these in version \(advisory.version), installed on this Mac. They leave this list once the formula is upgraded to a version with the fix and the scan runs again.")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        } header: {
            heading(
                "Known Vulnerabilities",
                "Homebrew checked the installed version against OSV.dev, an open database of known vulnerabilities, and left out those its own patches already fix. “Fixed by its developers, version unknown” means OSV.dev names the changes that fix it, but no version that carries them."
            )
        }
        let bySeverity = Dictionary(grouping: advisory.vulnerabilities, by: \.severity)
        ForEach(bySeverity.keys.sorted(by: >), id: \.self) { severity in
            let vulnerabilities = bySeverity[severity] ?? []
            Section {
                ForEach(vulnerabilities) { vulnerability in
                    HomebrewVulnerabilityRow(vulnerability: vulnerability)
                }
            } header: {
                SectionHeaderLine {
                    Label {
                        Text(severity.title)
                    } icon: {
                        Image(systemName: severity.symbol)
                            .foregroundStyle(severity.color)
                    }
                } count: {
                    Text("^[\(vulnerabilities.count) vulnerability](inflect: true)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } actions: {}
            }
        }
    }
}

private struct HomebrewVulnerabilityRow: View {
    let vulnerability: HomebrewVulnerability

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: vulnerability.summary.isEmpty ? vulnerability.id : vulnerability.summary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: 10) {
                ForEach([vulnerability.id] + vulnerability.aliases, id: \.self) { identifier in
                    Link(destination: Links.vulnerability(identifier)) {
                        Text(verbatim: identifier)
                            .font(.caption.monospaced())
                            .minimumTarget()
                    }
                    .help(Text(verbatim: Links.vulnerability(identifier).absoluteString))
                }
                vulnerability.fix.words
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

extension HomebrewVulnerability.Severity {
    var title: LocalizedStringResource {
        switch self {
        case .critical: "Critical"
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        case .unknown: "Unrated"
        }
    }

    /// A shape of its own for each severity, so the mark is read without its color too.
    var symbol: String {
        switch self {
        case .critical: "exclamationmark.octagon.fill"
        case .high: "exclamationmark.triangle.fill"
        case .medium: "exclamationmark.circle.fill"
        case .low: "exclamationmark.circle"
        case .unknown: "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .critical: .red
        case .high: .orange
        case .medium: .yellow
        case .low, .unknown: .secondary
        }
    }
}

private extension HomebrewVulnerability.Fix {
    var words: Text {
        switch self {
        case .versions(let versions): Text("Fixed in \(versions.formatted(.list(type: .and)))")
        case .commits: Text("Fixed by its developers, version unknown")
        case .notListed: Text("No fix known yet")
        }
    }
}

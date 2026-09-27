import Foundation

/// A model that holds which rows are selected, passed to each row as an object rather than as a `Binding`.
///
/// A `Binding(get:set:)` built in a parent's body holds two closures that can never compare equal, so
/// SwiftUI treats every row as changed and rebuilds all of them on every change.
protocol RowSelection: AnyObject {
    var selectedURLs: Set<URL> { get set }
    func setSelected(_ isSelected: Bool, for url: URL)
}

extension RowSelection {
    func isSelected(_ url: URL) -> Bool {
        selectedURLs.contains(url)
    }

    func setSelected(_ isSelected: Bool, for url: URL) {
        if isSelected {
            selectedURLs.insert(url)
        } else {
            selectedURLs.remove(url)
        }
    }
}

extension RemovalPlan: RowSelection {}
extension BulkRemovalPlan: RowSelection {}
extension ResetPlan: RowSelection {}
extension OrphanLibrary: RowSelection {}
extension DeveloperLibrary: RowSelection {}
extension InstallerLibrary: RowSelection {}
extension PackageLibrary: RowSelection {}
extension ProjectLibrary: RowSelection {}
extension FileSearchLibrary: RowSelection {}
extension CloudLibrary: RowSelection {}

import Foundation

/// A model that holds which rows are selected, passed to each row as an object rather than as a `Binding`.
///
/// A `Binding(get:set:)` built in a parent's body holds two closures that can never compare equal, so
/// SwiftUI treats every row as changed and rebuilds all of them on every change.
protocol RowSelection: AnyObject {
    var selectedURLs: Set<URL> { get set }
    /// Makes `selection` what is selected, as the person chose it: a click and a Select menu both come here.
    func select(_ selection: Set<URL>)
}

extension RowSelection {
    func isSelected(_ url: URL) -> Bool {
        selectedURLs.contains(url)
    }

    func select(_ selection: Set<URL>) {
        selectedURLs = selection
    }

    func setSelected(_ isSelected: Bool, for url: URL) {
        var selection = selectedURLs
        if isSelected {
            selection.insert(url)
        } else {
            selection.remove(url)
        }
        select(selection)
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

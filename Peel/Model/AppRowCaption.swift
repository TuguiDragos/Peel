import Foundation
import PeelCore

/// What an app's row in Applications says under its name while no update waits for it: when it was last opened, or
/// when it arrived if the list is sorted by that, else its version. Nil when it knows none of them, so the name stands
/// alone beside the icon rather than above an empty line.
enum AppRowCaption: Equatable {
    case opened(Date)
    case added(Date)
    case version(String)
    case neverOpened

    init?(app: InstalledApp, sort: AppSort) {
        switch sort {
        case .lastOpened, .name, .size:
            if let date = app.lastUsedDate {
                self = .opened(date)
            } else if let version = app.version {
                self = .version(version)
            } else if app.isUseRecorded {
                self = .neverOpened
            } else {
                return nil
            }
        case .dateAdded:
            if let date = app.dateAdded {
                self = .added(date)
            } else if let version = app.version {
                self = .version(version)
            } else {
                return nil
            }
        }
    }
}

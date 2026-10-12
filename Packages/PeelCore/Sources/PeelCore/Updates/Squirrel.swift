/// Squirrel.Mac, the updater many Electron apps ship, keeps an app's downloaded and staged update in the user's Caches
/// folder, in a folder named for the app's identifier with this after it (`SQRLShipItLauncher.m`,
/// `SQRLDirectoryManager.m`).
enum Squirrel {
    static let folderSuffix = ".ShipIt"
}

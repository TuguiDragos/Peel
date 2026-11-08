import PeelCore
import SwiftUI
import UniformTypeIdentifiers

extension MatchReason {
    var title: LocalizedStringResource {
        switch self {
        case .bundleIdentifier: "The app’s identifier"
        case .embeddedBundleIdentifier: "Helper or extension of the app"
        case .applicationGroup: "A group the app belongs to"
        case .bundleIdentifierPrefix: "Starts with the identifier of the app or of something inside it"
        case .name: "Same name as the app"
        case .teamIdentifier: "Starts with the same maker’s team ID"
        case .vendorPrefix: "Starts with the same maker’s identifier"
        case .namePrefix: "Starts with the app’s name"
        case .launchdJob: "Runs a program inside the app"
        case .linksToTheApp: "Leads to a tool inside the app"
        case .nativeMessagingHost: "Lets a browser extension run a program inside the app"
        case .installerReceipt: "The app’s installer receipt"
        case .homebrewReceipt: "The app’s Homebrew receipt"
        case .leadsIntoItsHomebrewReceipt: "Leads into the app’s Homebrew receipt"
        case .homebrewCask: "Listed by the Homebrew cask"
        case .managedByTheApp: "Managed by the app"
        case .updaterDownloads: "Where the app’s updater keeps its downloads"
        case .namedByTheApp: "Named by the app’s own files"
        case .documentedByItsMaker: "Documented by the app’s maker"
        case .inItsMakersFolder: "In its maker’s folder, and no other app of that maker is installed"
        }
    }
}

extension Greeting {
    var title: LocalizedStringResource {
        switch self {
        case .morning: "Good morning"
        case .afternoon: "Good afternoon"
        case .evening: "Good evening"
        }
    }
}

extension FileKind {
    var title: LocalizedStringResource {
        switch self {
        case .any: "Any kind"
        case .documents: "Documents"
        case .images: "Images"
        case .movies: "Movies"
        case .audio: "Audio"
        case .archives: "Archives"
        case .diskImages: "Disk images"
        }
    }
}

extension SearchLocation.Kind {
    /// The name of an item's kind, shown in the column beside its path. A path like
    /// `/var/folders/…/C/dev.warp.Warp-Stable` says little on its own, while "Caches" says what would be lost.
    /// ByHost preferences are shown as "Preferences": the path already shows the difference.
    var title: LocalizedStringResource {
        switch self {
        case .applicationSupport: "Application Support"
        case .applicationScripts: "Application Scripts"
        case .caches: LocalizedStringResource("Caches (Library folder)", defaultValue: "Caches")
        case .containers, .safariWebApps: "Container"
        case .groupContainers: "Group Container"
        case .preferences, .preferencesByHost: "Preferences"
        case .savedApplicationState: "Saved Windows"
        case .recentDocuments: "Recent Documents"
        case .logs: LocalizedStringResource("Logs (Library folder)", defaultValue: "Logs")
        case .httpStorages: "Web Storage"
        case .webKit: "WebKit Data"
        case .cookies: "Cookies"
        case .launchAgents: "Launch Agent"
        case .launchDaemons: "Launch Daemon"
        case .privilegedHelperTools: "Helper Tool"
        case .startupItems: "Startup Item"
        case .plugIns: "Plug-in"
        case .frameworks: "Framework"
        case .receipts: "Installer Receipt"
        case .homebrewReceipt: "Homebrew Receipt"
        case .library: "Library Folder"
        case .temporaryItems: "Temporary Files"
        case .commandLineTools: "Command-Line Tool"
        case .shellCompletions: "Shell Completion"
        case .nativeMessagingHosts: "Browser Extension Helper"
        case .elsewhere: "Elsewhere"
        case .sharedFolder: "Shared Folder"
        case .hiddenHomeFiles: "Hidden Item"
        case .homeFolder: "Home Folder"
        }
    }

    var symbolName: String {
        switch self {
        case .applicationSupport: "folder"
        case .applicationScripts: "applescript"
        case .caches: "archivebox"
        case .temporaryItems: "hourglass"
        case .commandLineTools, .shellCompletions: "terminal"
        case .nativeMessagingHosts: "puzzlepiece.extension"
        case .elsewhere: "mappin.and.ellipse"
        case .containers, .groupContainers, .safariWebApps: "shippingbox"
        case .preferences, .preferencesByHost: "gearshape"
        case .savedApplicationState: "macwindow"
        case .recentDocuments: "clock.arrow.circlepath"
        case .logs: "doc.text"
        case .httpStorages, .webKit, .cookies: "globe"
        case .launchAgents, .launchDaemons: "gearshape.2"
        case .privilegedHelperTools: "lock.shield"
        case .startupItems: "power"
        case .plugIns: "powerplug"
        case .frameworks: "books.vertical"
        case .receipts: "doc.text.below.ecg"
        case .homebrewReceipt: "mug"
        case .library: "building.columns"
        case .sharedFolder: "person.2"
        case .hiddenHomeFiles: "eye.slash"
        case .homeFolder: "house"
        }
    }
}

extension HelperModel.Action {
    var progress: LocalizedStringResource {
        switch self {
        case .install: "Installing…"
        case .repair: "Repairing…"
        case .uninstall: "Uninstalling…"
        }
    }
}

extension UninstallsItself {
    var warning: Text {
        switch uninstaller {
        case .logsOut(let script):
            Text("Once \(app.name) leaves the Applications folder, its own service uninstalls it: it logs this Mac out of your account and deletes its settings, which History can’t bring back. Write down your account number first, or run the app’s own uninstaller instead: `\(script)`.")
        case .deletesTheApp:
            Text("Once \(app.name) leaves the Applications folder, its own uninstaller opens and asks for an administrator’s password. If you continue there, it deletes the app, even from the Trash, and its system files, which History can’t bring back.")
        case .removesItsComponents:
            Text("Once \(app.name) leaves the Applications folder, its own uninstaller opens and asks to remove the components it keeps in the system. If you continue there, it deletes them, which History can’t bring back.")
        case .deletesItsSuite:
            Text("Once \(app.name) leaves the Applications folder, the cleanup BlueStacks installs runs as an administrator. It deletes the other BlueStacks app if it’s still in the Applications folder and the data BlueStacks keeps for every account in /Users/Shared, which History can’t bring back, and signs you out of now.gg unless BlueAI is installed.")
        case .uninstallsWithoutAsking:
            Text("Once \(app.name) leaves the Applications folder, its own service uninstalls it as an administrator, without asking: it deletes its system files and can delete the app from the Trash too, which History can’t bring back. Then NoMachine Uninstall opens and asks for an administrator’s password to delete the accounts NoMachine made.")
        case .watchedByAJob:
            Text("Moving \(app.name) to the Trash starts a program that waits for it to leave. Peel leaves that program and the file that starts it in place so it can finish, and History can’t bring back anything it removes.")
        }
    }
}

extension CommandToRunFirst {
    /// What `app` may have changed in the Mac's own settings, and the command that undoes it, said before it goes.
    func note(for app: String) -> Text {
        switch undoes {
        case .chargingLimit:
            Text("\(app) may have paused this Mac’s charging at a limit. Before it goes, run `\(command)`, which turns charging back on and removes its tools from /usr/local/bin.")
        }
    }
}

extension LeftInTheSystem {
    /// What `app` leaves in macOS's own settings folders once it goes, with what a rule for `sudo` among it allows.
    func whatStays(after app: String) -> Text {
        let places = paths.formatted(.list(type: .and))
        guard let rule = ruleForSudo else {
            return Text("\(app) leaves \(places) on this Mac after it goes, which only an administrator can remove.")
        }
        return Text("\(app) leaves \(places) on this Mac after it goes, which only an administrator can remove. \(rule) is a rule that lets anyone run the programs it names as an administrator, without a password.")
    }

    var step: Text {
        paths.count == 1 ? Text("To remove it, run `\(command)`.") : Text("To remove them, run `\(command)`.")
    }
}

extension TrustedRoot {
    /// What stops the Mac trusting the certificate, as its maker or Apple says; `app` names the app whose menu it is.
    func step(in app: String) -> Text {
        switch step {
        case .command(let command): Text("To stop trusting it, run `\(command)` first.")
        case .menu(let menu): Text("To stop trusting it, choose \(menu) in \(app) first.")
        case .keychainAccess:
            Text("To stop trusting it, open the certificate whose name begins with \(certificate) in Keychain Access and change its trust settings.")
        }
    }
}

/// What Peel says beside a kernel extension it lists.
enum KernelExtensionNotes {
    static func lines(onAppleSilicon: Bool = HostArchitecture.isAppleSilicon) -> [String] {
        let restart = String(localized: "macOS changes the kernel extensions it loads only when the Mac restarts, so restart once this one is in the Trash.")
        guard onAppleSilicon else { return [restart] }
        // On Apple silicon a kernel extension is installed only once the startup disk's security is Reduced Security.
        return [restart, String(localized: "If you set the startup disk’s security to Reduced Security to install it, it stays that way until you choose Full Security again: in the Recovery app, choose Utilities > Startup Security Utility.")]
    }
}

extension GuardRefusal {
    /// Why Peel never moves the item, in words for the person who asked to move it.
    var explanation: LocalizedStringResource {
        switch self {
        case .exclusionsNotKnown: "Peel won’t move this until it can read your exclusions."
        case .excluded: "Peel won’t move this: your exclusions in Settings keep it where it is."
        case .staysItself: "Peel won’t move this folder itself, since macOS expects to find it. What is inside it can go."
        case .protectedLocation: "Peel won’t move this: it is part of macOS, or inside something Peel protects."
        case .holdsProtectedData: "Peel won’t move this: something Peel protects is inside, such as a keychain or a wallet."
        case .inTheCloud(.cloud): "Peel won’t move this: it syncs to your other devices through iCloud or another app, and moving it to the Trash would also remove it from them."
        case .inTheCloud(.app(let app, let marker)):
            "Peel won’t move this: it is in a folder \(app.name) syncs to your other devices (its marker is \(marker.abbreviatedPath)), and moving it to the Trash would also remove it from them."
        case .holdsDocuments: "Peel won’t move this: an app’s documents are inside."
        case .holdsALibrary: "Peel won’t move this: a photo, music, or video library is inside."
        case .holdsWorkKeptInACache: "Peel won’t move this: an app keeps work inside that exists nowhere else, such as an editor’s local history."
        case .couldNotLookInside: "Peel won’t move this: macOS wouldn’t let Peel look inside to make sure nothing Peel protects, such as a library or a wallet, is there."
        }
    }
}

extension TrashFailure.Reason {
    /// What went wrong with one item of a removal, in words for the user who asked to move it.
    var explanation: String {
        explanation(in: nil)
    }

    /// The explanation read from `bundle`, or from the main bundle when it is nil.
    func explanation(in bundle: Bundle?) -> String {
        switch self {
        case .guarded(let refusal?): refusal.explanation.resolved(in: bundle)
        case .guarded(nil): String(localized: "Peel won’t move this: it is protected, or your exclusions in Settings keep it where it is.", bundle: bundle)
        case .changedSinceScan: String(localized: "It changed after Peel looked at it. Scan again to review it.", bundle: bundle)
        case .changeNotKnown: String(localized: "Peel couldn’t read it in time to see whether it changed after Peel looked at it. Scan again to review it.", bundle: bundle)
        case .claimedSinceScan: String(localized: "Peel couldn’t confirm it is still nobody’s: an installed app may claim it now. Scan again to review it.", bundle: bundle)
        case .lastCopy: String(localized: "The copy Peel was keeping has changed or moved since the scan, so this one may be the last.", bundle: bundle)
        case .notPermitted: String(localized: "macOS didn’t allow it.", bundle: bundle)
        case .locked: String(localized: "It is locked. In Finder, choose File > Get Info and deselect Locked, then try again.", bundle: bundle)
        case .needsHelper: String(localized: "It needs administrator access, which Peel’s helper provides.", bundle: bundle)
        case .movedWithoutATrace: String(localized: "It is in the Trash, but macOS didn’t say where, so it can only be put back from Finder.", bundle: bundle)
        case .somethingElseMoved(let name): String(localized: "Something else was at that path by the time it moved. It is in the Trash as \(name), and Finder can put it back.", bundle: bundle)
        case .historyUnreadable: String(localized: "Peel couldn’t read History, and it moves nothing it can’t put back.", bundle: bundle)
        case .historyCannotBeWritten(let problem?): problem.explanation(in: bundle)
        case .historyCannotBeWritten(nil): String(localized: "Peel couldn’t write to History then, and it moves nothing it can’t put back.", bundle: bundle)
        case .peelRemovesItself: String(localized: "Peel is removing itself, so it moves nothing else meanwhile.", bundle: bundle)
        case .heldOpen(let processes):
            String(localized: "It is in use by \(processes.formatted(.list(type: .and))). Quit \(processes.formatted(.list(type: .and))), then try again.", bundle: bundle)
        case .heldOpenByAJob(let processes) where processes.count > 1:
            String(localized: "It is in use by \(processes.formatted(.list(type: .and))). Quit \(processes.formatted(.list(type: .and))), or stop them in Background Items if they have no window, then try again.", bundle: bundle)
        case .heldOpenByAJob(let processes):
            String(localized: "It is in use by \(processes.formatted(.list(type: .and))). Quit \(processes.formatted(.list(type: .and))), or stop it in Background Items if it has no window, then try again.", bundle: bundle)
        case .peelRunsFromIt: String(localized: "Peel itself runs from here, and only Remove Peel, in Settings > General, removes Peel.", bundle: bundle)
        case .heldByAnotherAccount(let processes) where processes.count > 1:
            String(localized: "It is in use by \(processes.formatted(.list(type: .and))), which run as another account or as the system, so neither you nor Peel can quit them. Stop them in Background Items, or with the app’s own uninstaller, then try again.", bundle: bundle)
        case .heldByAnotherAccount(let processes):
            String(localized: "It is in use by \(processes.formatted(.list(type: .and))), which runs as another account or as the system, so neither you nor Peel can quit it. Stop it in Background Items, or with the app’s own uninstaller, then try again.", bundle: bundle)
        case .openForAnotherUser(let processes) where processes.count > 1:
            String(localized: "It is in use by \(processes.formatted(.list(type: .and))) in another user’s account on this Mac. Quit them in that account, then try again.", bundle: bundle)
        case .openForAnotherUser(let processes):
            String(localized: "It is in use by \(processes.formatted(.list(type: .and))) in another user’s account on this Mac. Quit it in that account, then try again.", bundle: bundle)
        case .heldByABuildTool(let tools):
            String(localized: "It is in use by \(tools.formatted(.list(type: .and))). Run \(BuildDaemon.stopCommands(for: tools).map { "`\($0)`" }.formatted(.list(type: .and))), then try again.", bundle: bundle)
        case .inUseAsAnInputSource:
            String(localized: "It is in use as an input source. In System Settings > Keyboard > Text Input, click Edit beside Input Sources, select it and click Remove, then try again.", bundle: bundle)
        case .inUseByMacOS(let processes):
            String(localized: "macOS is using it right now, through \(processes.formatted(.list(type: .and))), so it stays where it is.", bundle: bundle)
        case .attachedDiskImage:
            String(localized: "It is a disk image that is open right now. Eject it, then try again.", bundle: bundle)
        case .stillLeadsTo(let target):
            String(localized: "It still leads to \(URL(filePath: target).abbreviatedPath) on this Mac.", bundle: bundle)
        case .failed(let message): FixedSentence.translated(message, in: bundle)
        }
    }
}

extension CouldNotShow {
    /// Why the window couldn't show this app, with its path.
    var explanation: String {
        reason.explanation(at: url)
    }
}

extension AppInspector.Unreadable {
    /// Why the bundle at `url` couldn't be read as an app, with its path.
    func explanation(at url: URL) -> String {
        let path = url.abbreviatedPath
        return switch self {
        case .gone: String(localized: "\(path) isn’t there anymore.")
        case .notAnApp: String(localized: "\(path) isn’t an app.")
        case .noInfo: String(localized: "\(path) has no Info.plist, the file that says what an app is, so Peel can’t read it as one.")
        case .infoClosed: String(localized: "Permissions keep your account from reading the Info.plist in \(path), so Peel can’t read it as an app.")
        case .infoDamaged: String(localized: "The Info.plist in \(path) isn’t a property list Peel can read, so Peel can’t read it as an app.")
        }
    }
}

extension FileProblem {
    /// `sentence`, then why the file at `url` couldn't be read or saved.
    func said(after sentence: String, about url: URL) -> String {
        [sentence, why(about: url)].joined(separator: " ")
    }

    /// `sentence`, its Markdown read, then why the file at `url` couldn't be read or saved.
    func said(after sentence: AttributedString, about url: URL) -> AttributedString {
        sentence + AttributedString(" " + why(about: url))
    }

    private func why(about url: URL) -> String {
        switch self {
        case .notAFile: String(localized: "Something other than a file, such as a folder, is where the file should be.")
        case .tooLarge: String(localized: "The file is larger than Peel ever writes it, so Peel doesn’t read it.")
        case .damaged: String(localized: "The file’s contents aren’t in a form Peel can read.")
        case .failed(let error): String(localized: "macOS answered: \(error.description(of: url))")
        }
    }
}

extension FileProblem? {
    /// `sentence`, then why the file at `url` couldn't be read or saved, when that is known.
    func said(after sentence: String, about url: URL) -> String {
        self?.said(after: sentence, about: url) ?? sentence
    }

    /// What the Shell and SSH tabs say when Peel's own settings file at `url` can't be read.
    func peelsSettingsUnreadable(at url: URL) -> String {
        said(after: String(localized: "Peel’s settings file couldn’t be read."), about: url)
    }
}

extension FileProblem {
    /// What the Shell and SSH tabs say when Peel's own settings file at `url` couldn't be saved.
    func peelsSettingsNotSaved(at url: URL) -> String {
        said(after: String(localized: "Peel couldn’t save its settings file."), about: url)
    }
}

extension AppLibrary {
    /// `sentence`, then why Peel can't read its list of app folders, when Peel knows.
    func unreadableListOfFolders(saying sentence: String) -> String {
        whyListOfFoldersUnreadable.said(after: sentence, about: foldersFile)
    }

    /// That the folders couldn't be saved, then why, when Peel knows.
    var foldersNotSaved: String {
        whyFoldersNotSaved.said(after: String(localized: "Peel couldn’t save the app folders."), about: foldersFile)
    }
}

extension OrphanLibrary {
    /// What an alert says when the list of orphaned files that belong to an app or a tool couldn't be changed, and
    /// why.
    func ownersNotSaved(_ why: FileProblem?) -> String {
        let said = owners == nil
            ? String(localized: "Peel can’t read its list of the orphaned files you said belong to an app or a tool, so it lists them all. Start the list over in Settings > Exclusions.")
            : String(localized: "Nothing changed.")
        return why.said(after: said, about: OrphanOwners.defaultURL)
    }
}

extension ExclusionsStore {
    /// That nothing moves until the list starts over, then why it couldn't be read, when Peel knows.
    var nothingMovesUntilStartedOver: String {
        exclusions.whyUnreadable.said(after: String(localized: "Peel removes nothing and puts nothing back until you start the list over in Settings."), about: file)
    }
}

extension PreferenceBackup.NotSaved {
    /// Why a copy of an app's settings couldn't be made, as a sentence of its own.
    var sentence: String {
        switch self {
        case .noUsableIdentifier: String(localized: "The app has no identifier Peel can name a copy after.")
        case .noAnswer(let domain): String(localized: "The defaults command didn’t answer about \(domain).")
        case .notExported(let domain): String(localized: "The defaults command couldn’t copy \(domain).")
        case .noFolder(let why):
            why.said(after: String(localized: "Peel couldn’t make a folder for the copy."), about: PreferenceBackup.defaultDirectory)
        }
    }
}

extension PreferenceBackup.CopyUnreadable {
    /// Why the copy in `folder` couldn't be read, as a sentence of its own.
    func sentence(about folder: URL) -> String {
        switch self {
        case .folderUnreadable(let why): why.said(after: String(localized: "Peel couldn’t open the copy’s folder."), about: folder)
        case .noSettings: String(localized: "The copy holds no settings file.")
        case .notAPropertyList: String(localized: "The copy’s settings files aren’t in a form Peel can read.")
        }
    }
}

extension GitConfig.Refusal? {
    /// What the Git tab says when Git didn't make a change.
    var sentence: String {
        switch self {
        case .said(let words)? where !words.isEmpty:
            [String(localized: "Git refused the change."), String(localized: "Git said: \(words)")].joined(separator: " ")
        case .noAnswer?: String(localized: "Git didn’t answer, so nothing changed.")
        default: String(localized: "Git refused the change.")
        }
    }
}

extension HistoryWriteProblem {
    /// What keeps History from being written, and that nothing moves meanwhile, read from `bundle`, or from the main
    /// bundle when it is nil.
    func explanation(in bundle: Bundle? = nil) -> String {
        switch self {
        case .folderNotWritable(let folder):
            String(localized: "This account can’t write to \(folder.abbreviatedPath), where Peel keeps History. Peel removes nothing until it can, so that everything it moves can be put back.", bundle: bundle)
        case .diskFull(let free, let needed):
            String(localized: "The disk that holds Peel’s folder has \(free.formatted(.byteCount(style: .file))) free, and writing History needs \(needed.formatted(.byteCount(style: .file))). Peel removes nothing until there is room, so that everything it moves can be put back.", bundle: bundle)
        case .freeSpaceNotKnown(let folder):
            String(localized: "macOS didn’t say how much room is free on the disk that holds \(folder.abbreviatedPath). Peel removes nothing until it knows, so that everything it moves can be put back.", bundle: bundle)
        case .journalUnreadable(let journal):
            String(localized: "Something Peel can’t use stands at \(journal.abbreviatedPath), where it writes down each move, and Peel couldn’t set it aside. Peel removes nothing until it’s gone, so that everything it moves can be put back.", bundle: bundle)
        case .journalNotWritable(let journal):
            String(localized: "This account can’t write \(journal.abbreviatedPath), where Peel writes down each move. Peel removes nothing until it can, so that everything it moves can be put back.", bundle: bundle)
        }
    }
}

extension PrivacyReset.Result {
    /// Why the app's privacy permissions were not reset, or nil when they were.
    var explanation: String? {
        switch self {
        case .reset: nil
        case .notKnownToTheSystem: String(localized: "macOS couldn’t find the app, so what it was allowed to access is still on record.")
        case .refused: String(localized: "Peel never resets them for this app.")
        case .failed(let message): message.isEmpty ? String(localized: "macOS didn’t say why.") : String(localized: "macOS reported: \(message)")
        case .couldNotAsk(let message): FixedSentence.translated(message)
        }
    }
}

extension ProjectArtifacts.Refusal {
    /// Why a chosen folder can't be searched for projects. It is shown where the folder was chosen, rather
    /// than as an empty list.
    var explanation: String {
        switch self {
        case .tooBroad: String(localized: "A whole home folder or disk is too much to search. Choose the folder your projects are in.")
        case .systemFolder: String(localized: "It is a folder that macOS or every account uses, not a folder of projects. Choose the folder your projects are in.")
        case .inTheCloud(.cloud): String(localized: "It is in a folder that syncs to your other devices through iCloud or another app, which Peel leaves to that app.")
        case .inTheCloud(.app(let app, let marker)):
            String(localized: "It is in a folder \(app.name) syncs to your other devices (its marker is \(marker.abbreviatedPath)), which Peel leaves to that app.")
        case .unreachable(let problem): problem.explanation
        case .inAPackage: String(localized: "It is an app or another package, or inside one, and what is inside belongs to it.")
        case .neverSearched(.hidden(let name)):
            String(localized: "Peel doesn’t look for projects in \(name) or anything inside it, since apps and tools keep their own files in hidden folders.")
        case .neverSearched(.library):
            String(localized: "Peel doesn’t look for projects in a Library folder or anything inside it, since apps keep their data there.")
        case .neverSearched(.filledBy(let folder, let tool)):
            String(localized: "Peel doesn’t look for projects in \(folder) or anything inside it, since \(tool) fills it with what it installs.")
        case .insideAnotherFolder(let folder): String(localized: "It is inside \(folder.abbreviatedPath), which is already on the list.")
        case .holdsAnotherFolder(let folder): String(localized: "It holds \(folder.abbreviatedPath), which is already on the list. Remove that one first.")
        }
    }
}

extension DuplicateFinder.Refusal {
    /// Why a chosen folder isn't scanned for duplicates, shown where the folder was chosen and with the result.
    var explanation: String {
        switch self {
        case .protected: String(localized: "Peel protects what is there, and never moves it.")
        case .library: String(localized: "It is your Library, or a folder in it, where apps keep their data.")
        case .mediaFolder(.music): String(localized: "It is the folder where the Music app keeps its media, or a folder in it.")
        case .mediaFolder(.tv): String(localized: "It is the folder where the TV app keeps its media, or a folder in it.")
        case .readOnlyDisk: String(localized: "It is on a disk that can only be read, so nothing there could move to the Trash.")
        case .inAPackage: String(localized: "It is an app or another package, or inside one, and what is inside belongs to it.")
        case .outsideTheHome: String(localized: "It is outside your home folder, /Users/Shared, and the disks in /Volumes.")
        case .insideARepository: String(localized: "It is a repository, or sits inside one, and Peel leaves repositories alone.")
        case .unreachable(let problem): problem.explanation
        }
    }
}

extension UpdateFailure {
    /// Who Peel asked whether `app` has an update, and what came back instead of an answer.
    func explanation(about app: String) -> String {
        let asked = switch asked {
        case .appStore: String(localized: "Peel asked the App Store whether \(app) has an update.")
        case .server(let host): String(localized: "Peel asked \(host) whether \(app) has an update.")
        }
        let came = switch cause {
        case .noAnswer(let words): String(localized: "No answer came: \(words)")
        case .answered(let status):
            switch StatusMeaning(status: status) {
            case .nothingThere: String(localized: "It answered \(String(status)): nothing is at that address.")
            case .refused: String(localized: "It answered \(String(status)): access is refused.")
            case .tooManyRequests:
                String(localized: "It answered \(String(status)): it limits how often it answers, and asks Peel to wait.")
            case .serverError: String(localized: "It answered \(String(status)), an error on the server’s side.")
            case .other:
                String(localized: "It answered with HTTP status \(String(status)) instead of what Peel asked for.")
            }
        case .sentOnTo(let address):
            String(localized: "It sent Peel on to \(address), which isn’t https, so Peel didn’t follow.")
        case .tooLarge: String(localized: "It sent more than any update feed holds, so Peel stopped reading.")
        case .unreadable(let type?):
            String(localized: "What it sent, marked as \(Self.described(type)), isn’t an answer Peel can read.")
        case .unreadable(nil): String(localized: "What it sent isn’t an answer Peel can read.")
        case .olderThanFound(let version, let found):
            String(localized: "It answered \(version), older than the update to \(found) it offered before, so its catalog isn’t up to date yet.")
        case .unlistedAfterAnUpdate:
            String(localized: "It answered that it doesn’t list \(app), right after it offered an update, so Peel waits for a second answer.")
        }
        return asked + " " + came
    }

    /// A content type as macOS names it in the reader's language, or as the server wrote it when macOS doesn't know it.
    private static func described(_ type: String) -> String {
        UTType(mimeType: type).flatMap { $0.isDynamic ? nil : $0.localizedDescription } ?? type
    }
}

extension FolderReach {
    /// Why a chosen folder can't be reached.
    var explanation: String {
        switch self {
        case .diskNotConnected(let disk): String(localized: "It is on \(disk), a disk that isn’t connected now.")
        case .gone: String(localized: "It isn’t there anymore.")
        case .notAFolder: String(localized: "It isn’t a folder.")
        case .closed: String(localized: "Its permissions, or those of a folder on its way, keep your account out.")
        case .didNotAnswer: String(localized: "Its disk didn’t answer in time.")
        case .failed(let error): String(localized: "macOS couldn’t reach it: \(error.localizedDescription)")
        }
    }
}

extension RestoreFailure {
    /// Why one item stayed in the Trash. Shown beside the item, since a batch can fail for several reasons.
    var explanation: String {
        switch self {
        case .missingFromTrash: String(localized: "It is no longer in the Trash, so there is nothing to put back.")
        case .alreadyThere: String(localized: "Something is already there, and Peel never replaces it.")
        case .needsHelper: String(localized: "It needs administrator access, which Peel’s helper provides.")
        case .notAllowed(.excluded):
            String(localized: "Your exclusions in Settings keep Peel from putting anything back there. Take it off the list to put this back, or drag it out of the Trash in Finder.")
        case .notAllowed: String(localized: "Peel protects that place now, so it puts nothing back there. You can drag it out of the Trash in Finder.")
        case .notInATrash: String(localized: "It isn’t in the Trash where Peel put it, so Peel leaves it where it is.")
        case .notAllowedByTheHelper(let message): FixedSentence.translated(message)
        case .locked: String(localized: "It is locked. In Finder, choose File > Get Info and deselect Locked, then try again.")
        case .folderLocked:
            String(localized: "The folder it goes back to is locked. In Finder, choose File > Get Info for that folder and deselect Locked, then try again.")
        case .folderGone:
            String(localized: "The folder it goes back to isn’t there anymore. Put that folder back first, or drag this out of the Trash in Finder.")
        case .needsAppManagement:
            String(localized: "macOS lets Peel put back another developer’s app only with App Management. Allow Peel in System Settings > Privacy & Security > App Management, then try again.")
        case .notPermitted: String(localized: "macOS didn’t allow it.")
        case .failed(let message): FixedSentence.translated(message)
        case .replacementStays(let reason):
            String(localized: "The version now in its place couldn’t move to the Trash first, so nothing changed.") + " "
                + reason.explanation
        }
    }
}

extension RestoreFailure {
    /// The title of the alert after a Put Back of `asked` items that left `stayed` of them in the Trash.
    static func title(stayed: Int, of asked: Int) -> String {
        asked > 1 && stayed >= asked
            ? String(localized: "None of these could be put back.")
            : String(inflecting: "^[\(stayed) item](inflect: true) couldn’t be put back.")
    }
}

extension CloudRefusal {
    /// Why a file's local copy was not freed. Freeing deletes nothing, since the file stays in iCloud, so no
    /// way back is offered.
    var explanation: String {
        switch reason {
        case .gone: String(localized: "It isn’t there anymore.")
        case .editedSinceScan: String(localized: "It was edited after Peel looked at it, so Peel left it alone. Scan again to review it.")
        case .notDownloaded: String(localized: "Its download isn’t on this Mac anymore, so there is nothing to remove.")
        case .olderVersion: String(localized: "A newer version of it waits in iCloud, so Peel left the one on this Mac alone.")
        case .notUploaded: String(localized: "iCloud doesn’t have all of it yet, so removing its download could lose what isn’t uploaded.")
        case .inConflict: String(localized: "It has versions in conflict that iCloud hasn’t settled, so Peel left it alone.")
        case .syncPaused: String(localized: "Its syncing is paused, so iCloud may not have its newest version.")
        case .uploadFailed(let message): String(localized: "iCloud couldn’t upload it: \(message)")
        case .excluded: String(localized: "Excluded in Settings")
        case .inUse(let programs) where !programs.isEmpty:
            String(localized: "It is in use by \(programs.formatted(.list(type: .and))), so macOS couldn’t remove its download. Try again once nothing uses it.")
        case .inUse:
            String(localized: "macOS says it is in use, though no program of your account has it open, so its download couldn’t be removed. Try again later.")
        case .keptDownloaded: String(localized: "Keep Downloaded is on for it in Finder, so iCloud would download it again.")
        case .notRemovable: String(localized: "iCloud keeps this download on this Mac, so it can’t be removed.")
        case .failed(let message): message
        }
    }
}

extension RemovedElsewhere {
    /// Why a row of an app Peel never removes from its page stays where it is.
    var explanation: LocalizedStringResource {
        switch self {
        case .byRemovePeel: "Left alone: Peel removes itself only from Settings."
        case .byItsMaker(let uninstaller): "Left alone: \(uninstaller.maker)’s own uninstaller removes it."
        case .byFinder(let carried): Self.leftToFinder(carried)
        case .afterItsSystemExtensions(let carried):
            carried.inAnAppInside.count == 1
                ? "Left alone: macOS installed \(carried.inAnAppInside.formatted(.list(type: .and))) for an app bundled inside this app, and keeps it when the app moves, in Finder or in Peel. Remove the extension first, the way its maker describes."
                : "Left alone: macOS installed \(carried.inAnAppInside.formatted(.list(type: .and))) for an app bundled inside this app, and keeps them when the app moves, in Finder or in Peel. Remove the extensions first, the way their maker describes."
        }
    }

    private static func leftToFinder(_ carried: CarriedSystemExtensions) -> LocalizedStringResource {
        guard carried.isKnown else {
            return "Left alone: Peel can’t look inside the app to see which system extensions it carries, and macOS removes those only when the app goes to the Trash in Finder."
        }
        let names = carried.names.formatted(.list(type: .and))
        if #available(macOS 27, *) {
            guard carried.systemSettingsDeletesThem else {
                return "Left alone: only macOS can remove \(names). Move the app to the Trash in Finder, which asks macOS to do it."
            }
            return carried.names.count == 1
                ? "Left alone: only macOS can remove \(names). Move the app to the Trash in Finder. If it stays, in System Settings > General > Login Items & Extensions, choose By Category, click the Info button beside Network Extensions, then click the More button beside it and choose Delete Extension."
                : "Left alone: only macOS can remove \(names). Move the app to the Trash in Finder. If they stay, in System Settings > General > Login Items & Extensions, choose By Category, click the Info button beside Network Extensions, then click the More button beside each and choose Delete Extension."
        }
        return "Left alone: macOS removes \(names) only when the app goes to the Trash in Finder."
    }
}

extension HoldBack {
    /// Why Peel did not select an item, or leaves it where it is. It is shown in the note beside the row, with
    /// the reason for the match.
    var explanation: LocalizedStringResource {
        switch self {
        case .holdsRepository:
            "Not selected: there is a repository inside, so this folder may hold work that was committed and never pushed anywhere."
        case .trackedByGit:
            "Not selected: Git tracks files in this folder, so it is part of the project. Moving it would show them as deleted in Git."
        case .gitTrackingNotKnown:
            "Not selected: this folder is in a Git repository whose list of tracked files Peel couldn’t read, so it may be part of the project."
        case .gitTrackingNotReadInTime:
            "Not selected: reading which files Git tracks here took too long, so this folder may be part of the project. Rescan to try again."
        case .keepsItsSetup:
            "Not selected: it also keeps the options this build was set up with, which nothing else in the project holds."
        case .sharedWithEveryone:
            "Not selected: /Users/Shared belongs to every account on this Mac, so this may be another account’s."
        case .listedByAnotherPackage:
            "Not selected: another package installed on this Mac lists it too, so what that package installed may use it."
        case .holdsWhatOthersPut:
            "Not selected: the package made this folder, but something else put files in it, which may be another program’s or yours."
        case .namedLikeTheApp:
            "Not selected: only the name matches, and a folder here may be another program’s, holding work you rely on."
        case .holdsAnExclusion:
            "Left alone: something you excluded in Settings is inside, and moving this would take it along."
        case .notMeasured:
            "Not selected: this took too long to measure, so Peel doesn’t know how big it is or what is inside."
        case .couldNotBeRead:
            "Not selected: macOS wouldn’t let Peel read inside, so what is in there isn’t known. If Peel doesn’t have Full Disk Access yet, turning it on from Home may let it see."
        case .closedByPermissions:
            "Not selected: its own permissions keep your account out, so what is in there isn’t known. Full Disk Access lets Peel past macOS’s privacy protections, not past a folder’s own permissions."
        case .couldNotLookInside:
            "Left alone: macOS wouldn’t let Peel look inside to make sure nothing Peel protects, such as a library or a wallet, is there. If Peel doesn’t have Full Disk Access yet, turning it on from Home may let it see."
        case .holdsDocuments:
            "Left alone: the app’s own Documents folder is inside and may hold what you made with it. Peel never removes that."
        case .holdsALibrary:
            "Left alone: a photo, music, or video library is inside, so Peel leaves this folder where it is."
        case .holdsAWallet:
            "Not selected: a wallet or a signing key is inside. Once the Trash is emptied, what it opens is gone for good unless you have a backup."
        case .holdsAPasswordDatabase:
            "Not selected: a password database or its key file is inside. Once the Trash is emptied, the passwords are gone for good unless you have a backup."
        case .holdsLocalMail:
            "Not selected: this may hold mail kept only on this Mac, such as a local or POP account’s. Once the Trash is emptied, it’s gone for good unless you have a backup."
        case .holdsMessageHistory:
            "Not selected: this holds message history that may exist only on this Mac. Once the Trash is emptied, it’s gone for good unless you have a backup."
        case .holdsPasswordsOrCodes:
            "Not selected: this holds passwords or sign-in codes that may exist only on this Mac. Once the Trash is emptied, they’re gone for good unless you have a backup."
        case .holdsVPNConnections:
            "Not selected: this holds VPN connections, with their keys and certificates, that may exist only on this Mac. Once the Trash is emptied, they’re gone for good unless you have a backup."
        case .holdsSignIns:
            "Not selected: this holds a sign-in to a service, such as a token a tool saved when you logged in. Once the Trash is emptied, you’d sign in again."
        case .holdsTorrents:
            "Not selected: this holds your list of torrents and how far each one got, which may exist only on this Mac. Once the Trash is emptied, you’d have to add each torrent again."
        case .packageLeftMore:
            "Not selected: the package also left items outside the app. Package Receipts lists them only while this receipt is here."
        case .holdsWorkMadeWithTheApp:
            "Not selected: this holds what you made with the app, such as saved games, databases, or the app’s own backups, which may exist only on this Mac. Once the Trash is emptied, it’s gone for good unless you have another copy."
        case .holdsSimulators:
            "Not selected: this holds the app’s simulators, with the apps installed in them and their data, which may exist only on this Mac. Once the Trash is emptied, they’re gone for good unless you have a backup."
        case .holdsVirtualMachines:
            "Not selected: this holds virtual machines or Windows bottles, with the systems, apps, and files in them, which may exist only on this Mac. Once the Trash is emptied, they’re gone for good unless you have a backup."
        case .holdsKeys:
            "Left alone: a wallet or a key Peel protects is inside, so Peel leaves this folder where it is."
        case .holdsWorkKeptInACache:
            "Peel won’t move this: an app keeps work inside that exists nowhere else, such as an editor’s local history."
        case .insideAnotherAppsFolder:
            "Not selected: only the name matches, and it sits inside a folder that belongs to macOS or to another installed app, which may be keeping it for itself."
        case .holdsAnotherAppsData:
            "Left alone: another app on this Mac keeps its own data inside, and moving this would take that data too."
        case .beyondTheHelper:
            "Left alone: only an administrator can move this, and Peel’s helper isn’t allowed to move it from here."
        case .leftToItsUninstaller:
            "Left alone: the app’s own uninstaller removes this once the app is in the Trash, and History can’t bring it back."
        case .neededWhenTheAppLeaves:
            "Left alone: a program that runs once the app is in the Trash needs this, so Peel leaves it where it is."
        case .systemExtension:
            "Left alone: macOS installed this system extension and removes it only when the app that uses it goes to the Trash in Finder. If that app is gone, install it again, open it and use the feature that needs the extension, allow it when macOS asks, then move the app to the Trash in Finder and restart your Mac."
        case .systemExtensionGoingAtRestart:
            "Left alone: macOS removes this system extension when your Mac restarts."
        case .deletableSystemExtension:
            "Left alone: macOS installed this system extension, and only macOS removes it. In System Settings > General > Login Items & Extensions, choose By Category, click the Info button beside Network Extensions, then click the More button beside it and choose Delete Extension."
        case .signInPlugIn:
            "Left alone: macOS may load this plug-in when someone logs in, and taking it away could keep anyone from logging in, so only its maker’s uninstaller removes it."
        case .loadedByOtherApps:
            "Not selected: other apps can load it on their own, such as music apps."
        case .keptByMacOS:
            "Not selected: macOS keeps this for its own services, which may be using it right now."
        case .openedFromMail:
            "Not selected: Mail keeps a copy here of each attachment you open, and one you edited may exist nowhere else."
        case .crashReport:
            "Not selected: a report macOS wrote when the app crashed, which its developer may still ask you for."
        case .inTheCloud:
            "Left alone: this syncs to your other devices through iCloud or another app, and moving it to the Trash would also remove it from them."
        case .keepsWhatTheOthersLack:
            "Left alone: this copy has Finder tags, a Finder comment, or a resource fork the others don’t, which moving it would lose."
        case .keptDownloaded:
            "Not selected: Keep Downloaded is on for it in Finder, so iCloud downloads it again."
        case .inAnAppsICloudFolder:
            "Not selected: it is in an app’s own iCloud folder, which Finder may not show, and the app may expect to find it on this Mac."
        case .opensOnlyOnline:
            "Not selected: it holds passwords or a wallet’s keys, which open again only with an internet connection once the download is removed."
        case .inARepository:
            "Not selected: it is in a repository, so it may be part of a project’s work."
        case .openInAProgram:
            "Not selected: a program has this open right now, and may still be using it."
        case .attachedDiskImage:
            "Not selected: this disk image is open right now. Eject it first."
        case .changedRecently:
            "Not selected: this changed in the last day, so it may still be downloading."
        case .arrivedRecently:
            "Not selected: this arrived or changed in the last hour, so you may be installing from it now."
        case .mayStillBeResumed:
            "Not selected: a program that resumes downloads, such as a torrent client, may still finish this."
        case .writtenRecently:
            "Not selected: something wrote to this in the last 15 minutes, so a program may still be using it."
        case .serverStillListens:
            "Not selected: a server on this Mac still listens on the port this folder is named for, and keeps its uploads here."
        case .keptByAnApp:
            "Not selected: this is in a folder an app keeps, and the app may still need it."
        case .appIsRunning:
            "Not selected: the app is running and may install this update when it quits."
        case .mayBeTheOnlyCopy:
            "Not selected: this isn’t an installed app’s installer and nothing shows where it was downloaded from, so it may be your only copy."
        case .encryptedImage:
            "Not selected: an encrypted disk image holds what you put in it."
        }
    }

    /// The explanation, naming the app that keeps the item in step and its marker, or the programs that hold it open.
    func explanation(keptInStepBy keeper: SyncKeeper?, openBy programs: [String] = []) -> LocalizedStringResource {
        if self == .openInAProgram, !programs.isEmpty {
            return "Not selected: it is open in \(programs.formatted(.list(type: .and))) right now, which may still be using it."
        }
        guard self == .inTheCloud, case .app(let app, let marker)? = keeper else { return explanation }
        return "Left alone: this is in a folder \(app.name) syncs to your other devices (its marker is \(marker.abbreviatedPath)), and moving it to the Trash would also remove it from them."
    }
}

extension OrphanConfidence {
    /// The strongest thing Peel can say about these files, in one line.
    var summary: Text {
        text(for: reasons.first)
    }

    /// The badge on a group's page, or nil when it would add nothing: the summary when Peel is unsure, or
    /// else how long nothing has changed there. That Peel saw the app leave is said in a line of its own, so a
    /// change after it left is told without it.
    var badge: Text? {
        if case .writtenAfterItLeft(_, let written) = reasons.first { return modified(written) }
        if level == .unsure { return summary }
        return reasons.first { if case .untouched = $0 { true } else { false } }.map(text(for:))
    }

    private func modified(_ date: Date) -> Text {
        Text("Modified \(date, format: .relative(presentation: .named)), so something may still use these files")
    }

    private func text(for reason: Reason?) -> Text {
        guard let reason else { return Text("No installed app claims these") }
        return switch reason {
        case .running(let name):
            Text("\(name) is running now, so these may still be in use")
        case .leadsIntoAnAppThatIsGone:
            Text("These links lead into an app that is no longer there")
        case .onlyTheName(let name):
            Text("Only the name ties these to \(name), which Peel saw installed")
        case .writtenRecently(let date):
            modified(date)
        case .writtenAfterItLeft(let name, let written):
            Text("Modified \(written, format: .relative(presentation: .named)), after Peel last saw \(name) installed, so something may still use these files")
        case .sameMakerStillInstalled:
            Text("An app from the same maker is still installed")
        case .appLeft(let name, let lastSeen):
            Text("Peel last saw \(name) installed \(lastSeen, format: .relative(presentation: .named))")
        case .untouched(let months):
            Text("Not modified in ^[\(months) month](inflect: true)")
        case .nothingClaimsIt:
            Text("No installed app claims these")
        case .installedForAnAppThatIsGone(let name):
            Text("macOS installed these for \(name), which is gone")
        case .startsAProgramThatIsGone:
            Text("These start a program that is no longer there")
        case .loadedByOtherApps:
            Text("Other apps can load these on their own, such as music apps")
        }
    }

    /// Orange only when Peel is unsure. Being sure is the usual case here and needs no color.
    var tint: Color? {
        level == .unsure ? .orange : nil
    }

    var systemImage: String {
        switch level {
        case .unsure: "exclamationmark.triangle"
        case .likely: "questionmark.circle"
        case .certain: "checkmark.seal"
        }
    }

}

extension URL {
    var abbreviatedPath: String {
        (path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
    }

    /// The whole path as Finder copies it: a folder's `path(percentEncoded:)` keeps the URL's slash at the end.
    var fullPath: String {
        let path = path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}

extension Int64 {
    var byteCount: String {
        ByteCounts.string(for: self)
    }
}

/// Remembers formatted byte counts. Formatting one is the most expensive step in drawing a row, and a long
/// list redraws many rows at a time.
///
/// `ByteCountFormatter` is faster but writes different strings ("Zero KB" and "999 bytes" where the format
/// style writes "Zero kB" and "1 kB"), so the format style is kept and its answers are cached.
@MainActor
private enum ByteCounts {
    private static var known: [Int64: String] = [:]
    /// The most answers kept, enough for a long list. When full, the cache is emptied rather than left to
    /// grow without bound.
    private static let limit = 8192
    private static var watchesLocale = false

    static func string(for value: Int64) -> String {
        watchLocale()
        if let text = known[value] { return text }
        if known.count >= limit { known.removeAll(keepingCapacity: true) }
        let text = value.formatted(.byteCount(style: .file))
        known[value] = text
        return text
    }

    /// Empties the cache when the locale changes. Reading the locale on every call would cost more than the
    /// lookup it guards.
    private static func watchLocale() {
        guard !watchesLocale else { return }
        watchesLocale = true
        NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in known.removeAll(keepingCapacity: true) }
        }
    }
}

extension Int64? {
    /// The size, or "Unknown" when it is not known, such as for a folder that did not answer in time. An
    /// unknown size never reads as zero.
    var byteCount: String {
        self?.byteCount ?? String(localized: "Unknown")
    }
}

extension SizeTotal {
    /// What VoiceOver hears of a page's total once its scan ends, as the page's header says it, or nil when nothing
    /// is to move.
    var spoken: AttributedString? {
        !isNothing ? AttributedString(localized: "\(text) can be moved to the Trash") : nil
    }

    var text: String {
        switch reading {
        case .exactly(let size): size.byteCount
        case .atLeast(let size): String(localized: "Over \(size.byteCount)")
        case .unknown: String(localized: "Unknown")
        }
    }

    /// The form `text` is in, used as the view's identity: within one form the digits roll, while a change to
    /// or from a word, or "Over" coming or going, fades instead.
    var textKind: String {
        guard known > 0 else { return text }
        return isComplete ? "exact" : "over"
    }
}

extension Int {
    /// A count in compact form, such as "12K", for a lifetime total where six digits would not fit.
    var shortCount: String {
        formatted(.number.notation(.compactName))
    }
}

extension LocalizedStringResource {
    /// "Excluded in Settings", said of an app. It has its own key because in Spanish, French, Romanian,
    /// Polish, and Czech the words agree with the feminine word for an app. The plain key is said of a file,
    /// a folder, or a package.
    static let excludedApp = LocalizedStringResource(
        "Excluded in Settings (app)", defaultValue: "Excluded in Settings",
        comment: "Shown for an app the user excluded in Settings. Use the form that agrees with the word for an app."
    )
}

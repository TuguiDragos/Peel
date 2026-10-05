import Foundation
@testable import PeelCore
import Testing

struct LaunchctlTests {
    /// Any process running as the user can choose a job's label, even one that starts with a space, `=>`, and
    /// a space. Such a label must not crash the parser, which every Background Items and Intel Software scan uses.
    @Test func aLabelThatLooksLikeTheArrowAfterItDoesNotCrashTheParser() {
        let output = "\tdisabled services = {\n\t\t\" => x\" => disabled\n\t\t\"com.example.agent\" => enabled\n\t}"
        let parsed = Launchctl.parseDisabled(output)

        #expect(parsed?[" => x"] == true)
        #expect(parsed?["com.example.agent"] == false)
    }

    /// A label can hold a line break, so a line inside the block can hold nothing but tabs.
    @Test func aLineOfOnlyTabsInsideTheBlockDoesNotCrashTheParser() {
        let output = "\tdisabled services = {\n\t\t\"com.example.x\n\t\t\n\" => disabled\n\t\t\"com.example.agent\" => enabled\n\t}"
        let parsed = Launchctl.parseDisabled(output)

        #expect(parsed?["com.example.agent"] == false)
    }

    @Test func parsesUserJobList() throws {
        let output = "PID\tStatus\tLabel\n-\t0\tcom.adguard.mac.adguard.loginhelper\n22251\t0\tapplication.com.example.jotter.22249290.22249296\n"
        let jobs = try #require(Launchctl.parseList(output))
        #expect(jobs.count == 2)
        #expect(jobs["com.adguard.mac.adguard.loginhelper"] == .some(nil))
        #expect(jobs["application.com.example.jotter.22249290.22249296"] == .some(22251))
    }

    /// An answer in a form Peel does not recognize is read as not known, never as no jobs at all.
    @Test func anAnswerInAnotherFormIsNotKnown() {
        #expect(Launchctl.parseList("Label\tPID\ncom.example.agent\t-\n") == nil)
        #expect(Launchctl.parseList("Could not connect to the domain.\n") == nil)
        #expect(Launchctl.parseSystemServices("system = {\n\tjobs = {\n\t}\n}\n") == nil)
        #expect(Launchctl.parseDisabled("Bad request.\n") == nil)
        #expect(Launchctl.parseDetails("Bad request.\nCould not find service \"x\" in domain for user gui: 501\n") == nil)
        #expect(Launchctl.parseDetails("gui/501/org.example.agent = {\n\tstate = not running\n}\n") == nil)

        #expect(Launchctl.parseList("PID\tStatus\tLabel\n") == [:])
        #expect(Launchctl.parseSystemServices("system = {\n\tservices = {\n\t}\n}\n") == [:])
        #expect(Launchctl.parseDisabled("\tdisabled services = {\n\t}\n") == [:])
    }

    @Test func parsesSystemServicesAndDisabledOverrides() {
        let output = """
        system = {
        \tservices = {
        \t\t       0      - \tcom.vix.cron
        \t\t     761      - \tcom.adguard.mac.adguard.helper
        \t\t    1414      - \tNetworkExtension.com.adguard.mac.adguard.network-extension.2.19.0.2258
        \t}
        \tendpoints = {
        \t\t"com.adguard.mac.adguard.helper.xpc" = {
        \t\t}
        \t}
        \tdisabled services = {
        \t\t"org.example.agent" => enabled
        \t\t"com.example.daemon" => disabled
        \t}
        }
        """
        let services = Launchctl.parseSystemServices(output)
        #expect(services?["com.vix.cron"] == .some(nil))
        #expect(services?["com.adguard.mac.adguard.helper"] == .some(761))

        let disabled = Launchctl.parseDisabled(output)
        #expect(disabled == ["org.example.agent": false, "com.example.daemon": true])
    }

    @Test func parsesJobDetails() throws {
        let output = """
        gui/501/com.adguard.mac.adguard.loginhelper = {
        \tactive count = 0
        \tpath = (submitted by smd.524)
        \ttype = Submitted
        \tmanaged_by = com.apple.xpc.ServiceManagement
        \tstate = not running
        \tparent bundle identifier = com.adguard.mac.adguard
        \tinherited environment = {
        \t\tSSH_AUTH_SOCK => /var/run/com.apple.launchd.EkT9pRd9Br/Listeners
        \t}
        }
        """
        let details = try #require(Launchctl.parseDetails(output))
        #expect(details.managedBy == "com.apple.xpc.ServiceManagement")
        #expect(details.parentBundleIdentifier == "com.adguard.mac.adguard")
        #expect(details.path == "(submitted by smd.524)")
    }

    @Test func tellsAJobThatLeftFromAnAnswerItCannotRead() {
        let printed = """
        gui/501/org.example.updater = {
        \tactive count = 0
        \tpath = (submitted by smd.332)
        \ttype = Submitted
        \tmanaged_by = com.apple.xpc.ServiceManagement
        \tstate = not running

        \tprogram identifier = Contents/Resources/Updater (mode: 2)
        \tparent bundle identifier = org.example.app
        \tparent bundle version = 0
        \tinherited environment = {
        \t\tSSH_AUTH_SOCK => /private/tmp/com.apple.launchd.example/Listeners
        \t}

        \tdomain = gui/501 [100023]
        \truns = 0
        \tlast exit code = (never exited)
        }
        """
        let read = Launchctl.JobDetails(
            path: "(submitted by smd.332)", managedBy: "com.apple.xpc.ServiceManagement",
            parentBundleIdentifier: "org.example.app"
        )

        #expect(Launchctl.answer(status: 0, output: printed) == .details(read))
        #expect(Launchctl.answer(status: 113, output: "Bad request.\nCould not find service \"x\" in domain\n") == .gone)
        #expect(Launchctl.answer(status: 0, output: "Bad request.\n") == .unreadable)
        #expect(Launchctl.answer(status: 112, output: "Bad request.\nCould not find domain for user gui: 9\n") == .unreadable)
    }

    /// Every Mac with someone logged in runs Finder as a job, so this is what `launchctl` really answers here.
    @Test func readsWhatThisMacsLaunchctlSays() async {
        let domain = "gui/\(getuid())"
        let finder = await Launchctl.run(["print", "\(domain)/com.apple.Finder"])
        let nobody = await Launchctl.run(["print", "\(domain)/org.example.nothing"])

        guard case .details(let details) = Launchctl.answer(status: finder.status, output: finder.output) else {
            Issue.record("launchctl's answer about Finder could not be read: \(finder.output.prefix(200))")
            return
        }
        #expect(details.path == "/System/Library/LaunchAgents/com.apple.Finder.plist")
        #expect(details.program == "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder")
        #expect(Launchctl.answer(status: nobody.status, output: nobody.output) == .gone)
    }

    @Test func readsJobDefinitions() throws {
        let job = try #require(JobDefinition([
            "Label": "com.example.helper",
            "ProgramArguments": ["/Library/Application Support/Example/helper", "--daemon"],
            "KeepAlive": ["SuccessfulExit": false],
            "AssociatedBundleIdentifiers": ["com.example.app"],
        ]))
        #expect(job.program == "/Library/Application Support/Example/helper")
        #expect(job.keepsAlive)
        // `man launchd.plist`: KeepAlive "implicitly implies RunAtLoad".
        #expect(job.runsAtLoad)
        #expect(job.associated == ["com.example.app"])
        #expect(JobDefinition(["Program": "/bin/true"]) == nil)
    }

    @Test func findsOwningAppFromProgramPath() throws {
        let directory = try TemporaryDirectory()
        let info = ["CFBundleIdentifier": "com.example.app", "CFBundleName": "Example"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: directory.file("Example.app/Contents/Info.plist"))
        let helper = directory.url.appending(path: "Example.app/Contents/MacOS/Helper").path(percentEncoded: false)

        #expect(BackgroundItemOwnership.bundleIdentifier(inProgramPath: helper) == "com.example.app")
        #expect(BackgroundItemOwnership.bundleIdentifier(inProgramPath: "/usr/bin/true") == nil)
    }
}

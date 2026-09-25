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

    /// `launchctl`'s output is not an interface and can change. An answer in a form Peel does not recognize says
    /// nothing about which jobs are loaded, so it is read as not known rather than as no jobs at all.
    @Test func anAnswerInAnotherFormIsNotKnown() {
        #expect(Launchctl.parseList("Label\tPID\ncom.example.agent\t-\n") == nil)
        #expect(Launchctl.parseList("Could not connect to the domain.\n") == nil)
        #expect(Launchctl.parseSystemServices("system = {\n\tjobs = {\n\t}\n}\n") == nil)
        #expect(Launchctl.parseDisabled("Bad request.\n") == nil)

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
        \t\t"com.piriform.ccleaner.uninstall" => enabled
        \t\t"com.example.daemon" => disabled
        \t}
        }
        """
        let services = Launchctl.parseSystemServices(output)
        #expect(services?["com.vix.cron"] == .some(nil))
        #expect(services?["com.adguard.mac.adguard.helper"] == .some(761))

        let disabled = Launchctl.parseDisabled(output)
        #expect(disabled == ["com.piriform.ccleaner.uninstall": false, "com.example.daemon": true])
    }

    @Test func parsesJobDetails() {
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
        let details = Launchctl.parseDetails(output)
        #expect(details.managedBy == "com.apple.xpc.ServiceManagement")
        #expect(details.parentBundleIdentifier == "com.adguard.mac.adguard")
        #expect(details.path == "(submitted by smd.524)")
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

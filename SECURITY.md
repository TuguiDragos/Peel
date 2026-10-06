# Security

This is Peel's security policy: how to report a vulnerability, what happens after, and what is in scope. What Peel
protects, and how, has a page of its own: [SAFETY.md](SAFETY.md).

## Reporting a security problem

Email **contact@tuguidragos.com**. Put "Peel security" in the subject line.

Do not open a public issue, a discussion, or a pull request for a security bug. Do not post it
anywhere public until we have agreed on a date.

Please include, as much as you have:

- The version of Peel and the build number, from About.
- Your macOS version and whether the Mac is Apple silicon or Intel.
- Which component: the app, the privileged helper, the Finder extension, or the `peel` CLI.
- What an attacker gains, and what they need to start with. State plainly whether the attack
  needs a local unprivileged process, an admin account, or a user action.
- Steps to reproduce, and a proof of concept if you have one. A short script or a small sample
  app is worth more than a description.
- Anything you want credited, or that you would rather stay anonymous.

Send it in plain text. Attachments are fine. Encryption is available on request; there is no
published key yet, so ask and one will be set up before you send anything sensitive.

If you get no reply within 5 days, resend. Mail gets lost, and a solo maintainer is a single
point of failure.

## What you can expect

| Stage | Target |
| --- | --- |
| Acknowledgment that the mail arrived | 2 working days |
| First assessment: confirmed, not confirmed, or need more detail | 7 days |
| Fix released for a confirmed high-severity issue | 30 days |
| Fix released for anything else confirmed | 90 days |
| Public disclosure | when the fix ships, or 90 days from your report, whichever is first |

These are targets, not contractual promises. If a fix is going to be late, you will be told why
and given a new date, not silence.

## Coordinated disclosure

Peel follows coordinated disclosure.

- You report privately. The issue stays private while it is fixed.
- **90 days** after your report, you are free to publish, whether or not a fix exists. You do not
  need permission, and asking for an extension is a request, not a condition. 90 days is the
  longest deadline in common use: CERT/CC publishes 45 days after a report, and CISA may publish
  45 days after first trying to reach a vendor that does not answer.
- If the bug is being exploited in the wild, that clock is not useful. Say so in your report: the
  fix and the advisory then go out as fast as they can be built, and disclosure happens early on
  purpose, so people can protect themselves.
- If you need longer than 90 days for your own reasons, say so, and that is respected.
- The advisory names you as the reporter, with a link if you want one, unless you ask not to be
  named. That is the default, not a favor.

There is no bug bounty. There is no money. There is credit, a fast fix, and a straight answer.

## Supported versions

Peel is a single line of releases. Only the latest release gets security fixes.

| Version | Supported |
| --- | --- |
| Latest release | Yes |
| Anything older | No: update |

There are no long-term support branches and there will not be any. If you are on an older
build, the fix is to update.

Peel requires macOS 26 or later. Issues that only reproduce on an unsupported macOS version
are out of scope.

## Scope

Peel is not sandboxed and is distributed outside the Mac App Store. Releases are signed with a Developer ID and
notarized by Apple. It has four pieces:

- **Peel.app**: the interface, running as you.
- **com.tuguidragos.Peel.Helper**: a system daemon registered with `SMAppService`, running as
  **root**, reachable only over an XPC Mach service.
- **PeelFinder**: a sandboxed Finder Sync extension that opens `peel://open?path=`.
- **peel**: a command line tool inside `Peel.app/Contents/Helpers`. It never talks to the helper.

### In scope

Anything that gets code or file operations to run with privileges the attacker did not already
have, and anything that destroys data that cannot be recovered.

**The privileged helper.** This is the part that matters most.

- Any way for a process that is not the installed copy of Peel to get the helper to act. That
  includes defeating the code-signing requirement on the XPC peer, or replaying or forging a
  connection.
- Any way to get the helper to act for an account that is not an administrator. Every account on the
  Mac can reach its Mach service, by design; the helper answers administrators only, checked when a
  connection opens and again with each message.
- Any way to get the helper to touch a path outside the locations `PrivilegedPathPolicy` allows:
  path traversal, `..` handling, symlink or hardlink following, mount tricks, firmlinks, or a
  race between the check and the file operation (TOCTOU).
- Any way to use the restore path to write attacker-controlled content into a location that a
  root process later loads code from.
- Downgrade attacks: getting the helper to answer a copy of Peel other than the one it was
  installed beside, or getting an older or unsigned build accepted.
- Argument injection or unexpected behavior in the operation that runs `launchctl` for a launch
  daemon (bootstrap, bootout, kickstart, enable, and disable), or in the one that moves the helper's
  own ledger to the Trash for Remove Peel.
- Anything that leaves a root daemon installed, running, or reachable after Peel is removed, or
  that lets a non-admin install or replace it.

**Destruction of data.**

- Any way to get Peel to delete something permanently that it should have moved to the Trash. The
  few things Peel deletes, or can't undo, by design are listed in
  [SAFETY.md](SAFETY.md#nothing-of-yours-is-deleted-permanently).
- Any bypass of `RemovalGuard` that reaches anything [SAFETY.md](SAFETY.md) lists under "What Peel will never
  remove".
- Any bypass of the user's Exclusions.
- App Reset touching anything it did not list, taking an app's own data (its `Application Support`
  folder, group containers, or application scripts) without being asked, or touching a container's
  `Documents` or `Autosave Information`.
- Duplicates taking the last remaining copy of a group.

**The other components.**

- Path injection, argument injection, or unintended navigation through the `peel://` URL scheme,
  from the Finder extension, from any other process on the Mac, or from a web page, and through
  Peel's other ways in: an app dropped on it or opened with it, and the actions it gives Shortcuts.
- A sandbox escape in the Finder Sync extension.
- Hijacking the `peel` CLI, or getting it to perform an operation that should require the helper.
- Update-feed handling: Peel fetches update feeds whose addresses come out of each scanned app, a
  Sparkle feed in its `Info.plist` or an Electron app's `app-update.yml`, and for an update that
  waits, the page of release notes the feed names, which it reads as HTML, Markdown, or plain text.
  A malicious feed or page that causes memory corruption, an exploitable crash, a file write, or
  code execution, or that leaks data off the Mac, is in scope.
- Leaking the list of a user's installed apps, file paths, or scan results off the Mac, beyond what
  [PRIVACY.md](PRIVACY.md) describes.

**What Peel reads, runs, and writes.**

- Files from apps and disks Peel doesn't trust, which it reads to decide what is what: other apps'
  property lists, the headers of their programs (Mach-O), and the directory of a ZIP archive, read
  without extracting it. One that causes memory corruption, an exploitable crash, or a wrong answer
  about what may be removed is in scope.
- The programs Peel runs with what a scan found: `defaults`, `launchctl`, and `tccutil`, given an
  app's identifier or a launch job's label, and `brew`, including one chosen in Settings. Getting
  one to run with arguments an attacker chose, or getting Peel to run another program, is in scope.
- What Peel writes besides moving files: the Tweaks, which also restart the Dock, Finder, Control
  Center, or Window Manager with `killall`, and the settings the Terminal page writes for Terminal,
  the shell, ssh, and Git. Getting either to write anything but the setting the user chose, or to
  write it anywhere else, such as through a link, is in scope.

### Out of scope

Not because they do not matter, but because they are not bugs in Peel.

- **Anything that needs root to begin with.** If the attacker is already root, they can do all of
  this without Peel.
- **Anything an administrator can already do on macOS.** `/Applications` is writable by any
  admin by design. An admin who can already delete an app has gained nothing by using Peel to
  delete it. Escalation from *admin* to *root without an authentication prompt* is in scope, beyond
  what the helper does for an administrator by design once it is approved: moving items in the
  folders `PrivilegedPathPolicy` allows to the Trash and back, and running `launchctl` for another
  developer's launch daemon. Admin doing admin things is not.
- **Peel deleting what the user told it to delete.** The confirmation, the preselection rules, and
  the Trash are the safety net. A user who selects a checkbox and confirms is not a vulnerability. A
  bug that makes Peel select the checkbox *for* them, or that removes something not shown, is.
- **Bugs in macOS itself.** Report those to Apple at <https://security.apple.com/submit/>. See
  <https://support.apple.com/en-us/102549>. They are not fixable here.
- **Bugs in third-party apps that Peel merely lists, scans, or reports on.** Report those to the
  app's own developer.
- **Physical access, evil-maid, and unlocked-Mac scenarios.**
- **Social engineering** of users, of the developer, or of anyone else.
- **Self-inflicted configurations**: SIP disabled, Gatekeeper disabled, a modified or re-signed
  build of Peel, running as root on purpose.
- **Missing hardening with no exploit path.** Peel is deliberately not sandboxed: it has to read
  the whole disk to do its job. A report saying "not sandboxed", "hardened runtime flag X is
  absent", or "library validation could be stricter" needs a working attack to be actionable.
- **Automated scanner output with no proof of concept.**
- **Denial of service** that only affects the person running Peel, and filling your own disk.
- **The tuguidragos.com website.** Separate thing. Email the same address, but do not expect it
  to be treated as a Peel report.

If you are not sure which side of the line something falls on, send it. Getting it wrong in the
direction of reporting is the right mistake.

## Testing rules

Test on a Mac you own, with data you can afford to lose. Use a virtual machine if you can.

Do not test against other people's machines. Do not access, copy, or keep anyone else's data. If
you hit real personal data during testing, stop, delete what you have, and say so in the report.
Do not run anything that degrades service for other people. Do not use a finding to extort.

## Safe harbor

If you follow this policy in good faith:

- Your research is authorized. No legal action will be initiated or supported against you for
  accidental, good-faith violations of this policy.
- No claim will be brought against you for circumventing technical controls in Peel in the course
  of that research.
- If a third party takes legal action against you for work done in compliance with this policy,
  it will be made known that your actions were authorized.

Two limits, stated plainly because pretending otherwise would be dishonest:

- This only covers claims that are the maintainer's to bring. It does not bind Apple, does not
  bind the developers of any other app you touch while testing, and does not bind anyone else.
- It does not override the law. You are still expected to comply with it.

If you are uncertain whether something you are about to do is covered, ask by email first.

This safe harbor is adapted from the disclose.io model terms, which are published under CC0:
<https://github.com/disclose/dioterms>.

## Advisories and CVEs

Fixed issues are written up as an advisory in the release notes.

If an issue warrants one, a CVE will be requested. Once the source repository is public on
GitHub, that goes through GitHub Security Advisories: GitHub is a CVE Numbering Authority for
open source projects hosted on GitHub. You are welcome to request the CVE yourself instead, and
to be named in the record; say so in your report. If you would rather not wait, MITRE also takes
requests directly.

## Contact

**contact@tuguidragos.com**

One person reads that mailbox. English only.

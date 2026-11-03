public import Foundation
import PeelPrivileged
import Security

/// One administrator's approval for one action of an account that isn't an administrator: asked for when the action
/// first needs the helper, carried by each of its requests, and destroyed once the action ends.
actor AdministratorConsent {
    struct Approval: Sendable {
        let form: Data
        let destroy: @Sendable () -> Void
    }

    private let isAdministrator: @Sendable () async -> Bool
    private let ask: @Sendable () async -> Approval?
    private var answer: Task<Approval?, Never>?

    init(
        isAdministrator: @escaping @Sendable () async -> Bool = { await PrivilegedHelper.isAdministratorNow() },
        ask: @escaping @Sendable () async -> Approval? = { await AdministratorConsent.askAnAdministrator() }
    ) {
        self.isAdministrator = isAdministrator
        self.ask = ask
    }

    /// What each request of the action carries: nothing from an administrator, whom the helper serves as one, and
    /// otherwise the approval an administrator gave, asked for the first time it is needed. Nil when none gave it.
    func approval() async -> Data? {
        let answer = self.answer ?? Task { [isAdministrator, ask] in
            await isAdministrator() ? Approval(form: Data(), destroy: {}) : await ask()
        }
        self.answer = answer
        return await answer.value?.form
    }

    /// Destroys the approval, so nothing can use it once the action is over.
    func end() async {
        await answer?.value?.destroy()
    }

    /// Asks for an administrator's name and password in macOS's own window, on a thread of its own, since the window
    /// holds the thread until it closes.
    static func askAnAdministrator(prompt: String? = PrivilegedHelper.consentPrompt) async -> Approval? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: approvalFromAnAdministrator(prompt: prompt))
            }
        }
    }

    private static func approvalFromAnAdministrator(prompt: String?) -> Approval? {
        var made: AuthorizationRef?
        guard AuthorizationCreate(nil, nil, [], &made) == errAuthorizationSuccess, let made else { return nil }
        let authorization = Authorization(made)
        // Pre-authorized, the approval holds in the helper, which checks it without asking anybody.
        let flags: AuthorizationFlags = [.interactionAllowed, .extendRights, .preAuthorize]
        let status = AdministratorAuthorization.withRight { rights in
            withEnvironment(prompt) { AuthorizationCopyRights(made, &rights, $0, flags, nil) }
        }
        var external = AuthorizationExternalForm()
        guard status == errAuthorizationSuccess,
              AuthorizationMakeExternalForm(made, &external) == errAuthorizationSuccess
        else {
            authorization.destroy()
            return nil
        }
        return Approval(form: withUnsafeBytes(of: &external) { Data($0) }, destroy: authorization.destroy)
    }

    private static func withEnvironment<T>(
        _ prompt: String?, _ body: (UnsafePointer<AuthorizationEnvironment>?) -> T
    ) -> T {
        guard let prompt else { return body(nil) }
        return kAuthorizationEnvironmentPrompt.withCString { name in
            var text = Array(prompt.utf8)
            return text.withUnsafeMutableBytes { bytes in
                var item = AuthorizationItem(name: name, valueLength: bytes.count, value: bytes.baseAddress, flags: 0)
                return withUnsafeMutablePointer(to: &item) { pointer in
                    var environment = AuthorizationEnvironment(count: 1, items: pointer)
                    return body(&environment)
                }
            }
        }
    }

    /// An authorization, which macOS keeps until it is freed, from any thread.
    private final class Authorization: @unchecked Sendable {
        private let reference: AuthorizationRef

        init(_ reference: AuthorizationRef) {
            self.reference = reference
        }

        func destroy() {
            AuthorizationFree(reference, [.destroyRights])
        }
    }
}

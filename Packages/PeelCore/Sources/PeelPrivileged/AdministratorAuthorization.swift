public import Foundation
public import Security

/// An administrator's approval of what an account that isn't one asks the helper for. Peel asks for it, macOS shows
/// its own window for an administrator's name and password, and the helper checks it without asking anybody.
public enum AdministratorAuthorization {
    /// The right Peel asks an administrator for. macOS defines it, so no process of a standard account can define it
    /// as granted to anybody, and it keeps an approval in that one authorization alone, for five minutes
    /// (`security authorizationdb read system.privilege.admin`).
    public static let right = kAuthorizationRightExecute

    /// Whether `form`, an authorization's external form, holds an administrator's approval now.
    public static func isGranted(by form: Data) -> Bool {
        guard form.count == Int(kAuthorizationExternalFormLength) else { return false }
        var external = AuthorizationExternalForm()
        withUnsafeMutableBytes(of: &external) { _ = form.copyBytes(to: $0) }
        var authorization: AuthorizationRef?
        guard AuthorizationCreateFromExternalForm(&external, &authorization) == errAuthorizationSuccess,
              let authorization
        else { return false }
        defer { AuthorizationFree(authorization, []) }
        // Without `interactionAllowed`, macOS shows nothing and answers only from what the authorization holds.
        return withRight { rights in
            AuthorizationCopyRights(authorization, &rights, nil, [.extendRights], nil) == errAuthorizationSuccess
        }
    }

    /// Runs `body` with a set of rights holding `right` alone.
    public static func withRight<T>(_ body: (inout AuthorizationRights) -> T) -> T {
        right.withCString { name in
            var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { pointer in
                var rights = AuthorizationRights(count: 1, items: pointer)
                return body(&rights)
            }
        }
    }
}

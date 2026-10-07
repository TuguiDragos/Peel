import Foundation
import PeelPrivileged

// Clients must be signed by the helper's own team and be no older a build than the helper, so an older copy of Peel
// is never served. A helper with no team (unsigned or ad hoc) or no signed build does not run.
guard let teamIdentifier = CodeSigning.currentTeamIdentifier(), let build = CodeSigning.currentBuild else {
    exit(EXIT_FAILURE)
}

let requirement = CodeSigning.requirement(
    identifier: HelperIdentity.appIdentifier,
    teamIdentifier: teamIdentifier,
    minimumBuild: build
)
let listener = NSXPCListener(machServiceName: HelperIdentity.machServiceName)
listener.setConnectionCodeSigningRequirement(requirement)
let lifetime = HelperLifetime()
let delegate = HelperListenerDelegate(lifetime: lifetime, codeSigningRequirement: requirement)
listener.delegate = delegate
listener.resume()
lifetime.start()
dispatchMain()

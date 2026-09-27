import Foundation
import PeelPrivileged

// Clients must be signed by the helper's own team, so a helper with no team (unsigned or ad hoc) does not run.
guard let teamIdentifier = CodeSigning.currentTeamIdentifier() else {
    exit(EXIT_FAILURE)
}

let requirement = CodeSigning.requirement(identifier: HelperIdentity.appIdentifier, teamIdentifier: teamIdentifier)
let listener = NSXPCListener(machServiceName: HelperIdentity.machServiceName)
listener.setConnectionCodeSigningRequirement(requirement)
let lifetime = HelperLifetime()
let delegate = HelperListenerDelegate(lifetime: lifetime, codeSigningRequirement: requirement)
listener.delegate = delegate
listener.resume()
lifetime.start()
dispatchMain()

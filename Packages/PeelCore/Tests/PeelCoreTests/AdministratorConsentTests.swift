import Foundation
@testable import PeelCore
import Synchronization
import Testing

private final class Asked: Sendable {
    private let counts = Mutex((asked: 0, destroyed: 0))

    func ask() { counts.withLock { $0.asked += 1 } }
    func destroy() { counts.withLock { $0.destroyed += 1 } }
    var asked: Int { counts.withLock { $0.asked } }
    var destroyed: Int { counts.withLock { $0.destroyed } }
}

struct AdministratorConsentTests {
    private let form = Data(repeating: 9, count: 32)

    private func consent(isAdministrator: Bool, granting: Bool = true, _ asked: Asked) -> AdministratorConsent {
        let form = form
        return AdministratorConsent(isAdministrator: { isAdministrator }) {
            asked.ask()
            return granting ? AdministratorConsent.Approval(form: form) { asked.destroy() } : nil
        }
    }

    @Test func asksOnceForEveryRequestOfAnAction() async {
        let asked = Asked()
        let consent = consent(isAdministrator: false, asked)

        async let first = consent.approval()
        async let second = consent.approval()
        let forms = await [first, second, consent.approval()]

        #expect(forms == [form, form, form])
        #expect(asked.asked == 1)
        await consent.end()
        #expect(asked.destroyed == 1)
    }

    @Test func anAdministratorIsNeverAsked() async {
        let asked = Asked()
        let consent = consent(isAdministrator: true, asked)

        #expect(await consent.approval() == Data())
        await consent.end()

        #expect(asked.asked == 0)
        #expect(asked.destroyed == 0)
    }

    @Test func noApprovalWhenNoAdministratorGivesOne() async {
        let asked = Asked()
        let consent = consent(isAdministrator: false, granting: false, asked)

        #expect(await consent.approval() == nil)
        #expect(await consent.approval() == nil)
        #expect(asked.asked == 1)
    }

    @Test func anActionWithinAnotherUsesItsApproval() async {
        let outer = Asked()
        let inner = Asked()

        let carried = await PrivilegedHelper.withOneConsent(consent(isAdministrator: false, outer)) {
            await PrivilegedHelper.withOneConsent(consent(isAdministrator: false, inner)) {
                await PrivilegedHelper.consent?.approval()
            }
        }

        #expect(carried == form)
        #expect(outer.asked == 1)
        #expect(inner.asked == 0)
        #expect(outer.destroyed == 1)
    }

    @Test func theApprovalIsDestroyedWhenTheActionEnds() async {
        let asked = Asked()

        await PrivilegedHelper.withOneConsent(consent(isAdministrator: false, asked)) {
            _ = await PrivilegedHelper.consent?.approval()
            #expect(asked.destroyed == 0)
        }

        #expect(asked.destroyed == 1)
    }
}

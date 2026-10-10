import SwiftUI

/// The alert that says why a change of the helper failed, shown only by the place that asked for the change.
private struct HelperFailureAlert: ViewModifier {
    @Binding var failure: HelperModel.Failure?

    func body(content: Content) -> some View {
        content.alert(failure?.title ?? Text(verbatim: ""), isPresented: isShowingFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: failure?.reason ?? "")
        }
    }

    private var isShowingFailure: Binding<Bool> {
        Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
    }
}

extension HelperModel.Failure {
    fileprivate var title: Text {
        switch action {
        case .install: Text("The helper couldn’t be installed.")
        case .repair: Text("The helper couldn’t be repaired.")
        case .uninstall: Text("The helper couldn’t be uninstalled.")
        }
    }
}

extension View {
    func helperFailureAlert(_ failure: Binding<HelperModel.Failure?>) -> some View {
        modifier(HelperFailureAlert(failure: failure))
    }
}

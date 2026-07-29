import AppKit
import SwiftUI

/// Shared confirmation prompts used from more than one view, so the copy can't drift out of sync.
extension View {
    func endMeetingConfirmation(isPresented: Binding<Bool>, onConfirm: @escaping () -> Void) -> some View {
        confirmationDialog("Encerrar transcrição?", isPresented: isPresented, titleVisibility: .visible) {
            Button("Encerrar", role: .destructive, action: onConfirm)
            Button("Continuar gravando", role: .cancel) {}
        } message: {
            Text("A transcrição será salva. Você pode retomá-la depois abrindo a reunião.")
        }
    }

    func deleteMeetingConfirmation(isPresented: Binding<Bool>, title: String, onConfirm: @escaping () -> Void) -> some View {
        alert("Excluir reunião?", isPresented: isPresented) {
            Button("Excluir", role: .destructive, action: onConfirm)
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("“\(title)” será excluída permanentemente. Esta ação não pode ser desfeita.")
        }
    }
}

/// `.confirmationDialog`/`.sheet` don't reliably present from a `MenuBarExtra(.window)` panel: it's a
/// non-activating auxiliary window, so SwiftUI's dialog either fails to show or the panel resigns key
/// and dismisses itself before the user can respond (known SwiftUI limitation, no native fix as of
/// macOS 26). `NSAlert` opens its own real modal session instead, unaffected by the panel's lifecycle.
enum MenuBarConfirmation {
    @MainActor
    static func confirmEndMeeting(onConfirm: () -> Void) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Encerrar transcrição?")
        alert.informativeText = String(localized: "A transcrição será salva. Você pode retomá-la depois abrindo a reunião.")
        alert.alertStyle = .warning
        let end = alert.addButton(withTitle: String(localized: "Encerrar"))
        end.hasDestructiveAction = true
        alert.addButton(withTitle: String(localized: "Continuar gravando"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            onConfirm()
        }
    }
}

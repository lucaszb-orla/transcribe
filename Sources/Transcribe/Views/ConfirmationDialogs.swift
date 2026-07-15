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

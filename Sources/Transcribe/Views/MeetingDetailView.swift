import SwiftUI

struct MeetingDetailView: View {
    @Environment(AppState.self) private var appState
    @State var meeting: Meeting

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Título", text: $meeting.title)
                    .font(.title2.bold())
                    .textFieldStyle(.plain)

                if !meeting.participants.isEmpty {
                    Text(meeting.participants.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !meeting.summaryBullets.isEmpty {
                    section("Resumo") {
                        ForEach(meeting.summaryBullets, id: \.self) { bullet in
                            Label(bullet, systemImage: "circle.fill")
                                .imageScale(.small)
                        }
                    }
                }

                if !meeting.actionItems.isEmpty {
                    section("Ações") {
                        ForEach(meeting.actionItems, id: \.self) { item in
                            Label(item, systemImage: "checkmark.circle")
                        }
                    }
                }

                section("Transcrição") {
                    TextEditor(text: $meeting.editableTranscriptText)
                        .font(.body)
                        .frame(minHeight: 300)
                }
            }
            .padding()
        }
        .toolbar {
            ToolbarItem {
                Button("Salvar") {
                    try? appState.store.save(meeting)
                }
            }
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }
}

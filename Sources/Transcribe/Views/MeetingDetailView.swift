import SwiftUI

struct MeetingDetailView: View {
    @Environment(AppState.self) private var appState
    @State var meeting: Meeting

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TextField("Título", text: $meeting.title)
                    .font(.title2.bold())
                    .textFieldStyle(.plain)

                if !meeting.participants.isEmpty {
                    Label(meeting.participants.joined(separator: ", "), systemImage: "person.2")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !meeting.summaryBullets.isEmpty {
                    GroupBox("Resumo") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(meeting.summaryBullets, id: \.self) { bullet in
                                Label(bullet, systemImage: "circle.fill")
                                    .imageScale(.small)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                    }
                }

                if !meeting.actionItems.isEmpty {
                    GroupBox("Ações") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(meeting.actionItems, id: \.self) { item in
                                Label(item, systemImage: "checkmark.circle")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                    }
                }

                GroupBox("Transcrição") {
                    TextEditor(text: $meeting.editableTranscriptText)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 300)
                        .padding(.top, 4)
                }
            }
            .padding()
        }
        .toolbar {
            ToolbarItem {
                Button("Salvar", systemImage: "square.and.arrow.down") {
                    try? appState.store.save(meeting)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }
    }
}

import SwiftUI
import VampCore

/// The prompt box, with the backend and model picker beside the send button.
struct PromptComposer: View {
    @EnvironmentObject private var app: AppModel
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Describe the change you want to hear…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .lineLimit(1...6)
                .focused($focused)
                .onSubmit(send)
                .disabled(app.isAgentWorking)

            HStack(spacing: 8) {
                Menu {
                    ForEach(BackendKind.allCases) { kind in
                        SwiftUI.Section(kind.label) {
                            ForEach(kind.models, id: \.id) { option in
                                Button {
                                    app.backend = kind
                                    app.model = option.id
                                } label: {
                                    if app.backend == kind && app.model == option.id {
                                        Label(option.label, systemImage: "checkmark")
                                    } else {
                                        Text(option.label)
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    Label(currentLabel, systemImage: app.backend == .anthropicAPI ? "key.fill" : "person.crop.circle")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .foregroundStyle(Theme.muted)
                .help(app.backend.detail)

                Spacer()

                if app.isAgentWorking {
                    Button { app.cancelAgent() } label: {
                        Image(systemName: "stop.circle.fill").font(.system(size: 24))
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.muted).help("Stop the agent")
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 24))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(text.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.faint : Theme.accent)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Send (⌘↩)")
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.window))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(focused ? Theme.accent.opacity(0.5) : Theme.line))
        .padding(12)
        .onAppear { focused = true }
    }

    private var currentLabel: String { app.backend.displayName(model: app.model) }

    private func send() {
        guard !app.isAgentWorking else { return }
        app.send(text)
        text = ""
    }
}

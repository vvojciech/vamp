import SwiftUI
import VampCore

/// Choose where the agent runs and store the optional API key.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var apiKey = Keychain.apiKey ?? ""
    @State private var saved = false

    var body: some View {
        Form {
            Section("Agent") {
                Picker("Backend", selection: Binding(get: { app.backend }, set: { app.backend = $0 })) {
                    ForEach(BackendKind.allCases) { Text($0.label).tag($0) }
                }
                Text(app.backend.detail).font(.callout).foregroundStyle(.secondary)
                ForEach([("claude", BackendKind.claudeCLI), ("codex", BackendKind.codexCLI)], id: \.0) { tool, kind in
                    LabeledContent(kind.label) {
                        if let path = CLI.locate(tool) {
                            Label(path.path, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Label("\(tool) CLI not found", systemImage: "xmark.circle").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Anthropic API") {
                SecureField("API key", text: $apiKey, prompt: Text("sk-ant-…"))
                HStack {
                    Text("Stored in your login keychain.").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button(saved ? "Saved" : "Save key") {
                        Keychain.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        saved = true
                    }
                    .disabled(saved)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .onChange(of: apiKey) { saved = false }
    }
}

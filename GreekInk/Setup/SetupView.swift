import SwiftUI

/// Enable-keyboard steps, model status, the copy of the model the keyboard uses, diagnostics.
struct SetupView: View {
    @ObservedObject var service: InkRecognitionService
    @ObservedObject var exporter: KeyboardModelExporter
    @State private var storageReport = ""

    var body: some View {
        List {
            Section {
                Text("1. Settings → General → Keyboard → Keyboards → Add New Keyboard…")
                Text("2. Under Third-Party Keyboards pick “GreekInk”.")
                Text("3. In any text field, tap or hold the 🌐 key and choose GreekInk.")
            } header: {
                Text("Enable the keyboard")
            } footer: {
                Text("“Allow Full Access” is not needed: the keyboard uses the model this app downloads.")
            }

            Section("Recognition models") {
                ForEach(InkLanguage.allCases) { language in
                    HStack {
                        Text(language.label)
                        Spacer()
                        Text((service.modelStates[language] ?? .notDownloaded).label)
                            .foregroundStyle(.secondary)
                        if service.modelStates[language] == .downloaded {
                            Button("Delete", role: .destructive) { service.delete(language) }
                        } else if service.modelStates[language] != .downloading {
                            Button("Download") { service.download(language) }
                        }
                    }
                }
            }

            Section {
                LabeledContent("Shared copy", value: exporter.summary)
                Button("Copy model for keyboard") { exporter.export(service: service) }
                    .disabled(!InkLanguage.allCases.contains { service.modelStates[$0] == .downloaded })
                if !exporter.message.isEmpty {
                    Text(exporter.message).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Model for the keyboard")
            } footer: {
                Text("Copied automatically whenever a model is downloaded or deleted. The keyboard picks up the new copy the next time it opens.")
            }

            Section("Model storage (where ML Kit put the files)") {
                Text(storageReport.isEmpty ? "Tap Refresh" : storageReport)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
                Button("Refresh") { storageReport = ModelStorageInspector.report() }
            }

            Section("Memory (app)") {
                Text(MemoryFootprint.summary()).font(.caption.monospaced())
            }
        }
    }
}

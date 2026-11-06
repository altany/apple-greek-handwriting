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

            Section {
                ForEach(InkLanguage.allCases) { language in
                    modelRow(language.label, tag: language.rawValue)
                }
                modelRow("Gestures (test)", tag: InkModelTag.greekGestures)
            } header: {
                Text("Recognition models")
            } footer: {
                Text("Gestures: Phase 3 test. The keyboard logs what this model makes of your strokes (e.g. a scribble), nothing more yet.")
            }

            Section {
                LabeledContent("Shared copy", value: exporter.summary)
                Button("Copy model for keyboard") { exporter.export(service: service) }
                    .disabled(service.downloadedTags().isEmpty)
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

    private func modelRow(_ label: String, tag: String) -> some View {
        let state = service.states[tag] ?? .notDownloaded
        return HStack {
            Text(label)
            Spacer()
            Text(state.label).foregroundStyle(.secondary)
            if state == .downloaded {
                Button("Delete", role: .destructive) { service.delete(tag: tag) }
            } else if state != .downloading {
                Button("Download") { service.download(tag: tag) }
            }
        }
    }
}

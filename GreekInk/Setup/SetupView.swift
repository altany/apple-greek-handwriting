import SwiftUI

/// Setup steps, App Group test (Phase 0) and model storage report.
struct SetupView: View {
    @ObservedObject var service: InkRecognitionService
    @State private var log: [String] = []
    @State private var storageReport = ""

    var body: some View {
        List {
            Section("Enable the keyboard") {
                Text("1. Settings → General → Keyboard → Keyboards → Add New Keyboard…")
                Text("2. Under Third-Party Keyboards pick “GreekInk”.")
                Text("3. In any text field, hold the 🌐 key and choose GreekInk.")
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

            Section("Model storage (where ML Kit put the files)") {
                Text(storageReport.isEmpty ? "Tap Refresh" : storageReport)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
                Button("Refresh") { storageReport = ModelStorageInspector.report() }
            }

            Section("App Group test") {
                LabeledContent("Group", value: AppGroup.identifier)
                LabeledContent("Container", value: AppGroup.containerURL?.path ?? "nil (not granted)")
                    .font(.caption)
                Button("Write ping from app") { append(AppGroup.writePing(from: "app")) }
                Button("Read ping") { append(AppGroup.readPing()) }
            }

            Section("Memory (app)") {
                Text(MemoryFootprint.summary()).font(.caption.monospaced())
            }

            if !log.isEmpty {
                Section("Log") {
                    ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption.monospaced())
                    }
                    Button("Clear log", role: .destructive) { log.removeAll() }
                }
            }
        }
    }

    private func append(_ line: String) {
        log.insert("\(AppGroup.timestamp()) \(line)", at: 0)
    }
}

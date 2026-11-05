import SwiftUI

/// Phase 0 host app: setup steps + App Group test.
struct ContentView: View {
    @State private var log: [String] = []

    var body: some View {
        NavigationStack {
            List {
                Section("Enable the keyboard") {
                    Text("1. Settings → General → Keyboard → Keyboards → Add New Keyboard…")
                    Text("2. Under Third-Party Keyboards pick “GreekInk”.")
                    Text("3. In any text field, hold the 🌐 key and choose GreekInk.")
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
            .navigationTitle("GreekInk — Phase 0")
        }
    }

    private func append(_ line: String) {
        log.insert("\(AppGroup.timestamp()) \(line)", at: 0)
    }
}

#Preview {
    ContentView()
}

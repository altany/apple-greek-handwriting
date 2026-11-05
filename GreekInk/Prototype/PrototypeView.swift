import SwiftUI

/// Phase 1 screen: write, see candidates, copy. Judge the recogniser.
struct PrototypeView: View {
    @ObservedObject var vm: PrototypeViewModel
    @ObservedObject var service: InkRecognitionService
    @ObservedObject var log: MisreadLog

    @State private var showMisreadSheet = false

    var body: some View {
        VStack(spacing: 12) {
            header
            InkCanvas(view: vm.canvas)
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
            candidateRow
            actionRow
            Text(vm.status)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            misreadList
        }
        .padding()
        .onAppear { vm.onAppear() }
        .sheet(isPresented: $showMisreadSheet) {
            MisreadSheet(topCandidate: vm.candidates.first?.text ?? "") { expected in
                vm.logMisread(expected: expected)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Picker("Language", selection: $vm.language) {
                ForEach(InkLanguage.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)

            modelStatus

            Spacer()

            Button {
                vm.recognizeNow()
            } label: {
                Label("Recognise", systemImage: "text.viewfinder")
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.strokeCount == 0 || vm.isRecognizing)
        }
    }

    @ViewBuilder
    private var modelStatus: some View {
        let state = service.modelStates[vm.language] ?? .notDownloaded
        HStack(spacing: 6) {
            switch state {
            case .downloaded:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Model ready")
            case .downloading:
                ProgressView().controlSize(.small)
                Text("Downloading model…")
            case .notDownloaded:
                Image(systemName: "arrow.down.circle")
                Text("Model not downloaded")
                Button("Download") { service.download(vm.language) }
            case .failed(let why):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Download failed: \(why)").lineLimit(1)
                Button("Retry") { service.download(vm.language) }
            }
        }
        .font(.subheadline)
    }

    private var candidateRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if vm.candidates.isEmpty {
                    Text(vm.isRecognizing ? "Recognising…" : "Candidates appear here")
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 14)
                }
                ForEach(Array(vm.candidates.enumerated()), id: \.element.id) { index, candidate in
                    Button {
                        vm.selected = candidate
                    } label: {
                        VStack(spacing: 2) {
                            Text(candidate.text).font(.title2)
                            Text(candidate.score.map { String(format: "%d · %.2f", index + 1, $0) } ?? "\(index + 1)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(vm.selected == candidate ? .accentColor : .secondary)
                }
            }
        }
        .frame(minHeight: 64)
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button { vm.copySelected() } label: { Label("Copy", systemImage: "doc.on.doc") }
                .buttonStyle(.borderedProminent)
                .disabled(vm.selected == nil)
            Button { vm.undoStroke() } label: { Label("Undo stroke", systemImage: "arrow.uturn.backward") }
                .buttonStyle(.bordered)
                .disabled(vm.strokeCount == 0)
            Button(role: .destructive) { vm.clear() } label: { Label("Clear", systemImage: "trash") }
                .buttonStyle(.bordered)
                .disabled(vm.strokeCount == 0)
            Spacer()
            Button { showMisreadSheet = true } label: { Label("Log misread", systemImage: "exclamationmark.bubble") }
                .buttonStyle(.bordered)
                .disabled(vm.candidates.isEmpty)
        }
    }

    private var misreadList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Misread log (\(log.entries.count))").font(.headline)
                Spacer()
                Button("Copy all") { UIPasteboard.general.string = log.asText }
                    .disabled(log.entries.isEmpty)
                Button("Clear log", role: .destructive) { log.clear() }
                    .disabled(log.entries.isEmpty)
            }
            List {
                ForEach(log.entries) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("wrote: \(e.expected)").font(.body)
                        Text("got: \(e.candidates.joined(separator: " / "))")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("\(e.language) · \(e.strokes) strokes · \(e.date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .onDelete { log.remove(at: $0) }
            }
            .listStyle(.plain)
        }
    }
}

/// Asks what was actually written, prefilled with the top candidate for quick editing.
struct MisreadSheet: View {
    let topCandidate: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var expected: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("What did you write?") {
                    TextField("Expected text", text: $expected)
                        .focused($focused)
                        .autocorrectionDisabled()
                }
                Section { Text("Top candidate was: \(topCandidate)").foregroundStyle(.secondary) }
            }
            .navigationTitle("Log misread")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(expected); dismiss() }
                        .disabled(expected.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { expected = topCandidate; focused = true }
        }
    }
}

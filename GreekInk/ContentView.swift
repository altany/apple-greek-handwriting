import SwiftUI

struct ContentView: View {
    @StateObject private var service: InkRecognitionService
    @StateObject private var log: MisreadLog
    @StateObject private var prototype: PrototypeViewModel
    @StateObject private var exporter = KeyboardModelExporter()

    init() {
        let service = InkRecognitionService()
        let log = MisreadLog()
        _service = StateObject(wrappedValue: service)
        _log = StateObject(wrappedValue: log)
        _prototype = StateObject(wrappedValue: PrototypeViewModel(service: service, log: log))
    }

    var body: some View {
        TabView {
            NavigationStack {
                PrototypeView(vm: prototype, service: service, log: log)
                    .navigationTitle("GreekInk")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Write", systemImage: "pencil.and.scribble") }

            NavigationStack {
                SetupView(service: service, exporter: exporter)
                    .navigationTitle("Setup")
            }
            .tabItem { Label("Setup", systemImage: "gearshape") }
        }
        // The keyboard has no network without Full Access: keep a copy of the model for it.
        .task { exporter.exportIfNeeded(service: service) }
        .onChange(of: service.states) { exporter.exportIfNeeded(service: service) }
    }
}

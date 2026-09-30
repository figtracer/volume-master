import SwiftUI

@main
struct VolumeMasterApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Volume Master", systemImage: model.enabled ? "speaker.wave.2.fill" : "speaker") {
            ContentView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

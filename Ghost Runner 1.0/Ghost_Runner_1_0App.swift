import SwiftUI

@main
struct GhostRunnerApp: App {

    @StateObject private var ble = BLEManager()
    @StateObject private var sound = SoundPlayer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ble)
                .environmentObject(sound)
        }
    }
}

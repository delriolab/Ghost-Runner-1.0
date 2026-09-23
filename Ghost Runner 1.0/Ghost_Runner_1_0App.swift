//
//  Ghost_Runner_1_0App.swift
//  Ghost Runner 1.0
//
//  Created by Alexander del Rio on 4/3/26.
//

import SwiftUI

@main
struct Ghost_Runner_1_0App: App {
    init() {
        // Touch the singleton at launch so the audio session and buzzer.wav are ready before the first buzz
        _ = SoundPlayer.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Always dark; white keeps system controls (back button, toolbar) off the accent blue
                .preferredColorScheme(.dark)
                .tint(.white)
                .onAppear {
                    // Keep the screen awake while the app is open
                    UIApplication.shared.isIdleTimerDisabled = true
                }
        }
    }
}

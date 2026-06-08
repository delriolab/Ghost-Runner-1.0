import Foundation
import AVFoundation

class SoundPlayer {
    // Thread-safe singleton instance
    static let shared = SoundPlayer()
    
    private var player: AVAudioPlayer?
    
    // Private initializer prevents other files from creating separate instances
    private init() {
        configureAudioSession()
        loadBuzzerSound()
    }
    
    /// Configures iOS Audio Session to play sound even if the physical silent switch is flipped on.
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // .playback category ensures audio routes to external Bluetooth speakers
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("GhostRunner Audio Error: Failed to configure AVAudioSession: \(error.localizedDescription)")
        }
    }
    
    /// Safely loads the sound file from the app bundle into memory cache
    private func loadBuzzerSound() {
        // Looks for a file named "buzzer.wav" inside your Xcode project folders
        guard let url = Bundle.main.url(forResource: "buzzer", withExtension: "wav") else {
            print("GhostRunner Audio Error: 'buzzer.wav' file missing from app bundle assets!")
            return
        }
        
        do {
            player = try AVAudioPlayer(contentsOf: url)
            // Pre-loads the audio hardware buffers to ensure zero playback latency on trigger
            player?.prepareToPlay()
        } catch {
            print("GhostRunner Audio Error: Failed to initialize AVAudioPlayer: \(error.localizedDescription)")
        }
    }
    
    /// Instantly fires the buzzer sound, resetting the playback head to zero if already playing
    func play() {
        guard let player = player else {
            print("GhostRunner Audio Error: Playback failed. Player is not initialized.")
            return
        }
        
        // If the buzzer is already playing from a rapid trigger, cut it off and restart instantly
        if player.isPlaying {
            player.stop()
        }
        
        player.currentTime = 0
        player.play()
    }
}

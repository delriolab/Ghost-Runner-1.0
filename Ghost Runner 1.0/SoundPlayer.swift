import Foundation
import AVFoundation
import Combine

final class SoundPlayer: ObservableObject {

    private var player: AVAudioPlayer?

    init() {
        configureAudioSession()

        if let url = Bundle.main.url(forResource: "buzzer", withExtension: "wav") {
            player = try? AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
        }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    func playBuzzer() {
        player?.currentTime = 0
        player?.play()
    }
}

import Foundation
import AVFoundation
import Combine

final class SoundPlayer: ObservableObject {

    private var player: AVAudioPlayer?

    init() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback)
        try? session.setActive(true)

        if let url = Bundle.main.url(forResource: "buzzer", withExtension: "wav") {
            player = try? AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
        }
    }

    func playBuzzer() {
        player?.currentTime = 0
        player?.play()
    }
}

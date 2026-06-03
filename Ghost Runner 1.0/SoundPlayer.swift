//
//  SoundPlayer.swift
//  Ghost Runner 1.0
//
//  Created by Alexander del Rio on 4/3/26.
//

import Foundation
import AVFoundation
class SoundPlayer {
static let shared = SoundPlayer()
private var player: AVAudioPlayer?
private init() {
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

func play() {
    player?.stop()
    player?.currentTime = 0
    player?.play()
}

}


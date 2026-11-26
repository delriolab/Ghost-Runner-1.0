import Foundation
import AVFoundation
import Combine
import Speech

/// Pro voice logging: listens on the training screen and turns short calls into commands.
///
/// Recognition runs on the phone where supported (no internet needed). Each call is recognized on
/// its own: after a short pause the words are checked, then listening starts fresh.
///
/// Audio: the buzzer normally uses `.playback`. While listening, the session is `.playAndRecord`
/// with the speaker and Bluetooth speakers still used for sound (the phone's mic listens). `stop()`
/// puts `.playback` back, so with voice off nothing about the buzzer changes.
@MainActor
final class VoiceListener: ObservableObject {
    enum Status: Equatable {
        case off
        case listening
        /// Microphone or speech recognition not allowed in Settings
        case denied
        /// No recognizer for English on this phone
        case unavailable
    }

    @Published private(set) var status: Status = .off
    /// What it heard last, shown small on screen so the coach can see it working
    @Published private(set) var heard = ""

    var onCommand: ((VoiceCommand) -> Void)?
    var roster: [VoiceCommandParser.RosterName] = []

    /// Quiet time that ends a call
    static let callPause: Duration = .milliseconds(700)

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private let sink = BufferSink()
    private var task: SFSpeechRecognitionTask?
    private var settle: Task<Void, Never>?
    /// Ignores results from a call that has already been replaced
    private var callID = 0
    private var observers: [NSObjectProtocol] = []
    private let speaker = AVSpeechSynthesizer()
    /// False once stop() is called, so a start waiting on the permission prompt doesn't carry on
    private var wanted = false
    private var startedAt = Date.distantPast

    // MARK: Start and stop

    func start() async {
        guard status != .listening else { return }
        wanted = true
        let allowed = await Self.authorize()
        // stop() may have run while waiting for permission
        guard wanted, status != .listening else { return }
        guard allowed else {
            status = .denied
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            status = .unavailable
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setActive(true)

            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0),
                             block: Self.tapBlock(sink))
            engine.prepare()
            try engine.start()
        } catch {
            stop()
            status = .unavailable
            return
        }
        status = .listening
        startedAt = Date()
        watchForInterruptions()
        newCall()
    }

    func stop() {
        wanted = false
        settle?.cancel()
        task?.cancel()
        task = nil
        sink.request?.endAudio()
        sink.request = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if status == .listening {
            // Back to exactly what the buzzer uses
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default, options: [])
            try? session.setActive(true)
        }
        status = .off
        heard = ""
    }

    /// Forget anything said so far (e.g. at the bat strike, so chatter before it doesn't count)
    func newCall() {
        guard status == .listening, let recognizer else { return }
        settle?.cancel()
        task?.cancel()
        sink.request?.endAudio()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.contextualStrings = VoiceCommandParser.vocabulary(roster: roster)
        request.taskHint = .confirmation
        sink.request = request

        callID += 1
        task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler(self, callID: callID))
    }

    /// Says the logged call back, e.g. "Jake, out"
    func say(_ text: String) {
        speaker.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.55
        speaker.speak(utterance)
    }

    // MARK: Results

    private func handle(text: String, isFinal: Bool, failed: Bool, callID: Int) {
        guard callID == self.callID, status == .listening else { return }
        if failed {
            // On-device recognition ends after long silence; just listen again
            settle?.cancel()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                if callID == self.callID { self.newCall() }
            }
            return
        }
        heard = text
        settle?.cancel()
        if isFinal {
            finishCall(text)
            return
        }
        settle = Task { @MainActor in
            try? await Task.sleep(for: Self.callPause)
            guard !Task.isCancelled, callID == self.callID else { return }
            self.finishCall(text)
        }
    }

    private func finishCall(_ text: String) {
        if let command = VoiceCommandParser.parse(text, roster: roster) {
            onCommand?(command)
        }
        newCall()
    }

    // MARK: Interruptions (phone calls, Siri) and audio route changes

    private func watchForInterruptions() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                                            queue: .main) { [weak self] note in
            let ended = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init) == .ended
            Task { @MainActor in self?.restart(onlyIf: ended) }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                            queue: .main) { [weak self] _ in
            Task { @MainActor in
                // Starting changes the route itself; only react to later changes (headphones, speaker)
                guard let self, Date().timeIntervalSince(self.startedAt) > 2 else { return }
                self.restart(onlyIf: true)
            }
        })
    }

    private func restart(onlyIf condition: Bool) {
        guard condition, status == .listening else { return }
        stop()
        Task { await start() }
    }

    // MARK: Off the main thread

    /// Hands microphone audio to the current request (called on the audio thread)
    private final class BufferSink: @unchecked Sendable {
        private let lock = NSLock()
        private var _request: SFSpeechAudioBufferRecognitionRequest?

        var request: SFSpeechAudioBufferRecognitionRequest? {
            get { lock.withLock { _request } }
            set { lock.withLock { _request = newValue } }
        }

        func append(_ buffer: AVAudioPCMBuffer) {
            request?.append(buffer)
        }
    }

    nonisolated private static func tapBlock(_ sink: BufferSink) -> AVAudioNodeTapBlock {
        { buffer, _ in sink.append(buffer) }
    }

    nonisolated private static func resultHandler(_ listener: VoiceListener, callID: Int)
        -> @Sendable (SFSpeechRecognitionResult?, Error?) -> Void {
        { [weak listener] result, error in
            let text = result?.bestTranscription.formattedString ?? ""
            let isFinal = result?.isFinal ?? false
            let failed = error != nil && result == nil
            Task { @MainActor in
                listener?.handle(text: text, isFinal: isFinal, failed: failed, callID: callID)
            }
        }
    }

    nonisolated private static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}

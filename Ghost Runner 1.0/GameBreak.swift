import Foundation
import Combine

// MARK: - Game Break Challenge
//
// Tap the puck to start a hidden timer, tap again when you think 4.000 s has
// passed. Taps come from the puck as "HIT:<ms>", stamped with the puck's own
// millisecond clock, so Bluetooth delays don't affect the measured time.

/// A tap from the puck while it's in Game mode.
struct GameTap {
    /// Puck clock (CircuitPython supervisor.ticks_ms) when the tap was sampled; nil for simulated taps
    let puckMs: Int?
    /// Phone clock when the tap arrived, used if the puck time is missing
    let receivedAt: ContinuousClock.Instant
}

/// One timed attempt at the target time.
struct GameAttempt: Codable, Equatable {
    let elapsedMs: Int

    /// Negative is early, positive is late
    var errorMs: Int { elapsedMs - GameBreakScoring.targetMs }
    var absErrorMs: Int { abs(errorMs) }
    var score: Int { GameBreakScoring.score(absErrorMs: absErrorMs) }
    var isPerfect: Bool { absErrorMs <= GameBreakScoring.perfectMs }
}

enum GameBreakScoring {
    /// The time to hit. Change it here; every screen and score follows.
    static let targetMs = 4000
    static let perfectMs = 10

    /// Score at each error (ms); straight lines in between, 0 beyond the last point.
    static let points: [(ms: Double, score: Double)] = [
        (10, 100), (25, 95), (50, 90), (100, 80), (200, 60), (500, 0),
    ]

    static func score(absErrorMs: Int) -> Int {
        let e = Double(absErrorMs)
        guard let first = points.first, let last = points.last else { return 0 }
        if e <= first.ms { return Int(first.score) }
        if e >= last.ms { return Int(last.score) }
        for (low, high) in zip(points, points.dropFirst()) where e <= high.ms {
            let fraction = (e - low.ms) / (high.ms - low.ms)
            return Int((low.score + fraction * (high.score - low.score)).rounded())
        }
        return 0
    }

    /// The puck's ticks_ms counter wraps every 2^29 ms (about 6.2 days).
    static let puckClockPeriod = 1 << 29

    /// Milliseconds from one puck clock reading to a later one, allowing for wraparound.
    static func puckElapsedMs(from start: Int, to end: Int) -> Int {
        (end - start) & (puckClockPeriod - 1)
    }

    /// "4.000"
    static var targetText: String { seconds(targetMs) }

    /// "4.173"
    static func seconds(_ ms: Int) -> String {
        String(format: "%d.%03d", ms / 1000, ms % 1000)
    }
}

// MARK: - State machine

/// READY (green) -> first tap -> TIMING (dark, nothing shown) -> second tap -> RESULT (red),
/// then back to READY on its own so nobody has to touch the phone.
/// Green only appears once the puck has confirmed Game mode.
@MainActor
final class GameBreakEngine: ObservableObject {
    /// Taps this soon after the start are ignored (double taps, bounces)
    static let stopLockoutMs = 2500
    /// How long a result stays up before the next try starts automatically
    static let resultHoldSeconds = 3.0

    enum NotReady: Equatable {
        case disconnected
        case confirming
        /// Connected, but the puck never acknowledged GAME (older firmware)
        case needsFirmware
    }

    enum Phase: Equatable {
        case notReady(NotReady)
        case ready
        case timing
        case result(GameAttempt)
    }

    @Published private(set) var phase: Phase = .notReady(.disconnected)
    /// When the current result will be accepted automatically
    @Published private(set) var autoAdvanceAt: Date?

    /// Called once per attempt that counts (not for Redo); the open screen sets this
    var onAttemptAccepted: ((GameAttempt) -> Void)?

    private var startTap: GameTap?
    private var autoAdvance: DispatchWorkItem?
    /// nil when the puck (or the simulator) is ready to play
    private var unavailable: NotReady? = .disconnected

    func updateAvailability(connected: Bool, confirmed: Bool, failed: Bool, simulated: Bool) {
        let reason: NotReady?
        if simulated || (connected && confirmed) {
            reason = nil
        } else if !connected {
            reason = .disconnected
        } else if failed {
            reason = .needsFirmware
        } else {
            reason = .confirming
        }
        unavailable = reason

        switch phase {
        case .notReady:
            phase = reason.map(Phase.notReady) ?? .ready
        case .ready, .timing:
            // Losing the puck cancels an attempt in progress
            if let reason {
                startTap = nil
                phase = .notReady(reason)
            }
        case .result:
            break   // keep showing the result; accepting or redoing decides where to go
        }
    }

    func handleTap(_ tap: GameTap) {
        switch phase {
        case .ready:
            startTap = tap
            phase = .timing
        case .timing:
            guard let start = startTap else { return }
            let elapsed = Self.elapsedMs(from: start, to: tap)
            // A double tap or bounce right after the start can't end the attempt
            guard elapsed >= Self.stopLockoutMs else { return }
            startTap = nil
            showResult(GameAttempt(elapsedMs: elapsed))
        case .notReady, .result:
            break   // taps while the result is showing are ignored
        }
    }

    private func showResult(_ attempt: GameAttempt) {
        phase = .result(attempt)
        let work = DispatchWorkItem { [weak self] in self?.acceptResult() }
        autoAdvance = work
        autoAdvanceAt = Date().addingTimeInterval(Self.resultHoldSeconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.resultHoldSeconds, execute: work)
    }

    private func cancelAutoAdvance() {
        autoAdvance?.cancel()
        autoAdvance = nil
        autoAdvanceAt = nil
    }

    private func leaveResult() {
        cancelAutoAdvance()
        phase = unavailable.map(Phase.notReady) ?? .ready
    }

    /// Cancels an accidental start
    func reset() {
        guard phase == .timing else { return }
        startTap = nil
        phase = .ready
    }

    /// The attempt counts; on to the next try (also happens automatically after the hold)
    func acceptResult() {
        guard case .result(let attempt) = phase else { return }
        leaveResult()
        onAttemptAccepted?(attempt)
    }

    /// Throws the attempt away, e.g. after an accidental tap; the same player goes again
    func redo() {
        guard case .result = phase else { return }
        leaveResult()
    }

    static func elapsedMs(from start: GameTap, to end: GameTap) -> Int {
        if let a = start.puckMs, let b = end.puckMs {
            return GameBreakScoring.puckElapsedMs(from: a, to: b)
        }
        let duration = end.receivedAt - start.receivedAt
        let (seconds, attoseconds) = duration.components
        return Int((Double(seconds) * 1000 + Double(attoseconds) / 1e15).rounded())
    }
}

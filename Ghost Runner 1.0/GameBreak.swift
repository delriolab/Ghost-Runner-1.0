import Foundation
import Combine

// MARK: - Game Break Challenge
//
// Tap the puck to start a hidden timer, tap again when you think 4.200 s has
// passed. Taps come from the puck as "HIT:<ms>", stamped with the puck's own
// millisecond clock, so Bluetooth delays don't affect the measured time.

/// A tap from the puck while it's in Game mode.
struct GameTap {
    /// Puck clock (CircuitPython supervisor.ticks_ms) when the tap was sampled; nil for simulated taps
    let puckMs: Int?
    /// Phone clock when the tap arrived, used if the puck time is missing
    let receivedAt: ContinuousClock.Instant
}

/// One timed attempt at the 4.200 s target.
struct GameAttempt: Codable, Equatable {
    let elapsedMs: Int

    /// Negative is early, positive is late
    var errorMs: Int { elapsedMs - GameBreakScoring.targetMs }
    var absErrorMs: Int { abs(errorMs) }
    var score: Int { GameBreakScoring.score(absErrorMs: absErrorMs) }
    var isPerfect: Bool { absErrorMs <= GameBreakScoring.perfectMs }
}

enum GameBreakScoring {
    static let targetMs = 4200
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

    /// "4.173"
    static func seconds(_ ms: Int) -> String {
        String(format: "%d.%03d", ms / 1000, ms % 1000)
    }
}

// MARK: - State machine

/// READY (green) -> first tap -> TIMING (dark, nothing shown) -> second tap -> RESULT (red).
/// Green only appears once the puck has confirmed Game mode.
@MainActor
final class GameBreakEngine: ObservableObject {
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

    private var startTap: GameTap?
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
            break   // keep showing the result; NEXT TRY decides where to go
        }
    }

    func handleTap(_ tap: GameTap) {
        switch phase {
        case .ready:
            startTap = tap
            phase = .timing
        case .timing:
            guard let start = startTap else { return }
            startTap = nil
            phase = .result(GameAttempt(elapsedMs: Self.elapsedMs(from: start, to: tap)))
        case .notReady, .result:
            break
        }
    }

    /// Cancels an accidental start
    func reset() {
        guard phase == .timing else { return }
        startTap = nil
        phase = .ready
    }

    func nextTry() {
        guard case .result = phase else { return }
        phase = unavailable.map(Phase.notReady) ?? .ready
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

import Foundation

/// Tag up starts on the second hit: the coach hits the fly ball (first hit), then strikes the bat
/// on the ground when the ball reaches the fielder's glove (second hit), which starts the timer.
/// If no second hit comes within `catchWindow`, the next hit counts as a new fly ball.
struct TagUpTrigger: Equatable {
    static let drill = "Tag up"
    /// No fly ball stays up this long, and coaches want to keep things moving
    static let catchWindow: TimeInterval = 6

    /// When the fly ball was hit, while waiting for the catch
    private(set) var ballHitAt: Date?

    static func applies(to drill: String) -> Bool { drill == Self.drill }

    func isBallInAir(at now: Date) -> Bool {
        guard let ballHitAt else { return false }
        return now.timeIntervalSince(ballHitAt) < Self.catchWindow
    }

    /// Records a hit; true when it is the catch and the timer should start
    mutating func hit(at now: Date) -> Bool {
        if isBallInAir(at: now) {
            ballHitAt = nil
            return true
        }
        ballHit(at: now)
        return false
    }

    mutating func ballHit(at now: Date) { ballHitAt = now }

    mutating func reset() { ballHitAt = nil }
}

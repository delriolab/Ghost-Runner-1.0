import UIKit

/// Keeps the screen on while the puck is connected. Once the connection has been lost for
/// a couple of minutes (the puck went to sleep), the phone is allowed to auto-lock normally,
/// so the app isn't left sitting open with the screen on. iOS then suspends it until the
/// coach unlocks the phone, and it reconnects from there.
@MainActor
final class ScreenAwake {
    static let defaultGrace: TimeInterval = 120

    private let grace: TimeInterval
    private let setKeepAwake: (Bool) -> Void
    private var allowLock: DispatchWorkItem?

    init(grace: TimeInterval = ScreenAwake.defaultGrace,
         setKeepAwake: @escaping (Bool) -> Void = { UIApplication.shared.isIdleTimerDisabled = $0 }) {
        self.grace = grace
        self.setKeepAwake = setKeepAwake
    }

    /// Call at launch, whenever the connection changes, and when the app comes back to the front
    func update(connected: Bool) {
        allowLock?.cancel()
        allowLock = nil
        setKeepAwake(true)
        guard !connected else { return }

        // Not connected: stay on long enough to reconnect, then let the phone lock
        let work = DispatchWorkItem { [weak self] in self?.setKeepAwake(false) }
        allowLock = work
        DispatchQueue.main.asyncAfter(deadline: .now() + grace, execute: work)
    }
}

import SwiftUI
import SwiftData

struct ContentView: View {
    @StateObject private var bleManager = BLEManager()
    @Environment(\.scenePhase) private var scenePhase
    // Screen stays on while connected; may lock 2 minutes after the puck drops off
    @State private var screenAwake = ScreenAwake()

    // The coach's last setup, saved between launches
    @AppStorage("sport") private var savedSport = ""
    @AppStorage("baseballCategory") private var baseballCategory = ""
    @AppStorage("softballCategory") private var softballCategory = ""
    // Each sport remembers its own last drill (the shared "drill" key from earlier versions seeds both)
    @AppStorage("baseballDrill") private var baseballDrill = UserDefaults.standard.string(forKey: "drill") ?? StandardTimes.defaultDrill
    @AppStorage("softballDrill") private var softballDrill = UserDefaults.standard.string(forKey: "drill") ?? StandardTimes.defaultDrill
    @AppStorage("intensity") private var intensity: Intensity = .routine
    @AppStorage("customTimeEnabled") private var customTimeEnabled = false
    @AppStorage("customTime") private var customTime: Double = 0

    // Always starts on the home screen
    @State private var path: [Sport] = []
    /// When the app last went to the background, to decide whether to return home
    @State private var backgroundedAt: Date?
    @State private var paused = false
    @State private var showGameBreak = false
    @State private var remainingTime: Double = 0
    @State private var timerRunning = false
    @State private var timer: Timer?
    /// Tag up: the fly ball arms it, the strike at the catch starts the timer
    @State private var tagUp = TagUpTrigger()
    @State private var tagUpTimeout: Task<Void, Never>?

    // Pro: log each rep's outcome. Off by default; nothing below runs while it's off.
    @AppStorage(ProAccess.enabledKey) private var proEnabled = false
    @AppStorage("proFielder") private var fielderRaw = Fielder.team.rawValue
    @State private var pendingRep: PendingRep?
    @State private var lastLogged: Rep?
    /// The rep behind lastLogged, so Undo can bring the outcome buttons back
    @State private var lastLoggedFrom: PendingRep?
    @State private var showTeam = false

    var body: some View {
        NavigationStack(path: $path) {
            SportSelectionView(onGameBreak: { showGameBreak = true },
                               onTeam: proEnabled && ProStore.shared.container != nil ? { showTeam = true } : nil)
                .navigationDestination(isPresented: $showGameBreak) {
                    GameBreakHomeView(bleManager: bleManager)
                }
                .navigationDestination(isPresented: $showTeam) {
                    if let container = ProStore.shared.container {
                        TeamView().modelContainer(container)
                    }
                }
                .navigationDestination(for: Sport.self) { sport in
                    SetupView(
                        sport: sport,
                        category: categoryBinding(for: sport),
                        drill: drillBinding(for: sport),
                        intensity: $intensity,
                        customTimeEnabled: customTimeEnabledBinding,
                        customTime: $customTime,
                        selectedTime: selectedTime,
                        remainingTime: remainingTime,
                        timerRunning: timerRunning,
                        connectionStatus: bleManager.connectionStatus,
                        batteryLevel: bleManager.batteryLevel,
                        paused: paused,
                        ballInAir: tagUp.ballHitAt != nil,
                        onTogglePause: togglePause,
                        onTestBuzzer: { SoundPlayer.shared.play() },
                        pro: proEnabled ? proTraining : nil
                    )
                }
        }
        .onChange(of: path) { _, newPath in
            if let sport = newPath.last {
                savedSport = sport.rawValue
            } else if paused {
                // Back on sport selection: never leave the timer paused
                paused = false
            }
            resetTagUp()
            clearRep()
        }
        .onChange(of: proEnabled) { clearRep() }
        .onChange(of: baseballDrill) { resetTagUp() }
        .onChange(of: softballDrill) { resetTagUp() }
        .onAppear {
            screenAwake.update(connected: isConnected)
            // Hand the launch delay to BLEManager so it is sent as soon as the sensor connects
            bleManager.sendDelay(selectedDelay)
        }
        .onChange(of: selectedDelay) { _, newValue in
            bleManager.sendDelay(newValue)
        }
        .onReceive(bleManager.triggerPublisher) { _ in
            // Game Break has its own taps; never run the training countdown there.
            // While paused (coach talking), hits are ignored.
            guard !showGameBreak, !paused else { return }
            if let sport = path.last, TagUpTrigger.applies(to: drill(for: sport)) {
                tagUpHit()
            } else {
                startRep()
            }
        }
        .onChange(of: isConnected) { _, connected in
            screenAwake.update(connected: connected)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                backgroundedAt = Date()
            case .active:
                // Back after a real break (e.g. the phone locked): start again from the home screen
                if let since = backgroundedAt, HomeReturn.shouldGoHome(awayFor: Date().timeIntervalSince(since)) {
                    goHome()
                }
                backgroundedAt = nil
                // Unlocking the phone gives it time to reconnect before it may lock again
                screenAwake.update(connected: isConnected)
            default:
                break
            }
        }
        // The puck switches to Game Break taps only while those screens are open
        .onChange(of: showGameBreak) { _, isOpen in
            if isOpen {
                bleManager.enterGameMode()
            } else {
                bleManager.exitGameMode()
            }
        }
        // Vibrate when the countdown reaches zero (not when Stop cancels it), for noisy fields
        .sensoryFeedback(.warning, trigger: timerRunning) { wasRunning, isRunning in
            wasRunning && !isRunning && remainingTime <= 0
        }
    }

    private var isConnected: Bool {
        bleManager.connectionStatus.hasPrefix("Connected")
    }

    // MARK: - Selection

    private var currentSport: Sport {
        path.last ?? Sport(rawValue: savedSport) ?? .baseball
    }

    /// The coach's custom time when it's switched on, otherwise the standard time from the table
    private var selectedTime: Double? {
        if customTimeEnabled, customTime > 0 {
            return customTime
        }
        return standardTime
    }

    private var standardTime: Double? {
        StandardTimes.time(
            sport: currentSport,
            category: category(for: currentSport),
            drill: drill(for: currentSport),
            intensity: intensity
        )
    }

    /// Turning custom time on the first time starts the dial from the current standard time
    private var customTimeEnabledBinding: Binding<Bool> {
        Binding(
            get: { customTimeEnabled },
            set: { isOn in
                if isOn, customTime <= 0 {
                    customTime = CustomTime.adjusted(standardTime ?? 4.0, bySteps: 0)
                }
                customTimeEnabled = isOn
            }
        )
    }

    var selectedDelay: Double {
        selectedTime ?? 0
    }

    /// The saved age group for a sport, or its default if the saved one no longer exists
    private func category(for sport: Sport) -> String {
        let times = StandardTimes.table(for: sport)
        let saved = sport == .baseball ? baseballCategory : softballCategory
        return times.categories.contains(saved) ? saved : times.defaultCategory
    }

    private func goHome() {
        showGameBreak = false
        showTeam = false
        path = []
    }

    private func drill(for sport: Sport) -> String {
        let drills = StandardTimes.table(for: sport).drills
        let saved = sport == .baseball ? baseballDrill : softballDrill
        if drills.contains(saved) { return saved }
        return drills.contains(StandardTimes.defaultDrill) ? StandardTimes.defaultDrill : drills.first ?? ""
    }

    private func categoryBinding(for sport: Sport) -> Binding<String> {
        Binding(
            get: { category(for: sport) },
            set: { newValue in
                switch sport {
                case .baseball: baseballCategory = newValue
                case .softball: softballCategory = newValue
                }
            }
        )
    }

    private func drillBinding(for sport: Sport) -> Binding<String> {
        Binding(
            get: { drill(for: sport) },
            set: { newValue in
                switch sport {
                case .baseball: baseballDrill = newValue
                case .softball: softballDrill = newValue
                }
            }
        )
    }

    // MARK: - Pause

    /// Pausing ignores hits, and cancels a countdown in progress, while the coach is talking
    private func togglePause() {
        paused.toggle()
        if paused {
            stopTimer()
            resetTagUp()
        }
    }

    // MARK: - Tag up

    private func tagUpHit() {
        let now = Date()
        // During a countdown, a hit is the next fly ball; it doesn't restart the runner
        if timerRunning {
            if !tagUp.isBallInAir(at: now) {
                tagUp.ballHit(at: now)
                waitForCatch()
            }
            return
        }
        if tagUp.hit(at: now) {
            tagUpTimeout?.cancel()
            startRep()
        } else {
            waitForCatch()
        }
    }

    /// The fly ball is up: wait for the catch, but not forever
    private func waitForCatch() {
        tagUpTimeout?.cancel()
        tagUpTimeout = Task { @MainActor in
            try? await Task.sleep(for: .seconds(TagUpTrigger.catchWindow))
            guard !Task.isCancelled else { return }
            tagUp.reset()
        }
    }

    private func resetTagUp() {
        tagUpTimeout?.cancel()
        tagUp.reset()
    }

    // MARK: - Pro rep logging

    /// A hit that starts the ghost runner; with Pro on, it also opens a rep to log
    private func startRep() {
        startTimer()
        guard proEnabled, let sport = path.last else { return }
        pendingRep = PendingRep(
            fielder: Fielder(rawValue: fielderRaw),
            players: ProStore.shared.players(),
            sport: sport,
            category: category(for: sport),
            drill: drill(for: sport),
            intensity: intensity,
            runnerTime: selectedDelay,
            usedCustomTime: customTimeEnabled
        )
        lastLogged = nil
    }

    private var proTraining: ProTraining {
        ProTraining(
            fielder: $fielderRaw,
            hasPendingRep: pendingRep != nil,
            lastLogged: lastLogged.map { "\($0.fielderLabel) · \($0.outcome.title)" },
            onOutcome: { outcome in
                guard let pending = pendingRep else { return }
                lastLogged = ProStore.shared.record(pending, outcome: outcome)
                lastLoggedFrom = pending
                pendingRep = nil
            },
            onUndo: {
                if let rep = lastLogged { ProStore.shared.delete(rep) }
                lastLogged = nil
                // Pick again
                pendingRep = lastLoggedFrom
            }
        )
    }

    private func clearRep() {
        pendingRep = nil
        lastLogged = nil
        lastLoggedFrom = nil
    }

    // MARK: - Countdown

    func startTimer() {
        stopTimer()
        // Fix the buzz time against the real clock so late or skipped ticks can't add drift
        let endTime = Date().addingTimeInterval(selectedDelay)
        remainingTime = selectedDelay
        timerRunning = true

        let newTimer = Timer(timeInterval: 0.01, repeats: true) { _ in
            remainingTime = max(0, endTime.timeIntervalSinceNow)
            if remainingTime <= 0 {
                stopTimer()
                SoundPlayer.shared.play()
            }
        }
        newTimer.tolerance = 0
        // .common keeps the timer firing while the UI is tracking touches
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
        timerRunning = false
    }
}

/// When coming back to the app should start over on the home screen
enum HomeReturn {
    /// Quick switches away (reading a text mid-drill) keep their place; anything longer goes home
    static let awayThreshold: TimeInterval = 60

    static func shouldGoHome(awayFor seconds: TimeInterval) -> Bool {
        seconds >= awayThreshold
    }
}

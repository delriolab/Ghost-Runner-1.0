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
    /// When lastLogged was logged as an out with no call, so a late "safe" can still fix it
    @State private var lastOutAt: Date?
    /// Logs the open rep as an out if nothing is called in time
    @State private var outTimer: Task<Void, Never>?
    /// Counts reps, so the out timer only logs the rep it was started for
    @State private var repSerial = 0
    /// When "turn two" was said without a fielder, so a number right after makes it that double play
    @State private var turnTwoAt: Date?
    @State private var showRepHistory = false
    // Pro voice: hands-free logging on the training screen
    @AppStorage("proVoice") private var voiceEnabled = true
    @AppStorage("proSayItBack") private var sayItBack = true
    @StateObject private var voice = VoiceListener()

    /// Listen only on the training screen, in the foreground, with Pro voice on
    private var shouldListen: Bool {
        proEnabled && voiceEnabled && !path.isEmpty && !showGameBreak && scenePhase == .active
    }

    var body: some View {
        NavigationStack(path: $path) {
            SportSelectionView(onGameBreak: { showGameBreak = true },
                               onRepHistory: proEnabled && ProStore.shared.container != nil ? { showRepHistory = true } : nil)
                .navigationDestination(isPresented: $showGameBreak) {
                    GameBreakHomeView(bleManager: bleManager)
                }
                .navigationDestination(isPresented: $showRepHistory) {
                    if let container = ProStore.shared.container {
                        RepHistoryView().modelContainer(container)
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
        .onChange(of: shouldListen) { _, listen in updateListening(listen) }
        .onChange(of: baseballDrill) { resetTagUp() }
        .onChange(of: softballDrill) { resetTagUp() }
        .onAppear {
            voice.onCommand = handleVoice
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
        showRepHistory = false
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
        // A rep interrupted by the pause isn't logged, and talk during the pause is forgotten
        if paused { clearRep() }
        voice.newCall()
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
        // The previous rep had no "safe" call: it was an out
        logPendingAsOut()
        startTimer()
        guard proEnabled, let sport = path.last else { return }
        // Player names are on hold; a player picked in an earlier test build counts for the team
        let saved = Fielder(rawValue: fielderRaw)
        let pending = PendingRep(
            fielder: saved.playerID == nil ? saved : .team,
            players: ProStore.shared.players(),
            sport: sport,
            category: category(for: sport),
            drill: drill(for: sport),
            intensity: intensity,
            runnerTime: selectedDelay,
            usedCustomTime: customTimeEnabled
        )
        pendingRep = pending
        repSerial += 1
        let serial = repSerial
        lastLogged = nil
        lastOutAt = nil
        // Only what's said after the bat strike counts
        voice.newCall()

        let deadline = RepCall.outDeadline(start: Date(), runnerTime: selectedDelay)
        outTimer?.cancel()
        outTimer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
            guard !Task.isCancelled, serial == repSerial else { return }
            logPendingAsOut()
        }
    }

    private func logPendingAsOut() {
        outTimer?.cancel()
        guard let pending = pendingRep else { return }
        lastLogged = ProStore.shared.record(pending, outcome: .out)
        lastOutAt = Date()
        pendingRep = nil
    }

    /// "Safe": the open rep, or one just logged as an out with no call
    @discardableResult
    private func logSafe() -> Bool {
        if let pending = pendingRep {
            outTimer?.cancel()
            lastLogged = ProStore.shared.record(pending, outcome: .safe)
            lastOutAt = nil
            pendingRep = nil
            return true
        }
        if let rep = lastLogged, let at = lastOutAt, RepCall.canChangeToSafe(loggedAt: at, now: Date()) {
            ProStore.shared.change(rep, to: .safe)
            lastOutAt = nil
            return true
        }
        return false
    }

    /// The coach named the fielder: they stay the pick, and get credit for the open rep
    private func setFielder(_ fielder: Fielder) {
        fielderRaw = fielder.rawValue
        if let pending = pendingRep {
            pendingRep = pending.crediting(fielder, players: ProStore.shared.players())
        }
    }

    private var proTraining: ProTraining {
        ProTraining(
            fielder: $fielderRaw,
            hasPendingRep: pendingRep != nil,
            lastLogged: lastLogged.map { "\($0.fielderLabel) · \($0.outcome.title)" },
            voice: voiceEnabled ? VoiceDisplay(status: voice.status) : nil,
            onSafe: { logSafe() },
            onUndo: undoLastRep
        )
    }

    private func undoLastRep() {
        if let rep = lastLogged { ProStore.shared.delete(rep) }
        lastLogged = nil
        lastOutAt = nil
    }

    // MARK: - Pro voice

    private func updateListening(_ listen: Bool) {
        if listen {
            // Positions only for now; player names are on hold
            voice.roster = []
            Task { await voice.start() }
        } else {
            voice.stop()
        }
    }

    private func handleVoice(_ command: VoiceCommand) {
        guard proEnabled else { return }
        // "Ghost Runner pause" / "Ghost Runner resume" work like the Pause button
        if command.action == .pause || command.action == .resume {
            let wantPaused = command.action == .pause
            if wantPaused != paused {
                togglePause()
                if sayItBack { voice.say(paused ? "Paused" : "Resumed") }
            }
            return
        }
        guard !paused else { return }

        var said: [String] = []
        var fielder = command.fielder
        if command.turnTwo && fielder == nil {
            // "Turn two" alone: the current fielder's double play, or the number said next
            turnTwoAt = Date()
            fielder = Fielder(rawValue: fielderRaw).turningTwo
            if fielder == nil { said.append("Turn two") }
        } else if let named = fielder {
            if case .position = named, let at = turnTwoAt,
               Date().timeIntervalSince(at) <= DoublePlay.followUp, let doublePlay = named.turningTwo {
                fielder = doublePlay
            }
            turnTwoAt = nil
        }
        if let fielder {
            setFielder(fielder)
            said.append(spokenName(fielder))
        }
        switch command.action {
        case .safe:
            if logSafe() { said.append("Safe") }
        case .undo:
            if lastLogged != nil {
                undoLastRep()
                said.append("Undone")
            }
        case .pause, .resume, nil:
            break
        }
        if sayItBack, !said.isEmpty { voice.say(said.joined(separator: ", ")) }
    }

    private func spokenName(_ fielder: Fielder) -> String {
        switch fielder {
        case .team: "Team"
        case .position(let p): p.title
        case .doublePlay(let p): "\(DoublePlay.spoken(from: p) ?? ""), double play"
        case .player(let id):
            ProStore.shared.players().first { $0.id == id }?.name ?? "Player"
        }
    }

    private func clearRep() {
        outTimer?.cancel()
        pendingRep = nil
        lastLogged = nil
        lastOutAt = nil
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

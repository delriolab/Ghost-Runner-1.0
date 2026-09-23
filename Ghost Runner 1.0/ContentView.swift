import SwiftUI

struct ContentView: View {
    @StateObject private var bleManager = BLEManager()

    // The coach's last setup, saved between launches
    @AppStorage("sport") private var savedSport = ""
    @AppStorage("baseballCategory") private var baseballCategory = ""
    @AppStorage("softballCategory") private var softballCategory = ""
    @AppStorage("drill") private var savedDrill = StandardTimes.defaultDrill
    @AppStorage("intensity") private var intensity: Intensity = .routine

    @State private var path: [Sport]
    @State private var monitoring = false
    @State private var remainingTime: Double = 0
    @State private var timerRunning = false
    @State private var timer: Timer?

    init() {
        // Reopen straight on the setup screen for the last sport used
        let sport = UserDefaults.standard.string(forKey: "sport").flatMap(Sport.init(rawValue:))
        _path = State(initialValue: sport.map { [$0] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            SportSelectionView()
                .navigationDestination(for: Sport.self) { sport in
                    SetupView(
                        sport: sport,
                        category: categoryBinding(for: sport),
                        drill: drillBinding(for: sport),
                        intensity: $intensity,
                        selectedTime: selectedTime,
                        remainingTime: remainingTime,
                        timerRunning: timerRunning,
                        connectionStatus: bleManager.connectionStatus,
                        monitoring: monitoring,
                        onStart: start,
                        onStop: stop,
                        onTestBuzzer: { SoundPlayer.shared.play() }
                    )
                }
        }
        .onChange(of: path) { _, newPath in
            if let sport = newPath.last {
                savedSport = sport.rawValue
            } else if monitoring {
                // Back on sport selection: don't leave a drill armed
                stop()
            }
        }
        .onAppear {
            // Hand the launch delay to BLEManager so it is sent as soon as the sensor connects
            bleManager.sendDelay(selectedDelay)
        }
        .onChange(of: selectedDelay) { _, newValue in
            bleManager.sendDelay(newValue)
        }
        .onReceive(bleManager.triggerPublisher) { _ in
            startTimer()
        }
    }

    // MARK: - Selection

    private var currentSport: Sport {
        path.last ?? Sport(rawValue: savedSport) ?? .baseball
    }

    private var selectedTime: Double? {
        StandardTimes.time(
            sport: currentSport,
            category: category(for: currentSport),
            drill: drill(for: currentSport),
            intensity: intensity
        )
    }

    var selectedDelay: Double {
        selectedTime ?? 0
    }

    /// The saved field size / age group for a sport, or its default if the saved one no longer exists
    private func category(for sport: Sport) -> String {
        let times = StandardTimes.table(for: sport)
        let saved = sport == .baseball ? baseballCategory : softballCategory
        return times.categories.contains(saved) ? saved : times.defaultCategory
    }

    private func drill(for sport: Sport) -> String {
        let drills = StandardTimes.table(for: sport).drills
        if drills.contains(savedDrill) { return savedDrill }
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
            set: { savedDrill = $0 }
        )
    }

    // MARK: - Start / Stop

    private func start() {
        bleManager.startMonitoring()
        monitoring = true
    }

    private func stop() {
        bleManager.stopMonitoring()
        stopTimer()
        monitoring = false
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

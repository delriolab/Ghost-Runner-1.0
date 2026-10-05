import SwiftUI

// MARK: - Home

/// Game Break Challenge: pick Free Play or Tournament.
/// Opening this screen puts the puck in Game mode; leaving it puts it back to NORMAL.
struct GameBreakHomeView: View {
    @ObservedObject var bleManager: BLEManager
    @StateObject private var engine = GameBreakEngine()
    @StateObject private var store = TournamentStore()
    @AppStorage("gameBreakSimulateTaps") private var simulateTaps = false
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                SensorPill(status: bleManager.connectionStatus, batteryLevel: bleManager.batteryLevel)
            }

            Spacer()
            TargetHeader(size: 80)
            Text("How close can you get?")
                .font(.subheadline)
                .foregroundStyle(Theme.label)
                .padding(.top, 4)
            Spacer()

            VStack(spacing: 14) {
                NavigationLink {
                    FreePlayView(engine: engine, simulateTaps: simulateTaps)
                } label: {
                    ModeCardLabel(title: "Free Play", subtitle: "Tap to start, tap when you think 4.200 is up")
                }
                NavigationLink {
                    TournamentView(engine: engine, store: store, simulateTaps: simulateTaps)
                } label: {
                    ModeCardLabel(title: "Tournament",
                                  subtitle: store.tournament == nil
                                      ? "Qualifying, Final Four, championship"
                                      : "Continue the tournament in progress")
                }
            }
            .buttonStyle(SportCardButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .navigationTitle("Game Break Challenge")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gearshape") { showSettings = true }
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .navigationDestination(isPresented: $showSettings) {
            SettingsView(onTestBuzzer: { SoundPlayer.shared.play() })
        }
        .onReceive(bleManager.gameTapPublisher) { engine.handleTap($0) }
        .onAppear(perform: updateAvailability)
        .onChange(of: bleManager.connectionStatus) { updateAvailability() }
        .onChange(of: bleManager.gameModeConfirmed) { updateAvailability() }
        .onChange(of: bleManager.gameModeFailed) { updateAvailability() }
        .onChange(of: simulateTaps) { updateAvailability() }
    }

    private func updateAvailability() {
        engine.updateAvailability(
            connected: bleManager.connectionStatus.hasPrefix("Connected"),
            confirmed: bleManager.gameModeConfirmed,
            failed: bleManager.gameModeFailed,
            simulated: simulateTaps
        )
    }
}

private struct ModeCardLabel: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.label)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.accent)
        }
        .padding(.leading, 24)
        .padding(.trailing, 20)
        .frame(maxWidth: .infinity, minHeight: 80)
    }
}

/// "TARGET 4.200 s"
private struct TargetHeader: View {
    var size: CGFloat = 56

    var body: some View {
        VStack(spacing: 2) {
            Text("TARGET")
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(Theme.label)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("4.200")
                    .font(.system(size: size, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                Text("s")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.label)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Target 4.200 seconds")
    }
}

// MARK: - Play area

/// The big colored area: green READY, dark while timing, red with the result.
struct GameBreakPlayArea: View {
    let phase: GameBreakEngine.Phase
    /// Tournament: whose turn it is
    var player: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            content
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 260)
        .padding(20)
        .background(background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.divider, lineWidth: isColored ? 0 : 1)
        )
        .animation(.easeOut(duration: 0.15), value: phase)
        .accessibilityElement(children: .combine)
    }

    private var isColored: Bool {
        switch phase {
        case .ready, .result: return true
        default: return false
        }
    }

    private var background: Color {
        switch phase {
        case .ready: return Theme.ready
        case .result: return Theme.alert   // red means stopped, not a bad score
        default: return Theme.card
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .ready:
            if let player { playerLine(player, color: Theme.onAccent) }
            Text("READY")
                .font(.system(size: 52, weight: .heavy))
                .foregroundStyle(Theme.onAccent)
            Text("TAP GHOSTRUNNER TO START")
                .font(.headline.weight(.bold))
                .foregroundStyle(Theme.onAccent)

        case .timing:
            if let player { playerLine(player, color: Theme.label) }
            Text("TIMER RUNNING")
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(Theme.text)
            Text("TAP AGAIN TO STOP")
                .font(.headline.weight(.bold))
                .foregroundStyle(Theme.label)

        case .result(let attempt):
            if let player { playerLine(player, color: Theme.onAlert) }
            Text(GameBreakScoring.seconds(attempt.elapsedMs))
                .font(.system(size: 76, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Theme.onAlert)
            Text(deltaText(attempt))
                .font(.title3.weight(.heavy))
                .foregroundStyle(Theme.onAlert)
            Text(attempt.isPerfect ? "PERFECT · 100" : "SCORE \(attempt.score)")
                .font(.headline.weight(.bold))
                .foregroundStyle(Theme.onAlert.opacity(0.85))

        case .notReady(let reason):
            notReady(reason)
        }
    }

    private func playerLine(_ name: String, color: Color) -> some View {
        Text(name.uppercased())
            .font(.title3.weight(.heavy))
            .foregroundStyle(color)
    }

    private func deltaText(_ attempt: GameAttempt) -> String {
        if attempt.errorMs == 0 { return "RIGHT ON 4.200" }
        return "\(GameBreakScoring.seconds(attempt.absErrorMs)) \(attempt.errorMs < 0 ? "EARLY" : "LATE")"
    }

    @ViewBuilder
    private func notReady(_ reason: GameBreakEngine.NotReady) -> some View {
        switch reason {
        case .disconnected:
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.largeTitle)
                .foregroundStyle(Theme.label)
            Text("GhostRunner not connected")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.text)
            Text("Turn on the puck and keep it close to the phone.")
                .font(.subheadline)
                .foregroundStyle(Theme.label)
        case .confirming:
            ProgressView()
                .tint(Theme.label)
            Text("Getting GhostRunner ready…")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.text)
        case .needsFirmware:
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(Theme.connecting)
            Text("GhostRunner didn't switch to Game mode")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.text)
            Text("The puck needs the Game Break firmware update.")
                .font(.subheadline)
                .foregroundStyle(Theme.label)
        }
    }
}

// MARK: - Buttons

private struct GameButton: View {
    let title: String
    var primary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(primary ? Theme.onAccent : Theme.text)
                .frame(maxWidth: .infinity, minHeight: primary ? 60 : 50)
                .background(primary ? Theme.accent : Theme.card,
                            in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .strokeBorder(Theme.divider, lineWidth: primary ? 0 : 1)
                )
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Reset while timing, the next button after a result, and the developer tap simulator.
private struct GameControls: View {
    @ObservedObject var engine: GameBreakEngine
    let nextTitle: String
    let simulateTaps: Bool
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            switch engine.phase {
            case .timing:
                GameButton(title: "Reset") { engine.reset() }
            case .result:
                GameButton(title: nextTitle, primary: true, action: onNext)
            default:
                EmptyView()
            }
            if simulateTaps {
                GameButton(title: "Simulate puck tap") {
                    engine.handleTap(GameTap(puckMs: nil, receivedAt: .now))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Theme.background)   // keeps scrolling lists from showing through
    }
}

// MARK: - Free Play

struct FreePlayView: View {
    @ObservedObject var engine: GameBreakEngine
    let simulateTaps: Bool
    @State private var attempts: [GameAttempt] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                TargetHeader()
                GameBreakPlayArea(phase: engine.phase)
                if let best = attempts.min(by: { $0.absErrorMs < $1.absErrorMs }) {
                    HStack {
                        SessionStat(title: "Tries", value: "\(attempts.count)")
                        SessionStat(title: "Best", value: GameBreakScoring.seconds(best.elapsedMs))
                        SessionStat(title: "Best score", value: "\(best.score)")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.background)
        .navigationTitle("Free Play")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            GameControls(engine: engine, nextTitle: "NEXT TRY", simulateTaps: simulateTaps) {
                engine.nextTry()
            }
        }
        .onChange(of: engine.phase) { _, phase in
            if case .result(let attempt) = phase { attempts.append(attempt) }
        }
        .onDisappear {
            // Leave a clean slate for the next screen
            engine.reset()
            engine.nextTry()
        }
    }
}

private struct SessionStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.label)
            Text(value)
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .card()
    }
}

// MARK: - Tournament

/// Setup, play, or champion, depending on where the saved tournament is.
struct TournamentView: View {
    @ObservedObject var engine: GameBreakEngine
    @ObservedObject var store: TournamentStore
    let simulateTaps: Bool

    var body: some View {
        Group {
            if let tournament = store.tournament {
                if tournament.isFinished {
                    ChampionView(store: store)
                } else {
                    TournamentPlayView(engine: engine, store: store, simulateTaps: simulateTaps)
                }
            } else {
                TournamentSetupView(store: store)
            }
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TournamentSetupView: View {
    @ObservedObject var store: TournamentStore
    @State private var names: [String] = []
    @State private var newName = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Player name", text: $newName)
                        .focused($nameFieldFocused)
                        .submitLabel(.next)
                        .onSubmit(addName)
                        .foregroundStyle(Theme.text)
                    Button("Add", action: addName)
                        .foregroundStyle(Theme.accent)
                        .disabled(trimmedName.isEmpty)
                }
                .listRowBackground(Theme.card)
            } footer: {
                Text("Everyone gets 3 tries at 4.200. The 4 closest on average play the Final Four.")
                    .foregroundStyle(Theme.label)
            }

            Section {
                ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                    HStack {
                        Text("\(index + 1)")
                            .monospacedDigit()
                            .foregroundStyle(Theme.label)
                            .frame(width: 28, alignment: .leading)
                        Text(name)
                            .foregroundStyle(Theme.text)
                    }
                    .listRowBackground(Theme.card)
                }
                .onDelete { names.remove(atOffsets: $0) }
                .onMove { names.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                Text("Lineup (\(names.count))")
                    .foregroundStyle(Theme.label)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("New Tournament")
        .toolbar {
            if !names.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            GameButton(title: "Start tournament", primary: true) {
                store.tournament = Tournament(players: names)
            }
            .disabled(names.count < Tournament.minimumPlayers)
            .opacity(names.count < Tournament.minimumPlayers ? 0.4 : 1)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .onAppear { nameFieldFocused = true }
    }

    private var trimmedName: String { newName.trimmingCharacters(in: .whitespaces) }

    private func addName() {
        guard !trimmedName.isEmpty else { return }
        names.append(trimmedName)
        newName = ""
        nameFieldFocused = true
    }
}

private struct TournamentPlayView: View {
    @ObservedObject var engine: GameBreakEngine
    @ObservedObject var store: TournamentStore
    let simulateTaps: Bool
    @State private var confirmEnd = false

    var body: some View {
        if let tournament = store.tournament, let turn = tournament.currentTurn {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Text(turn.stage.uppercased())
                            .font(.caption.weight(.bold))
                            .tracking(1.5)
                            .foregroundStyle(Theme.accent)
                        Text(turn.detail)
                            .font(.subheadline)
                            .foregroundStyle(Theme.label)
                    }

                    GameBreakPlayArea(phase: engine.phase, player: tournament.players[turn.player])

                    if let match = currentMatch(tournament) {
                        MatchCard(match: match, players: tournament.players, title: turn.stage)
                    } else {
                        StandingsList(tournament: tournament)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Tournament")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Tournament options", systemImage: "ellipsis.circle") {
                        NavigationLink {
                            BracketView(tournament: tournament)
                        } label: {
                            Label("Bracket", systemImage: "list.number")
                        }
                        Button("End tournament", systemImage: "xmark.circle", role: .destructive) {
                            confirmEnd = true
                        }
                    }
                }
            }
            .confirmationDialog("End this tournament?", isPresented: $confirmEnd, titleVisibility: .visible) {
                Button("End tournament", role: .destructive) {
                    engine.reset()
                    engine.nextTry()
                    store.tournament = nil
                }
            } message: {
                Text("All scores will be cleared.")
            }
            .safeAreaInset(edge: .bottom) {
                GameControls(engine: engine, nextTitle: "NEXT", simulateTaps: simulateTaps, onNext: recordAndAdvance)
            }
            .onDisappear {
                // Don't lose a finished attempt if the screen closes before NEXT
                if case .result = engine.phase { recordAndAdvance() }
                engine.reset()
            }
        }
    }

    private func currentMatch(_ tournament: Tournament) -> Match? {
        if let i = tournament.semifinals.firstIndex(where: { $0.winner == nil }) {
            return tournament.semifinals[i]
        }
        return tournament.championship
    }

    /// The attempt counts for the player whose turn it was, then the next player is up
    private func recordAndAdvance() {
        guard case .result(let attempt) = engine.phase else { return }
        store.tournament?.record(attempt)
        engine.nextTry()
    }
}

private func averageText(_ ms: Double?) -> String {
    guard let ms else { return "—" }
    return String(format: "%.3f", ms / 1000)
}

private struct StandingsList: View {
    let tournament: Tournament

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader("Qualifying")
                Spacer()
                Text("AVG ERROR")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.label)
                    .padding(.trailing, 16)
            }
            VStack(spacing: 0) {
                ForEach(Array(tournament.standings.enumerated()), id: \.element.player) { rank, standing in
                    let advancing = rank < tournament.advancingCount && standing.attempts > 0
                    HStack(spacing: 12) {
                        Text("\(rank + 1)")
                            .font(.subheadline.weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(advancing ? Theme.accent : Theme.label)
                            .frame(width: 24)
                        Text(tournament.players[standing.player])
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        AttemptDots(done: standing.attempts, total: Tournament.qualifyingAttempts)
                        Text(averageText(standing.meanMs))
                            .font(.body.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.text)
                            .frame(width: 64, alignment: .trailing)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                }
            }
            .card()
            Text("Top \(tournament.advancingCount) advance · early and late count the same")
                .font(.footnote)
                .foregroundStyle(Theme.label)
                .padding(.horizontal, 16)
        }
    }
}

private struct AttemptDots: View {
    let done: Int
    let total: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i < done ? Theme.accent : Theme.divider)
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityLabel("\(done) of \(total) tries")
    }
}

private struct MatchCard: View {
    let match: Match
    let players: [String]
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            Text(match.inSuddenDeath ? "\(title.uppercased()) · SUDDEN DEATH" : title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(Theme.accent)
            HStack {
                side(player: match.a, attempts: match.aAttempts)
                Text("VS")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(Theme.label)
                side(player: match.b, attempts: match.bAttempts)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .card()
    }

    private func side(player: Int, attempts: [GameAttempt]) -> some View {
        let mean = attempts.isEmpty ? nil : Double(attempts.map(\.absErrorMs).reduce(0, +)) / Double(attempts.count)
        let won = match.winner == player
        return VStack(spacing: 4) {
            Text(players[player])
                .font(.title3.weight(.heavy))
                .foregroundStyle(won ? Theme.accent : Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(averageText(mean))
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
            AttemptDots(done: attempts.count, total: match.attemptsEach)
        }
        .frame(maxWidth: .infinity)
    }
}

struct BracketView: View {
    let tournament: Tournament

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if tournament.semifinals.isEmpty && tournament.championship == nil {
                    Text("The bracket fills in after qualifying.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.label)
                        .padding(.top, 24)
                }
                ForEach(Array(tournament.semifinals.enumerated()), id: \.offset) { i, match in
                    MatchCard(match: match, players: tournament.players, title: "Semifinal \(i + 1)")
                }
                if let championship = tournament.championship {
                    MatchCard(match: championship, players: tournament.players, title: "Championship")
                }
                StandingsList(tournament: tournament)
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("Bracket")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ChampionView: View {
    @ObservedObject var store: TournamentStore

    var body: some View {
        if let tournament = store.tournament, let champion = tournament.champion, let match = tournament.championship {
            let attempts = champion == match.a ? match.aAttempts : match.bAttempts
            let mean = Double(attempts.map(\.absErrorMs).reduce(0, +)) / Double(max(attempts.count, 1))
            let allAttempts = tournament.qualifying[champion] + attempts
            let closest = allAttempts.min { $0.absErrorMs < $1.absErrorMs }

            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 24)
                    Text("GAME BREAK CHAMPION")
                        .font(.caption.weight(.bold))
                        .tracking(1.5)
                        .foregroundStyle(Theme.label)
                    Text(tournament.players[champion])
                        .font(.system(size: 48, weight: .heavy))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center)
                    HStack {
                        SessionStat(title: "Final avg error", value: averageText(mean))
                        if let closest {
                            SessionStat(title: "Closest try", value: GameBreakScoring.seconds(closest.elapsedMs))
                        }
                    }
                    MatchCard(match: match, players: tournament.players, title: "Championship")
                    NavigationLink {
                        BracketView(tournament: tournament)
                    } label: {
                        Text("View bracket")
                            .font(.headline)
                            .foregroundStyle(Theme.accent)
                    }
                }
                .padding(.horizontal, 16)
            }
            .navigationTitle("Champion")
            .safeAreaInset(edge: .bottom) {
                GameButton(title: "New tournament", primary: true) {
                    store.tournament = nil
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }
}

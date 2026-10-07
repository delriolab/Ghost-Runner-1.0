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
                    ModeCardLabel(title: "Free Play", subtitle: "Tap to start, tap when you think \(GameBreakScoring.targetText) is up")
                }
                NavigationLink {
                    DuelView(engine: engine, simulateTaps: simulateTaps)
                } label: {
                    ModeCardLabel(title: "1 v 1", subtitle: "Player 1 vs Player 2, 3 tries each")
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

/// "TARGET 4.000 s"
private struct TargetHeader: View {
    var size: CGFloat = 56

    var body: some View {
        VStack(spacing: 2) {
            Text("TARGET")
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(Theme.label)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(GameBreakScoring.targetText)
                    .font(.system(size: size, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                Text("s")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.label)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Target \(GameBreakScoring.targetText) seconds")
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
        if attempt.errorMs == 0 { return "RIGHT ON \(GameBreakScoring.targetText)" }
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

/// The score in big numbers under the red box; only shown with a result.
struct GameBreakScore: View {
    let phase: GameBreakEngine.Phase

    var body: some View {
        if case .result(let attempt) = phase {
            VStack(spacing: 0) {
                Text(attempt.isPerfect ? "PERFECT" : "SCORE")
                    .font(attempt.isPerfect ? .title2.weight(.heavy) : .headline.weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(attempt.isPerfect ? Theme.accent : Theme.label)
                Text("\(attempt.score)")
                    .font(.system(size: 120, weight: .heavy))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(attempt.isPerfect ? Theme.accent : Theme.text)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(attempt.isPerfect ? "Perfect, score \(attempt.score)" : "Score \(attempt.score)")
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

/// Reset while timing; Redo or Next after a result (Next also happens on its own);
/// and the developer tap simulator.
private struct GameControls: View {
    @ObservedObject var engine: GameBreakEngine
    let nextTitle: String
    let simulateTaps: Bool

    /// Nothing to show while ready or not ready (unless simulating), so no bar at all
    private var hasButtons: Bool {
        if simulateTaps { return true }
        switch engine.phase {
        case .timing, .result: return true
        default: return false
        }
    }

    var body: some View {
        if hasButtons { buttons }
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            switch engine.phase {
            case .timing:
                GameButton(title: "Reset") { engine.reset() }
            case .result:
                HStack(spacing: 10) {
                    GameButton(title: "Redo") { engine.redo() }
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        GameButton(title: nextLabel(at: context.date), primary: true) { engine.acceptResult() }
                    }
                }
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
        .frame(maxWidth: .infinity)
        .background(Theme.background)   // keeps scrolling lists from showing through
    }

    /// "NEXT TRY · 4"
    private func nextLabel(at now: Date) -> String {
        guard let deadline = engine.autoAdvanceAt else { return nextTitle }
        let seconds = max(1, Int(deadline.timeIntervalSince(now).rounded(.up)))
        return "\(nextTitle) · \(seconds)"
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
                GameBreakScore(phase: engine.phase)
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
            GameControls(engine: engine, nextTitle: "NEXT TRY", simulateTaps: simulateTaps)
        }
        .onAppear {
            engine.onAttemptAccepted = { attempts.append($0) }
        }
        .onDisappear {
            // Leave a clean slate for the next screen
            engine.reset()
            engine.acceptResult()
            engine.onAttemptAccepted = nil
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
                Text("Each player takes 3 tries in a row, then passes the puck. The 4 best average scores play the Final Four.")
                    .foregroundStyle(Theme.label)
            }

            Section {
                ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                    HStack {
                        Text("\(index + 1)")
                            .monospacedDigit()
                            .foregroundStyle(Theme.label)
                            .lineLimit(1)
                            .fixedSize()
                            .frame(minWidth: 28, alignment: .leading)
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
                store.start(players: names)
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
                    GameBreakScore(phase: engine.phase)

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
                        Button("Redo last attempt", systemImage: "arrow.uturn.backward") {
                            redoLastAttempt()
                        }
                        .disabled(!canRedo)
                        Button("End tournament", systemImage: "xmark.circle", role: .destructive) {
                            confirmEnd = true
                        }
                    }
                }
            }
            .confirmationDialog("End this tournament?", isPresented: $confirmEnd, titleVisibility: .visible) {
                Button("End tournament", role: .destructive) {
                    engine.reset()
                    engine.redo()
                    store.end()
                }
            } message: {
                Text("All scores will be cleared.")
            }
            .safeAreaInset(edge: .bottom) {
                GameControls(engine: engine, nextTitle: "NEXT", simulateTaps: simulateTaps)
            }
            .onAppear {
                // Each accepted attempt counts for whoever's turn it is
                engine.onAttemptAccepted = { store.record($0) }
            }
            .onDisappear {
                // Don't lose a finished attempt if the screen closes before it's accepted
                engine.acceptResult()
                engine.reset()
                engine.onAttemptAccepted = nil
            }
        }
    }

    private func currentMatch(_ tournament: Tournament) -> Match? {
        if let i = tournament.semifinals.firstIndex(where: { $0.winner == nil }) {
            return tournament.semifinals[i]
        }
        return tournament.championship
    }

    private var canRedo: Bool {
        if case .result = engine.phase { return true }
        return store.beforeLastAttempt != nil
    }

    /// A result on screen is simply thrown away; otherwise the last recorded attempt is taken back
    private func redoLastAttempt() {
        if case .result = engine.phase {
            engine.redo()
        } else {
            engine.reset()
            store.undoLastAttempt()
        }
    }
}


private struct StandingsList: View {
    let tournament: Tournament

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader("Qualifying")
                Spacer()
                Text("AVG SCORE")
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
                            .lineLimit(1)
                            .fixedSize()
                            .frame(minWidth: 28)
                        Text(tournament.players[standing.player])
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        AttemptDots(done: standing.attempts, total: Tournament.qualifyingAttempts)
                        Text(averageScoreText(standing.averageScore))
                            .font(.body.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .fixedSize()
                            .frame(minWidth: 52, alignment: .trailing)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                }
            }
            .card()
            Text("Top \(tournament.advancingCount) average scores advance")
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
        let average = attempts.isEmpty ? nil : Double(attempts.map(\.score).reduce(0, +)) / Double(attempts.count)
        let won = match.winner == player
        return VStack(spacing: 4) {
            Text(players[player])
                .font(.title3.weight(.heavy))
                .foregroundStyle(won ? Theme.accent : Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(averageScoreText(average))
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
            let average = Double(attempts.map(\.score).reduce(0, +)) / Double(max(attempts.count, 1))
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
                        SessionStat(title: "Final avg score", value: averageScoreText(average))
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
                VStack(spacing: 10) {
                    if store.beforeLastAttempt != nil {
                        GameButton(title: "Redo last attempt") { store.undoLastAttempt() }
                    }
                    GameButton(title: "New tournament", primary: true) { store.end() }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - 1 v 1

struct DuelView: View {
    @ObservedObject var engine: GameBreakEngine
    let simulateTaps: Bool
    @State private var duel = Duel()
    /// The match before the last recorded try, for "Redo last attempt"
    @State private var beforeLastAttempt: Duel?
    @State private var confirmRestart = false

    var body: some View {
        Group {
            if let winner = duel.winner {
                DuelWinnerView(duel: duel, winner: winner,
                               canRedo: beforeLastAttempt != nil,
                               onRedo: redoLastAttempt,
                               onRematch: restart)
            } else if let turn = duel.currentTurn {
                ScrollView {
                    VStack(spacing: 16) {
                        Text(turn.detail)
                            .font(.subheadline)
                            .foregroundStyle(Theme.label)
                        GameBreakPlayArea(phase: engine.phase, player: Duel.names[turn.player])
                        GameBreakScore(phase: engine.phase)
                        DuelScoreboard(duel: duel, upNow: turn.player)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .scrollBounceBehavior(.basedOnSize)
                .safeAreaInset(edge: .bottom) {
                    GameControls(engine: engine, nextTitle: "NEXT", simulateTaps: simulateTaps)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("Match options", systemImage: "ellipsis.circle") {
                            Button("Redo last attempt", systemImage: "arrow.uturn.backward", action: redoLastAttempt)
                                .disabled(!canRedo)
                            Button("Restart match", systemImage: "arrow.counterclockwise", role: .destructive) {
                                confirmRestart = true
                            }
                        }
                    }
                }
                .confirmationDialog("Restart this match?", isPresented: $confirmRestart, titleVisibility: .visible) {
                    Button("Restart match", role: .destructive, action: restart)
                } message: {
                    Text("Both players start over.")
                }
            }
        }
        .background(Theme.background)
        .navigationTitle("1 v 1")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            engine.onAttemptAccepted = { attempt in
                beforeLastAttempt = duel
                duel.record(attempt)
            }
        }
        .onDisappear {
            engine.acceptResult()
            engine.reset()
            engine.onAttemptAccepted = nil
        }
    }

    private var canRedo: Bool {
        if case .result = engine.phase { return true }
        return beforeLastAttempt != nil
    }

    /// A result on screen is thrown away; otherwise the last recorded try is taken back
    private func redoLastAttempt() {
        if case .result = engine.phase {
            engine.redo()
        } else if let previous = beforeLastAttempt {
            engine.reset()
            duel = previous
            beforeLastAttempt = nil
        }
    }

    private func restart() {
        engine.reset()
        engine.redo()
        duel = Duel()
        beforeLastAttempt = nil
    }
}

private func averageScoreText(_ value: Double?) -> String {
    guard let value else { return "—" }
    return String(format: "%.1f", value)
}

/// Both players side by side: average score, each try's score, and who's up.
private struct DuelScoreboard: View {
    let duel: Duel
    let upNow: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            column(0)
            column(1)
        }
    }

    private func column(_ player: Int) -> some View {
        let isUp = upNow == player
        let tries = duel.attempts[player]
        return VStack(spacing: 6) {
            Text(Duel.names[player].uppercased())
                .font(.caption.weight(.heavy))
                .tracking(1)
                .foregroundStyle(isUp ? Theme.accent : Theme.label)
            Text(averageScoreText(duel.averageScore(player)))
                .font(.system(size: 40, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
            Text("AVG SCORE")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.label)
            HStack(spacing: 6) {
                ForEach(0..<Duel.attemptsEach, id: \.self) { i in
                    Text(i < tries.count ? "\(tries[i].score)" : "–")
                        .font(.footnote.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(i < tries.count ? Theme.text : Theme.label)
                        .frame(minWidth: 32, minHeight: 26)
                        .background(Theme.background, in: Capsule())
                }
            }
            if !duel.suddenDeath[player].isEmpty {
                Text("Sudden death: " + duel.suddenDeath[player].map { "\($0.score)" }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(Theme.label)
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(isUp ? Theme.accent : Theme.divider, lineWidth: isUp ? 2 : 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct DuelWinnerView: View {
    let duel: Duel
    let winner: Int
    let canRedo: Bool
    let onRedo: () -> Void
    let onRematch: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 24)
                Text(Duel.names[winner].uppercased() + " WINS")
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                if duel.averageScore(0) == duel.averageScore(1) {
                    Text("Won in sudden death")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.label)
                }
                DuelScoreboard(duel: duel, upNow: nil)
            }
            .padding(.horizontal, 16)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if canRedo {
                    GameButton(title: "Redo last attempt", action: onRedo)
                }
                GameButton(title: "Rematch", primary: true, action: onRematch)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }
}

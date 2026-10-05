import Foundation
import Combine

// MARK: - Game Break tournament
//
// Qualifying: 3 attempts each, taken in rotation through the lineup, ranked
// by mean absolute error from 4.200 s (best single attempt breaks ties, then
// sudden death). Top 4 play semifinals (#1 v #4, #2 v #3, 3 attempts each,
// alternating); the winners play a 5-attempt championship. With 2-3 players
// the top 2 go straight to the championship. Any tied match goes to sudden
// death: one attempt each per round until one is closer.

struct Tournament: Codable, Equatable {
    static let qualifyingAttempts = 3
    static let semifinalAttempts = 3
    static let finalAttempts = 5
    static let minimumPlayers = 2

    var players: [String]
    /// Qualifying attempts per player, in lineup order
    var qualifying: [[GameAttempt]]
    /// Sudden death for the last advancing spot(s), if qualifying ended tied
    var playoff: Playoff?
    /// Seeds in order once qualifying is settled
    var seeds: [Int]?
    var semifinals: [Match] = []
    var championship: Match?

    init(players: [String]) {
        self.players = players
        self.qualifying = Array(repeating: [], count: players.count)
    }

    // MARK: Turns

    struct Turn: Equatable {
        let player: Int
        let stage: String
        let detail: String
    }

    var currentTurn: Turn? {
        if let turn = qualifyingTurn { return turn }
        if let playoff, let player = playoff.nextPlayer {
            return Turn(player: player, stage: "Playoff", detail: "Sudden death for a spot · round \(playoff.roundNumber)")
        }
        for (i, match) in semifinals.enumerated() {
            if let turn = match.nextTurn(stage: "Semifinal \(i + 1)") { return turn }
        }
        if let championship, let turn = championship.nextTurn(stage: "Championship") { return turn }
        return nil
    }

    private var qualifyingTurn: Turn? {
        let taken = qualifying.reduce(0) { $0 + $1.count }
        let total = players.count * Self.qualifyingAttempts
        guard taken < total, !players.isEmpty else { return nil }
        let round = taken / players.count
        return Turn(player: taken % players.count,
                    stage: "Qualifying",
                    detail: "Round \(round + 1) of \(Self.qualifyingAttempts)")
    }

    var isFinished: Bool { champion != nil }

    var champion: Int? { championship?.winner }

    // MARK: Recording

    mutating func record(_ attempt: GameAttempt) {
        guard let turn = currentTurn else { return }

        if qualifyingTurn != nil {
            qualifying[turn.player].append(attempt)
            if qualifyingTurn == nil { settleQualifying() }
            return
        }
        if playoff != nil {
            playoff!.record(attempt, for: turn.player)
            if let winners = playoff!.decidedWinners {
                seeds = (seeds ?? []) + winners
                playoff = nil
                startBracket()
            }
            return
        }
        if let i = semifinals.firstIndex(where: { $0.winner == nil }) {
            semifinals[i].record(attempt, for: turn.player)
            if semifinals.allSatisfy({ $0.winner != nil }), championship == nil {
                championship = Match(a: semifinals[0].winner!, b: semifinals[1].winner!, attemptsEach: Self.finalAttempts)
            }
            return
        }
        championship?.record(attempt, for: turn.player)
    }

    // MARK: Standings

    struct Standing: Equatable {
        let player: Int
        let attempts: Int
        /// Mean absolute error in ms, nil before the first attempt
        let meanMs: Double?
        let bestMs: Int?
    }

    /// Qualifying standings: closest average first; players without attempts last
    var standings: [Standing] {
        players.indices.map { i in
            let errors = qualifying[i].map(\.absErrorMs)
            return Standing(player: i,
                            attempts: errors.count,
                            meanMs: errors.isEmpty ? nil : Double(errors.reduce(0, +)) / Double(errors.count),
                            bestMs: errors.min())
        }
        .sorted { a, b in
            switch (a.meanMs, b.meanMs) {
            case let (x?, y?) where x != y: return x < y
            case (nil, _?): return false
            case (_?, nil): return true
            default: break
            }
            if let x = a.bestMs, let y = b.bestMs, x != y { return x < y }
            return a.player < b.player
        }
    }

    var advancingCount: Int { players.count >= 4 ? 4 : 2 }

    private mutating func settleQualifying() {
        let order = standings
        let spots = min(advancingCount, order.count)
        func key(_ s: Standing) -> [Double] { [s.meanMs ?? .infinity, Double(s.bestMs ?? .max)] }

        // Tied across the cutoff on both average and best attempt: sudden death for those spots
        if order.count > spots, key(order[spots - 1]) == key(order[spots]) {
            let tieKey = key(order[spots - 1])
            let ahead = order.prefix(spots).filter { key($0) != tieKey }.map(\.player)
            let tied = order.filter { key($0) == tieKey }.map(\.player)
            seeds = ahead
            playoff = Playoff(contenders: tied, spots: spots - ahead.count)
        } else {
            seeds = order.prefix(spots).map(\.player)
            startBracket()
        }
    }

    private mutating func startBracket() {
        guard let seeds else { return }
        if seeds.count >= 4 {
            semifinals = [
                Match(a: seeds[0], b: seeds[3], attemptsEach: Self.semifinalAttempts),
                Match(a: seeds[1], b: seeds[2], attemptsEach: Self.semifinalAttempts),
            ]
        } else if seeds.count >= 2 {
            championship = Match(a: seeds[0], b: seeds[1], attemptsEach: Self.finalAttempts)
        }
    }
}

// MARK: - Head-to-head match

struct Match: Codable, Equatable {
    let a: Int
    let b: Int
    let attemptsEach: Int
    var aAttempts: [GameAttempt] = []
    var bAttempts: [GameAttempt] = []
    var suddenDeathA: [GameAttempt] = []
    var suddenDeathB: [GameAttempt] = []

    var aTotalMs: Int { aAttempts.map(\.absErrorMs).reduce(0, +) }
    var bTotalMs: Int { bAttempts.map(\.absErrorMs).reduce(0, +) }

    var regulationDone: Bool {
        aAttempts.count >= attemptsEach && bAttempts.count >= attemptsEach
    }

    var inSuddenDeath: Bool { regulationDone && aTotalMs == bTotalMs && winner == nil }

    /// Lower total (same as lower average) wins; a tie goes to sudden death
    var winner: Int? {
        guard regulationDone else { return nil }
        if aTotalMs != bTotalMs { return aTotalMs < bTotalMs ? a : b }
        for (x, y) in zip(suddenDeathA, suddenDeathB) where x.absErrorMs != y.absErrorMs {
            return x.absErrorMs < y.absErrorMs ? a : b
        }
        return nil
    }

    func nextTurn(stage: String) -> Tournament.Turn? {
        guard winner == nil else { return nil }
        if !regulationDone {
            // Alternate A, B, A, B ...
            let player = aAttempts.count <= bAttempts.count ? a : b
            let number = (player == a ? aAttempts.count : bAttempts.count) + 1
            return Tournament.Turn(player: player, stage: stage, detail: "Attempt \(number) of \(attemptsEach)")
        }
        let player = suddenDeathA.count <= suddenDeathB.count ? a : b
        return Tournament.Turn(player: player, stage: stage, detail: "Sudden death")
    }

    mutating func record(_ attempt: GameAttempt, for player: Int) {
        if !regulationDone {
            if player == a { aAttempts.append(attempt) } else { bAttempts.append(attempt) }
        } else {
            if player == a { suddenDeathA.append(attempt) } else { suddenDeathB.append(attempt) }
        }
    }
}

// MARK: - Sudden-death playoff for qualifying spots

struct Playoff: Codable, Equatable {
    /// Players still tied, in lineup order
    var contenders: [Int]
    /// How many of them advance
    var spots: Int
    /// Winners decided so far, best first
    var winners: [Int] = []
    /// This round's attempt for each contender, in the same order
    var round: [GameAttempt?]
    var roundNumber = 1

    init(contenders: [Int], spots: Int) {
        self.contenders = contenders
        self.spots = spots
        self.round = Array(repeating: nil, count: contenders.count)
    }

    var nextPlayer: Int? {
        guard decidedWinners == nil, let i = round.firstIndex(where: { $0 == nil }) else { return nil }
        return contenders[i]
    }

    /// Set once every spot is filled
    var decidedWinners: [Int]? { spots <= 0 ? winners : nil }

    mutating func record(_ attempt: GameAttempt, for player: Int) {
        guard let i = contenders.firstIndex(of: player) else { return }
        round[i] = attempt
        guard round.allSatisfy({ $0 != nil }) else { return }

        // Round complete: rank this round's errors
        let ranked = zip(contenders, round.map { $0!.absErrorMs }).sorted { $0.1 < $1.1 }
        if ranked.count > spots, ranked[spots - 1].1 == ranked[spots].1 {
            // Still tied at the cutoff: those clearly ahead advance, the tied ones go again
            let tieError = ranked[spots - 1].1
            let ahead = ranked.filter { $0.1 < tieError }.map(\.0)
            winners += ahead
            spots -= ahead.count
            contenders = ranked.filter { $0.1 == tieError }.map(\.0).sorted()
            round = Array(repeating: nil, count: contenders.count)
            roundNumber += 1
        } else {
            winners += ranked.prefix(spots).map(\.0)
            spots = 0
        }
    }
}

// MARK: - Saved tournament

/// Keeps the tournament in progress on the phone so closing the app doesn't lose it.
@MainActor
final class TournamentStore: ObservableObject {
    private static let key = "gameBreakTournament"

    @Published var tournament: Tournament? {
        didSet { save() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key) {
            tournament = try? JSONDecoder().decode(Tournament.self, from: data)
        }
    }

    private func save() {
        if let tournament, let data = try? JSONEncoder().encode(tournament) {
            UserDefaults.standard.set(data, forKey: Self.key)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.key)
        }
    }
}

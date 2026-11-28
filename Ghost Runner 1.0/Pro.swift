import Foundation
import SwiftData

// MARK: - Ghost Runner Pro
//
// Pro records each rep: who was fielding and whether they got the out. Everything Pro is behind
// `ProAccess.enabledKey` (off by default) and keeps its data in its own store, which isn't opened
// unless Pro is on, so the free app trains exactly as before.

enum ProAccess {
    /// Until the subscription exists, a test switch in Settings
    static let enabledKey = "proEnabled"
}

/// When a rep is decided. Only "safe" is called; a rep with no call is an out.
enum RepCall {
    /// A rep with no "safe" becomes an out this long after the buzzer (or at the next bat strike)
    static let callAfterBuzzer: TimeInterval = 8
    /// A late "safe" still fixes a rep just logged as an out, until the next bat strike
    static let lateSafe: TimeInterval = 15

    /// When an uncalled rep is logged as an out
    static func outDeadline(start: Date, runnerTime: Double) -> Date {
        start.addingTimeInterval(runnerTime + callAfterBuzzer)
    }

    static func canChangeToSafe(loggedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(loggedAt) <= lateSafe
    }
}

/// Defensive positions, in scorebook order
enum Position: String, CaseIterable, Identifiable, Codable {
    case pitcher = "P", catcher = "C", first = "1B", second = "2B", third = "3B"
    case shortstop = "SS", left = "LF", center = "CF", right = "RF"

    var id: String { rawValue }

    /// Scorebook number: pitcher 1 … right field 9
    var number: Int { Self.allCases.firstIndex(of: self)! + 1 }

    init?(number: Int) {
        guard (1...9).contains(number) else { return nil }
        self = Self.allCases[number - 1]
    }

    /// "6 · Shortstop"
    var numberedTitle: String { "\(number) · \(title)" }

    var title: String {
        switch self {
        case .pitcher: "Pitcher"
        case .catcher: "Catcher"
        case .first: "1st base"
        case .second: "2nd base"
        case .third: "3rd base"
        case .shortstop: "Shortstop"
        case .left: "Left field"
        case .center: "Center field"
        case .right: "Right field"
        }
    }
}

/// Double plays the coach can call. Where the ball is fielded decides the route:
/// 5-4-3, 6-4-3, 4-6-3, 3-6-3. The ghost runner is the batter going to first.
enum DoublePlay {
    /// "Turn two" then a number within this long is that double play
    static let followUp: TimeInterval = 4

    /// Fielded at, in the order they're listed
    static let starts: [Position] = [.third, .shortstop, .second, .first]

    static func route(from start: Position) -> [Position]? {
        switch start {
        case .third: [.third, .second, .first]
        case .shortstop: [.shortstop, .second, .first]
        case .second: [.second, .shortstop, .first]
        case .first: [.first, .shortstop, .first]
        default: nil
        }
    }

    /// "6-4-3"
    static func name(from start: Position) -> String? {
        route(from: start)?.map { String($0.number) }.joined(separator: "-")
    }

    /// "six four three", for Say it back
    static func spoken(from start: Position) -> String? {
        let words = ["", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
        return route(from: start)?.map { words[$0.number] }.joined(separator: " ")
    }
}

/// How the rep ended. Errors count as safe but are kept apart so coaches can see why.
enum RepOutcome: String, CaseIterable, Codable {
    case out, safe, gloveError, throwingError

    var title: String {
        switch self {
        case .out: "Out"
        case .safe: "Safe"
        case .gloveError: "Glove error"
        case .throwingError: "Throwing error"
        }
    }

    var isOut: Bool { self == .out }
}

// MARK: - Stored data
// Every property has a default and relationships are avoided, so the store can sync with iCloud later.

@Model
final class Player {
    var id: UUID = UUID()
    var name: String = ""
    /// Jersey number, optional
    var number: String = ""
    /// Main position (Position raw value), optional
    var positionRaw: String = ""
    var createdAt: Date = Date()

    init(name: String, number: String = "", position: Position? = nil) {
        self.name = name
        self.number = number
        self.positionRaw = position?.rawValue ?? ""
    }

    var position: Position? {
        get { Position(rawValue: positionRaw) }
        set { positionRaw = newValue?.rawValue ?? "" }
    }

    /// "Jake #7"
    var displayName: String { number.isEmpty ? name : "\(name) #\(number)" }
}

@Model
final class Rep {
    var id: UUID = UUID()
    var date: Date = Date()
    /// Who was fielding; nil for the whole team
    var playerID: UUID?
    /// The player's name when the rep was logged, so history reads right after a rename or delete
    var playerName: String = ""
    var positionRaw: String = ""
    var sportRaw: String = ""
    var category: String = ""
    var drill: String = ""
    var intensityRaw: String = ""
    /// Ghost runner time in seconds
    var runnerTime: Double = 0
    var usedCustomTime: Bool = false
    var outcomeRaw: String = RepOutcome.out.rawValue
    /// "6-4-3" for a double play rep; empty otherwise
    var play: String = ""

    init(_ pending: PendingRep, outcome: RepOutcome, at date: Date = Date()) {
        self.date = date
        self.playerID = pending.fielder.playerID
        self.playerName = pending.playerName
        self.positionRaw = pending.position?.rawValue ?? ""
        self.play = pending.play
        self.sportRaw = pending.sport.rawValue
        self.category = pending.category
        self.drill = pending.drill
        self.intensityRaw = pending.intensity.rawValue
        self.runnerTime = pending.runnerTime
        self.usedCustomTime = pending.usedCustomTime
        self.outcomeRaw = outcome.rawValue
    }

    var outcome: RepOutcome { RepOutcome(rawValue: outcomeRaw) ?? .out }
    var position: Position? { Position(rawValue: positionRaw) }
    var intensity: Intensity? { Intensity(rawValue: intensityRaw) }

    /// "Jake #7 · SS", "6 · Shortstop", "6-4-3 double play", or "Team"
    var fielderLabel: String {
        if !play.isEmpty { return "\(play) double play" }
        return switch (playerName.isEmpty, position) {
        case (false, let position?): "\(playerName) · \(position.rawValue)"
        case (false, nil): playerName
        case (true, let position?): position.numberedTitle
        case (true, nil): "Team"
        }
    }
}

// MARK: - Who's fielding

/// The coach's pick of who is up: the whole team, a position, or a player. Saved as a string.
enum Fielder: Equatable {
    case team
    case position(Position)
    /// A double play fielded at this position (5-4-3 from third, and so on)
    case doublePlay(Position)
    case player(UUID)

    init(rawValue: String) {
        if rawValue.hasPrefix("position:"), let p = Position(rawValue: String(rawValue.dropFirst(9))) {
            self = .position(p)
        } else if rawValue.hasPrefix("doublePlay:"), let p = Position(rawValue: String(rawValue.dropFirst(11))),
                  DoublePlay.route(from: p) != nil {
            self = .doublePlay(p)
        } else if rawValue.hasPrefix("player:"), let id = UUID(uuidString: String(rawValue.dropFirst(7))) {
            self = .player(id)
        } else {
            self = .team
        }
    }

    var rawValue: String {
        switch self {
        case .team: "team"
        case .position(let p): "position:\(p.rawValue)"
        case .doublePlay(let p): "doublePlay:\(p.rawValue)"
        case .player(let id): "player:\(id.uuidString)"
        }
    }

    /// The double play for this fielder's spot, if there is one ("turn two" with 6 up → 6-4-3)
    var turningTwo: Fielder? {
        switch self {
        case .position(let p), .doublePlay(let p):
            DoublePlay.route(from: p) == nil ? nil : .doublePlay(p)
        case .team, .player:
            nil
        }
    }

    /// "Whole team", "6 · Shortstop", "6-4-3 double play" (players aren't shown for now)
    var title: String {
        switch self {
        case .team, .player: "Whole team"
        case .position(let p): p.numberedTitle
        case .doublePlay(let p): "\(DoublePlay.name(from: p) ?? "") double play"
        }
    }

    var playerID: UUID? {
        if case .player(let id) = self { return id }
        return nil
    }
}

/// A rep that has started (the bat strike) but has no outcome yet. Captures the setup at that moment.
struct PendingRep: Equatable {
    let fielder: Fielder
    let playerName: String
    let position: Position?
    /// "6-4-3" for a double play; empty otherwise
    let play: String
    let sport: Sport
    let category: String
    let drill: String
    let intensity: Intensity
    let runnerTime: Double
    let usedCustomTime: Bool

    init(fielder: Fielder, players: [Player], sport: Sport, category: String, drill: String,
         intensity: Intensity, runnerTime: Double, usedCustomTime: Bool) {
        // A player who has since been deleted counts for the team
        let player = fielder.playerID.flatMap { id in players.first { $0.id == id } }
        self.fielder = player == nil && fielder.playerID != nil ? .team : fielder
        self.playerName = player?.displayName ?? ""
        switch fielder {
        case .position(let p): self.position = p
        case .doublePlay(let p): self.position = p
        case .player: self.position = player?.position
        case .team: self.position = nil
        }
        if case .doublePlay(let p) = fielder {
            self.play = DoublePlay.name(from: p) ?? ""
        } else {
            self.play = ""
        }
        self.sport = sport
        self.category = category
        self.drill = drill
        self.intensity = intensity
        self.runnerTime = runnerTime
        self.usedCustomTime = usedCustomTime
    }
}

extension PendingRep {
    /// The same rep credited to someone else, e.g. when the coach names the fielder in the call
    func crediting(_ fielder: Fielder, players: [Player]) -> PendingRep {
        PendingRep(fielder: fielder, players: players, sport: sport, category: category, drill: drill,
                   intensity: intensity, runnerTime: runnerTime, usedCustomTime: usedCustomTime)
    }
}

// MARK: - Totals

struct RepTally: Equatable {
    var reps = 0
    var outs = 0
    var safe = 0
    var gloveErrors = 0
    var throwingErrors = 0

    init(_ outcomes: [RepOutcome] = []) {
        for outcome in outcomes { add(outcome) }
    }

    mutating func add(_ outcome: RepOutcome) {
        reps += 1
        switch outcome {
        case .out: outs += 1
        case .safe: safe += 1
        case .gloveError: gloveErrors += 1
        case .throwingError: throwingErrors += 1
        }
    }

    /// Share of reps that were outs, 0...1; nil with no reps
    var outRate: Double? { reps == 0 ? nil : Double(outs) / Double(reps) }

    /// "75%" or "—"
    var outRateText: String { outRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—" }
}

// MARK: - Store

/// Opens Pro's own database the first time Pro needs it. The free app never opens it.
@MainActor
final class ProStore {
    static let shared = ProStore()

    private var opened: ModelContainer?
    private let inMemory: Bool

    init(inMemory: Bool = false) {
        self.inMemory = inMemory
    }

    /// nil if the database can't be opened; Pro then simply doesn't record
    var container: ModelContainer? {
        if let opened { return opened }
        let config = ModelConfiguration("GhostRunnerPro", isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        opened = try? ModelContainer(for: Player.self, Rep.self, configurations: config)
        return opened
    }

    func players() -> [Player] {
        guard let context = container?.mainContext else { return [] }
        let all = (try? context.fetch(FetchDescriptor<Player>())) ?? []
        return all.sorted(by: Self.rosterOrder)
    }

    /// Saves the rep and returns it (for Undo)
    @discardableResult
    func record(_ pending: PendingRep, outcome: RepOutcome, at date: Date = Date()) -> Rep? {
        guard let context = container?.mainContext else { return nil }
        let rep = Rep(pending, outcome: outcome, at: date)
        context.insert(rep)
        try? context.save()
        return rep
    }

    func change(_ rep: Rep, to outcome: RepOutcome) {
        rep.outcomeRaw = outcome.rawValue
        try? container?.mainContext.save()
    }

    func delete(_ rep: Rep) {
        guard let context = container?.mainContext else { return }
        context.delete(rep)
        try? context.save()
    }

    /// Roster order: numbered players by number, then everyone else by name
    nonisolated static func rosterOrder(_ a: Player, _ b: Player) -> Bool {
        switch (Int(a.number), Int(b.number)) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}

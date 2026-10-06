//
//  Ghost_Runner_1_0Tests.swift
//  Ghost Runner 1.0Tests
//

import Foundation
import Testing
@testable import Ghost_Runner_1_0

struct StandardTimesTests {

    @Test(arguments: Sport.allCases)
    func everySetupHasATime(sport: Sport) {
        let times = StandardTimes.table(for: sport)
        for category in times.categories {
            for drill in times.drills {
                for intensity in Intensity.allCases {
                    let time = StandardTimes.time(sport: sport, category: category, drill: drill, intensity: intensity)
                    #expect(time != nil, "\(sport.title) \(category) \(drill) \(intensity.title) has no time")
                    #expect((time ?? 0) > 0, "\(sport.title) \(category) \(drill) \(intensity.title) must be positive")
                }
            }
        }
    }

    @Test(arguments: Sport.allCases)
    func harderIntensityIsNeverSlower(sport: Sport) {
        let times = StandardTimes.table(for: sport)
        for (category, drills) in times.times {
            for (drill, set) in drills {
                #expect(set.routine >= set.pressure, "\(sport.title) \(category) \(drill): Routine faster than Pressure")
                #expect(set.pressure >= set.hairOnFire, "\(sport.title) \(category) \(drill): Pressure faster than Hair on fire")
            }
        }
    }

    @Test(arguments: Sport.allCases)
    func defaultsExist(sport: Sport) {
        let times = StandardTimes.table(for: sport)
        #expect(times.categories.contains(times.defaultCategory))
        #expect(times.drills.contains(StandardTimes.defaultDrill))
    }
}

struct BatteryTests {

    @Test func readsBatteryLevelByte() {
        #expect(BLEManager.batteryPercent(from: Data([82])) == 82)
        #expect(BLEManager.batteryPercent(from: Data([0])) == 0)
        #expect(BLEManager.batteryPercent(from: Data([100])) == 100)
    }

    @Test func clampsOutOfRangeAndIgnoresEmptyValues() {
        #expect(BLEManager.batteryPercent(from: Data([255])) == 100)
        #expect(BLEManager.batteryPercent(from: Data()) == nil)
        #expect(BLEManager.batteryPercent(from: nil) == nil)
    }

    @Test func lowBatteryAtOrBelowTwentyPercent() {
        #expect(BatteryDisplay.isLow(20))
        #expect(BatteryDisplay.isLow(5))
        #expect(!BatteryDisplay.isLow(21))
    }

    @Test func symbolTracksLevel() {
        #expect(BatteryDisplay.symbol(for: 5) == "battery.0percent")
        #expect(BatteryDisplay.symbol(for: 25) == "battery.25percent")
        #expect(BatteryDisplay.symbol(for: 50) == "battery.50percent")
        #expect(BatteryDisplay.symbol(for: 80) == "battery.75percent")
        #expect(BatteryDisplay.symbol(for: 100) == "battery.100percent")
    }
}

struct CustomTimeTests {

    @Test func stepsByFiveHundredths() {
        #expect(CustomTime.adjusted(4.30, bySteps: 1) == 4.35)
        #expect(CustomTime.adjusted(4.30, bySteps: -1) == 4.25)
        #expect(CustomTime.adjusted(4.30, bySteps: -6) == 4.00)
    }

    @Test func snapsOffStepValuesToTheNearestStep() {
        #expect(CustomTime.adjusted(4.32, bySteps: 0) == 4.30)
        #expect(CustomTime.adjusted(4.33, bySteps: 0) == 4.35)
    }

    @Test func staysWithinRange() {
        #expect(CustomTime.adjusted(CustomTime.range.lowerBound, bySteps: -1) == CustomTime.range.lowerBound)
        #expect(CustomTime.adjusted(CustomTime.range.upperBound, bySteps: 1) == CustomTime.range.upperBound)
        #expect(CustomTime.adjusted(0, bySteps: 0) == CustomTime.range.lowerBound)
    }

    @Test func batteryWarningAtOrBelowFifteenPercent() {
        #expect(BatteryDisplay.needsWarning(15))
        #expect(BatteryDisplay.needsWarning(3))
        #expect(!BatteryDisplay.needsWarning(16))
    }
}

private let T = GameBreakScoring.targetMs

struct GameBreakScoringTests {

    @Test func scoresMatchTheAgreedPoints() {
        #expect(GameBreakScoring.score(absErrorMs: 0) == 100)
        #expect(GameBreakScoring.score(absErrorMs: 10) == 100)
        #expect(GameBreakScoring.score(absErrorMs: 25) == 95)
        #expect(GameBreakScoring.score(absErrorMs: 50) == 90)
        #expect(GameBreakScoring.score(absErrorMs: 100) == 80)
        #expect(GameBreakScoring.score(absErrorMs: 200) == 60)
        #expect(GameBreakScoring.score(absErrorMs: 500) == 0)
        #expect(GameBreakScoring.score(absErrorMs: 900) == 0)
    }

    @Test func interpolatesBetweenPoints() {
        #expect(GameBreakScoring.score(absErrorMs: 27) == 95)   // 94.6
        #expect(GameBreakScoring.score(absErrorMs: 36) == 93)   // 92.8
        #expect(GameBreakScoring.score(absErrorMs: 350) == 30)
    }

    @Test func earlyAndLateScoreTheSame() {
        #expect(GameAttempt(elapsedMs: (T - 27)).score == GameAttempt(elapsedMs: (T + 27)).score)
        #expect(GameAttempt(elapsedMs: (T - 27)).errorMs == -27)
        #expect(GameAttempt(elapsedMs: (T + 36)).errorMs == 36)
        #expect(GameAttempt(elapsedMs: (T + 9)).isPerfect)
        #expect(!GameAttempt(elapsedMs: (T + 11)).isPerfect)
    }

    @Test func puckClockElapsedHandlesWraparound() {
        #expect(GameBreakScoring.puckElapsedMs(from: 3000, to: 7213) == 4213)
        let nearWrap = GameBreakScoring.puckClockPeriod - 1000
        #expect(GameBreakScoring.puckElapsedMs(from: nearWrap, to: 3200) == 4200)
    }

    @Test func formatsSeconds() {
        #expect(GameBreakScoring.seconds(4173) == "4.173")
        #expect(GameBreakScoring.seconds(27) == "0.027")
    }
}

@MainActor
struct GameBreakEngineTests {

    private func tap(_ ms: Int) -> GameTap { GameTap(puckMs: ms, receivedAt: .now) }

    @Test func readyOnlyAfterThePuckConfirmsGameMode() {
        let engine = GameBreakEngine()
        engine.updateAvailability(connected: true, confirmed: false, failed: false, simulated: false)
        #expect(engine.phase == .notReady(.confirming))
        engine.handleTap(tap(1000))
        #expect(engine.phase == .notReady(.confirming))   // taps ignored until confirmed
        engine.updateAvailability(connected: true, confirmed: true, failed: false, simulated: false)
        #expect(engine.phase == .ready)
    }

    @Test func noConfirmationMeansFirmwareUpdate() {
        let engine = GameBreakEngine()
        engine.updateAvailability(connected: true, confirmed: false, failed: true, simulated: false)
        #expect(engine.phase == .notReady(.needsFirmware))
    }

    @Test func twoTapsTimeAnAttemptFromThePuckClock() {
        let engine = GameBreakEngine()
        engine.updateAvailability(connected: true, confirmed: true, failed: false, simulated: false)
        engine.handleTap(tap(3000))
        #expect(engine.phase == .timing)
        engine.handleTap(tap(3000 + T - 27))
        #expect(engine.phase == .result(GameAttempt(elapsedMs: (T - 27))))
        engine.handleTap(tap(9000))                         // ignored while showing the result
        #expect(engine.phase == .result(GameAttempt(elapsedMs: (T - 27))))
        #expect(engine.autoAdvanceAt != nil)                // next try starts on its own
        engine.acceptResult()
        #expect(engine.phase == .ready)
        #expect(engine.autoAdvanceAt == nil)
    }

    @Test func doubleTapRightAfterTheStartIsIgnored() {
        let engine = GameBreakEngine()
        engine.updateAvailability(connected: true, confirmed: true, failed: false, simulated: false)
        engine.handleTap(tap(1000))
        engine.handleTap(tap(1080))                         // bounce
        engine.handleTap(tap(1000 + GameBreakEngine.stopLockoutMs - 1))   // still inside the lockout
        #expect(engine.phase == .timing)
        engine.handleTap(tap(1000 + T))
        #expect(engine.phase == .result(GameAttempt(elapsedMs: T)))
    }

    @Test func acceptedAttemptsAreReportedButRedoneOnesAreNot() {
        let engine = GameBreakEngine()
        var accepted: [GameAttempt] = []
        engine.onAttemptAccepted = { accepted.append($0) }
        engine.updateAvailability(connected: true, confirmed: true, failed: false, simulated: false)

        engine.handleTap(tap(0)); engine.handleTap(tap(GameBreakEngine.stopLockoutMs + 400))   // accidental early stop
        engine.redo()
        #expect(engine.phase == .ready)
        #expect(accepted.isEmpty)

        engine.handleTap(tap(10_000)); engine.handleTap(tap(10_000 + T - 10))
        engine.acceptResult()
        #expect(accepted == [GameAttempt(elapsedMs: (T - 10))])
    }

    @Test func resetCancelsAnAccidentalStart() {
        let engine = GameBreakEngine()
        engine.updateAvailability(connected: true, confirmed: true, failed: false, simulated: false)
        engine.handleTap(tap(100))
        engine.reset()
        #expect(engine.phase == .ready)
        engine.handleTap(tap(500))
        engine.handleTap(tap(500 + T))
        #expect(engine.phase == .result(GameAttempt(elapsedMs: T)))
    }

    @Test func disconnectCancelsAnAttempt() {
        let engine = GameBreakEngine()
        engine.updateAvailability(connected: true, confirmed: true, failed: false, simulated: false)
        engine.handleTap(tap(100))
        engine.updateAvailability(connected: false, confirmed: false, failed: false, simulated: false)
        #expect(engine.phase == .notReady(.disconnected))
        engine.updateAvailability(connected: true, confirmed: true, failed: false, simulated: false)
        #expect(engine.phase == .ready)                     // starts fresh, no stale first tap
    }
}

struct TournamentTests {

    private func attempt(_ errorMs: Int) -> GameAttempt { GameAttempt(elapsedMs: GameBreakScoring.targetMs + errorMs) }

    /// Plays the current turn with the error chosen for that player
    private func play(_ t: inout Tournament, _ errors: [String: Int]) {
        let turn = t.currentTurn!
        t.record(attempt(errors[t.players[turn.player]]!))
    }

    @Test func eachPlayerTakesAllThreeQualifyingTriesInARow() {
        var t = Tournament(players: ["A", "B", "C"])
        var order: [String] = []
        for _ in 0..<9 {
            order.append(t.players[t.currentTurn!.player])
            t.record(attempt(10))
        }
        #expect(order == ["A", "A", "A", "B", "B", "B", "C", "C", "C"])
    }

    @Test func topFourSeedIntoSemifinalsByMeanAbsoluteError() {
        let errors = ["P1": 5, "P2": -12, "P3": 20, "P4": -30, "P5": 40, "P6": 80]
        var t = Tournament(players: ["P6", "P5", "P4", "P3", "P2", "P1"])
        for _ in 0..<18 { play(&t, errors) }
        #expect(t.seeds?.map { t.players[$0] } == ["P1", "P2", "P3", "P4"])
        #expect(t.semifinals.count == 2)
        #expect(t.players[t.semifinals[0].a] == "P1" && t.players[t.semifinals[0].b] == "P4")
        #expect(t.players[t.semifinals[1].a] == "P2" && t.players[t.semifinals[1].b] == "P3")
    }

    @Test func earlyAndLateDoNotCancelOut() {
        // 100 early then 100 late averages 100 off, not 0
        var t = Tournament(players: ["Swing", "Steady"])
        for e in [-100, 100, 0] { t.record(attempt(e)) }      // Swing: averages 0 signed, 67 ms off
        for e in [30, -30, 30] { t.record(attempt(e)) }       // Steady: 30 ms off
        #expect(t.standings.first.map { t.players[$0.player] } == "Steady")
    }

    @Test func semifinalPlayersTakeTheirTriesInARowAndChampionshipIsFiveEach() {
        let errors = ["A": 5, "B": 10, "C": 15, "D": 20]
        var t = Tournament(players: ["A", "B", "C", "D"])
        for _ in 0..<12 { play(&t, errors) }
        var semiOrder: [String] = []
        for _ in 0..<6 {
            semiOrder.append(t.players[t.currentTurn!.player])
            play(&t, errors)
        }
        #expect(semiOrder == ["A", "A", "A", "D", "D", "D"])
        for _ in 0..<6 { play(&t, errors) }
        #expect(t.championship?.attemptsEach == 5)
        for _ in 0..<10 { play(&t, errors) }
        #expect(t.champion.map { t.players[$0] } == "A")
        #expect(t.currentTurn == nil)
    }

    @Test func tiedMatchGoesToSuddenDeath() {
        var t = Tournament(players: ["A", "B"])
        for _ in 0..<6 { t.record(attempt(20)) }              // qualifying all tied -> both advance
        for _ in 0..<10 { t.record(attempt(20)) }             // championship tied
        #expect(t.championship?.inSuddenDeath == true)
        #expect(t.currentTurn?.detail == "Sudden death")
        t.record(attempt(15))                                   // A
        t.record(attempt(15))                                   // B: still tied
        #expect(t.champion == nil)
        t.record(attempt(8))                                    // A
        t.record(attempt(9))                                    // B
        #expect(t.champion.map { t.players[$0] } == "A")
    }

    @Test func tieForFourthGoesToBestAttemptThenSuddenDeath() {
        // D and E tie on average and best attempt for the last spot
        var t = Tournament(players: ["A", "B", "C", "D", "E"])
        let tries: [[Int]] = [[1, 1, 1], [2, 2, 2], [3, 3, 3], [10, 20, 30], [10, 20, 30]]
        for player in tries { for e in player { t.record(attempt(e)) } }
        #expect(t.playoff != nil)
        #expect(t.currentTurn?.stage == "Playoff")
        t.record(attempt(50))                                   // D
        t.record(attempt(40))                                   // E wins the spot
        #expect(t.seeds?.map { t.players[$0] } == ["A", "B", "C", "E"])
        #expect(t.semifinals.count == 2)
    }

    @Test func survivesSavingAndLoading() throws {
        var t = Tournament(players: ["A", "B", "C", "D"])
        for e in [5, 10, 15, 20, 5] { t.record(attempt(e)) }
        let data = try JSONEncoder().encode(t)
        let loaded = try JSONDecoder().decode(Tournament.self, from: data)
        #expect(loaded == t)
        #expect(loaded.currentTurn == t.currentTurn)
    }
}


@MainActor
struct TournamentStoreTests {

    @Test func redoLastAttemptGivesThePlayerTheirTurnBack() {
        let store = TournamentStore()
        store.start(players: ["A", "B"])
        store.record(GameAttempt(elapsedMs: (T + 10)))
        store.record(GameAttempt(elapsedMs: 2900))            // accidental tap
        #expect(store.tournament?.qualifying[0].count == 2)
        store.undoLastAttempt()
        #expect(store.tournament?.qualifying[0] == [GameAttempt(elapsedMs: (T + 10))])
        #expect(store.tournament?.currentTurn?.detail == "Attempt 2 of 3")
        #expect(store.beforeLastAttempt == nil)              // one step back only
        store.end()
    }
}

//
//  Ghost_Runner_1_0Tests.swift
//  Ghost Runner 1.0Tests
//

import Foundation
import Testing
import SwiftData
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

private let T = GameBreakScoring.defaultTargetMs

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

    private func attempt(_ errorMs: Int) -> GameAttempt { GameAttempt(elapsedMs: GameBreakScoring.defaultTargetMs + errorMs) }

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

    @Test func topFourSeedIntoSemifinalsByAverageScore() {
        let errors = ["P1": 5, "P2": -12, "P3": 20, "P4": -30, "P5": 40, "P6": 80]
        var t = Tournament(players: ["P6", "P5", "P4", "P3", "P2", "P1"])
        for _ in 0..<18 { play(&t, errors) }
        #expect(t.seeds?.map { t.players[$0] } == ["P1", "P2", "P3", "P4"])
        #expect(t.semifinals.count == 2)
        #expect(t.players[t.semifinals[0].a] == "P1" && t.players[t.semifinals[0].b] == "P4")
        #expect(t.players[t.semifinals[1].a] == "P2" && t.players[t.semifinals[1].b] == "P3")
    }

    @Test func rankingUsesAverageScoreNotAverageTime() {
        // Close: three 0.010 misses are all PERFECT 100s.
        // Spotty: two exact hits and a 0.025 miss average 98.3, even though its average time is closer.
        var t = Tournament(players: ["Spotty", "Close"])
        for e in [0, 0, 25] { t.record(attempt(e)) }
        for e in [10, -10, 10] { t.record(attempt(e)) }
        #expect(t.standings.map { t.players[$0.player] } == ["Close", "Spotty"])
        #expect(t.standings.first?.averageScore == 100)
    }

    @Test func earlyAndLateDoNotCancelOut() {
        // 100 early then 100 late averages 100 off, not 0
        var t = Tournament(players: ["Swing", "Steady"])
        for e in [-100, 100, 0] { t.record(attempt(e)) }      // Swing: averages 0 signed, 67 ms off
        for e in [30, -30, 30] { t.record(attempt(e)) }       // Steady: 30 ms off
        #expect(t.standings.first.map { t.players[$0.player] } == "Steady")
    }

    @Test func semifinalPlayersTakeTheirTriesInARowAndChampionshipIsFiveEach() {
        let errors = ["A": 5, "B": 30, "C": 45, "D": 60]        // scores 100, 94, 91, 88
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

struct DuelTests {

    private func attempt(_ errorMs: Int) -> GameAttempt { GameAttempt(elapsedMs: T + errorMs) }

    @Test func playerOneTakesThreeTriesThenPlayerTwo() {
        var duel = Duel()
        var order: [Int] = []
        for _ in 0..<6 {
            order.append(duel.currentTurn!.player)
            duel.record(attempt(20))
        }
        #expect(order == [0, 0, 0, 1, 1, 1])
    }

    @Test func higherAverageScoreWins() {
        var duel = Duel()
        for e in [5, 30, -60] { duel.record(attempt(e)) }      // 100, 94, 88
        for e in [15, -40, 80] { duel.record(attempt(e)) }     // 98, 92, 84
        #expect(duel.averageScore(0)! > duel.averageScore(1)!)
        #expect(duel.winner == 0)
        #expect(duel.currentTurn == nil)
    }

    @Test func tieGoesToSuddenDeath() {
        var duel = Duel()
        for _ in 0..<6 { duel.record(attempt(25)) }            // both average 95
        #expect(duel.inSuddenDeath)
        #expect(duel.currentTurn == Duel.Turn(player: 0, detail: "Sudden death"))
        duel.record(attempt(50))                                // P1: 90
        #expect(duel.currentTurn?.player == 1)
        duel.record(attempt(-20))                               // P2: ~97
        #expect(duel.winner == 1)
    }

    @Test func suddenDeathTiedScoreGoesToTheCloserTime() {
        var duel = Duel()
        for _ in 0..<6 { duel.record(attempt(25)) }
        duel.record(attempt(4))                                 // both 100 PERFECT...
        duel.record(attempt(-7))                                // ...but P1 was closer
        #expect(duel.winner == 0)
    }
}

@MainActor
struct ScreenAwakeTests {

    @Test func staysAwakeWhileConnected() async throws {
        var keepAwake: [Bool] = []
        let screen = ScreenAwake(grace: 0.05) { keepAwake.append($0) }
        screen.update(connected: true)
        try await Task.sleep(for: .milliseconds(150))
        #expect(keepAwake == [true])
    }

    @Test func mayLockAfterTheGraceOnceDisconnected() async throws {
        var keepAwake: [Bool] = []
        let screen = ScreenAwake(grace: 0.05) { keepAwake.append($0) }
        screen.update(connected: true)
        screen.update(connected: false)
        #expect(keepAwake.last == true)                       // still on right after the drop
        try await Task.sleep(for: .milliseconds(150))
        #expect(keepAwake.last == false)                      // then the phone may lock
    }

    @Test func reconnectingWithinTheGraceKeepsItAwake() async throws {
        var keepAwake: [Bool] = []
        let screen = ScreenAwake(grace: 0.05) { keepAwake.append($0) }
        screen.update(connected: false)
        screen.update(connected: true)
        try await Task.sleep(for: .milliseconds(150))
        #expect(!keepAwake.contains(false))
    }
}

struct HomeReturnTests {

    @Test func quickSwitchesKeepTheirPlace() {
        #expect(!HomeReturn.shouldGoHome(awayFor: 5))
        #expect(!HomeReturn.shouldGoHome(awayFor: 59))
    }

    @Test func aRealBreakGoesBackHome() {
        #expect(HomeReturn.shouldGoHome(awayFor: 60))
        #expect(HomeReturn.shouldGoHome(awayFor: 3 * 60 * 60))
    }
}

struct CoachStartDrillTests {

    @Test(arguments: Sport.allCases)
    func tagUpIsBetweenTheSplitAndHomeToFirst(sport: Sport) {
        let times = StandardTimes.table(for: sport)
        for category in times.categories {
            for intensity in Intensity.allCases {
                let time = { StandardTimes.time(sport: sport, category: category, drill: $0, intensity: intensity)! }
                let split = time("Home to 2nd") - time("Home to 1st")
                let tagUp = time("Tag up")
                #expect(tagUp < time("Home to 1st"), "\(sport.title) \(category) \(intensity.title)")
                #expect(tagUp > split, "\(sport.title) \(category) \(intensity.title)")
            }
        }
    }

    @Test func coachStartDrillsAreMarked() {
        #expect(StandardTimes.isCoachStart("Tag up"))
        #expect(StandardTimes.isCoachStart("Delivery + Pop (steal 2nd)"))
        #expect(!StandardTimes.isCoachStart("Home to 1st"))
    }

    @Test func softballHasTagUpButNoDeliveryPlusPop() {
        #expect(StandardTimes.softball.drills.contains("Tag up"))
        #expect(!StandardTimes.softball.drills.contains("Delivery + Pop (steal 2nd)"))
        #expect(StandardTimes.baseball.drills.contains("Delivery + Pop (steal 2nd)"))
    }
}

struct GameBreakTargetTests {

    @Test func targetIsRoutineHomeToFirstForTheLevel() {
        #expect(GameBreakTarget(sport: .baseball, category: "High school (60/90)").ms == 4300)
        #expect(GameBreakTarget(sport: .baseball, category: "Frosh (60/90)").ms == 4500)
        #expect(GameBreakTarget(sport: .softball, category: "High school").ms == 3500)
        #expect(GameBreakTarget(sport: .softball, category: "College/elite").ms == 3200)
        #expect(GameBreakTarget(sport: .softball, category: "No such level").ms == nil)
    }

    @Test(arguments: Sport.allCases)
    func everyLevelHasATarget(sport: Sport) {
        for category in StandardTimes.table(for: sport).categories {
            #expect(GameBreakTarget(sport: sport, category: category).ms != nil, "\(sport.title) \(category)")
        }
    }

    @Test func attemptsScoreAgainstTheirOwnTarget() {
        let softball = GameAttempt(elapsedMs: 3473, targetMs: 3500)
        #expect(softball.errorMs == -27)
        #expect(softball.score == 95)
        #expect(GameAttempt(elapsedMs: 4300, targetMs: 4300).isPerfect)
    }

    @Test func attemptsSavedBeforeTargetsWereSelectableUseFourSeconds() throws {
        let old = try JSONDecoder().decode(GameAttempt.self, from: Data(#"{"elapsedMs":4012}"#.utf8))
        #expect(old.targetMs == 4000)
        #expect(old.errorMs == 12)
    }

    @Test func tournamentKeepsTheTargetItStartedWith() throws {
        var t = Tournament(players: ["A", "B"], targetMs: 3500, targetLabel: "Softball · High school")
        t.record(GameAttempt(elapsedMs: 3510, targetMs: t.targetMs))
        let loaded = try JSONDecoder().decode(Tournament.self, from: JSONEncoder().encode(t))
        #expect(loaded.targetMs == 3500)
        #expect(loaded.targetLabel == "Softball · High school")
        // A tournament saved before targets existed reads back as 4.000
        let legacy = try JSONDecoder().decode(Tournament.self, from: Data(#"{"players":["A","B"],"qualifying":[[],[]],"semifinals":[]}"#.utf8))
        #expect(legacy.targetMs == 4000)
    }

    @MainActor
    @Test func shortTargetsKeepRoomAfterTheLockout() {
        let engine = GameBreakEngine()
        engine.targetMs = 3200                                // Softball College/elite
        #expect(engine.lockoutMs == 2500)
        engine.targetMs = 2900
        #expect(engine.lockoutMs == 2200)                     // never closer than 0.7 s to the target
        engine.updateAvailability(connected: true, confirmed: true, failed: false, simulated: false)
        engine.handleTap(GameTap(puckMs: 0, receivedAt: .now))
        engine.handleTap(GameTap(puckMs: 2900, receivedAt: .now))
        #expect(engine.phase == .result(GameAttempt(elapsedMs: 2900, targetMs: 2900)))
    }
}

struct TagUpTriggerTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1000)

    @Test func onlyTagUpWaitsForTheSecondHit() {
        #expect(TagUpTrigger.applies(to: "Tag up"))
        for drill in StandardTimes.baseball.drills where drill != "Tag up" {
            #expect(!TagUpTrigger.applies(to: drill), "\(drill)")
        }
    }

    @Test func flyBallArmsThenTheCatchStarts() {
        var tagUp = TagUpTrigger()
        let flyBall = tagUp.hit(at: t0)
        #expect(!flyBall)
        #expect(tagUp.isBallInAir(at: t0.addingTimeInterval(3)))
        let atCatch = tagUp.hit(at: t0.addingTimeInterval(4.2))
        #expect(atCatch)                                             // starts the runner
        #expect(!tagUp.isBallInAir(at: t0.addingTimeInterval(4.3)))
        let nextFlyBall = tagUp.hit(at: t0.addingTimeInterval(9))
        #expect(!nextFlyBall)
    }

    @Test func noCatchWithinSixSecondsMeansTheNextHitIsANewFlyBall() {
        var tagUp = TagUpTrigger()
        _ = tagUp.hit(at: t0)
        #expect(tagUp.isBallInAir(at: t0.addingTimeInterval(5.9)))
        #expect(!tagUp.isBallInAir(at: t0.addingTimeInterval(6)))
        let late = tagUp.hit(at: t0.addingTimeInterval(7))
        #expect(!late)                                               // a new fly ball
        let itsCatch = tagUp.hit(at: t0.addingTimeInterval(10))
        #expect(itsCatch)
    }

    @Test func resetForgetsTheFlyBall() {
        var tagUp = TagUpTrigger()
        _ = tagUp.hit(at: t0)
        tagUp.reset()
        let afterReset = tagUp.hit(at: t0.addingTimeInterval(3))
        #expect(!afterReset)
    }
}

struct ProFielderTests {

    @Test func fielderIsSavedAndReadBack() {
        let id = UUID()
        for fielder in [Fielder.team, .position(.shortstop), .player(id)] {
            #expect(Fielder(rawValue: fielder.rawValue) == fielder)
        }
        #expect(Fielder(rawValue: "") == .team)
        #expect(Fielder(rawValue: "position:XX") == .team)
        #expect(Fielder(rawValue: "player:not-a-uuid") == .team)
    }

    private func pending(_ fielder: Fielder, players: [Player]) -> PendingRep {
        PendingRep(fielder: fielder, players: players, sport: .baseball, category: "High school (60/90)",
                   drill: "Home to 1st", intensity: .pressure, runnerTime: 4.2, usedCustomTime: false)
    }

    @Test func playerRepUsesTheirNameAndPosition() {
        let jake = Player(name: "Jake", number: "7", position: .shortstop)
        let rep = pending(.player(jake.id), players: [jake])
        #expect(rep.playerName == "Jake #7")
        #expect(rep.position == .shortstop)
        #expect(Rep(rep, outcome: .out).fielderLabel == "Jake #7 · SS")
    }

    @Test func positionAndTeamReps() {
        #expect(Rep(pending(.position(.center), players: []), outcome: .safe).fielderLabel == "8 · Center field")
        #expect(Rep(pending(.team, players: []), outcome: .safe).fielderLabel == "Team")
    }

    @Test func deletedPlayerCountsForTheTeam() {
        let rep = pending(.player(UUID()), players: [])
        #expect(rep.fielder == .team)
        #expect(rep.playerName.isEmpty)
    }

    @Test func rosterSortsByNumberThenName() {
        let players = [Player(name: "Zed", number: "12"), Player(name: "Amy", number: "3"),
                       Player(name: "Bo"), Player(name: "Al")]
        #expect(players.sorted(by: ProStore.rosterOrder).map(\.name) == ["Amy", "Zed", "Al", "Bo"])
    }
}

struct RepTallyTests {
    @Test func errorsCountAsNotOutButAreKeptApart() {
        let tally = RepTally([.out, .out, .out, .safe, .gloveError, .throwingError, .out, .out])
        #expect(tally.reps == 8)
        #expect(tally.outs == 5)
        #expect(tally.gloveErrors == 1)
        #expect(tally.throwingErrors == 1)
        #expect(tally.outRateText == "63%")
        #expect(RepTally().outRateText == "—")
    }
}

@MainActor
struct ProStoreTests {
    @Test func recordsAndUndoesReps() throws {
        let store = ProStore(inMemory: true)
        let context = try #require(store.container?.mainContext)
        let pending = PendingRep(fielder: .position(.first), players: [], sport: .softball, category: "High school",
                                 drill: "Home to 1st", intensity: .routine, runnerTime: 3.5, usedCustomTime: false)
        let rep = try #require(store.record(pending, outcome: .gloveError))
        var saved = try context.fetch(FetchDescriptor<Rep>())
        #expect(saved.count == 1)
        #expect(saved.first?.outcome == .gloveError)
        #expect(saved.first?.position == .first)
        #expect(saved.first?.intensity == .routine)
        store.delete(rep)
        saved = try context.fetch(FetchDescriptor<Rep>())
        #expect(saved.isEmpty)
    }
}

struct PositionNumberTests {
    @Test func scorebookNumbers() {
        #expect(Position.allCases.map(\.number) == Array(1...9))
        #expect(Position(number: 1) == .pitcher)
        #expect(Position(number: 6) == .shortstop)
        #expect(Position(number: 9) == .right)
        #expect(Position(number: 0) == nil)
        #expect(Position(number: 10) == nil)
        #expect(Position.shortstop.numberedTitle == "6 · Shortstop")
    }
}

struct RepCallTests {
    @Test func uncalledRepIsAnOutEightSecondsAfterTheBuzzer() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        #expect(RepCall.outDeadline(start: start, runnerTime: 4.3).timeIntervalSince(start) == 12.3)
    }

    @Test func aLateSafeCanStillFixIt() {
        let logged = Date(timeIntervalSinceReferenceDate: 0)
        #expect(RepCall.canChangeToSafe(loggedAt: logged, now: logged.addingTimeInterval(10)))
        #expect(!RepCall.canChangeToSafe(loggedAt: logged, now: logged.addingTimeInterval(16)))
    }

    @MainActor
    @Test func changingALoggedOutToSafe() throws {
        let store = ProStore(inMemory: true)
        let p = PendingRep(fielder: .position(.shortstop), players: [], sport: .baseball, category: "13U (54/80)",
                           drill: "Home to 1st", intensity: .routine, runnerTime: 4.4, usedCustomTime: false)
        let rep = try #require(store.record(p, outcome: .out))
        store.change(rep, to: .safe)
        let saved = try #require(store.container?.mainContext).fetch(FetchDescriptor<Rep>())
        #expect(saved.map(\.outcome) == [.safe])
    }
}

struct VoiceCommandTests {
    private let jake = VoiceCommandParser.RosterName(id: UUID(), name: "Jake")
    private let mia = VoiceCommandParser.RosterName(id: UUID(), name: "Mia Lopez")
    private let jakeB = VoiceCommandParser.RosterName(id: UUID(), name: "Jake Brown")
    private var roster: [VoiceCommandParser.RosterName] { [jake, mia] }

    private func parse(_ text: String, roster: [VoiceCommandParser.RosterName]? = nil) -> VoiceCommand? {
        VoiceCommandParser.parse(text, roster: roster ?? self.roster)
    }

    private func fielder(_ text: String) -> Fielder? { parse(text)?.fielder }

    @Test func numbersOneToNine() {
        let expected: [(String, Position)] = [("1", .pitcher), ("2", .catcher), ("3", .first), ("4", .second),
                                              ("5", .third), ("6", .shortstop), ("7", .left), ("8", .center), ("9", .right)]
        for (said, position) in expected {
            #expect(fielder(said) == .position(position), "\(said)")
        }
        #expect(fielder("Six") == .position(.shortstop))
        #expect(fielder("seven.") == .position(.left))
        #expect(parse("6")?.action == nil)                         // naming the fielder isn't a result
    }

    @Test func numbersTheRecognizerMightMishear() {
        #expect(fielder("to") == .position(.catcher))
        #expect(fielder("Too") == .position(.catcher))
        #expect(fielder("for") == .position(.second))
        #expect(fielder("ate") == .position(.center))
        #expect(fielder("won") == .position(.pitcher))
        #expect(fielder("for safe") == .position(.second))
    }

    @Test func numbersInsideOtherTalkAreIgnored() {
        #expect(parse("go to first") == nil)
        #expect(parse("one more time") == nil)
        #expect(parse("time for water") == nil)
        #expect(parse("nice play short") == nil)
        #expect(parse("good job Jake") == nil)
    }

    @Test func positionWordsAndNames() {
        #expect(fielder("short") == .position(.shortstop))
        #expect(fielder("Shortstop") == .position(.shortstop))
        #expect(fielder("center field") == .position(.center))
        #expect(fielder("second base") == .position(.second))
        #expect(fielder("pitcher") == .position(.pitcher))
        #expect(fielder("Jake") == .player(jake.id))
        #expect(fielder("Mia") == .player(mia.id))
        #expect(fielder("Mia Lopez") == .player(mia.id))
    }

    @Test func sharedFirstNamesNeedTheFullName() {
        let both = [jake, jakeB]
        #expect(parse("Jake Brown", roster: both)?.fielder == .player(jakeB.id))
        #expect(parse("Jake", roster: both)?.fielder == .player(jake.id))   // "Jake" is a full name
        #expect(parse("Brown", roster: both) == nil)
    }

    @Test func safe() {
        #expect(parse("Safe") == VoiceCommand(fielder: nil, action: .safe))
        #expect(parse("safe!")?.action == .safe)
        #expect(parse("6 safe") == VoiceCommand(fielder: .position(.shortstop), action: .safe))
        #expect(parse("Jake safe") == VoiceCommand(fielder: .player(jake.id), action: .safe))
    }

    @Test func undo() {
        #expect(parse("Undo") == VoiceCommand(fielder: nil, action: .undo))
        #expect(parse("scratch that")?.action == .undo)
    }

    @Test func everythingElseIsIgnored() {
        #expect(parse("out") == nil)                               // outs aren't called
        #expect(parse("nice play") == nil)
        #expect(parse("you're out of position, let's go again") == nil)
        #expect(parse("let's play it safe out there") == nil)      // too long to be a call
        #expect(parse("") == nil)
    }
}

import Foundation

// MARK: - 1 v 1
//
// Player 1 takes 3 tries in a row, then Player 2 takes 3. The higher
// average score wins. A tie goes to sudden death: one try each, higher
// score wins (closer time if the scores match), repeated until decided.

struct Duel: Equatable {
    static let attemptsEach = 3
    static let names = ["Player 1", "Player 2"]

    /// Regulation tries for Player 1 and Player 2
    var attempts: [[GameAttempt]] = [[], []]
    /// Sudden-death tries, one each per round
    var suddenDeath: [[GameAttempt]] = [[], []]

    var regulationDone: Bool { attempts.allSatisfy { $0.count >= Self.attemptsEach } }

    /// Average score so far, nil before the first try
    func averageScore(_ player: Int) -> Double? {
        let scores = attempts[player].map(\.score)
        guard !scores.isEmpty else { return nil }
        return Double(scores.reduce(0, +)) / Double(scores.count)
    }

    var inSuddenDeath: Bool { regulationDone && winner == nil }

    /// 0 for Player 1, 1 for Player 2, nil while undecided
    var winner: Int? {
        guard regulationDone, let a = averageScore(0), let b = averageScore(1) else { return nil }
        if a != b { return a > b ? 0 : 1 }
        for (x, y) in zip(suddenDeath[0], suddenDeath[1]) {
            if x.score != y.score { return x.score > y.score ? 0 : 1 }
            if x.absErrorMs != y.absErrorMs { return x.absErrorMs < y.absErrorMs ? 0 : 1 }
        }
        return nil
    }

    struct Turn: Equatable {
        let player: Int
        let detail: String
    }

    var currentTurn: Turn? {
        guard winner == nil else { return nil }
        if !regulationDone {
            // All of Player 1's tries, then all of Player 2's
            let player = attempts[0].count < Self.attemptsEach ? 0 : 1
            return Turn(player: player, detail: "Attempt \(attempts[player].count + 1) of \(Self.attemptsEach)")
        }
        let player = suddenDeath[0].count <= suddenDeath[1].count ? 0 : 1
        return Turn(player: player, detail: "Sudden death")
    }

    mutating func record(_ attempt: GameAttempt) {
        guard let turn = currentTurn else { return }
        if regulationDone {
            suddenDeath[turn.player].append(attempt)
        } else {
            attempts[turn.player].append(attempt)
        }
    }
}

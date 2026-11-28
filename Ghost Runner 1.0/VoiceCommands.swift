import Foundation

// MARK: - What the coach says
//
// Who's fielding: a scorebook number ("6"), a position word ("short") or a player's name ("Jake").
// It sticks until another one is said. The only result to call is "safe": a rep with no call is an
// out. "Undo" takes back the last rep. "Turn two", "roll it" or "let's get two" with where it's fielded calls a double
// play (5 → 5-4-3, 6 → 6-4-3, 4 → 4-6-3, 3 → 3-6-3). "Ghost Runner pause" / "Ghost Runner resume".
// A call is only those words; anything with other words in it is talk and is ignored.

struct VoiceCommand: Equatable {
    enum Action: Equatable {
        case safe
        case undo
        case pause
        case resume
    }

    /// Who the coach named, if anyone; a double play when "turn two" came with a fielder
    let fielder: Fielder?
    let action: Action?
    /// "Turn two" was said; with no fielder, it's for the current one (or the next number said)
    var turnTwo = false
}

enum VoiceCommandParser {
    /// "Let's get two short stop safe"; anything longer is conversation
    static let maxWords = 6

    struct RosterName: Equatable {
        let id: UUID
        let name: String
    }

    static func parse(_ text: String, roster: [RosterName] = []) -> VoiceCommand? {
        var words = normalize(text)
        guard !words.isEmpty, words.count <= maxWords else { return nil }

        if words == ["undo"] || words == ["scratch", "that"] {
            return VoiceCommand(fielder: nil, action: .undo)
        }
        if words.count == 3, Array(words[0...1]) == ["ghost", "runner"] {
            if pauseWords.contains(words[2]) { return VoiceCommand(fielder: nil, action: .pause) }
            if resumeWords.contains(words[2]) { return VoiceCommand(fielder: nil, action: .resume) }
            return nil
        }
        var turnTwo = false
        for phrase in turnTwoPhrases {
            if let i = index(of: phrase, in: words) {
                turnTwo = true
                words.removeSubrange(i..<(i + phrase.count))
                break
            }
        }
        var action: VoiceCommand.Action?
        if let i = words.firstIndex(of: "safe") {
            action = .safe
            words.remove(at: i)
        }
        if words.isEmpty {
            guard turnTwo || action != nil else { return nil }
            return VoiceCommand(fielder: nil, action: action, turnTwo: turnTwo)
        }
        // Every other word has to be the fielder, so talk like "nice play short" changes nothing
        guard var fielder = fielder(exactly: words, roster: roster) else { return nil }
        if turnTwo {
            // Only where a double play can start: 3, 4, 5 or 6
            guard let doublePlay = fielder.turningTwo else { return nil }
            fielder = doublePlay
        }
        return VoiceCommand(fielder: fielder, action: action, turnTwo: turnTwo)
    }

    /// Words to help the recognizer: the numbers, positions, roster names and calls
    static func vocabulary(roster: [RosterName]) -> [String] {
        ["safe", "undo", "turn two", "roll it", "let's get two", "Ghost Runner pause", "Ghost Runner resume"]
            + (1...9).map(String.init)
            + positionWords.map(\.phrase)
            + roster.map(\.name)
    }

    // MARK: Words

    /// Lowercased words with punctuation dropped; "1st" → "first"
    static func normalize(_ text: String) -> [String] {
        let lowered = text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "-", with: " ")
        let words = lowered.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let joined = ["1st": "first", "2nd": "second", "3rd": "third",
                      "centerfield": "center field", "rightfield": "right field", "leftfield": "left field",
                      "shortstop": "short stop", "ghostrunner": "ghost runner", "ghostrunners": "ghost runner"]
        return words.flatMap { (joined[$0] ?? $0).split(separator: " ").map(String.init) }
    }

    /// "Turn two" and how it may come back; "roll it" and "let's get two" mean the same.
    /// Longer phrases first, so "let's get two" isn't read as "get two" plus a stray word.
    private static let turnTwoPhrases: [[String]] = [
        ["lets", "get", "two"], ["lets", "get", "2"], ["lets", "get", "to"], ["let", "us", "get", "two"],
        ["turn", "two"], ["turn", "2"], ["turn", "to"], ["turn", "too"], ["turn", "it"],
        ["get", "two"], ["get", "2"], ["get", "to"],
        ["roll", "it"], ["role", "it"], ["rollit"],
    ]

    private static let pauseWords: Set = ["pause", "paws", "pas", "stop"]
    private static let resumeWords: Set = ["resume", "resumed", "start", "go"]

    /// Scorebook numbers, as digits or words
    private static let numberWords: [String: Int] = [
        "1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8, "9": 9,
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
    ]

    /// How a number said on its own can come back from the recognizer
    private static let soundAlikes: [String: Int] = [
        "won": 1, "to": 2, "too": 2, "for": 4, "fore": 4, "sex": 6, "sics": 6, "ate": 8,
    ]

    private static let positionWords: [(phrase: String, position: Position)] = [
        ("pitcher", .pitcher), ("catcher", .catcher),
        ("first base", .first), ("first baseman", .first), ("first", .first),
        ("second base", .second), ("second baseman", .second), ("second", .second),
        ("third base", .third), ("third baseman", .third), ("third", .third),
        ("short stop", .shortstop), ("short", .shortstop),
        ("left field", .left), ("left fielder", .left),
        ("center field", .center), ("center fielder", .center), ("center", .center),
        ("right field", .right), ("right fielder", .right),
    ]

    // MARK: Fielder

    /// The fielder when these words name one and nothing else: "6", "short stop", "Mia Lopez"
    private static func fielder(exactly words: [String], roster: [RosterName]) -> Fielder? {
        if words.count == 1, let n = numberWords[words[0]] ?? soundAlikes[words[0]] {
            return Position(number: n).map(Fielder.position)
        }
        if let entry = positionWords.first(where: { $0.phrase.split(separator: " ").map(String.init) == words }) {
            return .position(entry.position)
        }
        if let player = roster.first(where: { normalize($0.name) == words }) {
            return .player(player.id)
        }
        // A first name only one player has
        if words.count == 1 {
            let matches = roster.filter { normalize($0.name).first == words[0] }
            if matches.count == 1 { return .player(matches[0].id) }
        }
        return nil
    }

    private static func index(of phrase: [String], in words: [String]) -> Int? {
        guard !phrase.isEmpty, phrase.count <= words.count else { return nil }
        for i in 0...(words.count - phrase.count) where Array(words[i..<(i + phrase.count)]) == phrase {
            return i
        }
        return nil
    }
}

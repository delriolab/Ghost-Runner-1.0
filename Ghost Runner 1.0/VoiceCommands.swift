import Foundation

// MARK: - What the coach says
//
// "Jake, out" · "Shortstop got em" · "Throwing error, number 7" · "Safe" · "Undo"
// An outcome word is required; the fielder is optional (the Fielding pick is used without one).
// Only short calls count, so sideline talk ("you're out of position, let's go again") is ignored.

struct VoiceCommand: Equatable {
    enum Action: Equatable {
        case outcome(RepOutcome)
        case undo
    }

    let action: Action
    /// Who the coach named, if anyone
    let fielder: Fielder?
}

enum VoiceCommandParser {
    /// Longer than this is conversation, not a call
    static let maxWords = 6

    struct RosterName: Equatable {
        let id: UUID
        let name: String
        let number: String
    }

    static func parse(_ text: String, roster: [RosterName] = []) -> VoiceCommand? {
        let words = normalize(text)
        guard !words.isEmpty, words.count <= maxWords else { return nil }

        if saysUndo(words) {
            return VoiceCommand(action: .undo, fielder: nil)
        }
        guard let outcome = lastOutcome(words) else { return nil }
        return VoiceCommand(action: .outcome(outcome), fielder: fielder(in: words, roster: roster))
    }

    /// Words to help the recognizer: the calls, positions and roster names
    static func vocabulary(roster: [RosterName]) -> [String] {
        ["out", "safe", "got em", "glove error", "throwing error", "undo"]
            + positionPhrases.map(\.phrase)
            + roster.map(\.name)
    }

    // MARK: Words

    /// Lowercased words with punctuation dropped; "1st" → "first", "got'em" → "got em"
    static func normalize(_ text: String) -> [String] {
        let lowered = text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "'em", with: " em")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "#", with: " number ")
        let words = lowered.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let ordinals = ["1st": "first", "2nd": "second", "3rd": "third", "gotem": "got em", "gottem": "got em",
                        "centerfield": "center field", "rightfield": "right field", "leftfield": "left field"]
        return words.flatMap { (ordinals[$0] ?? $0).split(separator: " ").map(String.init) }
    }

    private static func saysUndo(_ words: [String]) -> Bool {
        words.contains("undo") || index(of: ["scratch", "that"], in: words) != nil
    }

    /// The last outcome said wins ("out… no, safe" → safe)
    private static func lastOutcome(_ words: [String]) -> RepOutcome? {
        var found: RepOutcome?
        for (i, word) in words.enumerated() {
            let next = i + 1 < words.count ? words[i + 1] : ""
            switch word {
            case "out": found = .out
            case "safe": found = .safe
            case "got" where ["em", "him", "them", "um"].contains(next): found = .out
            case "glove" where next.hasPrefix("error"): found = .gloveError
            case "throwing" where next.hasPrefix("error"),
                 "throw" where next.hasPrefix("error"),
                 "throwin" where next.hasPrefix("error"): found = .throwingError
            default: break
            }
        }
        return found
    }

    // MARK: Fielder

    private static let positionPhrases: [(phrase: String, position: Position)] = [
        ("pitcher", .pitcher), ("catcher", .catcher),
        ("first base", .first), ("first baseman", .first),
        ("second base", .second), ("second baseman", .second),
        ("third base", .third), ("third baseman", .third),
        ("shortstop", .shortstop), ("short stop", .shortstop), ("short", .shortstop),
        ("left field", .left), ("left fielder", .left),
        ("center field", .center), ("center fielder", .center), ("center", .center),
        ("right field", .right), ("right fielder", .right),
    ]

    /// The first player or position named. "Shortstop, out at first base" is the shortstop.
    private static func fielder(in words: [String], roster: [RosterName]) -> Fielder? {
        // Earliest mention wins; at the same spot, the longer match ("Jake Brown" over "Jake")
        var best: (index: Int, length: Int, fielder: Fielder)?
        func consider(_ index: Int, _ length: Int, _ fielder: Fielder) {
            guard let current = best else { best = (index, length, fielder); return }
            if index < current.index || (index == current.index && length > current.length) {
                best = (index, length, fielder)
            }
        }

        // "number 7"
        for i in words.indices.dropLast() where words[i] == "number" {
            if let player = roster.first(where: { !$0.number.isEmpty && $0.number == words[i + 1] }) {
                consider(i, 2, .player(player.id))
            }
        }
        // A player's full name, or a first name only one player has
        for player in roster {
            let full = normalize(player.name)
            guard let first = full.first else { continue }
            if let i = index(of: full, in: words) {
                consider(i, full.count, .player(player.id))
            } else if roster.filter({ normalize($0.name).first == first }).count == 1,
                      let i = words.firstIndex(of: first) {
                consider(i, 1, .player(player.id))
            }
        }
        for entry in positionPhrases {
            let phrase = entry.phrase.split(separator: " ").map(String.init)
            if let i = index(of: phrase, in: words) {
                consider(i, phrase.count, .position(entry.position))
            }
        }
        return best?.fielder
    }

    private static func index(of phrase: [String], in words: [String]) -> Int? {
        guard !phrase.isEmpty, phrase.count <= words.count else { return nil }
        for i in 0...(words.count - phrase.count) where Array(words[i..<(i + phrase.count)]) == phrase {
            return i
        }
        return nil
    }
}

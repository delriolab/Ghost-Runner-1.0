import SwiftUI
import SwiftData

// MARK: - Training screen pieces

/// What the training screen needs for Pro; nil in the free app
struct ProTraining {
    var fielder: Binding<String>
    /// A rep has started and hasn't been logged yet (it's an out unless "safe" is called)
    var hasPendingRep: Bool
    /// "6 · Shortstop · Out" once logged, until the next rep starts
    var lastLogged: String?
    /// Voice logging state; nil when voice is off
    var voice: VoiceDisplay?
    var onSafe: () -> Void
    var onUndo: () -> Void
}

/// The microphone line on the training screen
struct VoiceDisplay: Equatable {
    var status: VoiceListener.Status

    var text: String {
        switch status {
        case .listening: "Listening · fielder 1\u{2013}9 · \u{201C}safe\u{201D}"
        case .off: "Voice starting…"
        case .denied: "Voice is off: allow Microphone and Speech Recognition for Ghost Runner in Settings"
        case .unavailable: "Voice isn't available right now"
        }
    }

    var symbol: String { status == .listening ? "mic.fill" : "mic.slash" }
    var color: Color { status == .listening ? Theme.accent : Theme.connecting }
}

/// "Fielding: 6 · Shortstop" — a position, or the whole team (player names are on hold for now)
struct FielderCard: View {
    @Binding var selection: String

    private static let teamTitle = "Whole team"

    private var options: [(title: String, fielder: Fielder)] {
        ([Fielder.team] + Position.allCases.map(Fielder.position) + DoublePlay.starts.map(Fielder.doublePlay))
            .map { ($0.title, $0) }
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: {
                let current = Fielder(rawValue: selection)
                return options.first { $0.fielder == current }?.title ?? Self.teamTitle
            },
            set: { title in
                if let option = options.first(where: { $0.title == title }) {
                    selection = option.fielder.rawValue
                }
            }
        )
    }

    var body: some View {
        PickerRow(label: "Fielding", options: options.map(\.title), selection: titleBinding)
            .card()
    }
}

/// Out / Safe / Glove error / Throwing error after each rep, then "Logged … Undo"
struct OutcomeBar: View {
    let pro: ProTraining

    var body: some View {
        VStack(spacing: 8) {
            if let voice = pro.voice {
                Label(voice.text, systemImage: voice.symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(voice.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            if pro.hasPendingRep {
                Button(action: pro.onSafe) {
                    VStack(spacing: 2) {
                        Text("SAFE")
                            .font(.title3.weight(.heavy))
                        Text("No call = out")
                            .font(.caption.weight(.semibold))
                            .opacity(0.8)
                    }
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Theme.alert, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
            } else if let lastLogged = pro.lastLogged {
                HStack {
                    Label("Logged: \(lastLogged)", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer()
                    Button("Undo", action: pro.onUndo)
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .card()
            }
        }
    }
}

// MARK: - History

/// Every logged rep, newest first, grouped by day with Out totals
struct RepHistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Rep.date, order: .reverse) private var reps: [Rep]

    private var days: [(day: Date, reps: [Rep])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: reps) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        List {
            if reps.isEmpty {
                Text("No reps yet. With Pro on, every rep is logged on the training screen: an out unless you call \u{201C}safe\u{201D}.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.label)
                    .listRowBackground(Theme.card)
            }
            ForEach(days, id: \.day) { day in
                Section {
                    ForEach(day.reps) { rep in
                        RepRow(rep: rep)
                            .listRowBackground(Theme.card)
                    }
                    .onDelete { offsets in
                        for i in offsets { context.delete(day.reps[i]) }
                        try? context.save()
                    }
                } header: {
                    DayHeader(day: day.day, tally: RepTally(day.reps.map(\.outcome)))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Rep History")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DayHeader: View {
    let day: Date
    let tally: RepTally

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(day.formatted(.dateTime.weekday(.wide).month().day()))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.text)
            Text(summary)
                .font(.caption)
                .foregroundStyle(Theme.label)
        }
        .textCase(nil)
    }

    private var summary: String {
        var parts = ["\(tally.reps) reps", "\(tally.outs) outs (\(tally.outRateText))"]
        if tally.gloveErrors > 0 { parts.append("\(tally.gloveErrors) glove E") }
        if tally.throwingErrors > 0 { parts.append("\(tally.throwingErrors) throwing E") }
        return parts.joined(separator: " · ")
    }
}

private struct RepRow: View {
    let rep: Rep

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rep.fielderLabel)
                    .foregroundStyle(Theme.text)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.label)
            }
            Spacer()
            Text(rep.outcome.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
        }
    }

    private var detail: String {
        let time = String(format: rep.usedCustomTime ? "%.2f s" : "%.1f s", rep.runnerTime)
        return [rep.date.formatted(date: .omitted, time: .shortened), rep.drill,
                rep.intensity?.title ?? "", time]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var color: Color {
        switch rep.outcome {
        case .out: Theme.ready
        case .safe: Theme.alert
        case .gloveError, .throwingError: Theme.connecting
        }
    }
}

// MARK: - Home and Settings

/// Home screen card into rep history (Pro only)
struct RepHistoryCardLabel: View {
    var body: some View {
        HStack(alignment: .center) {
            Text("Rep History")
                .font(.title2.weight(.heavy))
                .foregroundStyle(Theme.text)
            Text("PRO")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.accent, in: Capsule())
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

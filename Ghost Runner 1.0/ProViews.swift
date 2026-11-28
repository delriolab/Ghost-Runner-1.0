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
        case .listening: "Listening · fielder 1\u{2013}9 or a name · \u{201C}safe\u{201D}"
        case .off: "Voice starting…"
        case .denied: "Voice is off: allow Microphone and Speech Recognition for Ghost Runner in Settings"
        case .unavailable: "Voice isn't available right now"
        }
    }

    var symbol: String { status == .listening ? "mic.fill" : "mic.slash" }
    var color: Color { status == .listening ? Theme.accent : Theme.connecting }
}

/// "Fielding: Jake #7 (SS)" — the whole team, a player, or a position
struct FielderCard: View {
    @Binding var selection: String
    @Query private var players: [Player]

    private var roster: [Player] { players.sorted(by: ProStore.rosterOrder) }

    private static let teamTitle = "Whole team"

    private func title(_ player: Player) -> String {
        player.position.map { "\(player.displayName) (\($0.rawValue))" } ?? player.displayName
    }

    private var options: [(title: String, fielder: Fielder)] {
        [(Self.teamTitle, .team)]
            + Position.allCases.map { ($0.numberedTitle, .position($0)) }
            + roster.map { (title($0), .player($0.id)) }
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

// MARK: - Team

/// The roster, plus the way into rep history
struct TeamView: View {
    @Environment(\.modelContext) private var context
    @Query private var players: [Player]
    @State private var editing: Player?
    @State private var adding = false

    private var roster: [Player] { players.sorted(by: ProStore.rosterOrder) }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    // Pushed screens don't always inherit the store, so hand it over
                    RepHistoryView().modelContainer(context.container)
                } label: {
                    Label("Rep history", systemImage: "list.bullet.rectangle")
                        .foregroundStyle(Theme.text)
                }
                .listRowBackground(Theme.card)
            }

            Section {
                if roster.isEmpty {
                    Text("No players yet. Add your roster to log reps by name; positions work without one.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.label)
                        .listRowBackground(Theme.card)
                }
                ForEach(roster) { player in
                    Button { editing = player } label: {
                        HStack {
                            Text(player.displayName)
                                .foregroundStyle(Theme.text)
                            Spacer()
                            Text(player.position?.title ?? "")
                                .foregroundStyle(Theme.label)
                        }
                    }
                    .listRowBackground(Theme.card)
                }
                .onDelete { offsets in
                    for i in offsets { context.delete(roster[i]) }
                    try? context.save()
                }
            } header: {
                Text("Roster")
                    .foregroundStyle(Theme.label)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Team")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add player", systemImage: "plus") { adding = true }
            }
        }
        .sheet(isPresented: $adding) {
            PlayerEditor(player: nil).modelContainer(context.container)
        }
        .sheet(item: $editing) { player in
            PlayerEditor(player: player).modelContainer(context.container)
        }
    }
}

/// Add or edit a player: name, number, main position
private struct PlayerEditor: View {
    let player: Player?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var number = ""
    @State private var position: Position?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("Number", text: $number)
                        .keyboardType(.numberPad)
                }
                .listRowBackground(Theme.card)
                Section("Main position") {
                    Picker("Position", selection: $position) {
                        Text("None").tag(Position?.none)
                        ForEach(Position.allCases) { p in
                            Text(p.title).tag(Position?.some(p))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(player == nil ? "Add Player" : "Edit Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let player {
                    name = player.name
                    number = player.number
                    position = player.position
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let num = number.trimmingCharacters(in: .whitespaces)
        if let player {
            player.name = trimmed
            player.number = num
            player.position = position
        } else {
            context.insert(Player(name: trimmed, number: num, position: position))
        }
        try? context.save()
        dismiss()
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

/// Home screen card into the team (Pro only)
struct TeamCardLabel: View {
    var body: some View {
        HStack(alignment: .center) {
            Text("Team & Reps")
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

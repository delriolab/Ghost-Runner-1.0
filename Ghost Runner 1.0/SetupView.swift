import SwiftUI

/// Screen 2: shows the selected time and lets the coach set up the drill.
struct SetupView: View {
    let sport: Sport
    @Binding var category: String
    @Binding var drill: String
    @Binding var intensity: Intensity

    let selectedTime: Double?
    let remainingTime: Double
    let timerRunning: Bool
    let connectionStatus: String
    let monitoring: Bool

    let onStart: () -> Void
    let onStop: () -> Void
    let onTestBuzzer: () -> Void

    private var times: SportTimes { StandardTimes.table(for: sport) }

    private var bigNumber: String {
        if timerRunning {
            return String(format: "%.1f", remainingTime)
        }
        guard let selectedTime else { return "—" }
        return String(format: "%.1f", selectedTime)
    }

    private var startDisabled: Bool { selectedTime == nil && !monitoring }

    @State private var showSettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack {
                    Spacer()
                    SensorPill(status: connectionStatus)
                }

                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(bigNumber)
                            .font(.system(size: 120, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.text)
                        Text("s")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Theme.label)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                    Text("Ghost runner time")
                        .font(.footnote)
                        .foregroundStyle(Theme.label)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(timerRunning
                    ? "Ghost runner time, \(bigNumber) seconds left"
                    : "Ghost runner time, \(bigNumber) seconds")

                VStack(spacing: 0) {
                    PickerRow(label: times.categoryLabel, options: times.categories, selection: $category)
                    Rectangle()
                        .fill(Theme.divider)
                        .frame(height: 0.5)
                        .padding(.leading, 16)
                    PickerRow(label: "Drill", options: times.drills, selection: $drill)
                }
                .card()

                IntensityControl(selection: $intensity)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.background)
        .navigationTitle(sport.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Test buzzer lives on the settings screen so it isn't hit by accident
                Button("Settings", systemImage: "gearshape") {
                    showSettings = true
                }
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .navigationDestination(isPresented: $showSettings) {
            SettingsView(onTestBuzzer: onTestBuzzer)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                monitoring ? onStop() : onStart()
            } label: {
                Text(monitoring ? "Stop" : "Start")
                    .font(.title2.bold())
                    .foregroundStyle(startDisabled ? Theme.label : Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(
                        monitoring ? Theme.disconnected : (startDisabled ? Theme.card : Theme.accent),
                        in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    )
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(startDisabled)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }
}

/// A card row with a gray label and a white value that opens a menu of options.
private struct PickerRow: View {
    let label: String
    let options: [String]
    @Binding var selection: String

    var body: some View {
        Menu {
            Picker(label, selection: $selection) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
        } label: {
            HStack(spacing: 8) {
                Text(label)
                    .foregroundStyle(Theme.label)
                Spacer()
                Text(selection)
                    .foregroundStyle(Theme.text)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.label)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .accessibilityValue(selection)
    }
}

/// Routine / Pressure / Hair on fire: the selected option is a blue pill, the rest gray text.
private struct IntensityControl: View {
    @Binding var selection: Intensity

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Intensity.allCases) { level in
                let selected = level == selection
                Button {
                    selection = level
                } label: {
                    Text(level.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? Theme.text : Theme.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(selected ? Theme.accent : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.card, in: Capsule())
    }
}

/// Small status pill: green when connected, amber while searching, red when off.
private struct SensorPill: View {
    let status: String

    // Maps BLEManager's connectionStatus strings to a dot color and short label
    private var state: (color: Color, text: String) {
        if status.hasPrefix("Connected") {
            return (Theme.ready, status == "Connected: Monitoring" ? "Monitoring" : "Connected")
        }
        if status.hasPrefix("Searching") || status.hasPrefix("Connecting") || status.contains("Reconnecting") {
            return (Theme.connecting, "Searching")
        }
        if status == "Bluetooth Disabled" { return (Theme.disconnected, "Bluetooth off") }
        return (Theme.disconnected, "Sensor off")
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.color)
                .frame(width: 8, height: 8)
            Text(state.text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.card, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sensor: \(state.text)")
    }
}

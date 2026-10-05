import SwiftUI

/// Screen 2: shows the selected time and lets the coach set up the drill.
struct SetupView: View {
    let sport: Sport
    @Binding var category: String
    @Binding var drill: String
    @Binding var intensity: Intensity
    @Binding var customTimeEnabled: Bool
    @Binding var customTime: Double

    let selectedTime: Double?
    let remainingTime: Double
    let timerRunning: Bool
    let connectionStatus: String
    let batteryLevel: Int?
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
        // Custom times move in 0.05 s steps, so they need hundredths
        return String(format: customTimeEnabled ? "%.2f" : "%.1f", selectedTime)
    }

    private var timeCaption: String { customTimeEnabled ? "Custom time" : "Ghost runner time" }

    private var startDisabled: Bool { selectedTime == nil && !monitoring }

    /// Last second of the countdown turns red, like the website's "hot" clock
    private var countdownHot: Bool { timerRunning && remainingTime <= 1.0 }

    private var countdownProgress: Double {
        guard timerRunning, let total = selectedTime, total > 0 else { return 1 }
        return min(max(remainingTime / total, 0), 1)
    }

    @State private var showSettings = false
    @State private var lowBatteryDismissed = false

    private var showLowBatteryBanner: Bool {
        guard let batteryLevel, !lowBatteryDismissed else { return false }
        return BatteryDisplay.needsWarning(batteryLevel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack {
                    Spacer()
                    SensorPill(status: connectionStatus, batteryLevel: batteryLevel)
                }

                if showLowBatteryBanner, let batteryLevel {
                    LowBatteryBanner(percent: batteryLevel) {
                        lowBatteryDismissed = true
                    }
                }

                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(bigNumber)
                            .font(.system(size: 120, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(countdownHot ? Theme.alert : Theme.text)
                        Text("s")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Theme.label)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                    Text(timeCaption)
                        .font(.footnote)
                        .foregroundStyle(Theme.label)

                    CountdownBar(progress: countdownProgress, hot: countdownHot)
                        .padding(.top, 12)
                        .opacity(timerRunning ? 1 : 0)   // keeps its space so the layout doesn't jump
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(timerRunning
                    ? "\(timeCaption), \(bigNumber) seconds left"
                    : "\(timeCaption), \(bigNumber) seconds")

                VStack(spacing: 0) {
                    PickerRow(label: times.categoryLabel, options: times.categories, selection: $category)
                    Rectangle()
                        .fill(Theme.divider)
                        .frame(height: 0.5)
                        .padding(.leading, 16)
                    PickerRow(label: "Drill", options: times.drills, selection: $drill)
                }
                .card()
                // Still editable, but dimmed while the custom time is in charge
                .opacity(customTimeEnabled ? 0.4 : 1)

                IntensityControl(selection: $intensity)
                    .opacity(customTimeEnabled ? 0.4 : 1)

                CustomTimeCard(isOn: $customTimeEnabled, time: $customTime)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .onChange(of: batteryLevel) { _, level in
            // A charged sensor re-arms the warning for next time
            if let level, !BatteryDisplay.needsWarning(level) {
                lowBatteryDismissed = false
            }
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
                    .foregroundStyle(startDisabled ? Theme.label : (monitoring ? Theme.onAlert : Theme.onAccent))
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(
                        monitoring ? Theme.alert : (startDisabled ? Theme.card : Theme.accent),
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

/// Routine / Pressure / Hair on fire: the selected option is a filled pill, the rest gray text.
/// Hair on fire uses the alert red, as on the website's preset cards.
private struct IntensityControl: View {
    @Binding var selection: Intensity

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Intensity.allCases) { level in
                let selected = level == selection
                let hot = level == .hairOnFire
                Button {
                    selection = level
                } label: {
                    Text(level.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? (hot ? Theme.onAlert : Theme.onAccent) : Theme.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(selected ? (hot ? Theme.alert : Theme.accent) : Color.clear, in: Capsule())
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

/// How the sensor battery is shown: an SF Symbol for the level, and red at or below 20%.
enum BatteryDisplay {
    static let lowThreshold = 20
    /// At or below this, the setup screen also shows a warning banner
    static let warningThreshold = 15

    static func needsWarning(_ percent: Int) -> Bool {
        percent <= warningThreshold
    }

    static func symbol(for percent: Int) -> String {
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    static func isLow(_ percent: Int) -> Bool {
        percent <= lowThreshold
    }
}

/// Small status pill: green when connected, amber while searching, red when off, plus battery level when known.
struct SensorPill: View {
    let status: String
    let batteryLevel: Int?

    // Battery only means something while connected
    private var battery: Int? {
        status.hasPrefix("Connected") ? batteryLevel : nil
    }

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

            if let battery {
                let color = BatteryDisplay.isLow(battery) ? Theme.alert : Theme.label
                Image(systemName: BatteryDisplay.symbol(for: battery))
                    .font(.caption)
                    .foregroundStyle(color)
                    .padding(.leading, 4)
                Text("\(battery)%")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.card, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let battery else { return "Sensor: \(state.text)" }
        let low = BatteryDisplay.isLow(battery) ? ", low" : ""
        return "Sensor: \(state.text), battery \(battery) percent\(low)"
    }
}

/// Drains from full to empty during the countdown; red in the last second.
private struct CountdownBar: View {
    let progress: Double
    let hot: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.card)
                Capsule()
                    .fill(hot ? Theme.alert : Theme.accent)
                    .frame(width: geo.size.width * progress)
            }
        }
        .frame(width: 240, height: 6)
    }
}

/// Shown once the sensor battery is at or below the warning level, until dismissed.
private struct LowBatteryBanner: View {
    let percent: Int
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "battery.25percent")
                .foregroundStyle(Theme.alert)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sensor battery low (\(percent)%)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text("Charge it after practice.")
                    .font(.footnote)
                    .foregroundStyle(Theme.label)
            }
            Spacer(minLength: 0)
            Button("Dismiss", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.label)
                .frame(width: 44, height: 44)   // comfortable tap target
                .contentShape(Rectangle())
        }
        .padding(16)
        .background(Theme.alert.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Theme.alert.opacity(0.4), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

/// Lets each coach dial in their own time instead of the table's.
private struct CustomTimeCard: View {
    @Binding var isOn: Bool
    @Binding var time: Double

    var body: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $isOn) {
                Text("Custom time")
                    .foregroundStyle(Theme.label)
            }
            .tint(Theme.accent)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)

            if isOn {
                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 0.5)
                    .padding(.leading, 16)

                HStack {
                    stepButton("Decrease", systemImage: "minus", steps: -1)
                    Spacer()
                    Text(String(format: "%.2f s", time))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                    Spacer()
                    stepButton("Increase", systemImage: "plus", steps: 1)
                }
                .padding(.horizontal, 8)
                .frame(minHeight: 60)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Custom time")
                .accessibilityValue(String(format: "%.2f seconds", time))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: time = CustomTime.adjusted(time, bySteps: 1)
                    case .decrement: time = CustomTime.adjusted(time, bySteps: -1)
                    @unknown default: break
                    }
                }
            }
        }
        .card()
    }

    private func stepButton(_ label: String, systemImage: String, steps: Int) -> some View {
        let atLimit = steps < 0 ? time <= CustomTime.range.lowerBound : time >= CustomTime.range.upperBound
        return Button(label, systemImage: systemImage) {
            time = CustomTime.adjusted(time, bySteps: steps)
        }
        .labelStyle(.iconOnly)
        .font(.title3.weight(.semibold))
        .foregroundStyle(atLimit ? Theme.label : Theme.accent)
        .frame(width: 52, height: 44)
        .background(Theme.background, in: Capsule())
        .contentShape(Capsule())
        .buttonRepeatBehavior(.enabled)   // hold to keep stepping
        .disabled(atLimit)
    }
}

import SwiftUI
import Combine

struct HitRecord: Identifiable {
    let id = UUID()
    let number: Int
    let delay: Double
    let time: Date
}

struct ContentView: View {

    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var sound: SoundPlayer

    private let delayOptions: [Double] = [3.9, 4.0, 4.1, 4.2, 4.3, 4.4]

    @State private var selectedDelay: Double = 4.0

    @State private var isRunning = false
    @State private var countdown: Double = 4.0
    @State private var isCounting = false

    @State private var hitCount = 0
    @State private var history: [HitRecord] = []
    @State private var lastHitText = "—"

    @State private var flashActive = false

    private let ticker = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {

            headerSection
            Divider()

            ScrollView {
                VStack(spacing: 20) {

                    connectionStatus
                    delayPicker
                    timerDisplay
                    controlButtons
                    lastHitRow
                    historySection

                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .background(flashActive ? Color.yellow.opacity(0.45) : Color(.systemBackground))
        .animation(.easeOut(duration: 0.2), value: flashActive)

        .onReceive(ble.hitPublisher) { _ in
            onHit()
        }

        .onReceive(ticker) { _ in
            onTick()
        }

        .onChange(of: selectedDelay) {
            if ble.isConnected {
                ble.sendDelay(selectedDelay)
            }
        }
    }

    // MARK: UI

    private var headerSection: some View {
        VStack(spacing: 4) {
            Image("GhostLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 80)
                .padding(.top, 12)

            Text("GHOST RUNNER")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
        }
        .padding(.bottom, 10)
    }

    private var connectionStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ble.isConnected ? Color.green : Color.red)
                .frame(width: 12, height: 12)

            Text(ble.statusText)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var delayPicker: some View {
        VStack(alignment: .leading, spacing: 6) {

            Text("DELAY (seconds)")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            Picker("Delay", selection: $selectedDelay) {
                ForEach(delayOptions, id: \.self) { d in
                    Text(String(format: "%.1f", d)).tag(d)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isRunning)
        }
    }

    private var timerDisplay: some View {
        VStack(spacing: 4) {

            Text(isCounting ? "TIME REMAINING" : (isRunning ? "ARMED" : "READY"))
                .font(.caption.bold())
                .foregroundColor(isRunning ? .green : .secondary)

            Text(String(format: "%.1f", isCounting ? countdown : selectedDelay))
                .font(.system(size: 88, weight: .bold, design: .monospaced))
                .foregroundColor(isCounting ? .green : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground))
                )
        }
    }

    private var controlButtons: some View {
        HStack(spacing: 16) {

            Button(action: tapStart) {
                Label("START", systemImage: "play.fill")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(isRunning || !ble.isConnected ? Color.gray : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }
            .disabled(isRunning || !ble.isConnected)

            Button(action: tapStop) {
                Label("STOP", systemImage: "stop.fill")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(!isRunning ? Color.gray : Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }
            .disabled(!isRunning)
        }
    }

    private var lastHitRow: some View {
        HStack {
            Image(systemName: "bolt.fill")
                .foregroundColor(.yellow)

            Text("Last hit")
                .font(.headline)

            Spacer()

            Text(lastHitText)
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {

            HStack {
                Text("SESSION HISTORY")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                Spacer()

                if !history.isEmpty {
                    Button("Clear") {
                        history = []
                        hitCount = 0
                        lastHitText = "—"
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
            }

            if history.isEmpty {

                Text("No hits yet this session")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)

            } else {

                ForEach(history.reversed()) { record in
                    HStack {

                        Text("Hit #\(record.number)")
                            .font(.body.bold())

                        Spacer()

                        Text(record.time.formatted(date: .omitted, time: .standard))
                            .foregroundColor(.secondary)

                        Text(String(format: "%.1f s", record.delay))
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 6)

                    Divider()
                }
            }
        }
    }

    // MARK: Actions

    private func tapStart() {
        isRunning = true
        isCounting = false
        countdown = selectedDelay

        ble.sendDelay(selectedDelay)
        ble.sendStart()
    }

    private func tapStop() {
        isRunning = false
        isCounting = false
        countdown = selectedDelay

        ble.sendStop()
    }

    private func onHit() {
        guard isRunning else { return }

        flashActive = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            flashActive = false
        }

        hitCount += 1
        let record = HitRecord(number: hitCount, delay: selectedDelay, time: Date())
        history.append(record)

        lastHitText = record.time.formatted(date: .omitted, time: .standard)

        countdown = selectedDelay
        isCounting = true
    }

    private func onTick() {
        guard isCounting else { return }

        countdown -= 0.05

        if countdown <= 0 {
            countdown = 0
            isCounting = false

            sound.playBuzzer()
        }
    }
}

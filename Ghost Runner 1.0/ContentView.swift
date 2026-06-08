import SwiftUI
import Combine

struct HitRecord: Identifiable {
    let id = UUID()
    let number: Int
    let delay: Double
    let time: Date
}

struct ContentView: View {

    @EnvironmentObject private var ble: BLEManager
    @EnvironmentObject private var sound: SoundPlayer

    private let delayOptions: [Double] = [3.9, 4.0, 4.1, 4.2, 4.3, 4.4]

    @State private var selectedDelay: Double = 4.0
    @State private var isRunning = false
    @State private var isCounting = false
    @State private var countdown: Double = 4.0

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

        // ✅ FIXED onReceive
        .onReceive(ble.hitPublisher) { (_: Void) in
            onHit()
        }

        .onReceive(ticker) { _ in
            onTick()
        }

        .onChange(of: selectedDelay) { _ in
            if ble.isConnected {
                ble.sendDelay(selectedDelay)
            }
        }
    }

    // MARK: UI

    private var headerSection: some View {
        VStack(spacing: 4) {
            Text("GHOST RUNNER")
                .font(.system(size: 26, weight: .heavy))
        }
        .padding(.bottom, 10)
    }

    private var connectionStatus: some View {
        HStack(spacing: 8) {

            Circle()
                .fill(ble.isConnected ? Color.green : Color.red)
                .frame(width: 12, height: 12)

            Text(ble.statusText)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var delayPicker: some View {
        VStack(alignment: .leading) {

            Text("DELAY")

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
        Text(String(format: "%.1f", isCounting ? countdown : selectedDelay))
            .font(.system(size: 80, weight: .bold, design: .monospaced))
            .frame(maxWidth: .infinity)
            .padding()
    }

    private var controlButtons: some View {

        HStack(spacing: 16) {

            Button(action: tapStart) {
                Label("START", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isRunning || !ble.isConnected ? Color.gray : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(isRunning || !ble.isConnected)

            Button(action: tapStop) {
                Label("STOP", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(!isRunning ? Color.gray : Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(!isRunning)
        }
    }

    private var lastHitRow: some View {
        HStack {

            Text("Last hit")

            Spacer()

            Text(lastHitText)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private var historySection: some View {

        VStack(alignment: .leading) {

            Text("HISTORY")

            ForEach(history.reversed()) { record in
                HStack {

                    Text("Hit #\(record.number)")

                    Spacer()

                    Text(String(format: "%.1f s", record.delay))
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

        let record = HitRecord(
            number: hitCount,
            delay: selectedDelay,
            time: Date()
        )

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

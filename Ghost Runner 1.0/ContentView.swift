//
//  ContentView.swift
//  Ghost Runner 1.0
//
//  Created by Alexander del Rio on 4/3/26.
//
import SwiftUI
struct ContentView: View {
@StateObject private var bleManager = BLEManager()

@State private var selectedDelay: Double = 4.0
@State private var remainingTime: Double = 0
@State private var timerRunning = false
@State private var timer: Timer?

let delayOptions: [Double] = [3.9, 4.0, 4.1, 4.2, 4.3, 4.4]

var body: some View {
    VStack(spacing: 24) {

        Image("GhostLogo")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .padding(.top, 20)

        Text("Ghost Runner")
            .font(.title)

        Picker("Delay", selection: $selectedDelay) {
            ForEach(delayOptions, id: \.self) { value in
                Text(String(format: "%.1f s", value))
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: selectedDelay) {
            bleManager.sendDelay(selectedDelay)
        }

        Text(statusText)

        VStack(spacing: 16) {

            Button("Start") {
                bleManager.startMonitoring()
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("Stop") {
                bleManager.stopMonitoring()
                stopTimer()
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .buttonStyle(.bordered)
            .controlSize(.large)
        }

        Button("Test Trigger") {
            SoundPlayer.shared.play()
        }
        .frame(maxWidth: .infinity, minHeight: 60)
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
    .padding()
    .onReceive(bleManager.triggerPublisher) { _ in
        startTimer()
    }
}

var statusText: String {
    if timerRunning {
        return "Timer: \(String(format: "%.1f", remainingTime)) s"
    } else {
        return bleManager.connectionStatus
    }
}

func startTimer() {
    stopTimer()
    remainingTime = selectedDelay
    timerRunning = true

    timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
        remainingTime -= 0.1
        if remainingTime <= 0 {
            stopTimer()
            SoundPlayer.shared.play()
        }
    }
}

func stopTimer() {
    timer?.invalidate()
    timer = nil
    timerRunning = false
}

}


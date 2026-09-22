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
            // Updated syntax to handle state values securely
            .onChange(of: selectedDelay) { _, newValue in
                bleManager.sendDelay(newValue)
            }
            
            Text(statusText)
                .font(.body)
                .foregroundColor(.secondary)
            
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
        // Fix the buzz time against the real clock so late or skipped ticks can't add drift
        let endTime = Date().addingTimeInterval(selectedDelay)
        remainingTime = selectedDelay
        timerRunning = true

        let newTimer = Timer(timeInterval: 0.01, repeats: true) { _ in
            remainingTime = max(0, endTime.timeIntervalSinceNow)
            if remainingTime <= 0 {
                stopTimer()
                SoundPlayer.shared.play()
            }
        }
        newTimer.tolerance = 0
        // .common keeps the timer firing while the UI is tracking touches
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
        timerRunning = false
    }
}

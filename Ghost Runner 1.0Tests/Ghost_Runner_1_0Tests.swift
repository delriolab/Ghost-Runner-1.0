//
//  Ghost_Runner_1_0Tests.swift
//  Ghost Runner 1.0Tests
//

import Foundation
import Testing
@testable import Ghost_Runner_1_0

struct StandardTimesTests {

    @Test(arguments: Sport.allCases)
    func everySetupHasATime(sport: Sport) {
        let times = StandardTimes.table(for: sport)
        for category in times.categories {
            for drill in times.drills {
                for intensity in Intensity.allCases {
                    let time = StandardTimes.time(sport: sport, category: category, drill: drill, intensity: intensity)
                    #expect(time != nil, "\(sport.title) \(category) \(drill) \(intensity.title) has no time")
                    #expect((time ?? 0) > 0, "\(sport.title) \(category) \(drill) \(intensity.title) must be positive")
                }
            }
        }
    }

    @Test(arguments: Sport.allCases)
    func harderIntensityIsNeverSlower(sport: Sport) {
        let times = StandardTimes.table(for: sport)
        for (category, drills) in times.times {
            for (drill, set) in drills {
                #expect(set.routine >= set.pressure, "\(sport.title) \(category) \(drill): Routine faster than Pressure")
                #expect(set.pressure >= set.hairOnFire, "\(sport.title) \(category) \(drill): Pressure faster than Hair on fire")
            }
        }
    }

    @Test(arguments: Sport.allCases)
    func defaultsExist(sport: Sport) {
        let times = StandardTimes.table(for: sport)
        #expect(times.categories.contains(times.defaultCategory))
        #expect(times.drills.contains(StandardTimes.defaultDrill))
    }
}

struct BatteryTests {

    @Test func readsBatteryLevelByte() {
        #expect(BLEManager.batteryPercent(from: Data([82])) == 82)
        #expect(BLEManager.batteryPercent(from: Data([0])) == 0)
        #expect(BLEManager.batteryPercent(from: Data([100])) == 100)
    }

    @Test func clampsOutOfRangeAndIgnoresEmptyValues() {
        #expect(BLEManager.batteryPercent(from: Data([255])) == 100)
        #expect(BLEManager.batteryPercent(from: Data()) == nil)
        #expect(BLEManager.batteryPercent(from: nil) == nil)
    }

    @Test func lowBatteryAtOrBelowTwentyPercent() {
        #expect(BatteryDisplay.isLow(20))
        #expect(BatteryDisplay.isLow(5))
        #expect(!BatteryDisplay.isLow(21))
    }

    @Test func symbolTracksLevel() {
        #expect(BatteryDisplay.symbol(for: 5) == "battery.0percent")
        #expect(BatteryDisplay.symbol(for: 25) == "battery.25percent")
        #expect(BatteryDisplay.symbol(for: 50) == "battery.50percent")
        #expect(BatteryDisplay.symbol(for: 80) == "battery.75percent")
        #expect(BatteryDisplay.symbol(for: 100) == "battery.100percent")
    }
}

struct CustomTimeTests {

    @Test func stepsByFiveHundredths() {
        #expect(CustomTime.adjusted(4.30, bySteps: 1) == 4.35)
        #expect(CustomTime.adjusted(4.30, bySteps: -1) == 4.25)
        #expect(CustomTime.adjusted(4.30, bySteps: -6) == 4.00)
    }

    @Test func snapsOffStepValuesToTheNearestStep() {
        #expect(CustomTime.adjusted(4.32, bySteps: 0) == 4.30)
        #expect(CustomTime.adjusted(4.33, bySteps: 0) == 4.35)
    }

    @Test func staysWithinRange() {
        #expect(CustomTime.adjusted(CustomTime.range.lowerBound, bySteps: -1) == CustomTime.range.lowerBound)
        #expect(CustomTime.adjusted(CustomTime.range.upperBound, bySteps: 1) == CustomTime.range.upperBound)
        #expect(CustomTime.adjusted(0, bySteps: 0) == CustomTime.range.lowerBound)
    }

    @Test func batteryWarningAtOrBelowFifteenPercent() {
        #expect(BatteryDisplay.needsWarning(15))
        #expect(BatteryDisplay.needsWarning(3))
        #expect(!BatteryDisplay.needsWarning(16))
    }
}

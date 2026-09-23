//
//  Ghost_Runner_1_0Tests.swift
//  Ghost Runner 1.0Tests
//

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

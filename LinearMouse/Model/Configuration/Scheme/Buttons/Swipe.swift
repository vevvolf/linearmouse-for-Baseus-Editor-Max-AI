// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

extension Scheme.Buttons {
    struct Swipe: Codable, Equatable, ImplicitInitable {
        static let thresholdRange: ClosedRange<Double> = 10 ... 200
        static let defaultThreshold: Double = 50
        static let spaceSwipeDistanceRange: ClosedRange<Double> = 200 ... 2000
        static let defaultSpaceSwipeDistance: Double = 900
        static let missionControlSwipeDistanceRange: ClosedRange<Double> = 100 ... 1000
        static let defaultMissionControlSwipeDistance: Double = 250

        var threshold: Double?
        var lockPointer: Bool?
        /// Drive Spaces, Mission Control and App Exposé swipes like a trackpad four-finger swipe.
        var continuous: Bool?
        /// Pointer movement of a continuous swipe that switches one Space.
        var spaceSwipeDistance: Double?
        /// Pointer movement of a continuous swipe that fully opens Mission Control or App Exposé.
        var missionControlSwipeDistance: Double?

        var effectiveThreshold: Double {
            guard let threshold, threshold.isFinite else {
                return Self.defaultThreshold
            }
            return min(max(threshold, Self.thresholdRange.lowerBound), Self.thresholdRange.upperBound)
        }

        var effectiveSpaceSwipeDistance: Double {
            Self.clamp(spaceSwipeDistance, to: Self.spaceSwipeDistanceRange, default: Self.defaultSpaceSwipeDistance)
        }

        var effectiveMissionControlSwipeDistance: Double {
            Self.clamp(
                missionControlSwipeDistance,
                to: Self.missionControlSwipeDistanceRange,
                default: Self.defaultMissionControlSwipeDistance
            )
        }

        private static func clamp(_ value: Double?, to range: ClosedRange<Double>, default: Double) -> Double {
            guard let value, value.isFinite else {
                return `default`
            }
            return min(max(value, range.lowerBound), range.upperBound)
        }

        func merge(into swipe: inout Self) {
            if let threshold {
                swipe.threshold = threshold
            }
            if let lockPointer {
                swipe.lockPointer = lockPointer
            }
            if let continuous {
                swipe.continuous = continuous
            }
            if let spaceSwipeDistance {
                swipe.spaceSwipeDistance = spaceSwipeDistance
            }
            if let missionControlSwipeDistance {
                swipe.missionControlSwipeDistance = missionControlSwipeDistance
            }
        }
    }
}

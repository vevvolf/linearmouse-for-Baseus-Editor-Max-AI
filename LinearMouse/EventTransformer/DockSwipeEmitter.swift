// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import GestureKit

/// Turns continuous swipe updates from button mappings into trackpad-style Dock swipes, so a
/// Space or Mission Control follows the pointer and can be dragged back before release.
final class DockSwipeEmitter {
    typealias Axis = ButtonMappingEngine.DockSwipeAxis
    typealias Update = ButtonMappingEngine.DockSwipeUpdate
    typealias Clock = () -> TimeInterval
    typealias Sink = (_ motion: DockSwipeMotion, _ phase: CGSGesturePhase, _ progress: Double, _ delta: Double,
                      _ velocity: Double, _ direction: IOHIDSwipeMask?) -> Void

    /// Only movement this recent counts toward the release velocity.
    static let velocityWindow: TimeInterval = 0.1
    /// Release velocity of a swipe past halfway. A mouse usually stops before the button is
    /// released, unlike fingers lifting off a trackpad, and Mission Control snaps back without it.
    static let completionVelocity: Double = 1.5
    /// Movement in one direction before it is reported as the swipe direction, as a trackpad does.
    static let directionThreshold: Double = 0.03

    /// Pointer movement that equals one full Space switch.
    let horizontalDistance: Double
    /// Pointer movement that fully opens Mission Control or App Exposé.
    let verticalDistance: Double
    private let clock: Clock
    private let sink: Sink

    private var axis: Axis?
    /// The swipe is only posted from its first movement: like a trackpad, its `.began` must
    /// already carry that movement, or Mission Control always moves toward the first Space.
    private var hasBegun = false
    private var progress = 0.0
    /// The last reported swipe direction.
    private var direction: IOHIDSwipeMask?
    private var isIncreasing: Bool?
    /// Progress where the input last turned around.
    private var turnProgress = 0.0
    private var samples = [(time: TimeInterval, progress: Double)]()

    init(
        horizontalDistance: Double = Scheme.Buttons.Swipe.defaultSpaceSwipeDistance,
        verticalDistance: Double = Scheme.Buttons.Swipe.defaultMissionControlSwipeDistance,
        clock: @escaping Clock = { ProcessInfo.processInfo.systemUptime },
        sink: @escaping Sink = DockSwipeEmitter.post
    ) {
        self.horizontalDistance = horizontalDistance
        self.verticalDistance = verticalDistance
        self.clock = clock
        self.sink = sink
    }

    var isActive: Bool {
        axis != nil
    }

    func handle(_ update: Update) {
        switch update {
        case let .began(axis):
            end()
            self.axis = axis
            progress = 0
            direction = nil
            isIncreasing = nil
            turnProgress = 0
            hasBegun = false
            samples = [(clock(), 0)]

        case let .changed(axis, delta):
            guard axis == self.axis, delta != 0 else {
                return
            }
            let step = delta / distance(of: axis)
            let previous = progress
            progress += step
            let now = clock()
            samples.append((now, progress))
            samples.removeAll { now - $0.time > Self.velocityWindow }
            if !hasBegun {
                hasBegun = true
                sink(Self.motion(of: axis), .began, progress, step, 0, nil)
            }
            sink(Self.motion(of: axis), .changed, progress, step, 0, newDirection(from: previous, axis: axis))

        case let .ended(axis):
            guard axis == self.axis else {
                return
            }
            end()
        }
    }

    /// Finishes an unfinished swipe, letting the Dock settle on the nearest state.
    func end() {
        guard let axis else {
            return
        }
        if hasBegun {
            sink(Self.motion(of: axis), .ended, progress, 0, releaseVelocity(), nil)
        }
        self.axis = nil
        samples.removeAll()
    }

    /// The direction to report when the input has moved far enough in a new direction.
    private func newDirection(from previous: Double, axis: Axis) -> IOHIDSwipeMask? {
        let increasing = progress > previous
        if increasing != isIncreasing {
            isIncreasing = increasing
            turnProgress = previous
        }
        let current = Self.swipeDirection(axis: axis, increasing: increasing)
        guard current != direction, abs(progress - turnProgress) >= Self.directionThreshold else {
            return nil
        }
        direction = current
        return current
    }

    /// Fingers moving left raise horizontal progress; fingers moving up lower vertical progress.
    private static func swipeDirection(axis: Axis, increasing: Bool) -> IOHIDSwipeMask {
        switch axis {
        case .horizontal:
            increasing ? .swipeLeft : .swipeRight
        case .vertical:
            increasing ? .swipeDown : .swipeUp
        }
    }

    private func releaseVelocity() -> Double {
        let velocity = recentVelocity()
        guard abs(progress) >= 0.5, velocity * progress >= 0 else {
            return velocity
        }
        let sign: Double = progress > 0 ? 1 : -1
        return sign * max(abs(velocity), Self.completionVelocity)
    }

    private func recentVelocity() -> Double {
        let now = clock()
        guard let first = samples.first(where: { now - $0.time <= Self.velocityWindow }),
              let last = samples.last,
              last.time > first.time else {
            return 0
        }
        return (last.progress - first.progress) / (last.time - first.time)
    }

    private static func motion(of axis: Axis) -> DockSwipeMotion {
        axis == .horizontal ? .horizontal : .vertical
    }

    private func distance(of axis: Axis) -> Double {
        axis == .horizontal ? horizontalDistance : verticalDistance
    }

    static func post(
        motion: DockSwipeMotion,
        phase: CGSGesturePhase,
        progress: Double,
        delta: Double,
        velocity: Double,
        direction: IOHIDSwipeMask?
    ) {
        GestureEvent(
            dockSwipeSource: nil,
            motion: motion,
            phase: phase,
            progress: progress,
            delta: delta,
            velocity: velocity,
            direction: direction
        )?.post(tap: .cgSessionEventTap)
    }
}

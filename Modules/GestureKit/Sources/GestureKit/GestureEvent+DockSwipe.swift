// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics

/// Axis of a Dock swipe, as reported by a trackpad four-finger swipe.
public enum DockSwipeMotion: Int64, Sendable {
    /// Switch Spaces and full-screen apps.
    case horizontal = 1
    /// Mission Control (negative progress) and App Exposé (positive progress).
    case vertical = 2
}

public extension GestureEvent {
    /// A continuous Dock swipe, the gesture the Dock tracks while four fingers move on a trackpad.
    ///
    /// The Dock follows `progress` as it changes, so the Space or Mission Control moves with the
    /// input. `progress` is cumulative since `.began`, in screen widths (or heights): positive
    /// horizontal progress moves to the Space on the right, negative vertical progress opens
    /// Mission Control. On `.ended` the Dock decides from `progress` and `velocity` (progress per
    /// second) whether to finish or snap back. `direction` marks where the input started moving,
    /// sent once a movement in a new direction is recognized; Mission Control relies on it.
    ///
    /// Field layout recorded from a built-in trackpad on macOS 26.
    convenience init?(
        dockSwipeSource source: CGEventSource?,
        motion: DockSwipeMotion,
        phase: CGSGesturePhase,
        progress: Double,
        delta: Double,
        velocity: Double = 0,
        direction: IOHIDSwipeMask? = nil
    ) {
        guard let gestureEvent = CGEvent(source: source),
              let dockEvent = CGEvent(source: source),
              let gestureType = CGEventType(nsEventType: .gesture),
              let dockControlType = CGEventType(rawValue: Self.dockControlEventType) else {
            return nil
        }

        // A trackpad sends each Dock control event right after an empty gesture event.
        gestureEvent.type = gestureType
        dockEvent.type = dockControlType
        dockEvent.setIntegerValueField(.gestureHIDType, value: Int64(IOHIDEventType.dockSwipe.rawValue))
        dockEvent.setIntegerValueField(.gestureSwipeMotion, value: motion.rawValue)
        dockEvent.setIntegerValueField(.gestureSwipeMotionAgain, value: motion.rawValue)
        dockEvent.setDoubleValueField(.gestureSwipeProgress, value: progress)
        dockEvent.setDoubleValueField(.gestureSwipeDelta, value: delta)
        dockEvent.setIntegerValueField(
            .gestureSwipeProgressFloatBits,
            value: Int64(Float(progress).bitPattern)
        )
        dockEvent.setIntegerValueField(.gesturePhase, value: Int64(phase.rawValue))
        dockEvent.setIntegerValueField(.gestureDockPhase, value: Int64(phase.rawValue))
        dockEvent.setIntegerValueField(.gestureDockSwipeFlag, value: 1)
        dockEvent.setIntegerValueField(.gestureDockSwipeKind, value: 3)
        if let direction {
            let mask = Int64(direction.rawValue)
            dockEvent.setIntegerValueField(.gestureSwipeValue, value: mask)
            dockEvent.setIntegerValueField(.gestureStartEndSeriesType, value: mask)
            dockEvent.setIntegerValueField(.gestureSwipeDirection, value: mask)
        }
        if phase == .ended {
            dockEvent.setDoubleValueField(.gestureSwipeVelocityX, value: velocity)
            dockEvent.setDoubleValueField(.gestureSwipeVelocityY, value: velocity)
        }

        self.init(cgEvents: [gestureEvent, dockEvent])
    }

    /// `kCGSEventDockControl`.
    private static let dockControlEventType: UInt32 = 30
}

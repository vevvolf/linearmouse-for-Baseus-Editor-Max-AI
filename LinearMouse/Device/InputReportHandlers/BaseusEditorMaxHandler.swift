// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

/// Turns the two extra buttons of the Baseus Editor Max (BS-007 Max) into mouse buttons.
///
/// The mouse exposes a single HID device with three input reports:
///
/// - Report 1 (9 bytes): boot-style keyboard, `| ID | modifiers | reserved | key × 6 |`
/// - Report 2 (3 bytes): consumer controls
/// - Report 3 (6 bytes): mouse, `| ID | buttons | X | Y | wheel | AC pan |`
///
/// Neither extra button is a mouse button. Their behaviour is a macro stored in the
/// firmware:
///
/// - **M (side) button** holds F11 (usage 0x44) in report 1 for as long as the button is
///   held, so press, hold and drag all work. On macOS F11 shows the desktop, so the handler
///   also disables F11 *from this device only* (see `BaseusKeyRemapper`).
/// - **AI button** sends nothing usable on macOS (its macro targets Baseus' Windows-only AI
///   assistant): only the "macro finished" cleanup, an empty report 1 followed by an empty
///   report 2, after release. It can therefore only act as a click, never a hold. The M
///   button sends the same cleanup roughly 500 ms after its own release, and sometimes about
///   170 ms *before* its F11. The ordinary buttons (left, right, ...) also send it about
///   550 ms after release. A cleanup therefore counts as an AI click only when no button
///   activity happened shortly before it, and the click is held back briefly and dropped if
///   F11 follows.
///
/// The handler synthesizes button 3 (back) for M and button 4 (forward) for AI, which
/// LinearMouse can then remap like any other button.
///
/// The side wheel sends AC pan of ±10 per notch. macOS handles it natively; set
/// Scrolling → Horizontal → "By lines" in LinearMouse to tame it, no handling needed here.
///
/// Report layout confirmed on-device over Bluetooth LE (firmware defaults).
///
/// Supported devices:
/// - Baseus Editor Max / BS-007 Max (0xFFF1:0x0012)
struct BaseusEditorMaxHandler: InputReportHandler {
    struct Product: Hashable {
        let vendorID: Int
        let productID: Int
    }

    static let supportedProducts: Set<Product> = [
        .init(vendorID: 0xFFF1, productID: 0x0012) // Baseus Editor Max (BS-007 Max)
    ]

    static let keyboardReportID: UInt8 = 0x01
    static let consumerReportID: UInt8 = 0x02
    static let mouseReportID: UInt8 = 0x03
    /// HID keyboard usage the firmware sends for the M button (F11).
    static let mButtonKeyUsage: UInt8 = 0x44

    /// Synthesized button numbers (0-based, like `CGMouseButton`).
    static let mButton = 3
    static let aiButton = 4

    /// Bit used in `InputReportContext.lastButtonStates` to remember that M is held.
    private static let mButtonMask: UInt8 = 1 << 3

    /// A cleanup arriving this soon after button activity belongs to that button, not to AI.
    static let buttonCleanupWindow: TimeInterval = 0.8
    /// Ignore cleanups that follow an AI click this closely (duplicate reports).
    static let aiDebounce: TimeInterval = 0.25
    /// How long an AI click is held back in case F11 follows (M sometimes leads with a cleanup).
    static let aiConfirmDelay: TimeInterval = 0.3

    typealias Scheduler = (_ delay: TimeInterval, _ work: @escaping () -> Void) -> Void

    private static let schedulerQueue = DispatchQueue(label: "LinearMouse.BaseusEditorMaxHandler")

    static func scheduleOnHandlerQueue(_ delay: TimeInterval, _ work: @escaping () -> Void) {
        schedulerQueue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Mutable timing state shared across reports and the delayed AI confirmation. Only one
    /// such mouse is expected, so a single box is enough.
    private final class State {
        let lock = NSLock()
        /// Last M or regular mouse button activity; any of them is followed by a cleanup.
        var lastButtonActivity: TimeInterval = -.infinity
        var lastMouseButtons: UInt8 = 0
        var lastAIClick: TimeInterval = -.infinity
        /// Bumped by every M press; a pending AI click only fires if it is unchanged.
        var mPressGeneration = 0
    }

    private let state = State()
    private let emit: MouseButtonEmitter
    private let now: () -> TimeInterval
    private let schedule: Scheduler
    private let suppressFunctionKey: () -> Void

    init(
        emit: @escaping MouseButtonEmitter = SyntheticMouseButtonEventEmitter.postHIDButton,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        schedule: @escaping Scheduler = BaseusEditorMaxHandler.scheduleOnHandlerQueue,
        suppressFunctionKey: @escaping () -> Void = { BaseusKeyRemapper.shared.apply() }
    ) {
        self.emit = emit
        self.now = now
        self.schedule = schedule
        self.suppressFunctionKey = suppressFunctionKey
    }

    func matches(vendorID: Int, productID: Int) -> Bool {
        Self.supportedProducts.contains(.init(vendorID: vendorID, productID: productID))
    }

    func alwaysNeedsReportObservation() -> Bool {
        true
    }

    func handleReport(_ context: InputReportContext, next: (InputReportContext) -> Void) {
        defer { next(context) }

        guard let reportID = context.report.first else {
            return
        }

        // The keyboard service is new after every reconnect, so (re)apply the F11 mapping on any
        // report, such as the first movement, before M is pressed. It is cheap once applied.
        suppressFunctionKey()

        switch reportID {
        case Self.keyboardReportID:
            handleKeyboardReport(context)
        case Self.consumerReportID:
            handleConsumerReport(context)
        case Self.mouseReportID:
            handleMouseReport(context)
        default:
            break
        }
    }

    private func handleKeyboardReport(_ context: InputReportContext) {
        // | ID | modifiers | reserved | key 1 ... key 6 |
        guard context.report.count >= 4 else {
            return
        }

        let keys = context.report.dropFirst(3)
        let mDown = keys.contains(Self.mButtonKeyUsage)
        let wasDown = context.lastButtonStates & Self.mButtonMask != 0

        if mDown || wasDown {
            state.lock.lock()
            state.lastButtonActivity = now()
            if mDown, !wasDown {
                state.mPressGeneration += 1
            }
            state.lock.unlock()
        }

        guard mDown != wasDown else {
            return
        }

        emit(Self.mButton, mDown)
        if mDown {
            context.lastButtonStates |= Self.mButtonMask
        } else {
            context.lastButtonStates &= ~Self.mButtonMask
        }
    }

    private func handleMouseReport(_ context: InputReportContext) {
        // | ID | buttons | X | Y | wheel | AC pan |
        guard context.report.count >= 2 else {
            return
        }

        // Only note the activity; the report itself is left to macOS.
        let buttons = context.report[context.report.startIndex + 1]
        state.lock.lock()
        if buttons != 0 || buttons != state.lastMouseButtons {
            state.lastButtonActivity = now()
        }
        state.lastMouseButtons = buttons
        state.lock.unlock()
    }

    private func handleConsumerReport(_ context: InputReportContext) {
        // Only the empty cleanup report is of interest.
        let isEmptyReport = context.report.dropFirst().allSatisfy { $0 == 0 }
        guard isEmptyReport else {
            return
        }

        guard context.lastButtonStates & Self.mButtonMask == 0 else {
            return
        }

        state.lock.lock()
        let time = now()
        guard time - state.lastButtonActivity > Self.buttonCleanupWindow,
              time - state.lastAIClick > Self.aiDebounce else {
            state.lock.unlock()
            return
        }
        state.lastAIClick = time
        let generation = state.mPressGeneration
        state.lock.unlock()

        schedule(Self.aiConfirmDelay) { [state, emit] in
            state.lock.lock()
            let mPressedMeanwhile = state.mPressGeneration != generation
            state.lock.unlock()
            guard !mPressedMeanwhile else {
                return
            }
            emit(Self.aiButton, true)
            emit(Self.aiButton, false)
        }
    }

    func releasePressedButtons(_ context: InputReportContext) {
        if context.lastButtonStates & Self.mButtonMask != 0 {
            emit(Self.mButton, false)
        }
        context.lastButtonStates &= ~Self.mButtonMask
    }
}

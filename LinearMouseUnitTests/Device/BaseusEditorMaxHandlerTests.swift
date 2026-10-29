// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

/// Replays report sequences captured from a real Baseus Editor Max over Bluetooth LE.
final class BaseusEditorMaxHandlerTests: XCTestCase {
    private final class Harness {
        var time: TimeInterval = 0
        var events: [(button: Int, down: Bool)] = []
        var suppressCalls = 0
        var lastButtonStates: UInt8 = 0
        /// Delayed AI confirmations, run when the test advances time past them.
        var pending: [(due: TimeInterval, work: () -> Void)] = []

        lazy var handler = BaseusEditorMaxHandler(
            emit: { [weak self] button, down in self?.events.append((button, down)) },
            now: { [weak self] in self?.time ?? 0 },
            schedule: { [weak self] delay, work in
                guard let self else {
                    return
                }
                pending.append((time + delay, work))
            },
            suppressFunctionKey: { [weak self] in self?.suppressCalls += 1 }
        )

        /// Feeds one report at `time` seconds, carrying button state like `Device` does.
        func feed(_ bytes: [UInt8], at time: TimeInterval) {
            advance(to: time)
            let context = InputReportContext(report: Data(bytes), lastButtonStates: lastButtonStates)
            handler.handleReport(context) { _ in }
            lastButtonStates = context.lastButtonStates
        }

        /// Moves the clock forward, running delayed work that became due on the way.
        func advance(to time: TimeInterval) {
            while let index = pending.indices.min(by: { pending[$0].due < pending[$1].due }),
                  pending[index].due <= time {
                let item = pending.remove(at: index)
                self.time = item.due
                item.work()
            }
            self.time = time
        }
    }

    private static let emptyKeyboard: [UInt8] = [0x01, 0, 0, 0, 0, 0, 0, 0, 0]
    private static let f11Down: [UInt8] = [0x01, 0, 0, 0x44, 0, 0, 0, 0, 0]
    private static let emptyConsumer: [UInt8] = [0x02, 0, 0]

    private func assertEvents(
        _ harness: Harness,
        _ expected: [(Int, Bool)],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(harness.events.map(\.button), expected.map(\.0), file: file, line: line)
        XCTAssertEqual(harness.events.map(\.down), expected.map(\.1), file: file, line: line)
    }

    func testMatchesBaseusEditorMaxOnly() {
        let handler = BaseusEditorMaxHandler()

        XCTAssertTrue(handler.matches(vendorID: 0xFFF1, productID: 0x0012))
        XCTAssertFalse(handler.matches(vendorID: 0xFFF1, productID: 0x0013))
        XCTAssertFalse(handler.matches(vendorID: 0x1234, productID: 0x0012))
        XCTAssertTrue(handler.alwaysNeedsReportObservation())
    }

    func testRegistryReturnsHandlerForDevice() {
        let handlers = InputReportHandlerRegistry.handlers(for: 0xFFF1, productID: 0x0012)

        XCTAssertTrue(handlers.contains { $0 is BaseusEditorMaxHandler })
    }

    func testAIButtonClicks() {
        // Captured: three AI presses, each only an empty keyboard + consumer cleanup.
        let harness = Harness()
        for time in [11.04, 11.76, 12.57] {
            harness.feed(Self.emptyKeyboard, at: time)
            harness.feed(Self.emptyConsumer, at: time)
        }
        harness.advance(to: 20)

        assertEvents(harness, [(4, true), (4, false), (4, true), (4, false), (4, true), (4, false)])
    }

    func testMButtonPressAndReleaseWithoutPhantomAIClicks() {
        // Captured: quick M presses, each followed ~500 ms after release by a cleanup.
        let harness = Harness()
        harness.feed(Self.f11Down, at: 26.14)
        harness.feed(Self.emptyKeyboard, at: 26.31)
        harness.feed(Self.f11Down, at: 26.82)
        harness.feed(Self.emptyKeyboard, at: 27.01)
        harness.feed(Self.emptyKeyboard, at: 27.55)
        harness.feed(Self.emptyConsumer, at: 27.55)
        harness.feed(Self.f11Down, at: 27.66)
        harness.feed(Self.emptyKeyboard, at: 27.86)
        harness.feed(Self.emptyKeyboard, at: 28.35)
        harness.feed(Self.emptyConsumer, at: 28.36)
        harness.advance(to: 40)

        assertEvents(harness, [(3, true), (3, false), (3, true), (3, false), (3, true), (3, false)])
        XCTAssertEqual(harness.lastButtonStates, 0)
        XCTAssertGreaterThan(harness.suppressCalls, 0)
    }

    func testMButtonHoldLastsUntilRelease() {
        // Captured: M held for 5.3 s, then 2.3 s, with no reports in between.
        let harness = Harness()
        harness.feed(Self.f11Down, at: 3.37)
        XCTAssertEqual(harness.lastButtonStates, 1 << 3)
        harness.feed(Self.emptyKeyboard, at: 8.63)
        harness.feed(Self.emptyKeyboard, at: 9.19)
        harness.feed(Self.emptyConsumer, at: 9.20)
        harness.feed(Self.f11Down, at: 11.22)
        harness.feed(Self.emptyKeyboard, at: 13.55)
        harness.feed(Self.emptyKeyboard, at: 14.06)
        harness.feed(Self.emptyConsumer, at: 14.07)
        harness.advance(to: 20)

        assertEvents(harness, [(3, true), (3, false), (3, true), (3, false)])
    }

    func testCleanupJustBeforeMIsNotAnAIClick() {
        // Captured: an M press led by a cleanup 170 ms before its F11, then two AI presses.
        let harness = Harness()
        harness.feed(Self.emptyKeyboard, at: 8.23)
        harness.feed(Self.emptyConsumer, at: 8.23)
        harness.feed(Self.f11Down, at: 8.40)
        harness.feed(Self.emptyKeyboard, at: 9.67)
        harness.feed(Self.emptyKeyboard, at: 10.22)
        harness.feed(Self.emptyConsumer, at: 10.22)
        harness.feed(Self.emptyKeyboard, at: 16.90)
        harness.feed(Self.emptyConsumer, at: 16.90)
        harness.feed(Self.emptyKeyboard, at: 24.21)
        harness.feed(Self.emptyConsumer, at: 24.21)
        harness.advance(to: 30)

        assertEvents(harness, [(3, true), (3, false), (4, true), (4, false), (4, true), (4, false)])
    }

    func testAIClickIsDelayedUntilConfirmed() {
        let harness = Harness()
        harness.feed(Self.emptyConsumer, at: 1.00)
        XCTAssertTrue(harness.events.isEmpty)

        harness.advance(to: 1.00 + BaseusEditorMaxHandler.aiConfirmDelay)
        assertEvents(harness, [(4, true), (4, false)])
    }

    func testAIClickAfterMOnceCleanupWindowHasPassed() {
        let harness = Harness()
        harness.feed(Self.f11Down, at: 30.33)
        harness.feed(Self.emptyKeyboard, at: 30.48)
        harness.feed(Self.emptyConsumer, at: 30.97) // M cleanup, ignored
        harness.feed(Self.emptyKeyboard, at: 33.00)
        harness.feed(Self.emptyConsumer, at: 33.00) // AI click
        harness.advance(to: 40)

        assertEvents(harness, [(3, true), (3, false), (4, true), (4, false)])
    }

    func testCleanupAfterLeftClickIsNotAnAIClick() {
        // Captured: four left clicks, each followed ~550 ms after release by a cleanup.
        let harness = Harness()
        for (down, up, cleanup) in [(28.40, 28.52, 29.09), (29.16, 29.29, 29.82), (29.87, 29.98, 30.54),
                                    (30.74, 30.87, 31.44)] {
            harness.feed([0x03, 0x01, 0, 0, 0, 0], at: down)
            harness.feed([0x03, 0x00, 0, 0, 0, 0], at: up)
            harness.feed(Self.emptyKeyboard, at: cleanup)
            harness.feed(Self.emptyConsumer, at: cleanup)
        }
        harness.feed(Self.emptyKeyboard, at: 35.00)
        harness.feed(Self.emptyConsumer, at: 35.00) // AI click
        harness.advance(to: 40)

        assertEvents(harness, [(4, true), (4, false)])
    }

    func testDuplicateCleanupIsDebounced() {
        let harness = Harness()
        harness.feed(Self.emptyConsumer, at: 5.00)
        harness.feed(Self.emptyConsumer, at: 5.05)
        harness.advance(to: 10)

        assertEvents(harness, [(4, true), (4, false)])
    }

    func testMouseReportsAreLeftToMacOS() {
        let harness = Harness()
        harness.feed([0x03, 0x01, 0, 0, 0, 0], at: 1) // left button
        harness.feed([0x03, 0x00, 0, 0, 0, 0x0A], at: 2) // side wheel

        XCTAssertTrue(harness.events.isEmpty)
    }

    func testReleasePressedButtonsReleasesHeldM() {
        let harness = Harness()
        harness.feed(Self.f11Down, at: 1)

        let context = InputReportContext(report: Data(), lastButtonStates: harness.lastButtonStates)
        harness.handler.releasePressedButtons(context)

        assertEvents(harness, [(3, true), (3, false)])
        XCTAssertEqual(context.lastButtonStates, 0)
    }

    func testMouseMovementAppliesFunctionKeyMapping() {
        // After a reconnect, the mapping must be in place before M is first pressed.
        let harness = Harness()
        harness.feed([0x03, 0x00, 0x05, 0x00, 0, 0], at: 1)

        XCTAssertEqual(harness.suppressCalls, 1)
    }

    func testCallsNextForEveryReport() {
        let handler = BaseusEditorMaxHandler(emit: { _, _ in }, now: { 0 }, suppressFunctionKey: {})
        for report in [Self.f11Down, Self.emptyConsumer, [0x03, 0, 0, 0, 0, 0], []] {
            var nextCalled = false
            handler.handleReport(InputReportContext(report: Data(report), lastButtonStates: 0)) { _ in
                nextCalled = true
            }
            XCTAssertTrue(nextCalled)
        }
    }
}

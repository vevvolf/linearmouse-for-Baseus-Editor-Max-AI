// MIT License
// Copyright (c) 2021-2026 LinearMouse

import GestureKit
@testable import LinearMouse
import XCTest

final class DockSwipeEmitterTests: XCTestCase {
    private struct Posted: Equatable {
        var motion: DockSwipeMotion
        var phase: CGSGesturePhase
        var progress: Double
        var velocity: Double
        var direction: IOHIDSwipeMask?
    }

    private var time: TimeInterval = 0
    private var posted = [Posted]()

    private lazy var emitter = DockSwipeEmitter(
        horizontalDistance: 600,
        verticalDistance: 400,
        clock: { [unowned self] in time }
    ) { [unowned self] motion, phase, progress, _, velocity, direction in
        posted.append(.init(motion: motion, phase: phase, progress: progress, velocity: velocity, direction: direction))
    }

    func testProgressAccumulatesInScreenFractions() {
        emitter.handle(.began(.horizontal))
        time = 0.05
        emitter.handle(.changed(.horizontal, delta: 600 / 2))
        time = 0.1
        emitter.handle(.changed(.horizontal, delta: 600 / 4))
        emitter.handle(.ended(.horizontal))

        XCTAssertEqual(posted.map(\.phase), [.began, .changed, .changed, .ended])
        XCTAssertEqual(posted.map(\.progress), [0.5, 0.5, 0.75, 0.75])
        XCTAssertEqual(posted.map(\.motion), Array(repeating: .horizontal, count: 4))
        XCTAssertFalse(emitter.isActive)
    }

    func testReleaseVelocityUsesRecentMovement() {
        emitter.handle(.began(.vertical))
        time = 0.5
        emitter.handle(.changed(.vertical, delta: -400 / 2))
        time = 0.55
        emitter.handle(.changed(.vertical, delta: -400 / 5))
        emitter.handle(.ended(.vertical))

        XCTAssertEqual(posted.last?.phase, .ended)
        XCTAssertEqual(posted.last?.progress ?? 0, -0.7, accuracy: 1e-9)
        XCTAssertEqual(posted.last?.velocity ?? 0, -4, accuracy: 1e-9)
    }

    func testReleaseBeforeHalfwayAfterPauseHasNoVelocity() {
        emitter.handle(.began(.horizontal))
        emitter.handle(.changed(.horizontal, delta: 100))
        time = 1
        emitter.handle(.ended(.horizontal))

        XCTAssertEqual(posted.last?.velocity, 0)
    }

    func testReleasePastHalfwayCompletesAfterPause() {
        emitter.handle(.began(.horizontal))
        emitter.handle(.changed(.horizontal, delta: -400))
        time = 1
        emitter.handle(.ended(.horizontal))

        XCTAssertEqual(posted.last?.velocity, -DockSwipeEmitter.completionVelocity)
    }

    func testReleaseWhileMovingBackKeepsVelocity() {
        emitter.handle(.began(.horizontal))
        emitter.handle(.changed(.horizontal, delta: 480))
        time = 1
        emitter.handle(.changed(.horizontal, delta: -60))
        time = 1.05
        emitter.handle(.changed(.horizontal, delta: -60))
        emitter.handle(.ended(.horizontal))

        XCTAssertEqual(posted.last?.progress ?? 0, 0.6, accuracy: 1e-9)
        XCTAssertEqual(posted.last?.velocity ?? 0, -2, accuracy: 1e-9)
    }

    func testProgressCanCrossSeveralSpaces() {
        emitter.handle(.began(.horizontal))
        emitter.handle(.changed(.horizontal, delta: 900))
        emitter.handle(.changed(.horizontal, delta: -60))

        XCTAssertEqual(posted.map(\.progress), [1.5, 1.5, 1.4])
    }

    func testDirectionIsReportedOncePerTurn() {
        emitter.handle(.began(.horizontal))
        emitter.handle(.changed(.horizontal, delta: 6)) // 0.01
        emitter.handle(.changed(.horizontal, delta: 18)) // 0.04, recognized
        emitter.handle(.changed(.horizontal, delta: 60))
        emitter.handle(.changed(.horizontal, delta: -12)) // back 0.02
        emitter.handle(.changed(.horizontal, delta: -12)) // back 0.04, recognized
        emitter.handle(.changed(.horizontal, delta: -60))

        XCTAssertEqual(posted.map(\.direction), [nil, nil, .swipeLeft, nil, nil, .swipeRight, nil])
    }

    func testVerticalDirectionFollowsFingers() {
        emitter.handle(.began(.vertical))
        emitter.handle(.changed(.vertical, delta: -40))

        XCTAssertEqual(posted.last?.direction, .swipeUp)
    }

    func testEndFinishesActiveSwipeOnce() {
        emitter.handle(.began(.horizontal))
        emitter.handle(.changed(.horizontal, delta: 100))
        emitter.end()
        emitter.end()
        emitter.handle(.changed(.horizontal, delta: 100))

        XCTAssertEqual(posted.map(\.phase), [.began, .changed, .ended])
    }

    func testBeganCarriesFirstMovement() {
        // Mission Control takes the direction from the first event and ignores a zero start.
        emitter.handle(.began(.horizontal))
        XCTAssertTrue(posted.isEmpty)
        emitter.handle(.changed(.horizontal, delta: 30))

        XCTAssertEqual(posted.map(\.phase), [.began, .changed])
        XCTAssertEqual(posted.first?.progress, 0.05)
    }

    func testSwipeWithoutMovementPostsNothing() {
        emitter.handle(.began(.horizontal))
        emitter.handle(.ended(.horizontal))

        XCTAssertTrue(posted.isEmpty)
        XCTAssertFalse(emitter.isActive)
    }
}

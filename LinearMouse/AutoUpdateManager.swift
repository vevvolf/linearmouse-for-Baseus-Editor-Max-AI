// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Defaults
import Foundation
import Sparkle
import Version

class AutoUpdateManager: NSObject {
    static let shared = AutoUpdateManager()

    private var _controller: SPUStandardUpdaterController!
    var controller: SPUStandardUpdaterController {
        _controller
    }

    override init() {
        super.init()
        _controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }
}

extension AutoUpdateManager: SPUUpdaterDelegate {
    /// This build adds Baseus Editor Max support that official releases lack, and the update
    /// feed serves official releases, so an update would silently replace it. Never update.
    func updater(_: SPUUpdater, mayPerform _: SPUUpdateCheck) throws {
        throw NSError(
            domain: Bundle.main.bundleIdentifier ?? "LinearMouse",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "Updates are disabled in this build: official releases lack its Baseus Editor Max support."
            ]
        )
    }

    func allowedChannels(for _: SPUUpdater) -> Set<String> {
        Defaults[.betaChannelOn] ? ["beta"] : []
    }

    func versionComparator(for _: SPUUpdater) -> SUVersionComparison? {
        SemanticVersioningComparator()
    }
}

class SemanticVersioningComparator: SUVersionComparison {
    func compareVersion(_ versionA: String, toVersion versionB: String) -> ComparisonResult {
        guard let a = try? Version(versionA) else {
            return .orderedAscending
        }
        guard let b = try? Version(versionB) else {
            return .orderedDescending
        }
        if a < b {
            return .orderedAscending
        }
        if a > b {
            return .orderedDescending
        }
        return .orderedSame
    }
}

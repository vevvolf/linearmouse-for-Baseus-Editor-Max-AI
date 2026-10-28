// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import Foundation
import os.log

/// Stops the F11 keystroke that the Baseus Editor Max firmware sends for its M button from
/// reaching apps (F11 shows the desktop on macOS).
///
/// It sets a `UserKeyMapping` on the mouse's own keyboard service only, the same mechanism
/// as `hidutil property --matching '{"VendorID":0xFFF1,"ProductID":0x12}' --set ...`, so real
/// keyboards keep their F11. Raw input reports are read before the key mapping is applied,
/// which is why `BaseusEditorMaxHandler` still sees F11 and can synthesize the button.
///
/// The mapping lives on the HID service: it disappears when the mouse disconnects, and it is
/// cleared when LinearMouse quits.
final class BaseusKeyRemapper {
    static let shared = BaseusKeyRemapper()

    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "LinearMouse",
        category: "BaseusKeyRemapper"
    )

    private static let vendorID = 0xFFF1
    private static let productID = 0x0012

    /// HID usage page 7 (keyboard) shifted into the high 32 bits, as UserKeyMapping expects.
    private static let keyboardUsagePageBase: UInt64 = 0x7_0000_0000
    private static let f11: UInt64 = keyboardUsagePageBase | 0x44
    /// F20: present in the HID tables, unbound on macOS by default.
    private static let unusedKey: UInt64 = keyboardUsagePageBase | 0x6F

    private static let userKeyMappingKey = "UserKeyMapping" as CFString

    private let lock = NSLock()
    private var remappedServiceIDs: Set<UInt64> = []
    private var lastAttempt: TimeInterval = -.infinity
    private var terminationObserver: NSObjectProtocol?

    private init() {
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.clear()
        }
    }

    /// Applies the mapping to any matching keyboard service that does not have it yet.
    /// Cheap to call on every keyboard report: it rescans services at most once a second.
    func apply() {
        lock.lock()
        defer { lock.unlock() }

        let time = ProcessInfo.processInfo.systemUptime
        guard time - lastAttempt >= 1 else {
            return
        }
        lastAttempt = time

        let mapping: [[String: UInt64]] = [[
            "HIDKeyboardModifierMappingSrc": Self.f11,
            "HIDKeyboardModifierMappingDst": Self.unusedKey
        ]]

        var liveServiceIDs: Set<UInt64> = []
        for service in Self.matchingKeyboardServices() {
            guard let serviceID = Self.registryID(of: service) else {
                continue
            }
            liveServiceIDs.insert(serviceID)
            guard !remappedServiceIDs.contains(serviceID) else {
                continue
            }
            if Self.isTrue(IOHIDServiceClientSetProperty(service, Self.userKeyMappingKey, mapping as CFArray)) {
                remappedServiceIDs.insert(serviceID)
                os_log(
                    "Remapped F11 to F20 on Baseus keyboard service %{public}llu",
                    log: Self.log,
                    type: .info,
                    serviceID
                )
            } else {
                os_log(
                    "Failed to set UserKeyMapping on Baseus keyboard service %{public}llu",
                    log: Self.log,
                    type: .error,
                    serviceID
                )
            }
        }
        // Forget services that went away (the mouse reconnected), so new ones get remapped.
        remappedServiceIDs.formIntersection(liveServiceIDs)
    }

    /// Removes the mapping from every matching service.
    func clear() {
        lock.lock()
        defer { lock.unlock() }

        for service in Self.matchingKeyboardServices() {
            _ = IOHIDServiceClientSetProperty(service, Self.userKeyMappingKey, [] as CFArray)
        }
        remappedServiceIDs.removeAll()
        lastAttempt = -.infinity
    }

    private static func matchingKeyboardServices() -> [IOHIDServiceClient] {
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        guard let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else {
            return []
        }
        return services.filter { service in
            intProperty(service, kIOHIDVendorIDKey) == vendorID
                && intProperty(service, kIOHIDProductIDKey) == productID
                && conformsToKeyboard(service)
        }
    }

    private static func conformsToKeyboard(_ service: IOHIDServiceClient) -> Bool {
        let usagePage = UInt32(kHIDPage_GenericDesktop)
        let usage = UInt32(kHIDUsage_GD_Keyboard)
        return isTrue(IOHIDServiceClientConformsTo(service, usagePage, usage))
    }

    private static func intProperty(_ service: IOHIDServiceClient, _ key: String) -> Int? {
        (IOHIDServiceClientCopyProperty(service, key as CFString) as? NSNumber)?.intValue
    }

    private static func registryID(of service: IOHIDServiceClient) -> UInt64? {
        IOHIDServiceClientGetRegistryID(service) as? UInt64
    }

    /// IOKit's `Boolean` imports as `Bool` or as an integer depending on the declaring header.
    private static func isTrue(_ value: Bool) -> Bool {
        value
    }

    private static func isTrue(_ value: DarwinBoolean) -> Bool {
        value.boolValue
    }

    private static func isTrue<T: BinaryInteger>(_ value: T) -> Bool {
        value != 0
    }
}

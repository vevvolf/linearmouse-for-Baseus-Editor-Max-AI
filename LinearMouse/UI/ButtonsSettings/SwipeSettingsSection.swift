// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct SwipeSettingsSection: View {
    @ObservedObject private var state = ButtonsSettingsState.shared

    private static let thresholdFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    var body: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                Slider(
                    value: $state.swipeThreshold,
                    in: Scheme.Buttons.Swipe.thresholdRange,
                    step: 5
                ) {
                    Text("Swipe trigger distance")
                }
                DeferredNumberField(
                    value: $state.swipeThreshold,
                    formatter: Self.thresholdFormatter,
                    range: Scheme.Buttons.Swipe.thresholdRange
                )
                .frame(width: 72)
                .accessibility(label: Text("Swipe trigger distance"))
                Text("pixels")
                    .foregroundColor(.secondary)
            }

            Toggle("Lock pointer during swipes", isOn: $state.lockPointerDuringSwipe)

            Toggle(isOn: $state.continuousSwipes) {
                withDescription {
                    Text("Trackpad-like swipes")
                    Text(
                        "Spaces, Mission Control and App Exposé follow the pointer like a four-finger trackpad swipe."
                    )
                }
            }

            if state.continuousSwipes {
                distanceSlider(
                    "Space switch distance",
                    value: $state.spaceSwipeDistance,
                    in: Scheme.Buttons.Swipe.spaceSwipeDistanceRange
                )
                distanceSlider(
                    "Mission Control distance",
                    value: $state.missionControlSwipeDistance,
                    in: Scheme.Buttons.Swipe.missionControlSwipeDistanceRange
                )
            }

            Button("Reset") {
                state.resetSwipeSettings()
            }
            .disabled(!state.hasSwipeSettingsOverride)
        } header: {
            Text("Swipe Settings")
        }
        .modifier(SectionViewModifier())
    }

    private func distanceSlider(
        _ title: LocalizedStringKey,
        value: Binding<Double>,
        in range: ClosedRange<Double>
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Slider(value: value, in: range, step: 10) {
                Text(title)
            } minimumValueLabel: {
                Text("Sensitive")
            } maximumValueLabel: {
                Text("Firm")
            }
            DeferredNumberField(value: value, formatter: Self.thresholdFormatter, range: range)
                .frame(width: 72)
                .accessibility(label: Text(title))
            Text("pixels")
                .foregroundColor(.secondary)
        }
    }
}

import SwiftUI
import VampCore

/// Name, role, mute, solo and volume for one layer.
struct LaneHeader: View {
    @Environment(AppModel.self) private var app
    let layer: Layer
    let error: String?

    var body: some View {
        let tint = Theme.color(for: layer.role)
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Image(systemName: Theme.symbol(for: layer.role))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7).fill(tint.opacity(0.16)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(layer.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(layer.role.label).font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 4)
                if let error {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.danger)
                        .help(error)
                }
            }
            HStack(spacing: 6) {
                IconToggle(symbol: "M", isOn: layer.muted, tint: Theme.muted, help: "Mute") {
                    app.updateLayer(layer.id) { $0.muted.toggle() }
                }
                IconToggle(symbol: "S", isOn: layer.solo, tint: Color(hex: 0xFFC15E), help: "Solo") {
                    app.updateLayer(layer.id) { $0.solo.toggle() }
                }
                GainSlider(value: layer.gain, tint: tint) { value in
                    app.updateLayer(layer.id, coalesce: true) { $0.gain = value }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
    }
}

/// A slim volume bar. Drag to set, double-click to reset to 0.8.
struct GainSlider: View {
    let value: Double
    let tint: Color
    let onChange: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let fraction = value / Song.gainRange.upperBound
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.raised)
                Capsule().fill(tint.opacity(0.8)).frame(width: max(6, geo.size.width * fraction))
            }
            .frame(height: 6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let ratio = min(max(drag.location.x / geo.size.width, 0), 1)
                onChange((ratio * Song.gainRange.upperBound * 100).rounded() / 100)
            })
            .onTapGesture(count: 2) { onChange(0.8) }
        }
        .frame(height: 20)
        .help("Volume \(Int(value * 100))%")
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int(value * 100)) percent")
        .accessibilityAdjustableAction { direction in
            onChange(min(max(value + (direction == .increment ? 0.05 : -0.05), 0), Song.gainRange.upperBound))
        }
    }
}

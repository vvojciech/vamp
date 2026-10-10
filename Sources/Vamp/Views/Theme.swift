import SwiftUI
import VampCore

/// Colours come from the app icon: midnight indigo with warm and cool light.
enum Theme {
    static let window = Color(hex: 0x0E0F20)
    static let panel = Color(hex: 0x14152B)
    static let lane = Color(hex: 0x191A35)
    static let laneSelected = Color(hex: 0x20214180)
    static let raised = Color(hex: 0x23244A)
    static let line = Color.white.opacity(0.07)
    static let lineStrong = Color.white.opacity(0.16)
    static let text = Color.white.opacity(0.92)
    static let muted = Color.white.opacity(0.55)
    static let faint = Color.white.opacity(0.32)
    static let accent = Color(hex: 0xFF7A59)
    static let danger = Color(hex: 0xFF5C70)
    static let playhead = Color.white

    static let mono = Font.system(size: 12.5, design: .monospaced)

    static func color(for role: LayerRole) -> Color {
        switch role {
        case .drums: Color(hex: 0xFF7A59)
        case .percussion: Color(hex: 0xFFA36B)
        case .bass: Color(hex: 0x3FD8C7)
        case .chords: Color(hex: 0xFFC15E)
        case .pad: Color(hex: 0xA99BFF)
        case .lead: Color(hex: 0xFF6FB5)
        case .arp: Color(hex: 0x5CC8FF)
        case .fx: Color(hex: 0xB5E86B)
        }
    }

    static func symbol(for role: LayerRole) -> String {
        switch role {
        case .drums: "circle.hexagongrid.fill"
        case .percussion: "hand.tap.fill"
        case .bass: "waveform.path"
        case .chords: "pianokeys"
        case .pad: "cloud.fill"
        case .lead: "music.note"
        case .arp: "arrow.up.right"
        case .fx: "sparkles"
        }
    }
}

extension Color {
    /// 0xRRGGBB or 0xRRGGBBAA.
    init(hex: UInt32) {
        let hasAlpha = hex > 0xFFFFFF
        let r = Double((hex >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = Double((hex >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = Double((hex >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? Double(hex & 0xFF) / 255 : 1
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

extension LayerRole {
    var label: String { rawValue.capitalized }
}

/// Small rounded icon button used in lane headers and the transport.
struct IconToggle: View {
    let symbol: String
    let isOn: Bool
    let tint: Color
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .frame(width: 22, height: 20)
                .foregroundStyle(isOn ? Color.black.opacity(0.85) : Theme.muted)
                .background(RoundedRectangle(cornerRadius: 5).fill(isOn ? tint : Theme.raised))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

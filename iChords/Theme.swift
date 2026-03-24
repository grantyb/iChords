import SwiftUI

enum Theme {
    static let bg = Color(red: 0.071, green: 0.071, blue: 0.071)
    static let surface = Color(red: 0.118, green: 0.118, blue: 0.118)
    static let surface2 = Color(red: 0.165, green: 0.165, blue: 0.165)
    static let text = Color(red: 0.878, green: 0.878, blue: 0.878)
    static let textDim = Color(red: 0.533, green: 0.533, blue: 0.533)
    static let accent = Color(red: 0.310, green: 0.765, blue: 0.969)
    static let accentGlow = Color(red: 0.310, green: 0.765, blue: 0.969).opacity(0.3)
    static let chordBg = Color(red: 0.149, green: 0.196, blue: 0.220)
    static let sectionColor = Color(red: 1.0, green: 0.671, blue: 0.251)
    static let heartRed = Color(red: 0.898, green: 0.224, blue: 0.208)

    static let monoFont = Font.system(.body, design: .monospaced)
    static let monoSmall = Font.system(.caption, design: .monospaced).weight(.bold)
}

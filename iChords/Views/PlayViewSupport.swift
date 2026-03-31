import SwiftUI
import UIKit

// MARK: - Scroll tracking preference keys

struct ContentOriginKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct LinePositionKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct HeroHeightKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Stalled playback indicator

struct StalledIndicator: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 5, height: 5)
                    .opacity(phase == i ? 1.0 : 0.3)
                    .scaleEffect(phase == i ? 1.25 : 0.85)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: phase)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000)
                phase = (phase + 1) % 3
            }
        }
    }
}

// MARK: - Tab line renderer

struct TabBeatHighlight {
    let range: Range<Int>  // body-relative column range (after the first `|`)
    let color: Color
    let isActive: Bool     // true = bright/full; false = dim
}

struct TabLineView: View {
    let text: String
    var highlights: [TabBeatHighlight] = []
    var onColumnTap: ((Int) -> Void)? = nil  // called with absolute char column

    var body: some View {
        let font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let cw = ("0" as NSString).size(withAttributes: [.font: font]).width
        let ch = font.lineHeight
        let chars = Array(text)

        // Convert body-relative ranges to absolute column ranges once.
        let pipeOffset: Int = (chars.firstIndex(of: "|").map { $0 + 1 }) ?? 0
        let absHighlights: [(range: Range<Int>, color: Color, isActive: Bool)] = highlights.map { h in
            let lo = h.range.lowerBound + pipeOffset
            let hi = h.range.upperBound + pipeOffset
            return (lo..<hi, h.color, h.isActive)
        }

        GeometryReader { geo in
        Canvas { context, size in
            guard !chars.isEmpty, size.width > 0 else { return }

            let naturalWidth = CGFloat(chars.count) * cw
            if naturalWidth > size.width {
                context.concatenate(CGAffineTransform(scaleX: size.width / naturalWidth, y: 1))
            }

            // Draw highlight backgrounds (dim beats first, active beat on top).
            for h in absHighlights where !h.isActive && !h.range.isEmpty {
                let x = CGFloat(h.range.lowerBound) * cw
                let w = CGFloat(h.range.count) * cw
                context.fill(Path(CGRect(x: x, y: 0, width: w, height: size.height)),
                             with: .color(h.color.opacity(0.12)))
            }
            for h in absHighlights where h.isActive && !h.range.isEmpty {
                let x = CGFloat(h.range.lowerBound) * cw
                let w = CGFloat(h.range.count) * cw
                context.fill(Path(CGRect(x: x, y: 0, width: w, height: size.height)),
                             with: .color(h.color.opacity(0.30)))
            }

            let midY = size.height / 2
            var i = 0

            while i < chars.count {
                let x = CGFloat(i) * cw
                let c = chars[i]

                if c == "-" {
                    var j = i
                    while j < chars.count && chars[j] == "-" { j += 1 }
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: midY))
                    p.addLine(to: CGPoint(x: CGFloat(j) * cw, y: midY))
                    context.stroke(p, with: .color(Theme.textDim.opacity(0.5)), lineWidth: 0.75)
                    i = j

                } else if c == "|" {
                    var p = Path()
                    p.move(to: CGPoint(x: x + cw / 2, y: 0))
                    p.addLine(to: CGPoint(x: x + cw / 2, y: size.height))
                    context.stroke(p, with: .color(Theme.textDim.opacity(0.5)), lineWidth: 0.75)
                    i += 1

                } else if c.isNumber {
                    var j = i
                    while j < chars.count && chars[j].isNumber { j += 1 }
                    let numStr = String(chars[i..<j])
                    let numWidth = CGFloat(j - i) * cw

                    var p = Path()
                    p.move(to: CGPoint(x: x, y: midY))
                    p.addLine(to: CGPoint(x: x + numWidth, y: midY))
                    context.stroke(p, with: .color(Theme.textDim.opacity(0.2)), lineWidth: 0.75)

                    let numColor: Color = {
                        if let h = absHighlights.first(where: { $0.range.contains(i) }) {
                            return h.isActive ? h.color : h.color.opacity(0.6)
                        }
                        return Theme.text
                    }()
                    let label = context.resolve(
                        Text(numStr)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(numColor)
                    )
                    context.draw(label, at: CGPoint(x: x + numWidth / 2, y: midY), anchor: .center)
                    i = j

                } else {
                    let label = context.resolve(
                        Text(String(c))
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .foregroundColor(Theme.textDim)
                    )
                    context.draw(label, at: CGPoint(x: x + cw / 2, y: midY), anchor: .center)
                    i += 1
                }
            }
        }
        .onTapGesture(coordinateSpace: .local) { location in
            guard let onColumnTap else { return }
            let naturalWidth = CGFloat(chars.count) * cw
            let scale = naturalWidth > geo.size.width && geo.size.width > 0
                ? geo.size.width / naturalWidth : 1.0
            let col = Int(location.x / (cw * scale))
            onColumnTap(col)
        }
        } // GeometryReader
        .frame(maxWidth: .infinity, minHeight: ch, maxHeight: ch)
        .allowsHitTesting(onColumnTap != nil)
    }
}

// MARK: - Corner radius helper

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

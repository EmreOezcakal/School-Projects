import SwiftUI

/// Verdunkelt alles außerhalb des gewählten Bildformats.
struct CropMask: Shape {
    let crop: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRect(crop)
        return path
    }
}

/// Drittel-Raster innerhalb des Bildformats.
struct GridLines: Shape {
    let area: CGRect

    func path(in _: CGRect) -> Path {
        var path = Path()
        for i in 1...2 {
            let x = area.minX + area.width * CGFloat(i) / 3
            path.move(to: CGPoint(x: x, y: area.minY))
            path.addLine(to: CGPoint(x: x, y: area.maxY))
            let y = area.minY + area.height * CGFloat(i) / 3
            path.move(to: CGPoint(x: area.minX, y: y))
            path.addLine(to: CGPoint(x: area.maxX, y: y))
        }
        return path
    }
}

/// Horizontlinie: dreht sich gegen die Neigung des iPhones und wird gelb, wenn es gerade ist.
struct LevelLine: View {
    let roll: Double
    let isLevel: Bool
    let width: CGFloat

    var body: some View {
        HStack(spacing: width * 0.12) {
            Capsule().frame(width: width * 0.16, height: 2)
            Capsule().frame(width: width * 0.16, height: 2)
        }
        .foregroundStyle(isLevel ? Color.yellow : Color.white.opacity(0.85))
        .rotationEffect(.degrees(isLevel ? 0 : -roll))
        .animation(.easeOut(duration: 0.1), value: roll)
        .allowsHitTesting(false)
    }
}

/// Der gelbe Rahmen um das Motiv.
struct TargetBox: View {
    let rect: CGRect
    let aligned: Bool
    let label: String?

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(Color.yellow, lineWidth: aligned ? 4 : 2.5)
            .shadow(color: .yellow.opacity(aligned ? 0.8 : 0), radius: 8)
            .overlay(alignment: .topLeading) {
                if let label {
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.yellow, in: Capsule())
                        .offset(y: -24)
                }
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .animation(.linear(duration: 0.12), value: rect)
            .allowsHitTesting(false)
    }
}

struct ShutterButton: View {
    let highlighted: Bool
    let action: () -> Void
    @State private var pulse = false

    init(highlighted: Bool, action: @escaping () -> Void) {
        self.highlighted = highlighted
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(highlighted ? Color.yellow : Color.white, lineWidth: 5)
                    .frame(width: 82, height: 82)
                Circle()
                    .fill(Color.white)
                    .frame(width: 66, height: 66)
            }
            .shadow(color: .yellow.opacity(highlighted ? 0.9 : 0), radius: highlighted ? 18 : 0)
            .scaleEffect(pulse ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .onChange(of: highlighted) {
            withAnimation(highlighted ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default) {
                pulse = highlighted
            }
        }
        .accessibilityLabel("Auslösen")
    }
}

/// ✦ – Tippen scannt, lange drücken nutzt den jeweils anderen Scan-Modus.
struct ScanButton: View {
    let isScanning: Bool
    let tap: () -> Void
    let longPress: () -> Void

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.yellow.opacity(0.22))
                .frame(width: 62, height: 62)
            if isScanning {
                ProgressView().tint(.yellow)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.yellow)
            }
        }
        .contentShape(Circle())
        .onTapGesture { if !isScanning { tap() } }
        .onLongPressGesture(minimumDuration: 0.5) { if !isScanning { longPress() } }
        .accessibilityLabel("Motiv suchen")
    }
}

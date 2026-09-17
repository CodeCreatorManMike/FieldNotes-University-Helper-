import SwiftUI

/// The two-leaf UniFlow mark (mint -> sky gradient), matching dist/logo.svg's
/// path data so the web app and the island use the same silhouette.
struct LeafMark: View {
    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 120
            ZStack {
                leftLeaf(scale: s)
                    .fill(LinearGradient(colors: [Color(red: 0.435, green: 0.839, blue: 0.659), Color(red: 0.247, green: 0.714, blue: 0.788)], startPoint: .topLeading, endPoint: .bottomTrailing))
                rightLeaf(scale: s)
                    .fill(LinearGradient(colors: [Color(red: 0.435, green: 0.690, blue: 1.0), Color(red: 0.184, green: 0.373, blue: 0.839)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(rightLeaf(scale: s).stroke(Color.black.opacity(0.35), lineWidth: 1))
            }
        }
    }

    private func leftLeaf(scale s: CGFloat) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 16 * s, y: 18 * s))
            p.addCurve(to: CGPoint(x: 45 * s, y: 100 * s), control1: CGPoint(x: 6 * s, y: 45 * s), control2: CGPoint(x: 10 * s, y: 78 * s))
            p.addCurve(to: CGPoint(x: 60 * s, y: 46 * s), control1: CGPoint(x: 60 * s, y: 90 * s), control2: CGPoint(x: 66 * s, y: 68 * s))
            p.addCurve(to: CGPoint(x: 16 * s, y: 18 * s), control1: CGPoint(x: 54 * s, y: 24 * s), control2: CGPoint(x: 34 * s, y: 10 * s))
            p.closeSubpath()
        }
    }

    private func rightLeaf(scale s: CGFloat) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 103 * s, y: 24 * s))
            p.addCurve(to: CGPoint(x: 68 * s, y: 103 * s), control1: CGPoint(x: 112 * s, y: 50 * s), control2: CGPoint(x: 106 * s, y: 80 * s))
            p.addCurve(to: CGPoint(x: 58 * s, y: 50 * s), control1: CGPoint(x: 55 * s, y: 92 * s), control2: CGPoint(x: 51 * s, y: 70 * s))
            p.addCurve(to: CGPoint(x: 103 * s, y: 24 * s), control1: CGPoint(x: 66 * s, y: 28 * s), control2: CGPoint(x: 86 * s, y: 15 * s))
            p.closeSubpath()
        }
    }
}

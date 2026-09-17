import SwiftUI

/// A small animated ring for "today's plan" completion — springs to the new
/// fill whenever the data updates, and glows gently on a slow loop so the
/// corner isn't just a static number. Sits in the empty space next to the
/// stats row in the expanded panel.
struct RingProgressView: View {
    var progress: Double // 0...1
    var color: Color
    var size: CGFloat = 60

    @State private var animatedProgress: Double = 0
    @State private var glow = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 6)
            Circle()
                .trim(from: 0, to: max(animatedProgress, 0.003))
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(glow ? 0.75 : 0.25), radius: glow ? 7 : 2)
            Text("\(Int((progress * 100).rounded()))%")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.8)) { animatedProgress = progress }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { glow = true }
        }
        .onChange(of: progress) { new in
            withAnimation(.spring(response: 0.9, dampingFraction: 0.8)) { animatedProgress = new }
        }
    }
}

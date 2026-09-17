import SwiftUI

/// The always-visible glanceable anchor: a small capsule docked at the
/// screen edge, colored by urgency, that the expanded panel grows out of.
struct PillView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let c = state.urgency.color
        HStack(spacing: 5) {
            Circle()
                .fill(Color(red: c.0, green: c.1, blue: c.2))
                .frame(width: 7, height: 7)
            Text("f.").font(.system(size: 11, weight: .bold, design: .serif)).italic().foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contextMenu { menuItems }
    }

    @ViewBuilder private var menuItems: some View {
        Button("Refresh now") { Commands.refresh() }
        Button(LaunchAtLogin.isEnabled ? "Disable launch at login" : "Launch at login") { Commands.toggleLogin() }
        Divider()
        Button("Quit Fieldnotes Island") { Commands.quit() }
    }
}

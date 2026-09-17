import SwiftUI

/// The always-visible idle indicator: a ring that fills as today's plan
/// fills (planUsedMinutes / dailyTarget), colored by urgency, with a black
/// disc and white "U" mark at its center for contrast against anything
/// behind it. Hover shows a native tooltip with the top task; hovering the
/// edge/pill expands the full panel (handled by EdgeWatcher, not here).
struct PillView: View {
    @EnvironmentObject var state: AppState

    private var progress: Double {
        guard let n = state.next, n.dailyTarget > 0 else { return 0 }
        return min(1, max(0, Double(n.planUsedMinutes) / Double(n.dailyTarget)))
    }

    var body: some View {
        let c = state.urgency.color
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.18), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(progress, 0.02))
                .stroke(Color(red: c.0, green: c.1, blue: c.2), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(Color.black)
                .frame(width: 38, height: 38)
            Text("U")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 54, height: 54)
        .padding(4)
        .contentShape(Circle())
        .help(tooltip)
        .onTapGesture {
            if let id = state.next?.top?.id { FieldnotesAPI.openRoute("topic/\(id)") }
            else { FieldnotesAPI.openRoute("home") }
        }
        .contextMenu { menuItems }
    }

    private var tooltip: String {
        guard let top = state.next?.top else { return state.isReachable ? "Fieldnotes — nothing queued" : "Fieldnotes — server unreachable" }
        return "\(top.title) · \(top.module)\n\(top.reason.first ?? "")"
    }

    @ViewBuilder private var menuItems: some View {
        Button("Refresh now") { Commands.refresh() }
        Button(LaunchAtLogin.isEnabled ? "Disable launch at login" : "Launch at login") { Commands.toggleLogin() }
        Divider()
        Button("Quit Fieldnotes Island") { Commands.quit() }
    }
}

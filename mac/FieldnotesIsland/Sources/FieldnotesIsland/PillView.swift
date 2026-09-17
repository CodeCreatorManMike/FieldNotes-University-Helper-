import SwiftUI

/// The always-visible glanceable anchor: solid white, black symbol and
/// text, docked at the screen edge, showing the single most important
/// thing to do right now so it never needs a hover to be useful. The full
/// panel still grows out from here on hover for everything else.
struct PillView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let c = state.urgency.color
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.black)
                    .frame(width: 24, height: 24)
                Text("f.").font(.system(size: 13, weight: .bold, design: .serif)).italic().foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                if let top = state.next?.top {
                    Text(top.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                    Text(top.module)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.black.opacity(0.5))
                } else if state.isReachable {
                    Text("All clear").font(.system(size: 12, weight: .semibold)).foregroundStyle(.black)
                    Text("nothing queued").font(.system(size: 9.5)).foregroundStyle(.black.opacity(0.5))
                } else {
                    Text("Fieldnotes").font(.system(size: 12, weight: .semibold)).foregroundStyle(.black)
                    Text("server unreachable").font(.system(size: 9.5)).foregroundStyle(.red.opacity(0.75))
                }
            }
            Spacer(minLength: 0)
            Circle()
                .fill(Color(red: c.0, green: c.1, blue: c.2))
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minWidth: 210, maxWidth: 260)
        .contentShape(Rectangle())
        .onTapGesture {
            if let id = state.next?.top?.id { FieldnotesAPI.openRoute("topic/\(id)") }
            else { FieldnotesAPI.openRoute("home") }
        }
        .contextMenu { menuItems }
    }

    @ViewBuilder private var menuItems: some View {
        Button("Refresh now") { Commands.refresh() }
        Button(LaunchAtLogin.isEnabled ? "Disable launch at login" : "Launch at login") { Commands.toggleLogin() }
        Divider()
        Button("Quit Fieldnotes Island") { Commands.quit() }
    }
}

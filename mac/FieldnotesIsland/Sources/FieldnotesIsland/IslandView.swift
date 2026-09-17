import SwiftUI

private struct NavItem: Identifiable {
    let id: String
    let label: String
    let icon: String
}

private let navItems: [NavItem] = [
    NavItem(id: "home", label: "Today", icon: "sun.max.fill"),
    NavItem(id: "modules", label: "Modules", icon: "square.grid.2x2.fill"),
    NavItem(id: "week", label: "Week", icon: "calendar"),
    NavItem(id: "tasks", label: "Tasks", icon: "checklist"),
    NavItem(id: "journal", label: "Journal", icon: "book.closed.fill"),
    NavItem(id: "settings", label: "Settings", icon: "gearshape.fill"),
]

struct IslandView: View {
    @EnvironmentObject var state: AppState
    @State private var hoveredNav: String?
    @State private var upNextHovered = false
    @State private var quickTask = ""
    @FocusState private var quickTaskFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            upNext
            progressStrip
            quickAdd
            Divider().overlay(Color.white.opacity(0.14))
            VStack(spacing: 3) { ForEach(navItems) { navRow($0) } }
            Divider().overlay(Color.white.opacity(0.14))
            brand
        }
        .padding(18)
        .frame(width: 300)
        .background(Color.clear)
        .contextMenu {
            Button("Refresh now") { Commands.refresh() }
            Button(LaunchAtLogin.isEnabled ? "Disable launch at login" : "Launch at login") { Commands.toggleLogin() }
            Divider()
            Button("Quit Fieldnotes Island") { Commands.quit() }
        }
    }

    private var brand: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
                Text("f.").font(.system(size: 12, weight: .bold, design: .serif)).italic().foregroundStyle(.black)
            }
            Text("fieldnotes").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
            Spacer()
            Circle().fill(state.isReachable ? Color.green : Color.red).frame(width: 6, height: 6)
        }
    }

    private func navRow(_ item: NavItem) -> some View {
        Button {
            FieldnotesAPI.openRoute(item.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.icon).font(.system(size: 14)).frame(width: 18)
                Text(item.label).font(.system(size: 14.5, weight: .medium))
                Spacer()
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hoveredNav == item.id ? Color.white.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.95))
        .onHover { hovering in hoveredNav = hovering ? item.id : (hoveredNav == item.id ? nil : hoveredNav) }
    }

    @ViewBuilder
    private var upNext: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MOST IMPORTANT RIGHT NOW").font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(.white.opacity(0.5))
            if let top = state.next?.top {
                Button { FieldnotesAPI.openRoute("topic/\(top.id)") } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(top.module).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color(red: 0.71, green: 0.95, blue: 0.49))
                        Text(top.title).font(.system(size: 18, weight: .bold)).foregroundStyle(.white).lineLimit(2)
                        Text(top.reason.first ?? "Ready to start").font(.system(size: 12)).foregroundStyle(.white.opacity(0.65)).lineLimit(upNextHovered ? 4 : 1)
                        if upNextHovered, top.reason.count > 1 {
                            ForEach(top.reason.dropFirst(), id: \.self) { r in
                                Text("· " + r).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .onHover { upNextHovered = $0 }
                HStack(spacing: 8) {
                    actionButton("Snooze 2d", "moon.zzz.fill") { state.snoozeTop() }
                    actionButton("Know it", "checkmark.circle.fill") { state.markTopKnown() }
                    if state.isBusy { ProgressView().controlSize(.mini).tint(.white) }
                }
            } else if state.isReachable {
                Text("Nothing queued — nice work.").font(.system(size: 13)).foregroundStyle(.white.opacity(0.65))
            } else {
                Text("Can't reach the local server.").font(.system(size: 13)).foregroundStyle(.orange.opacity(0.85))
            }
        }
    }

    @ViewBuilder
    private var progressStrip: some View {
        if let n = state.next {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 18) {
                    stat("\(n.coverage.done)/\(n.coverage.total)", "covered")
                    stat("\(n.streak)", "day streak")
                    stat("\(n.openTasks)", "open")
                }
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Today's plan").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                        Spacer()
                        Text("\(n.planUsedMinutes)/\(n.dailyTarget) min").font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.14)).frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(red: 0.71, green: 0.95, blue: 0.49))
                                .frame(width: geo.size.width * min(1, n.dailyTarget > 0 ? Double(n.planUsedMinutes) / Double(n.dailyTarget) : 0), height: 6)
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
    }

    private func actionButton(_ label: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9))
                Text(label).font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.75))
        .disabled(state.isBusy)
    }

    @ViewBuilder
    private var quickAdd: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle.fill").font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
            TextField("Quick add a task…", text: $quickTask)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(.white)
                .focused($quickTaskFocused)
                .onSubmit {
                    state.addTask(quickTask)
                    quickTask = ""
                }
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
            Text(label).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
        }
    }
}

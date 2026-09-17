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

private let TAGLINES = [
    "Focus builds the future.",
    "Small steps, real progress.",
    "One task at a time.",
    "Consistency beats intensity.",
    "Show up. That's the whole plan.",
]

private let mint = Color(red: 0.435, green: 0.827, blue: 0.690)

struct IslandView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var focus = FocusTimer()
    @State private var hoveredNav: String?
    @State private var nextUpHovered = false
    @State private var quickTask = ""
    @FocusState private var quickTaskFocused: Bool
    private let tagline = TAGLINES.randomElement() ?? TAGLINES[0]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            clockBlock
            nextUp
            focusMode
            statsRow
            quickAdd
            Divider().overlay(Color.white.opacity(0.14))
            VStack(spacing: 3) { ForEach(navItems) { navRow($0) } }
        }
        .padding(18)
        .frame(width: 300)
        .background(Color.clear)
        .contextMenu {
            Button("Refresh now") { Commands.refresh() }
            Button(LaunchAtLogin.isEnabled ? "Disable launch at login" : "Launch at login") { Commands.toggleLogin() }
            Divider()
            Button("Quit UniFlow") { Commands.quit() }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            LeafMark().frame(width: 20, height: 20)
            Text("UniFlow").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(state.isReachable ? mint : Color.red).frame(width: 6, height: 6)
                Text(state.isReachable ? "Stay on track" : "Reconnecting").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var clockBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(context.date, style: .time).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.white)
            }
            Text(tagline).font(.system(size: 12.5)).italic().foregroundStyle(.white.opacity(0.55))
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
    private var nextUp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NEXT UP").font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(.white.opacity(0.5))
            if let top = state.next?.top {
                Button { FieldnotesAPI.openRoute("topic/\(top.id)") } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "flag.fill").font(.system(size: 13)).foregroundStyle(mint).frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(top.title).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                            Text(top.reason.first ?? top.module).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.55)).lineLimit(nextUpHovered ? 3 : 1)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.35))
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .onHover { nextUpHovered = $0 }
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

    private var focusMode: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FOCUS MODE").font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(.white.opacity(0.5))
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: max(focus.progress, 0.001))
                        .stroke(mint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "bolt.fill").font(.system(size: 13)).foregroundStyle(mint)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Deep Work").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    Text(focus.isRunning ? "Distractions off. You've got this." : "25 minutes, uninterrupted.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(focus.label).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.85))
                Button { focus.toggle() } label: {
                    Image(systemName: focus.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.black)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.white))
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
        }
    }

    private var statsRow: some View {
        HStack(spacing: 14) {
            if let n = state.next {
                stat("\(n.coverage.done)/\(n.coverage.total)", "covered")
                stat("\(n.streak)", "streak")
                stat("\(n.openTasks)", "open")
                Spacer(minLength: 0)
                RingProgressView(progress: n.dailyTarget > 0 ? Double(n.planUsedMinutes) / Double(n.dailyTarget) : 0, color: mint, size: 40)
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
            Text(value).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            Text(label).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.5))
        }
    }
}

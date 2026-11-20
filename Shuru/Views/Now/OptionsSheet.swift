import SwiftUI

struct OptionsSheet: View {
    enum Action { case smaller, timer, notNow, pickOne, done }

    @EnvironmentObject var store: AppStore
    let item: NowItem
    let holdMode: Bool
    let run: (Action) -> Void

    var body: some View {
        let smaller = store.isSmaller(item)
        let timing = store.timer?.itemID == item.id
        let pushes = store.pushes(item)
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Right now")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(store.displayTitle(item))
                        .font(.system(size: 17, weight: .semibold))
                    if pushes >= 2 {
                        Text("You’ve pushed this one \(pushes) times. Smaller might help.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.accent(store.settings.palette))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)

                row(icon: "arrow.down.right.and.arrow.up.left",
                    title: smaller ? "Back to the full task" : "Make it smaller",
                    detail: smaller ? item.step.title : item.step.smallerOrDefault,
                    action: .smaller)
                row(icon: "timer",
                    title: timing ? "Stop the timer" : "Start a 5-minute timer",
                    detail: timing ? "Back to just the task" : "Just begin. Stop whenever.",
                    action: .timer)
                row(icon: "moon", title: "Not now", detail: "Move it later in the line", action: .notNow)
                row(icon: "shuffle", title: "Pick one for me", detail: "Skip the deciding", action: .pickOne)
                if holdMode {
                    row(icon: "checkmark", title: "Mark it done", detail: "Skip the hold this time", action: .done)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 22)
        }
    }

    private func row(icon: String, title: String, detail: String, action: Action) -> some View {
        Button {
            run(action)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 42, height: 42)
                    .background(Theme.card2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Text(detail).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

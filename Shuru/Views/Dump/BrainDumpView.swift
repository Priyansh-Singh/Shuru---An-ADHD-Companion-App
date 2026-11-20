import SwiftUI

/// Get thoughts out of your head fast. Sort them later.
struct BrainDumpView: View {
    @EnvironmentObject var store: AppStore
    @State private var draft = ""
    @State private var showSorted = false
    @State private var toast: String?
    @FocusState private var focused: Bool

    private var accent: Color { Theme.accent(store.settings.palette) }

    var body: some View {
        let open = store.data.dump.filter { $0.sortedAt == nil }
        let sorted = store.data.dump.filter { $0.sortedAt != nil }
        ZStack(alignment: .bottom) {
            PageScroll {
                ScreenHeader(title: "Brain dump", subtitle: "Get it out of your head. Sort it later.")

                Card {
                    InlineAdd(text: $draft, placeholder: "What’s on your mind?", focused: $focused, accent: accent) {
                        store.addThought(draft)
                        draft = ""
                        focused = true
                    }
                    ForEach(open) { item in
                        HStack(spacing: 12) {
                            Circle().fill(Theme.checkbox).frame(width: 6, height: 6).frame(width: 44)
                            Text(item.text).font(.system(size: 16))
                            Spacer(minLength: 8)
                            Button("Today") {
                                store.moveThoughtToToday(item.id)
                                show("Added to today")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(accent)
                            .frame(minWidth: 44, minHeight: 44)
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Add “\(item.text)” to today")
                        }
                        .padding(.leading, 2)
                        .padding(.trailing, 12)
                        .frame(minHeight: 48)
                        .contextMenu {
                            Button("Add to today", systemImage: "calendar") {
                                store.moveThoughtToToday(item.id)
                                show("Added to today")
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) { store.deleteThought(item.id) }
                        }
                    }
                    if open.isEmpty {
                        Text("Nothing here. Anything nagging at you?")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                }

                if !sorted.isEmpty {
                    Card {
                        Button {
                            withAnimation { showSorted.toggle() }
                        } label: {
                            HStack {
                                Text("Sorted").font(.system(size: 16, weight: .semibold))
                                Text("\(sorted.count)").font(.system(size: 14)).foregroundStyle(.secondary)
                                Spacer()
                                Image(systemName: showSorted ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if showSorted {
                            ForEach(sorted) { item in
                                HStack(spacing: 12) {
                                    CheckCircle(done: true, tint: Theme.checkbox).frame(width: 44)
                                    Text(item.text).font(.system(size: 16)).strikethrough().foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.leading, 2)
                                .frame(minHeight: 48)
                                .contextMenu {
                                    Button("Delete", systemImage: "trash", role: .destructive) { store.deleteThought(item.id) }
                                }
                            }
                        }
                    }
                }
            }
            if let toast {
                Toast(text: toast).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: toast)
    }

    private func show(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if toast == text { toast = nil }
        }
    }
}

import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        let pages = store.visiblePages
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()

            TabView(selection: $store.page) {
                ForEach(pages) { p in
                    page(p)
                        .tag(p)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(.container, edges: .bottom)

            if store.settings.showDots && store.pauseStage == nil {
                PageDots(pages: pages, current: store.page) { p in
                    withAnimation(.easeOut(duration: 0.3)) { store.page = p }
                }
            }
        }
        .onChange(of: pages) { _, newPages in
            if !newPages.contains(store.page) { store.page = .now }
        }
    }

    @ViewBuilder
    private func page(_ p: Page) -> some View {
        switch p {
        case .settings: SettingsView()
        case .dump: BrainDumpView()
        case .hours: HoursView()
        case .now: NowView()
        case .calendar: CalendarView()
        case .routines: RoutinesView()
        case .week: WeekView()
        }
    }
}

struct PageDots: View {
    let pages: [Page]
    let current: Page
    let go: (Page) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(pages) { p in
                Button {
                    go(p)
                } label: {
                    Capsule()
                        .fill(p == current ? Color.primary : Color.primary.opacity(0.28))
                        .frame(width: p == current ? 18 : 6, height: 6)
                        .frame(width: 30, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Go to " + p.label)
                .accessibilityAddTraits(p == current ? .isSelected : [])
            }
        }
        .animation(.easeOut(duration: 0.25), value: current)
        .padding(.top, 28)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Theme.background.opacity(0), Theme.background], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.6))
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        )
    }
}

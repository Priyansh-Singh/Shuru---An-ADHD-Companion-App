import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        let pages = store.visiblePages
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()

            Pager(pages: pages) { p in page(p) }
                .ignoresSafeArea(.container, edges: .bottom)

            if store.settings.showDots && store.pauseStage == nil && !(store.nowPanelOpen && store.page == .now) {
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

enum SwipeAxis { case horizontal, vertical }

/// Left/right paging that commits to one direction as soon as a swipe starts,
/// so a quick swipe down on Now can never turn into a page change.
struct Pager<Content: View>: View {
    @EnvironmentObject var store: AppStore
    let pages: [Page]
    @ViewBuilder var content: (Page) -> Content

    @State private var dragX: CGFloat = 0
    @State private var axis: SwipeAxis?

    private let spring = Animation.spring(response: 0.38, dampingFraction: 0.9)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let index = CGFloat(pages.firstIndex(of: store.page) ?? 0)
            HStack(spacing: 0) {
                ForEach(pages) { p in
                    content(p)
                        .frame(width: w, height: geo.size.height)
                        .accessibilityHidden(p != store.page)
                }
            }
            .frame(width: w, height: geo.size.height, alignment: .leading)
            .offset(x: -index * w + dragX)
            .animation(spring, value: store.page)
            .contentShape(Rectangle())
            .simultaneousGesture(drag(width: w))
        }
        .clipped()
    }

    private func drag(width w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in
                let dx = v.translation.width, dy = v.translation.height
                if axis == nil {
                    axis = abs(dx) > abs(dy) * 1.15 ? .horizontal : .vertical
                    store.swipeAxis = axis
                }
                guard axis == .horizontal, store.pauseStage == nil else { return }
                let i = pages.firstIndex(of: store.page) ?? 0
                let atEdge = (i == 0 && dx > 0) || (i == pages.count - 1 && dx < 0)
                dragX = atEdge ? dx * 0.3 : dx
            }
            .onEnded { v in
                let wasHorizontal = axis == .horizontal
                axis = nil
                DispatchQueue.main.async { store.swipeAxis = nil }
                guard wasHorizontal, store.pauseStage == nil else {
                    withAnimation(spring) { dragX = 0 }
                    return
                }
                let i = pages.firstIndex(of: store.page) ?? 0
                let moved = v.translation.width
                let flung = v.predictedEndTranslation.width
                var next = i
                if (moved < -w * 0.25 || flung < -w * 0.5) && i < pages.count - 1 { next = i + 1 }
                if (moved > w * 0.25 || flung > w * 0.5) && i > 0 { next = i - 1 }
                withAnimation(spring) {
                    store.page = pages[next]
                    dragX = 0
                }
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

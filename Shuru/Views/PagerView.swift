import SwiftUI
import UIKit

/// Which pages are at least partly on screen. Only Now listens, and it only changes when that set changes.
final class PagerVisibility: ObservableObject {
    static let shared = PagerVisibility()
    @Published private(set) var visible: Set<Page> = [.now]

    func set(_ pages: Set<Page>) {
        if pages != visible { visible = pages }
    }
}

/// Left/right paging on iOS's own scroll view, so it's smooth and cancels taps like any iPhone app.
/// The scroll view only starts when a swipe begins sideways; swipes that start vertical are left
/// to the page (pulling the day flow on Now).
struct PagerView: UIViewControllerRepresentable {
    let pages: [Page]
    @Binding var selection: Page
    let store: AppStore
    let palette: Palette
    let content: (Page) -> AnyView

    func makeUIViewController(context: Context) -> PagerController {
        let vc = PagerController()
        vc.makePage = { p in
            AnyView(content(p).environmentObject(store).tint(Theme.accent(palette)))
        }
        vc.onPageChange = { p in if selection != p { selection = p } }
        vc.update(pages: pages, selection: selection, palette: palette, animated: false)
        return vc
    }

    func updateUIViewController(_ vc: PagerController, context: Context) {
        vc.makePage = { p in
            AnyView(content(p).environmentObject(store).tint(Theme.accent(palette)))
        }
        vc.onPageChange = { p in if selection != p { selection = p } }
        vc.update(pages: pages, selection: selection, palette: palette, animated: true)
    }
}

final class DirectionalScrollView: UIScrollView {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer {
            let v = panGestureRecognizer.velocity(in: self)
            let t = panGestureRecognizer.translation(in: self)
            let x = abs(v.x) + abs(t.x) * 10
            let y = abs(v.y) + abs(t.y) * 10
            // Mostly vertical: not a page swipe.
            if x <= y * 1.15 { return false }
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}

final class PagerController: UIViewController, UIScrollViewDelegate {
    private let scroll = DirectionalScrollView()
    private var hosts: [Page: UIHostingController<AnyView>] = [:]
    private var pages: [Page] = []
    private var current: Page = .now
    private var palette: Palette?
    private var isUserScrolling = false

    var makePage: ((Page) -> AnyView)?
    var onPageChange: ((Page) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        scroll.isPagingEnabled = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.alwaysBounceVertical = false
        scroll.isDirectionalLockEnabled = true
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.delaysContentTouches = false
        scroll.canCancelContentTouches = true
        scroll.decelerationRate = .fast
        scroll.backgroundColor = .clear
        scroll.delegate = self
        view.addSubview(scroll)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPages()
    }

    func update(pages newPages: [Page], selection: Page, palette newPalette: Palette, animated: Bool) {
        loadViewIfNeeded()
        let paletteChanged = palette != newPalette
        palette = newPalette

        if newPages != pages {
            for (p, host) in hosts where !newPages.contains(p) {
                host.willMove(toParent: nil)
                host.view.removeFromSuperview()
                host.removeFromParent()
                hosts[p] = nil
            }
            for p in newPages where hosts[p] == nil {
                guard let page = makePage?(p) else { continue }
                let host = UIHostingController(rootView: page)
                host.view.backgroundColor = .clear
                addChild(host)
                scroll.addSubview(host.view)
                host.didMove(toParent: self)
                hosts[p] = host
            }
            pages = newPages
            layoutPages()
        } else if paletteChanged {
            for (p, host) in hosts {
                if let page = makePage?(p) { host.rootView = page }
            }
        }

        let target = newPages.contains(selection) ? selection : (newPages.contains(.now) ? .now : newPages.first ?? .now)
        if target != current {
            current = target
            scrollTo(target, animated: animated && view.window != nil)
        }
        updateAccessibility()
    }

    private func reportVisible() {
        let w = scroll.bounds.width
        guard w > 0 else { return }
        let left = scroll.contentOffset.x, right = left + w
        var on: Set<Page> = []
        for (i, p) in pages.enumerated() {
            let x0 = CGFloat(i) * w, x1 = x0 + w
            if x1 > left + 1 && x0 < right - 1 { on.insert(p) }
        }
        PagerVisibility.shared.set(on)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        reportVisible()
    }

    private func layoutPages() {
        scroll.frame = view.bounds
        let w = view.bounds.width, h = view.bounds.height
        guard w > 0 else { return }
        for (i, p) in pages.enumerated() {
            hosts[p]?.view.frame = CGRect(x: CGFloat(i) * w, y: 0, width: w, height: h)
        }
        scroll.contentSize = CGSize(width: w * CGFloat(pages.count), height: h)
        if !isUserScrolling, let i = pages.firstIndex(of: current) {
            scroll.contentOffset = CGPoint(x: CGFloat(i) * w, y: 0)
        }
        reportVisible()
    }

    private func scrollTo(_ p: Page, animated: Bool) {
        guard let i = pages.firstIndex(of: p) else { return }
        let x = CGFloat(i) * scroll.bounds.width
        if abs(scroll.contentOffset.x - x) > 0.5 {
            scroll.setContentOffset(CGPoint(x: x, y: 0), animated: animated)
        }
    }

    private func settle() {
        isUserScrolling = false
        let w = scroll.bounds.width
        guard w > 0, !pages.isEmpty else { return }
        let i = min(max(Int((scroll.contentOffset.x / w).rounded()), 0), pages.count - 1)
        let p = pages[i]
        if p != current {
            current = p
            onPageChange?(p)
            updateAccessibility()
        }
    }

    private func updateAccessibility() {
        for (p, host) in hosts {
            host.view.accessibilityElementsHidden = p != current
        }
    }

    // MARK: UIScrollViewDelegate

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        isUserScrolling = true
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { settle() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        settle()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        settle()
    }
}

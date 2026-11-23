import AppKit
import Combine
import SwiftUI

/// SwiftUI content that also drags its window. NSHostingView swallows the
/// mouse-down, so `isMovableByWindowBackground` never starts a drag; this
/// moves the window itself once the mouse travels more than a click's worth.
final class DragHostingView<Content: View>: NSHostingView<Content> {
    private var dragStartMouse: NSPoint?
    private var dragStartOrigin: NSPoint?
    private var isDragging = false
    /// Called once when a drag finishes, so the position is saved only for real user moves.
    var onDragEnd: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = window?.frame.origin
        isDragging = false
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartMouse, let origin = dragStartOrigin, let window else {
            super.mouseDragged(with: event)
            return
        }
        let now = NSEvent.mouseLocation
        let dx = now.x - start.x, dy = now.y - start.y
        if isDragging || hypot(dx, dy) > 3 {
            isDragging = true
            window.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
        } else {
            super.mouseDragged(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let wasDragging = isDragging
        isDragging = false
        dragStartMouse = nil
        dragStartOrigin = nil
        // After a drag, don't let the release land as a click on a control.
        if wasDragging { onDragEnd?() } else { super.mouseUp(with: event) }
    }
}

/// The pinned desktop widget: a borderless, non-activating, draggable panel.
///
/// - Always on top ON: floating level, on all Spaces. OFF: normal window level
///   (sits behind the active app's windows, like a desktop widget).
/// - Material follows the system "Icon & widget style": Default/Dark use an
///   opaque system material, Clear uses clear glass, Tinted uses glass tinted
///   by the system tint (the tint overlay is drawn by PinnedWidgetView).
/// - Position is remembered per display; layout and Always on top persist.
@MainActor
final class PinnedWidgetController: NSObject, NSWindowDelegate {
    private let store: UsageStore
    private let styleStore: WidgetStyleStore
    private let preferences: Preferences
    private let onClose: () -> Void
    /// The signed-out "Sign in" plate was clicked.
    var onSignIn: () -> Void = {}
    /// Screen frame of Cap's menu bar item; the first-run position hangs beneath it.
    private let statusItemFrame: () -> NSRect?

    private var panel: NSPanel?
    private var hosting: DragHostingView<PinnedWidgetView>?
    private var materialView: NSView?
    private var currentMaterial: PinnedTheme.Material?
    private var subscriptions = Set<AnyCancellable>()
    private var refitTimer: Timer?
    private var isPlacing = false

    init(store: UsageStore, styleStore: WidgetStyleStore, preferences: Preferences, statusItemFrame: @escaping () -> NSRect?, onClose: @escaping () -> Void) {
        self.statusItemFrame = statusItemFrame
        self.store = store
        self.styleStore = styleStore
        self.preferences = preferences
        self.onClose = onClose
    }

    // MARK: Show / hide

    func show() {
        if panel != nil { refit(); return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 170, height: 170),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // No system shadow: macOS derives it from the window's rectangular alpha,
        // which shows as a square box under the rounded glass corners.
        panel.hasShadow = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = false // dragging is handled by DragHostingView
        panel.hidesOnDeactivate = false
        panel.delegate = self
        self.panel = panel

        applyLevel()
        installMaterial(for: materialKind(styleStore.style))
        panel.appearance = styleStore.style.appearance

        placeInitially()
        panel.orderFrontRegardless()

        preferences.$alwaysOnTop
            .sink { [weak self] _ in Task { @MainActor in self?.applyLevel() } }
            .store(in: &subscriptions)
        preferences.$pinnedLayout
            .dropFirst()
            .sink { [weak self] _ in Task { @MainActor in self?.layoutChanged() } }
            .store(in: &subscriptions)
        styleStore.$style
            .dropFirst()
            .sink { [weak self] style in Task { @MainActor in self?.styleChanged(style) } }
            .store(in: &subscriptions)

        // Width/height can change with the data (e.g. "100%" in the strip).
        refitTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refit() }
        }
    }

    func hide() {
        refitTimer?.invalidate()
        refitTimer = nil
        subscriptions.removeAll()
        panel?.orderOut(nil)
        panel?.delegate = nil
        panel = nil
        hosting = nil
        materialView = nil
        currentMaterial = nil
    }

    // MARK: Level

    private func applyLevel() {
        guard let panel else { return }
        if preferences.alwaysOnTop {
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        } else {
            panel.level = .normal
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        }
    }

    // MARK: Material

    private func materialKind(_ style: WidgetStyle) -> PinnedTheme.Material {
        switch style.kind {
        case .regular, .dark: return .system
        case .clear: return .glassClear
        case .tinted: return .glassRegular
        }
    }

    private func makeHosting() -> DragHostingView<PinnedWidgetView> {
        let view = DragHostingView(rootView: PinnedWidgetView(
            store: store, styleStore: styleStore, preferences: preferences,
            onClose: { [weak self] in self?.onClose() },
            onSignIn: { [weak self] in self?.onSignIn() }
        ))
        view.onDragEnd = { [weak self] in self?.savePosition() }
        return view
    }

    private func installMaterial(for kind: PinnedTheme.Material) {
        guard let panel else { return }
        let hosting = makeHosting()
        let radius = PinnedWidgetView.cornerRadius(for: preferences.pinnedLayout)

        if #available(macOS 26.0, *), kind != .system {
            let glass = NSGlassEffectView()
            glass.style = kind == .glassClear ? .clear : .regular
            glass.cornerRadius = radius
            glass.contentView = hosting
            panel.contentView = glass
            materialView = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = kind == .system ? .popover : .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = radius
            effect.layer?.cornerCurve = .continuous
            effect.layer?.masksToBounds = true
            hosting.frame = effect.bounds
            hosting.autoresizingMask = [.width, .height]
            effect.addSubview(hosting)
            panel.contentView = effect
            materialView = effect
        }
        self.hosting = hosting
        currentMaterial = kind
    }

    private func styleChanged(_ style: WidgetStyle) {
        guard let panel else { return }
        panel.appearance = style.appearance
        let kind = materialKind(style)
        if kind != currentMaterial {
            installMaterial(for: kind)
            refit()
        }
    }

    private func layoutChanged() {
        let radius = PinnedWidgetView.cornerRadius(for: preferences.pinnedLayout)
        if #available(macOS 26.0, *), let glass = materialView as? NSGlassEffectView {
            glass.cornerRadius = radius
        } else {
            materialView?.layer?.cornerRadius = radius
        }
        // Let SwiftUI lay out the new layout, then resize the panel to fit.
        DispatchQueue.main.async { [weak self] in self?.refit() }
    }

    // MARK: Size and position

    /// Resize to the content, keeping the top-left corner where it is.
    private func refit() {
        guard let panel, let hosting else { return }
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        guard size.width > 1, size.height > 1 else { return }
        let old = panel.frame
        if abs(old.width - size.width) < 0.5, abs(old.height - size.height) < 0.5 { return }
        isPlacing = true
        panel.setFrame(NSRect(x: old.minX, y: old.maxY - size.height, width: size.width, height: size.height), display: true)
        isPlacing = false
        panel.invalidateShadow()
    }

    private func displayID(for screen: NSScreen?) -> String {
        let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return number.map { "\($0)" } ?? "main"
    }

    private func placeInitially() {
        guard let panel, let hosting else { return }
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let screen = NSScreen.main ?? NSScreen.screens.first
        let id = displayID(for: screen)

        var topLeft: CGPoint
        if let saved = preferences.pinnedTopLeft(display: id),
           NSScreen.screens.contains(where: { $0.frame.contains(CGPoint(x: saved.x + 20, y: saved.y - 20)) }) {
            topLeft = saved
        } else if let item = statusItemFrame(), let visible = screen?.visibleFrame {
            // First run: just beneath the menu bar item, left edges aligned.
            let x = min(item.minX, visible.maxX - size.width - 12)
            topLeft = CGPoint(x: max(visible.minX + 12, x), y: min(item.minY, visible.maxY) - 8)
        } else if let visible = screen?.visibleFrame {
            topLeft = CGPoint(x: visible.maxX - size.width - 12, y: visible.maxY - 12)
        } else {
            topLeft = CGPoint(x: 100, y: 800)
        }
        isPlacing = true
        panel.setFrame(NSRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height), display: true)
        isPlacing = false
    }

    private func savePosition() {
        guard let panel else { return }
        let topLeft = CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
        preferences.setPinnedTopLeft(topLeft, display: displayID(for: panel.screen))
    }

}

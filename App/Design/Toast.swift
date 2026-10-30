import SwiftUI
import UIKit
import VelovCore

struct ToastBanner: View {
    let toast: Toast
    let close: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: Space.label) {
            VStack(alignment: .leading, spacing: 0) {
                Text(toast.message).typo(.body(.base)).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: Layout.hit, alignment: .leading)
                if toast.action == .openSettings {
                    TextLink(title: "Ouvrir Réglages") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        close()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            IconButton(icon: .x, label: "Fermer", action: close)
        }
        .padding(.leading, Space.card).padding(.trailing, Space.pair).padding(.vertical, Space.pair)
        .ringed(RoundedRectangle(cornerRadius: Concentric.fallback, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

private struct ToastLayer: View {
    let report: (CGRect) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                if let toast = model.toasts.current {
                    ToastBanner(toast: toast) { model.dismissToast(toast.id) }
                        .id(toast.id)
                        .transition(still ? .opacity : .move(edge: .top).combined(with: .opacity))
                        .task(id: toast.id) {
                            AccessibilityNotification.Announcement(toast.message).post()
                            guard model.snapshot == nil else { return }
                            try? await Task.sleep(for: .seconds(5))
                            model.dismissToast(toast.id)
                        }
                }
            }
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: report)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Concentric.inset)
        .padding(.top, Space.label)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(still ? Motion.standard : Motion.panel, value: model.toasts.current?.id)
        .preferredColorScheme(.light)
    }
}

private final class PassthroughWindow: UIWindow {
    var active = CGRect.zero

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        active.contains(point) ? super.hitTest(point, with: event) : nil
    }
}

private struct ToastWindowAnchor: UIViewRepresentable {
    let model: AppModel

    func makeUIView(context: Context) -> Anchor { Anchor(model: model) }

    func updateUIView(_ anchor: Anchor, context: Context) {}

    final class Anchor: UIView {
        private let model: AppModel
        private var overlay: PassthroughWindow?

        init(model: AppModel) {
            self.model = model
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard overlay == nil, let scene = window?.windowScene else { return }
            let overlay = PassthroughWindow(windowScene: scene)
            let layer = ToastLayer { [weak overlay] in overlay?.active = $0 }.environment(model)
            let host = UIHostingController(rootView: layer)
            host.view.backgroundColor = .clear
            overlay.rootViewController = host
            overlay.windowLevel = .normal + 1
            overlay.overrideUserInterfaceStyle = .light
            overlay.isHidden = false
            self.overlay = overlay
        }
    }
}

extension View {
    func toastWindow(_ model: AppModel) -> some View {
        background(ToastWindowAnchor(model: model).frame(width: 0, height: 0))
    }
}

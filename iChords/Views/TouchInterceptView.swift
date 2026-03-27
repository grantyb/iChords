import SwiftUI
import UIKit

struct TouchInterceptView: UIViewRepresentable {
    var onTouchBegan: () -> Void
    var onTouchEnded: () -> Void
    var onScrollEnd: (() -> Void)?
    var onScroll: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTouchBegan: onTouchBegan,
            onTouchEnded: onTouchEnded,
            onScrollEnd: onScrollEnd,
            onScroll: onScroll
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false

        let recognizer = TouchTrackingRecognizer(coordinator: context.coordinator)
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        context.coordinator.recognizer = recognizer

        // Defer attaching to the scroll view until it's in the hierarchy
        DispatchQueue.main.async {
            if let scrollView = view.findParent(ofType: UIScrollView.self) {
                scrollView.addGestureRecognizer(recognizer)
                context.coordinator.attachedTo = scrollView
                context.coordinator.setupKVO()
            }
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTouchBegan = onTouchBegan
        context.coordinator.onTouchEnded = onTouchEnded
        context.coordinator.onScrollEnd = onScrollEnd
        context.coordinator.onScroll = onScroll
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        if let recognizer = coordinator.recognizer, let scrollView = coordinator.attachedTo {
            scrollView.removeGestureRecognizer(recognizer)
        }
        coordinator.teardownKVO()
    }

    class Coordinator: NSObject, @unchecked Sendable {
        var onTouchBegan: () -> Void
        var onTouchEnded: () -> Void
        var onScrollEnd: (() -> Void)?
        var onScroll: (() -> Void)?
        var recognizer: TouchTrackingRecognizer?
        weak var attachedTo: UIScrollView?
        private var isObservingContentOffset = false
        private var scrollEndTask: Task<Void, Never>?

        init(
            onTouchBegan: @escaping () -> Void,
            onTouchEnded: @escaping () -> Void,
            onScrollEnd: (() -> Void)?,
            onScroll: (() -> Void)?
        ) {
            self.onTouchBegan = onTouchBegan
            self.onTouchEnded = onTouchEnded
            self.onScrollEnd = onScrollEnd
            self.onScroll = onScroll
        }

        func setupKVO() {
            guard let sv = attachedTo else { return }
            sv.addObserver(self, forKeyPath: "contentOffset", options: [.new], context: nil)
            isObservingContentOffset = true
        }

        func teardownKVO() {
            if isObservingContentOffset, let sv = attachedTo {
                sv.removeObserver(self, forKeyPath: "contentOffset")
                isObservingContentOffset = false
            }
            scrollEndTask?.cancel()
        }

        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
            guard keyPath == "contentOffset" else { return }
            DispatchQueue.main.async { [weak self] in
                self?.onScroll?()
            }
        }

        func handleTouchEnded() {
            onTouchEnded()
            startScrollEndDetection()
        }

        func startScrollEndDetection() {
            scrollEndTask?.cancel()
            scrollEndTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 50_000_000) // poll every 50ms
                    guard let self, let sv = self.attachedTo else { break }
                    if !sv.isDragging && !sv.isDecelerating {
                        self.onScrollEnd?()
                        break
                    }
                }
            }
        }
    }
}

class TouchTrackingRecognizer: UIGestureRecognizer {
    weak var coordinator: TouchInterceptView.Coordinator?

    init(coordinator: TouchInterceptView.Coordinator) {
        self.coordinator = coordinator
        super.init(target: nil, action: nil)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        coordinator?.onTouchBegan()
        // Don't change state — let other recognizers handle normally
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        coordinator?.handleTouchEnded()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        coordinator?.handleTouchEnded()
    }
}

extension UIView {
    func findParent<T: UIView>(ofType type: T.Type) -> T? {
        var current = superview
        while let view = current {
            if let match = view as? T { return match }
            current = view.superview
        }
        return nil
    }
}

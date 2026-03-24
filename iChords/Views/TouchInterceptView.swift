import SwiftUI
import UIKit

struct TouchInterceptView: UIViewRepresentable {
    var onTouchBegan: () -> Void
    var onTouchEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTouchBegan: onTouchBegan, onTouchEnded: onTouchEnded)
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
            }
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTouchBegan = onTouchBegan
        context.coordinator.onTouchEnded = onTouchEnded
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        if let recognizer = coordinator.recognizer, let scrollView = coordinator.attachedTo {
            scrollView.removeGestureRecognizer(recognizer)
        }
    }

    class Coordinator {
        var onTouchBegan: () -> Void
        var onTouchEnded: () -> Void
        var recognizer: TouchTrackingRecognizer?
        weak var attachedTo: UIScrollView?

        init(onTouchBegan: @escaping () -> Void, onTouchEnded: @escaping () -> Void) {
            self.onTouchBegan = onTouchBegan
            self.onTouchEnded = onTouchEnded
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
        coordinator?.onTouchEnded()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        coordinator?.onTouchEnded()
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

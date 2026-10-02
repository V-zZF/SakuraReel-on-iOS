//
//  UnsavedDismissGuard.swift
//  SakuraReel
//
//  Created by OpenAI Codex on behalf of zzf on 2026/10/2.
//
import SwiftUI

/// UIKit provides the attempted-dismiss callback SwiftUI's interactiveDismissDisabled lacks.
struct UnsavedDismissGuard: ViewModifier {
    var isDirty: Bool
    var onAttempt: () -> Void
    func body(content: Content) -> some View {
        content.interactiveDismissDisabled(isDirty)
            .background(DismissObserver(isDirty: isDirty, onAttempt: onAttempt).frame(width: 0, height: 0))
    }
}
private struct DismissObserver: UIViewControllerRepresentable {
    var isDirty: Bool
    var onAttempt: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }
    func updateUIViewController(_ controller: UIViewController, context: Context) {
        context.coordinator.value = self
        DispatchQueue.main.async {
            var parent: UIViewController? = controller
            while let current = parent {
                if let presentation = current.presentationController { presentation.delegate = context.coordinator }
                parent = current.parent
            }
        }
    }
    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        var value: DismissObserver
        init(_ value: DismissObserver) { self.value = value }
        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool { !value.isDirty }
        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) { value.onAttempt() }
    }
}

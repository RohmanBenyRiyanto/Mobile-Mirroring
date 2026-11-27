import SwiftUI

/// Animates a change of `value`, unless the user asked for reduced motion (System Settings › Accessibility › Display):
/// then the change is immediate. (HIG: make motion optional.)
private struct Animated<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    public func animated<Value: Equatable>(_ animation: Animation = Theme.Motion.smooth, value: Value) -> some View {
        modifier(Animated(animation: animation, value: value))
    }
}

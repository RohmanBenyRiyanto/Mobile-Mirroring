import SwiftUI
import Theme

/// A soft moving highlight over a placeholder. It stands still when Reduce Motion is on.
private struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(colors: [.clear, Color.white.opacity(0.22), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: proxy.size.width * 0.6)
                            .offset(x: proxy.size.width * phase)
                    }
                    .clipped()
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1.4 }
            }
    }
}

/// A grey bar that stands in for a value that has not arrived yet.
public struct SkeletonBar: View {
    private let width: CGFloat

    public init(width: CGFloat = 90) { self.width = width }

    public var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Theme.Palette.control.color)
            .frame(width: width, height: 12)
            .modifier(Shimmer())
            .accessibilityLabel("Loading")
    }
}

/// Shows a skeleton while `isLoading`, then fades the real value in, so a field never just appears out of nothing.
public struct LoadedValue<Content: View>: View {
    private let isLoading: Bool
    private let skeletonWidth: CGFloat
    private let content: Content

    public init(isLoading: Bool, skeletonWidth: CGFloat = 90, @ViewBuilder content: () -> Content) {
        self.isLoading = isLoading
        self.skeletonWidth = skeletonWidth
        self.content = content()
    }

    public var body: some View {
        ZStack(alignment: .trailing) {
            if isLoading {
                SkeletonBar(width: skeletonWidth).transition(.opacity)
            } else {
                content.transition(.opacity)
            }
        }
        .animated(value: isLoading)
    }
}

/// A small spinner with a line of text, for a list or panel that is still filling in.
public struct LoadingLabel: View {
    private let text: LocalizedStringKey

    public init(_ text: LocalizedStringKey) { self.text = text }

    public var body: some View {
        HStack(spacing: Theme.Space.s2) {
            ProgressView().controlSize(.small)
            Text(text).foregroundStyle(Theme.Palette.textSecondary.color)
        }
        .transition(.opacity)
    }
}

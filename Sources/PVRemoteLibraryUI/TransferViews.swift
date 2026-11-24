import PVRemoteLibrary
import SwiftUI

/// The bar at the bottom of a library while a game is coming down: what it is,
/// what is happening, how far along, and a way to stop it.
public struct TransferBanner: View {
    private let title: String
    private let description: TransferDescription
    private let onCancel: (() -> Void)?
    private let onDismiss: (() -> Void)?

    /// - Parameters:
    ///   - onCancel: stops the transfer; shown while it can still be stopped.
    ///   - onDismiss: clears a failed transfer; shown only after a failure.
    public init(title: String, state: TransferState, onCancel: (() -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.title = title
        description = TransferDescription(state)
        self.onCancel = onCancel
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: Metrics.spacing) {
            TransferRing(description: description)
                .frame(width: Metrics.ring, height: Metrics.ring)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text(description.failure ?? description.phase)
                    .font(.subheadline)
                    .foregroundStyle(description.failure == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                    .lineLimit(2)
                if let fraction = description.fraction {
                    // Drawn here, not a system ProgressView: the same bar on iOS, tvOS and the Mac.
                    Capsule()
                        .fill(.tint.opacity(0.2))
                        .frame(height: Metrics.bar)
                        .overlay(alignment: .leading) {
                            GeometryReader { geometry in
                                Capsule()
                                    .fill(.tint)
                                    .frame(width: max(Metrics.bar, geometry.size.width * fraction))
                                    .animation(.easeOut(duration: 0.25), value: fraction)
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if description.canCancel, let onCancel {
                Button("Cancel", systemImage: "xmark", role: .cancel, action: onCancel)
                    .labelStyle(.iconOnly)
            } else if description.failure != nil, let onDismiss {
                Button("Dismiss", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
            }
        }
        .padding(Metrics.padding)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous))
        .padding(.horizontal, Metrics.padding)
        .padding(.bottom, Metrics.padding / 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(title), \(description.failure ?? description.phase)"))
        .accessibilityValue(Text(description.percent ?? ""))
    }

    private enum Metrics {
        #if os(tvOS)
        static let ring: CGFloat = 64
        static let bar: CGFloat = 8
        static let padding: CGFloat = 28
        static let spacing: CGFloat = 24
        static let corner: CGFloat = 24
        #else
        static let ring: CGFloat = 40
        static let bar: CGFloat = 5
        static let padding: CGFloat = 14
        static let spacing: CGFloat = 12
        static let corner: CGFloat = 16
        #endif
    }
}

/// A progress ring with the percentage inside, sized by its frame. Sits on a game's cover.
public struct TransferRing: View {
    private let description: TransferDescription
    @State private var spinning = false

    public init(state: TransferState) {
        description = TransferDescription(state)
    }

    init(description: TransferDescription) {
        self.description = description
    }

    public var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let line = max(2, side * 0.1)
            ZStack {
                Circle().stroke(.tint.opacity(0.2), lineWidth: line)
                if description.failure != nil {
                    Image(systemName: "exclamationmark")
                        .font(.system(size: side * 0.45, weight: .bold))
                        .foregroundStyle(.orange)
                } else if let fraction = description.fraction {
                    Circle()
                        .trim(from: 0, to: max(fraction, 0.02))
                        .stroke(.tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.25), value: fraction)
                    Text(description.percent ?? "")
                        .font(.system(size: side * 0.28, weight: .semibold).monospacedDigit())
                        .minimumScaleFactor(0.5)
                } else {
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(.tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .rotationEffect(.degrees(spinning ? 360 : 0))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spinning)
                        .onAppear { spinning = true }
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Names the source a library screen is showing: a glyph, the host or device name, a count.
public struct SourcePill: View {
    private let info: LibrarySourceInfo
    private let count: Int?
    private let isSelected: Bool
    private let isReachable: Bool

    public init(_ info: LibrarySourceInfo, count: Int? = nil, isSelected: Bool = false, isReachable: Bool = true) {
        self.info = info
        self.count = count
        self.isSelected = isSelected
        self.isReachable = isReachable
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isReachable ? info.symbol : "wifi.slash")
            Text(info.name).lineLimit(1)
            if let count {
                Text(count.formatted())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.quaternary), in: Capsule())
        .overlay(Capsule().strokeBorder(.tint.opacity(isSelected ? 0.8 : 0), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

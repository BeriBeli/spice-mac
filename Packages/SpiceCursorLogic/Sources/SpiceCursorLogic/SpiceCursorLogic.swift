import CoreGraphics
import Foundation

public enum SpiceCursorLogic {
    public enum HostCursorPresentation: Equatable {
        case transparent
        case custom
        case systemDefault
    }

    public struct PresentationDecision: Equatable {
        public let hostCursor: HostCursorPresentation
        public let inhibitOverlay: Bool

        public func visibleCursorCount(customOverlayVisible: Bool) -> Int {
            let hostVisible = hostCursor == .transparent ? 0 : 1
            let overlayVisible = !inhibitOverlay && customOverlayVisible ? 1 : 0
            return hostVisible + overlayVisible
        }
    }

    /// Pure description of the current presentation policy. Keeping this separate
    /// lets regression tests assert the exactly-one-visible-cursor invariant.
    public static func presentationDecision(
        serverMode: Bool,
        hidden: Bool,
        hasCustomShape: Bool,
        windowActive: Bool = true
    ) -> PresentationDecision {
        if !windowActive {
            return PresentationDecision(hostCursor: .systemDefault, inhibitOverlay: true)
        }
        if hidden {
            return PresentationDecision(hostCursor: .transparent, inhibitOverlay: true)
        }
        if serverMode && hasCustomShape {
            return PresentationDecision(hostCursor: .transparent, inhibitOverlay: false)
        }
        return PresentationDecision(
            hostCursor: hasCustomShape ? .custom : .systemDefault,
            inhibitOverlay: true
        )
    }

    /// Builds a CGImage using the byte interpretation currently used by the app.
    /// Tests intentionally exercise this function with known RGBA pixels.
    public static func makeNativeCursorImage(width: Int, height: Int, data: Data) -> CGImage? {
        guard width > 0, height > 0,
              data.count >= width * height * 4,
              let provider = CGDataProvider(data: data as CFData)
        else { return nil }

        let alpha = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: [.byteOrder32Big, alpha],
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

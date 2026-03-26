import SwiftUI

enum ColorPalette {
    // Background colors
    static let background = Color(nsColor: .windowBackgroundColor)
    static let secondaryBackground = Color(nsColor: .controlBackgroundColor)
    static let tertiaryBackground = Color(nsColor: .underPageBackgroundColor)

    // Text colors
    static let primaryText = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)

    // Accent colors
    static let accent = Color.accentColor
    static let selection = Color(nsColor: .selectedContentBackgroundColor)

    // Status colors
    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red
    static let info = Color.blue

    // Treemap gradient colors for depth
    static func depthColor(depth: Int, maxDepth: Int = 10) -> Color {
        let normalizedDepth = min(Double(depth) / Double(maxDepth), 1.0)
        return Color(
            hue: 0.6 - (normalizedDepth * 0.3),
            saturation: 0.3 + (normalizedDepth * 0.3),
            brightness: 0.9 - (normalizedDepth * 0.2)
        )
    }

    // Size-based color intensity
    static func sizeIntensity(size: UInt64, maxSize: UInt64) -> Double {
        guard maxSize > 0 else { return 0.5 }
        let ratio = Double(size) / Double(maxSize)
        return 0.4 + (ratio * 0.6)
    }
}

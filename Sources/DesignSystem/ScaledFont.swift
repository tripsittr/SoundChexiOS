// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// Fonts that keep the design's size but still grow with the reader's chosen
/// text size (#434).
///
/// The app was written with `.font(.system(size: 15))` throughout. A literal
/// point size ignores Dynamic Type completely: at the largest accessibility
/// setting the app looked exactly as it did at the smallest, which is the
/// single most common reason someone cannot read an app at all.
///
/// The obvious fix — `.system(size:relativeTo:)` — **does not exist**. Only
/// `Font.custom(_:size:relativeTo:)` takes a `relativeTo:`, and it needs a
/// named face rather than the system font. `.custom("SFPro-Regular", …)` is
/// not reliable across devices either, so the size itself is scaled with
/// `UIFontMetrics` and handed to the ordinary system font.
///
/// `UIFontMetrics` is what the text styles use underneath, so the result
/// tracks Dynamic Type exactly as `.body` would, from the size the design
/// actually asked for.
enum ScaledFont {
    /// The system font at `size`, scaled as `style` would be.
    ///
    /// - Parameters:
    ///   - size: the point size the design specifies at the default setting.
    ///   - style: the text style to scale in step with. Pick the one nearest
    ///     the size, so the growth curve matches what it looks like.
    ///   - weight: as `Font.system`.
    ///   - design: as `Font.system`.
    static func system(
        size: CGFloat,
        relativeTo style: Font.TextStyle = .body,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
    ) -> Font {
        .system(size: scaled(size, relativeTo: style), weight: weight, design: design)
    }

    /// The scaled point size on its own, for the places that need a number
    /// rather than a font — a frame that has to grow with the text in it.
    static func scaled(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> CGFloat {
        UIFontMetrics(forTextStyle: uiStyle(style)).scaledValue(for: size)
    }

    /// SwiftUI's text styles and UIKit's are the same set under two names.
    private static func uiStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}

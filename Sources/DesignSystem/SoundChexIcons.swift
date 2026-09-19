// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// The app's own icons, matched to the web media UI rather than to SF Symbols.
///
/// The web app draws its navigation with hand-made 24×24 stroked SVGs — a house,
/// a screen-with-play, a note-with-two-beats, a book, a magnifier — which give it
/// a look that is not Apple Music's default symbol set. These `Shape`s reproduce
/// those exact paths so the native tab bar reads as the same product.
///
/// Native `.tabItem` takes an image, not a view, so `tabImage(_:)` rasterises a
/// shape into a template `UIImage`. Everywhere else the `Shape`s can be stroked
/// directly.
enum SoundChexIcons {
    /// The web nav's stroke weight and canvas.
    static let stroke: CGFloat = 1.8
    static let canvas: CGFloat = 24

    // MARK: - Shapes (paths lifted from resources/views/components/media/nav.blade.php)

    /// House outline. Web: `M3 11l9-7 9 7v9a1 1 0 01-1 1h-5v-6H9v6H4a1 1 0 01-1-1z`
    struct Home: Shape {
        func path(in rect: CGRect) -> Path {
            SoundChexIcons.scaled(rect) { p, s in
                p.move(to: s(3, 11))
                p.addLine(to: s(12, 4))
                p.addLine(to: s(21, 11))
                p.addLine(to: s(21, 20))
                p.addLine(to: s(20, 21))
                p.addLine(to: s(15, 21))
                p.addLine(to: s(15, 15))
                p.addLine(to: s(9, 15))
                p.addLine(to: s(9, 21))
                p.addLine(to: s(4, 21))
                p.addLine(to: s(3, 20))
                p.closeSubpath()
            }
        }
    }

    /// Screen with a play triangle. Web: rect + `M10 9l5 2.5-5 2.5z`.
    struct Watch: Shape {
        func path(in rect: CGRect) -> Path {
            SoundChexIcons.scaled(rect) { p, s in
                p.addRoundedRect(in: CGRect(x: s(2, 4).x, y: s(2, 4).y,
                                            width: s(22, 4).x - s(2, 4).x,
                                            height: s(2, 19).y - s(2, 4).y),
                                 cornerSize: CGSize(width: rect.width / 12, height: rect.width / 12))
                p.move(to: s(10, 9))
                p.addLine(to: s(15, 11.5))
                p.addLine(to: s(10, 14))
                p.closeSubpath()
            }
        }
    }

    /// A note with two beats. Web: `M9 18V5l10-2v13` + two circles.
    struct Music: Shape {
        func path(in rect: CGRect) -> Path {
            SoundChexIcons.scaled(rect) { p, s in
                p.move(to: s(9, 18))
                p.addLine(to: s(9, 5))
                p.addLine(to: s(19, 3))
                p.addLine(to: s(19, 16))
                SoundChexIcons.addCircle(&p, center: s(6.5, 18), radius: rect.width / 24 * 2.5)
                SoundChexIcons.addCircle(&p, center: s(16.5, 16), radius: rect.width / 24 * 2.5)
            }
        }
    }

    /// A book. Web: `M4 5a2 2 0 012-2h13v18H6a2 2 0 01-2-2z` + spine `M8 3v18`.
    struct Book: Shape {
        func path(in rect: CGRect) -> Path {
            SoundChexIcons.scaled(rect) { p, s in
                p.move(to: s(4, 6))
                p.addLine(to: s(6, 4))
                p.addLine(to: s(19, 4))
                p.addLine(to: s(19, 21))
                p.addLine(to: s(6, 21))
                p.addLine(to: s(4, 19))
                p.closeSubpath()
                p.move(to: s(8, 4))
                p.addLine(to: s(8, 21))
            }
        }
    }

    /// A magnifier. Web: circle + `M20 20l-3.5-3.5`.
    struct Search: Shape {
        func path(in rect: CGRect) -> Path {
            SoundChexIcons.scaled(rect) { p, s in
                SoundChexIcons.addCircle(&p, center: s(11, 11), radius: rect.width / 24 * 7)
                p.move(to: s(20, 20))
                p.addLine(to: s(16.5, 16.5))
            }
        }
    }

    // MARK: - Rasterise a shape into a template tab image

    @MainActor
    static func tabImage<S: Shape>(_ shape: S, size: CGFloat = 26) -> Image {
        let view = shape
            .stroke(style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .foregroundStyle(.black) // template-rendered, so tint wins at use site

        let renderer = ImageRenderer(content: view)
        renderer.scale = UIScreen.main.scale

        if let ui = renderer.uiImage?.withRenderingMode(.alwaysTemplate) {
            return Image(uiImage: ui)
        }

        return Image(systemName: "square")
    }

    // MARK: - Helpers

    /// Map the web's 24-unit coordinates onto `rect`.
    static func scaled(_ rect: CGRect, _ build: (inout Path, (_ x: CGFloat, _ y: CGFloat) -> CGPoint) -> Void) -> Path {
        var path = Path()
        let sx = rect.width / canvas
        let sy = rect.height / canvas
        let point: (CGFloat, CGFloat) -> CGPoint = { x, y in
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }
        build(&path, point)
        return path
    }

    static func addCircle(_ path: inout Path, center: CGPoint, radius: CGFloat) {
        path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}

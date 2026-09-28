// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// Grid columns that suit the screen they are on (S-408).
///
/// The library grids were already `GridItem(.adaptive(minimum:))`, so they do
/// fill an iPad rather than leaving a phone-width strip. The trouble is what
/// they fill it *with*: a minimum tuned for a 393pt phone gives **ten columns
/// of 121pt posters** on a 13-inch iPad. Nothing is broken, and nothing is
/// readable either — artwork is the point of a library grid, and ten tiny
/// tiles is a worse way to browse than six good ones.
///
/// A bigger screen should mean bigger tiles *and* more of them. Raising the
/// minimum at regular width does both: four to seven poster columns at about
/// 180pt, rather than ten at 121pt.
///
/// Keyed on the horizontal size class rather than on `userInterfaceIdiom`,
/// because what matters is how much width this view actually has. An iPad in
/// Split View is compact and should look like a phone; a phone in landscape
/// is still compact and should not suddenly grow tiles.
enum AdaptiveGrid {
    /// How much wider a tile may be when there is room for it.
    ///
    /// 1.6 was chosen by working out the resulting column counts rather than
    /// by eye: it gives 4 columns on an 11-inch iPad in portrait and 7 on a
    /// 13-inch in landscape, which are the counts that look like a library
    /// rather than a contact sheet.
    private static let regularScale: CGFloat = 1.6

    /// Columns for a grid of this minimum tile width.
    ///
    /// - Parameters:
    ///   - minimum: the smallest a tile may be on a phone.
    ///   - spacing: the gap between columns.
    ///   - sizeClass: the view's horizontal size class.
    static func columns(
        minimum: CGFloat,
        spacing: CGFloat,
        for sizeClass: UserInterfaceSizeClass?,
    ) -> [GridItem] {
        // `Self.` because the parameter shadows the method of the same name.
        [GridItem(.adaptive(minimum: Self.minimum(for: sizeClass, base: minimum)), spacing: spacing)]
    }

    /// The minimum tile width for a size class.
    static func minimum(for sizeClass: UserInterfaceSizeClass?, base: CGFloat) -> CGFloat {
        sizeClass == .regular ? base * regularScale : base
    }
}

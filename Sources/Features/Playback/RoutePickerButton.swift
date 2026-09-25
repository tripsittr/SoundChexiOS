// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import AVKit
import SwiftUI

/// The AirPlay button — pick a speaker, an Apple TV, a HomePod (S-165).
///
/// The audio already *goes* to AirPlay: the session is configured `.playback`
/// with the `.longFormAudio` policy, so iOS routes it like any music app and
/// Control Centre can move it. What was missing was a way to choose a
/// destination without leaving the app, which is the whole of this file.
///
/// `AVRoutePickerView` is UIKit and has no SwiftUI equivalent, so it is wrapped.
/// It draws and manages its own icon, which changes to reflect the active route
/// — that is why the colours are set on the view rather than by a SwiftUI
/// `foregroundStyle` that would fight it.
struct RoutePickerButton: UIViewRepresentable {
    var tint: UIColor
    /// The colour of the icon while something is playing to a remote route, so
    /// the button says *where* the audio is, not just that a picker exists.
    var activeTint: UIColor

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()

        view.tintColor = tint
        view.activeTintColor = activeTint
        // Video-capable routes are offered by default, which on an audio-only
        // player means an Apple TV appears as a mirroring target and picking it
        // does nothing useful.
        view.prioritizesVideoDevices = false

        // A UIKit view inside a SwiftUI HStack otherwise claims more width than
        // its icon needs and pushes the row apart.
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentCompressionResistancePriority(.required, for: .horizontal)

        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.tintColor = tint
        view.activeTintColor = activeTint
    }
}

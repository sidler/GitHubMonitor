import AppKit
import SwiftUI

/// The system's hues, at a weight that can be read.
///
/// `.red`, `.green` and the rest are tuned to stand out on a control, not
/// to be read as small text against a page. Measured in light mode, a
/// green tick came in at 2.2 to one, an orange timestamp at 2.3 and a
/// yellow one at 1.5; on the grey of a selected row, lower still. Four and
/// a half to one is where small text stops being work.
///
/// So each hue was walked along its own brightness -- darker in light
/// mode, lighter in dark -- until it cleared that against every ground the
/// app actually draws it on: the page, a selected row, and the two tinted
/// bands a diff puts behind a changed line, and the wash a chip lays down
/// behind its own name. The hues are the system's. A
/// string is still red and a type still teal; only the weight has moved.
///
/// One palette rather than one per view. The colours used to be chosen
/// separately in four files, which is four chances to pick one nobody can
/// read, and `ReviewDecision.tint` already carried a comment warning about
/// a trap the others walked into anyway.
public enum Ink {
    public static let red = pair(light: 0xA8_12_15, dark: 0xFF_A9_AA)
    public static let orange = pair(light: 0x8E_43_01, dark: 0xFF_BE_83)
    public static let yellow = pair(light: 0x71_5A_00, dark: 0xFF_D6_00)
    public static let green = pair(light: 0x0E_67_24, dark: 0x45_E9_6E)
    public static let teal = pair(light: 0x00_63_69, dark: 0x0B_E2_F1)
    public static let blue = pair(light: 0x00_55_A0, dark: 0x85_CA_FF)
    /// The system's cyan: the light blue, for a line the app writes among
    /// lines it did not.
    ///
    /// Walked the same way as the rest, and it had less room than most.
    /// In light mode it is about as light as a blue gets before it stops
    /// clearing four and a half to one on the grounds this app draws on,
    /// which leaves it a third brighter than `blue` and a dozen degrees
    /// cooler -- the distance wanted, since `blue` is the rule down an
    /// unsettled conversation and these two must not read as one mark.
    /// Cyan sits between `blue` and `teal` because that is where the
    /// hue is; the weight is what keeps the three apart.
    public static let cyan = pair(light: 0x00_66_8B, dark: 0x5F_D8_EF)
    public static let indigo = pair(light: 0x46_3B_CA, dark: 0xB8_C0_FF)
    public static let purple = pair(light: 0x8E_14_9E, dark: 0xF4_A2_FF)
    public static let pink = pair(light: 0xA8_0A_28, dark: 0xFF_A6_B8)
    public static let gray = pair(light: 0x55_55_5F, dark: 0xC9_C9_C9)

    /// A wash of one of these, for a chip to sit on.
    ///
    /// The system colour rather than the weighted one: the band is behind
    /// the text, so it wants to stay light while the text goes dark. Using
    /// the same value for both is what made an issue type read at two to
    /// one -- the two were the same colour at different strengths.
    public static func wash(_ system: Color, _ strength: Double = 0.14) -> Color {
        system.opacity(strength)
    }

    /// Light and dark in one colour, resolved by whoever draws it.
    ///
    /// A dynamic `NSColor` rather than two static ones: the app follows a
    /// change of theme without being told, and a view asking for a tint
    /// does not build a new object each time.
    private static func pair(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            value(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
    }

    private static func value(_ packed: Int) -> NSColor {
        NSColor(
            srgbRed: Double((packed >> 16) & 0xFF) / 255,
            green: Double((packed >> 8) & 0xFF) / 255,
            blue: Double(packed & 0xFF) / 255,
            alpha: 1
        )
    }
}

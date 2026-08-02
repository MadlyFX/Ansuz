#+build !freestanding
package ansuz

// --- Embedded Font Data ---
// OpenSans Regular TTF, embedded at compile time for use as the default font
// on desktop and web targets. Freestanding (embedded) targets use only the
// built-in 5x7 bitmap font.

OPENSANS_FONT_SCALE := f32(4)

OPENSANS_REGULAR :: #load("fonts/OpenSans-Regular.ttf")
OPENSANS_REGULAR_ITALIC :: #load("fonts/OpenSans-Italic.ttf")
OPENSANS_MEDIUM :: #load("fonts/OpenSans-Medium.ttf")
OPENSANS_MEDIUM_ITALIC :: #load("fonts/OpenSans-MediumItalic.ttf")
OPENSANS_SEMIBOLD :: #load("fonts/OpenSans-SemiBold.ttf")
OPENSANS_SEMIBOLD_ITALIC :: #load("fonts/OpenSans-SemiBoldItalic.ttf")
OPENSANS_BOLD :: #load("fonts/OpenSans-Bold.ttf")
OPENSANS_BOLD_ITALIC :: #load("fonts/OpenSans-BoldItalic.ttf")

// Roboto Mono (Apache-2.0) — a fixed-width companion to OpenSans, used to render
// code notes so indentation and columns line up. See fonts/RobotoMono-LICENSE.txt.
ROBOTOMONO_REGULAR :: #load("fonts/RobotoMono-Regular.ttf")

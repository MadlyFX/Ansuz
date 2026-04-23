//+build !freestanding
package ansuz

// --- Embedded Font Data ---
// OpenSans Regular TTF, embedded at compile time for use as the default font
// on desktop and web targets. Freestanding (embedded) targets use only the
// built-in 5x7 bitmap font.

OPENSANS_FONT_SCALE := f32(4)

OPENSANS_REGULAR :: #load("fonts/OpenSans-Regular.ttf")
OPENSANS_BOLD :: #load("fonts/OpenSans-Bold.ttf")
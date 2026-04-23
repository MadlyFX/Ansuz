package ansuz

import "core:math/ease"

// --- Easing Functions ---
// Delegates to core:math/ease. Input t is 0..1, output is 0..1.
// See https://easings.net for visual reference.

// Re-export the stdlib Ease enum so callers use ansuz.Ease_Func
Ease_Func :: ease.Ease

// Apply an easing curve to t in [0, 1].
ease_apply :: proc(raw_t: f32, func: Ease_Func = .Quadratic_Out) -> f32 {
	return ease.ease(func, clamp(raw_t, 0, 1))
}

// Interpolate between two f32 values with easing.
ease_lerp :: proc(from, to, t: f32, func: Ease_Func = .Quadratic_Out) -> f32 {
	return from + (to - from) * ease_apply(t, func)
}

// Interpolate between two colors with easing.
ease_color :: proc(from, to: Color, t: f32, func: Ease_Func = .Quadratic_Out) -> Color {
	e := ease_apply(t, func)
	return color_lerp(from, to, e)
}

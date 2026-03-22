package ogui

import "core:math"

// --- Easing Functions ---
// Standard easing curves for animations. Input t is 0..1, output is 0..1.
// See https://easings.net for visual reference.

Ease_Func :: enum {
	Linear,
	Ease_In_Quad,
	Ease_Out_Quad,
	Ease_In_Out_Quad,
	Ease_In_Cubic,
	Ease_Out_Cubic,
	Ease_In_Out_Cubic,
	Ease_Out_Back,
	Ease_Out_Elastic,
	Ease_Out_Bounce,
}

ease :: proc(raw_t: f32, func: Ease_Func = .Ease_Out_Quad) -> f32 {
	t := clamp(raw_t, 0, 1)

	switch func {
	case .Linear:
		return t

	case .Ease_In_Quad:
		return t * t

	case .Ease_Out_Quad:
		return 1 - (1 - t) * (1 - t)

	case .Ease_In_Out_Quad:
		if t < 0.5 {
			return 2 * t * t
		}
		return 1 - (-2 * t + 2) * (-2 * t + 2) / 2

	case .Ease_In_Cubic:
		return t * t * t

	case .Ease_Out_Cubic:
		p := 1 - t
		return 1 - p * p * p

	case .Ease_In_Out_Cubic:
		if t < 0.5 {
			return 4 * t * t * t
		}
		p := -2 * t + 2
		return 1 - p * p * p / 2

	case .Ease_Out_Back:
		c1 :: 1.70158
		c3 :: c1 + 1
		p := t - 1
		return 1 + c3 * p * p * p + c1 * p * p

	case .Ease_Out_Elastic:
		if t == 0 || t == 1 { return t }
		c4 :: (2 * math.PI) / 3
		return math.pow_f32(2, -10 * t) * math.sin_f32((t * 10 - 0.75) * c4) + 1

	case .Ease_Out_Bounce:
		return ease_out_bounce(t)
	}

	return t
}

ease_out_bounce :: proc(t: f32) -> f32 {
	n1 :: f32(7.5625)
	d1 :: f32(2.75)

	if t < 1 / d1 {
		return n1 * t * t
	} else if t < 2 / d1 {
		t2 := t - 1.5 / d1
		return n1 * t2 * t2 + 0.75
	} else if t < 2.5 / d1 {
		t2 := t - 2.25 / d1
		return n1 * t2 * t2 + 0.9375
	} else {
		t2 := t - 2.625 / d1
		return n1 * t2 * t2 + 0.984375
	}
}

// Interpolate between two f32 values with easing.
ease_lerp :: proc(from, to, t: f32, func: Ease_Func = .Ease_Out_Quad) -> f32 {
	return from + (to - from) * ease(t, func)
}

// Interpolate between two colors with easing.
ease_color :: proc(from, to: Color, t: f32, func: Ease_Func = .Ease_Out_Quad) -> Color {
	e := ease(t, func)
	return color_lerp(from, to, e)
}

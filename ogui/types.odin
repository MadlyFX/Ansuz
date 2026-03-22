package ogui

// --- Basic Types ---

Vec2 :: [2]f32

Rect :: struct {
	x, y, w, h: f32,
}

Color :: struct {
	r, g, b, a: u8,
}

Font_Handle :: distinct u32

// --- Predefined Colors ---

COLOR_TRANSPARENT :: Color{0, 0, 0, 0}
COLOR_WHITE       :: Color{255, 255, 255, 255}
COLOR_BLACK       :: Color{0, 0, 0, 255}
COLOR_RED         :: Color{220, 50, 50, 255}
COLOR_GREEN       :: Color{50, 200, 50, 255}
COLOR_BLUE        :: Color{50, 100, 220, 255}
COLOR_YELLOW      :: Color{240, 220, 50, 255}
COLOR_CYAN        :: Color{50, 220, 220, 255}
COLOR_MAGENTA     :: Color{220, 50, 220, 255}
COLOR_GRAY        :: Color{128, 128, 128, 255}
COLOR_DARK_GRAY   :: Color{45, 45, 48, 255}

// --- Rect Helpers ---

rect_contains :: proc(r: Rect, px, py: f32) -> bool {
	return px >= r.x && px < r.x + r.w && py >= r.y && py < r.y + r.h
}

rect_intersect :: proc(a, b: Rect) -> Rect {
	x1 := max(a.x, b.x)
	y1 := max(a.y, b.y)
	x2 := min(a.x + a.w, b.x + b.w)
	y2 := min(a.y + a.h, b.y + b.h)
	if x2 <= x1 || y2 <= y1 {
		return {}
	}
	return Rect{x1, y1, x2 - x1, y2 - y1}
}

rect_expand :: proc(r: Rect, amount: f32) -> Rect {
	return Rect{r.x - amount, r.y - amount, r.w + amount * 2, r.h + amount * 2}
}

rect_shrink :: proc(r: Rect, top, right, bottom, left: f32) -> Rect {
	return Rect{
		r.x + left,
		r.y + top,
		max(0, r.w - left - right),
		max(0, r.h - top - bottom),
	}
}

// --- Color Helpers ---

color_lerp :: proc(a, b: Color, t: f32) -> Color {
	tc := clamp(t, 0, 1)
	return Color{
		u8(f32(a.r) + (f32(b.r) - f32(a.r)) * tc),
		u8(f32(a.g) + (f32(b.g) - f32(a.g)) * tc),
		u8(f32(a.b) + (f32(b.b) - f32(a.b)) * tc),
		u8(f32(a.a) + (f32(b.a) - f32(a.a)) * tc),
	}
}

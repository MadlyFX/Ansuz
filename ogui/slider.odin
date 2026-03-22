package ogui

import "core:fmt"

// --- Slider ---
// A horizontal slider that writes its value through a pointer.
// Uses the pointer-based reactive state pattern: pass &my_value.

SLIDER_TRACK_HEIGHT   :: f32(6)
SLIDER_THUMB_WIDTH    :: f32(16)
SLIDER_THUMB_HEIGHT   :: f32(22)
SLIDER_DEFAULT_HEIGHT :: f32(30)

THEME_SLIDER_TRACK       :: Color{50, 53, 60, 255}
THEME_SLIDER_FILL        :: Color{80, 140, 220, 255}
THEME_SLIDER_FILL_HOVER  :: Color{100, 160, 240, 255}
THEME_SLIDER_THUMB        :: Color{200, 203, 210, 255}
THEME_SLIDER_THUMB_ACTIVE :: Color{80, 140, 220, 255}

slider_f32 :: proc(
	mgr:   ^Manager,
	value: ^f32,
	lo:    f32 = 0,
	hi:    f32 = 1,
	scale: f32 = 1.0,
	size:  [2]Size_Spec = {SIZE_GROW, SIZE_FIT},
	loc    := #caller_location,
) -> Interaction {
	id := id_from_ptr_loc(&mgr.id_stack, value, loc)

	// Compute actual size — Fit height auto-scales from the scale parameter
	actual_size := size
	if actual_size[1].kind == .Fit {
		actual_size[1] = size_fixed(SLIDER_DEFAULT_HEIGHT * scale)
	}

	// Look up previous frame's rect
	prev_rect := Rect{}
	if state, ok := mgr.widget_states[id]; ok {
		prev_rect = state.prev_rect
	}

	interaction := compute_interaction(mgr, id, prev_rect)

	// If actively dragging, update value from mouse position
	thumb_w := SLIDER_THUMB_WIDTH * scale
	if .Pressed in interaction && prev_rect.w > 0 {
		track_left  := prev_rect.x + thumb_w / 2
		track_right := prev_rect.x + prev_rect.w - thumb_w / 2
		track_width := track_right - track_left

		if track_width > 0 {
			t := clamp((mgr.input.mouse_x - track_left) / track_width, 0, 1)
			value^ = lo + (hi - lo) * t
		}
	}

	// Clamp value
	value^ = clamp(value^, lo, hi)

	// Create the box for this slider
	idx := box(mgr, size = actual_size, loc = loc)

	// Track value for dirty detection and register for prev_rect update
	track_value(mgr, id, value)
	append(&mgr.widget_box_map, Widget_Box_Entry{id = id, box_index = idx})

	// Defer custom drawing (track + thumb) until after layout
	t := f32(0)
	if hi > lo {
		t = (value^ - lo) / (hi - lo)
	}
	append(&mgr.deferred_draws, Deferred_Draw{
		box_index = idx,
		kind      = .Slider,
		scale     = scale,
		slider    = Deferred_Slider_Data{
			t           = t,
			interaction = interaction,
		},
	})

	return interaction
}

slider :: proc{slider_f32}

// --- Slider Label ---
// A slider with a label showing the current value.

slider_labeled :: proc(
	mgr:    ^Manager,
	text:   string,
	value:  ^f32,
	lo:     f32 = 0,
	hi:     f32 = 1,
	scale:  f32 = 1.0,
	format: string = "%.2f",
	loc     := #caller_location,
) -> Interaction {
	row_h := SLIDER_DEFAULT_HEIGHT * scale
	gap := max(2, 10 * scale)
	flex_begin(mgr, axis = .Horizontal, gap = gap, align = .Center, size = {SIZE_GROW, size_fixed(row_h)}, loc = loc)
	label(mgr, text, scale = scale * DEFAULT_FONT_SCALE)
	interaction := slider_f32(mgr, value, lo, hi, scale = scale, size = {SIZE_GROW, size_fixed(row_h)})
	label(mgr, fmt.tprintf(format, value^), scale = scale * DEFAULT_FONT_SCALE, color = THEME_TEXT_DIM)
	flex_end(mgr)
	return interaction
}

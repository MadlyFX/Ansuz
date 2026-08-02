package ansuz

import "core:fmt"

// --- Slider ---
// A horizontal slider that writes its value through a pointer.
// Uses the pointer-based reactive state pattern: pass &my_value.
// scale is a whole-widget multiplier (1 = default size).
// colors slots: bg = track, fg = fill, hover = fill while hovered,
// press = thumb while dragging, focus = thumb.

SLIDER_TRACK_HEIGHT   :: f32(6)
SLIDER_THUMB_WIDTH    :: f32(16)
SLIDER_THUMB_HEIGHT   :: f32(22)
SLIDER_DEFAULT_HEIGHT :: f32(30)

slider_f32 :: proc(
	mgr:   ^Manager,
	value: ^f32,
	lo:    f32 = 0,
	hi:    f32 = 1,
	scale: f32 = 1.0,
	colors: Widget_Color = Widget_Color{
		bg    = THEME_SLIDER_TRACK,
		fg    = THEME_SLIDER_FILL,
		hover = THEME_SLIDER_FILL_HOVER,
		press = THEME_SLIDER_THUMB_ACTIVE,
		focus = THEME_SLIDER_THUMB,
	},
	size:  [2]Size_Spec = {SIZE_GROW, SIZE_FIT},
	disabled: bool = false,
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

	interaction: Interaction
	if disabled {
		release_interaction(mgr, id)
	} else {
		interaction = compute_interaction(mgr, id, prev_rect)
	}

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
	draw_colors := colors
	if disabled {
		draw_colors.fg = disabled_color(draw_colors.fg, 0.35)
		draw_colors.focus = disabled_color(draw_colors.focus, 0.35)
	}
	append(&mgr.deferred_draws, Deferred_Draw{
		box_index = idx,
		kind      = .Slider,
		scale     = scale,
		colors    = draw_colors,
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
	font: Font_Handle = FONT_DEFAULT,
	colors: Widget_Color = Widget_Color{
		bg    = THEME_SLIDER_TRACK,
		fg    = THEME_SLIDER_FILL,
		hover = THEME_SLIDER_FILL_HOVER,
		press = THEME_SLIDER_THUMB_ACTIVE,
		focus = THEME_SLIDER_THUMB,
	},
	text_color: Color = THEME_TEXT,
	disabled: bool = false,
	loc     := #caller_location,
) -> Interaction {
	effective_font := resolve_font(mgr, font)
	// Plain if instead of a ternary: mixing a param and a call result in one
	// ternary miscompiles on arm32 with current Odin nightlies.
	effective_text_color := text_color
	if disabled {
		effective_text_color = disabled_color(text_color)
	}
	row_h := SLIDER_DEFAULT_HEIGHT * scale
	gap := max(2, 10 * scale)
	flex_begin(mgr, axis = .Horizontal, gap = gap, align = .Center, size = {SIZE_GROW, size_fixed(row_h)}, loc = loc)
	label(mgr, text, scale = scale * DEFAULT_FONT_SCALE, font = effective_font, color = effective_text_color)
	interaction := slider_f32(mgr, value, lo, hi, scale = scale, size = {SIZE_GROW, size_fixed(row_h)}, colors = colors, disabled = disabled)
	label(mgr, fmt.tprintf(format, value^), scale = scale * DEFAULT_FONT_SCALE, color = effective_text_color, font = effective_font)
	flex_end(mgr)
	return interaction
}

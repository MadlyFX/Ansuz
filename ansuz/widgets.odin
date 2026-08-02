package ansuz
import "core:fmt"

// --- Widget Procs ---
// Label, button, and heading. Theme color defaults live in theme.odin.
//
// Scale conventions across the widget set:
//   - Text widgets (label, button, heading, dropdown, menu_button, tree rows,
//     text_input, collapsible_header) take a font scale, defaulting to
//     DEFAULT_FONT_SCALE.
//   - Composite widgets whose geometry scales as a whole (checkbox, slider,
//     disclosure_icon, hamburger_icon) take a widget multiplier defaulting to
//     1.0; their text is drawn at scale * DEFAULT_FONT_SCALE.

// Scale for the built-in bitmap font (2 = 10x14 pixel characters).
// Mutable so it can be shadowed for custom fonts with different native sizes.
DEFAULT_FONT_SCALE := f32(2)

// --- Deferred Text Entry ---
// Text draw commands are deferred until after layout resolve, because the
// box position isn't known when the widget proc is called.

Deferred_Text :: struct {
	box_index: int,
	text:      string,
	color:     Color,
	scale:     f32,
	font:      Font_Handle, // which font to render with
	center_h:  bool, // center horizontally within box
	center_v:  bool, // center vertically within box
	clip:      bool, // clip text to content rect (for text inputs)
	offset_x:  f32, // horizontal scroll offset (single-line text inputs)
	offset_y:  f32, // vertical scroll offset (multiline text inputs)
	selection_start: int, // byte range highlighted before this text is drawn
	selection_end:   int,
	selection_color: Color,
	// Styled (rich) text. When runs is non-empty they are drawn instead of
	// `text`, one draw per emphasis fragment — see richtext.odin.
	runs:            []Text_Run,
	run_lines:       int,
	run_line_height: f32,
	code_color:      Color, // chip behind inline-code runs; transparent = none
}

// --- Label ---
// Displays text. No interaction.

label :: proc(
	mgr: ^Manager,
	text: string,
	color: Color = THEME_TEXT,
	bg_color: Color = COLOR_TRANSPARENT,
	font: Font_Handle = FONT_DEFAULT,
	scale: f32 = DEFAULT_FONT_SCALE,
	size: [2]Size_Spec = SIZE_FIT_FIT,
	padding: [4]f32 = {2, 4, 2, 4},
	clip: bool = false,
	loc := #caller_location,
) -> int {
	effective_font := resolve_font(mgr, font)

	// If size is Fit, compute from text measurement
	actual_size := size
	text_dims := measure_text(mgr, text, effective_font, scale)
	if actual_size[0].kind == .Fit {
		actual_size[0] = size_fixed(text_dims.x + padding[1] + padding[3])
	}
	if actual_size[1].kind == .Fit {
		actual_size[1] = size_fixed(text_dims.y + padding[0] + padding[2])
	}

	idx := box(mgr, size = actual_size, loc = loc, bg_color = bg_color)
	mgr.boxes[idx].padding = padding

	// Defer text drawing until after layout
	append(
		&mgr.deferred_texts,
		Deferred_Text {
			box_index = idx,
			text = text,
			color = color,
			scale = scale,
			font = effective_font,
			center_h = false,
			center_v = true,
			clip = clip,
		},
	)

	return idx
}

Affix :: enum {
	None,
	Prefix,
	Suffix,
}

label_decorated :: proc(
	mgr: ^Manager,
	text: string,
	decorator: string,
	color: Color = THEME_TEXT,
	bg_color: Color = COLOR_TRANSPARENT,
	affix: Affix = .Prefix,
	font: Font_Handle = FONT_DEFAULT,
	scale: f32 = DEFAULT_FONT_SCALE,
	size: [2]Size_Spec = SIZE_FIT_FIT,
	padding: [4]f32 = {2, 4, 2, 4},
	clip: bool = false,
	loc := #caller_location,
) -> int {
	output_text := text

	if affix == .Prefix {
		output_text = fmt.tprintf("%s%s", decorator, text)
	} else if affix == .Suffix {
		output_text = fmt.tprintf("%s%s", text, decorator)
	}

	return label(
		mgr,
		output_text,
		color = color,
		bg_color = bg_color,
		scale = scale,
		size = size,
		padding = padding,
		clip = clip,
		loc = loc,
		font = font,
	)
}

// --- Button ---
// Clickable button with text. Returns interaction flags.
// colors slots: bg = resting fill, fg = border, hover/press/focus = state fills.

button :: proc(
	mgr: ^Manager,
	text: string,
	scale: f32 = DEFAULT_FONT_SCALE,
	size: [2]Size_Spec = SIZE_FIT_FIT,
	padding: [4]f32 = {6, 16, 6, 16},
	colors: Widget_Color = Widget_Color{
		bg = THEME_BG_BUTTON,
		fg = THEME_BORDER,
		hover = THEME_BG_BUTTON_HOVER,
		press = THEME_BG_BUTTON_ACTIVE,
		focus = THEME_BG_BUTTON_HOVER,
	},
	text_color: Color = THEME_TEXT,
	font: Font_Handle = FONT_DEFAULT,
	corner_radius: f32 = -1, // negative = derive from scale
	disabled: bool = false,
	clip: bool = false,
	loc := #caller_location,
) -> Interaction {
	effective_font := resolve_font(mgr, font)
	id := id_from_loc(&mgr.id_stack, loc)

	// Look up previous frame's rect for hit testing
	prev_rect := Rect{}
	if state, ok := mgr.widget_states[id]; ok {
		prev_rect = state.prev_rect
	}

	// Compute interaction
	interaction: Interaction
	bg := colors.bg
	border := colors.fg
	effective_text_color := text_color
	if disabled {
		release_interaction(mgr, id)
		border = disabled_color(border)
		effective_text_color = disabled_color(effective_text_color)
	} else {
		interaction = compute_interaction(mgr, id, prev_rect)

		// Smooth color transition based on interaction state
		hover_t := get_hover_t(mgr, id, .Hovered in interaction)
		press_t := get_press_t(mgr, id, .Pressed in interaction)
		focus_t := get_focus_t(mgr, id, .Focused in interaction)
		bg = blend_interaction_color(
			colors.bg,
			colors.hover,
			colors.press,
			colors.focus,
			hover_t,
			press_t,
			focus_t,
		)
	}

	// Compute size from text if Fit
	actual_size := size
	text_dims := measure_text(mgr, text, effective_font, scale)
	if actual_size[0].kind == .Fit {
		actual_size[0] = size_fixed(text_dims.x + padding[1] + padding[3])
	}
	if actual_size[1].kind == .Fit {
		actual_size[1] = size_fixed(text_dims.y + padding[0] + padding[2])
	}

	idx := box(mgr, size = actual_size, bg_color = bg, loc = loc)
	mgr.boxes[idx].padding = padding
	mgr.boxes[idx].border_width = 1
	mgr.boxes[idx].border_color = border
	mgr.boxes[idx].corner_radius = corner_radius if corner_radius >= 0 else max(1, 4 * (scale / DEFAULT_FONT_SCALE))

	// Defer text drawing
	append(
		&mgr.deferred_texts,
		Deferred_Text {
			box_index = idx,
			text = text,
			color = effective_text_color,
			scale = scale,
			font = effective_font,
			center_h = true,
			center_v = true,
			clip = clip,
		},
	)

	// Register for prev_rect update
	get_or_create_widget_state(mgr, id)

	// Store box index so frame_end can update prev_rect
	append(&mgr.widget_box_map, Widget_Box_Entry{id = id, box_index = idx})

	return interaction
}

// --- Heading ---
// Larger text label.

heading :: proc(
	mgr: ^Manager,
	text: string,
	color: Color = THEME_TEXT,
	bg_color: Color = COLOR_TRANSPARENT,
	font: Font_Handle = FONT_DEFAULT,
	scale: f32 = 3,
	size: [2]Size_Spec = SIZE_FIT_FIT,
	padding: [4]f32 = {4, 4, 4, 4},
	clip: bool = false,
	loc := #caller_location,
) -> int {
	return label(
		mgr,
		text,
		color = color,
		bg_color = bg_color,
		scale = scale,
		size = size,
		padding = padding,
		clip = clip,
		loc = loc,
		font = font,
	)
}

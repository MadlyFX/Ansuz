package ansuz

// --- Checkbox ---
// A toggle box with optional label text. Writes through a ^bool pointer.
// scale is a whole-widget multiplier (1 = default size); text renders at
// scale * DEFAULT_FONT_SCALE.
// colors slots: bg = row background, fg = unchecked box fill,
// hover = hovered box fill, focus = checked box fill (press is unused).

CHECKBOX_BOX_SIZE :: f32(22)

checkbox :: proc(
	mgr: ^Manager,
	text: string,
	value: ^bool,
	scale: f32 = 1.0,
	font: Font_Handle = FONT_DEFAULT,
	colors: Widget_Color = Widget_Color{
		bg = COLOR_TRANSPARENT,
		fg = THEME_CHECKBOX_BG,
		hover = THEME_CHECKBOX_BG_HOVER,
		focus = THEME_CHECKBOX_CHECKED,
	},
	text_color: Color = THEME_TEXT,
	check_color: Color = THEME_CHECKBOX_CHECK_MARK,
	border_color: Color = THEME_BORDER,
	disabled: bool = false,
	loc := #caller_location,
) -> Interaction {
	effective_font := resolve_font(mgr, font)
	id := id_from_ptr_loc(&mgr.id_stack, value, loc)

	box_size := CHECKBOX_BOX_SIZE * scale
	gap := max(2, 8 * scale)
	pad_v := max(1, 2 * scale)
	pad_h := max(2, 4 * scale)
	font_scale := scale * DEFAULT_FONT_SCALE

	// Look up previous frame's rect
	prev_rect := Rect{}
	if state, ok := mgr.widget_states[id]; ok {
		prev_rect = state.prev_rect
	}

	interaction: Interaction
	box_bg: Color
	effective_text_color := text_color
	effective_check_color := check_color
	effective_border_color := border_color
	if disabled {
		release_interaction(mgr, id)
		box_bg = colors.focus if value^ else colors.fg
		box_bg = disabled_color(box_bg, 0.35)
		effective_text_color = disabled_color(effective_text_color)
		effective_check_color = disabled_color(effective_check_color)
		effective_border_color = disabled_color(effective_border_color)
	} else {
		interaction = compute_interaction(mgr, id, prev_rect)

		// Toggle on click
		if .Clicked in interaction {
			value^ = !value^
		}

		// Smooth color transitions — press_t doubles as the checked-state fade
		hover_t := get_hover_t(mgr, id, .Hovered in interaction)
		unchecked_bg := color_lerp(colors.fg, colors.hover, hover_t)
		box_bg = color_lerp(unchecked_bg, colors.focus, get_press_t(mgr, id, value^))
	}

	// Layout: horizontal flex with checkbox box + label
	row_size := [2]Size_Spec{SIZE_FIT, size_fixed(box_size + pad_v * 2)}
	if len(text) > 0 {
		text_dims := measure_text(mgr, text, effective_font, font_scale)
		row_size[0] = size_fixed(box_size + gap + text_dims.x + pad_h * 2)
	} else {
		row_size[0] = size_fixed(box_size + pad_h * 2)
	}

	// Create an outer box for the whole checkbox widget (used for hit testing)
	outer_idx := push_box(mgr, id)
	outer := &mgr.boxes[outer_idx]
	outer.layout_kind = .Flex
	outer.layout_axis = .Horizontal
	outer.align = .Center
	outer.gap = gap
	outer.size = row_size
	outer.padding = {pad_v, pad_h, pad_v, pad_h}
	outer.bg_color = colors.bg

	// The checkbox square
	check_idx := box(mgr, size = {size_fixed(box_size), size_fixed(box_size)}, bg_color = box_bg)
	mgr.boxes[check_idx].border_width = max(1, 1 * scale)
	mgr.boxes[check_idx].border_color = effective_border_color
	mgr.boxes[check_idx].corner_radius = max(1, 3 * scale)

	// Checkmark: deferred draw
	if value^ {
		append(
			&mgr.deferred_draws,
			Deferred_Draw{
				box_index = check_idx,
				kind = .Checkmark,
				scale = scale,
				checkmark = Deferred_Checkmark_Data{color = effective_check_color},
			},
		)
	}

	// Label text
	if len(text) > 0 {
		label(mgr, text, scale = font_scale, color = effective_text_color, font = effective_font)
	}

	pop_box(mgr) // end outer

	// Track value for dirty detection and register for prev_rect update
	track_value(mgr, id, value)
	append(&mgr.widget_box_map, Widget_Box_Entry{id = id, box_index = outer_idx})

	return interaction
}

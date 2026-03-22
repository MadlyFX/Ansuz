package ogui

// --- Checkbox ---
// A toggle box with optional label text. Writes through a ^bool pointer.

CHECKBOX_BOX_SIZE :: f32(22)

THEME_CHECKBOX_BG          :: Color{50, 53, 60, 255}
THEME_CHECKBOX_BG_HOVER    :: Color{65, 68, 78, 255}
THEME_CHECKBOX_CHECKED     :: Color{80, 140, 220, 255}
THEME_CHECKBOX_CHECK_MARK  :: Color{255, 255, 255, 255}

checkbox :: proc(
	mgr:   ^Manager,
	text:  string,
	value: ^bool,
	scale: f32 = 1.0,
	loc    := #caller_location,
) -> Interaction {
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

	interaction := compute_interaction(mgr, id, prev_rect)

	// Toggle on click
	if .Clicked in interaction {
		value^ = !value^
	}

	// Smooth color transitions
	hover_t := get_hover_t(mgr, id, .Hovered in interaction)
	unchecked_bg := color_lerp(THEME_CHECKBOX_BG, THEME_CHECKBOX_BG_HOVER, hover_t)
	box_bg := color_lerp(unchecked_bg, THEME_CHECKBOX_CHECKED, get_press_t(mgr, id, value^))

	// Layout: horizontal flex with checkbox box + label
	row_size := [2]Size_Spec{SIZE_FIT, size_fixed(box_size + pad_v * 2)}
	if len(text) > 0 {
		text_dims := measure_text_builtin(text, font_scale)
		row_size[0] = size_fixed(box_size + gap + text_dims.x + pad_h * 2)
	} else {
		row_size[0] = size_fixed(box_size + pad_h * 2)
	}

	// Create an outer box for the whole checkbox widget (used for hit testing)
	outer_idx := push_box(mgr, id)
	outer := &mgr.boxes[outer_idx]
	outer.layout_kind = .Flex
	outer.layout_axis = .Horizontal
	outer.align       = .Center
	outer.gap         = gap
	outer.size        = row_size
	outer.padding     = {pad_v, pad_h, pad_v, pad_h}

	// The checkbox square
	check_idx := box(mgr,
		size     = {size_fixed(box_size), size_fixed(box_size)},
		bg_color = box_bg,
	)
	mgr.boxes[check_idx].border_width = max(1, 1 * scale)
	mgr.boxes[check_idx].border_color = THEME_BORDER
	mgr.boxes[check_idx].corner_radius = max(1, 3 * scale)

	// Checkmark: deferred draw
	if value^ {
		append(&mgr.deferred_draws, Deferred_Draw{
			box_index = check_idx,
			kind      = .Checkmark,
			scale     = scale,
		})
	}

	// Label text
	if len(text) > 0 {
		label(mgr, text, scale = font_scale)
	}

	pop_box(mgr) // end outer

	// Track value for dirty detection and register for prev_rect update
	track_value(mgr, id, value)
	append(&mgr.widget_box_map, Widget_Box_Entry{id = id, box_index = outer_idx})

	return interaction
}

package ansuz

// --- Dropdown ---
// A dropdown selector. Writes the selected index through a ^int pointer.
// The dropdown list renders as a popup overlay on top of other content.
// colors slots: bg = closed fill, fg = border, hover = hovered fill,
// press = open fill (focus is unused).

DROPDOWN_SCROLLBAR_WIDTH :: f32(6)

// Minimum height of a popup list row; rows grow with the font's line height.
POPUP_ITEM_MIN_HEIGHT :: f32(28)
POPUP_ITEM_PADDING    :: f32(8)

DROPDOWN_DEFAULT_SIZE :: [2]Size_Spec{Size_Spec{.Fixed, 200}, SIZE_FIT}

dropdown :: proc(
	mgr:      ^Manager,
	selected: ^int,
	options:  []string,
	size:     [2]Size_Spec = DROPDOWN_DEFAULT_SIZE,
	scale:    f32 = DEFAULT_FONT_SCALE,
	font:     Font_Handle = FONT_DEFAULT,
	colors: Widget_Color = Widget_Color{
		bg    = THEME_DROPDOWN_BG,
		fg    = THEME_BORDER,
		hover = THEME_DROPDOWN_BG_HOVER,
		press = THEME_DROPDOWN_BG_OPEN,
	},
	text_color: Color = THEME_TEXT,
	indicator_color: Color = THEME_DROPDOWN_ARROW,
	popup_color: Color = THEME_DROPDOWN_POPUP,
	popup_border_color: Color = THEME_BORDER,
	item_hover_color: Color = THEME_DROPDOWN_ITEM_HOVER,
	selected_color: Color = THEME_ACCENT,
	padding: [4]f32 = {4, 28, 4, 10}, // right padding reserves the arrow zone
	corner_radius: f32 = 4,
	max_popup_height: f32 = 0, // 0 leaves the popup uncapped; set to make long lists scroll
	disabled: bool = false,
	loc := #caller_location,
) -> Interaction {
	effective_font := resolve_font(mgr, font)
	item_height := max(POPUP_ITEM_MIN_HEIGHT, get_line_height(mgr, effective_font, scale) + POPUP_ITEM_PADDING)
	id := id_from_ptr_loc(&mgr.id_stack, selected, loc)

	// Look up previous frame's rect
	prev_rect := Rect{}
	if state, ok := mgr.widget_states[id]; ok {
		prev_rect = state.prev_rect
	}

	// Check if this dropdown is currently open
	is_open := !disabled && mgr.popup_owner == id

	// Interaction on the trigger button
	interaction: Interaction
	if disabled {
		release_interaction(mgr, id)
		if mgr.popup_owner == id {
			mgr.popup_owner = ID_NONE
		}
	} else {
		interaction = compute_interaction(mgr, id, prev_rect)
	}

	if .Clicked in interaction {
		// Toggle open/close
		if is_open {
			mgr.popup_owner = ID_NONE
			is_open = false
		} else {
			mgr.popup_owner = id
			mgr.dropdown_scroll_offsets[id] = 0
			is_open = true
		}
	}
	if id not_in mgr.dropdown_scroll_offsets {
		mgr.dropdown_scroll_offsets[id] = 0
	}

	popup_rect := dropdown_popup_rect(mgr, prev_rect, len(options), item_height, max_popup_height)
	content_h := f32(len(options)) * item_height
	if is_open && content_h > popup_rect.h && rect_contains(popup_rect, mgr.input.mouse_x, mgr.input.mouse_y) && mgr.input.mouse_scroll_y != 0 {
		if offset, ok := &mgr.dropdown_scroll_offsets[id]; ok {
			offset^ -= mgr.input.mouse_scroll_y * SCROLL_SPEED
			offset^ = clamp(offset^, 0, max(0, content_h - popup_rect.h))
			mgr.popup_consumed_scroll = true
		}
	}

	// Close on click outside (if open and something else got clicked)
	if is_open && mgr.input.mouse_left && !rect_contains(prev_rect, mgr.input.mouse_x, mgr.input.mouse_y) {
		// Check if click is inside the popup area
		if !rect_contains(popup_rect, mgr.input.mouse_x, mgr.input.mouse_y) {
			mgr.popup_owner = ID_NONE
			mgr.popup_block = true  // block widgets until mouse released
			is_open = false
		}
	}

	// Choose appearance
	bg: Color
	if is_open {
		bg = colors.press
	} else if .Hovered in interaction {
		bg = colors.hover
	} else {
		bg = colors.bg
	}
	border := colors.fg
	effective_text_color := text_color
	effective_indicator_color := indicator_color
	if disabled {
		border = disabled_color(border)
		effective_text_color = disabled_color(effective_text_color)
		effective_indicator_color = disabled_color(effective_indicator_color)
	}

	// Clamp selected
	if len(options) > 0 {
		selected^ = clamp(selected^, 0, len(options) - 1)
	}

	// Compute size — Fit height derives from the font like button/text_input
	actual_size := size
	if actual_size[1].kind == .Fit {
		actual_size[1] = size_fixed(get_line_height(mgr, effective_font, scale) + padding[0] + padding[2])
	}

	// Create the trigger button box
	idx := box(mgr, size = actual_size, bg_color = bg, loc = loc)
	mgr.boxes[idx].padding      = padding
	mgr.boxes[idx].border_width = 1
	mgr.boxes[idx].border_color = border
	mgr.boxes[idx].corner_radius = corner_radius

	// Display selected option text
	display_text := ""
	if len(options) > 0 && selected^ >= 0 && selected^ < len(options) {
		display_text = options[selected^]
	}
	append(&mgr.deferred_texts, Deferred_Text{
		box_index = idx,
		text      = display_text,
		color     = effective_text_color,
		scale     = scale,
		font      = effective_font,
		center_h  = false,
		center_v  = true,
		clip      = true,
	})

	// Defer the arrow indicator (scaled with the widget's font scale)
	append(&mgr.deferred_draws, Deferred_Draw{
		box_index = idx,
		kind      = .Dropdown_Arrow,
		scale     = max(1, scale / DEFAULT_FONT_SCALE),
		dropdown  = Deferred_Dropdown_Data{
			is_open = is_open,
			color   = effective_indicator_color,
		},
	})

	// Track value for dirty detection and register for prev_rect update
	track_value(mgr, id, selected)
	append(&mgr.widget_box_map, Widget_Box_Entry{id = id, box_index = idx})

	// If open, register the popup for overlay rendering
	if is_open && len(options) > 0 {
		// Popup drawing happens after the caller has returned. The supplied slice
		// may be backed by a caller-local array, so retain its descriptors in the
		// frame arena instead of leaving a dangling stack reference.
		popup_options := make([]string, len(options), mgr.frame_allocator)
		copy(popup_options, options)
		append(&mgr.popup_draws, Popup_Draw{
			owner_box_index = idx,
			kind            = .Dropdown_List,
			dropdown_list   = Popup_Dropdown_Data{
				options            = popup_options,
				selected           = selected,
				owner_id           = id,
				font               = effective_font,
				scale              = scale,
				item_height        = item_height,
				text_color         = text_color,
				popup_color        = popup_color,
				popup_border_color = popup_border_color,
				item_hover_color   = item_hover_color,
				selected_color     = selected_color,
				max_popup_height   = max_popup_height,
				corner_radius      = corner_radius,
			},
		})
	}

	return interaction
}

dropdown_popup_rect :: proc(mgr: ^Manager, anchor: Rect, option_count: int, item_height, max_popup_height: f32) -> Rect {
	content_h := f32(option_count) * item_height
	popup_h := content_h
	if max_popup_height > 0 {
		popup_h = min(popup_h, max_popup_height)
	}

	below_y := anchor.y + anchor.h
	space_below := max(f32(0), f32(mgr.backend.height) - below_y)
	space_above := max(f32(0), anchor.y)
	y := below_y
	if popup_h > space_below && space_above > space_below {
		popup_h = min(popup_h, space_above)
		y = anchor.y - popup_h
	} else {
		popup_h = min(popup_h, space_below)
	}
	return Rect{anchor.x, y, anchor.w, popup_h}
}

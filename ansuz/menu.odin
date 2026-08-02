package ansuz

// --- Menu Button ---
// A button that opens an action list popup, right-aligned under the trigger.
// Writes the picked option index through `selected` (reset it after handling).
// colors slots: bg = resting fill, fg = border, hover = hovered fill,
// press = open fill, focus = unused.

MENU_POPUP_MIN_TEXT_MARGIN :: f32(20)

menu_button :: proc(
	mgr:      ^Manager,
	text:     string,
	selected: ^int,
	options:  []string,
	size:     [2]Size_Spec = SIZE_FIT_FIT,
	scale:    f32 = DEFAULT_FONT_SCALE,
	font:     Font_Handle = FONT_DEFAULT,
	colors: Widget_Color = Widget_Color{
		bg    = THEME_BG_BUTTON,
		fg    = THEME_BORDER,
		hover = THEME_BG_BUTTON_HOVER,
		press = THEME_BG_BUTTON_ACTIVE,
		focus = THEME_BG_BUTTON_HOVER,
	},
	text_color: Color = THEME_TEXT,
	popup_color: Color = THEME_MENU_POPUP,
	popup_border_color: Color = THEME_BORDER,
	item_hover_color: Color = THEME_MENU_ITEM_HOVER,
	padding: [4]f32 = {4, 12, 4, 12},
	corner_radius: f32 = 4,
	disabled: bool = false,
	loc := #caller_location,
) -> Interaction {
	effective_font := resolve_font(mgr, font)
	item_height := max(POPUP_ITEM_MIN_HEIGHT, get_line_height(mgr, effective_font, scale) + POPUP_ITEM_PADDING)
	id := id_from_ptr_loc(&mgr.id_stack, selected, loc)

	prev_rect := Rect{}
	if state, ok := mgr.widget_states[id]; ok {
		prev_rect = state.prev_rect
	}

	is_open := !disabled && mgr.popup_owner == id
	interaction: Interaction
	if disabled {
		release_interaction(mgr, id)
		if mgr.popup_owner == id {
			mgr.popup_owner = ID_NONE
		}
	} else {
		interaction = compute_interaction(mgr, id, prev_rect)
	}

	popup_w: f32 = prev_rect.w
	for opt in options {
		dims := measure_text(mgr, opt, effective_font, scale)
		popup_w = max(popup_w, dims.x + MENU_POPUP_MIN_TEXT_MARGIN)
	}

	if .Clicked in interaction {
		if is_open {
			mgr.popup_owner = ID_NONE
			is_open = false
		} else {
			mgr.popup_owner = id
			is_open = true
		}
	}

	if is_open && mgr.input.mouse_left && !rect_contains(prev_rect, mgr.input.mouse_x, mgr.input.mouse_y) {
		popup_rect := Rect{
			prev_rect.x + prev_rect.w - popup_w,
			prev_rect.y + prev_rect.h,
			popup_w,
			f32(len(options)) * item_height,
		}
		if !rect_contains(popup_rect, mgr.input.mouse_x, mgr.input.mouse_y) {
			mgr.popup_owner = ID_NONE
			mgr.popup_block = true
			is_open = false
		}
	}

	bg := colors.press if is_open else (colors.hover if .Hovered in interaction else colors.bg)
	border := colors.fg
	effective_text_color := text_color
	if disabled {
		border = disabled_color(border)
		effective_text_color = disabled_color(effective_text_color)
	}

	// Compute size from text if Fit (matches button behavior)
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
	mgr.boxes[idx].corner_radius = corner_radius

	append(&mgr.deferred_texts, Deferred_Text{
		box_index = idx,
		text      = text,
		color     = effective_text_color,
		scale     = scale,
		font      = effective_font,
		center_h  = true,
		center_v  = true,
	})

	get_or_create_widget_state(mgr, id)
	append(&mgr.widget_box_map, Widget_Box_Entry{id = id, box_index = idx})

	if is_open && len(options) > 0 {
		// Popup drawing happens after the caller has returned. The supplied slice
		// may be backed by a caller-local array, so retain its descriptors in the
		// frame arena instead of leaving a dangling stack reference.
		popup_options := make([]string, len(options), mgr.frame_allocator)
		copy(popup_options, options)
		append(&mgr.popup_draws, Popup_Draw{
			owner_box_index = idx,
			kind            = .Menu_List,
			menu_list        = Popup_Menu_Data{
				options            = popup_options,
				selected           = selected,
				owner_id           = id,
				font               = effective_font,
				scale              = scale,
				item_height        = item_height,
				width              = popup_w,
				text_color         = text_color,
				popup_color        = popup_color,
				popup_border_color = popup_border_color,
				item_hover_color   = item_hover_color,
				corner_radius      = corner_radius,
			},
		})
	}

	return interaction
}

HAMBURGER_ICON_SIZE :: [2]Size_Spec{Size_Spec{.Fixed, 18}, Size_Spec{.Fixed, 18}}

// Three-line "hamburger" menu icon. Draw-only, like disclosure_icon; layer it
// over a button in a stack to build a clickable menu toggle.
hamburger_icon :: proc(
	mgr:   ^Manager,
	color: Color = THEME_TEXT,
	size:  [2]Size_Spec = HAMBURGER_ICON_SIZE,
	scale: f32 = 1,
	loc    := #caller_location,
) -> int {
	idx := box(mgr, size = size, loc = loc)
	append(
		&mgr.deferred_draws,
		Deferred_Draw{
			box_index = idx,
			kind = .Hamburger_Icon,
			scale = scale,
			hamburger = Deferred_Hamburger_Data{color = color},
		},
	)
	return idx
}

package ansuz

THEME_MENU_POPUP      :: Color{45, 48, 55, 245}
THEME_MENU_ITEM_HOVER :: Color{80, 140, 220, 255}

menu_button :: proc(
	mgr:      ^Manager,
	text:     string,
	selected: ^int,
	options:  []string,
	size:     [2]Size_Spec = {{.Fixed, 34}, {.Fixed, 30}},
	scale:    f32 = DEFAULT_FONT_SCALE,
	font:     Font_Handle = FONT_DEFAULT,
	color: Widget_Color = Widget_Color{
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
	loc := #caller_location,
) -> Interaction {
	effective_font := resolve_font(mgr, font)
	item_height := max(28, get_line_height(mgr, effective_font, scale) + 8)
	id := id_from_ptr_loc(&mgr.id_stack, selected, loc)

	prev_rect := Rect{}
	if state, ok := mgr.widget_states[id]; ok {
		prev_rect = state.prev_rect
	}

	is_open := mgr.popup_owner == id
	interaction := compute_interaction(mgr, id, prev_rect)

	popup_w: f32 = prev_rect.w
	for opt in options {
		dims := measure_text(mgr, opt, effective_font, scale)
		popup_w = max(popup_w, dims.x + 20)
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

	bg := color.press if is_open else (color.hover if .Hovered in interaction else color.bg)

	idx := box(mgr, size = size, bg_color = bg, loc = loc)
	mgr.boxes[idx].padding = {4, 8, 4, 8}
	mgr.boxes[idx].border_width = 1
	mgr.boxes[idx].border_color = color.fg
	mgr.boxes[idx].corner_radius = 4

	append(&mgr.deferred_texts, Deferred_Text{
		box_index = idx,
		text      = text,
		color     = text_color,
		scale     = scale,
		font      = effective_font,
		center_h  = true,
		center_v  = true,
	})

	get_or_create_widget_state(mgr, id)
	append(&mgr.widget_box_map, Widget_Box_Entry{id = id, box_index = idx})

	if is_open && len(options) > 0 {
		append(&mgr.popup_draws, Popup_Draw{
			owner_box_index = idx,
			kind            = .Menu_List,
			menu_list        = Popup_Menu_Data{
				options            = options,
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
			},
		})
	}

	return interaction
}

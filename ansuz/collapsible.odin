package ansuz

// --- Collapsible Header ---
// A header row that expands/collapses a section, binding through a ^bool.
// Returns (open, interaction) like tree_node_begin, so sections read as:
//
//     open, _ := collapsible_header(mgr, "Details", &expanded)
//     if open { ...section content... }
//
// colors slots: bg = collapsed fill, hover/press = state fills,
// focus = expanded fill (fg is unused; borders come from border_color params).

COLLAPSIBLE_HEADER_HEIGHT :: f32(34)
COLLAPSIBLE_HEADER_ICON_SIZE :: f32(18)
COLLAPSIBLE_HEADER_SIZE :: [2]Size_Spec{SIZE_GROW, Size_Spec{.Fixed, COLLAPSIBLE_HEADER_HEIGHT}}
COLLAPSIBLE_ICON_SIZE :: [2]Size_Spec{
	Size_Spec{.Fixed, COLLAPSIBLE_HEADER_ICON_SIZE},
	Size_Spec{.Fixed, COLLAPSIBLE_HEADER_ICON_SIZE},
}

collapsible_header :: proc(
	mgr: ^Manager,
	text: string,
	expanded: ^bool,
	size: [2]Size_Spec = COLLAPSIBLE_HEADER_SIZE,
	padding: [4]f32 = {2, 4, 2, 4},
	gap: f32 = 4,
	colors: Widget_Color = Widget_Color{
		bg    = THEME_COLLAPSIBLE_BG,
		hover = THEME_COLLAPSIBLE_BG_HOVER,
		press = THEME_COLLAPSIBLE_BG_PRESS,
		focus = THEME_COLLAPSIBLE_BG_EXPANDED,
	},
	text_color: Color = THEME_TEXT_DIM,
	expanded_text_color: Color = THEME_TEXT,
	icon_color: Color = THEME_TEXT_DIM,
	expanded_icon_color: Color = THEME_TEXT,
	border_color: Color = THEME_BORDER,
	expanded_border_color: Color = THEME_BORDER,
	icon_size: f32 = COLLAPSIBLE_HEADER_ICON_SIZE,
	corner_radius: f32 = 2,
	font: Font_Handle = FONT_DEFAULT,
	scale: f32 = DEFAULT_FONT_SCALE,
	clip: bool = true,
	value_is_collapsed: bool = false,
	toggle_on_icon_only: bool = false,
	toggled: ^bool = nil,
	loc := #caller_location,
) -> (open: bool, interaction: Interaction) {
	effective_font := resolve_font(mgr, font)
	id := id_from_ptr_loc(&mgr.id_stack, expanded, loc)
	icon_id := Widget_ID(hash_string("disclosure-icon", u64(id)))

	if toggled != nil {
		toggled^ = false
	}

	icon_interaction: Interaction
	if toggle_on_icon_only {
		icon_prev_rect := Rect{}
		if state, ok := mgr.widget_states[icon_id]; ok {
			icon_prev_rect = state.prev_rect
		}
		icon_interaction = compute_interaction(mgr, icon_id, icon_prev_rect)
	}

	prev_rect := Rect{}
	if state, ok := mgr.widget_states[id]; ok {
		prev_rect = state.prev_rect
	}

	interaction = compute_interaction(mgr, id, prev_rect)
	if (toggle_on_icon_only && .Clicked in icon_interaction) || (!toggle_on_icon_only && .Clicked in interaction) {
		expanded^ = !expanded^
		if toggled != nil {
			toggled^ = true
		}
	}
	is_expanded := !expanded^ if value_is_collapsed else expanded^

	hover_t := get_hover_t(mgr, id, .Hovered in interaction)
	press_t := get_press_t(mgr, id, .Pressed in interaction)
	focus_t := get_focus_t(mgr, id, .Focused in interaction)
	base_bg := colors.focus if is_expanded else colors.bg
	bg := blend_interaction_color(
		base_bg,
		colors.hover,
		colors.press,
		colors.focus,
		hover_t,
		press_t,
		focus_t,
	)

	line_h := get_line_height(mgr, effective_font, scale)
	icon_box_size := max(icon_size, line_h)
	actual_size := size
	if actual_size[0].kind == .Fit {
		text_dims := measure_text(mgr, text, effective_font, scale)
		actual_size[0] = size_fixed(icon_box_size + gap + text_dims.x + padding[1] + padding[3])
	}
	if actual_size[1].kind == .Fit {
		actual_size[1] = size_fixed(max(icon_box_size, line_h) + padding[0] + padding[2])
	}

	idx := push_box(mgr, id)
	header := &mgr.boxes[idx]
	header.layout_kind = .Flex
	header.layout_axis = .Horizontal
	header.align = .Center
	header.gap = gap
	header.size = actual_size
	header.padding = padding
	header.bg_color = bg
	header.border_width = 1
	header.border_color = expanded_border_color if is_expanded else border_color
	header.corner_radius = corner_radius

	current_icon_color := expanded_icon_color if is_expanded else icon_color
	icon_idx := disclosure_icon_box(
		mgr,
		icon_id,
		is_expanded,
		color = current_icon_color,
		size = {size_fixed(icon_box_size), size_fixed(icon_box_size)},
		scale = max(1, scale / DEFAULT_FONT_SCALE),
	)
	if toggle_on_icon_only {
		get_or_create_widget_state(mgr, icon_id)
		append(&mgr.widget_box_map, Widget_Box_Entry{id = icon_id, box_index = icon_idx})
	}

	label(
		mgr,
		text,
		color = expanded_text_color if is_expanded else text_color,
		font = effective_font,
		scale = scale,
		size = {SIZE_GROW, SIZE_FIT},
		clip = clip,
	)

	pop_box(mgr)

	track_value(mgr, id, expanded)
	append(&mgr.widget_box_map, Widget_Box_Entry{id = id, box_index = idx})

	open = is_expanded
	return
}

disclosure_icon :: proc(
	mgr: ^Manager,
	expanded: bool,
	color: Color = THEME_TEXT_DIM,
	size: [2]Size_Spec = COLLAPSIBLE_ICON_SIZE,
	scale: f32 = 1,
	loc := #caller_location,
) -> int {
	id := id_from_loc(&mgr.id_stack, loc)
	return disclosure_icon_box(mgr, id, expanded, color, size, scale)
}

disclosure_icon_box :: proc(
	mgr: ^Manager,
	id: Widget_ID,
	expanded: bool,
	color: Color,
	size: [2]Size_Spec,
	scale: f32,
) -> int {
	idx := push_box(mgr, id)
	b := &mgr.boxes[idx]
	b.size = size
	pop_box(mgr)
	append(
		&mgr.deferred_draws,
		Deferred_Draw{
			box_index = idx,
			kind = .Disclosure_Icon,
			scale = scale,
			disclosure = Deferred_Disclosure_Data{
				expanded = expanded,
				color = color,
			},
		},
	)
	return idx
}

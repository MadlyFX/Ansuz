package ogui

// --- Dropdown ---
// A dropdown selector. Writes the selected index through a ^int pointer.
// The dropdown list renders as a popup overlay on top of other content.

THEME_DROPDOWN_BG        :: Color{55, 58, 65, 255}
THEME_DROPDOWN_BG_HOVER  :: Color{70, 73, 83, 255}
THEME_DROPDOWN_BG_OPEN   :: Color{50, 53, 58, 255}
THEME_DROPDOWN_ITEM_HOVER :: Color{80, 140, 220, 255}
THEME_DROPDOWN_ARROW      :: Color{180, 180, 185, 255}

dropdown :: proc(
	mgr:      ^Manager,
	selected: ^int,
	options:  []string,
	size:     [2]Size_Spec = FIXED_200_30,
	loc       := #caller_location,
) -> Interaction {
	id := id_from_ptr_loc(&mgr.id_stack, selected, loc)

	// Look up previous frame's rect
	prev_rect := Rect{}
	if state, ok := mgr.widget_states[id]; ok {
		prev_rect = state.prev_rect
	}

	// Check if this dropdown is currently open
	is_open := mgr.popup_owner == id

	// Interaction on the trigger button
	interaction := compute_interaction(mgr, id, prev_rect)

	if .Clicked in interaction {
		// Toggle open/close
		if is_open {
			mgr.popup_owner = ID_NONE
			is_open = false
		} else {
			mgr.popup_owner = id
			is_open = true
		}
	}

	// Close on click outside (if open and something else got clicked)
	if is_open && mgr.input.mouse_left && !rect_contains(prev_rect, mgr.input.mouse_x, mgr.input.mouse_y) {
		// Check if click is inside the popup area
		popup_rect := Rect{
			prev_rect.x,
			prev_rect.y + prev_rect.h,
			prev_rect.w,
			f32(len(options)) * 28,
		}
		if !rect_contains(popup_rect, mgr.input.mouse_x, mgr.input.mouse_y) {
			mgr.popup_owner = ID_NONE
			is_open = false
		}
	}

	// Choose appearance
	bg: Color
	if is_open {
		bg = THEME_DROPDOWN_BG_OPEN
	} else if .Hovered in interaction {
		bg = THEME_DROPDOWN_BG_HOVER
	} else {
		bg = THEME_DROPDOWN_BG
	}

	// Clamp selected
	if len(options) > 0 {
		selected^ = clamp(selected^, 0, len(options) - 1)
	}

	// Create the trigger button box
	idx := box(mgr, size = size, bg_color = bg, loc = loc)
	mgr.boxes[idx].padding      = {4, 28, 4, 10} // right padding for arrow
	mgr.boxes[idx].border_width = 1
	mgr.boxes[idx].border_color = THEME_BORDER
	mgr.boxes[idx].corner_radius = 4

	// Display selected option text
	display_text := ""
	if len(options) > 0 && selected^ >= 0 && selected^ < len(options) {
		display_text = options[selected^]
	}
	append(&mgr.deferred_texts, Deferred_Text{
		box_index = idx,
		text      = display_text,
		color     = THEME_TEXT,
		scale     = DEFAULT_FONT_SCALE,
		center_h  = false,
		center_v  = true,
	})

	// Defer the arrow indicator
	append(&mgr.deferred_draws, Deferred_Draw{
		box_index = idx,
		kind      = .Dropdown_Arrow,
		dropdown  = Deferred_Dropdown_Data{
			is_open = is_open,
		},
	})

	// Track value for dirty detection and register for prev_rect update
	track_value(mgr, id, selected)
	append(&mgr.widget_box_map, Widget_Box_Entry{id = id, box_index = idx})

	// If open, register the popup for overlay rendering
	if is_open && len(options) > 0 {
		append(&mgr.popup_draws, Popup_Draw{
			owner_box_index = idx,
			kind            = .Dropdown_List,
			dropdown_list   = Popup_Dropdown_Data{
				options       = options,
				selected      = selected,
				owner_id      = id,
			},
		})
	}

	return interaction
}

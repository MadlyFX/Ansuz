package ansuz

// --- Scrollbox Widget ---
// A scrollable container. Children are clipped to the viewport and
// scrolled via mouse wheel. A scrollbar indicator is drawn when content
// overflows the visible area.
//
// Usage:
//   scroll_begin(&mgr, size = {SIZE_GROW, size_fixed(300)})
//     label(&mgr, "item 1")
//     label(&mgr, "item 2")
//     // ... many items
//   scroll_end(&mgr)

SCROLL_SPEED :: f32(30)

THEME_SCROLLBAR_BG    :: Color{50, 53, 60, 100}
THEME_SCROLLBAR_THUMB :: Color{120, 123, 130, 180}
SCROLLBAR_WIDTH       :: f32(6)

Scroll_State :: struct {
	axis:     Axis,   // scroll direction (follows the container's layout axis)
	offset:   f32,    // pixels scrolled along the scroll axis (from top/left)
	content:  f32,    // total content extent along the scroll axis (measured from previous frame)
	viewport: f32,    // visible extent along the scroll axis (measured from previous frame)
}

scroll_begin :: proc(
	mgr:      ^Manager,
	axis:     Axis       = .Vertical,
	gap:      f32        = 0,
	size:     [2]Size_Spec = GROW_GROW,
	padding:  [4]f32     = {},
	bg_color: Color      = COLOR_TRANSPARENT,
	loc       := #caller_location,
) -> ^Scroll_State {
	id := id_from_loc(&mgr.id_stack, loc)

	// Look up previous frame's rect for mouse wheel hit test
	prev_rect := Rect{}
	if state, ok := mgr.widget_states[id]; ok {
		prev_rect = state.prev_rect
	}

	// Get or create scroll state
	if id not_in mgr.scroll_states {
		mgr.scroll_states[id] = Scroll_State{}
	}
	ss := &mgr.scroll_states[id]
	ss.axis = axis

	// Track deepest scroll container under mouse for wheel routing.
	// Since children are visited after parents, the last writer is the deepest.
	if rect_contains(prev_rect, mgr.input.mouse_x, mgr.input.mouse_y) {
		mgr.scroll_wheel_candidate = id
	}

	// Create the scrollbox container
	idx := push_box(mgr, id)
	b := &mgr.boxes[idx]
	b.layout_kind  = .Flex
	b.layout_axis  = axis
	b.gap          = gap
	b.size         = size
	b.padding      = padding
	b.bg_color     = bg_color
	b.flags        = {.Clip_Children}
	b.scroll_offset = scroll_offset_for_axis(axis, ss.offset)

	// Register for prev_rect update and hit testing
	get_or_create_widget_state(mgr, id)
	append(&mgr.widget_box_map, Widget_Box_Entry{id = id, box_index = idx})

	// Queue scrollbar deferred draw (uses previous frame's measurements)
	if ss.content > ss.viewport && ss.viewport > 0 {
		append(&mgr.deferred_draws, Deferred_Draw{
			box_index = idx,
			kind      = .Scrollbar,
			scrollbar = Deferred_Scrollbar_Data{
				axis     = axis,
				offset   = ss.offset,
				content  = ss.content,
				viewport = ss.viewport,
			},
		})
	}
	return ss
}

scroll_end :: proc(mgr: ^Manager) {
	pop_box(mgr)
}

// Convert a scalar scroll offset along `axis` into the Vec2 shift applied to
// the container's children. Content is pushed up (vertical) or left (horizontal).
scroll_offset_for_axis :: proc(axis: Axis, offset: f32) -> Vec2 {
	if axis == .Horizontal {
		return {-offset, 0}
	}
	return {0, -offset}
}

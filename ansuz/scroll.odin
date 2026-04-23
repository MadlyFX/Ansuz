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
	offset_y:   f32,    // pixels scrolled from top
	content_h:  f32,    // total content height (measured from previous frame)
	viewport_h: f32,    // visible height (measured from previous frame)
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
	b.scroll_offset = {0, -ss.offset_y}

	// Register for prev_rect update and hit testing
	get_or_create_widget_state(mgr, id)
	append(&mgr.widget_box_map, Widget_Box_Entry{id = id, box_index = idx})

	// Queue scrollbar deferred draw (uses previous frame's measurements)
	if ss.content_h > ss.viewport_h && ss.viewport_h > 0 {
		append(&mgr.deferred_draws, Deferred_Draw{
			box_index = idx,
			kind      = .Scrollbar,
			scrollbar = Deferred_Scrollbar_Data{
				offset_y   = ss.offset_y,
				content_h  = ss.content_h,
				viewport_h = ss.viewport_h,
			},
		})
	}
	return ss
}

scroll_end :: proc(mgr: ^Manager) {
	pop_box(mgr)
}

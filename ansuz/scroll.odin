package ansuz

// --- Scrollbox Widget ---
// A scrollable container. Children are clipped to the viewport and
// scrolled via mouse wheel or by dragging the scrollbar. A scrollbar is drawn
// when content overflows the visible area.
//
// Usage:
//   scroll_begin(&mgr, size = {SIZE_GROW, size_fixed(300)})
//     label(&mgr, "item 1")
//     label(&mgr, "item 2")
//     // ... many items
//   scroll_end(&mgr)

SCROLL_SPEED :: f32(30)
SCROLLBAR_WIDTH :: f32(6)
// Shortest the thumb may get, so a very long page still leaves something to grab.
SCROLLBAR_MIN_THUMB :: f32(20)
// How far either side of the bar still counts as pressing it. A 6px target is
// hard to hit; the slack reaches into the container's padding, where there is
// nothing else to press.
SCROLLBAR_GRAB_PAD :: f32(5)

Scroll_State :: struct {
	axis:       Axis,
	offset_x:   f32,    // pixels scrolled from left
	offset_y:   f32,    // pixels scrolled from top
	content_w:  f32,    // total content width (measured from previous frame)
	content_h:  f32,    // total content height (measured from previous frame)
	viewport_w: f32,    // visible width (measured from previous frame)
	viewport_h: f32,    // visible height (measured from previous frame)
	// Thumb drag. grab is where inside the thumb the press landed, so the thumb
	// stays under the pointer instead of jumping its middle to it.
	dragging:   bool,
	grab:       f32,
}

// scrollbar_rects returns the bar's track and thumb for a container occupying
// `rect`. Hit testing and drawing both go through it, so the bar a press lands
// on is always the bar that was drawn.
scrollbar_rects :: proc(
	rect: Rect,
	axis: Axis,
	offset, content, viewport, width, inset: f32,
) -> (track, thumb: Rect) {
	max_scroll := content - viewport
	t := clamp(offset / max_scroll, 0, 1) if max_scroll > 0 else 0
	if axis == .Horizontal {
		track = Rect{rect.x + inset, rect.y + rect.h - width - inset, rect.w - inset * 2, width}
		length := min(track.w, max(SCROLLBAR_MIN_THUMB, track.w * (viewport / content)))
		thumb = Rect{track.x + (track.w - length) * t, track.y, length, width}
		return
	}
	track = Rect{rect.x + rect.w - width - inset, rect.y + inset, width, rect.h - inset * 2}
	length := min(track.h, max(SCROLLBAR_MIN_THUMB, track.h * (viewport / content)))
	thumb = Rect{track.x, track.y + (track.h - length) * t, width, length}
	return
}

scroll_begin :: proc(
	mgr:      ^Manager,
	axis:     Axis       = .Vertical,
	gap:      f32        = 0,
	size:     [2]Size_Spec = GROW_GROW,
	padding:  [4]f32     = {},
	bg_color: Color      = COLOR_TRANSPARENT,
	scrollbar_color:              Color = THEME_SCROLLBAR_BG,
	scrollbar_thumb_color:        Color = THEME_SCROLLBAR_THUMB,
	scrollbar_thumb_hover_color:  Color = THEME_SCROLLBAR_THUMB_HOVER,
	scrollbar_thumb_active_color: Color = THEME_SCROLLBAR_THUMB_ACTIVE,
	scrollbar_width:              f32   = SCROLLBAR_WIDTH,
	scrollbar_inset:              f32   = 2,
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

	// The scrollbar, hit tested against last frame's rect and measurements — the
	// same ones it was drawn from. Done before the container box is pushed so a
	// drag moves the content on the very frame of the press rather than the next.
	horizontal := axis == .Horizontal
	content := ss.content_w if horizontal else ss.content_h
	viewport := ss.viewport_w if horizontal else ss.viewport_h
	overflowing := content > viewport && viewport > 0
	bar_hovered := false
	if overflowing && prev_rect.w > 0 && prev_rect.h > 0 {
		offset := ss.offset_x if horizontal else ss.offset_y
		track, thumb := scrollbar_rects(
			prev_rect, axis, offset, content, viewport, scrollbar_width, scrollbar_inset,
		)
		grab_area := track
		if horizontal {
			grab_area.y -= SCROLLBAR_GRAB_PAD
			grab_area.h += SCROLLBAR_GRAB_PAD * 2
		} else {
			grab_area.x -= SCROLLBAR_GRAB_PAD
			grab_area.w += SCROLLBAR_GRAB_PAD * 2
		}
		bar_hovered = rect_contains(grab_area, mgr.input.mouse_x, mgr.input.mouse_y)

		// A modal, an open popup, or a popup that just closed under a still-held
		// button owns the pointer — a press on it must not reach a bar drawn
		// underneath. compute_interaction turns every other widget away for the
		// same reasons; the bar is hit tested here by hand and would otherwise be
		// the one control that ignores them. Only the grab is gated: a drag
		// already in flight keeps the pointer until it is let go.
		blocked := mgr.popup_block ||
		           (mgr.popup_owner != ID_NONE && mgr.popup_owner != id) ||
		           (mgr.modal_owner != ID_NONE &&
			            mgr.modal_owner != id &&
			            !id_stack_contains(&mgr.id_stack, mgr.modal_owner))
		pointer := mgr.input.mouse_x if horizontal else mgr.input.mouse_y
		thumb_start := thumb.x if horizontal else thumb.y
		thumb_length := thumb.w if horizontal else thumb.h
		if mgr.input.mouse_left_pressed && bar_hovered && !blocked {
			// On the thumb, keep hold of the spot that was grabbed. Off it, put the
			// thumb's middle under the pointer — so a press on the empty track jumps
			// there and then keeps dragging, rather than paging by a fixed step.
			on_thumb := pointer >= thumb_start && pointer <= thumb_start + thumb_length
			ss.grab = pointer - thumb_start if on_thumb else thumb_length / 2
			ss.dragging = true
		}
		if ss.dragging && mgr.input.mouse_left {
			track_start := track.x if horizontal else track.y
			track_length := track.w if horizontal else track.h
			travel := track_length - thumb_length
			scrolled: f32 = 0
			if travel > 0 {
				scrolled = clamp((pointer - ss.grab - track_start) / travel, 0, 1) * (content - viewport)
			}
			if horizontal {
				ss.offset_x = scrolled
			} else {
				ss.offset_y = scrolled
			}
		}
	}
	if !mgr.input.mouse_left || !overflowing {
		ss.dragging = false
	}
	if ss.dragging {
		mgr.scrollbar_drag = true
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
	b.scroll_offset = {-ss.offset_x, 0} if axis == .Horizontal else {0, -ss.offset_y}

	// Register for prev_rect update and hit testing
	get_or_create_widget_state(mgr, id)
	append(&mgr.widget_box_map, Widget_Box_Entry{id = id, box_index = idx})

	// Queue scrollbar deferred draw (uses previous frame's measurements)
	if overflowing {
		append(&mgr.deferred_draws, Deferred_Draw{
			box_index = idx,
			kind      = .Scrollbar,
			scrollbar = Deferred_Scrollbar_Data{
				axis               = axis,
				offset             = ss.offset_x if horizontal else ss.offset_y,
				content            = content,
				viewport           = viewport,
				width              = scrollbar_width,
				inset              = scrollbar_inset,
				track_color        = scrollbar_color,
				thumb_color        = scrollbar_thumb_color,
				thumb_hover_color  = scrollbar_thumb_hover_color,
				thumb_active_color = scrollbar_thumb_active_color,
				hovered            = bar_hovered,
				active             = ss.dragging,
			},
		})
	}
	return ss
}

scroll_end :: proc(mgr: ^Manager) {
	pop_box(mgr)
}

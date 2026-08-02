package ansuz


// --- Reactive Value Tracking ---
// The manager internally tracks values passed to widgets via pointers.
// Each frame, the current value is compared to the previous snapshot for
// dirty detection — embedded hosts can skip redrawing unchanged frames.
//
// The user API stays clean — just pass &my_variable. The tracking is automatic.

// Transmute a value's bytes to u64 for storage. Works for types <= 8 bytes.
@(private)
value_to_bits_f32 :: proc(v: f32) -> u64 {
	return u64(transmute(u32)v)
}

@(private)
value_to_bits_bool :: proc(v: bool) -> u64 {
	return 1 if v else 0
}

@(private)
value_to_bits_int :: proc(v: int) -> u64 {
	return cast(u64)i64(v)
}

// Track an f32 value for a widget. Call this from widget procs.
// Compares current value to stored snapshot, sets dirty flag.
track_value_f32 :: proc(mgr: ^Manager, id: Widget_ID, value: ^f32) {
	ws := get_or_create_widget_state(mgr, id)
	bits := value_to_bits_f32(value^)

	if ws.has_value {
		ws.dirty = bits != ws.prev_value_bits
	} else {
		ws.dirty = true  // First frame is always dirty
		ws.has_value = true
	}

	ws.prev_value_bits = bits
}

// Track a bool value for a widget.
track_value_bool :: proc(mgr: ^Manager, id: Widget_ID, value: ^bool) {
	ws := get_or_create_widget_state(mgr, id)
	bits := value_to_bits_bool(value^)

	if ws.has_value {
		ws.dirty = bits != ws.prev_value_bits
	} else {
		ws.dirty = true
		ws.has_value = true
	}

	ws.prev_value_bits = bits
}

// Track an int value for a widget.
track_value_int :: proc(mgr: ^Manager, id: Widget_ID, value: ^int) {
	ws := get_or_create_widget_state(mgr, id)
	bits := value_to_bits_int(value^)

	if ws.has_value {
		ws.dirty = bits != ws.prev_value_bits
	} else {
		ws.dirty = true
		ws.has_value = true
	}

	ws.prev_value_bits = bits
}

// Overloaded track_value for convenience
track_value :: proc{track_value_f32, track_value_bool, track_value_int}

// --- User-Facing Query API ---

// Check if a widget's tracked value changed this frame.
// Pass the same pointer you passed to the widget.
value_dirty :: proc(mgr: ^Manager, ptr: rawptr, loc := #caller_location) -> bool {
	id := id_from_ptr_loc(&mgr.id_stack, ptr, loc)
	if ws, ok := mgr.widget_states[id]; ok {
		return ws.dirty
	}
	return false
}

// Check if any tracked value changed this frame (useful for global dirty check).
any_value_dirty :: proc(mgr: ^Manager) -> bool {
	for _, state in mgr.widget_states {
		if state.dirty {
			return true
		}
	}
	return false
}

// widget_prev_rect returns a widget's rect as resolved on the previous frame,
// or ok=false if the widget was not present last frame. Useful for hit testing
// a container (composer, scrollbox) against a pointer position from the host.
widget_prev_rect :: proc(mgr: ^Manager, id: Widget_ID) -> (Rect, bool) {
	if ws, ok := mgr.widget_states[id]; ok {
		return ws.prev_rect, true
	}
	return Rect{}, false
}

// track_box_rect registers `box_idx` under `id` so that, after layout, its
// resolved rect is recorded and can be read next frame via widget_prev_rect.
// Non-interactive boxes (e.g. labels) are not tracked by default; call this to
// give one prev-frame bounds, which immediate-mode callers need for width-
// dependent decisions such as wrapping text to the column's actual width.
track_box_rect :: proc(mgr: ^Manager, id: Widget_ID, box_idx: int) {
	get_or_create_widget_state(mgr, id)
	append(&mgr.widget_box_map, Widget_Box_Entry{id = id, box_index = box_idx})
}

// current_box_id returns the id of the box currently on top of the build stack,
// i.e. the container most recently opened with a *_begin call. Pair it with
// widget_prev_rect to read that container's last-frame bounds.
current_box_id :: proc(mgr: ^Manager) -> Widget_ID {
	if len(mgr.box_stack) == 0 {
		return ID_NONE
	}
	return mgr.boxes[mgr.box_stack[len(mgr.box_stack) - 1]].id
}

// last_widget_id returns the id of the most recently emitted interactive widget
// (button, checkbox, text input, …), or ID_NONE if none has been emitted yet
// this frame. Read it right after a widget call, then pass it to widget_prev_rect
// to recover that widget's last-frame bounds (leaf widgets, unlike containers,
// are not reachable through current_box_id).
last_widget_id :: proc(mgr: ^Manager) -> Widget_ID {
	if len(mgr.widget_box_map) == 0 {
		return ID_NONE
	}
	return mgr.widget_box_map[len(mgr.widget_box_map) - 1].id
}

// --- Internal ---

// Get or create a widget state entry. Returns a pointer into the map.
get_or_create_widget_state :: proc(mgr: ^Manager, id: Widget_ID) -> ^Widget_State {
	ws := &mgr.widget_states[id]
	if ws == nil {
		mgr.widget_states[id] = Widget_State{last_seen_frame = mgr.frame_id}
		ws = &mgr.widget_states[id]
	}
	ws.last_seen_frame = mgr.frame_id
	return ws
}

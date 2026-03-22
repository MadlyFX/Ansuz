package ogui


// --- Reactive Value Tracking ---
// The manager internally tracks values passed to widgets via pointers.
// Each frame, the current value is compared to the previous snapshot.
// This enables:
//   1. Dirty detection — skip re-rendering unchanged widgets on embedded
//   2. Future: value constraints (clamp, wrap) and animation overrides
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

// --- Future: Constraint API (infrastructure in place, not yet enforced) ---

// Set constraints on a tracked value. The manager will enforce these
// when animations or overrides write to the value.
set_constraints_f32 :: proc(mgr: ^Manager, id: Widget_ID, lo, hi: f32, wrap: bool = false) {
	ws := get_or_create_widget_state(mgr, id)
	ws.constraint_min = value_to_bits_f32(lo)
	ws.constraint_max = value_to_bits_f32(hi)
	ws.has_constraints = true
	ws.wrap = wrap
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

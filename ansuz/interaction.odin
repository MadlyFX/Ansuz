package ansuz

// --- Interaction System ---
// Hit testing and hot/active/focus state management.
// Uses previous frame's rect for interaction (standard imgui one-frame latency).

Interaction :: bit_set[Interaction_Flag]

Interaction_Flag :: enum {
	Hovered,   // Mouse is over the widget
	Pressed,   // Mouse button is down on the widget
	Clicked,   // Mouse button was released on the widget this frame
	Focused,   // Widget has keyboard focus
}

// Drop any interaction ownership a widget currently holds. Called when a
// widget is disabled so a stale hot/active/focus reference cannot linger and
// block other widgets from interacting.
release_interaction :: proc(mgr: ^Manager, id: Widget_ID) {
	if mgr.hot_id == id { mgr.hot_id = ID_NONE }
	if mgr.active_id == id { mgr.active_id = ID_NONE }
	if mgr.focus_id == id { mgr.focus_id = ID_NONE }
}

// interaction_blocked reports whether something else owns the pointer this
// frame — a modal, a popup, a held scrollbar — or whether the widget is scrolled
// out of its container's visible clip. Split out so compute_interaction can
// still release a press the widget already owns before turning it away.
@(private = "file")
interaction_blocked :: proc(mgr: ^Manager, id: Widget_ID) -> bool {
	if mgr.modal_owner != ID_NONE &&
	   mgr.modal_owner != id &&
	   !id_stack_contains(&mgr.id_stack, mgr.modal_owner) {
		return true
	}

	// When a popup is open or just closed (mouse still held), block all
	// non-owner widgets so clicks don't bleed through the overlay.
	if mgr.popup_block {
		return true
	}
	if mgr.popup_owner != ID_NONE && mgr.popup_owner != id {
		return true
	}

	// A held scrollbar owns the pointer until it is let go, so the content it is
	// drawn over never takes the drag as a press of its own.
	if mgr.scrollbar_drag {
		return true
	}

	if state, ok := mgr.widget_states[id]; ok {
		if state.has_prev_clip && !rect_contains(state.prev_clip, mgr.input.mouse_x, mgr.input.mouse_y) {
			return true
		}
	}
	return false
}

// Compute interaction state for a widget given its rect from the previous frame.
compute_interaction :: proc(mgr: ^Manager, id: Widget_ID, rect: Rect) -> Interaction {
	result: Interaction

	if interaction_blocked(mgr, id) {
		// A blocked widget still has to hand back a press it already owns.
		// active_id is released only on the release branch below, which a block
		// skips — so a widget that gets pressed and is then blocked before the
		// button comes up (a modal opens over it, its container scrolls it out of
		// clip) would pin active_id forever, and no widget anywhere could ever
		// claim a press again. The whole UI goes dead with no way back.
		if !mgr.input.mouse_left && mgr.active_id == id {
			mgr.active_id = ID_NONE
		}
		return result
	}

	mouse_over := rect_contains(rect, mgr.input.mouse_x, mgr.input.mouse_y)

	// Update hot (hovered) state
	if mouse_over {
		mgr.hot_id = id
	}

	if mgr.hot_id == id {
		result += {.Hovered}
	}

	// Handle mouse press/release for active state
	if mgr.input.mouse_left {
		if mouse_over && mgr.active_id == ID_NONE {
			mgr.active_id = id
		}
	} else {
		// Mouse released
		if mgr.active_id == id {
			if mouse_over {
				result += {.Clicked}
			}
			mgr.active_id = ID_NONE
		}
	}

	if mgr.active_id == id {
		result += {.Pressed}
	}

	if mgr.focus_id == id {
		result += {.Focused}
	}

	return result
}

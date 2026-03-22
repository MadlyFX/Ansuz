package ogui

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

// Compute interaction state for a widget given its rect from the previous frame.
compute_interaction :: proc(mgr: ^Manager, id: Widget_ID, rect: Rect) -> Interaction {
	result: Interaction

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
			// Mouse pressed on this widget
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

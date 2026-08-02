package ansuz

// --- Widget Transitions ---
// Smooth visual transitions for widget state changes (hover, press, etc.).
// Each widget stores fade values that smoothly approach 0 or 1 based on
// interaction state, using the animation system's delta time.

TRANSITION_SPEED       :: f32(8.0)   // Higher = faster transition
TRANSITION_SPEED_PRESS :: f32(12.0)  // Press feedback reacts faster than hover

// Smooth a transition value toward a target (0 or 1).
// Call each frame — returns the interpolated value.
transition_toward :: proc(current: ^f32, target: f32, dt: f32, speed: f32 = TRANSITION_SPEED) -> f32 {
	diff := target - current^
	current^ += diff * clamp(speed * dt, 0, 1)

	// Snap when close enough to avoid perpetual tiny updates
	if abs(current^ - target) < 0.005 {
		current^ = target
	}

	return current^
}

// Get the hover fade for a widget, advancing it toward the current state.
// Returns 0..1 representing the hover highlight strength.
get_hover_t :: proc(mgr: ^Manager, id: Widget_ID, hovered: bool) -> f32 {
	ws := get_or_create_widget_state(mgr, id)
	return transition_toward(&ws.hover_t, 1 if hovered else 0, mgr.anim_pool.dt)
}

// Get the focus fade for a widget (keyboard focus ring, focused border).
get_focus_t :: proc(mgr: ^Manager, id: Widget_ID, focused: bool) -> f32 {
	ws := get_or_create_widget_state(mgr, id)
	return transition_toward(&ws.focus_t, 1 if focused else 0, mgr.anim_pool.dt)
}

// Get the press fade for a widget. Checkbox reuses this slot for its
// checked-state fade, since a checkbox never shows a separate press color.
get_press_t :: proc(mgr: ^Manager, id: Widget_ID, pressed: bool) -> f32 {
	ws := get_or_create_widget_state(mgr, id)
	return transition_toward(&ws.press_t, 1 if pressed else 0, mgr.anim_pool.dt, speed = TRANSITION_SPEED_PRESS)
}

// Compute a blended color for a widget based on hover, press, and focus state.
blend_interaction_color :: proc(
	base, hover, pressed, focused: Color,
	hover_t, press_t, focus_t: f32,
) -> Color {
	result := color_lerp(base, hover, hover_t)
	result = color_lerp(result, pressed, press_t)
	result = color_lerp(result, focused, focus_t)
	return result
}

package ansuz

// --- Widget Transitions ---
// Smooth visual transitions for widget state changes (hover, press, etc.).
// Each widget can store a "visual t" that smoothly approaches 0 or 1
// based on interaction state, using the animation system's delta time.

TRANSITION_SPEED :: f32(8.0)  // Higher = faster transition

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

// Get or initialize the hover transition value for a widget.
// Stored in Widget_State's prev_value_bits upper bits (we repurpose override_bits for this).
// Returns 0..1 representing current hover fade.
get_hover_t :: proc(mgr: ^Manager, id: Widget_ID, hovered: bool) -> f32 {
	ws := get_or_create_widget_state(mgr, id)

	// Use override_bits to store the hover_t as f32 bits
	current := transmute(f32)u32(ws.override_bits & 0xFFFFFFFF)
	target := f32(1) if hovered else f32(0)

	result := transition_toward(&current, target, mgr.anim_pool.dt)
	ws.override_bits = u64(transmute(u32)current)

	return result
}

get_focus_t :: proc(mgr: ^Manager, id: Widget_ID, focused: bool) -> f32 {
	ws := get_or_create_widget_state(mgr, id)

	current := transmute(f32)u32((ws.override_bits >> 32) & 0xFFFFFFFF)
	target := f32(1) if focused else f32(0)

	result := transition_toward(&current, target, mgr.anim_pool.dt)
	ws.override_bits = (ws.override_bits & 0xFFFFFFFF) | (u64(transmute(u32)current) << 32)

	return result
}

// Get the press transition value for a widget.
// Stored in the upper 32 bits of override_bits.
get_press_t :: proc(mgr: ^Manager, id: Widget_ID, pressed: bool) -> f32 {
	ws := get_or_create_widget_state(mgr, id)

	bits := u32(ws.constraint_min & 0xFFFFFFFF)  // Repurpose constraint_min for press_t
	current := transmute(f32)bits
	target := f32(1) if pressed else f32(0)

	result := transition_toward(&current, target, mgr.anim_pool.dt, speed = 12)
	ws.constraint_min = u64(transmute(u32)current)

	return result
}

// Compute a blended color for a widget based on hover and press and focused state.
blend_interaction_color :: proc(
	base, hover, pressed, focused: Color,
	hover_t, press_t, focus_t: f32,
) -> Color {
	result := color_lerp(base, hover, hover_t)
	result = color_lerp(result, pressed, press_t)
	result = color_lerp(result, focused, focus_t)
	return result
}

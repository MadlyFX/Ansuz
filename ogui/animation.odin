package ogui

import "core:time"

// --- Animation / Tween System ---
// The manager owns all active animations. Each animation smoothly interpolates
// a value from its current state to a target over a duration with easing.
//
// Animations integrate with the reactive tracking system: while an animation
// is active on a widget, it writes through the user's pointer each frame,
// and the override_active flag prevents the user's own writes from fighting it.
//
// Usage:
//   animate_f32(&mgr, &my_value, target = 1.0, duration = 0.3)
//
// The animation runs across frames. The manager ticks all active animations
// at the start of each frame.

MAX_ANIMATIONS :: 64

Anim_State :: enum {
	Idle,
	Running,
	Finished,
}

Animation :: struct {
	id:         Widget_ID,   // Which widget this belongs to (0 = free slot)
	state:      Anim_State,

	// Value interpolation
	from_bits:  u64,
	to_bits:    u64,
	value_ptr:  rawptr,      // Pointer to the user's variable
	value_kind: Anim_Value_Kind,

	// Timing
	duration:   f32,         // Seconds
	elapsed:    f32,         // Seconds elapsed
	easing:     Ease_Func,

	// Looping
	looping:    bool,
	ping_pong:  bool,        // Reverse direction on loop
	reversed:   bool,        // Current direction (for ping-pong)
}

Anim_Value_Kind :: enum {
	F32,
	Color,
}

// Animation storage lives in the Manager
Anim_Pool :: struct {
	anims:     [MAX_ANIMATIONS]Animation,
	count:     int,
	prev_time: time.Time,
	dt:        f32,  // Delta time in seconds for current frame
}

// --- Public API ---

// Animate an f32 value from its current value to a target.
// If an animation is already running on this value, it is replaced.
animate_f32 :: proc(
	mgr:       ^Manager,
	value:     ^f32,
	target:    f32,
	duration:  f32        = 0.3,
	easing:    Ease_Func  = .Ease_Out_Quad,
	looping:   bool       = false,
	ping_pong: bool       = false,
	loc        := #caller_location,
) {
	id := id_from_ptr_loc(&mgr.id_stack, value, loc)
	from := value^

	anim := alloc_animation(&mgr.anim_pool, id)
	anim.state      = .Running
	anim.from_bits  = u64(transmute(u32)from)
	anim.to_bits    = u64(transmute(u32)target)
	anim.value_ptr  = value
	anim.value_kind = .F32
	anim.duration   = duration
	anim.elapsed    = 0
	anim.easing     = easing
	anim.looping    = looping
	anim.ping_pong  = ping_pong
	anim.reversed   = false
}

// Animate a color value.
animate_color :: proc(
	mgr:      ^Manager,
	value:    ^Color,
	target:   Color,
	duration: f32       = 0.3,
	easing:   Ease_Func = .Ease_Out_Quad,
	loc       := #caller_location,
) {
	id := id_from_ptr_loc(&mgr.id_stack, value, loc)
	from := value^

	anim := alloc_animation(&mgr.anim_pool, id)
	anim.state      = .Running
	anim.from_bits  = transmute(u64)([2]u32{transmute(u32)from, 0})
	anim.to_bits    = transmute(u64)([2]u32{transmute(u32)target, 0})
	anim.value_ptr  = value
	anim.value_kind = .Color
	anim.duration   = duration
	anim.elapsed    = 0
	anim.easing     = easing
	anim.looping    = false
	anim.ping_pong  = false
	anim.reversed   = false
}

// Cancel all animations on a value.
cancel_animation :: proc(mgr: ^Manager, ptr: rawptr, loc := #caller_location) {
	id := id_from_ptr_loc(&mgr.id_stack, ptr, loc)
	for &anim in mgr.anim_pool.anims {
		if anim.id == id && anim.state == .Running {
			anim.state = .Finished
			anim.id = Widget_ID(0)
		}
	}
}

// Check if a value currently has an active animation.
is_animating :: proc(mgr: ^Manager, ptr: rawptr, loc := #caller_location) -> bool {
	id := id_from_ptr_loc(&mgr.id_stack, ptr, loc)
	for anim in mgr.anim_pool.anims {
		if anim.id == id && anim.state == .Running {
			return true
		}
	}
	return false
}

// --- Spring-like helper: animate toward a target each frame ---
// Call every frame. If the value is already close to target, does nothing.
// Otherwise starts/updates an animation. Good for responsive UI transitions.

spring_f32 :: proc(
	mgr:      ^Manager,
	value:    ^f32,
	target:   f32,
	duration: f32       = 0.15,
	easing:   Ease_Func = .Ease_Out_Quad,
	epsilon:  f32       = 0.001,
	loc       := #caller_location,
) {
	if abs(value^ - target) < epsilon {
		value^ = target
		return
	}

	id := id_from_ptr_loc(&mgr.id_stack, value, loc)

	// Check if already animating toward this target
	for anim in mgr.anim_pool.anims {
		if anim.id == id && anim.state == .Running {
			target_stored := transmute(f32)u32(anim.to_bits)
			if abs(target_stored - target) < epsilon {
				return // Already heading there
			}
		}
	}

	animate_f32(mgr, value, target, duration, easing, loc = loc)
}

// --- Internal ---

anim_pool_init :: proc(pool: ^Anim_Pool) {
	pool.prev_time = time.now()
	pool.count = 0
}

// Tick all active animations. Called at the start of each frame.
anim_pool_tick :: proc(pool: ^Anim_Pool) {
	now := time.now()
	pool.dt = f32(time.duration_seconds(time.diff(pool.prev_time, now)))
	pool.prev_time = now

	// Clamp dt to avoid huge jumps on resume/breakpoint
	pool.dt = clamp(pool.dt, 0, 0.1)

	for &anim in pool.anims {
		if anim.state != .Running {
			continue
		}

		anim.elapsed += pool.dt

		t := clamp(anim.elapsed / anim.duration, 0, 1) if anim.duration > 0 else 1

		// Apply easing and write value
		switch anim.value_kind {
		case .F32:
			from := transmute(f32)u32(anim.from_bits)
			to   := transmute(f32)u32(anim.to_bits)
			if anim.reversed {
				from, to = to, from
			}
			result := ease_lerp(from, to, t, anim.easing)
			(cast(^f32)anim.value_ptr)^ = result

		case .Color:
			from := transmute(Color)u32(anim.from_bits)
			to   := transmute(Color)u32(anim.to_bits)
			if anim.reversed {
				from, to = to, from
			}
			result := ease_color(from, to, t, anim.easing)
			(cast(^Color)anim.value_ptr)^ = result
		}

		// Check completion
		if t >= 1 {
			if anim.looping {
				anim.elapsed = 0
				if anim.ping_pong {
					anim.reversed = !anim.reversed
				}
			} else {
				anim.state = .Finished
				anim.id = Widget_ID(0)
				pool.count -= 1
			}
		}
	}
}

// Allocate or reuse an animation slot. Replaces existing animation on same ID.
alloc_animation :: proc(pool: ^Anim_Pool, id: Widget_ID) -> ^Animation {
	// First check if this ID already has an animation — replace it
	for &anim in pool.anims {
		if anim.id == id {
			return &anim
		}
	}

	// Find a free slot
	for &anim in pool.anims {
		if anim.id == Widget_ID(0) || anim.state == .Finished {
			anim.id = id
			pool.count += 1
			return &anim
		}
	}

	// Pool full — overwrite oldest (slot 0)
	pool.anims[0].id = id
	return &pool.anims[0]
}

// Get the delta time for the current frame (seconds).
get_dt :: proc(mgr: ^Manager) -> f32 {
	return mgr.anim_pool.dt
}

package odin_ui

// ansuz embedded export layer.
// Compiles to an object file for ARM Cortex-M4 (freestanding_arm32).
// Exports C-callable functions that the Arduino sketch links against.
//
// Build:
//   odin build odin_ui -target:freestanding_arm32 -microarch:cortex-m4 \
//       -no-crt -o:size -build-mode:obj -out:build/ansuz_ui
//
// NOTE: Before building, reduce FRAME_ARENA_SIZE in ansuz/manager.odin
//       from 256*1024 to 4*1024 (or smaller) for microcontroller targets.
//       The default 256KB arena exceeds most MCU SRAM.

import ansuz "../../ansuz"
import soft "../../backend_soft"
import "base:runtime"
import "core:mem"

// --- Static Memory for Freestanding ---
// All allocations come from this buffer. No OS heap needed.
HEAP_SIZE :: 48 * 1024
heap_buf: [HEAP_SIZE]u8
heap_arena: mem.Arena

// SSD1306 OLED: 128x64 monochrome
// We render to RGBA32, then the Arduino side thresholds to 1-bit.
DISPLAY_W :: 128
DISPLAY_H :: 64

// RGBA framebuffer — 32KB (128 * 64 * 4 bytes)
framebuffer: [DISPLAY_W * DISPLAY_H]u32

// Framework state (static lifetime)
backend: ansuz.Backend
mgr: ansuz.Manager

// Persisted Odin context for freestanding
odin_ctx: runtime.Context

// --- Exported C-callable Functions ---

// Shared state between Odin UI and C/Arduino code.
// Odin owns the memory; C accesses it via ansuz_get_state().
UI_State :: struct {
	brightness:  f32,
	volume:      f32,
	wifi_on:     bool,
	click_count: i32,
}

state: UI_State

@(export)
ansuz_get_state :: proc "c" () -> ^UI_State {
	return &state
}

@(export)
ansuz_init :: proc "c" () {
	// Must set a context before any Odin calls (freestanding has none by default)
	context = runtime.default_context()

	// Set up allocator from static buffer
	mem.arena_init(&heap_arena, heap_buf[:])
	context.allocator = mem.arena_allocator(&heap_arena)

	// Create software renderer targeting the static framebuffer
	backend = soft.create(DISPLAY_W, DISPLAY_H, framebuffer[:])
	backend.init(&backend, DISPLAY_W, DISPLAY_H)

	// Initialize the UI manager
	ansuz.init(&mgr, &backend)

	// Route temp allocator (used by fmt.tprintf) through the frame arena,
	// which is reset every frame_begin. Without this, tprintf strings
	// accumulate in the heap arena and exhaust it after a few frames.
	context.temp_allocator = mgr.frame_allocator
	odin_ctx = context
}

header_anim_val: f32 = 0

@(export)
ansuz_render_frame :: proc "c" () {
	context = odin_ctx

	ansuz.frame_begin(&mgr)

	ansuz.flex_begin(&mgr, axis = .Vertical, gap = 2, padding = {4, 4, 4, 4})

	ansuz.label(&mgr, "Ansuz", scale = 2, font = ansuz.FONT_BUILTIN, padding = {0, 0, -2, 0})
	ansuz.box(&mgr, size = {ansuz.SIZE_GROW, ansuz.size_fixed(1)}, bg_color = ansuz.COLOR_WHITE)
	ansuz.slider_labeled(
		&mgr,
		"A1:",
		ansuz.FONT_BUILTIN,
		value = &state.volume,
		lo = 0,
		hi = 1024,
		scale = 0.5,
	)
	ansuz.checkbox(
		&mgr,
		state.wifi_on ? "True" : "False",
		&state.wifi_on,
		scale = 0.5,
		font = ansuz.FONT_BUILTIN,
	)


	ansuz.flex_end(&mgr)

	ansuz.frame_end(&mgr)
}

// Returns a pointer to the RGBA32 framebuffer (128*64 u32 values).
// The Arduino side reads this and converts to 1-bit for the SSD1306.
@(export)
ansuz_get_framebuffer :: proc "c" () -> [^]u32 {
	return raw_data(framebuffer[:])
}

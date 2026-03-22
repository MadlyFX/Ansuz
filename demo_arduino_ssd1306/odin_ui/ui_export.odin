package odin_ui

// OGUI embedded export layer.
// Compiles to an object file for ARM Cortex-M4 (freestanding_arm32).
// Exports C-callable functions that the Arduino sketch links against.
//
// Build:
//   odin build odin_ui -target:freestanding_arm32 -microarch:cortex-m4 \
//       -no-crt -o:size -build-mode:obj -out:build/ogui_ui
//
// NOTE: Before building, reduce FRAME_ARENA_SIZE in ogui/manager.odin
//       from 256*1024 to 4*1024 (or smaller) for microcontroller targets.
//       The default 256KB arena exceeds most MCU SRAM.

import "base:runtime"
import "core:mem"
import ogui "../../ogui"
import soft "../../backend_soft"
import "core:fmt"

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
backend: ogui.Backend
mgr: ogui.Manager

// Persisted Odin context for freestanding
odin_ctx: runtime.Context

// --- Exported C-callable Functions ---

// Shared state between Odin UI and C/Arduino code.
// Odin owns the memory; C accesses it via ogui_get_state().
UI_State :: struct {
    brightness:  f32,
    volume:      f32,
    wifi_on:     bool,
    click_count: i32,
}

state: UI_State

@(export)
ogui_get_state :: proc "c" () -> ^UI_State {
    return &state
}

@(export)
ogui_init :: proc "c" () {
	// Must set a context before any Odin calls (freestanding has none by default)
	context = runtime.default_context()

	// Set up allocator from static buffer
	mem.arena_init(&heap_arena, heap_buf[:])
	context.allocator = mem.arena_allocator(&heap_arena)

	// Create software renderer targeting the static framebuffer
	backend = soft.create(DISPLAY_W, DISPLAY_H, framebuffer[:])
	backend.init(&backend, DISPLAY_W, DISPLAY_H)

	// Initialize the UI manager
	ogui.init(&mgr, &backend)

	// Route temp allocator (used by fmt.tprintf) through the frame arena,
	// which is reset every frame_begin. Without this, tprintf strings
	// accumulate in the heap arena and exhaust it after a few frames.
	context.temp_allocator = mgr.frame_allocator
	odin_ctx = context
}

@(export)
ogui_render_frame :: proc "c" () {
	context = odin_ctx

	ogui.frame_begin(&mgr)

	ogui.flex_begin(&mgr, axis = .Vertical, gap = 2, padding = {4, 4, 4, 4})

	ogui.label(&mgr, "OGUI", scale = 2, color = ogui.COLOR_WHITE)
	ogui.box(&mgr, size = {ogui.SIZE_GROW, ogui.size_fixed(1)}, bg_color = ogui.COLOR_WHITE)
	ogui.checkbox(&mgr, state.wifi_on ? "True" : "False", &state.wifi_on, scale=0.5)
	ogui.slider_labeled(&mgr, fmt.tprintf("%.0f", state.volume), &state.volume, 0, 100, scale=0.5)

	ogui.flex_end(&mgr)

	ogui.frame_end(&mgr)
}

// Returns a pointer to the RGBA32 framebuffer (128*64 u32 values).
// The Arduino side reads this and converts to 1-bit for the SSD1306.
@(export)
ogui_get_framebuffer :: proc "c" () -> [^]u32 {
	return raw_data(framebuffer[:])
}

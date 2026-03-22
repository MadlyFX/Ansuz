package demo_web

// WebGL/WASM demo for OGUI.
// Compiles to WebAssembly and runs in a browser.
// Build: odin build . -target:js_wasm32 -out:web/ogui_demo.wasm

import "core:fmt"
import ogui "../ogui"
import backend "../backend_webgl"

mgr: ogui.Manager
sdl: ogui.Backend

slider_val: f32 = 0.5
check_a: bool = true
check_b: bool = false
anim_val: f32 = 0
selected: int = 0
options := [?]string{"Alpha", "Beta", "Gamma"}

input_buf: [dynamic]u8
multi_buf: [dynamic]u8

// Exported functions for JavaScript mouse input
@(export)
_ogui_set_mouse :: proc(x, y: f32) {
	mgr.input.mouse_x = x
	mgr.input.mouse_y = y
}

@(export)
_ogui_set_mouse_button :: proc(down: i32) {
	if down != 0 && !mgr.input.mouse_left {
		mgr.input.mouse_left_pressed = true
	}
	mgr.input.mouse_left = down != 0
}

// Exported functions for JavaScript keyboard input
@(export)
_ogui_key_down :: proc(key_code: i32) {
	switch key_code {
	case 8:  mgr.input.key_backspace = true   // Backspace
	case 46: mgr.input.key_delete = true      // Delete
	case 37: mgr.input.key_left = true        // ArrowLeft
	case 39: mgr.input.key_right = true       // ArrowRight
	case 38: mgr.input.key_up = true          // ArrowUp
	case 40: mgr.input.key_down = true        // ArrowDown
	case 36: mgr.input.key_home = true        // Home
	case 35: mgr.input.key_end = true         // End
	case 13: mgr.input.key_enter = true       // Enter
	case 16: mgr.input.key_shift = true       // Shift
	case 17: mgr.input.key_ctrl = true        // Control
	}
}

@(export)
_ogui_mouse_wheel :: proc(delta_y: f32) {
	mgr.input.mouse_scroll_y = delta_y
}

@(export)
_ogui_key_up :: proc(key_code: i32) {
	switch key_code {
	case 16: mgr.input.key_shift = false
	case 17: mgr.input.key_ctrl = false
	}
}

@(export)
_ogui_text_input :: proc(char_code: i32) {
	if char_code >= 32 && mgr.input.text_char_len < len(mgr.input.text_chars) {
		mgr.input.text_chars[mgr.input.text_char_len] = u8(char_code)
		mgr.input.text_char_len += 1
	}
}

main :: proc() {
	sdl = backend.create(800, 600)
	sdl.init(&sdl, sdl.width, sdl.height)

	ogui.init(&mgr, &sdl)

	// Initialize text buffers
	append(&input_buf, ..transmute([]u8)string("Hello, OGUI!"))
	append(&multi_buf, ..transmute([]u8)string("Line 1\nLine 2\nLine 3"))
}

@(export)
step :: proc(dt: f32) -> bool {
	ogui.frame_begin(&mgr)

	ogui.flex_begin(&mgr, axis = .Vertical, gap = 12, padding = {16, 20, 16, 20})

	ogui.heading(&mgr, "OGUI Web Demo")
	ogui.label(&mgr, "Running in WebAssembly + WebGL", color = ogui.THEME_TEXT_DIM)

	// Buttons
	ogui.label(&mgr, "Buttons", scale = 2.5, color = ogui.COLOR_WHITE)
	ogui.flex_begin(&mgr, axis = .Horizontal, gap = 10, size = {ogui.SIZE_GROW, ogui.SIZE_FIT}, align = .Center)
	if .Clicked in ogui.button(&mgr, "Ease Out") {
		ogui.animate_f32(&mgr, &anim_val, 1 if anim_val < 0.5 else 0, duration = 0.5, easing = .Ease_Out_Cubic)
	}
	if .Clicked in ogui.button(&mgr, "Bounce") {
		ogui.animate_f32(&mgr, &anim_val, 1 if anim_val < 0.5 else 0, duration = 0.8, easing = .Ease_Out_Bounce)
	}
	ogui.flex_end(&mgr)

	// Animated bar
	ogui.flex_begin(&mgr, axis = .Horizontal, size = {ogui.SIZE_GROW, ogui.size_fixed(16)}, bg_color = ogui.Color{40, 43, 50, 255})
	ogui.box(&mgr, size = {ogui.size_pct(anim_val), ogui.SIZE_GROW}, bg_color = ogui.COLOR_BLUE)
	ogui.flex_end(&mgr)

	// Slider
	ogui.label(&mgr, "Slider", scale = 2.5, color = ogui.COLOR_WHITE)
	ogui.slider_labeled(&mgr, "Value", &slider_val, 0, 1)

	// Checkboxes
	ogui.label(&mgr, "Checkboxes", scale = 2.5, color = ogui.COLOR_WHITE)
	ogui.checkbox(&mgr, "Option A", &check_a)
	ogui.checkbox(&mgr, "Option B", &check_b)

	// Dropdown
	ogui.label(&mgr, "Dropdown", scale = 2.5, color = ogui.COLOR_WHITE)
	ogui.dropdown(&mgr, &selected, options[:], size = ogui.FIXED_200_30)

	// Text Input
	ogui.label(&mgr, "Text Input", scale = 2.5, color = ogui.COLOR_WHITE)
	ogui.text_input(&mgr, &input_buf, placeholder = "Type here...", size = {ogui.size_fixed(300), ogui.SIZE_FIT})

	ogui.label(&mgr, "Multi-line", scale = 2.5, color = ogui.COLOR_WHITE)
	ogui.text_input(&mgr, &multi_buf, multiline = true, size = {ogui.SIZE_GROW, ogui.size_fixed(80)})

	// Scrollbox
	ogui.label(&mgr, "Scrollbox", scale = 2.5, color = ogui.COLOR_WHITE)
	ogui.scroll_begin(&mgr, gap = 4, size = {ogui.SIZE_GROW, ogui.size_fixed(120)},
		padding = {8, 8, 8, 8}, bg_color = ogui.Color{40, 43, 50, 255})
	for i in 0..<15 {
		ogui.push_id(&mgr, i)
		ogui.label(&mgr, fmt.tprintf("Scrollable item %d", i + 1), padding = {4, 8, 4, 8})
		ogui.pop_id(&mgr)
	}
	ogui.scroll_end(&mgr)

	ogui.flex_end(&mgr)

	ogui.frame_end(&mgr)

	return true  // Keep running
}

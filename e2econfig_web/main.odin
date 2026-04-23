package main

// E2E Config Web/WASM build.
// Build: odin build . -target:js_wasm32 -out:web/e2econfig.wasm

import ansuz "../ansuz"
import backend "../backend_webgl"
import e2e "../e2econfig/e2econfig"
import "base:runtime"

mgr: ansuz.Manager
web: ansuz.Backend

opensans:      ansuz.Font_Handle
opensans_bold: ansuz.Font_Handle

save_pending: bool

// --- Input exports ---

@(export)
_ansuz_set_mouse :: proc(x, y: f32) {
	mgr.input.mouse_x = x
	mgr.input.mouse_y = y
}

@(export)
_ansuz_set_mouse_button :: proc(down: i32) {
	if down != 0 && !mgr.input.mouse_left {
		mgr.input.mouse_left_pressed = true
	}
	mgr.input.mouse_left = down != 0
}

@(export)
_ansuz_key_down :: proc(key_code: i32) {
	switch key_code {
	case 8:  mgr.input.key_backspace = true
	case 46: mgr.input.key_delete    = true
	case 37: mgr.input.key_left      = true
	case 39: mgr.input.key_right     = true
	case 38: mgr.input.key_up        = true
	case 40: mgr.input.key_down      = true
	case 36: mgr.input.key_home      = true
	case 35: mgr.input.key_end       = true
	case 13: mgr.input.key_enter     = true
	case 16: mgr.input.key_shift     = true
	case 17: mgr.input.key_ctrl      = true
	}
}

@(export)
_ansuz_key_up :: proc(key_code: i32) {
	switch key_code {
	case 16: mgr.input.key_shift = false
	case 17: mgr.input.key_ctrl  = false
	}
}

@(export)
_ansuz_mouse_wheel :: proc(delta_y: f32) {
	mgr.input.mouse_scroll_y = delta_y
}

@(export)
_ansuz_text_input :: proc(char_code: i32) {
	if char_code >= 32 && mgr.input.text_char_len < len(mgr.input.text_chars) {
		mgr.input.text_chars[mgr.input.text_char_len] = u8(char_code)
		mgr.input.text_char_len += 1
	}
}

// --- Save exports ---
// JS polls _ansuz_save_pending each frame; when true it reads the JSON
// from linear memory and triggers a browser download.

@(export)
_ansuz_save_pending :: proc() -> bool {
	if save_pending {
		save_pending = false
		return true
	}
	return false
}

@(export)
_ansuz_get_json_ptr :: proc() -> uintptr {
	return uintptr(raw_data(e2e.out_string))
}

@(export)
_ansuz_get_json_len :: proc() -> int {
	return len(e2e.out_string)
}

save_config :: proc() -> bool {
	save_pending = true
	return true
}

main :: proc() {
	web = backend.create(900, 800)
	web.init(&web, web.width, web.height)

	ansuz.init(&mgr, &web)

	font_ok: bool
	opensans, font_ok = ansuz.load_font(&mgr, ansuz.OPENSANS_REGULAR, 96, ansuz.FONT_EXTRA_CODEPOINTS[:])
	if font_ok {
		ansuz.set_default_font(&mgr, opensans)
		ansuz.DEFAULT_FONT_SCALE = ansuz.OPENSANS_FONT_SCALE
	}
	opensans_bold, _ = ansuz.load_font(&mgr, ansuz.OPENSANS_BOLD, 96)

	e2e.Init_Gui(&mgr, save_config, opensans, opensans_bold)
}

@(export)
step :: proc(dt: f32) -> bool {
	context = runtime.default_context()
	ansuz.frame_begin(&mgr)
	e2e.Draw_Gui()
	ansuz.frame_end(&mgr)
	return true
}

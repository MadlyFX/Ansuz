package demo_web

// WebGL/WASM demo for ansuz.
// Compiles to WebAssembly and runs in a browser.
// Build: odin build . -target:js_wasm32 -out:web/ansuz_demo.wasm

import ansuz "../ansuz"
import backend "../backend_webgl"
import "core:fmt"
import "core:image"
import "core:image/png"

PNG_DATA :: #load("logo.png")

mgr: ansuz.Manager
sdl: ansuz.Backend

img: ^image.Image
img_err: image.Error

click_count: int = 0
slider_val: f32 = 0.5
r_val: f32 = 0.47
g_val: f32 = 0.82
b_val: f32 = 1.0
check_a: bool = true
check_b: bool = false
selected: int = 0
options := [?]string{"Option A", "Option B", "Option C", "Option D"}
menu_selected: int = -1
last_menu_action: int = -1
menu_options := [?]string{"Show overlay", "Cool preview", "Warm preview", "Reset tint"}
overlay_open: bool = false
overlay_t: f32 = 0
anim_val: f32 = 0
bounce_val: f32 = 50
header_anim_val: f32 = 50

input_buf: [dynamic]u8
multi_buf: [dynamic]u8

// Exported functions for JavaScript mouse input
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

// Exported functions for JavaScript keyboard input
@(export)
_ansuz_key_down :: proc(key_code: i32) {
	switch key_code {
	case 8:
		mgr.input.key_backspace = true // Backspace
	case 46:
		mgr.input.key_delete = true // Delete
	case 37:
		mgr.input.key_left = true // ArrowLeft
	case 39:
		mgr.input.key_right = true // ArrowRight
	case 38:
		mgr.input.key_up = true // ArrowUp
	case 40:
		mgr.input.key_down = true // ArrowDown
	case 36:
		mgr.input.key_home = true // Home
	case 35:
		mgr.input.key_end = true // End
	case 13:
		mgr.input.key_enter = true // Enter
	case 16:
		mgr.input.key_shift = true // Shift
	case 17:
		mgr.input.key_ctrl = true // Control
	}
}

@(export)
_ansuz_mouse_wheel :: proc(delta_y: f32) {
	mgr.input.mouse_scroll_y = delta_y
}

@(export)
_ansuz_key_up :: proc(key_code: i32) {
	switch key_code {
	case 16:
		mgr.input.key_shift = false
	case 17:
		mgr.input.key_ctrl = false
	}
}

@(export)
_ansuz_text_input :: proc(char_code: i32) {
	if char_code >= 32 && mgr.input.text_char_len < len(mgr.input.text_chars) {
		mgr.input.text_chars[mgr.input.text_char_len] = u8(char_code)
		mgr.input.text_char_len += 1
	}
}

opensans: ansuz.Font_Handle
opensans_bold: ansuz.Font_Handle

test_image: ansuz.Image_Handle
selected_item := 0

main :: proc() {
	sdl = backend.create(1024, 768)
	sdl.init(&sdl, sdl.width, sdl.height)

	ansuz.init(&mgr, &sdl)

	font_ok := false
	// Load OpenSans as the default font (antialiased TTF)
	opensans, font_ok = ansuz.load_font(&mgr, ansuz.OPENSANS_REGULAR, 96)
	if font_ok {
		ansuz.set_default_font(&mgr, opensans)
		ansuz.DEFAULT_FONT_SCALE = ansuz.OPENSANS_FONT_SCALE
	}

	// Load OpenSans Bold as the bold font (antialiased TTF)
	opensans_bold, font_ok = ansuz.load_font(&mgr, ansuz.OPENSANS_BOLD, 96)

	img_err: image.Error
	img, img_err = png.load_from_bytes(PNG_DATA)
	if img_err != nil {
		fmt.println("Failed to load image:", img_err)
		return
	}

	test_image = backend.create_image(
		&sdl,
		img.pixels.buf[:],
		i32(img.width),
		i32(img.height),
		i32(img.channels),
	)

	// Initialize text buffers
	append(&input_buf, ..transmute([]u8)string("Hellope!"))
	append(&multi_buf, ..transmute([]u8)string("Line 1\nLine 2\nLine 3"))
}

@(export)
step :: proc(dt: f32) -> bool {
		ansuz.frame_begin(&mgr, dt)

		modal_anim_id := ansuz.id_from_string(&mgr.id_stack, "web-modal-t")
		modal_id := ansuz.id_from_string(&mgr.id_stack, "web-modal")

		if menu_selected >= 0 {
			last_menu_action = menu_selected
			switch menu_selected {
			case 0:
				overlay_open = true
				ansuz.animate_f32_id(&mgr, modal_anim_id, &overlay_t, 1, duration = 0.25, easing = .Cubic_Out)
			case 1:
				r_val = 0.20
				g_val = 0.58
				b_val = 1.0
			case 2:
				r_val = 1.0
				g_val = 0.56
				b_val = 0.30
			case 3:
				r_val = 0.47
				g_val = 0.82
				b_val = 1.0
			}
			menu_selected = -1
		}

		modal_visible := overlay_open || overlay_t > 0.01 || ansuz.is_animating_id(&mgr, modal_anim_id)
		if modal_visible {
			mgr.modal_owner = modal_id
		} else {
			mgr.modal_owner = ansuz.ID_NONE
		}

		ansuz.stack_begin(&mgr, size = {ansuz.SIZE_GROW, ansuz.SIZE_GROW})
		ansuz.scroll_begin(
			&mgr,
			gap = 14,
			size = {ansuz.SIZE_GROW, ansuz.SIZE_GROW},
			padding = {20, 24, 20, 24},
		)
		preview_color := ansuz.Color{u8(r_val * 255), u8(g_val * 255), u8(b_val * 255), 255} //Controlled by sliders below

		ansuz.heading(
			&mgr,
			"Ansuz Demo",
			scale = 10,
			font = opensans_bold,
			padding = {0, 900, 0, header_anim_val},
			color = preview_color,
			bg_color = ansuz.COLOR_DARK_GRAY,
		)


		ansuz.label(
			&mgr,
			"A cross-platform UI framework in Odin",
			scale = 4,
			font = opensans,
			padding = {-10, 0, 0, 0},
			color = ansuz.THEME_TEXT_DIM,
		)
		ansuz.box(
			&mgr,
			size = {ansuz.size_grow(1.0), ansuz.size_fixed(3)},
			bg_color = ansuz.COLOR_DARK_GRAY,
			margin = {-10, 0, 0, 0},
		) //Divider
		ansuz.box(
			&mgr,
			size = {ansuz.size_grow(1.0), ansuz.size_fixed(3)},
			bg_color = ansuz.COLOR_TRANSPARENT,
			margin = {-10, 0, 0, 0},
		) //Spacer

		//buttons
		ansuz.label(&mgr, "Buttons", font = opensans_bold, padding = {-20, 4, 4, 4})
		ansuz.flex_begin(
			&mgr,
			axis = .Horizontal,
			gap = 10,
			size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT},
			align = .Center,
		)
		if .Clicked in ansuz.button(&mgr, "Click Me", scale = 4) {
			click_count += 1
			ansuz.animate_f32(
				&mgr,
				&header_anim_val,
				250 if header_anim_val < 100 else 50,
				duration = 0.8,
				easing = .Elastic_Out,
			)
		}

		if .Clicked in ansuz.button(&mgr, "Reset", scale = 4) {click_count = 0}
		ansuz.label(
			&mgr,
			fmt.tprintf("Clicks: %d", click_count),
			padding = {6, 12, 6, 12},
			font = opensans,
		)
		ansuz.flex_end(&mgr)

		//sliders
		ansuz.label(&mgr, "Sliders", font = opensans_bold)
		ansuz.slider_labeled(&mgr, "Value", &slider_val, font = opensans)

		ansuz.flex_begin(
			&mgr,
			axis = .Horizontal,
			gap = 16,
			size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT},
			align = .Center,
		)
		ansuz.flex_begin(&mgr, axis = .Vertical, gap = 4, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT})
		ansuz.slider_labeled(&mgr, "R", &r_val, font = opensans)
		ansuz.slider_labeled(&mgr, "G", &g_val, font = opensans)
		ansuz.slider_labeled(&mgr, "B", &b_val, font = opensans)
		ansuz.flex_end(&mgr)
		ansuz.box(&mgr, size = {ansuz.size_fixed(60), ansuz.size_fixed(60)})
		ansuz.flex_end(&mgr)

		//checkboxes/dropdowns
		ansuz.flex_begin(
			&mgr,
			axis = .Horizontal,
			gap = 40,
			size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT},
		)

		ansuz.flex_begin(&mgr, axis = .Vertical, gap = 6, size = {ansuz.SIZE_FIT, ansuz.SIZE_FIT})
		ansuz.label(&mgr, "Checkboxes", font = opensans_bold)
		ansuz.checkbox(&mgr, "Enable feature A", &check_a, font = opensans)
		ansuz.checkbox(&mgr, "Enable feature B", &check_b, font = opensans)
		ansuz.flex_end(&mgr)

		ansuz.flex_begin(&mgr, axis = .Vertical, gap = 6, size = {ansuz.SIZE_FIT, ansuz.SIZE_FIT})
		ansuz.label(&mgr, "Dropdown", font = opensans_bold)
		ansuz.dropdown(
			&mgr,
			&selected_item,
			options[:],
			size = ansuz.FIXED_200_30,
			font = opensans,
			text_color = ansuz.COLOR_WHITE,
			popup_color = ansuz.Color{34, 38, 46, 245},
			item_hover_color = preview_color,
			selected_color = ansuz.COLOR_CYAN,
		)
		ansuz.label(&mgr, fmt.tprintf("Selected: %s", options[selected_item]), font = opensans)
		ansuz.flex_end(&mgr)

		ansuz.flex_begin(&mgr, axis = .Vertical, gap = 6, size = {ansuz.SIZE_FIT, ansuz.SIZE_FIT})
		ansuz.label(&mgr, "Menu Popup", font = opensans_bold)
		ansuz.menu_button(
			&mgr,
			"Actions",
			&menu_selected,
			menu_options[:],
			size = ansuz.FIXED_200_30,
			font = opensans,
			text_color = ansuz.COLOR_WHITE,
			popup_color = ansuz.Color{32, 35, 42, 245},
			item_hover_color = preview_color,
		)
		action_text := "None"
		if last_menu_action >= 0 {
			action_text = menu_options[last_menu_action]
		}
		ansuz.label(&mgr, fmt.tprintf("Last action: %s", action_text), font = opensans)
		if .Clicked in ansuz.button(&mgr, "Show Floating Overlay", font = opensans) {
			overlay_open = true
			ansuz.animate_f32_id(&mgr, modal_anim_id, &overlay_t, 1, duration = 0.25, easing = .Cubic_Out)
		}
		ansuz.flex_end(&mgr)
		ansuz.flex_end(&mgr)

		//text input
		ansuz.label(&mgr, "Text Input", font = opensans_bold)
		ansuz.text_input(
			&mgr,
			&input_buf,
			font = opensans,
			placeholder = "Type here...",
			size = {ansuz.size_fixed(300), ansuz.SIZE_FIT},
		)
		ansuz.label(&mgr, fmt.tprintf("Content: %s", string(input_buf[:])), font = opensans)

		ansuz.label(&mgr, "Multi-line", font = opensans_bold)
		ansuz.text_input(
			&mgr,
			&multi_buf,
			font = opensans,
			multiline = true,
			size = {ansuz.SIZE_GROW, ansuz.size_fixed(100)},
			scale = 3.0,
		)

		//animations
		ansuz.label(&mgr, "Animations", font = opensans_bold)
		ansuz.flex_begin(
			&mgr,
			axis = .Horizontal,
			gap = 10,
			size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT},
			align = .Center,
		)
		if .Clicked in ansuz.button(&mgr, "Ease Out") {
			ansuz.animate_f32(
				&mgr,
				&anim_val,
				1 if anim_val < 0.5 else 0,
				duration = 0.5,
				easing = .Cubic_Out,
			)
		}
		if .Clicked in ansuz.button(&mgr, "Bounce") {
			ansuz.animate_f32(
				&mgr,
				&bounce_val,
				300 if bounce_val < 150 else 50,
				duration = 0.8,
				easing = .Bounce_Out,
			)
		}
		if .Clicked in ansuz.button(&mgr, "Elastic") {
			ansuz.animate_f32(
				&mgr,
				&anim_val,
				1 if anim_val < 0.5 else 0,
				duration = 0.7,
				easing = .Elastic_Out,
			)
		}

		ansuz.flex_end(&mgr)

		ansuz.flex_begin(
			&mgr,
			axis = .Horizontal,
			size = {ansuz.SIZE_GROW, ansuz.size_fixed(16)},
			bg_color = ansuz.Color{40, 43, 50, 255},
		)
		ansuz.box(
			&mgr,
			size = {ansuz.size_pct(anim_val), ansuz.SIZE_GROW},
			bg_color = ansuz.COLOR_BLUE,
		)

		ansuz.flex_end(&mgr)
		ansuz.box(
			&mgr,
			size = {ansuz.size_fixed(bounce_val), ansuz.size_fixed(20)},
			bg_color = ansuz.COLOR_MAGENTA,
		)

		//image
		ansuz.label(&mgr, "Image", font = opensans_bold)
		ansuz.flex_begin(
			&mgr,
			axis = .Horizontal,
			gap = 16,
			align = .Center,
			size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT},
		)
		ansuz.image(&mgr, test_image)
		ansuz.flex_end(&mgr)

		//scrollbox
		ansuz.label(&mgr, "Scrollbox", font = opensans_bold)
		ansuz.label(
			&mgr,
			"Separate scroll containers:",
			font = opensans,
		)
		ansuz.flex_begin(
			&mgr,
			axis = .Horizontal,
			gap = 12,
			size = {ansuz.SIZE_GROW, ansuz.size_fixed(180)},
		)

		ansuz.scroll_begin(
			&mgr,
			gap = 4,
			size = {ansuz.SIZE_GROW, ansuz.SIZE_GROW},
			padding = {8, 8, 8, 8},
			bg_color = ansuz.Color{40, 43, 50, 255},
		)
		for i in 0 ..< 20 {
			ansuz.push_id(&mgr, i)
			ansuz.label_decorated(	
				mgr = &mgr,
				text = fmt.tprintf("Left panel item %d", i + 1),
				decorator = fmt.tprintf("%d. ", i + 1),
				padding = {4, 8, 4, 8},
				font = opensans,
			)
			ansuz.pop_id(&mgr)
		}
		ansuz.scroll_end(&mgr)

		ansuz.scroll_begin(
			&mgr,
			gap = 4,
			size = {ansuz.SIZE_GROW, ansuz.SIZE_GROW},
			padding = {8, 8, 8, 8},
			bg_color = ansuz.Color{50, 43, 40, 255},
		)
		for i in 0 ..< 15 {
			ansuz.push_id(&mgr, i)
			ansuz.label(
				&mgr,
				fmt.tprintf("Right panel item %d", i + 1),
				padding = {4, 8, 4, 8},
				font = opensans,
			)
			ansuz.pop_id(&mgr)
		}

		ansuz.scroll_end(&mgr)
		ansuz.flex_end(&mgr)


		ansuz.scroll_end(&mgr) // end outer scroll

		if modal_visible {
			ansuz.push_id(&mgr, "web-modal")
			ansuz.stack_begin(&mgr, size = {ansuz.SIZE_GROW, ansuz.SIZE_GROW}, floating = true)
			ansuz.box(
				&mgr,
				size = {ansuz.SIZE_GROW, ansuz.SIZE_GROW},
				bg_color = ansuz.Color{0, 0, 0, u8(150 * overlay_t)},
			)

			screen_w := f32(mgr.backend.width)
			screen_h := f32(mgr.backend.height)
			modal_margin := f32(48) if screen_w >= 640 && screen_h >= 420 else f32(24)
			panel_w := max(f32(300), min(f32(520), screen_w - modal_margin * 2))
			panel_h := f32(220)
			panel_x := max(modal_margin, (screen_w - panel_w) / 2)
			panel_y := max(modal_margin, (screen_h - panel_h) / 2)

			ansuz.flex_begin(
				&mgr,
				axis = .Vertical,
				gap = 10,
				size = {ansuz.size_fixed(panel_w), ansuz.size_fixed(panel_h)},
				padding = {22, 26, 22, 26},
				margin = {panel_y, 0, 0, panel_x},
				bg_color = ansuz.Color{34, 37, 44, 250},
			)
			ansuz.flex_begin(&mgr, axis = .Horizontal, gap = 12, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT}, align = .Center)
			ansuz.label(&mgr, "Floating Overlay", font = opensans_bold, color = ansuz.COLOR_WHITE, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT})
			if .Clicked in ansuz.button(&mgr, "Close", font = opensans) {
				overlay_open = false
				ansuz.animate_f32_id(&mgr, modal_anim_id, &overlay_t, 0, duration = 0.20, easing = .Cubic_In)
			}
			ansuz.flex_end(&mgr)
			ansuz.label(
				&mgr,
				"Stack layout + floating pass",
				font = opensans,
				color = ansuz.THEME_TEXT_DIM,
				size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT},
				clip = true,
			)
			ansuz.label(
				&mgr,
				"Background input locked",
				font = opensans,
				color = ansuz.THEME_TEXT_DIM,
				size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT},
				clip = true,
			)
			ansuz.box(&mgr, size = {ansuz.SIZE_GROW, ansuz.size_fixed(1)}, bg_color = ansuz.THEME_BORDER)
			ansuz.label(
				&mgr,
				fmt.tprintf("Animation: %.2f", overlay_t),
				font = opensans,
				color = ansuz.COLOR_WHITE,
				size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT},
				clip = true,
			)
			ansuz.flex_end(&mgr)
			ansuz.stack_end(&mgr)
			ansuz.pop_id(&mgr)
		}

		ansuz.stack_end(&mgr)
		ansuz.frame_end(&mgr)

	return true
}

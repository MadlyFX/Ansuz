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
			ansuz.frame_begin(&mgr)

		ansuz.scroll_begin(
			&mgr,
			gap = 14,
			size = {ansuz.SIZE_GROW, ansuz.SIZE_GROW},
			padding = {20, 24, 20, 24},
		)
		preview_color := ansuz.Color{u8(r_val * 255), u8(g_val * 255), u8(b_val * 255), 255} //Controlled by sliders below

		header_color := ansuz.Label_Color {
			bg    = ansuz.COLOR_DARK_GRAY,
			label = preview_color,
		}

		ansuz.heading(
			&mgr,
			"Ansuz Demo",
			scale = 10,
			font = opensans_bold,
			padding = {0, 900, 0, header_anim_val},
			color = header_color,
		)


		ansuz.label(
			&mgr,
			"A cross-platform UI framework in Odin",
			scale = 4,
			font = opensans,
			padding = {-10, 0, 0, 0},
			color = ansuz.Label_Color{label = ansuz.THEME_TEXT_DIM},
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
		ansuz.slider_labeled(&mgr, "Value", opensans, value = &slider_val)

		ansuz.flex_begin(
			&mgr,
			axis = .Horizontal,
			gap = 16,
			size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT},
			align = .Center,
		)
		ansuz.flex_begin(&mgr, axis = .Vertical, gap = 4, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT})
		ansuz.slider_labeled(&mgr, "R", opensans, value = &r_val)
		ansuz.slider_labeled(&mgr, "G", opensans, value = &g_val)
		ansuz.slider_labeled(&mgr, "B", opensans, value = &b_val)
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
		ansuz.dropdown(&mgr, &selected_item, options[:], size = ansuz.FIXED_200_30)
		ansuz.label(&mgr, fmt.tprintf("Selected: %s", options[selected_item]), font = opensans)
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
		ansuz.frame_end(&mgr)

	return true
}

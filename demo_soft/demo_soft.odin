package demo_soft

// Software renderer demo.
// Renders the UI into a raw pixel framebuffer (like an embedded display),
// then copies it to an SDL window so you can see the result on desktop.
// On a real microcontroller, you'd send the framebuffer to your display
// (SPI, I2C, parallel, etc.) instead of SDL.

import "core:fmt"
import "core:time"
import SDL "vendor:sdl2"
import ansuz "../ansuz"
import soft "../backend_soft"

// Simulated embedded display resolution
DISPLAY_W :: 320
DISPLAY_H :: 240



main :: proc() {
	// The raw framebuffer — on embedded, this would be in SRAM or a DMA buffer.
	// Heap-allocated here for desktop; on a microcontroller you'd use a static buffer.
	framebuffer := make([]u32, DISPLAY_W * DISPLAY_H)
	defer delete(framebuffer)

	// Create the software renderer backend
	backend := soft.create(DISPLAY_W, DISPLAY_H, framebuffer)
	backend.init(&backend, DISPLAY_W, DISPLAY_H)
	defer backend.shutdown(&backend)

	// Initialize ansuz
	mgr: ansuz.Manager
	ansuz.init(&mgr, &backend)
	defer ansuz.shutdown(&mgr)



	// --- SDL setup (for desktop visualization only) ---
	SDL.Init({.VIDEO})
	defer SDL.Quit()

	// Window is 2x the framebuffer for visibility
	SCALE :: 2
	window := SDL.CreateWindow(
		"ansuz Software Renderer (320x240)",
		SDL.WINDOWPOS_CENTERED, SDL.WINDOWPOS_CENTERED,
		DISPLAY_W * SCALE, DISPLAY_H * SCALE,
		{.SHOWN},
	)
	defer SDL.DestroyWindow(window)

	renderer := SDL.CreateRenderer(window, -1, {.ACCELERATED, .PRESENTVSYNC})
	defer SDL.DestroyRenderer(renderer)

	texture := SDL.CreateTexture(renderer, .RGBA32, .STREAMING, DISPLAY_W, DISPLAY_H)
	defer SDL.DestroyTexture(texture)

	SDL.StartTextInput()

	// Create a procedural test image (gradient)
	IMG_W :: i32(32)
	IMG_H :: i32(32)
	img_pixels: [IMG_W * IMG_H * 4]u8
	for y in 0..<IMG_H {
		for x in 0..<IMG_W {
			idx := (y * IMG_W + x) * 4
			img_pixels[idx + 0] = u8(x * 8)
			img_pixels[idx + 1] = u8(y * 8)
			img_pixels[idx + 2] = u8((x + y) * 4)
			img_pixels[idx + 3] = 255
		}
	}
	test_image := soft.create_image(&backend, img_pixels[:], IMG_W, IMG_H)
	defer soft.destroy_image(test_image)

	ansuz.DEFAULT_FONT_SCALE = 1.0

	// Application state
	click_count := 0
	slider_val: f32 = 0.5
	r_val: f32 = 0.3
	g_val: f32 = 0.7
	b_val: f32 = 0.5
	check_a := true
	check_b := false
	selected_item := 0
	header_anim_val: f32 = 20
	options := [?]string{"Option A", "Option B", "Option C", "Option D"}
	menu_selected := -1
	last_menu_action := -1
	menu_options := [?]string{"Show overlay", "Cool tint", "Warm tint"}
	overlay_open := false
	overlay_t: f32 = 0
	anim_val: f32 = 0
	bounce_val: f32 = 50

	input_buf: [dynamic]u8
	defer delete(input_buf)
	append(&input_buf, ..transmute([]u8)string("Hellope!"))

	multi_buf: [dynamic]u8
	defer delete(multi_buf)
	append(&multi_buf, ..transmute([]u8)string("Line 1\nLine 2"))

	last_frame_time := time.now()
	running := true
	for running {
		now := time.now()
		dt := f32(time.duration_seconds(time.diff(last_frame_time, now)))
		last_frame_time = now

		// Reset per-frame edge-triggered input events
		mgr.input.mouse_left_pressed = false
		mgr.input.text_char_len = 0
		mgr.input.key_backspace = false
		mgr.input.key_delete = false
		mgr.input.key_left = false
		mgr.input.key_right = false
		mgr.input.key_up = false
		mgr.input.key_down = false
		mgr.input.key_home = false
		mgr.input.key_end = false
		mgr.input.key_enter = false
		mgr.input.key_copy = false
		mgr.input.key_paste = false
		mgr.input.key_cut = false
		mgr.input.mouse_scroll_y = 0

		// Poll SDL events (since software backend has no event polling)
		for e: SDL.Event; SDL.PollEvent(&e); /**/ {
			#partial switch e.type {
			case .QUIT:
				running = false
			case .MOUSEMOTION:
				// Scale mouse coordinates from window space to framebuffer space
				mgr.input.mouse_x = f32(e.motion.x) / SCALE
				mgr.input.mouse_y = f32(e.motion.y) / SCALE
			case .MOUSEBUTTONDOWN:
				if e.button.button == SDL.BUTTON_LEFT {
					mgr.input.mouse_left = true
					mgr.input.mouse_left_pressed = true
				}
			case .MOUSEBUTTONUP:
				if e.button.button == SDL.BUTTON_LEFT {
					mgr.input.mouse_left = false
				}
			case .MOUSEWHEEL:
				mgr.input.mouse_scroll_y = f32(e.wheel.y)
			case .TEXTINPUT:
				for i in 0..<32 {
					ch := e.text.text[i]
					if ch == 0 { break }
					if ch >= 32 && mgr.input.text_char_len < len(mgr.input.text_chars) {
						mgr.input.text_chars[mgr.input.text_char_len] = u8(ch)
						mgr.input.text_char_len += 1
					}
				}
			case .KEYDOWN:
				#partial switch e.key.keysym.scancode {
				case .ESCAPE:
					running = false
				case .BACKSPACE:
					mgr.input.key_backspace = true
				case .DELETE:
					mgr.input.key_delete = true
				case .LEFT:
					mgr.input.key_left = true
				case .RIGHT:
					mgr.input.key_right = true
				case .UP:
					mgr.input.key_up = true
				case .DOWN:
					mgr.input.key_down = true
				case .HOME:
					mgr.input.key_home = true
				case .END:
					mgr.input.key_end = true
				case .RETURN, .KP_ENTER:
					mgr.input.key_enter = true
				case .LSHIFT, .RSHIFT:
					mgr.input.key_shift = true
				case .LCTRL, .RCTRL:
					mgr.input.key_ctrl = true
				}
			case .KEYUP:
				#partial switch e.key.keysym.scancode {
				case .LSHIFT, .RSHIFT:
					mgr.input.key_shift = false
				case .LCTRL, .RCTRL:
					mgr.input.key_ctrl = false
				}
			}
		}

		// --- Render the UI into the framebuffer ---
		ansuz.frame_begin(&mgr, dt)

		modal_anim_id := ansuz.id_from_string(&mgr.id_stack, "soft-modal-t")
		modal_id := ansuz.id_from_string(&mgr.id_stack, "soft-modal")

		if menu_selected >= 0 {
			last_menu_action = menu_selected
			switch menu_selected {
			case 0:
				overlay_open = true
				ansuz.animate_f32_id(&mgr, modal_anim_id, &overlay_t, 1, duration = 0.25, easing = .Cubic_Out)
			case 1:
				r_val = 0.15
				g_val = 0.45
				b_val = 0.95
			case 2:
				r_val = 0.95
				g_val = 0.55
				b_val = 0.25
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
		scroll_id := ansuz.scroll_begin(&mgr, gap = 14, size = {ansuz.SIZE_GROW, ansuz.SIZE_GROW}, padding = {20, 24, 20, 24})
		preview_color := ansuz.Color{u8(r_val * 255), u8(g_val * 255), u8(b_val * 255), 255}//Controlled by sliders below
		ansuz.heading(&mgr, "Ansuz Demo", font = ansuz.FONT_BUILTIN, scale=2, padding={0, 0, 0, header_anim_val}, color = preview_color)
		ansuz.label(&mgr, "A cross-platform UI framework in Odin", color = ansuz.THEME_TEXT_DIM, font=ansuz.FONT_BUILTIN, padding={-15, 2, 20, 20})
		ansuz.box(&mgr, size = {ansuz.size_grow(1.0), ansuz.size_fixed(3)}, bg_color = ansuz.COLOR_DARK_GRAY, margin={-20, 0, 0, 0})

		// --- Buttons ---
		ansuz.label(&mgr, "Buttons", color = ansuz.COLOR_WHITE, font=ansuz.FONT_BUILTIN, padding={-20, 4, 4, 4})
		ansuz.flex_begin(&mgr, axis = .Horizontal, gap = 10, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT}, align = .Center)
		if .Clicked in ansuz.button(&mgr, "Click Me") { 
			click_count += 1 
			ansuz.animate_f32(&mgr, &header_anim_val, 150 if header_anim_val < 100 else 20 , duration = 0.8, easing = .Elastic_Out)
		}

		if .Clicked in ansuz.button(&mgr, "Reset") { click_count = 0 }
			ansuz.label(&mgr, fmt.tprintf("Clicks: %d", click_count), padding = {6, 12, 6, 12}, font=ansuz.FONT_BUILTIN)
			ansuz.flex_end(&mgr)
		

		// --- Sliders ---
		ansuz.label(&mgr, "Sliders", color = ansuz.COLOR_WHITE, font=ansuz.FONT_BUILTIN)
		ansuz.slider_labeled(&mgr, "Value", &slider_val, 0, 1, font = ansuz.FONT_BUILTIN)

		ansuz.flex_begin(&mgr, axis = .Horizontal, gap = 16, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT}, align = .Center)
		ansuz.flex_begin(&mgr, axis = .Vertical, gap = 4, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT})
		ansuz.slider_labeled(&mgr, "R", &r_val, 0, 1, scale=0.5, font = ansuz.FONT_BUILTIN)
		ansuz.slider_labeled(&mgr, "G", &g_val, 0, 1, scale=0.5, font = ansuz.FONT_BUILTIN)
		ansuz.slider_labeled(&mgr, "B", &b_val, 0, 1, scale=0.5, font = ansuz.FONT_BUILTIN)
		ansuz.flex_end(&mgr)
		
		ansuz.box(&mgr, size = {ansuz.size_fixed(60), ansuz.size_fixed(60)}, bg_color = preview_color)
		ansuz.flex_end(&mgr)

		// --- Checkboxes + Dropdown side by side ---
		ansuz.flex_begin(&mgr, axis = .Horizontal, gap = 60, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT})

		ansuz.flex_begin(&mgr, axis = .Vertical, gap = 6, size = {ansuz.SIZE_FIT, ansuz.SIZE_FIT})
		ansuz.label(&mgr, "Checkboxes", color = ansuz.COLOR_WHITE, font=ansuz.FONT_BUILTIN)
		ansuz.checkbox(&mgr, "Enable feature A", &check_a, font=ansuz.FONT_BUILTIN, scale=0.5)
		ansuz.checkbox(&mgr, "Enable feature B", &check_b, font=ansuz.FONT_BUILTIN, scale=0.5)
		ansuz.flex_end(&mgr)

		ansuz.flex_begin(&mgr, axis = .Vertical, gap = 6, size = {ansuz.SIZE_FIT, ansuz.SIZE_FIT})
		ansuz.label(&mgr, "Dropdown", color = ansuz.COLOR_WHITE, font=ansuz.FONT_BUILTIN)
		ansuz.dropdown(&mgr, &selected_item, options[:], size = ansuz.GROW_FIXED_30)
		ansuz.label(&mgr, fmt.tprintf("Selected: %s", options[selected_item]), color = ansuz.THEME_TEXT_DIM, font=ansuz.FONT_BUILTIN)
		ansuz.flex_end(&mgr)

		ansuz.flex_end(&mgr)

		// --- Menu popup + floating overlay ---
		ansuz.label(&mgr, "Menu Popup", color = ansuz.COLOR_WHITE, font=ansuz.FONT_BUILTIN)
		ansuz.menu_button(
			&mgr,
			"Actions",
			&menu_selected,
			menu_options[:],
			size = ansuz.FIXED_200_30,
			scale = 0.5,
			font = ansuz.FONT_BUILTIN,
			text_color = ansuz.COLOR_WHITE,
			popup_color = ansuz.Color{32, 35, 42, 245},
			item_hover_color = preview_color,
		)
		action_text := "None"
		if last_menu_action >= 0 {
			action_text = menu_options[last_menu_action]
		}
		ansuz.label(&mgr, fmt.tprintf("Action: %s", action_text), color = ansuz.THEME_TEXT_DIM, font=ansuz.FONT_BUILTIN)
		if .Clicked in ansuz.button(&mgr, "Overlay", font=ansuz.FONT_BUILTIN) {
			overlay_open = true
			ansuz.animate_f32_id(&mgr, modal_anim_id, &overlay_t, 1, duration = 0.25, easing = .Cubic_Out)
		}

		// --- Text Input ---
		ansuz.label(&mgr, "Text Input", color = ansuz.COLOR_WHITE, font=ansuz.FONT_BUILTIN)
		ansuz.text_input(&mgr, &input_buf, font = ansuz.FONT_BUILTIN, placeholder = "Type here...", size = {ansuz.size_fixed(300), ansuz.SIZE_FIT})
		ansuz.label(&mgr, fmt.tprintf("Content: %s", string(input_buf[:])), color = ansuz.THEME_TEXT_DIM, font=ansuz.FONT_BUILTIN)

		ansuz.label(&mgr, "Multi-line", color = ansuz.COLOR_WHITE, font=ansuz.FONT_BUILTIN)
		ansuz.text_input(&mgr, &multi_buf, font = ansuz.FONT_BUILTIN, multiline = true, size = {ansuz.SIZE_GROW, ansuz.size_fixed(80)})

		// --- Animations ---
		ansuz.label(&mgr, "Animations", color = ansuz.COLOR_WHITE, font=ansuz.FONT_BUILTIN)
		ansuz.flex_begin(&mgr, axis = .Horizontal, gap = 10, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT}, align = .Center)
		if .Clicked in ansuz.button(&mgr, "Ease Out") {
			ansuz.animate_f32(&mgr, &anim_val, 1 if anim_val < 0.5 else 0, duration = 0.5, easing = .Cubic_Out)
		}
		if .Clicked in ansuz.button(&mgr, "Bounce") {
			ansuz.animate_f32(&mgr, &bounce_val, 300 if bounce_val < 150 else 50, duration = 0.8, easing = .Bounce_Out)
		}
		if .Clicked in ansuz.button(&mgr, "Elastic") {
			ansuz.animate_f32(&mgr, &anim_val, 1 if anim_val < 0.5 else 0, duration = 0.7, easing = .Elastic_Out)
		}

		ansuz.flex_end(&mgr)

		ansuz.flex_begin(&mgr, axis = .Horizontal, size = {ansuz.SIZE_GROW, ansuz.size_fixed(16)}, bg_color = ansuz.Color{40, 43, 50, 255})
		ansuz.box(&mgr, size = {ansuz.size_pct(anim_val), ansuz.SIZE_GROW}, bg_color = ansuz.COLOR_BLUE)
		ansuz.flex_end(&mgr)

		ansuz.box(&mgr, size = {ansuz.size_fixed(bounce_val), ansuz.size_fixed(20)}, bg_color = ansuz.COLOR_MAGENTA)

		// // --- Image ---
		// ansuz.label(&mgr, "Image", color = ansuz.COLOR_WHITE, font=ansuz.FONT_BUILTIN_bold)
		// ansuz.flex_begin(&mgr, axis = .Horizontal, gap = 16, align = .Center, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT})
		// ansuz.image(&mgr, test_image)
		// //ansuz.image(&mgr, test_image, size = {ansuz.size_fixed(128), ansuz.size_fixed(128)})
		// //ansuz.label(&mgr, "Procedural gradient", color = ansuz.THEME_TEXT_DIM)
		// ansuz.flex_end(&mgr)

		// --- Scrollbox ---
		ansuz.label(&mgr, "Scrollbox", color = ansuz.COLOR_WHITE, font=ansuz.FONT_BUILTIN)
		ansuz.label(&mgr, "Independent scroll containers inside a horizontal flex:", color = ansuz.THEME_TEXT_DIM, font=ansuz.FONT_BUILTIN)
		ansuz.flex_begin(&mgr, axis = .Horizontal, gap = 12, size = {ansuz.SIZE_GROW, ansuz.size_fixed(180)})

		ansuz.scroll_begin(&mgr, gap = 4, size = {ansuz.SIZE_GROW, ansuz.SIZE_GROW},
			padding = {8, 8, 8, 8}, bg_color = ansuz.Color{40, 43, 50, 255})
		for i in 0..<20 {
			ansuz.push_id(&mgr, i)
			ansuz.label(&mgr, fmt.tprintf("Left panel item %d", i + 1), padding = {4, 8, 4, 8}, font=ansuz.FONT_BUILTIN)
			ansuz.pop_id(&mgr)
		}
		ansuz.scroll_end(&mgr)

		ansuz.scroll_begin(&mgr, gap = 4, size = {ansuz.SIZE_GROW, ansuz.SIZE_GROW},
			padding = {8, 8, 8, 8}, bg_color = ansuz.Color{50, 43, 40, 255})
		for i in 0..<15 {
			ansuz.push_id(&mgr, i)
			ansuz.label(&mgr, fmt.tprintf("Right panel item %d", i + 1), padding = {4, 8, 4, 8}, font=ansuz.FONT_BUILTIN)
			ansuz.pop_id(&mgr)
		}
		ansuz.scroll_end(&mgr)

		ansuz.flex_end(&mgr)

		ansuz.scroll_end(&mgr) // end outer scroll

		if modal_visible {
			ansuz.push_id(&mgr, "soft-modal")
			ansuz.stack_begin(&mgr, size = {ansuz.SIZE_GROW, ansuz.SIZE_GROW}, floating = true)
			ansuz.box(
				&mgr,
				size = {ansuz.SIZE_GROW, ansuz.SIZE_GROW},
				bg_color = ansuz.Color{0, 0, 0, u8(145 * overlay_t)},
			)

			soft_margin := f32(16)
			panel_w := f32(260)
			panel_h := f32(118)
			panel_x := max(soft_margin, (f32(mgr.backend.width) - panel_w) / 2)
			panel_y := max(soft_margin, (f32(mgr.backend.height) - panel_h) / 2)

			ansuz.flex_begin(
				&mgr,
				axis = .Vertical,
				gap = 6,
				size = {ansuz.size_fixed(panel_w), ansuz.size_fixed(panel_h)},
				padding = {12, 14, 12, 14},
				margin = {panel_y, 0, 0, panel_x},
				bg_color = ansuz.Color{34, 37, 44, 250},
			)
			ansuz.flex_begin(&mgr, axis = .Horizontal, gap = 6, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT}, align = .Center)
			ansuz.label(&mgr, "Floating Overlay", color = ansuz.COLOR_WHITE, font=ansuz.FONT_BUILTIN, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT})
			if .Clicked in ansuz.button(&mgr, "Close", font=ansuz.FONT_BUILTIN) {
				overlay_open = false
				ansuz.animate_f32_id(&mgr, modal_anim_id, &overlay_t, 0, duration = 0.20, easing = .Cubic_In)
			}
			ansuz.flex_end(&mgr)
			ansuz.label(&mgr, "Input locked below", color = ansuz.THEME_TEXT_DIM, font=ansuz.FONT_BUILTIN, scale = 0.5)
			ansuz.label(&mgr, fmt.tprintf("t %.2f", overlay_t), color = ansuz.THEME_TEXT_DIM, font=ansuz.FONT_BUILTIN, scale = 0.5)
			ansuz.flex_end(&mgr)
			ansuz.stack_end(&mgr)
			ansuz.pop_id(&mgr)
		}

		ansuz.stack_end(&mgr)
		ansuz.frame_end(&mgr)
		free_all(context.temp_allocator)

		// --- Copy framebuffer to SDL texture and display ---
		SDL.UpdateTexture(texture, nil, raw_data(framebuffer[:]), DISPLAY_W * 4)
		SDL.RenderClear(renderer)
		SDL.RenderCopy(renderer, texture, nil, nil)  // Stretches to window size (2x)
		SDL.RenderPresent(renderer)
	}
}

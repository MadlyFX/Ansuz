package demo

import ansuz "../ansuz"
import backend "../backend_sdl"
import "core:fmt"
import "core:image"
import "core:image/png"
import "core:strings"

img: ^image.Image
img_err: image.Error


main :: proc() {
	sdl := backend.create(900, 800, "ansuz Demo")
	if !sdl.init(&sdl, sdl.width, sdl.height) {
		return
	}
	defer sdl.shutdown(&sdl)

	mgr: ansuz.Manager
	ansuz.init(&mgr, &sdl)
	defer ansuz.shutdown(&mgr)

	// Load OpenSans as the default font (antialiased TTF)
	opensans, font_ok := ansuz.load_font(&mgr, ansuz.OPENSANS_REGULAR, 96, ansuz.FONT_EXTRA_CODEPOINTS[:])
	if font_ok {
		ansuz.set_default_font(&mgr, opensans)
		ansuz.DEFAULT_FONT_SCALE = ansuz.OPENSANS_FONT_SCALE
	}

	// Load OpenSans as the default font (antialiased TTF)
	opensans_bold, bolt_font_ok := ansuz.load_font(&mgr, ansuz.OPENSANS_BOLD, 96)

	img, img_err = image.load_from_file("logo.png")
	if img_err != nil {
		fmt.println("Failed to load image:", img_err)
		return
	}

	test_image := backend.create_image(
		&sdl,
		img.pixels.buf[:],
		i32(img.width),
		i32(img.height),
		i32(img.channels),
	)
	defer backend.destroy_image(test_image)

	// Application state
	click_count := 0
	slider_val: f32 = 0.5
	r_val: f32 = 0.47
	g_val: f32 = 0.82
	b_val: f32 = 1.0
	check_a := true
	check_b := false
	selected_item := 0
	options := [?]string{"Option A", "Option B", "Option C", "Option D"}
	anim_val: f32 = 0
	bounce_val: f32 = 50
	header_anim_val: f32 = 50

	input_buf: [dynamic]u8
	defer delete(input_buf)
	append(&input_buf, ..transmute([]u8)string("Hellope!"))

	multi_buf: [dynamic]u8
	defer delete(multi_buf)
	append(&multi_buf, ..transmute([]u8)string("Line 1\nLine 2\nLine 3"))

	for !ansuz.should_quit(&mgr) {
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
			mgr = &mgr,
			text = "A cross-platform UI framework in Odin",
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
				100 + f32(click_count * 5) if header_anim_val < 100 else 50,
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
		ansuz.box(&mgr, size = {ansuz.size_fixed(60), ansuz.size_fixed(60)}, bg_color = preview_color)
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
			"Independent scroll containers inside a horizontal flex:",
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
	}
}

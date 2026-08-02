package demo

import ansuz "../ansuz"
import backend "../backend_sdl"
import "core:fmt"
import "core:image"
import _ "core:image/png"
import "core:time"

img: ^image.Image
img_err: image.Error

// Demo text renders at these widget scales. Font atlases are rasterized at the
// matching physical pixel size (scale x glyph height x monitor pixel density)
// so glyphs keep proper weight instead of being minified from a large atlas.
DEMO_FONT_SCALE    :: f32(3)
HEADING_FONT_SCALE :: f32(6)

main :: proc() {
	sdl := backend.create(900, 800, "ansuz Demo")
	if !sdl.init(&sdl, sdl.width, sdl.height) {
		return
	}
	defer sdl.shutdown(&sdl)

	mgr: ansuz.Manager
	ansuz.init(&mgr, &sdl)
	defer ansuz.shutdown(&mgr)

	// Load OpenSans atlases at display size (antialiased TTF)
	density := backend.pixel_density(&sdl)
	body_px := DEMO_FONT_SCALE * ansuz.FONT_GLYPH_HEIGHT * density
	heading_px := HEADING_FONT_SCALE * ansuz.FONT_GLYPH_HEIGHT * density

	opensans, font_ok := ansuz.load_font(&mgr, ansuz.OPENSANS_REGULAR, body_px, ansuz.FONT_EXTRA_CODEPOINTS[:])
	if font_ok {
		ansuz.set_default_font(&mgr, opensans)
		ansuz.DEFAULT_FONT_SCALE = DEMO_FONT_SCALE
	}
	opensans_bold, _ := ansuz.load_font(&mgr, ansuz.OPENSANS_BOLD, body_px)
	opensans_heading, _ := ansuz.load_font(&mgr, ansuz.OPENSANS_BOLD, heading_px)

	img, img_err = image.load_from_file("demo/logo.png")
	if img_err != nil {
		img, img_err = image.load_from_file("logo.png")
	}
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
	menu_selected := -1
	last_menu_action := -1
	menu_options := [?]string{"Show overlay", "Cool preview", "Warm preview", "Reset tint"}
	overlay_open := false
	overlay_t: f32 = 0
	anim_val: f32 = 0
	bounce_val: f32 = 50
	header_anim_val: f32 = 50

	tree_projects_expanded := true
	tree_renderer_expanded := true
	tree_notes_expanded := false
	tree_selected := -1

	input_buf: [dynamic]u8
	defer delete(input_buf)
	append(&input_buf, ..transmute([]u8)string("Hellope!"))

	multi_buf: [dynamic]u8
	defer delete(multi_buf)
	append(&multi_buf, ..transmute([]u8)string("Line 1\nLine 2\nLine 3"))

	last_frame_time := time.now()

	for !ansuz.should_quit(&mgr) {
		now := time.now()
		dt := f32(time.duration_seconds(time.diff(last_frame_time, now)))
		last_frame_time = now

		ansuz.frame_begin(&mgr, dt)

		modal_anim_id := ansuz.id_from_string(&mgr.id_stack, "desktop-modal-t")
		modal_id := ansuz.id_from_string(&mgr.id_stack, "desktop-modal")

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
			gap = 8,
			size = {ansuz.SIZE_GROW, ansuz.SIZE_GROW},
			padding = {14, 20, 14, 20},
		)

		preview_color := ansuz.Color{u8(r_val * 255), u8(g_val * 255), u8(b_val * 255), 255} //Controlled by sliders below

		ansuz.heading(
			&mgr,
			"Ansuz Demo",
			scale = HEADING_FONT_SCALE,
			font = opensans_heading,
			padding = {0, 900, 0, header_anim_val},
			color = preview_color,
			bg_color = ansuz.COLOR_DARK_GRAY,
		)
		ansuz.label(
			mgr = &mgr,
			text = "A cross-platform UI framework in Odin",
			font = opensans,
			padding = {-6, 0, 0, 0},
			color = ansuz.THEME_TEXT_DIM,
		)
		ansuz.box(
			&mgr,
			size = {ansuz.size_grow(1.0), ansuz.size_fixed(2)},
			bg_color = ansuz.COLOR_DARK_GRAY,
			margin = {-6, 0, 0, 0},
		) //Divider

		//buttons | sliders
		ansuz.flex_begin(&mgr, axis = .Horizontal, gap = 28, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT}, align = .Start)

		ansuz.flex_begin(&mgr, axis = .Vertical, gap = 6, size = {ansuz.SIZE_FIT, ansuz.SIZE_FIT})
		ansuz.label(&mgr, "Buttons", font = opensans_bold, padding = {2, 4, 0, 4})
		ansuz.flex_begin(&mgr, axis = .Horizontal, gap = 8, size = {ansuz.SIZE_FIT, ansuz.SIZE_FIT}, align = .Center)
		if .Clicked in ansuz.button(&mgr, "Click Me") {
			click_count += 1
			ansuz.animate_f32(
				&mgr,
				&header_anim_val,
				100 + f32(click_count * 5) if header_anim_val < 100 else 50,
				duration = 0.8,
				easing = .Elastic_Out,
			)
		}
		if .Clicked in ansuz.button(&mgr, "Reset") {click_count = 0}
		ansuz.label(&mgr, fmt.tprintf("Clicks: %d", click_count), padding = {4, 8, 4, 8}, font = opensans)
		ansuz.flex_end(&mgr)

		ansuz.label(&mgr, "Checkboxes", font = opensans_bold, padding = {8, 4, 0, 4})
		ansuz.checkbox(&mgr, "Enable feature A", &check_a, font = opensans)
		ansuz.checkbox(&mgr, "Enable feature B", &check_b, font = opensans)
		ansuz.flex_end(&mgr)

		ansuz.flex_begin(&mgr, axis = .Vertical, gap = 4, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT})
		ansuz.label(&mgr, "Sliders", font = opensans_bold, padding = {2, 4, 0, 4})
		ansuz.slider_labeled(&mgr, "Value", &slider_val, font = opensans)
		ansuz.flex_begin(&mgr, axis = .Horizontal, gap = 12, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT}, align = .Center)
		ansuz.flex_begin(&mgr, axis = .Vertical, gap = 4, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT})
		ansuz.slider_labeled(&mgr, "R", &r_val, font = opensans)
		ansuz.slider_labeled(&mgr, "G", &g_val, font = opensans)
		ansuz.slider_labeled(&mgr, "B", &b_val, font = opensans)
		ansuz.flex_end(&mgr)
		ansuz.box(&mgr, size = {ansuz.size_fixed(48), ansuz.size_fixed(48)}, bg_color = preview_color)
		ansuz.flex_end(&mgr)
		ansuz.flex_end(&mgr)

		ansuz.flex_end(&mgr)

		//dropdown | menu | image
		ansuz.flex_begin(&mgr, axis = .Horizontal, gap = 28, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT}, align = .Start)

		ansuz.flex_begin(&mgr, axis = .Vertical, gap = 6, size = {ansuz.SIZE_FIT, ansuz.SIZE_FIT})
		ansuz.label(&mgr, "Dropdown", font = opensans_bold, padding = {2, 4, 0, 4})
		ansuz.dropdown(
			&mgr,
			&selected_item,
			options[:],
			size = {ansuz.size_fixed(200), ansuz.size_fixed(30)},
			font = opensans,
			text_color = ansuz.COLOR_WHITE,
			popup_color = ansuz.Color{34, 38, 46, 245},
			item_hover_color = preview_color,
			selected_color = ansuz.COLOR_CYAN,
		)
		ansuz.label(&mgr, fmt.tprintf("Selected: %s", options[selected_item]), font = opensans)
		ansuz.flex_end(&mgr)

		ansuz.flex_begin(&mgr, axis = .Vertical, gap = 6, size = {ansuz.SIZE_FIT, ansuz.SIZE_FIT})
		ansuz.label(&mgr, "Menu Popup", font = opensans_bold, padding = {2, 4, 0, 4})
		ansuz.menu_button(
			&mgr,
			"Actions",
			&menu_selected,
			menu_options[:],
			size = {ansuz.size_fixed(200), ansuz.size_fixed(30)},
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
		ansuz.flex_end(&mgr)

		ansuz.flex_begin(&mgr, axis = .Vertical, gap = 6, size = {ansuz.SIZE_FIT, ansuz.SIZE_FIT})
		ansuz.label(&mgr, "Overlay", font = opensans_bold, padding = {2, 4, 0, 4})
		if .Clicked in ansuz.button(&mgr, "Show Floating Overlay", font = opensans) {
			overlay_open = true
			ansuz.animate_f32_id(&mgr, modal_anim_id, &overlay_t, 1, duration = 0.25, easing = .Cubic_Out)
		}
		ansuz.flex_end(&mgr)

		ansuz.flex_begin(&mgr, axis = .Vertical, gap = 6, size = {ansuz.SIZE_FIT, ansuz.SIZE_FIT})
		ansuz.label(&mgr, "Image", font = opensans_bold, padding = {2, 4, 0, 4})
		ansuz.image(&mgr, test_image, size = {ansuz.size_fixed(160), ansuz.size_fixed(74)})
		ansuz.flex_end(&mgr)

		ansuz.flex_end(&mgr)

		//text input | animations
		ansuz.flex_begin(&mgr, axis = .Horizontal, gap = 28, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT}, align = .Start)

		ansuz.flex_begin(&mgr, axis = .Vertical, gap = 6, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT})
		ansuz.label(&mgr, "Text Input", font = opensans_bold, padding = {2, 4, 0, 4})
		ansuz.text_input(
			&mgr,
			&input_buf,
			font = opensans,
			placeholder = "Type here...",
			size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT},
		)
		ansuz.label(&mgr, fmt.tprintf("Content: %s", string(input_buf[:])), font = opensans, clip = true, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT})
		ansuz.text_input(
			&mgr,
			&multi_buf,
			font = opensans,
			multiline = true,
			size = {ansuz.SIZE_GROW, ansuz.size_fixed(96)},
		)
		ansuz.flex_end(&mgr)

		ansuz.flex_begin(&mgr, axis = .Vertical, gap = 6, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT}, align = .Start)
		ansuz.label(&mgr, "Animations", font = opensans_bold, padding = {2, 4, 0, 4})
		ansuz.flex_begin(&mgr, axis = .Horizontal, gap = 8, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT}, align = .Center)
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
		ansuz.flex_begin(
			&mgr,
			axis = .Horizontal,
			size = {ansuz.SIZE_GROW, ansuz.size_fixed(14)},
			bg_color = ansuz.Color{40, 43, 50, 255},
		)
		ansuz.box(&mgr, size = {ansuz.size_pct(anim_val), ansuz.SIZE_GROW}, bg_color = ansuz.COLOR_BLUE)
		ansuz.flex_end(&mgr)
		ansuz.box(&mgr, size = {ansuz.size_fixed(bounce_val), ansuz.size_fixed(16)}, bg_color = ansuz.COLOR_MAGENTA)
		ansuz.flex_end(&mgr)

		ansuz.flex_end(&mgr)

		//scrollbox | tree
		ansuz.flex_begin(&mgr, axis = .Horizontal, gap = 28, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT}, align = .Start)

		ansuz.flex_begin(&mgr, axis = .Vertical, gap = 6, size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT})
		ansuz.label(&mgr, "Scrollbox", font = opensans_bold, padding = {2, 4, 0, 4})
		ansuz.flex_begin(
			&mgr,
			axis = .Horizontal,
			gap = 10,
			size = {ansuz.SIZE_GROW, ansuz.size_fixed(144)},
		)
		ansuz.scroll_begin(
			&mgr,
			gap = 4,
			size = {ansuz.SIZE_GROW, ansuz.SIZE_GROW},
			padding = {6, 6, 6, 6},
			bg_color = ansuz.Color{40, 43, 50, 255},
		)
		for i in 0 ..< 20 {
			ansuz.push_id(&mgr, i)
			ansuz.label_decorated(
				mgr = &mgr,
				text = fmt.tprintf("Left panel item %d", i + 1),
				decorator = fmt.tprintf("%d. ", i + 1),
				padding = {2, 6, 2, 6},
				font = opensans,
			)
			ansuz.pop_id(&mgr)
		}
		ansuz.scroll_end(&mgr)

		ansuz.scroll_begin(
			&mgr,
			gap = 4,
			size = {ansuz.SIZE_GROW, ansuz.SIZE_GROW},
			padding = {6, 6, 6, 6},
			bg_color = ansuz.Color{50, 43, 40, 255},
		)
		for i in 0 ..< 15 {
			ansuz.push_id(&mgr, i)
			ansuz.label(
				&mgr,
				fmt.tprintf("Right panel item %d", i + 1),
				padding = {2, 6, 2, 6},
				font = opensans,
			)
			ansuz.pop_id(&mgr)
		}
		ansuz.scroll_end(&mgr)
		ansuz.flex_end(&mgr)
		ansuz.flex_end(&mgr)

		ansuz.flex_begin(&mgr, axis = .Vertical, gap = 6, size = {ansuz.size_fixed(300), ansuz.SIZE_FIT})
		ansuz.label(&mgr, "Tree", font = opensans_bold, padding = {2, 4, 0, 4})
		ansuz.flex_begin(
			&mgr,
			axis = .Vertical,
			size = {ansuz.SIZE_GROW, ansuz.SIZE_FIT},
			padding = {8, 6, 8, 6},
			bg_color = ansuz.Color{34, 37, 44, 255},
		)
		ansuz.tree_begin(&mgr)

		projects_open, projects_node := ansuz.tree_node_begin(
			&mgr,
			"Projects",
			&tree_projects_expanded,
			selected = tree_selected == 0,
			row_height = 26,
			font = opensans,
		)
		if .Clicked in projects_node {tree_selected = 0}
		if projects_open {
			if .Clicked in ansuz.tree_leaf(&mgr, "ansuz.odin", selected = tree_selected == 1, icon = .Document, row_height = 26, font = opensans) {
				tree_selected = 1
			}
			renderer_open, renderer_node := ansuz.tree_node_begin(
				&mgr,
				"renderer",
				&tree_renderer_expanded,
				selected = tree_selected == 2,
				is_last = true,
				row_height = 26,
				font = opensans,
			)
			if .Clicked in renderer_node {tree_selected = 2}
			if renderer_open {
				if .Clicked in ansuz.tree_leaf(&mgr, "soft.odin", selected = tree_selected == 3, icon = .Document, row_height = 26, font = opensans) {
					tree_selected = 3
				}
				if .Clicked in ansuz.tree_leaf(&mgr, "sdl.odin", selected = tree_selected == 4, icon = .Document, is_last = true, row_height = 26, font = opensans) {
					tree_selected = 4
				}
			}
			ansuz.tree_node_end(&mgr)
		}
		ansuz.tree_node_end(&mgr)

		notes_open, notes_node := ansuz.tree_node_begin(
			&mgr,
			"Notes",
			&tree_notes_expanded,
			selected = tree_selected == 6,
			is_last = true,
			row_height = 26,
			font = opensans,
		)
		if .Clicked in notes_node {tree_selected = 6}
		if notes_open {
			if .Clicked in ansuz.tree_leaf(&mgr, "Ideas", selected = tree_selected == 7, icon = .Document, row_height = 26, font = opensans) {
				tree_selected = 7
			}
			if .Clicked in ansuz.tree_leaf(&mgr, "Todo", selected = tree_selected == 8, icon = .Document, is_last = true, row_height = 26, font = opensans) {
				tree_selected = 8
			}
		}
		ansuz.tree_node_end(&mgr)

		ansuz.tree_end(&mgr)
		ansuz.flex_end(&mgr)
		ansuz.flex_end(&mgr)

		ansuz.flex_end(&mgr)

		ansuz.scroll_end(&mgr) // end outer scroll

		if modal_visible {
			ansuz.push_id(&mgr, "desktop-modal")
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
		free_all(context.temp_allocator)
	}
}

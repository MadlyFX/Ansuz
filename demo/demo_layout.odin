package demo

import "core:fmt"
import ogui "../ogui"
import backend "../backend_sdl"

main :: proc() {
	sdl := backend.create(900, 800, "OGUI Demo")
	if !sdl.init(&sdl, sdl.width, sdl.height) {
		return
	}
	defer sdl.shutdown(&sdl)

	mgr: ogui.Manager
	ogui.init(&mgr, &sdl)
	defer ogui.shutdown(&mgr)

	// Create a procedural test image (a gradient)
	IMG_W :: i32(64)
	IMG_H :: i32(64)
	img_pixels: [IMG_W * IMG_H * 4]u8
	for y in 0..<IMG_H {
		for x in 0..<IMG_W {
			idx := (y * IMG_W + x) * 4
			img_pixels[idx + 0] = u8(x * 4)
			img_pixels[idx + 1] = u8(y * 4)
			img_pixels[idx + 2] = u8((x + y) * 2)
			img_pixels[idx + 3] = 255
		}
	}
	test_image := backend.create_image(&sdl, img_pixels[:], IMG_W, IMG_H)
	defer backend.destroy_image(test_image)

	// Application state
	click_count := 0
	slider_val: f32 = 0.5
	r_val: f32 = 0.3
	g_val: f32 = 0.7
	b_val: f32 = 0.5
	check_a := true
	check_b := false
	selected_item := 0
	options := [?]string{"Option A", "Option B", "Option C", "Option D"}
	anim_val: f32 = 0
	bounce_val: f32 = 50

	input_buf: [dynamic]u8
	defer delete(input_buf)
	append(&input_buf, ..transmute([]u8)string("Hello, OGUI!"))

	multi_buf: [dynamic]u8
	defer delete(multi_buf)
	append(&multi_buf, ..transmute([]u8)string("Line 1\nLine 2\nLine 3"))

	for !ogui.should_quit(&mgr) {
		ogui.frame_begin(&mgr)

		ogui.scroll_begin(&mgr, gap = 14, size = {ogui.SIZE_GROW, ogui.SIZE_GROW}, padding = {20, 24, 20, 24})

		ogui.heading(&mgr, "OGUI Demo")
		ogui.label(&mgr, "A cross-platform UI framework in Odin", color = ogui.THEME_TEXT_DIM)

		// --- Buttons ---
		ogui.label(&mgr, "Buttons", scale = 2.5, color = ogui.COLOR_WHITE)
		ogui.flex_begin(&mgr, axis = .Horizontal, gap = 10, size = {ogui.SIZE_GROW, ogui.SIZE_FIT}, align = .Center)
		if .Clicked in ogui.button(&mgr, "Click Me") { click_count += 1 }
		if .Clicked in ogui.button(&mgr, "Reset") { click_count = 0 }
		ogui.label(&mgr, fmt.tprintf("Clicks: %d", click_count), padding = {6, 12, 6, 12})
		ogui.flex_end(&mgr)

		// --- Sliders ---
		ogui.label(&mgr, "Sliders", scale = 2.5, color = ogui.COLOR_WHITE)
		ogui.slider_labeled(&mgr, "Value", &slider_val, 0, 1)

		ogui.flex_begin(&mgr, axis = .Horizontal, gap = 16, size = {ogui.SIZE_GROW, ogui.SIZE_FIT}, align = .Center)
		ogui.flex_begin(&mgr, axis = .Vertical, gap = 4, size = {ogui.SIZE_GROW, ogui.SIZE_FIT})
		ogui.slider_labeled(&mgr, "R", &r_val, 0, 1)
		ogui.slider_labeled(&mgr, "G", &g_val, 0, 1)
		ogui.slider_labeled(&mgr, "B", &b_val, 0, 1)
		ogui.flex_end(&mgr)
		preview_color := ogui.Color{u8(r_val * 255), u8(g_val * 255), u8(b_val * 255), 255}
		ogui.box(&mgr, size = {ogui.size_fixed(60), ogui.size_fixed(60)}, bg_color = preview_color)
		ogui.flex_end(&mgr)

		// --- Checkboxes + Dropdown side by side ---
		ogui.flex_begin(&mgr, axis = .Horizontal, gap = 40, size = {ogui.SIZE_GROW, ogui.SIZE_FIT})

		ogui.flex_begin(&mgr, axis = .Vertical, gap = 6, size = {ogui.SIZE_FIT, ogui.SIZE_FIT})
		ogui.label(&mgr, "Checkboxes", scale = 2.5, color = ogui.COLOR_WHITE)
		ogui.checkbox(&mgr, "Enable feature A", &check_a)
		ogui.checkbox(&mgr, "Enable feature B", &check_b)
		ogui.flex_end(&mgr)

		ogui.flex_begin(&mgr, axis = .Vertical, gap = 6, size = {ogui.SIZE_FIT, ogui.SIZE_FIT})
		ogui.label(&mgr, "Dropdown", scale = 2.5, color = ogui.COLOR_WHITE)
		ogui.dropdown(&mgr, &selected_item, options[:], size = ogui.FIXED_200_30)
		ogui.label(&mgr, fmt.tprintf("Selected: %s", options[selected_item]), color = ogui.THEME_TEXT_DIM)
		ogui.flex_end(&mgr)

		ogui.flex_end(&mgr)

		// --- Text Input ---
		ogui.label(&mgr, "Text Input", scale = 2.5, color = ogui.COLOR_WHITE)
		ogui.text_input(&mgr, &input_buf, placeholder = "Type here...", size = {ogui.size_fixed(300), ogui.SIZE_FIT})
		ogui.label(&mgr, fmt.tprintf("Content: %s", string(input_buf[:])), color = ogui.THEME_TEXT_DIM)

		ogui.label(&mgr, "Multi-line", scale = 2.5, color = ogui.COLOR_WHITE)
		ogui.text_input(&mgr, &multi_buf, multiline = true, size = {ogui.SIZE_GROW, ogui.size_fixed(80)})

		// --- Animations ---
		ogui.label(&mgr, "Animations", scale = 2.5, color = ogui.COLOR_WHITE)
		ogui.flex_begin(&mgr, axis = .Horizontal, gap = 10, size = {ogui.SIZE_GROW, ogui.SIZE_FIT}, align = .Center)
		if .Clicked in ogui.button(&mgr, "Ease Out") {
			ogui.animate_f32(&mgr, &anim_val, 1 if anim_val < 0.5 else 0, duration = 0.5, easing = .Ease_Out_Cubic)
		}
		if .Clicked in ogui.button(&mgr, "Bounce") {
			ogui.animate_f32(&mgr, &bounce_val, 300 if bounce_val < 150 else 50, duration = 0.8, easing = .Ease_Out_Bounce)
		}
		if .Clicked in ogui.button(&mgr, "Elastic") {
			ogui.animate_f32(&mgr, &anim_val, 1 if anim_val < 0.5 else 0, duration = 0.7, easing = .Ease_Out_Elastic)
		}
		ogui.flex_end(&mgr)

		ogui.flex_begin(&mgr, axis = .Horizontal, size = {ogui.SIZE_GROW, ogui.size_fixed(16)}, bg_color = ogui.Color{40, 43, 50, 255})
		ogui.box(&mgr, size = {ogui.size_pct(anim_val), ogui.SIZE_GROW}, bg_color = ogui.COLOR_BLUE)
		ogui.flex_end(&mgr)

		ogui.box(&mgr, size = {ogui.size_fixed(bounce_val), ogui.size_fixed(20)}, bg_color = ogui.COLOR_MAGENTA)

		// --- Image ---
		ogui.label(&mgr, "Image", scale = 2.5, color = ogui.COLOR_WHITE)
		ogui.flex_begin(&mgr, axis = .Horizontal, gap = 16, align = .Center, size = {ogui.SIZE_GROW, ogui.SIZE_FIT})
		ogui.image(&mgr, test_image)
		ogui.image(&mgr, test_image, size = {ogui.size_fixed(128), ogui.size_fixed(128)})
		ogui.label(&mgr, "Procedural gradient", color = ogui.THEME_TEXT_DIM)
		ogui.flex_end(&mgr)

		// --- Scrollbox ---
		ogui.label(&mgr, "Scrollbox", scale = 2.5, color = ogui.COLOR_WHITE)
		ogui.scroll_begin(&mgr, gap = 4, size = {ogui.SIZE_GROW, ogui.size_fixed(150)},
			padding = {8, 8, 8, 8}, bg_color = ogui.Color{40, 43, 50, 255})
		for i in 0..<20 {
			ogui.push_id(&mgr, i)
			ogui.label(&mgr, fmt.tprintf("Scrollable item %d", i + 1), padding = {4, 8, 4, 8})
			ogui.pop_id(&mgr)
		}
		ogui.scroll_end(&mgr)

		ogui.scroll_end(&mgr) // end outer scroll

		ogui.frame_end(&mgr)
	}
}

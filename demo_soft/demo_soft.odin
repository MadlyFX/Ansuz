package demo_soft

// Software renderer demo.
// Renders the UI into a raw pixel framebuffer (like an embedded display),
// then copies it to an SDL window so you can see the result on desktop.
// On a real microcontroller, you'd send the framebuffer to your display
// (SPI, I2C, parallel, etc.) instead of SDL.

import SDL "vendor:sdl2"
import ogui "../ogui"
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

	// Initialize OGUI
	mgr: ogui.Manager
	ogui.init(&mgr, &backend)
	defer ogui.shutdown(&mgr)

	// --- SDL setup (for desktop visualization only) ---
	SDL.Init({.VIDEO})
	defer SDL.Quit()

	// Window is 2x the framebuffer for visibility
	SCALE :: 2
	window := SDL.CreateWindow(
		"OGUI Software Renderer (320x240)",
		SDL.WINDOWPOS_CENTERED, SDL.WINDOWPOS_CENTERED,
		DISPLAY_W * SCALE, DISPLAY_H * SCALE,
		{.SHOWN},
	)
	defer SDL.DestroyWindow(window)

	renderer := SDL.CreateRenderer(window, -1, {.ACCELERATED, .PRESENTVSYNC})
	defer SDL.DestroyRenderer(renderer)

	texture := SDL.CreateTexture(renderer, .RGBA32, .STREAMING, DISPLAY_W, DISPLAY_H)
	defer SDL.DestroyTexture(texture)

	// Application state
	slider_val: f32 = 0.5
	check_a := true
	check_b := false

	running := true
	for running {
		// Poll SDL events (since software backend has no event polling)
		for e: SDL.Event; SDL.PollEvent(&e); /**/ {
			#partial switch e.type {
			case .QUIT:
				running = false
			case .KEYDOWN:
				if e.key.keysym.sym == .ESCAPE { running = false }
			case .MOUSEMOTION:
				// Scale mouse coordinates from window space to framebuffer space
				mgr.input.mouse_x = f32(e.motion.x) / SCALE
				mgr.input.mouse_y = f32(e.motion.y) / SCALE
			case .MOUSEBUTTONDOWN:
				if e.button.button == SDL.BUTTON_LEFT { mgr.input.mouse_left = true }
			case .MOUSEBUTTONUP:
				if e.button.button == SDL.BUTTON_LEFT { mgr.input.mouse_left = false }
			}
		}

		// --- Render the UI into the framebuffer ---
		ogui.frame_begin(&mgr)

		ogui.flex_begin(&mgr, axis = .Vertical, gap = 6, padding = {8, 8, 8, 8})

		ogui.label(&mgr, "OGUI Embedded", scale = 2, color = ogui.COLOR_WHITE)
		ogui.label(&mgr, "320x240 Software Renderer", scale = 1, color = ogui.THEME_TEXT_DIM)

		// Buttons
		ogui.flex_begin(&mgr, axis = .Horizontal, gap = 4, size = {ogui.SIZE_GROW, ogui.SIZE_FIT}, align = .Center)
		ogui.button(&mgr, "OK", padding = {3, 8, 3, 8})
		ogui.button(&mgr, "Cancel", padding = {3, 8, 3, 8})
		ogui.flex_end(&mgr)

		// Slider
		ogui.slider_labeled(&mgr, "Vol", &slider_val, 0, 1, format = "%.0f%%")

		// Checkboxes
		ogui.checkbox(&mgr, "WiFi", &check_a)
		ogui.checkbox(&mgr, "BT", &check_b)

		// Color boxes showing layout still works at small resolution
		ogui.flex_begin(&mgr, axis = .Horizontal, gap = 4, size = {ogui.SIZE_GROW, ogui.size_fixed(30)})
		ogui.box(&mgr, size = {ogui.size_grow(), ogui.SIZE_GROW}, bg_color = ogui.COLOR_RED)
		ogui.box(&mgr, size = {ogui.size_grow(2), ogui.SIZE_GROW}, bg_color = ogui.COLOR_GREEN)
		ogui.box(&mgr, size = {ogui.size_grow(), ogui.SIZE_GROW}, bg_color = ogui.COLOR_BLUE)
		ogui.flex_end(&mgr)

		ogui.flex_end(&mgr)

		ogui.frame_end(&mgr)

		// --- Copy framebuffer to SDL texture and display ---
		SDL.UpdateTexture(texture, nil, raw_data(framebuffer[:]), DISPLAY_W * 4)
		SDL.RenderClear(renderer)
		SDL.RenderCopy(renderer, texture, nil, nil)  // Stretches to window size (2x)
		SDL.RenderPresent(renderer)
	}
}

package ogui_backend_sdl

import "core:c"
import "core:fmt"
import SDL "vendor:sdl2"
import ogui "../ogui"

// --- SDL2 Backend Data ---

SDL_Data :: struct {
	window:       ^SDL.Window,
	renderer:     ^SDL.Renderer,
	font_texture: ^SDL.Texture,  // 16x16 grid of 5x7 glyphs = 80x112 atlas
}

// Create and initialize an SDL2 backend.
create :: proc(width: i32 = 960, height: i32 = 540, title: cstring = "OGUI") -> ogui.Backend {
	backend: ogui.Backend
	backend.width  = width
	backend.height = height

	data := new(SDL_Data)
	backend.user_data = data

	backend.init         = sdl_init
	backend.shutdown     = sdl_shutdown
	backend.begin_frame  = sdl_begin_frame
	backend.end_frame    = sdl_end_frame
	backend.execute      = sdl_execute
	backend.measure_text = sdl_measure_text
	backend.poll_events  = sdl_poll_events

	return backend
}

// --- Backend proc implementations ---

sdl_init :: proc(backend: ^ogui.Backend, width, height: i32) -> bool {
	if err := SDL.Init({.VIDEO}); err != 0 {
		fmt.eprintln("SDL.Init failed:", SDL.GetError())
		return false
	}

	data := cast(^SDL_Data)backend.user_data

	data.window = SDL.CreateWindow(
		"OGUI",
		SDL.WINDOWPOS_CENTERED, SDL.WINDOWPOS_CENTERED,
		width, height,
		{.SHOWN, .RESIZABLE},
	)
	if data.window == nil {
		fmt.eprintln("SDL.CreateWindow failed:", SDL.GetError())
		return false
	}

	data.renderer = SDL.CreateRenderer(data.window, -1, {.ACCELERATED, .PRESENTVSYNC})
	if data.renderer == nil {
		fmt.eprintln("SDL.CreateRenderer failed:", SDL.GetError())
		return false
	}

	SDL.SetRenderDrawBlendMode(data.renderer, .BLEND)

	// Create font atlas texture (16 cols x 16 rows of 6x9 cells = 96x144 pixels)
	ATLAS_W :: 16 * ogui.FONT_CHAR_WIDTH    // 96
	ATLAS_H :: 16 * ogui.FONT_CHAR_HEIGHT   // 144

	data.font_texture = SDL.CreateTexture(
		data.renderer,
		.RGBA32, .TARGET,
		ATLAS_W, ATLAS_H,
	)
	if data.font_texture == nil {
		fmt.eprintln("Failed to create font texture:", SDL.GetError())
		return false
	}
	SDL.SetTextureBlendMode(data.font_texture, .BLEND)

	// Render font glyphs into the atlas
	pixels: [ATLAS_W * ATLAS_H][4]u8
	for ch in 0..<256 {
		cell_x := (ch % 16) * ogui.FONT_CHAR_WIDTH
		cell_y := (ch / 16) * ogui.FONT_CHAR_HEIGHT
		for col in 0..<ogui.FONT_GLYPH_WIDTH {
			for row in 0..<ogui.FONT_GLYPH_HEIGHT {
				if ogui.font_pixel(u8(ch), col, row) {
					px := cell_x + col
					py := cell_y + row
					idx := py * ATLAS_W + px
					pixels[idx] = {0xFF, 0xFF, 0xFF, 0xFF}
				}
			}
		}
	}
	SDL.UpdateTexture(data.font_texture, nil, &pixels, ATLAS_W * 4)

	backend.width = width
	backend.height = height

	SDL.StartTextInput()

	return true
}

sdl_shutdown :: proc(backend: ^ogui.Backend) {
	data := cast(^SDL_Data)backend.user_data
	if data.font_texture != nil {
		SDL.DestroyTexture(data.font_texture)
	}
	if data.renderer != nil {
		SDL.DestroyRenderer(data.renderer)
	}
	if data.window != nil {
		SDL.DestroyWindow(data.window)
	}
	SDL.Quit()
	free(data)
}

sdl_begin_frame :: proc(backend: ^ogui.Backend) {
	data := cast(^SDL_Data)backend.user_data
	SDL.SetRenderDrawColor(data.renderer, 30, 30, 34, 255)
	SDL.RenderClear(data.renderer)
}

sdl_end_frame :: proc(backend: ^ogui.Backend) {
	data := cast(^SDL_Data)backend.user_data
	SDL.RenderPresent(data.renderer)
}

sdl_execute :: proc(backend: ^ogui.Backend, cmd: ogui.Draw_Command) {
	data := cast(^SDL_Data)backend.user_data

	switch c in cmd {
	case ogui.Draw_Filled_Rect:
		SDL.SetRenderDrawColor(data.renderer, c.color.r, c.color.g, c.color.b, c.color.a)
		r := SDL.Rect{
			i32(c.rect.x),
			i32(c.rect.y),
			i32(c.rect.w),
			i32(c.rect.h),
		}
		SDL.RenderFillRect(data.renderer, &r)

	case ogui.Draw_Rect_Outline:
		SDL.SetRenderDrawColor(data.renderer, c.color.r, c.color.g, c.color.b, c.color.a)
		r := SDL.Rect{
			i32(c.rect.x),
			i32(c.rect.y),
			i32(c.rect.w),
			i32(c.rect.h),
		}
		SDL.RenderDrawRect(data.renderer, &r)

	case ogui.Draw_Line:
		SDL.SetRenderDrawColor(data.renderer, c.color.r, c.color.g, c.color.b, c.color.a)
		SDL.RenderDrawLine(
			data.renderer,
			i32(c.p0.x), i32(c.p0.y),
			i32(c.p1.x), i32(c.p1.y),
		)

	case ogui.Draw_Text:
		SDL.SetTextureColorMod(data.font_texture, c.color.r, c.color.g, c.color.b)
		SDL.SetTextureAlphaMod(data.font_texture, c.color.a)

		scale := c.size  // size field is used as scale factor
		char_w := i32(f32(ogui.FONT_CHAR_WIDTH) * scale)
		char_h := i32(f32(ogui.FONT_CHAR_HEIGHT) * scale)
		cursor_x := i32(c.pos.x)
		cursor_y := i32(c.pos.y)
		start_x := cursor_x

		for ch in c.text {
			if ch == '\n' {
				cursor_x = start_x
				cursor_y += char_h
				continue
			}

			idx := int(ch) if int(ch) < 256 else int('?')
			src_x := i32((idx % 16) * ogui.FONT_CHAR_WIDTH)
			src_y := i32((idx / 16) * ogui.FONT_CHAR_HEIGHT)

			src := SDL.Rect{src_x, src_y, ogui.FONT_GLYPH_WIDTH, ogui.FONT_GLYPH_HEIGHT}
			dst := SDL.Rect{cursor_x, cursor_y, i32(f32(ogui.FONT_GLYPH_WIDTH) * scale), i32(f32(ogui.FONT_GLYPH_HEIGHT) * scale)}
			SDL.RenderCopy(data.renderer, data.font_texture, &src, &dst)

			cursor_x += char_w
		}

	case ogui.Draw_Clip:
		r := SDL.Rect{
			i32(c.rect.x),
			i32(c.rect.y),
			i32(c.rect.w),
			i32(c.rect.h),
		}
		SDL.RenderSetClipRect(data.renderer, &r)

	case ogui.Draw_Image:
		if c.handle != nil {
			tex := cast(^SDL.Texture)c.handle
			SDL.SetTextureColorMod(tex, c.tint.r, c.tint.g, c.tint.b)
			SDL.SetTextureAlphaMod(tex, c.tint.a)
			dst := SDL.Rect{i32(c.rect.x), i32(c.rect.y), i32(c.rect.w), i32(c.rect.h)}
			SDL.RenderCopy(data.renderer, tex, nil, &dst)
		}
	}
}

// Create an image texture from raw RGBA pixel data.
// Returns an Image_Handle that can be passed to the image widget.
create_image :: proc(backend: ^ogui.Backend, pixels: []u8, width, height: i32) -> ogui.Image_Handle {
	data := cast(^SDL_Data)backend.user_data
	tex := SDL.CreateTexture(data.renderer, .RGBA32, .STATIC, width, height)
	if tex == nil { return ogui.IMAGE_NONE }
	SDL.SetTextureBlendMode(tex, .BLEND)
	SDL.UpdateTexture(tex, nil, raw_data(pixels), width * 4)
	return ogui.Image_Handle{ptr = tex, width = width, height = height}
}

// Destroy an image texture.
destroy_image :: proc(img: ogui.Image_Handle) {
	if img.ptr != nil {
		SDL.DestroyTexture(cast(^SDL.Texture)img.ptr)
	}
}

sdl_measure_text :: proc(backend: ^ogui.Backend, text: string, font: ogui.Font_Handle, size: f32) -> ogui.Vec2 {
	// Placeholder: estimate 8px per character width, size for height
	return {f32(len(text)) * 8, size}
}

sdl_poll_events :: proc(backend: ^ogui.Backend, input: ^ogui.Input_State) -> bool {
	data := cast(^SDL_Data)backend.user_data
	quit := false

	// Reset per-frame edge-triggered input events
	input.mouse_left_pressed = false
	input.text_char_len = 0
	input.key_backspace = false
	input.key_delete = false
	input.key_left = false
	input.key_right = false
	input.key_up = false
	input.key_down = false
	input.key_home = false
	input.key_end = false
	input.key_enter = false
	input.mouse_scroll_y = 0

	for e: SDL.Event; SDL.PollEvent(&e); /**/ {
		#partial switch e.type {
		case .QUIT:
			quit = true

		case .WINDOWEVENT:
			#partial switch e.window.event {
			case .RESIZED, .SIZE_CHANGED:
				backend.width = e.window.data1
				backend.height = e.window.data2
			}

		case .MOUSEMOTION:
			input.mouse_x = f32(e.motion.x)
			input.mouse_y = f32(e.motion.y)

		case .MOUSEBUTTONDOWN:
			switch e.button.button {
			case SDL.BUTTON_LEFT:
				input.mouse_left = true
				input.mouse_left_pressed = true
			case SDL.BUTTON_RIGHT:  input.mouse_right = true
			case SDL.BUTTON_MIDDLE: input.mouse_middle = true
			}

		case .MOUSEBUTTONUP:
			switch e.button.button {
			case SDL.BUTTON_LEFT:   input.mouse_left = false
			case SDL.BUTTON_RIGHT:  input.mouse_right = false
			case SDL.BUTTON_MIDDLE: input.mouse_middle = false
			}

		case .MOUSEWHEEL:
			input.mouse_scroll_y = f32(e.wheel.y)

		case .TEXTINPUT:
			for i in 0..<32 {
				ch := e.text.text[i]
				if ch == 0 { break }
				if ch >= 32 && input.text_char_len < len(input.text_chars) {
					input.text_chars[input.text_char_len] = u8(ch)
					input.text_char_len += 1
				}
			}

		case .KEYDOWN:
			#partial switch e.key.keysym.sym {
			case .ESCAPE:
				quit = true
			case .BACKSPACE:
				input.key_backspace = true
			case .DELETE:
				input.key_delete = true
			case .LEFT:
				input.key_left = true
			case .RIGHT:
				input.key_right = true
			case .UP:
				input.key_up = true
			case .DOWN:
				input.key_down = true
			case .HOME:
				input.key_home = true
			case .END:
				input.key_end = true
			case .RETURN, .KP_ENTER:
				input.key_enter = true
			case .LSHIFT, .RSHIFT:
				input.key_shift = true
			case .LCTRL, .RCTRL:
				input.key_ctrl = true
			}

		case .KEYUP:
			#partial switch e.key.keysym.sym {
			case .LSHIFT, .RSHIFT:
				input.key_shift = false
			case .LCTRL, .RCTRL:
				input.key_ctrl = false
			}
		}
	}

	return quit
}

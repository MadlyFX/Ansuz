package ansuz_backend_sdl

import "core:fmt"
import SDL "vendor:sdl3"
import ansuz "../ansuz"

// --- SDL3 Backend Data ---

// Per-font GPU data for loaded TTF fonts.
SDL_Font :: struct {
	texture:        ^SDL.Texture,
	glyphs:         [256]ansuz.Font_Glyph_Info,
	glyphs_unicode: map[rune]ansuz.Font_Glyph_Info,
	atlas_width:    i32,
	atlas_height:   i32,
	ascent:         f32,
	line_height:    f32,
}

SDL_Data :: struct {
	window:              ^SDL.Window,
	renderer:            ^SDL.Renderer,
	builtin_font_texture: ^SDL.Texture,  // 16x16 grid of 5x7 glyphs = 80x112 atlas
	loaded_fonts:        [dynamic]SDL_Font,
}

// Create and initialize an SDL3 backend.
create :: proc(width: i32 = 960, height: i32 = 540, title: cstring = "ansuz") -> ansuz.Backend {
	backend: ansuz.Backend
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
	backend.load_font    = sdl_load_font

	return backend
}

// --- Backend proc implementations ---

sdl_init :: proc(backend: ^ansuz.Backend, width, height: i32) -> bool {
	if !SDL.Init({.VIDEO}) {
		fmt.eprintln("SDL.Init failed:", SDL.GetError())
		return false
	}

	data := cast(^SDL_Data)backend.user_data

	data.window = SDL.CreateWindow(
		"ansuz",
		width, height,
		{.RESIZABLE},
	)
	if data.window == nil {
		fmt.eprintln("SDL.CreateWindow failed:", SDL.GetError())
		return false
	}

	data.renderer = SDL.CreateRenderer(data.window, nil)
	if data.renderer == nil {
		fmt.eprintln("SDL.CreateRenderer failed:", SDL.GetError())
		return false
	}

	SDL.SetRenderVSync(data.renderer, 1)
	SDL.SetRenderDrawBlendMode(data.renderer, SDL.BLENDMODE_BLEND)

	// Create font atlas texture (16 cols x 16 rows of 6x9 cells = 96x144 pixels)
	ATLAS_W :: 16 * ansuz.FONT_CHAR_WIDTH    // 96
	ATLAS_H :: 16 * ansuz.FONT_CHAR_HEIGHT   // 144

	data.builtin_font_texture = SDL.CreateTexture(
		data.renderer,
		.RGBA32, .TARGET,
		ATLAS_W, ATLAS_H,
	)
	if data.builtin_font_texture == nil {
		fmt.eprintln("Failed to create font texture:", SDL.GetError())
		return false
	}
	SDL.SetTextureBlendMode(data.builtin_font_texture, SDL.BLENDMODE_BLEND)
	SDL.SetTextureScaleMode(data.builtin_font_texture, .NEAREST)

	// Render font glyphs into the atlas
	pixels: [ATLAS_W * ATLAS_H][4]u8
	for ch in 0..<256 {
		cell_x := (ch % 16) * ansuz.FONT_CHAR_WIDTH
		cell_y := (ch / 16) * ansuz.FONT_CHAR_HEIGHT
		for col in 0..<ansuz.FONT_GLYPH_WIDTH {
			for row in 0..<ansuz.FONT_GLYPH_HEIGHT {
				if ansuz.font_pixel(u8(ch), col, row) {
					px := cell_x + col
					py := cell_y + row
					idx := py * ATLAS_W + px
					pixels[idx] = {0xFF, 0xFF, 0xFF, 0xFF}
				}
			}
		}
	}
	SDL.UpdateTexture(data.builtin_font_texture, nil, &pixels, ATLAS_W * 4)

	backend.width = width
	backend.height = height

	_ = SDL.StartTextInput(data.window)

	return true
}

// Upload a TTF font atlas as an SDL texture for rendering.
sdl_load_font :: proc(backend: ^ansuz.Backend, font: ^ansuz.Font, handle: ansuz.Font_Handle) {
	data := cast(^SDL_Data)backend.user_data

	w := font.atlas_width
	h := font.atlas_height

	// Create RGBA texture from grayscale atlas (white pixels + alpha from atlas)
	tex := SDL.CreateTexture(data.renderer, .RGBA32, .STATIC, w, h)
	if tex == nil { return }
	SDL.SetTextureBlendMode(tex, SDL.BLENDMODE_BLEND)
	SDL.SetTextureScaleMode(tex, .LINEAR)  // Smooth filtering for antialiased TTF

	// Convert grayscale to RGBA
	pixel_count := int(w * h)
	rgba := make([]u8, pixel_count * 4)
	defer delete(rgba)
	for i in 0..<pixel_count {
		rgba[i * 4 + 0] = 255
		rgba[i * 4 + 1] = 255
		rgba[i * 4 + 2] = 255
		rgba[i * 4 + 3] = font.atlas_pixels[i]
	}
	SDL.UpdateTexture(tex, nil, raw_data(rgba), w * 4)

	// Store font entry with glyph metrics
	entry: SDL_Font
	entry.texture      = tex
	entry.atlas_width  = w
	entry.atlas_height = h
	entry.ascent       = font.ascent
	entry.line_height  = font.line_height
	for i in 0..<256 {
		entry.glyphs[i] = font.glyphs[i]
	}
	if len(font.glyphs_unicode) > 0 {
		entry.glyphs_unicode = make(map[rune]ansuz.Font_Glyph_Info, len(font.glyphs_unicode))
		for k, v in font.glyphs_unicode {
			entry.glyphs_unicode[k] = v
		}
	}

	append(&data.loaded_fonts, entry)
}

sdl_shutdown :: proc(backend: ^ansuz.Backend) {
	data := cast(^SDL_Data)backend.user_data
	if data.builtin_font_texture != nil {
		SDL.DestroyTexture(data.builtin_font_texture)
	}
	for &f in data.loaded_fonts {
		if f.texture != nil {
			SDL.DestroyTexture(f.texture)
		}
		delete(f.glyphs_unicode)
	}
	delete(data.loaded_fonts)
	if data.renderer != nil {
		SDL.DestroyRenderer(data.renderer)
	}
	if data.window != nil {
		SDL.DestroyWindow(data.window)
	}
	SDL.Quit()
	free(data)
}

sdl_begin_frame :: proc(backend: ^ansuz.Backend) {
	data := cast(^SDL_Data)backend.user_data
	SDL.SetRenderDrawColor(data.renderer, 30, 30, 34, 255)
	SDL.RenderClear(data.renderer)
}

sdl_end_frame :: proc(backend: ^ansuz.Backend) {
	data := cast(^SDL_Data)backend.user_data
	SDL.RenderPresent(data.renderer)
}

sdl_execute :: proc(backend: ^ansuz.Backend, cmd: ansuz.Draw_Command) {
	data := cast(^SDL_Data)backend.user_data

	switch c in cmd {
	case ansuz.Draw_Filled_Rect:
		SDL.SetRenderDrawColor(data.renderer, c.color.r, c.color.g, c.color.b, c.color.a)
		r := SDL.FRect{
			f32(c.rect.x),
			f32(c.rect.y),
			f32(c.rect.w),
			f32(c.rect.h),
		}
		SDL.RenderFillRect(data.renderer, &r)
		

	case ansuz.Draw_Rect_Outline:
		SDL.SetRenderDrawColor(data.renderer, c.color.r, c.color.g, c.color.b, c.color.a)
		r := SDL.FRect{
			f32(c.rect.x),
			f32(c.rect.y),
			f32(c.rect.w),
			f32(c.rect.h),
		}
		SDL.RenderRect(data.renderer, &r)

	case ansuz.Draw_Line:
		SDL.SetRenderDrawColor(data.renderer, c.color.r, c.color.g, c.color.b, c.color.a)
		SDL.RenderLine(
			data.renderer,
			f32(c.p0.x), f32(c.p0.y),
			f32(c.p1.x), f32(c.p1.y),
		)

	case ansuz.Draw_Text:
		font_handle := c.font
		scale := c.size

		if font_handle == ansuz.FONT_BUILTIN || int(font_handle) - 1 >= len(data.loaded_fonts) {
			// Builtin bitmap font rendering
			SDL.SetTextureColorMod(data.builtin_font_texture, c.color.r, c.color.g, c.color.b)
			SDL.SetTextureAlphaMod(data.builtin_font_texture, c.color.a)

			char_w := f32(ansuz.FONT_CHAR_WIDTH) * scale
			char_h := f32(ansuz.FONT_CHAR_HEIGHT) * scale
			cursor_x := f32(c.pos.x)
			cursor_y := f32(c.pos.y)
			start_x := cursor_x

			for ch in c.text {
				if ch == '\n' {
					cursor_x = start_x
					cursor_y += char_h
					continue
				}

				idx := int(ch) if int(ch) < 256 else int('?')
				src_x := f32((idx % 16) * ansuz.FONT_CHAR_WIDTH)
				src_y := f32((idx / 16) * ansuz.FONT_CHAR_HEIGHT)

				src := SDL.FRect{src_x, src_y, f32(ansuz.FONT_GLYPH_WIDTH), f32(ansuz.FONT_GLYPH_HEIGHT)}
				dst := SDL.FRect{cursor_x, cursor_y, f32(ansuz.FONT_GLYPH_WIDTH) * scale, f32(ansuz.FONT_GLYPH_HEIGHT) * scale}
				SDL.RenderTexture(data.renderer, data.builtin_font_texture, &src, &dst)

				cursor_x += char_w
			}
		} else {
			// TTF font atlas rendering
			font := &data.loaded_fonts[int(font_handle) - 1]
			SDL.SetTextureColorMod(font.texture, c.color.r, c.color.g, c.color.b)
			SDL.SetTextureAlphaMod(font.texture, c.color.a)

			cursor_x := f32(c.pos.x)
			cursor_y := f32(c.pos.y)
			start_x := cursor_x

			for ch in c.text {
				if ch == '\n' {
					cursor_x = start_x
					cursor_y += font.line_height * scale
					continue
				}

				g_val := font.glyphs[int(ch)] if int(ch) < 256 else (font.glyphs_unicode[ch] if ch in font.glyphs_unicode else font.glyphs[int('?')])
				g := &g_val
				if g.atlas_w == 0 && g.atlas_h == 0 {
					cursor_x += g.advance * scale
					continue
				}

				src := SDL.FRect{
					f32(g.atlas_x), f32(g.atlas_y),
					f32(g.atlas_w), f32(g.atlas_h),
				}
				dst := SDL.FRect{
					cursor_x + g.x_offset * scale,
					cursor_y + (font.ascent + g.y_offset) * scale,
					f32(g.atlas_w) * scale,
					f32(g.atlas_h) * scale,
				}
				SDL.RenderTexture(data.renderer, font.texture, &src, &dst)

				cursor_x += g.advance * scale
			}
		}

	case ansuz.Draw_Clip:
		r := SDL.Rect{
			i32(c.rect.x),
			i32(c.rect.y),
			i32(c.rect.w),
			i32(c.rect.h),
		}
		SDL.SetRenderClipRect(data.renderer, &r)

	case ansuz.Draw_Image:
		if c.handle != nil {
			tex := cast(^SDL.Texture)c.handle
			SDL.SetTextureColorMod(tex, c.tint.r, c.tint.g, c.tint.b)
			SDL.SetTextureAlphaMod(tex, c.tint.a)
			dst := SDL.FRect{f32(c.rect.x), f32(c.rect.y), f32(c.rect.w), f32(c.rect.h)}
			SDL.RenderTexture(data.renderer, tex, nil, &dst)
		}
	}
}

// Create an image texture from pixel data with any channel count (1-4).
// Converts to RGBA32 internally for SDL. Returns an Image_Handle for the image widget.
create_image :: proc(backend: ^ansuz.Backend, pixels: []u8, width, height: i32, channels: i32 = 4) -> ansuz.Image_Handle {
	data := cast(^SDL_Data)backend.user_data
	pixel_count := int(width * height)

	rgba: []u8
	needs_free := false

	switch channels {
	case 4:
		rgba = pixels
	case 3:
		rgba = make([]u8, pixel_count * 4)
		needs_free = true
		for i in 0..<pixel_count {
			rgba[i * 4 + 0] = pixels[i * 3 + 0]
			rgba[i * 4 + 1] = pixels[i * 3 + 1]
			rgba[i * 4 + 2] = pixels[i * 3 + 2]
			rgba[i * 4 + 3] = 255
		}
	case 1:
		rgba = make([]u8, pixel_count * 4)
		needs_free = true
		for i in 0..<pixel_count {
			rgba[i * 4 + 0] = pixels[i]
			rgba[i * 4 + 1] = pixels[i]
			rgba[i * 4 + 2] = pixels[i]
			rgba[i * 4 + 3] = 255
		}
	case 2: // grayscale + alpha
		rgba = make([]u8, pixel_count * 4)
		needs_free = true
		for i in 0..<pixel_count {
			rgba[i * 4 + 0] = pixels[i * 2 + 0]
			rgba[i * 4 + 1] = pixels[i * 2 + 0]
			rgba[i * 4 + 2] = pixels[i * 2 + 0]
			rgba[i * 4 + 3] = pixels[i * 2 + 1]
		}
	case:
		return ansuz.IMAGE_NONE
	}
	defer if needs_free { delete(rgba) }

	tex := SDL.CreateTexture(data.renderer, .RGBA32, .STATIC, width, height)
	if tex == nil { return ansuz.IMAGE_NONE }
	SDL.SetTextureBlendMode(tex, SDL.BLENDMODE_BLEND)
	SDL.UpdateTexture(tex, nil, raw_data(rgba), width * 4)
	return ansuz.Image_Handle{ptr = tex, width = width, height = height}
}

// Destroy an image texture.
destroy_image :: proc(img: ansuz.Image_Handle) {
	if img.ptr != nil {
		SDL.DestroyTexture(cast(^SDL.Texture)img.ptr)
	}
}

sdl_measure_text :: proc(backend: ^ansuz.Backend, text: string, font: ansuz.Font_Handle, size: f32) -> ansuz.Vec2 {
	return ansuz.measure_text_builtin(text, size)
}

sdl_poll_events :: proc(backend: ^ansuz.Backend, input: ^ansuz.Input_State) -> bool {
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

		case .WINDOW_RESIZED, .WINDOW_PIXEL_SIZE_CHANGED:
			backend.width = e.window.data1
			backend.height = e.window.data2

		case .MOUSE_MOTION:
			input.mouse_x = e.motion.x
			input.mouse_y = e.motion.y

		case .MOUSE_BUTTON_DOWN:
			switch e.button.button {
			case SDL.BUTTON_LEFT:
				input.mouse_left = true
				input.mouse_left_pressed = true
			case SDL.BUTTON_RIGHT:  input.mouse_right = true
			case SDL.BUTTON_MIDDLE: input.mouse_middle = true
			}

		case .MOUSE_BUTTON_UP:
			switch e.button.button {
			case SDL.BUTTON_LEFT:   input.mouse_left = false
			case SDL.BUTTON_RIGHT:  input.mouse_right = false
			case SDL.BUTTON_MIDDLE: input.mouse_middle = false
			}

		case .MOUSE_WHEEL:
			input.mouse_scroll_y = e.wheel.y

		case .TEXT_INPUT:
			text_bytes := transmute([^]u8)e.text.text
			for i in 0..<256 {
				ch := text_bytes[i]
				if ch == 0 { break }
				if ch >= 32 && input.text_char_len < len(input.text_chars) {
					input.text_chars[input.text_char_len] = u8(ch)
					input.text_char_len += 1
				}
			}

		case .KEY_DOWN:
			#partial switch e.key.scancode {
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

		case .KEY_UP:
			#partial switch e.key.scancode {
			case .LSHIFT, .RSHIFT:
				input.key_shift = false
			case .LCTRL, .RCTRL:
				input.key_ctrl = false
			}
		}
	}

	return quit
}

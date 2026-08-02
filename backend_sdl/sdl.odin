package ansuz_backend_sdl

import "core:fmt"
import "core:math"
import "core:strings"
import "base:runtime"
import SDL "vendor:sdl3"
import ansuz "../ansuz"

// --- SDL3 Backend Data ---

// Per-font GPU data for antialiased TTF fonts.
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
	title:               cstring,
	pixel_density:       f32,
	clear_color:         ansuz.Color,
	file_drag_active:    bool,
	file_drop_completed: bool,
	builtin_font_texture: ^SDL.Texture,  // 16x16 grid of 5x7 glyphs = 80x112 atlas
	loaded_fonts:        [dynamic]SDL_Font,
	// Client-drawn title bar support. When borderless is set (before init) the
	// OS decoration is dropped and an SDL hit test turns the top strip into a
	// drag handle plus resizable borders. titlebar_height and controls_width are
	// in window (logical) coordinates and describe the draggable region: the top
	// `titlebar_height` pixels, excluding the rightmost `controls_width` pixels
	// where the app draws its own minimize/maximize/close buttons.
	borderless:          bool,
	titlebar_height:     i32,
	controls_width:      i32,
	// UI zoom: logical resolution is the window size divided by this factor, so a
	// zoom below 1 renders the whole UI smaller (see set_zoom). Mouse input is
	// divided by the same factor to stay in logical coordinates.
	zoom:                f32,
}

// Width of the invisible resize border around a borderless window, in logical px.
BORDERLESS_RESIZE_BORDER :: 6

// Create and initialize an SDL3 backend.
create :: proc(width: i32 = 960, height: i32 = 540, title: cstring = "ansuz") -> ansuz.Backend {
	backend: ansuz.Backend
	backend.width  = width
	backend.height = height

	data := new(SDL_Data)
	data.title = title
	data.clear_color = ansuz.Color{30, 30, 34, 255}
	data.zoom = 1
	backend.user_data = data

	backend.init         = sdl_init
	backend.shutdown     = sdl_shutdown
	backend.begin_frame  = sdl_begin_frame
	backend.end_frame    = sdl_end_frame
	backend.execute      = sdl_execute
	backend.measure_text = sdl_measure_text
	backend.poll_events  = sdl_poll_events
	backend.load_font    = sdl_load_font
	backend.set_clipboard_text = sdl_set_clipboard_text
	backend.get_clipboard_text = sdl_get_clipboard_text
	backend.open_url = sdl_open_url

	return backend
}

// Request a borderless (client-decorated) window. Call before init; the flag is
// read when the SDL window is created.
set_borderless :: proc(backend: ^ansuz.Backend, borderless: bool) {
	data := cast(^SDL_Data)backend.user_data
	if data != nil {
		data.borderless = borderless
	}
}

// Describe the draggable title bar for the hit test, in window (logical) pixels.
// height is the title bar strip along the top; controls_width is the button
// cluster on the right that must stay clickable (so it is not part of the drag
// region).
set_titlebar_hit_zones :: proc(backend: ^ansuz.Backend, height, controls_width: i32) {
	data := cast(^SDL_Data)backend.user_data
	if data != nil {
		data.titlebar_height = height
		data.controls_width = controls_width
	}
}

// Set the UI zoom. Everything lays out and draws in logical pixels; a zoom
// below 1 inflates the logical resolution relative to the window so the whole
// UI renders proportionally smaller. Window metrics are refreshed immediately
// so the next frame's root box already uses the new logical size.
set_zoom :: proc(backend: ^ansuz.Backend, zoom: f32) {
	data := cast(^SDL_Data)backend.user_data
	if data == nil {
		return
	}
	data.zoom = clamp(zoom, 0.25, 4)
	sdl_sync_window_metrics(backend)
}

// The raw OS window size in window coordinates, independent of any zoom. Hosts
// use it to decide the zoom itself (backend.width already has zoom applied).
window_size :: proc(backend: ^ansuz.Backend) -> (w, h: i32) {
	data := cast(^SDL_Data)backend.user_data
	if data == nil || data.window == nil {
		return backend.width, backend.height
	}
	if !SDL.GetWindowSize(data.window, &w, &h) {
		return backend.width, backend.height
	}
	return
}

// Reveal a window that was created hidden (borderless startup). Safe to call
// once the first frame has been presented.
window_show :: proc(backend: ^ansuz.Backend) {
	data := cast(^SDL_Data)backend.user_data
	if data != nil && data.window != nil {
		SDL.ShowWindow(data.window)
	}
}

window_minimize :: proc(backend: ^ansuz.Backend) {
	data := cast(^SDL_Data)backend.user_data
	if data != nil && data.window != nil {
		SDL.MinimizeWindow(data.window)
	}
}

// Keep the window above (or no longer above) all other windows. Safe to call
// every frame; SDL only re-stacks when the flag actually changes.
window_set_always_on_top :: proc(backend: ^ansuz.Backend, on_top: bool) {
	data := cast(^SDL_Data)backend.user_data
	if data != nil && data.window != nil {
		_ = SDL.SetWindowAlwaysOnTop(data.window, on_top)
	}
}

window_is_maximized :: proc(backend: ^ansuz.Backend) -> bool {
	data := cast(^SDL_Data)backend.user_data
	if data == nil || data.window == nil {
		return false
	}
	return .MAXIMIZED in SDL.GetWindowFlags(data.window)
}

window_toggle_maximize :: proc(backend: ^ansuz.Backend) {
	data := cast(^SDL_Data)backend.user_data
	if data == nil || data.window == nil {
		return
	}
	if .MAXIMIZED in SDL.GetWindowFlags(data.window) {
		SDL.RestoreWindow(data.window)
	} else {
		SDL.MaximizeWindow(data.window)
	}
}

// Ask the app to close by queuing an SDL quit, which the poll loop reports as a
// quit on the next frame — the same path the OS close button used to take.
window_request_close :: proc(backend: ^ansuz.Backend) {
	e := SDL.Event{type = .QUIT}
	_ = SDL.PushEvent(&e)
}

// OS hit test for the borderless window. area is in window (logical) coordinates.
sdl_hit_test :: proc "c" (win: ^SDL.Window, area: ^SDL.Point, userdata: rawptr) -> SDL.HitTestResult {
	data := cast(^SDL_Data)userdata
	w, h: i32
	if !SDL.GetWindowSize(win, &w, &h) {
		return .NORMAL
	}
	x := area.x
	y := area.y

	// Maximized windows are not resizable from their (screen-flush) edges.
	if .MAXIMIZED not_in SDL.GetWindowFlags(win) {
		b := i32(BORDERLESS_RESIZE_BORDER)
		left   := x < b
		right  := x >= w - b
		top    := y < b
		bottom := y >= h - b
		switch {
		case top && left:     return .RESIZE_TOPLEFT
		case top && right:    return .RESIZE_TOPRIGHT
		case bottom && left:  return .RESIZE_BOTTOMLEFT
		case bottom && right: return .RESIZE_BOTTOMRIGHT
		case left:            return .RESIZE_LEFT
		case right:           return .RESIZE_RIGHT
		case top:             return .RESIZE_TOP
		case bottom:          return .RESIZE_BOTTOM
		}
	}

	// The title bar strip drags the window, except over the control buttons.
	if y < data.titlebar_height && x < w - data.controls_width {
		return .DRAGGABLE
	}
	return .NORMAL
}

// --- Backend proc implementations ---

sdl_init :: proc(backend: ^ansuz.Backend, width, height: i32) -> bool {
	if !SDL.Init({.VIDEO}) {
		fmt.eprintln("SDL.Init failed:", SDL.GetError())
		return false
	}

	data := cast(^SDL_Data)backend.user_data

	window_flags := SDL.WindowFlags{.RESIZABLE, .HIGH_PIXEL_DENSITY}
	if data.borderless {
		// Start hidden so the host can paint the first frame before revealing the
		// window (see window_show); this avoids a black flash while fonts load and
		// the initial content is composited.
		window_flags += {.BORDERLESS, .HIDDEN}
	}
	data.window = SDL.CreateWindow(
		data.title,
		width, height,
		window_flags,
	)
	if data.window == nil {
		fmt.eprintln("SDL.CreateWindow failed:", SDL.GetError())
		return false
	}

	// With no OS chrome, an SDL hit test provides the window move/resize behavior
	// the decoration used to. It classifies the client-drawn title bar as a drag
	// handle and the window edges as resize borders.
	if data.borderless {
		SDL.SetWindowHitTest(data.window, sdl_hit_test, data)
	}

	data.renderer = SDL.CreateRenderer(data.window, nil)
	if data.renderer == nil {
		fmt.eprintln("SDL.CreateRenderer failed:", SDL.GetError())
		return false
	}

	SDL.SetRenderVSync(data.renderer, 1)
	SDL.SetRenderDrawBlendMode(data.renderer, SDL.BLENDMODE_BLEND)
	sdl_sync_window_metrics(backend)

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

// Keep layout and input in window coordinates while rendering into every
// physical pixel of a high-density back buffer. Without this, Windows may
// scale a low-resolution surface after SDL presents it, softening or aliasing
// text and one-pixel UI details.
sdl_sync_window_metrics :: proc(backend: ^ansuz.Backend) {
	data := cast(^SDL_Data)backend.user_data
	if data.window == nil || data.renderer == nil {
		return
	}

	window_w, window_h: i32
	output_w, output_h: i32
	if !SDL.GetWindowSize(data.window, &window_w, &window_h) || window_w <= 0 || window_h <= 0 {
		return
	}

	zoom := data.zoom
	if zoom <= 0 {
		zoom = 1
	}
	backend.width = max(i32(f32(window_w) / zoom + 0.5), 1)
	backend.height = max(i32(f32(window_h) / zoom + 0.5), 1)
	data.pixel_density = 1
	if SDL.GetRenderOutputSize(data.renderer, &output_w, &output_h) && output_w > 0 && output_h > 0 {
		// Render scale maps logical pixels (window / zoom) onto output pixels.
		scale_x := f32(output_w) / f32(window_w) * zoom
		scale_y := f32(output_h) / f32(window_h) * zoom
		_ = SDL.SetRenderScale(data.renderer, scale_x, scale_y)
		data.pixel_density = max(scale_x, scale_y)
	}
}

// The desktop host uses this to rasterize its font atlas near the physical
// size at which glyphs will be displayed.
pixel_density :: proc(backend: ^ansuz.Backend) -> f32 {
	data := cast(^SDL_Data)backend.user_data
	if data == nil || data.pixel_density <= 0 {
		return 1
	}
	return data.pixel_density
}

// Upload a TTF grayscale coverage atlas as an SDL texture for antialiased rendering.
sdl_load_font :: proc(backend: ^ansuz.Backend, font: ^ansuz.Font, handle: ansuz.Font_Handle) {
	data := cast(^SDL_Data)backend.user_data

	w := font.atlas_width
	h := font.atlas_height

	// Create RGBA texture from grayscale coverage atlas (white pixels + alpha from atlas).
	tex := SDL.CreateTexture(data.renderer, .RGBA32, .STATIC, w, h)
	if tex == nil { return }
	SDL.SetTextureBlendMode(tex, SDL.BLENDMODE_BLEND)
	SDL.SetTextureScaleMode(tex, .LINEAR)

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

// Set the color the window is cleared to at the start of each frame.
set_clear_color :: proc(backend: ^ansuz.Backend, color: ansuz.Color) {
	data := cast(^SDL_Data)backend.user_data
	data.clear_color = color
}

sdl_begin_frame :: proc(backend: ^ansuz.Backend) {
	data := cast(^SDL_Data)backend.user_data
	c := data.clear_color
	SDL.SetRenderDrawColor(data.renderer, c.r, c.g, c.b, c.a)
	SDL.RenderClear(data.renderer)
}

sdl_end_frame :: proc(backend: ^ansuz.Backend) {
	data := cast(^SDL_Data)backend.user_data
	SDL.RenderPresent(data.renderer)
}

draw_sdl_filled_rect :: proc(renderer: ^SDL.Renderer, rect: ansuz.Rect, radius: f32) {
	if rect.w <= 0 || rect.h <= 0 {
		return
	}

	r := clamp_radius(rect, radius)
	if r < 1 {
		sdl_rect := SDL.FRect{rect.x, rect.y, rect.w, rect.h}
		SDL.RenderFillRect(renderer, &sdl_rect)
		return
	}

	row_count := ceil_f32_to_int(rect.h)
	for row in 0..<row_count {
		row_y := f32(row)
		if row_y >= rect.h {
			break
		}

		row_h := min(f32(1), rect.h - row_y)
		inset := rounded_row_inset(rect.h, r, row_y, row_h)
		span_w := rect.w - inset * 2
		if span_w <= 0 {
			continue
		}

		span := SDL.FRect{rect.x + inset, rect.y + row_y, span_w, row_h}
		SDL.RenderFillRect(renderer, &span)
	}
}

draw_sdl_rect_outline :: proc(renderer: ^SDL.Renderer, rect: ansuz.Rect, thickness, radius: f32) {
	if rect.w <= 0 || rect.h <= 0 || thickness <= 0 {
		return
	}

	t := min(thickness, min(rect.w, rect.h) * 0.5)
	r := clamp_radius(rect, radius)
	row_count := ceil_f32_to_int(rect.h)

	for row in 0..<row_count {
		row_y := f32(row)
		if row_y >= rect.h {
			break
		}

		row_h := min(f32(1), rect.h - row_y)
		center_y := row_y + row_h * 0.5
		outer_inset := rounded_row_inset(rect.h, r, row_y, row_h)
		outer_left := rect.x + outer_inset
		outer_right := rect.x + rect.w - outer_inset

		if outer_right <= outer_left {
			continue
		}

		inner_exists := rect.w > t * 2 && rect.h > t * 2 && center_y >= t && center_y < rect.h - t
		if !inner_exists {
			span := SDL.FRect{outer_left, rect.y + row_y, outer_right - outer_left, row_h}
			SDL.RenderFillRect(renderer, &span)
			continue
		}

		inner_h := rect.h - t * 2
		inner_radius := max(f32(0), r - t)
		inner_inset := t + rounded_row_inset(inner_h, inner_radius, row_y - t, row_h)
		inner_left := rect.x + inner_inset
		inner_right := rect.x + rect.w - inner_inset

		left_w := min(inner_left, outer_right) - outer_left
		if left_w > 0 {
			left := SDL.FRect{outer_left, rect.y + row_y, left_w, row_h}
			SDL.RenderFillRect(renderer, &left)
		}

		right_x := max(inner_right, outer_left)
		right_w := outer_right - right_x
		if right_w > 0 {
			right := SDL.FRect{right_x, rect.y + row_y, right_w, row_h}
			SDL.RenderFillRect(renderer, &right)
		}
	}
}

clamp_radius :: proc(rect: ansuz.Rect, radius: f32) -> f32 {
	if radius <= 0 {
		return 0
	}
	return min(radius, min(rect.w, rect.h) * 0.5)
}

rounded_row_inset :: proc(height, radius, row_y, row_h: f32) -> f32 {
	if radius <= 0 {
		return 0
	}

	center_y := row_y + row_h * 0.5
	dy: f32
	if center_y < radius {
		dy = radius - center_y
	} else if center_y > height - radius {
		dy = center_y - (height - radius)
	} else {
		return 0
	}

	span := sqrt_f32(max(f32(0), radius * radius - dy * dy))
	return max(f32(0), radius - span)
}

ceil_f32_to_int :: proc(value: f32) -> int {
	i := int(value)
	if f32(i) < value {
		return i + 1
	}
	return i
}

sqrt_f32 :: proc(x: f32) -> f32 {
	if x <= 0 {
		return 0
	}

	guess := x / 2
	if guess < 1 {
		guess = 1
	}
	for _ in 0..<10 {
		guess = (guess + x / guess) / 2
	}
	return guess
}

sdl_execute :: proc(backend: ^ansuz.Backend, cmd: ansuz.Draw_Command) {
	data := cast(^SDL_Data)backend.user_data

	switch c in cmd {
	case ansuz.Draw_Filled_Rect:
		SDL.SetRenderDrawColor(data.renderer, c.color.r, c.color.g, c.color.b, c.color.a)
		draw_sdl_filled_rect(data.renderer, c.rect, c.radius)

	case ansuz.Draw_Rect_Outline:
		SDL.SetRenderDrawColor(data.renderer, c.color.r, c.color.g, c.color.b, c.color.a)
		draw_sdl_rect_outline(data.renderer, c.rect, c.thickness, c.radius)

	case ansuz.Draw_Line:
		// RenderLine rasterizes a hairline after the render scale is applied, so a
		// fractional scale below 1 (the smol-mode zoom) can drop diagonal strokes
		// entirely — the window ✕ and checkmarks vanish. Draw the line as a thin
		// quad instead (the WebGL backend's approach), which also honors the
		// command's thickness.
		dx := c.p1.x - c.p0.x
		dy := c.p1.y - c.p0.y
		length := math.sqrt(dx * dx + dy * dy)
		if length < 1 {
			length = 1
		}
		half := max(c.thickness, 1) * 0.5
		nx := -dy / length * half
		ny := dx / length * half
		line_color := SDL.FColor{
			f32(c.color.r) / 255,
			f32(c.color.g) / 255,
			f32(c.color.b) / 255,
			f32(c.color.a) / 255,
		}
		line_verts := [4]SDL.Vertex{
			{position = {c.p0.x + nx, c.p0.y + ny}, color = line_color},
			{position = {c.p1.x + nx, c.p1.y + ny}, color = line_color},
			{position = {c.p1.x - nx, c.p1.y - ny}, color = line_color},
			{position = {c.p0.x - nx, c.p0.y - ny}, color = line_color},
		}
		line_indices := [6]i32{0, 1, 2, 0, 2, 3}
		_ = SDL.RenderGeometry(
			data.renderer,
			nil,
			raw_data(line_verts[:]),
			4,
			raw_data(line_indices[:]),
			6,
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
			// Glyph advances are fractional, so unsnapped quads land between
			// pixels and linear filtering smears the atlas texels, softening
			// text that was rasterized for 1:1 display. Snap each glyph
			// origin to a physical pixel (density-aware for high-DPI).
			px_density := data.pixel_density if data.pixel_density > 0 else 1

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
				math.round((cursor_x + g.x_offset * scale) * px_density) / px_density,
				math.round((cursor_y + (font.ascent + g.y_offset) * scale) * px_density) / px_density,
				(g.x_offset2 - g.x_offset) * scale,
					(g.y_offset2 - g.y_offset) * scale,
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
	// Mouse events arrive in window coordinates; layout runs in logical
	// (zoom-divided) coordinates, so input is converted at this seam.
	zoom := data.zoom
	if zoom <= 0 {
		zoom = 1
	}
	// Keep the overlay visible for the frame that receives DROP_FILE, even when
	// SDL queues DROP_COMPLETE immediately after it. Clear it on the next poll.
	if data.file_drop_completed {
		data.file_drag_active = false
		data.file_drop_completed = false
	}

	// Reset per-frame edge-triggered input events
	input.mouse_left_pressed = false
	input.mouse_right_pressed = false
	input.text_char_len = 0
	input.key_backspace = false
	input.key_tab = false
	input.key_delete = false
	input.key_left = false
	input.key_right = false
	input.key_up = false
	input.key_down = false
	input.key_home = false
	input.key_end = false
	input.key_enter = false
	input.key_escape = false
	input.key_copy = false
	input.key_paste = false
	input.key_cut = false
	input.key_find = false
	input.key_find_all = false
	input.key_code = 0
	input.dropped_file_len = 0
	input.mouse_scroll_y = 0

	for e: SDL.Event; SDL.PollEvent(&e); /**/ {
		#partial switch e.type {
		case .QUIT:
			quit = true

		case .WINDOW_RESIZED, .WINDOW_PIXEL_SIZE_CHANGED, .WINDOW_DISPLAY_SCALE_CHANGED:
			sdl_sync_window_metrics(backend)

		case .MOUSE_MOTION:
			input.mouse_x = e.motion.x / zoom
			input.mouse_y = e.motion.y / zoom

		case .MOUSE_BUTTON_DOWN:
			switch e.button.button {
			case SDL.BUTTON_LEFT:
				input.mouse_left = true
				input.mouse_left_pressed = true
			case SDL.BUTTON_RIGHT:
				input.mouse_right = true
				input.mouse_right_pressed = true
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
			text_bytes := cast([^]u8)e.text.text
			for i in 0..<256 {
				ch := text_bytes[i]
				if ch == 0 { break }
				if ch >= 32 && input.text_char_len < len(input.text_chars) {
					input.text_chars[input.text_char_len] = u8(ch)
					input.text_char_len += 1
				}
			}

		case .KEY_DOWN:
			ctrl_down := input.key_ctrl || .LCTRL in e.key.mod || .RCTRL in e.key.mod
			// Re-derive Alt from the event's modifier mask every key press so a
			// release missed during Alt+Tab (window defocus) self-heals here.
			input.key_alt = .LALT in e.key.mod || .RALT in e.key.mod
			key_value := i32(e.key.key)
			if key_value >= 'a' && key_value <= 'z' {
				key_value -= 'a' - 'A'
			}
			input.key_code = key_value
			#partial switch e.key.scancode {
			case .ESCAPE:
				input.key_escape = true
			case .BACKSPACE:
				input.key_backspace = true
			case .TAB:
				input.key_tab = true
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
			case .C:
				if ctrl_down { input.key_copy = true }
			case .V:
				if ctrl_down { input.key_paste = true }
			case .X:
				if ctrl_down { input.key_cut = true }
			case .F:
				if ctrl_down {
					input.key_find = true
					input.key_find_all = input.key_shift || .LSHIFT in e.key.mod || .RSHIFT in e.key.mod
				}
			case .LSHIFT, .RSHIFT:
				input.key_shift = true
			case .LCTRL, .RCTRL:
				input.key_ctrl = true
			case .LALT, .RALT:
				input.key_alt = true
			}

		case .KEY_UP:
			#partial switch e.key.scancode {
			case .LSHIFT, .RSHIFT:
				input.key_shift = false
			case .LCTRL, .RCTRL:
				input.key_ctrl = false
			case .LALT, .RALT:
				input.key_alt = false
			}

		case .DROP_BEGIN, .DROP_POSITION:
			data.file_drag_active = true

		case .DROP_FILE:
			data.file_drag_active = true
			if e.drop.data != nil {
				bytes := cast([^]u8)e.drop.data
				for i in 0..<len(input.dropped_file) {
					if bytes[i] == 0 { break }
					input.dropped_file[input.dropped_file_len] = bytes[i]
					input.dropped_file_len += 1
				}
				// SDL3 owns event payload memory and releases it during later
				// event polling. SDL2 required callers to free dropped paths,
				// but doing that with SDL3 double-frees this pointer.
			}

		case .DROP_COMPLETE:
			if input.dropped_file_len > 0 {
				data.file_drop_completed = true
			} else {
				data.file_drag_active = false
			}
		}
	}
	input.file_drag_active = data.file_drag_active

	return quit
}

sdl_set_clipboard_text :: proc(backend: ^ansuz.Backend, text: string) -> bool {
	c_text, err := strings.clone_to_cstring(text, context.temp_allocator)
	if err != nil {
		return false
	}
	return SDL.SetClipboardText(c_text)
}

sdl_get_clipboard_text :: proc(backend: ^ansuz.Backend, allocator: runtime.Allocator) -> string {
	ptr := SDL.GetClipboardText()
	if ptr == nil {
		return ""
	}
	defer SDL.free(rawptr(ptr))

	n := int(SDL.strlen(cstring(ptr)))
	return strings.clone(string(ptr[:n]), allocator)
}

sdl_open_url :: proc(backend: ^ansuz.Backend, url: string) -> bool {
	c_url, err := strings.clone_to_cstring(url, context.temp_allocator)
	if err != nil {
		return false
	}
	return SDL.OpenURL(c_url)
}

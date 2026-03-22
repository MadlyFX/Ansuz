package ogui_backend_soft

import ogui "../ogui"

// --- Software Framebuffer Renderer ---
// Pure software renderer that writes pixels into a []u32 RGBA buffer.
// No external dependencies — suitable for embedded systems, microcontrollers,
// or any target where only raw pixel output is available.
//
// This is the Odin equivalent of Adafruit GFX's GFXcanvas approach:
// draw to an in-memory framebuffer, then transfer it to hardware.
//
// Usage:
//   fb: [320 * 240]u32
//   soft := backend_soft.create(320, 240, fb[:])
//   // ... use with ogui.Manager ...
//   // fb now contains RGBA pixels ready to send to your display

Soft_Data :: struct {
	framebuffer: []u32,   // RGBA32 pixels, size = width * height
	clip:        ogui.Rect,
}

// Create a software renderer backend targeting a pixel buffer.
// The buffer must be at least width*height elements.
create :: proc(width, height: i32, framebuffer: []u32) -> ogui.Backend {
	assert(len(framebuffer) >= int(width * height), "Framebuffer too small")

	data := new(Soft_Data)
	data.framebuffer = framebuffer
	data.clip = ogui.Rect{0, 0, f32(width), f32(height)}

	backend: ogui.Backend
	backend.width      = width
	backend.height     = height
	backend.user_data  = data
	backend.init       = soft_init
	backend.shutdown   = soft_shutdown
	backend.begin_frame = soft_begin_frame
	backend.end_frame  = soft_end_frame
	backend.execute    = soft_execute
	backend.measure_text = soft_measure_text
	backend.poll_events = nil  // No event system — embedded targets handle input separately

	return backend
}

// Get the raw framebuffer pointer (for sending to display hardware).
get_framebuffer :: proc(backend: ^ogui.Backend) -> []u32 {
	data := cast(^Soft_Data)backend.user_data
	return data.framebuffer
}

// --- Backend proc implementations ---

soft_init :: proc(backend: ^ogui.Backend, width, height: i32) -> bool {
	backend.width = width
	backend.height = height
	data := cast(^Soft_Data)backend.user_data
	data.clip = ogui.Rect{0, 0, f32(width), f32(height)}
	return true
}

soft_shutdown :: proc(backend: ^ogui.Backend) {
	data := cast(^Soft_Data)backend.user_data
	free(data)
}

soft_begin_frame :: proc(backend: ^ogui.Backend) {
	data := cast(^Soft_Data)backend.user_data
	// Clear to dark background
	clear_color := pack_rgba(30, 30, 34, 255)
	for i in 0..<int(backend.width * backend.height) {
		data.framebuffer[i] = clear_color
	}
	data.clip = ogui.Rect{0, 0, f32(backend.width), f32(backend.height)}
}

soft_end_frame :: proc(backend: ^ogui.Backend) {
	// No-op for software renderer — framebuffer is ready to read
}

soft_execute :: proc(backend: ^ogui.Backend, cmd: ogui.Draw_Command) {
	data := cast(^Soft_Data)backend.user_data
	w := int(backend.width)
	h := int(backend.height)

	switch c in cmd {
	case ogui.Draw_Filled_Rect:
		clipped := ogui.rect_intersect(c.rect, data.clip)
		if clipped.w <= 0 || clipped.h <= 0 { return }
		x0 := max(0, int(clipped.x))
		y0 := max(0, int(clipped.y))
		x1 := min(w, int(clipped.x + clipped.w))
		y1 := min(h, int(clipped.y + clipped.h))
		for py in y0..<y1 {
			for px in x0..<x1 {
				blend_pixel(data.framebuffer, w, px, py, c.color)
			}
		}

	case ogui.Draw_Rect_Outline:
		r := c.rect
		t := max(1, int(c.thickness))
		// Top edge
		fill_rect_clipped(data, w, h, int(r.x), int(r.y), int(r.w), t, c.color)
		// Bottom edge
		fill_rect_clipped(data, w, h, int(r.x), int(r.y + r.h) - t, int(r.w), t, c.color)
		// Left edge
		fill_rect_clipped(data, w, h, int(r.x), int(r.y), t, int(r.h), c.color)
		// Right edge
		fill_rect_clipped(data, w, h, int(r.x + r.w) - t, int(r.y), t, int(r.h), c.color)

	case ogui.Draw_Line:
		draw_line_bresenham(data, w, h, c.p0, c.p1, c.color)

	case ogui.Draw_Text:
		draw_text_bitmap(data, w, h, c.pos, c.text, c.color, c.size)

	case ogui.Draw_Clip:
		full := ogui.Rect{0, 0, f32(w), f32(h)}
		data.clip = ogui.rect_intersect(c.rect, full)

	case ogui.Draw_Image:
		// Image rendering requires a texture handle — not supported in pure software mode
		// On embedded, you'd blit raw pixel data here
	}
}

soft_measure_text :: proc(backend: ^ogui.Backend, text: string, font: ogui.Font_Handle, size: f32) -> ogui.Vec2 {
	return ogui.measure_text_builtin(text, size)
}

// --- Pixel operations ---

pack_rgba :: proc(r, g, b, a: u8) -> u32 {
	return u32(r) | (u32(g) << 8) | (u32(b) << 16) | (u32(a) << 24)
}

unpack_rgba :: proc(pixel: u32) -> (r, g, b, a: u8) {
	return u8(pixel), u8(pixel >> 8), u8(pixel >> 16), u8(pixel >> 24)
}

blend_pixel :: proc(fb: []u32, stride: int, x, y: int, color: ogui.Color) {
	if x < 0 || y < 0 { return }
	idx := y * stride + x
	if idx >= len(fb) { return }

	if color.a == 255 {
		fb[idx] = pack_rgba(color.r, color.g, color.b, 255)
		return
	}
	if color.a == 0 { return }

	// Alpha blend
	dr, dg, db, _ := unpack_rgba(fb[idx])
	a := u16(color.a)
	inv_a := 255 - a
	out_r := u8((u16(color.r) * a + u16(dr) * inv_a) / 255)
	out_g := u8((u16(color.g) * a + u16(dg) * inv_a) / 255)
	out_b := u8((u16(color.b) * a + u16(db) * inv_a) / 255)
	fb[idx] = pack_rgba(out_r, out_g, out_b, 255)
}

fill_rect_clipped :: proc(data: ^Soft_Data, w, h: int, rx, ry, rw, rh: int, color: ogui.Color) {
	clip := data.clip
	x0 := max(max(0, rx), int(clip.x))
	y0 := max(max(0, ry), int(clip.y))
	x1 := min(min(w, rx + rw), int(clip.x + clip.w))
	y1 := min(min(h, ry + rh), int(clip.y + clip.h))
	for py in y0..<y1 {
		for px in x0..<x1 {
			blend_pixel(data.framebuffer, w, px, py, color)
		}
	}
}

// --- Bresenham line drawing ---

draw_line_bresenham :: proc(data: ^Soft_Data, w, h: int, p0, p1: ogui.Vec2, color: ogui.Color) {
	x0 := int(p0.x)
	y0 := int(p0.y)
	x1 := int(p1.x)
	y1 := int(p1.y)

	dx := abs(x1 - x0)
	dy := -abs(y1 - y0)
	sx := 1 if x0 < x1 else -1
	sy := 1 if y0 < y1 else -1
	err := dx + dy

	for {
		if x0 >= int(data.clip.x) && x0 < int(data.clip.x + data.clip.w) &&
		   y0 >= int(data.clip.y) && y0 < int(data.clip.y + data.clip.h) {
			blend_pixel(data.framebuffer, w, x0, y0, color)
		}
		if x0 == x1 && y0 == y1 { break }
		e2 := 2 * err
		if e2 >= dy {
			err += dy
			x0 += sx
		}
		if e2 <= dx {
			err += dx
			y0 += sy
		}
	}
}

// --- Bitmap text rendering ---

draw_text_bitmap :: proc(data: ^Soft_Data, w, h: int, pos: ogui.Vec2, text: string, color: ogui.Color, scale: f32) {
	s := max(1, int(scale))
	cursor_x := int(pos.x)
	cursor_y := int(pos.y)

	for ch in text {
		c := int(ch) if int(ch) < 256 else int('?')
		for col in 0..<ogui.FONT_GLYPH_WIDTH {
			for row in 0..<ogui.FONT_GLYPH_HEIGHT {
				if ogui.font_pixel(u8(c), col, row) {
					px := cursor_x + col * s
					py := cursor_y + row * s
					// Draw a scale x scale block for each font pixel
					for sy in 0..<s {
						for sx in 0..<s {
							fx := px + sx
							fy := py + sy
							if fx >= int(data.clip.x) && fx < int(data.clip.x + data.clip.w) &&
							   fy >= int(data.clip.y) && fy < int(data.clip.y + data.clip.h) {
								blend_pixel(data.framebuffer, w, fx, fy, color)
							}
						}
					}
				}
			}
		}
		cursor_x += ogui.FONT_CHAR_WIDTH * s
	}
}

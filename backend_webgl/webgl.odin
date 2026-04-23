package ansuz_backend_webgl

import gl "vendor:wasm/WebGL"
import ansuz "../ansuz"

// --- WebGL Backend ---
// Renders ansuz draw commands using WebGL in a browser via WASM.
// Uses a simple 2D colored-quad shader. Text is rendered using
// the built-in bitmap font uploaded as a WebGL texture.

CANVAS_ID :: "ansuz-canvas"
MAX_VERTICES :: 16384

Vertex :: struct {
	x, y:    f32,
	u, v:    f32,
	r, g, b, a: f32,
}

WebGL_Image :: struct {
	texture: gl.Texture,
}

// Per-font GPU data for loaded TTF fonts.
WebGL_Font :: struct {
	texture:        gl.Texture,
	glyphs:         [256]ansuz.Font_Glyph_Info,
	glyphs_unicode: map[rune]ansuz.Font_Glyph_Info,
	atlas_width:    i32,
	atlas_height:   i32,
	ascent:         f32,
	line_height:    f32,
}

WebGL_Data :: struct {
	color_program:       gl.Program,
	tex_program:         gl.Program,
	img_program:         gl.Program,
	vbo:                 gl.Buffer,
	builtin_font_texture: gl.Texture,
	bound_texture:       gl.Texture,
	vertices:            [MAX_VERTICES]Vertex,
	vertex_count:        int,
	current_program:     gl.Program,
	width, height:       f32,
	loaded_fonts:        [dynamic]WebGL_Font,
}

create :: proc(width, height: i32) -> ansuz.Backend {
	data := new(WebGL_Data)
	data.width = f32(width)
	data.height = f32(height)

	backend: ansuz.Backend
	backend.width     = width
	backend.height    = height
	backend.user_data = data
	backend.init      = webgl_init
	backend.shutdown  = webgl_shutdown
	backend.begin_frame = webgl_begin_frame
	backend.end_frame = webgl_end_frame
	backend.execute   = webgl_execute
	backend.measure_text = webgl_measure_text
	backend.poll_events = nil  // Events handled by JavaScript
	backend.load_font = webgl_load_font

	return backend
}

// --- Shaders ---

COLOR_VERT :: `attribute vec2 a_pos;
attribute vec4 a_color;
uniform vec2 u_resolution;
varying vec4 v_color;
void main() {
    vec2 clip = (a_pos / u_resolution) * 2.0 - 1.0;
    gl_Position = vec4(clip.x, -clip.y, 0, 1);
    v_color = a_color;
}`

COLOR_FRAG :: `precision mediump float;
varying vec4 v_color;
void main() {
    gl_FragColor = v_color;
}`

TEX_VERT :: `attribute vec2 a_pos;
attribute vec2 a_uv;
attribute vec4 a_color;
uniform vec2 u_resolution;
varying vec2 v_uv;
varying vec4 v_color;
void main() {
    vec2 clip = (a_pos / u_resolution) * 2.0 - 1.0;
    gl_Position = vec4(clip.x, -clip.y, 0, 1);
    v_uv = a_uv;
    v_color = a_color;
}`

TEX_FRAG :: `precision mediump float;
uniform sampler2D u_texture;
varying vec2 v_uv;
varying vec4 v_color;
void main() {
    float a = texture2D(u_texture, v_uv).a;
    gl_FragColor = v_color * vec4(1, 1, 1, a);
}`

IMG_FRAG :: `precision mediump float;
uniform sampler2D u_texture;
varying vec2 v_uv;
varying vec4 v_color;
void main() {
    gl_FragColor = texture2D(u_texture, v_uv) * v_color;
}`

// --- Backend implementations ---

webgl_init :: proc(backend: ^ansuz.Backend, width, height: i32) -> bool {
	data := cast(^WebGL_Data)backend.user_data

	gl.CreateCurrentContextById(CANVAS_ID, {.stencil})

	// Compile shader programs
	data.color_program = gl.CreateProgramFromStrings(
		{COLOR_VERT}, {COLOR_FRAG},
	) or_return

	data.tex_program = gl.CreateProgramFromStrings(
		{TEX_VERT}, {TEX_FRAG},
	) or_return

	data.img_program = gl.CreateProgramFromStrings(
		{TEX_VERT}, {IMG_FRAG},
	) or_return

	// Create vertex buffer
	data.vbo = gl.CreateBuffer()

	// Create font atlas texture
	create_font_texture(data)

	data.bound_texture = data.builtin_font_texture

	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	data.width = f32(width)
	data.height = f32(height)
	backend.width = width
	backend.height = height

	return true
}

webgl_shutdown :: proc(backend: ^ansuz.Backend) {
	data := cast(^WebGL_Data)backend.user_data
	for &f in data.loaded_fonts {
		gl.DeleteTexture(f.texture)
		delete(f.glyphs_unicode)
	}
	delete(data.loaded_fonts)
	free(data)
}

webgl_begin_frame :: proc(backend: ^ansuz.Backend) {
	data := cast(^WebGL_Data)backend.user_data

	// Update viewport to match canvas
	canvas_w := gl.DrawingBufferWidth()
	canvas_h := gl.DrawingBufferHeight()
	gl.Viewport(0, 0, canvas_w, canvas_h)
	data.width = f32(canvas_w)
	data.height = f32(canvas_h)
	backend.width = canvas_w
	backend.height = canvas_h

	gl.ClearColor(0.118, 0.118, 0.133, 1)
	gl.Clear(u32(gl.COLOR_BUFFER_BIT))

	data.vertex_count = 0
}

webgl_end_frame :: proc(backend: ^ansuz.Backend) {
	data := cast(^WebGL_Data)backend.user_data
	flush_batch(data, data.current_program)
}

webgl_execute :: proc(backend: ^ansuz.Backend, cmd: ansuz.Draw_Command) {
	data := cast(^WebGL_Data)backend.user_data

	switch c in cmd {
	case ansuz.Draw_Filled_Rect:
		use_program(data, data.color_program)
		push_colored_quad(data,
			c.rect.x, c.rect.y,
			c.rect.x + c.rect.w, c.rect.y + c.rect.h,
			c.color,
		)

	case ansuz.Draw_Rect_Outline:
		use_program(data, data.color_program)
		t := max(c.thickness, 1)
		r := c.rect
		// Top
		push_colored_quad(data, r.x, r.y, r.x + r.w, r.y + t, c.color)
		// Bottom
		push_colored_quad(data, r.x, r.y + r.h - t, r.x + r.w, r.y + r.h, c.color)
		// Left
		push_colored_quad(data, r.x, r.y, r.x + t, r.y + r.h, c.color)
		// Right
		push_colored_quad(data, r.x + r.w - t, r.y, r.x + r.w, r.y + r.h, c.color)

	case ansuz.Draw_Line:
		use_program(data, data.color_program)
		// Approximate line as a thin quad
		dx := c.p1.x - c.p0.x
		dy := c.p1.y - c.p0.y
		len := max(1, sqrt_f32(dx * dx + dy * dy))
		nx := -dy / len * max(c.thickness, 1) * 0.5
		ny :=  dx / len * max(c.thickness, 1) * 0.5
		push_quad_verts(data,
			c.p0.x + nx, c.p0.y + ny,
			c.p1.x + nx, c.p1.y + ny,
			c.p1.x - nx, c.p1.y - ny,
			c.p0.x - nx, c.p0.y - ny,
			c.color,
		)

	case ansuz.Draw_Text:
		font_handle := c.font

		if font_handle == ansuz.FONT_BUILTIN || int(font_handle) - 1 >= len(data.loaded_fonts) {
			// Builtin bitmap font
			if data.bound_texture != data.builtin_font_texture {
				flush_batch(data, data.current_program)
				data.bound_texture = data.builtin_font_texture
			}
			use_program(data, data.tex_program)
			draw_text_webgl(data, c.pos, c.text, c.color, c.size)
		} else {
			// TTF font atlas
			font := &data.loaded_fonts[int(font_handle) - 1]
			flush_batch(data, data.current_program)
			data.bound_texture = font.texture
			use_program(data, data.tex_program)
			draw_text_ttf_webgl(data, c.pos, c.text, c.color, c.size, font)
			flush_batch(data, data.current_program)
			data.bound_texture = data.builtin_font_texture
		}

	case ansuz.Draw_Clip:
		flush_batch(data, data.current_program)
		gl.Enable(gl.SCISSOR_TEST)
		// WebGL scissor is bottom-left origin
		gl.Scissor(
			i32(c.rect.x),
			i32(data.height - c.rect.y - c.rect.h),
			i32(c.rect.w),
			i32(c.rect.h),
		)

	case ansuz.Draw_Image:
		if c.handle != nil {
			img_data := cast(^WebGL_Image)c.handle
			flush_batch(data, data.current_program)
			data.bound_texture = img_data.texture
			use_program(data, data.img_program)

			x0, y0 := c.rect.x, c.rect.y
			x1, y1 := c.rect.x + c.rect.w, c.rect.y + c.rect.h
			push_vertex(data, x0, y0, 0, 0, c.tint)
			push_vertex(data, x1, y0, 1, 0, c.tint)
			push_vertex(data, x1, y1, 1, 1, c.tint)
			push_vertex(data, x0, y0, 0, 0, c.tint)
			push_vertex(data, x1, y1, 1, 1, c.tint)
			push_vertex(data, x0, y1, 0, 1, c.tint)

			flush_batch(data, data.current_program)
			data.bound_texture = data.builtin_font_texture
		}
	}
}

webgl_measure_text :: proc(backend: ^ansuz.Backend, text: string, font: ansuz.Font_Handle, size: f32) -> ansuz.Vec2 {
	return ansuz.measure_text_builtin(text, size)
}

// --- Batching ---

use_program :: proc(data: ^WebGL_Data, program: gl.Program) {
	if data.current_program != program {
		flush_batch(data, data.current_program)
		data.current_program = program
	}
}

flush_batch :: proc(data: ^WebGL_Data, program: gl.Program) {
	if data.vertex_count == 0 { return }

	gl.UseProgram(program)

	// Set resolution uniform
	loc := gl.GetUniformLocation(program, "u_resolution")
	gl.Uniform2f(loc, data.width, data.height)

	// Upload vertex data
	gl.BindBuffer(gl.ARRAY_BUFFER, data.vbo)
	gl.BufferDataSlice(gl.ARRAY_BUFFER, data.vertices[:data.vertex_count], gl.STREAM_DRAW)

	stride := size_of(Vertex)

	// Position attribute
	pos_loc := gl.GetAttribLocation(program, "a_pos")
	gl.EnableVertexAttribArray(pos_loc)
	gl.VertexAttribPointer(pos_loc, 2, gl.FLOAT, false, stride, 0)

	// Check if textured program
	uv_loc := gl.GetAttribLocation(program, "a_uv")
	if uv_loc >= 0 {
		gl.EnableVertexAttribArray(uv_loc)
		gl.VertexAttribPointer(uv_loc, 2, gl.FLOAT, false, stride, 2 * size_of(f32))

		color_loc := gl.GetAttribLocation(program, "a_color")
		gl.EnableVertexAttribArray(color_loc)
		gl.VertexAttribPointer(color_loc, 4, gl.FLOAT, false, stride, 4 * size_of(f32))

		// Bind active texture (font or image)
		tex_loc := gl.GetUniformLocation(program, "u_texture")
		gl.ActiveTexture(gl.TEXTURE0)
		gl.BindTexture(gl.TEXTURE_2D, data.bound_texture)
		gl.Uniform1i(tex_loc, 0)
	} else {
		color_loc := gl.GetAttribLocation(program, "a_color")
		gl.EnableVertexAttribArray(color_loc)
		gl.VertexAttribPointer(color_loc, 4, gl.FLOAT, false, stride, 4 * size_of(f32))
	}

	gl.DrawArrays(gl.TRIANGLES, 0, data.vertex_count)
	data.vertex_count = 0
}

// --- Geometry helpers ---

push_vertex :: proc(data: ^WebGL_Data, x, y, u, v: f32, color: ansuz.Color) {
	if data.vertex_count >= MAX_VERTICES {
		flush_batch(data, data.current_program)
	}
	data.vertices[data.vertex_count] = Vertex{
		x, y, u, v,
		f32(color.r) / 255, f32(color.g) / 255,
		f32(color.b) / 255, f32(color.a) / 255,
	}
	data.vertex_count += 1
}

push_colored_quad :: proc(data: ^WebGL_Data, x0, y0, x1, y1: f32, color: ansuz.Color) {
	if data.vertex_count + 6 > MAX_VERTICES {
		flush_batch(data, data.current_program)
	}
	push_vertex(data, x0, y0, 0, 0, color)
	push_vertex(data, x1, y0, 0, 0, color)
	push_vertex(data, x1, y1, 0, 0, color)
	push_vertex(data, x0, y0, 0, 0, color)
	push_vertex(data, x1, y1, 0, 0, color)
	push_vertex(data, x0, y1, 0, 0, color)
}

push_quad_verts :: proc(data: ^WebGL_Data, x0, y0, x1, y1, x2, y2, x3, y3: f32, color: ansuz.Color) {
	if data.vertex_count + 6 > MAX_VERTICES {
		flush_batch(data, data.current_program)
	}
	push_vertex(data, x0, y0, 0, 0, color)
	push_vertex(data, x1, y1, 0, 0, color)
	push_vertex(data, x2, y2, 0, 0, color)
	push_vertex(data, x0, y0, 0, 0, color)
	push_vertex(data, x2, y2, 0, 0, color)
	push_vertex(data, x3, y3, 0, 0, color)
}

// --- Font texture ---

ATLAS_W :: 16 * ansuz.FONT_CHAR_WIDTH   // 96
ATLAS_H :: 16 * ansuz.FONT_CHAR_HEIGHT  // 144

create_font_texture :: proc(data: ^WebGL_Data) {
	// Generate atlas pixel data (alpha-only, stored as RGBA)
	pixels: [ATLAS_W * ATLAS_H * 4]u8
	for ch in 0..<256 {
		cell_x := (ch % 16) * ansuz.FONT_CHAR_WIDTH
		cell_y := (ch / 16) * ansuz.FONT_CHAR_HEIGHT
		for col in 0..<ansuz.FONT_GLYPH_WIDTH {
			for row in 0..<ansuz.FONT_GLYPH_HEIGHT {
				if ansuz.font_pixel(u8(ch), col, row) {
					px := cell_x + col
					py := cell_y + row
					idx := (py * ATLAS_W + px) * 4
					pixels[idx + 0] = 255
					pixels[idx + 1] = 255
					pixels[idx + 2] = 255
					pixels[idx + 3] = 255
				}
			}
		}
	}

	data.builtin_font_texture = gl.CreateTexture()
	gl.BindTexture(gl.TEXTURE_2D, data.builtin_font_texture)
	gl.TexImage2DSlice(gl.TEXTURE_2D, 0, gl.RGBA, ATLAS_W, ATLAS_H, 0, gl.RGBA, gl.UNSIGNED_BYTE, pixels[:])
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, i32(gl.NEAREST))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, i32(gl.NEAREST))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, i32(gl.CLAMP_TO_EDGE))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, i32(gl.CLAMP_TO_EDGE))
}

// Upload a TTF font atlas as a WebGL texture for rendering.
webgl_load_font :: proc(backend: ^ansuz.Backend, font: ^ansuz.Font, handle: ansuz.Font_Handle) {
	data := cast(^WebGL_Data)backend.user_data

	w := font.atlas_width
	h := font.atlas_height

	// Convert grayscale atlas to RGBA (white + alpha)
	pixel_count := int(w * h)
	rgba := make([]u8, pixel_count * 4)
	defer delete(rgba)
	for i in 0..<pixel_count {
		rgba[i * 4 + 0] = 255
		rgba[i * 4 + 1] = 255
		rgba[i * 4 + 2] = 255
		rgba[i * 4 + 3] = font.atlas_pixels[i]
	}

	tex := gl.CreateTexture()
	gl.BindTexture(gl.TEXTURE_2D, tex)
	gl.TexImage2DSlice(gl.TEXTURE_2D, 0, gl.RGBA, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, rgba)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, i32(gl.LINEAR))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, i32(gl.LINEAR))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, i32(gl.CLAMP_TO_EDGE))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, i32(gl.CLAMP_TO_EDGE))

	// Store font entry with glyph metrics
	entry: WebGL_Font
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

// --- Text rendering ---

draw_text_webgl :: proc(data: ^WebGL_Data, pos: ansuz.Vec2, text: string, color: ansuz.Color, scale: f32) {
	s := scale
	char_w := f32(ansuz.FONT_CHAR_WIDTH) * s
	char_h := f32(ansuz.FONT_CHAR_HEIGHT) * s
	cursor_x := pos.x
	cursor_y := pos.y
	start_x := pos.x

	atlas_w := f32(ATLAS_W)
	atlas_h := f32(ATLAS_H)

	for ch in text {
		if ch == '\n' {
			cursor_x = start_x
			cursor_y += char_h
			continue
		}

		idx := int(ch) if int(ch) < 256 else int('?')
		src_x := f32((idx % 16) * ansuz.FONT_CHAR_WIDTH)
		src_y := f32((idx / 16) * ansuz.FONT_CHAR_HEIGHT)

		// UV coordinates into the atlas
		u0 := src_x / atlas_w
		v0 := src_y / atlas_h
		u1 := (src_x + f32(ansuz.FONT_GLYPH_WIDTH)) / atlas_w
		v1 := (src_y + f32(ansuz.FONT_GLYPH_HEIGHT)) / atlas_h

		// Destination quad
		dx0 := cursor_x
		dy0 := cursor_y
		dx1 := cursor_x + f32(ansuz.FONT_GLYPH_WIDTH) * s
		dy1 := cursor_y + f32(ansuz.FONT_GLYPH_HEIGHT) * s

		if data.vertex_count + 6 > MAX_VERTICES {
			flush_batch(data, data.current_program)
		}
		push_vertex(data, dx0, dy0, u0, v0, color)
		push_vertex(data, dx1, dy0, u1, v0, color)
		push_vertex(data, dx1, dy1, u1, v1, color)
		push_vertex(data, dx0, dy0, u0, v0, color)
		push_vertex(data, dx1, dy1, u1, v1, color)
		push_vertex(data, dx0, dy1, u0, v1, color)

		cursor_x += char_w
	}
}

// --- TTF text rendering ---

draw_text_ttf_webgl :: proc(data: ^WebGL_Data, pos: ansuz.Vec2, text: string, color: ansuz.Color, scale: f32, font: ^WebGL_Font) {
	cursor_x := pos.x
	cursor_y := pos.y
	start_x := pos.x

	atlas_w := f32(font.atlas_width)
	atlas_h := f32(font.atlas_height)

	for ch in text {
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

		// UV coordinates into the atlas
		u0 := f32(g.atlas_x) / atlas_w
		v0 := f32(g.atlas_y) / atlas_h
		u1 := f32(g.atlas_x + g.atlas_w) / atlas_w
		v1 := f32(g.atlas_y + g.atlas_h) / atlas_h

		// Destination quad with baseline offset
		dx0 := cursor_x + g.x_offset * scale
		dy0 := cursor_y + (font.ascent + g.y_offset) * scale
		dx1 := dx0 + f32(g.atlas_w) * scale
		dy1 := dy0 + f32(g.atlas_h) * scale

		if data.vertex_count + 6 > MAX_VERTICES {
			flush_batch(data, data.current_program)
		}
		push_vertex(data, dx0, dy0, u0, v0, color)
		push_vertex(data, dx1, dy0, u1, v0, color)
		push_vertex(data, dx1, dy1, u1, v1, color)
		push_vertex(data, dx0, dy0, u0, v0, color)
		push_vertex(data, dx1, dy1, u1, v1, color)
		push_vertex(data, dx0, dy1, u0, v1, color)

		cursor_x += g.advance * scale
	}
}

// --- Image support ---

create_image :: proc(backend: ^ansuz.Backend, pixels: []u8, width, height: i32, channels: i32 = 4) -> ansuz.Image_Handle {
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
	case 2:
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

	tex := gl.CreateTexture()
	gl.BindTexture(gl.TEXTURE_2D, tex)
	gl.TexImage2DSlice(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, rgba)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, i32(gl.LINEAR))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, i32(gl.LINEAR))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, i32(gl.CLAMP_TO_EDGE))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, i32(gl.CLAMP_TO_EDGE))

	img_data := new(WebGL_Image)
	img_data.texture = tex

	return ansuz.Image_Handle{ptr = img_data, width = width, height = height}
}

destroy_image :: proc(img: ansuz.Image_Handle) {
	if img.ptr != nil {
		img_data := cast(^WebGL_Image)img.ptr
		gl.DeleteTexture(img_data.texture)
		free(img_data)
	}
}

// --- Math helper ---

sqrt_f32 :: proc(x: f32) -> f32 {
	if x <= 0 { return 0 }
	guess := x / 2
	for _ in 0..<10 {
		guess = (guess + x / guess) / 2
	}
	return guess
}

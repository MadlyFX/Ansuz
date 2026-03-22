package ogui_backend_webgl

import gl "vendor:wasm/WebGL"
import ogui "../ogui"

// --- WebGL Backend ---
// Renders OGUI draw commands using WebGL in a browser via WASM.
// Uses a simple 2D colored-quad shader. Text is rendered using
// the built-in bitmap font uploaded as a WebGL texture.

CANVAS_ID :: "ogui-canvas"
MAX_VERTICES :: 16384

Vertex :: struct {
	x, y:    f32,
	u, v:    f32,
	r, g, b, a: f32,
}

WebGL_Data :: struct {
	color_program:  gl.Program,
	tex_program:    gl.Program,
	vbo:            gl.Buffer,
	font_texture:   gl.Texture,
	vertices:       [MAX_VERTICES]Vertex,
	vertex_count:   int,
	current_program: gl.Program,
	width, height:  f32,
}

create :: proc(width, height: i32) -> ogui.Backend {
	data := new(WebGL_Data)
	data.width = f32(width)
	data.height = f32(height)

	backend: ogui.Backend
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

// --- Backend implementations ---

webgl_init :: proc(backend: ^ogui.Backend, width, height: i32) -> bool {
	data := cast(^WebGL_Data)backend.user_data

	gl.CreateCurrentContextById(CANVAS_ID, {.stencil})

	// Compile shader programs
	data.color_program = gl.CreateProgramFromStrings(
		{COLOR_VERT}, {COLOR_FRAG},
	) or_return

	data.tex_program = gl.CreateProgramFromStrings(
		{TEX_VERT}, {TEX_FRAG},
	) or_return

	// Create vertex buffer
	data.vbo = gl.CreateBuffer()

	// Create font atlas texture
	create_font_texture(data)

	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	data.width = f32(width)
	data.height = f32(height)
	backend.width = width
	backend.height = height

	return true
}

webgl_shutdown :: proc(backend: ^ogui.Backend) {
	data := cast(^WebGL_Data)backend.user_data
	free(data)
}

webgl_begin_frame :: proc(backend: ^ogui.Backend) {
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

webgl_end_frame :: proc(backend: ^ogui.Backend) {
	data := cast(^WebGL_Data)backend.user_data
	flush_batch(data, data.current_program)
}

webgl_execute :: proc(backend: ^ogui.Backend, cmd: ogui.Draw_Command) {
	data := cast(^WebGL_Data)backend.user_data

	switch c in cmd {
	case ogui.Draw_Filled_Rect:
		use_program(data, data.color_program)
		push_colored_quad(data,
			c.rect.x, c.rect.y,
			c.rect.x + c.rect.w, c.rect.y + c.rect.h,
			c.color,
		)

	case ogui.Draw_Rect_Outline:
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

	case ogui.Draw_Line:
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

	case ogui.Draw_Text:
		// Flush any colored geometry, switch to textured program
		use_program(data, data.tex_program)
		draw_text_webgl(data, c.pos, c.text, c.color, c.size)

	case ogui.Draw_Clip:
		flush_batch(data, data.current_program)
		gl.Enable(gl.SCISSOR_TEST)
		// WebGL scissor is bottom-left origin
		gl.Scissor(
			i32(c.rect.x),
			i32(data.height - c.rect.y - c.rect.h),
			i32(c.rect.w),
			i32(c.rect.h),
		)

	case ogui.Draw_Image:
		// Not implemented for WebGL demo
	}
}

webgl_measure_text :: proc(backend: ^ogui.Backend, text: string, font: ogui.Font_Handle, size: f32) -> ogui.Vec2 {
	return ogui.measure_text_builtin(text, size)
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

		// Bind font texture
		tex_loc := gl.GetUniformLocation(program, "u_texture")
		gl.ActiveTexture(gl.TEXTURE0)
		gl.BindTexture(gl.TEXTURE_2D, data.font_texture)
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

push_vertex :: proc(data: ^WebGL_Data, x, y, u, v: f32, color: ogui.Color) {
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

push_colored_quad :: proc(data: ^WebGL_Data, x0, y0, x1, y1: f32, color: ogui.Color) {
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

push_quad_verts :: proc(data: ^WebGL_Data, x0, y0, x1, y1, x2, y2, x3, y3: f32, color: ogui.Color) {
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

ATLAS_W :: 16 * ogui.FONT_CHAR_WIDTH   // 96
ATLAS_H :: 16 * ogui.FONT_CHAR_HEIGHT  // 144

create_font_texture :: proc(data: ^WebGL_Data) {
	// Generate atlas pixel data (alpha-only, stored as RGBA)
	pixels: [ATLAS_W * ATLAS_H * 4]u8
	for ch in 0..<256 {
		cell_x := (ch % 16) * ogui.FONT_CHAR_WIDTH
		cell_y := (ch / 16) * ogui.FONT_CHAR_HEIGHT
		for col in 0..<ogui.FONT_GLYPH_WIDTH {
			for row in 0..<ogui.FONT_GLYPH_HEIGHT {
				if ogui.font_pixel(u8(ch), col, row) {
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

	data.font_texture = gl.CreateTexture()
	gl.BindTexture(gl.TEXTURE_2D, data.font_texture)
	gl.TexImage2DSlice(gl.TEXTURE_2D, 0, gl.RGBA, ATLAS_W, ATLAS_H, 0, gl.RGBA, gl.UNSIGNED_BYTE, pixels[:])
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, i32(gl.NEAREST))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, i32(gl.NEAREST))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, i32(gl.CLAMP_TO_EDGE))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, i32(gl.CLAMP_TO_EDGE))
}

// --- Text rendering ---

draw_text_webgl :: proc(data: ^WebGL_Data, pos: ogui.Vec2, text: string, color: ogui.Color, scale: f32) {
	s := scale
	char_w := f32(ogui.FONT_CHAR_WIDTH) * s
	char_h := f32(ogui.FONT_CHAR_HEIGHT) * s
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
		src_x := f32((idx % 16) * ogui.FONT_CHAR_WIDTH)
		src_y := f32((idx / 16) * ogui.FONT_CHAR_HEIGHT)

		// UV coordinates into the atlas
		u0 := src_x / atlas_w
		v0 := src_y / atlas_h
		u1 := (src_x + f32(ogui.FONT_GLYPH_WIDTH)) / atlas_w
		v1 := (src_y + f32(ogui.FONT_GLYPH_HEIGHT)) / atlas_h

		// Destination quad
		dx0 := cursor_x
		dy0 := cursor_y
		dx1 := cursor_x + f32(ogui.FONT_GLYPH_WIDTH) * s
		dy1 := cursor_y + f32(ogui.FONT_GLYPH_HEIGHT) * s

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

// --- Math helper ---

sqrt_f32 :: proc(x: f32) -> f32 {
	if x <= 0 { return 0 }
	guess := x / 2
	for _ in 0..<10 {
		guess = (guess + x / guess) / 2
	}
	return guess
}

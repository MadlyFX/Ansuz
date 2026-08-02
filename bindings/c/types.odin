package ansuz_c

import ansuz "../../ansuz"

C_Color :: struct {
	r, g, b, a: u8,
}

C_String :: struct {
	data:   [^]u8,
	length: u32,
}

C_Size_Spec :: struct {
	kind:  u32,
	value: f32,
}

C_Size :: struct {
	width:  C_Size_Spec,
	height: C_Size_Spec,
}

C_Edges :: struct {
	top, right, bottom, left: f32,
}

C_Rect :: struct {
	x, y, width, height: f32,
}

C_Vec2 :: struct {
	x, y: f32,
}

C_Widget_Color :: struct {
	bg, fg, hover, press, focus: C_Color,
}

C_Init_Config :: struct {
	width:              i32,
	height:             i32,
	framebuffer:        [^]u32,
	framebuffer_length: uintptr,
	heap:               [^]u8,
	heap_size:          uintptr,
	clear_color:        C_Color,
}

C_Flex_Options :: struct {
	axis:       u32,
	justify:    u32,
	align:      u32,
	gap:        f32,
	size:       C_Size,
	padding:    C_Edges,
	bg_color:   C_Color,
}

C_Grid_Options :: struct {
	gap:      f32,
	size:     C_Size,
	padding:  C_Edges,
	bg_color: C_Color,
}

C_Box_Options :: struct {
	size:     C_Size,
	bg_color: C_Color,
	margin:   C_Edges,
}

C_Grid_Cell_Options :: struct {
	col_span: i32,
	row_span: i32,
	bg_color: C_Color,
	margin:   C_Edges,
}

C_Scroll_Options :: struct {
	axis:       u32,
	gap:        f32,
	size:       C_Size,
	padding:    C_Edges,
	bg_color:   C_Color,
}

C_Label_Options :: struct {
	color:    C_Color,
	bg_color: C_Color,
	font:     u32,
	scale:    f32,
	size:     C_Size,
	padding:  C_Edges,
}

C_Button_Options :: struct {
	scale:      f32,
	size:       C_Size,
	padding:    C_Edges,
	color:      C_Widget_Color,
	text_color: C_Color,
	font:       u32,
}

C_Checkbox_Options :: struct {
	scale:        f32,
	font:         u32,
	color:        C_Widget_Color,
	text_color:   C_Color,
	check_color:  C_Color,
	border_color: C_Color,
}

C_Slider_Options :: struct {
	lo:         f32,
	hi:         f32,
	scale:      f32,
	size:       C_Size,
	color:      C_Widget_Color,
}

C_Slider_Labeled_Options :: struct {
	lo:         f32,
	hi:         f32,
	scale:      f32,
	format:     C_String,
	font:       u32,
	color:      C_Widget_Color,
	text_color: C_Color,
}

C_Dropdown_Options :: struct {
	size:               C_Size,
	scale:              f32,
	font:               u32,
	color:              C_Widget_Color,
	text_color:         C_Color,
	indicator_color:    C_Color,
	popup_color:        C_Color,
	popup_border_color: C_Color,
	item_hover_color:   C_Color,
	selected_color:     C_Color,
}

C_Text_Input_Options :: struct {
	multiline:        u8,
	font:             u32,
	scale:            f32,
	size:             C_Size,
	padding:          C_Edges,
	placeholder:      C_String,
	color:            C_Widget_Color,
	text_color:       C_Color,
	placeholder_color: C_Color,
	cursor_color:     C_Color,
}

C_Text_Buffer :: struct {
	data:     [^]u8,
	capacity: u32,
	length:   u32,
}

C_Image :: struct {
	handle: rawptr,
	width:  i32,
	height: i32,
}

C_Image_Options :: struct {
	size: C_Size,
	tint: C_Color,
}

C_Animation_Options :: struct {
	duration:  f32,
	easing:    u32,
	looping:   u8,
	ping_pong: u8,
}

when size_of(uintptr) == 4 {
	#assert(size_of(C_Color) == 4)
	#assert(size_of(C_String) == 8)
	#assert(size_of(C_Init_Config) == 28)
	#assert(size_of(C_Flex_Options) == 52)
	#assert(size_of(C_Label_Options) == 48)
	#assert(size_of(C_Button_Options) == 64)
	#assert(size_of(C_Checkbox_Options) == 40)
	#assert(size_of(C_Slider_Options) == 48)
	#assert(size_of(C_Slider_Labeled_Options) == 48)
	#assert(size_of(C_Dropdown_Options) == 68)
	#assert(size_of(C_Text_Input_Options) == 84)
	#assert(size_of(C_Text_Buffer) == 12)
	#assert(size_of(C_Image) == 12)
	#assert(size_of(C_Animation_Options) == 12)

	#assert(offset_of(C_Init_Config, framebuffer_length) == 12)
	#assert(offset_of(C_Init_Config, heap) == 16)
	#assert(offset_of(C_Init_Config, clear_color) == 24)
	#assert(offset_of(C_Label_Options, font) == 8)
	#assert(offset_of(C_Label_Options, size) == 16)
	#assert(offset_of(C_Button_Options, color) == 36)
	#assert(offset_of(C_Button_Options, font) == 60)
	#assert(offset_of(C_Text_Input_Options, font) == 4)
	#assert(offset_of(C_Text_Input_Options, size) == 12)
	#assert(offset_of(C_Text_Input_Options, placeholder) == 44)
	#assert(offset_of(C_Text_Input_Options, color) == 52)
	#assert(offset_of(C_Text_Input_Options, cursor_color) == 80)
}

to_color :: proc(color: C_Color) -> ansuz.Color {
	return ansuz.Color{color.r, color.g, color.b, color.a}
}

to_string :: proc(value: C_String) -> string {
	if value.data == nil || value.length == 0 {
		return ""
	}
	return string(value.data[:int(value.length)])
}

to_size_spec :: proc(spec: C_Size_Spec) -> ansuz.Size_Spec {
	switch spec.kind {
	case 0:
		return ansuz.size_fixed(spec.value)
	case 1:
		return ansuz.size_pct(spec.value)
	case 2:
		return ansuz.size_grow(spec.value)
	case 3, 4: // ANSUZ_SIZE_FIT; ANSUZ_SIZE_AUTO is a legacy alias of FIT
		return ansuz.SIZE_FIT
	}
	return ansuz.SIZE_FIT
}

to_size :: proc(size: C_Size) -> [2]ansuz.Size_Spec {
	return {to_size_spec(size.width), to_size_spec(size.height)}
}

to_edges :: proc(edges: C_Edges) -> [4]f32 {
	return {edges.top, edges.right, edges.bottom, edges.left}
}

to_widget_color :: proc(color: C_Widget_Color) -> ansuz.Widget_Color {
	return ansuz.Widget_Color{
		bg     = to_color(color.bg),
		fg     = to_color(color.fg),
		hover  = to_color(color.hover),
		press  = to_color(color.press),
		focus  = to_color(color.focus),
	}
}

to_axis :: proc(value: u32) -> ansuz.Axis {
	return .Vertical if value == 1 else .Horizontal
}

to_justify :: proc(value: u32) -> ansuz.Justify {
	switch value {
	case 1: return .Center
	case 2: return .End
	case 3: return .Space_Between
	case 4: return .Space_Around
	case 5: return .Space_Evenly
	}
	return .Start
}

to_align :: proc(value: u32) -> ansuz.Align {
	switch value {
	case 0: return .Start
	case 1: return .Center
	case 2: return .End
	}
	return .Stretch
}

to_font :: proc(value: u32) -> ansuz.Font_Handle {
	return ansuz.Font_Handle(value)
}

to_rect :: proc(rect: ansuz.Rect) -> C_Rect {
	return C_Rect{rect.x, rect.y, rect.w, rect.h}
}

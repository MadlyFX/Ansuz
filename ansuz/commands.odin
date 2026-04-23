package ansuz

// --- Draw Commands ---
// Abstract rendering primitives consumed by the backend each frame.

Draw_Filled_Rect :: struct {
	rect:   Rect,
	color:  Color,
	radius: f32,
}

Draw_Rect_Outline :: struct {
	rect:      Rect,
	color:     Color,
	thickness: f32,
	radius:    f32,
}

Draw_Line :: struct {
	p0, p1:    Vec2,
	color:     Color,
	thickness: f32,
}

Draw_Text :: struct {
	pos:   Vec2,
	text:  string,
	color: Color,
	font:  Font_Handle,
	size:  f32,
}

Draw_Clip :: struct {
	rect: Rect,
}

Draw_Image :: struct {
	rect:   Rect,
	handle: rawptr,
	tint:   Color,
}

Draw_Command :: union {
	Draw_Filled_Rect,
	Draw_Rect_Outline,
	Draw_Line,
	Draw_Text,
	Draw_Clip,
	Draw_Image,
}

// --- Draw Command Buffer ---

Draw_List :: struct {
	commands: [dynamic]Draw_Command,
}

draw_list_init :: proc(dl: ^Draw_List, allocator := context.allocator) {
	dl.commands = make([dynamic]Draw_Command, 0, 256, allocator)
}

draw_list_destroy :: proc(dl: ^Draw_List) {
	delete(dl.commands)
}

draw_list_clear :: proc(dl: ^Draw_List) {
	clear(&dl.commands)
}

push_filled_rect :: proc(dl: ^Draw_List, rect: Rect, color: Color, radius: f32 = 0) {
	append(&dl.commands, Draw_Command(Draw_Filled_Rect{rect, color, radius}))
}

push_rect_outline :: proc(dl: ^Draw_List, rect: Rect, color: Color, thickness: f32 = 1, radius: f32 = 0) {
	append(&dl.commands, Draw_Command(Draw_Rect_Outline{rect, color, thickness, radius}))
}

push_line :: proc(dl: ^Draw_List, p0, p1: Vec2, color: Color, thickness: f32 = 1) {
	append(&dl.commands, Draw_Command(Draw_Line{p0, p1, color, thickness}))
}

push_text :: proc(dl: ^Draw_List, pos: Vec2, text: string, color: Color, font: Font_Handle = 0, size: f32 = 14) {
	append(&dl.commands, Draw_Command(Draw_Text{pos, text, color, font, size}))
}

push_clip :: proc(dl: ^Draw_List, rect: Rect) {
	append(&dl.commands, Draw_Command(Draw_Clip{rect}))
}

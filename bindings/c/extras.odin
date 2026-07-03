package ansuz_c

import ansuz "../../ansuz"
import soft "../../backend_soft"

@(export)
ansuz_set_default_font :: proc "c" (font: u32) {
	if !initialized {
		return
	}
	context = odin_context
	ansuz.set_default_font(&manager, to_font(font))
}

@(export)
ansuz_measure_text :: proc "c" (
	text: C_String,
	font: u32,
	scale: f32,
	out_size: ^C_Vec2,
) -> u8 {
	if !initialized || out_size == nil {
		return 0
	}
	context = odin_context
	size := ansuz.measure_text(&manager, to_string(text), to_font(font), scale)
	out_size^ = C_Vec2{size.x, size.y}
	return 1
}

@(export)
ansuz_get_delta_time :: proc "c" () -> f32 {
	if !initialized {
		return 0
	}
	context = odin_context
	return ansuz.get_dt(&manager)
}

@(export)
ansuz_color_lerp :: proc "c" (from, to: C_Color, amount: f32) -> C_Color {
	if !initialized {
		return C_Color{}
	}
	context = odin_context
	color := ansuz.color_lerp(to_color(from), to_color(to), amount)
	return C_Color{color.r, color.g, color.b, color.a}
}

@(export)
ansuz_ease_apply :: proc "c" (amount: f32, easing: u32) -> f32 {
	if !initialized {
		return 0
	}
	context = odin_context
	return ansuz.ease_apply(amount, ansuz.Ease_Func(easing))
}

@(export)
ansuz_ease_lerp :: proc "c" (from, to, amount: f32, easing: u32) -> f32 {
	if !initialized {
		return 0
	}
	context = odin_context
	return ansuz.ease_lerp(from, to, amount, ansuz.Ease_Func(easing))
}

@(export)
ansuz_ease_color :: proc "c" (
	from, to: C_Color,
	amount: f32,
	easing: u32,
) -> C_Color {
	if !initialized {
		return C_Color{}
	}
	context = odin_context
	color := ansuz.ease_color(to_color(from), to_color(to), amount, ansuz.Ease_Func(easing))
	return C_Color{color.r, color.g, color.b, color.a}
}

@(export)
ansuz_image_create :: proc "c" (
	pixels: [^]u8,
	pixel_byte_count: uintptr,
	width, height, channels: i32,
	out_image: ^C_Image,
) -> u8 {
	if !initialized || pixels == nil || out_image == nil || width <= 0 || height <= 0 {
		return 0
	}
	if channels < 1 || channels > 4 {
		return 0
	}
	required := uintptr(width) * uintptr(height) * uintptr(channels)
	if pixel_byte_count < required {
		return 0
	}
	context = odin_context
	image := soft.create_image(
		&backend,
		pixels[:int(required)],
		width,
		height,
		channels,
	)
	if image.ptr == nil {
		return 0
	}
	out_image^ = C_Image{image.ptr, image.width, image.height}
	return 1
}

@(export)
ansuz_image_destroy :: proc "c" (image: ^C_Image) {
	if !initialized || image == nil || image.handle == nil {
		return
	}
	context = odin_context
	soft.destroy_image(
		ansuz.Image_Handle{
			ptr = image.handle,
			width = image.width,
			height = image.height,
		},
	)
	image^ = C_Image{}
}

@(export)
ansuz_image :: proc "c" (id: u64, image: ^C_Image, options: ^C_Image_Options) -> i32 {
	if !initialized || !frame_open || image == nil || image.handle == nil {
		return -1
	}
	context = odin_context
	push_scoped_id(id)
	defer pop_scoped_id()
	handle := ansuz.Image_Handle{
		ptr = image.handle,
		width = image.width,
		height = image.height,
	}
	if options == nil {
		return i32(ansuz.image(&manager, handle))
	}
	return i32(
		ansuz.image(
			&manager,
			handle,
			size = to_size(options.size),
			tint = to_color(options.tint),
		),
	)
}

@(export)
ansuz_animate_f32 :: proc "c" (
	id: u64,
	value: ^f32,
	target: f32,
	options: ^C_Animation_Options,
) {
	if !initialized || value == nil {
		return
	}
	context = odin_context
	animation_id := make_scoped_id(id)
	if options == nil {
		ansuz.animate_f32_id(&manager, animation_id, value, target)
		return
	}
	ansuz.animate_f32_id(
		&manager,
		animation_id,
		value,
		target,
		duration = options.duration,
		easing = ansuz.Ease_Func(options.easing),
		looping = options.looping != 0,
		ping_pong = options.ping_pong != 0,
	)
}

@(export)
ansuz_animate_color :: proc "c" (
	id: u64,
	value: ^C_Color,
	target: C_Color,
	options: ^C_Animation_Options,
) {
	if !initialized || value == nil {
		return
	}
	context = odin_context
	animation_id := make_scoped_id(id)
	color_value := cast(^ansuz.Color)value
	if options == nil {
		ansuz.animate_color_id(&manager, animation_id, color_value, to_color(target))
		return
	}
	ansuz.animate_color_id(
		&manager,
		animation_id,
		color_value,
		to_color(target),
		duration = options.duration,
		easing = ansuz.Ease_Func(options.easing),
	)
}

@(export)
ansuz_spring_f32 :: proc "c" (
	id: u64,
	value: ^f32,
	target, duration: f32,
	easing: u32,
	epsilon: f32,
) {
	if !initialized || value == nil {
		return
	}
	context = odin_context
	ansuz.spring_f32_id(
		&manager,
		make_scoped_id(id),
		value,
		target,
		duration,
		ansuz.Ease_Func(easing),
		epsilon,
	)
}

@(export)
ansuz_cancel_animation :: proc "c" (id: u64) {
	if !initialized {
		return
	}
	context = odin_context
	ansuz.cancel_animation_id(&manager, make_scoped_id(id))
}

@(export)
ansuz_is_animating :: proc "c" (id: u64) -> u8 {
	if !initialized {
		return 0
	}
	context = odin_context
	return 1 if ansuz.is_animating_id(&manager, make_scoped_id(id)) else 0
}

@(export)
ansuz_draw_filled_rect :: proc "c" (rect: C_Rect, color: C_Color, radius: f32) {
	if !initialized || !frame_open {
		return
	}
	context = odin_context
	ansuz.push_filled_rect(
		&manager.draw_list,
		ansuz.Rect{rect.x, rect.y, rect.width, rect.height},
		to_color(color),
		radius,
	)
}

@(export)
ansuz_draw_rect_outline :: proc "c" (
	rect: C_Rect,
	color: C_Color,
	thickness, radius: f32,
) {
	if !initialized || !frame_open {
		return
	}
	context = odin_context
	ansuz.push_rect_outline(
		&manager.draw_list,
		ansuz.Rect{rect.x, rect.y, rect.width, rect.height},
		to_color(color),
		thickness,
		radius,
	)
}

@(export)
ansuz_draw_line :: proc "c" (
	x0, y0, x1, y1: f32,
	color: C_Color,
	thickness: f32,
) {
	if !initialized || !frame_open {
		return
	}
	context = odin_context
	ansuz.push_line(
		&manager.draw_list,
		ansuz.Vec2{x0, y0},
		ansuz.Vec2{x1, y1},
		to_color(color),
		thickness,
	)
}

@(export)
ansuz_draw_text :: proc "c" (
	x, y: f32,
	text: C_String,
	color: C_Color,
	font: u32,
	scale: f32,
) {
	if !initialized || !frame_open {
		return
	}
	context = odin_context
	effective_font := ansuz.resolve_font(&manager, to_font(font))
	effective_scale := ansuz.get_effective_scale(&manager, effective_font, scale)
	ansuz.push_text(
		&manager.draw_list,
		ansuz.Vec2{x, y},
		to_string(text),
		to_color(color),
		effective_font,
		effective_scale,
	)
}

@(export)
ansuz_draw_clip :: proc "c" (rect: C_Rect) {
	if !initialized || !frame_open {
		return
	}
	context = odin_context
	ansuz.push_clip(
		&manager.draw_list,
		ansuz.Rect{rect.x, rect.y, rect.width, rect.height},
	)
}

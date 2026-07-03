package ansuz_c

import ansuz "../../ansuz"
import soft "../../backend_soft"
import "base:runtime"
import "core:mem"

backend: ansuz.Backend
manager: ansuz.Manager

heap_arena: mem.Arena
odin_context: runtime.Context

framebuffer_ptr: [^]u32
framebuffer_length: uintptr

initialized: bool
frame_open: bool

Text_Buffer_State :: struct {
	buffer: [dynamic]u8,
}

text_buffers: map[u64]^Text_Buffer_State
dropdown_values: map[u64]^int

make_scoped_id :: proc(id: u64) -> ansuz.Widget_ID {
	parent := ansuz.id_stack_top(&manager.id_stack)
	return ansuz.Widget_ID(ansuz.hash_u64(id, parent))
}

push_scoped_id :: proc(id: u64) {
	ansuz.id_stack_push(&manager.id_stack, make_scoped_id(id))
}

pop_scoped_id :: proc() {
	ansuz.id_stack_pop(&manager.id_stack)
}

@(export)
ansuz_init :: proc "c" (config: ^C_Init_Config) -> u8 {
	if initialized || config == nil {
		return 0
	}
	if config.width <= 0 || config.height <= 0 {
		return 0
	}
	required_pixels := uintptr(config.width) * uintptr(config.height)
	if config.framebuffer == nil || config.framebuffer_length < required_pixels {
		return 0
	}
	if config.heap == nil || config.heap_size == 0 {
		return 0
	}

	context = runtime.default_context()
	mem.arena_init(&heap_arena, config.heap[:int(config.heap_size)])
	context.allocator = mem.arena_allocator(&heap_arena)

	framebuffer_ptr = config.framebuffer
	framebuffer_length = config.framebuffer_length
	framebuffer := config.framebuffer[:int(required_pixels)]

	backend = soft.create(config.width, config.height, framebuffer)
	if backend.init != nil && !backend.init(&backend, config.width, config.height) {
		return 0
	}
	soft.set_clear_color(&backend, to_color(config.clear_color))

	ansuz.init(&manager, &backend)
	context.temp_allocator = manager.frame_allocator
	text_buffers = make(map[u64]^Text_Buffer_State, 8)
	dropdown_values = make(map[u64]^int, 8)

	odin_context = context
	initialized = true
	return 1
}

@(export)
ansuz_shutdown :: proc "c" () {
	if !initialized {
		return
	}
	context = odin_context

	for _, state in text_buffers {
		delete(state.buffer)
		free(state)
	}
	delete(text_buffers)
	for _, value in dropdown_values {
		free(value)
	}
	delete(dropdown_values)

	ansuz.shutdown(&manager)
	if backend.shutdown != nil {
		backend.shutdown(&backend)
	}

	initialized = false
	frame_open = false
	framebuffer_ptr = nil
	framebuffer_length = 0
}

@(export)
ansuz_is_initialized :: proc "c" () -> u8 {
	return 1 if initialized else 0
}

@(export)
ansuz_should_quit :: proc "c" () -> u8 {
	if !initialized {
		return 1
	}
	context = odin_context
	return 1 if ansuz.should_quit(&manager) else 0
}

@(export)
ansuz_frame_begin :: proc "c" (delta_seconds: f32) {
	if !initialized || frame_open {
		return
	}
	context = odin_context
	ansuz.frame_begin(&manager, delta_seconds)
	frame_open = true
}

@(export)
ansuz_frame_end :: proc "c" () {
	if !initialized || !frame_open {
		return
	}
	context = odin_context
	ansuz.frame_end(&manager)
	frame_open = false
}

@(export)
ansuz_set_clear_color :: proc "c" (color: C_Color) {
	if !initialized {
		return
	}
	context = odin_context
	soft.set_clear_color(&backend, to_color(color))
}

@(export)
ansuz_get_width :: proc "c" () -> i32 {
	return backend.width if initialized else 0
}

@(export)
ansuz_get_height :: proc "c" () -> i32 {
	return backend.height if initialized else 0
}

@(export)
ansuz_get_framebuffer :: proc "c" () -> [^]u32 {
	return framebuffer_ptr if initialized else nil
}

@(export)
ansuz_get_framebuffer_length :: proc "c" () -> uintptr {
	return framebuffer_length if initialized else 0
}

@(export)
ansuz_push_id :: proc "c" (id: u64) {
	if !initialized {
		return
	}
	context = odin_context
	push_scoped_id(id)
}

@(export)
ansuz_push_id_string :: proc "c" (id: C_String) {
	if !initialized {
		return
	}
	context = odin_context
	parent := ansuz.id_stack_top(&manager.id_stack)
	scoped := ansuz.Widget_ID(ansuz.hash_string(to_string(id), parent))
	ansuz.id_stack_push(&manager.id_stack, scoped)
}

@(export)
ansuz_pop_id :: proc "c" () {
	if !initialized || manager.id_stack.count == 0 {
		return
	}
	context = odin_context
	pop_scoped_id()
}

@(export)
ansuz_input_pointer :: proc "c" (x, y: f32, left, right, middle: u8) {
	if !initialized {
		return
	}
	context = odin_context
	manager.input.mouse_prev_x = manager.input.mouse_x
	manager.input.mouse_prev_y = manager.input.mouse_y
	manager.input.mouse_x = x
	manager.input.mouse_y = y

	left_down := left != 0
	manager.input.mouse_left_pressed = left_down && !manager.input.mouse_left
	manager.input.mouse_left = left_down
	manager.input.mouse_right = right != 0
	manager.input.mouse_middle = middle != 0
}

@(export)
ansuz_input_scroll :: proc "c" (delta_y: f32) {
	if !initialized {
		return
	}
	context = odin_context
	manager.input.mouse_scroll_y += delta_y
}

@(export)
ansuz_input_text :: proc "c" (text: C_String) {
	if !initialized || text.data == nil {
		return
	}
	context = odin_context
	available := len(manager.input.text_chars) - manager.input.text_char_len
	count := min(int(text.length), available)
	for i in 0..<count {
		manager.input.text_chars[manager.input.text_char_len + i] = text.data[i]
	}
	manager.input.text_char_len += count
}

@(export)
ansuz_input_key :: proc "c" (key: u32, down: u8) {
	if !initialized {
		return
	}
	context = odin_context
	is_down := down != 0
	switch key {
	case 0: manager.input.key_backspace = is_down
	case 1: manager.input.key_delete = is_down
	case 2: manager.input.key_left = is_down
	case 3: manager.input.key_right = is_down
	case 4: manager.input.key_up = is_down
	case 5: manager.input.key_down = is_down
	case 6: manager.input.key_home = is_down
	case 7: manager.input.key_end = is_down
	case 8: manager.input.key_enter = is_down
	case 9: manager.input.key_shift = is_down
	case 10: manager.input.key_ctrl = is_down
	}
}

@(export)
ansuz_any_value_dirty :: proc "c" () -> u8 {
	if !initialized {
		return 0
	}
	context = odin_context
	return 1 if ansuz.any_value_dirty(&manager) else 0
}

@(export)
ansuz_get_box_rect :: proc "c" (box_index: i32, out_rect: ^C_Rect) -> u8 {
	if !initialized || out_rect == nil || box_index < 0 || int(box_index) >= len(manager.boxes) {
		return 0
	}
	context = odin_context
	out_rect^ = to_rect(manager.boxes[int(box_index)].computed_rect)
	return 1
}

@(export)
ansuz_get_box_content_rect :: proc "c" (box_index: i32, out_rect: ^C_Rect) -> u8 {
	if !initialized || out_rect == nil || box_index < 0 || int(box_index) >= len(manager.boxes) {
		return 0
	}
	context = odin_context
	out_rect^ = to_rect(manager.boxes[int(box_index)].content_rect)
	return 1
}

package ansuz_c

import ansuz "../../ansuz"

interaction_bits :: proc(interaction: ansuz.Interaction) -> u32 {
	result: u32
	if .Hovered in interaction { result |= 1 << 0 }
	if .Pressed in interaction { result |= 1 << 1 }
	if .Clicked in interaction { result |= 1 << 2 }
	if .Focused in interaction { result |= 1 << 3 }
	return result
}

to_strings :: proc(values: [^]C_String, count: u32) -> []string {
	if values == nil || count == 0 {
		return nil
	}
	result := make([]string, int(count), context.temp_allocator)
	for i in 0..<int(count) {
		result[i] = to_string(values[i])
	}
	return result
}

@(export)
ansuz_label :: proc "c" (id: u64, text: C_String, options: ^C_Label_Options) -> i32 {
	if !initialized || !frame_open {
		return -1
	}
	context = odin_context
	push_scoped_id(id)
	defer pop_scoped_id()

	if options == nil {
		return i32(ansuz.label(&manager, to_string(text)))
	}
	return i32(
		ansuz.label(
			&manager,
			to_string(text),
			color = to_color(options.color),
			bg_color = to_color(options.bg_color),
			font = to_font(options.font),
			scale = options.scale,
			size = to_size(options.size),
			padding = to_edges(options.padding),
		),
	)
}

@(export)
ansuz_label_decorated :: proc "c" (
	id: u64,
	text, decorator: C_String,
	affix: u32,
	options: ^C_Label_Options,
) -> i32 {
	if !initialized || !frame_open {
		return -1
	}
	context = odin_context
	push_scoped_id(id)
	defer pop_scoped_id()
	affix_value: ansuz.Affix = .Prefix
	if affix == 0 {
		affix_value = .None
	} else if affix == 2 {
		affix_value = .Suffix
	}

	if options == nil {
		return i32(
			ansuz.label_decorated(
				&manager,
				to_string(text),
				to_string(decorator),
				affix = affix_value,
			),
		)
	}
	return i32(
		ansuz.label_decorated(
			&manager,
			to_string(text),
			to_string(decorator),
			color = to_color(options.color),
			bg_color = to_color(options.bg_color),
			affix = affix_value,
			font = to_font(options.font),
			scale = options.scale,
			size = to_size(options.size),
			padding = to_edges(options.padding),
		),
	)
}

@(export)
ansuz_heading :: proc "c" (id: u64, text: C_String, options: ^C_Label_Options) -> i32 {
	if !initialized || !frame_open {
		return -1
	}
	context = odin_context
	push_scoped_id(id)
	defer pop_scoped_id()

	if options == nil {
		return i32(ansuz.heading(&manager, to_string(text)))
	}
	return i32(
		ansuz.heading(
			&manager,
			to_string(text),
			color = to_color(options.color),
			bg_color = to_color(options.bg_color),
			font = to_font(options.font),
			scale = options.scale,
			size = to_size(options.size),
			padding = to_edges(options.padding),
		),
	)
}

@(export)
ansuz_button :: proc "c" (id: u64, text: C_String, options: ^C_Button_Options) -> u32 {
	if !initialized || !frame_open {
		return 0
	}
	context = odin_context
	push_scoped_id(id)
	defer pop_scoped_id()

	if options == nil {
		return interaction_bits(ansuz.button(&manager, to_string(text)))
	}
	return interaction_bits(
		ansuz.button(
			&manager,
			to_string(text),
			scale = options.scale,
			size = to_size(options.size),
			padding = to_edges(options.padding),
			colors = to_widget_color(options.color),
			text_color = to_color(options.text_color),
			font = to_font(options.font),
		),
	)
}

@(export)
ansuz_checkbox :: proc "c" (
	id: u64,
	text: C_String,
	value: ^u8,
	options: ^C_Checkbox_Options,
) -> u32 {
	if !initialized || !frame_open || value == nil {
		return 0
	}
	context = odin_context
	push_scoped_id(id)
	defer pop_scoped_id()
	bool_value := cast(^bool)value

	if options == nil {
		return interaction_bits(ansuz.checkbox(&manager, to_string(text), bool_value))
	}
	return interaction_bits(
		ansuz.checkbox(
			&manager,
			to_string(text),
			bool_value,
			scale = options.scale,
			font = to_font(options.font),
			colors = to_widget_color(options.color),
			text_color = to_color(options.text_color),
			check_color = to_color(options.check_color),
			border_color = to_color(options.border_color),
		),
	)
}

@(export)
ansuz_slider_f32 :: proc "c" (
	id: u64,
	value: ^f32,
	options: ^C_Slider_Options,
) -> u32 {
	if !initialized || !frame_open || value == nil {
		return 0
	}
	context = odin_context
	push_scoped_id(id)
	defer pop_scoped_id()

	if options == nil {
		return interaction_bits(ansuz.slider_f32(&manager, value))
	}
	return interaction_bits(
		ansuz.slider_f32(
			&manager,
			value,
			options.lo,
			options.hi,
			scale = options.scale,
			colors = to_widget_color(options.color),
			size = to_size(options.size),
		),
	)
}

@(export)
ansuz_slider_labeled_f32 :: proc "c" (
	id: u64,
	text: C_String,
	value: ^f32,
	options: ^C_Slider_Labeled_Options,
) -> u32 {
	if !initialized || !frame_open || value == nil {
		return 0
	}
	context = odin_context
	push_scoped_id(id)
	defer pop_scoped_id()

	if options == nil {
		return interaction_bits(ansuz.slider_labeled(&manager, to_string(text), value))
	}
	format := to_string(options.format)
	if len(format) == 0 {
		format = "%.2f"
	}
	return interaction_bits(
		ansuz.slider_labeled(
			&manager,
			to_string(text),
			value,
			options.lo,
			options.hi,
			scale = options.scale,
			format = format,
			font = to_font(options.font),
			colors = to_widget_color(options.color),
			text_color = to_color(options.text_color),
		),
	)
}

@(export)
ansuz_dropdown :: proc "c" (
	id: u64,
	selected: ^i32,
	options_list: [^]C_String,
	option_count: u32,
	options: ^C_Dropdown_Options,
) -> u32 {
	if !initialized || !frame_open || selected == nil {
		return 0
	}
	context = odin_context
	values := to_strings(options_list, option_count)
	bridge_key := u64(make_scoped_id(id))

	if bridge_key not_in dropdown_values {
		dropdown_values[bridge_key] = new(int)
	}
	bridge_value := dropdown_values[bridge_key]
	bridge_value^ = int(selected^)

	push_scoped_id(id)
	defer pop_scoped_id()

	interaction: ansuz.Interaction
	if options == nil {
		interaction = ansuz.dropdown(&manager, bridge_value, values)
	} else {
		interaction = ansuz.dropdown(
			&manager,
			bridge_value,
			values,
			size = to_size(options.size),
			scale = options.scale,
			font = to_font(options.font),
			colors = to_widget_color(options.color),
			text_color = to_color(options.text_color),
			indicator_color = to_color(options.indicator_color),
			popup_color = to_color(options.popup_color),
			popup_border_color = to_color(options.popup_border_color),
			item_hover_color = to_color(options.item_hover_color),
			selected_color = to_color(options.selected_color),
		)
	}
	selected^ = i32(bridge_value^)
	return interaction_bits(interaction)
}

get_text_buffer :: proc(id: u64, capacity: int) -> ^Text_Buffer_State {
	if id not_in text_buffers {
		state := new(Text_Buffer_State)
		state.buffer = make([dynamic]u8, 0, max(capacity, 1))
		text_buffers[id] = state
	}
	return text_buffers[id]
}

@(export)
ansuz_text_input :: proc "c" (
	id: u64,
	buffer: ^C_Text_Buffer,
	options: ^C_Text_Input_Options,
) -> u32 {
	if !initialized || !frame_open || buffer == nil || buffer.data == nil || buffer.capacity == 0 {
		return 0
	}
	context = odin_context
	max_length := int(buffer.capacity) - 1
	input_length := min(int(buffer.length), max_length)
	bridge_key := u64(make_scoped_id(id))
	state := get_text_buffer(bridge_key, max_length)
	clear(&state.buffer)
	for i in 0..<input_length {
		append(&state.buffer, buffer.data[i])
	}

	push_scoped_id(id)
	defer pop_scoped_id()

	interaction: ansuz.Interaction
	if options == nil {
		interaction, _ = ansuz.text_input(&manager, &state.buffer)
	} else {
		interaction, _ = ansuz.text_input(
			&manager,
			&state.buffer,
			multiline = options.multiline != 0,
			font = to_font(options.font),
			scale = options.scale,
			size = to_size(options.size),
			padding = to_edges(options.padding),
			placeholder = to_string(options.placeholder),
			colors = to_widget_color(options.color),
			text_color = to_color(options.text_color),
			placeholder_color = to_color(options.placeholder_color),
			cursor_color = to_color(options.cursor_color),
		)
	}

	if len(state.buffer) > max_length {
		resize(&state.buffer, max_length)
	}
	for i in 0..<len(state.buffer) {
		buffer.data[i] = state.buffer[i]
	}
	buffer.data[len(state.buffer)] = 0
	buffer.length = u32(len(state.buffer))
	return interaction_bits(interaction)
}

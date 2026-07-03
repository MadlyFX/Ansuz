package ansuz_c

import ansuz "../../ansuz"

to_size_specs :: proc(specs: [^]C_Size_Spec, count: u32) -> []ansuz.Size_Spec {
	if specs == nil || count == 0 {
		return nil
	}
	result := make([]ansuz.Size_Spec, int(count), context.temp_allocator)
	for i in 0..<int(count) {
		result[i] = to_size_spec(specs[i])
	}
	return result
}

@(export)
ansuz_flex_begin :: proc "c" (id: u64, options: ^C_Flex_Options) {
	if !initialized || !frame_open {
		return
	}
	context = odin_context
	push_scoped_id(id)

	if options == nil {
		ansuz.flex_begin(&manager)
		return
	}
	ansuz.flex_begin(
		&manager,
		axis = to_axis(options.axis),
		justify = to_justify(options.justify),
		align = to_align(options.align),
		gap = options.gap,
		size = to_size(options.size),
		padding = to_edges(options.padding),
		bg_color = to_color(options.bg_color),
	)
}

@(export)
ansuz_flex_end :: proc "c" () {
	if !initialized || !frame_open || len(manager.box_stack) <= 1 {
		return
	}
	context = odin_context
	ansuz.flex_end(&manager)
	pop_scoped_id()
}

@(export)
ansuz_grid_begin :: proc "c" (
	id: u64,
	columns: [^]C_Size_Spec,
	column_count: u32,
	rows: [^]C_Size_Spec,
	row_count: u32,
	options: ^C_Grid_Options,
) {
	if !initialized || !frame_open || columns == nil || column_count == 0 {
		return
	}
	context = odin_context
	cols := to_size_specs(columns, column_count)
	row_specs := to_size_specs(rows, row_count)
	push_scoped_id(id)

	if options == nil {
		ansuz.grid_begin(&manager, cols, rows = row_specs)
		return
	}
	ansuz.grid_begin(
		&manager,
		cols,
		rows = row_specs,
		gap = options.gap,
		size = to_size(options.size),
		padding = to_edges(options.padding),
		bg_color = to_color(options.bg_color),
	)
}

@(export)
ansuz_grid_end :: proc "c" () {
	if !initialized || !frame_open || len(manager.box_stack) <= 1 {
		return
	}
	context = odin_context
	ansuz.grid_end(&manager)
	pop_scoped_id()
}

@(export)
ansuz_scroll_begin :: proc "c" (id: u64, options: ^C_Scroll_Options) {
	if !initialized || !frame_open {
		return
	}
	context = odin_context
	push_scoped_id(id)

	if options == nil {
		ansuz.scroll_begin(&manager)
		return
	}
	ansuz.scroll_begin(
		&manager,
		axis = to_axis(options.axis),
		gap = options.gap,
		size = to_size(options.size),
		padding = to_edges(options.padding),
		bg_color = to_color(options.bg_color),
	)
}

@(export)
ansuz_scroll_end :: proc "c" () {
	if !initialized || !frame_open || len(manager.box_stack) <= 1 {
		return
	}
	context = odin_context
	ansuz.scroll_end(&manager)
	pop_scoped_id()
}

@(export)
ansuz_box :: proc "c" (id: u64, options: ^C_Box_Options) -> i32 {
	if !initialized || !frame_open {
		return -1
	}
	context = odin_context
	push_scoped_id(id)
	defer pop_scoped_id()

	if options == nil {
		return i32(ansuz.box(&manager))
	}
	return i32(
		ansuz.box(
			&manager,
			size = to_size(options.size),
			bg_color = to_color(options.bg_color),
			margin = to_edges(options.margin),
		),
	)
}

@(export)
ansuz_grid_cell :: proc "c" (
	id: u64,
	column, row: i32,
	options: ^C_Grid_Cell_Options,
) -> i32 {
	if !initialized || !frame_open {
		return -1
	}
	context = odin_context
	push_scoped_id(id)
	defer pop_scoped_id()

	if options == nil {
		return i32(ansuz.grid_cell(&manager, int(column), int(row)))
	}
	return i32(
		ansuz.grid_cell(
			&manager,
			int(column),
			int(row),
			col_span = int(options.col_span),
			row_span = int(options.row_span),
			bg_color = to_color(options.bg_color),
			margin = to_edges(options.margin),
		),
	)
}

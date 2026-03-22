package ogui

// --- Grid Layout Solver ---
// Resolves sizes and positions for children of a grid container.
// Children specify their cell via grid_col/grid_row/grid_col_span/grid_row_span.

grid_solve :: proc(mgr: ^Manager, box_idx: int) {
	b := &mgr.boxes[box_idx]
	if b.child_count == 0 {
		return
	}

	avail_w := content_size(b, 0)
	avail_h := content_size(b, 1)
	origin_x := content_origin(b, 0)
	origin_y := content_origin(b, 1)

	num_cols := len(b.grid_cols) if len(b.grid_cols) > 0 else 1
	num_rows := len(b.grid_rows) if len(b.grid_rows) > 0 else infer_grid_rows(mgr, box_idx, num_cols)

	// Resolve column widths
	col_sizes := make([]f32, num_cols, context.temp_allocator)
	resolve_track_sizes(b.grid_cols, avail_w, b.gap, col_sizes)

	// Resolve row heights
	row_sizes := make([]f32, num_rows, context.temp_allocator)
	if len(b.grid_rows) > 0 {
		resolve_track_sizes(b.grid_rows, avail_h, b.gap, row_sizes)
	} else {
		// Auto rows: distribute evenly
		total_gap := b.gap * f32(max(0, num_rows - 1))
		per_row := (avail_h - total_gap) / f32(num_rows)
		for i in 0..<num_rows {
			row_sizes[i] = max(0, per_row)
		}
	}

	// Compute cumulative positions
	col_pos := make([]f32, num_cols, context.temp_allocator)
	row_pos := make([]f32, num_rows, context.temp_allocator)

	col_pos[0] = origin_x
	for i in 1..<num_cols {
		col_pos[i] = col_pos[i-1] + col_sizes[i-1] + b.gap
	}

	row_pos[0] = origin_y
	for i in 1..<num_rows {
		row_pos[i] = row_pos[i-1] + row_sizes[i-1] + b.gap
	}

	// Place children into their cells
	child_idx := b.first_child
	auto_col := 0
	auto_row := 0

	for child_idx != -1 {
		child := &mgr.boxes[child_idx]

		col := child.grid_col
		row := child.grid_row
		col_span := max(1, child.grid_col_span)
		row_span := max(1, child.grid_row_span)

		// Auto-placement if child didn't specify a cell
		if child.grid_col_span == 0 && child.grid_row_span == 0 {
			col = auto_col
			row = auto_row
			col_span = 1
			row_span = 1
			auto_col += 1
			if auto_col >= num_cols {
				auto_col = 0
				auto_row += 1
			}
		}

		// Clamp to grid bounds
		col = clamp(col, 0, num_cols - 1)
		row = clamp(row, 0, num_rows - 1)
		end_col := min(col + col_span, num_cols) - 1
		end_row := min(row + row_span, num_rows) - 1

		// Compute cell rect (spanning multiple cells includes gaps)
		x := col_pos[col]
		y := row_pos[row]
		w := (col_pos[end_col] + col_sizes[end_col]) - col_pos[col]
		h := (row_pos[end_row] + row_sizes[end_row]) - row_pos[row]

		child.computed_rect = Rect{
			x + child.margin[3],
			y + child.margin[0],
			max(0, w - child.margin[1] - child.margin[3]),
			max(0, h - child.margin[0] - child.margin[2]),
		}

		clamp_box_size(child)

		child.content_rect = rect_shrink(
			child.computed_rect,
			child.padding[0], child.padding[1],
			child.padding[2], child.padding[3],
		)

		child_idx = child.next_sibling
	}
}

// --- Grid Helpers ---

// Infer number of rows from child count and column count
infer_grid_rows :: proc(mgr: ^Manager, box_idx: int, num_cols: int) -> int {
	b := &mgr.boxes[box_idx]
	max_row := 0

	child_idx := b.first_child
	auto_col := 0
	auto_row := 0

	for child_idx != -1 {
		child := &mgr.boxes[child_idx]

		if child.grid_col_span == 0 && child.grid_row_span == 0 {
			// Auto-placed child
			row := auto_row
			max_row = max(max_row, row)
			auto_col += 1
			if auto_col >= num_cols {
				auto_col = 0
				auto_row += 1
			}
		} else {
			row_end := child.grid_row + max(1, child.grid_row_span) - 1
			max_row = max(max_row, row_end)
		}

		child_idx = child.next_sibling
	}

	return max_row + 1
}

// Resolve track sizes (column widths or row heights) from specs
resolve_track_sizes :: proc(specs: []Size_Spec, available: f32, gap: f32, out: []f32) {
	n := len(specs)
	if n == 0 {
		return
	}

	total_gap := gap * f32(max(0, n - 1))
	usable := max(0, available - total_gap)

	total_fixed: f32 = 0
	total_grow:  f32 = 0

	for i in 0..<n {
		switch specs[i].kind {
		case .Fixed:
			out[i] = specs[i].value
			total_fixed += specs[i].value
		case .Percent:
			out[i] = usable * specs[i].value
			total_fixed += out[i]
		case .Grow:
			total_grow += specs[i].value
		case .Fit, .Auto:
			// For grid tracks, treat as grow(1)
			total_grow += 1
		}
	}

	remaining := max(0, usable - total_fixed)

	if total_grow > 0 {
		for i in 0..<n {
			weight: f32
			switch specs[i].kind {
			case .Grow:
				weight = specs[i].value
			case .Fit, .Auto:
				weight = 1
			case .Fixed, .Percent:
				continue
			}
			out[i] = remaining * (weight / total_grow)
		}
	}
}

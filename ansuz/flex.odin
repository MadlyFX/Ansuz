package ansuz

// --- Flex Layout Solver ---
// Resolves sizes and positions for children of a flex container.

flex_solve :: proc(mgr: ^Manager, box_idx: int) {
	b := &mgr.boxes[box_idx]
	if b.child_count == 0 {
		return
	}

	main_axis  := int(b.layout_axis)                 // 0 = Horizontal, 1 = Vertical
	cross_axis := 1 - main_axis

	// Available space = content rect (computed rect minus padding)
	avail_main  := content_size(b, main_axis)
	avail_cross := content_size(b, cross_axis)

	// First pass: measure fixed children and sum grow weights
	total_fixed:  f32 = 0
	total_grow:   f32 = 0
	child_count:  int = 0
	gap_total:    f32 = 0

	child_idx := b.first_child
	for child_idx != -1 {
		child := &mgr.boxes[child_idx]

		// Resolve main-axis size for non-grow children
		resolved := resolve_size_spec(child.size[main_axis], avail_main)
		if child.size[main_axis].kind == .Grow {
			total_grow += child.size[main_axis].value
		} else {
			total_fixed += resolved
		}

		// Resolve cross-axis size
		if child.size[cross_axis].kind != .Grow {
			child_cross := resolve_size_spec(child.size[cross_axis], avail_cross)
			set_rect_dim(&child.computed_rect, cross_axis, child_cross)
		}

		child_count += 1
		child_idx = child.next_sibling
	}

	// Account for gaps between children
	if child_count > 1 {
		gap_total = b.gap * f32(child_count - 1)
	}

	remaining := max(0, avail_main - total_fixed - gap_total)

	// Second pass: resolve grow children and assign main-axis sizes
	child_idx = b.first_child
	for child_idx != -1 {
		child := &mgr.boxes[child_idx]

		if child.size[main_axis].kind == .Grow {
			weight := child.size[main_axis].value
			if total_grow > 0 {
				child_main := remaining * (weight / total_grow)
				set_rect_dim(&child.computed_rect, main_axis, child_main)
			}
		} else {
			resolved := resolve_size_spec(child.size[main_axis], avail_main)
			set_rect_dim(&child.computed_rect, main_axis, resolved)
		}

		// Handle cross-axis Grow / Stretch
		if child.size[cross_axis].kind == .Grow || b.align == .Stretch {
			set_rect_dim(&child.computed_rect, cross_axis, avail_cross)
		}

		// Clamp to min/max
		clamp_box_size(child)

		child_idx = child.next_sibling
	}

	// Third pass: position children along the main axis using justify
	content_origin_main  := content_origin(b, main_axis)
	content_origin_cross := content_origin(b, cross_axis)

	// Calculate total children size for justify
	total_children_main: f32 = 0
	child_idx = b.first_child
	for child_idx != -1 {
		child := &mgr.boxes[child_idx]
		total_children_main += get_rect_dim(child.computed_rect, main_axis)
		child_idx = child.next_sibling
	}
	total_children_main += gap_total

	// Justify: compute starting offset and inter-child spacing
	start_offset: f32 = 0
	extra_gap:    f32 = 0

	switch b.justify {
	case .Start:
		start_offset = 0
	case .Center:
		start_offset = (avail_main - total_children_main) / 2
	case .End:
		start_offset = avail_main - total_children_main
	case .Space_Between:
		if child_count > 1 {
			space := avail_main - (total_children_main - gap_total)
			extra_gap = space / f32(child_count - 1) - b.gap
		}
	case .Space_Around:
		if child_count > 0 {
			space := avail_main - (total_children_main - gap_total)
			per := space / f32(child_count)
			start_offset = per / 2
			extra_gap = per - b.gap
		}
	case .Space_Evenly:
		if child_count > 0 {
			space := avail_main - (total_children_main - gap_total)
			per := space / f32(child_count + 1)
			start_offset = per
			extra_gap = per - b.gap
		}
	}

	cursor := content_origin_main + start_offset

	child_idx = b.first_child
	first := true
	for child_idx != -1 {
		child := &mgr.boxes[child_idx]

		if !first {
			cursor += b.gap + extra_gap
		}

		// Position along main axis
		set_rect_pos(&child.computed_rect, main_axis, cursor)
		cursor += get_rect_dim(child.computed_rect, main_axis)

		// Position along cross axis (alignment)
		child_cross_size := get_rect_dim(child.computed_rect, cross_axis)
		switch b.align {
		case .Start, .Stretch:
			set_rect_pos(&child.computed_rect, cross_axis, content_origin_cross)
		case .Center:
			set_rect_pos(&child.computed_rect, cross_axis, content_origin_cross + (avail_cross - child_cross_size) / 2)
		case .End:
			set_rect_pos(&child.computed_rect, cross_axis, content_origin_cross + avail_cross - child_cross_size)
		}

		// Apply margin offsets
		child.computed_rect.x += child.margin[3] // left
		child.computed_rect.y += child.margin[0] // top

		// Compute content rect (inner rect after padding)
		child.content_rect = rect_shrink(
			child.computed_rect,
			child.padding[0], child.padding[1],
			child.padding[2], child.padding[3],
		)

		first = false
		child_idx = child.next_sibling
	}
}

// --- Helper procs ---

resolve_size_spec :: proc(spec: Size_Spec, available: f32) -> f32 {
	switch spec.kind {
	case .Fixed:
		return spec.value
	case .Percent:
		return available * spec.value
	case .Fit, .Auto:
		return 0 // Will be determined later or by content
	case .Grow:
		return 0 // Resolved in the grow pass
	}
	return 0
}

content_size :: proc(b: ^Box, axis: int) -> f32 {
	if axis == 0 {
		return max(0, b.computed_rect.w - b.padding[1] - b.padding[3])
	} else {
		return max(0, b.computed_rect.h - b.padding[0] - b.padding[2])
	}
}

content_origin :: proc(b: ^Box, axis: int) -> f32 {
	if axis == 0 {
		return b.computed_rect.x + b.padding[3]
	} else {
		return b.computed_rect.y + b.padding[0]
	}
}

get_rect_dim :: proc(r: Rect, axis: int) -> f32 {
	return r.w if axis == 0 else r.h
}

set_rect_dim :: proc(r: ^Rect, axis: int, val: f32) {
	if axis == 0 {
		r.w = val
	} else {
		r.h = val
	}
}

get_rect_pos :: proc(r: Rect, axis: int) -> f32 {
	return r.x if axis == 0 else r.y
}

set_rect_pos :: proc(r: ^Rect, axis: int, val: f32) {
	if axis == 0 {
		r.x = val
	} else {
		r.y = val
	}
}

clamp_box_size :: proc(b: ^Box) {
	if b.min_size[0] > 0 {
		b.computed_rect.w = max(b.computed_rect.w, b.min_size[0])
	}
	if b.min_size[1] > 0 {
		b.computed_rect.h = max(b.computed_rect.h, b.min_size[1])
	}
	if b.max_size[0] > 0 {
		b.computed_rect.w = min(b.computed_rect.w, b.max_size[0])
	}
	if b.max_size[1] > 0 {
		b.computed_rect.h = min(b.computed_rect.h, b.max_size[1])
	}
}

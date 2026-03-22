package ogui

// --- Layout Resolution ---
// The solver runs in two phases:
//   1. Bottom-up: compute natural sizes for Fit-sized boxes (leaf to root)
//   2. Top-down: resolve positions and distribute Grow space (root to leaf)

resolve_layout :: proc(mgr: ^Manager) {
	if len(mgr.boxes) == 0 {
		return
	}

	// Root box gets the full window rect
	root := &mgr.boxes[0]
	root.computed_rect = Rect{0, 0, root.size[0].value, root.size[1].value}
	root.content_rect = rect_shrink(
		root.computed_rect,
		root.padding[0], root.padding[1],
		root.padding[2], root.padding[3],
	)

	// Phase 1: Bottom-up — compute natural sizes for Fit-sized boxes
	compute_natural_sizes(mgr, 0)

	// Phase 2: Top-down — resolve positions and distribute grow space
	resolve_children(mgr, 0)

	// Phase 3: Apply scroll offsets — measure content, clamp offset, shift descendants
	apply_scroll_offsets(mgr, 0)
}

// --- Phase 1: Bottom-up natural size computation ---
// Traverses children before parents. For each Fit-sized axis,
// computes the natural size from children's sizes.

compute_natural_sizes :: proc(mgr: ^Manager, box_idx: int) {
	b := &mgr.boxes[box_idx]

	// Recurse into children first (bottom-up)
	child_idx := b.first_child
	for child_idx != -1 {
		compute_natural_sizes(mgr, child_idx)
		child_idx = mgr.boxes[child_idx].next_sibling
	}

	// If this box doesn't have Fit on either axis, nothing to do
	if b.size[0].kind != .Fit && b.size[1].kind != .Fit {
		return
	}

	if b.child_count == 0 {
		// Leaf with Fit size — stays at 0 (or whatever was set by the widget)
		return
	}

	// Compute natural size based on layout kind
	switch b.layout_kind {
	case .Flex:
		compute_flex_natural_size(mgr, box_idx)
	case .Grid, .Stack:
		compute_stack_natural_size(mgr, box_idx)
	}
}

compute_flex_natural_size :: proc(mgr: ^Manager, box_idx: int) {
	b := &mgr.boxes[box_idx]
	main_axis  := int(b.layout_axis)
	cross_axis := 1 - main_axis

	main_total: f32 = 0
	cross_max:  f32 = 0
	count := 0

	child_idx := b.first_child
	for child_idx != -1 {
		child := &mgr.boxes[child_idx]

		// Get the child's size on each axis
		child_main  := get_child_natural_size(child, main_axis)
		child_cross := get_child_natural_size(child, cross_axis)

		main_total += child_main
		cross_max = max(cross_max, child_cross)
		count += 1

		child_idx = child.next_sibling
	}

	// Add gaps
	if count > 1 {
		main_total += b.gap * f32(count - 1)
	}

	// Add padding
	main_total += b.padding[main_axis_start(main_axis)] + b.padding[main_axis_end(main_axis)]
	cross_max  += b.padding[main_axis_start(cross_axis)] + b.padding[main_axis_end(cross_axis)]

	// Only override Fit axes
	if b.size[main_axis].kind == .Fit {
		b.size[main_axis] = size_fixed(main_total)
	}
	if b.size[cross_axis].kind == .Fit {
		b.size[cross_axis] = size_fixed(cross_max)
	}
}

compute_stack_natural_size :: proc(mgr: ^Manager, box_idx: int) {
	b := &mgr.boxes[box_idx]

	max_w: f32 = 0
	max_h: f32 = 0

	child_idx := b.first_child
	for child_idx != -1 {
		child := &mgr.boxes[child_idx]
		max_w = max(max_w, get_child_natural_size(child, 0))
		max_h = max(max_h, get_child_natural_size(child, 1))
		child_idx = child.next_sibling
	}

	if b.size[0].kind == .Fit {
		b.size[0] = size_fixed(max_w + b.padding[1] + b.padding[3])
	}
	if b.size[1].kind == .Fit {
		b.size[1] = size_fixed(max_h + b.padding[0] + b.padding[2])
	}
}

// Get a child's natural size on an axis. For Fixed/Fit (already resolved), returns the value.
// For Grow/Percent, returns 0 (they need parent context to resolve).
get_child_natural_size :: proc(child: ^Box, axis: int) -> f32 {
	spec := child.size[axis]
	switch spec.kind {
	case .Fixed:
		return spec.value
	case .Fit:
		// Fit should already be resolved to Fixed by bottom-up pass
		return spec.value
	case .Grow, .Percent, .Auto:
		return 0
	}
	return 0
}

// Padding index helpers: top=0, right=1, bottom=2, left=3
// For axis 0 (horizontal): start=left(3), end=right(1)
// For axis 1 (vertical): start=top(0), end=bottom(2)
main_axis_start :: proc(axis: int) -> int {
	return 3 if axis == 0 else 0  // left or top
}

main_axis_end :: proc(axis: int) -> int {
	return 1 if axis == 0 else 2  // right or bottom
}

// --- Phase 2: Top-down position resolution ---

resolve_children :: proc(mgr: ^Manager, box_idx: int) {
	b := &mgr.boxes[box_idx]

	if b.child_count == 0 {
		return
	}

	switch b.layout_kind {
	case .Flex:
		flex_solve(mgr, box_idx)
	case .Grid:
		grid_solve(mgr, box_idx)
	case .Stack:
		stack_solve(mgr, box_idx)
	}

	// Recurse into children
	child_idx := b.first_child
	for child_idx != -1 {
		resolve_children(mgr, child_idx)
		child_idx = mgr.boxes[child_idx].next_sibling
	}
}

// Stack layout: all children positioned at parent's content origin.
stack_solve :: proc(mgr: ^Manager, box_idx: int) {
	b := &mgr.boxes[box_idx]
	avail_w := content_size(b, 0)
	avail_h := content_size(b, 1)
	origin_x := content_origin(b, 0)
	origin_y := content_origin(b, 1)

	child_idx := b.first_child
	for child_idx != -1 {
		child := &mgr.boxes[child_idx]

		w := resolve_size_spec(child.size[0], avail_w)
		h := resolve_size_spec(child.size[1], avail_h)
		if child.size[0].kind == .Grow { w = avail_w }
		if child.size[1].kind == .Grow { h = avail_h }

		child.computed_rect = Rect{
			origin_x + child.margin[3],
			origin_y + child.margin[0],
			w, h,
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

// --- Phase 3: Scroll offset application ---
// After layout is fully resolved, find boxes with scroll offsets
// and shift all their descendants. Also update scroll state measurements.

apply_scroll_offsets :: proc(mgr: ^Manager, box_idx: int) {
	b := &mgr.boxes[box_idx]

	// If this box has a scroll offset, measure content and apply
	if b.scroll_offset.x != 0 || b.scroll_offset.y != 0 || .Clip_Children in b.flags {
		// Measure total content extent from children (before offsetting)
		content_bottom: f32 = 0
		child := b.first_child
		for child != -1 {
			c := &mgr.boxes[child]
			bottom := c.computed_rect.y + c.computed_rect.h - b.content_rect.y
			content_bottom = max(content_bottom, bottom)
			child = c.next_sibling
		}

		// Update scroll state if this box has one
		if ss, ok := &mgr.scroll_states[b.id]; ok {
			ss.content_h = content_bottom
			ss.viewport_h = b.content_rect.h

			// Re-clamp offset in case content size changed
			max_scroll := max(0, ss.content_h - ss.viewport_h)
			ss.offset_y = clamp(ss.offset_y, 0, max_scroll)

			// Update the box's scroll offset from the clamped value
			b.scroll_offset = {0, -ss.offset_y}
		}

		// Offset all descendant rects
		if b.scroll_offset.x != 0 || b.scroll_offset.y != 0 {
			offset_descendants(mgr, box_idx, b.scroll_offset)
		}
	}

	// Recurse into children
	child := b.first_child
	for child != -1 {
		apply_scroll_offsets(mgr, child)
		child = mgr.boxes[child].next_sibling
	}
}

offset_descendants :: proc(mgr: ^Manager, parent_idx: int, offset: Vec2) {
	child := mgr.boxes[parent_idx].first_child
	for child != -1 {
		c := &mgr.boxes[child]
		c.computed_rect.x += offset.x
		c.computed_rect.y += offset.y
		c.content_rect.x += offset.x
		c.content_rect.y += offset.y
		// Recurse to grandchildren
		offset_descendants(mgr, child, offset)
		child = c.next_sibling
	}
}

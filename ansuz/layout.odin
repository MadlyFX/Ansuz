package ansuz

// --- Layout Public API ---
// Immediate-mode layout calls. The user calls begin/end pairs to build the box tree.

// Begin a flex container. Children are laid out along `axis`.
flex_begin :: proc(
	mgr:      ^Manager,
	axis:     Axis       = .Horizontal,
	justify:  Justify    = .Start,
	align:    Align      = .Stretch,
	gap:      f32        = 0,
	size:     [2]Size_Spec = GROW_GROW,
	padding:  [4]f32     = {},
	margin:   [4]f32     = {},
	bg_color: Color      = COLOR_TRANSPARENT,
	floating: bool       = false,
	loc       := #caller_location,
) {
	id := id_from_loc(&mgr.id_stack, loc)
	idx := push_box(mgr, id)
	b := &mgr.boxes[idx]
	b.layout_kind = .Flex
	b.layout_axis = axis
	b.justify     = justify
	b.align       = align
	b.gap         = gap
	b.size        = size
	b.padding     = padding
	b.margin      = margin
	b.bg_color    = bg_color
	if floating {
		b.flags += {.Is_Floating}
	}
}

// End a flex container.
flex_end :: proc(mgr: ^Manager) {
	pop_box(mgr)
}

stack_begin :: proc(
	mgr:      ^Manager,
	size:     [2]Size_Spec = GROW_GROW,
	padding:  [4]f32       = {},
	margin:   [4]f32       = {},
	bg_color: Color        = COLOR_TRANSPARENT,
	floating: bool         = false,
	loc       := #caller_location,
) {
	id := id_from_loc(&mgr.id_stack, loc)
	idx := push_box(mgr, id)
	b := &mgr.boxes[idx]
	b.layout_kind = .Stack
	b.size        = size
	b.padding     = padding
	b.margin      = margin
	b.bg_color    = bg_color
	if floating {
		b.flags += {.Is_Floating}
	}
}

stack_end :: proc(mgr: ^Manager) {
	pop_box(mgr)
}

// Begin a grid container.
grid_begin :: proc(
	mgr:      ^Manager,
	cols:     []Size_Spec,
	rows:     []Size_Spec = {},
	gap:      f32         = 0,
	size:     [2]Size_Spec = GROW_GROW,
	padding:  [4]f32      = {},
	bg_color: Color       = COLOR_TRANSPARENT,
	loc       := #caller_location,
) {
	id := id_from_loc(&mgr.id_stack, loc)
	idx := push_box(mgr, id)
	b := &mgr.boxes[idx]
	b.layout_kind = .Grid
	b.layout_axis = .Horizontal
	b.gap         = gap
	b.size        = size
	b.padding     = padding
	b.bg_color    = bg_color
	// The layout solver runs at frame_end, after the caller may have returned.
	// Retain the track specs in the frame arena so slices backed by caller-local
	// arrays cannot dangle.
	b.grid_cols   = copy_specs_to_frame(mgr, cols)
	b.grid_rows   = copy_specs_to_frame(mgr, rows)
}

@(private)
copy_specs_to_frame :: proc(mgr: ^Manager, specs: []Size_Spec) -> []Size_Spec {
	if len(specs) == 0 {
		return nil
	}
	retained := make([]Size_Spec, len(specs), mgr.frame_allocator)
	copy(retained, specs)
	return retained
}

// End a grid container.
grid_end :: proc(mgr: ^Manager) {
	pop_box(mgr)
}

// Declare a leaf box (no children).
// Returns a pointer to the box so the caller can read computed_rect after layout.
box :: proc(
	mgr:      ^Manager,
	size:     [2]Size_Spec = GROW_GROW,
	bg_color: Color        = COLOR_TRANSPARENT,
	margin:   [4]f32       = {},
	floating: bool         = false,
	loc       := #caller_location,
) -> int {
	id := id_from_loc(&mgr.id_stack, loc)
	idx := push_box(mgr, id)
	b := &mgr.boxes[idx]
	b.size     = size
	b.bg_color = bg_color
	b.margin   = margin
	if floating {
		b.flags += {.Is_Floating}
	}
	// Leaf box: immediately pop (no children)
	pop_box(mgr)
	return idx
}

// Declare a leaf box positioned in a specific grid cell.
grid_cell :: proc(
	mgr:      ^Manager,
	col:      int,
	row:      int,
	col_span: int     = 1,
	row_span: int     = 1,
	bg_color: Color   = COLOR_TRANSPARENT,
	margin:   [4]f32  = {},
	loc       := #caller_location,
) -> int {
	id := id_from_loc(&mgr.id_stack, loc)
	idx := push_box(mgr, id)
	b := &mgr.boxes[idx]
	b.size          = GROW_GROW
	b.bg_color      = bg_color
	b.margin        = margin
	b.grid_col      = col
	b.grid_row      = row
	b.grid_col_span = col_span
	b.grid_row_span = row_span
	pop_box(mgr)
	return idx
}

// --- Internal: Box Tree Management ---

// Allocate a new box, link it as a child of the current parent, and push it onto the box stack.
push_box :: proc(mgr: ^Manager, id: Widget_ID) -> int {
	idx := len(mgr.boxes)

	new_box := Box{
		id           = id,
		parent_index = -1,
		first_child  = -1,
		next_sibling = -1,
	}

	// Link to parent
	if len(mgr.box_stack) > 0 {
		parent_idx := mgr.box_stack[len(mgr.box_stack) - 1]
		parent := &mgr.boxes[parent_idx]
		new_box.parent_index = parent_idx

		if parent.first_child == -1 {
			parent.first_child = idx
		} else {
			// Walk to the last sibling
			sib := parent.first_child
			for mgr.boxes[sib].next_sibling != -1 {
				sib = mgr.boxes[sib].next_sibling
			}
			mgr.boxes[sib].next_sibling = idx
		}
		parent.child_count += 1
	}

	append(&mgr.boxes, new_box)
	// Push this box as the new parent for subsequent children
	append(&mgr.box_stack, idx)

	return idx
}

// Pop the current parent from the box stack.
pop_box :: proc(mgr: ^Manager) {
	assert(len(mgr.box_stack) > 0, "pop_box: box stack underflow")
	pop(&mgr.box_stack)
}

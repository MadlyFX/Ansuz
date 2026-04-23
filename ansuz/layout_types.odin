package ansuz

// --- Layout Enums ---

Axis :: enum {
	Horizontal,
	Vertical,
}

Size_Kind :: enum {
	Fixed,    // Exact pixel value
	Percent,  // Fraction of parent (0.0–1.0)
	Grow,     // Fill remaining space, weighted
	Fit,      // Shrink to fit children
	Auto,     // Determined by content (e.g. text measurement)
}

Size_Spec :: struct {
	kind:  Size_Kind,
	value: f32,
}

Justify :: enum {
	Start,
	Center,
	End,
	Space_Between,
	Space_Around,
	Space_Evenly,
}

Align :: enum {
	Start,
	Center,
	End,
	Stretch,
}

Layout_Kind :: enum {
	Flex,
	Grid,
	Stack,  // absolute positioning within parent
}

Box_Flag :: enum {
	Draw_Background,
	Draw_Border,
	Clip_Children,
	Is_Floating,
}

Box_Flags :: bit_set[Box_Flag]

// --- The Box ---
// Every widget and every container is a Box.
// Boxes form a tree via index-based links into the Manager.boxes array.

Box :: struct {
	// Tree links (indices into Manager.boxes, -1 = none)
	id:             Widget_ID,
	parent_index:   int,
	first_child:    int,
	next_sibling:   int,
	child_count:    int,

	// Desired size
	size:           [2]Size_Spec,    // [horizontal, vertical]
	min_size:       [2]f32,
	max_size:       [2]f32,          // 0 means unbounded

	// Container layout properties
	layout_kind:    Layout_Kind,
	layout_axis:    Axis,
	justify:        Justify,
	align:          Align,
	gap:            f32,
	wrap:           bool,

	// Grid-specific
	grid_cols:      []Size_Spec,
	grid_rows:      []Size_Spec,
	grid_col:       int,
	grid_row:       int,
	grid_col_span:  int,
	grid_row_span:  int,

	// Spacing
	padding:        [4]f32,  // top, right, bottom, left
	margin:         [4]f32,

	// Visual
	bg_color:       Color,
	border_color:   Color,
	border_width:   f32,
	corner_radius:  f32,

	// Output (filled by layout solver)
	computed_rect:  Rect,
	content_rect:   Rect,

	// Scroll offset applied to children after layout (set by scroll_begin)
	scroll_offset:  Vec2,

	// Effective clip region from ancestor chain (set during draw emission).
	// is_clipped is true only when an ancestor has Clip_Children, to avoid
	// unnecessary clip state changes for unclipped boxes.
	effective_clip: Rect,
	is_clipped:     bool,

	flags:          Box_Flags,
}

// --- Size_Spec Constructors ---

size_fixed :: proc(px: f32) -> Size_Spec {
	return Size_Spec{.Fixed, px}
}

size_grow :: proc(weight: f32 = 1.0) -> Size_Spec {
	return Size_Spec{.Grow, weight}
}

size_pct :: proc(p: f32) -> Size_Spec {
	return Size_Spec{.Percent, p}
}

size_fit :: proc() -> Size_Spec {
	return Size_Spec{.Fit, 0}
}

size_auto :: proc() -> Size_Spec {
	return Size_Spec{.Auto, 0}
}

// Constants for use as default parameters (procs can't be used as defaults)
SIZE_GROW :: Size_Spec{.Grow, 1.0}
SIZE_FIT  :: Size_Spec{.Fit, 0}
SIZE_AUTO :: Size_Spec{.Auto, 0}
GROW_GROW    :: [2]Size_Spec{SIZE_GROW, SIZE_GROW}
SIZE_FIT_FIT :: [2]Size_Spec{SIZE_FIT, SIZE_FIT}
GROW_FIXED_30 :: [2]Size_Spec{SIZE_GROW, {.Fixed, 30}}
FIXED_200_30  :: [2]Size_Spec{{.Fixed, 200}, {.Fixed, 30}}
FIXED_200_FIT :: [2]Size_Spec{{.Fixed, 200}, SIZE_FIT}

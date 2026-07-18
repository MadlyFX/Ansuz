package ansuz

// --- Tree Widget ---
// Explorer-style tree: expandable nodes with disclosure icons, leaf rows with
// optional document icons, and indent guide lines connecting each level.
//
// Rows are flat, compact, and left aligned (the standard button intentionally
// centers its label). Expansion binds through an `expanded` pointer like
// collapsible_header; selection stays in application data and rows report
// clicks through the returned Interaction.
//
// Usage:
//     tree_begin(mgr)
//     open, node := tree_node_begin(mgr, "Notebook", &state.expanded)
//     if .Clicked in node { /* select the notebook */ }
//     if open {
//         if .Clicked in tree_leaf(mgr, "Page 1", icon = .Document) { ... }
//         if .Clicked in tree_leaf(mgr, "Page 2", icon = .Document, is_last = true) { ... }
//     }
//     tree_node_end(mgr)
//     tree_end(mgr)
//
// Rows built in a loop need unique IDs: push a per-item scope first with
// id_stack_push(&mgr.id_stack, id_from_int(&mgr.id_stack, item_id)).

TREE_ROW_HEIGHT      :: f32(30)
TREE_INDENT          :: f32(24) // width of one nesting level (and the disclosure column)
TREE_GUIDE_INSET     :: f32(10) // guide line x position within an indent column
TREE_GUIDE_TICK      :: f32(7)  // length of the horizontal tick reaching each row
TREE_DOC_ICON_WIDTH  :: f32(9)
TREE_DOC_ICON_HEIGHT :: f32(11)
TREE_MAX_DEPTH       :: 16

THEME_TREE_ROW_HOVER    :: Color{60, 63, 70, 255}
THEME_TREE_ROW_PRESS    :: Color{45, 48, 55, 255}
THEME_TREE_ROW_SELECTED :: Color{55, 80, 120, 255}
THEME_TREE_GUIDE        :: Color{80, 83, 90, 255}

TREE_ROW_SIZE :: [2]Size_Spec{SIZE_GROW, Size_Spec{.Fixed, TREE_ROW_HEIGHT}}

// Rows sit directly on the surrounding container, so the resting background is
// transparent. The focus slot doubles as the selected-row background.
THEME_TREE_ROW_COLOR :: Widget_Color{
	bg    = COLOR_TRANSPARENT,
	fg    = COLOR_TRANSPARENT,
	hover = THEME_TREE_ROW_HOVER,
	press = THEME_TREE_ROW_PRESS,
	focus = THEME_TREE_ROW_SELECTED,
}

Tree_Icon :: enum {
	None,
	Document,
}

// Begin a tree: a vertical flex container that sizes to its content. Also
// resets nesting depth so an unbalanced tree from a previous frame cannot
// leak guide state into this one.
tree_begin :: proc(
	mgr:      ^Manager,
	gap:      f32          = 2,
	size:     [2]Size_Spec = {SIZE_GROW, SIZE_FIT},
	padding:  [4]f32       = {},
	bg_color: Color        = COLOR_TRANSPARENT,
	loc       := #caller_location,
) {
	mgr.tree_depth = 0
	flex_begin(
		mgr,
		axis = .Vertical,
		gap = gap,
		size = size,
		padding = padding,
		bg_color = bg_color,
		loc = loc,
	)
}

tree_end :: proc(mgr: ^Manager) {
	assert(mgr.tree_depth == 0, "tree_end: unbalanced tree_node_begin/tree_node_end")
	flex_end(mgr)
}

// Expandable tree node. Draws a disclosure icon and a left-aligned row at the
// current nesting depth, then opens a child nesting scope. Always pair with
// tree_node_end, emitting children only when `open` returns true:
//
//     open, node := tree_node_begin(mgr, "Node", &expanded)
//     if open { ...children... }
//     tree_node_end(mgr)
//
// Clicking the disclosure icon toggles `expanded` (the whole row toggles when
// toggle_on_row is true). Row clicks are reported through the returned
// Interaction so the application can track selection. Pass is_last when the
// node is the final row of its level so the guide line ends at its connector.
tree_node_begin :: proc(
	mgr:      ^Manager,
	text:     string,
	expanded: ^bool,
	selected:      bool = false,
	is_last:       bool = false,
	toggle_on_row: bool = false,
	row_height: f32 = TREE_ROW_HEIGHT,
	color: Widget_Color = THEME_TREE_ROW_COLOR,
	text_color:          Color = THEME_TEXT,
	selected_text_color: Color = THEME_TEXT,
	icon_color:          Color = THEME_TEXT_DIM,
	expanded_icon_color: Color = THEME_TEXT,
	guide_color:         Color = THEME_TREE_GUIDE,
	font:  Font_Handle = FONT_DEFAULT,
	scale: f32 = DEFAULT_FONT_SCALE,
	loc   := #caller_location,
) -> (open: bool, interaction: Interaction) {
	assert(mgr.tree_depth < TREE_MAX_DEPTH, "tree_node_begin: nested deeper than TREE_MAX_DEPTH")

	id := id_from_ptr_loc(&mgr.id_stack, expanded, loc)
	icon_id := Widget_ID(hash_string("tree-disclosure", u64(id)))
	row_id := Widget_ID(hash_string("tree-row", u64(id)))

	// The disclosure icon and the label row are separate hit targets: the icon
	// always toggles expansion, the row reports clicks for selection.
	icon_prev_rect := Rect{}
	if state, ok := mgr.widget_states[icon_id]; ok {
		icon_prev_rect = state.prev_rect
	}
	icon_interaction := compute_interaction(mgr, icon_id, icon_prev_rect)

	row_prev_rect := Rect{}
	if state, ok := mgr.widget_states[row_id]; ok {
		row_prev_rect = state.prev_rect
	}
	interaction = compute_interaction(mgr, row_id, row_prev_rect)

	if .Clicked in icon_interaction || (toggle_on_row && .Clicked in interaction) {
		expanded^ = !expanded^
	}

	flex_begin(
		mgr,
		axis = .Horizontal,
		align = .Center,
		size = {SIZE_GROW, size_fixed(row_height)},
		loc = loc,
	)
	tree_emit_guides(mgr, row_height, is_last, guide_color)

	icon_idx := disclosure_icon_box(
		mgr,
		icon_id,
		expanded^,
		color = expanded_icon_color if expanded^ else icon_color,
		size = {size_fixed(TREE_INDENT), size_fixed(row_height)},
		scale = max(1, scale / DEFAULT_FONT_SCALE),
	)
	get_or_create_widget_state(mgr, icon_id)
	append(&mgr.widget_box_map, Widget_Box_Entry{id = icon_id, box_index = icon_idx})

	tree_row_box(
		mgr,
		row_id,
		text,
		selected,
		interaction,
		size = {SIZE_GROW, size_fixed(row_height - 2)},
		padding = {1, 7, 1, 5},
		color = color,
		text_color = selected_text_color if selected else text_color,
		font = font,
		scale = scale,
	)
	flex_end(mgr)

	track_value(mgr, id, expanded)

	open = expanded^
	mgr.tree_continues[mgr.tree_depth] = !is_last
	mgr.tree_depth += 1
	return
}

tree_node_end :: proc(mgr: ^Manager) {
	assert(mgr.tree_depth > 0, "tree_node_end: no matching tree_node_begin")
	mgr.tree_depth -= 1
}

// A leaf row at the current nesting depth: guide connector, optional icon,
// and a flat left-aligned row. Pass is_last on the final row of its level.
tree_leaf :: proc(
	mgr:  ^Manager,
	text: string,
	selected: bool = false,
	is_last:  bool = false,
	icon: Tree_Icon = .None,
	row_height: f32 = TREE_ROW_HEIGHT,
	color: Widget_Color = THEME_TREE_ROW_COLOR,
	text_color:          Color = THEME_TEXT,
	selected_text_color: Color = THEME_TEXT,
	icon_color:          Color = THEME_TEXT_DIM,
	guide_color:         Color = THEME_TREE_GUIDE,
	font:  Font_Handle = FONT_DEFAULT,
	scale: f32 = DEFAULT_FONT_SCALE,
	loc   := #caller_location,
) -> Interaction {
	id := id_from_loc(&mgr.id_stack, loc)

	prev_rect := Rect{}
	if state, ok := mgr.widget_states[id]; ok {
		prev_rect = state.prev_rect
	}
	interaction := compute_interaction(mgr, id, prev_rect)

	flex_begin(
		mgr,
		axis = .Horizontal,
		align = .Center,
		size = {SIZE_GROW, size_fixed(row_height)},
		loc = loc,
	)
	tree_emit_guides(mgr, row_height, is_last, guide_color)

	if icon == .Document {
		doc_idx := box(mgr, size = {size_fixed(TREE_DOC_ICON_WIDTH), size_fixed(TREE_DOC_ICON_HEIGHT)})
		mgr.boxes[doc_idx].border_width = 1
		mgr.boxes[doc_idx].border_color = icon_color
		mgr.boxes[doc_idx].corner_radius = 1
		box(mgr, size = {size_fixed(5), size_fixed(1)})
	}

	tree_row_box(
		mgr,
		id,
		text,
		selected,
		interaction,
		size = {SIZE_GROW, size_fixed(row_height - 2)},
		padding = {1, 7, 1, 7},
		color = color,
		text_color = selected_text_color if selected else text_color,
		font = font,
		scale = scale,
	)
	flex_end(mgr)

	return interaction
}

// A flat, compact, left-aligned row. The tree building block, usable on its
// own anywhere an explorer-style row is wanted.
tree_row :: proc(
	mgr:  ^Manager,
	text: string,
	selected: bool = false,
	size:    [2]Size_Spec = TREE_ROW_SIZE,
	padding: [4]f32 = {2, 7, 2, 7},
	color: Widget_Color = THEME_TREE_ROW_COLOR,
	text_color: Color = THEME_TEXT,
	font:  Font_Handle = FONT_DEFAULT,
	scale: f32 = DEFAULT_FONT_SCALE,
	loc   := #caller_location,
) -> Interaction {
	id := id_from_loc(&mgr.id_stack, loc)

	prev_rect := Rect{}
	if state, ok := mgr.widget_states[id]; ok {
		prev_rect = state.prev_rect
	}
	interaction := compute_interaction(mgr, id, prev_rect)

	tree_row_box(mgr, id, text, selected, interaction, size, padding, color, text_color, font, scale)
	return interaction
}

// Emit the row box for a precomputed id/interaction pair. Split from tree_row
// so composite widgets (tree_node_begin, tree_leaf) can derive their own IDs.
tree_row_box :: proc(
	mgr:  ^Manager,
	id:   Widget_ID,
	text: string,
	selected:    bool,
	interaction: Interaction,
	size:    [2]Size_Spec,
	padding: [4]f32,
	color: Widget_Color,
	text_color: Color,
	font:  Font_Handle,
	scale: f32,
) -> int {
	effective_font := resolve_font(mgr, font)

	hover_t := get_hover_t(mgr, id, .Hovered in interaction)
	press_t := get_press_t(mgr, id, .Pressed in interaction)
	focus_t := get_focus_t(mgr, id, .Focused in interaction)
	base_bg := color.focus if selected else color.bg
	bg := blend_interaction_color(base_bg, color.hover, color.press, color.focus, hover_t, press_t, focus_t)

	idx := push_box(mgr, id)
	b := &mgr.boxes[idx]
	b.size = size
	b.padding = padding
	b.bg_color = bg
	b.corner_radius = 2
	pop_box(mgr)

	append(
		&mgr.deferred_texts,
		Deferred_Text{
			box_index = idx,
			text = text,
			color = text_color,
			scale = scale,
			font = effective_font,
			center_h = false,
			center_v = true,
			clip = true,
		},
	)

	get_or_create_widget_state(mgr, id)
	append(&mgr.widget_box_map, Widget_Box_Entry{id = id, box_index = idx})
	return idx
}

// Emit indent guide columns for a row at the current depth: continuation
// lines for ancestor levels, then the connector for this row (a vertical
// line reaching the row's center with a horizontal tick into it; the line
// stops at the tick when the row is the last of its level).
tree_emit_guides :: proc(mgr: ^Manager, row_height: f32, is_last: bool, guide_color: Color) {
	if mgr.tree_depth == 0 {
		return
	}

	// Ancestor column `level` carries the guide line that links the siblings at
	// depth level+1, so it continues through this row only while the ancestor
	// at that depth still has later siblings.
	for level in 0 ..< mgr.tree_depth - 1 {
		line_color := guide_color if mgr.tree_continues[level + 1] else COLOR_TRANSPARENT
		box(mgr, size = {size_fixed(TREE_GUIDE_INSET), size_fixed(1)})
		box(mgr, size = {size_fixed(1), size_fixed(row_height)}, bg_color = line_color)
		box(mgr, size = {size_fixed(TREE_INDENT - TREE_GUIDE_INSET - 1), size_fixed(1)})
	}

	tail_color := COLOR_TRANSPARENT if is_last else guide_color
	box(mgr, size = {size_fixed(TREE_GUIDE_INSET), size_fixed(1)})
	flex_begin(mgr, axis = .Vertical, size = {size_fixed(1), size_fixed(row_height)})
	box(mgr, size = {size_fixed(1), size_fixed(row_height / 2)}, bg_color = guide_color)
	box(mgr, size = {size_fixed(1), SIZE_GROW}, bg_color = tail_color)
	flex_end(mgr)
	box(mgr, size = {size_fixed(TREE_GUIDE_TICK), size_fixed(1)}, bg_color = guide_color)
	box(mgr, size = {size_fixed(TREE_INDENT - TREE_GUIDE_INSET - 1 - TREE_GUIDE_TICK), size_fixed(1)})
}

package ogui

// --- Widget Procs ---
// Button, Label, and other basic widgets for Step 2.

// --- Theme Colors ---

THEME_BG_BUTTON         :: Color{60, 63, 70, 255}
THEME_BG_BUTTON_HOVER   :: Color{75, 78, 88, 255}
THEME_BG_BUTTON_ACTIVE  :: Color{45, 48, 55, 255}
THEME_TEXT               :: Color{230, 230, 230, 255}
THEME_TEXT_DIM           :: Color{160, 160, 165, 255}
THEME_BORDER             :: Color{80, 83, 90, 255}

// Scale for the built-in bitmap font (2 = 10x14 pixel characters)
DEFAULT_FONT_SCALE :: f32(2)

// --- Deferred Text Entry ---
// Text draw commands are deferred until after layout resolve, because the
// box position isn't known when the widget proc is called.

Deferred_Text :: struct {
	box_index: int,
	text:      string,
	color:     Color,
	scale:     f32,
	center_h:  bool,   // center horizontally within box
	center_v:  bool,   // center vertically within box
	clip:      bool,   // clip text to content rect (for text inputs)
}

// --- Label ---
// Displays text. No interaction.

label :: proc(
	mgr:      ^Manager,
	text:     string,
	color:    Color      = THEME_TEXT,
	scale:    f32        = DEFAULT_FONT_SCALE,
	size:     [2]Size_Spec = SIZE_FIT_FIT,
	padding:  [4]f32     = {2, 4, 2, 4},
	loc       := #caller_location,
) -> int {
	// If size is Fit, compute from text measurement
	actual_size := size
	text_dims := measure_text_builtin(text, scale)
	if actual_size[0].kind == .Fit {
		actual_size[0] = size_fixed(text_dims.x + padding[1] + padding[3])
	}
	if actual_size[1].kind == .Fit {
		actual_size[1] = size_fixed(text_dims.y + padding[0] + padding[2])
	}

	idx := box(mgr, size = actual_size, loc = loc)
	mgr.boxes[idx].padding = padding

	// Defer text drawing until after layout
	append(&mgr.deferred_texts, Deferred_Text{
		box_index = idx,
		text      = text,
		color     = color,
		scale     = scale,
		center_h  = false,
		center_v  = true,
	})

	return idx
}

// --- Button ---
// Clickable button with text. Returns interaction flags.

button :: proc(
	mgr:       ^Manager,
	text:      string,
	scale:     f32           = DEFAULT_FONT_SCALE,
	size:      [2]Size_Spec  = SIZE_FIT_FIT,
	padding:   [4]f32        = {6, 16, 6, 16},
	loc        := #caller_location,
) -> Interaction {
	id := id_from_loc(&mgr.id_stack, loc)

	// Look up previous frame's rect for hit testing
	prev_rect := Rect{}
	if state, ok := mgr.widget_states[id]; ok {
		prev_rect = state.prev_rect
	}

	// Compute interaction
	interaction := compute_interaction(mgr, id, prev_rect)

	// Smooth color transition based on interaction state
	hover_t := get_hover_t(mgr, id, .Hovered in interaction)
	press_t := get_press_t(mgr, id, .Pressed in interaction)
	focus_t := get_focus_t(mgr, id, .Focused in interaction)
	bg := blend_interaction_color(THEME_BG_BUTTON, THEME_BG_BUTTON_HOVER, THEME_BG_BUTTON_ACTIVE, THEME_BG_BUTTON_ACTIVE, hover_t, press_t, focus_t)

	// Compute size from text if Fit
	actual_size := size
	text_dims := measure_text_builtin(text, scale)
	if actual_size[0].kind == .Fit {
		actual_size[0] = size_fixed(text_dims.x + padding[1] + padding[3])
	}
	if actual_size[1].kind == .Fit {
		actual_size[1] = size_fixed(text_dims.y + padding[0] + padding[2])
	}

	idx := box(mgr, size = actual_size, bg_color = bg, loc = loc)
	mgr.boxes[idx].padding = padding
	mgr.boxes[idx].border_width = 1
	mgr.boxes[idx].border_color = THEME_BORDER
	mgr.boxes[idx].corner_radius = max(1, 4 * (scale / DEFAULT_FONT_SCALE))

	// Defer text drawing
	append(&mgr.deferred_texts, Deferred_Text{
		box_index = idx,
		text      = text,
		color     = THEME_TEXT,
		scale     = scale,
		center_h  = true,
		center_v  = true,
	})

	// Register for prev_rect update
	get_or_create_widget_state(mgr, id)

	// Store box index so frame_end can update prev_rect
	append(&mgr.widget_box_map, Widget_Box_Entry{id = id, box_index = idx})

	return interaction
}

// --- Heading ---
// Larger text label.

heading :: proc(
	mgr:      ^Manager,
	text:     string,
	color:    Color      = THEME_TEXT,
	scale:    f32        = 3,
	size:     [2]Size_Spec = SIZE_FIT_FIT,
	padding:  [4]f32     = {4, 4, 4, 4},
	loc       := #caller_location,
) -> int {
	return label(mgr, text, color = color, scale = scale, size = size, padding = padding, loc = loc)
}

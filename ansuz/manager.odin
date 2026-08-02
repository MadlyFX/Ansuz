package ansuz

import "core:mem"

// --- Widget State ---
// Per-widget persistent state that survives across frames.

Widget_State :: struct {
	last_seen_frame: u64,
	prev_rect:       Rect,       // Rect from last frame, used for hit testing
	prev_clip:       Rect,       // Visible clip from last frame for clipped descendants
	has_prev_clip:   bool,

	// --- Value tracking ---
	// The manager snapshots bound values each frame to detect changes.
	// This enables skipping re-render for unchanged widgets on embedded.
	prev_value_bits: u64,        // Snapshot of the bound value (as raw bits)
	has_value:       bool,       // Whether this widget tracks a value
	dirty:           bool,       // Value changed since last frame

	// --- Interaction transitions ---
	// Smoothed 0..1 fades driving hover/press/focus visuals (see transition.odin).
	// Checkbox reuses press_t as its checked-state fade.
	hover_t:         f32,
	press_t:         f32,
	focus_t:         f32,
}

// Maps widget ID to its box index so frame_end can update prev_rect.
Widget_Box_Entry :: struct {
	id:        Widget_ID,
	box_index: int,
}

// --- Manager ---
// The central retained-state store. Immediate-mode calls read/write through this.

Manager :: struct {
	// Frame bookkeeping
	frame_id:         u64,

	// Widget state persists across frames, keyed by hashed ID
	widget_states:    map[Widget_ID]Widget_State,

	// Layout tree — flat array, rebuilt each frame
	boxes:            [dynamic]Box,
	box_stack:        [dynamic]int,   // stack of parent box indices for nesting

	// Draw command buffer — consumed by backend after frame_end
	draw_list:        Draw_List,

	// Input
	input:            Input_State,

	// Immediate-mode interaction tracking
	hot_id:           Widget_ID,
	active_id:        Widget_ID,
	focus_id:         Widget_ID,

	// Text inputs registered this frame, in render order. Enables Tab-to-next-field
	// focus cycling (see focus_cycle). Rebuilt every frame.
	focus_order:      [dynamic]Widget_ID,

	// ID generation stack
	id_stack:         ID_Stack,

	// Backend handle
	backend:          ^Backend,

	// Frame arena — bulk-freed each frame. Heap-backed for portability (WASM, embedded).
	frame_arena:      mem.Arena,
	frame_arena_buf:  []u8,          // Backing memory for the arena
	frame_allocator:  mem.Allocator,

	// Deferred text entries — resolved after layout
	deferred_texts:   [dynamic]Deferred_Text,

	// Widget-to-box mapping for updating prev_rect after layout
	widget_box_map:   [dynamic]Widget_Box_Entry,

	// Deferred custom draws — resolved after layout
	deferred_draws:   [dynamic]Deferred_Draw,

	// Popup overlays — rendered on top of everything
	popup_draws:      [dynamic]Popup_Draw,
	popup_owner:      Widget_ID,  // ID of the widget that owns the currently open popup
	popup_block:      bool,       // block all interaction until mouse released (popup just closed)
	modal_owner:      Widget_ID,  // Optional ancestor ID allowed to receive interaction.

	// Animation pool
	anim_pool:        Anim_Pool,

	// Per-widget text input state (cursor position, scroll offset)
	text_states:      map[Widget_ID]Text_Input_State,

	// Per-widget scroll state (scroll position, content/viewport sizes)
	scroll_states:    map[Widget_ID]Scroll_State,
	// Per-dropdown popup scroll offset. Kept separately from scrollbox state because
	// dropdown lists are rendered as overlays rather than layout boxes.
	dropdown_scroll_offsets: map[Widget_ID]f32,
	popup_consumed_scroll:   bool,

	// Tracks deepest scroll container under mouse cursor for wheel routing
	scroll_wheel_candidate: Widget_ID,
	// Set while a scrollbar thumb is held. The bar is drawn over the container it
	// scrolls, so for as long as it has the pointer nothing underneath may take
	// the press as its own (see compute_interaction).
	scrollbar_drag:         bool,

	// Tree widget nesting — current depth and, per ancestor level, whether the
	// guide line continues past this row (that level's node has later siblings)
	tree_depth:       int,
	tree_continues:   [TREE_MAX_DEPTH]bool,

	// Sequence counter for generating unique IDs within a single call site (loops)
	seq_counter:      int,

	// Loaded fonts (index 0 = Font_Handle(1), etc.)
	fonts:            [dynamic]Font,
	default_font:     Font_Handle,
}

// Capacity defaults — reduced on freestanding targets to fit in MCU SRAM.
when ODIN_OS == .Freestanding {
	INIT_CAP_WIDGETS :: 32
	INIT_CAP_BOXES   :: 32
	INIT_CAP_STACK   :: 16
	INIT_CAP_DEFER   :: 16
	FRAME_ARENA_SIZE :: 4 * 1024
} else {
	INIT_CAP_WIDGETS :: 256
	INIT_CAP_BOXES   :: 256
	INIT_CAP_STACK   :: 32
	INIT_CAP_DEFER   :: 64
	FRAME_ARENA_SIZE :: 256 * 1024
}

// Initialize the manager. Must be called once before the frame loop.
init :: proc(mgr: ^Manager, backend: ^Backend) {
	mgr.backend = backend
	mgr.widget_states = make(map[Widget_ID]Widget_State, INIT_CAP_WIDGETS)
	mgr.boxes = make([dynamic]Box, 0, INIT_CAP_BOXES)
	mgr.box_stack = make([dynamic]int, 0, INIT_CAP_STACK)
	draw_list_init(&mgr.draw_list)
	mgr.deferred_texts = make([dynamic]Deferred_Text, 0, INIT_CAP_DEFER)
	mgr.widget_box_map = make([dynamic]Widget_Box_Entry, 0, INIT_CAP_DEFER)
	mgr.focus_order    = make([dynamic]Widget_ID, 0, 16)
	mgr.deferred_draws = make([dynamic]Deferred_Draw, 0, INIT_CAP_DEFER)
	mgr.popup_draws    = make([dynamic]Popup_Draw, 0, 4)
	mgr.text_states    = make(map[Widget_ID]Text_Input_State, 16)
	mgr.scroll_states  = make(map[Widget_ID]Scroll_State, 8)
	mgr.dropdown_scroll_offsets = make(map[Widget_ID]f32, 8)
	mgr.fonts          = make([dynamic]Font, 0, 4)
	anim_pool_init(&mgr.anim_pool)

	// Set up frame arena — heap-backed, portable across WASM, embedded, desktop.
	mgr.frame_arena_buf = make([]u8, FRAME_ARENA_SIZE)
	mem.arena_init(&mgr.frame_arena, mgr.frame_arena_buf)
	mgr.frame_allocator = mem.arena_allocator(&mgr.frame_arena)
}

// Shut down the manager and release resources.
shutdown :: proc(mgr: ^Manager) {
	delete(mgr.widget_states)
	delete(mgr.boxes)
	delete(mgr.box_stack)
	delete(mgr.deferred_texts)
	delete(mgr.widget_box_map)
	delete(mgr.focus_order)
	delete(mgr.deferred_draws)
	delete(mgr.popup_draws)
	delete(mgr.text_states)
	delete(mgr.scroll_states)
	delete(mgr.dropdown_scroll_offsets)
	for &f in mgr.fonts {
		if f.atlas_pixels != nil {
			delete(f.atlas_pixels)
		}
		delete(f.glyphs_unicode)
	}
	delete(mgr.fonts)
	draw_list_destroy(&mgr.draw_list)
	delete(mgr.frame_arena_buf)
}

// Begin a new frame. Call this at the top of your frame loop.
frame_begin :: proc(mgr: ^Manager, dt: f32 = -1) {
	// Reset per-frame allocations
	free_all(mgr.frame_allocator)
	clear(&mgr.boxes)
	clear(&mgr.box_stack)
	draw_list_clear(&mgr.draw_list)
	clear(&mgr.deferred_texts)
	clear(&mgr.widget_box_map)
	clear(&mgr.focus_order)
	clear(&mgr.deferred_draws)
	clear(&mgr.popup_draws)
	mgr.seq_counter = 0
	mgr.hot_id = ID_NONE
	mgr.tree_depth = 0
	mgr.scroll_wheel_candidate = ID_NONE
	mgr.popup_consumed_scroll = false
	// Re-armed by whichever scroll container still has the pointer this frame.
	mgr.scrollbar_drag = false

	mgr.frame_id += 1

	// Tick animations (before input so animated values are updated before widgets read them)
	if dt >= 0 {
		anim_pool_tick_dt(&mgr.anim_pool, dt)
	} else {
		anim_pool_tick(&mgr.anim_pool)
	}

	// Poll backend for input events
	if mgr.backend.poll_events != nil {
		mgr.input.quit = mgr.backend.poll_events(mgr.backend, &mgr.input)
	}

	// Release popup interaction block once mouse is up
	if mgr.popup_block && !mgr.input.mouse_left {
		mgr.popup_block = false
	}

	// Clear keyboard focus when mouse is clicked (text inputs reclaim if pressed on them)
	if mgr.input.mouse_left_pressed {
		mgr.focus_id = ID_NONE
	}

	// Push root box that fills the window
	root := Box{
		id           = ID_NONE,
		parent_index = -1,
		first_child  = -1,
		next_sibling = -1,
		layout_kind  = .Flex,
		layout_axis  = .Vertical,
		justify      = .Start,
		align        = .Stretch,
		size         = {size_fixed(f32(mgr.backend.width)), size_fixed(f32(mgr.backend.height))},
	}
	append(&mgr.boxes, root)
	append(&mgr.box_stack, 0) // root is at index 0

	// Begin backend frame
	if mgr.backend.begin_frame != nil {
		mgr.backend.begin_frame(mgr.backend)
	}
}

// End the frame. Runs layout solver and emits draw commands for all boxes.
frame_end :: proc(mgr: ^Manager) {
	// Pop root from box stack
	if len(mgr.box_stack) > 0 {
		pop(&mgr.box_stack)
	}

	// Run layout solver
	resolve_layout(mgr)

	full_screen := Rect{0, 0, f32(mgr.backend.width), f32(mgr.backend.height)}

	// Emit normal-layer draw commands via tree walk (enables proper clip nesting for scrollboxes)
	if len(mgr.boxes) > 0 {
		emit_box_tree(mgr, 0, full_screen, false, false)
	}
	emit_deferred_texts(mgr, false)
	emit_deferred_draws(mgr, false)

	// Floating boxes render after normal text/draws, so modal backgrounds
	// cover the UI below them instead of sitting underneath deferred text.
	if len(mgr.boxes) > 0 {
		emit_box_tree(mgr, 0, full_screen, false, true)
	}
	emit_deferred_texts(mgr, true)
	emit_deferred_draws(mgr, true)

	// Update widget prev_rects for next frame's hit testing
	for entry in mgr.widget_box_map {
		if ws, ok := &mgr.widget_states[entry.id]; ok {
			box := &mgr.boxes[entry.box_index]
			ws.prev_rect = box.computed_rect
			ws.has_prev_clip = box.is_clipped
			if box.is_clipped {
				ws.prev_clip = box.effective_clip
			}
		}
	}

	// Execute all main draw commands through the backend
	if mgr.backend.execute != nil {
		for cmd in mgr.draw_list.commands {
			mgr.backend.execute(mgr.backend, cmd)
		}
	}

	// Emit and execute popup overlays (on top of everything)
	if len(mgr.popup_draws) > 0 {
		popup_list: Draw_List
		draw_list_init(&popup_list, context.temp_allocator)
		saved := mgr.draw_list
		mgr.draw_list = popup_list
		emit_popup_draws(mgr)
		popup_list = mgr.draw_list
		mgr.draw_list = saved

		if mgr.backend.execute != nil {
			for cmd in popup_list.commands {
				mgr.backend.execute(mgr.backend, cmd)
			}
		}
	}

	// End backend frame (present)
	if mgr.backend.end_frame != nil {
		mgr.backend.end_frame(mgr.backend)
	}

	// Reset edge-triggered input events after widgets have consumed them.
	// This ensures events set asynchronously (web/WASM) persist until processed.
	mgr.input.mouse_left_pressed = false
	mgr.input.mouse_right_pressed = false
	mgr.input.text_char_len = 0
	mgr.input.key_backspace = false
	mgr.input.key_tab = false
	mgr.input.key_delete = false
	mgr.input.key_left = false
	mgr.input.key_right = false
	mgr.input.key_up = false
	mgr.input.key_down = false
	mgr.input.key_home = false
	mgr.input.key_end = false
	mgr.input.key_enter = false
	mgr.input.key_escape = false
	mgr.input.key_copy = false
	mgr.input.key_paste = false
	mgr.input.key_cut = false
	mgr.input.key_find = false
	mgr.input.key_find_all = false
	mgr.input.key_code = 0
	mgr.input.dropped_file_len = 0
	mgr.input.mouse_scroll_y = 0

	// GC: remove widget states not seen for 60 frames
	gc_stale_states(mgr)
}

emit_deferred_texts :: proc(mgr: ^Manager, floating: bool) {
	full_screen := Rect{0, 0, f32(mgr.backend.width), f32(mgr.backend.height)}
	needs_clip_reset := false
	for &dt in mgr.deferred_texts {
		if box_is_floating(mgr, dt.box_index) != floating {
			continue
		}
		b := &mgr.boxes[dt.box_index]
		text_size := measure_text(mgr, dt.text, dt.font, dt.scale)
		if len(dt.runs) > 0 {
			text_size = styled_runs_size(dt.runs, dt.run_lines, dt.run_line_height)
		}
		eff_scale := get_effective_scale(mgr, dt.font, dt.scale)
		cr := b.content_rect

		// Only push clip when the box is inside a clipping ancestor or needs its own clip
		if b.is_clipped || dt.clip {
			clip := b.effective_clip
			if dt.clip {
				clip = rect_intersect(clip, cr)
			}
			push_clip(&mgr.draw_list, clip)
			needs_clip_reset = true
		} else if needs_clip_reset {
			push_clip(&mgr.draw_list, full_screen)
			needs_clip_reset = false
		}

		tx := cr.x + dt.offset_x
		ty := cr.y + dt.offset_y
		if dt.center_h {
			tx = cr.x + (cr.w - text_size.x) / 2
		}
		if dt.center_v {
			ty = cr.y + (cr.h - text_size.y) / 2
		}

		if len(dt.runs) > 0 {
			emit_styled_runs(mgr, dt, {tx, ty})
			continue
		}

		if dt.selection_end > dt.selection_start && len(dt.text) > 0 {
			emit_text_selection(
				mgr,
				dt.text,
				dt.selection_start,
				dt.selection_end,
				{tx, ty},
				dt.font,
				dt.scale,
				dt.selection_color,
			)
		}
		push_text(&mgr.draw_list, {tx, ty}, dt.text, dt.color, dt.font, eff_scale)
	}
	if needs_clip_reset {
		push_clip(&mgr.draw_list, full_screen)
	}
}

emit_text_selection :: proc(
	mgr: ^Manager,
	text: string,
	selection_start, selection_end: int,
	origin: Vec2,
	font: Font_Handle,
	scale: f32,
	color: Color,
) {
	start := clamp(selection_start, 0, len(text))
	end := clamp(selection_end, start, len(text))
	if start == end {
		return
	}

	line_h := get_line_height(mgr, font, scale)
	line_start := 0
	line_index := 0
	for line_start <= len(text) {
		line_end := len(text)
		for i in line_start..<len(text) {
			if text[i] == '\n' {
				line_end = i
				break
			}
		}

		segment_start := max(start, line_start)
		segment_end := min(end, line_end)
		if segment_start < segment_end {
			x1 := origin.x + measure_text_prefix(mgr, text[line_start:line_end], segment_start - line_start, font, scale)
			x2 := origin.x + measure_text_prefix(mgr, text[line_start:line_end], segment_end - line_start, font, scale)
			push_filled_rect(
				&mgr.draw_list,
				Rect{x1, origin.y + f32(line_index) * line_h, max(f32(1), x2 - x1), line_h},
				color,
			)
		}

		if line_end == len(text) {
			break
		}
		line_start = line_end + 1
		line_index += 1
	}
}

// Returns true if the application should quit.
should_quit :: proc(mgr: ^Manager) -> bool {
	return mgr.input.quit
}

// --- ID helpers for user code ---

push_id_int :: proc(mgr: ^Manager, n: int) {
	id := id_from_int(&mgr.id_stack, n)
	id_stack_push(&mgr.id_stack, id)
}

push_id_string :: proc(mgr: ^Manager, label: string) {
	id := id_from_string(&mgr.id_stack, label)
	id_stack_push(&mgr.id_stack, id)
}

push_id :: proc{push_id_int, push_id_string}

pop_id :: proc(mgr: ^Manager) {
	id_stack_pop(&mgr.id_stack)
}

// Move keyboard focus to the next (or previous, when backward) text input that
// registered itself this frame. Cycling is confined to the focus_order slice
// [lo, hi) so a caller can scope Tab traversal to a single form; pass 0 and
// len(mgr.focus_order) to cycle across every input. Wraps around at the ends,
// and starts from the first (or last) entry when nothing in range is focused.
focus_cycle :: proc(mgr: ^Manager, lo, hi: int, backward := false) {
	lo := clamp(lo, 0, len(mgr.focus_order))
	hi := clamp(hi, lo, len(mgr.focus_order))
	n := hi - lo
	if n <= 0 {
		return
	}
	current := -1
	for i in lo..<hi {
		if mgr.focus_order[i] == mgr.focus_id {
			current = i - lo
			break
		}
	}
	next: int
	if current < 0 {
		next = n - 1 if backward else 0
	} else {
		step := n - 1 if backward else 1
		next = (current + step) % n
	}
	mgr.focus_id = mgr.focus_order[lo + next]
}

// --- Internal ---

// Recursive tree walk for draw emission. Handles clip push/pop for scroll containers.
// parent_clip is the active clip region inherited from the ancestor chain.
// parent_is_clipped is true when any ancestor has Clip_Children set.
emit_box_tree :: proc(
	mgr: ^Manager,
	idx: int,
	parent_clip: Rect,
	parent_is_clipped: bool,
	include_floating: bool,
	parent_is_floating: bool = false,
) {
	b := &mgr.boxes[idx]
	self_is_floating := parent_is_floating || .Is_Floating in b.flags
	draw_self := self_is_floating == include_floating
	if idx == 0 {
		draw_self = !include_floating
	}

	// Store effective clip so deferred draws (text, sliders, etc.) can use it.
	// Only the pass that actually draws this box owns that bookkeeping: the tree
	// is walked twice (normal, then floating), and writing here on every visit
	// let the floating pass — which clips nothing, because a non-floating
	// container's draw_self is false in it — erase the normal pass's clip for
	// every scrolled widget in the app. frame_end snapshots these into
	// has_prev_clip/prev_clip afterwards, so that erasure silently disabled the
	// hit test's clip guard: a row scrolled out of its viewport kept a live rect
	// and took presses meant for whatever is laid out below the container.
	if draw_self {
		b.effective_clip = parent_clip
		b.is_clipped = parent_is_clipped
	}

	// Draw background
	if draw_self && b.bg_color.a > 0 {
		push_filled_rect(&mgr.draw_list, b.computed_rect, b.bg_color, b.corner_radius)
	}
	// Draw border
	if draw_self && b.border_width > 0 && b.border_color.a > 0 {
		push_rect_outline(&mgr.draw_list, b.computed_rect, b.border_color, b.border_width, b.corner_radius)
	}

	// Push clip for containers that clip children (scrollboxes).
	// Intersect with parent clip so nested clips are properly contained.
	clipping := draw_self && .Clip_Children in b.flags
	current_clip := parent_clip
	child_is_clipped := parent_is_clipped
	if clipping {
		current_clip = rect_intersect(parent_clip, b.content_rect)
		child_is_clipped = true
		push_clip(&mgr.draw_list, current_clip)
	}

	// Recurse into children
	child := b.first_child
	for child != -1 {
		emit_box_tree(mgr, child, current_clip, child_is_clipped, include_floating, self_is_floating)
		child = mgr.boxes[child].next_sibling
	}

	// Restore parent's clip region
	if clipping {
		push_clip(&mgr.draw_list, parent_clip)
	}
}

box_is_floating :: proc(mgr: ^Manager, idx: int) -> bool {
	cursor := idx
	for cursor != -1 {
		if .Is_Floating in mgr.boxes[cursor].flags {
			return true
		}
		cursor = mgr.boxes[cursor].parent_index
	}
	return false
}

// --- Font Management ---

// Load a TrueType font from raw TTF file data, rasterize it at the given pixel size,
// and upload it to the backend. Backends without a font upload hook stay bitmap-only.
// Returns a Font_Handle for use with set_default_font.
// Pass antialiasing = .None for hard-edged, unantialiased glyphs.
when ODIN_OS != .Freestanding {
	load_font :: proc(
		mgr: ^Manager,
		ttf_data: []u8,
		pixel_size: f32,
		extra_codepoints: []rune = nil,
		antialiasing: Font_Antialiasing = .Grayscale,
	) -> (Font_Handle, bool) {
		if mgr.backend == nil || mgr.backend.load_font == nil {
			return FONT_BUILTIN, false
		}

		font, ok := load_font_from_data(ttf_data, pixel_size, extra_codepoints, antialiasing)
		if !ok { return FONT_BUILTIN, false }

		handle := Font_Handle(len(mgr.fonts) + 1)
		append(&mgr.fonts, font)

		// Notify the backend so it can create a GPU texture from the alpha atlas.
		mgr.backend.load_font(mgr.backend, &mgr.fonts[len(mgr.fonts) - 1], handle)

		return handle, true
	}
}

// Set the default font used by all widgets (labels, buttons, headings, etc.).
set_default_font :: proc(mgr: ^Manager, font: Font_Handle) {
	if font != FONT_DEFAULT && (font == FONT_BUILTIN || (int(font) - 1 < len(mgr.fonts))) {
		mgr.default_font = font
	}
}

// Get a pointer to a loaded Font by handle. Returns nil for FONT_BUILTIN or invalid handles.
get_font :: proc(mgr: ^Manager, handle: Font_Handle) -> ^Font {
	effective_handle := resolve_font(mgr, handle)
	if effective_handle == FONT_BUILTIN || int(effective_handle) - 1 >= len(mgr.fonts) { return nil }
	return &mgr.fonts[int(effective_handle) - 1]
}

// --- Internal ---

gc_stale_states :: proc(mgr: ^Manager) {
	GC_THRESHOLD :: 60
	to_remove: [dynamic]Widget_ID
	defer delete(to_remove)

	for id, state in mgr.widget_states {
		if mgr.frame_id - state.last_seen_frame > GC_THRESHOLD {
			append(&to_remove, id)
		}
	}
	for id in to_remove {
		delete_key(&mgr.widget_states, id)
	}
}

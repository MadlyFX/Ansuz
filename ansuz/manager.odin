package ansuz

import "core:mem"

// --- Widget State ---
// Per-widget persistent state that survives across frames.

Widget_State :: struct {
	last_seen_frame: u64,
	prev_rect:       Rect,       // Rect from last frame, used for hit testing

	// --- Value tracking ---
	// The manager snapshots bound values each frame to detect changes.
	// This enables skipping re-render for unchanged widgets on embedded.
	prev_value_bits: u64,        // Snapshot of the bound value (as raw bits)
	has_value:       bool,       // Whether this widget tracks a value
	dirty:           bool,       // Value changed since last frame

	// --- Future: value interception ---
	// These fields enable the manager to constrain or override values.
	// Not yet enforced — infrastructure for Step 4 (animations) and user constraints.
	constraint_min:  u64,        // Min value (as raw bits)
	constraint_max:  u64,        // Max value (as raw bits)
	has_constraints: bool,
	wrap:            bool,       // Wrap vs clamp on constraint violation
	override_bits:   u64,        // Animation override value
	override_active: bool,       // Whether override is in effect
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

	// Animation pool
	anim_pool:        Anim_Pool,

	// Per-widget text input state (cursor position, scroll offset)
	text_states:      map[Widget_ID]Text_Input_State,

	// Per-widget scroll state (scroll position, content/viewport sizes)
	scroll_states:    map[Widget_ID]Scroll_State,

	// Tracks deepest scroll container under mouse cursor for wheel routing
	scroll_wheel_candidate: Widget_ID,

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
	mgr.deferred_draws = make([dynamic]Deferred_Draw, 0, INIT_CAP_DEFER)
	mgr.popup_draws    = make([dynamic]Popup_Draw, 0, 4)
	mgr.text_states    = make(map[Widget_ID]Text_Input_State, 16)
	mgr.scroll_states  = make(map[Widget_ID]Scroll_State, 8)
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
	delete(mgr.deferred_draws)
	delete(mgr.popup_draws)
	delete(mgr.text_states)
	delete(mgr.scroll_states)
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
frame_begin :: proc(mgr: ^Manager) {
	// Reset per-frame allocations
	free_all(mgr.frame_allocator)
	clear(&mgr.boxes)
	clear(&mgr.box_stack)
	draw_list_clear(&mgr.draw_list)
	clear(&mgr.deferred_texts)
	clear(&mgr.widget_box_map)
	clear(&mgr.deferred_draws)
	clear(&mgr.popup_draws)
	mgr.seq_counter = 0
	mgr.hot_id = ID_NONE
	mgr.scroll_wheel_candidate = ID_NONE

	mgr.frame_id += 1

	// Tick animations (before input so animated values are updated before widgets read them)
	anim_pool_tick(&mgr.anim_pool)

	// Poll backend for input events
	if mgr.backend.poll_events != nil {
		mgr.input.mouse_prev_x = mgr.input.mouse_x
		mgr.input.mouse_prev_y = mgr.input.mouse_y
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

	// Emit draw commands via tree walk (enables proper clip nesting for scrollboxes)
	if len(mgr.boxes) > 0 {
		full_screen := Rect{0, 0, f32(mgr.backend.width), f32(mgr.backend.height)}
		emit_box_tree(mgr, 0, full_screen, false)
	}

	// Emit deferred text draw commands (now that layout rects are resolved)
	full_screen := Rect{0, 0, f32(mgr.backend.width), f32(mgr.backend.height)}
	needs_clip_reset := false
	for &dt in mgr.deferred_texts {
		b := &mgr.boxes[dt.box_index]
		text_size := measure_text(mgr, dt.text, dt.font, dt.scale)
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

		push_text(&mgr.draw_list, {tx, ty}, dt.text, dt.color, dt.font, eff_scale)
	}
	if needs_clip_reset {
		push_clip(&mgr.draw_list, full_screen)
	}

	// Emit deferred custom draws (sliders, checkmarks, arrows, etc.)
	emit_deferred_draws(mgr)

	// Update widget prev_rects for next frame's hit testing
	for entry in mgr.widget_box_map {
		if ws, ok := &mgr.widget_states[entry.id]; ok {
			ws.prev_rect = mgr.boxes[entry.box_index].computed_rect
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
	mgr.input.text_char_len = 0
	mgr.input.key_backspace = false
	mgr.input.key_delete = false
	mgr.input.key_left = false
	mgr.input.key_right = false
	mgr.input.key_up = false
	mgr.input.key_down = false
	mgr.input.key_home = false
	mgr.input.key_end = false
	mgr.input.key_enter = false
	mgr.input.mouse_scroll_y = 0

	// GC: remove widget states not seen for 60 frames
	gc_stale_states(mgr)
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

// --- Internal ---

// Recursive tree walk for draw emission. Handles clip push/pop for scroll containers.
// parent_clip is the active clip region inherited from the ancestor chain.
// parent_is_clipped is true when any ancestor has Clip_Children set.
emit_box_tree :: proc(mgr: ^Manager, idx: int, parent_clip: Rect, parent_is_clipped: bool) {
	b := &mgr.boxes[idx]

	// Store effective clip so deferred draws (text, sliders, etc.) can use it
	b.effective_clip = parent_clip
	b.is_clipped = parent_is_clipped

	// Draw background
	if b.bg_color.a > 0 {
		push_filled_rect(&mgr.draw_list, b.computed_rect, b.bg_color, b.corner_radius)
	}
	// Draw border
	if b.border_width > 0 && b.border_color.a > 0 {
		push_rect_outline(&mgr.draw_list, b.computed_rect, b.border_color, b.border_width, b.corner_radius)
	}

	// Push clip for containers that clip children (scrollboxes).
	// Intersect with parent clip so nested clips are properly contained.
	clipping := .Clip_Children in b.flags
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
		emit_box_tree(mgr, child, current_clip, child_is_clipped)
		child = mgr.boxes[child].next_sibling
	}

	// Restore parent's clip region
	if clipping {
		push_clip(&mgr.draw_list, parent_clip)
	}
}

// --- Font Management ---

// Load a TrueType font from raw TTF file data, rasterize it at the given pixel size,
// and upload it to the backend. Returns a Font_Handle for use with set_default_font.
when ODIN_OS != .Freestanding {
	load_font :: proc(mgr: ^Manager, ttf_data: []u8, pixel_size: f32, extra_codepoints: []rune = nil) -> (Font_Handle, bool) {
		font, ok := load_font_from_data(ttf_data, pixel_size, extra_codepoints)
		if !ok { return FONT_BUILTIN, false }

		handle := Font_Handle(len(mgr.fonts) + 1)
		append(&mgr.fonts, font)

		// Notify the backend so it can create a GPU texture from the atlas
		if mgr.backend.load_font != nil {
			mgr.backend.load_font(mgr.backend, &mgr.fonts[len(mgr.fonts) - 1], handle)
		}

		return handle, true
	}
}

// Set the default font used by all widgets (labels, buttons, headings, etc.).
set_default_font :: proc(mgr: ^Manager, font: Font_Handle) {
	if font == FONT_BUILTIN || (int(font) - 1 < len(mgr.fonts)) {
		mgr.default_font = font
	}
}

// Get a pointer to a loaded Font by handle. Returns nil for FONT_BUILTIN or invalid handles.
get_font :: proc(mgr: ^Manager, handle: Font_Handle) -> ^Font {
	if handle == FONT_BUILTIN || int(handle) - 1 >= len(mgr.fonts) { return nil }
	return &mgr.fonts[int(handle) - 1]
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

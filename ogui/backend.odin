package ogui

// --- Backend Interface ---
// A struct of procedure pointers. Each rendering backend (SDL, software, etc.)
// populates these with its own implementations.

Backend :: struct {
	// Called once at startup
	init:         proc(backend: ^Backend, width, height: i32) -> bool,

	// Called once at shutdown
	shutdown:     proc(backend: ^Backend),

	// Called at the start of each frame
	begin_frame:  proc(backend: ^Backend),

	// Called at the end of each frame (present/flip)
	end_frame:    proc(backend: ^Backend),

	// Execute a single draw command
	execute:      proc(backend: ^Backend, cmd: Draw_Command),

	// Measure text dimensions (needed by layout for Auto-sized text boxes)
	measure_text: proc(backend: ^Backend, text: string, font: Font_Handle, size: f32) -> Vec2,

	// Poll for input events. Returns true if the application should quit.
	poll_events:  proc(backend: ^Backend, input: ^Input_State) -> bool,

	// Backend-specific data
	user_data:    rawptr,

	// Current window dimensions (updated by backend)
	width:        i32,
	height:       i32,
}

// --- Input State ---

Input_State :: struct {
	mouse_x:            f32,
	mouse_y:            f32,
	mouse_prev_x:       f32,
	mouse_prev_y:       f32,
	mouse_left:         bool,
	mouse_right:        bool,
	mouse_middle:       bool,
	mouse_left_pressed: bool,    // went down this frame (edge-triggered)
	quit:               bool,

	// Text input characters typed this frame (from OS text input events)
	text_chars:    [64]u8,
	text_char_len: int,

	// Keyboard key-down events (reset each frame, set by backend on key press)
	key_backspace: bool,
	key_delete:    bool,
	key_left:      bool,
	key_right:     bool,
	key_up:        bool,
	key_down:      bool,
	key_home:      bool,
	key_end:       bool,
	key_enter:     bool,

	// Modifier held states
	key_shift:     bool,
	key_ctrl:      bool,

	// Mouse scroll wheel (positive = scroll up/towards user)
	mouse_scroll_y: f32,
}

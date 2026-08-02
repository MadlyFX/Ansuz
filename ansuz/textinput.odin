package ansuz

// --- Text Input Widget ---
// Editable text field with single-line and multi-line modes.
// The user passes a ^[dynamic]u8 buffer; the widget reads/writes it.
// Cursor position and scroll state are tracked internally by the manager.

Text_Input_State :: struct {
	cursor:           int,  // cursor byte position in the buffer
	selection_anchor: int,  // fixed end of the selection; equals cursor when empty
	dragging:         bool,
	scroll_x:         f32, // horizontal scroll offset (single-line)
	scroll_y:         f32, // vertical scroll offset (multiline)
}

THEME_TEXTINPUT_BG           :: Color{35, 38, 45, 255}
THEME_TEXTINPUT_FOCUS_BORDER :: Color{80, 140, 220, 255}
THEME_TEXTINPUT_CURSOR       :: Color{200, 210, 230, 255}

text_input :: proc(
	mgr:         ^Manager,
	buf:         ^[dynamic]u8,
	multiline:   bool         = false,
	// Fold long lines to the field's own column (multiline only). Without it a
	// line runs off the right edge with nothing to scroll it back into view.
	wrap:        bool         = false,
	font:        Font_Handle  = FONT_DEFAULT,
	scale:       f32          = DEFAULT_FONT_SCALE,
	size:        [2]Size_Spec = FIXED_200_FIT,
	padding:     [4]f32       = {6, 8, 6, 8},
	placeholder: string       = "",
	color: Widget_Color = Widget_Color{
		bg    = THEME_TEXTINPUT_BG,
		fg    = THEME_BORDER,
		hover = THEME_TEXTINPUT_FOCUS_BORDER,
		focus = THEME_TEXTINPUT_FOCUS_BORDER,
	},
	text_color: Color = THEME_TEXT,
	placeholder_color: Color = THEME_TEXT_DIM,
	cursor_color: Color = THEME_TEXTINPUT_CURSOR,
	selection_color: Color = Color{80, 140, 220, 110},
	loc          := #caller_location,
) -> (Interaction, ^Text_Input_State) {
	effective_font := resolve_font(mgr, font)
	id := id_from_ptr_loc(&mgr.id_stack, buf, loc)

	// Record this field in the frame's focus order so Tab can cycle between inputs.
	append(&mgr.focus_order, id)

	// Look up previous frame's rect for hit testing
	prev_rect := Rect{}
	if state, ok := mgr.widget_states[id]; ok {
		prev_rect = state.prev_rect
	}

	interaction := compute_interaction(mgr, id, prev_rect)

	// Focus on press (not click) so it reclaims immediately after frame_begin clears focus
	if .Pressed in interaction {
		mgr.focus_id = id
	}

	is_focused := mgr.focus_id == id
	if is_focused {
		interaction += {.Focused}
	}

	// Get or create text input state
	if id not_in mgr.text_states {
		mgr.text_states[id] = Text_Input_State{cursor = len(buf^), selection_anchor = len(buf^)}
	}
	ts := &mgr.text_states[id]
	ts.cursor = clamp(ts.cursor, 0, len(buf^))
	ts.selection_anchor = clamp(ts.selection_anchor, 0, len(buf^))

	// Where the text folds to fit the column, as byte offsets into the buffer.
	// The buffer itself is never rewritten, so the cursor, the selection and every
	// edit below stay in buffer coordinates; only what is drawn, hit-tested and
	// stepped over vertically works in the folded form. The column comes from last
	// frame's rect, so a resized field settles on the next one.
	content_w := prev_rect.w - padding[1] - padding[3]
	soft_wrap := multiline && wrap && content_w > 0
	breaks: []int
	if soft_wrap {
		breaks = soft_wrap_offsets(mgr, string(buf^[:]), content_w, effective_font, scale)
	}

	// Click and drag establish a real selection. Shift-click extends the current
	// selection instead of replacing its anchor.
	if (mgr.input.mouse_left_pressed && .Pressed in interaction || ts.dragging && mgr.input.mouse_left) &&
	   prev_rect.w > 0 {
		hit_text := string(buf^[:])
		if soft_wrap {
			hit_text = wrapped_text(hit_text, breaks)
		}
		position := text_input_hit_cursor(
			mgr,
			hit_text,
			multiline,
			effective_font,
			scale,
			prev_rect,
			padding,
			ts.scroll_x,
			ts.scroll_y,
			mgr.input.mouse_x,
			mgr.input.mouse_y,
		)
		if soft_wrap {
			position = wrap_buffer_index(breaks, position)
		}
		if mgr.input.mouse_left_pressed {
			if !mgr.input.key_shift {
				ts.selection_anchor = position
			}
			ts.dragging = true
		}
		ts.cursor = position
	}
	if !mgr.input.mouse_left {
		ts.dragging = false
	}

	// Handle keyboard input when focused
	if is_focused {
		if mgr.input.key_ctrl && mgr.input.key_code == 'A' {
			ts.selection_anchor = 0
			ts.cursor = len(buf^)
		}

		if mgr.input.key_copy && mgr.backend.set_clipboard_text != nil {
			if selection, selected := selected_text(buf^[:], ts); selected {
				_ = mgr.backend.set_clipboard_text(mgr.backend, selection)
			}
		}

		if mgr.input.key_cut && mgr.backend.set_clipboard_text != nil {
			if selection, selected := selected_text(buf^[:], ts); selected {
				_ = mgr.backend.set_clipboard_text(mgr.backend, selection)
				delete_text_selection(buf, ts)
			}
		}

		if mgr.input.key_paste && mgr.backend.get_clipboard_text != nil {
			text := mgr.backend.get_clipboard_text(mgr.backend, context.temp_allocator)
			delete_text_selection(buf, ts)
			insert_text_at_cursor(buf, &ts.cursor, text, multiline)
			ts.selection_anchor = ts.cursor
		}

		// Insert typed characters
		if !mgr.input.key_ctrl && mgr.input.text_char_len > 0 {
			delete_text_selection(buf, ts)
			for i in 0..<mgr.input.text_char_len {
				ch := mgr.input.text_chars[i]
				if ch >= 32 {
					if ts.cursor >= len(buf^) {
						append(buf, ch)
					} else {
						inject_at(buf, ts.cursor, ch)
					}
					ts.cursor += 1
				}
			}
			ts.selection_anchor = ts.cursor
		}

		// Backspace
		if mgr.input.key_backspace {
			if !delete_text_selection(buf, ts) && ts.cursor > 0 {
				ts.cursor -= 1
				ordered_remove(buf, ts.cursor)
				ts.selection_anchor = ts.cursor
			}
		}

		// Delete
		if mgr.input.key_delete {
			if !delete_text_selection(buf, ts) && ts.cursor < len(buf^) {
				ordered_remove(buf, ts.cursor)
				ts.selection_anchor = ts.cursor
			}
		}

		// Arrow keys
		if mgr.input.key_left {
			selection_start, _, selected := text_selection_bounds(ts)
			if selected && !mgr.input.key_shift {
				ts.cursor = selection_start
			} else if ts.cursor > 0 {
				ts.cursor -= 1
			}
			if !mgr.input.key_shift { ts.selection_anchor = ts.cursor }
		}
		if mgr.input.key_right {
			_, selection_end, selected := text_selection_bounds(ts)
			if selected && !mgr.input.key_shift {
				ts.cursor = selection_end
			} else if ts.cursor < len(buf^) {
				ts.cursor += 1
			}
			if !mgr.input.key_shift { ts.selection_anchor = ts.cursor }
		}

		// Home
		if mgr.input.key_home {
			ts.cursor = visual_line_start(string(buf^[:]), breaks, ts.cursor) if multiline else 0
			if !mgr.input.key_shift { ts.selection_anchor = ts.cursor }
		}

		// End
		if mgr.input.key_end {
			ts.cursor = visual_line_end(string(buf^[:]), breaks, ts.cursor) if multiline else len(buf^)
			if !mgr.input.key_shift { ts.selection_anchor = ts.cursor }
		}

		// Enter for multiline
		if multiline && mgr.input.key_enter {
			delete_text_selection(buf, ts)
			if ts.cursor >= len(buf^) {
				append(buf, '\n')
			} else {
				inject_at(buf, ts.cursor, u8('\n'))
			}
			ts.cursor += 1
			ts.selection_anchor = ts.cursor
		}

		// Up/Down for multiline. Both step a visual line, so a folded line is walked
		// the way it reads rather than jumping over the whole paragraph it belongs to.
		if multiline {
			text := string(buf^[:])
			if mgr.input.key_up {
				start := visual_line_start(text, breaks, ts.cursor)
				if start > 0 {
					previous := visual_line_start(text, breaks, start - 1)
					length := visual_line_end(text, breaks, previous) - previous
					ts.cursor = previous + min(ts.cursor - start, length)
				}
				if !mgr.input.key_shift { ts.selection_anchor = ts.cursor }
			}
			if mgr.input.key_down {
				end := visual_line_end(text, breaks, ts.cursor)
				if end < len(text) {
					column := ts.cursor - visual_line_start(text, breaks, ts.cursor)
					// A hard break is a byte to step over; a soft one is not.
					next := end + 1 if text[end] == '\n' else end
					length := visual_line_end(text, breaks, next) - next
					ts.cursor = next + min(column, length)
				}
				if !mgr.input.key_shift { ts.selection_anchor = ts.cursor }
			}
		}
	}

	// Clamp cursor and selection after edits or external buffer changes.
	ts.cursor = clamp(ts.cursor, 0, len(buf^))
	ts.selection_anchor = clamp(ts.selection_anchor, 0, len(buf^))

	// The keystrokes above may have rewritten the buffer, so fold it again before
	// anything below counts, scrolls or draws its lines.
	folded := string(buf^[:])
	if soft_wrap {
		breaks = soft_wrap_offsets(mgr, folded, content_w, effective_font, scale)
		folded = wrapped_text(folded, breaks)
	}

	// Auto-scroll for single-line: keep cursor visible within the content area
	if !multiline && prev_rect.w > 0 {
		viewport_w := prev_rect.w - padding[1] - padding[3]
		if viewport_w > 0 {
			cursor_px := measure_text_prefix(mgr, string(buf^[:]), ts.cursor, effective_font, scale)
			if cursor_px > ts.scroll_x + viewport_w {
				ts.scroll_x = cursor_px - viewport_w
			}
			if cursor_px < ts.scroll_x {
				ts.scroll_x = cursor_px
			}
			ts.scroll_x = max(ts.scroll_x, 0)
		}
	}

	// Auto-scroll for multiline: ensure cursor line is visible
	if multiline {
		line_h := get_line_height(mgr, effective_font, scale)
		// Find cursor line
		cursor_line := 0
		for i in 0..<ts.cursor {
			if i < len(buf^) && buf^[i] == '\n' {
				cursor_line += 1
			}
		}
		for b in breaks {
			if b > ts.cursor { break }
			cursor_line += 1
		}
		cursor_y_top := f32(cursor_line) * line_h
		cursor_y_bot := cursor_y_top + line_h

		// Use prev_rect to estimate the visible content height
		viewport_h := prev_rect.h - padding[0] - padding[2]
		if viewport_h > 0 {
			if cursor_y_bot > ts.scroll_y + viewport_h {
				ts.scroll_y = cursor_y_bot - viewport_h
			}
			if cursor_y_top < ts.scroll_y {
				ts.scroll_y = cursor_y_top
			}
			// Never hold an offset the text no longer needs. A field that grows to
			// fit its content — or loses lines to an edit — would otherwise keep
			// scrolling the top of it out of sight above the box.
			line_count := 1 + len(breaks)
			for ch in buf^ {
				if ch == '\n' { line_count += 1 }
			}
			ts.scroll_y = min(ts.scroll_y, max(0, f32(line_count) * line_h - viewport_h))
		}
		ts.scroll_y = max(ts.scroll_y, 0)
	}

	// Visual styling
	hover_t := get_hover_t(mgr, id, .Hovered in interaction)
	focus_t := get_focus_t(mgr, id, is_focused)
	border_base := color_lerp(color.fg, color.hover, hover_t)
	border := color_lerp(border_base, color.focus, focus_t)

	// Display text (show placeholder if buffer is empty)
	display_text := folded if len(buf^) > 0 else placeholder
	display_color := text_color if len(buf^) > 0 else placeholder_color
	// Compute size
	actual_size := size
	line_h := get_line_height(mgr, effective_font, scale)
	if !multiline {
		if actual_size[1].kind == .Fit {
			actual_size[1] = size_fixed(line_h + padding[0] + padding[2])
		}
	} else {
		if actual_size[1].kind == .Fit {
			line_count := 1 + len(breaks)
			for ch in buf^ {
				if ch == '\n' { line_count += 1 }
			}
			line_count = max(line_count, 3)
			actual_size[1] = size_fixed(f32(line_count) * line_h + padding[0] + padding[2])
		}
	}

	idx := box(mgr, size = actual_size, bg_color = color.bg, loc = loc)
	mgr.boxes[idx].padding = padding
	mgr.boxes[idx].border_width = max(1, 1.5 * (scale / DEFAULT_FONT_SCALE))
	mgr.boxes[idx].border_color = border
	mgr.boxes[idx].corner_radius = max(1, 4 * (scale / DEFAULT_FONT_SCALE))

	// Defer text drawing (clipped to content rect for overflow)
	append(&mgr.deferred_texts, Deferred_Text{
		box_index = idx,
		text      = display_text,
		color     = display_color,
		scale     = scale,
		font      = effective_font,
		center_h  = false,
		center_v  = !multiline,
		clip      = true,
		offset_x  = -ts.scroll_x if !multiline else 0,
		offset_y  = -ts.scroll_y if multiline else 0,
		// Everything drawn works in the folded text's coordinates, so the buffer
		// offsets the selection is stored at are mapped over to it.
		selection_start = wrap_display_index(breaks, min(ts.cursor, ts.selection_anchor)) if len(buf^) > 0 else 0,
		selection_end   = wrap_display_index(breaks, max(ts.cursor, ts.selection_anchor)) if len(buf^) > 0 else 0,
		selection_color = selection_color,
	})

	// Defer cursor drawing if focused
	if is_focused {
		append(&mgr.deferred_draws, Deferred_Draw{
			box_index   = idx,
			kind        = .Text_Cursor,
			scale       = scale,
			text_cursor = Deferred_Text_Cursor_Data{
				cursor_pos = wrap_display_index(breaks, ts.cursor),
				multiline  = multiline,
				text       = folded,
				font       = effective_font,
				color      = cursor_color,
				offset_x   = -ts.scroll_x if !multiline else 0,
				offset_y   = -ts.scroll_y if multiline else 0,
			},
		})
	}

	// Register widget state for hit testing and prev_rect update
	get_or_create_widget_state(mgr, id)
	append(&mgr.widget_box_map, Widget_Box_Entry{id = id, box_index = idx})

	return interaction, ts
}

// --- Soft-wrapped editing -------------------------------------------------
// A wrapped field folds its text for display only and leaves the buffer alone,
// so every index it stores stays a buffer index. `breaks` is what
// soft_wrap_offsets returned for that buffer; an empty one makes all of these
// degrade to plain hard-break behavior, which is exactly what an unwrapped
// multiline field wants.

// wrapped_text returns `text` with a newline inserted at each soft break — the
// form the renderer, the caret and hit testing all work in.
wrapped_text :: proc(text: string, breaks: []int, allocator := context.temp_allocator) -> string {
	if len(breaks) == 0 {
		return text
	}
	out := make([dynamic]u8, 0, len(text) + len(breaks), allocator)
	next := 0
	for i in 0 ..< len(text) {
		for next < len(breaks) && breaks[next] <= i {
			append(&out, '\n')
			next += 1
		}
		append(&out, text[i])
	}
	return string(out[:])
}

// wrap_display_index maps a buffer index to the same spot in the wrapped text.
// An index sitting exactly on a break lands after the inserted newline, i.e. at
// the head of the continuation rather than off the end of the line above it.
wrap_display_index :: proc(breaks: []int, index: int) -> int {
	shift := 0
	for b in breaks {
		if b > index { break }
		shift += 1
	}
	return index + shift
}

// wrap_buffer_index maps an index in the wrapped text back to the buffer. A
// click landing on an inserted newline resolves to the end of the line it broke.
wrap_buffer_index :: proc(breaks: []int, index: int) -> int {
	shift := 0
	for b, i in breaks {
		if b + i >= index { break }
		shift += 1
	}
	return index - shift
}

// visual_line_start returns where the line `index` sits on begins: after the
// nearest newline before it, or at the soft break that opened it.
visual_line_start :: proc(text: string, breaks: []int, index: int) -> int {
	position := clamp(index, 0, len(text))
	start := 0
	for i := position - 1; i >= 0; i -= 1 {
		if text[i] == '\n' {
			start = i + 1
			break
		}
	}
	for b in breaks {
		if b > position { break }
		if b > start { start = b }
	}
	return start
}

// visual_line_end returns where that line ends: at the next newline, the next
// soft break, or the end of the text.
visual_line_end :: proc(text: string, breaks: []int, index: int) -> int {
	position := clamp(index, 0, len(text))
	end := len(text)
	for i := position; i < len(text); i += 1 {
		if text[i] == '\n' {
			end = i
			break
		}
	}
	for b in breaks {
		if b > position && b < end {
			end = b
			break
		}
	}
	return end
}

text_selection_bounds :: proc(ts: ^Text_Input_State) -> (start, end: int, selected: bool) {
	start = min(ts.cursor, ts.selection_anchor)
	end = max(ts.cursor, ts.selection_anchor)
	selected = start != end
	return
}

selected_text :: proc(buf: []u8, ts: ^Text_Input_State) -> (string, bool) {
	start, end, selected := text_selection_bounds(ts)
	start = clamp(start, 0, len(buf))
	end = clamp(end, start, len(buf))
	if !selected || start == end {
		return "", false
	}
	return string(buf[start:end]), true
}

delete_text_selection :: proc(buf: ^[dynamic]u8, ts: ^Text_Input_State) -> bool {
	start, end, selected := text_selection_bounds(ts)
	if !selected {
		return false
	}
	for _ in start..<end {
		ordered_remove(buf, start)
	}
	ts.cursor = start
	ts.selection_anchor = start
	return true
}

text_input_hit_cursor :: proc(
	mgr: ^Manager,
	text: string,
	multiline: bool,
	font: Font_Handle,
	scale: f32,
	rect: Rect,
	padding: [4]f32,
	scroll_x, scroll_y: f32,
	mouse_x, mouse_y: f32,
) -> int {
	content_x := rect.x + padding[3]
	content_y := rect.y + padding[0]
	if !multiline {
		rel_x := mouse_x - content_x + scroll_x
		return hit_test_text(mgr, text, rel_x, font, scale)
	}

	line_h := get_line_height(mgr, font, scale)
	rel_x := mouse_x - content_x
	rel_y := mouse_y - content_y + scroll_y
	target_line := max(0, int(rel_y / line_h))
	line := 0
	line_start := 0
	for i in 0..<len(text) {
		if text[i] != '\n' {
			continue
		}
		if line == target_line {
			return line_start + hit_test_text(mgr, text[line_start:i], rel_x, font, scale)
		}
		line += 1
		line_start = i + 1
	}
	if line == target_line {
		return line_start + hit_test_text(mgr, text[line_start:], rel_x, font, scale)
	}
	return len(text)
}

insert_text_at_cursor :: proc(buf: ^[dynamic]u8, cursor: ^int, text: string, multiline: bool) {
	for ch in transmute([]u8)text {
		if ch == 0 || ch == '\r' {
			continue
		}
		if ch == '\n' && !multiline {
			continue
		}
		if ch < 32 && !(multiline && ch == '\n') {
			continue
		}

		if cursor^ >= len(buf^) {
			append(buf, ch)
		} else {
			inject_at(buf, cursor^, ch)
		}
		cursor^ += 1
	}
}

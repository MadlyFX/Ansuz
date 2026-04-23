package ansuz

// --- Text Input Widget ---
// Editable text field with single-line and multi-line modes.
// The user passes a ^[dynamic]u8 buffer; the widget reads/writes it.
// Cursor position and scroll state are tracked internally by the manager.

Text_Input_State :: struct {
	cursor:   int,    // cursor byte position in the buffer
	scroll_x: f32,   // horizontal scroll offset (single-line)
	scroll_y: f32,   // vertical scroll offset (multiline)
}

THEME_TEXTINPUT_BG           :: Color{35, 38, 45, 255}
THEME_TEXTINPUT_FOCUS_BORDER :: Color{80, 140, 220, 255}

text_input :: proc(
	mgr:         ^Manager,
	buf:         ^[dynamic]u8,
	multiline:   bool         = false,
	font:        Font_Handle,
	scale:       f32          = DEFAULT_FONT_SCALE,
	size:        [2]Size_Spec = FIXED_200_FIT,
	padding:     [4]f32       = {6, 8, 6, 8},
	placeholder: string       = "",
	loc          := #caller_location,
	color: Widget_Color = Widget_Color{
		bg    = THEME_TEXTINPUT_BG,
		fg    = THEME_TEXT,
		hover = THEME_TEXTINPUT_FOCUS_BORDER,
		focus = THEME_TEXTINPUT_FOCUS_BORDER,
	},
	label_color: Label_Color = Label_Color{label = THEME_TEXT},
) -> (Interaction, ^Text_Input_State) {
	id := id_from_ptr_loc(&mgr.id_stack, buf, loc)

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
		mgr.text_states[id] = Text_Input_State{cursor = len(buf^)}
	}
	ts := &mgr.text_states[id]

	// Click to position cursor (using prev_rect from last frame)
	if mgr.input.mouse_left_pressed && is_focused && prev_rect.w > 0 {
		cr_x := prev_rect.x + padding[3]
		cr_y := prev_rect.y + padding[0]
		line_h := get_line_height(mgr, font, scale)

		if !multiline {
			rel_x := mgr.input.mouse_x - cr_x - ts.scroll_x
			ts.cursor = hit_test_text(mgr, string(buf^[:]), rel_x, font, scale)
		} else {
			rel_x := mgr.input.mouse_x - cr_x
			rel_y := mgr.input.mouse_y - cr_y + ts.scroll_y
			target_line := max(0, int(rel_y / line_h))

			line := 0
			line_start := 0
			found := false
			for i in 0..<len(buf^) {
				if buf^[i] == '\n' {
					if line == target_line {
						line_text := string(buf^[line_start:i])
						ts.cursor = line_start + hit_test_text(mgr, line_text, rel_x, font, scale)
						found = true
						break
					}
					line += 1
					line_start = i + 1
				}
			}
			if !found {
				line_text := string(buf^[line_start:])
				if line == target_line {
					ts.cursor = line_start + hit_test_text(mgr, line_text, rel_x, font, scale)
				} else {
					ts.cursor = len(buf^)
				}
			}
		}
	}

	// Handle keyboard input when focused
	if is_focused {
		// Insert typed characters
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

		// Backspace
		if mgr.input.key_backspace && ts.cursor > 0 {
			ts.cursor -= 1
			ordered_remove(buf, ts.cursor)
		}

		// Delete
		if mgr.input.key_delete && ts.cursor < len(buf^) {
			ordered_remove(buf, ts.cursor)
		}

		// Arrow keys
		if mgr.input.key_left && ts.cursor > 0 {
			ts.cursor -= 1
		}
		if mgr.input.key_right && ts.cursor < len(buf^) {
			ts.cursor += 1
		}

		// Home
		if mgr.input.key_home {
			if multiline {
				pos := ts.cursor - 1
				for pos >= 0 && buf^[pos] != '\n' { pos -= 1 }
				ts.cursor = pos + 1
			} else {
				ts.cursor = 0
			}
		}

		// End
		if mgr.input.key_end {
			if multiline {
				pos := ts.cursor
				for pos < len(buf^) && buf^[pos] != '\n' { pos += 1 }
				ts.cursor = pos
			} else {
				ts.cursor = len(buf^)
			}
		}

		// Enter for multiline
		if multiline && mgr.input.key_enter {
			if ts.cursor >= len(buf^) {
				append(buf, '\n')
			} else {
				inject_at(buf, ts.cursor, u8('\n'))
			}
			ts.cursor += 1
		}

		// Up/Down for multiline
		if multiline {
			if mgr.input.key_up {
				col := 0
				pos := ts.cursor - 1
				for pos >= 0 && buf^[pos] != '\n' {
					col += 1
					pos -= 1
				}
				if pos >= 0 {
					prev_end := pos
					pos -= 1
					for pos >= 0 && buf^[pos] != '\n' { pos -= 1 }
					prev_start := pos + 1
					prev_len := prev_end - prev_start
					ts.cursor = prev_start + min(col, prev_len)
				}
			}
			if mgr.input.key_down {
				col := 0
				pos := ts.cursor - 1
				for pos >= 0 && buf^[pos] != '\n' {
					col += 1
					pos -= 1
				}
				pos = ts.cursor
				for pos < len(buf^) && buf^[pos] != '\n' { pos += 1 }
				if pos < len(buf^) {
					next_start := pos + 1
					next_end := next_start
					for next_end < len(buf^) && buf^[next_end] != '\n' { next_end += 1 }
					next_len := next_end - next_start
					ts.cursor = next_start + min(col, next_len)
				}
			}
		}
	}

	// Clamp cursor
	ts.cursor = clamp(ts.cursor, 0, len(buf^))

	// Auto-scroll for single-line: keep cursor visible within the content area
	if !multiline && prev_rect.w > 0 {
		viewport_w := prev_rect.w - padding[1] - padding[3]
		if viewport_w > 0 {
			cursor_px := measure_text_prefix(mgr, string(buf^[:]), ts.cursor, font, scale)
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
		line_h := get_line_height(mgr, font, scale)
		// Find cursor line
		cursor_line := 0
		for i in 0..<ts.cursor {
			if i < len(buf^) && buf^[i] == '\n' {
				cursor_line += 1
			}
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
		}
		ts.scroll_y = max(ts.scroll_y, 0)
	}

	// Visual styling
	//hover_t := get_hover_t(mgr, id, .Hovered in interaction)
	focus_t := get_focus_t(mgr, id, is_focused)
	border := color_lerp(THEME_BORDER, color.focus, focus_t)

	// Display text (show placeholder if buffer is empty)
	display_text := string(buf^[:]) if len(buf^) > 0 else placeholder
	text_color := label_color.label if len(buf^) > 0 else label_color.label / COLOR_DIM
	// Compute size
	actual_size := size
	line_h := get_line_height(mgr, font, scale)
	if !multiline {
		if actual_size[1].kind == .Fit {
			actual_size[1] = size_fixed(line_h + padding[0] + padding[2])
		}
	} else {
		if actual_size[1].kind == .Fit {
			line_count := 1
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
		color     = text_color,
		scale     = scale,
		font      = font,
		center_h  = false,
		center_v  = !multiline,
		clip      = true,
		offset_x  = -ts.scroll_x if !multiline else 0,
		offset_y  = -ts.scroll_y if multiline else 0,
	})

	// Defer cursor drawing if focused
	if is_focused {
		append(&mgr.deferred_draws, Deferred_Draw{
			box_index   = idx,
			kind        = .Text_Cursor,
			scale       = scale,
			text_cursor = Deferred_Text_Cursor_Data{
				cursor_pos = ts.cursor,
				multiline  = multiline,
				text       = string(buf^[:]),
				font       = font,
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

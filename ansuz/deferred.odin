package ansuz

// --- Deferred Draw System ---
// Custom draw operations that are resolved after layout (box rects are known).
// Used by widgets that need custom rendering beyond simple rects and text.

Deferred_Draw_Kind :: enum {
	Slider,
	Checkmark,
	Dropdown_Arrow,
	Image,
	Text_Cursor,
	Scrollbar,
}

Deferred_Slider_Data :: struct {
	t:           f32,         // normalized position 0..1
	interaction: Interaction,
}

Deferred_Dropdown_Data :: struct {
	is_open: bool,
}

Deferred_Image_Data :: struct {
	handle: Image_Handle,
	tint:   Color,
}

Deferred_Text_Cursor_Data :: struct {
	cursor_pos: int,
	multiline:  bool,
	text:       string,   // reference to buffer contents for line/col calculation
	font:       Font_Handle,
	offset_x:   f32,      // horizontal scroll offset (single-line)
	offset_y:   f32,      // vertical scroll offset (multiline)
}

Deferred_Scrollbar_Data :: struct {
	offset_y:   f32,
	content_h:  f32,
	viewport_h: f32,
}

Deferred_Draw :: struct {
	box_index: int,
	kind:      Deferred_Draw_Kind,
	scale:     f32,   // overall scale factor for rendering (1.0 = default)
	slider:      Deferred_Slider_Data,
	dropdown:    Deferred_Dropdown_Data,
	image:       Deferred_Image_Data,
	text_cursor: Deferred_Text_Cursor_Data,
	scrollbar:   Deferred_Scrollbar_Data,
	color: 	 Widget_Color, 
}

// --- Popup Overlay System ---
// Popup content rendered on top of everything else after the main draw pass.

Popup_Draw_Kind :: enum {
	Dropdown_List,
}

Popup_Dropdown_Data :: struct {
	options:  []string,
	selected: ^int,
	owner_id: Widget_ID,
}

Popup_Draw :: struct {
	owner_box_index: int,
	kind:            Popup_Draw_Kind,
	dropdown_list:   Popup_Dropdown_Data,
}

// Emit deferred draw commands. Called from frame_end after layout.
emit_deferred_draws :: proc(mgr: ^Manager) {
	full_screen := Rect{0, 0, f32(mgr.backend.width), f32(mgr.backend.height)}
	needs_clip_reset := false
	for &dd in mgr.deferred_draws {
		b := &mgr.boxes[dd.box_index]
		r := b.computed_rect

		// Only push clip when the box is inside a clipping ancestor
		if b.is_clipped {
			push_clip(&mgr.draw_list, b.effective_clip)
			needs_clip_reset = true
		} else if needs_clip_reset {
			push_clip(&mgr.draw_list, full_screen)
			needs_clip_reset = false
		}

		s := dd.scale if dd.scale > 0 else 1.0

		switch dd.kind {
		case .Slider:
			emit_slider_draw(mgr, r, dd.slider, s, dd.color)

		case .Checkmark:
			emit_checkmark_draw(mgr, r, s)

		case .Dropdown_Arrow:
			emit_dropdown_arrow(mgr, r, dd.dropdown)

		case .Image:
			emit_image_draw(mgr, r, dd.image)

		case .Text_Cursor:
			cr := mgr.boxes[dd.box_index].content_rect
			emit_text_cursor_draw(mgr, cr, dd.text_cursor, s)

		case .Scrollbar:
			emit_scrollbar_draw(mgr, r, dd.scrollbar)
		}
	}
	if needs_clip_reset {
		push_clip(&mgr.draw_list, full_screen)
	}
}

emit_image_draw :: proc(mgr: ^Manager, rect: Rect, data: Deferred_Image_Data) {
	if data.handle.ptr == nil { return }
	append(&mgr.draw_list.commands, Draw_Command(Draw_Image{
		rect   = rect,
		handle = data.handle.ptr,
		tint   = data.tint,
	}))
}

emit_slider_draw :: proc(mgr: ^Manager, rect: Rect, data: Deferred_Slider_Data, scale: f32 = 1.0, color: Widget_Color) {
	track_h  := SLIDER_TRACK_HEIGHT * scale
	thumb_w  := SLIDER_THUMB_WIDTH * scale
	thumb_h  := SLIDER_THUMB_HEIGHT * scale
	pad      := 4 * scale
	radius   := 3 * scale

	// Track background
	track_y := rect.y + (rect.h - track_h) / 2
	track_rect := Rect{rect.x + pad, track_y, rect.w - pad * 2, track_h}
	push_filled_rect(&mgr.draw_list, track_rect, color.bg, radius)

	// Fill (left of thumb)
	usable_w := rect.w - thumb_w
	thumb_x := rect.x + thumb_w / 2 + usable_w * data.t - thumb_w / 2

	if data.t > 0 {
		fill_color := color.hover if .Hovered in data.interaction else color.fg
		fill_w := (thumb_x + thumb_w / 2) - (rect.x + pad)
		if fill_w > 0 {
			fill_rect := Rect{rect.x + pad, track_y, fill_w, track_h}
			push_filled_rect(&mgr.draw_list, fill_rect, fill_color, radius)
		}
	}

	// Thumb
	thumb_color := color.press if .Pressed in data.interaction else color.focus
	thumb_y := rect.y + (rect.h - thumb_h) / 2
	thumb_rect := Rect{thumb_x, thumb_y, thumb_w, thumb_h}
	push_filled_rect(&mgr.draw_list, thumb_rect, thumb_color, radius + 1)
}

emit_checkmark_draw :: proc(mgr: ^Manager, rect: Rect, scale: f32 = 1.0) {
	// Draw a simple checkmark using two lines inside the box
	// Auto-scales to box size; line thickness scales with the scale parameter
	cx := rect.x + rect.w * 0.5
	cy := rect.y + rect.h * 0.5
	s := min(rect.w, rect.h) * 0.3

	// Checkmark: two line segments  \/
	p1 := Vec2{cx - s, cy}
	p2 := Vec2{cx - s * 0.3, cy + s * 0.7}
	p3 := Vec2{cx + s, cy - s * 0.6}

	thickness := max(1, 2.5 * scale)
	push_line(&mgr.draw_list, p1, p2, THEME_CHECKBOX_CHECK_MARK, thickness)
	push_line(&mgr.draw_list, p2, p3, THEME_CHECKBOX_CHECK_MARK, thickness)
}

emit_dropdown_arrow :: proc(mgr: ^Manager, rect: Rect, data: Deferred_Dropdown_Data) {
	// Draw a small triangle arrow on the right side of the dropdown
	arrow_x := rect.x + rect.w - 20
	arrow_y := rect.y + rect.h / 2
	s := f32(4)

	if data.is_open {
		// Up arrow  ^
		p1 := Vec2{arrow_x - s, arrow_y + s * 0.5}
		p2 := Vec2{arrow_x,     arrow_y - s * 0.5}
		p3 := Vec2{arrow_x + s, arrow_y + s * 0.5}
		push_line(&mgr.draw_list, p1, p2, THEME_DROPDOWN_ARROW, 2)
		push_line(&mgr.draw_list, p2, p3, THEME_DROPDOWN_ARROW, 2)
	} else {
		// Down arrow  v
		p1 := Vec2{arrow_x - s, arrow_y - s * 0.5}
		p2 := Vec2{arrow_x,     arrow_y + s * 0.5}
		p3 := Vec2{arrow_x + s, arrow_y - s * 0.5}
		push_line(&mgr.draw_list, p1, p2, THEME_DROPDOWN_ARROW, 2)
		push_line(&mgr.draw_list, p2, p3, THEME_DROPDOWN_ARROW, 2)
	}
}

// Emit popup overlay draws. Called from frame_end after all main draws.
emit_popup_draws :: proc(mgr: ^Manager) {
	for &pd in mgr.popup_draws {
		owner_rect := mgr.boxes[pd.owner_box_index].computed_rect

		switch pd.kind {
		case .Dropdown_List:
			emit_dropdown_list(mgr, owner_rect, pd.dropdown_list)
		}
	}
}

emit_dropdown_list :: proc(mgr: ^Manager, anchor: Rect, data: Popup_Dropdown_Data) {
	item_h := f32(28)
	list_h := f32(len(data.options)) * item_h
	list_rect := Rect{anchor.x, anchor.y + anchor.h, anchor.w, list_h}

	// Background
	push_filled_rect(&mgr.draw_list, list_rect, Color{45, 48, 55, 245}, 0)
	push_rect_outline(&mgr.draw_list, list_rect, THEME_BORDER, 1, 0)

	// Items
	for opt, i in data.options {
		item_y := list_rect.y + f32(i) * item_h
		item_rect := Rect{list_rect.x, item_y, list_rect.w, item_h}

		mouse_over := rect_contains(item_rect, mgr.input.mouse_x, mgr.input.mouse_y)

		// Highlight hovered item
		if mouse_over {
			push_filled_rect(&mgr.draw_list, item_rect, THEME_DROPDOWN_ITEM_HOVER, 0)
		}

		// Selected indicator
		if i == data.selected^ {
			push_filled_rect(&mgr.draw_list, Rect{item_rect.x, item_y, 3, item_h}, THEME_SLIDER_FILL, 0)
		}

		// Item text
		text_dims := measure_text(mgr, opt, mgr.default_font, DEFAULT_FONT_SCALE)
		eff_scale := get_effective_scale(mgr, mgr.default_font, DEFAULT_FONT_SCALE)
		tx := item_rect.x + 10
		ty := item_rect.y + (item_h - text_dims.y) / 2
		push_text(&mgr.draw_list, {tx, ty}, opt, THEME_TEXT, mgr.default_font, eff_scale)

		// Click to select
		if mouse_over && mgr.input.mouse_left {
			data.selected^ = i
			mgr.popup_owner = ID_NONE
			mgr.popup_block = true  // block widgets until mouse released
		}
	}
}

// --- Text Cursor ---

THEME_TEXTINPUT_CURSOR :: Color{200, 210, 230, 255}

emit_text_cursor_draw :: proc(mgr: ^Manager, cr: Rect, data: Deferred_Text_Cursor_Data, scale: f32) {
	// Blink cursor (~0.5s on, ~0.5s off)
	if (mgr.frame_id / 30) % 2 != 0 { return }

	line_h := get_line_height(mgr, data.font, scale)

	cursor_x := cr.x
	cursor_y := cr.y

	if data.multiline {
		// Find the line and line-start of the cursor position
		line := 0
		line_start := 0
		text_len := len(data.text)
		for i in 0..<min(data.cursor_pos, text_len) {
			if data.text[i] == '\n' {
				line += 1
				line_start = i + 1
			}
		}
		prefix_len := data.cursor_pos - line_start
		cursor_x = cr.x + measure_text_prefix(mgr, data.text[line_start:], prefix_len, data.font, scale)
		cursor_y = cr.y + f32(line) * line_h + data.offset_y
	} else {
		cursor_x = cr.x + measure_text_prefix(mgr, data.text, data.cursor_pos, data.font, scale) + data.offset_x
		cursor_y = cr.y + (cr.h - line_h) / 2
	}

	thickness := max(1, 2 * (scale / DEFAULT_FONT_SCALE))
	push_filled_rect(&mgr.draw_list, Rect{cursor_x, cursor_y, thickness, line_h}, THEME_TEXTINPUT_CURSOR)
}

// --- Scrollbar ---

emit_scrollbar_draw :: proc(mgr: ^Manager, rect: Rect, data: Deferred_Scrollbar_Data) {
	if data.content_h <= 0 || data.viewport_h <= 0 { return }

	bar_w := SCROLLBAR_WIDTH
	track_rect := Rect{
		rect.x + rect.w - bar_w - 2,
		rect.y + 2,
		bar_w,
		rect.h - 4,
	}

	// Track background
	push_filled_rect(&mgr.draw_list, track_rect, THEME_SCROLLBAR_BG, bar_w / 2)

	// Thumb
	ratio := data.viewport_h / data.content_h
	thumb_h := max(20, track_rect.h * ratio)
	max_scroll := data.content_h - data.viewport_h
	scroll_ratio := data.offset_y / max_scroll if max_scroll > 0 else 0
	thumb_y := track_rect.y + (track_rect.h - thumb_h) * scroll_ratio

	thumb_rect := Rect{track_rect.x, thumb_y, bar_w, thumb_h}
	push_filled_rect(&mgr.draw_list, thumb_rect, THEME_SCROLLBAR_THUMB, bar_w / 2)
}

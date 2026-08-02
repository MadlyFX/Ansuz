package ansuz

// --- Deferred Draw System ---
// Custom draw operations that are resolved after layout (box rects are known).
// Used by widgets that need custom rendering beyond simple rects and text.

Deferred_Draw_Kind :: enum {
	Slider,
	Checkmark,
	Dropdown_Arrow,
	Disclosure_Icon,
	Hamburger_Icon,
	Window_Icon,
	Image,
	Text_Cursor,
	Scrollbar,
}

// Native window-control glyphs for a custom (client-drawn) title bar.
Window_Icon_Glyph :: enum {
	Minimize,
	Maximize,
	Restore,
	Close,
}

Deferred_Window_Icon_Data :: struct {
	glyph: Window_Icon_Glyph,
	color: Color,
}

Deferred_Slider_Data :: struct {
	t:           f32,         // normalized position 0..1
	interaction: Interaction,
}

Deferred_Checkmark_Data :: struct {
	color: Color,
}

Deferred_Dropdown_Data :: struct {
	is_open: bool,
	color:   Color,
}

Deferred_Disclosure_Data :: struct {
	expanded: bool,
	color:    Color,
}

Deferred_Hamburger_Data :: struct {
	color: Color,
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
	color:      Color,
	offset_x:   f32,      // horizontal scroll offset (single-line)
	offset_y:   f32,      // vertical scroll offset (multiline)
}

Deferred_Scrollbar_Data :: struct {
	axis:     Axis,
	offset:   f32,
	content:  f32,
	viewport: f32,
	width:    f32,
	inset:    f32,
	// bg is the track, fg the thumb; hover and press are the thumb's states under
	// the pointer (see scroll_begin, which does the hit testing).
	color:    Widget_Color,
	hovered:  bool,
	active:   bool,
}

Deferred_Draw :: struct {
	box_index: int,
	kind:      Deferred_Draw_Kind,
	scale:     f32,   // overall scale factor for rendering (1.0 = default)
	slider:      Deferred_Slider_Data,
	checkmark:   Deferred_Checkmark_Data,
	dropdown:    Deferred_Dropdown_Data,
	disclosure:  Deferred_Disclosure_Data,
	hamburger:   Deferred_Hamburger_Data,
	window_icon: Deferred_Window_Icon_Data,
	image:       Deferred_Image_Data,
	text_cursor: Deferred_Text_Cursor_Data,
	scrollbar:   Deferred_Scrollbar_Data,
	color:       Widget_Color,
}

// --- Popup Overlay System ---
// Popup content rendered on top of everything else after the main draw pass.

Popup_Draw_Kind :: enum {
	Dropdown_List,
	Menu_List,
}

Popup_Dropdown_Data :: struct {
	options:  []string,
	selected: ^int,
	owner_id: Widget_ID,
	font:               Font_Handle,
	scale:              f32,
	item_height:        f32,
	text_color:         Color,
	popup_color:        Color,
	popup_border_color: Color,
	item_hover_color:   Color,
	selected_color:     Color,
	max_popup_height:   f32,
}

Popup_Menu_Data :: struct {
	options:  []string,
	selected: ^int,
	owner_id: Widget_ID,
	font:               Font_Handle,
	scale:              f32,
	item_height:        f32,
	width:              f32,
	text_color:         Color,
	popup_color:        Color,
	popup_border_color: Color,
	item_hover_color:   Color,
}

Popup_Draw :: struct {
	owner_box_index: int,
	kind:            Popup_Draw_Kind,
	dropdown_list:   Popup_Dropdown_Data,
	menu_list:       Popup_Menu_Data,
}

// Emit deferred draw commands. Called from frame_end after layout.
emit_deferred_draws :: proc(mgr: ^Manager, floating: bool = false) {
	full_screen := Rect{0, 0, f32(mgr.backend.width), f32(mgr.backend.height)}
	needs_clip_reset := false
	for &dd in mgr.deferred_draws {
		if box_is_floating(mgr, dd.box_index) != floating {
			continue
		}
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
			emit_checkmark_draw(mgr, r, dd.checkmark, s)

		case .Dropdown_Arrow:
			emit_dropdown_arrow(mgr, r, dd.dropdown)

		case .Disclosure_Icon:
			emit_disclosure_icon(mgr, r, dd.disclosure, s)

		case .Hamburger_Icon:
			emit_hamburger_icon(mgr, r, dd.hamburger, s)

		case .Window_Icon:
			emit_window_icon(mgr, r, dd.window_icon, s)

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

emit_disclosure_icon :: proc(mgr: ^Manager, rect: Rect, data: Deferred_Disclosure_Data, scale: f32 = 1.0) {
	cx := rect.x + rect.w * 0.5
	cy := rect.y + rect.h * 0.5
	s := min(rect.w, rect.h) * 0.28
	thickness := max(1, 2 * scale)

	if data.expanded {
		p1 := Vec2{cx - s, cy - s * 0.45}
		p2 := Vec2{cx,     cy + s * 0.45}
		p3 := Vec2{cx + s, cy - s * 0.45}
		push_line(&mgr.draw_list, p1, p2, data.color, thickness)
		push_line(&mgr.draw_list, p2, p3, data.color, thickness)
	} else {
		p1 := Vec2{cx - s * 0.4, cy - s}
		p2 := Vec2{cx + s * 0.45, cy}
		p3 := Vec2{cx - s * 0.4, cy + s}
		push_line(&mgr.draw_list, p1, p2, data.color, thickness)
		push_line(&mgr.draw_list, p2, p3, data.color, thickness)
	}
}

emit_hamburger_icon :: proc(mgr: ^Manager, rect: Rect, data: Deferred_Hamburger_Data, scale: f32 = 1.0) {
	cx := rect.x + rect.w * 0.5
	cy := rect.y + rect.h * 0.5
	half_width := min(rect.w, rect.h) * 0.22
	line_gap := min(rect.w, rect.h) * 0.15
	thickness := max(f32(1.5), 2 * scale)
	offsets := [?]f32{-line_gap, 0, line_gap}
	for offset in offsets {
		push_line(
			&mgr.draw_list,
			Vec2{cx - half_width, cy + offset},
			Vec2{cx + half_width, cy + offset},
			data.color,
			thickness,
		)
	}
}

// Draw a native-style window control glyph (minimize / maximize / restore /
// close) centered in the button rect. Coordinates are pixel-snapped so the thin
// square outlines and strokes stay crisp at the physical resolution.
emit_window_icon :: proc(mgr: ^Manager, rect: Rect, data: Deferred_Window_Icon_Data, scale: f32 = 1.0) {
	// A ~10px glyph reads well against the 46x40 hit target used by the title bar.
	s := f32(int(min(rect.w, rect.h) * 0.26))
	if s < 5 {
		s = 5
	}
	cx := f32(int(rect.x + rect.w * 0.5))
	cy := f32(int(rect.y + rect.h * 0.5))
	thickness := max(f32(1), 1.3 * scale)

	switch data.glyph {
	case .Minimize:
		y := cy
		push_line(&mgr.draw_list, Vec2{cx - s, y}, Vec2{cx + s, y}, data.color, thickness)

	case .Maximize:
		push_rect_outline(&mgr.draw_list, Rect{cx - s, cy - s, s * 2, s * 2}, data.color, thickness)

	case .Restore:
		// Two overlapping square outlines, like the OS "restore down" glyph: a
		// back square offset up-and-right behind the front square.
		off := f32(int(s * 0.6))
		side := s * 2 - off
		push_rect_outline(&mgr.draw_list, Rect{cx - s + off, cy - s, side, side}, data.color, thickness)
		push_rect_outline(&mgr.draw_list, Rect{cx - s, cy - s + off, side, side}, data.color, thickness)

	case .Close:
		push_line(&mgr.draw_list, Vec2{cx - s, cy - s}, Vec2{cx + s, cy + s}, data.color, thickness)
		push_line(&mgr.draw_list, Vec2{cx - s, cy + s}, Vec2{cx + s, cy - s}, data.color, thickness)
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

emit_checkmark_draw :: proc(mgr: ^Manager, rect: Rect, data: Deferred_Checkmark_Data, scale: f32 = 1.0) {
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
	push_line(&mgr.draw_list, p1, p2, data.color, thickness)
	push_line(&mgr.draw_list, p2, p3, data.color, thickness)
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
		push_line(&mgr.draw_list, p1, p2, data.color, 2)
		push_line(&mgr.draw_list, p2, p3, data.color, 2)
	} else {
		// Down arrow  v
		p1 := Vec2{arrow_x - s, arrow_y - s * 0.5}
		p2 := Vec2{arrow_x,     arrow_y + s * 0.5}
		p3 := Vec2{arrow_x + s, arrow_y - s * 0.5}
		push_line(&mgr.draw_list, p1, p2, data.color, 2)
		push_line(&mgr.draw_list, p2, p3, data.color, 2)
	}
}

// Emit popup overlay draws. Called from frame_end after all main draws.
emit_popup_draws :: proc(mgr: ^Manager) {
	for &pd in mgr.popup_draws {
		owner_rect := mgr.boxes[pd.owner_box_index].computed_rect

		switch pd.kind {
		case .Dropdown_List:
			emit_dropdown_list(mgr, owner_rect, pd.dropdown_list)
		case .Menu_List:
			emit_menu_list(mgr, owner_rect, pd.menu_list)
		}
	}
}

emit_dropdown_list :: proc(mgr: ^Manager, anchor: Rect, data: Popup_Dropdown_Data) {
	item_h := data.item_height
	content_h := f32(len(data.options)) * item_h
	list_rect := dropdown_popup_rect(mgr, anchor, len(data.options), item_h, data.max_popup_height)
	list_h := list_rect.h
	scroll_offset := f32(0)
	if offset, ok := &mgr.dropdown_scroll_offsets[data.owner_id]; ok {
		offset^ = clamp(offset^, 0, max(0, content_h - list_h))
		scroll_offset = offset^
	}

	// Background
	push_filled_rect(&mgr.draw_list, list_rect, data.popup_color, 0)
	push_rect_outline(&mgr.draw_list, list_rect, data.popup_border_color, 1, 0)

	full_screen := Rect{0, 0, f32(mgr.backend.width), f32(mgr.backend.height)}
	push_clip(&mgr.draw_list, list_rect)

	// Items
	for opt, i in data.options {
		item_y := list_rect.y + f32(i) * item_h - scroll_offset
		item_rect := Rect{list_rect.x, item_y, list_rect.w, item_h}

		mouse_over := rect_contains(item_rect, mgr.input.mouse_x, mgr.input.mouse_y)

		// Highlight hovered item
		if mouse_over {
			push_filled_rect(&mgr.draw_list, item_rect, data.item_hover_color, 0)
		}

		// Selected indicator
		if i == data.selected^ {
			push_filled_rect(&mgr.draw_list, Rect{item_rect.x, item_y, 3, item_h}, data.selected_color, 0)
		}

		// Item text
		text_dims := measure_text(mgr, opt, data.font, data.scale)
		eff_scale := get_effective_scale(mgr, data.font, data.scale)
		tx := item_rect.x + 10
		ty := item_rect.y + (item_h - text_dims.y) / 2
		push_text(&mgr.draw_list, {tx, ty}, opt, data.text_color, data.font, eff_scale)

		// Click to select
		if mouse_over && mgr.input.mouse_left {
			data.selected^ = i
			mgr.popup_owner = ID_NONE
			mgr.popup_block = true  // block widgets until mouse released
		}
	}
	push_clip(&mgr.draw_list, full_screen)

	if content_h > list_h && list_h > 0 {
		track := Rect{list_rect.x + list_rect.w - DROPDOWN_SCROLLBAR_WIDTH, list_rect.y, DROPDOWN_SCROLLBAR_WIDTH, list_h}
		thumb_h := max(f32(20), list_h * list_h / content_h)
		max_offset := content_h - list_h
		thumb_y := track.y
		if max_offset > 0 {
			thumb_y += (scroll_offset / max_offset) * (track.h - thumb_h)
		}
		push_filled_rect(&mgr.draw_list, track, Color{0, 0, 0, 75}, 0)
		push_filled_rect(&mgr.draw_list, Rect{track.x, thumb_y, track.w, thumb_h}, THEME_DROPDOWN_ARROW, 2)
	}
}

emit_menu_list :: proc(mgr: ^Manager, anchor: Rect, data: Popup_Menu_Data) {
	item_h := data.item_height
	list_h := f32(len(data.options)) * item_h
	list_w := max(anchor.w, data.width)
	list_x := anchor.x + anchor.w - list_w
	list_rect := Rect{list_x, anchor.y + anchor.h, list_w, list_h}

	push_filled_rect(&mgr.draw_list, list_rect, data.popup_color, 0)
	push_rect_outline(&mgr.draw_list, list_rect, data.popup_border_color, 1, 0)

	for opt, i in data.options {
		item_y := list_rect.y + f32(i) * item_h
		item_rect := Rect{list_rect.x, item_y, list_rect.w, item_h}

		mouse_over := rect_contains(item_rect, mgr.input.mouse_x, mgr.input.mouse_y)
		if mouse_over {
			push_filled_rect(&mgr.draw_list, item_rect, data.item_hover_color, 0)
		}

		text_dims := measure_text(mgr, opt, data.font, data.scale)
		eff_scale := get_effective_scale(mgr, data.font, data.scale)
		tx := item_rect.x + 10
		ty := item_rect.y + (item_h - text_dims.y) / 2
		push_text(&mgr.draw_list, {tx, ty}, opt, data.text_color, data.font, eff_scale)

		if mouse_over && mgr.input.mouse_left {
			data.selected^ = i
			mgr.popup_owner = ID_NONE
			mgr.popup_block = true
		}
	}
}

// --- Text Cursor ---
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
	push_filled_rect(&mgr.draw_list, Rect{cursor_x, cursor_y, thickness, line_h}, data.color)
}

// --- Scrollbar ---

emit_scrollbar_draw :: proc(mgr: ^Manager, rect: Rect, data: Deferred_Scrollbar_Data) {
	if data.content <= 0 || data.viewport <= 0 { return }

	bar_w := data.width if data.width > 0 else SCROLLBAR_WIDTH
	track_rect, thumb_rect := scrollbar_rects(
		rect, data.axis, data.offset, data.content, data.viewport, bar_w, data.inset,
	)
	thumb_color := data.color.fg
	if data.active {
		thumb_color = data.color.press
	} else if data.hovered {
		thumb_color = data.color.hover
	}
	push_filled_rect(&mgr.draw_list, track_rect, data.color.bg, bar_w / 2)
	push_filled_rect(&mgr.draw_list, thumb_rect, thumb_color, bar_w / 2)
}

package ansuz

import "base:runtime"
import "core:strings"

// --- Styled text --------------------------------------------------------------
// A styled string is a sequence of spans, each carrying its own emphasis. This
// file turns those spans into positioned runs — one draw per contiguous
// same-style fragment of a line — so a paragraph can mix regular, bold, italic,
// struck-through and monospaced fragments and still wrap as a single block of
// prose. Callers hand the runs to styled_label; drawing happens in
// emit_deferred_texts alongside ordinary labels.
//
// The layout is deliberately kept here rather than in the app: wrapping needs
// per-glyph advances from the font atlas, and mixed faces need a shared
// baseline, both of which only this package can measure.

Text_Style_Flag :: enum u8 {
	Bold,
	Italic,
	Strike,
	Mono,
}

Text_Style :: bit_set[Text_Style_Flag]

// Styled_Span is one fragment of source text with a uniform style.
Styled_Span :: struct {
	text:  string,
	style: Text_Style,
}

// Style_Fonts names the face used for each emphasis combination. Entries left at
// FONT_BUILTIN fall back to a loaded relative (bold+italic → bold → regular), so
// a host that loaded only one face still renders readable — if unemphasized —
// text rather than nothing.
Style_Fonts :: struct {
	regular:     Font_Handle,
	bold:        Font_Handle,
	italic:      Font_Handle,
	bold_italic: Font_Handle,
	mono:        Font_Handle,
}

// Text_Run is one positioned fragment produced by layout_styled_text. `x` is
// relative to the text origin and `line` counts wrapped lines from it, so a
// caller only has to add the box's content origin at draw time. `y_offset` puts
// runs of different faces on one baseline (see layout_styled_text).
Text_Run :: struct {
	text:     string,
	font:     Font_Handle,
	style:    Text_Style,
	x:        f32,
	w:        f32,
	line:     int,
	y_offset: f32,
}

// style_font picks the face for a style, falling back through progressively
// plainer faces when the host did not load the exact one.
style_font :: proc(fonts: Style_Fonts, style: Text_Style) -> Font_Handle {
	pick :: proc(candidates: ..Font_Handle) -> Font_Handle {
		for c in candidates {
			if c != FONT_BUILTIN {
				return c
			}
		}
		return candidates[len(candidates) - 1]
	}
	if .Mono in style {
		return pick(fonts.mono, fonts.regular)
	}
	switch {
	case .Bold in style && .Italic in style:
		return pick(fonts.bold_italic, fonts.bold, fonts.italic, fonts.regular)
	case .Bold in style:
		return pick(fonts.bold, fonts.regular)
	case .Italic in style:
		return pick(fonts.italic, fonts.regular)
	}
	return fonts.regular
}

@(private = "file")
Token_Kind :: enum {
	Word,
	Space,
	Break,
}

@(private = "file")
Token :: struct {
	text:  string,
	style: Text_Style,
	font:  Font_Handle,
	width: f32,
	kind:  Token_Kind,
}

// Builder state for the run currently being accumulated. Adjacent same-style
// fragments on one line are merged into a single run so a paragraph costs a
// handful of draw calls rather than one per word.
@(private = "file")
Run_Builder :: struct {
	sb:     strings.Builder,
	style:  Text_Style,
	font:   Font_Handle,
	x:      f32,
	w:      f32,
	line:   int,
	active: bool,
}

// layout_styled_text wraps `spans` to `max_width` pixels and returns the runs to
// draw, how many lines they occupy, and the line height to advance by.
//
// Wrapping matches wrap_text_to_width's prose behaviour — greedy, breaking at
// spaces, collapsing runs of whitespace, hard-breaking a word wider than the
// column — with one addition: a "word" may span several styles (`**bo**ld` is
// one word), so a break is never taken in the middle of one just because the
// emphasis changed there. `max_width <= 0` lays everything out on one line,
// which is what the first frame of a SIZE_GROW column gets before its width is
// known.
//
// Line height and baseline come from the widest and tallest faces actually used,
// so an inline monospaced fragment cannot overlap the line above and every face
// sits on one baseline instead of hanging from a common top edge. The result is
// allocated with `allocator` (temp by default), so it lives until that resets.
layout_styled_text :: proc(
	mgr: ^Manager,
	spans: []Styled_Span,
	fonts: Style_Fonts,
	scale: f32,
	max_width: f32,
	allocator := context.temp_allocator,
) -> (
	runs: []Text_Run,
	lines: int,
	line_height: f32,
) {
	tokens := make([dynamic]Token, 0, 32, context.temp_allocator)
	for span in spans {
		font := style_font(fonts, span.style)
		text := span.text
		i := 0
		for i < len(text) {
			c := text[i]
			if c == '\n' {
				append(&tokens, Token{style = span.style, font = font, kind = .Break})
				i += 1
				continue
			}
			start := i
			if c == ' ' || c == '\t' {
				for i < len(text) && (text[i] == ' ' || text[i] == '\t') {
					i += 1
				}
				append(&tokens, Token{text = text[start:i], style = span.style, font = font, kind = .Space})
				continue
			}
			for i < len(text) && text[i] != ' ' && text[i] != '\t' && text[i] != '\n' {
				i += 1
			}
			word := text[start:i]
			append(
				&tokens,
				Token {
					text = word,
					style = span.style,
					font = font,
					width = measure_text(mgr, word, font, scale).x,
					kind = .Word,
				},
			)
		}
	}

	out := make([dynamic]Text_Run, 0, 8, allocator)
	// Each run is cloned out of the builder as it is flushed, so the scratch
	// buffer itself is not part of the result.
	rb := Run_Builder{sb = strings.builder_make(allocator)}
	defer strings.builder_destroy(&rb.sb)
	pen := f32(0)
	line := 0
	line_has_content := false
	pending_space := false
	pending_space_style := Text_Style{}
	pending_space_font := fonts.regular

	i := 0
	for i < len(tokens) {
		tok := tokens[i]
		switch tok.kind {
		case .Break:
			run_flush(&out, &rb, allocator)
			line += 1
			pen = 0
			line_has_content = false
			pending_space = false
			i += 1

		case .Space:
			// Whitespace is not placed where it is found: a run of it collapses to
			// one space, and a space at a wrap point disappears with the break.
			if line_has_content {
				pending_space = true
				pending_space_style = tok.style
				pending_space_font = tok.font
			}
			i += 1

		case .Word:
			// A word may continue across style changes, so measure the whole group
			// before deciding whether it fits.
			group_end := i
			group_w := f32(0)
			for group_end < len(tokens) && tokens[group_end].kind == .Word {
				group_w += tokens[group_end].width
				group_end += 1
			}
			space_w := f32(0)
			if pending_space {
				space_w = measure_text(mgr, " ", pending_space_font, scale).x
			}
			if max_width > 0 && line_has_content && pen + space_w + group_w > max_width {
				run_flush(&out, &rb, allocator)
				line += 1
				pen = 0
				line_has_content = false
				pending_space = false
				space_w = 0
			}
			if pending_space {
				run_place(&out, &rb, allocator, " ", pending_space_style, pending_space_font, space_w, &pen, line)
				pending_space = false
			}
			if max_width > 0 && group_w > max_width {
				// Wider than the whole column even on its own line (a long URL):
				// break it between glyphs, which is the only place left to break.
				for k in i ..< group_end {
					word := tokens[k]
					for r in word.text {
						rw := measure_rune(mgr, r, word.font, scale)
						if pen + rw > max_width && line_has_content {
							run_flush(&out, &rb, allocator)
							line += 1
							pen = 0
							line_has_content = false
						}
						run_place(
							&out,
							&rb,
							allocator,
							rune_string(r, context.temp_allocator),
							word.style,
							word.font,
							rw,
							&pen,
							line,
						)
						line_has_content = true
					}
				}
			} else {
				for k in i ..< group_end {
					word := tokens[k]
					run_place(&out, &rb, allocator, word.text, word.style, word.font, word.width, &pen, line)
				}
				line_has_content = true
			}
			i = group_end
		}
	}
	run_flush(&out, &rb, allocator)

	// Height and baseline follow the faces that were actually used: a line of
	// plain prose keeps the plain line height even when the note elsewhere
	// carries a taller monospaced fragment on its own line.
	baseline := f32(0)
	line_height = 0
	for run in out {
		baseline = max(baseline, get_ascent(mgr, run.font, scale))
		line_height = max(line_height, get_line_height(mgr, run.font, scale))
	}
	if line_height == 0 {
		line_height = get_line_height(mgr, fonts.regular, scale)
	}
	for &run in out {
		run.y_offset = baseline - get_ascent(mgr, run.font, scale)
	}
	return out[:], line + 1, line_height
}

// destroy_styled_runs frees a layout made with a non-temporary allocator. The
// UI path lays out into temp memory each frame and does not need it.
destroy_styled_runs :: proc(runs: []Text_Run, allocator := context.allocator) {
	for run in runs {
		delete(run.text, allocator)
	}
	delete(runs, allocator)
}

// styled_runs_size returns the pixel size of a laid-out block, for a caller that
// needs to size a box around it.
styled_runs_size :: proc(runs: []Text_Run, lines: int, line_height: f32) -> Vec2 {
	width := f32(0)
	for run in runs {
		width = max(width, run.x + run.w)
	}
	return {width, f32(max(lines, 1)) * line_height}
}

@(private = "file")
run_place :: proc(
	out: ^[dynamic]Text_Run,
	rb: ^Run_Builder,
	allocator: runtime.Allocator,
	text: string,
	style: Text_Style,
	font: Font_Handle,
	width: f32,
	pen: ^f32,
	line: int,
) {
	if rb.active && (rb.style != style || rb.font != font || rb.line != line) {
		run_flush(out, rb, allocator)
	}
	if !rb.active {
		rb.style = style
		rb.font = font
		rb.x = pen^
		rb.w = 0
		rb.line = line
		rb.active = true
	}
	strings.write_string(&rb.sb, text)
	rb.w += width
	pen^ += width
}

@(private = "file")
run_flush :: proc(out: ^[dynamic]Text_Run, rb: ^Run_Builder, allocator: runtime.Allocator) {
	if !rb.active {
		return
	}
	if strings.builder_len(rb.sb) > 0 {
		append(
			out,
			Text_Run {
				text = strings.clone(strings.to_string(rb.sb), allocator),
				font = rb.font,
				style = rb.style,
				x = rb.x,
				w = rb.w,
				line = rb.line,
			},
		)
	}
	strings.builder_reset(&rb.sb)
	rb.active = false
}

@(private = "file")
rune_string :: proc(r: rune, allocator: runtime.Allocator) -> string {
	sb := strings.builder_make(allocator)
	strings.write_rune(&sb, r)
	return strings.to_string(sb)
}

// --- Styled label -------------------------------------------------------------

// styled_label displays pre-laid-out runs (see layout_styled_text). It is the
// rich-text counterpart of label: same sizing and padding rules, but the text is
// drawn run by run so emphasis, strikethrough and inline code survive. No
// interaction — an editable note swaps back to a plain text input on its raw
// Markdown.
styled_label :: proc(
	mgr: ^Manager,
	runs: []Text_Run,
	lines: int,
	line_height: f32,
	scale: f32 = DEFAULT_FONT_SCALE,
	color: Color = THEME_TEXT,
	bg_color: Color = COLOR_TRANSPARENT,
	code_color: Color = COLOR_TRANSPARENT,
	size: [2]Size_Spec = SIZE_FIT_FIT,
	padding: [4]f32 = {2, 4, 2, 4},
	clip: bool = false,
	loc := #caller_location,
) -> int {
	actual_size := size
	dims := styled_runs_size(runs, lines, line_height)
	if actual_size[0].kind == .Fit {
		actual_size[0] = size_fixed(dims.x + padding[1] + padding[3])
	}
	if actual_size[1].kind == .Fit {
		actual_size[1] = size_fixed(dims.y + padding[0] + padding[2])
	}

	idx := box(mgr, size = actual_size, loc = loc, bg_color = bg_color)
	mgr.boxes[idx].padding = padding

	append(
		&mgr.deferred_texts,
		Deferred_Text {
			box_index = idx,
			color = color,
			scale = scale,
			font = runs[0].font if len(runs) > 0 else FONT_DEFAULT,
			center_v = true,
			clip = clip,
			runs = runs,
			run_lines = lines,
			run_line_height = line_height,
			code_color = code_color,
		},
	)
	return idx
}

// emit_styled_runs draws one laid-out block at `origin` (the top-left of its
// first line): the inline-code chip first, then the glyphs, then the
// strikethrough rule, so each decoration lands over the right pixels.
emit_styled_runs :: proc(mgr: ^Manager, dt: Deferred_Text, origin: Vec2) {
	line_h := dt.run_line_height
	for run in dt.runs {
		x := origin.x + run.x
		top := origin.y + f32(run.line) * line_h
		if .Mono in run.style && dt.code_color.a > 0 {
			push_filled_rect(
				&mgr.draw_list,
				Rect{x - 2, top + 1, run.w + 4, max(1, line_h - 2)},
				dt.code_color,
				3,
			)
		}
		eff_scale := get_effective_scale(mgr, run.font, dt.scale)
		push_text(&mgr.draw_list, {x, top + run.y_offset}, run.text, dt.color, run.font, eff_scale)
		if .Strike in run.style {
			// Roughly mid x-height: high enough to read as a strike, low enough not
			// to collide with the tops of lowercase letters.
			ascent := get_ascent(mgr, run.font, dt.scale)
			y := top + run.y_offset + ascent * 0.7
			thickness := max(1, line_h * 0.06)
			push_filled_rect(&mgr.draw_list, Rect{x, y, run.w, thickness}, dt.color)
		}
	}
}

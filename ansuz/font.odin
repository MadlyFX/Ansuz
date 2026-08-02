package ansuz

import "core:strings"
import "core:unicode/utf8"

// --- Font System ---
// Supports both the built-in 5x7 bitmap font and loaded TrueType font atlases.
// TTF fonts are rasterized into a grayscale atlas at load time using stb_truetype.
// Scale normalization maps widget scale values (designed for the bitmap font) to
// equivalent visual sizes for TTF fonts.

Font_Antialiasing :: enum {
	None,
	Grayscale,
}

FONT_TTF_OVERSAMPLE_X :: 1
FONT_TTF_OVERSAMPLE_Y :: 1
FONT_TTF_ATLAS_PADDING :: 2

Font_Glyph_Info :: struct {
	atlas_x:  u16,    // X position in atlas texture
	atlas_y:  u16,    // Y position in atlas texture
	atlas_w:  u16,    // Width in atlas texture
	atlas_h:  u16,    // Height in atlas texture
	x_offset: f32,    // Horizontal offset when rendering
	y_offset: f32,    // Vertical offset from baseline
	x_offset2: f32,   // Horizontal end offset when rendering
	y_offset2: f32,   // Vertical end offset from baseline
	advance:  f32,    // Horizontal advance to next character
}

Font :: struct {
	pixel_size:    f32,           // Size the font was rasterized at
	atlas_width:   i32,
	atlas_height:  i32,
	atlas_pixels:  []u8,          // Grayscale alpha coverage values (for GPU upload)
	glyphs:        [256]Font_Glyph_Info,
	glyphs_unicode: map[rune]Font_Glyph_Info, // Overflow for codepoints > 255
	line_height:   f32,           // Line height at native pixel_size
	ascent:        f32,           // Ascent at native pixel_size
	scale_norm:    f32,           // Normalization: FONT_GLYPH_HEIGHT / pixel_size
	antialiasing:  Font_Antialiasing,
	oversample_x:  u8,
	oversample_y:  u8,
}

// Common Unicode codepoints to bake when loading a TTF font.
// Pass FONT_EXTRA_CODEPOINTS[:] to load_font to include these.
@(rodata)
FONT_EXTRA_CODEPOINTS := [?]rune{
	0x2022, // • BULLET
	0x25E6, // ◦ WHITE BULLET
	0x2026, // … HORIZONTAL ELLIPSIS
	0x2013, // – EN DASH
	0x2014, // — EM DASH
	0x2713, // ✓ CHECK MARK
	0x2717, // ✗ BALLOT X
	0x25B8, // ▸ BLACK RIGHT-POINTING SMALL TRIANGLE
	0x25B9, // ▹ WHITE RIGHT-POINTING SMALL TRIANGLE
	0x25BE, // ▾ BLACK DOWN-POINTING SMALL TRIANGLE
	0x2190, // ← LEFT ARROW
	0x2191, // ↑ UP ARROW
	0x2192, // → RIGHT ARROW
	0x2193, // ↓ DOWN ARROW
	0x201C, // " LEFT DOUBLE QUOTATION MARK
	0x201D, // " RIGHT DOUBLE QUOTATION MARK
}

// Look up glyph info for a rune, checking the unicode overflow map for codepoints > 255.
font_atlas_glyph :: proc(font: ^Font, ch: rune) -> Font_Glyph_Info {
	if int(ch) < 256 {
		return font.glyphs[int(ch)]
	}
	if g, ok := font.glyphs_unicode[ch]; ok {
		return g
	}
	return font.glyphs[int('?')]
}

FONT_BUILTIN :: Font_Handle(0)
FONT_DEFAULT :: Font_Handle(0xffffffff)

// Resolve an optional widget font override. FONT_DEFAULT means "use the
// manager's configured default"; FONT_BUILTIN remains an explicit bitmap font.
resolve_font :: proc(mgr: ^Manager, font: Font_Handle = FONT_DEFAULT) -> Font_Handle {
	if font == FONT_DEFAULT {
		return mgr.default_font
	}
	return font
}

// Measure text using the specified font, handling scale normalization for TTF fonts.
measure_text :: proc(mgr: ^Manager, text: string, font: Font_Handle, scale: f32) -> Vec2 {
	effective_font := resolve_font(mgr, font)
	if effective_font == FONT_BUILTIN || len(mgr.fonts) == 0 || int(effective_font) - 1 >= len(mgr.fonts) {
		return measure_text_builtin(text, scale)
	}
	f := &mgr.fonts[int(effective_font) - 1]
	return measure_text_atlas(text, f, scale * f.scale_norm)
}

// Measure text using per-glyph advance widths from a TTF font atlas.
measure_text_atlas :: proc(text: string, font: ^Font, effective_scale: f32) -> Vec2 {
	if len(text) == 0 { return {0, 0} }

	max_width: f32 = 0
	cur_width: f32 = 0
	lines := 1

	for ch in text {
		if ch == '\n' {
			max_width = max(max_width, cur_width)
			cur_width = 0
			lines += 1
			continue
		}

		cur_width += font_atlas_glyph(font, ch).advance * effective_scale
	}

	max_width = max(max_width, cur_width)
	return {max_width, font.line_height * effective_scale * f32(lines)}
}

// Measure the advance width in pixels of a single rune for the given font/scale.
measure_rune :: proc(mgr: ^Manager, r: rune, font: Font_Handle, scale: f32) -> f32 {
	effective_font := resolve_font(mgr, font)
	if effective_font == FONT_BUILTIN || len(mgr.fonts) == 0 || int(effective_font) - 1 >= len(mgr.fonts) {
		return f32(FONT_CHAR_WIDTH) * builtin_scale(scale)
	}
	f := &mgr.fonts[int(effective_font) - 1]
	return font_atlas_glyph(f, r).advance * scale * f.scale_norm
}

// wrap_text_to_width returns `text` with newlines inserted so that no rendered
// line exceeds `max_width` pixels for `font` at `scale`. Lines are filled greedily
// word by word (words split on spaces and tabs); a single word wider than a line
// is hard-broken between glyphs so unbroken runs (e.g. URLs) still wrap. Existing
// newlines are preserved as hard breaks. Returns `text` unchanged when
// `max_width <= 0`. The result is allocated with `allocator` (temp by default),
// so it lives only until that allocator is reset.
wrap_text_to_width :: proc(
	mgr: ^Manager,
	text: string,
	max_width: f32,
	font: Font_Handle,
	scale: f32,
	allocator := context.temp_allocator,
) -> string {
	if max_width <= 0 || len(text) == 0 {
		return text
	}

	sb := strings.builder_make(allocator)
	space_w := measure_text(mgr, " ", font, scale).x
	line_w: f32 = 0
	line_has_content := false

	i := 0
	for i < len(text) {
		c := text[i]
		if c == '\n' {
			strings.write_byte(&sb, '\n')
			line_w = 0
			line_has_content = false
			i += 1
			continue
		}
		if c == ' ' || c == '\t' {
			i += 1
			continue
		}

		// Collect the next word: a run of non-space, non-newline bytes.
		word_start := i
		for i < len(text) && text[i] != ' ' && text[i] != '\t' && text[i] != '\n' {
			i += 1
		}
		word := text[word_start:i]
		word_w := measure_text(mgr, word, font, scale).x

		if word_w <= max_width {
			// Wrap before the word if it would overflow the current line.
			if line_has_content && line_w + space_w + word_w > max_width {
				strings.write_byte(&sb, '\n')
				line_w = 0
				line_has_content = false
			}
			if line_has_content {
				strings.write_byte(&sb, ' ')
				line_w += space_w
			}
			strings.write_string(&sb, word)
			line_w += word_w
			line_has_content = true
		} else {
			// Word is wider than a full line: break it between glyphs.
			if line_has_content {
				strings.write_byte(&sb, '\n')
				line_w = 0
				line_has_content = false
			}
			for r in word {
				rw := measure_rune(mgr, r, font, scale)
				if line_has_content && line_w + rw > max_width {
					strings.write_byte(&sb, '\n')
					line_w = 0
					line_has_content = false
				}
				strings.write_rune(&sb, r)
				line_w += rw
				line_has_content = true
			}
		}
	}

	return strings.to_string(sb)
}

// The character a truncated line ends with. A single glyph rather than three
// periods so it cannot be mistaken for the text's own punctuation, and so the
// cut costs one advance instead of three.
ELLIPSIS :: "…"

// truncate_text_to_width returns `text` as a single line no wider than
// `max_width`, ending in an ellipsis when anything had to be dropped. Every line
// break and tab becomes a space first: the result has to be genuinely one line,
// because a label that vertically centres its text measures the block it is
// given and would centre a two-line string on the middle of a one-line box.
//
// Returns `text` untouched when `max_width <= 0` — the column has not been
// measured yet, which is the same thing wrap_text_to_width does and the same
// answer the caller wants: no cut is better than a cut at a guessed width.
truncate_text_to_width :: proc(
	mgr: ^Manager,
	text: string,
	max_width: f32,
	font: Font_Handle,
	scale: f32,
	allocator := context.temp_allocator,
) -> string {
	if max_width <= 0 || len(text) == 0 {
		return text
	}
	// Flatten first, then measure: a break in the middle changes nothing about
	// how wide the visible line is, but it does change how tall the block
	// measures.
	flat := text
	needs_flattening := false
	for i in 0 ..< len(text) {
		if text[i] == '\n' || text[i] == '\t' || text[i] == '\r' {
			needs_flattening = true
			break
		}
	}
	if needs_flattening {
		sb := strings.builder_make(allocator)
		for i in 0 ..< len(text) {
			c := text[i]
			strings.write_byte(&sb, ' ' if c == '\n' || c == '\t' || c == '\r' else c)
		}
		flat = strings.to_string(sb)
	}
	if measure_text(mgr, flat, font, scale).x <= max_width {
		return flat
	}

	// Room for the ellipsis has to come out of the budget, or the cut line plus
	// its marker overruns the column the cut was meant to fit.
	budget := max_width - measure_text(mgr, ELLIPSIS, font, scale).x
	if budget <= 0 {
		return ELLIPSIS
	}
	width: f32 = 0
	cut := 0
	for ch, offset in flat {
		advance := measure_rune(mgr, ch, font, scale)
		if width + advance > budget {
			break
		}
		width += advance
		cut = offset + utf8.rune_size(ch)
	}
	// Prefer cutting at the last word boundary so the tail reads as a clipped
	// phrase rather than a clipped word — but only when one is close enough that
	// the line does not visibly shorten.
	for back := cut; back > 0 && back > cut - 12; back -= 1 {
		if flat[back - 1] == ' ' {
			cut = back - 1
			break
		}
	}
	sb := strings.builder_make(allocator)
	strings.write_string(&sb, flat[:cut])
	strings.write_string(&sb, ELLIPSIS)
	return strings.to_string(sb)
}

// soft_wrap_offsets returns the byte offsets at which `text` has to start a new
// visual line to fit `max_width` pixels for `font` at `scale`. Only the soft
// breaks are reported — the newlines already in the text are hard breaks the
// caller can find for itself — and no byte is added, removed or moved, so an
// index into `text` and an index into its wrapped form differ only by how many
// of these offsets precede it. That is what lets an editable field wrap what it
// draws while its cursor and selection keep addressing the buffer directly (see
// wrapped_text in textinput.odin). Words wrap whole, exactly like
// wrap_text_to_width; a word wider than the whole column breaks between glyphs.
// Returns nothing when `max_width <= 0`, i.e. before the column is measured. The
// result is allocated with `allocator` (temp by default).
soft_wrap_offsets :: proc(
	mgr: ^Manager,
	text: string,
	max_width: f32,
	font: Font_Handle,
	scale: f32,
	allocator := context.temp_allocator,
) -> []int {
	if max_width <= 0 || len(text) == 0 {
		return nil
	}

	breaks := make([dynamic]int, 0, 8, allocator)
	space_w := measure_rune(mgr, ' ', font, scale)
	line_start := 0 // byte offset the current visual line begins at
	line_w: f32 = 0

	i := 0
	for i < len(text) {
		c := text[i]
		if c == '\n' {
			i += 1
			line_start = i
			line_w = 0
			continue
		}
		// Whitespace only advances the pen: a line that ends in spaces is allowed to
		// overhang the column rather than wrapping on them, which is what keeps the
		// break in front of the next word instead of behind a trailing blank.
		if c == ' ' || c == '\t' {
			line_w += space_w
			i += 1
			continue
		}

		word_start := i
		for i < len(text) && text[i] != ' ' && text[i] != '\t' && text[i] != '\n' {
			i += 1
		}
		word := text[word_start:i]
		word_w := measure_text(mgr, word, font, scale).x

		if word_w <= max_width {
			// Move the whole word down instead of splitting it — unless it already
			// starts the line, in which case it fits by definition.
			if line_w + word_w > max_width && word_start > line_start {
				append(&breaks, word_start)
				line_start = word_start
				line_w = 0
			}
			line_w += word_w
			continue
		}

		// Wider than the column however it is placed: give it a fresh line if
		// anything precedes it, then break it between glyphs.
		if word_start > line_start {
			append(&breaks, word_start)
			line_start = word_start
			line_w = 0
		}
		for r, offset in word {
			rune_w := measure_rune(mgr, r, font, scale)
			at := word_start + offset
			if line_w + rune_w > max_width && at > line_start {
				append(&breaks, at)
				line_start = at
				line_w = 0
			}
			line_w += rune_w
		}
	}

	return breaks[:]
}

// wrap_code_to_width soft-wraps `text` to `max_width` pixels for code, preserving
// the author's own formatting wherever it fits: real newlines stay hard breaks and
// leading indentation is kept, so short/normal lines render verbatim. Only lines
// that overrun the column are wrapped, and they wrap at whitespace boundaries
// (never mid-token unless a single token is wider than the whole column). Wrapped
// fragments get a hanging indent — the source line's indent plus two spaces — so a
// continuation reads as part of its line rather than a new statement; that is what
// keeps a long block legible instead of a flat edge-to-edge run. Unlike
// wrap_text_to_width it never collapses interior runs of spaces, so alignment
// survives. Returns `text` unchanged when `max_width <= 0`. The result is allocated
// with `allocator` (temp by default), so it lives only until that allocator resets.
wrap_code_to_width :: proc(
	mgr: ^Manager,
	text: string,
	max_width: f32,
	font: Font_Handle,
	scale: f32,
	allocator := context.temp_allocator,
) -> string {
	if max_width <= 0 || len(text) == 0 {
		return text
	}

	// Wrap each source line independently so the author's own line breaks (and the
	// blank lines between blocks) are reproduced exactly.
	sb := strings.builder_make(allocator)
	line_start := 0
	for i := 0; i <= len(text); i += 1 {
		if i < len(text) && text[i] != '\n' {
			continue
		}
		if line_start != 0 {
			strings.write_byte(&sb, '\n')
		}
		wrap_code_line(&sb, mgr, text[line_start:i], max_width, font, scale)
		line_start = i + 1
	}

	return strings.to_string(sb)
}

// wrap_code_line wraps one source line (no embedded newlines) into `sb`. See
// wrap_code_to_width for the policy.
@(private = "file")
wrap_code_line :: proc(
	sb: ^strings.Builder,
	mgr: ^Manager,
	line: string,
	max_width: f32,
	font: Font_Handle,
	scale: f32,
) {
	// Leading indentation is reproduced as a hanging indent on continuations.
	indent_end := 0
	for indent_end < len(line) && (line[indent_end] == ' ' || line[indent_end] == '\t') {
		indent_end += 1
	}
	indent := line[:indent_end]
	space_w := measure_rune(mgr, ' ', font, scale)
	indent_w := measure_text(mgr, indent, font, scale).x

	// Continuation prefix = indent + 2 spaces, so a wrapped fragment sits just past
	// the code and reads as a continuation. Never let it swallow more than half the
	// column, or a deep indent would wrap the body to slivers: first drop the extra
	// two spaces, then the indent itself.
	cont_extra := 2
	draw_indent := true
	cont_w := indent_w + f32(cont_extra) * space_w
	if cont_w > max_width * 0.5 {
		cont_extra = 0
		cont_w = indent_w
	}
	if cont_w > max_width * 0.5 {
		draw_indent = false
		cont_w = 0
	}

	// The first visual line keeps the real leading indent verbatim.
	strings.write_string(sb, indent)
	line_w := indent_w
	placed := false // whether a non-break glyph sits on the current visual line

	i := indent_end
	for i < len(line) {
		// A run of spaces/tabs, kept verbatim unless we choose to wrap here.
		ws_start := i
		for i < len(line) && (line[i] == ' ' || line[i] == '\t') {
			i += 1
		}
		ws := line[ws_start:i]
		if i >= len(line) {
			strings.write_string(sb, ws) // trailing whitespace: keep it, then stop
			break
		}
		ws_w := measure_text(mgr, ws, font, scale).x

		// The next word: a run of non-whitespace.
		word_start := i
		for i < len(line) && line[i] != ' ' && line[i] != '\t' {
			i += 1
		}
		word := line[word_start:i]
		word_w := measure_text(mgr, word, font, scale).x

		would_wrap := placed && line_w + ws_w + word_w > max_width
		// A token can be narrower than the whole column and still not fit after
		// source or continuation indentation. Use the remaining width or an
		// indented token simply runs through the right edge.
		needs_hard_break := word_w > max_width ||
			(!placed && line_w + ws_w + word_w > max_width) ||
			(would_wrap && cont_w + word_w > max_width)
		if needs_hard_break {
			// Hard-break between glyphs. Start on a fresh continuation when the line
			// already has content; otherwise use the width after source indentation.
			if placed {
				write_code_continuation(sb, indent, cont_extra, draw_indent)
				line_w = cont_w
				placed = false
			} else {
				strings.write_string(sb, ws)
				line_w += ws_w
			}
			for r in word {
				rw := measure_rune(mgr, r, font, scale)
				if line_w + rw > max_width && (placed || line_w > 0) {
					write_code_continuation(sb, indent, cont_extra, draw_indent)
					line_w = cont_w
					placed = false
				}
				strings.write_rune(sb, r)
				line_w += rw
				placed = true
			}
		} else if would_wrap {
			// Wrap before the word; the spaces at the break are replaced by the
			// hanging indent rather than left dangling at the line end.
			write_code_continuation(sb, indent, cont_extra, draw_indent)
			line_w = cont_w
			strings.write_string(sb, word)
			line_w += word_w
			placed = true
		} else {
			// Fits on the current line: keep the original spacing verbatim.
			strings.write_string(sb, ws)
			strings.write_string(sb, word)
			line_w += ws_w + word_w
			placed = true
		}
	}
}

// write_code_continuation starts a wrapped continuation line: a newline followed by
// the hanging indent (source indent, unless too deep, plus `n_extra` spaces).
@(private = "file")
write_code_continuation :: proc(sb: ^strings.Builder, indent: string, n_extra: int, draw_indent: bool) {
	strings.write_byte(sb, '\n')
	if draw_indent {
		strings.write_string(sb, indent)
	}
	for _ in 0 ..< n_extra {
		strings.write_byte(sb, ' ')
	}
}

// Get the effective rendering scale for a font, applying normalization.
// For the builtin bitmap font, returns the scale unchanged.
// For TTF fonts, normalizes so that widget scale values produce equivalent visual sizes.
get_effective_scale :: proc(mgr: ^Manager, font: Font_Handle, scale: f32) -> f32 {
	effective_font := resolve_font(mgr, font)
	if effective_font == FONT_BUILTIN || len(mgr.fonts) == 0 || int(effective_font) - 1 >= len(mgr.fonts) {
		return scale
	}
	return scale * mgr.fonts[int(effective_font) - 1].scale_norm
}

// Get the ascent (top of the line box to the baseline) in pixels for a font at a
// given scale. Text is positioned by its line box, so mixing faces on one line
// means offsetting each by the difference in ascent to share a baseline.
get_ascent :: proc(mgr: ^Manager, font: Font_Handle, scale: f32) -> f32 {
	effective_font := resolve_font(mgr, font)
	if effective_font == FONT_BUILTIN || len(mgr.fonts) == 0 || int(effective_font) - 1 >= len(mgr.fonts) {
		// The bitmap font draws from the top of its cell; there is no baseline to
		// share, so every "face" starts at the same place.
		return 0
	}
	f := &mgr.fonts[int(effective_font) - 1]
	return f.ascent * scale * f.scale_norm
}

// Get the line height in pixels for a font at a given scale.
get_line_height :: proc(mgr: ^Manager, font: Font_Handle, scale: f32) -> f32 {
	effective_font := resolve_font(mgr, font)
	if effective_font == FONT_BUILTIN || len(mgr.fonts) == 0 || int(effective_font) - 1 >= len(mgr.fonts) {
		return f32(FONT_CHAR_HEIGHT) * builtin_scale(scale)
	}
	f := &mgr.fonts[int(effective_font) - 1]
	return f.line_height * scale * f.scale_norm
}

// Measure the pixel width of the first `count` characters of `text` (single line, no newline handling).
// Used for cursor positioning in text inputs with proportional fonts.
measure_text_prefix :: proc(mgr: ^Manager, text: string, count: int, font: Font_Handle, scale: f32) -> f32 {
	effective_font := resolve_font(mgr, font)
	n := min(count, len(text))
	if effective_font == FONT_BUILTIN || len(mgr.fonts) == 0 || int(effective_font) - 1 >= len(mgr.fonts) {
		return f32(n) * f32(FONT_CHAR_WIDTH) * builtin_scale(scale)
	}
	f := &mgr.fonts[int(effective_font) - 1]
	eff := scale * f.scale_norm
	width: f32 = 0
	i := 0
	for ch in text {
		if i >= n { break }
		width += font_atlas_glyph(f, ch).advance * eff
		i += 1
	}
	return width
}

// Find the character index closest to a given pixel x-offset within `text` (single line).
// Returns the insertion position (0..len) that best matches the click position.
hit_test_text :: proc(mgr: ^Manager, text: string, x_offset: f32, font: Font_Handle, scale: f32) -> int {
	effective_font := resolve_font(mgr, font)
	if effective_font == FONT_BUILTIN || len(mgr.fonts) == 0 || int(effective_font) - 1 >= len(mgr.fonts) {
		char_w := f32(FONT_CHAR_WIDTH) * builtin_scale(scale)
		col := int(x_offset / char_w + 0.5)
		return clamp(col, 0, len(text))
	}
	f := &mgr.fonts[int(effective_font) - 1]
	eff := scale * f.scale_norm
	accum: f32 = 0
	i := 0
	for ch in text {
		advance := font_atlas_glyph(f, ch).advance * eff
		// If click is before the midpoint of this glyph, cursor goes before it
		if x_offset < accum + advance * 0.5 {
			return i
		}
		accum += advance
		i += 1
	}
	return i
}

// --- Bitmap Font ---
// 5x7 pixel font covering all 256 ASCII/extended characters.
// Column-major format: each character is 5 bytes, each byte is one column,
// bit 0 (LSB) = top row, bit 6 = bottom row.
// Derived from the Adafruit GFX classic font (public domain).

FONT_GLYPH_WIDTH  :: 5
FONT_GLYPH_HEIGHT :: 7
FONT_CHAR_WIDTH   :: 6  // glyph + 1px spacing
FONT_CHAR_HEIGHT  :: 9  // glyph + 2px spacing (for readability)

// The bitmap font can only be drawn at whole-pixel multiples, so measurement
// and drawing MUST use the same integer scale — otherwise a widget reserves a
// box at the fractional scale but the glyphs render at the truncated integer
// scale, leaving small text floating in an oversized box. Round to nearest,
// clamped to at least 1. draw_text_bitmap uses this same function.
builtin_scale :: proc "contextless" (scale: f32) -> f32 {
	return f32(max(1, int(scale + 0.5)))
}

// Measure a string in pixels at a given scale.
measure_text_builtin :: proc(text: string, scale: f32 = 2) -> Vec2 {
	if len(text) == 0 {
		return {0, 0}
	}
	s := builtin_scale(scale)
	max_cols := 0
	cur_cols := 0
	lines := 1
	for ch in text {
		if ch == '\n' {
			max_cols = max(max_cols, cur_cols)
			cur_cols = 0
			lines += 1
		} else {
			cur_cols += 1
		}
	}
	max_cols = max(max_cols, cur_cols)
	return {
		f32(max_cols) * f32(FONT_CHAR_WIDTH) * s,
		f32(lines) * f32(FONT_CHAR_HEIGHT) * s,
	}
}

// Check if a pixel is set in a glyph. col: 0-4, row: 0-6.
font_pixel :: proc(ch: u8, col, row: int) -> bool {
	idx := int(ch) * 5 + col
	return (FONT_5X7_DATA[idx] & (1 << u8(row))) != 0
}

// Standard ASCII 5x7 font data — 256 chars x 5 bytes = 1280 bytes.
// Stored as a runtime variable so it can be indexed with runtime values.
@(rodata)
FONT_5X7_DATA := [1280]u8{
	0x00, 0x00, 0x00, 0x00, 0x00, 0x3E, 0x5B, 0x4F, 0x5B, 0x3E, 0x3E, 0x6B, 0x4F, 0x6B, 0x3E, 0x1C,
	0x3E, 0x7C, 0x3E, 0x1C, 0x18, 0x3C, 0x7E, 0x3C, 0x18, 0x1C, 0x57, 0x7D, 0x57, 0x1C, 0x1C, 0x5E,
	0x7F, 0x5E, 0x1C, 0x00, 0x18, 0x3C, 0x18, 0x00, 0xFF, 0xE7, 0xC3, 0xE7, 0xFF, 0x00, 0x18, 0x24,
	0x18, 0x00, 0xFF, 0xE7, 0xDB, 0xE7, 0xFF, 0x30, 0x48, 0x3A, 0x06, 0x0E, 0x26, 0x29, 0x79, 0x29,
	0x26, 0x40, 0x7F, 0x05, 0x05, 0x07, 0x40, 0x7F, 0x05, 0x25, 0x3F, 0x5A, 0x3C, 0xE7, 0x3C, 0x5A,
	0x7F, 0x3E, 0x1C, 0x1C, 0x08, 0x08, 0x1C, 0x1C, 0x3E, 0x7F, 0x14, 0x22, 0x7F, 0x22, 0x14, 0x5F,
	0x5F, 0x00, 0x5F, 0x5F, 0x06, 0x09, 0x7F, 0x01, 0x7F, 0x00, 0x66, 0x89, 0x95, 0x6A, 0x60, 0x60,
	0x60, 0x60, 0x60, 0x94, 0xA2, 0xFF, 0xA2, 0x94, 0x08, 0x04, 0x7E, 0x04, 0x08, 0x10, 0x20, 0x7E,
	0x20, 0x10, 0x08, 0x08, 0x2A, 0x1C, 0x08, 0x08, 0x1C, 0x2A, 0x08, 0x08, 0x1E, 0x10, 0x10, 0x10,
	0x10, 0x0C, 0x1E, 0x0C, 0x1E, 0x0C, 0x30, 0x38, 0x3E, 0x38, 0x30, 0x06, 0x0E, 0x3E, 0x0E, 0x06,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x5F, 0x00, 0x00, 0x00, 0x07, 0x00, 0x07, 0x00, 0x14,
	0x7F, 0x14, 0x7F, 0x14, 0x24, 0x2A, 0x7F, 0x2A, 0x12, 0x23, 0x13, 0x08, 0x64, 0x62, 0x36, 0x49,
	0x56, 0x20, 0x50, 0x00, 0x08, 0x07, 0x03, 0x00, 0x00, 0x1C, 0x22, 0x41, 0x00, 0x00, 0x41, 0x22,
	0x1C, 0x00, 0x2A, 0x1C, 0x7F, 0x1C, 0x2A, 0x08, 0x08, 0x3E, 0x08, 0x08, 0x00, 0x80, 0x70, 0x30,
	0x00, 0x08, 0x08, 0x08, 0x08, 0x08, 0x00, 0x00, 0x60, 0x60, 0x00, 0x20, 0x10, 0x08, 0x04, 0x02,
	0x3E, 0x51, 0x49, 0x45, 0x3E, 0x00, 0x42, 0x7F, 0x40, 0x00, 0x72, 0x49, 0x49, 0x49, 0x46, 0x21,
	0x41, 0x49, 0x4D, 0x33, 0x18, 0x14, 0x12, 0x7F, 0x10, 0x27, 0x45, 0x45, 0x45, 0x39, 0x3C, 0x4A,
	0x49, 0x49, 0x31, 0x41, 0x21, 0x11, 0x09, 0x07, 0x36, 0x49, 0x49, 0x49, 0x36, 0x46, 0x49, 0x49,
	0x29, 0x1E, 0x00, 0x00, 0x14, 0x00, 0x00, 0x00, 0x40, 0x34, 0x00, 0x00, 0x00, 0x08, 0x14, 0x22,
	0x41, 0x14, 0x14, 0x14, 0x14, 0x14, 0x00, 0x41, 0x22, 0x14, 0x08, 0x02, 0x01, 0x59, 0x09, 0x06,
	0x3E, 0x41, 0x5D, 0x59, 0x4E, 0x7C, 0x12, 0x11, 0x12, 0x7C, 0x7F, 0x49, 0x49, 0x49, 0x36, 0x3E,
	0x41, 0x41, 0x41, 0x22, 0x7F, 0x41, 0x41, 0x41, 0x3E, 0x7F, 0x49, 0x49, 0x49, 0x41, 0x7F, 0x09,
	0x09, 0x09, 0x01, 0x3E, 0x41, 0x41, 0x51, 0x73, 0x7F, 0x08, 0x08, 0x08, 0x7F, 0x00, 0x41, 0x7F,
	0x41, 0x00, 0x20, 0x40, 0x41, 0x3F, 0x01, 0x7F, 0x08, 0x14, 0x22, 0x41, 0x7F, 0x40, 0x40, 0x40,
	0x40, 0x7F, 0x02, 0x1C, 0x02, 0x7F, 0x7F, 0x04, 0x08, 0x10, 0x7F, 0x3E, 0x41, 0x41, 0x41, 0x3E,
	0x7F, 0x09, 0x09, 0x09, 0x06, 0x3E, 0x41, 0x51, 0x21, 0x5E, 0x7F, 0x09, 0x19, 0x29, 0x46, 0x26,
	0x49, 0x49, 0x49, 0x32, 0x03, 0x01, 0x7F, 0x01, 0x03, 0x3F, 0x40, 0x40, 0x40, 0x3F, 0x1F, 0x20,
	0x40, 0x20, 0x1F, 0x3F, 0x40, 0x38, 0x40, 0x3F, 0x63, 0x14, 0x08, 0x14, 0x63, 0x03, 0x04, 0x78,
	0x04, 0x03, 0x61, 0x59, 0x49, 0x4D, 0x43, 0x00, 0x7F, 0x41, 0x41, 0x41, 0x02, 0x04, 0x08, 0x10,
	0x20, 0x00, 0x41, 0x41, 0x41, 0x7F, 0x04, 0x02, 0x01, 0x02, 0x04, 0x40, 0x40, 0x40, 0x40, 0x40,
	0x00, 0x03, 0x07, 0x08, 0x00, 0x20, 0x54, 0x54, 0x78, 0x40, 0x7F, 0x28, 0x44, 0x44, 0x38, 0x38,
	0x44, 0x44, 0x44, 0x28, 0x38, 0x44, 0x44, 0x28, 0x7F, 0x38, 0x54, 0x54, 0x54, 0x18, 0x00, 0x08,
	0x7E, 0x09, 0x02, 0x18, 0xA4, 0xA4, 0x9C, 0x78, 0x7F, 0x08, 0x04, 0x04, 0x78, 0x00, 0x44, 0x7D,
	0x40, 0x00, 0x20, 0x40, 0x40, 0x3D, 0x00, 0x7F, 0x10, 0x28, 0x44, 0x00, 0x00, 0x41, 0x7F, 0x40,
	0x00, 0x7C, 0x04, 0x78, 0x04, 0x78, 0x7C, 0x08, 0x04, 0x04, 0x78, 0x38, 0x44, 0x44, 0x44, 0x38,
	0xFC, 0x18, 0x24, 0x24, 0x18, 0x18, 0x24, 0x24, 0x18, 0xFC, 0x7C, 0x08, 0x04, 0x04, 0x08, 0x48,
	0x54, 0x54, 0x54, 0x24, 0x04, 0x04, 0x3F, 0x44, 0x24, 0x3C, 0x40, 0x40, 0x20, 0x7C, 0x1C, 0x20,
	0x40, 0x20, 0x1C, 0x3C, 0x40, 0x30, 0x40, 0x3C, 0x44, 0x28, 0x10, 0x28, 0x44, 0x4C, 0x90, 0x90,
	0x90, 0x7C, 0x44, 0x64, 0x54, 0x4C, 0x44, 0x00, 0x08, 0x36, 0x41, 0x00, 0x00, 0x00, 0x77, 0x00,
	0x00, 0x00, 0x41, 0x36, 0x08, 0x00, 0x02, 0x01, 0x02, 0x04, 0x02, 0x3C, 0x26, 0x23, 0x26, 0x3C,
	0x1E, 0xA1, 0xA1, 0x61, 0x12, 0x3A, 0x40, 0x40, 0x20, 0x7A, 0x38, 0x54, 0x54, 0x55, 0x59, 0x21,
	0x55, 0x55, 0x79, 0x41, 0x22, 0x54, 0x54, 0x78, 0x42, 0x21, 0x55, 0x54, 0x78, 0x40, 0x20, 0x54,
	0x55, 0x79, 0x40, 0x0C, 0x1E, 0x52, 0x72, 0x12, 0x39, 0x55, 0x55, 0x55, 0x59, 0x39, 0x54, 0x54,
	0x54, 0x59, 0x39, 0x55, 0x54, 0x54, 0x58, 0x00, 0x00, 0x45, 0x7C, 0x41, 0x00, 0x02, 0x45, 0x7D,
	0x42, 0x00, 0x01, 0x45, 0x7C, 0x40, 0x7D, 0x12, 0x11, 0x12, 0x7D, 0xF0, 0x28, 0x25, 0x28, 0xF0,
	0x7C, 0x54, 0x55, 0x45, 0x00, 0x20, 0x54, 0x54, 0x7C, 0x54, 0x7C, 0x0A, 0x09, 0x7F, 0x49, 0x32,
	0x49, 0x49, 0x49, 0x32, 0x3A, 0x44, 0x44, 0x44, 0x3A, 0x32, 0x4A, 0x48, 0x48, 0x30, 0x3A, 0x41,
	0x41, 0x21, 0x7A, 0x3A, 0x42, 0x40, 0x20, 0x78, 0x00, 0x9D, 0xA0, 0xA0, 0x7D, 0x3D, 0x42, 0x42,
	0x42, 0x3D, 0x3D, 0x40, 0x40, 0x40, 0x3D, 0x3C, 0x24, 0xFF, 0x24, 0x24, 0x48, 0x7E, 0x49, 0x43,
	0x66, 0x2B, 0x2F, 0xFC, 0x2F, 0x2B, 0xFF, 0x09, 0x29, 0xF6, 0x20, 0xC0, 0x88, 0x7E, 0x09, 0x03,
	0x20, 0x54, 0x54, 0x79, 0x41, 0x00, 0x00, 0x44, 0x7D, 0x41, 0x30, 0x48, 0x48, 0x4A, 0x32, 0x38,
	0x40, 0x40, 0x22, 0x7A, 0x00, 0x7A, 0x0A, 0x0A, 0x72, 0x7D, 0x0D, 0x19, 0x31, 0x7D, 0x26, 0x29,
	0x29, 0x2F, 0x28, 0x26, 0x29, 0x29, 0x29, 0x26, 0x30, 0x48, 0x4D, 0x40, 0x20, 0x38, 0x08, 0x08,
	0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x38, 0x2F, 0x10, 0xC8, 0xAC, 0xBA, 0x2F, 0x10, 0x28, 0x34,
	0xFA, 0x00, 0x00, 0x7B, 0x00, 0x00, 0x08, 0x14, 0x2A, 0x14, 0x22, 0x22, 0x14, 0x2A, 0x14, 0x08,
	0x55, 0x00, 0x55, 0x00, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0xFF, 0x55, 0xFF, 0x55, 0xFF, 0x00,
	0x00, 0x00, 0xFF, 0x00, 0x10, 0x10, 0x10, 0xFF, 0x00, 0x14, 0x14, 0x14, 0xFF, 0x00, 0x10, 0x10,
	0xFF, 0x00, 0xFF, 0x10, 0x10, 0xF0, 0x10, 0xF0, 0x14, 0x14, 0x14, 0xFC, 0x00, 0x14, 0x14, 0xF7,
	0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0xFF, 0x14, 0x14, 0xF4, 0x04, 0xFC, 0x14, 0x14, 0x17, 0x10,
	0x1F, 0x10, 0x10, 0x1F, 0x10, 0x1F, 0x14, 0x14, 0x14, 0x1F, 0x00, 0x10, 0x10, 0x10, 0xF0, 0x00,
	0x00, 0x00, 0x00, 0x1F, 0x10, 0x10, 0x10, 0x10, 0x1F, 0x10, 0x10, 0x10, 0x10, 0xF0, 0x10, 0x00,
	0x00, 0x00, 0xFF, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0xFF, 0x10, 0x00, 0x00,
	0x00, 0xFF, 0x14, 0x00, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0x00, 0x1F, 0x10, 0x17, 0x00, 0x00, 0xFC,
	0x04, 0xF4, 0x14, 0x14, 0x17, 0x10, 0x17, 0x14, 0x14, 0xF4, 0x04, 0xF4, 0x00, 0x00, 0xFF, 0x00,
	0xF7, 0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0xF7, 0x00, 0xF7, 0x14, 0x14, 0x14, 0x17, 0x14,
	0x10, 0x10, 0x1F, 0x10, 0x1F, 0x14, 0x14, 0x14, 0xF4, 0x14, 0x10, 0x10, 0xF0, 0x10, 0xF0, 0x00,
	0x00, 0x1F, 0x10, 0x1F, 0x00, 0x00, 0x00, 0x1F, 0x14, 0x00, 0x00, 0x00, 0xFC, 0x14, 0x00, 0x00,
	0xF0, 0x10, 0xF0, 0x10, 0x10, 0xFF, 0x10, 0xFF, 0x14, 0x14, 0x14, 0xFF, 0x14, 0x10, 0x10, 0x10,
	0x1F, 0x00, 0x00, 0x00, 0x00, 0xF0, 0x10, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xF0, 0xF0, 0xF0, 0xF0,
	0xF0, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F,
	0x38, 0x44, 0x44, 0x38, 0x44, 0xFC, 0x4A, 0x4A, 0x4A, 0x34, 0x7E, 0x02, 0x02, 0x06, 0x06, 0x02,
	0x7E, 0x02, 0x7E, 0x02, 0x63, 0x55, 0x49, 0x41, 0x63, 0x38, 0x44, 0x44, 0x3C, 0x04, 0x40, 0x7E,
	0x20, 0x1E, 0x20, 0x06, 0x02, 0x7E, 0x02, 0x02, 0x99, 0xA5, 0xE7, 0xA5, 0x99, 0x1C, 0x2A, 0x49,
	0x2A, 0x1C, 0x4C, 0x72, 0x01, 0x72, 0x4C, 0x30, 0x4A, 0x4D, 0x4D, 0x30, 0x30, 0x48, 0x78, 0x48,
	0x30, 0xBC, 0x62, 0x5A, 0x46, 0x3D, 0x3E, 0x49, 0x49, 0x49, 0x00, 0x7E, 0x01, 0x01, 0x01, 0x7E,
	0x2A, 0x2A, 0x2A, 0x2A, 0x2A, 0x44, 0x44, 0x5F, 0x44, 0x44, 0x40, 0x51, 0x4A, 0x44, 0x40, 0x40,
	0x44, 0x4A, 0x51, 0x40, 0x00, 0x00, 0xFF, 0x01, 0x03, 0xE0, 0x80, 0xFF, 0x00, 0x00, 0x08, 0x08,
	0x6B, 0x6B, 0x08, 0x36, 0x12, 0x36, 0x24, 0x36, 0x06, 0x0F, 0x09, 0x0F, 0x06, 0x00, 0x00, 0x18,
	0x18, 0x00, 0x00, 0x00, 0x10, 0x10, 0x00, 0x30, 0x40, 0xFF, 0x01, 0x01, 0x00, 0x1F, 0x01, 0x01,
	0x1E, 0x00, 0x19, 0x1D, 0x17, 0x12, 0x00, 0x3C, 0x3C, 0x3C, 0x3C, 0x00, 0x00, 0x00, 0x00, 0x00,
}

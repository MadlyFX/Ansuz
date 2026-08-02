#+build !freestanding
package ansuz

import "core:strings"
import "core:testing"

// The builtin bitmap face is fixed-width, so a column of N characters is exactly
// N * FONT_CHAR_WIDTH * builtin_scale(scale) wide. Every expectation below is
// written in whole characters at scale 1, where one character is one pixel wider
// than FONT_CHAR_WIDTH's glyph box.
@(private = "file")
CHAR_W :: f32(FONT_CHAR_WIDTH)

@(test)
truncation_keeps_a_line_that_already_fits :: proc(t: ^testing.T) {
	mgr: Manager
	backend := Backend{width = 400, height = 400}
	init(&mgr, &backend)
	defer shutdown(&mgr)

	fits := truncate_text_to_width(&mgr, "short", CHAR_W * 20, FONT_BUILTIN, 1)
	testing.expect_value(t, fits, "short")

	// An unmeasured column cannot be cut against — the same answer
	// wrap_text_to_width gives, and for the same reason.
	testing.expect_value(t, truncate_text_to_width(&mgr, "short", 0, FONT_BUILTIN, 1), "short")
	testing.expect_value(t, truncate_text_to_width(&mgr, "", CHAR_W * 20, FONT_BUILTIN, 1), "")
}

@(test)
truncation_flattens_a_multi_line_note_that_fits :: proc(t: ^testing.T) {
	mgr: Manager
	backend := Backend{width = 400, height = 400}
	init(&mgr, &backend)
	defer shutdown(&mgr)

	// Even when the text is narrow enough to keep whole, the breaks have to go:
	// a label that centres its text vertically measures the block it is handed,
	// so a two-line string would be centred as two lines in a one-line box.
	flat := truncate_text_to_width(&mgr, "a\nb\tc", CHAR_W * 20, FONT_BUILTIN, 1)
	testing.expect_value(t, flat, "a b c")
	testing.expect(t, !strings.contains(flat, "\n"))
}

@(test)
truncation_marks_the_cut_and_stays_inside_the_column :: proc(t: ^testing.T) {
	mgr: Manager
	backend := Backend{width = 400, height = 400}
	init(&mgr, &backend)
	defer shutdown(&mgr)

	// Ten characters of room for a much longer line.
	width := CHAR_W * 10
	cut := truncate_text_to_width(&mgr, "abcdefghijklmnopqrstuvwxyz", width, FONT_BUILTIN, 1)
	testing.expect(t, strings.has_suffix(cut, ELLIPSIS), "a cut line says so")
	testing.expect(t, len(cut) < len("abcdefghijklmnopqrstuvwxyz"))
	// The marker is part of the budget, not extra: the whole thing still fits the
	// column it was cut to.
	testing.expect(t, measure_text(&mgr, cut, FONT_BUILTIN, 1).x <= width)
}

@(test)
truncation_prefers_the_last_word_boundary :: proc(t: ^testing.T) {
	mgr: Manager
	backend := Backend{width = 400, height = 400}
	init(&mgr, &backend)
	defer shutdown(&mgr)

	// "alpha beta gamma" cut near the middle should end after a whole word
	// rather than mid-word, so the tail reads as a clipped phrase.
	cut := truncate_text_to_width(&mgr, "alpha beta gamma delta", CHAR_W * 14, FONT_BUILTIN, 1)
	testing.expect(t, strings.has_suffix(cut, ELLIPSIS))
	body := cut[:len(cut) - len(ELLIPSIS)]
	testing.expect(t, !strings.has_suffix(body, " "), "the space itself is dropped with the tail")
	testing.expect(t, body == "alpha beta" || body == "alpha", "cut at a word, not inside one")
}

@(test)
truncation_survives_a_column_narrower_than_the_marker :: proc(t: ^testing.T) {
	mgr: Manager
	backend := Backend{width = 400, height = 400}
	init(&mgr, &backend)
	defer shutdown(&mgr)

	// Nothing fits beside the ellipsis: the marker alone is the honest answer,
	// and the loop must not run off the end looking for room that is not there.
	testing.expect_value(t, truncate_text_to_width(&mgr, "abcdef", 1, FONT_BUILTIN, 1), ELLIPSIS)
}

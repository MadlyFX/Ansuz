#+build !freestanding
package ansuz

import "core:testing"

// These tests use the builtin 5x7 bitmap font (no TTF loaded), whose glyph
// advance is exactly FONT_CHAR_WIDTH (6px) at scale 1, making wrap widths
// easy to reason about.

@(test)
wrap_text_breaks_at_word_boundaries :: proc(t: ^testing.T) {
	backend := Backend{width = 640, height = 480}
	mgr: Manager
	init(&mgr, &backend)
	defer shutdown(&mgr)

	// "hello"(30) + " "(6) + "world"(30) = 66 > 60, so "world" wraps; "foo"(18)
	// then fits after "world" (30 + 6 + 18 = 54 <= 60).
	got := wrap_text_to_width(&mgr, "hello world foo", 60, FONT_DEFAULT, 1, context.allocator)
	defer delete(got)
	testing.expect_value(t, got, "hello\nworld foo")
}

@(test)
wrap_text_hard_breaks_long_words :: proc(t: ^testing.T) {
	backend := Backend{width = 640, height = 480}
	mgr: Manager
	init(&mgr, &backend)
	defer shutdown(&mgr)

	// A single 10-glyph word (60px) at a 30px width breaks every 5 glyphs.
	got := wrap_text_to_width(&mgr, "aaaaaaaaaa", 30, FONT_DEFAULT, 1, context.allocator)
	defer delete(got)
	testing.expect_value(t, got, "aaaaa\naaaaa")
}

@(test)
wrap_text_preserves_short_text :: proc(t: ^testing.T) {
	backend := Backend{width = 640, height = 480}
	mgr: Manager
	init(&mgr, &backend)
	defer shutdown(&mgr)

	got := wrap_text_to_width(&mgr, "short", 600, FONT_DEFAULT, 1, context.allocator)
	defer delete(got)
	testing.expect_value(t, got, "short")
}

@(test)
wrap_text_noop_for_nonpositive_width :: proc(t: ^testing.T) {
	backend := Backend{width = 640, height = 480}
	mgr: Manager
	init(&mgr, &backend)
	defer shutdown(&mgr)

	// Width <= 0 means the column isn't measured yet; return the text untouched.
	got := wrap_text_to_width(&mgr, "hello world", 0, FONT_DEFAULT, 1, context.allocator)
	testing.expect_value(t, got, "hello world")
}

@(test)
soft_wrap_offsets_break_before_the_overflowing_word :: proc(t: ^testing.T) {
	backend := Backend{width = 640, height = 480}
	mgr: Manager
	init(&mgr, &backend)
	defer shutdown(&mgr)

	// Same column as wrap_text_breaks_at_word_boundaries: "world" is what
	// overflows, and it starts at byte 6. Nothing is inserted or collapsed, so the
	// offset indexes the original string.
	got := soft_wrap_offsets(&mgr, "hello world foo", 60, FONT_DEFAULT, 1, context.allocator)
	defer delete(got)
	testing.expect_value(t, len(got), 1)
	testing.expect_value(t, got[0], 6)
	testing.expect_value(t, wrapped_text("hello world foo", got, context.temp_allocator), "hello \nworld foo")
}

@(test)
soft_wrap_offsets_split_a_word_wider_than_the_column :: proc(t: ^testing.T) {
	backend := Backend{width = 640, height = 480}
	mgr: Manager
	init(&mgr, &backend)
	defer shutdown(&mgr)

	got := soft_wrap_offsets(&mgr, "aaaaaaaaaa", 30, FONT_DEFAULT, 1, context.allocator)
	defer delete(got)
	testing.expect_value(t, len(got), 1)
	testing.expect_value(t, got[0], 5)
}

@(test)
soft_wrap_offsets_measure_each_hard_line_on_its_own :: proc(t: ^testing.T) {
	backend := Backend{width = 640, height = 480}
	mgr: Manager
	init(&mgr, &backend)
	defer shutdown(&mgr)

	// A newline restarts the column, so neither short line has anything to fold.
	got := soft_wrap_offsets(&mgr, "hello\nworld", 60, FONT_DEFAULT, 1, context.allocator)
	defer delete(got)
	testing.expect_value(t, len(got), 0)
}

@(test)
soft_wrap_offsets_are_empty_before_the_column_is_measured :: proc(t: ^testing.T) {
	backend := Backend{width = 640, height = 480}
	mgr: Manager
	init(&mgr, &backend)
	defer shutdown(&mgr)

	got := soft_wrap_offsets(&mgr, "hello world", 0, FONT_DEFAULT, 1, context.allocator)
	testing.expect_value(t, len(got), 0)
}

@(test)
wrap_indices_round_trip_between_buffer_and_display :: proc(t: ^testing.T) {
	// "hello \nworld foo": one newline inserted at buffer offset 6.
	breaks := []int{6}

	// Before the break the two spaces agree; from the break on, display runs one
	// byte ahead. An index sitting on the break belongs to the continuation.
	testing.expect_value(t, wrap_display_index(breaks, 0), 0)
	testing.expect_value(t, wrap_display_index(breaks, 5), 5)
	testing.expect_value(t, wrap_display_index(breaks, 6), 7)
	testing.expect_value(t, wrap_display_index(breaks, 9), 10)

	testing.expect_value(t, wrap_buffer_index(breaks, 5), 5)
	// Display index 6 is the inserted newline itself: it resolves to the end of
	// the line it broke, so a click on the fold does not jump a character.
	testing.expect_value(t, wrap_buffer_index(breaks, 6), 6)
	testing.expect_value(t, wrap_buffer_index(breaks, 7), 6)
	testing.expect_value(t, wrap_buffer_index(breaks, 10), 9)
}

@(test)
visual_lines_span_hard_and_soft_breaks_alike :: proc(t: ^testing.T) {
	text := "hello world\nagain"
	breaks := []int{6}

	// "hello " — a soft break ends it, and the break offset opens the next line.
	testing.expect_value(t, visual_line_start(text, breaks, 3), 0)
	testing.expect_value(t, visual_line_end(text, breaks, 3), 6)
	// "world" — from the soft break to the newline.
	testing.expect_value(t, visual_line_start(text, breaks, 6), 6)
	testing.expect_value(t, visual_line_start(text, breaks, 9), 6)
	testing.expect_value(t, visual_line_end(text, breaks, 6), 11)
	// "again" — the last line runs to the end of the text.
	testing.expect_value(t, visual_line_start(text, breaks, 14), 12)
	testing.expect_value(t, visual_line_end(text, breaks, 14), 17)

	// With no folds the same calls describe the hard lines alone.
	testing.expect_value(t, visual_line_start(text, nil, 9), 0)
	testing.expect_value(t, visual_line_end(text, nil, 3), 11)
}

@(test)
wrap_code_word_wraps_with_hanging_indent :: proc(t: ^testing.T) {
	backend := Backend{width = 640, height = 480}
	mgr: Manager
	init(&mgr, &backend)
	defer shutdown(&mgr)

	// "    foo bar baz" at a 12-glyph (72px) column: "foo bar" (indent 4 + 7 = 66)
	// fits, then "baz" would overflow, so it wraps at the space — the token is not
	// split — onto a continuation indented to the source indent (4) plus 2, i.e.
	// 6 spaces. The leading indent and interior single spaces survive verbatim.
	got := wrap_code_to_width(&mgr, "    foo bar baz", 72, FONT_DEFAULT, 1, context.allocator)
	defer delete(got)
	testing.expect_value(t, got, "    foo bar\n      baz")
}

@(test)
wrap_code_hard_breaks_overlong_token :: proc(t: ^testing.T) {
	backend := Backend{width = 640, height = 480}
	mgr: Manager
	init(&mgr, &backend)
	defer shutdown(&mgr)

	// A single 8-glyph token (48px) at a 6-glyph (36px) column has no break
	// opportunity, so it hard-breaks between glyphs; the continuation still gets
	// the 2-space hanging indent. No infinite loop when a run exceeds the column.
	got := wrap_code_to_width(&mgr, "aaaaaaaa", 36, FONT_DEFAULT, 1, context.allocator)
	defer delete(got)
	testing.expect_value(t, got, "aaaaaa\n  aa")
}

@(test)
wrap_code_accounts_for_indent_when_breaking_tokens :: proc(t: ^testing.T) {
	backend := Backend{width = 640, height = 480}
	mgr: Manager
	init(&mgr, &backend)
	defer shutdown(&mgr)

	// The token is only 10 glyphs wide, but four source-indent columns leave eight
	// glyphs on the first line.
	got := wrap_code_to_width(&mgr, "    aaaaaaaaaa", 72, FONT_DEFAULT, 1, context.allocator)
	defer delete(got)
	testing.expect_value(t, got, "    aaaaaaaa\n      aa")
}

@(test)
wrap_code_keeps_newlines_and_indent :: proc(t: ^testing.T) {
	backend := Backend{width = 640, height = 480}
	mgr: Manager
	init(&mgr, &backend)
	defer shutdown(&mgr)

	// Lines that fit are untouched: the author's own line breaks and indentation
	// are preserved as-is.
	got := wrap_code_to_width(&mgr, "  x = 1\n  y = 2", 600, FONT_DEFAULT, 1, context.allocator)
	defer delete(got)
	testing.expect_value(t, got, "  x = 1\n  y = 2")
}

@(test)
wrap_code_preserves_interior_spacing :: proc(t: ^testing.T) {
	backend := Backend{width = 640, height = 480}
	mgr: Manager
	init(&mgr, &backend)
	defer shutdown(&mgr)

	// Runs of spaces used for alignment are kept verbatim when the line fits —
	// unlike wrap_text_to_width, which would collapse them to single spaces.
	got := wrap_code_to_width(&mgr, "a   =   1", 600, FONT_DEFAULT, 1, context.allocator)
	defer delete(got)
	testing.expect_value(t, got, "a   =   1")
}

@(test)
wrap_code_noop_for_nonpositive_width :: proc(t: ^testing.T) {
	backend := Backend{width = 640, height = 480}
	mgr: Manager
	init(&mgr, &backend)
	defer shutdown(&mgr)

	// Width <= 0 means the column isn't measured yet; return the text untouched.
	got := wrap_code_to_width(&mgr, "  indented", 0, FONT_DEFAULT, 1, context.allocator)
	testing.expect_value(t, got, "  indented")
}

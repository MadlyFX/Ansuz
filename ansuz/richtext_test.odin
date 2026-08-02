#+build !freestanding
package ansuz

import "core:testing"

// Like wrap_test.odin, these run against the builtin 5x7 bitmap font, whose
// advance is exactly FONT_CHAR_WIDTH (6px) at scale 1 — so a five-letter word is
// 30px wide and wrap points can be reasoned about exactly.

@(private = "file")
plain_fonts :: proc() -> Style_Fonts {
	return Style_Fonts{}
}

@(test)
styled_text_merges_same_style_fragments :: proc(t: ^testing.T) {
	backend := Backend{width = 640, height = 480}
	mgr: Manager
	init(&mgr, &backend)
	defer shutdown(&mgr)

	spans := []Styled_Span{{text = "hello "}, {text = "world", style = {.Bold}}}
	runs, lines, _ := layout_styled_text(&mgr, spans, plain_fonts(), 1, 0, context.allocator)
	defer destroy_styled_runs(runs)

	testing.expect_value(t, lines, 1)
	testing.expect_value(t, len(runs), 2)
	// The separating space rides along with the run before it, so the emphasized
	// run starts exactly where its first glyph does.
	testing.expect_value(t, runs[0].text, "hello ")
	testing.expect_value(t, runs[0].x, f32(0))
	testing.expect_value(t, runs[1].text, "world")
	testing.expect_value(t, runs[1].x, f32(36))
	testing.expect(t, .Bold in runs[1].style)
}

@(test)
styled_text_never_breaks_inside_a_word :: proc(t: ^testing.T) {
	backend := Backend{width = 640, height = 480}
	mgr: Manager
	init(&mgr, &backend)
	defer shutdown(&mgr)

	// "bo"+"ld" is one word written as two spans (**bo**ld). At a 30px column the
	// preceding word must move to its own line rather than the word splitting at
	// the emphasis boundary.
	spans := []Styled_Span{{text = "xx "}, {text = "bo", style = {.Bold}}, {text = "ld"}}
	runs, lines, _ := layout_styled_text(&mgr, spans, plain_fonts(), 1, 30, context.allocator)
	defer destroy_styled_runs(runs)

	testing.expect_value(t, lines, 2)
	testing.expect_value(t, len(runs), 3)
	testing.expect_value(t, runs[0].line, 0)
	testing.expect_value(t, runs[1].line, 1)
	testing.expect_value(t, runs[1].x, f32(0))
	testing.expect_value(t, runs[2].line, 1)
	testing.expect_value(t, runs[2].x, f32(12))
}

@(test)
styled_text_keeps_hard_line_breaks :: proc(t: ^testing.T) {
	backend := Backend{width = 640, height = 480}
	mgr: Manager
	init(&mgr, &backend)
	defer shutdown(&mgr)

	spans := []Styled_Span{{text = "one\ntwo", style = {.Strike}}}
	runs, lines, line_height := layout_styled_text(&mgr, spans, plain_fonts(), 1, 0, context.allocator)
	defer destroy_styled_runs(runs)

	testing.expect_value(t, lines, 2)
	testing.expect_value(t, len(runs), 2)
	testing.expect_value(t, runs[1].text, "two")
	testing.expect_value(t, runs[1].line, 1)
	testing.expect_value(t, runs[1].x, f32(0))
	testing.expect_value(t, line_height, get_line_height(&mgr, FONT_BUILTIN, 1))
}

@(test)
styled_text_hard_breaks_a_word_wider_than_the_column :: proc(t: ^testing.T) {
	backend := Backend{width = 640, height = 480}
	mgr: Manager
	init(&mgr, &backend)
	defer shutdown(&mgr)

	spans := []Styled_Span{{text = "aaaaaaaaaa"}}
	runs, lines, _ := layout_styled_text(&mgr, spans, plain_fonts(), 1, 30, context.allocator)
	defer destroy_styled_runs(runs)

	testing.expect_value(t, lines, 2)
	testing.expect_value(t, len(runs), 2)
	testing.expect_value(t, runs[0].text, "aaaaa")
	testing.expect_value(t, runs[1].text, "aaaaa")
}

@(test)
styled_text_size_covers_every_line :: proc(t: ^testing.T) {
	backend := Backend{width = 640, height = 480}
	mgr: Manager
	init(&mgr, &backend)
	defer shutdown(&mgr)

	spans := []Styled_Span{{text = "hello world foo"}}
	runs, lines, line_height := layout_styled_text(&mgr, spans, plain_fonts(), 1, 60, context.allocator)
	defer destroy_styled_runs(runs)

	size := styled_runs_size(runs, lines, line_height)
	testing.expect_value(t, lines, 2)
	testing.expect(t, size.x <= 60)
	testing.expect_value(t, size.y, line_height * 2)
}

@(test)
style_font_falls_back_to_a_loaded_face :: proc(t: ^testing.T) {
	fonts := Style_Fonts {
		regular = Font_Handle(1),
		bold    = Font_Handle(2),
	}
	// No italic loaded: italic borrows regular, bold+italic borrows bold, so text
	// stays legible instead of vanishing into an unloaded handle.
	testing.expect_value(t, style_font(fonts, {.Italic}), Font_Handle(1))
	testing.expect_value(t, style_font(fonts, {.Bold, .Italic}), Font_Handle(2))
	testing.expect_value(t, style_font(fonts, {.Mono}), Font_Handle(1))
	testing.expect_value(t, style_font(fonts, {}), Font_Handle(1))
}

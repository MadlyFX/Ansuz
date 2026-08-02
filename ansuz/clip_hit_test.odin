#+build !freestanding
package ansuz

import "core:testing"

// Hit testing across a scroll container's edge. A scrollbox's children keep
// their full translated rects — nothing clamps them to the viewport — so the
// rows below the fold sit on top of whatever is laid out under the container.
// compute_interaction is supposed to turn them away by their clip, and
// frame_end's has_prev_clip/prev_clip snapshot is what feeds that check.

// Builds a 300px scroll viewport over 900px of rows with a "composer" bar as the
// next sibling below it, and returns the interactions of the row that would sit
// under the bar and of the bar itself.
@(private = "file")
build_stream_over_bar :: proc(
	mgr: ^Manager,
	bar_height: f32,
) -> (
	under_bar: Interaction,
	bar: Interaction,
) {
	frame_begin(mgr, 1.0 / 60.0)
	flex_begin(mgr, axis = .Vertical, size = {SIZE_GROW, SIZE_GROW})
	scroll_begin(mgr, size = {SIZE_GROW, SIZE_GROW})
	for i in 0 ..< 9 {
		push_id_int(mgr, i)
		row := button(mgr, "", size = {SIZE_GROW, size_fixed(100)})
		if .Pressed in row || .Clicked in row {
			under_bar = row
		}
		pop_id(mgr)
	}
	scroll_end(mgr)
	bar = button(mgr, "bar", size = {SIZE_GROW, size_fixed(bar_height)})
	flex_end(mgr)
	frame_end(mgr)
	return
}

@(test)
a_press_below_a_scroll_container_belongs_to_what_is_under_it :: proc(t: ^testing.T) {
	backend := Backend{width = 400, height = 400}
	mgr: Manager
	init(&mgr, &backend)
	defer shutdown(&mgr)

	// Two frames so the rects the hit test reads exist.
	build_stream_over_bar(&mgr, 100)
	build_stream_over_bar(&mgr, 100)

	// y = 350 is inside the bar (300..400) and, in the stream's own untrimmed
	// coordinates, inside the fourth row.
	mgr.input.mouse_x = 200
	mgr.input.mouse_y = 350
	mgr.input.mouse_left = true
	mgr.input.mouse_left_pressed = true
	row_press, bar_press := build_stream_over_bar(&mgr, 100)
	testing.expect(t, .Pressed not_in row_press, "a row below the fold must not take the press")
	testing.expect(t, .Pressed in bar_press, "the bar must take the press")

	mgr.input.mouse_left = false
	mgr.input.mouse_left_pressed = false
	row_click, bar_click := build_stream_over_bar(&mgr, 100)
	testing.expect(t, .Clicked not_in row_click, "a row below the fold must not take the click")
	testing.expect(t, .Clicked in bar_click, "the bar must take the click")
}

@(test)
scrolled_rows_report_the_container_as_their_clip :: proc(t: ^testing.T) {
	backend := Backend{width = 400, height = 400}
	mgr: Manager
	init(&mgr, &backend)
	defer shutdown(&mgr)

	build_stream_over_bar(&mgr, 100)
	build_stream_over_bar(&mgr, 100)

	// The tree is walked twice — once for the normal layer, once for floating
	// boxes — and only the pass that draws a box may write its clip. A second
	// pass writing over the first left every row unclipped, which silently
	// disabled the guard above.
	clipped := 0
	for _, state in mgr.widget_states {
		if state.has_prev_clip && state.prev_clip.h == 300 {
			clipped += 1
		}
	}
	testing.expect(t, clipped >= 9, "every scrolled row should carry the container's clip")
}

@(test)
a_press_is_released_even_when_its_owner_is_scrolled_away :: proc(t: ^testing.T) {
	backend := Backend{width = 400, height = 400}
	mgr: Manager
	init(&mgr, &backend)
	defer shutdown(&mgr)

	// Returns the top row's interaction, and whichever row took a press.
	build :: proc(mgr: ^Manager, scroll: f32) -> (first, pressed: Interaction) {
		frame_begin(mgr, 1.0 / 60.0)
		ss := scroll_begin(mgr, size = {SIZE_GROW, size_fixed(300)})
		ss.offset_y = scroll
		for i in 0 ..< 9 {
			push_id_int(mgr, i)
			row := button(mgr, "", size = {SIZE_GROW, size_fixed(100)})
			if i == 0 {
				first = row
			}
			if .Pressed in row {
				pressed = row
			}
			pop_id(mgr)
		}
		scroll_end(mgr)
		frame_end(mgr)
		return
	}

	build(&mgr, 0)
	build(&mgr, 0)

	mgr.input.mouse_x = 200
	mgr.input.mouse_y = 50
	mgr.input.mouse_left = true
	mgr.input.mouse_left_pressed = true
	press, _ := build(&mgr, 0)
	testing.expect(t, .Pressed in press, "the top row owns the press")

	// It scrolls out of the viewport while the button is still held. The clip
	// check now turns it away, and the branch that hands active_id back sits
	// below that check — so without a release of its own the press would stay
	// pinned to a row that can no longer see it, and nothing in the app could
	// ever be pressed again.
	mgr.input.mouse_left_pressed = false
	build(&mgr, 600)
	mgr.input.mouse_left = false
	build(&mgr, 600)
	testing.expect_value(t, mgr.active_id, ID_NONE)

	mgr.input.mouse_left = true
	mgr.input.mouse_left_pressed = true
	_, after := build(&mgr, 600)
	testing.expect(t, .Pressed in after, "a fresh press still lands afterwards")
}

@(test)
a_modal_owner_blocks_a_scrollbar_grab_underneath_it :: proc(t: ^testing.T) {
	backend := Backend{width = 400, height = 400}
	mgr: Manager
	init(&mgr, &backend)
	defer shutdown(&mgr)

	// The scrollbar is hit tested by hand inside scroll_begin rather than through
	// compute_interaction, so it has to honour the same ownership rules or it
	// becomes the one control a modal cannot cover.
	build :: proc(mgr: ^Manager, owner: Widget_ID) -> ^Scroll_State {
		frame_begin(mgr, 1.0 / 60.0)
		mgr.modal_owner = owner
		ss := scroll_begin(mgr, size = {SIZE_GROW, SIZE_GROW})
		for i in 0 ..< 9 {
			push_id_int(mgr, i)
			box(mgr, size = {SIZE_GROW, size_fixed(100)})
			pop_id(mgr)
		}
		scroll_end(mgr)
		frame_end(mgr)
		return ss
	}

	build(&mgr, ID_NONE)
	build(&mgr, ID_NONE)

	// Press on the bar's track, at the right edge of the container.
	mgr.input.mouse_x = 393
	mgr.input.mouse_y = 200
	mgr.input.mouse_left = true
	mgr.input.mouse_left_pressed = true
	blocked := build(&mgr, id_from_string(&mgr.id_stack, "some-modal"))
	testing.expect(t, !blocked.dragging, "a modal's press must not grab the bar under it")

	mgr.input.mouse_left = false
	mgr.input.mouse_left_pressed = false
	build(&mgr, ID_NONE)

	mgr.input.mouse_left = true
	mgr.input.mouse_left_pressed = true
	free := build(&mgr, ID_NONE)
	testing.expect(t, free.dragging, "with nothing over it the bar still grabs")
}

#+build !freestanding
package ansuz

import "core:testing"

// A 100px-tall container showing 100px of a 200px page: the thumb is half the
// track, and the other half of the track is the whole scrollable range.
CONTAINER :: Rect{0, 0, 60, 100}

@(test)
scrollbar_thumb_spans_the_visible_fraction :: proc(t: ^testing.T) {
	track, thumb := scrollbar_rects(CONTAINER, .Vertical, 0, 200, 100, 8, 2)

	// The track runs the container's height minus the inset at each end, and hugs
	// the right edge inside it.
	testing.expect_value(t, track.x, f32(50)) // 60 - 8 - 2
	testing.expect_value(t, track.y, f32(2))
	testing.expect_value(t, track.w, f32(8))
	testing.expect_value(t, track.h, f32(96))

	// Half the page is visible, so the thumb is half the track, parked at the top.
	testing.expect_value(t, thumb.y, f32(2))
	testing.expect_value(t, thumb.h, f32(48))
	testing.expect_value(t, thumb.x, track.x)
}

@(test)
scrollbar_thumb_tracks_the_offset :: proc(t: ^testing.T) {
	track, thumb := scrollbar_rects(CONTAINER, .Vertical, 50, 200, 100, 8, 2)
	// Halfway down a 100px range puts the thumb halfway along its travel.
	testing.expect_value(t, thumb.y, track.y + (track.h - thumb.h) / 2)

	_, bottom := scrollbar_rects(CONTAINER, .Vertical, 100, 200, 100, 8, 2)
	testing.expect_value(t, bottom.y, track.y + track.h - bottom.h)

	// An offset past the end cannot push the thumb off the track.
	_, past := scrollbar_rects(CONTAINER, .Vertical, 1_000, 200, 100, 8, 2)
	testing.expect_value(t, past.y, bottom.y)
}

@(test)
scrollbar_keeps_a_grabbable_thumb_on_a_long_page :: proc(t: ^testing.T) {
	// One screen of a hundred: the proportional thumb would be a 1px sliver, so it
	// stops shrinking at SCROLLBAR_MIN_THUMB and still reaches the track's end.
	track, thumb := scrollbar_rects(CONTAINER, .Vertical, 0, 10_000, 100, 8, 2)
	testing.expect_value(t, thumb.h, SCROLLBAR_MIN_THUMB)

	_, end := scrollbar_rects(CONTAINER, .Vertical, 9_900, 10_000, 100, 8, 2)
	testing.expect_value(t, end.y, track.y + track.h - SCROLLBAR_MIN_THUMB)
}

@(test)
scrollbar_lies_along_the_bottom_when_horizontal :: proc(t: ^testing.T) {
	track, thumb := scrollbar_rects(CONTAINER, .Horizontal, 0, 120, 60, 8, 2)
	testing.expect_value(t, track.x, f32(2))
	testing.expect_value(t, track.y, f32(90)) // 100 - 8 - 2
	testing.expect_value(t, track.w, f32(56))
	testing.expect_value(t, thumb.w, f32(28))
	testing.expect_value(t, thumb.y, track.y)
}

@(test)
dragging_the_thumb_scrolls_the_container :: proc(t: ^testing.T) {
	backend := Backend{width = 640, height = 480}
	mgr: Manager
	init(&mgr, &backend)
	defer shutdown(&mgr)

	// Frame one lays the container out; the scrollbar is hit tested against the
	// rect and measurements it was drawn from, which only exist from frame two.
	build :: proc(mgr: ^Manager) -> ^Scroll_State {
		frame_begin(mgr, 1.0 / 60.0)
		ss := scroll_begin(mgr, size = {size_fixed(60), size_fixed(100)}, scrollbar_width = 8, scrollbar_inset = 2)
		box(mgr, size = {size_fixed(60), size_fixed(200)})
		scroll_end(mgr)
		frame_end(mgr)
		return ss
	}

	ss := build(&mgr)
	testing.expect_value(t, ss.content_h, f32(200))
	testing.expect_value(t, ss.viewport_h, f32(100))

	// The container stretches to the root's width, so its bar sits at x 630..638
	// (640 - width - inset). Press on the thumb, which is the top half of the
	// track, and drag to the bottom.
	mgr.input.mouse_x = 634
	mgr.input.mouse_y = 10
	mgr.input.mouse_left = true
	mgr.input.mouse_left_pressed = true
	ss = build(&mgr)
	testing.expect(t, ss.dragging)
	// The press alone must not move the page: the thumb keeps the spot it was
	// taken hold of.
	testing.expect_value(t, ss.offset_y, f32(0))

	mgr.input.mouse_left_pressed = false
	mgr.input.mouse_y = 98
	ss = build(&mgr)
	testing.expect_value(t, ss.offset_y, f32(100)) // the whole 200-100 range

	// Releasing ends the drag and leaves the page where it was put.
	mgr.input.mouse_left = false
	ss = build(&mgr)
	testing.expect(t, !ss.dragging)
	testing.expect_value(t, ss.offset_y, f32(100))

	// A press away from the bar is not a scroll.
	mgr.input.mouse_x = 300
	mgr.input.mouse_y = 50
	mgr.input.mouse_left = true
	mgr.input.mouse_left_pressed = true
	ss = build(&mgr)
	testing.expect(t, !ss.dragging)
	testing.expect_value(t, ss.offset_y, f32(100))
}

@(test)
pressing_the_empty_track_jumps_the_page_there :: proc(t: ^testing.T) {
	backend := Backend{width = 640, height = 480}
	mgr: Manager
	init(&mgr, &backend)
	defer shutdown(&mgr)

	build :: proc(mgr: ^Manager) -> ^Scroll_State {
		frame_begin(mgr, 1.0 / 60.0)
		ss := scroll_begin(mgr, size = {size_fixed(60), size_fixed(100)}, scrollbar_width = 8, scrollbar_inset = 2)
		box(mgr, size = {size_fixed(60), size_fixed(200)})
		scroll_end(mgr)
		frame_end(mgr)
		return ss
	}

	_ = build(&mgr)

	// Below the thumb: it centres on the press instead of paging by a fixed step,
	// and stays in hand so the same gesture can keep dragging.
	mgr.input.mouse_x = 634
	mgr.input.mouse_y = 90
	mgr.input.mouse_left = true
	mgr.input.mouse_left_pressed = true
	ss := build(&mgr)
	testing.expect(t, ss.dragging)
	// Thumb 48 tall on a 96 track: centring it on y=90 pins it to the bottom.
	testing.expect_value(t, ss.offset_y, f32(100))
}

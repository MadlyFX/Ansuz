#+build !freestanding
package ansuz

import "core:testing"

@(test)
text_selection_bounds_follow_anchor_and_cursor :: proc(t: ^testing.T) {
	state := Text_Input_State{cursor = 2, selection_anchor = 7}
	start, end, selected := text_selection_bounds(&state)
	testing.expect_value(t, start, 2)
	testing.expect_value(t, end, 7)
	testing.expect(t, selected)

	state.cursor = 9
	state.selection_anchor = 4
	start, end, selected = text_selection_bounds(&state)
	testing.expect_value(t, start, 4)
	testing.expect_value(t, end, 9)
	testing.expect(t, selected)
	value := string("copy this value")
	text, text_selected := selected_text(transmute([]u8)value, &state)
	testing.expect(t, text_selected)
	testing.expect_value(t, text, " this")
}

@(test)
deleting_a_text_selection_keeps_unselected_text :: proc(t: ^testing.T) {
	buffer := make([dynamic]u8)
	defer delete(buffer)
	append(&buffer, "copy selected text")
	state := Text_Input_State{cursor = 13, selection_anchor = 4}

	testing.expect(t, delete_text_selection(&buffer, &state))
	testing.expect_value(t, string(buffer[:]), "copy text")
	testing.expect_value(t, state.cursor, 4)
	testing.expect_value(t, state.selection_anchor, 4)
}

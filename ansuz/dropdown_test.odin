package ansuz

import "core:testing"

render_local_options_dropdown :: proc(mgr: ^Manager, selected: ^int) {
	options := [?]string{"Disabled", "Custom upload API", "Dropbox", "Google Drive"}
	_ = dropdown(mgr, selected, options[:])
}

@(test)
dropdown_popup_retains_caller_local_options_until_frame_end :: proc(t: ^testing.T) {
	backend := Backend{width = 640, height = 480}
	mgr: Manager
	init(&mgr, &backend)
	defer shutdown(&mgr)
	selected := 0

	frame_begin(&mgr, 0)
	render_local_options_dropdown(&mgr, &selected)
	testing.expect(t, len(mgr.widget_box_map) > 0)
	owner_id := mgr.widget_box_map[len(mgr.widget_box_map) - 1].id
	frame_end(&mgr)

	mgr.popup_owner = owner_id
	frame_begin(&mgr, 0)
	render_local_options_dropdown(&mgr, &selected)
	testing.expect_value(t, len(mgr.popup_draws), 1)
	testing.expect_value(t, mgr.popup_draws[0].dropdown_list.options[2], "Dropbox")
	frame_end(&mgr)
}

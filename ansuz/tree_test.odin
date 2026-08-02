#+build !freestanding
package ansuz

import "core:testing"

@(test)
tree_nodes_track_depth_and_guide_continuation :: proc(t: ^testing.T) {
	backend := Backend{width = 640, height = 480}
	mgr: Manager
	init(&mgr, &backend)
	defer shutdown(&mgr)

	expanded_root := true
	expanded_child := false

	frame_begin(&mgr, 0)
	tree_begin(&mgr)

	open_root, _ := tree_node_begin(&mgr, "Root", &expanded_root, is_last = true)
	testing.expect(t, open_root)
	testing.expect_value(t, mgr.tree_depth, 1)
	testing.expect_value(t, mgr.tree_continues[0], false)

	open_child, _ := tree_node_begin(&mgr, "Child", &expanded_child)
	testing.expect(t, !open_child)
	testing.expect_value(t, mgr.tree_depth, 2)
	testing.expect_value(t, mgr.tree_continues[1], true)
	tree_node_end(&mgr)

	_ = tree_leaf(&mgr, "Leaf", is_last = true)

	tree_node_end(&mgr)
	testing.expect_value(t, mgr.tree_depth, 0)

	tree_end(&mgr)
	frame_end(&mgr)
}

@(test)
collapsed_tree_nodes_still_balance_the_nesting_scope :: proc(t: ^testing.T) {
	backend := Backend{width = 640, height = 480}
	mgr: Manager
	init(&mgr, &backend)
	defer shutdown(&mgr)

	expanded := false

	frame_begin(&mgr, 0)
	tree_begin(&mgr)
	open, _ := tree_node_begin(&mgr, "Collapsed", &expanded, is_last = true)
	testing.expect(t, !open)
	testing.expect_value(t, mgr.tree_depth, 1)
	tree_node_end(&mgr)
	tree_end(&mgr)
	frame_end(&mgr)
}

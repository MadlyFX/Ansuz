package ogui

// --- Image System ---
// Backend-agnostic image handles. The backend creates textures from pixel data,
// and the framework references them via opaque handles.

Image_Handle :: struct {
	ptr:    rawptr,   // Backend-specific texture pointer
	width:  i32,
	height: i32,
}

IMAGE_NONE :: Image_Handle{}

// Image widget — displays an image within a layout box.
image :: proc(
	mgr:      ^Manager,
	img:      Image_Handle,
	size:     [2]Size_Spec = SIZE_FIT_FIT,
	tint:     Color        = COLOR_WHITE,
	loc       := #caller_location,
) -> int {
	actual_size := size
	if actual_size[0].kind == .Fit {
		actual_size[0] = size_fixed(f32(img.width))
	}
	if actual_size[1].kind == .Fit {
		actual_size[1] = size_fixed(f32(img.height))
	}

	idx := box(mgr, size = actual_size, loc = loc)

	// Defer image drawing until after layout
	append(&mgr.deferred_draws, Deferred_Draw{
		box_index = idx,
		kind      = .Image,
		image     = Deferred_Image_Data{
			handle = img,
			tint   = tint,
		},
	})

	return idx
}

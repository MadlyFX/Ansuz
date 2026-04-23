package main

import "core:fmt"
import ansuz "../ansuz"
import backend "../backend_sdl"
import sdl "vendor:sdl3"
import e2e "e2econfig"
import "base:runtime"
import "core:c"
import os "core:os"

sdl_data : ^backend.SDL_Data

file_dialog_callback :: proc "c" (
userdata: rawptr,
filelist: ^^c.char,
filter: c.int,
) {
    context = runtime.default_context()
    fmt.println("Callback triggered!")

    if filelist == nil {
        fmt.println("Error or cancelled.")
        fmt.println((sdl.GetError()))
        return
    }
    if (filelist == nil) {
        fmt.println((sdl.GetError()))
        return
    } else if (filelist^ == nil) {
        fmt.println("The user did not select any file.");
        return
    }

    file_ptr := cstring(filelist^)

    if file_ptr == nil {
        fmt.println((sdl.GetError()))
    }

    fmt.printf("Selected file %d: %s\n", 0, file_ptr)

    handle, err := os.open(string(file_ptr), os.O_WRONLY | os.O_CREATE)
    if err != nil {
        fmt.println("Error opening file:", err)
        return
    }

    os.write_string(handle, e2e.out_string)
    os.close(handle)

}

main :: proc() {
	sdl := backend.create(900, 800, "ansuz Demo")
	sdl_data = cast(^backend.SDL_Data)sdl.user_data
	if !sdl.init(&sdl, sdl.width, sdl.height) {
		return
	}
	defer sdl.shutdown(&sdl)

	mgr: ansuz.Manager
	ansuz.init(&mgr, &sdl)
	defer ansuz.shutdown(&mgr)

	opensans, _ := ansuz.load_font(&mgr, ansuz.OPENSANS_REGULAR, 96, ansuz.FONT_EXTRA_CODEPOINTS[:])
	ansuz.set_default_font(&mgr, opensans)
	ansuz.DEFAULT_FONT_SCALE = ansuz.OPENSANS_FONT_SCALE
	opensans_bold, _ := ansuz.load_font(&mgr, ansuz.OPENSANS_BOLD, 96)

	e2e.Init_Gui(&mgr, Save_File, opensans, opensans_bold)

	for !ansuz.should_quit(&mgr) {
		ansuz.frame_begin(&mgr)
		e2e.Draw_Gui()

		ansuz.frame_end(&mgr)
	}
}

Save_File :: proc() -> bool {
    filters := [1]sdl.DialogFileFilter{
        { name = "E2E Config Files", pattern = "json" },
    }

    sdl.ShowSaveFileDialog(
    sdl.DialogFileCallback(file_dialog_callback),
    nil, // userdata
    sdl_data.window,
    &filters[0],
    1, // nfilters
    "e2e_config.json", // default_location
    )

    return true

}

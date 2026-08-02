# Ansuz

Ansuz is a cross-platform UI framework written in Odin.

It offers an immediate-mode authoring style with a retained internal state manager, so you can write straightforward per-frame UI code while the framework tracks widget state, interaction, and transitions across frames.

![Demo image](demo.png?v=4)


## Status
The API is stabilized for 1.0. Naming is consistent across the widget set (see
"Colors and Theming" below), all widgets take their colors, fonts, scale, and
sizing as parameters with themed defaults, and interactive widgets support a
`disabled` state. PRs welcome.

## Highlights

- Immediate-mode API with internal state retention
- Flexible layout system:
  - Flex containers
  - Grid containers
  - Scroll containers
  - Stack containers and floating overlay layers
- Built-in widgets:
  - Label and heading
  - Button
  - Menu button
  - Checkbox
  - Slider
  - Dropdown
  - Text input (single-line and multi-line) with mouse/keyboard text selection and clipboard support
  - Image widget
  - Collapsible header
  - Tree (explorer-style disclosure nodes, leaf rows, and indent guide lines)
  - Disclosure and hamburger icons
- Popup rendering for dropdowns and menu lists with scroll support
- High-DPI aware rendering on the SDL3 and WebGL backends (layout and input stay in logical pixels while rendering fills every physical pixel)
- Animation support with easing functions and optional host-provided delta time
- Font support:
  - Built-in bitmap font
  - Manager default font plus per-widget overrides
  - TTF loading for higher-quality text
- Multiple backends:
  - SDL3 renderer backend
  - Software renderer backend (embedded-style framebuffer path)
  - WebGL backend for `js_wasm32`
- C ABI and Arduino static-library workflow for freestanding hosts

## Repository Layout

- `ansuz/`: Core UI framework package
- `backend_sdl/`: SDL3 backend implementation
- `backend_soft/`: Software framebuffer backend
- `backend_webgl/`: WebGL backend for web builds
- `bindings/c/`: Complete C ABI and public header for Arduino/freestanding use
- `demo/`: Desktop SDL demo
- `demo_soft/`: Software renderer demo
- `demo_web/`: WebAssembly/WebGL demo
- `demo_arduino_oled/`: Arduino OLED demo and static-library build

## Requirements

- Odin compiler (recent version with `js_wasm32` support for web builds)
- SDL3 available for desktop demos/backends
- Python (optional, only to serve web demo locally)

## Quick Start (Desktop SDL)

This is the minimal frame loop pattern with the SDL backend:

```odin
package main

import ansuz "../ansuz"
import backend "../backend_sdl"

main :: proc() {
    sdl := backend.create(960, 540, "ansuz app")
    if !sdl.init(&sdl, sdl.width, sdl.height) {
        return
    }
    defer sdl.shutdown(&sdl)

    mgr: ansuz.Manager
    ansuz.init(&mgr, &sdl)
    defer ansuz.shutdown(&mgr)

    // Built-in bitmap font defaults are available immediately.
    ansuz.DEFAULT_FONT_SCALE = 2

    for !ansuz.should_quit(&mgr) {
        ansuz.frame_begin(&mgr)

        ansuz.flex_begin(
            &mgr,
            axis = .Vertical,
            gap = 10,
            size = {ansuz.SIZE_GROW, ansuz.SIZE_GROW},
            padding = {16, 16, 16, 16},
        )

        ansuz.label(&mgr, "Hello from ansuz")
        _ = ansuz.button(&mgr, "Click")

        ansuz.flex_end(&mgr)

        ansuz.frame_end(&mgr)
        free_all(context.temp_allocator)
    }
}
```

## Running the Demos

From the repository root:

### 1. SDL Desktop Demo

```powershell
odin run demo
```

On Windows, make sure `SDL3.dll` is discoverable by the executable. When running
from the repository root, either keep `SDL3.dll` in the root directory or have it
on `PATH`.

### 2. Software Renderer Demo

```powershell
odin run demo_soft
```

![Demo image](arduino2.png)

### 3. Web Demo (WASM + WebGL)

Windows:

```powershell
cd demo_web
.\build.bat
cd web
py -m http.server 8080
```

macOS/Linux:

```bash
cd demo_web
./build.sh
cd web
python3 -m http.server 8080
```

Then open `http://localhost:8080`.

### 4. Arduino Static Library

```powershell
cd demo_arduino_oled
.\build.bat m4
# or:
.\build.bat rp2040
```

The build produces `build/libansuz.a` and `build/ansuz.h`. The Arduino sketch
constructs the UI directly through the C interface; no application-specific UI
code remains inside the Odin object. See
[`bindings/c/README.md`](bindings/c/README.md) for the lifecycle and API usage.

## Core Frame Lifecycle

Typical usage follows this order each frame:

1. `frame_begin`
2. Build layout and widgets (`flex_begin`/`flex_end`, `grid_begin`/`grid_end`, widget calls)
3. `frame_end`
4. `free_all(context.temp_allocator)` if the frame used Odin temporary allocations

Internally, ansuz resolves layout, emits draw commands, handles deferred text/custom draws, executes backend rendering, and updates persistent widget state.

`frame_begin` also accepts an optional `dt` value. Pass `frame_begin(&mgr, dt)`
when the host application owns timing, or omit `dt` to use the default animation
tick path.

## Temporary Allocations

Ansuz resets its internal frame arena at `frame_begin`, but it does not reset the
host application's `context.temp_allocator`. If your frame code builds labels,
menus, option arrays, formatted strings, or other short-lived values with
`context.temp_allocator` or helpers such as `fmt.tprintf`, reset that allocator
after `frame_end`:

```odin
for !ansuz.should_quit(&mgr) {
    ansuz.frame_begin(&mgr, dt)

    // Build UI here. Values allocated from context.temp_allocator only need to
    // live until frame_end has rendered the frame.

    ansuz.frame_end(&mgr)
    free_all(context.temp_allocator)
}
```

Do not store pointers, slices, or strings allocated from `context.temp_allocator`
in persistent app state. Clone those values with the regular allocator first, or
store them in your own explicitly managed allocation.

## Layout, Floating UI, and Popups

Use `flex_begin`/`flex_end` for row or column layout, `grid_begin`/`grid_end`
for explicit cells, `scroll_begin`/`scroll_end` for clipped scroll regions, and
`stack_begin`/`stack_end` when children should share the same parent rectangle.

Flex containers, stack containers, and leaf `box` calls accept `floating = true`.
Floating boxes are emitted after the normal UI pass, which makes them suitable
for modal backgrounds, dialogs, and other overlays. The manager's `modal_owner`
field can be set while a modal is open so interaction outside the modal's ID
stack is blocked.

Dropdowns and `menu_button` use the popup overlay pass. Popup lists carry their
own font, sizing, text, border, hover, and selected-state colors, and input is
blocked behind an open or just-closed popup to avoid click-through.

## Backends

ansuz is backend-agnostic through the `Backend` interface in `ansuz/backend.odin`.

A backend provides function pointers for:

- Initialization and shutdown
- Per-frame begin/end hooks
- Draw command execution
- Text measurement
- Event polling (mouse, keyboard, scroll wheel, and host file drop where supported)
- Font upload
- Clipboard access for text input where supported
- URL opening (`open_url`) where supported

This allows the same UI code to run on desktop, embedded-style software pipelines, and web targets with backend-specific rendering/event handling.

## Fonts

- Omit `font` to use the manager's default font. The built-in bitmap font is the initial default.
- Use `FONT_BUILTIN` as an explicit per-widget override, even after setting a TTF default.
- Use `load_font` and `set_default_font` to change the manager default for all widgets.
- For the sharpest text, rasterize atlases at the size they will be displayed: `widget scale x FONT_GLYPH_HEIGHT x pixel density` (see the demos; the SDL and WebGL backends expose a `pixel_density` helper). Glyphs are drawn snapped to physical pixels.
- Pass `antialiasing = .None` to `load_font` for hard-edged, unantialiased glyphs (e-ink, low-density LCDs, pixel-art styling). The default is `.Grayscale`.
- Demos use OpenSans for anti-aliased text rendering.

## Colors and Theming

The default palette lives in `ansuz/theme.odin` as `THEME_*` constants, and
every widget takes its colors as parameters defaulted to that palette — no
global theme object to configure, no hidden styling state. One naming rule
holds across the whole API:

- `color` — a single plain `Color` (label text, icon lines)
- `colors` — a `Widget_Color` five-state palette (`bg`, `fg`, `hover`,
  `press`, `focus`) on interactive widgets; each widget documents what its
  slots control
- `text_color` — glyph color on composite widgets (button, checkbox, dropdown, ...)
- `bg_color` — flat background fill on containers and labels

Interactive widgets (`button`, `checkbox`, `slider`, `dropdown`,
`menu_button`, `text_input`) also accept `disabled = true`, which blocks
interaction and renders the widget dimmed.

Scale follows two documented conventions: text widgets take a font scale
defaulting to `DEFAULT_FONT_SCALE`, while composite widgets whose geometry
scales as a whole (checkbox, slider, icons) take a widget multiplier
defaulting to `1.0` and draw their text at `scale * DEFAULT_FONT_SCALE`.

## Animations

Pointer-based helpers such as `animate_f32`, `animate_color`, and `spring_f32`
are still available for ordinary widget state. ID-based variants such as
`animate_f32_id`, `animate_color_id`, `spring_f32_id`, `cancel_animation_id`,
and `is_animating_id` let callers drive animations from explicit widget IDs.

## Current Widget Set

Core widget modules currently include:

- `widgets.odin`
- `menu.odin`
- `checkbox.odin`
- `slider.odin`
- `dropdown.odin`
- `textinput.odin`
- `scroll.odin`
- `image.odin`
- `collapsible.odin`
- `tree.odin`

Additional supporting systems include animations/easing, transitions, interaction state, and reactive value plumbing.

## Notes
- `SDL2.dll` may be present in the workspace, but the current desktop backend implementation imports SDL3 (`vendor:sdl3`).

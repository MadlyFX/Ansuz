# Ansuz C Interface

This binding exposes the Ansuz framework through a stable C ABI suitable for
Arduino and other freestanding applications.

## Memory Ownership

The application supplies:

- An RGBA32 framebuffer with `width * height` pixels.
- A persistent heap buffer used by Ansuz.
- Widget values such as slider floats and checkbox bytes.

Ansuz does not call the platform allocator. The recommended starting heap size
is `ANSUZ_RECOMMENDED_HEAP_SIZE`; applications using images or many text inputs
may need more.

```cpp
static uint32_t framebuffer[128 * 64];
alignas(8) static uint8_t heap[ANSUZ_RECOMMENDED_HEAP_SIZE];

AnsuzInitConfig config = {};
config.width = 128;
config.height = 64;
config.framebuffer = framebuffer;
config.framebuffer_length = 128 * 64;
config.heap = heap;
config.heap_size = sizeof(heap);
config.clear_color = ansuz_rgba(0, 0, 0, 255);

ansuz_init(&config);
```

## Frame Lifecycle

Build the UI between `ansuz_frame_begin` and `ansuz_frame_end`. Pass the frame
delta from `millis()` or another platform clock so animations work without an
operating-system timer.

```cpp
ansuz_frame_begin(delta_seconds);

AnsuzFlexOptions root = ansuz_flex_options_default();
root.axis = ANSUZ_AXIS_VERTICAL;
ansuz_flex_begin(ANSUZ_ID("root"), &root);

ansuz_label(ANSUZ_ID("title"), ANSUZ_STR("Settings"), NULL);
ansuz_slider_f32(ANSUZ_ID("volume"), &volume, NULL);

ansuz_flex_end();
ansuz_frame_end();
```

Every widget and container receives a stable ID. `ANSUZ_ID("name")` hashes a
string literal. Container IDs remain active until their matching end call, so
children are automatically namespaced.

## Input

Inject input before `ansuz_frame_begin`:

```cpp
ansuz_input_pointer(x, y, touch_down, 0, 0);
ansuz_input_scroll(scroll_delta);
ansuz_input_text(ANSUZ_STR("a"));
ansuz_input_key(ANSUZ_KEY_BACKSPACE, 1);
```

Interactions are returned as flags:

```cpp
AnsuzInteraction result = ansuz_button(ANSUZ_ID("save"), ANSUZ_STR("Save"), NULL);
if (result & ANSUZ_INTERACTION_CLICKED) {
    save_settings();
}
```

## Covered API

The interface includes:

- Initialization, shutdown, frame timing, input, and framebuffer access
- ID scopes and widget rectangle queries
- Flex, grid, scroll, box, and grid-cell layout
- Labels, decorated labels, headings, buttons, checkboxes, sliders, dropdowns,
  text inputs, and images
- Widget color and font overrides through option structs
- Float and color animations, springs, cancellation, and animation queries
- Text measurement and low-level drawing commands

Pass `NULL` for an option pointer to use the built-in defaults. To override
individual fields, start with the corresponding `*_options_default()` helper.

The current embedded software backend renders the built-in bitmap font.
The font handle remains part of the ABI so other backends can expose loaded
fonts without changing widget signatures.

The supplied ARM build uses the soft-float calling convention on both Cortex-M4
and RP2040 so its float-bearing API matches typical Arduino toolchains.

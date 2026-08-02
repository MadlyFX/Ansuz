#ifndef ANSUZ_H
#define ANSUZ_H

#include <stddef.h>
#include <stdint.h>

#define ANSUZ_RECOMMENDED_HEAP_SIZE (48u * 1024u)
#define ANSUZ_FONT_BUILTIN ((uint32_t)0)
#define ANSUZ_FONT_DEFAULT ((uint32_t)0xffffffffu)

#ifdef __cplusplus
#define ANSUZ_ALIGNAS(bytes) alignas(bytes)
#else
#define ANSUZ_ALIGNAS(bytes) _Alignas(bytes)
#endif

typedef uint64_t AnsuzId;
typedef uint32_t AnsuzInteraction;

typedef enum AnsuzInteractionFlag {
    ANSUZ_INTERACTION_HOVERED = 1u << 0,
    ANSUZ_INTERACTION_PRESSED = 1u << 1,
    ANSUZ_INTERACTION_CLICKED = 1u << 2,
    ANSUZ_INTERACTION_FOCUSED = 1u << 3,
} AnsuzInteractionFlag;

typedef enum AnsuzAxis {
    ANSUZ_AXIS_HORIZONTAL = 0,
    ANSUZ_AXIS_VERTICAL = 1,
} AnsuzAxis;

typedef enum AnsuzSizeKind {
    ANSUZ_SIZE_FIXED = 0,
    ANSUZ_SIZE_PERCENT = 1,
    ANSUZ_SIZE_GROW = 2,
    ANSUZ_SIZE_FIT = 3,
    ANSUZ_SIZE_AUTO = 4, /* legacy alias of ANSUZ_SIZE_FIT */
} AnsuzSizeKind;

typedef enum AnsuzJustify {
    ANSUZ_JUSTIFY_START = 0,
    ANSUZ_JUSTIFY_CENTER = 1,
    ANSUZ_JUSTIFY_END = 2,
    ANSUZ_JUSTIFY_SPACE_BETWEEN = 3,
    ANSUZ_JUSTIFY_SPACE_AROUND = 4,
    ANSUZ_JUSTIFY_SPACE_EVENLY = 5,
} AnsuzJustify;

typedef enum AnsuzAlign {
    ANSUZ_ALIGN_START = 0,
    ANSUZ_ALIGN_CENTER = 1,
    ANSUZ_ALIGN_END = 2,
    ANSUZ_ALIGN_STRETCH = 3,
} AnsuzAlign;

typedef enum AnsuzAffix {
    ANSUZ_AFFIX_NONE = 0,
    ANSUZ_AFFIX_PREFIX = 1,
    ANSUZ_AFFIX_SUFFIX = 2,
} AnsuzAffix;

typedef enum AnsuzKey {
    ANSUZ_KEY_BACKSPACE = 0,
    ANSUZ_KEY_DELETE = 1,
    ANSUZ_KEY_LEFT = 2,
    ANSUZ_KEY_RIGHT = 3,
    ANSUZ_KEY_UP = 4,
    ANSUZ_KEY_DOWN = 5,
    ANSUZ_KEY_HOME = 6,
    ANSUZ_KEY_END = 7,
    ANSUZ_KEY_ENTER = 8,
    ANSUZ_KEY_SHIFT = 9,
    ANSUZ_KEY_CTRL = 10,
} AnsuzKey;

typedef enum AnsuzEase {
    ANSUZ_EASE_LINEAR = 0,
    ANSUZ_EASE_QUADRATIC_IN,
    ANSUZ_EASE_QUADRATIC_OUT,
    ANSUZ_EASE_QUADRATIC_IN_OUT,
    ANSUZ_EASE_CUBIC_IN,
    ANSUZ_EASE_CUBIC_OUT,
    ANSUZ_EASE_CUBIC_IN_OUT,
    ANSUZ_EASE_QUARTIC_IN,
    ANSUZ_EASE_QUARTIC_OUT,
    ANSUZ_EASE_QUARTIC_IN_OUT,
    ANSUZ_EASE_QUINTIC_IN,
    ANSUZ_EASE_QUINTIC_OUT,
    ANSUZ_EASE_QUINTIC_IN_OUT,
    ANSUZ_EASE_SINE_IN,
    ANSUZ_EASE_SINE_OUT,
    ANSUZ_EASE_SINE_IN_OUT,
    ANSUZ_EASE_CIRCULAR_IN,
    ANSUZ_EASE_CIRCULAR_OUT,
    ANSUZ_EASE_CIRCULAR_IN_OUT,
    ANSUZ_EASE_EXPONENTIAL_IN,
    ANSUZ_EASE_EXPONENTIAL_OUT,
    ANSUZ_EASE_EXPONENTIAL_IN_OUT,
    ANSUZ_EASE_ELASTIC_IN,
    ANSUZ_EASE_ELASTIC_OUT,
    ANSUZ_EASE_ELASTIC_IN_OUT,
    ANSUZ_EASE_BACK_IN,
    ANSUZ_EASE_BACK_OUT,
    ANSUZ_EASE_BACK_IN_OUT,
    ANSUZ_EASE_BOUNCE_IN,
    ANSUZ_EASE_BOUNCE_OUT,
    ANSUZ_EASE_BOUNCE_IN_OUT,
} AnsuzEase;

typedef struct AnsuzColor {
    uint8_t r, g, b, a;
} AnsuzColor;

typedef struct AnsuzString {
    const uint8_t *data;
    uint32_t length;
} AnsuzString;

typedef struct AnsuzSizeSpec {
    uint32_t kind;
    float value;
} AnsuzSizeSpec;

typedef struct AnsuzSize {
    AnsuzSizeSpec width;
    AnsuzSizeSpec height;
} AnsuzSize;

typedef struct AnsuzEdges {
    float top, right, bottom, left;
} AnsuzEdges;

typedef struct AnsuzVec2 {
    float x, y;
} AnsuzVec2;

typedef struct AnsuzRect {
    float x, y, width, height;
} AnsuzRect;

typedef struct AnsuzWidgetColor {
    AnsuzColor bg, fg, hover, press, focus;
} AnsuzWidgetColor;

typedef struct AnsuzInitConfig {
    int32_t width;
    int32_t height;
    uint32_t *framebuffer;
    size_t framebuffer_length;
    uint8_t *heap;
    size_t heap_size;
    AnsuzColor clear_color;
} AnsuzInitConfig;

typedef struct AnsuzFlexOptions {
    uint32_t axis;
    uint32_t justify;
    uint32_t align;
    float gap;
    AnsuzSize size;
    AnsuzEdges padding;
    AnsuzColor bg_color;
} AnsuzFlexOptions;

typedef struct AnsuzGridOptions {
    float gap;
    AnsuzSize size;
    AnsuzEdges padding;
    AnsuzColor bg_color;
} AnsuzGridOptions;

typedef struct AnsuzBoxOptions {
    AnsuzSize size;
    AnsuzColor bg_color;
    AnsuzEdges margin;
} AnsuzBoxOptions;

typedef struct AnsuzGridCellOptions {
    int32_t col_span;
    int32_t row_span;
    AnsuzColor bg_color;
    AnsuzEdges margin;
} AnsuzGridCellOptions;

typedef struct AnsuzScrollOptions {
    uint32_t axis;
    float gap;
    AnsuzSize size;
    AnsuzEdges padding;
    AnsuzColor bg_color;
} AnsuzScrollOptions;

typedef struct AnsuzLabelOptions {
    AnsuzColor color;
    AnsuzColor bg_color;
    uint32_t font;
    float scale;
    AnsuzSize size;
    AnsuzEdges padding;
} AnsuzLabelOptions;

typedef struct AnsuzButtonOptions {
    float scale;
    AnsuzSize size;
    AnsuzEdges padding;
    AnsuzWidgetColor color;
    AnsuzColor text_color;
    uint32_t font;
} AnsuzButtonOptions;

typedef struct AnsuzCheckboxOptions {
    float scale;
    uint32_t font;
    AnsuzWidgetColor color;
    AnsuzColor text_color;
    AnsuzColor check_color;
    AnsuzColor border_color;
} AnsuzCheckboxOptions;

typedef struct AnsuzSliderOptions {
    float lo;
    float hi;
    float scale;
    AnsuzSize size;
    AnsuzWidgetColor color;
} AnsuzSliderOptions;

typedef struct AnsuzSliderLabeledOptions {
    float lo;
    float hi;
    float scale;
    AnsuzString format;
    uint32_t font;
    AnsuzWidgetColor color;
    AnsuzColor text_color;
} AnsuzSliderLabeledOptions;

typedef struct AnsuzDropdownOptions {
    AnsuzSize size;
    float scale;
    uint32_t font;
    AnsuzWidgetColor color;
    AnsuzColor text_color;
    AnsuzColor indicator_color;
    AnsuzColor popup_color;
    AnsuzColor popup_border_color;
    AnsuzColor item_hover_color;
    AnsuzColor selected_color;
} AnsuzDropdownOptions;

typedef struct AnsuzTextInputOptions {
    uint8_t multiline;
    uint32_t font;
    float scale;
    AnsuzSize size;
    AnsuzEdges padding;
    AnsuzString placeholder;
    AnsuzWidgetColor color;
    AnsuzColor text_color;
    AnsuzColor placeholder_color;
    AnsuzColor cursor_color;
} AnsuzTextInputOptions;

typedef struct AnsuzTextBuffer {
    uint8_t *data;
    uint32_t capacity;
    uint32_t length;
} AnsuzTextBuffer;

typedef struct AnsuzImage {
    void *handle;
    int32_t width;
    int32_t height;
} AnsuzImage;

typedef struct AnsuzImageOptions {
    AnsuzSize size;
    AnsuzColor tint;
} AnsuzImageOptions;

typedef struct AnsuzAnimationOptions {
    float duration;
    uint32_t easing;
    uint8_t looping;
    uint8_t ping_pong;
} AnsuzAnimationOptions;

#ifdef __cplusplus
#define ANSUZ_STR(literal) AnsuzString{(const uint8_t *)(literal), (uint32_t)(sizeof(literal) - 1u)}
extern "C" {
#else
#define ANSUZ_STR(literal) ((AnsuzString){(const uint8_t *)(literal), (uint32_t)(sizeof(literal) - 1u)})
#endif

uint8_t ansuz_init(const AnsuzInitConfig *config);
void ansuz_shutdown(void);
uint8_t ansuz_is_initialized(void);
uint8_t ansuz_should_quit(void);

void ansuz_frame_begin(float delta_seconds);
void ansuz_frame_end(void);
void ansuz_set_clear_color(AnsuzColor color);
int32_t ansuz_get_width(void);
int32_t ansuz_get_height(void);
uint32_t *ansuz_get_framebuffer(void);
size_t ansuz_get_framebuffer_length(void);

void ansuz_push_id(AnsuzId id);
void ansuz_push_id_string(AnsuzString id);
void ansuz_pop_id(void);

void ansuz_input_pointer(float x, float y, uint8_t left, uint8_t right, uint8_t middle);
void ansuz_input_scroll(float delta_y);
void ansuz_input_text(AnsuzString text);
void ansuz_input_key(uint32_t key, uint8_t down);

void ansuz_flex_begin(AnsuzId id, const AnsuzFlexOptions *options);
void ansuz_flex_end(void);
void ansuz_grid_begin(
    AnsuzId id,
    const AnsuzSizeSpec *columns,
    uint32_t column_count,
    const AnsuzSizeSpec *rows,
    uint32_t row_count,
    const AnsuzGridOptions *options
);
void ansuz_grid_end(void);
void ansuz_scroll_begin(AnsuzId id, const AnsuzScrollOptions *options);
void ansuz_scroll_end(void);
int32_t ansuz_box(AnsuzId id, const AnsuzBoxOptions *options);
int32_t ansuz_grid_cell(
    AnsuzId id,
    int32_t column,
    int32_t row,
    const AnsuzGridCellOptions *options
);

int32_t ansuz_label(AnsuzId id, AnsuzString text, const AnsuzLabelOptions *options);
int32_t ansuz_label_decorated(
    AnsuzId id,
    AnsuzString text,
    AnsuzString decorator,
    uint32_t affix,
    const AnsuzLabelOptions *options
);
int32_t ansuz_heading(AnsuzId id, AnsuzString text, const AnsuzLabelOptions *options);
AnsuzInteraction ansuz_button(
    AnsuzId id,
    AnsuzString text,
    const AnsuzButtonOptions *options
);
AnsuzInteraction ansuz_checkbox(
    AnsuzId id,
    AnsuzString text,
    uint8_t *value,
    const AnsuzCheckboxOptions *options
);
AnsuzInteraction ansuz_slider_f32(
    AnsuzId id,
    float *value,
    const AnsuzSliderOptions *options
);
AnsuzInteraction ansuz_slider_labeled_f32(
    AnsuzId id,
    AnsuzString text,
    float *value,
    const AnsuzSliderLabeledOptions *options
);
AnsuzInteraction ansuz_dropdown(
    AnsuzId id,
    int32_t *selected,
    const AnsuzString *options_list,
    uint32_t option_count,
    const AnsuzDropdownOptions *options
);
AnsuzInteraction ansuz_text_input(
    AnsuzId id,
    AnsuzTextBuffer *buffer,
    const AnsuzTextInputOptions *options
);

void ansuz_set_default_font(uint32_t font);
uint8_t ansuz_measure_text(
    AnsuzString text,
    uint32_t font,
    float scale,
    AnsuzVec2 *out_size
);
float ansuz_get_delta_time(void);
AnsuzColor ansuz_color_lerp(AnsuzColor from, AnsuzColor to, float amount);
float ansuz_ease_apply(float amount, uint32_t easing);
float ansuz_ease_lerp(float from, float to, float amount, uint32_t easing);
AnsuzColor ansuz_ease_color(
    AnsuzColor from,
    AnsuzColor to,
    float amount,
    uint32_t easing
);

uint8_t ansuz_image_create(
    const uint8_t *pixels,
    size_t pixel_byte_count,
    int32_t width,
    int32_t height,
    int32_t channels,
    AnsuzImage *out_image
);
void ansuz_image_destroy(AnsuzImage *image);
int32_t ansuz_image(AnsuzId id, const AnsuzImage *image, const AnsuzImageOptions *options);

void ansuz_animate_f32(
    AnsuzId id,
    float *value,
    float target,
    const AnsuzAnimationOptions *options
);
void ansuz_animate_color(
    AnsuzId id,
    AnsuzColor *value,
    AnsuzColor target,
    const AnsuzAnimationOptions *options
);
void ansuz_spring_f32(
    AnsuzId id,
    float *value,
    float target,
    float duration,
    uint32_t easing,
    float epsilon
);
void ansuz_cancel_animation(AnsuzId id);
uint8_t ansuz_is_animating(AnsuzId id);

uint8_t ansuz_any_value_dirty(void);
uint8_t ansuz_get_box_rect(int32_t box_index, AnsuzRect *out_rect);
uint8_t ansuz_get_box_content_rect(int32_t box_index, AnsuzRect *out_rect);

void ansuz_draw_filled_rect(AnsuzRect rect, AnsuzColor color, float radius);
void ansuz_draw_rect_outline(
    AnsuzRect rect,
    AnsuzColor color,
    float thickness,
    float radius
);
void ansuz_draw_line(
    float x0,
    float y0,
    float x1,
    float y1,
    AnsuzColor color,
    float thickness
);
void ansuz_draw_text(
    float x,
    float y,
    AnsuzString text,
    AnsuzColor color,
    uint32_t font,
    float scale
);
void ansuz_draw_clip(AnsuzRect rect);

#ifdef __cplusplus
}
#endif

static inline AnsuzColor ansuz_rgba(uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
    AnsuzColor color = {r, g, b, a};
    return color;
}

static inline AnsuzString ansuz_string(const char *data, uint32_t length) {
    AnsuzString value = {(const uint8_t *)data, length};
    return value;
}

static inline AnsuzSizeSpec ansuz_size_fixed(float pixels) {
    AnsuzSizeSpec value = {ANSUZ_SIZE_FIXED, pixels};
    return value;
}

static inline AnsuzSizeSpec ansuz_size_percent(float percent) {
    AnsuzSizeSpec value = {ANSUZ_SIZE_PERCENT, percent};
    return value;
}

static inline AnsuzSizeSpec ansuz_size_grow(float weight) {
    AnsuzSizeSpec value = {ANSUZ_SIZE_GROW, weight};
    return value;
}

static inline AnsuzSizeSpec ansuz_size_fit(void) {
    AnsuzSizeSpec value = {ANSUZ_SIZE_FIT, 0.0f};
    return value;
}

/* Legacy alias of ansuz_size_fit(). */
static inline AnsuzSizeSpec ansuz_size_auto(void) {
    AnsuzSizeSpec value = {ANSUZ_SIZE_AUTO, 0.0f};
    return value;
}

static inline AnsuzSize ansuz_size(AnsuzSizeSpec width, AnsuzSizeSpec height) {
    AnsuzSize value = {width, height};
    return value;
}

static inline AnsuzEdges ansuz_edges(float top, float right, float bottom, float left) {
    AnsuzEdges value = {top, right, bottom, left};
    return value;
}

static inline uint64_t ansuz_hash_bytes(const uint8_t *data, size_t length) {
    uint64_t hash = UINT64_C(0xcbf29ce484222325);
    for (size_t i = 0; i < length; ++i) {
        hash ^= data[i];
        hash *= UINT64_C(0x100000001b3);
    }
    return hash;
}

#define ANSUZ_ID(literal) ansuz_hash_bytes((const uint8_t *)(literal), sizeof(literal) - 1u)

static inline AnsuzFlexOptions ansuz_flex_options_default(void) {
    AnsuzFlexOptions options = {0};
    options.axis = ANSUZ_AXIS_HORIZONTAL;
    options.justify = ANSUZ_JUSTIFY_START;
    options.align = ANSUZ_ALIGN_STRETCH;
    options.size = ansuz_size(ansuz_size_grow(1.0f), ansuz_size_grow(1.0f));
    options.bg_color = ansuz_rgba(0, 0, 0, 0);
    return options;
}

static inline AnsuzGridOptions ansuz_grid_options_default(void) {
    AnsuzGridOptions options = {0};
    options.size = ansuz_size(ansuz_size_grow(1.0f), ansuz_size_grow(1.0f));
    options.bg_color = ansuz_rgba(0, 0, 0, 0);
    return options;
}

static inline AnsuzBoxOptions ansuz_box_options_default(void) {
    AnsuzBoxOptions options = {0};
    options.size = ansuz_size(ansuz_size_grow(1.0f), ansuz_size_grow(1.0f));
    options.bg_color = ansuz_rgba(0, 0, 0, 0);
    return options;
}

static inline AnsuzGridCellOptions ansuz_grid_cell_options_default(void) {
    AnsuzGridCellOptions options = {0};
    options.col_span = 1;
    options.row_span = 1;
    options.bg_color = ansuz_rgba(0, 0, 0, 0);
    return options;
}

static inline AnsuzScrollOptions ansuz_scroll_options_default(void) {
    AnsuzScrollOptions options = {0};
    options.axis = ANSUZ_AXIS_VERTICAL;
    options.size = ansuz_size(ansuz_size_grow(1.0f), ansuz_size_grow(1.0f));
    options.bg_color = ansuz_rgba(0, 0, 0, 0);
    return options;
}

static inline AnsuzLabelOptions ansuz_label_options_default(void) {
    AnsuzLabelOptions options = {0};
    options.color = ansuz_rgba(230, 230, 230, 255);
    options.bg_color = ansuz_rgba(0, 0, 0, 0);
    options.font = ANSUZ_FONT_DEFAULT;
    options.scale = 2.0f;
    options.size = ansuz_size(ansuz_size_fit(), ansuz_size_fit());
    options.padding = ansuz_edges(2, 4, 2, 4);
    return options;
}

static inline AnsuzLabelOptions ansuz_heading_options_default(void) {
    AnsuzLabelOptions options = ansuz_label_options_default();
    options.bg_color = ansuz_rgba(45, 45, 48, 255);
    options.scale = 3.0f;
    options.padding = ansuz_edges(4, 4, 4, 4);
    return options;
}

static inline AnsuzButtonOptions ansuz_button_options_default(void) {
    AnsuzButtonOptions options = {0};
    options.scale = 2.0f;
    options.size = ansuz_size(ansuz_size_fit(), ansuz_size_fit());
    options.padding = ansuz_edges(6, 16, 6, 16);
    options.color.bg = ansuz_rgba(60, 63, 70, 255);
    options.color.fg = ansuz_rgba(80, 83, 90, 255);
    options.color.hover = ansuz_rgba(75, 78, 88, 255);
    options.color.press = ansuz_rgba(45, 48, 55, 255);
    options.color.focus = ansuz_rgba(75, 78, 88, 255);
    options.text_color = ansuz_rgba(230, 230, 230, 255);
    options.font = ANSUZ_FONT_DEFAULT;
    return options;
}

static inline AnsuzCheckboxOptions ansuz_checkbox_options_default(void) {
    AnsuzCheckboxOptions options = {0};
    options.scale = 1.0f;
    options.font = ANSUZ_FONT_DEFAULT;
    options.color.bg = ansuz_rgba(0, 0, 0, 0);
    options.color.fg = ansuz_rgba(50, 53, 60, 255);
    options.color.hover = ansuz_rgba(65, 68, 78, 255);
    options.color.focus = ansuz_rgba(80, 140, 220, 255);
    options.text_color = ansuz_rgba(230, 230, 230, 255);
    options.check_color = ansuz_rgba(255, 255, 255, 255);
    options.border_color = ansuz_rgba(80, 83, 90, 255);
    return options;
}

static inline AnsuzSliderOptions ansuz_slider_options_default(void) {
    AnsuzSliderOptions options = {0};
    options.lo = 0.0f;
    options.hi = 1.0f;
    options.scale = 1.0f;
    options.size = ansuz_size(ansuz_size_grow(1.0f), ansuz_size_fit());
    options.color.bg = ansuz_rgba(50, 53, 60, 255);
    options.color.fg = ansuz_rgba(80, 140, 220, 255);
    options.color.hover = ansuz_rgba(100, 160, 240, 255);
    options.color.press = ansuz_rgba(80, 140, 220, 255);
    options.color.focus = ansuz_rgba(200, 203, 210, 255);
    return options;
}

static inline AnsuzSliderLabeledOptions ansuz_slider_labeled_options_default(void) {
    AnsuzSliderLabeledOptions options = {0};
    AnsuzSliderOptions slider = ansuz_slider_options_default();
    options.lo = slider.lo;
    options.hi = slider.hi;
    options.scale = slider.scale;
    options.format = ANSUZ_STR("%.2f");
    options.font = ANSUZ_FONT_DEFAULT;
    options.color = slider.color;
    options.text_color = ansuz_rgba(230, 230, 230, 255);
    return options;
}

static inline AnsuzDropdownOptions ansuz_dropdown_options_default(void) {
    AnsuzDropdownOptions options = {0};
    options.size = ansuz_size(ansuz_size_fixed(200), ansuz_size_fixed(30));
    options.scale = 2.0f;
    options.font = ANSUZ_FONT_DEFAULT;
    options.color.bg = ansuz_rgba(55, 58, 65, 255);
    options.color.fg = ansuz_rgba(70, 73, 83, 255);
    options.color.hover = ansuz_rgba(70, 73, 83, 255);
    options.color.press = ansuz_rgba(50, 53, 58, 255);
    options.text_color = ansuz_rgba(230, 230, 230, 255);
    options.indicator_color = ansuz_rgba(180, 180, 185, 255);
    options.popup_color = ansuz_rgba(45, 48, 55, 245);
    options.popup_border_color = ansuz_rgba(80, 83, 90, 255);
    options.item_hover_color = ansuz_rgba(80, 140, 220, 255);
    options.selected_color = ansuz_rgba(80, 140, 220, 255);
    return options;
}

static inline AnsuzTextInputOptions ansuz_text_input_options_default(void) {
    AnsuzTextInputOptions options = {0};
    options.font = ANSUZ_FONT_DEFAULT;
    options.scale = 2.0f;
    options.size = ansuz_size(ansuz_size_fixed(200), ansuz_size_fit());
    options.padding = ansuz_edges(6, 8, 6, 8);
    options.color.bg = ansuz_rgba(35, 38, 45, 255);
    options.color.fg = ansuz_rgba(80, 83, 90, 255);
    options.color.hover = ansuz_rgba(80, 140, 220, 255);
    options.color.focus = ansuz_rgba(80, 140, 220, 255);
    options.text_color = ansuz_rgba(230, 230, 230, 255);
    options.placeholder_color = ansuz_rgba(160, 160, 165, 255);
    options.cursor_color = ansuz_rgba(200, 210, 230, 255);
    return options;
}

static inline AnsuzImageOptions ansuz_image_options_default(void) {
    AnsuzImageOptions options = {0};
    options.size = ansuz_size(ansuz_size_fit(), ansuz_size_fit());
    options.tint = ansuz_rgba(255, 255, 255, 255);
    return options;
}

static inline AnsuzAnimationOptions ansuz_animation_options_default(void) {
    AnsuzAnimationOptions options = {0};
    options.duration = 0.3f;
    options.easing = ANSUZ_EASE_QUADRATIC_OUT;
    return options;
}

static inline void ansuz_framebuffer_to_mono_pages(
    const uint32_t *rgba,
    uint8_t *mono,
    int width,
    int height,
    uint8_t luminance_threshold
) {
    int page_count = height / 8;
    for (int page = 0; page < page_count; ++page) {
        for (int x = 0; x < width; ++x) {
            uint8_t byte_value = 0;
            for (int bit = 0; bit < 8; ++bit) {
                int y = page * 8 + bit;
                uint32_t pixel = rgba[y * width + x];
                uint8_t r = (uint8_t)pixel;
                uint8_t g = (uint8_t)(pixel >> 8);
                uint8_t b = (uint8_t)(pixel >> 16);
                uint16_t luminance =
                    (uint16_t)r * 77u +
                    (uint16_t)g * 150u +
                    (uint16_t)b * 29u;
                if ((uint8_t)(luminance >> 8) > luminance_threshold) {
                    byte_value |= (uint8_t)(1u << bit);
                }
            }
            mono[page * width + x] = byte_value;
        }
    }
}

#endif

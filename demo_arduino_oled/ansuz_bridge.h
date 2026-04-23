// ansuz_bridge.h — C interface to the Odin-compiled ansuz library.
// Include this in your Arduino sketch or C/C++ application.

#ifndef ansuz_BRIDGE_H
#define ansuz_BRIDGE_H
#endif 

#include <stdint.h>

typedef struct {
    float brightness;
    float volume;
    uint8_t wifi_on;     // Odin bool = 1 byte
    int32_t click_count;
} UI_State;

#ifdef __cplusplus
extern "C" {
#endif

// Initialize the ansuz framework and software renderer.
// Call once in setup(). Allocates from a static arena — no malloc needed.
void ansuz_init(void);

// Render one frame of the UI into the internal RGBA32 framebuffer.
// Call each iteration of loop().
void ansuz_render_frame(void);

// Get a pointer to the RGBA32 framebuffer (128 * 64 = 8192 uint32_t values).
// Pixel format: 0xAABBGGRR (R in low byte, A in high byte).
uint32_t* ansuz_get_framebuffer(void);

// Get a pointer to the shared UI state struct.
// Read/write this from Arduino to exchange data with the Odin UI.
UI_State* ansuz_get_state(void);



#ifdef __cplusplus
}

// Convert the RGBA32 framebuffer to SSD1306 page-format buffer.
//
// SSD1306 stores pixels in 8 "pages" of 128 bytes. Each byte holds 8 vertical
// pixels (bit 0 = top of page, bit 7 = bottom). Total: 1024 bytes for 128x64.
//
// This function thresholds each pixel's luminance to produce 1-bit output.
static inline void ansuz_framebuffer_to_ssd1306(const uint32_t* rgba, uint8_t* mono) {
    for (int page = 0; page < 8; page++) {
        for (int x = 0; x < 128; x++) {
            uint8_t byte_val = 0;
            for (int bit = 0; bit < 8; bit++) {
                int y = page * 8 + bit;
                uint32_t pixel = rgba[y * 128 + x];
                uint8_t r = (uint8_t)(pixel);
                uint8_t g = (uint8_t)(pixel >> 8);
                uint8_t b = (uint8_t)(pixel >> 16);
                // Weighted luminance: 0.30R + 0.59G + 0.11B
                uint16_t lum = (uint16_t)r * 77 + (uint16_t)g * 150 + (uint16_t)b * 29;
                if ((lum >> 8) > 64) {
                    byte_val |= (1 << bit);
                }
            }
            mono[page * 128 + x] = byte_val;
        }
    }
}



#endif // ansuz_BRIDGE_H
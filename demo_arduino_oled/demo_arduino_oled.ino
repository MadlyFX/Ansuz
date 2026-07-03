#include <gfxfont.h>
#include <Adafruit_SPITFT_Macros.h>
#include <Adafruit_SPITFT.h>
#include <Adafruit_GrayOLED.h>
#include <Wire.h>
#include <Adafruit_SSD1306.h>
#include "ansuz_bridge.h"

#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define SCREEN_ADDR 0x3C
#define ANSUZ_PIXEL_COUNT (SCREEN_WIDTH * SCREEN_HEIGHT)
#define LED_PIN 13

Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire);

static uint32_t ansuzFramebuffer[ANSUZ_PIXEL_COUNT];
ANSUZ_ALIGNAS(8) static uint8_t ansuzHeap[ANSUZ_RECOMMENDED_HEAP_SIZE];

static float volume = 0.0f;
static uint8_t wifiOn = 0;

static void renderUi(float deltaSeconds) {
  ansuz_frame_begin(deltaSeconds);

  AnsuzFlexOptions root = ansuz_flex_options_default();
  root.axis = ANSUZ_AXIS_VERTICAL;
  root.gap = 2.0f;
  root.padding = ansuz_edges(4, 4, 4, 4);
  ansuz_flex_begin(ANSUZ_ID("root"), &root);

  AnsuzLabelOptions title = ansuz_label_options_default();
  title.scale = 2.0f;
  title.font = ANSUZ_FONT_BUILTIN;
  title.padding = ansuz_edges(0, 0, -2, 0);
  ansuz_label(ANSUZ_ID("title"), ANSUZ_STR("Ansuz"), &title);

  AnsuzBoxOptions divider = ansuz_box_options_default();
  divider.size = ansuz_size(ansuz_size_grow(1), ansuz_size_fixed(1));
  divider.bg_color = ansuz_rgba(255, 255, 255, 255);
  ansuz_box(ANSUZ_ID("divider"), &divider);

  AnsuzSliderLabeledOptions slider = ansuz_slider_labeled_options_default();
  slider.lo = 0.0f;
  slider.hi = 1024.0f;
  slider.scale = 0.5f;
  slider.font = ANSUZ_FONT_BUILTIN;
  ansuz_slider_labeled_f32(
      ANSUZ_ID("volume"),
      ANSUZ_STR("A1:"),
      &volume,
      &slider);

  AnsuzCheckboxOptions checkbox = ansuz_checkbox_options_default();
  checkbox.scale = 0.5f;
  checkbox.font = ANSUZ_FONT_BUILTIN;
  ansuz_checkbox(
      ANSUZ_ID("wifi"),
      wifiOn ? ANSUZ_STR("True") : ANSUZ_STR("False"),
      &wifiOn,
      &checkbox);

  ansuz_flex_end();
  ansuz_frame_end();
}

void setup() {
  pinMode(A1, INPUT_PULLDOWN);
  pinMode(LED_PIN, OUTPUT);

  if (!display.begin(SSD1306_SWITCHCAPVCC, SCREEN_ADDR)) {
    while (1) {}
  }

  display.clearDisplay();
  display.display();

  AnsuzInitConfig config = {};
  config.width = SCREEN_WIDTH;
  config.height = SCREEN_HEIGHT;
  config.framebuffer = ansuzFramebuffer;
  config.framebuffer_length = ANSUZ_PIXEL_COUNT;
  config.heap = ansuzHeap;
  config.heap_size = sizeof(ansuzHeap);
  config.clear_color = ansuz_rgba(0, 0, 0, 255);

  if (!ansuz_init(&config)) {
    while (1) {}
  }
}

static unsigned long lastToggle = 0;
static unsigned long lastFrameMillis = 0;

void loop() {
  unsigned long now = millis();
  float deltaSeconds =
      lastFrameMillis == 0 ? 0.0f : (now - lastFrameMillis) / 1000.0f;
  lastFrameMillis = now;

  volume = analogRead(A1);
  renderUi(deltaSeconds);

  analogWrite(LED_PIN, wifiOn ? 255 : 0);

  ansuz_framebuffer_to_mono_pages(
      ansuz_get_framebuffer(),
      display.getBuffer(),
      SCREEN_WIDTH,
      SCREEN_HEIGHT,
      64);
  display.display();

  if (now - lastToggle >= 500) {
    wifiOn = !wifiOn;
    lastToggle = now;
  }
}

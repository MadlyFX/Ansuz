


#include <gfxfont.h>
#include <Adafruit_SPITFT_Macros.h>
#include <Adafruit_SPITFT.h>
#include <Adafruit_GrayOLED.h>
#include <Wire.h>
#include <Adafruit_SSD1306.h>
#include "ansuz_bridge.h"
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define SCREEN_ADDR 0x3C  // Typical I2C address for SSD1306

//#define PIN_OLED_SDA        2   // I2C Data for OLED
//#define PIN_OLED_SCL        3   // I2C Clock for OLED
//#define OLED_RESET        4   // OLED Reset Pin
#define LED_PIN 13

Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire);

void setup() {


  //     Wire1.setSDA(PIN_OLED_SDA);
  // Wire1.setSCL(PIN_OLED_SCL);
  // Wire1.begin();

  pinMode(A1, INPUT_PULLDOWN);

  if (!display.begin(SSD1306_SWITCHCAPVCC, SCREEN_ADDR)) {
    // SSD1306 init failed — halt
    while (1) {}
  }

  display.clearDisplay();
  display.display();

  // Initialize the Odin-compiled ansuz framework
  ansuz_init();
}
static unsigned long lastToggle = 0;
static unsigned long lastMilis = 0;


void loop() {
  // // Render the UI into the RGBA32 framebuffer (inside Odin code)

  UI_State* ui = ansuz_get_state();

  // Write sensor data → Odin UI displays it
  ui->volume = analogRead(A1);

  // Render the UI (Odin reads/writes state internally)
  ansuz_render_frame();

  // Read UI values → control hardware
  analogWrite(LED_PIN, (int)(ui->brightness * 255));

  // Get the RGBA framebuffer and convert to 1-bit monochrome
  uint32_t* fb = ansuz_get_framebuffer();
  uint8_t* disp_buf = display.getBuffer();

  ansuz_framebuffer_to_ssd1306(fb, disp_buf);

  // Push to the OLED
  display.display();

  if (millis() - lastToggle >= 500) {
    ui->wifi_on = !ui->wifi_on;
    lastToggle = millis();
  }
  ui->click_count = 1000 / (millis() - lastMilis);
  lastMilis = millis();

}
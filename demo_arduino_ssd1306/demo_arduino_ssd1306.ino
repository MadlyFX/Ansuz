// demo_arduino_ssd1306.ino
//
// Hello World: OGUI framework on an SSD1306 128x64 OLED via Arduino.
//
// The OGUI library and software renderer are compiled from Odin to an object
// file (freestanding_arm32), then linked into this sketch as a static library.
// The Odin code renders the UI into an RGBA32 framebuffer, and this sketch
// converts it to 1-bit and pushes it to the SSD1306 over I2C.
//
// Hardware:
//   - ARM Cortex-M4 Arduino-compatible board (e.g. Adafruit Feather M4,
//     Arduino Nano 33 BLE, or STM32-based board) — needs ~80KB free SRAM
//   - SSD1306 128x64 I2C OLED (SDA/SCL)
//
// Dependencies:
//   - Adafruit_GFX (already in repo)
//   - Adafruit_SSD1306
//   - Pre-built libogui.a (see build.bat)

#include <gfxfont.h>
#include <Adafruit_SPITFT_Macros.h>
#include <Adafruit_SPITFT.h>
#include <Adafruit_GrayOLED.h>
#include <Wire.h>
#include <Adafruit_SSD1306.h>
#include "ogui_bridge.h"

#define SCREEN_WIDTH  128
#define SCREEN_HEIGHT 64
#define SCREEN_ADDR   0x3C  // Typical I2C address for SSD1306

#define PIN_OLED_SDA        2   // I2C Data for OLED
#define PIN_OLED_SCL        3   // I2C Clock for OLED
#define OLED_RESET        4   // OLED Reset Pin
#define LED_PIN 13

Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire1, OLED_RESET);

void setup() {
  pinMode(OLED_RESET, OUTPUT);
  digitalWrite(OLED_RESET, LOW);
  delay(50);
  digitalWrite(OLED_RESET, HIGH);

      Wire1.setSDA(PIN_OLED_SDA);
  Wire1.setSCL(PIN_OLED_SCL);
  Wire1.begin();

    if (!display.begin(SSD1306_SWITCHCAPVCC, SCREEN_ADDR)) {
        // SSD1306 init failed — halt
        while (1) {}
    }

    display.clearDisplay();
    display.display();

    // Initialize the Odin-compiled OGUI framework
    ogui_init();
}
static unsigned long lastToggle = 0;


void loop() {
    // // Render the UI into the RGBA32 framebuffer (inside Odin code)

     UI_State* ui = ogui_get_state();

    // Write sensor data → Odin UI displays it
    ui->volume = random(0, 100);

    // Render the UI (Odin reads/writes state internally)
    ogui_render_frame();

    // Read UI values → control hardware
    analogWrite(LED_PIN, (int)(ui->brightness * 255));

    // Get the RGBA framebuffer and convert to 1-bit monochrome
    uint32_t* fb = ogui_get_framebuffer();
    uint8_t* disp_buf = display.getBuffer();

    ogui_framebuffer_to_ssd1306(fb, disp_buf);

    // Push to the OLED
    display.display();

    if (millis() - lastToggle >= 500) {
    ui->wifi_on = !ui->wifi_on;
    lastToggle = millis();
    }
    ui->click_count++;
    delay(10);

    
}

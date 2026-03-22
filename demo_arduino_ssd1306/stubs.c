// stubs.c — Bare-metal stubs for symbols required by Odin's freestanding runtime.

#include <stdint.h>

// Thread-local storage read — Odin's runtime uses this for the default RNG.
// On bare metal there are no threads, so return a fixed static buffer.
static char __tls_area[64];
void* __aeabi_read_tp(void) {
    return __tls_area;
}

// Double to half-precision float conversion (IEEE 754 binary16).
// Required by Odin's fmt/strconv when soft-float is enabled.
uint16_t __aeabi_d2h(double d) {
    float f = (float)d;
    uint32_t fi;
    __builtin_memcpy(&fi, &f, sizeof(fi));
    uint16_t sign = (fi >> 16) & 0x8000;
    int exp = ((fi >> 23) & 0xFF) - 127 + 15;
    uint32_t mant = fi & 0x007FFFFF;
    if (exp <= 0) return sign;          // underflow → zero
    if (exp >= 31) return sign | 0x7C00; // overflow → inf
    return sign | (uint16_t)(exp << 10) | (uint16_t)(mant >> 13);
}

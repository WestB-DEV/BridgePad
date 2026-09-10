#ifndef BRIDGEPAD_HID_H
#define BRIDGEPAD_HID_H

#include <stdint.h>

#define BRIDGEPAD_HID_MOUSE_ALL_BUTTONS 0xffU

static inline uint16_t bridgepad_hid_sdk_keycode(uint16_t keycode) {
    /* The wire uses HID usages; Flipper places modifier bits in the high byte.
     * Leave existing packed modifier + usage chords unchanged. */
    if(keycode >= 0xe0U && keycode <= 0xe7U) {
        return (uint16_t)(1U << (keycode - 0xe0U + 8U));
    }
    return keycode;
}

#endif

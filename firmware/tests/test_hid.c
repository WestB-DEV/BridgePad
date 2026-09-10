#include "bridgepad_hid.h"

#include <assert.h>
#include <stdio.h>

static void test_standard_modifier_usages_use_sdk_modifier_bits(void) {
    for(uint16_t usage = 0xe0; usage <= 0xe7; usage++) {
        assert(bridgepad_hid_sdk_keycode(usage) == (uint16_t)(1U << (usage - 0xe0 + 8)));
    }
}

static void test_normal_keys_and_packed_chords_are_preserved(void) {
    assert(bridgepad_hid_sdk_keycode(0x0028) == 0x0028); /* Enter */
    assert(bridgepad_hid_sdk_keycode(0x0006) == 0x0006); /* C */
    assert(bridgepad_hid_sdk_keycode(0x0806) == 0x0806); /* Command + C */
    assert(bridgepad_hid_sdk_keycode(0x0306) == 0x0306); /* Ctrl + Shift + C */
    assert(bridgepad_hid_sdk_keycode(0x0100) == 0x0100); /* Packed Ctrl only */
}

static void test_chord_release_clears_only_its_own_modifiers(void) {
    const uint16_t chord = bridgepad_hid_sdk_keycode(0x0806);
    uint8_t report_modifiers = 0x01; /* Independently held Ctrl */
    report_modifiers |= (uint8_t)(chord >> 8);
    assert(report_modifiers == 0x09);
    report_modifiers &= (uint8_t)~(chord >> 8);
    assert(report_modifiers == 0x01);
}

static void test_release_all_clears_every_mouse_button(void) {
    uint8_t report_buttons = 0xff;
    report_buttons &= (uint8_t)~BRIDGEPAD_HID_MOUSE_ALL_BUTTONS;
    assert(report_buttons == 0);
}

int main(void) {
    test_standard_modifier_usages_use_sdk_modifier_bits();
    test_normal_keys_and_packed_chords_are_preserved();
    test_chord_release_clears_only_its_own_modifiers();
    test_release_all_clears_every_mouse_button();
    puts("HID adapter tests passed");
    return 0;
}

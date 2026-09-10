#pragma once

#include "bridgepad_protocol.h"

#define BRIDGEPAD_HEARTBEAT_TIMEOUT_MS 5000U

typedef struct {
    void* context;
    void (*release_all)(void* context);
    bool (*text_ascii)(void* context, const uint8_t* text, size_t length);
    bool (*key_press)(void* context, uint16_t keycode);
    bool (*key_release)(void* context, uint16_t keycode);
    bool (*pointer_move)(void* context, int8_t dx, int8_t dy);
    bool (*pointer_button)(void* context, uint8_t mask, bool down);
    bool (*scroll)(void* context, int8_t delta);
    void (*send_frame)(
        void* context,
        BridgepadOpcode opcode,
        uint16_t sequence,
        const uint8_t* payload,
        size_t payload_length);
} BridgepadCoreIo;

typedef struct {
    BridgepadCoreIo io;
    uint32_t last_heartbeat_ms;
    uint16_t last_sequence;
    bool ble_connected;
    bool usb_connected;
    bool armed;
    bool has_last_sequence;
} BridgepadCore;

void bridgepad_core_init(BridgepadCore* core, const BridgepadCoreIo* io);
void bridgepad_core_set_ble_connected(BridgepadCore* core, bool connected);
void bridgepad_core_set_usb_connected(BridgepadCore* core, bool connected);
bool bridgepad_core_toggle_arm(BridgepadCore* core, uint32_t now_ms);
void bridgepad_core_disarm(BridgepadCore* core);
bool bridgepad_core_is_armed(const BridgepadCore* core);
void bridgepad_core_tick(BridgepadCore* core, uint32_t now_ms);
void bridgepad_core_handle_frame(BridgepadCore* core, const BridgepadFrame* frame, uint32_t now_ms);
void bridgepad_core_send_status(BridgepadCore* core, uint16_t sequence);

#include "bridgepad_core.h"

#include <string.h>

enum {
    BridgepadStateBleConnected = 1U << 0,
    BridgepadStateUsbConnected = 1U << 1,
    BridgepadStateArmed = 1U << 2,
};

static void bridgepad_core_send_result(
    BridgepadCore* core,
    BridgepadOpcode opcode,
    uint16_t sequence,
    BridgepadStatusCode status) {
    const uint8_t payload[] = {
        (uint8_t)(sequence & 0xFFU),
        (uint8_t)(sequence >> 8),
        (uint8_t)status,
    };
    core->io.send_frame(core->io.context, opcode, sequence, payload, sizeof(payload));
}

static void bridgepad_core_ack(
    BridgepadCore* core, uint16_t sequence, BridgepadStatusCode status) {
    bridgepad_core_send_result(core, BridgepadOpcodeAck, sequence, status);
}

static void bridgepad_core_error(
    BridgepadCore* core, uint16_t sequence, BridgepadStatusCode status) {
    bridgepad_core_send_result(core, BridgepadOpcodeError, sequence, status);
}

static bool bridgepad_keycode_is_valid(uint16_t keycode) {
    const uint8_t usage = (uint8_t)(keycode & 0xFFU);
    return keycode != 0 && usage <= 0xE7U;
}

static bool bridgepad_core_is_input_opcode(BridgepadOpcode opcode) {
    switch(opcode) {
    case BridgepadOpcodeTextAscii:
    case BridgepadOpcodeKeyDown:
    case BridgepadOpcodeKeyUp:
    case BridgepadOpcodePointerMove:
    case BridgepadOpcodePointerButton:
    case BridgepadOpcodeScroll:
        return true;
    default:
        return false;
    }
}

void bridgepad_core_init(BridgepadCore* core, const BridgepadCoreIo* io) {
    memset(core, 0, sizeof(*core));
    core->io = *io;
}

void bridgepad_core_send_status(BridgepadCore* core, uint16_t sequence) {
    uint8_t state = 0;
    if(core->ble_connected) state |= BridgepadStateBleConnected;
    if(core->usb_connected) state |= BridgepadStateUsbConnected;
    if(core->armed) state |= BridgepadStateArmed;
    const uint8_t payload[] = {
        state,
        BRIDGEPAD_PROTOCOL_VERSION,
        (uint8_t)(BRIDGEPAD_MAX_FRAME_PAYLOAD & 0xFFU),
        (uint8_t)(BRIDGEPAD_MAX_FRAME_PAYLOAD >> 8),
    };
    core->io.send_frame(
        core->io.context, BridgepadOpcodeStatus, sequence, payload, sizeof(payload));
}

void bridgepad_core_disarm(BridgepadCore* core) {
    if(!core->armed) return;
    core->armed = false;
    core->io.release_all(core->io.context);
    bridgepad_core_send_status(core, 0);
}

void bridgepad_core_set_ble_connected(BridgepadCore* core, bool connected, uint32_t now_ms) {
    (void)now_ms;
    if(core->ble_connected == connected) return;
    core->ble_connected = connected;
    core->has_last_sequence = false;
    if(!connected) bridgepad_core_disarm(core);
    bridgepad_core_send_status(core, 0);
}

void bridgepad_core_set_usb_connected(BridgepadCore* core, bool connected, uint32_t now_ms) {
    (void)now_ms;
    if(core->usb_connected == connected) return;
    core->usb_connected = connected;
    if(!connected) bridgepad_core_disarm(core);
    bridgepad_core_send_status(core, 0);
}

bool bridgepad_core_toggle_arm(BridgepadCore* core, uint32_t now_ms) {
    if(core->armed) {
        bridgepad_core_disarm(core);
        return false;
    }
    if(!core->ble_connected || !core->usb_connected) return false;
    core->armed = true;
    core->last_heartbeat_ms = now_ms;
    bridgepad_core_send_status(core, 0);
    return true;
}

bool bridgepad_core_is_armed(const BridgepadCore* core) {
    return core->armed;
}

void bridgepad_core_tick(BridgepadCore* core, uint32_t now_ms) {
    if(core->armed && (uint32_t)(now_ms - core->last_heartbeat_ms) > BRIDGEPAD_HEARTBEAT_TIMEOUT_MS) {
        bridgepad_core_disarm(core);
    }
}

static bool bridgepad_core_execute_input(BridgepadCore* core, const BridgepadFrame* frame) {
    switch(frame->opcode) {
    case BridgepadOpcodeTextAscii:
        if(!bridgepad_text_is_supported(frame->payload, frame->payload_length)) return false;
        return core->io.text_ascii(core->io.context, frame->payload, frame->payload_length);
    case BridgepadOpcodeKeyDown:
    case BridgepadOpcodeKeyUp: {
        if(frame->payload_length != 2) return false;
        const uint16_t keycode =
            (uint16_t)frame->payload[0] | ((uint16_t)frame->payload[1] << 8);
        if(!bridgepad_keycode_is_valid(keycode)) return false;
        return frame->opcode == BridgepadOpcodeKeyDown ?
                   core->io.key_press(core->io.context, keycode) :
                   core->io.key_release(core->io.context, keycode);
    }
    case BridgepadOpcodePointerMove:
        if(frame->payload_length != 2) return false;
        return core->io.pointer_move(
            core->io.context, (int8_t)frame->payload[0], (int8_t)frame->payload[1]);
    case BridgepadOpcodePointerButton:
        if(frame->payload_length != 2 || frame->payload[0] == 0 ||
           (frame->payload[0] & ~0x07U) != 0 || frame->payload[1] > 1) {
            return false;
        }
        return core->io.pointer_button(
            core->io.context, frame->payload[0], frame->payload[1] == 1);
    case BridgepadOpcodeScroll:
        if(frame->payload_length != 1 || frame->payload[0] == 0) return false;
        return core->io.scroll(core->io.context, (int8_t)frame->payload[0]);
    default:
        return false;
    }
}

void bridgepad_core_handle_frame(BridgepadCore* core, const BridgepadFrame* frame, uint32_t now_ms) {
    if(!core || !frame) return;

    if(frame->opcode == BridgepadOpcodeHello) {
        bridgepad_core_send_status(core, frame->sequence);
        bridgepad_core_ack(core, frame->sequence, BridgepadStatusOk);
        return;
    }
    if(frame->opcode == BridgepadOpcodePing) {
        core->last_heartbeat_ms = now_ms;
        bridgepad_core_ack(core, frame->sequence, BridgepadStatusOk);
        return;
    }
    if(frame->opcode == BridgepadOpcodeReleaseAll) {
        bridgepad_core_disarm(core);
        bridgepad_core_ack(core, frame->sequence, BridgepadStatusOk);
        return;
    }
    if(!bridgepad_core_is_input_opcode(frame->opcode)) {
        bridgepad_core_error(core, frame->sequence, BridgepadStatusUnsupported);
        return;
    }
    if(!core->armed) {
        bridgepad_core_error(core, frame->sequence, BridgepadStatusNotArmed);
        return;
    }
    if(core->has_last_sequence && core->last_sequence == frame->sequence) {
        bridgepad_core_ack(core, frame->sequence, BridgepadStatusDuplicate);
        return;
    }

    if(!bridgepad_core_execute_input(core, frame)) {
        bridgepad_core_error(core, frame->sequence, BridgepadStatusInvalidPayload);
        return;
    }

    core->has_last_sequence = true;
    core->last_sequence = frame->sequence;
    bridgepad_core_ack(core, frame->sequence, BridgepadStatusOk);
}

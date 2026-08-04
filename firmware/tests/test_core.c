#include "bridgepad_core.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

typedef struct {
    unsigned release_all_count;
    unsigned text_count;
    unsigned key_press_count;
    unsigned pointer_move_count;
    BridgepadOpcode response_opcode;
    uint16_t response_sequence;
    uint8_t response_payload[16];
    size_t response_payload_length;
} FakeHardware;

static void fake_release_all(void* context) {
    ((FakeHardware*)context)->release_all_count++;
}

static bool fake_text_ascii(void* context, const uint8_t* text, size_t length) {
    FakeHardware* hardware = context;
    hardware->text_count += (unsigned)length;
    return text != NULL || length == 0;
}

static bool fake_key_press(void* context, uint16_t keycode) {
    FakeHardware* hardware = context;
    hardware->key_press_count++;
    return keycode != 0;
}

static bool fake_key_release(void* context, uint16_t keycode) {
    (void)context;
    return keycode != 0;
}

static bool fake_pointer_move(void* context, int8_t dx, int8_t dy) {
    FakeHardware* hardware = context;
    hardware->pointer_move_count++;
    return dx != 0 || dy != 0;
}

static bool fake_pointer_button(void* context, uint8_t mask, bool down) {
    (void)context;
    (void)down;
    return mask != 0;
}

static bool fake_scroll(void* context, int8_t delta) {
    (void)context;
    return delta != 0;
}

static void fake_send_frame(
    void* context,
    BridgepadOpcode opcode,
    uint16_t sequence,
    const uint8_t* payload,
    size_t payload_length) {
    FakeHardware* hardware = context;
    hardware->response_opcode = opcode;
    hardware->response_sequence = sequence;
    hardware->response_payload_length = payload_length;
    assert(payload_length <= sizeof(hardware->response_payload));
    if(payload_length) memcpy(hardware->response_payload, payload, payload_length);
}

static BridgepadCore make_core(FakeHardware* hardware) {
    const BridgepadCoreIo io = {
        .context = hardware,
        .release_all = fake_release_all,
        .text_ascii = fake_text_ascii,
        .key_press = fake_key_press,
        .key_release = fake_key_release,
        .pointer_move = fake_pointer_move,
        .pointer_button = fake_pointer_button,
        .scroll = fake_scroll,
        .send_frame = fake_send_frame,
    };
    BridgepadCore core;
    bridgepad_core_init(&core, &io);
    return core;
}

static BridgepadFrame frame(BridgepadOpcode opcode, uint16_t sequence, const uint8_t* payload, size_t length) {
    const BridgepadFrame value = {
        .version = BRIDGEPAD_PROTOCOL_VERSION,
        .opcode = opcode,
        .sequence = sequence,
        .payload_length = (uint16_t)length,
        .payload = payload,
    };
    return value;
}

static void connect_and_arm(BridgepadCore* core, uint32_t now) {
    bridgepad_core_set_ble_connected(core, true, now);
    bridgepad_core_set_usb_connected(core, true, now);
    assert(bridgepad_core_toggle_arm(core, now));
    assert(bridgepad_core_is_armed(core));
}

static void test_requires_both_connections_to_arm(void) {
    FakeHardware hardware = {0};
    BridgepadCore core = make_core(&hardware);

    assert(!bridgepad_core_toggle_arm(&core, 100));
    bridgepad_core_set_ble_connected(&core, true, 100);
    assert(!bridgepad_core_toggle_arm(&core, 100));
    bridgepad_core_set_usb_connected(&core, true, 100);
    assert(bridgepad_core_toggle_arm(&core, 100));
}

static void test_rejects_input_until_armed(void) {
    FakeHardware hardware = {0};
    BridgepadCore core = make_core(&hardware);
    const uint8_t text[] = "hello";
    BridgepadFrame text_frame = frame(BridgepadOpcodeTextAscii, 7, text, sizeof(text) - 1);

    bridgepad_core_handle_frame(&core, &text_frame, 100);

    assert(hardware.text_count == 0);
    assert(hardware.response_opcode == BridgepadOpcodeError);
    assert(hardware.response_payload[2] == BridgepadStatusNotArmed);
}

static void test_heartbeat_timeout_releases_input(void) {
    FakeHardware hardware = {0};
    BridgepadCore core = make_core(&hardware);
    connect_and_arm(&core, 1000);

    bridgepad_core_tick(&core, 6001);

    assert(!bridgepad_core_is_armed(&core));
    assert(hardware.release_all_count == 1);
}

static void test_ping_refreshes_heartbeat(void) {
    FakeHardware hardware = {0};
    BridgepadCore core = make_core(&hardware);
    connect_and_arm(&core, 1000);
    BridgepadFrame ping = frame(BridgepadOpcodePing, 1, NULL, 0);

    bridgepad_core_handle_frame(&core, &ping, 5000);
    bridgepad_core_tick(&core, 9000);

    assert(bridgepad_core_is_armed(&core));
    assert(hardware.response_opcode == BridgepadOpcodeAck);
}

static void test_disconnect_releases_and_disarms(void) {
    FakeHardware hardware = {0};
    BridgepadCore core = make_core(&hardware);
    connect_and_arm(&core, 100);

    bridgepad_core_set_ble_connected(&core, false, 200);

    assert(!bridgepad_core_is_armed(&core));
    assert(hardware.release_all_count == 1);
}

static void test_duplicate_command_is_not_replayed(void) {
    FakeHardware hardware = {0};
    BridgepadCore core = make_core(&hardware);
    connect_and_arm(&core, 100);
    const uint8_t text[] = "abc";
    BridgepadFrame text_frame = frame(BridgepadOpcodeTextAscii, 42, text, sizeof(text) - 1);

    bridgepad_core_handle_frame(&core, &text_frame, 150);
    bridgepad_core_handle_frame(&core, &text_frame, 160);

    assert(hardware.text_count == 3);
    assert(hardware.response_opcode == BridgepadOpcodeAck);
    assert(hardware.response_payload[2] == BridgepadStatusDuplicate);
}

static void test_rejects_malformed_keycode(void) {
    FakeHardware hardware = {0};
    BridgepadCore core = make_core(&hardware);
    connect_and_arm(&core, 100);
    const uint8_t invalid_key[] = {0xFF, 0xFF};
    BridgepadFrame key = frame(BridgepadOpcodeKeyDown, 8, invalid_key, sizeof(invalid_key));

    bridgepad_core_handle_frame(&core, &key, 150);

    assert(hardware.key_press_count == 0);
    assert(hardware.response_opcode == BridgepadOpcodeError);
    assert(hardware.response_payload[2] == BridgepadStatusInvalidPayload);
}

static void test_executes_text_and_pointer_commands_when_armed(void) {
    FakeHardware hardware = {0};
    BridgepadCore core = make_core(&hardware);
    connect_and_arm(&core, 100);
    const uint8_t text[] = "A1!";
    const uint8_t movement[] = {4, (uint8_t)-3};
    BridgepadFrame text_frame = frame(BridgepadOpcodeTextAscii, 10, text, sizeof(text) - 1);
    BridgepadFrame move_frame = frame(BridgepadOpcodePointerMove, 11, movement, sizeof(movement));

    bridgepad_core_handle_frame(&core, &text_frame, 110);
    bridgepad_core_handle_frame(&core, &move_frame, 120);

    assert(hardware.text_count == 3);
    assert(hardware.pointer_move_count == 1);
    assert(hardware.response_opcode == BridgepadOpcodeAck);
    assert(hardware.response_sequence == 11);
}

int main(void) {
    test_requires_both_connections_to_arm();
    test_rejects_input_until_armed();
    test_heartbeat_timeout_releases_input();
    test_ping_refreshes_heartbeat();
    test_disconnect_releases_and_disarms();
    test_duplicate_command_is_not_replayed();
    test_rejects_malformed_keycode();
    test_executes_text_and_pointer_commands_when_armed();
    puts("bridgepad core tests passed");
    return 0;
}

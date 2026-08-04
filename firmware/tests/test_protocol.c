#include "bridgepad_protocol.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

static void test_decodes_valid_frame(void) {
    const uint8_t bytes[] = {1, BridgepadOpcodeTextAscii, 0x34, 0x12, 3, 0, 'a', 'b', 'c'};
    BridgepadFrame frame = {0};

    assert(bridgepad_frame_decode(bytes, sizeof(bytes), &frame) == BridgepadProtocolOk);
    assert(frame.version == BRIDGEPAD_PROTOCOL_VERSION);
    assert(frame.opcode == BridgepadOpcodeTextAscii);
    assert(frame.sequence == 0x1234);
    assert(frame.payload_length == 3);
    assert(memcmp(frame.payload, "abc", 3) == 0);
}

static void test_rejects_truncated_header(void) {
    const uint8_t bytes[] = {1, BridgepadOpcodePing, 1};
    BridgepadFrame frame = {0};

    assert(bridgepad_frame_decode(bytes, sizeof(bytes), &frame) == BridgepadProtocolTruncated);
}

static void test_rejects_wrong_version(void) {
    const uint8_t bytes[] = {2, BridgepadOpcodePing, 1, 0, 0, 0};
    BridgepadFrame frame = {0};

    assert(bridgepad_frame_decode(bytes, sizeof(bytes), &frame) == BridgepadProtocolUnsupportedVersion);
}

static void test_rejects_unknown_opcode(void) {
    const uint8_t bytes[] = {1, 0x7F, 1, 0, 0, 0};
    BridgepadFrame frame = {0};

    assert(bridgepad_frame_decode(bytes, sizeof(bytes), &frame) == BridgepadProtocolUnknownOpcode);
}

static void test_rejects_payload_length_mismatch(void) {
    const uint8_t bytes[] = {1, BridgepadOpcodeTextAscii, 1, 0, 4, 0, 'a'};
    BridgepadFrame frame = {0};

    assert(bridgepad_frame_decode(bytes, sizeof(bytes), &frame) == BridgepadProtocolLengthMismatch);
}

static void test_rejects_oversized_payload(void) {
    uint8_t bytes[BRIDGEPAD_FRAME_HEADER_SIZE] = {
        1,
        BridgepadOpcodeTextAscii,
        1,
        0,
        (uint8_t)((BRIDGEPAD_MAX_FRAME_PAYLOAD + 1) & 0xFF),
        (uint8_t)((BRIDGEPAD_MAX_FRAME_PAYLOAD + 1) >> 8),
    };
    BridgepadFrame frame = {0};

    assert(bridgepad_frame_decode(bytes, sizeof(bytes), &frame) == BridgepadProtocolPayloadTooLarge);
}

static void test_encodes_ack_frame(void) {
    const uint8_t payload[] = {0x34, 0x12, BridgepadStatusOk};
    uint8_t encoded[BRIDGEPAD_MAX_FRAME_SIZE] = {0};

    const size_t encoded_size = bridgepad_frame_encode(
        BridgepadOpcodeAck, 9, payload, sizeof(payload), encoded, sizeof(encoded));

    const uint8_t expected[] = {
        1, BridgepadOpcodeAck, 9, 0, 3, 0, 0x34, 0x12, BridgepadStatusOk};
    assert(encoded_size == sizeof(expected));
    assert(memcmp(encoded, expected, sizeof(expected)) == 0);
}

static void test_rejects_non_ascii_text(void) {
    const uint8_t valid[] = "P@ssw0rd!";
    const uint8_t invalid[] = {'o', 'k', 0xC3, 0xA9};

    assert(bridgepad_text_is_supported(valid, sizeof(valid) - 1));
    assert(!bridgepad_text_is_supported(invalid, sizeof(invalid)));
    assert(!bridgepad_text_is_supported((const uint8_t*)"line\n", 5));
}

int main(void) {
    test_decodes_valid_frame();
    test_rejects_truncated_header();
    test_rejects_wrong_version();
    test_rejects_unknown_opcode();
    test_rejects_payload_length_mismatch();
    test_rejects_oversized_payload();
    test_encodes_ack_frame();
    test_rejects_non_ascii_text();
    puts("bridgepad protocol tests passed");
    return 0;
}

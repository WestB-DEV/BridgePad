#include "bridgepad_protocol.h"

#include <string.h>

bool bridgepad_opcode_is_known(uint8_t opcode) {
    switch((BridgepadOpcode)opcode) {
    case BridgepadOpcodeHello:
    case BridgepadOpcodePing:
    case BridgepadOpcodeReleaseAll:
    case BridgepadOpcodeTextAscii:
    case BridgepadOpcodeKeyDown:
    case BridgepadOpcodeKeyUp:
    case BridgepadOpcodePointerMove:
    case BridgepadOpcodePointerButton:
    case BridgepadOpcodeScroll:
    case BridgepadOpcodeStatus:
    case BridgepadOpcodeAck:
    case BridgepadOpcodeError:
        return true;
    default:
        return false;
    }
}

BridgepadProtocolResult
    bridgepad_frame_decode(const uint8_t* bytes, size_t size, BridgepadFrame* frame) {
    if(!bytes || !frame) return BridgepadProtocolInvalidArgument;
    if(size < BRIDGEPAD_FRAME_HEADER_SIZE) return BridgepadProtocolTruncated;
    if(bytes[0] != BRIDGEPAD_PROTOCOL_VERSION) return BridgepadProtocolUnsupportedVersion;
    if(!bridgepad_opcode_is_known(bytes[1])) return BridgepadProtocolUnknownOpcode;

    const uint16_t payload_length = (uint16_t)bytes[4] | ((uint16_t)bytes[5] << 8);
    if(payload_length > BRIDGEPAD_MAX_FRAME_PAYLOAD) return BridgepadProtocolPayloadTooLarge;
    if(size != BRIDGEPAD_FRAME_HEADER_SIZE + payload_length) {
        return BridgepadProtocolLengthMismatch;
    }

    frame->version = bytes[0];
    frame->opcode = (BridgepadOpcode)bytes[1];
    frame->sequence = (uint16_t)bytes[2] | ((uint16_t)bytes[3] << 8);
    frame->payload_length = payload_length;
    frame->payload = bytes + BRIDGEPAD_FRAME_HEADER_SIZE;
    return BridgepadProtocolOk;
}

size_t bridgepad_frame_encode(
    BridgepadOpcode opcode,
    uint16_t sequence,
    const uint8_t* payload,
    size_t payload_length,
    uint8_t* output,
    size_t output_capacity) {
    if(!output || !bridgepad_opcode_is_known((uint8_t)opcode)) return 0;
    if(payload_length > BRIDGEPAD_MAX_FRAME_PAYLOAD) return 0;
    if(payload_length && !payload) return 0;

    const size_t frame_size = BRIDGEPAD_FRAME_HEADER_SIZE + payload_length;
    if(output_capacity < frame_size) return 0;

    output[0] = BRIDGEPAD_PROTOCOL_VERSION;
    output[1] = (uint8_t)opcode;
    output[2] = (uint8_t)(sequence & 0xFFU);
    output[3] = (uint8_t)(sequence >> 8);
    output[4] = (uint8_t)(payload_length & 0xFFU);
    output[5] = (uint8_t)(payload_length >> 8);
    if(payload_length) memcpy(output + BRIDGEPAD_FRAME_HEADER_SIZE, payload, payload_length);
    return frame_size;
}

bool bridgepad_text_is_supported(const uint8_t* text, size_t length) {
    if(length && !text) return false;
    for(size_t index = 0; index < length; index++) {
        if(text[index] < 0x20U || text[index] > 0x7EU) return false;
    }
    return true;
}

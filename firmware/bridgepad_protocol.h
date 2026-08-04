#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define BRIDGEPAD_PROTOCOL_VERSION 1U
#define BRIDGEPAD_FRAME_HEADER_SIZE 6U
#define BRIDGEPAD_MAX_FRAME_PAYLOAD 220U
#define BRIDGEPAD_MAX_FRAME_SIZE (BRIDGEPAD_FRAME_HEADER_SIZE + BRIDGEPAD_MAX_FRAME_PAYLOAD)
#define BRIDGEPAD_MAX_TEXT_BYTES 4096U

typedef enum {
    BridgepadOpcodeHello = 0x01,
    BridgepadOpcodePing = 0x02,
    BridgepadOpcodeReleaseAll = 0x03,
    BridgepadOpcodeTextAscii = 0x10,
    BridgepadOpcodeKeyDown = 0x11,
    BridgepadOpcodeKeyUp = 0x12,
    BridgepadOpcodePointerMove = 0x20,
    BridgepadOpcodePointerButton = 0x21,
    BridgepadOpcodeScroll = 0x22,
    BridgepadOpcodeStatus = 0x80,
    BridgepadOpcodeAck = 0x81,
    BridgepadOpcodeError = 0x82,
} BridgepadOpcode;

typedef enum {
    BridgepadStatusOk = 0,
    BridgepadStatusNotArmed = 1,
    BridgepadStatusInvalidPayload = 2,
    BridgepadStatusUnsupported = 3,
    BridgepadStatusDuplicate = 4,
    BridgepadStatusUsbUnavailable = 5,
} BridgepadStatusCode;

typedef enum {
    BridgepadProtocolOk = 0,
    BridgepadProtocolTruncated,
    BridgepadProtocolUnsupportedVersion,
    BridgepadProtocolUnknownOpcode,
    BridgepadProtocolLengthMismatch,
    BridgepadProtocolPayloadTooLarge,
    BridgepadProtocolInvalidArgument,
} BridgepadProtocolResult;

typedef struct {
    uint8_t version;
    BridgepadOpcode opcode;
    uint16_t sequence;
    uint16_t payload_length;
    const uint8_t* payload;
} BridgepadFrame;

BridgepadProtocolResult
    bridgepad_frame_decode(const uint8_t* bytes, size_t size, BridgepadFrame* frame);

size_t bridgepad_frame_encode(
    BridgepadOpcode opcode,
    uint16_t sequence,
    const uint8_t* payload,
    size_t payload_length,
    uint8_t* output,
    size_t output_capacity);

bool bridgepad_opcode_is_known(uint8_t opcode);
bool bridgepad_text_is_supported(const uint8_t* text, size_t length);

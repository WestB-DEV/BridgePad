#pragma once

#include "bridgepad_protocol.h"

#define BRIDGEPAD_TX_QUEUE_DEPTH 8U

typedef struct {
    uint16_t length;
    uint8_t data[BRIDGEPAD_MAX_FRAME_SIZE];
} BridgepadTxFrame;

typedef struct {
    BridgepadTxFrame frames[BRIDGEPAD_TX_QUEUE_DEPTH];
    uint8_t head;
    uint8_t count;
    bool in_flight;
} BridgepadTxQueue;

void bridgepad_tx_queue_init(BridgepadTxQueue* queue);
void bridgepad_tx_queue_reset(BridgepadTxQueue* queue);
bool bridgepad_tx_queue_push(BridgepadTxQueue* queue, const uint8_t* data, size_t length);
BridgepadTxFrame* bridgepad_tx_queue_peek_ready(BridgepadTxQueue* queue);
void bridgepad_tx_queue_mark_in_flight(BridgepadTxQueue* queue);
bool bridgepad_tx_queue_complete(BridgepadTxQueue* queue);

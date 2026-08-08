#include "bridgepad_tx_queue.h"

#include <string.h>

void bridgepad_tx_queue_init(BridgepadTxQueue* queue) {
    if(!queue) return;
    memset(queue, 0, sizeof(*queue));
}

void bridgepad_tx_queue_reset(BridgepadTxQueue* queue) {
    bridgepad_tx_queue_init(queue);
}

bool bridgepad_tx_queue_push(BridgepadTxQueue* queue, const uint8_t* data, size_t length) {
    if(!queue || !data || length == 0 || length > BRIDGEPAD_MAX_FRAME_SIZE ||
       queue->count >= BRIDGEPAD_TX_QUEUE_DEPTH) {
        return false;
    }

    const uint8_t tail = (uint8_t)((queue->head + queue->count) % BRIDGEPAD_TX_QUEUE_DEPTH);
    BridgepadTxFrame* frame = &queue->frames[tail];
    frame->length = (uint16_t)length;
    memcpy(frame->data, data, length);
    queue->count++;
    return true;
}

BridgepadTxFrame* bridgepad_tx_queue_peek_ready(BridgepadTxQueue* queue) {
    if(!queue || queue->in_flight || queue->count == 0) return NULL;
    return &queue->frames[queue->head];
}

void bridgepad_tx_queue_mark_in_flight(BridgepadTxQueue* queue) {
    if(queue && queue->count > 0) queue->in_flight = true;
}

bool bridgepad_tx_queue_complete(BridgepadTxQueue* queue) {
    if(!queue || !queue->in_flight || queue->count == 0) return false;
    queue->head = (uint8_t)((queue->head + 1U) % BRIDGEPAD_TX_QUEUE_DEPTH);
    queue->count--;
    queue->in_flight = false;
    return true;
}

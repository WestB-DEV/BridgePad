#include "bridgepad_tx_queue.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

static void test_serializes_hello_status_and_ack(void) {
    BridgepadTxQueue queue;
    bridgepad_tx_queue_init(&queue);
    const uint8_t status[] = {1, BridgepadOpcodeStatus, 1, 0};
    const uint8_t ack[] = {1, BridgepadOpcodeAck, 1, 0};

    assert(bridgepad_tx_queue_push(&queue, status, sizeof(status)));
    assert(bridgepad_tx_queue_push(&queue, ack, sizeof(ack)));

    BridgepadTxFrame* ready = bridgepad_tx_queue_peek_ready(&queue);
    assert(ready != NULL);
    assert(ready->length == sizeof(status));
    assert(memcmp(ready->data, status, sizeof(status)) == 0);

    bridgepad_tx_queue_mark_in_flight(&queue);
    assert(bridgepad_tx_queue_peek_ready(&queue) == NULL);

    assert(bridgepad_tx_queue_complete(&queue));
    ready = bridgepad_tx_queue_peek_ready(&queue);
    assert(ready != NULL);
    assert(ready->length == sizeof(ack));
    assert(memcmp(ready->data, ack, sizeof(ack)) == 0);

    bridgepad_tx_queue_mark_in_flight(&queue);
    assert(bridgepad_tx_queue_complete(&queue));
    assert(bridgepad_tx_queue_peek_ready(&queue) == NULL);
}

static void test_rejects_overflow_without_losing_queued_frames(void) {
    BridgepadTxQueue queue;
    bridgepad_tx_queue_init(&queue);
    const uint8_t frame[] = {0xAA};

    for(size_t index = 0; index < BRIDGEPAD_TX_QUEUE_DEPTH; index++) {
        assert(bridgepad_tx_queue_push(&queue, frame, sizeof(frame)));
    }
    assert(!bridgepad_tx_queue_push(&queue, frame, sizeof(frame)));

    for(size_t index = 0; index < BRIDGEPAD_TX_QUEUE_DEPTH; index++) {
        BridgepadTxFrame* ready = bridgepad_tx_queue_peek_ready(&queue);
        assert(ready != NULL);
        assert(ready->length == sizeof(frame));
        assert(ready->data[0] == frame[0]);
        bridgepad_tx_queue_mark_in_flight(&queue);
        assert(bridgepad_tx_queue_complete(&queue));
    }
    assert(bridgepad_tx_queue_peek_ready(&queue) == NULL);
}

static void test_rejects_invalid_frames(void) {
    BridgepadTxQueue queue;
    bridgepad_tx_queue_init(&queue);
    uint8_t oversized[BRIDGEPAD_MAX_FRAME_SIZE + 1U] = {0};

    assert(!bridgepad_tx_queue_push(&queue, NULL, 1));
    assert(!bridgepad_tx_queue_push(&queue, oversized, 0));
    assert(!bridgepad_tx_queue_push(&queue, oversized, sizeof(oversized)));
}

int main(void) {
    test_serializes_hello_status_and_ack();
    test_rejects_overflow_without_losing_queued_frames();
    test_rejects_invalid_frames();
    puts("bridgepad TX queue tests passed");
    return 0;
}

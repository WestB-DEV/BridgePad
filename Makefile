.PHONY: test test-protocol test-core test-startup test-tx-queue clean

CC ?= cc
CFLAGS ?= -std=c11 -Wall -Wextra -Werror -pedantic
PROTOCOL_TEST := build/test_protocol
CORE_TEST := build/test_core
STARTUP_TEST := build/test_startup
TX_QUEUE_TEST := build/test_tx_queue

test: test-protocol test-core test-startup test-tx-queue

test-protocol: $(PROTOCOL_TEST)
	./$(PROTOCOL_TEST)

$(PROTOCOL_TEST): firmware/tests/test_protocol.c firmware/bridgepad_protocol.c firmware/bridgepad_protocol.h
	mkdir -p build
	$(CC) $(CFLAGS) -Ifirmware firmware/tests/test_protocol.c firmware/bridgepad_protocol.c -o $(PROTOCOL_TEST)

test-core: $(CORE_TEST)
	./$(CORE_TEST)

$(CORE_TEST): firmware/tests/test_core.c firmware/bridgepad_core.c firmware/bridgepad_core.h firmware/bridgepad_protocol.c firmware/bridgepad_protocol.h
	mkdir -p build
	$(CC) $(CFLAGS) -Ifirmware firmware/tests/test_core.c firmware/bridgepad_core.c firmware/bridgepad_protocol.c -o $(CORE_TEST)

test-startup: $(STARTUP_TEST)
	./$(STARTUP_TEST)

$(STARTUP_TEST): firmware/tests/test_startup.c firmware/bridgepad_startup.c firmware/bridgepad_startup.h
	mkdir -p build
	$(CC) $(CFLAGS) -Ifirmware firmware/tests/test_startup.c firmware/bridgepad_startup.c -o $(STARTUP_TEST)

test-tx-queue: $(TX_QUEUE_TEST)
	./$(TX_QUEUE_TEST)

$(TX_QUEUE_TEST): firmware/tests/test_tx_queue.c firmware/bridgepad_tx_queue.c firmware/bridgepad_tx_queue.h firmware/bridgepad_protocol.h
	mkdir -p build
	$(CC) $(CFLAGS) -Ifirmware firmware/tests/test_tx_queue.c firmware/bridgepad_tx_queue.c -o $(TX_QUEUE_TEST)

clean:
	rm -f $(PROTOCOL_TEST) $(CORE_TEST) $(STARTUP_TEST) $(TX_QUEUE_TEST)

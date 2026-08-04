.PHONY: test test-protocol test-core clean

CC ?= cc
CFLAGS ?= -std=c11 -Wall -Wextra -Werror -pedantic
PROTOCOL_TEST := build/test_protocol
CORE_TEST := build/test_core

test: test-protocol test-core

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

clean:
	rm -f $(PROTOCOL_TEST) $(CORE_TEST)

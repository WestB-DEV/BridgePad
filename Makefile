.PHONY: test test-protocol clean

CC ?= cc
CFLAGS ?= -std=c11 -Wall -Wextra -Werror -pedantic
PROTOCOL_TEST := build/test_protocol

test: test-protocol

test-protocol: $(PROTOCOL_TEST)
	./$(PROTOCOL_TEST)

$(PROTOCOL_TEST): firmware/tests/test_protocol.c firmware/bridgepad_protocol.c firmware/bridgepad_protocol.h
	mkdir -p build
	$(CC) $(CFLAGS) -Ifirmware firmware/tests/test_protocol.c firmware/bridgepad_protocol.c -o $(PROTOCOL_TEST)

clean:
	rm -f $(PROTOCOL_TEST)

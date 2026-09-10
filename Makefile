.PHONY: test test-protocol test-core test-startup test-hid clean

CC ?= cc
CFLAGS ?= -std=c11 -Wall -Wextra -Werror -pedantic
PROTOCOL_TEST := build/test_protocol
CORE_TEST := build/test_core
STARTUP_TEST := build/test_startup
HID_TEST := build/test_hid

test: test-protocol test-core test-startup test-hid

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

test-hid: $(HID_TEST)
	./$(HID_TEST)

$(HID_TEST): firmware/tests/test_hid.c firmware/bridgepad_hid.h
	mkdir -p build
	$(CC) $(CFLAGS) -Ifirmware firmware/tests/test_hid.c -o $(HID_TEST)

clean:
	rm -f $(PROTOCOL_TEST) $(CORE_TEST) $(STARTUP_TEST) $(HID_TEST)

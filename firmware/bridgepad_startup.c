#include "bridgepad_startup.h"

void bridgepad_startup_init(BridgepadStartup* startup) {
    startup->bluetooth_started = false;
    startup->usb_started = false;
}

void bridgepad_startup_try(
    BridgepadStartup* startup,
    BridgepadStartupFunction start_bluetooth,
    BridgepadStartupFunction start_usb,
    void* context) {
    if(!startup->bluetooth_started) {
        startup->bluetooth_started = start_bluetooth(context);
    }
    if(!startup->usb_started) {
        startup->usb_started = start_usb(context);
    }
}

bool bridgepad_startup_ready(const BridgepadStartup* startup) {
    return startup->bluetooth_started && startup->usb_started;
}

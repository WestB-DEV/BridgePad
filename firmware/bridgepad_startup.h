#pragma once

#include <stdbool.h>

typedef bool (*BridgepadStartupFunction)(void* context);

typedef struct {
    bool bluetooth_started;
    bool usb_started;
} BridgepadStartup;

void bridgepad_startup_init(BridgepadStartup* startup);
void bridgepad_startup_try(
    BridgepadStartup* startup,
    BridgepadStartupFunction start_bluetooth,
    BridgepadStartupFunction start_usb,
    void* context);
bool bridgepad_startup_ready(const BridgepadStartup* startup);

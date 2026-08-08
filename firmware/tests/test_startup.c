#include "bridgepad_startup.h"

#include <assert.h>
#include <stdbool.h>
#include <stdio.h>

typedef struct {
    unsigned bluetooth_attempts;
    unsigned usb_attempts;
    unsigned usb_failures_remaining;
} FakeStartupHardware;

static bool fake_start_bluetooth(void* context) {
    FakeStartupHardware* hardware = context;
    hardware->bluetooth_attempts++;
    return true;
}

static bool fake_start_usb(void* context) {
    FakeStartupHardware* hardware = context;
    hardware->usb_attempts++;
    if(hardware->usb_failures_remaining) {
        hardware->usb_failures_remaining--;
        return false;
    }
    return true;
}

static void test_failed_usb_start_is_recoverable(void) {
    FakeStartupHardware hardware = {.usb_failures_remaining = 1};
    BridgepadStartup startup;
    bridgepad_startup_init(&startup);

    bridgepad_startup_try(
        &startup, fake_start_bluetooth, fake_start_usb, &hardware);

    assert(startup.bluetooth_started);
    assert(!startup.usb_started);
    assert(!bridgepad_startup_ready(&startup));

    bridgepad_startup_try(
        &startup, fake_start_bluetooth, fake_start_usb, &hardware);

    assert(startup.bluetooth_started);
    assert(startup.usb_started);
    assert(bridgepad_startup_ready(&startup));
    assert(hardware.usb_attempts == 2);
}

static void test_retry_does_not_restart_successful_subsystems(void) {
    FakeStartupHardware hardware = {.usb_failures_remaining = 1};
    BridgepadStartup startup;
    bridgepad_startup_init(&startup);

    bridgepad_startup_try(
        &startup, fake_start_bluetooth, fake_start_usb, &hardware);
    bridgepad_startup_try(
        &startup, fake_start_bluetooth, fake_start_usb, &hardware);

    assert(hardware.bluetooth_attempts == 1);
    assert(hardware.usb_attempts == 2);
}

int main(void) {
    test_failed_usb_start_is_recoverable();
    test_retry_does_not_restart_successful_subsystems();
    puts("bridgepad startup tests passed");
    return 0;
}

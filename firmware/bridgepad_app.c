#include "bridgepad_core.h"
#include "bridgepad_protocol.h"
#include "bridgepad_startup.h"

#include <bt/bt_service/bt.h>
#include <furi.h>
#include <furi_hal_bt.h>
#include <furi_hal_usb.h>
#include <furi_hal_usb_hid.h>
#include <gui/gui.h>
#include <gui/view_port.h>
#include <profiles/serial_profile.h>
#include <storage/storage.h>

#include <string.h>

#define BRIDGEPAD_QUEUE_DEPTH 8U
#define BRIDGEPAD_USB_VID 0x1209U
#define BRIDGEPAD_USB_PID 0xB1D6U

typedef enum {
    BridgepadEventInput,
    BridgepadEventBleConnected,
    BridgepadEventBleDisconnected,
    BridgepadEventUsbConnected,
    BridgepadEventUsbDisconnected,
    BridgepadEventBleData,
    BridgepadEventBleReset,
} BridgepadEventType;

typedef struct {
    BridgepadEventType type;
    InputEvent input;
    uint16_t data_length;
    uint8_t data[BRIDGEPAD_MAX_FRAME_SIZE];
} BridgepadEvent;

typedef struct {
    BridgepadCore core;
    FuriMessageQueue* queue;
    FuriMutex* display_mutex;
    Gui* gui;
    ViewPort* view_port;
    Bt* bt;
    FuriHalBleProfileBase* serial_profile;
    FuriHalUsbInterface* previous_usb_config;
    BridgepadStartup startup;
    bool exit_requested;
    bool display_ble_connected;
    bool display_usb_connected;
    bool display_armed;
    char error_text[32];
} BridgepadApp;

static const FuriHalUsbHidConfig bridgepad_usb_config = {
    .vid = BRIDGEPAD_USB_VID,
    .pid = BRIDGEPAD_USB_PID,
    .manuf = "BridgePad Project",
    .product = "BridgePad HID",
};

static void bridgepad_queue_event(BridgepadApp* app, const BridgepadEvent* event) {
    furi_message_queue_put(app->queue, event, 0);
}

static void bridgepad_input_callback(InputEvent* input, void* context) {
    BridgepadApp* app = context;
    BridgepadEvent event = {.type = BridgepadEventInput, .input = *input};
    bridgepad_queue_event(app, &event);
}

static void bridgepad_usb_state_callback(bool connected, void* context) {
    BridgepadApp* app = context;
    BridgepadEvent event = {
        .type = connected ? BridgepadEventUsbConnected : BridgepadEventUsbDisconnected,
    };
    bridgepad_queue_event(app, &event);
}

static void bridgepad_bt_status_callback(BtStatus status, void* context) {
    BridgepadApp* app = context;
    BridgepadEvent event = {
        .type = status == BtStatusConnected ? BridgepadEventBleConnected :
                                             BridgepadEventBleDisconnected,
    };
    bridgepad_queue_event(app, &event);
}

static uint16_t bridgepad_serial_callback(SerialServiceEvent serial_event, void* context) {
    BridgepadApp* app = context;
    if(serial_event.event == SerialServiceEventTypeDataReceived) {
        BridgepadEvent event = {.type = BridgepadEventBleData};
        event.data_length = MIN(serial_event.data.size, (uint16_t)sizeof(event.data));
        memcpy(event.data, serial_event.data.buffer, event.data_length);
        bridgepad_queue_event(app, &event);
    } else if(serial_event.event == SerialServiceEventTypesBleResetRequest) {
        const BridgepadEvent event = {.type = BridgepadEventBleReset};
        bridgepad_queue_event(app, &event);
    }
    return serial_event.data.size;
}

static void bridgepad_hid_release_all(void* context) {
    UNUSED(context);
    furi_hal_hid_kb_release_all();
    furi_hal_hid_consumer_key_release_all();
    furi_hal_hid_mouse_release(0);
}

static bool bridgepad_hid_text_ascii(void* context, const uint8_t* text, size_t length) {
    UNUSED(context);
    for(size_t index = 0; index < length; index++) {
        const uint16_t keycode = HID_ASCII_TO_KEY(text[index]);
        if(keycode == HID_KEYBOARD_NONE) return false;
        if(!furi_hal_hid_kb_press(keycode)) return false;
        furi_delay_ms(6);
        if(!furi_hal_hid_kb_release(keycode)) return false;
        furi_delay_ms(6);
    }
    return true;
}

static bool bridgepad_hid_key_press(void* context, uint16_t keycode) {
    UNUSED(context);
    return furi_hal_hid_kb_press(keycode);
}

static bool bridgepad_hid_key_release(void* context, uint16_t keycode) {
    UNUSED(context);
    return furi_hal_hid_kb_release(keycode);
}

static bool bridgepad_hid_pointer_move(void* context, int8_t dx, int8_t dy) {
    UNUSED(context);
    return furi_hal_hid_mouse_move(dx, dy);
}

static bool bridgepad_hid_pointer_button(void* context, uint8_t mask, bool down) {
    UNUSED(context);
    return down ? furi_hal_hid_mouse_press(mask) : furi_hal_hid_mouse_release(mask);
}

static bool bridgepad_hid_scroll(void* context, int8_t delta) {
    UNUSED(context);
    return furi_hal_hid_mouse_scroll(delta);
}

static void bridgepad_send_frame(
    void* context,
    BridgepadOpcode opcode,
    uint16_t sequence,
    const uint8_t* payload,
    size_t payload_length) {
    BridgepadApp* app = context;
    if(!app->serial_profile) return;
    uint8_t encoded[BRIDGEPAD_MAX_FRAME_SIZE];
    const size_t encoded_length = bridgepad_frame_encode(
        opcode, sequence, payload, payload_length, encoded, sizeof(encoded));
    if(encoded_length) {
        ble_profile_serial_tx(app->serial_profile, encoded, (uint16_t)encoded_length);
    }
}

static void bridgepad_draw_callback(Canvas* canvas, void* context) {
    BridgepadApp* app = context;
    furi_mutex_acquire(app->display_mutex, FuriWaitForever);
    const bool ble_connected = app->display_ble_connected;
    const bool usb_connected = app->display_usb_connected;
    const bool armed = app->display_armed;
    char error_text[sizeof(app->error_text)];
    strlcpy(error_text, app->error_text, sizeof(error_text));
    furi_mutex_release(app->display_mutex);

    canvas_clear(canvas);
    canvas_set_font(canvas, FontPrimary);
    canvas_draw_str(canvas, 4, 11, "BridgePad");
    canvas_set_font(canvas, FontSecondary);
    canvas_draw_str(canvas, 4, 25, ble_connected ? "Phone: connected" : "Phone: waiting");
    canvas_draw_str(canvas, 4, 36, usb_connected ? "USB: keyboard + mouse" : "USB: waiting");
    canvas_draw_str(canvas, 4, 47, armed ? "ARMED - Back stops" : "OK to arm");
    if(error_text[0]) canvas_draw_str(canvas, 4, 59, error_text);
}

static void bridgepad_refresh(BridgepadApp* app) {
    furi_mutex_acquire(app->display_mutex, FuriWaitForever);
    app->display_ble_connected = app->core.ble_connected;
    app->display_usb_connected = app->core.usb_connected;
    app->display_armed = app->core.armed;
    furi_mutex_release(app->display_mutex);
    view_port_update(app->view_port);
}

static void bridgepad_set_error(BridgepadApp* app, const char* message) {
    furi_mutex_acquire(app->display_mutex, FuriWaitForever);
    strlcpy(app->error_text, message, sizeof(app->error_text));
    furi_mutex_release(app->display_mutex);
}

static void bridgepad_clear_error(BridgepadApp* app) {
    bridgepad_set_error(app, "");
}

static void bridgepad_reclaim_serial_profile(BridgepadApp* app) {
    if(!app->serial_profile) return;
    ble_profile_serial_set_event_callback(
        app->serial_profile, BRIDGEPAD_MAX_FRAME_SIZE, bridgepad_serial_callback, app);
    ble_profile_serial_set_rpc_active(app->serial_profile, false);
    ble_profile_serial_notify_buffer_is_empty(app->serial_profile);
}

static bool bridgepad_start_usb(void* context) {
    BridgepadApp* app = context;
    app->previous_usb_config = furi_hal_usb_get_config();
    furi_hal_hid_set_state_callback(bridgepad_usb_state_callback, app);
    if(!furi_hal_usb_set_config(&usb_hid, (void*)&bridgepad_usb_config)) {
        furi_hal_hid_set_state_callback(NULL, NULL);
        return false;
    }
    bridgepad_core_set_usb_connected(&app->core, furi_hal_hid_is_connected(), furi_get_tick());
    return true;
}

static void bridgepad_stop_bluetooth(BridgepadApp* app) {
    if(!app->bt) return;
    bt_set_status_changed_callback(app->bt, NULL, NULL);
    bt_disconnect(app->bt);
    furi_delay_ms(200);
    if(app->serial_profile) {
        ble_profile_serial_set_event_callback(app->serial_profile, 0, NULL, NULL);
        app->serial_profile = NULL;
    }
    bt_keys_storage_set_default_path(app->bt);
    bt_profile_restore_default(app->bt);
    furi_record_close(RECORD_BT);
    app->bt = NULL;
}

static bool bridgepad_start_bluetooth(void* context) {
    BridgepadApp* app = context;
    app->bt = furi_record_open(RECORD_BT);
    if(!app->bt) return false;
    bt_set_status_changed_callback(app->bt, bridgepad_bt_status_callback, app);
    bt_disconnect(app->bt);
    furi_delay_ms(200);
    bt_keys_storage_set_storage_path(app->bt, APP_DATA_PATH("bridgepad.keys"));
    app->serial_profile = bt_profile_start(app->bt, ble_profile_serial, NULL);
    if(!app->serial_profile) {
        bridgepad_stop_bluetooth(app);
        return false;
    }
    bridgepad_reclaim_serial_profile(app);
    furi_hal_bt_start_advertising();
    return true;
}

static void bridgepad_stop_hardware(BridgepadApp* app) {
    bridgepad_core_disarm(&app->core);
    if(app->startup.usb_started) {
        bridgepad_hid_release_all(app);
        furi_hal_hid_set_state_callback(NULL, NULL);
        furi_hal_usb_set_config(app->previous_usb_config, NULL);
        app->startup.usb_started = false;
    }
    bridgepad_stop_bluetooth(app);
    app->startup.bluetooth_started = false;
}

static void bridgepad_update_startup_error(BridgepadApp* app) {
    if(!app->startup.bluetooth_started) {
        bridgepad_set_error(app, "BT busy: OK to retry");
    } else if(!app->startup.usb_started) {
        bridgepad_set_error(app, "USB busy: close qFlip");
    } else {
        bridgepad_clear_error(app);
    }
}

static void bridgepad_try_start_hardware(BridgepadApp* app) {
    bridgepad_startup_try(
        &app->startup, bridgepad_start_bluetooth, bridgepad_start_usb, app);
    bridgepad_update_startup_error(app);
}

static bool bridgepad_app_init(BridgepadApp* app) {
    memset(app, 0, sizeof(*app));
    bridgepad_startup_init(&app->startup);
    app->queue = furi_message_queue_alloc(BRIDGEPAD_QUEUE_DEPTH, sizeof(BridgepadEvent));
    if(!app->queue) return false;
    app->display_mutex = furi_mutex_alloc(FuriMutexTypeNormal);
    if(!app->display_mutex) return false;
    const BridgepadCoreIo io = {
        .context = app,
        .release_all = bridgepad_hid_release_all,
        .text_ascii = bridgepad_hid_text_ascii,
        .key_press = bridgepad_hid_key_press,
        .key_release = bridgepad_hid_key_release,
        .pointer_move = bridgepad_hid_pointer_move,
        .pointer_button = bridgepad_hid_pointer_button,
        .scroll = bridgepad_hid_scroll,
        .send_frame = bridgepad_send_frame,
    };
    bridgepad_core_init(&app->core, &io);

    app->view_port = view_port_alloc();
    if(!app->view_port) return false;
    view_port_draw_callback_set(app->view_port, bridgepad_draw_callback, app);
    view_port_input_callback_set(app->view_port, bridgepad_input_callback, app);
    app->gui = furi_record_open(RECORD_GUI);
    if(!app->gui) return false;
    gui_add_view_port(app->gui, app->view_port, GuiLayerFullscreen);

    bridgepad_try_start_hardware(app);
    return true;
}

static void bridgepad_app_free(BridgepadApp* app) {
    bridgepad_stop_hardware(app);
    if(app->gui && app->view_port) gui_remove_view_port(app->gui, app->view_port);
    if(app->view_port) view_port_free(app->view_port);
    if(app->gui) furi_record_close(RECORD_GUI);
    if(app->display_mutex) furi_mutex_free(app->display_mutex);
    if(app->queue) furi_message_queue_free(app->queue);
    free(app);
}

static void bridgepad_handle_input(BridgepadApp* app, const InputEvent* input) {
    if(input->type != InputTypeShort) return;
    if(input->key == InputKeyOk) {
        if(!bridgepad_startup_ready(&app->startup)) {
            bridgepad_try_start_hardware(app);
            return;
        }
        bridgepad_clear_error(app);
        if(!bridgepad_core_toggle_arm(&app->core, furi_get_tick()) && !app->core.armed) {
            bridgepad_set_error(app, "Connect phone + USB");
        }
    } else if(input->key == InputKeyBack) {
        if(app->core.armed) {
            bridgepad_core_disarm(&app->core);
        } else {
            app->exit_requested = true;
        }
    }
}

static void bridgepad_handle_data(BridgepadApp* app, const BridgepadEvent* event) {
    BridgepadFrame frame;
    const BridgepadProtocolResult result =
        bridgepad_frame_decode(event->data, event->data_length, &frame);
    if(result == BridgepadProtocolOk) {
        bridgepad_core_handle_frame(&app->core, &frame, furi_get_tick());
    } else {
        bridgepad_set_error(app, "Invalid BLE frame");
    }
    ble_profile_serial_notify_buffer_is_empty(app->serial_profile);
}

static void bridgepad_handle_event(BridgepadApp* app, const BridgepadEvent* event) {
    switch(event->type) {
    case BridgepadEventInput:
        bridgepad_handle_input(app, &event->input);
        break;
    case BridgepadEventBleConnected:
        bridgepad_reclaim_serial_profile(app);
        bridgepad_core_set_ble_connected(&app->core, true, furi_get_tick());
        bridgepad_clear_error(app);
        break;
    case BridgepadEventBleDisconnected:
        bridgepad_core_set_ble_connected(&app->core, false, furi_get_tick());
        break;
    case BridgepadEventUsbConnected:
        bridgepad_core_set_usb_connected(&app->core, true, furi_get_tick());
        break;
    case BridgepadEventUsbDisconnected:
        bridgepad_core_set_usb_connected(&app->core, false, furi_get_tick());
        break;
    case BridgepadEventBleData:
        bridgepad_handle_data(app, event);
        break;
    case BridgepadEventBleReset:
        bridgepad_core_disarm(&app->core);
        break;
    }
    bridgepad_refresh(app);
}

int32_t bridgepad_app(void* context) {
    UNUSED(context);
    BridgepadApp* app = malloc(sizeof(BridgepadApp));
    if(!app) return -1;
    const bool initialized = bridgepad_app_init(app);
    if(initialized) bridgepad_refresh(app);

    while(initialized && !app->exit_requested) {
        BridgepadEvent event;
        if(furi_message_queue_get(app->queue, &event, 100) == FuriStatusOk) {
            bridgepad_handle_event(app, &event);
        }
        bridgepad_core_tick(&app->core, furi_get_tick());
    }

    bridgepad_app_free(app);
    return 0;
}

# BridgePad BLE Protocol v1

BridgePad uses the official Flipper serial service:

| Role | UUID |
|---|---|
| Service | `8fe5b3d5-2e7f-4a98-2a48-7acc60fe0000` |
| Phone writes / RX | `19ed82ae-ed21-4c9d-4145-228e62fe0000` |
| Phone subscribes / TX | `19ed82ae-ed21-4c9d-4145-228e61fe0000` |
| Flow control | `19ed82ae-ed21-4c9d-4145-228e63fe0000` |

Bonding is handled by the platform and the Flipper stores BridgePad keys in the application's private data path.

## Frame

All multi-byte integers are little-endian.

| Offset | Field | Size |
|---:|---|---:|
| 0 | version (`1`) | 1 |
| 1 | opcode | 1 |
| 2 | sequence | 2 |
| 4 | payload length | 2 |
| 6 | payload | 0–220 |

Reliable commands receive an `ACK` or `ERROR`. Those response payloads contain `acknowledgedSequence:u16LE | status:u8`. A duplicate reliable sequence is acknowledged with status `4` but not executed again.

## Opcodes

| Name | Value | Payload |
|---|---:|---|
| `HELLO` | `0x01` | empty; returns `STATUS`, then `ACK` |
| `PING` | `0x02` | empty |
| `RELEASE_ALL` | `0x03` | empty; releases and disarms |
| `TEXT_ASCII` | `0x10` | 1–220 printable bytes (`0x20`–`0x7e`) |
| `KEY_DOWN` | `0x11` | HID keyboard usage `u16LE` |
| `KEY_UP` | `0x12` | HID keyboard usage `u16LE` |
| `POINTER_MOVE` | `0x20` | signed `dx:i8 | dy:i8` |
| `POINTER_BUTTON` | `0x21` | mask `u8` (1/2/4) and state `u8` (0/1) |
| `SCROLL` | `0x22` | non-zero signed delta `i8` |
| `STATUS` | `0x80` | flags, protocol version, maximum payload `u16LE` |
| `ACK` | `0x81` | acknowledged sequence and status |
| `ERROR` | `0x82` | rejected sequence and status |

`STATUS` flag bits are BLE connected = 0, USB connected = 1, armed = 2. Status codes are OK = 0, not armed = 1, invalid payload = 2, unsupported = 3, duplicate = 4, and USB unavailable = 5.

The phone sends `PING` every two seconds. Five seconds without a heartbeat disarms the Flipper and releases every keyboard key and mouse button. A single text operation is capped at 4,096 bytes and split into sequentially acknowledged frames.

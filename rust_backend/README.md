# MLRC ACCS Rust backend

This crate implements the first Rust backend layer: watcher mode checks, transport selection, and frame transport. It accepts opaque frame bytes; it does not capture screens, encode/decode media, render frames, discover peers, or expose an FFI to Flutter. The Flutter controls are not connected to this crate yet.

## Build and test

```powershell
cargo test
cargo test --features usb
```

The default build includes Wi-Fi/UDP support. The `usb` feature adds the libusb implementation (`rusb`); USB builds may need platform-specific libusb/driver setup.

## UDP

Create a `UdpConfig` on each peer with its local bind address and the other peer's socket address. Frames are split into datagrams using this 12-byte big-endian header:

| Bytes | Field |
|---|---|
| 0–3 | `MAC1` signature |
| 4–7 | Frame sequence number |
| 8–9 | Chunk index |
| 10–11 | Chunk count |

The receiver reassembles chunks, discards duplicate/expired data, and uses the configured bounded jitter buffer to move past missing frame sequence numbers. UDP is best-effort: it does not retransmit lost packets. The default packet payload is 1200 bytes, the maximum accepted frame is 32 MiB, and total receive buffering is capped at 64 MiB.

## USB bulk

Configure the USB vendor/product IDs, interface number, IN and OUT endpoint addresses, timeout, and maximum frame size in `UsbConfig`. The peer must implement the same framing: each direction sends a 4-byte big-endian frame length followed by that many bytes on its bulk endpoint. Device enumeration, endpoint discovery, peer firmware, and USB authorization/driver installation are outside this crate.

## Watcher API

`WatcherConfig` selects `Transmit` or `Receive`, an explicit `Usb`/`Wifi` preference or `Auto`, and the corresponding transport settings. `Auto` tries configured USB first and uses Wi-Fi on USB initialization failure; the reason is available from `fallback_reason()`. Call `transmit()` or `receive()` only in the matching mode.

This transport protocol is currently unauthenticated and should only be used on a trusted network or with a trusted USB peer.

# Protocol-Agnostic, Cross-OS Local Transport & Streaming Bridge

A single-codebase (**Rust core + Flutter UI**) node-to-node control, telemetry, and screen/camera streaming bridge supporting seamless operation across **Android, Windows, and Linux** over the commercial proximity communication stack (**USB $\rightarrow$ Wi-Fi $\rightarrow$ Bluetooth**).

---

## 1. Core Architectural Vision

Modern remote desktop and screen-mirroring ecosystems assume either a stable IP network (e.g., RustDesk, WebRTC) or an asymmetric host-to-mobile pipeline (e.g., `scrcpy` over ADB/Wi-Fi). They break down in air-gapped, infrastructure-free, or severely bandwidth- and power-constrained environments where devices must communicate directly over heterogeneous local links.

This project decouples the **application & media/control payload layer** from the **physical/link transport layer** via a unified Rust transport abstraction:

1. **USB (OTG / ADB / Bulk / Serial):** High-throughput, ultra-low-latency primary wired path when physically tethered.
2. **Wi-Fi (Local LAN / Direct UDP & TCP Sockets):** Primary high-bandwidth wireless path for real-time screen/camera frames and low-latency HID control.
3. **Bluetooth (Classic RFCOMM/SPP & BLE):** Resilient last-resort / low-power degraded mode supporting control commands, compact telemetry payloads, and aggressively downscaled/delta-compressed visual state updates.

---

## 2. Positioning Against Existing Literature & Systems

While existing tools share portions of the implementation stack (e.g., Rust + Flutter cross-platform builds), none address **symmetric any-to-any OS local connectivity across non-IP and IP proximity transports**:

| System / Literature Domain | OS Topology | Supported Transports | Key Architectural Gap Addressed by This Work |
| :--- | :--- | :--- | :--- |
| **`scrcpy` / `QtScrcpy`** | Asymmetric (Desktop $\rightarrow$ Android only) | USB (ADB) & Wi-Fi | Relies on Android ADB daemon; no any-to-any OS symmetry (e.g., Android $\rightarrow$ Windows/Linux); zero Bluetooth support. |
| **`RustDesk`** | Symmetric (Windows $\leftrightarrow$ Linux $\leftrightarrow$ Android $\leftrightarrow$ macOS) | IP Networks Only (TCP/UDP, relay/NAT) | Assumes routable IP sockets; lacks local physical bus support (USB OTG/serial) and low-bandwidth Bluetooth fallback modes. |
| **`ZenLink` / `ZeroLink`** | Asymmetric / Local LAN | USB & Wi-Fi | Optimized for standard screen mirroring; lacks unified tri-modal transport fallback into Bluetooth. |
| **Multipath & Handover Literature (MPTCP, IEEE 802.21)** | Enterprise / IP-routable interfaces | Wi-Fi / Cellular / Ethernet | Bonding asymmetric paths causes Head-of-Line (HoL) blocking; omits local peripheral buses (USB OTG) and raw RFCOMM pipes. |
| **Bluetooth Media Studies (`mBlueThunder`, *ImgBeacon*)** | Homogeneous / Single-link | Bluetooth Classic (L2CAP/RFCOMM) or BLE | Focuses on isolated Bluetooth link-layer buffering or static BLE beacon broadcasts without cross-OS multi-transport switching. |

---

## 3. IEEE / ACM Paper Framing: Scope vs. Future Work

To maintain strict scientific rigor and empirical defensibility for peer review, the research contribution is partitioned into **Current Scope** (implemented and benchmarked) and **Future Development** (architectural roadmap).

### Current Paper Scope (Node-to-Node Tri-Modal Bridge)
* **Unified Transport Abstraction:** A compiled Rust networking core exposing a uniform async stream/datagram trait over OS-specific USB, Wi-Fi socket, and Bluetooth Classic/BLE adapters, paired with a single Flutter interface.
* **Degraded-Mode Adaptation:** Rate- and payload-adaptive framing inspired by real-time congestion control—dropping stale frames to avoid bufferbloat and scaling down visual fidelity/FPS when falling back to Bluetooth.
* **Empirical Systems Evaluation:**
  * End-to-end RTT latency, jitter, and effective goodput across **USB vs. Wi-Fi vs. Bluetooth** on Android, Windows, and Linux.
  * Transport switch-over latency and frame-drop cost during forced link degradation.
  * Resource footprint comparison (release binary size, RAM RSS, CPU utilization, and shared vs. platform-specific SLOC).

### Future Work (Near-Device Resilient Multi-Node Cluster)
The long-term objective of this architecture—explicitly scoped as **future work** beyond the current pairwise evaluation—is **near-device, multi-node, resilient local cluster communication**:
* **Dynamic Payload-Driven Protocol Selection:** Automatically routing traffic across transports based on *what* is being shared (e.g., dispatching sub-kilobyte control/state messages over BLE/RFCOMM while reserving Wi-Fi/USB for high-bitrate video frames).
* **State- & Battery-Aware Transport Switching:** Incorporating node telemetry—such as **remaining battery level**, thermal throttling, and RF channel interference—into a formalized hysteresis cost function so devices dynamically downshift to lower-power radios (e.g., Bluetooth) without manual intervention.
* **Multi-Node Mesh & Topology Orchestration:** Extending pairwise node-to-node links into self-healing local clusters across heterogeneous consumer hardware without external cloud or router infrastructure.

---

## 4. Draft Introduction / Positioning Paragraph (Ready for Paper)

> *"While modern cross-platform remote-access tools leverage unified UI and systems frameworks (such as Flutter and Rust) to span desktop and mobile operating systems, they remain fundamentally tied to routable IP networks and homogeneous link assumptions. Conversely, existing mobile mirroring utilities exploit local USB and Wi-Fi links but remain asymmetric and omit Bluetooth fallbacks. In this work, we present a protocol-agnostic, cross-OS node-to-node control and visual streaming bridge spanning Android, Windows, and Linux across USB, Wi-Fi, and Bluetooth. By decoupling media/control framing from underlying transport drivers and introducing graceful degraded-mode adaptation for constrained Bluetooth links, our architecture establishes a foundational building block toward resilient, near-device multi-node local clusters capable of dynamically switching protocols based on payload characteristics and device state (such as battery constraints), which we outline as our primary direction for future work."*

---

## 5. Build & Size Audit Quick Reference

When benchmarking mobile binary footprint for systems evaluation, always measure single-ABI release artifacts rather than universal debug builds:

```bash
# Generate split-ABI release APKs with symbol/size breakdown
flutter build apk --release --split-per-abi --analyze-size
```
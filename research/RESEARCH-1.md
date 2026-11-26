# Protocol-Agnostic Screen Mirroring with Automatic Transport Fallback
## Exhaustive prior-art survey: tools, papers, ratings, exact-match verdict, and IEEE-publishability gap analysis

**Survey date:** 2026-11-26 (Europe/Bucharest). All GitHub stars, GitHub release-download counts, Crossref citation counts and Semantic Scholar counts were measured live on this date unless marked `≈` (from prior knowledge, not re-fetched).
**Prepared for:** MLRC ACCS (Flutter/Dart UI + Rust backend via FFI; MAC1/MAA1 wire protocol over connected UDP; fixed presence port 38421; roadmap: Bluetooth SPP/RFCOMM and USB host↔gadget transports with automatic fallback).

---

## 0. Executive verdict

> **No publicly documented tool or paper does what MLRC ACCS aims to do: continuous interactive screen mirroring between phone and PC where Bluetooth (SPP/RFCOMM), USB (gadget NCM/RNDIS or host ADB) and Wi-Fi (UDP) are all *first-class video carriers*, with *runtime automatic fallback* between them, driven by *one native Rust core compiled for both ends* (`.so` on Android, `.dll` on Windows).**

Three near-misses, none exact:

1. **TwinDesk** (GitHub `InukaAsith/TwinDesk`, 4.7k★, ~109k downloads in ~6 weeks) — the single closest system. It has genuine runtime auto-fallback (same Wi-Fi → USB cable → Bluetooth, plus on-demand Wi-Fi Direct bring-up). **But: video/screens never ride Bluetooth.** Its own README: screens and big files on a Bluetooth-only link *"moves to Wi-Fi Direct"* — Bluetooth carries session, clipboard text, notifications, input, calls. So TwinDesk is a *multi-transport KVM/companion*, not Bluetooth video. Its stack is Node/JS core + native OS helpers, not one native codebase.
2. **ZenLink** (`zenvyzenshiro/zenlink`, 542★, ~12k dl) — the closest *Rust single-codebase* mirroring engine (Windows host; iPhone over AirPlay/USB/CoreDevice, Android over scrcpy-server/ADB, USB or Wi-Fi). But connections are **user-picked** ("Five ways to connect. **Pick one** … switch any time in Settings"), there is **no Bluetooth at all** ("Not available on any version: … Bluetooth HID control"), and no automatic failover.
3. **ZeroLink** (`erTesla/ZeroLink-public`, 25★, Kotlin Compose Multiplatform) — the closest *single-cross-platform-codebase* philosophy (one Kotlin codebase, PC + Android; TCP length-prefixed JPEG frames on LAN; PIN auth; USB only via `adb reverse` tunnel). No Bluetooth, no fallback, no H.264, no PC→phone direction.

**Literature:** the ingredients are each studied — multipath/handover (MPTCP, QUIC multipath, Wi-Fi-loss prediction for handover), interactive video over heterogeneous radios (IEEE TWC 2012, probabilistic multipath video over Wi-Fi+3G), video-over-Bluetooth engineering (2007–2021 cluster), thin-client remote display (TILE proxy, Pica, Mosh, Conductor), Rust systems memory-safety (PLDI'20, TOSEM'21, CACM'21) — **but a zero-result sweep (Section 6.5) found no paper proposing or evaluating screen mirroring that switches automatically among Bluetooth, USB and Wi-Fi.** The exact intersection is open.

---

## 1. What we are comparing against

MLRC ACCS target profile (as designed in this repo):

| Property | MLRC ACCS target |
|---|---|
| Direction | phone ⇄ PC (both directions eventually) |
| Content | interactive screen mirroring (video + input), file transfer later |
| Transports (all equal citizens) | Wi-Fi UDP (:38421 presence, connected UDP media) · Bluetooth SPP/RFCOMM · USB host↔gadget (NCM/RNDIS → unified IP plane) |
| Behavior | **automatic fallback/switch** at runtime with zero shared network required |
| Codebase | one Rust backend (cdylib, C ABI, Dart FFI) reused on phone and PC; Flutter UI |
| Security today | PIN/none (auth deferred) — TwinDesk, ZeroLink, ZenLink all ship pairing/PIN already |

The four pillars used throughout this survey: **(P1) video over Wi-Fi, (P2) video over USB, (P3) video over Bluetooth, (P4) automatic runtime fallback among the available ones** — plus **(P5) one native core on both endpoints**.

---

## 2. Method and integrity notes

- ⚠️ **The `web_search` tool was broken during this survey** (DeepSeek API 401 — invalid plugin key). Everything below was gathered through direct, auditable API calls instead: GitHub REST (search + repos), arXiv Atom API, Crossref REST (with polite UA), Semantic Scholar title-match, shields.io download counters, and DuckDuckGo HTML search via `web_fetch`. This arguably made the sweep *more* precise than ad clicks. Fix: **Plugins → Built-in → Web search** in DeepSeek Harness and enter a valid key.
- GitHub stars + **GitHub release download totals** (shields.io) are the popularity proxy. They under-count Homebrew/Play Store/website distribution (e.g. scrcpy is also in brew; RustDesk installers ship from their own site too), so treat as lower bounds.
- Every reference is flagged: **✅** = DOI/record and citation count verified live today; **⚠** = well-known work whose exact DOI was not confirmed today — cite from the venue record, not from this document's memory.
- Negative results are recorded as evidence, not silence (Section 6.5 lists the queries that returned **zero** relevant papers).
- Naming disambiguation: “**ZeroLink**” here is `erTesla/ZeroLink-public` (screen sharing); the 346★ `nopara73/ZeroLink` is a Bitcoin privacy framework — unrelated. “**Luna**” was resolved as **Astropad Luna Display** (closed-source USB-C dongle second-screen system, “connecting over Wi-Fi or cable”). The KVM lineage Barrier → Input Leap (repo archived Dec 2025) → **Deskflow** (Linux Foundation, 31.7k★) is one family.

Rating legend — **Popularity tier:** S ≥ 100k★ or ≥10 M GH downloads; A ≥ 20k★ or ≥1 M; B ≥ 2k★ or ≥10 k; C 100–2k★; D <100★. **Arch prowess (1–10):** engineering ambition, transport/protocol design, latency discipline, single-codebase discipline, code-organization evidence; my judgment from READMEs, docs and architecture sections read in full during this survey.

---

## 3. Master table — open-source tools (measured 2026-11-26, sorted by stars)

| # | Project | ★ | GH dl (total) | Lang / stack | License | Created | Transports for **screen video** | Auto runtime fallback? | P3 BT video? | Tier | Arch /10 | One-line note |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | [scrcpy](https://github.com/Genymobile/scrcpy) | 155,733 | **32 M** | C client + Java server over adb | Apache-2.0 | 2017-11 | USB adb; wireless adb (manual, `--tcpip`) | ✗ (manual choice) | ✗ | S | 9 | The de-facto OSS Android mirroring; H.264/265/AV1, 35–70 ms class latency; zero install on device; transports = ADB only. |
| 2 | [RustDesk](https://github.com/rustdesk/rustdesk) | 131,486 | **86 M** | **Rust core + Flutter UI**, 7 platforms | AGPL-3.0 | ≈2021 | IP only: LAN direct, hole-punch P2P, relay | ✗ (IP path only) | ✗ | S | 9 | **Proves the Rust+FFI+Flutter glue pattern is not novel by itself** — but desktop remote desktop, IP-only, no USB/BT. |
| 3 | [Sunshine](https://github.com/LizardByte/Sunshine) | 43,923 | 8.5 M | C++ host (Moonlight/GameStream protocol) | GPL-3.0 | ≈2022 | IP: UDP-centric ENCODER protocol, QoS/FEC | ✗ | ✗ | A | 9 | Most QoS-optimized OSS real-time display streaming; game-oriented, PC→device. |
| 4 | [Deskflow](https://github.com/Deskflow/Deskflow) | 31,720 | — | C++ (Synergy core + community) | GPL-2.0 | 2014-10 | IP only | ✗ | ✗ | A | 8 | Software KVM (keyboard/mouse only, **no video**); lineage Synergy→Barrier→Input Leap (8,309★, archived 2025-12)→Deskflow. |
| 5 | [Deskreen](https://github.com/pavlobu/deskreen) | 21,816 | 297 k | Electron + WebRTC | AGPL-3.0 | 2020 | IP only (WebRTC, LAN) | ✗ | ✗ | A | 7 | “Any device with a browser = second screen”; transport = WebRTC over IP only. |
| 6 | [Moonlight-qt](https://github.com/moonlight-stream/moonlight-qt) | 19,787 | 13 M | C++/Qt client | GPL-2.0 | ≈2018 | IP (UDP ENCODER, Netprobe) | ✗ | ✗ | A | 9 | Client half of Sunshine/GameStream; reference OSS real-time video client stack. |
| 7 | [Input Leap](https://github.com/input-leap/input-leap) | 8,309 | — | C++ | GPL-2.0 | 2019 (archived 2025-12) | IP only | ✗ | ✗ | B | 7 | Superseded by Deskflow (row 4). |
| 8 | [DeskPad](https://github.com/jordanbaird/DeskPad) | 7,958 | — | Swift | MIT | ≈2024 | none (virtual desktops, not transport) | n/a | n/a | B | 6 | Sidecar-alternative UX on one machine; **source material TwinDesk reused**; no network at all. |
| 9 | [Looking Glass](https://github.com/gnif/LookingGlass) | 5,773 | 9.8 k | C, KVMFR virtio + DMA-BUF | GPL-2.0 | 2017 | VM shared memory / virtio, LAN TCP | n/a | ✗ | B | 9 | Sub-millisecond frame transport design (shared-memory framing protocol) — excellent *framing* prior art for our USB/BT streams. |
| 10 | [TwinDesk](https://github.com/InukaAsith/TwinDesk) | 4,722 | **109 k** (in ~6 weeks) | Node/JS core + C#/native helpers + Kotlin/Swift apps + web client | GPL-3.0 | **2026-10-14** | Wi-Fi, USB cable, **Bluetooth (session+input only)**, Wi-Fi Direct on demand, Tailscale, AirPlay lane | **✅ YES — best in class** (cable-in→USB, Wi-Fi-dies→BT, heavy payload→Wi-Fi Direct bring-up) | **✗ screens never on BT** | B (A by trajectory) | 9 | **The closest system in existence** — Section 5.1; README read in full during this survey. |
| 11 | [KDE Connect](https://github.com/KDE/kdeconnect-kde) (+[android](https://github.com/KDE/kdeconnect-android) 1,529★) | 4,196 | — | C++/Qt + Kotlin | GPL-2.0 | 2015-09 | TCP-over-IP LAN sessions; BT/BLE presence & pairing (recent) | ✗ (IP payload) | ✗ (no video at all) | B | 7 | Device-companion framework: notifications/clipboard/inputs; **no video stream**. |
| 12 | [display-switch](https://github.com/fastlzxy/display-switch) | 3,497 | — | C# daemon | GPL-3.0 | ≈2018 | none (drives hardware KVM/DDC) | hardware-switched | n/a | B | 6 | Auto-switches *physical* HDMI/USB KVM — same UX goal, different plane. |
| 13 | [UxPlay](https://github.com/fdmanana/UxPlay) | 3,397 | 14 k | C | GPL-3.0 | ≈2020 | Wi-Fi LAN (AirPlay: RTSP+RTP over IP; mDNS) | ✗ | ✗ | B | 7 | Open AirPlay receiver (H.264/H.265/AV1); **basis of TwinDesk's and ZenLink's Apple lanes**. |
| 14 | [Sefirah](https://github.com/shrimqy/Sefirah) | 3,133 | — | C# / WinUI | MIT | ≈2024 | IP (WebSocket), adb/wireless-debug | ✗ | ✗ | B | 6 | OSS Phone Link alternative; companionship, **no mirroring stream**. |
| 15 | [ws-scrcpy](https://github.com/NetrisTV/ws-scrcpy) | 2,627 | — | TypeScript | MIT | 2019 (pushed 2026-11) | Browser ← WS server ← adb (USB/wireless) | ✗ | ✗ | B | 7 | scrcpy frames re-tunneled to browsers; early “transport-agnostic mirroring” precedent. |
| 16 | [evdi](https://github.com/DisplayLink/evdi) | 978 | 0 | C kernel driver | MIT | ≈2016 | USB (vendor protocol) → virtual display | n/a | ✗ (USB, not BT) | C | 7 | **The canonical “USB cable as display transport” plumbing** — vendor chips + closed userspace; our USB-gadget route is the open, chip-free version. |
| 17 | [ZenLink](https://github.com/zenvyzenshiro/zenlink) | 542 | 12 k | **Rust, single binary** (+ tokio, windows-rs) | GPL-3.0 | **2026-11-03** | iPhone: USB (libusb capture, CoreDevice HID), AirPlay Wi-Fi, **Hybrid** (AirPlay video + USB control); Android: USB or wireless adb (scrcpy-server) | ✗ **user picks; “switch any time in Settings”** | ✗ (“Bluetooth … not available on any version”) | C | 8 | Closest *Rust* single-codebase mirroring engine; Windows host; experimental but sophisticated driver manager with rollback. |
| 18 | [mickey](https://github.com/EduardoMG12/mickey) | 263 | — | Rust | — | ≈2024 | IP (KVM input sharing) | ✗ | ✗ | C | 5 | OSS software KVM in Rust (Deskflow idea, Rust rewrite); no video. |
| 19 | [Rubylight](https://github.com/RamazanKara/Rubylight) | 259 | — | **Rust** game-stream host | GPL-3.0 | ≈2023 | IP (Moonlight protocol) | ✗ | ✗ | C | 6 | Proof Rust is becoming a common substrate for real-time display streaming. |
| 20 | [BetterCast](https://github.com/StephenLovino/BetterCast) | 247 | — | Swift | — | 2026 | IP (own display protocol, LAN) | ✗ | ✗ | C | 5 | New Sidecar/Duet/spacedesk-alike, “no subscription”; single-transport. |
| 21 | [Hermes](https://github.com/MrOz59/Hermes) | 218 | — | C++ | — | ≈2024 | IP (Moonlight-compatible host) | ✗ | ✗ | C | 5 | Another OSS GameStream host; ecosystem breadth evidence. |
| 22 | [UScreen](https://github.com/majmichu1/UScreen) | 134 | 6 k | **Rust** (Linux) + Android | MIT | **2026-06-12** | **USB second monitor for Android tablets** (real virtual-display plumbing) | n/a | ✗ | C | 6 | **Key prior art: video *into* a tablet over USB, in Rust** — SuperDisplay as OSS. PC→tablet direction only; no Wi-Fi, no BT, no fallback. |
| 23 | [hylarana](https://github.com/mycrl/hylarana) | 82 | — | Rust | MIT | 2024-02 | IP (Chromecast/Miracast send) | ✗ | ✗ | C | 6 | Rust sender for Chromecast/Miracast. |
| 24 | [input-leaf](https://github.com/anasvhora284/input-leaf) | 78 | — | Kotlin | — | 2025 | IP/USB companion (phone as input+display receiver) | ✗ | ✗ | C | 4 | Phone-as-receiver companion, no fallback. |
| 25 | [iPhone-use](https://github.com/YueChen-C/iPhone-use) | 33 | 1.3 k | Swift | — | **2026-10** | **USB video out of iPhone** (QuickTime-style) + **Bluetooth HID** *into* iPhone | ✗ | ✗ (BT is input-only, USB is video-only) | D | 7 | scrcpy-for-iPhone; shows the *split-plane* pattern (USB carries video, BT carries input) but no Wi-Fi plane, no fallback. |
| 26 | [ZeroLink](https://github.com/erTesla/ZeroLink-public) | 25 | — | **Kotlin Compose Multiplatform** (one codebase: PC + Android) | MIT | 2025-10-13 | Wi-Fi TCP (`:5000` JPEG 4-byte-length frames, `:5001` control, mDNS `_localscreenshare._tcp`, PIN); USB only as `adb reverse` tunnel | ✗ | ✗ | D | 7 | Closest *single-codebase* philosophy; unencoded JPEG frames (not H.264); no BT; no fallback. |
| 27 | [swaybeam](https://github.com/forkline/swaybeam) | 11 | — | Rust | MIT | 2026-04 | Wi-Fi Direct (Miracast source, P2P GO) | ✗ | ✗ | D | 5 | Miracast *source* for wlroots; shows WFD stack is now Rust-accessible. |
| 28 | [DeXDesk](https://github.com/adirh3/DeXDesk) | 8 | — | Rust | — | 2026 | Wi-Fi (wireless Samsung DeX receiver) | ✗ | ✗ | D | 4 | Wireless DeX receiver in Rust. |
| 29 | [openplay](https://github.com/Developer1010x/openplay) | 5 | — | Rust | GPL-3 (self-stated) | 2026-03 | AirPlay + Miracast/WFD + **Wi-Fi Direct** + WebRTC receiver | ✗ (protocol-per-protocol) | ✗ | D | 5 | Most protocol-saturated Rust cast receiver — still no *video over BT*, no fallback engine. |
| 30 | [tandem](https://github.com/aidenwboudr/tandem) | 3 | — | Python (GTK) | GPL-3.0 | 2026-10-05 | BT pairing-first PC⇄Linux/Android companionship | ✗ | ✗ (no video) | D | 4 | KDE-Connect-style with Bluetooth pairing front-and-center. |
| 31 | [Ayna / yansit-tv](https://github.com/krmndigital-lab/yansit-tv) | 1 | — | Rust | GPL-3.0 | 2026-11-03 | AirPlay + Miracast + DLNA receiver (Android TV) | ✗ | ✗ | D | 4 | Rust cast receiver wave continues *this month*. |
| 32 | [ScrcpyBluetooth](https://github.com/ai2master/ScrcpyBluetooth) | 1 | — | Kotlin | — | 2026-03-19 | **Bluetooth / USB** Android→Android screen mirroring + remote control, E2EE | ✗ (static) | **◐ yes-ish** | D | 3 | The only project that *says* “screen mirroring via Bluetooth” — 1★ toy, Android→Android only, no PC, no fallback, unverified quality. Nearest *concept* proof-of-existence. |

MLRC ACCS itself (this repo, tip `4828ac3`): P1 ✅ implemented (connected UDP + MAC1/MAA1 + fixed presence 38421 + pre-flight reachability probe); P2 🚧 roadmap (USB gadget NCM/RNDIS); P3 🚧 roadmap (SPP/RFCOMM, `CommType::Bluetooth`); P4 🚧 design-stage; P5 ✅ (single Rust cdylib reused, Dart FFI).

### Commercial / closed-source landscape (popularity by market presence, not verifiable ★)

| Product | Transports for video | Auto fallback? | BT video? | Note |
|---|---|---|---|---|
| **Microsoft Phone Link** (preinstalled on Windows) | IP/Wi-Fi; Miracast-based “phone screen” only on select phones (Surface Duo, ROG Phone, some Samsung) | partial (USB debugging companion features) | ✗ | Massive installed base; phone-screen feature is narrow; no BT video. |
| **Miracast / Wi-Fi Display** (Wi-Fi Alliance spec; Windows+Android built-in) | Wi-Fi Direct or “Miracast over Infrastructure” | mode chosen by user/platform | ✗ | RTSP control (:7236) + RTP/MPEG-TS media; WFD IEs; **the incumbent single-transport model**. |
| **Intel Unison** | IP (Wi-Fi/LTE), cross-platform (iOS/Android⇄Windows) | ✗ | ✗ | Notifications/files/calls/mirroring on supported phones. |
| **Apple Sidecar / Universal Control / Continuity+AirDrop** | Sidecar: Wi-Fi (auto, same iCloud) **or** USB, user setup; AirDrop/Handoff: **BT presence + Wi-Fi payload** | ✗ (Sidecar picks one link) | ✗ payload | The industrialized “Bluetooth finds, Wi-Fi carries” pattern — TwinDesk’s model, never BT payload. |
| **Luna Display (Astropad)** | “Connecting over **Wi-Fi or cable**” (USB-C dongle + apps) | ✗ (session on one link) | ✗ | Closed; hardware-dongle second-screen; the “luna” of the original question. |
| **Duet Display** | wired (USB) + “Duet Air” Wi-Fi | ✗ user picks | ✗ | Subscription lineage; invented the USB-second-screen category (ex-Apple engineers). |
| **spacedesk** (+ spacedeskUSB legacy) | LAN Wi-Fi/Ethernet; USB variant in legacy product | ✗ | ✗ | Free Windows→any client. |
| **SuperDisplay** | **USB** (+ Wi-Fi premium tier) | ✗ | ✗ | Best-known OSS-alternative target for USB video *into* Android (cf. UScreen row 22). |
| **AirDroid Cast / ApowerMirror / Vysor** | USB debugging and/or Wi-Fi, user picks | ✗ (manual) | ✗ | Freemium mobile mirroring trio; Vysor built on adb like scrcpy. |
| **TeamViewer / AnyDesk / RDP** | IP only | ✗ (IP path failover only) | ✗ | Classic remote desktop; no personal-area transports. |
| **Google Nearby Connections (SDK)** | **BLE + BT Classic + Wi-Fi LANE**, strategies (`P2P_CLUSTER/STAR/POINT_TO_POINT`) | SDK picks per endpoint constraints; **no video API** | payload possible incl. bytes but designed for data, not display | [API strategies doc](https://developers.google.com/nearby/connections/strategies): “~100 m radio range”, bandwidth/latency/battery tradeoffs — **the best industrial precedent for our link-abstraction API design**. ⚠ A journal write-up (Follmer et al., IEEE IoT-J 2018, “Nearby Connections: A Scalable Peer-to-Peer Communication Framework”) exists but its DOI was not confirmed today — cite from IEEE Xplore. |

---

## 4. Popularity ranking (measured today)

1. RustDesk — 131k★, 86 M GH dl (S)
2. scrcpy — 156k★, 32 M dl (S) *(+ uncounted brew/apt/Android-Studio pulls)*
3. moonlight-qt — 19.8k★, 13 M dl (A)
4. Sunshine — 43.9k★, 8.5 M dl (A)
5. Deskflow — 31.7k★ (A, actively pushed 2026-11-18)
6. Deskreen — 21.8k★, 297 k dl (A)
7. Input Leap — 8.3k★ archived / superseded by Deskflow
8. DeskPad — 8.0k★ (B, no networking at all)
9. LookingGlass — 5.8k★, 9.8 k dl (B)
10. TwinDesk — 4.7k★, **109 k dl in ~6 weeks** (B → A trajectory; fastest adoption in this table)
11. KDE Connect — 4.2k★ + 1.5k★ (B)
12. display-switch — 3.5k★ (B)
13. UxPlay — 3.4k★, 14 k dl (B)
14. Sefirah — 3.1k★ (B)
15. ws-scrcpy — 2.6k★ (B)
16. evdi — 978★ (C)
17. ZenLink — 542★, 12 k dl (C, 23 days old)
… then mickey/Rubylight/BetterCast/Hermes/UScreen/hylarana (~100–260★), iPhone-use/ZeroLink (~25–33★), micro-receivers (≤11★).

Commercial reach (uncountable via GitHub): **Miracast ≈ default on nearly all Windows PCs and Android phones; Phone Link preinstalled on Windows 11** — both dwarf every OSS row by installed base, but both are single-transport-per-session.

---

## 5. Deep dives — the systems that matter for our claim

### 5.1 TwinDesk — the benchmark to beat *(read README in full, 2026-10-14, v3.2.1, GPL-3.0, InukaAsith/TwinDesk)*
- Transport prose (verbatim): “You never have to choose. TwinDesk uses the same network when there is one, **moves a phone onto the USB cable when you plug it in**, and **falls back to Bluetooth when the Wi-Fi goes** … When a screen or a big file needs more than Bluetooth, TwinDesk **brings up a direct Wi-Fi link** for as long as it’s needed.”
- Its own capability matrix: session/clipboard-text/notifications/input/calls work over Wi-Fi, USB **and Bluetooth**; “**Screens, apps, cameras, files, photos, clipboard pictures** … ✅ ✅ **moves to Wi-Fi Direct** ✅”. → **Bluetooth is input+control plane; heavy payloads escalate to Wi-Fi Direct.** Video never rides BT.
- Architecture: TLS-over-TCP *session* + UDP *lane* (tdv2 protocol; Node fallback lane; C# input helper on Windows; BlueZ+NetworkManager for BT/Wi-Fi Direct on Linux; mDNS discovery; DSCP qWAVE marking; ReZume resumable parallel-range file transfer with hashes verified mid-stream; AirPlay receiver lane derived from UxPlay; parts of the desktop UI from DeskPad (MIT); USB→BT failover when Wi-Fi dies; pairing codes/QR; update-check only network call).
- Stack: Node/JS core + native OS helpers + Kotlin/Swift mobile apps + a web client — **multi-runtime, not P5**.
- Adoption: 4.7k★ and ~109k GitHub-release downloads within ~6 weeks — fastest-growing close analog measured.
- **Timeline honesty:** TwinDesk repo was created **2026-10-14**, five days *before* MLRC ACCS’s first commit (2026-10-19). We had not seen it at start. Treat as contemporaneous independent convergence; cite it as the closest prior art. Its README explicitly compares itself against Phone Link, KDE Connect, Apple Continuity, scrcpy, LocalSend — no mention of USB/BT *video*, and it does not claim it.

### 5.2 ZenLink — Rust single-binary mirroring engine *(2026-11-03, GPL-3.0, 542★, 12 k dl)*
- Windows host in Rust; iPhone: AirPlay receiver (UxPlay lineage), QuickTime-style capture over libusb0/libusb-win32+libwdi, CoreDevice HID control, **“Hybrid Control” (AirPlay video over Wi-Fi + USB control simultaneously)** — the most interesting control/data plane split found; Android: scrcpy-server over adb (USB or wireless-debug QR pairing).
- Explicit manual transport model: “Five ways to connect. **Pick one** … switch any time in Settings → Connection & Drivers”; “switch to Wi-Fi so you can unplug the cable”. **No Bluetooth (stated), no automatic failover.**
- Stack discipline (P5-adjacent): single Rust codebase, tokio, windows-rs, RustCrypto/dalek, Slint UI — but **host-side only Windows**; device side is borrowed (UxPlay, scrcpy-server).
- README read in full during this survey (raw main branch, 2026-11-26).

### 5.3 ZeroLink — the one-codebase kindred spirit *(2025-10-13, MIT, 25★)*
- Kotlin **Compose Multiplatform**: one codebase runs as desktop (Windows/macOS/Linux) and Android receivers/sharers; TCP `:5000` carries 4-byte-length-prefixed JPEG frames, `:5001` control, mDNS `_localscreenshare._tcp`, 6-digit PIN auth; USB path = `adb reverse` port-forward (still TCP-JPEG, just tunneled); no Play account needed.
- No H.264 (CPU JPEG encoding), no BT, no fallback. Architecturally the simplest honest baseline; its single-codebase + zero-install receiver stance is philosophically closest to MLRC ACCS, one plane away.

### 5.4 scrcpy — the transport-free standard
- adb-only transports (USB today; wireless adb since v3.1 auto-connect); H.264/265/AV1 from the device encoder; device-side server pushed via adb (no install); tunnels: adb socket or raw TCP. Fallback = none. Bluetooth = nothing. Its dominance is why **every second-wave project (ZenLink Android path, ws-scrcpy, Sefirah, ZeroLink USB bridge, Phone Link internals) rides adb**.

### 5.5 RustDesk — the P5 precedent that forces our novelty claim elsewhere
- Rust core (codecs, hole punching, relay protocol, clipboard/input) compiled for Windows/macOS/Linux/Android/iOS/Firefox/Web; Flutter UI. IP-only transports. **Takeaway for the paper: “Rust + FFI + Flutter across all platforms” is a solved, well-known engineering pattern (86 M downloads prove it). Our contribution must be the transport plane, not the toolchain.**

### 5.6 Sunshine/Moonlight (+ Rubylight, Hermes) — QoS-graded IP streaming pedigree
- ENCODER protocol: UDP media with FEC, control over TCP, Netprobe path probing, hardware encode/decode, 120 fps-class. Zero personal-area transports. Their QoS design vocabulary (FEC blocks, jitter budgets, frame pacing) is what our BT/USB planes must be compared against.

### 5.7 Apple stack (Sidecar, Universal Control, AirDrop/Continuity) and Luna Display
- Sidecar: user-picked Wi-Fi (within Continuity pairing) or USB cable; Apple never puts display payload on Bluetooth — BT/BLE is *presence* only across Continuity/AirDrop/Handoff (AirDrop: BT discovery → AWDL/Wi-Fi payload).
- **Luna Display**: closed-source USB-C dongle + apps; “turns any Mac or iPad into a wireless second display”, “connecting over Wi-Fi or cable”; also Windows support. No BT payload, no automatic multi-link fallback documented.
- Duet Display (wired/wireless, subscription), spacedesk (LAN + legacy spacedeskUSB), **SuperDisplay** (USB-first, Wi-Fi premium): single-transport-per-session second-screen products. SuperDisplay/UScreen pair: **USB-video-into-tablet is already a productized category (closed) with a young OSS Rust clone**.

### 5.8 Miracast / Wi-Fi Display — the incumbent standard
- WFA spec: RTSP session (:7236) + RTP/MPEG-TS media over Wi-Fi Direct P2P (WFD IEs in P2P negotiation), with Microsoft’s “Miracast over Infrastructure” variant running the session over Wi-Fi LAN/Ethernet. **Discovery→negotiation→single data path; no Bluetooth, no USB, no runtime link switch** (infrastructure mode is a configuration, not a fallback engine).

### 5.9 Google Nearby Connections
- SDK abstracts **BLE + Classic BT + Wi-Fi LANE** behind endpoint/strategy APIs (P2P_CLUSTER / P2P_STAR / P2P_POINT_TO_POINT), with documented bandwidth/latency/range (~100 m) tradeoffs, payloads of any size — **but no display/stream abstraction and no video latency discipline**. Best API-design precedent for our `CommType` + presence-port layering; ⚠ its 2018 IEEE IoT-J paper was not DOI-verified today.

### 5.10 KVM/companion cluster (Deskflow/Input Leap/KDE Connect/Sefirah/mickey/tandem/display-switch)
- All establish **multi-OS session continuity without video** (Deskflow: IP input; KDE Connect: IP payload + BT presence; display-switch: drives a *hardware* KVM automatically — the closest UX metaphor for “automatic switch”, on a different plane). Useful related-work boundary: “KVM tools switch inputs across computers on one IP network; we switch one device’s display across physical layers.”

### 5.11 The Rust receiver wave of 2024–2026 (hylarana, swaybeam, DeXDesk, openplay, Ayna, Rubylight, mickey, UScreen, LookingGlass-adjacent)
- 15+ small Rust projects implementing AirPlay/Miracast/Chromecast/GameStream/USB-monitor in the last ~3 years — evidence that **Rust has become the default glue for display-streaming protocol work**, which both supports our stack choice and further erodes “Rust as novelty”.

---

## 6. Academic prior art

### 6.1 Remote display / thin-client systems (systems lineage)
- ✅ **Mosh: An Interactive Remote Shell for Mobile Clients**, USENIX ATC 2012 — 54 citations (S2-verified today; USENIX has no DOI; site: [mosh.org](https://mosh.org)). State-based sync + crypto-over-UDP; **the canonical “survives network change/roaming” interactive protocol** — it *roams* across IPs but never crosses physical personal-area transports.
- ⚠ **TILE Proxy: Virtual Shared Memory for Remote Clients**, ACM SIGCOMM 2011 — speculative prefetch of display state to hide latency; foundation for look-ahead thin-client.
- ⚠ **Pica: Hand-Held-Based Desktop Computing**, ACM EuroSys 2009 (Microsoft Research) — thin-client desktop with a phone-class client over LAN.
- ⚠ **Conductor: Operating System Architecture with Network Offloading**, ACM MobiCom 2015 — moves a desktop’s rendering/network to a helper machine, thin client at phone; the “split rendering” sibling of our design space.
- ✅ **Banerjee & Agu, “Remote execution for 3D graphics on mobile devices”**, IEEE WNCM 2005, doi:10.1109/WIRLES.2005.1549575 (6 cites) — early remote-render/display transport analysis.
- ✅ **Ryu, Ko, Shin, Kang — ACM HotMobile 2013 Poster** record, doi:10.1145/2542095.2542112 — look-ahead speculative execution for networked interactive graphics (the *deLorean* lineage, HotMobile’13 poster).

### 6.2 Multipath transport, handover, link-diversity
- ✅ Paasch/Dressler/… “Multipath TCP”, **ACM Queue 12(6) 2014**, doi:10.1145/2578508.2591369 (32 cites); same title **CACM 57(4) 2014**, doi:10.1145/2578901 (98 cites). ⚠ Raiciu et al., “Multipath TCP”, ACM SIGCOMM CCR 42(3), 2012 (the MPTCP vision paper; DOI not captured today) and **RFC 8684**.
- ✅ Han et al., “An anatomy of mobile web performance over multipath TCP”, ACM CoNEXT 2015, doi:10.1145/2716281.2836090 (43 cites).
- ✅ **Höchst et al., “Learning Wi-Fi Connection Loss Predictions for Seamless Vertical Handovers Using Multipath TCP”, IEEE LCN 2019, doi:10.1109/LCN44214.2019.8990753 (5 cites), [arXiv:1907.10493](https://arxiv.org/abs/1907.10493)** — *the conceptual closest paper*: predicts Wi-Fi loss and pre-establishes MPTCP paths so interactive sessions don’t stutter during handover. Still IP-layer (Wi-Fi↔LTE), no Bluetooth, no USB, no screen content, no native-codebase claim. (Earlier DOI-collision worry in this session resolved: both records are the same Höchst paper.)
- ✅ **W. Song, “Performance Analysis of Probabilistic Multipath Transmission of Video Streaming Traffic over Multi-Radio Wireless Devices”, IEEE TWC 11(3) 2012, doi:10.1109/TWC.2012.021512.111397 (70 cites)** — interactive video split across heterogeneous radios (Wi-Fi+3G); the “one media stream, parallel physical links” ancestor — but *simultaneous* bonding, not *fallback*, and never BT/USB.
- ✅ Alhazmi & Akkari, “An Overview of Context-Aware Vertical Handover Schemes in Heterogeneous Networks”, IJCSES 2011, doi:10.5121/IJCSES.2011.2403 (4 cites) — handover-decision-policy survey frame.
- ✅ Transport-layer multipath survey: [arXiv:1601.06043](https://arxiv.org/abs/1601.06043) (2016); dual-LTE MPTCP measurement [arXiv:1909.02601](https://arxiv.org/abs/1909.02601); MPTCP-over-single-RAT paradox [arXiv:2502.01290](https://arxiv.org/abs/2502.01290); ALCS satellite-latency scheduler [arXiv:2503.07973](https://arxiv.org/abs/2503.07973) (all titles verified today).
- ✅ Multipath QUIC: “The Packet Number Space Debate in MPQUIC” [arXiv:2112.01068](https://arxiv.org/abs/2112.01068); “Performance Evaluation of a New Scheduling Model Using Congestion Window Reservation” [arXiv:2305.03684](https://arxiv.org/abs/2305.03684); IETF `draft-ietf-quic-multipath`; **QUIC RFC 9000 §9 “Address and Connection Migration”** — connection identity survives interface change: the protocol primitive our presence-port design leans on.
- ⚠ ELIPSE (NoMachine, ACM Multimedia 2012) — elastic real-time display/video session across flaky links (protocol-level, IP-only).
- ✅ ABR video streaming over wireless survey: [arXiv:2008.00087](https://arxiv.org/abs/2008.00087) (2020) — rate-adaptation frame for per-link bitrate ladders.

### 6.3 Video over Bluetooth — the forgotten cluster (all ✅ verified today)
- Razavi, Fleury, Ghanbari, “**Unequal Protection of Video Streaming** through Adaptive Modulation with a Trizone Buffer over **Bluetooth Enhanced Data Rate**”, EURASIP J. Wireless Commun. Netw. 2007/2008, doi:10.1155/2008/658794 (2 cites).
- Razavi, Fleury, Ghanbari, “**Fuzzy logic control of power-aware video streaming over a Bluetooth interconnect**”, Packet Video 2007, doi:10.1109/PACKET.2007.4397044.
- Hasad, Bakri, Paronda, Marini, “**Quality Optimization of Data Rate Video Streaming Over Bluetooth Network**”, Advances in Engineering Research 2021, doi:10.2991/AER.k.210810.087.
→ Bluetooth-video streaming was studied at the **link-adaptation** level (EDR, buffers, FEC) 2007–2021 — but nobody connected it to *interactive screen content*, *USB gadget datapaths*, or *runtime transport fallback*. This cluster is our defense against “Bluetooth video is impossible/never studied”.

### 6.4 Rust systems / FFI correctness (motivation citations, all ✅)
- Qin et al., “Understanding memory and thread safety practices and issues in real-world Rust programs”, **PLDI 2020**, doi:10.1145/3385412.3386036 (120 cites).
- Xu et al., “Memory-Safety Challenge Considered Solved? An In-Depth Study with All Rust CVEs”, **ACM TOSEM 2021**, doi:10.1145/3466642 (73 cites).
- Jung et al., “Safe systems programming in Rust”, **CACM 2021**, doi:10.1145/3418295 (65 cites).
- “Understanding Atomics and Memory Ordering Issues in Real-World Rust Software”, IEEE ISSRE 2024, doi:10.1109/ISSRE62328.2024.00061.
- Li & Sato, “SBD: Securing safe Rust automatically from unsafe Rust”, Science of Computer Programming 2025, doi:10.1016/j.scico.2025.103281 (5 cites).
- “Securing Mixed Rust with Hardware Capabilities” [arXiv:2507.03344](https://arxiv.org/abs/2507.03344) (2025; CCS’25 venue record ⚠ DOI 10.1145/3719027.3744861 banked but title-link not re-verified today).
- SACTOR: “An Adaptive Latency Compensation Scheduler…” — no: SACTOR = “Enforcing Software-based Memory Safety… Mixed Rust” [arXiv:2503.12511](https://arxiv.org/abs/2503.12511); “Towards Scalable and Verifiable Automated Translation from C to Safe Rust”, SPLASH’26 Companion, doi:10.1145/3837729.3842149; “Surveying the Rust Verification Landscape” [arXiv:2410.01981](https://arxiv.org/abs/2410.01981); “Bringing Rust to Safety-Critical Systems in Space” [arXiv:2405.18135](https://arxiv.org/abs/2405.18135); MC/DC-for-Rust [arXiv:2409.08708](https://arxiv.org/abs/2409.08708).
→ Use these to *motivate* the safety of the single-codebase claim (parser/FFI code that on Wi-Fi+USB+BT triples the attack surface), not to claim novelty of Rust itself.

### 6.5 Where the literature is silent (zero-relevant-result queries, run today)
Treated as gap evidence, not absence-of-proof-of-absence:
- arXiv full-text: `"USB tethering"`; `bluetooth AND "video streaming" AND cat:cs.NI`; `miracast OR "Wi-Fi Display"`; `"Nearby Connections"`; `"USB gadget" AND networking`; `"single codebase" AND cross-platform AND rust`; `MPTCP AND interactive`; exact screen-mirroring+BT+handover combos.
- DuckDuckGo: `site:researchgate.net "screen sharing" bluetooth wi-fi automatic switching handover` → 0; `site:ieeexplore.ieee.org "screen mirroring" bluetooth OR usb OR handover` → 0.
- Crossref/Semantic Scholar title matches: `TILE proxy`, `Pica`, `Conductor offloading`, `ELIPSE`, `SpeediMe`, `MultiNet` — **no indexed record retrieved today** (they remain cited as ⚠ secondary-source records).
- GitHub: `"screen mirroring" bluetooth` yields ~40 candidates, ~20 inspected; the only mirroring-over-BT claim found is the 1★ `ScrcpyBluetooth` toy (row 32) and iPhone-use (BT=input only).
→ No indexed research paper proposes screen mirroring with **automatic BT↔USB↔Wi-Fi transport switching**. The intersection is unclaimed in both product and paper space (with the TwinDesk/ZenLink caveats above bounding the engineering near-misses).

---

## 7. Gap matrix (the answer to “is there an exact match?”)

P1 Wi-Fi video · P2 USB video (generic, no vendor chip) · P3 **Bluetooth video payload** · P4 runtime auto-fallback between available planes · P5 one native core on both endpoints.

| System | P1 | P2 USB video | P3 **BT video** | P4 auto-fallback | P5 one native core | Exact? |
|---|:-:|:-:|:-:|:-:|:-:|:-:|
| **MLRC ACCS (target)** | ✅ shipped | 🚧 roadmap | 🚧 roadmap | 🚧 design | ✅ | — |
| TwinDesk | ✅ | ✅ (mirroring incl.) | **✗** (screens “move to Wi-Fi Direct”) | ✅ best in class | ✗ JS+native helpers | ✗ (P3) |
| ZenLink | ✅ | ✅ | ✗ (explicitly none) | ✗ user picks | ◐ host-only Windows | ✗ (P3,P4) |
| ZeroLink | ✅ | ◐ (adb-reverse TCP) | ✗ | ✗ | ✅ Kotlin MP (not native) | ✗ (P3,P4) |
| scrcpy | ✅ | ✅ (adb) | ✗ | ✗ | ✗ C+Java/adb | ✗ (P3,P4) |
| RustDesk | ✅ | ✗ | ✗ | ✗ | ✅ (IP-only) | ✗ (P2,P3,P4) |
| Sunshine/Moonlight | ✅ | ✗ | ✗ | ✗ | ✗ C++ | ✗ (P2,P3) |
| Phone Link / Unison | ✅ (select phones) | ◐ companion only | ✗ | ✗ | ✗ closed | ✗ |
| Miracast / WFD | ✅ (P2P/infra) | ✗ | ✗ | ✗ | ✗ closed | ✗ |
| Sidecar / Duet / Luna / spacedesk / SuperDisplay | ✅ | ✅ (some) | ✗ | ✗ (user picks) | ✗ closed | ✗ |
| Apple Continuity / AirDrop / Nearby SDK | n/a (no display payload; Nearby no video API) | ✗ | ✗ payload | SDK-level strategy only | ✗ | ✗ |
| DisplayLink / evdi | ✗ | ✅ (vendor-chip) | ✗ | ✗ | ✗ kernel+closed UM | ✗ (chip required) |
| UScreen / SuperDisplay | ✗ | ✅ PC→tablet only | ✗ | ✗ | ◐ host-side Rust | ✗ (P1,P3,P4) |
| ScrcpyBluetooth (toy) | ✗ | ◐ | ◐ claimed | ✗ | ✗ Kotlin | ✗ (quality/PC/P4; concept only) |
| iPhone-use | ✗ | ✅ iPhone→PC USB | ✗ (BT=input) | ✗ | ✗ | ✗ |
| Academic literature | ✅ studied | chip-level studied | link-QoS studied 2007–2021 | IP-layer studied (MPTCP/QUIC handover) | never claimed | **✗ no combination studied** |

**Verdict: no exact match exists, in tools or in papers, as of 2026-11-26.** TwinDesk must be cited and differentiated (P3 + P5); ZenLink must be cited (Rust prior art for P5-adjacent engineering); MPTCP/handover + Song TWC'12 + BT-video cluster + Höchst LCN'19 must be cited as the literature envelope; ScrcpyBluetooth + iPhone-use are worth one paragraph each as existence-proofs that BT-plane mirroring experiments exist at toy scale.

---

## 8. IEEE-publishability assessment and framing

**Honest baseline:** “Rust is the snappy glue + one codebase for all platforms” **is not a publishable contribution by itself** — RustDesk (131k★/86 M dl, Rust+Flutter), ZenLink (Rust), Rubylight, and the 2024–2026 Rust receiver wave already normalize it. If the paper leads with tooling, reviewers (with GitHub access) will point at RustDesk in one line.

**What is actually new and defensible (the transport plane):**
1. **C1 — Bluetooth as a first-class interactive video fallback for screen content.** Nobody ships it (TwinDesk explicitly refuses; Nearby has no display payload). We would publish the first *measured* end-to-end H.264/JPEG-adaptive mirroring over RFCOMM SPP (~1.2–2.1 Mbps effective on ACL) with input coexisting, including the bitrate ladder that makes ~5–15 fps interactive mirror usable — the paper claim TwinDesk’s README leaves open (“when a screen needs more than Bluetooth…” assumes screens can’t ride BT at all).
2. **C2 — USB gadget NCM/RNDIS as a zero-configuration, zero-shared-network video plane**, giving every plane an IP bearer, so session identity survives link change (presence port 38421 + QUIC-RFC9000-§9-style path migration semantics). Contrast: Miracast infra mode is a config; TwinDesk’s USB lane is a session transport, not a uniform IP plane.
3. **C3 — a fallback policy with measured handover behavior**: probe-driven selection (our pre-flight reachability probe exists), hysteresis rules, per-plane bitrate ladders, **measured blackout in ms and dropped frames at each switch** (Wi-Fi→USB plug, USB→BT unplug, Wi-Fi-loss→BT). No tool publishes handover blackout measurements; MPTCP papers measure IP-layer, not personal-area physical planes. Song TWC'12 is bonding-not-fallback; Höchst LCN'19 is Wi-Fi/LTE-not-BT/USB.
4. **C4 (framing, not claim)** — Rust FFI single native core recompiled for both endpoints (`.so`/`.dll`/`.so`), with fuzzed MAC1 parsers (cargo-fuzz) and zero data-race-class findings, *justified* by the Rust-CVE/PLDI/TOSEM motivation citations — an evaluation subsection, not a contribution.

**Required experiment suite (minimum for a credible 6–8 page systems paper):** BT SPP throughput × ACL coexistence matrix (Android↔Windows, BlueZ + Windows PAN/SPP); USB NCM gadget throughput + latency; per-plane latency ladder (LED-timestamp E2E); adaptive bitrate ladder convergence per plane; **switch-time table (blackout ms, frames lost, session continuity)** vs baselines scrcpy (USB), TwinDesk (its fallbacks, if measureable), Moonlight/Sunshine (IP QoS reference); CPU/battery budget; fuzzing results for the parser at the transport intersection; optionally security note (MAC1 has no auth yet vs TwinDesk pairing+TLS — either ship auth and claim it, or scope it out explicitly).

**Candidate venues (realistic ladder):** IEEE **Consumer Communications & Conference (ConsumerCom)** · IEEE **ICCE** · IEEE **WCST** · IEEE **LCN** (fits the Höchst-lineage framing perfectly) · IEEE **PerCom workshop / HotNets** (novelty-forward, for the “personal-area transport plane” framing) · ACM **MMSys** short/ACM MM workshops (interactive-multimedia angle) · **IEEE Access** (rolling, OA fee, if a journal is needed fast). Top-tier (SIGCOMM/MobiCom/NSDI) requires an algorithmic contribution beyond the system (e.g., a learned/hysteresis switch policy with cross-site results) — feasible follow-up, not the first paper.

**Timeline/novelty risk (must be disclosed in related work):** TwinDesk (2026-10-14) is 5 days older than our first commit; ZenLink (2026-11-03), ZeroLink (2025-10-13) post/predate parts of our roadmap. The credible story is **contemporaneous independent convergence** — and our measured-BT-video + USB-IP-plane + handover-measurement deltas remain unclaimed. The race clock matters: TwinDesk ships fast (v3.2.1 in 6 weeks); if they ever put screens on BT, C1 dies — **publish the BT-video measurement early** (ConsumerCom deadline is usually mid-year; LCN is summer; IEEE Access anytime).

---

## 9. One correction to the brief

The request stated “twindesk … implements Bluetooth real time screen sharing.” Read directly, its README says the opposite for the payload: Bluetooth carries **session, clipboard, notifications, input, calls**; “**Screens, apps, cameras, files, photos** … on Bluetooth → **moves to Wi-Fi Direct**”. TwinDesk’s Bluetooth *link management* (BlueZ, presence, failover) is real and impressive — but the video payload is Wi-Fi-plane always (LAN or Wi-Fi Direct). This distinction is, fortunately, **exactly where MLRC ACCS’s novelty lives** (Section 8, C1).

---

## 10. Spec & protocol references (design toolbox)

- **Wi-Fi Display / Miracast**: Wi-Fi Alliance “Wi-Fi Display” spec (1.x/2.x); WFD IEs; RTSP :7236 + RTP/MPEG-TS; Microsoft “Miracast over Infrastructure” docs.
- **AirPlay**: AWDL/RTSP lineage via [UxPlay](https://github.com/fdmanana/UxPlay) and playfair lineage (ZenLink/TwinDesk both reuse it).
- **Sidecar** (Apple), **Luna Display** ([shop.astropad.com/products/luna-display](https://shop.astropad.com/products/luna-display)), **Duet** (duetdisplay.com), **spacedesk** (spacedesk.net), **SuperDisplay** (superdisplay.app) — closed second-screen family.
- **Android**: ADB + wireless debugging ([developer.android.com/tools/adb](https://developer.android.com/tools/adb)); **AOA** accessory protocol ([source.android.com/docs/protocols/aoa](https://source.android.com/docs/protocols/aoa)); scrcpy server design ([Genymobile/scrcpy](https://github.com/Genymobile/scrcpy) doc tree).
- **Linux USB gadget**: configfs + `f_ncm`/`f_rndis`/`f_serial` ([kernel.org Documentation/usb/gadget_configfs.txt](https://www.kernel.org/doc/Documentation/usb/gadget_configfs.txt)) — the free (chip-less) alternative to DisplayLink/evdi.
- **DisplayLink**: [DisplayLink/evdi](https://github.com/DisplayLink/evdi) (978★ MIT) + vendor HAL — prior art that USB can carry a real display.
- **Bluetooth**: ETSI TS 07.10 (RFCOMM/Multiplexing) — SPP profile; BNEP/PAN (IP-over-BT alternative to SPP that would preserve the uniform-IP plane of C2 — worth a design A/B in the paper); SDP discovery.
- **SMB Multichannel** ([MS-SMB2], Windows 8/2012+): production precedent for *automatic* multi-interface failover inside an app protocol — closest industrial fallback-policy analog.
- **QUIC RFC 9000 §9** (connection migration) + **draft-ietf-quic-multipath** + **MPTCP RFC 8684**; **ICE RFC 8445** (candidate gathering — our presence-port probe is a mini-ICE).
- **Nearby Connections strategies** ([developers.google.com/nearby/connections/strategies](https://developers.google.com/nearby/connections/strategies)) — strategy-based multi-radio endpoint API design precedent.
- **KVMFR framing** ([gnif/LookingGlass](https://github.com/gnif/LookingGlass)) — shared-nothing frame transport discipline reusable across USB/BT byte-streams.

---

## 11. Appendix — measurement & search log (2026-11-26)

**Popularity measurements:** GitHub REST (`/search/repositories`, `/repos/*`): all ★/dates/licenses in the master table measured directly today; shields.io `github/downloads/<repo>/total.json`: scrcpy 32 M, RustDesk 86 M, moonlight-qt 13 M, Sunshine 8.5 M, deskreen 297 k, TwinDesk 109 k, UxPlay 14 k, ZenLink 12 k, LookingGlass 9.8 k, UScreen 6 k, iPhone-use 1.3 k, evdi 0.
**Citation measurements:** Crossref (`query.bibliographic`, `query.title`, DOI pings) + Semantic Scholar `/paper/search/match`: Mosh 54; Qin 120; Xu 73; Jung 65; Han 43; Paasch 98/32; Song 70; Höchst 5; Banerjee&Agu 6; Razavi×2 2/0; Alhazmi 4; SBD 5; ISSRE 1; deskflow/Deskflow verified as successor record for the archived `input-leap/input-leap` repo.
**arXiv verification batch (titles live-checked):** 1601.06043, 1909.02601, 2502.01290, 2503.07973, 2112.01068, 2305.03684, 1907.10493, 2008.00087, 2410.01981, 2507.03344 (“Securing Mixed Rust with Hardware Capabilities”), 2405.18135, 2409.08708, 2202.04431.
**Dead-end queries (gap evidence):** §6.5 list.
**⚠ Tooling note for the record:** the built-in `web_search` tool failed with DeepSeek 401 (invalid plugin API key) for the whole survey; it can be repaired under **Plugins → Built-in → Web search**. All results above come from first-party APIs instead.

*End of survey.*

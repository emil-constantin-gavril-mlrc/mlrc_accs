# Protocol-Agnostic Screen Sharing: Research Notes

**Single-codebase, OS-agnostic system with adaptive transport selection (USB → Wi-Fi → Bluetooth) and a high-performance Rust networking backend.**

---

## 1. Project Overview

### Goal
Build a **protocol-agnostic** screen sharing / remote display system that:

- Uses a **single codebase** across major operating systems (Windows, macOS, Linux, Android, and potentially iOS).
- Employs a **hierarchical adaptive transport** strategy: prefer USB when available, fall back to Wi-Fi, and use Bluetooth only as a last resort.
- Implements the core networking and streaming logic in **Rust** for performance, memory safety, and cross-platform consistency.

### Core Value Proposition
- Continuity of service even when preferred transports become unavailable or degraded.
- Reduced long-term maintenance cost through a true single codebase.
- Competitive latency and quality on high-bandwidth paths while remaining usable on extremely constrained links (Bluetooth).

### Related Systems
| System     | Notes                                                                 | Relevance |
|------------|-----------------------------------------------------------------------|---------|
| scrcpy     | Excellent Android USB/Wi-Fi screen sharing (H.264/H.265)              | Strong baseline for USB + Wi-Fi performance |
| ZeroLink   | Local-network screen sharing (Android ↔ Android / PC), JPEG frames, Kotlin Multiplatform | Multiplatform comparison point |
| ZenLink    | Native Rust Windows client for iPhone/iPad/Android (USB + Wi-Fi), hardware decode, ~9 MB binary | Closest Rust-based competitor |
| Miracast / AirPlay / WebRTC | Industry standards                     | Reference points for quality and latency expectations |

---

## 2. IEEE / Publication Potential

**Assessment**: Borderline for strong IEEE venues as a pure implementation case study. More realistic for mid-tier conferences, workshops, IEEE Access, or demo tracks.

**Strengths**
- Explicit multi-transport hierarchy (especially including Bluetooth as a usable degraded mode) is under-explored in the academic literature.
- Single-codebase OS-agnostic design with a modern systems language (Rust) is still non-trivial and of practical interest.
- Adaptive transport selection under real constraints (latency, jitter, bandwidth, battery) offers a clear research angle.

**Weaknesses**
- Individual components (USB screen sharing, Wi-Fi mirroring, Rust remote desktop tools) already exist.
- Pure “we built it” papers face a high bar; strong evaluation and a clear technical contribution (especially around adaptive selection) are required.

**Realistic targets**
- Workshops and mid-tier IEEE conferences (PerCom workshops, LCN, ICC workshops, etc.).
- IEEE Access or similar open-access venues.
- Demo / poster tracks as a first step.

**What would strengthen a paper**
- Adaptive transport selection with a formalized cost model and hysteresis.
- Rigorous multi-platform evaluation (latency, FPS, power, switch-over cost).
- Clear quantification of the single-codebase advantage.
- Novel handling of the Bluetooth path (codec choice + quality adaptation).

---

## 3. Research Subpoint 1: Metrics & Profiles for Adaptive Transport Selection

### Core Metrics
| Metric                        | Unit          | Role in decision |
|-------------------------------|---------------|------------------|
| Latency (one-way / RTT)       | ms            | Primary interactivity signal |
| Jitter                        | ms            | Predicts freezes / stutter |
| Available bandwidth / goodput | Mbps          | Determines feasible resolution + FPS + quality |
| Packet loss / retransmission  | %             | Especially costly on reliable (TCP-like) transports |
| Battery / power draw          | mW or %/h     | Critical on mobile devices |
| Switch-over cost              | ms + dropped frames | Penalty for changing transport mid-session |
| CPU / thermal load            | % or °C       | Affects sustained encoding performance |

### Typical Performance Envelopes
| Transport   | Usable Bandwidth     | Typical Latency (good conditions) | Jitter     | Battery Impact     | Role |
|-------------|----------------------|-----------------------------------|------------|--------------------|------|
| **USB**     | 100–400+ Mbps       | 35–70 ms                         | Very low   | Low–medium (often charging) | Preferred when available |
| **Wi-Fi**   | 20–150 Mbps (realistic goodput) | 65–150 ms                | Medium–high| Medium–high        | Primary wireless path |
| **Bluetooth** | 0.5–2 Mbps practical | 80–250+ ms                     | High       | Low–medium         | Last-resort / degraded mode |

### Example Decision Profiles
- **Prefer USB** whenever it is present and stable (latency < 80 ms, near-zero loss).
- **Prefer Wi-Fi** when USB is unavailable **and** goodput ≥ 4–8 Mbps **and** RTT < 120 ms **and** jitter < 30 ms.
- **Fall to Bluetooth** only when higher-priority paths are unavailable or severely degraded, **or** when battery is critically low and the user accepts reduced quality (e.g., ≤ 480p @ 10–15 fps).
- **Hysteresis is mandatory**: require sustained degradation (several seconds) before switching down, and a clear improvement window before switching up, to avoid oscillation.

### Suggested Cost Function (starting point)
\[
\text{Cost} = w_L \cdot L + w_J \cdot J + w_B \cdot \frac{1}{B} + w_E \cdot E + w_S \cdot S
\]
where \(L\) = latency, \(J\) = jitter, \(B\) = bandwidth, \(E\) = energy cost, \(S\) = switch cost. Weights can be scenario-dependent (gaming vs. presentation vs. passive viewing).

---

## 4. Research Subpoint 2: Quantifying the Utility of a Single Rust Codebase

### Comparison Targets
- **ZeroLink**: Kotlin Multiplatform, local-network focus, JPEG-based frames.
- **ZenLink**: Rust Windows client, scrcpy / QuickTime backends, hardware decode, very small binary.

### Recommended Metrics
| Category              | Concrete Metrics                                      | Expected Advantage of Single Rust Codebase |
|-----------------------|-------------------------------------------------------|--------------------------------------------|
| Code size & complexity| Total SLOC, SLOC per platform, cyclomatic complexity, % platform-specific code | Lower total SLOC and far fewer platform-specific branches |
| Binary & dependencies | Final binary size, number of external libraries, runtime dependencies | Competitive or better (ZenLink already ~9 MB) |
| Performance parity    | End-to-end latency, FPS, CPU %, memory, power draw on identical hardware | Should match or exceed specialized tools |
| Safety & reliability  | Crash rate, memory-safety issues                      | Strong differentiator vs. C/C++ or mixed-language stacks |
| Maintenance effort    | Time/commits to add a new OS or transport; bug density | Lower long-term cost |
| Developer velocity    | Time to implement a new feature across all platforms  | Higher due to shared core |

### Key Claims to Validate
- A well-designed Rust core + thin platform adapters yields a significantly higher percentage of shared code than current multi-language approaches.
- Performance remains competitive with purpose-built tools (scrcpy on Android USB/Wi-Fi, ZenLink on Windows).
- Long-term maintenance and feature velocity improve measurably.

---

## 5. Research Subpoint 3: Codecs for Bluetooth and Bandwidth-Constrained Streaming

### Bluetooth Context
- Bluetooth SIG Video Distribution Profile (VDP) historically mandated **H.263 Baseline**.
- In practice, modern systems almost always prefer **H.264** because of vastly better compression and ubiquitous hardware support.
- Sustained goodput on real Bluetooth links is typically only 0.5–2 Mbps for video, far below theoretical peaks.

### Recommended Codec Strategy
| Bandwidth Regime              | Recommended Codec              | Notes |
|-------------------------------|--------------------------------|-------|
| Bluetooth (≤ 1–2 Mbps usable) | H.264 (baseline/main) at very low bitrate + aggressive resolution/FPS reduction | Most compatible and practical starting point |
| Slightly better constrained links (2–5 Mbps) | H.265 / HEVC or VP9           | Better quality at same bitrate; check hardware support |
| Modern low-bandwidth (CPU available) | **AV1**                       | Best compression efficiency (often 30–50 % better than H.264); excellent for screen content |
| Extreme / ultra-static content | MJPEG or custom delta + keyframes | Possible fallback for very static screens |

### Industry Precedents for Low-Bandwidth Video
- Telemetry / aerospace / defense links: highly tuned H.265 or specialized light codecs at a few hundred kbps to a few Mbps.
- Mobile real-time communication (e.g., Meta): AV1 at very low bitrates for poor networks.
- Surveillance and IoT cameras: H.265 or AV1 for constrained backhaul.
- Screen sharing under poor networks: AV1 or VP9 preferred when CPU allows; H.264 remains the compatibility baseline.

### Practical Guidance for the Bluetooth Path
- Treat Bluetooth as an explicitly **degraded mode**.
- Drop resolution aggressively (≤ 480p), reduce frame rate (10–15 fps), and use content-aware encoding when possible (prioritize UI/text).
- Prefer hardware H.264 encode/decode to protect battery life.
- Measure real sustained goodput on the actual Bluetooth links you target; do not rely on theoretical maximums.

---

## 6. Suggested Experimental Agenda

1. **Characterize the three transports** on representative hardware (latency, jitter, goodput, power, loss under load).
2. **Implement and tune** the adaptive selector with hysteresis and a multi-objective cost function.
3. **Measure switch-over cost** (time + visual disruption) between all pairs of transports.
4. **Benchmark the single Rust codebase** against ZeroLink and ZenLink on code metrics, binary size, and runtime performance.
5. **Evaluate codec choices** on the Bluetooth path (H.264 vs. H.265 vs. AV1) at realistic bitrates and resolutions.
6. **User-facing quality study** (or at least structured subjective evaluation) under different transport and battery conditions.

---

## 7. Academic Papers

- **On the Performance Comparisons of Native and Clientless Real-Time Screen Sharing Technologies**  
  Chun-Ying Huang, Yun-Chen Cheng, Guan-Zhang Huang, Ching-Ling Fan, Cheng-Hsin Hsu  
  *ACM Transactions on Multimedia Computing, Communications, and Applications (TOMM)*, Vol. 17, No. 2, Article 54, 2021  
  https://doi.org/10.1145/3437881  
  https://dl.acm.org/doi/fullHtml/10.1145/3437881

- **LiteMirroring: BT Based Screen Mirroring Solution**  
  2024 International Conference on Consumer Electronics - Taiwan (ICCE-Taiwan)  
  IEEE  
  https://ieeexplore.ieee.org/document/10674135/

- **A QoS-adaptive framework for screen sharing over Internet**  
  IEEE  
  https://ieeexplore.ieee.org/document/7536942/

- **Screen dynamics analysis-based adaptive frame skipping for efficient mobile screen sharing**  
  Proceedings of the 14th International Conference on Information Processing in Sensor Networks (IPSN)  
  https://dl.acm.org/doi/10.1145/2737095.2737728

- **Learning Wi-Fi Connection Loss Predictions for Seamless Vertical Handovers Using Multipath TCP**  
  arXiv:1907.10493, 2019 IEEE 44th Conference on Local Computer Networks (LCN)  
  https://arxiv.org/abs/1907.10493

- **A reliable and energy-efficient hybrid screen mirroring multicast system** (overhearing-based multicast + Raptor codes)  
  IEEE  
  https://ieeexplore.ieee.org/document/7964696/

- **Wireless Screen-casting QoE evaluation model** (end-side + network factors)  
  IEEE  
  https://ieeexplore.ieee.org/document/10695843/

- **Scheduling virtual wifi interfaces for high bandwidth video upstreaming using multipath TCP**  
  Proceedings of the 20th International Conference on Distributed Computing and Networking (ICDCN)  
  https://dl.acm.org/doi/10.1145/3288599.3288620

- **Design and empirical validation of a stock-Android software architecture for Wi-Fi Direct multi-group communication**  
  arXiv:2604.07889  
  https://arxiv.org/abs/2604.07889

- **Camel: Frame-Level Bandwidth Estimation for Low-Latency Live Streaming under Video Bitrate Undershooting**  
  arXiv:2602.09500 (WWW 2026)  
  https://arxiv.org/abs/2602.09500

- **An Axiomatic Analysis of Path Selection Strategies for Multipath Transport in Path-Aware Networks**  
  arXiv  
  https://arxiv.org/html/2509.05938v1

- **On Deadline-Aware and Cost-Aware Multipath Packet Scheduling in Mobile Applications**  
  IEEE Transactions on Mobile Computing  
  https://www.computer.org/csdl/journal/tm/2026/12/11680014/2jvJHWOZ3jy

- **Low-delay cost-aware multipath scheduling over dynamic links for access traffic steering, switching, and splitting**  
  Computer Networks, 2024  
  https://www.sciencedirect.com/science/article/pii/S1389128624000185

- **Cross-layer Path Selection in Multi-path Transport Protocol for Mobile Devices**  
  arXiv:2007.01536  
  https://arxiv.org/html/2007.01536v1

- **A Method of Codec Comparison and Selection for Good Quality Video Transmission Over Limited-Bandwidth Networks**  
  Sensors, 2021  
  https://www.mdpi.com/1424-8220/21/13/4589

## 8. Patents

- **Streaming On Diverse Transports** (Transport Agnostic Display – TAD)  
  US20210176089A1 / US11764996 / US10791003  
  https://patents.google.com/patent/US20210176089A1/en  
  https://patents.justia.com/patent/11764996

## 9. Relevant Systems / Tools (non-paper)

- TwinDesk (multi-transport including USB, Wi-Fi, Bluetooth LE)  
- ZeroLink / LocalScreenShare  
- ZenLink (Rust-based)  
- scrcpy  
- Luna Display (USB + peer-to-peer Wi-Fi)

## 10. Notes on Coverage
No exact academic paper was found that implements a full hierarchical fallback of **USB → Wi-Fi → Bluetooth** for continuous screen sharing with adaptive selection. Closest related work covers:
- Bluetooth-only or Bluetooth-assisted screen mirroring (LiteMirroring)
- Transport-agnostic display protocols (Intel TAD patents)
- Multipath / adaptive path selection in mobile networking
- Codec and QoS adaptation for screen sharing
- Performance comparisons of screen-sharing technologies (WebRTC vs native)

---

## 11. Open Questions / Future Work

- How aggressively should the system reduce quality on Bluetooth before the experience becomes unusable?
- Can content-type detection (static UI vs. video playback vs. gaming) improve transport and codec decisions?
- What is the right user-visible model for transport changes (silent, notification, manual override)?
- How does the system behave under multipath opportunities (e.g., simultaneous Wi-Fi + Bluetooth) if they become available?
- Security and privacy implications of falling back across very different link types.

---

*Document generated from project discussion. Last updated: 2026-11-26.*

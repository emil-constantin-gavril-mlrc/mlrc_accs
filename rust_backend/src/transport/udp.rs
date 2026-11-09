use std::collections::BTreeMap;
use std::io;
use std::net::UdpSocket;
use std::time::{Duration, Instant};

use crate::{BackendError, CommType};

const MAGIC: [u8; 4] = *b"MAC1";
const ACK_MAGIC: [u8; 4] = *b"MAA1";
const HEADER_BYTES: usize = 12;
const ACK_BYTES: usize = 8;
const MAX_UDP_PAYLOAD: usize = 65_507;
const MAX_FRAME_BYTES: usize = 32 * 1024 * 1024;
const MAX_BUFFERED_BYTES: usize = 64 * 1024 * 1024;
const MAX_INCOMPLETE_FRAMES: usize = 32;
const INCOMPLETE_FRAME_TTL: Duration = Duration::from_secs(5);
const MAX_SEND_ATTEMPTS: usize = 3;
const ACK_TIMEOUT: Duration = Duration::from_millis(500);
const PACKET_SEND_DELAY: Duration = Duration::from_micros(100);

#[derive(Clone, Debug)]
pub struct UdpConfig {
    pub bind_address: std::net::SocketAddr,
    pub peer_address: std::net::SocketAddr,
    pub packet_payload_bytes: usize,
    pub receive_timeout: Duration,
    pub jitter_buffer_frames: usize,
    pub jitter_timeout: Duration,
}

impl Default for UdpConfig {
    fn default() -> Self {
        Self {
            bind_address: "0.0.0.0:0".parse().expect("valid default bind address"),
            peer_address: "127.0.0.1:0".parse().expect("valid default peer address"),
            packet_payload_bytes: 1200,
            receive_timeout: Duration::from_secs(1),
            jitter_buffer_frames: 4,
            jitter_timeout: Duration::from_millis(40),
        }
    }
}

struct FrameAssembly {
    chunks: Vec<Option<Vec<u8>>>,
    received_chunks: usize,
    total_bytes: usize,
    started_at: Instant,
}

struct Packet<'a> {
    frame_id: u32,
    chunk_index: u16,
    chunk_count: u16,
    payload: &'a [u8],
}

pub struct UdpTransport {
    socket: UdpSocket,
    config: UdpConfig,
    next_frame_id: u32,
    expected_frame_id: Option<u32>,
    incomplete: BTreeMap<u32, FrameAssembly>,
    ready: BTreeMap<u32, Vec<u8>>,
    gap_started_at: Option<Instant>,
}

impl UdpTransport {
    pub fn new(config: UdpConfig) -> Result<Self, BackendError> {
        if config.packet_payload_bytes == 0
            || config.packet_payload_bytes > MAX_UDP_PAYLOAD - HEADER_BYTES
        {
            return Err(BackendError::Configuration(format!(
                "packet payload must be between 1 and {} bytes",
                MAX_UDP_PAYLOAD - HEADER_BYTES
            )));
        }
        if config.receive_timeout.is_zero() || config.jitter_timeout.is_zero() {
            return Err(BackendError::Configuration(
                "receive and jitter timeouts must be greater than zero".to_owned(),
            ));
        }
        if config.peer_address.port() == 0 {
            return Err(BackendError::Configuration(
                "peer address must use a nonzero UDP port".to_owned(),
            ));
        }
        if config.jitter_buffer_frames == 0 || config.jitter_buffer_frames > 64 {
            return Err(BackendError::Configuration(
                "jitter buffer capacity must be between 1 and 64 frames".to_owned(),
            ));
        }

        let socket = UdpSocket::bind(config.bind_address)?;
        socket.connect(config.peer_address)?;

        Ok(Self {
            socket,
            config,
            next_frame_id: 0,
            expected_frame_id: Some(0),
            incomplete: BTreeMap::new(),
            ready: BTreeMap::new(),
            gap_started_at: None,
        })
    }

    pub fn local_addr(&self) -> Result<std::net::SocketAddr, BackendError> {
        self.socket.local_addr().map_err(BackendError::from)
    }

    fn send_frame(&mut self, frame: &[u8]) -> Result<(), BackendError> {
        if frame.len() > MAX_FRAME_BYTES {
            return Err(BackendError::FrameTooLarge {
                size: frame.len(),
                maximum: MAX_FRAME_BYTES,
            });
        }

        let chunk_count = frame
            .len()
            .max(1)
            .div_ceil(self.config.packet_payload_bytes);
        let chunk_count = u16::try_from(chunk_count).map_err(|_| {
            BackendError::Configuration("frame needs more than 65535 UDP packets".to_owned())
        })?;
        let frame_id = self.next_frame_id;
        self.next_frame_id = self.next_frame_id.wrapping_add(1);

        for _ in 0..MAX_SEND_ATTEMPTS {
            for chunk_index in 0..chunk_count {
                let start = usize::from(chunk_index) * self.config.packet_payload_bytes;
                let end = (start + self.config.packet_payload_bytes).min(frame.len());
                let chunk = frame.get(start..end).unwrap_or_default();
                let mut packet = Vec::with_capacity(HEADER_BYTES + chunk.len());
                packet.extend_from_slice(&MAGIC);
                packet.extend_from_slice(&frame_id.to_be_bytes());
                packet.extend_from_slice(&chunk_index.to_be_bytes());
                packet.extend_from_slice(&chunk_count.to_be_bytes());
                packet.extend_from_slice(chunk);

                let sent = self.socket.send(&packet)?;
                if sent != packet.len() {
                    return Err(BackendError::Transport(format!(
                        "UDP sent {sent} of {} packet bytes",
                        packet.len()
                    )));
                }
                if chunk_index + 1 < chunk_count {
                    std::thread::sleep(PACKET_SEND_DELAY);
                }
            }

            if self.wait_for_ack(frame_id)? {
                return Ok(());
            }
        }

        Err(BackendError::Transport(format!(
            "UDP frame {frame_id} was not acknowledged after {MAX_SEND_ATTEMPTS} attempts"
        )))
    }

    fn wait_for_ack(&self, frame_id: u32) -> Result<bool, BackendError> {
        let deadline = Instant::now() + ACK_TIMEOUT;
        let mut packet = [0_u8; MAX_UDP_PAYLOAD];
        loop {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                return Ok(false);
            }
            self.socket.set_read_timeout(Some(remaining))?;
            match self.socket.recv(&mut packet) {
                Ok(bytes)
                    if bytes == ACK_BYTES
                        && packet[..4] == ACK_MAGIC
                        && u32::from_be_bytes(
                            packet[4..8].try_into().expect("fixed-width slice"),
                        ) == frame_id =>
                {
                    return Ok(true);
                }
                Ok(_) => {}
                Err(error)
                    if matches!(
                        error.kind(),
                        io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut
                    ) =>
                {
                    return Ok(false);
                }
                Err(error) => return Err(BackendError::Io(error)),
            }
        }
    }

    fn send_ack(&self, frame_id: u32) -> Result<(), BackendError> {
        let mut packet = [0_u8; ACK_BYTES];
        packet[..4].copy_from_slice(&ACK_MAGIC);
        packet[4..].copy_from_slice(&frame_id.to_be_bytes());
        let sent = self.socket.send(&packet)?;
        if sent != packet.len() {
            return Err(BackendError::Transport(format!(
                "UDP sent {sent} of {} acknowledgement bytes",
                packet.len()
            )));
        }
        Ok(())
    }

    fn receive_frame(&mut self) -> Result<Vec<u8>, BackendError> {
        let mut packet = vec![0_u8; MAX_UDP_PAYLOAD];
        loop {
            if let Some(frame) = self.pop_ready_frame() {
                return Ok(frame);
            }

            let timeout = self.read_timeout();
            self.socket.set_read_timeout(Some(timeout))?;
            match self.socket.recv(&mut packet) {
                Ok(packet_bytes) => {
                    self.expire_incomplete_frames();
                    let decoded = decode_packet(&packet[..packet_bytes])?;
                    self.push_chunk(
                        decoded.frame_id,
                        decoded.chunk_index,
                        decoded.chunk_count,
                        decoded.payload,
                    )?;
                }
                Err(error)
                    if matches!(
                        error.kind(),
                        io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut
                    ) =>
                {
                    if self.ready.len() >= self.config.jitter_buffer_frames
                        || self.gap_started_at.is_some_and(|started_at| {
                            started_at.elapsed() >= self.config.jitter_timeout
                        })
                    {
                        continue;
                    }
                    return Err(BackendError::Io(error));
                }
                Err(error) => return Err(BackendError::Io(error)),
            }
        }
    }

    fn push_chunk(
        &mut self,
        frame_id: u32,
        chunk_index: u16,
        chunk_count: u16,
        payload: &[u8],
    ) -> Result<(), BackendError> {
        if chunk_count == 0 || chunk_index >= chunk_count {
            return Err(BackendError::InvalidPacket("invalid chunk index or count"));
        }
        if self
            .expected_frame_id
            .is_some_and(|expected| is_before(frame_id, expected))
        {
            return self.send_ack(frame_id);
        }
        if !self.incomplete.contains_key(&frame_id)
            && self.incomplete.len() >= MAX_INCOMPLETE_FRAMES
        {
            return Err(BackendError::Transport(
                "too many incomplete UDP frames; peer may be sending faster than the receiver"
                    .to_owned(),
            ));
        }
        if let Some(assembly) = self.incomplete.get(&frame_id) {
            if assembly.chunks.len() != usize::from(chunk_count) {
                return Err(BackendError::InvalidPacket(
                    "chunk count changed within a frame",
                ));
            }
            if assembly.chunks[usize::from(chunk_index)].is_some() {
                return Ok(());
            }
        }
        if self.buffered_bytes() + payload.len() > MAX_BUFFERED_BYTES {
            self.incomplete.remove(&frame_id);
            return Err(BackendError::Transport(
                "buffered UDP frames exceeded the 64 MiB receiver limit".to_owned(),
            ));
        }

        let assembly = self
            .incomplete
            .entry(frame_id)
            .or_insert_with(|| FrameAssembly {
                chunks: vec![None; usize::from(chunk_count)],
                received_chunks: 0,
                total_bytes: 0,
                started_at: Instant::now(),
            });
        if assembly.total_bytes + payload.len() > MAX_FRAME_BYTES {
            let size = assembly.total_bytes + payload.len();
            self.incomplete.remove(&frame_id);
            return Err(BackendError::FrameTooLarge {
                size,
                maximum: MAX_FRAME_BYTES,
            });
        }

        assembly.chunks[usize::from(chunk_index)] = Some(payload.to_vec());
        assembly.received_chunks += 1;
        assembly.total_bytes += payload.len();
        if assembly.received_chunks != assembly.chunks.len() {
            return Ok(());
        }

        let assembly = self.incomplete.remove(&frame_id).expect("assembly exists");
        let mut frame = Vec::with_capacity(assembly.total_bytes);
        for chunk in assembly.chunks {
            frame.extend_from_slice(chunk.as_deref().ok_or(BackendError::InvalidPacket(
                "completed frame has a missing chunk",
            ))?);
        }

        if !self
            .expected_frame_id
            .is_some_and(|expected| is_before(frame_id, expected))
        {
            self.ready.entry(frame_id).or_insert(frame);
            self.send_ack(frame_id)?;
        }
        Ok(())
    }

    fn pop_ready_frame(&mut self) -> Option<Vec<u8>> {
        loop {
            let expected = *self
                .expected_frame_id
                .get_or_insert_with(|| self.ready.keys().next().copied().unwrap_or_default());
            if let Some(frame) = self.ready.remove(&expected) {
                self.expected_frame_id = Some(expected.wrapping_add(1));
                self.gap_started_at = None;
                return Some(frame);
            }
            if self.ready.is_empty() {
                return None;
            }

            let gap_started = *self.gap_started_at.get_or_insert_with(Instant::now);
            if self.ready.len() < self.config.jitter_buffer_frames
                && gap_started.elapsed() < self.config.jitter_timeout
            {
                return None;
            }

            let next = self.closest_ready_sequence(expected)?;
            self.expected_frame_id = Some(next);
            self.gap_started_at = None;
        }
    }

    fn closest_ready_sequence(&self, expected: u32) -> Option<u32> {
        self.ready
            .keys()
            .copied()
            .filter(|frame_id| !is_before(*frame_id, expected))
            .min_by_key(|frame_id| frame_id.wrapping_sub(expected))
    }

    fn read_timeout(&self) -> Duration {
        match (self.gap_started_at, self.ready.is_empty()) {
            (Some(started_at), false) => self.config.receive_timeout.min(
                self.config
                    .jitter_timeout
                    .saturating_sub(started_at.elapsed()),
            ),
            _ => self.config.receive_timeout,
        }
    }

    fn expire_incomplete_frames(&mut self) {
        let now = Instant::now();
        self.incomplete
            .retain(|_, assembly| now.duration_since(assembly.started_at) < INCOMPLETE_FRAME_TTL);
    }

    fn buffered_bytes(&self) -> usize {
        self.incomplete
            .values()
            .map(|assembly| assembly.total_bytes)
            .chain(self.ready.values().map(Vec::len))
            .sum()
    }
}

impl super::Transport for UdpTransport {
    fn communication_type(&self) -> CommType {
        CommType::Wifi
    }

    fn send(&mut self, frame: &[u8]) -> Result<(), BackendError> {
        self.send_frame(frame)
    }

    fn receive(&mut self) -> Result<Vec<u8>, BackendError> {
        self.receive_frame()
    }
}

fn is_before(candidate: u32, expected: u32) -> bool {
    candidate.wrapping_sub(expected) >= (1 << 31)
}

fn decode_packet(packet: &[u8]) -> Result<Packet<'_>, BackendError> {
    if packet.len() < HEADER_BYTES {
        return Err(BackendError::InvalidPacket("packet header is truncated"));
    }
    if packet[..4] != MAGIC {
        return Err(BackendError::InvalidPacket("unknown packet signature"));
    }

    let frame_id = u32::from_be_bytes(packet[4..8].try_into().expect("fixed-width slice"));
    let chunk_index = u16::from_be_bytes(packet[8..10].try_into().expect("fixed-width slice"));
    let chunk_count = u16::from_be_bytes(packet[10..12].try_into().expect("fixed-width slice"));
    Ok(Packet {
        frame_id,
        chunk_index,
        chunk_count,
        payload: &packet[HEADER_BYTES..],
    })
}

#[cfg(test)]
mod tests {
    use std::net::{IpAddr, Ipv4Addr, SocketAddr};
    use std::thread;

    use super::*;
    use crate::transport::Transport;

    #[test]
    fn loopback_sends_and_reassembles_fragmented_frames() {
        let receiver_bind = SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), 0);
        let receiver_socket = UdpSocket::bind(receiver_bind).unwrap();
        let receiver_address = receiver_socket.local_addr().unwrap();
        drop(receiver_socket);

        let config = UdpConfig {
            bind_address: SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), 0),
            peer_address: receiver_address,
            packet_payload_bytes: 64,
            receive_timeout: Duration::from_secs(2),
            jitter_buffer_frames: 4,
            jitter_timeout: Duration::from_millis(40),
        };
        let mut sender = UdpTransport::new(config.clone()).unwrap();

        let receiver_config = UdpConfig {
            bind_address: receiver_address,
            peer_address: sender.local_addr().unwrap(),
            ..config
        };
        let mut receiver = UdpTransport::new(receiver_config).unwrap();
        let frame = (0..4096).map(|byte| (byte % 251) as u8).collect::<Vec<_>>();

        let expected = frame.clone();
        let sender_thread = thread::spawn(move || sender.send(&frame));
        assert_eq!(receiver.receive().unwrap(), expected);
        sender_thread.join().unwrap().unwrap();
    }

    #[test]
    fn sender_retries_when_the_first_frame_acknowledgement_is_lost() {
        let receiver = UdpSocket::bind("127.0.0.1:0").unwrap();
        receiver
            .set_read_timeout(Some(Duration::from_secs(3)))
            .unwrap();
        let receiver_address = receiver.local_addr().unwrap();
        let config = UdpConfig {
            bind_address: "127.0.0.1:0".parse().unwrap(),
            peer_address: receiver_address,
            packet_payload_bytes: 64,
            ..UdpConfig::default()
        };
        let mut sender = UdpTransport::new(config).unwrap();
        let sender_address = sender.local_addr().unwrap();
        let frame = vec![7; 128];

        let receiver_thread = thread::spawn(move || {
            let mut packet = [0_u8; 128];
            for attempt in 0..2 {
                let mut received_chunks = BTreeMap::new();
                let mut frame_id = None;
                let mut chunk_count = 0;
                while received_chunks.len() < 2 {
                    let (length, source) = receiver.recv_from(&mut packet).unwrap();
                    let decoded = decode_packet(&packet[..length]).unwrap();
                    frame_id = Some(decoded.frame_id);
                    chunk_count = decoded.chunk_count;
                    received_chunks.insert(decoded.chunk_index, source);
                }
                assert_eq!(chunk_count, 2);
                if attempt == 1 {
                    let frame_id = frame_id.unwrap();
                    let mut ack = [0_u8; ACK_BYTES];
                    ack[..4].copy_from_slice(&ACK_MAGIC);
                    ack[4..].copy_from_slice(&frame_id.to_be_bytes());
                    receiver
                        .send_to(&ack, sender_address)
                        .expect("send retry acknowledgement");
                }
            }
        });

        sender.send_frame(&frame).unwrap();
        receiver_thread.join().unwrap();
    }

    #[test]
    fn malformed_packet_is_rejected() {
        assert!(matches!(
            decode_packet(b"bad"),
            Err(BackendError::InvalidPacket(_))
        ));
    }

    #[test]
    fn sequence_comparison_handles_wraparound() {
        assert!(is_before(u32::MAX, 0));
        assert!(!is_before(0, u32::MAX));
    }

    #[test]
    fn receiver_reorders_complete_frames_within_the_jitter_window() {
        let sender = UdpSocket::bind("127.0.0.1:0").unwrap();
        let receiver_socket = UdpSocket::bind("127.0.0.1:0").unwrap();
        let receiver_address = receiver_socket.local_addr().unwrap();
        drop(receiver_socket);

        let config = UdpConfig {
            bind_address: receiver_address,
            peer_address: sender.local_addr().unwrap(),
            packet_payload_bytes: 64,
            receive_timeout: Duration::from_secs(2),
            jitter_buffer_frames: 4,
            jitter_timeout: Duration::from_millis(100),
        };
        let mut receiver = UdpTransport::new(config).unwrap();

        for (frame_id, payload) in [(1_u32, b"second".as_slice()), (0, b"first".as_slice())] {
            let mut packet = Vec::from(MAGIC);
            packet.extend_from_slice(&frame_id.to_be_bytes());
            packet.extend_from_slice(&0_u16.to_be_bytes());
            packet.extend_from_slice(&1_u16.to_be_bytes());
            packet.extend_from_slice(payload);
            sender.send_to(&packet, receiver_address).unwrap();
        }

        assert_eq!(receiver.receive().unwrap(), b"first");
        assert_eq!(receiver.receive().unwrap(), b"second");
    }

    #[test]
    fn receive_timeout_does_not_discard_a_frame_still_in_the_jitter_window() {
        let sender = UdpSocket::bind("127.0.0.1:0").unwrap();
        let receiver_socket = UdpSocket::bind("127.0.0.1:0").unwrap();
        let receiver_address = receiver_socket.local_addr().unwrap();
        drop(receiver_socket);

        let config = UdpConfig {
            bind_address: receiver_address,
            peer_address: sender.local_addr().unwrap(),
            receive_timeout: Duration::from_millis(10),
            jitter_timeout: Duration::from_millis(100),
            ..UdpConfig::default()
        };
        let mut receiver = UdpTransport::new(config).unwrap();
        let mut packet = Vec::from(MAGIC);
        packet.extend_from_slice(&1_u32.to_be_bytes());
        packet.extend_from_slice(&0_u16.to_be_bytes());
        packet.extend_from_slice(&1_u16.to_be_bytes());
        packet.extend_from_slice(b"buffered");
        sender.send_to(&packet, receiver_address).unwrap();

        assert!(matches!(
            receiver.receive(),
            Err(BackendError::Io(error))
                if matches!(error.kind(), io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut)
        ));
        std::thread::sleep(Duration::from_millis(110));
        assert_eq!(receiver.receive().unwrap(), b"buffered");
    }
}

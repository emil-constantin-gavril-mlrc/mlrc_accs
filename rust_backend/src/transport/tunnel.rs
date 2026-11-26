//! Interim direct USB link: framed TCP over an `adb forward`/`adb reverse`
//! tunnel.
//!
//! The cable itself carries the adbd USB bulk transfers, so this transport is
//! reported as [`CommType::Usb`] while staying pure standard-library TCP.
//! A receiver listens on local port 38430. The host connects to the phone
//! through `adb forward tcp:38433 tcp:38430`; the phone connects to the host
//! through `adb reverse tcp:38432 tcp:38430`. Separate client-side ports keep
//! ADB's local listeners from colliding with either app's receive socket.
//!
//! The wire format matches the rusb bulk transport exactly: a big-endian u32
//! frame length followed by the raw frame bytes. No MAC1/MAA1 ACK layer is
//! needed because TCP is reliable and ordered.
//!
//! `receive()` never blocks past the configured read timeout and preserves
//! partial frame state across calls, because the FFI worker loop treats only
//! `WouldBlock`/`TimedOut` I/O errors as "keep polling".

use std::io::{self, Read, Write};
use std::net::{SocketAddr, TcpListener, TcpStream};
use std::thread;
use std::time::Duration;

use crate::{BackendError, CommType};

use super::Transport;

const LENGTH_PREFIX_BYTES: usize = 4;

#[derive(Clone, Debug)]
pub struct TunnelConfig {
    /// Receiving role: waits for the peer (arriving through adb reverse) to
    /// connect here.
    pub listen_port: Option<u16>,
    /// Transmitting role: connects to the peer endpoint (adb forward makes
    /// the host-side address land on the device, and adb reverse makes the
    /// device-side address land on the host).
    pub connect_address: Option<SocketAddr>,
    /// Per-poll read timeout; partial frame state survives the timeout.
    pub read_timeout: Duration,
    pub connect_attempt_timeout: Duration,
    pub connect_retry_delay: Duration,
    pub max_connect_attempts: usize,
    pub max_frame_bytes: usize,
}

impl Default for TunnelConfig {
    fn default() -> Self {
        Self {
            listen_port: None,
            connect_address: None,
            read_timeout: Duration::from_millis(50),
            connect_attempt_timeout: Duration::from_millis(400),
            connect_retry_delay: Duration::from_millis(150),
            max_connect_attempts: 10,
            max_frame_bytes: 32 * 1024 * 1024,
        }
    }
}

pub struct TunnelTransport {
    listener: Option<TcpListener>,
    stream: Option<TcpStream>,
    connect_address: Option<SocketAddr>,
    config: TunnelConfig,
    header: [u8; LENGTH_PREFIX_BYTES],
    header_filled: usize,
    frame: Vec<u8>,
    frame_filled: usize,
}

impl TunnelTransport {
    pub fn new(config: TunnelConfig) -> Result<Self, BackendError> {
        if config.listen_port.is_some() == config.connect_address.is_some() {
            return Err(BackendError::Configuration(
                "the tunnel transport needs exactly one role: a listen port or a connect address"
                    .to_owned(),
            ));
        }
        let listener = match config.listen_port {
            Some(0) => {
                return Err(BackendError::Configuration(
                    "the USB tunnel listen port must not be zero".to_owned(),
                ));
            }
            Some(port) => {
                let listener = TcpListener::bind(SocketAddr::from(([0, 0, 0, 0], port)))
                    .map_err(|error| {
                        BackendError::Transport(format!(
                            "cannot listen for USB tunnel peers on port {port}: {error}"
                        ))
                    })?;
                listener.set_nonblocking(true)?;
                Some(listener)
            }
            None => None,
        };
        Ok(Self {
            listener,
            stream: None,
            connect_address: config.connect_address,
            config,
            header: [0; LENGTH_PREFIX_BYTES],
            header_filled: 0,
            frame: Vec::new(),
            frame_filled: 0,
        })
    }

    fn reset_frame_state(&mut self) {
        self.header = [0; LENGTH_PREFIX_BYTES];
        self.header_filled = 0;
        self.frame.clear();
        self.frame_filled = 0;
    }

    fn configure_stream(
        stream: &TcpStream,
        config: &TunnelConfig,
    ) -> Result<(), BackendError> {
        stream.set_nodelay(true)?;
        stream.set_read_timeout(Some(config.read_timeout))?;
        stream.set_write_timeout(Some(config.connect_attempt_timeout.max(config.read_timeout)))?;
        Ok(())
    }

    /// Establishes the data stream: accepts on the listening (receive) side,
    /// retries connect on the transmitting side. Returns `Ok(false)` only
    /// when the listening side has no incoming peer yet.
    fn next_stream(&mut self) -> Result<bool, BackendError> {
        if self.stream.is_some() {
            return Ok(true);
        }
        if let Some(listener) = self.listener.as_ref() {
            return match listener.accept() {
                Ok((stream, _)) => {
                    stream.set_nonblocking(false)?;
                    Self::configure_stream(&stream, &self.config)?;
                    self.stream = Some(stream);
                    Ok(true)
                }
                Err(error) if error.kind() == io::ErrorKind::WouldBlock => Ok(false),
                Err(error) => Err(BackendError::Io(error)),
            };
        }
        let address = self
            .connect_address
            .expect("construction guarantees a connect address here");
        let attempts = self.config.max_connect_attempts.max(1);
        let mut last_error: Option<io::Error> = None;
        for attempt in 1..=attempts {
            match TcpStream::connect_timeout(&address, self.config.connect_attempt_timeout) {
                Ok(stream) => {
                    Self::configure_stream(&stream, &self.config)?;
                    self.stream = Some(stream);
                    return Ok(true);
                }
                Err(error) => {
                    last_error = Some(error);
                    if attempt < attempts {
                        thread::sleep(self.config.connect_retry_delay);
                    }
                }
            }
        }
        Err(BackendError::Transport(format!(
            "could not open the USB tunnel connection to {address} after {attempts} attempts: {}. \
             Start the peer's MLRC ACCS session first; if the phone was plugged in after peer \
             discovery started, toggle peer discovery once so the adb tunnel rules are reapplied.",
            last_error
                .map(|error| error.to_string())
                .unwrap_or_else(|| "no connection detail was reported".to_owned())
        )))
    }

    pub fn send(&mut self, payload: &[u8]) -> Result<(), BackendError> {
        if payload.len() > self.config.max_frame_bytes {
            return Err(BackendError::FrameTooLarge {
                size: payload.len(),
                maximum: self.config.max_frame_bytes,
            });
        }
        if self.stream.is_none() {
            if self.listener.is_some() {
                return Err(BackendError::Transport(
                    "this USB tunnel session is the receiving end; start Transmit on the peer \
                     first so it connects over the tunnel"
                        .to_owned(),
                ));
            }
            self.next_stream()?;
        }
        let Some(stream) = self.stream.as_mut() else {
            return Err(BackendError::Transport(
                "the USB tunnel has no connection yet".to_owned(),
            ));
        };
        let prefix = (payload.len() as u32).to_be_bytes();
        let written = stream
            .write_all(&prefix)
            .and_then(|()| stream.write_all(payload));
        if let Err(error) = written {
            self.stream = None;
            self.reset_frame_state();
            return Err(BackendError::Io(error));
        }
        Ok(())
    }

    pub fn receive(&mut self) -> Result<Vec<u8>, BackendError> {
        if !self.next_stream()? {
            return Err(BackendError::Io(io::Error::from(
                io::ErrorKind::WouldBlock,
            )));
        }
        let max_frame_bytes = self.config.max_frame_bytes;
        let Self {
            stream,
            header,
            header_filled,
            frame,
            frame_filled,
            ..
        } = self;
        if stream.is_none() {
            return Err(BackendError::Io(io::Error::from(
                io::ErrorKind::WouldBlock,
            )));
        }

        let disconnected = |stream: &mut Option<TcpStream>,
                            header: &mut [u8; LENGTH_PREFIX_BYTES],
                            header_filled: &mut usize,
                            frame: &mut Vec<u8>,
                            frame_filled: &mut usize,
                            reason: String|
         -> BackendError {
            *stream = None;
            *header = [0; LENGTH_PREFIX_BYTES];
            *header_filled = 0;
            *frame_filled = 0;
            frame.clear();
            BackendError::Transport(reason)
        };

        while *header_filled < LENGTH_PREFIX_BYTES {
            let read_result = stream
                .as_mut()
                .expect("the stream presence was checked above")
                .read(&mut header[*header_filled..LENGTH_PREFIX_BYTES]);
            match read_result {
                Ok(0) => {
                    return Err(disconnected(
                        stream,
                        header,
                        header_filled,
                        frame,
                        frame_filled,
                        "the USB tunnel peer disconnected".to_owned(),
                    ));
                }
                Ok(read) => *header_filled += read,
                Err(error)
                    if matches!(
                        error.kind(),
                        io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut
                    ) =>
                {
                    // Partial state is preserved; the worker loop polls again.
                    return Err(BackendError::Io(error));
                }
                Err(error) => {
                    return Err(disconnected(
                        stream,
                        header,
                        header_filled,
                        frame,
                        frame_filled,
                        format!("the USB tunnel read failed: {error}"),
                    ));
                }
            }
        }

        if *frame_filled == 0 {
            let length = u32::from_be_bytes(*header) as usize;
            if length == 0 || length > max_frame_bytes {
                *stream = None;
                *header = [0; LENGTH_PREFIX_BYTES];
                *header_filled = 0;
                return Err(BackendError::Transport(format!(
                    "the USB tunnel peer announced an invalid frame length of {length}"
                )));
            }
            frame.clear();
            frame.resize(length, 0);
        }

        while *frame_filled < frame.len() {
            let read_result = stream
                .as_mut()
                .expect("the stream presence was checked above")
                .read(&mut frame[*frame_filled..]);
            match read_result {
                Ok(0) => {
                    return Err(disconnected(
                        stream,
                        header,
                        header_filled,
                        frame,
                        frame_filled,
                        "the USB tunnel peer disconnected mid-frame".to_owned(),
                    ));
                }
                Ok(read) => *frame_filled += read,
                Err(error)
                    if matches!(
                        error.kind(),
                        io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut
                    ) =>
                {
                    return Err(BackendError::Io(error));
                }
                Err(error) => {
                    return Err(disconnected(
                        stream,
                        header,
                        header_filled,
                        frame,
                        frame_filled,
                        format!("the USB tunnel read failed mid-frame: {error}"),
                    ));
                }
            }
        }

        let completed = std::mem::take(frame);
        *header = [0; LENGTH_PREFIX_BYTES];
        *header_filled = 0;
        *frame_filled = 0;
        Ok(completed)
    }
}

impl Transport for TunnelTransport {
    fn communication_type(&self) -> CommType {
        CommType::Usb
    }

    fn send(&mut self, frame: &[u8]) -> Result<(), BackendError> {
        TunnelTransport::send(self, frame)
    }

    fn receive(&mut self) -> Result<Vec<u8>, BackendError> {
        TunnelTransport::receive(self)
    }
}

#[cfg(test)]
mod tests {
    use std::time::Instant;

    use super::*;

    #[test]
    fn tunnel_transport_exchanges_a_frame_over_loopback() {
        let port = 38_477;
        let mut receiver = TunnelTransport::new(TunnelConfig {
            listen_port: Some(port),
            ..TunnelConfig::default()
        })
        .expect("listen transport");
        let mut sender = TunnelTransport::new(TunnelConfig {
            connect_address: Some(SocketAddr::from(([127, 0, 0, 1], port))),
            max_connect_attempts: 4,
            ..TunnelConfig::default()
        })
        .expect("connect transport");

        let frame = b"tunnel-frame-over-tcp";
        sender.send(frame).expect("send frame");

        let deadline = Instant::now() + Duration::from_secs(3);
        loop {
            match receiver.receive() {
                Ok(received) => {
                    assert_eq!(received, frame);
                    break;
                }
                Err(BackendError::Io(error))
                    if matches!(
                        error.kind(),
                        io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut
                    ) =>
                {
                    assert!(Instant::now() < deadline, "no frame arrived in time");
                }
                Err(error) => panic!("receive failed: {error}"),
            }
        }
    }
}

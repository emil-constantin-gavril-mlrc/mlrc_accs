mod ffi;
pub mod transport;

use std::error::Error;
use std::fmt;

use transport::{Transport, UdpConfig, UdpTransport};

#[cfg(feature = "usb")]
use transport::UsbBulkTransport;

#[derive(Debug)]
pub enum BackendError {
    Configuration(String),
    Io(std::io::Error),
    InvalidPacket(&'static str),
    FrameTooLarge {
        size: usize,
        maximum: usize,
    },
    Unsupported(String),
    Transport(String),
    WrongMode {
        required: OperationMode,
        actual: OperationMode,
    },
}

impl fmt::Display for BackendError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Configuration(message) => write!(formatter, "invalid configuration: {message}"),
            Self::Io(error) => write!(formatter, "I/O error: {error}"),
            Self::InvalidPacket(message) => {
                write!(formatter, "invalid transport packet: {message}")
            }
            Self::FrameTooLarge { size, maximum } => {
                write!(formatter, "frame size {size} exceeds maximum {maximum}")
            }
            Self::Unsupported(message) => write!(formatter, "unsupported operation: {message}"),
            Self::Transport(message) => write!(formatter, "transport error: {message}"),
            Self::WrongMode { required, actual } => {
                write!(
                    formatter,
                    "operation requires {required:?} mode, watcher is {actual:?}"
                )
            }
        }
    }
}

impl Error for BackendError {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        match self {
            Self::Io(error) => Some(error),
            _ => None,
        }
    }
}

impl From<std::io::Error> for BackendError {
    fn from(error: std::io::Error) -> Self {
        Self::Io(error)
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum OsType {
    Windows,
    Linux,
    Android,
    Ios,
    MacOs,
    Other,
}

impl OsType {
    pub fn current() -> Self {
        match std::env::consts::OS {
            "windows" => Self::Windows,
            "linux" => Self::Linux,
            "android" => Self::Android,
            "ios" => Self::Ios,
            "macos" => Self::MacOs,
            _ => Self::Other,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum OperationMode {
    Transmit,
    Receive,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CommType {
    Usb,
    Wifi,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CommPreference {
    Auto,
    Usb,
    Wifi,
}

pub struct WatcherConfig {
    pub mode: OperationMode,
    pub communication: CommPreference,
    pub usb: Option<transport::UsbConfig>,
    pub wifi: Option<UdpConfig>,
}

pub struct Watcher {
    mode: OperationMode,
    transport: Box<dyn Transport>,
    fallback_reason: Option<String>,
}

impl Watcher {
    pub fn new(config: WatcherConfig) -> Result<Self, BackendError> {
        let (transport, fallback_reason): (Box<dyn Transport>, Option<String>) =
            match config.communication {
                CommPreference::Wifi => (Box::new(open_wifi(config.wifi)?), None),
                CommPreference::Usb => (open_usb(config.usb)?, None),
                CommPreference::Auto => match config.usb {
                    Some(usb_config) => match open_usb(Some(usb_config)) {
                        Ok(transport) => (transport, None),
                        Err(usb_error) => {
                            let wifi = open_wifi(config.wifi)?;
                            (Box::new(wifi), Some(usb_error.to_string()))
                        }
                    },
                    None => (Box::new(open_wifi(config.wifi)?), None),
                },
            };

        Ok(Self {
            mode: config.mode,
            transport,
            fallback_reason,
        })
    }

    /// Wraps a ready-made transport (used by the FFI layer for the USB-over-
    /// adb tunnel, which has no vendor/product IDs to look up).
    #[doc(hidden)]
    pub fn with_transport(
        mode: OperationMode,
        transport: Box<dyn Transport>,
    ) -> Self {
        Self {
            mode,
            transport,
            fallback_reason: None,
        }
    }

    pub fn mode(&self) -> OperationMode {
        self.mode
    }

    pub fn communication_type(&self) -> CommType {
        self.transport.communication_type()
    }

    pub fn fallback_reason(&self) -> Option<&str> {
        self.fallback_reason.as_deref()
    }

    pub fn transmit(&mut self, frame: &[u8]) -> Result<(), BackendError> {
        if self.mode != OperationMode::Transmit {
            return Err(BackendError::WrongMode {
                required: OperationMode::Transmit,
                actual: self.mode,
            });
        }
        self.transport.send(frame)
    }

    pub fn receive(&mut self) -> Result<Vec<u8>, BackendError> {
        if self.mode != OperationMode::Receive {
            return Err(BackendError::WrongMode {
                required: OperationMode::Receive,
                actual: self.mode,
            });
        }
        self.transport.receive()
    }
}

fn open_wifi(config: Option<UdpConfig>) -> Result<UdpTransport, BackendError> {
    UdpTransport::new(config.ok_or_else(|| {
        BackendError::Configuration("Wi-Fi transport settings are required".to_owned())
    })?)
}

fn open_usb(config: Option<transport::UsbConfig>) -> Result<Box<dyn Transport>, BackendError> {
    let config = config.ok_or_else(|| {
        BackendError::Configuration("USB transport settings are required".to_owned())
    })?;

    #[cfg(feature = "usb")]
    {
        let transport = UsbBulkTransport::open(config)
            .map_err(|error| BackendError::Transport(error.to_string()))?;
        Ok(Box::new(transport))
    }

    #[cfg(not(feature = "usb"))]
    {
        let _ = config;
        Err(BackendError::Unsupported(
            "USB support was not enabled; rebuild with the `usb` feature".to_owned(),
        ))
    }
}

#[cfg(test)]
mod tests {
    use std::net::{IpAddr, Ipv4Addr, SocketAddr};

    use super::*;

    fn loopback_config(peer: SocketAddr) -> UdpConfig {
        UdpConfig {
            bind_address: SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), 0),
            peer_address: peer,
            ..UdpConfig::default()
        }
    }

    #[test]
    fn watcher_rejects_transmit_in_receive_mode() {
        let receiver = UdpTransport::new(loopback_config(SocketAddr::new(
            IpAddr::V4(Ipv4Addr::LOCALHOST),
            9,
        )))
        .unwrap();
        let mut watcher = Watcher {
            mode: OperationMode::Receive,
            transport: Box::new(receiver),
            fallback_reason: None,
        };

        assert!(matches!(
            watcher.transmit(b"frame"),
            Err(BackendError::WrongMode {
                required: OperationMode::Transmit,
                actual: OperationMode::Receive
            })
        ));
    }

    #[test]
    fn watcher_auto_uses_wifi_when_usb_is_not_configured() {
        let config = WatcherConfig {
            mode: OperationMode::Transmit,
            communication: CommPreference::Auto,
            usb: None,
            wifi: Some(loopback_config(SocketAddr::new(
                IpAddr::V4(Ipv4Addr::LOCALHOST),
                9,
            ))),
        };

        let watcher = Watcher::new(config).unwrap();
        assert_eq!(watcher.communication_type(), CommType::Wifi);
        assert!(watcher.fallback_reason().is_none());
    }

    #[test]
    fn watcher_auto_reports_usb_fallback_when_usb_is_unavailable() {
        let config = WatcherConfig {
            mode: OperationMode::Transmit,
            communication: CommPreference::Auto,
            usb: Some(transport::UsbConfig::default()),
            wifi: Some(loopback_config(SocketAddr::new(
                IpAddr::V4(Ipv4Addr::LOCALHOST),
                9,
            ))),
        };

        let watcher = Watcher::new(config).unwrap();
        assert_eq!(watcher.communication_type(), CommType::Wifi);
        #[cfg(not(feature = "usb"))]
        assert!(watcher.fallback_reason().unwrap().contains("USB support"));
    }
}

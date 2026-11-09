mod udp;

#[cfg(feature = "usb")]
mod usb;

pub use udp::{UdpConfig, UdpTransport};

#[cfg(feature = "usb")]
pub use usb::UsbBulkTransport;

use std::time::Duration;

use crate::BackendError;

pub trait Transport: Send {
    fn communication_type(&self) -> crate::CommType;
    fn send(&mut self, frame: &[u8]) -> Result<(), BackendError>;
    fn receive(&mut self) -> Result<Vec<u8>, BackendError>;
}

#[derive(Clone, Debug)]
pub struct UsbConfig {
    pub vendor_id: u16,
    pub product_id: u16,
    pub interface_number: u8,
    pub endpoint_in: u8,
    pub endpoint_out: u8,
    pub timeout: Duration,
    pub max_frame_bytes: usize,
}

impl Default for UsbConfig {
    fn default() -> Self {
        Self {
            vendor_id: 0,
            product_id: 0,
            interface_number: 0,
            endpoint_in: 0x81,
            endpoint_out: 0x01,
            timeout: Duration::from_secs(2),
            max_frame_bytes: 32 * 1024 * 1024,
        }
    }
}

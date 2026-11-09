use std::time::Duration;

use rusb::{DeviceHandle, GlobalContext};

use crate::{BackendError, CommType};

use super::{Transport, UsbConfig};

pub struct UsbBulkTransport {
    handle: DeviceHandle<GlobalContext>,
    interface_number: u8,
    endpoint_in: u8,
    endpoint_out: u8,
    timeout: Duration,
    max_frame_bytes: usize,
}

impl UsbBulkTransport {
    pub fn open(config: UsbConfig) -> Result<Self, rusb::Error> {
        if config.endpoint_in & 0x80 == 0
            || config.endpoint_out & 0x80 != 0
            || config.timeout.is_zero()
            || config.max_frame_bytes == 0
        {
            return Err(rusb::Error::InvalidParam);
        }

        let handle = rusb::open_device_with_vid_pid(config.vendor_id, config.product_id)
            .ok_or(rusb::Error::NoDevice)?;
        handle.claim_interface(config.interface_number)?;

        Ok(Self {
            handle,
            interface_number: config.interface_number,
            endpoint_in: config.endpoint_in,
            endpoint_out: config.endpoint_out,
            timeout: config.timeout,
            max_frame_bytes: config.max_frame_bytes,
        })
    }

    fn write_all(&self, mut bytes: &[u8]) -> Result<(), BackendError> {
        while !bytes.is_empty() {
            let written = self
                .handle
                .write_bulk(self.endpoint_out, bytes, self.timeout)
                .map_err(|error| BackendError::Transport(error.to_string()))?;
            if written == 0 {
                return Err(BackendError::Transport(
                    "USB bulk write made no progress".to_owned(),
                ));
            }
            bytes = &bytes[written..];
        }
        Ok(())
    }

    fn read_exact(&self, mut bytes: &mut [u8]) -> Result<(), BackendError> {
        while !bytes.is_empty() {
            let read = self
                .handle
                .read_bulk(self.endpoint_in, bytes, self.timeout)
                .map_err(|error| BackendError::Transport(error.to_string()))?;
            if read == 0 {
                return Err(BackendError::Transport(
                    "USB bulk read returned no data".to_owned(),
                ));
            }
            bytes = &mut bytes[read..];
        }
        Ok(())
    }
}

impl Transport for UsbBulkTransport {
    fn communication_type(&self) -> CommType {
        CommType::Usb
    }

    fn send(&mut self, frame: &[u8]) -> Result<(), BackendError> {
        if frame.len() > self.max_frame_bytes || frame.len() > u32::MAX as usize {
            return Err(BackendError::FrameTooLarge {
                size: frame.len(),
                maximum: self.max_frame_bytes.min(u32::MAX as usize),
            });
        }

        let mut header = [0_u8; 4];
        header.copy_from_slice(&(frame.len() as u32).to_be_bytes());
        self.write_all(&header)?;
        self.write_all(frame)
    }

    fn receive(&mut self) -> Result<Vec<u8>, BackendError> {
        let mut header = [0_u8; 4];
        self.read_exact(&mut header)?;
        let frame_len = u32::from_be_bytes(header) as usize;
        if frame_len > self.max_frame_bytes {
            return Err(BackendError::FrameTooLarge {
                size: frame_len,
                maximum: self.max_frame_bytes,
            });
        }

        let mut frame = vec![0_u8; frame_len];
        self.read_exact(&mut frame)?;
        Ok(frame)
    }
}

impl Drop for UsbBulkTransport {
    fn drop(&mut self) {
        let _ = self.handle.release_interface(self.interface_number);
    }
}

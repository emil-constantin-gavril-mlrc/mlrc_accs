use std::ffi::c_char;
use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::ptr;
use std::slice;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::mpsc::{self, Receiver, SyncSender, TryRecvError, TrySendError};
use std::thread::{self, JoinHandle};
use std::time::Duration;

use crate::transport::{TunnelConfig, TunnelTransport, UdpConfig};
use crate::{BackendError, CommPreference, OperationMode, Watcher, WatcherConfig};

const MAX_FRAME_BYTES: usize = 32 * 1024 * 1024;
const RECEIVE_TIMEOUT: Duration = Duration::from_millis(50);

pub struct FfiWatcher {
    outgoing: SyncSender<Vec<u8>>,
    incoming: Receiver<Result<Vec<u8>, String>>,
    stopped: Arc<AtomicBool>,
    acknowledged_bytes: Arc<AtomicUsize>,
    worker: Option<JoinHandle<()>>,
}

fn write_error(message: &str, buffer: *mut c_char, capacity: usize) {
    if buffer.is_null() || capacity == 0 {
        return;
    }

    let bytes = message.as_bytes();
    let copy_length = bytes.len().min(capacity - 1);
    unsafe {
        ptr::copy_nonoverlapping(bytes.as_ptr(), buffer.cast(), copy_length);
        *buffer.add(copy_length) = 0;
    }
}

fn deliver(
    incoming: &SyncSender<Result<Vec<u8>, String>>,
    mut message: Result<Vec<u8>, String>,
    stopped: &AtomicBool,
) {
    loop {
        match incoming.try_send(message) {
            Ok(()) | Err(TrySendError::Disconnected(_)) => return,
            Err(TrySendError::Full(returned)) => {
                if stopped.load(Ordering::Acquire) {
                    return;
                }
                message = returned;
                thread::sleep(Duration::from_millis(10));
            }
        }
    }
}

fn build_watcher(
    mode: OperationMode,
    local_port: u16,
    peer_ipv4: u32,
    peer_port: u16,
    comm: u32,
) -> Result<Watcher, BackendError> {
    let peer = Ipv4Addr::new(
        (peer_ipv4 >> 24) as u8,
        (peer_ipv4 >> 16) as u8,
        (peer_ipv4 >> 8) as u8,
        peer_ipv4 as u8,
    );
    if comm == 1 {
        // USB over the adb tunnel: the cable link is loopback TCP framed by
        // adbd, so the same wire format as the rusb bulk transport applies.
        let tunnel = TunnelConfig {
            listen_port: if mode == OperationMode::Receive {
                Some(local_port)
            } else {
                None
            },
            connect_address: if mode == OperationMode::Transmit {
                Some(SocketAddr::new(IpAddr::V4(peer), peer_port))
            } else {
                None
            },
            ..TunnelConfig::default()
        };
        let transport = TunnelTransport::new(tunnel)?;
        return Ok(Watcher::with_transport(mode, Box::new(transport)));
    }
    Watcher::new(WatcherConfig {
        mode,
        communication: CommPreference::Wifi,
        usb: None,
        wifi: Some(UdpConfig {
            bind_address: SocketAddr::new(IpAddr::V4(Ipv4Addr::UNSPECIFIED), local_port),
            peer_address: SocketAddr::new(IpAddr::V4(peer), peer_port),
            receive_timeout: RECEIVE_TIMEOUT,
            ..UdpConfig::default()
        }),
    })
}

fn run_worker(
    mut watcher: Watcher,
    mode: OperationMode,
    outgoing: Receiver<Vec<u8>>,
    incoming: SyncSender<Result<Vec<u8>, String>>,
    stopped: Arc<AtomicBool>,
    acknowledged_bytes: Arc<AtomicUsize>,
) {
    match mode {
        OperationMode::Transmit => {
            while !stopped.load(Ordering::Acquire) {
                match outgoing.recv_timeout(RECEIVE_TIMEOUT) {
                    Ok(frame) => {
                        if let Err(error) = watcher.transmit(&frame) {
                            deliver(&incoming, Err(error.to_string()), &stopped);
                            return;
                        }
                        acknowledged_bytes.fetch_add(frame.len(), Ordering::Relaxed);
                    }
                    Err(mpsc::RecvTimeoutError::Timeout) => {}
                    Err(mpsc::RecvTimeoutError::Disconnected) => return,
                }
            }
        }
        OperationMode::Receive => {
            while !stopped.load(Ordering::Acquire) {
                match watcher.receive() {
                    Ok(frame) => deliver(&incoming, Ok(frame), &stopped),
                    Err(BackendError::Io(error))
                        if matches!(
                            error.kind(),
                            std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut
                        ) => {}
                    Err(error) => {
                        deliver(&incoming, Err(error.to_string()), &stopped);
                        return;
                    }
                }
            }
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mlrc_watcher_start(
    mode: u32,
    local_port: u16,
    peer_ipv4: u32,
    peer_port: u16,
    comm: u32,
    output: *mut *mut FfiWatcher,
    error_buffer: *mut c_char,
    error_capacity: usize,
) -> i32 {
    if output.is_null() {
        write_error(
            "watcher output pointer is null",
            error_buffer,
            error_capacity,
        );
        return -1;
    }
    unsafe {
        *output = ptr::null_mut();
    }
    if peer_port == 0 {
        write_error("peer port must not be zero", error_buffer, error_capacity);
        return -1;
    }

    let mode = match mode {
        0 => OperationMode::Transmit,
        1 => OperationMode::Receive,
        _ => {
            write_error(
                "watcher mode must be 0 (transmit) or 1 (receive)",
                error_buffer,
                error_capacity,
            );
            return -1;
        }
    };
    if comm > 1 {
        write_error(
            "communication kind must be 0 (Wi-Fi UDP) or 1 (USB over adb tunnel)",
            error_buffer,
            error_capacity,
        );
        return -1;
    }
    let watcher = match build_watcher(mode, local_port, peer_ipv4, peer_port, comm) {
        Ok(watcher) => watcher,
        Err(error) => {
            write_error(&error.to_string(), error_buffer, error_capacity);
            return -1;
        }
    };

    let (outgoing_sender, outgoing_receiver) = mpsc::sync_channel(4);
    let (incoming_sender, incoming_receiver) = mpsc::sync_channel(4);
    let stopped = Arc::new(AtomicBool::new(false));
    let worker_stopped = Arc::clone(&stopped);
    let acknowledged_bytes = Arc::new(AtomicUsize::new(0));
    let worker_acknowledged_bytes = Arc::clone(&acknowledged_bytes);
    let worker = thread::spawn(move || {
        run_worker(
            watcher,
            mode,
            outgoing_receiver,
            incoming_sender,
            worker_stopped,
            worker_acknowledged_bytes,
        )
    });

    let handle = Box::new(FfiWatcher {
        outgoing: outgoing_sender,
        incoming: incoming_receiver,
        stopped,
        acknowledged_bytes,
        worker: Some(worker),
    });
    unsafe {
        *output = Box::into_raw(handle);
    }
    0
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mlrc_watcher_send(
    watcher: *mut FfiWatcher,
    data: *const u8,
    length: usize,
    error_buffer: *mut c_char,
    error_capacity: usize,
) -> i32 {
    if watcher.is_null() || data.is_null() {
        write_error(
            "watcher or frame pointer is null",
            error_buffer,
            error_capacity,
        );
        return -1;
    }
    if length > MAX_FRAME_BYTES {
        write_error(
            "frame exceeds the 32 MiB transport limit",
            error_buffer,
            error_capacity,
        );
        return -1;
    }

    let frame = unsafe { slice::from_raw_parts(data, length) }.to_vec();
    let watcher = unsafe { &*watcher };
    match watcher.outgoing.try_send(frame) {
        Ok(()) => 0,
        Err(TrySendError::Full(_)) => {
            write_error(
                "transmit queue is full; retry after polling",
                error_buffer,
                error_capacity,
            );
            -1
        }
        Err(TrySendError::Disconnected(_)) => {
            write_error("transmit worker has stopped", error_buffer, error_capacity);
            -1
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mlrc_watcher_acknowledged_bytes(watcher: *mut FfiWatcher) -> usize {
    if watcher.is_null() {
        return 0;
    }
    unsafe { &*watcher }
        .acknowledged_bytes
        .load(Ordering::Relaxed)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mlrc_watcher_poll(
    watcher: *mut FfiWatcher,
    output_data: *mut *mut u8,
    output_length: *mut usize,
    error_buffer: *mut c_char,
    error_capacity: usize,
) -> i32 {
    if watcher.is_null() || output_data.is_null() || output_length.is_null() {
        write_error(
            "watcher or frame output pointer is null",
            error_buffer,
            error_capacity,
        );
        return -1;
    }
    unsafe {
        *output_data = ptr::null_mut();
        *output_length = 0;
    }

    let watcher = unsafe { &*watcher };
    match watcher.incoming.try_recv() {
        Ok(Ok(frame)) => {
            let frame = frame.into_boxed_slice();
            unsafe {
                *output_length = frame.len();
                *output_data = Box::into_raw(frame) as *mut u8;
            }
            1
        }
        Ok(Err(error)) => {
            write_error(&error, error_buffer, error_capacity);
            -1
        }
        Err(TryRecvError::Empty) => 0,
        Err(TryRecvError::Disconnected) => {
            write_error("receive worker has stopped", error_buffer, error_capacity);
            -1
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mlrc_buffer_free(data: *mut u8, length: usize) {
    if !data.is_null() {
        let frame = ptr::slice_from_raw_parts_mut(data, length);
        unsafe {
            drop(Box::from_raw(frame));
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mlrc_watcher_stop(watcher: *mut FfiWatcher) {
    if watcher.is_null() {
        return;
    }

    let mut watcher = unsafe { Box::from_raw(watcher) };
    watcher.stopped.store(true, Ordering::Release);
    if let Some(worker) = watcher.worker.take() {
        let _ = worker.join();
    }
}

#[cfg(test)]
mod tests {
    use std::ffi::c_char;
    use std::net::UdpSocket;
    use std::thread;
    use std::time::{Duration, Instant};

    use super::*;

    fn unused_udp_port() -> u16 {
        UdpSocket::bind("127.0.0.1:0")
            .unwrap()
            .local_addr()
            .unwrap()
            .port()
    }

    #[test]
    fn ffi_watchers_exchange_a_frame_over_loopback() {
        let sender_port = unused_udp_port();
        let receiver_port = unused_udp_port();
        let mut error = [0 as c_char; 256];
        let mut sender = ptr::null_mut();
        let mut receiver = ptr::null_mut();

        assert_eq!(
            unsafe {
                mlrc_watcher_start(
                    0,
                    sender_port,
                    u32::from_be_bytes([127, 0, 0, 1]),
                    receiver_port,
                    0,
                    &mut sender,
                    error.as_mut_ptr(),
                    error.len(),
                )
            },
            0,
            "{}",
            unsafe { std::ffi::CStr::from_ptr(error.as_ptr()) }.to_string_lossy()
        );
        assert_eq!(
            unsafe {
                mlrc_watcher_start(
                    1,
                    receiver_port,
                    u32::from_be_bytes([127, 0, 0, 1]),
                    sender_port,
                    0,
                    &mut receiver,
                    error.as_mut_ptr(),
                    error.len(),
                )
            },
            0,
            "{}",
            unsafe { std::ffi::CStr::from_ptr(error.as_ptr()) }.to_string_lossy()
        );

        let frame = b"flutter-to-rust-over-udp";
        assert_eq!(
            unsafe {
                mlrc_watcher_send(
                    sender,
                    frame.as_ptr(),
                    frame.len(),
                    error.as_mut_ptr(),
                    error.len(),
                )
            },
            0
        );

        let deadline = Instant::now() + Duration::from_secs(2);
        let mut received = false;
        while Instant::now() < deadline {
            let mut data = ptr::null_mut();
            let mut length = 0;
            let result = unsafe {
                mlrc_watcher_poll(
                    receiver,
                    &mut data,
                    &mut length,
                    error.as_mut_ptr(),
                    error.len(),
                )
            };
            if result == 1 {
                let bytes = unsafe { slice::from_raw_parts(data, length) };
                assert_eq!(bytes, frame);
                unsafe { mlrc_buffer_free(data, length) };
                received = true;
                break;
            }
            assert_eq!(result, 0);
            thread::sleep(Duration::from_millis(10));
        }

        unsafe {
            mlrc_watcher_stop(sender);
            mlrc_watcher_stop(receiver);
        }
        assert!(received, "receiver did not receive the transmitted frame");
    }
}

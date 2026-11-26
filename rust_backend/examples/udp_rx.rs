// Example receiver: listens for complete reassembled frames from the peer
// address and prints each one. Timeouts are silent; real errors are logged.
// Usage: cargo run --release --example udp_rx -- <peer-ip:port> [local-port]
// Defaults to the fixed presence port 38421 on both ends.

use std::error::Error;
use std::io::ErrorKind;
use std::net::SocketAddr;

use mlrc_accs_backend::BackendError;
use mlrc_accs_backend::transport::{Transport, UdpConfig, UdpTransport};

const FIXED_PORT: u16 = 38421;

fn main() -> Result<(), Box<dyn Error>> {
    let mut args = std::env::args().skip(1);
    let Some(peer) = args.next().and_then(|value| value.parse().ok()) else {
        eprintln!("usage: udp_rx <peer-ip:port> [local-port, default {FIXED_PORT}]");
        std::process::exit(2);
    };
    let peer: SocketAddr = peer;
    let local_port: u16 = match args.next() {
        Some(value) => value.parse()?,
        None => FIXED_PORT,
    };

    let config = UdpConfig {
        bind_address: SocketAddr::from(([0, 0, 0, 0], local_port)),
        peer_address: peer,
        ..UdpConfig::default()
    };
    let mut transport = UdpTransport::new(config)?;
    println!(
        "udp_rx: bound {}, expecting frames from {peer} (Ctrl+C to stop)",
        transport.local_addr()?
    );

    loop {
        match transport.receive() {
            Ok(frame) => println!(
                "udp_rx: received frame ({} bytes, starts with {:?})",
                frame.len(),
                String::from_utf8_lossy(&frame[..frame.len().min(32)])
            ),
            Err(BackendError::Io(error))
                if matches!(error.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut) =>
            {
                // No complete frame yet; keep listening.
            }
            Err(error) => eprintln!("udp_rx: {error}"),
        }
    }
}

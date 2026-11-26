// Example sender: streams a synthetic ~200 KB frame once per second to the
// peer address, with the same ACK/retransmit behavior the app worker uses.
// Usage: cargo run --release --example udp_tx -- <peer-ip:port> [local-port]
// Defaults to the fixed presence port 38421 on both ends.

use std::error::Error;
use std::net::SocketAddr;
use std::thread::sleep;
use std::time::Duration;

use mlrc_accs_backend::transport::{Transport, UdpConfig, UdpTransport};

const FIXED_PORT: u16 = 38421;

fn main() -> Result<(), Box<dyn Error>> {
    let mut args = std::env::args().skip(1);
    let Some(peer) = args.next().and_then(|value| value.parse().ok()) else {
        eprintln!("usage: udp_tx <peer-ip:port> [local-port, default {FIXED_PORT}]");
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
        "udp_tx: bound {}, sending to {peer} (Ctrl+C to stop)",
        transport.local_addr()?
    );

    let mut sequence = 0_u32;
    loop {
        let frame = format!("MLRC-EXAMPLE-FRAME #{sequence}{}", "x".repeat(200_000));
        let frame = frame.into_bytes();
        transport.send(&frame)?;
        println!(
            "udp_tx: frame #{sequence} ({} bytes) acknowledged",
            frame.len()
        );
        sequence += 1;
        sleep(Duration::from_secs(1));
    }
}

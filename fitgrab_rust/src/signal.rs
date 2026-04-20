//! Signal handling for graceful shutdown.

use tokio::signal;

/// Setup SIGINT handler.
pub fn setup_sigint() {
    tokio::spawn(async {
        signal::ctrl_c()
            .await
            .expect("Failed to install Ctrl+C handler");
        println!();
        println!();
        println!("  ════════════════════════════════════════╗");
        println!("  ║  Interrupted — re-run to resume        ║");
        println!("  ════════════════════════════════════════╝");
        println!();
        std::process::exit(0);
    });
}

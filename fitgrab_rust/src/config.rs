//! Configuration constants for fitgrab.

/// User-agent pool rotated per browser context to avoid detection.
pub const USER_AGENTS: &[&str] = &[
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Mozilla/5.0 (X11; Linux x86_64; rv:127.0) Gecko/20100101 Firefox/127.0",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Safari/605.1.15",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:126.0) Gecko/20100101 Firefox/126.0",
];

/// Default UA used outside Stage 3.
pub const DEFAULT_USER_AGENT: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0";

// Rate-limit bypass constants
pub const MAX_ATTEMPTS: u32 = 5;
pub const COOLDOWN_AFTER_429: f64 = 20.0;
pub const BACKOFF_BASE: f64 = 3.0;
pub const BACKOFF_CAP: f64 = 60.0;

/// HTML substrings indicating rate limit.
pub const RATE_LIMIT_SIGNALS: &[&str] = &[
    "rate limit",
    "too many requests",
    "429",
    "please slow down",
    "try again later",
    "access denied",
];

/// Parallel browser contexts for Stage 3.
pub const DEFAULT_CONCURRENCY: usize = 2;

// aria2c configuration
pub const ARIA2_CONCURRENT: usize = 3;
pub const ARIA2_SPLIT: usize = 1;
pub const ARIA2_MIN_SPLIT: &str = "1M";
pub const ARIA2_FILE_ALLOCATION: &str = "none";
pub const ARIA2_RETRY_WAIT: u32 = 5;
pub const ARIA2_MAX_TRIES: u32 = 6;
pub const ARIA2_TIMEOUT: u32 = 60;
pub const ARIA2_CONNECT_TIMEOUT: u32 = 15;

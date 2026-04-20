#!/usr/bin/env node
/**
 * fitgrab-playwright-helper — Browser automation for fitgrab Rust.
 * 
 * Handles stages 1-3:
 *   Stage 1+2: FitGirl page → PrivateBin paste → FF links
 *   Stage 3: Resolve each FF page → direct CDN URL
 * 
 * Input: JSON via stdin or CLI args
 * Output: JSON to stdout
 * 
 * Usage:
 *   node index.js '{"url": "...", "concurrency": 2}'
 *   echo '{"url": "..."}' | node index.js
 */

const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

// Optional stealth mode
let stealthAsync = null;
try {
  stealthAsync = require('playwright-stealth').stealth_async;
} catch (e) {
  // stealth not available
}

// ── Constants ────────────────────────────────────────────────────────────────

const USER_AGENTS = [
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0",
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
  "Mozilla/5.0 (X11; Linux x86_64; rv:127.0) Gecko/20100101 Firefox/127.0",
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Safari/605.1.15",
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:126.0) Gecko/20100101 Firefox/126.0",
];

const DEFAULT_USER_AGENT = USER_AGENTS[0];

const MAX_ATTEMPTS = 5;
const COOLDOWN_AFTER_429 = 20;
const BACKOFF_BASE = 3.0;
const BACKOFF_CAP = 60.0;

const RATE_LIMIT_SIGNALS = [
  "rate limit",
  "too many requests",
  "429",
  "please slow down",
  "try again later",
  "access denied",
];

const DEFAULT_CONCURRENCY = 2;

// ── Utilities ──────────────────────────────────────────────────────────────────

function jitteredBackoff(attempt) {
  const ceiling = Math.min(BACKOFF_BASE * Math.pow(2, attempt), BACKOFF_CAP);
  return Math.random() * ceiling;
}

function randomChoice(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// ── Stage 1+2: Get FF links from game page or paste URL ───────────────────────

async function getFFLinks(gameUrl, context, pasteUrl = null) {
  const page = await context.newPage();
  let title = 'fitgirl_download';
  let ffLinks = [];

  try {
    if (pasteUrl) {
      // Direct paste URL provided
      console.error('  → Detected direct paste URL, skipping game page…');
    } else {
      // Stage 1: Load game page
      console.error('  → Loading game page…');
      await page.goto(gameUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });

      // Extract title
      const titleEl = await page.$('h1.entry-title') || await page.$('h1');
      if (titleEl) {
        title = await titleEl.innerText();
      } else {
        // Fallback: extract from URL
        title = gameUrl.split('/').filter(s => s).pop().replace(/-/g, ' ');
      }

      // Find PrivateBin paste URL for FuckingFast
      pasteUrl = await page.$$eval('a[href*="paste.fitgirl-repacks.site"]', (els) => {
        for (const el of els) {
          const li = el.closest('li');
          if (li && li.textContent.includes('FuckingFast')) {
            return el.href;
          }
        }
        return els.length ? els[0].href : null;
      });

      if (!pasteUrl) {
        console.error('  ✗  No paste.fitgirl-repacks.site link found on game page.');
        return { title, links: [] };
      }
    }

    // Stage 2: Load PrivateBin paste
    console.error(`  → Loading paste (PrivateBin, decrypting via JS)…`);
    console.error(`    ${pasteUrl}`);
    await page.goto(pasteUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });

    try {
      await page.waitForSelector('a[href*="fuckingfast.co"]', { timeout: 15000 });
    } catch (e) {
      console.error('  ✗  Paste page did not render FF links within 15s.');
      console.error('     Possible causes: wrong paste URL, PrivateBin JS failed,');
      console.error('     or the paste requires a password.');
      return { title, links: [] };
    }

    // Extract unique FF links
    ffLinks = await page.$$eval('a[href*="fuckingfast.co"]', (els) => {
      const set = new Set(els.map(e => e.href));
      return [...set];
    });

    // If we started with a direct paste URL, try to extract game name from first link
    if (title === 'fitgirl_download' && ffLinks.length > 0) {
      const match = ffLinks[0].match(/fuckingfast\.co\/[^/]+\/([^/]+?)(?:___|_part\d+)/);
      if (match) {
        title = match[1].replace(/_/g, ' ');
      }
    }

    return { title, links: ffLinks };

  } finally {
    await page.close();
  }
}

// ── Stage 3: Resolve FF URL → direct CDN URL ──────────────────────────────────

async function resolveFFUrl(page, ffUrl, idx, total, attempt = 0) {
  const label = `[${String(idx).padStart(2, '0')}/${String(total).padStart(2, '0')}]`;

  if (attempt > 0) {
    const wait = jitteredBackoff(attempt - 1);
    console.error(`  ${label}  ↻  attempt ${attempt + 1}/${MAX_ATTEMPTS}  (backing off ${wait.toFixed(1)}s…)`);
    await sleep(wait);
  }

  try {
    await page.goto(ffUrl, { waitUntil: 'networkidle', timeout: 25000 });

    // Check for rate limit signals
    const html = await page.content();
    const htmlLower = html.toLowerCase();
    for (const sig of RATE_LIMIT_SIGNALS) {
      if (htmlLower.includes(sig)) {
        console.error(`  ${label}  ⚠  Rate-limit signal detected`);
        return '__RATE_LIMITED__';
      }
    }

    // Wait for Alpine.js to render
    await page.waitForTimeout(Math.floor(Math.random() * 2000) + 2500);

    // Debug: surface button state on first attempt
    if (attempt === 0) {
      const debugInfo = await page.evaluate(() => {
        const buttons = Array.from(document.querySelectorAll('button'));
        return {
          count: buttons.length,
          sample: buttons.slice(0, 6).map(b => ({
            text: b.textContent.trim().slice(0, 50),
            classes: b.className,
            visible: b.offsetParent !== null
          }))
        };
      });
      if (debugInfo.count === 0) {
        console.error(`  ${label}  DEBUG: No buttons found; saving HTML snapshot…`);
        const snapPath = `/tmp/fitgrab_debug_${idx}.html`;
        fs.writeFileSync(snapPath, html);
        console.error(`  ${label}  DEBUG: ${snapPath}`);
      }
    }

    // Click download button and capture download
    const [download] = await Promise.all([
      page.waitForEvent('download', { timeout: 18000 }),
      page.evaluate(() => {
        const buttons = Array.from(document.querySelectorAll('button'));
        const btn = buttons.find(b =>
          b.textContent.toUpperCase().includes('DOWNLOAD') ||
          b.classList.contains('link-button') ||
          b.classList.contains('gay-button')
        );
        if (btn) {
          btn.click();
          return { found: true, text: btn.textContent.trim().slice(0, 30) };
        }
        return { found: false, count: buttons.length };
      })
    ]);

    // Get URL and cancel download
    const url = download.url();
    await download.cancel();

    const fname = url.split('/').pop().split('?')[0] || ffUrl.split('#').pop().slice(0, 40);
    console.error(`  ${label}  ✓  ${fname}`);
    return url;

  } catch (e) {
    if (e.name === 'TimeoutError') {
      console.error(`  ${label}  ✗  Timeout (attempt ${attempt + 1})`);
      return '__RETRY__';
    }
    console.error(`  ${label}  ✗  ${e.message || e}`);
    return '__RETRY__';
  }
}

// ── Stage 3: Resolve all FF URLs with parallel workers ─────────────────────────

async function resolveAll(ffLinks, concurrency) {
  const queue = [];
  for (let i = 0; i < ffLinks.length; i++) {
    queue.push({ idx: i, url: ffLinks[i], attempt: 0 });
  }

  const results = new Array(ffLinks.length).fill(null);
  const total = ffLinks.length;

  const browser = await chromium.launch({
    headless: true,
    args: [
      '--no-sandbox',
      '--disable-gpu',
      '--disable-dev-shm-usage',
      '--disable-blink-features=AutomationControlled',
      '--disable-web-security',
      '--disable-features=IsolateOrigins,site-per-process',
    ],
  });

  const semaphore = { count: concurrency, waiters: [] };

  async function acquire() {
    if (semaphore.count > 0) {
      semaphore.count--;
      return;
    }
    await new Promise(resolve => semaphore.waiters.push(resolve));
  }

  function release() {
    semaphore.count++;
    if (semaphore.waiters.length > 0) {
      const next = semaphore.waiters.shift();
      next();
    }
  }

  async function worker(workerId) {
    while (true) {
      const item = queue.shift();
      if (!item) break;

      const { idx, url, attempt } = item;

      await acquire();

      try {
        // Create fresh context per attempt
        const ua = randomChoice(USER_AGENTS);
        const context = await browser.newContext({
          userAgent: ua,
          acceptDownloads: true,
          viewport: {
            width: Math.floor(Math.random() * 640) + 1280,
            height: Math.floor(Math.random() * 360) + 720,
          },
        });

        // Block media to speed up
        await context.route(/\.(png|jpg|jpeg|gif|webp|svg|woff2?|ttf|mp4)(\?.*)?$/i, route => route.abort());

        const page = await context.newPage();

        // Apply stealth if available
        if (stealthAsync) {
          await stealthAsync(page);
        }

        const result = await resolveFFUrl(page, url, idx + 1, total, attempt);

        await page.close();
        await context.close();

        if (result === '__RATE_LIMITED__') {
          if (attempt < MAX_ATTEMPTS - 1) {
            const cooldown = COOLDOWN_AFTER_429 + Math.random() * 10;
            console.error(`  [worker-${workerId}]  ❄  Cooling ${cooldown.toFixed(0)}s before retry…`);
            await sleep(cooldown * 1000);
            queue.push({ idx, url, attempt: attempt + 1 });
          } else {
            console.error(`  [${String(idx + 1).padStart(2, '0')}/${String(total).padStart(2, '0')}]  ✗  Gave up after ${MAX_ATTEMPTS} attempts (rate limit)`);
          }
        } else if (result === '__RETRY__') {
          if (attempt < MAX_ATTEMPTS - 1) {
            queue.push({ idx, url, attempt: attempt + 1 });
          } else {
            console.error(`  [${String(idx + 1).padStart(2, '0')}/${String(total).padStart(2, '0')}]  ✗  Gave up after ${MAX_ATTEMPTS} attempts`);
          }
        } else if (result) {
          results[idx] = result;
        }

      } finally {
        release();
      }
    }
  }

  // Start workers
  const workers = [];
  for (let i = 0; i < concurrency; i++) {
    workers.push(worker(i));
  }
  await Promise.all(workers);

  await browser.close();

  return results.filter(r => r);
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main(input) {
  const { url, concurrency = DEFAULT_CONCURRENCY } = input;

  console.error('\n  ╔═══════════════════════════════════════╗');
  console.error('  ║   fitgrab  —  FitGirl speed loader    ║');
  console.error('  ╚═══════════════════════════════════════╝\n');

  let directPasteUrl = null;
  if (url.includes('paste.fitgirl-repacks.site')) {
    directPasteUrl = url;
  }

  // Stage 1+2: Get FF links
  const browser = await chromium.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-gpu'],
  });

  const context = await browser.newContext({ userAgent: DEFAULT_USER_AGENT });
  const { title, links: ffLinks } = await getFFLinks(url, context, directPasteUrl);
  await context.close();
  await browser.close();

  if (!ffLinks.length) {
    console.error('\n  ✗  No FuckingFast links found. Check the game URL.\n');
    return { title, links: [] };
  }

  console.error(`\n  ✓  Game  : ${title}`);
  console.error(`  ✓  Parts : ${ffLinks.length}`);

  // Stage 3: Resolve FF URLs
  console.error(`\n  → Resolving ${ffLinks.length} URLs (${concurrency} parallel contexts)…\n`);

  const directUrls = await resolveAll(ffLinks, concurrency);

  console.error(`\n  ✓  Resolved : ${directUrls.length}/${ffLinks.length}`);
  const failed = ffLinks.length - directUrls.length;
  if (failed) {
    console.error(`  ✗  Failed   : ${failed}  (re-run fitgrab to retry)`);
  }

  return { title, links: directUrls };
}

// ── Entry point ───────────────────────────────────────────────────────────────

async function run() {
  let input;

  // Read input from stdin or CLI arg
  if (process.argv.length > 2) {
    try {
      input = JSON.parse(process.argv[2]);
    } catch (e) {
      console.error('Failed to parse CLI argument as JSON');
      process.exit(1);
    }
  } else {
    // Read from stdin
    let data = '';
    for await (const chunk of process.stdin) {
      data += chunk;
    }
    try {
      input = JSON.parse(data);
    } catch (e) {
      console.error('Failed to parse stdin as JSON');
      process.exit(1);
    }
  }

  if (!input.url) {
    console.error('Missing "url" in input');
    process.exit(1);
  }

  try {
    const result = await main(input);
    // Output result as JSON to stdout (for Rust to parse)
    console.log(JSON.stringify(result));
  } catch (e) {
    console.error(`Fatal error: ${e.message}`);
    process.exit(1);
  }
}

run();

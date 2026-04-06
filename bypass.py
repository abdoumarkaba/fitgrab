import random
import asyncio
from playwright.async_api import TimeoutError as PWTimeout

# ── Rotating UA pool ──────────────────────────────────────────────────────────

USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Mozilla/5.0 (X11; Linux x86_64; rv:127.0) Gecko/20100101 Firefox/127.0",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0",
]

# ── Backoff helper ────────────────────────────────────────────────────────────

def jittered_backoff(attempt: int, base: float = 3.0, cap: float = 60.0) -> float:
    """
    Full-jitter exponential backoff.
    attempt=0 → 0–3s, attempt=1 → 0–6s, attempt=2 → 0–12s … capped at 60s.
    Full jitter (random in [0, exponential_ceiling]) is empirically better
    than equal jitter at distributing load spikes.
    """
    ceiling = min(base * (2 ** attempt), cap)
    return random.uniform(0, ceiling)


# ── Revised Stage 3 ───────────────────────────────────────────────────────────

MAX_ATTEMPTS = 5          # per URL across the retry queue
COOLDOWN_AFTER_429 = 20  # seconds to pause the whole worker on hard rate-limit

RATE_LIMIT_SIGNALS = [
    "rate limit", "too many requests", "429",
    "please slow down", "try again later",
]


async def resolve_ff_url(page, ff_url: str, idx: int, total: int,
                         attempt: int = 0) -> str | None:
    """
    Single-tab URL resolution with per-attempt jittered backoff.
    `attempt` is carried in from the retry queue so backoff widens globally,
    not just within a single tab's local loop.
    """
    label = f"[{idx:02d}/{total:02d}]"

    # Pre-request delay — widens with each retry
    if attempt > 0:
        wait = jittered_backoff(attempt - 1)
        print(f"  {label}  ↻  attempt {attempt + 1}/{MAX_ATTEMPTS}  "
              f"(waiting {wait:.1f}s…)")
        await asyncio.sleep(wait)

    try:
        await page.goto(ff_url, wait_until="networkidle", timeout=25_000)

        html = await page.content()
        if any(sig in html.lower() for sig in RATE_LIMIT_SIGNALS):
            print(f"  {label}  ⚠  Rate-limited — backing off…")
            return "__RATE_LIMITED__"   # sentinel; caller re-queues

        # Give Alpine.js time to render — varies with server load
        await page.wait_for_timeout(random.randint(2500, 4500))

        async with page.expect_download(timeout=18_000) as dl_info:
            clicked = await page.evaluate("""() => {
                const btn = Array.from(document.querySelectorAll('button')).find(b =>
                    b.textContent.toUpperCase().includes('DOWNLOAD') ||
                    b.classList.contains('link-button') ||
                    b.classList.contains('gay-button')
                );
                if (btn) { btn.click(); return {found: true, text: btn.textContent.trim()}; }
                return {found: false};
            }""")

        if not clicked.get("found"):
            print(f"  {label}  ✗  Download button not found")
            return None

        dl = await dl_info.value
        url = dl.url
        await dl.cancel()

        fname = url.split("/")[-1].split("?")[0] or ff_url.split("#")[-1][:40]
        print(f"  {label}  ✓  {fname}")
        return url

    except PWTimeout:
        print(f"  {label}  ✗  Timeout")
        return "__RETRY__"
    except Exception as e:
        print(f"  {label}  ✗  {e}")
        return None


async def resolve_all(ff_links: list[str], concurrency: int) -> list[str]:
    """
    Resolves FF links with a persistent retry queue.
    Failed URLs re-enter the queue (up to MAX_ATTEMPTS) rather than being
    silently dropped. Rate-limited URLs trigger a full-worker cooldown.
    """
    # Each item: (original_index, url, attempt_number)
    queue: asyncio.Queue = asyncio.Queue()
    for i, url in enumerate(ff_links):
        await queue.put((i, url, 0))

    results: list[str | None] = [None] * len(ff_links)
    total = len(ff_links)
    sem = asyncio.Semaphore(concurrency)

    async with async_playwright() as pw:
        browser = await pw.chromium.launch(
            headless=True,
            args=[
                "--no-sandbox",
                "--disable-gpu",
                "--disable-dev-shm-usage",
                "--disable-blink-features=AutomationControlled",
                "--disable-web-security",
            ],
        )

        async def worker(worker_id: int):
            while True:
                try:
                    idx, url, attempt = queue.get_nowait()
                except asyncio.QueueEmpty:
                    break

                async with sem:
                    # Each tab gets its own UA and a randomised viewport
                    ua = random.choice(USER_AGENTS)
                    context = await browser.new_context(
                        user_agent=ua,
                        accept_downloads=True,
                        viewport={
                            "width": random.randint(1280, 1920),
                            "height": random.randint(720, 1080),
                        },
                    )
                    await context.route(
                        re.compile(r"\.(png|jpg|jpeg|gif|webp|svg|woff2?|ttf|mp4)(\?.*)?$"),
                        lambda r: r.abort(),
                    )
                    page = await context.new_page()

                    if STEALTH_AVAILABLE and stealth_async:
                        await stealth_async(page)

                    result = await resolve_ff_url(page, url, idx + 1, total, attempt)

                    await page.close()
                    await context.close()

                    if result == "__RATE_LIMITED__":
                        if attempt < MAX_ATTEMPTS - 1:
                            # Cool the entire worker down before re-queuing
                            cooldown = COOLDOWN_AFTER_429 + random.uniform(0, 10)
                            print(f"  [worker-{worker_id}]  ❄  Cooling {cooldown:.0f}s…")
                            await asyncio.sleep(cooldown)
                            await queue.put((idx, url, attempt + 1))
                        else:
                            print(f"  [{idx+1:02d}/{total:02d}]  ✗  Gave up after {MAX_ATTEMPTS} attempts")
                    elif result == "__RETRY__":
                        if attempt < MAX_ATTEMPTS - 1:
                            await queue.put((idx, url, attempt + 1))
                        else:
                            print(f"  [{idx+1:02d}/{total:02d}]  ✗  Gave up after {MAX_ATTEMPTS} attempts")
                    elif result:
                        results[idx] = result

                queue.task_done()

        workers = [asyncio.create_task(worker(i)) for i in range(concurrency)]
        await asyncio.gather(*workers)
        await browser.close()

    return [r for r in results if r]
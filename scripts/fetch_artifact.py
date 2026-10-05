"""Fetch the Claude artifact iframe HTML and write it to index.html (used by GitHub Actions)."""
import sys
from playwright.sync_api import sync_playwright

URL = "https://claude.ai/artifact/KsWnh4DMA3Dps7ED5SumU8"
MIN_SIZE = 1_000_000
MARKER = "IM Camp"


def fetch():
    with sync_playwright() as p:
        b = p.chromium.launch(headless=False,
                              args=["--disable-blink-features=AutomationControlled"])
        try:
            ctx = b.new_context(user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
                                viewport={"width": 1366, "height": 768})
            page = ctx.new_page()
            page.goto(URL, wait_until="domcontentloaded", timeout=60000)
            page.wait_for_timeout(25000)
            print("TITLE:", page.title())
            for f in page.frames:
                print("FRAME", f.url[:100])
                if "claudeusercontent.com" in f.url:
                    return f.content()
        finally:
            b.close()
    return None


def main():
    for attempt in range(3):
        try:
            html = fetch()
        except Exception as e:
            print("error:", e)
            html = None
        if html and len(html) >= MIN_SIZE and MARKER in html:
            open("index.html", "w", encoding="utf-8", newline="").write(html)
            print("OK", len(html))
            return 0
        print("attempt", attempt + 1, "invalid")
    print("FAILED")
    return 1


if __name__ == "__main__":
    sys.exit(main())

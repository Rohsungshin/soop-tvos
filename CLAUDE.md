# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

tvOS app (Apple TV) for watching [SOOP Live](https://www.sooplive.com/) (formerly 아프리카TV) streams natively via AVPlayer. The app bypasses WKWebView (unavailable on tvOS) and calls SOOP's HTTP APIs directly.

**Target**: tvOS 17.0+, Xcode 16+, Swift 5

## Build Commands

```bash
# Regenerate Xcode project from project.yml (required after project.yml changes)
xcodegen generate

# Validate .env + regenerate + build for simulator
./build.sh

# Build manually for simulator
xcodebuild \
  -project soop-app.xcodeproj \
  -scheme soop-app \
  -destination "platform=tvOS Simulator,name=Apple TV 4K (3rd generation)" \
  -configuration Debug build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
```

Open `soop-app.xcodeproj` in Xcode and run to the simulator or a real Apple TV.

## Credentials Setup

Create `.env` (gitignored) before building:
```
SOOP_ID=your_id
SOOP_PASSWORD=your_password
# Optional: manually inject session cookies to bypass OAuth flows
SOOP_COOKIES=_au=xxx; AuthTicket=yyy; UserTicket=zzz
```

The `scripts/copy-env.sh` pre-build script copies `.env` into the app bundle. `SOOPAPIClient` reads it at runtime via `Bundle.main.path(forResource: ".env", ofType: nil)`.

## Architecture

### Entry Point & Navigation
- **`AppDelegate`** — Creates `RootTabBarController` as root, then triggers `SOOPAPIClient.shared.login()` in the background to populate session cookies.
- **`RootTabBarController`** — 3-tab layout: LIVE → `LiveCategoriesViewController`, 탐색 → `ExploreViewController` (placeholder), MY → `MyViewController`.

### Data Layer: `SOOPAPIClient` (singleton)
All SOOP network calls go through this class. Key APIs:
- `login()` — POST to `login.sooplive.co.kr/app/LoginAction.php`. On success, `AuthTicket`/`UserTicket` cookies land in `HTTPCookieStorage.shared`.
- `fetchCategories()` — paginated fetch from `sch.sooplive.com/api.php?m=categoryList` (up to 7 pages × 100 categories).
- `fetchBroadcasts(byCategory:)` — `sch.sooplive.com/api.php?m=categoryContentsList` for live broadcasts in a category.
- `fetchFavorites()` — `myapi.sooplive.co.kr/api/favorite` (requires login cookies).
- `fetchStreamInfo(bjId:broadNo:)` — multi-step stream resolution:
  1. Bootstraps session cookies by visiting homepage + play page.
  2. POSTs to `live.sooplive.com/afreeca/player_live_api.php` to get stream metadata + TS URL.
  3. Fetches AID token (second POST with `type=aid`).
  4. Fetches `view_url` from `livestream-manager.sooplive.com/broad_stream_assign.html`.
  5. Returns `StreamInfo` with primary URL (TS with embedded token) and fallback URL (`view_url+?aid=`).
- `sanitizeJSONBytes(_:)` — strips control characters (0x00–0x1F except \n \r \t) from SOOP responses before JSON parsing. **Always use this before parsing SOOP API responses.**

### UI Layer
- **`LiveCategoriesViewController`** — Grid of categories (320×240 cards, 5 columns). Play/Pause remote button refreshes. Selects → pushes `LiveListViewController`.
- **`LiveListViewController`** — Grid of live broadcasts for a chosen category (380×290 cards, 4 columns). Selects → calls `fetchStreamInfo` → presents `PlayerViewController` full-screen.
- **`MyViewController`** — Grid of favorited BJs. Live ones show LIVE badge; offline ones show alert instead of playing.
- **`PlayerViewController`** — Wraps `AVPlayerViewController`. On `.failed` status, automatically tries fallback URL (`timeShiftURL`). Injects SOOP cookies and `Referer`/`Origin` headers via `AVURLAssetHTTPHeaderFieldsKey`.

### `CategoryDirectory`
Hardcoded BJID pools per category, scraped from SOOP's category pages (which use client-side rendering and can't be fetched natively). Used as input to `fetchLiveListForBJIDs()` for the older polling approach. The newer `fetchBroadcasts(byCategory:)` via `sch.sooplive.com` API doesn't need this.

## Key Design Constraints

- **No WKWebView on tvOS** — all content is fetched via `URLSession` and rendered natively.
- **Cookie-based auth** — login stores cookies in `HTTPCookieStorage.shared`; all subsequent API calls reuse them automatically. `SOOP_COOKIES` in `.env` allows manual cookie injection for non-password auth flows.
- **Stream URL strategy** — SOOP restricts 1080p to subscribers. Non-subscribers get master HLS with HD(540p)+SD(360p) variants. TS URLs carry embedded auth tokens; `view_url+aid` is the fallback. `PlayerViewController` handles automatic fallback on play failure.
- **project.yml excludes** — several files (`ViewController.swift`, `iOSViewController.swift`, `OverlayView.swift`, `TVBrowserViewController.swift`, `LoginManager.swift`, `CategoryDirectory.swift`, `main.swift`) are excluded from the build target. They are kept as reference/legacy code.
# CLAUDE.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.

# PRODUCT.md — Velora Design System & Brand Direction

> Maintained by `kb-ui` (`ui-ux-designer` role) following the Impeccable doctrine (`~/.kobean/references/design/impeccable-taste.md`). Read this before building or modifying any surface in `Sources/Velora/` or `scripts/generate-icon.swift`.

## 1. Product Identity & Audience
- **Kind of Product:** Native macOS Pro Media Extraction & Conversion Studio (`yt-dlp` + `ffmpeg` + `deno`).
- **Primary User & Context:** macOS developers, video editors, creators, and power users on macOS Sonoma/Sequoia (`1440x900` to `5K` Retina displays, both Light & Dark system appearances) who expect native Apple-grade polish (on par with Final Cut, Raycast, Linear, and Downie 4) combined with transparent CLI control.
- **Voice & Tone:** Plain, crisp, technical, zero marketing fluff. Status labels state exact actions and counts (`Downloading 64%`, `Verified SHA-256`, `Muxing MP4`), never filler copy.
- **Design Mode:** `Default (Impeccable Craft — M2 · Apple Gallery Minimalist Cobalt)`

## 2. Typography Scale & Pairing
- **UI Headings & Chrome:** Native `SF Pro` (`.system`), never `.rounded` inside URL inputs, badges, or primary buttons.
  - **Window / View Title:** `.title3.weight(.semibold)` (`16pt`)
  - **Card / Section Heading:** `.headline` (`13pt semibold`)
  - **Body / Control Label:** `.subheadline` / `.body` (`12pt–13pt regular/medium`)
  - **Caption / Metadata:** `.caption` (`11pt`) — reserve `.caption2` (`10pt`) strictly for high-contrast pill badges (`>= 4.5:1`).
- **Monospace / Technical Data:** `SF Mono` (`.system(..., design: .monospaced)`) for URL inputs, CLI previews, format IDs, SHA-256 digests, file paths, and live logs.
- **Numeric Discipline (`tabular-nums` Mandatory):** Every badge, percentage, download speed, ETA, byte size, duration, view count, stepper label, version string, and queue counter MUST apply `.monospacedDigit()` to prevent horizontal jitter during 10Hz live updates.

## 3. Semantic Color Tokens (Adaptive Light & Dark — WCAG 2.2 AA Verified)
Implemented via `NSColor(name: nil) { appearance in ... }` inside `VeloraTheme.swift` and wired at the root window via `.tint(VeloraTheme.accent)` so sidebar selection, native pop-up chevrons, toggles, and primary CTAs share **one cohesive accent hue**:

| Token | Light Mode (`aqua`) | Dark Mode (`darkAqua`) | Contrast / Purpose |
| :--- | :--- | :--- | :--- |
| **`ground`** | `#F9FAFC` (Apple Gallery Alabaster) | `#0E1014` (Calm Obsidian) | Root canvas background |
| **`surfaceElevated`** | `#FFFFFF` (Soft gallery shadow) | `#161920` (`1px` `#FFFFFF` `@ 6%`) | Floating Spotlight command bar, cards, modals |
| **`surfaceSubtle`** | `#F0F2F6` | `#1D212B` | Segmented pills, preset chips, code blocks, skeletons |
| **`inkPrimary`** | `#0F172A` (`>= 15:1`) | `#F4F6FA` (`>= 14:1`) | Primary titles, active inputs, filenames |
| **`inkSecondary`** | `#64748B` (`>= 4.7:1`) | `#8B95A7` (`>= 6.1:1`) | Subtitles, metadata, form labels |
| **`accent` (Fill)** | `#3B49DF` (White text `6.8:1`) | `#5B6CFF` (White text `5.1:1`) | Primary Download pill, active tab/chip tint, root `.tint` |
| **`accentText`** | `#313ECB` (`7.5:1` on card) | `#8C98FF` (`6.7:1` on card) | Selected preset labels, subtle cobalt badges |
| **`success`** | `#0E7A4E` (`5.3:1`) | `#34D399` (`8.9:1`) | Verified engine/checksum, completed status, success toast |
| **`warning`** | `#B45309` (`5.0:1`) | `#FBBF24` (`10.4:1`) | Missing optional `ffmpeg`/JS runtime, paused/retrying |
| **`danger`** | `#C81E1E` (`5.9:1`) | `#F87171` (`6.7:1`) | Missing `yt-dlp`, failed task, error toast, destructive actions |
| **`info`** | `#0369A1` (`5.9:1`) | `#38BDF8` (`8.5:1`) | Live speed/ETA telemetry, playlist progress |

## 4. Layout, Control Sizing & Motion Rules
- **Approved Layout Architecture (`M2 · Apple Gallery`):** Zero sidebar; centered floating segmented top navigation pill (`Studio | Queue | History | Presets`) with right-aligned engine status dot and update pill; centered `680pt` gallery canvas featuring the floating rounded Spotlight Hero Command Pill, whisper preset capsule + 6 whisper-quiet preset chips, clean borderless Media Preview slot, collapsed-by-default Apple-Settings `All Download Options` disclosure preserving 100% of features, and quiet hairline Recent Activity strip underneath.
- **Spacing Grid:** `4pt` / `8pt` base scale (`24pt` vertical canvas rhythm, `16pt` surface padding, `12pt`–`16pt` corner radius on surfaces, `9999pt` capsule pills).
- **Control Sizing (No 650pt Stretched Pickers):** Apple System Settings hairline grouped rows with right-aligned compact controls (`<= 220pt` max width) inside `All Download Options`.
- **Motion Rules:** `150ms–200ms` `.snappy` / `.easeOut` transitions; strictly gated by `@Environment(\.accessibilityReduceMotion)` (instant state swap when enabled).

## 5. Project-Specific Anti-Patterns (Hard Bans)
- **NEVER** use neon violet-to-cyan gradients (`#7D5CFF -> #21D4ED`) on buttons, badges, or cards.
- **NEVER** render white text over low-contrast cyan/amber fills (`< 4.5:1` is a hard gate failure).
- **NEVER** allow more than 1 primary brand accent color alongside semantic status indicators.
- **NEVER** ship an async surface without all 4 states: `loading` (`CLS = 0` skeleton), `empty` (`ContentUnavailableView`), `error` (with `Retry` / contextual fix), and `populated`.
- **NEVER** ship an icon-only button or custom `.plain` button without `.accessibilityLabel`, `>= 24x24pt` target frame, hover state, and `:focus-visible` keyboard focus ring.

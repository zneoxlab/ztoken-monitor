# Website Design QA

## Comparison target

- User desktop captures: `/Users/xiaozhou/Pictures/ztmonitor/电脑端/` (8 PNG files).
- User mobile captures: `/Users/xiaozhou/Pictures/ztmonitor/手机端/` (4 JPEG files).
- Final desktop hero: `/private/tmp/zt-monitor-actual-home-desktop.png` (`1440 × 1000`).
- Final feature section: `/private/tmp/zt-monitor-actual-features.png` (`1440 × 1000`).
- Final mobile hero: `/private/tmp/zt-monitor-actual-home-mobile.png` (`390 × 844`).
- Final mobile showcase: `/private/tmp/zt-monitor-actual-mobile-showcase.png` (`390 × 844`).

## Screenshot fidelity

- All 12 user captures were copied into `website/assets/screenshots/` without recompression or synthetic reconstruction.
- The hero desktop scene uses the real horizontal usage dashboard plus the real desktop Home widget.
- The hero mobile scene uses the real Overview, Tool details, Limits, and Devices captures in a four-state animated stack.
- Core feature sections now use the matching real captures for Home, limits, tools, models, sessions, trends, devices, and Hub settings.
- The source captures and final browser screenshots were inspected together. Product details, colors, typography, and internal screen composition are preserved.

## First-screen clarity

- The slogan and lead explain that ZT Monitor monitors AI-tool tokens, cost, cache hits, and account limits across desktop and mobile.
- macOS, Windows, Linux, Android, HarmonyOS, and iOS are all visible in the hero as a stable two-row platform grid.
- Android and HarmonyOS are marked beta and expose QR-code application panels. iOS is visibly planned and cannot be downloaded.
- The current-device CTA still resolves the appropriate desktop asset from the latest GitHub Release.

## Motion and responsive behavior

- Desktop and mobile product modes still rotate automatically and remain manually switchable.
- The four mobile captures rotate every 3.2 seconds with restrained depth, opacity, and position transitions; their tabs support direct selection.
- Reduced-motion users receive static transitions and no automatic capture rotation.
- At `1440px` and `390px`, document width equals viewport width and no horizontal overflow is present.
- On mobile, the six platform entries remain visible in a `2 × 3` grid and the real product images scale without cropping outside the page.

## Interaction and runtime checks

- Android QR open state: `is-open = true`, `aria-expanded = true`.
- The Android download QR resolves to the current deployment base plus `downloads/ZT-Monitor-Android.apk`; the direct link uses the same path and `download="ZT-Monitor-Android.apk"`.
- The Android popover includes both a `142 × 142` download QR and the supplied community QR at the `390 × 844` viewport without horizontal overflow.
- HarmonyOS uses the supplied `联系我们.png` community QR and explicitly asks users to add the note `zt monitor`.
- The mobile capture navigation updates `aria-selected`, the active figure, and the stack positions.
- All hero and feature images loaded at their expected natural dimensions.
- The footer shows `© 2026 智纪探索 版权所有`, the ICP record, and the public-security record with the supplied badge; both record links resolve to the requested official query sites.
- `npm run lint` passed.

## Findings

- No actionable P0, P1, or P2 visual differences remain.
- The Android and HarmonyOS QR destinations still point to platform-specific GitHub beta application pages until final distribution links are available.

## Implementation checklist

- [x] Real desktop captures replace previous marketing mockups.
- [x] Real mobile captures replace the hand-built phone demonstration.
- [x] Mobile has multiple images and subtle motion.
- [x] All six platform entries are visible in the hero.
- [x] Android and HarmonyOS QR interactions work on desktop and mobile.
- [x] Android scans directly to the fixed APK path and also exposes the community QR.
- [x] HarmonyOS scans to the community contact QR with the required note.
- [x] iOS remains planned-only.
- [x] Core features use matching real screenshots.
- [x] Desktop and mobile layouts have no horizontal overflow.
- [x] Copyright, ICP, and public-security records are readable and responsive in the footer.

final result: passed

## Unreleased

- Add `resetZoom`, the zoom Ctrl/Command+0 goes back to, for apps that
  restore a saved zoom through `initialZoom`.
- Take Ctrl/Command+wheel from the raw pointer data so that scrollables and
  other wheel listeners under the cursor no longer swallow the zoom.
- Report the zoomed logical size through MediaQuery so breakpoints follow it.
- Paint each zoom step at once and lay the content out again only when the
  wheel pauses (`reflowDelay`, 150 ms by default), so zooming stays smooth in
  apps that are costly to lay out.
- Zoom with trackpad pinches (Windows precision touchpads, macOS): zoom at the
  start of the pinch × its scale. Widgets below keep the two-finger pan but
  no longer receive the pinch scale.
- Move Ctrl/Command+wheel by `zoomStep` per full wheel notch (100 engine units,
  the Windows and Chromium default) and proportionally for the small deltas of
  high-resolution wheels and touchpads, instead of one step per event. Web
  Ctrl+wheel scale signals follow the same rule.

## 0.1.0

- Add app-wide Ctrl/Command+wheel and scale-event zoom.
- Keep the Flutter viewport filled at every configured zoom level.
- Add Ctrl/Command+0 reset and configurable zoom bounds.

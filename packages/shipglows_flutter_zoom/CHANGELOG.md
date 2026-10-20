## Unreleased

- Take Ctrl/Command+wheel from the raw pointer data so that scrollables and
  other wheel listeners under the cursor no longer swallow the zoom.
- Report the zoomed logical size through MediaQuery so breakpoints follow it.
- Paint each zoom step at once and lay the content out again only when the
  wheel pauses (`reflowDelay`, 150 ms by default), so zooming stays smooth in
  apps that are costly to lay out.

## 0.1.0

- Add app-wide Ctrl/Command+wheel and scale-event zoom.
- Keep the Flutter viewport filled at every configured zoom level.
- Add Ctrl/Command+0 reset and configurable zoom bounds.

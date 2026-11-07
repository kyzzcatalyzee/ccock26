# CCock26
iOS 26 style control center for iOS 15-16 (based on CCock18 by pawxed, modified by zilvyn)

What is different from CCock18:
- iOS 26 look by default (round modules, edit mode on)
- Media page: the progress bar and the volume bar can be dragged, like the real player
- Edit mode: "Add a Control" button (hold the background to enter edit mode) to bring back a removed module
- Bouncy page change
- Edit mode: "+" under the page dots adds a new page for modules, the layers button jumps to the next page
- Connectivity (2x2, 4x4, 4x6) and Now Playing (2x2, 4x2, 4x4, 4x6) can be resized in edit mode and get big layouts:
  one card per toggle for Connectivity, artwork / seek bar / transport / volume for Music
- Pages you add and leave empty are removed when you leave edit mode
- A new control goes to the first free spot (top left first); when every page is full a new page is opened
- Works with LiquidAss: corner radius follows LiquidAss, so resizing back keeps the glass shape

known issue:
- causes respring loop in some devices
- prone to tweak conflict

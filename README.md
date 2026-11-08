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

## 0.3.4
- Add a Control: Connectivity and Music Player that are already on a page are now **added as a second copy** (4x4 Connectivity, 4x2 Music Player) instead of being moved. Copies can be removed with the minus button; they cannot be resized or dragged. Reset Layout removes them.

## 0.3.5
- Adding Music Player while a new page is shown always adds the 4x2 copy. Connectivity adds the 4x4 copy once the real Connectivity is on the grid.

## 0.3.6
- Big Connectivity now follows the iOS 26 layout: Airplane Mode as a wide pill on top, Wi-Fi / AirDrop / Cellular / Bluetooth as square cards, Personal Hotspot as a pill at the bottom.

## 0.3.7
- Big Connectivity always shows all six tiles. Cellular Data or Personal Hotspot missing on the device stay dimmed and cannot be pressed.

## 0.4.0
- Crash log: Settings > CCock26 > Crash Log shows /var/mobile/Library/Preferences/ccock26-crash.log. A crash adds the reason, the last steps and a backtrace. Copy / Clear buttons included.

## 0.4.1
- Fix: SpringBoard crashed (safe mode) when Control Center opened with a big Connectivity / Music Player: Apple's code sent `caAnimationContainerView` to the overlay view. The overlay now answers it. Found with the crash log.

## 0.4.2
- Copies are repositioned after Apple's layout pass, can be resized (drag the corner handle, snaps to the allowed sizes), and write what they are doing to the crash log for debugging.

## 0.4.3
- The built-in music page and the paw (promo) page are removed. Pages of your own now start right after page 1, and saved layouts are moved up once on first start.
- A page of your own gets its pager icon from what is on it: antenna for Connectivity, music note for Music Player, dot otherwise.

## 0.4.4
- Big Connectivity tiles and the big Music Player use the same material as the stock controls (so LiquidAss can style them). The module background behind big Connectivity is hidden, so the tiles float on their own.

## 0.4.5
- Swipe up on the controls to go to the next page, swipe down to come back (down on the first page still closes Control Center). The page follows your finger and lands with the same springy jelly slide as the pager. Sliders are left alone.
- Big Music Player: material view gets the panel's corner radius.

## 0.4.6
- Page swipe has its own mechanism: the pages follow your finger (rubber band at the ends), no shrinking of Control Center, and a jelly wobble when the page lands. The pager icons are left alone while swiping.
- Big Music Player on the real module no longer covers the stock material, so LiquidAss styles it like the other controls. A second copy still brings its own material.

## 0.4.7
- Page swipe: the layout pass no longer snaps the page back to its rest spot while you drag (the page used to jump back / stay half way under the header blur).
- Big Music Player: material is built exactly like the old built-in music page (recipe 4, weight 1, group `ccMediaPlayer`), which LiquidAss already styles.

## 0.4.8
- The blur strip under the status bar (header material) is hidden on every page.

## 0.4.9
- Page swipe: Apple's own pull-down-to-close pans are switched off while a page swipe runs, so Control Center and the status bar no longer get pulled down (which made the pager icons disappear).

## 0.4.10
- Page swipe: Apple's pull-down-to-close pans now have to wait for the page swipe (instead of being switched off half way), so the panel and status bar are not dragged. What they are is written to the crash log.

## 0.4.11
- Page swipe: found in Control26 that Control Center's own overlay scroll view is what pulls the panel down. Its pan now waits for the page swipe and is held off while a page swipe runs.

## 0.4.12
- Big Music Player gets LiquidAss the way the old music page did: a LiquidAss glass layer behind it (from PACCLIQ), replacing the plain material.
- Off the first page the overlay scroll view is switched off, so a swipe down can no longer start Apple's pull-to-close (it dragged the panel and status bar). On the first page it stays on, so closing works there.

## 0.4.13
- Reverted switching off the panel scroll view (it stopped swiping on added pages). While swiping, the scroll view is pinned at rest instead.

## 0.4.14
- Page swipe now listens on the whole panel window, so it works on pages with few controls (empty space used to ignore touches).

## 0.4.15
- Swipe diagnostics in the crash log (touch view, why a swipe did not begin).

## 0.4.16
- A cancelled swipe now still picks the page (it used to snap back when started on a stock button); easier thresholds; end-of-swipe log line.

## 0.4.17
- Slow swipes cancelled by the system right after starting now still change page, by their direction.

## 0.4.18
- Page swipe reworked after ControlCenter26: it lives on the panel view, is exclusive (Apple pans wait for it), and only takes touches in the middle band (not the top 60pt or bottom 110pt).

## 0.4.19
- Ships its own PrivateSymbols.bundle (from ControlCenter26) so the iOS 26 Connectivity glyph is used for the Connectivity page icon.

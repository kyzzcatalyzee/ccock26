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

## 0.4.20
- Page swipe back to the earlier behaviour (no touch band, not exclusive). Pager icon for Connectivity back to the antenna.

## 0.4.21
- Page swipe like ControlCenter26 again (middle band only, exclusive), without the scroll-pan suspension.

## 0.4.22
- Big Connectivity: the AirDrop card uses the iOS 26 private Connectivity glyph.

## 0.4.23
- Page swipe: Apple pans wait for it through the delegate (like ControlCenter26) from the first touch.

## 0.4.24
- Cellular uses the cellularbars glyph like ControlCenter26; the globe tile falls back to the system "network" symbol and tries every copy of the private symbols.

## 0.4.25
- The small Connectivity control now shows the ControlCenter26 glyphs (cellular bars, bluetooth, hotspot) on Apple's own mini buttons.

## 0.4.26
- Small Connectivity keeps Apple's Bluetooth glyph. The expanded Connectivity panel now shows the CCock26 layout. The big layout has a VPN pill under Hotspot, the globe moved to VPN, and AirDrop and Bluetooth use drawn Apple-style marks.

## 0.4.27
- Page swipe slides without overshoot; the jelly wobble is a bit taller; less rubber band at the ends.

## 0.4.28
- Expanded Connectivity: no plate behind it, same size and look as the big Connectivity on a page.
- No bounce anywhere when changing page; tapping a pager icon now gives the same jelly as the swipe. The pager icon no longer pulses.

## 0.4.30
- Tapping a pager icon now ends in the same jelly as the swipe. Expanded Connectivity hides every plate behind it.

## 0.4.31
- Expanded Connectivity: LiquidAss's LGLiveBackdropView plate behind the cards is hidden.

## 0.4.32
- Expanded Connectivity: provides its own platter (as ControlCenter26 does), so no plate is drawn behind the cards.

## 0.4.33
- Expanded Connectivity: Apple's chrome around the panel is stripped on every container layout (the way ControlCenter26 does it) and restored afterwards.

## 0.5.4
The PACCLIQ glass no longer needs LiquidAss. With LiquidAss off or not installed, the controls use a built-in glass (blur, saturation, a light tint) with the same specular and edge layers. When LiquidAss is on, nothing changes.

## 0.5.3
- Everything named ccock18 is now ccock26 (package id, tweak and prefs bundle names, files, preferences domain pawxed.ccock26.preferences). Because the domain changed, saved settings start fresh. All // comments were removed from the source.

## 0.5.2
- The first-install Connectivity and Music Player pages start at 4x6.

## 0.5.1
- First install: Control Center starts with two pages of its own, a Connectivity page (4x6) and a Music Player page (4x6), like the old built-in pages. They are normal pages, so each one disappears when its control is removed. Only on a fresh install (no saved layout); an existing setup is left alone.
- Page indicator: more space between the icons (39 to 50 pt).

## 0.5.0
- Music 2x2: back to our own tile, with the exact numbers of Control26's compact player (art 56, AirPlay bubble 42, title 14.5 semibold, transport at 84% height, 46 pt spacing). The MRU hooks are off.

## 0.4.99
- Music 2x2 is Apple's own view again (as in ControlCenter26), laid out like iOS 26 by hooks on MRUNowPlayingView / MRUNowPlayingHeaderView / MRUArtworkView / MRUNowPlayingTransportControlsView: large rounded artwork top left, round AirPlay button top right, title under the artwork, wide transport row. AirPlay works because it is Apple's button. The own 2x2 tile from 0.4.98 is no longer used for the module (only for stand-alone copies).

## 0.4.98
- Music at 2x2 now uses our own tile in the iOS 26 layout: large rounded artwork top left, an AirPlay bubble top right, a bold title and a wide transport row (previous / next dim while nothing plays). The AirPlay bubble is only a look for now.

## 0.4.97
- Empty-cell circles: on a page without any module the grid top now comes from a module of another page (it started too high, under the status bar), and the circles are removed as soon as edit mode ends.

## 0.4.96
- Edit mode: every free cell of the page you are on (page 0 and the pages you added) shows a faint circle, so you can see where a control fits.

## 0.4.95
- Edit mode (LiquidAss on): the outline sits right on the module edge (no gap); the remove button keeps its white fill again (with the thin rim and dark edge on top); the resize handle is back to the glass-bubble look.

## 0.4.94
- Edit mode: the module outline is back to its own look (no LiquidAss specular). The remove button loses its white fill and shows only the LiquidAss rim over a dark edge; the rim is thinner (0.6 pt) on the remove button and the resize handle, and both get the dark edge (3D look, glass mode only).

## 0.4.93
- LiquidAss: when a module that holds our controls (a real Music / Connectivity module made bigger) already has LiquidAss's own LGLiveBackdropView, the PACCLIQ glass is not built (and removed if present), so the two no longer double up.

## 0.4.92
- Edit mode: the resize handle, the remove (minus) button and the module outline take the LiquidAss rim: mode (none / border / glass), opacity and Specular Type (iOS 26 / iOS 27) from the LiquidAss settings. Without LiquidAss the old look stays.

## 0.4.91
- Expanded Connectivity: the module glass behind the panel is hidden again (the grey backdrop came back in 0.4.77-0.4.90).
- LiquidAss Specular Type (More Options > Extra stuff, Renderer.SpecularType): PACCLIQ follows it. iOS 26 = diagonal light (-135 degrees, LiquidAss's rest angle); iOS 27 = a horizontal bright band with the 12 alpha stops read from LiquidAss. The iOS 27 vibrance layer is not reproduced.

## 0.4.90
- LiquidAss: custom controls and the Music page use the PACCLIQ glass again (not LGLiveBackdropView). PACCLIQ now follows LiquidAss: the .rN radius step and .dark filter type like LiquidAss, the scale budget, the rim (none / border / glass) with its opacity and Fresnel strength, and the Control Center blur, all read from the LiquidAss settings.
- Page indicator: the plain-page dot is smaller; the add-page button is an open ring (circle) instead of "+" and sits a little higher.

## 0.4.89
- Page indicator icons now follow ControlCenter26: the music page uses the bundled "music" symbol (SF music.note as fallback) instead of a hand-drawn note, and a plain page is a filled dot (circle.fill) instead of an open ring.

## 0.4.88
- LiquidAss: the radius lock also covers glass layers that fill only the width or only the height of a module (e.g. the 346x108 glass inside Now Playing, which was skipped and snapped back when held).

## 0.4.87
- LiquidAss: the glass shape (radius 38) is now locked for as long as Control Center is open, not only for a moment after a resize, so it no longer snaps back when a control is held/pressed.

## 0.4.86
- Diagnostics: one second after adding a copy, the log gets a "copy tree" of the new control (class, frame, radius per subview); [PACBig] lines now carry a timestamp.

## 0.4.85
- LiquidAss: custom controls create LGLiveBackdropView with the base ControlCenter type "dylv.liquidglass.cc" (LiquidAss appends the .rN radius step itself). With ".r2" the lens filter never resolved, which is why the glass looked dark/flat. Specular mode (iOS 27 / 26 / none), blur and the other Control Center settings now follow LiquidAss automatically.

## 0.4.84
- LiquidAss: PACCLIQGlassView is never created or kept while LiquidAss's LGLiveBackdropView class exists.

## 0.4.83
- LiquidAss: the Now Playing / Music page (CCAMediaPlayerView) now gets the real LGLiveBackdropView instead of PACCLIQGlassView.

## 0.4.82
- LiquidAss: every card of the custom Connectivity page and the custom toggles now use the real LGLiveBackdropView too (old material removed), not only the Music control.

## 0.4.81
- Music control copy on a new page: the LiquidAss glass lens is rebuilt when the page becomes visible and when the card enters a window (it was built while hidden and stayed empty).

## 0.4.80
- Music control copy: uses LiquidAss LGLiveBackdropView whenever that class exists (no longer depends on the PACCLIQ probe); logs the layout state.

## 0.4.79
- Music control: logs (ccock26-crash.log, [PACBig]) whether the LiquidAss glass view could be created and is live.

## 0.4.78
- LiquidAss: the custom Music control now uses a real LiquidAss LGLiveBackdropView (ControlCenter filter), the same as the modules. The old material and our PACCLIQ glass are removed.

## 0.4.77
- LiquidAss: the custom Music control uses LiquidAss's own glass again (same look as the modules); our older PACCLIQ glass is removed. The big Connectivity page keeps the LiquidAss glass behind it instead of stripping it.

## 0.4.76
- LiquidAss: the custom Music control no longer keeps its old material (and the extra glass LiquidAss built on it); only the one glass layer is used.

## 0.4.75
- LiquidAss: the glass radius fix now runs every frame for one second after each resize step, so the right shape shows at once instead of after a few seconds.

## 0.4.74
- LiquidAss: the opened (long-press) panel glass, which sits outside the module container, gets the same corner radius as the rest instead of a full pill.

## 0.4.73
- LiquidAss glass fix is also applied directly after each resize resync (not only through hooks); logs the wide glass layers and their radius after the fix.

## 0.4.72
- LiquidAss glass fix: no longer skips glass under a slider class (the log of 0.4.71 showed it only ran for 2x2); logs why a pill glass is skipped.

## 0.4.71
- LiquidAss glass fix: a method the class only inherits is added to that class instead of changing UIView for every view.

## 0.4.70
- LiquidAss: the radius fix also runs after the glass's updateSpecular, which LiquidAss calls each time it sets a radius, so it cannot put the pill back between layouts.

## 0.4.69
- LiquidAss: after the radius is corrected, the glass is told to rebuild its lens (updateSpecular / applyFilters), as LiquidAss does itself. The first fixes are written to the log.

## 0.4.68
- LiquidAss: glass layers inset from the module (7.5pt) are matched by size ratio, and the glass lays out again after its radius changes.

## 0.4.67
- LiquidAss: the radius fix also runs after the module container's layout and covers the inset glass layers, so the extra pill-shaped material is rounded like the rest.

## 0.4.66
- LiquidAss: every control size keeps the corner of a 1x1 control (LiquidAss alone makes wide / tall ones into pills). The glass and the edit outline use the same radius.

## 0.4.65
- LiquidAss: found the cause in its source: it rounds the glass from the module's current bounds on every layout, so an animated resize shows in-between sizes as pills. Now a resize or move is laid out in one step with LiquidAss (no animated bounds), so the glass gets its final shape at once. Per-frame glass lock removed.

## 0.4.64
- Fix build error (undeclared PACLockGlassShape): one glass-lock path only.

## 0.4.63
- LiquidAss: while resizing, its glass is locked every frame to the module's outline (same size, same corner radius), so it follows the edge and cannot bend.

## 0.4.62
- LiquidAss: resizing now works like Control26: every size step and the final size run Control Center's relayout in one spring animation.

## 0.4.61
- LiquidAss: the edit outline takes its corner radius from the control's size, not from the changing layer, so it no longer turns into a circle or pill by mistake.

## 0.4.60
- LiquidAss: resizing a control no longer animates the modules, so the glass cannot bend.

## 0.4.59
- LiquidAss: glass is kept hidden every frame during a resize (LiquidAss kept bringing it back), then fades in.

## 0.4.58
- LiquidAss: a resize also runs Control Center's own relayout inside one spring animation, the way Control26 does it.

## 0.4.57
- LiquidAss: the glass of every module is hidden while a resize animates (it bent into diamonds) and fades back in when all modules have settled.

## 0.4.56
- Diagnostics: the glass dump after a resize now lists every visible module (size, radius, glass views), not only the resized one.

## 0.4.55
- Diagnostics: after a resize with LiquidAss active, the view tree of the resized module and its glass (class, frame, radius) is written to ccock26-crash.log (first 6 resizes per launch).

## 0.4.54
- LiquidAss: CCock26 no longer writes corner radii into the modules' layers while LiquidAss is active (Control26 never does either); Control Center and LiquidAss follow every size natively, so the glass stays the right shape after a resize. Removed the forced glass resize of 0.4.53.

## 0.4.53
- LiquidAss: after a resize the module's own LiquidAss glass is put back on the module's current size and radius, so it no longer stays 1x1 or bends into a diamond.

## 0.4.52
- Reverted the glass hiding during resize (0.4.51): it did not help and the white tiles next to a resized module stayed diamond shaped.

## 0.4.51
- LiquidAss: the glass of a module is hidden while the module changes size (it bent into a diamond / octagon) and fades back in once it has settled.

## 0.4.50
- The lower-case duplicate name on Wi-Fi / Cellular / Bluetooth / Hotspot modules came from the resize title of CCock26 itself; our own modules are now left alone by it.
- Edit mode: outlines, minus buttons and resize rings left behind by removed or replaced controls are swept away while editing, not only when leaving edit mode.

## 0.4.49
- Modules: also look for the stray name label inside the module's own view, and write a one-time view-tree dump of the first wide module to ccock26-crash.log (to find where that label comes from).

## 0.4.48
- Wide Wi-Fi / Cellular / Bluetooth / Hotspot modules: the second, lower-case name label drawn by Control Center is hidden.

## 0.4.47
- Wi-Fi / Cellular / Bluetooth / Hotspot modules: the 2x1 size is the pill again (round glyph on the left, name and On/Off on the right).
- Fix: resize handle, minus button and outline staying on screen after leaving edit mode (leftovers whose module was replaced are swept away).

## 0.4.46
- Modules (Wi-Fi, Cellular, Bluetooth, Hotspot): adopt Control Center's module protocols at load so they are accepted and drawn.

## 0.4.45
- Build fix: unused variable in the module bundles (Bluetooth, Hotspot).

## 0.4.44
- Wi-Fi, Cellular Data, Bluetooth and Hotspot are real Control Center modules now (bundles in modules/, like SiriPlusCC). They show up in Settings > Control Center and in Add a Control. They press the real Connectivity button, so Connectivity has to stay on the grid.
- The earlier built-in copies of these four are gone from the Add a Control list.

## 0.4.43
- New control: Silent Mode (like RingerToggle): bell glyph, orange with a slashed bell when silent; works on its own, no Connectivity needed.

## 0.4.41
- The 2x1 Wi-Fi / Cellular / Bluetooth / Hotspot pill shows its name and status again.

## 0.4.40
- New controls of our own: Wi-Fi, Cellular Data, Bluetooth and Hotspot, each as a round control (1x1, or a pill at 2x1) you add from "Add a Control". They press the real Connectivity buttons, so the Connectivity module has to stay on the grid.

## 0.4.39
- Edit mode: the square box behind the resize handle is gone (translucent arc only).
- Holding the page icons: same dim grey / white colours as at rest.
- Page icons: the plain-page ring is a little smaller; the music page uses two beamed notes.
- "Add a Control" sits lower.

## 0.4.38
- Edit mode: the 3D look is redone as plain translucent, no liquid glass: thin soft rim on the controls, translucent minus button and resize handle, light shadows.
- Page icons: the selected page is white, the others a dim grey; a plain page is an open ring.

## 0.4.37
- Edit mode: the outline of every control is a glass bubble now (bright rim on the upper left, darker rim underneath, soft inner glow, drop shadow) for the 3D look.

## 0.4.36
- Edit mode: soft drop shadow under the minus button and the resize handle (3D look).
- Edit mode: "Add a Control" is smaller and sits lower, so it no longer touches the last row.

## 0.4.36
- Edit mode: "Add a Control" is smaller (text 14pt, height 36) and sits lower so it no longer covers the last row of controls.
- Edit mode: the page "+" button is a plain white glyph without backdrop.

## 0.4.35
- Edit mode: the remove (minus) button and the resize handle are small liquid-glass pieces now (LiquidAss glass, thin light rim, white minus).
- Edit mode: "Add a Control" and "Reset Layout" have no backdrop any more, only icon and text.
- Edit mode: the layers button beside "Add a Control" is removed.

## 0.4.34
- Plate behind the big and expanded Connectivity hidden the way Control26 does it: an empty layer mask on material/backdrop views of the module size, up to 8 levels up.

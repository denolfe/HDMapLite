# HD Map Lite

High-resolution world map art for WoW: Forever, with nothing else.

- **World, Kalimdor, Eastern Kingdoms:** the stitched HD tiles from the
  *High Fidelity World Map: Art* pack (`HighFidelityWorldMap_Art_Forever`).
- **53 outdoor zones:** the client's own minimap tiles, laid out as the zone map
  (the "satellite" view).
- **Fog of war, on every map:** the HD art appears only where you've explored,
  cut to the same torn edges as Blizzard's reveal art. Unexplored ground shows
  the stock map.
  - **Zone maps** reveal the zone itself and the neighbouring zones visible at
    its edges, each by its own exploration.
  - **Continent and world maps** reveal every zone on them the same way.
  - Cities and battlegrounds have no fog in the stock UI either, so their zone
    maps are drawn in full. On the continent they show through their
    surrounding zone's reveal.
- **Area names on zone maps:** towns, capitals, subzones and the districts of
  Stormwind, Orgrimmar, Thunder Bluff and Darnassus, in gold with a black
  outline, since the HD art covers the names painted on the stock map.
  Under fog a name appears once its spot is explored, like the stock map's.
  Names keep a steady size on screen while you zoom (they spread apart rather
  than grow), which keeps the text crisp instead of shimmering.
- **Player halo:** a soft dark disc under your arrow so it stands out on the
  busier HD art. It follows you while the map is open.
- **Everything else** (dungeons, caves, Ironforge, Undercity, battlegrounds
  without data): Blizzard's stock map, untouched.

No options, SavedVariables, slash commands, keybinds or globals. To turn it
off, disable the addon.

## Why it shouldn't conflict

It adds one frame of its own to the map canvas (with a child layer for each
of the last three maps drawn) and draws into it. It never
hides, moves, re-levels, hooks or writes a field on anything of Blizzard's.

| High Fidelity World Map does | HD Map Lite |
|---|---|
| Hides Blizzard's detail layers and tiles; hooks `Show`/`SetShown`/`RefreshDetailTiles` on them and writes `_hfwmHooked` onto them | Covers them with an opaque backdrop instead |
| Hides the map frame's backing textures (`MapFrameBg`) | Not needed |
| Sets exploration pins to alpha 0 and re-levels them every frame from an `OnUpdate` | Puts its frame one level above the exploration pins (a read-only lookup) |
| `hooksecurefunc` on `WorldMapFrame.OnMapChanged`, `ShowUIPanel`, `HideUIPanel`, `ToggleWorldMap`, `ToggleQuestLog`, `MarkCanvasDirty`, pin pools | `EventRegistry` callbacks only, which Blizzard runs isolated |
| `HookScript` on `WorldMapFrame`, `GameMenuFrame` and the scroll container | Only its own frame's `OnSizeChanged` |
| `SetBindingClick("ALT-M")`, gamepad override bindings | None |
| `UIDropDownMenu`, `StaticPopup`, Ace3, a settings panel | None |
| Fog of war by reading Blizzard's live exploration-pin textures (after setting them to alpha 0) and anchoring masks to them | Asks `C_MapExplorationInfo` for the explored overlays and builds its own masks from the same files on its own frame |
| Continent/world fog from per-zone outline masks, revealing a zone only once it's fully explored or its achievement is earned; tracks visits in SavedVariables | Projects each zone's explored overlays onto the open map with `C_Map.GetMapRectOnMap`, so continents reveal exactly what you've explored. No extra art, no saved state |
| Area labels with six types, fonts, gradients, fades and custom entries | Towns, capitals, subzones and city districts in one fixed style |
| Caves, zoom levels, map memory, keep-centred, the HD/SD slider, coordinates | Out of scope |

## Install

1. Copy the `HDMapLite` folder to
   `World of Warcraft\_forever_\Interface\AddOns\`.
2. Disable or remove **High Fidelity World Map** (the two would draw over
   each other).
3. Keep the `HighFidelityWorldMap_Art_Forever` folder in place. The character
   screen will list it as "missing dependency" because its TOC requires High
   Fidelity World Map. That's expected: it has no code, and this addon reads
   its tiles by file path (see the first test below).

## In-game test plan

Turn on BugSack/BugGrabber, and `/console taintLog 1` (the log goes to
`Logs\taint.log`).

1. **HD art loads with the art pack "missing dependency".** Open Kalimdor or
   Eastern Kingdoms where you've explored. The explored zones should show HD
   art on a blue sea. If they show Blizzard's stock art instead, the client
   won't serve files from an addon that can't load. In that case, tell me and
   we'll move the tiles.
2. **Zones:** open Elwynn Forest, Durotar and The Barrens. You should see the
   satellite view on the ground you've explored.
3. **Fog of war:** in a zone you've partly explored, HD should show only on
   explored ground, with ragged edges blending into the stock art, and none of
   it should be misaligned. Walk into new ground with the map open: the reveal
   should grow. Stormwind and Orgrimmar should be fully HD.
4. **Neighbours:** on a zone map, explored parts of the neighbouring zones at
   the edges should show HD too, lining up with the current zone's art.
5. **Continent and world:** each explored area should sit exactly where it is
   on the zone map, with nothing shifted. Also check how fast the world map
   opens once a lot is explored.
6. **Pins on top:** check quest markers, Questie, Shortest Path routes and
   flight points, the player arrow and party members. All should sit above the
   art.
7. **Fallback:** open a dungeon map, Ironforge and Deeprun Tram. You should see
   the stock map and no blue box.
8. **No blink:** switch between a zone, its continent and the world a few
   times. The HD art should be there in the same frame as the stock map, with
   no flash of stock art. A map you've never opened this session may still
   take a moment the first time while its files load from disk.
9. **Resize:** maximise and minimise the map, then zoom in and out. Tiles
   should stay aligned.
10. **Combat:** open the map, switch zones and close it, in combat. No
   "action blocked" messages.
11. **`/reload` mid-combat**, then open the map.
12. **Gamepad:** switch to the gamepad UI and open the map. Focus navigation
   should behave as before.
13. **Area names:** in Elwynn Forest, Durotar and Stormwind, names should sit on their
   places and only appear on explored ground. Check they're readable at
   default zoom and zoomed in, and steady (no pulsing) while zooming. If
   they're too big or small, tell me.
14. **Player arrow:** on a zone map and a continent, the arrow should stand
   out on a dark halo. The halo should follow you smoothly and size with the
   arrow at any zoom. It should vanish inside dungeons.
15. **Taint:** after all of the above, search `taint.log` for `HDMapLite`.

Known interaction: *Spoken Places*' map highlight uses the same frame level.
Whether it draws above or below the HD art is up to the client; it's cosmetic.

## Credits

The zone tile layout table, the list of fogged zones (`Zones.lua`) and the
area label positions (`Labels.lua`, generated from the game's own tables) come from
[High Fidelity World Map](https://github.com/Sectimus/HighFidelityWorldMap)
by Sectimus. Its CurseForge page lists it as MIT; the repository has no
LICENSE file. The HD art is the separate *High Fidelity World Map: Art* pack
(All Rights Reserved), which this addon does not include. Users install it
themselves.

# In-game test plan

What the specs can't cover: the real art, taint, alignment and how it looks.

Turn on BugSack/BugGrabber, and `/console taintLog 1` (the log goes to
`Logs\taint.log`).

1. **The art pack loads while "missing dependency".** Open Kalimdor or Eastern
   Kingdoms where you've explored. The explored zones should show HD art on a
   blue sea. If they show Blizzard's stock art instead, the client isn't
   serving files from an addon that can't load, and the tiles would need to
   move into this addon's folder.
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
   no flash of stock art. A map you haven't opened yet this session may still
   take a moment the first time while its files load from disk.
9. **Resize:** maximise and minimise the map, then zoom in and out. Tiles
   should stay aligned.
10. **Combat:** open the map, switch zones and close it, in combat. No
    "action blocked" messages.
11. **`/reload` mid-combat**, then open the map.
12. **Gamepad:** switch to the gamepad UI and open the map. Focus navigation
    should behave as before.
13. **Area names:** in Elwynn Forest, Durotar and Stormwind, names should sit
    on their places and only appear on explored ground. They should be
    readable at default zoom and zoomed in, and steady (no pulsing) while
    zooming. In Elwynn, The Stonefield Farm and Fargodeep Mine should sit
    apart at default zoom and slide back onto their spots as you zoom in.
14. **Player arrow:** on a zone map and a continent, the arrow should stand
    out on a dark halo. The halo should follow you smoothly and stay the same
    size on screen at any zoom. It should vanish inside dungeons.
15. **No art pack:** rename the `HighFidelityWorldMap_Art_Forever` folder and
    log in. A chat notice should appear after a few seconds, the continents
    should be stock, and zone maps should still be HD. Rename it back.
16. **Taint:** after all of the above, search `taint.log` for `HDMapLite`.

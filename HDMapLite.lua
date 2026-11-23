-- HD Map Lite: draws high-resolution art over the world map, and nothing else.
--
-- One frame of our own sits on the map canvas, just above Blizzard's
-- exploration overlays and below every pin, holding one child layer per
-- recently drawn map. Maps we have no art for are left alone (the overlay
-- hides).
--
-- Art:
--   World / Kalimdor / Eastern Kingdoms: the stitched tiles in the
--     HighFidelityWorldMap_Art_Forever folder (32 x 22 tiles of 256 px).
--   Zones (Zones.lua): the client's own minimap tiles.
--
-- Fog of war, on every map we draw except zones with no fog (cities,
-- battlegrounds), which are drawn in full on an ocean backdrop:
--   HD shows only where the player has explored. For each zone with fog that
--   is visible on the open map (the zone itself and its neighbours on a zone
--   map; every zone on a continent or the world map), its explored overlays
--   (C_MapExplorationInfo, laid out the way Blizzard's own
--   MapExplorationPinMixin:RefreshOverlays does) are projected onto the open
--   map through C_Map.GetMapRectOnMap. Each overlay tile becomes a mask over
--   the HD art, so the edge is Blizzard's own torn edge and unexplored ground
--   shows the stock map.
--
-- What touches Blizzard code, all of it read-only:
--   EventRegistry callbacks "MapCanvas.MapSet", "WorldMapOnShow",
--     "WorldMapMaximized", "WorldMapMinimized" (CallbackRegistry runs them
--     through secureexecuterange, isolated);
--   WorldMapFrame:GetMapID(), .ScrollContainer.Child, and the pin frame-level
--     manager's GetValidFrameLevel / GetFrameLevelRange (pure reads);
--   C_Map.GetMapArtLayers / GetMapInfo / GetMapRectOnMap and
--     C_MapExplorationInfo.GetExploredMapTextures.
-- No hooksecurefunc, no HookScript on Blizzard frames, no field writes, no
-- reading or changing Blizzard's pins, no SavedVariables, no globals, no
-- slash commands, no OnUpdate.

local _, ns = ...

local ZONES, FOG = ns.ZONES, ns.FOG

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local C_AddOns = C_AddOns
local C_Map = C_Map
local C_MapExplorationInfo = C_MapExplorationInfo
local EventRegistry = EventRegistry
local geterrorhandler = geterrorhandler
local print = print
local xpcall, pcall, type, ipairs, pairs = xpcall, pcall, type, ipairs, pairs
local math_max, math_min, math_floor, math_ceil = math.max, math.min, math.floor, math.ceil

-- The game's coastal water colour (HFWM's "Ocean Blue" background). Shows
-- through the art pack's transparent sea and any gap in the zone tile grids.
local OCEAN_R, OCEAN_G, OCEAN_B = 26 / 255, 50 / 255, 69 / 255

local ART_ADDON = "HighFidelityWorldMap_Art_Forever"
local ART_BASE = "Interface\\AddOns\\" .. ART_ADDON .. "\\WorldMap\\"
local HD_MAPS = {
	[947] = "AzerothHD\\azerothhd", -- Azeroth (world)
	[1414] = "KalimdorHD\\kalimdorhd",
	[1415] = "EasternKingdomsHD\\easternkingdomshd",
}
-- Tile n is <prefix><n>.blp, n = row * HD_COLS + col + 1. The grid is
-- 8192 x 5632; the art layer is the top 8192 x 5461, so the last row is clipped.
local HD_COLS, HD_ROWS, HD_TILE = 32, 22, 256
local HD_W, HD_H = 8192, 5461

local EXPLORATION_LEVEL = "PIN_FRAME_LEVEL_MAP_EXPLORATION"
-- A mask file reads as fully opaque until it has loaded, so the first fogged
-- draw of a freshly opened map is redone once, this long after.
local MASK_SETTLE_DELAY = 0.2
local OCEAN = {} -- sentinel source: an ocean-coloured piece instead of a file

-- Texture files load asynchronously, so a texture that has to (re)load its
-- file shows nothing for a few frames. To keep the art from blinking:
--   * each recently drawn map keeps its own layer (a child frame of the
--     overlay) with its textures still holding their files, so switching back
--     to it is just a Show;
--   * redrawing a map reuses its layer's textures in the same order, so each
--     one is handed the file it already has and nothing reloads.
-- Only the least recently used layer gives its files up.
local MAX_LAYERS = 3 -- e.g. a zone, its continent and the world

local overlay
local layers = {} -- least recently used first
local current -- the layer being drawn or shown, nil on maps we leave alone
local hdAvailable -- nil until the first HD draw tests it
local hdFailed = false -- set by a draw whose HD art didn't resolve
local settledMapID -- map whose masks have had their settle redraw
local pending, settlePending = false, false

-- Layers --------------------------------------------------------------------

local function NewLayer()
	local frame = CreateFrame("Frame", nil, overlay)
	frame:SetAllPoints(overlay)
	frame:EnableMouse(false)
	local backdrop = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	backdrop:SetAllPoints(frame)
	backdrop:SetColorTexture(OCEAN_R, OCEAN_G, OCEAN_B, 1)
	return { frame = frame, backdrop = backdrop, tex = {}, n = 0, masks = {}, nm = 0, maskOf = {} }
end

-- The next texture of the layer being drawn, in drawing order.
local function Acquire(drawLayer)
	local L = current
	local i = L.n + 1
	L.n = i
	local tex = L.tex[i]
	if not tex then
		tex = L.frame:CreateTexture(nil, "ARTWORK")
		L.tex[i] = tex
	end
	local mask = L.maskOf[tex]
	if mask then
		-- Re-added below if still wanted; re-adding also makes the client
		-- re-read a mask whose file has loaded since (see Settle).
		tex:RemoveMaskTexture(mask)
		L.maskOf[tex] = nil
	end
	tex:ClearAllPoints()
	tex:SetDrawLayer(drawLayer)
	tex:Show()
	return tex
end

local function AcquireMask()
	local L = current
	local i = L.nm + 1
	L.nm = i
	local mask = L.masks[i]
	if not mask then
		mask = L.frame:CreateMaskTexture()
		L.masks[i] = mask
	end
	mask:ClearAllPoints()
	return mask
end

local function BeginLayer(L)
	L.n, L.nm = 0, 0
end

-- Retire the textures this draw didn't use. They drop their files: a redraw of
-- the same map only grows (more explored), so leftovers are art we no longer
-- show. Masks keep theirs: they are small, and a mask that has to reload draws
-- opaque until it does.
local function FinishLayer(L)
	for i = L.n + 1, #L.tex do
		local tex = L.tex[i]
		local mask = L.maskOf[tex]
		if mask then
			tex:RemoveMaskTexture(mask)
			L.maskOf[tex] = nil
		end
		tex:Hide()
		tex:ClearAllPoints()
		tex:SetTexture(nil)
	end
	for i = L.nm + 1, #L.masks do
		L.masks[i]:ClearAllPoints()
	end
end

local function ClearLayer(L)
	BeginLayer(L)
	FinishLayer(L)
end

-- The layer for *mapID*: its own if it has one, else a new one or the least
-- recently used one, emptied. Marks it most recently used.
local function LayerFor(mapID)
	local L
	for i, l in ipairs(layers) do
		if l.mapID == mapID then
			L = table.remove(layers, i)
			break
		end
	end
	if not L then
		if #layers >= MAX_LAYERS then
			L = table.remove(layers, 1)
			ClearLayer(L)
		else
			L = NewLayer()
		end
		L.mapID, L.dirty = mapID, true
	end
	layers[#layers + 1] = L
	return L
end

local function MarkAllDirty()
	for _, L in ipairs(layers) do
		L.dirty = true
	end
end

-- Draw the part of a tile that falls inside a clip rect. Everything is in
-- canvas units; (x0, y0, tw, th) is the whole tile, (cx0, cy0)-(cx1, cy1) the
-- clip. Returns SetTexture's result, or true when nothing overlaps.
local function Piece(src, x0, y0, tw, th, cx0, cy0, cx1, cy1, mask)
	local ix0, ix1 = math_max(x0, cx0), math_min(x0 + tw, cx1)
	local iy0, iy1 = math_max(y0, cy0), math_min(y0 + th, cy1)
	if ix1 <= ix0 or iy1 <= iy0 then
		return true
	end
	local tex = Acquire(src == OCEAN and "BACKGROUND" or "ARTWORK")
	tex:SetPoint("TOPLEFT", current.frame, "TOPLEFT", ix0, -iy0)
	tex:SetSize(ix1 - ix0, iy1 - iy0)
	if mask then
		tex:AddMaskTexture(mask)
		current.maskOf[tex] = mask
	end
	if src == OCEAN then
		tex:SetTexCoord(0, 1, 0, 1)
		tex:SetColorTexture(OCEAN_R, OCEAN_G, OCEAN_B, 1)
		return true
	end
	tex:SetTexCoord((ix0 - x0) / tw, (ix1 - x0) / tw, (iy0 - y0) / th, (iy1 - y0) / th)
	return tex:SetTexture(src)
end

-- Tile painters: draw a map's art inside a clip rect (canvas units).

-- Every minimap tile of *zone* that overlaps the clip, cut to it.
local function ZoneTiles(zone, w, h, cx0, cy0, cx1, cy1, mask)
	local sx, sy = w / zone.layerW, h / zone.layerH
	for _, reg in ipairs(zone.regions) do
		local f, cols = reg.f, reg.cols
		local tw, th = reg.tw * sx, reg.th * sy
		local gx, gy = reg.ox * sx, reg.oy * sy
		local c0 = math_max(0, math_floor((cx0 - gx) / tw))
		local c1 = math_min(cols - 1, math_ceil((cx1 - gx) / tw) - 1)
		local r0 = math_max(0, math_floor((cy0 - gy) / th))
		local r1 = math_min(reg.rows - 1, math_ceil((cy1 - gy) / th) - 1)
		for row = r0, r1 do
			for col = c0, c1 do
				local fdid = f[row * cols + col + 1]
				if fdid and fdid ~= 0 then
					Piece(fdid, gx + col * tw, gy + row * th, tw, th, cx0, cy0, cx1, cy1, mask)
				end
			end
		end
	end
end

-- Every HD art-pack tile that overlaps the clip, cut to it.
local function HDTiles(prefix, w, h, cx0, cy0, cx1, cy1, mask)
	local tw, th = HD_TILE * w / HD_W, HD_TILE * h / HD_H
	local c0 = math_max(0, math_floor(cx0 / tw))
	local c1 = math_min(HD_COLS - 1, math_ceil(cx1 / tw) - 1)
	local r0 = math_max(0, math_floor(cy0 / th))
	local r1 = math_min(HD_ROWS - 1, math_ceil(cy1 / th) - 1)
	for row = r0, r1 do
		for col = c0, c1 do
			if not Piece(ART_BASE .. prefix .. (row * HD_COLS + col + 1), col * tw, row * th, tw, th, cx0, cy0, cx1, cy1, mask) then
				hdFailed = true
				return
			end
		end
	end
end

-- Map geometry (static, cached for the session) ------------------------------

local layerCache, parentCache, rectCache, candidateCache = {}, {}, {}, {}

local function ArtLayer(mapID)
	local cached = layerCache[mapID]
	if cached == nil then
		cached = false
		if C_Map and C_Map.GetMapArtLayers then
			local ok, artLayers = pcall(C_Map.GetMapArtLayers, mapID)
			local layer = ok and type(artLayers) == "table" and artLayers[1]
			if layer and (layer.layerWidth or 0) > 0 and (layer.layerHeight or 0) > 0 then
				cached = layer
			end
		end
		layerCache[mapID] = cached
	end
	return cached or nil
end

local function Parent(mapID)
	local cached = parentCache[mapID]
	if cached == nil then
		cached = false
		if C_Map and C_Map.GetMapInfo then
			local ok, info = pcall(C_Map.GetMapInfo, mapID)
			local parent = ok and type(info) == "table" and info.parentMapID
			if type(parent) == "number" and parent > 0 and parent ~= mapID then
				cached = parent
			end
		end
		parentCache[mapID] = cached
	end
	return cached or nil
end

local function DirectRect(mapID, top)
	if not (C_Map and C_Map.GetMapRectOnMap) then
		return nil
	end
	local ok, x0, x1, y0, y1 = pcall(C_Map.GetMapRectOnMap, mapID, top)
	if ok and type(x0) == "number" and type(x1) == "number" and type(y0) == "number" and type(y1) == "number"
		and x1 > x0 and y1 > y0 then
		return { x0, x1, y0, y1 }
	end
	return nil
end

-- *mapID*'s rect in *top*'s normalized space {minX, maxX, minY, maxY}, or nil.
-- Asks the client directly, and failing that composes the rects up the parent
-- chain (each step a plain child-on-parent lookup).
local function RectOn(mapID, top, depth)
	if mapID == top then
		return { 0, 1, 0, 1 }
	end
	local key = mapID * 65536 + top
	local cached = rectCache[key]
	if cached == nil then
		cached = DirectRect(mapID, top)
		if not cached and (depth or 0) < 6 then
			local parent = Parent(mapID)
			local inParent = parent and DirectRect(mapID, parent)
			local parentOnTop = inParent and RectOn(parent, top, (depth or 0) + 1)
			if parentOnTop then
				local px, pw = parentOnTop[1], parentOnTop[2] - parentOnTop[1]
				local py, ph = parentOnTop[3], parentOnTop[4] - parentOnTop[3]
				cached = { px + inParent[1] * pw, px + inParent[2] * pw, py + inParent[3] * ph, py + inParent[4] * ph }
			end
		end
		rectCache[key] = cached or false
	end
	return cached or nil
end

-- The map whose space reveals are measured in, and the open map's rect in it:
-- a zone map works in its continent, a continent or the world in itself.
local function Frame(mapID)
	if HD_MAPS[mapID] then
		return mapID, { 0, 1, 0, 1 }
	end
	local parent = Parent(mapID)
	local rect = parent and RectOn(mapID, parent)
	if rect then
		return parent, rect
	end
	return mapID, { 0, 1, 0, 1 }
end

-- Zones with fog whose ground shows on *mapID*, each with its rect in the
-- open map's normalized space (may reach past 0..1).
local function Candidates(mapID)
	local list = candidateCache[mapID]
	if list then
		return list
	end
	list = {}
	local frame, open = Frame(mapID)
	local ow, oh = open[2] - open[1], open[4] - open[3]
	for zoneID in pairs(FOG) do
		local r = zoneID == mapID and { 0, 1, 0, 1 } or RectOn(zoneID, frame)
		if r then
			if zoneID ~= mapID then
				r = { (r[1] - open[1]) / ow, (r[2] - open[1]) / ow, (r[3] - open[3]) / oh, (r[4] - open[3]) / oh }
			end
			if r[2] > 0 and r[1] < 1 and r[4] > 0 and r[3] < 1 then
				list[#list + 1] = { zoneID, r }
			end
		end
	end
	table.sort(list, function(a, b)
		return a[1] < b[1]
	end)
	candidateCache[mapID] = list
	return list
end

-- Fog -----------------------------------------------------------------------

local function PowerOfTwoAtLeast(n)
	local s = 16
	while s < n do
		s = s * 2
	end
	return s
end

local function ExplorationAvailable()
	return C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures and C_Map and C_Map.GetMapArtLayers
		and true or false
end

-- Reveal one zone's explored ground on the open map. *rect* is the zone's rect
-- in the open map's normalized space; *paint* draws the open map's art in a
-- clip rect under a mask.
local function Reveal(zoneID, rect, w, h, paint, art)
	local layer = ArtLayer(zoneID)
	if not layer then
		return
	end
	local ok, explored = pcall(C_MapExplorationInfo.GetExploredMapTextures, zoneID)
	if not (ok and type(explored) == "table") then
		return
	end
	local ox, oy = rect[1] * w, rect[3] * h
	local kx = (rect[2] - rect[1]) * w / layer.layerWidth
	local ky = (rect[4] - rect[3]) * h / layer.layerHeight
	local TW, TH = layer.tileWidth or 256, layer.tileHeight or 256
	for _, info in ipairs(explored) do
		-- Mouse-over overlays are hover highlights, not explored ground.
		if not info.isShownByMouseOver and type(info.fileDataIDs) == "table" then
			local wide = math_ceil(info.textureWidth / TW)
			local tall = math_ceil(info.textureHeight / TH)
			for j = 1, tall do
				local ph, fh = TH, TH
				if j == tall then
					ph = info.textureHeight % TH
					if ph == 0 then
						ph = TH
					end
					fh = PowerOfTwoAtLeast(ph)
				end
				for k = 1, wide do
					local pw, fw = TW, TW
					if k == wide then
						pw = info.textureWidth % TW
						if pw == 0 then
							pw = TW
						end
						fw = PowerOfTwoAtLeast(pw)
					end
					local fid = info.fileDataIDs[(j - 1) * wide + k]
					local x0 = ox + (info.offsetX + TW * (k - 1)) * kx
					local y0 = oy + (info.offsetY + TH * (j - 1)) * ky
					local x1, y1 = x0 + pw * kx, y0 + ph * ky
					local cx0, cy0 = math_max(x0, 0), math_max(y0, 0)
					local cx1, cy1 = math_min(x1, w), math_min(y1, h)
					if fid and cx1 > cx0 and cy1 > cy0 then
						-- The mask covers the whole power-of-two file rather
						-- than relying on texcoords to crop a MaskTexture;
						-- pieces are clipped to the visible part anyway.
						local mask = AcquireMask()
						mask:SetPoint("TOPLEFT", current.frame, "TOPLEFT", x0, -y0)
						mask:SetSize(fw * kx, fh * ky)
						-- CLAMP, not CLAMPTOBLACKADDITIVE: it keeps adjoining
						-- overlay tiles from fading at their shared seam.
						mask:SetTexture(fid, "CLAMP", "CLAMP")
						Piece(OCEAN, cx0, cy0, cx1 - cx0, cy1 - cy0, cx0, cy0, cx1, cy1, mask)
						paint(art, w, h, cx0, cy0, cx1, cy1, mask)
						if hdFailed then
							return
						end
					end
				end
			end
		end
	end
end

-- Draw *mapID* with fog. Returns false when fog can't be computed here.
local function DrawFogged(mapID, w, h, paint, art)
	if not ExplorationAvailable() then
		return false
	end
	current.backdrop:Hide()
	for _, c in ipairs(Candidates(mapID)) do
		Reveal(c[1], c[2], w, h, paint, art)
		if hdFailed then
			return true
		end
	end
	return true
end

-- Map types -----------------------------------------------------------------

local function DrawZone(zone, mapID, w, h)
	if FOG[mapID] and DrawFogged(mapID, w, h, ZoneTiles, zone) then
		return true
	end
	-- No fog on this map (or no way to read it): the whole zone.
	current.backdrop:Show()
	ZoneTiles(zone, w, h, 0, 0, w, h)
	return true
end

local function ArtPackPresent()
	if C_AddOns and C_AddOns.DoesAddOnExist then
		local ok, exists = pcall(C_AddOns.DoesAddOnExist, ART_ADDON)
		return ok and exists == true
	end
	return true -- can't tell; the SetTexture result still guards
end

local function DrawHD(prefix, mapID, w, h)
	if hdAvailable == nil then
		hdAvailable = ArtPackPresent()
	end
	if not hdAvailable then
		return false
	end
	if not DrawFogged(mapID, w, h, HDTiles, prefix) then
		current.backdrop:Show()
		HDTiles(prefix, w, h, 0, 0, w, h)
	end
	if hdFailed then
		-- The client couldn't resolve the art: fall back to the stock map for
		-- the rest of the session rather than an empty sea.
		hdAvailable = false
		ClearLayer(current)
		return false
	end
	return true
end

-- Drawing -------------------------------------------------------------------

-- Just above Blizzard's exploration overlays (which would otherwise paint the
-- old art over ours) and under every pin type the world map registers.
local function OverlayLevel(map, canvas)
	local mgr = map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
	if mgr and mgr.GetValidFrameLevel then
		local ok, start = pcall(mgr.GetValidFrameLevel, mgr, EXPLORATION_LEVEL)
		if ok and type(start) == "number" then
			local range = 1
			if mgr.GetFrameLevelRange then
				local okR, r = pcall(mgr.GetFrameLevelRange, mgr, EXPLORATION_LEVEL)
				if okR and type(r) == "number" and r >= 1 then
					range = r
				end
			end
			return start + range
		end
	end
	return canvas:GetFrameLevel() + 1
end

local Schedule

-- Redo the open map once its masks have loaded. The redraw reuses every
-- texture and file in place, so it costs no blink.
local function Settle()
	settlePending = false
	if current then
		current.dirty = true
	end
	Schedule()
end

local function HideLayersBut(keep)
	for _, L in ipairs(layers) do
		if L ~= keep then
			L.frame:Hide()
		end
	end
end

local function Draw()
	local map = WorldMapFrame
	if not (overlay and map and map.GetMapID and map:IsShown()) then
		return
	end
	local canvas = map.ScrollContainer and map.ScrollContainer.Child
	if not canvas then
		return
	end

	if overlay:GetParent() ~= canvas then
		-- The client replaced the canvas: follow it.
		overlay:SetParent(canvas)
		overlay:ClearAllPoints()
		overlay:SetAllPoints(canvas)
		MarkAllDirty()
	end
	local level = OverlayLevel(map, canvas)
	if overlay:GetFrameLevel() ~= level then
		overlay:SetFrameLevel(level)
	end

	local mapID = map:GetMapID()
	local w, h = canvas:GetSize()
	if not (mapID and w > 0 and h > 0 and (ZONES[mapID] or HD_MAPS[mapID])) then
		-- A map we leave alone. Cached layers stay loaded for coming back.
		current = nil
		HideLayersBut(nil)
		overlay:Hide()
		return
	end
	if current and current.mapID == mapID and current.w == w and current.h == h and not current.dirty then
		return
	end

	local L = LayerFor(mapID)
	current = L
	HideLayersBut(L)
	if L.dirty or L.w ~= w or L.h ~= h then
		L.w, L.h, L.dirty = w, h, false
		BeginLayer(L)
		hdFailed = false
		local drawn
		local zone = ZONES[mapID]
		if zone then
			drawn = DrawZone(zone, mapID, w, h)
		else
			drawn = DrawHD(HD_MAPS[mapID], mapID, w, h)
		end
		FinishLayer(L)
		L.drawn = drawn
		if not drawn then
			L.dirty = true -- try again next visit rather than cache a failure
		end
	end
	L.frame:SetShown(L.drawn)
	overlay:SetShown(L.drawn)

	if L.drawn and L.nm > 0 and settledMapID ~= mapID and not settlePending then
		settledMapID = mapID
		settlePending = true
		C_Timer.After(MASK_SETTLE_DELAY, Settle)
	end
end

local function RunDraw()
	pending = false
	xpcall(Draw, geterrorhandler())
end

-- Coalesce bursts (exploration updates, resizes, settles) into one draw on the
-- next frame.
Schedule = function() -- check-ignore: global-write (assigns the `local Schedule` forward-declared above Draw)
	if not pending then
		pending = true
		C_Timer.After(0, RunDraw)
	end
end

-- Map changes draw at once, in the same frame as Blizzard's own art, so the
-- new map never shows a frame without ours. MapSet fires just before the
-- client resizes the canvas to the new map's art layer; when that size will
-- differ, wait for it (OnSizeChanged) instead of drawing twice.
local function OnMapSet(_, mapID)
	local map = WorldMapFrame
	local canvas = map and map.ScrollContainer and map.ScrollContainer.Child
	local layer = type(mapID) == "number" and ArtLayer(mapID)
	if canvas and layer then
		local w, h = canvas:GetSize()
		if w ~= layer.layerWidth or h ~= layer.layerHeight then
			Schedule()
			return
		end
	end
	xpcall(Draw, geterrorhandler())
end

-- Setup ---------------------------------------------------------------------

local callbackOwner = {}

-- Once per login, and only when the client says for certain the art pack
-- folder isn't there: without it the world and continent maps silently stay
-- stock, which looks like a broken addon.
local NOTICE_DELAY = 5 -- seconds, so it isn't lost in the login chat burst
local NOTICE = "|cff33ccffHD Map Lite:|r the world and continent maps need the "
	.. "|cffffd100High Fidelity World Map: Art|r pack (CurseForge: hfwm-art). "
	.. "Zone maps work without it."

local function NoticeIfArtMissing()
	if C_AddOns and C_AddOns.DoesAddOnExist then
		local ok, exists = pcall(C_AddOns.DoesAddOnExist, ART_ADDON)
		if ok and exists == false then
			print(NOTICE)
		end
	end
end

local function OnMapShown()
	settledMapID = nil -- masks may have been unloaded while the map was shut
	xpcall(Draw, geterrorhandler())
end

local function Init()
	if overlay or not (WorldMapFrame and WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child) then
		return
	end
	local canvas = WorldMapFrame.ScrollContainer.Child
	overlay = CreateFrame("Frame", nil, canvas)
	overlay:SetAllPoints(canvas)
	overlay:EnableMouse(false)
	overlay:Hide()

	-- Our own frame tracks the canvas size, so no hook on Blizzard's.
	overlay:SetScript("OnSizeChanged", Schedule)

	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("MapCanvas.MapSet", OnMapSet, callbackOwner)
		EventRegistry:RegisterCallback("WorldMapOnShow", OnMapShown, callbackOwner)
		-- The overlay is hidden on maps we don't draw, and a hidden frame may
		-- not report OnSizeChanged, so resizes come from these too.
		EventRegistry:RegisterCallback("WorldMapMaximized", Schedule, callbackOwner)
		EventRegistry:RegisterCallback("WorldMapMinimized", Schedule, callbackOwner)
	end
	Schedule()
	C_Timer.After(NOTICE_DELAY, NoticeIfArtMissing)
end

-- New ground explored: every cached fogged map is stale. Redraw the open one
-- (in place, so only the new ground appears); the rest redraw when next shown.
local function OnExplorationUpdated()
	local any = false
	for _, L in ipairs(layers) do
		if FOG[L.mapID] or HD_MAPS[L.mapID] then
			L.dirty = true
			any = any or L == current
		end
	end
	if any then
		Schedule()
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, name)
	if event == "MAP_EXPLORATION_UPDATED" then
		xpcall(OnExplorationUpdated, geterrorhandler())
		return
	end
	if event == "ADDON_LOADED" and name ~= "Blizzard_WorldMap" then
		return
	end
	xpcall(Init, geterrorhandler())
	if overlay then
		self:UnregisterEvent("PLAYER_LOGIN")
		self:UnregisterEvent("ADDON_LOADED")
		self:RegisterEvent("MAP_EXPLORATION_UPDATED")
	end
end)

-- Exposed for tests only; nothing in game reads it.
ns._test = {
	-- The current layer's textures and masks in use, in drawing order.
	Active = function()
		local t = {}
		for i = 1, current and current.n or 0 do
			t[i] = current.tex[i]
		end
		return t
	end,
	ActiveMasks = function()
		local t = {}
		for i = 1, current and current.nm or 0 do
			t[i] = current.masks[i]
		end
		return t
	end,
	MaskOf = function(tex)
		return current and current.maskOf[tex]
	end,
	ActiveCount = function()
		return current and current.n or 0
	end,
	Layers = function()
		return layers
	end,
	Overlay = function()
		return overlay
	end,
	Backdrop = function()
		return current and current.backdrop
	end,
	ResetHD = function()
		hdAvailable = nil
		MarkAllDirty()
	end,
	ResetGeometry = function()
		MarkAllDirty()
		wipe(layerCache)
		wipe(parentCache)
		wipe(rectCache)
		wipe(candidateCache)
	end,
	Candidates = Candidates,
	NoticeIfArtMissing = NoticeIfArtMissing,
}

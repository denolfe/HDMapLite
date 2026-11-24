-- Drives HDMapLite against a fake WorldMapFrame. Run from the addon folder:
--   luajit <skill>/scripts/mini_busted.lua tests/map_spec.lua tests/map_spec.lua
-- (mini_busted takes a helper first; this file is its own helper.)
if _G.__HDML_LOADED then return end
_G.__HDML_LOADED = true

local W = {}
local MT = { __index = W }
local function New(kind, parent)
	return setmetatable({ kind = kind, parent = parent, shown = true, level = 1, scripts = {}, events = {}, w = 0, h = 0 }, MT)
end
function W:CreateTexture(_, layer) local t = New("Texture", self); t.layer = layer; return t end
function W:CreateMaskTexture() return New("MaskTexture", self) end
function W:SetPoint(...) self.point = { ... } end
function W:ClearAllPoints() self.point = nil end
function W:SetAllPoints(f) self.all = f end
function W:SetSize(w, h) self.w, self.h = w, h end
function W:GetSize() return self.w, self.h end
function W:SetTexCoord(...) self.tc = { ... } end
function W:SetDrawLayer(l) self.layer = l end
function W:SetTexture(src, wrapH)
	-- a texture handed a different file has to load it (and blinks meanwhile)
	if src ~= nil and src ~= self.src then _G.__loads = (_G.__loads or 0) + 1 end
	self.src, self.color, self.wrap = src, nil, wrapH
	if type(src) == "string" and _G.__missingArt then return false end
	return true
end
function W:SetColorTexture(...) self.color, self.src = { ... }, nil end
function W:AddMaskTexture(m) self.masks = self.masks or {}; self.masks[#self.masks + 1] = m end
function W:RemoveMaskTexture(m)
	for i, x in ipairs(self.masks or {}) do if x == m then table.remove(self.masks, i) return end end
	error("removing a mask that was never added")
end
function W:CreateFontString(_, layer) local f = New("FontString", self); f.layer = layer; return f end
function W:SetFont(font, size, flags) self.font, self.size, self.flags = font, size, flags end
function W:SetText(s) self.text = s end
function W:SetTextColor(...) self.textColor = { ... } end
function W:SetShadowOffset(...) self.shadow = { ... } end
function W.SetShadowColor() end
function W:SetVertexColor(...) self.vertex = { ... } end
-- effective scale: a test sets .scale on a canvas-scaled frame; a frame that
-- was SetScale'd multiplies its parent's
function W:GetEffectiveScale()
	if self.ownScale then return self.ownScale * (self.parent and self.parent:GetEffectiveScale() or 1) end
	return self.scale or 1
end
function W:SetScale(s) self.ownScale = s end
function W:Show() self.shown = true end
function W:Hide() self.shown = false end
function W:SetShown(v) self.shown = v and true or false end
function W:IsShown() return self.shown end
function W:EnableMouse(v) self.mouse = v end
function W:SetParent(p) self.parent = p end
function W:GetParent() return self.parent end
function W:SetFrameLevel(l) self.level = l end
function W:GetFrameLevel() return self.level end
function W:SetScript(s, f) self.scripts[s] = f end
function W:RegisterEvent(e) self.events[e] = true end
function W:UnregisterEvent(e) self.events[e] = nil end

function CreateFrame(kind, _, parent) return New(kind, parent) end
function geterrorhandler() return function(e) error(e, 0) end end
local timers = {}
C_Timer = { After = function(d, f) timers[#timers + 1] = f; if d > 0 and C_Timer.ranDelays then C_Timer.ranDelays[#C_Timer.ranDelays + 1] = d end end }
function _G.FlushTimers() local t = timers; timers = {}; for _, f in ipairs(t) do f() end end
C_AddOns = { DoesAddOnExist = function() return not _G.__noArtFolder end }
local callbacks = {}
EventRegistry = { RegisterCallback = function(_, ev, f) callbacks[ev] = f end }
function _G.FireCallback(ev, ...) callbacks[ev](nil, ...) end
-- Map geometry: Elwynn (1429) and Westfall (1436) side by side on Eastern
-- Kingdoms (1415), Durotar (1411) on Kalimdor (1414); both continents on the
-- world (947), whose direct zone lookups fail so the addon must compose them.
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
local PARENT = { [1429] = 1415, [1436] = 1415, [1453] = 1415, [1411] = 1414, [1414] = 947, [1415] = 947 }
local RECT = {
	["1429:1415"] = { 0.40, 0.50, 0.60, 0.70 },
	["1436:1415"] = { 0.32, 0.42, 0.62, 0.72 },
	["1453:1415"] = { 0.41, 0.43, 0.60, 0.62 },
	["1411:1414"] = { 0.60, 0.70, 0.40, 0.50 },
	["1414:947"] = { 0.00, 0.50, 0.00, 1.00 },
	["1415:947"] = { 0.50, 1.00, 0.00, 1.00 },
}
C_Map = {
	GetMapArtLayers = function() return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 } } end,
	GetMapInfo = function(id) return { mapID = id, parentMapID = PARENT[id] or 0 } end,
	GetMapRectOnMap = function(id, top)
		local r = RECT[id .. ":" .. top]
		if r then return r[1], r[2], r[3], r[4] end
		return 0, 0, 0, 0
	end,
}
_G.__explored = {}
C_MapExplorationInfo = {
	GetExploredMapTextures = function(id) return _G.__explored[id] or {} end,
	-- explored if an overlay of that map covers the point (layer is 1002 x 668)
	GetExploredAreaIDsAtPosition = function(id, pos)
		local x, y = pos.x * 1002, pos.y * 668
		for _, o in ipairs(_G.__explored[id] or {}) do
			if x >= o.offsetX and x <= o.offsetX + o.textureWidth and y >= o.offsetY and y <= o.offsetY + o.textureHeight then
				return { 1 }
			end
		end
		return nil
	end,
}
function CreateVector2D(x, y) return { x = x, y = y } end
UIParent = New("Frame")
_G.__playerPos = {}
C_Map.GetPlayerMapPosition = function(id)
	local p = _G.__playerPos[id]
	if not p then return nil end
	return { GetXY = function() return p[1], p[2] end }
end
_G.__secret = {}
function issecretvalue(v) return _G.__secret[v] == true end
local function Overlay(x, y, w, h, ids, hover)
	return { offsetX = x, offsetY = y, textureWidth = w, textureHeight = h, fileDataIDs = ids, isShownByMouseOver = hover or false }
end

local canvas = New("Frame"); canvas.level = 3
local mgr = {
	GetValidFrameLevel = function(_, t) return t == "PIN_FRAME_LEVEL_MAP_EXPLORATION" and 2002 or 2000 end,
	GetFrameLevelRange = function() return 1 end,
}
WorldMapFrame = New("Frame")
WorldMapFrame.ScrollContainer = { Child = canvas }
WorldMapFrame.mapID = 1453
function WorldMapFrame:GetMapID() return self.mapID end
function WorldMapFrame.GetPinFrameLevelsManager() return mgr end
_G.Canvas = canvas

_G.__printed = {}
local realPrint = print
function print(...)
	if _G.__capturePrint then _G.__printed[#_G.__printed + 1] = table.concat({ ... }, " ") return end
	realPrint(...)
end

local ns = {}
_G.NS = ns
assert(loadfile("Zones.lua"))("HDMapLite", ns)
assert(loadfile("Labels.lua"))("HDMapLite", ns)
local loader
local realCreate = CreateFrame
CreateFrame = function(...) local f = realCreate(...); loader = loader or f; return f end
assert(loadfile("HDMapLite.lua"))("HDMapLite", ns)
CreateFrame = realCreate
_G.Loader = loader

local STORMWIND, ELWYNN = 1453, 1429 -- unfogged city, fogged zone

describe("HDMapLite", function()
	local T = ns._test
	local function open(mapID, w, h)
		WorldMapFrame.mapID = mapID
		canvas:SetSize(w or 1002, h or 668)
		FireCallback("MapCanvas.MapSet", mapID)
		FlushTimers()
	end
	-- New exploration data, announced the way the client does.
	local function explore(data)
		_G.__explored = data
		Loader.scripts.OnEvent(Loader, "MAP_EXPLORATION_UPDATED")
	end
	local function inside(tex, x0, y0, x1, y1)
		local x, y = tex.point[4], -tex.point[5]
		return x >= x0 - 1e-6 and y >= y0 - 1e-6 and x + tex.w <= x1 + 1e-6 and y + tex.h <= y1 + 1e-6
	end

	it("initialises on PLAYER_LOGIN and swaps to the exploration event", function()
		Loader.scripts.OnEvent(Loader, "PLAYER_LOGIN")
		assert(T.Overlay(), "overlay created")
		assert.are.equal(canvas, T.Overlay():GetParent())
		assert.is_false(T.Overlay().mouse)
		assert.is_nil(Loader.events.PLAYER_LOGIN)
		assert.is_nil(Loader.events.ADDON_LOADED)
		assert.is_true(Loader.events.MAP_EXPLORATION_UPDATED)
	end)

	it("tells the player once at login when the art pack is missing", function()
		_G.__capturePrint = true
		_G.__noArtFolder = true
		T.NoticeIfArtMissing()
		assert.are.equal(1, #_G.__printed)
		assert(_G.__printed[1]:find("hfwm-art", 1, true), _G.__printed[1])
		_G.__noArtFolder = nil
		T.NoticeIfArtMissing()
		assert.are.equal(1, #_G.__printed, "silent when the pack is there")
		local saved = C_AddOns.DoesAddOnExist
		C_AddOns.DoesAddOnExist = nil
		T.NoticeIfArtMissing()
		assert.are.equal(1, #_G.__printed, "silent when it can't tell")
		C_AddOns.DoesAddOnExist = saved
		_G.__capturePrint = nil
	end)

	it("knows which zones are fogged", function()
		assert.is_true(NS.FOG[ELWYNN])
		assert.is_nil(NS.FOG[STORMWIND])
		for id in pairs(NS.FOG) do assert(NS.ZONES[id], "fog entry without tiles: " .. id) end
	end)

	it("sits one level above exploration pins", function()
		open(STORMWIND)
		assert.are.equal(2003, T.Overlay():GetFrameLevel())
	end)

	it("draws an unfogged zone in full, clipped to the canvas", function()
		open(STORMWIND)
		local zone = NS.ZONES[STORMWIND]
		assert(T.ActiveCount() > 0, "tiles drawn")
		assert.is_true(T.Overlay():IsShown())
		assert.is_true(T.Backdrop():IsShown())
		local sx = 1002 / zone.layerW
		for _, tex in ipairs(T.Active()) do
			assert(inside(tex, 0, 0, 1002, 668), "inside canvas")
			assert(type(tex.src) == "number", "fdid")
			assert.is_nil(tex.masks and tex.masks[1])
			local u0, u1 = tex.tc[1], tex.tc[2]
			assert(math.abs((u1 - u0) * zone.regions[1].tw * sx - tex.w) < 1e-6, "texcoord matches width")
		end
	end)

	it("skips redraw when nothing changed", function()
		local first = T.Active()[1]
		open(STORMWIND)
		assert.are.equal(first, T.Active()[1])
	end)

	it("shows only the stock map on a fogged zone with nothing explored", function()
		explore({})
		open(ELWYNN)
		assert.are.equal(0, T.ActiveCount())
		assert.is_false(T.Backdrop():IsShown())
		assert.is_true(T.Overlay():IsShown())
	end)

	it("finds the zone and its neighbours, not other continents", function()
		local ids = {}
		for _, c in ipairs(T.Candidates(ELWYNN)) do ids[c[1]] = c[2] end
		assert(ids[ELWYNN], "self")
		assert(ids[1436], "Westfall")
		assert.is_nil(ids[1411])
		-- Westfall in Elwynn's normalized space: x (0.32-0.40)/0.1 .. (0.42-0.40)/0.1
		assert(math.abs(ids[1436][1] + 0.8) < 1e-9 and math.abs(ids[1436][2] - 0.2) < 1e-9, "projected x")
		assert(math.abs(ids[1436][3] - 0.2) < 1e-9 and math.abs(ids[1436][4] - 1.2) < 1e-9, "projected y")
	end)

	it("draws HD only under explored overlays, masked by their files", function()
		explore({ [ELWYNN] = {
			Overlay(100, 50, 300, 200, { 111, 112 }),
			Overlay(600, 300, 100, 100, { 999 }, true), -- hover highlight: ignored
		} })
		open(STORMWIND) -- leave and come back, so the zone is drawn fresh
		open(ELWYNN)
		assert.are.equal(2, #T.ActiveMasks())
		local m1, m2 = T.ActiveMasks()[1], T.ActiveMasks()[2]
		assert.are.equal(111, m1.src); assert.are.equal("CLAMP", m1.wrap)
		assert.are.equal(112, m2.src)
		-- first tile is a full 256; the second is 44 px wide in a 64 px file,
		-- 200 px tall in a 256 px file
		assert.are.same({ 256, 256 }, { m1.w, m1.h })
		assert.are.same({ 64, 256 }, { m2.w, m2.h })
		assert.are.same({ 100, -50 }, { m1.point[4], m1.point[5] })
		assert.are.same({ 356, -50 }, { m2.point[4], m2.point[5] })
		local ocean, tiles = 0, 0
		for _, tex in ipairs(T.Active()) do
			assert(tex.masks and #tex.masks == 1, "every piece masked")
			local m = tex.masks[1]
			local mx1 = m == m1 and 356 or 400
			assert(inside(tex, m.point[4], 50, mx1, 250), "piece stays inside its overlay tile")
			if tex.color then ocean = ocean + 1; assert.are.equal("BACKGROUND", tex.layer)
			else tiles = tiles + 1; assert.are.equal("ARTWORK", tex.layer) end
		end
		assert.are.equal(2, ocean)
		assert(tiles > 0, "HD tiles drawn")
	end)

	it("shows a neighbour's explored ground at the zone's edge", function()
		-- Westfall overlay near its east edge: x 900 of 1002 lands at
		-- Elwynn x = (-0.8 + 900/1002) * 1002 = 98.4
		explore({ [1436] = { Overlay(900, 0, 102, 256, { 4242 }) } })
		open(STORMWIND); open(ELWYNN)
		assert.are.equal(1, #T.ActiveMasks())
		local m = T.ActiveMasks()[1]
		assert.are.equal(4242, m.src)
		assert(math.abs(m.point[4] - 98.4) < 1e-6, "x " .. m.point[4])
		-- y: Westfall's top sits at 0.2 of Elwynn's height
		assert(math.abs(m.point[5] + 0.2 * 668) < 1e-6, "y " .. m.point[5])
		for _, tex in ipairs(T.Active()) do assert(tex.masks and tex.masks[1] == m, "masked") end
	end)

	it("redraws once more after masks have had time to load", function()
		explore({ [ELWYNN] = { Overlay(0, 0, 256, 256, { 7 }) } })
		open(STORMWIND)
		WorldMapFrame.mapID = ELWYNN
		C_Timer.ranDelays = {}
		FireCallback("WorldMapOnShow") -- a fresh open resets the settle; draws at once
		FlushTimers()
		assert.are.equal(1, #C_Timer.ranDelays)
		assert.are.equal(0.2, C_Timer.ranDelays[1])
		local before = T.Active()
		_G.__loads = 0
		FlushTimers() -- settle: queues a redraw of the same map
		FlushTimers() -- ...which runs
		assert.are.same(before, T.Active(), "same textures, same order")
		assert.are.equal(0, _G.__loads, "nothing reloads")
		assert.are.equal(1, #C_Timer.ranDelays, "only once per open")
		C_Timer.ranDelays = nil
	end)

	it("redraws a fogged zone when exploration updates", function()
		explore({ [ELWYNN] = { Overlay(0, 0, 256, 256, { 5 }) } })
		Loader.scripts.OnEvent(Loader, "MAP_EXPLORATION_UPDATED")
		FlushTimers()
		assert.are.equal(1, #T.ActiveMasks())
		assert.are.equal(5, T.ActiveMasks()[1].src)
	end)

	it("keeps a left fogged zone loaded but hidden, with its masks", function()
		local pieces = T.Active()
		local elwynnFrame = pieces[1]:GetParent()
		open(STORMWIND)
		assert.are.equal(0, #T.ActiveMasks())
		assert.is_false(elwynnFrame:IsShown())
		for _, tex in ipairs(pieces) do
			assert.are.equal(1, #tex.masks, "still masked")
			assert(tex.src or tex.color, "still holds its file")
		end
		for _, tex in ipairs(T.Active()) do
			assert.are.equal(0, #(tex.masks or {}))
		end
		assert.is_true(T.Backdrop():IsShown())
	end)

	it("draws a map change in the same frame, without waiting a frame", function()
		explore({ [1411] = { Overlay(0, 0, 256, 256, { 3 }) } })
		open(STORMWIND)
		WorldMapFrame.mapID = 1414
		FireCallback("MapCanvas.MapSet", 1414)
		assert(T.ActiveCount() > 0, "Durotar drawn before any timer runs")
		assert.is_true(T.Overlay():IsShown())
		FlushTimers()
		explore({}); open(STORMWIND)
	end)

	it("waits for the canvas resize when the new map's art is another size", function()
		WorldMapFrame.mapID = 1414
		canvas:SetSize(500, 300) -- not yet the 1002 x 668 art layer
		FireCallback("MapCanvas.MapSet", 1414)
		assert.are.equal(STORMWIND, T.Layers()[#T.Layers()].mapID, "not drawn yet")
		canvas:SetSize(1002, 668)
		FlushTimers()
		assert.are.equal(1414, T.Layers()[#T.Layers()].mapID, "drawn after the resize")
		open(STORMWIND)
	end)

	it("switches back to a recent map without reloading anything", function()
		explore({ [ELWYNN] = { Overlay(0, 0, 256, 256, { 9 }) } })
		open(ELWYNN)
		local elwynn = T.Active()
		open(STORMWIND)
		_G.__loads = 0
		open(ELWYNN)
		assert.are.same(elwynn, T.Active(), "same textures")
		assert.is_true(elwynn[1]:GetParent():IsShown())
		assert.are.equal(0, _G.__loads)
	end)

	it("redraws in place when exploration grows: only new ground loads", function()
		local before = T.Active()
		_G.__loads = 0
		explore({ [ELWYNN] = { Overlay(0, 0, 256, 256, { 9 }), Overlay(300, 300, 64, 64, { 10 }) } })
		FlushTimers()
		local after = T.Active()
		for i, tex in ipairs(before) do assert.are.equal(tex, after[i], "reused in order") end
		assert(#after > #before, "new ground drawn")
		assert(_G.__loads > 0 and _G.__loads <= #after - #before + 1, "only the new pieces load: " .. _G.__loads)
	end)

	it("keeps every loaded tile when new ground appears earlier in the draw", function()
		-- Continent: Westfall (1436) explored, then Elwynn (1429) gets explored.
		-- Elwynn sorts first, so its pieces are drawn before Westfall's.
		explore({ [1436] = { Overlay(0, 0, 256, 256, { 21 }) } })
		open(1415)
		local before = {}
		for _, tex in ipairs(T.Active()) do before[tex] = tex.src or "ocean" end
		_G.__loads = 0
		explore({ [1429] = { Overlay(0, 0, 256, 256, { 22 }) }, [1436] = { Overlay(0, 0, 256, 256, { 21 }) } })
		FlushTimers()
		local kept, new = 0, 0
		for _, tex in ipairs(T.Active()) do
			if before[tex] then
				kept = kept + 1
				assert.are.equal(before[tex], tex.src or "ocean", "a kept texture keeps its file")
			else
				new = new + 1
			end
		end
		assert.are.equal(#T.Active(), kept + new)
		assert(kept > 0 and new > 0)
		assert(_G.__loads <= new + 1, "only Elwynn's pieces load: " .. _G.__loads .. " vs " .. new)
	end)

	it("doesn't redraw a cached map when exploration changed nothing on it", function()
		local before = T.Active()
		local tex = before[1]
		tex.src = "sentinel" -- would be overwritten by any redraw
		explore(_G.__explored) -- an update, but the same data
		FlushTimers()
		assert.are.equal("sentinel", tex.src)
		assert.are.same(before, T.Active())
		explore({}); FlushTimers()
		assert.are.equal(0, T.ActiveCount(), "a real change still redraws")
	end)

	it("keeps at most three maps and drops the oldest one's files", function()
		open(ELWYNN)
		open(STORMWIND); open(1414); open(1415)
		assert.are.equal(3, #T.Layers())
		for _, L in ipairs(T.Layers()) do
			assert(L.mapID ~= ELWYNN, "Elwynn evicted")
			for _, tex in ipairs(L.used) do assert(tex.src ~= 9, "Elwynn's file dropped") end
			for _, tex in ipairs(L.spare) do assert.is_nil(tex.src) end
		end
		explore({}); open(STORMWIND)
	end)

	it("labels a fogged zone's explored places only", function()
		explore({ [ELWYNN] = { Overlay(380, 400, 100, 100, { 31 }) } }) -- around Goldshire
		open(STORMWIND); open(ELWYNN)
		local labels = T.Labels()
		assert.are.equal(1, #labels)
		local fs = labels[1]
		assert.are.equal("Goldshire", fs.text)
		assert.are.equal("OVERLAY", fs.layer)
		assert.are.equal("OUTLINE", fs.flags)
		local anchor = fs.point[2]
		assert.are.equal("CENTER", fs.point[1])
		assert(math.abs(anchor.point[4] - 0.424 * 1002) < 1e-6 and math.abs(anchor.point[5] + 0.666 * 668) < 1e-6, "placed")
		assert(math.abs(fs.size - 12 * 0.85) < 1e-6, "sized")
		assert.is_true(fs.shown)
	end)

	it("names every district of an unfogged city", function()
		open(STORMWIND)
		local names = {}
		for _, fs in ipairs(T.Labels()) do names[fs.text] = fs end
		assert.are.equal(#NS.LABELS[STORMWIND], #T.Labels())
		assert(names["Trade District"] and names["Mage Quarter"] and names["Old Town"])
		assert.are.same({ 1, 0.82, 0, 1 }, names["Trade District"].textColor)
		open(ELWYNN)
	end)

	it("adds labels as exploration grows, and hides them on continents", function()
		explore({ [ELWYNN] = { Overlay(380, 400, 100, 100, { 31 }), Overlay(0, 0, 1002, 668, { 32 }) } })
		FlushTimers()
		local n = #NS.LABELS[ELWYNN]
		assert.are.equal(n, #T.Labels(), "fully explored: every name")
		open(1415)
		assert.are.equal(0, #T.Labels())
		explore({}); open(STORMWIND)
	end)

	it("puts a halo under the player and follows them", function()
		_G.__playerPos[STORMWIND] = { 0.5, 0.25 }
		T.UpdateHalo()
		local halo = T.Halo()
		assert.are.equal(3, #halo)
		for i, t in ipairs(halo) do
			assert.is_true(t.shown)
			assert.are.same({ 0, 0, 0 }, { t.vertex[1], t.vertex[2], t.vertex[3] })
			local anchor = t.point[2]
			assert.are.same({ 501, -167 }, { anchor.point[4], anchor.point[5] })
			if i > 1 then assert(t.w < halo[i - 1].w, "rings shrink") end
		end
		assert.are.equal(46, halo[1].w)
		_G.__playerPos[STORMWIND] = { 0.5, 0.5 }
		T.UpdateHalo()
		assert.are.same({ 501, -334 }, { halo[1].point[2].point[4], halo[1].point[2].point[5] })
	end)

	it("keeps labels and the halo the same size on screen through a zoom", function()
		local screen = T.Halo()[1]:GetParent()
		local canvasLayer = screen:GetParent()
		for _, scale in ipairs({ 1, 1.37, 2, 3.5 }) do
			canvasLayer.scale = scale -- the canvas zooms
			T.ApplyScreenScale()
			assert(math.abs(screen:GetEffectiveScale() - UIParent:GetEffectiveScale()) < 1e-9, "screen-sized at " .. scale)
		end
		local set = screen.ownScale
		T.ApplyScreenScale()
		assert.are.equal(set, screen.ownScale, "no SetScale when nothing changed")
		canvasLayer.scale = nil
		T.ApplyScreenScale()
	end)

	it("hides the halo off the map, on secret positions and on maps it leaves alone", function()
		local halo = T.Halo()
		_G.__playerPos[STORMWIND] = nil
		T.UpdateHalo()
		assert.is_false(halo[1].shown)
		local sx = 0.3
		_G.__secret[sx] = true
		_G.__playerPos[STORMWIND] = { sx, 0.3 }
		T.UpdateHalo()
		assert.is_false(halo[1].shown)
		_G.__secret[sx] = nil
		T.UpdateHalo()
		assert.is_true(halo[1].shown)
		open(9999)
		assert.is_false(halo[1].shown)
		_G.__playerPos[ELWYNN] = { 0.5, 0.5 }
		open(ELWYNN)
		assert.is_true(halo[1].shown, "moves to the newly open map")
		assert.are.equal(T.Active()[1] and T.Active()[1]:GetParent() or halo[1]:GetParent(), halo[1]:GetParent())
		_G.__playerPos = {}
		open(STORMWIND)
	end)

	it("ignores exploration updates on unfogged maps", function()
		local first = T.Active()[1]
		Loader.scripts.OnEvent(Loader, "MAP_EXPLORATION_UPDATED")
		FlushTimers()
		assert.are.equal(first, T.Active()[1])
	end)

	it("fogs the continent from every zone on it", function()
		explore({
			[ELWYNN] = { Overlay(0, 0, 256, 256, { 1 }) },
			[1436] = { Overlay(0, 0, 256, 256, { 2 }) },
			[1411] = { Overlay(0, 0, 256, 256, { 3 }) }, -- Kalimdor: not here
		})
		open(1415)
		assert.is_false(T.Backdrop():IsShown())
		local srcs = {}
		for _, m in ipairs(T.ActiveMasks()) do srcs[m.src] = m end
		assert(srcs[1] and srcs[2], "both Eastern Kingdoms zones")
		assert.is_nil(srcs[3])
		-- Elwynn at 0.40, 0.60 of the continent; its 256 px overlay is 0.1 of 256 px
		assert(math.abs(srcs[1].point[4] - 0.4 * 1002) < 1e-6 and math.abs(srcs[1].point[5] + 0.6 * 668) < 1e-6, "placed")
		assert(math.abs(srcs[1].w - 25.6) < 1e-6, "scaled")
		local tiles = 0
		for _, tex in ipairs(T.Active()) do
			assert(tex.masks and #tex.masks == 1, "masked")
			if type(tex.src) == "string" then
				tiles = tiles + 1
				assert(tex.src:find("EasternKingdomsHD", 1, true), tex.src)
			end
		end
		assert(tiles > 0 and tiles < 704, "only the revealed HD tiles")
	end)

	it("fogs the world map through the parent chain", function()
		open(947)
		local srcs = {}
		for _, m in ipairs(T.ActiveMasks()) do srcs[m.src] = m end
		assert(srcs[1] and srcs[2] and srcs[3], "zones on both continents")
		-- Elwynn: 0.5 + 0.40 * 0.5 = 0.70 across; Durotar: 0.60 * 0.5 = 0.30
		assert(math.abs(srcs[1].point[4] - 0.70 * 1002) < 1e-6, "x " .. srcs[1].point[4])
		assert(math.abs(srcs[3].point[4] - 0.30 * 1002) < 1e-6, "Durotar x " .. srcs[3].point[4])
		assert(math.abs(srcs[1].w - 0.05 * 256) < 1e-6, "scaled")
	end)

	it("shows only the stock continent when nothing is explored", function()
		explore({})
		open(1414)
		assert.are.equal(0, T.ActiveCount())
		assert.is_true(T.Overlay():IsShown())
	end)

	it("falls back to unfogged art when the exploration API is missing", function()
		local saved = C_MapExplorationInfo.GetExploredMapTextures
		C_MapExplorationInfo.GetExploredMapTextures = nil
		T.ResetHD() -- cached fogged layers are stale
		open(ELWYNN)
		assert(T.ActiveCount() > 0, "whole zone")
		assert.is_true(T.Backdrop():IsShown())
		open(1414)
		assert.are.equal(704, T.ActiveCount())
		C_MapExplorationInfo.GetExploredMapTextures = saved
	end)

	it("falls back to the stock map when fogged HD art can't be loaded", function()
		T.ResetHD(); _G.__missingArt = true
		explore({ [ELWYNN] = { Overlay(0, 0, 256, 256, { 1 }) } })
		open(1415)
		assert.are.equal(0, T.ActiveCount())
		assert.is_false(T.Overlay():IsShown())
		_G.__missingArt = nil; T.ResetHD(); explore({})
	end)

	-- The tests from here on use full continent grids, so fog is off.
	it("draws the full HD continent grid", function()
		_G.__savedExp = C_MapExplorationInfo.GetExploredMapTextures
		C_MapExplorationInfo.GetExploredMapTextures = nil
		open(1414)
		assert.are.equal(32 * 22, T.ActiveCount())
		assert.is_true(T.Backdrop():IsShown())
		local last = T.Active()[#T.Active()]
		assert(last.src:find("KalimdorHD\\kalimdorhd704", 1, true), last.src)
		-- bottom row is clipped: 5461 - 21*256 = 85 px of 256
		assert(math.abs(last.tc[4] - 85 / 256) < 1e-9, "clipped texcoord")
		assert(math.abs(last.point[5] * -1 + last.h - 668) < 1e-6, "ends at canvas bottom")
	end)

	it("hides itself on maps it has no art for", function()
		open(1581)
		assert.are.equal(0, T.ActiveCount())
		assert.is_false(T.Overlay():IsShown())
	end)

	it("falls back to the stock map when the art can't be loaded", function()
		T.ResetHD(); _G.__missingArt = true
		open(1415)
		assert.are.equal(0, T.ActiveCount())
		assert.is_false(T.Overlay():IsShown())
		_G.__missingArt = nil
		open(STORMWIND)
		assert(T.ActiveCount() > 0, "zones still drawn")
		T.ResetHD()
	end)

	it("skips HD when the art folder is absent", function()
		T.ResetHD(); _G.__noArtFolder = true
		open(947)
		assert.are.equal(0, T.ActiveCount())
		_G.__noArtFolder = nil; T.ResetHD()
	end)

	it("does nothing while the map is closed", function()
		WorldMapFrame:Hide()
		open(1414)
		assert.are.equal(0, T.ActiveCount())
		WorldMapFrame:Show()
		FireCallback("WorldMapOnShow"); FlushTimers()
		assert.are.equal(704, T.ActiveCount())
	end)

	it("follows a replaced canvas", function()
		local new = setmetatable({}, getmetatable(canvas))
		for k, v in pairs(canvas) do new[k] = v end
		new.scripts = {}
		WorldMapFrame.ScrollContainer.Child = new
		FireCallback("MapCanvas.MapSet", 1414); FlushTimers()
		assert.are.equal(new, T.Overlay():GetParent())
		assert.are.equal(704, T.ActiveCount())
		WorldMapFrame.ScrollContainer.Child = canvas
	end)

	it("coalesces a burst into one draw", function()
		C_MapExplorationInfo.GetExploredMapTextures = _G.__savedExp
		WorldMapFrame.mapID = STORMWIND
		FireCallback("MapCanvas.MapSet", STORMWIND)
		FireCallback("WorldMapOnShow")
		FireCallback("WorldMapMaximized")
		FlushTimers()
		local n = T.ActiveCount()
		assert(n > 0 and n < 704, "one zone draw")
	end)
end)

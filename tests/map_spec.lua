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
C_MapExplorationInfo = { GetExploredMapTextures = function(id) return _G.__explored[id] or {} end }
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
		for _, tex in ipairs(T.Active) do
			assert(inside(tex, 0, 0, 1002, 668), "inside canvas")
			assert(type(tex.src) == "number", "fdid")
			assert.is_nil(tex.masks and tex.masks[1])
			local u0, u1 = tex.tc[1], tex.tc[2]
			assert(math.abs((u1 - u0) * zone.regions[1].tw * sx - tex.w) < 1e-6, "texcoord matches width")
		end
	end)

	it("skips redraw when nothing changed", function()
		local first = T.Active[1]
		open(STORMWIND)
		assert.are.equal(first, T.Active[1])
	end)

	it("shows only the stock map on a fogged zone with nothing explored", function()
		_G.__explored = {}
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
		_G.__explored = { [ELWYNN] = {
			Overlay(100, 50, 300, 200, { 111, 112 }),
			Overlay(600, 300, 100, 100, { 999 }, true), -- hover highlight: ignored
		} }
		open(STORMWIND) -- leave and come back, so the zone is drawn fresh
		open(ELWYNN)
		assert.are.equal(2, #T.ActiveMasks)
		local m1, m2 = T.ActiveMasks[1], T.ActiveMasks[2]
		assert.are.equal(111, m1.src); assert.are.equal("CLAMP", m1.wrap)
		assert.are.equal(112, m2.src)
		-- first tile is a full 256; the second is 44 px wide in a 64 px file,
		-- 200 px tall in a 256 px file
		assert.are.same({ 256, 256 }, { m1.w, m1.h })
		assert.are.same({ 64, 256 }, { m2.w, m2.h })
		assert.are.same({ 100, -50 }, { m1.point[4], m1.point[5] })
		assert.are.same({ 356, -50 }, { m2.point[4], m2.point[5] })
		local ocean, tiles = 0, 0
		for _, tex in ipairs(T.Active) do
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
		_G.__explored = { [1436] = { Overlay(900, 0, 102, 256, { 4242 }) } }
		open(STORMWIND); open(ELWYNN)
		assert.are.equal(1, #T.ActiveMasks)
		local m = T.ActiveMasks[1]
		assert.are.equal(4242, m.src)
		assert(math.abs(m.point[4] - 98.4) < 1e-6, "x " .. m.point[4])
		-- y: Westfall's top sits at 0.2 of Elwynn's height
		assert(math.abs(m.point[5] + 0.2 * 668) < 1e-6, "y " .. m.point[5])
		for _, tex in ipairs(T.Active) do assert(tex.masks and tex.masks[1] == m, "masked") end
	end)

	it("redraws once more after masks have had time to load", function()
		_G.__explored = { [ELWYNN] = { Overlay(0, 0, 256, 256, { 7 }) } }
		open(STORMWIND)
		WorldMapFrame.mapID = ELWYNN
		FireCallback("WorldMapOnShow") -- a fresh open resets the settle
		C_Timer.ranDelays = {}
		FlushTimers() -- draws, queues the settle redraw
		assert.are.equal(1, #C_Timer.ranDelays)
		assert.are.equal(0.2, C_Timer.ranDelays[1])
		local before = T.Active[1]
		FlushTimers() -- settle: queues a fresh draw of the same map
		FlushTimers() -- ...which runs
		assert(before and T.Active[1], "drawn both times")
		assert.are.equal(1, #C_Timer.ranDelays, "only once per open")
		C_Timer.ranDelays = nil
	end)

	it("redraws a fogged zone when exploration updates", function()
		_G.__explored = { [ELWYNN] = { Overlay(0, 0, 256, 256, { 5 }) } }
		Loader.scripts.OnEvent(Loader, "MAP_EXPLORATION_UPDATED")
		FlushTimers()
		assert.are.equal(1, #T.ActiveMasks)
		assert.are.equal(5, T.ActiveMasks[1].src)
	end)

	it("releases masks cleanly when leaving a fogged zone", function()
		local pieces = {}
		for i, tex in ipairs(T.Active) do pieces[i] = tex end
		open(STORMWIND)
		assert.are.equal(0, #T.ActiveMasks)
		for _, tex in ipairs(pieces) do
			assert.are.equal(0, #(tex.masks or {}))
			assert.is_nil(T.MaskOf[tex])
		end
		assert.is_true(T.Backdrop():IsShown())
	end)

	it("ignores exploration updates on unfogged maps", function()
		local first = T.Active[1]
		Loader.scripts.OnEvent(Loader, "MAP_EXPLORATION_UPDATED")
		FlushTimers()
		assert.are.equal(first, T.Active[1])
	end)

	it("fogs the continent from every zone on it", function()
		_G.__explored = {
			[ELWYNN] = { Overlay(0, 0, 256, 256, { 1 }) },
			[1436] = { Overlay(0, 0, 256, 256, { 2 }) },
			[1411] = { Overlay(0, 0, 256, 256, { 3 }) }, -- Kalimdor: not here
		}
		open(1415)
		assert.is_false(T.Backdrop():IsShown())
		local srcs = {}
		for _, m in ipairs(T.ActiveMasks) do srcs[m.src] = m end
		assert(srcs[1] and srcs[2], "both Eastern Kingdoms zones")
		assert.is_nil(srcs[3])
		-- Elwynn at 0.40, 0.60 of the continent; its 256 px overlay is 0.1 of 256 px
		assert(math.abs(srcs[1].point[4] - 0.4 * 1002) < 1e-6 and math.abs(srcs[1].point[5] + 0.6 * 668) < 1e-6, "placed")
		assert(math.abs(srcs[1].w - 25.6) < 1e-6, "scaled")
		local tiles = 0
		for _, tex in ipairs(T.Active) do
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
		for _, m in ipairs(T.ActiveMasks) do srcs[m.src] = m end
		assert(srcs[1] and srcs[2] and srcs[3], "zones on both continents")
		-- Elwynn: 0.5 + 0.40 * 0.5 = 0.70 across; Durotar: 0.60 * 0.5 = 0.30
		assert(math.abs(srcs[1].point[4] - 0.70 * 1002) < 1e-6, "x " .. srcs[1].point[4])
		assert(math.abs(srcs[3].point[4] - 0.30 * 1002) < 1e-6, "Durotar x " .. srcs[3].point[4])
		assert(math.abs(srcs[1].w - 0.05 * 256) < 1e-6, "scaled")
	end)

	it("shows only the stock continent when nothing is explored", function()
		_G.__explored = {}
		open(1414)
		assert.are.equal(0, T.ActiveCount())
		assert.is_true(T.Overlay():IsShown())
	end)

	it("falls back to unfogged art when the exploration API is missing", function()
		local saved = C_MapExplorationInfo.GetExploredMapTextures
		C_MapExplorationInfo.GetExploredMapTextures = nil
		open(ELWYNN)
		assert(T.ActiveCount() > 0, "whole zone")
		assert.is_true(T.Backdrop():IsShown())
		open(1414)
		assert.are.equal(704, T.ActiveCount())
		C_MapExplorationInfo.GetExploredMapTextures = saved
	end)

	it("falls back to the stock map when fogged HD art can't be loaded", function()
		T.ResetHD(); _G.__missingArt = true
		_G.__explored = { [ELWYNN] = { Overlay(0, 0, 256, 256, { 1 }) } }
		open(1415)
		assert.are.equal(0, T.ActiveCount())
		assert.is_false(T.Overlay():IsShown())
		_G.__missingArt = nil; T.ResetHD(); _G.__explored = {}
	end)

	-- The tests from here on use full continent grids, so fog is off.
	it("draws the full HD continent grid", function()
		_G.__savedExp = C_MapExplorationInfo.GetExploredMapTextures
		C_MapExplorationInfo.GetExploredMapTextures = nil
		open(1414)
		assert.are.equal(32 * 22, T.ActiveCount())
		assert.is_true(T.Backdrop():IsShown())
		local last = T.Active[#T.Active]
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

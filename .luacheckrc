std = "lua51"
max_line_length = false
exclude_files = { ".release/" }

-- This addon writes no globals at all.
globals = {}

-- Every WoW global it reads.
read_globals = {
	"CreateFrame", "C_Timer", "C_AddOns", "C_Map", "C_MapExplorationInfo", "EventRegistry", "WorldMapFrame",
	"geterrorhandler", "wipe", "CreateVector2D", "UIParent", "issecretvalue",
}

files["Zones.lua"] = { max_line_length = false }
files["Labels.lua"] = { max_line_length = false }
-- The spec fakes the client, so it writes the WoW globals the addon reads.
files["tests/"] = {
	std = "+busted",
	globals = {
		"CreateFrame", "C_Timer", "C_AddOns", "C_Map", "C_MapExplorationInfo", "EventRegistry", "WorldMapFrame",
		"geterrorhandler", "wipe", "CreateVector2D", "UIParent", "issecretvalue", "print", "FireCallback", "FlushTimers", "Loader", "NS", "Canvas",
	},
}

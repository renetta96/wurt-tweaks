-- This information tells other players more about the mod
name = "Wurt And Merm AI Tweaks"
description = ""
author = "Zeta"
version = "1.1.0" -- This is the version of the template. Change it to your own number.

-- This is the URL name of the mod's thread on the forum; the part after the ? and before the first & in the url
forumthread = ""


-- This lets other players know if your mod is out of date, update it to match the current version in the game
api_version = 10

-- Compatible with Don't Starve Together
dst_compatible = true

-- Not compatible with Don't Starve
dont_starve_compatible = false
reign_of_giants_compatible = false

-- Character mods need this set to true
all_clients_require_mod = true

icon_atlas = "modicon.xml"
icon = "modicon.tex"

-- The mod's tags displayed on the server list
server_filter_tags = {
"character",
}

configuration_options = {
	{
		name = 'ENABLE_SMARTER_MERM',
		label = 'Enable smarter merm',
		options = {
			{ description = 'Yes', data = true },
			{ description = 'No', data = false }
		},
		default = true
	},
	{
		name = 'MERM_EPIC_DODGE_CHANCE',
		label = 'Merm boss attack dodge chance',
		options = {
			{ description = 'Disabled', data = 0 },
			{ description = '25%', data = 0.25 },
			{ description = '50%', data = 0.5 },
			{ description = '75%', data = 0.75 },
			{ description = '100%', data = 1 }
		},
		default = 1,
		hover = 'How likely merms try to dodge boss attack'
	},
	{
		name = 'ENABLE_WURT_MOD',
		label = 'Enable Wurt mod',
		options = {
			{ description = 'Yes', data = true },
			{ description = 'No', data = false }
		},
		default = false
	},
}
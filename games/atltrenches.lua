-- Running the script again: unload the copy that's already running first, before its replacement loads the ESP
if getgenv().SuperNovaUnload then
    pcall(getgenv().SuperNovaUnload)
    getgenv().SuperNovaUnload = nil
end

local OasisUI = loadstring(game:HttpGet("https://github.com/Mold53/OasisUI/releases/download/v1.6.0/OasisUI.lua"))()
local ESPLibrary = loadstring(game:HttpGet("https://raw.githubusercontent.com/idonotlikeppl/supernovav2/refs/heads/main/util/exunys-fork-isaeva.lua"))()
local Players = game:GetService("Players")
local Player = Players.LocalPlayer
local Remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
local Workspace = game:GetService("Workspace")
local GameFolder = Workspace:WaitForChild("GameFolder")
local Locations = GameFolder:WaitForChild("Locations")
local LocationsTBL = {
    ["Marked"] = Locations:WaitForChild("Google Maps"):WaitForChild("MapLocations"),

}
local DrawingFonts = Drawing.Fonts or {UI = 0, System = 1, Plex = 2, Monospace = 3}
ESPLibrary.Load()

--// Binding helpers

-- ESP tables are looked up on every write: the ESP replaces them on Restart / UpdateConfiguration.
local function Env()
	return getgenv().ExunysDeveloperESP
end

local function Resolve(Path)
	local Keys = string.split(Path, ".")
	local Table = Env()

	for Index = 1, #Keys - 1 do
		Table = Table and Table[Keys[Index]]
	end

	return Table, Keys[#Keys]
end

local function Read(Path)
	local Table, Key = Resolve(Path)
	return Table and Table[Key]
end

local function Write(Path, Value)
	local Table, Key = Resolve(Path)

	if Table then
		Table[Key] = Value
	end
end

local function Flag(Path)
	return "ESP." .. Path
end

local function Toggle(Container, Title, Path, Description)
	return Container:Toggle({
		Title = Title,
		Description = Description,
		Default = Read(Path) == true,
		Flag = Flag(Path),
		Callback = function(Value) Write(Path, Value) end
	})
end

local function Checkbox(Container, Title, Path, Description)
	return Container:Checkbox({
		Title = Title,
		Description = Description,
		Default = Read(Path) == true,
		Flag = Flag(Path),
		Callback = function(Value) Write(Path, Value) end
	})
end

local function Slider(Container, Title, Path, Min, Max, Step, Suffix, Description)
	return Container:Slider({
		Title = Title,
		Description = Description,
		Min = Min,
		Max = Max,
		Step = Step or 1,
		Suffix = Suffix,
		Default = Read(Path) or Min,
		Flag = Flag(Path),
		Callback = function(Value) Write(Path, Value) end
	})
end

local function Color(Container, Title, Path)
	return Container:ColorPicker({
		Title = Title,
		Default = Read(Path) or Color3.new(1, 1, 1),
		Flag = Flag(Path),
		Callback = function(Value) Write(Path, Value) end
	})
end

-- Choices maps the shown names to the values the ESP expects, in display order: {{"Bottom", 1}, ...}
local function Choice(Container, Title, Path, Choices, Kind, Description)
	local Names, Values, Default = {}, {}, nil

	for _, Pair in next, Choices do
		table.insert(Names, Pair[1])
		Values[Pair[1]] = Pair[2]

		if Pair[2] == Read(Path) then
			Default = Pair[1]
		end
	end

	return Container[Kind or "Segmented"](Container, {
		Title = Title,
		Description = Description,
		Values = Names,
		Default = Default or Names[1],
		Flag = Flag(Path),
		Callback = function(Name)
			if Values[Name] ~= nil then
				Write(Path, Values[Name])
			end
		end
	})
end

-- A visual's card: the switch drives Properties.<Name>.Enabled
local function VisualCard(Container, Title, Name, Icon, Description, Side, Extra)
	local Def = {
		Title = Title,
		Description = Description,
		Icon = Icon,
		Side = Side,
		Default = Read("Properties." .. Name .. ".Enabled") == true,
		Flag = Flag("Properties." .. Name .. ".Enabled"),
		Keybind = false,
		Callback = function(Enabled) Write("Properties." .. Name .. ".Enabled", Enabled) end
	}

	for Index, Value in next, Extra or {} do
		Def[Index] = Value
	end

	return Container:Module(Def)
end

-- Main + outline color block shared by most visuals
local function ColorBlock(Module, Name, HasMain, HasOutline)
	local Group = Module:Group({Title = "Colors", Icon = "palette", Opened = true})
	local Base = "Properties." .. Name .. "."

	if HasMain ~= false then
		Color(Group, "Color", Base .. "Color")
	end

	if HasOutline ~= false then
		local Outline = Checkbox(Group, "Outline", Base .. "Outline")
		Color(Group, "Outline color", Base .. "OutlineColor"):DependsOn(Outline, nil, "Hide")
	end

	return Group
end

local settings = {
    CandyFarm = false,
    LoadMap = true,
    AreaTime = 5,
    GunFarm = false,
    Check = false,
}

-- GetProductInfo is a web call: if it fails, the menu still opens instead of the whole script erroring
local NameOk, GameName = pcall(function()
    return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name
end)
GameName = NameOk and GameName or "ATL Trenches"

local Window = OasisUI:CreateWindow({
    Title = GameName,
    Subtitle = "✨SuperNova💫 vInfDev",
    Folder = "shenyu_u",
    DefaultConfig = "default",
    AutoSave = true,
    AutoLoad = false -- loaded by hand once the whole menu is built
})

getgenv().SuperNovaUnload = function()
	OasisUI:Unload()
end

OasisUI:OnUnload(function()
	-- Stop the farms too; their loop outlives the menu otherwise
	settings.CandyFarm, settings.GunFarm, settings.Check = false, false, false

	local Environment = Env()

	if Environment and Environment.Exit then
		pcall(Environment.Exit, Environment)
	end
end)

--// Overview

local Overview = Window:Tab({Title = "Overview", Icon = "house"})

do
	local Status = Overview:Section({Title = "Status", Icon = "activity", Side = "Left"})
	local Wrapped = Status:Label({Text = "Wrapped targets", Value = "0"})
	local PlayersLabel = Status:Label({Text = "Players", Value = "0"})
	local Visible = Status:Label({Text = "Drawing now", Value = "0"})

	task.spawn(function()
		while task.wait(0.5) do
			local Environment = Env()

			if not Environment or not Environment.UtilityAssets then
				break
			end

			local Count, PlayerCount, ReadyCount = 0, 0, 0

			for _, Entry in next, Environment.UtilityAssets.WrappedObjects do
				Count += 1
				PlayerCount += Entry.IsAPlayer and 1 or 0
				ReadyCount += (Entry.Checks and Entry.Checks.Ready) and 1 or 0
			end

			Wrapped:SetValue(tostring(Count))
			PlayersLabel:SetValue(tostring(PlayerCount))
			Visible:SetValue(tostring(ReadyCount))
		end
	end)

	local Actions = Overview:Section({Title = "Actions", Icon = "zap", Side = "Right"})
	Actions:Button({Title = "Restart ESP", Tooltip = "Rebuilds every visual. Use after changing Update on, or if something stops drawing.", Icon = "refresh-cw", Callback = function()
		task.spawn(function()
			Env():Restart()
			OasisUI:Notify({Title = "ESP", Content = "Restarted.", Type = "Success", Duration = 3})
		end)
	end})
	Actions:Button({Title = "Unload", Icon = "power", Style = "Danger", Confirm = "Unload the ESP and the menu?", Callback = function()
		OasisUI:Unload()
	end})

	--// Session kills and deaths

	local Session = Overview:Section({Title = "Session", Icon = "swords", Side = "Left"})
	local KillsLabel = Session:Label({Text = "Kills", Value = "0", ValueColor = "Success"})
	local DeathsLabel = Session:Label({Text = "Deaths", Value = "0", ValueColor = "Danger"})
	local RatioLabel = Session:Label({Text = "K/D", Value = "0.00"})
	local TimeLabel = Session:Label({Text = "Session time", Value = "0:00"})

	local Kills, Deaths, StartTime = 0, 0, os.clock()
	local CountedDeaths = setmetatable({}, {__mode = "k"}) -- humanoids already counted, so a death isn't counted twice

	local function UpdateSession()
		KillsLabel:SetValue(tostring(Kills))
		DeathsLabel:SetValue(tostring(Deaths))
		RatioLabel:SetValue(("%.2f"):format(Kills / math.max(Deaths, 1)))
	end

	-- The server fires MurderRemote to the killer on every kill
	task.spawn(function()
		local MurderRemote = Remotes:WaitForChild("MurderRemote", 30)

		if MurderRemote then
			MurderRemote.OnClientEvent:Connect(function()
				Kills += 1
				UpdateSession()
			end)
		else
			warn("SuperNova > Remotes.MurderRemote not found, kills will not be counted.")
		end
	end)

	local function WatchHumanoid(Humanoid)
		Humanoid.Died:Connect(function()
			if CountedDeaths[Humanoid] then
				return
			end

			CountedDeaths[Humanoid] = true
			Deaths += 1
			UpdateSession()
		end)
	end

	-- Deaths: only your own characters are watched
	local function OnCharacter(Character)
		local Humanoid = Character:WaitForChild("Humanoid", 10)

		if Humanoid then
			WatchHumanoid(Humanoid)
		end
	end

	if Player.Character then
		task.spawn(OnCharacter, Player.Character)
	end

	Player.CharacterAdded:Connect(OnCharacter)

	Session:Button({Title = "Reset counter", Icon = "rotate-ccw", Style = "Ghost", Callback = function()
		Kills, Deaths, StartTime = 0, 0, os.clock()
		UpdateSession()
	end})

	task.spawn(function()
		while task.wait(1) do
			if not Env() then -- menu unloaded
				break
			end

			local Elapsed = math.floor(os.clock() - StartTime)
			TimeLabel:SetValue(Elapsed >= 3600 and ("%d:%02d:%02d"):format(Elapsed // 3600, Elapsed % 3600 // 60, Elapsed % 60) or ("%d:%02d"):format(Elapsed // 60, Elapsed % 60))
		end
	end)
end

--// Tabs: declared together so the sidebar and the sub-tab chips always come out in this order

Window:TabSection("Player")

local PlayerTab = Window:Tab({Title = "Player", Icon = "user"})
local GunsTab = PlayerTab:SubTab({Title = "Guns", Icon = "crosshair"})
local AimTab = PlayerTab:SubTab({Title = "Aim", Icon = "target"})
local FistsTab = PlayerTab:SubTab({Title = "Fists", Icon = "swords"})
local AntiAimTab = PlayerTab:SubTab({Title = "Anti-aim", Icon = "orbit"})
local CharacterTab = PlayerTab:SubTab({Title = "Character", Icon = "user-round"})
local IdentityTab = PlayerTab:SubTab({Title = "Identity", Icon = "id-card"})

local Visual = Window:Tab({Title = "Visual", Icon = "eye"}) -- ESP sub-tabs are created with the ESP below, Spectate last

Window:TabSection("World")

local World = Window:Tab({Title = "World", Icon = "globe"})
local InteractTab = World:SubTab({Title = "Interactions", Icon = "hand"})
local TravelTab = World:SubTab({Title = "Travel", Icon = "navigation"})
local PlayersTab = World:SubTab({Title = "Players", Icon = "users"})
local ContractsTab = World:SubTab({Title = "Contracts", Icon = "target"})
local RenderTab = World:SubTab({Title = "Render", Icon = "sun"})

local VehicleTab = Window:Tab({Title = "Vehicle", Icon = "gauge"})
local TuningTab = VehicleTab:SubTab({Title = "Tuning", Icon = "sliders-horizontal"})
local TheftTab = VehicleTab:SubTab({Title = "Theft", Icon = "key"})
local GarageTab = VehicleTab:SubTab({Title = "Garage", Icon = "car"})
local DamageTab = VehicleTab:SubTab({Title = "Damage", Icon = "zap"})

local EconomyTab = Window:Tab({Title = "Economy", Icon = "gem"})
local BankingTab = EconomyTab:SubTab({Title = "Banking", Icon = "database"})
local PrintersTab = EconomyTab:SubTab({Title = "Printers", Icon = "layers"})
local ChecksTab = EconomyTab:SubTab({Title = "Checks", Icon = "file-text"})
local JobsTab = EconomyTab:SubTab({Title = "Jobs", Icon = "package"})
local ShopsTab = EconomyTab:SubTab({Title = "Shops", Icon = "tag"})

Window:TabSection("Farming")

local Automation = Window:Tab({Title = "Automation", Icon = "cog"})
local Autofarm = Automation:SubTab({Title = "Autofarm", Icon = "zap"})
local Automisc = Automation:SubTab({Title = "Misc", Icon = "settings-2"})

--// ESP: General

local General = Visual:SubTab({Title = "General", Icon = "settings-2"})

do
	-- One card per utility; the card's switch drives the setting at Path
	local function Card(Title, Path, Icon, Description, Side, Extra)
		local Def = {
			Title = Title,
			Description = Description,
			Icon = Icon,
			Side = Side,
			Default = Read(Path) == true,
			Flag = Flag(Path),
			Keybind = false,
			Callback = function(Enabled) Write(Path, Enabled) end
		}

		for Index, Value in next, Extra or {} do
			Def[Index] = Value
		end

		return General:Module(Def)
	end

	Card("ESP", "Settings.Enabled", "scan", "Master switch for every visual and the crosshair.", "Left", {
		Keybind = {Key = Enum.KeyCode.V, Mode = "Toggle"}
	})

	local TeamCheck = Card("Team check", "Settings.TeamCheck", "shield-check", "Hide players on your team.", "Left")
	Choice(TeamCheck, "Team decided by", "DeveloperSettings.TeamCheckOption", {{"TeamColor", "TeamColor"}, {"Team", "Team"}}, nil, "Which player property counts as the team. Also used by Team colors.")

	Card("Alive check", "Settings.AliveCheck", "heart", "Hide dead players and NPCs.", "Left")

	local TeamColors = Card("Team colors", "Settings.EnableTeamColors", "users", "Draw teammates in their own color.", "Right")
	Color(TeamColors, "Team color", "Settings.TeamColor")

	Card("NPC ESP", "Settings.EntityESP", "bot", "Draw models with a Humanoid that aren't players.", "Right")
	Card("Cache positions", "Settings.CachePositions", "gauge", "Skip redraws while a target stands still. Saves FPS.", "Right")
end

--// Visuals

local Visuals = Visual:SubTab({Title = "Overlays", Icon = "scan"})
local Models = Visuals

do
	--// Text (names, distance, health, tool)

	local Text = VisualCard(Visuals, "Text", "ESP", "type", "Name, distance, health and held tool above and below each target.", "Left")
	local Lines = Text:Group({Title = "Shown", Icon = "list", Opened = true})
	Checkbox(Lines, "Display name", "Properties.ESP.DisplayDisplayName")
	Checkbox(Lines, "Username", "Properties.ESP.DisplayName")
	Checkbox(Lines, "Health", "Properties.ESP.DisplayHealth")
	Checkbox(Lines, "Distance", "Properties.ESP.DisplayDistance")
	Checkbox(Lines, "Held tool", "Properties.ESP.DisplayTool")

	local Style = Text:Group({Title = "Style", Icon = "brush"})
	Choice(Style, "Font", "Properties.ESP.Font", {{"UI", DrawingFonts.UI}, {"System", DrawingFonts.System}, {"Plex", DrawingFonts.Plex}, {"Monospace", DrawingFonts.Monospace}}, "Dropdown")
	Slider(Style, "Size", "Properties.ESP.Size", 8, 32, 1, " px")
	Checkbox(Style, "Scale with distance", "Properties.ESP.RelativeFontSize", "Smaller text for far targets.")
	Slider(Style, "Offset", "Properties.ESP.Offset", 0, 40, 1, " px", "Gap between the box and the text.")
	Slider(Style, "Opacity", "Properties.ESP.Transparency", 0, 1, 0.05)
	ColorBlock(Text, "ESP")

	--// Tracers

	local Tracer = VisualCard(Visuals, "Tracers", "Tracer", "navigation", "A line from your screen to each target.", "Left")
	Choice(Tracer, "Origin", "Properties.Tracer.Position", {{"Bottom", 1}, {"Center", 2}, {"Mouse", 3}})
	Slider(Tracer, "Thickness", "Properties.Tracer.Thickness", 1, 6, 1, " px")
	Slider(Tracer, "Opacity", "Properties.Tracer.Transparency", 0, 1, 0.05)
	ColorBlock(Tracer, "Tracer")

	--// Boxes

	local Box = VisualCard(Visuals, "Boxes", "Box", "square", "2D, 3D or corner boxes around each target.", "Right")
	local BoxType = Choice(Box, "Type", "Properties.Box.Type", {{"2D", 1}, {"3D", 2}, {"Corner", 3}})
	Slider(Box, "Corner length", "Properties.Box.LineSize", 2, 20, 1, " px"):DependsOn(BoxType, function(Value) return Value == "Corner" end, "Hide")
	Slider(Box, "Thickness", "Properties.Box.Thickness", 1, 6, 1, " px")
	Slider(Box, "Opacity", "Properties.Box.Transparency", 0, 1, 0.05)

	local Fill = Box:Group({Title = "Fill", Icon = "droplet"})
	local Filled = Checkbox(Fill, "Fill box", "Properties.Box.FillSquare", "Not drawn for 3D boxes.")
	Color(Fill, "Fill color", "Properties.Box.FillColor"):DependsOn(Filled, nil, "Hide")
	Slider(Fill, "Fill opacity", "Properties.Box.FillTransparency", 0, 1, 0.05):DependsOn(Filled, nil, "Hide")
	ColorBlock(Box, "Box")

	--// Health bar

	local Health = VisualCard(Visuals, "Health bar", "HealthBar", "heart", "Colored by health, from red to green.", "Right")
	Choice(Health, "Side", "Properties.HealthBar.Position", {{"Top", 1}, {"Bottom", 2}, {"Left", 3}, {"Right", 4}})
	Slider(Health, "Offset", "Properties.HealthBar.Offset", 4, 12, 1, " px")
	Slider(Health, "Thickness", "Properties.HealthBar.Thickness", 1, 6, 1, " px")
	Slider(Health, "Opacity", "Properties.HealthBar.Transparency", 0, 1, 0.05)
	Slider(Health, "Blue tint", "Properties.HealthBar.Blue", 0, 255, 1, nil, "Blue channel mixed into the health color.")
	ColorBlock(Health, "HealthBar", false, true)
end

do
	--// Head dot

	local HeadDot = VisualCard(Models, "Head dot", "HeadDot", "circle-dot", "A circle on each target's head.", "Left")
	Checkbox(HeadDot, "Filled", "Properties.HeadDot.Filled")
	Slider(HeadDot, "Sides", "Properties.HeadDot.NumSides", 3, 60, 1)
	Slider(HeadDot, "Thickness", "Properties.HeadDot.Thickness", 1, 6, 1, " px")
	Slider(HeadDot, "Opacity", "Properties.HeadDot.Transparency", 0, 1, 0.05)
	ColorBlock(HeadDot, "HeadDot")

	--// Skeleton

	local Skeleton = VisualCard(Models, "Skeleton", "Skeleton", "activity", "Bone lines for R6 and R15 rigs.", "Left")
	Slider(Skeleton, "Thickness", "Properties.Skeleton.Thickness", 1, 6, 1, " px")
	Slider(Skeleton, "Opacity", "Properties.Skeleton.Transparency", 0, 1, 0.05)
	Slider(Skeleton, "R6 height", "DeveloperSettings.SkeletonR6HeightModifier", 0, 1, 0.05, nil, "Where the R6 limbs meet the torso.")
	ColorBlock(Skeleton, "Skeleton", true, false)

	--// Highlight

	local Highlight = VisualCard(Models, "Highlight", "Highlight", "sparkles", "Roblox Highlight on each target. Cheapest way to see through walls.", "Right")
	Choice(Highlight, "Depth", "Properties.Highlight.DepthMode", {{"Through walls", Enum.HighlightDepthMode.AlwaysOnTop}, {"Visible only", Enum.HighlightDepthMode.Occluded}})

	local HighlightFill = Highlight:Group({Title = "Fill", Icon = "droplet", Opened = true})
	Color(HighlightFill, "Fill color", "Properties.Highlight.FillColor")
	Slider(HighlightFill, "Fill transparency", "Properties.Highlight.FillTransparency", 0, 1, 0.05, nil, "0 is solid, 1 is invisible.")
	local HealthColor = Checkbox(HighlightFill, "Color by health", "Properties.Highlight.HealthColor", "Overrides the fill color.")
	Slider(HighlightFill, "Health blue tint", "Properties.Highlight.HealthColorBlue", 0, 255, 1):DependsOn(HealthColor, nil, "Hide")

	local HighlightOutline = Highlight:Group({Title = "Outline", Icon = "square"})
	Color(HighlightOutline, "Outline color", "Properties.Highlight.OutlineColor")
	Slider(HighlightOutline, "Outline transparency", "Properties.Highlight.OutlineTransparency", 0, 1, 0.05, nil, "0 is solid, 1 is invisible.")
end

--// Crosshair

local CrosshairTab = Visual:SubTab({Title = "Crosshair", Icon = "crosshair"})

do
	local Base = "Properties.Crosshair."
	local Crosshair = VisualCard(CrosshairTab, "Crosshair", "Crosshair", "crosshair", "A drawn crosshair that can spin and pulse.", "Left", {Opened = true})

	Choice(Crosshair, "Follow", Base .. "Position", {{"Mouse", 1}, {"Screen center", 2}})
	Checkbox(Crosshair, "T-style", Base .. "TStyled", "Drops the top line.")
	Slider(Crosshair, "Size", Base .. "Size", 1, 40, 1, " px")
	Slider(Crosshair, "Gap", Base .. "GapSize", 0, 24, 1, " px")
	Slider(Crosshair, "Thickness", Base .. "Thickness", 1, 6, 1, " px")
	Slider(Crosshair, "Opacity", Base .. "Transparency", 0, 1, 0.05)

	local Rotation = Crosshair:Group({Title = "Rotation", Icon = "orbit"})
	Slider(Rotation, "Angle", Base .. "Rotation", 0, 360, 1, "°")
	local Rotate = Checkbox(Rotation, "Spin", Base .. "Rotate")
	Checkbox(Rotation, "Clockwise", Base .. "RotateClockwise"):DependsOn(Rotate, nil, "Hide")
	Slider(Rotation, "Spin speed", Base .. "RotationSpeed", 1, 20, 1):DependsOn(Rotate, nil, "Hide")

	local Pulse = Crosshair:Group({Title = "Pulse", Icon = "activity"})
	local Pulsing = Checkbox(Pulse, "Pulse gap", Base .. "PulseGap")
	Slider(Pulse, "Pulse step", Base .. "PulsingStep", 0, 24, 1):DependsOn(Pulsing, nil, "Hide")
	Slider(Pulse, "Pulse speed", Base .. "PulsingSpeed", 1, 20, 1):DependsOn(Pulsing, nil, "Hide")

	local Bounds = Read(Base .. "PulsingBounds") or {4, 8}
	Pulse:Range({
		Title = "Gap range",
		Min = 0,
		Max = 24,
		Default = {Bounds[1], Bounds[2]},
		MinGap = 1,
		Suffix = " px",
		Flag = Flag(Base .. "PulsingBounds"),
		Callback = function(Low, High) Write(Base .. "PulsingBounds", {Low, High}) end
	}):DependsOn(Pulsing, nil, "Hide")

	ColorBlock(Crosshair, "Crosshair")

	--// Center dot

	local DotBase = Base .. "CenterDot."
	local Dot = CrosshairTab:Module({
		Title = "Center dot",
		Description = "A dot in the middle of the crosshair.",
		Icon = "dot",
		Side = "Right",
		Default = Read(DotBase .. "Enabled") == true,
		Flag = Flag(DotBase .. "Enabled"),
		Keybind = false,
		Callback = function(Enabled) Write(DotBase .. "Enabled", Enabled) end
	})
	Checkbox(Dot, "Filled", DotBase .. "Filled")
	Slider(Dot, "Radius", DotBase .. "Radius", 1, 10, 1, " px")
	Slider(Dot, "Sides", DotBase .. "NumSides", 3, 60, 1)
	Slider(Dot, "Thickness", DotBase .. "Thickness", 1, 6, 1, " px")
	Slider(Dot, "Opacity", DotBase .. "Transparency", 0, 1, 0.05)

	local DotColors = Dot:Group({Title = "Colors", Icon = "palette", Opened = true})
	Color(DotColors, "Color", DotBase .. "Color")
	local DotOutline = Checkbox(DotColors, "Outline", DotBase .. "Outline")
	Color(DotColors, "Outline color", DotBase .. "OutlineColor"):DependsOn(DotOutline, nil, "Hide")
end

--// Targets

local Targets = Visual:SubTab({Title = "Targets", Icon = "target"})

do
	local VisualNames = {"ESP", "Tracer", "Box", "HealthBar", "HeadDot", "Skeleton", "Highlight"}

	local function PlayerNames()
		local Names = {}

		for _, Other in next, Players:GetPlayers() do
			if Other ~= Player then
				table.insert(Names, Other.Name)
			end
		end

		return Names
	end

	-- Rewraps an object so the ESP rebuilds its visuals with a new Allowed table and render distance
	local function Rewrap(Object, PseudoName, Allowed, Distance)
		local Environment = Env()
		local Entry = Environment.GetEntry(Object)

		if Entry then
			Environment.UnwrapObject(Entry.Hash)
		end

		task.wait()

		return Environment.WrapObject(Object, PseudoName, Allowed, Distance)
	end

	--// Per player

	local PerPlayer = Targets:Section({Title = "Per player", Icon = "user-round", Side = "Left"})
	PerPlayer:Paragraph({Content = "Hide chosen visuals on one player, or cap how far away they are drawn. Not saved in configs."})

	local Target
	Target = PerPlayer:Dropdown({
		Title = "Player",
		Values = PlayerNames(),
		Search = true,
		AllowNone = true,
		Action = {Icon = "refresh-cw", Tooltip = "Refresh players", Callback = function() Target:Refresh(PlayerNames(), true) end}
	})

	local Hidden = PerPlayer:Dropdown({Title = "Hide on this player", Values = VisualNames, Multi = true, Default = {}})
	local PlayerDistance = PerPlayer:Slider({Title = "Max distance", Min = 0, Max = 5000, Step = 50, Default = 0, Suffix = " st", Description = "0 is unlimited."})

	PerPlayer:Buttons({
		{Title = "Apply", Icon = "check", Style = "Primary", Callback = function()
			local Player = Target:Get() and Players:FindFirstChild(Target:Get())

			if not Player then
				return OasisUI:Notify({Title = "Per player", Content = "Pick a player first.", Type = "Warning", Duration = 3})
			end

			local Allowed = {}

			for _, Name in next, Hidden:Get() or {} do
				Allowed[Name] = false
			end

			local Distance = PlayerDistance:Get()
			Rewrap(Player, nil, Allowed, Distance > 0 and Distance or nil)
			OasisUI:Notify({Title = "Per player", Content = "Updated " .. Player.Name .. ".", Type = "Success", Duration = 3})
		end},
		{Title = "Reset", Icon = "rotate-ccw", Callback = function()
			local Player = Target:Get() and Players:FindFirstChild(Target:Get())

			if Player then
				Rewrap(Player)
			end
		end}
	})

	Players.PlayerAdded:Connect(function() Target:Refresh(PlayerNames(), true) end)
	Players.PlayerRemoving:Connect(function() task.defer(function() Target:Refresh(PlayerNames(), true) end) end)
end

--// Advanced

local Advanced = Visual:SubTab({Title = "Advanced", Icon = "wrench"})

do
	local Performance = Advanced:Section({Title = "Performance", Icon = "gauge", Side = "Left"})
	local Throttle = Checkbox(Performance, "Throttle", "DeveloperSettings.Throttle", "Updates 3D boxes and checks less often. Helps FPS with many targets.")
	Slider(Performance, "Throttle step", "DeveloperSettings.ThrottleStep", 2, 4, 1, nil, "Higher means fewer updates."):DependsOn(Throttle, nil, "Hide")
	Choice(Performance, "Update on", "DeveloperSettings.UpdateMode", {{"RenderStepped", "RenderStepped"}, {"Heartbeat", "Heartbeat"}, {"Stepped", "Stepped"}}, "Dropdown", "Takes effect after Restart ESP on the Overview tab.")

	local Tuning = Advanced:Section({Title = "Tuning", Icon = "sliders-horizontal", Side = "Right"})
	Slider(Tuning, "Box width", "DeveloperSettings.WidthBoundary", 0.5, 4, 0.05, nil, "Smaller is wider.")
	Checkbox(Tuning, "Unwrap on character loss", "DeveloperSettings.UnwrapOnCharacterAbsence", "Drop a player's visuals when their character is removed.")
	Checkbox(Tuning, "Hide ESP warnings", "DeveloperSettings.DisableWarnings")
end

local CandyCard = Autofarm:Module({
    Title = "Candy Collection",
    Description = "Automatically collects candies around the map without teleportation.",
    Icon = "gift",                      -- optional, shown before the title
    Flag = "CandyFarm",                      -- saves enabled state + key
    Default = false,
    Keybind = false,  -- false hides the pill
    Risky = false,                        -- red title
    Side = "Left",                        -- first placement; the user's layout wins afterwards
    Color = nil,                          -- { ColorPicker options }: a color swatch next to the switch, own Flag
    Notify = false,                       -- default of the card's bell: a notification on every on / off
    Opened = nil,                         -- force the settings open/closed initially
    Callback = function(enabled)
        settings.CandyFarm = enabled
    end,
})

CandyCard:Checkbox({
    Title = "Load the whole map",
    Tooltip = "Pulls in far parts of the map the way spectate does, so candies everywhere get collected, not just near you.",
    Default = true,
    Flag = "CandyFarm.LoadMap",
    Callback = function(enabled)
        settings.LoadMap = enabled
    end,
})

CandyCard:Slider({
    Title = "Seconds per area",
    Tooltip = "How long the loader stays on each area before moving on. Longer gives candies time to load in and get picked up.",
    Min = 2,
    Max = 15,
    Step = 0.5,
    Default = 5,
    Suffix = " s",
    Flag = "CandyFarm.AreaTime",
    Callback = function(value)
        settings.AreaTime = value
    end,
})

local CandyLoaded = CandyCard:Label({Text = "Collected this session", Value = "0", ValueColor = "Success"})
local CandyTotal = CandyCard:Label({Text = "Candies total", Value = "-"})
local CandyArea = CandyCard:Label({Text = "Loading around", Value = "-"})

Autofarm:Module({
    Title = "Improve Aim State",
    Description = "Automatically max aim stat.",
    Icon = "crosshair",                      -- optional, shown before the title
    Flag = "GunFarm",                      -- saves enabled state + key
    Default = false,
    Keybind = false,  -- false hides the pill
    Risky = false,                        -- red title
    Side = "Left",                        -- first placement; the user's layout wins afterwards
    Color = nil,                          -- { ColorPicker options }: a color swatch next to the switch, own Flag
    Notify = false,                       -- default of the card's bell: a notification on every on / off
    Opened = false,                         -- force the settings open/closed initially
    Callback = function(enabled)
        settings.GunFarm = enabled
    end,
})

Automisc:Module({
    Title = "Auto Claim Daily Check",
    Description = "Automatically claim daily check.",
    Icon = "calendar",                      -- optional, shown before the title
    Flag = "DailyCheck",                      -- saves enabled state + key
    Default = false,
    Keybind = false,  -- false hides the pill
    Risky = false,                        -- red title
    Side = "Left",                        -- first placement; the user's layout wins afterwards
    Color = nil,                          -- { ColorPicker options }: a color swatch next to the switch, own Flag
    Notify = false,                       -- default of the card's bell: a notification on every on / off
    Opened = false,                         -- force the settings open/closed initially
    Callback = function(enabled)
        settings.Check = enabled
    end,
})

--// Player: Guns

do
    -- Every setting the demo script changed. Number mods get a value box next to their switch ("inf" = math.huge).
    local GunMods = {
        {Group = "Penetration", Key = "PenetrationAmount", Title = "Penetration amount", Value = math.huge},
        {Group = "Penetration", Key = "PenetrationDepth", Title = "Penetration depth", Value = math.huge},

        {Group = "Ammo", Key = "Ammo", Title = "Ammo", Value = math.huge},
        {Group = "Ammo", Key = "AmmoPerMag", Title = "Ammo per mag", Value = math.huge},
        {Group = "Ammo", Key = "LimitedAmmoEnabled", Title = "No ammo limit", Value = false, Tip = "Sets LimitedAmmoEnabled to false."},
        {Group = "Ammo", Key = "ReloadTime", Title = "Reload time", Value = 0},

        {Group = "Handling", Key = "Recoil", Title = "Recoil", Value = 0},
        {Group = "Handling", Key = "Spread", Title = "Spread", Value = 0},
        {Group = "Handling", Key = "FireRate", Title = "Fire rate", Value = math.huge},
        {Group = "Handling", Key = "Auto", Title = "Full auto", Value = true, Tip = "Sets Auto to true."},

        {Group = "Effects", Key = "MotionBlur", Title = "No motion blur", Value = false, Tip = "Sets MotionBlur to false."},

        -- Your client flies the bullet, so these change real shots
        -- Multiplier: the slider scales each gun's own value, so every gun stays within 5x of what it was built for
        {Group = "Projectile", Key = "BulletSpeed", Title = "Faster bullets", Value = 2, Tip = "Multiplies each gun's own bullet speed. Very fast bullets broke shooting before, so it stops at 5x.",
            Slider = {Title = "Bullet speed", Min = 1, Max = 5, Step = 0.1, Suffix = "x", Multiplier = true}},

        -- Test only: the server knows your ammo and fire rate, and 8 hits per trigger pull is easy to flag
        {Group = "Shotgun", Key = "ShotgunEnabled", Title = "Shotgun mode", Value = true, Tip = "Fires several bullets per shot. Test carefully, this is the easiest one to flag."},
        {Group = "Shotgun", Key = "BulletPerShot", Title = "Set bullets per shot", Value = 8, Tip = "Capped at 100: too many pellets crash your game.",
            Slider = {Title = "Bullets per shot", Min = 1, Max = 100, Step = 1}}
    }

    local GunsEnabled = false
    local Active, Values = {}, {}
    local Originals = setmetatable({}, {__mode = "k"}) -- settings table -> {Key = {original value}}
    local Tracked = setmetatable({}, {__mode = "k"}) -- every settings table seen, so switching off restores unequipped guns too
    local Running = true

    local function ParseNumber(Text, Fallback)
        Text = tostring(Text):lower():gsub("%s", "")

        if Text == "inf" or Text == "huge" or Text == "math.huge" then
            return math.huge
        end

        return tonumber(Text) or Fallback
    end

    local function FormatNumber(Value)
        return Value == math.huge and "inf" or tostring(Value)
    end

    local function WriteSetting(Module, Key, Value)
        local WasReadonly = true -- the demo leaves the table read-only, so do the same when the executor can't tell us

        if isreadonly then
            local Success, Result = pcall(isreadonly, Module)
            WasReadonly = Success and Result or false
        end

        if setreadonly then
            pcall(setreadonly, Module, false)
        end

        local Success = pcall(function()
            Module[Key] = Value
        end)

        if setreadonly and WasReadonly then
            pcall(setreadonly, Module, true)
        end

        return Success
    end

    -- Brings one settings table in line with the switches: modded where on, original where off
    local function ApplyTo(Module)
        local Saved = Originals[Module]

        if not Saved then
            Saved = {}
            Originals[Module] = Saved
        end

        for _, Mod in next, GunMods do
            local Key = Mod.Key

            if GunsEnabled and Active[Key] then
                if not Saved[Key] then
                    Saved[Key] = {Module[Key]} -- boxed so an original nil is remembered too
                end

                local Value = Values[Key]

                if Value == nil then
                    Value = Mod.Value
                end

                -- A multiplier scales the gun's original value; skip guns that don't have one
                if Mod.Slider and Mod.Slider.Multiplier then
                    local Original = Saved[Key][1]
                    Value = type(Original) == "number" and Original * Value or Original
                end

                if Module[Key] ~= Value then
                    WriteSetting(Module, Key, Value)
                end
            elseif Saved[Key] then
                WriteSetting(Module, Key, Saved[Key][1])
                Saved[Key] = nil
            end
        end
    end

    local function SettingModules(Tool)
        local Modules = {}
        local Setting = Tool:FindFirstChild("Setting")

        if Setting then
            for _, Child in next, Setting:GetChildren() do
                if Child:IsA("ModuleScript") then
                    local Success, Result = pcall(require, Child)

                    if Success and type(Result) == "table" then
                        table.insert(Modules, Result)
                    end
                end
            end
        end

        return Modules
    end

    local function GunContainers()
        local Containers = {}
        local GameCharacter = GameFolder:FindFirstChild("Players") and GameFolder.Players:FindFirstChild(Player.Name)

        for _, Container in next, {GameCharacter, Player.Character, Player:FindFirstChildOfClass("Backpack")} do
            if Container then
                table.insert(Containers, Container)
            end
        end

        return Containers
    end

    local function Refresh()
        for _, Container in next, GunContainers() do
            for _, Tool in next, Container:GetChildren() do
                if Tool:IsA("Tool") then
                    for _, Module in next, SettingModules(Tool) do
                        Tracked[Module] = true
                    end
                end
            end
        end

        local Count = 0

        for Module in next, Tracked do
            ApplyTo(Module)
            Count += 1
        end

        return Count
    end

    --// Card

    local Guns = GunsTab:Module({
        Title = "Gun mods",
        Description = "Changes your guns' settings. Switching anything off puts the original value back.",
        Icon = "crosshair",
        Side = "Left",
        Risky = true,
        Default = false,
        Flag = "Guns.Enabled",
        Keybind = false,
        Opened = true,
        Callback = function(Enabled)
            GunsEnabled = Enabled
            Refresh()
        end
    })

    local Groups = {}

    for _, Mod in next, GunMods do
        local Group = Groups[Mod.Group]

        if not Group then
            Group = Guns:Group({Title = Mod.Group, Opened = Mod.Group == "Handling"})
            Groups[Mod.Group] = Group
        end

        local Def = {
            Title = Mod.Title,
            Tooltip = Mod.Tip,
            Default = false,
            Flag = "Guns." .. Mod.Key,
            Callback = function(Enabled)
                Active[Mod.Key] = Enabled
                Refresh()
            end
        }

        if Mod.Slider then
            local Toggle = Group:Checkbox(Def)

            Group:Slider({
                Title = Mod.Slider.Title,
                Min = Mod.Slider.Min,
                Max = Mod.Slider.Max,
                Step = Mod.Slider.Step,
                Default = Mod.Value,
                Suffix = Mod.Slider.Suffix,
                Buttons = true,
                Flag = "Guns." .. Mod.Key .. ".Slider",
                Callback = function(Value)
                    Values[Mod.Key] = Value
                    Refresh()
                end
            }):DependsOn(Toggle, nil, "Hide")

            continue
        end

        if type(Mod.Value) == "number" then
            Def.Field = {
                Default = FormatNumber(Mod.Value),
                Placeholder = "inf",
                Width = 64,
                Flag = "Guns." .. Mod.Key .. ".Value",
                Validate = function(Text)
                    return ParseNumber(Text) ~= nil, "A number or inf"
                end,
                Callback = function(Text)
                    Values[Mod.Key] = ParseNumber(Text, Mod.Value)
                    Refresh()
                end
            }
        end

        Group:Checkbox(Def)
    end

    --// Info

    --// Aim: Silent aim, Triggerbot

    -- How it works: GunClient aims each shot through Camera:ScreenPointToRay at the crosshair, then fires a real
    -- bullet along that ray and reports whatever it hits. Bending that one ray makes the bullet, its path and the
    -- hit report all agree, which the server accepts.

    -- Older Headtapper hooks from this session stay installed until a rejoin; keep them switched off
    for _, Old in next, {getgenv().SuperNovaHeadtapper, getgenv().SuperNovaHeadtapperV2} do
        Old.Enabled = false
        Old.Log = false
    end

    -- The hook is installed once per session and calls whatever Handler the current script sets,
    -- so re-running or editing the script never needs a new hook
    local AimHook = getgenv().SuperNovaAimHook

    if not AimHook then
        AimHook = {}
        getgenv().SuperNovaAimHook = AimHook

        local wrap = newcclosure or function(Function) return Function end

        -- Only the gun's own aiming calls are touched; menus and other scripts keep the real ray
        local function FromGunClient()
            if not getcallingscript then
                return true
            end

            -- Some executors return nil here; only skip calls we know came from another script
            local Success, Caller = pcall(getcallingscript)
            return not Success or Caller == nil or Caller.Name == "GunClient"
        end

        local OldNamecall
        OldNamecall = hookmetamethod(game, "__namecall", wrap(function(...)
            local self = ...
            local Method = getnamecallmethod()

            if Method == "ScreenPointToRay" and AimHook.Handler and typeof(self) == "Instance" and self.ClassName == "Camera" and FromGunClient() then
                local Original = OldNamecall(...)
                local Success, Bent = pcall(AimHook.Handler, Original, select(2, ...))

                return Success and Bent or Original
            end

            return OldNamecall(...)
        end))
    end

    local Aim = {
        Silent = false,
        FOV = 120,
        ShowFOV = true,
        VisibleOnly = true,
        TeamCheck = false,
        AimPart = "Head",
        Trigger = false,
        TriggerDelay = 0.05,
        TriggerSilent = false,
        TriggerIgnoreCars = false
    }

    local GuiService = game:GetService("GuiService")
    local UserInputService = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")

    local function PlayersFolder()
        return GameFolder:FindFirstChild("Players")
    end

    local function OwnCharacters()
        local Folder = PlayersFolder()
        return {Player.Character, Folder and Folder:FindFirstChild(Player.Name), workspace.CurrentCamera}
    end

    -- The part's character: the model straight under GameFolder.Players, or the nearest one with a Humanoid
    local function HitCharacter(Part)
        local Folder = PlayersFolder()
        local Node = Part

        while Node and Node ~= workspace do
            if Node.Parent == Folder or (Node:IsA("Model") and Node:FindFirstChildOfClass("Humanoid")) then
                return Node
            end

            Node = Node.Parent
        end
    end

    local function IsEnemy(Character)
        if not Character or Character == Player.Character then
            return false
        end

        local Owner = Players:GetPlayerFromCharacter(Character) or Players:FindFirstChild(Character.Name)

        if Owner == Player then
            return false
        end

        if Aim.TeamCheck and Owner and Owner.Team ~= nil and Owner.Team == Player.Team then
            return false
        end

        local Humanoid = Character:FindFirstChildOfClass("Humanoid")
        return Humanoid == nil or Humanoid.Health > 0
    end

    -- HeadHitbox is a recursive search, so remember it per character (weak: dead characters drop out)
    local HeadHitboxes = setmetatable({}, {__mode = "k"})

    local function AimPartOf(Character)
        if Aim.AimPart == "Head" then
            local Hitbox = HeadHitboxes[Character]

            if not (Hitbox and Hitbox.Parent and Hitbox:IsDescendantOf(Character)) then
                Hitbox = Character:FindFirstChild("HeadHitbox", true)
                HeadHitboxes[Character] = Hitbox
            end

            return Hitbox or Character:FindFirstChild("Head")
        end

        return Character:FindFirstChild("HumanoidRootPart") or Character:FindFirstChild("UpperTorso") or Character:FindFirstChild("Torso")
    end

    -- One RaycastParams, rebuilt only when what it ignores changes. Setting FilterDescendantsInstances is the
    -- expensive part, and silent aim used to do it once per player per shot.
    local CachedParams = RaycastParams.new()
    CachedParams.FilterType = Enum.RaycastFilterType.Exclude
    local CachedKey = {}

    local function NewParams()
        local Ignore = OwnCharacters()

        -- Ignore cars: rays pass through every car, so a player behind or inside one still counts as on target
        if Aim.TriggerIgnoreCars then
            table.insert(Ignore, GameFolder:FindFirstChild("Vehicles"))
        end

        local Changed = false

        for Index = 1, 4 do
            if Ignore[Index] ~= CachedKey[Index] then
                Changed = true
            end
        end

        if Changed then
            local List = {}

            for Index = 1, 4 do
                if Ignore[Index] then
                    table.insert(List, Ignore[Index])
                end
            end

            CachedParams.FilterDescendantsInstances = List
            CachedKey = Ignore
        end

        return CachedParams
    end

    -- Nothing between the camera and the part except the target itself
    local function IsVisible(Part, Character)
        local Origin = workspace.CurrentCamera.CFrame.Position
        local Result = workspace:Raycast(Origin, Part.Position - Origin, NewParams())

        return Result == nil or Result.Instance:IsDescendantOf(Character)
    end

    -- The enemy whose aim part is closest to the screen point, within the FOV radius
    local function SilentTarget(ScreenPoint)
        local Camera = workspace.CurrentCamera
        local Folder = PlayersFolder()
        local Best, BestDistance = nil, Aim.FOV

        for _, Other in next, Players:GetPlayers() do
            local Character = Other ~= Player and (Other.Character or (Folder and Folder:FindFirstChild(Other.Name)))

            if Character and IsEnemy(Character) then
                local Part = AimPartOf(Character)

                if Part then
                    local Position, OnScreen = Camera:WorldToScreenPoint(Part.Position)
                    local Distance = (Vector2.new(Position.X, Position.Y) - ScreenPoint).Magnitude

                    if OnScreen and Distance <= BestDistance and (not Aim.VisibleOnly or IsVisible(Part, Character)) then
                        Best, BestDistance = Part, Distance
                    end
                end
            end
        end

        return Best
    end

    -- The enemy character a ray from Origin along Direction would hit, if any
    local function RayTarget(Origin, Direction)
        local Result = workspace:Raycast(Origin, Direction.Unit * 1000, NewParams())
        local Character = Result and HitCharacter(Result.Instance)

        return IsEnemy(Character) and Character or nil
    end

    -- GunClient calls ScreenPointToRay(x, y, 1000): the ray starts 1000 studs out from the camera, and the gun
    -- aims at Origin + Direction. So the bent ray has to start at that same depth on the camera-to-part line,
    -- not just point a different way from the old origin.
    local function RayAt(Original, Part)
        local Camera = workspace.CurrentCamera.CFrame.Position
        local Depth = (Original.Origin - Camera).Magnitude
        local Unit = (Part.Position - Camera).Unit

        return Ray.new(Camera + Unit * Depth, Unit)
    end

    AimHook.Handler = function(Original, X, Y)
        if Aim.Silent and X and Y then
            local Part = SilentTarget(Vector2.new(X, Y))

            if Part then
                return RayAt(Original, Part)
            end
        end

        return Original
    end

    --// Silent aim

    local FOVCircle = Drawing.new("Circle")
    FOVCircle.Visible = false
    FOVCircle.Filled = false
    FOVCircle.NumSides = 64
    FOVCircle.Thickness = 1
    FOVCircle.Transparency = 1
    FOVCircle.Color = Color3.fromRGB(255, 255, 255)

    local Silent = AimTab:Module({
        Title = "Silent aim",
        Description = "Shots go to the nearest player inside the circle around your crosshair.",
        Icon = "crosshair",
        Side = "Left",
        Risky = true,
        Default = false,
        Flag = "Combat.SilentAim",
        Keybind = false,
        Callback = function(Enabled)
            Aim.Silent = Enabled
        end
    })

    Silent:Slider({Title = "FOV radius", Min = 20, Max = 600, Step = 5, Default = 120, Suffix = " px", Flag = "Combat.SilentAim.FOV", Callback = function(Value) Aim.FOV = Value end})
    Silent:Segmented({Title = "Aim at", Values = {"Head", "Torso"}, Default = "Head", Flag = "Combat.SilentAim.Part", Callback = function(Value) Aim.AimPart = Value end})
    Silent:Checkbox({Title = "Visible only", Tooltip = "Skip players behind walls. Without it, shots into cover hit the cover.", Default = true, Flag = "Combat.SilentAim.Visible", Callback = function(Value) Aim.VisibleOnly = Value end})
    Silent:Checkbox({Title = "Team check", Tooltip = "Skip players on your team.", Default = false, Flag = "Combat.TeamCheck", Callback = function(Value) Aim.TeamCheck = Value end})
    Silent:Checkbox({
        Title = "Show FOV circle",
        Default = true,
        Flag = "Combat.SilentAim.ShowFOV",
        Callback = function(Value) Aim.ShowFOV = Value end,
        Color = {
            Default = Color3.fromRGB(255, 255, 255),
            Flag = "Combat.SilentAim.FOVColor",
            Callback = function(Value) FOVCircle.Color = Value end
        }
    })

    --// Triggerbot

    local Trigger = AimTab:Module({
        Title = "Triggerbot",
        Description = "Fires your gun when your crosshair is on an enemy.",
        Icon = "zap",
        Side = "Right",
        Risky = true,
        Default = false,
        Flag = "Combat.Triggerbot",
        Keybind = {Key = nil, Mode = "Toggle"},
        Callback = function(Enabled)
            if Enabled and not (mouse1press and mouse1release) then
                OasisUI:Notify({Title = "Triggerbot", Content = "This executor has no mouse1press, so the triggerbot can't click.", Type = "Error", Duration = 5})
            end

            Aim.Trigger = Enabled
        end
    })

    Trigger:Slider({Title = "Reaction delay", Min = 0, Max = 500, Step = 10, Default = 50, Suffix = " ms", Flag = "Combat.Triggerbot.Delay", Callback = function(Value) Aim.TriggerDelay = Value / 1000 end})
    Trigger:Checkbox({Title = "Fire on silent aim targets", Tooltip = "Also fires when silent aim has a target in its circle, not only when the crosshair is on one.", Default = false, Flag = "Combat.Triggerbot.Silent", Callback = function(Value) Aim.TriggerSilent = Value end})
    Trigger:Checkbox({Title = "Ignore cars", Tooltip = "Cars don't block the target check: fires at players inside or behind cars. Also applies to silent aim's visible-only check.", Default = false, Flag = "Combat.Triggerbot.IgnoreCars", Callback = function(Value) Aim.TriggerIgnoreCars = Value end})

    local function HoldingGun()
        local Folder = PlayersFolder()

        for _, Character in next, {Player.Character, Folder and Folder:FindFirstChild(Player.Name)} do
            if Character and Character:FindFirstChildOfClass("Tool") then
                return true
            end
        end

        return false
    end

    local Firing = false
    local CircleShown = false

    local AimLoop = RunService.RenderStepped:Connect(function()
        local ShowCircle = Aim.Silent and Aim.ShowFOV

        -- Drawing writes go through the executor, so only touch the circle while it's on screen
        if ShowCircle ~= CircleShown then
            FOVCircle.Visible = ShowCircle
            CircleShown = ShowCircle
        end

        if not (ShowCircle or Aim.Trigger) then
            return
        end

        local MousePosition = UserInputService:GetMouseLocation()

        if ShowCircle then
            FOVCircle.Radius = Aim.FOV
            FOVCircle.Position = MousePosition
        end

        if not Aim.Trigger or Firing or not (mouse1press and mouse1release) or not HoldingGun() then
            return
        end

        local Camera = workspace.CurrentCamera
        local MouseRay = Camera:ViewportPointToRay(MousePosition.X, MousePosition.Y)
        local OnTarget = RayTarget(MouseRay.Origin, MouseRay.Direction) ~= nil

        if not OnTarget and Aim.TriggerSilent and Aim.Silent then
            OnTarget = SilentTarget(MousePosition - GuiService:GetGuiInset()) ~= nil
        end

        if OnTarget then
            Firing = true

            task.spawn(function()
                task.wait(Aim.TriggerDelay)
                mouse1press()
                task.wait(0.03)
                mouse1release()
                Firing = false
            end)
        end
    end)

    OasisUI:OnUnload(function()
        AimHook.Handler = nil
        Aim.Trigger = false
        AimLoop:Disconnect()
        FOVCircle:Remove()
    end)

    local Info = GunsTab:Section({Title = "Status", Icon = "info", Side = "Right"})
    local TrackedLabel = Info:Label({Text = "Gun settings tracked", Value = "0"})

    Info:Paragraph({Content = "Mods apply to the equipped gun and everything in your backpack, and follow new guns and respawns. Number boxes take any number or <b>inf</b>."})
    Info:Button({Title = "Restore all guns", Icon = "rotate-ccw", Style = "Danger", Callback = function()
        Guns:Set(false)
    end})

    task.spawn(function()
        while Running do
            TrackedLabel:SetValue(tostring(Refresh()))
            task.wait(1)
        end
    end)

    OasisUI:OnUnload(function()
        Running = false
        GunsEnabled = false
        Refresh()
    end)
end

--// Player: Character

do
    local SpeedEnabled = false
    local SpeedHeld = false -- the hold key (Left Shift by default) is down
    local Speed = 22
    local OriginalSpeed = {} -- Humanoid -> its walk speed before we touched it (weak, so dead characters drop out)
    setmetatable(OriginalSpeed, {__mode = "k"})

    local function Humanoid()
        local Character = Player.Character
        return Character and Character:FindFirstChildOfClass("Humanoid")
    end

    local function Restore()
        for Target, Original in next, OriginalSpeed do
            if Target.Parent then
                Target.WalkSpeed = Original
            end
        end

        table.clear(OriginalSpeed)
    end

    -- Re-applied every frame: sprint and stamina scripts keep writing their own speed
    local Connection = game:GetService("RunService").Heartbeat:Connect(function()
        if not (SpeedEnabled or SpeedHeld) then
            return
        end

        local Target = Humanoid()

        if Target then
            if OriginalSpeed[Target] == nil then
                OriginalSpeed[Target] = Target.WalkSpeed
            end

            if Target.WalkSpeed ~= Speed then
                Target.WalkSpeed = Speed
            end
        end
    end)

    local WalkSpeed = CharacterTab:Module({
        Title = "Walk speed",
        Description = "Holds your walk speed at the value below while switched on or while the hold key is down. Off puts the game's speed back.",
        Icon = "wind",
        Side = "Left",
        Default = false,
        Flag = "Character.WalkSpeed",
        Keybind = false,
        Opened = true,
        Callback = function(Enabled)
            SpeedEnabled = Enabled

            if not (Enabled or SpeedHeld) then
                Restore()
            end
        end
    })

    WalkSpeed:Keybind({
        Title = "Hold to sprint",
        Description = "Uses the speed below only while held, even with the switch off. Click to rebind.",
        Default = "LeftShift",
        Mode = "Hold",
        Modes = {"Hold"},
        Listed = false,
        Flag = "Character.WalkSpeed.HoldKey",
        Callback = function(Held)
            SpeedHeld = Held

            if not (Held or SpeedEnabled) then
                Restore()
            end
        end
    })

    WalkSpeed:Slider({
        Title = "Speed",
        Min = 22,
        Max = 46,
        Step = 1,
        Default = 22,
        Suffix = " st/s",
        Buttons = true,
        Flag = "Character.WalkSpeed.Value",
        Callback = function(Value)
            Speed = Value
        end
    })

    OasisUI:OnUnload(function()
        SpeedEnabled, SpeedHeld = false, false
        Connection:Disconnect()
        Restore()
    end)
end

--// CharacterClient features: stamina, dehydration, restraints, roll dash, fists, auto-stomp, anti-aim

do
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")

    local getupvalues = debug.getupvalues or getupvalues
    local getconstants = debug.getconstants or getconstants
    local setconstant = debug.setconstant or setconstant
    local getprotos = debug.getprotos or getprotos

    local Misc = Remotes:WaitForChild("Misc")
    local BodyMovementEvent = Misc:FindFirstChild("BodyMovementEvent")

    local Features = {
        NoDehydration = false,
        NoFallDamage = false,
        FreeMovement = false,
        RestrainedSpeed = 16,
        RollDash = false,
        DashSpeed = 25,
        InfiniteStamina = false,
        AntiAimLocal = true,
        FastFists = false,
        AutoStomp = false,
        StompRange = 8,
        AntiAim = false,
        Yaw = "Spin",
        Pitch = "Down",
        PitchJoint = "Torso",
        PitchDegrees = 120,
        SpinSpeed = 720,
        JitterAngle = 90
    }

    local Running = true

    local function GameCharacter()
        local Folder = GameFolder:FindFirstChild("Players")
        return Folder and Folder:FindFirstChild(Player.Name)
    end

    local function MyCharacter()
        return Player.Character or GameCharacter()
    end

    --// Finding CharacterClient's internals (redone on every respawn: each character runs a fresh copy)

    -- Table2 holds MovementTable / Variables, Fist holds the fist cooldowns,
    -- RollProto + RollIndex point at the roll's stored dash speed (25)
    local Context = {}

    local function FindClientScript()
        for _, Character in next, {Player.Character, GameCharacter()} do
            local Script = Character and Character:FindFirstChild("CharacterClient")

            if Script then
                return Script
            end
        end
    end

    -- Hoisted: building this closure inside the loop made one new function per GC object scanned
    local function ScriptOf(Env)
        return Env.script
    end

    local function ScanClient(Script)
        local Found = {Script = Script}

        for _, Function in next, getgc() do
            if type(Function) == "function" and islclosure(Function) then
                local Success, Env = pcall(getfenv, Function)

                local Owner = Success and type(Env) == "table" and (rawget(Env, "script") or select(2, pcall(ScriptOf, Env)))

                if Owner == Script then
                    local UpOk, Upvalues = pcall(getupvalues, Function)

                    for _, Value in next, UpOk and Upvalues or {} do
                        if type(Value) == "table" then
                            if rawget(Value, "MovementTable") ~= nil and rawget(Value, "Variables") ~= nil then
                                Found.Table2 = Value
                            elseif rawget(Value, "SlamReady") ~= nil and rawget(Value, "WeaveReady") ~= nil then
                                Found.Fist = Value
                            end
                        end
                    end

                    local ConstOk, Constants = pcall(getconstants, Function)

                    if not Found.Roll and ConstOk and table.find(Constants, "RollCD") and table.find(Constants, "BodyImpact") then
                        Found.Roll = Function
                    end
                end
            end
        end

        -- The dash velocity lives in a small inner function: Vector3.new(X, 0, Z).Unit * 25
        if Found.Roll and getprotos then
            for _, Proto in next, getprotos(Found.Roll) do
                local Ok, Constants = pcall(getconstants, Proto)

                if Ok and table.find(Constants, "Velocity") then
                    for Index, Value in next, Constants do
                        if Value == 25 then
                            Found.RollProto, Found.RollIndex = Proto, Index
                        end
                    end
                end
            end
        end

        return Found
    end

    local function ApplyDashSpeed()
        if Context.RollProto and setconstant then
            pcall(setconstant, Context.RollProto, Context.RollIndex, Features.RollDash and Features.DashSpeed or 25)
        end
    end

    -- Re-scans whenever a new CharacterClient shows up; retries while the script is still starting
    task.spawn(function()
        while Running do
            local Script = FindClientScript()

            if Script and Script ~= Context.Script then
                for _ = 1, 15 do
                    local Found = ScanClient(Script)

                    if Found.Table2 then
                        Context = Found
                        ApplyDashSpeed()
                        break
                    end

                    task.wait(1)
                end
            end

            task.wait(1)
        end
    end)

    --// Remote filter: drops the game's own sends we need to override (our own sends always pass)

    local RemoteHook = getgenv().SuperNovaRemoteHook

    if not RemoteHook then
        RemoteHook = {}
        getgenv().SuperNovaRemoteHook = RemoteHook

        local wrap = newcclosure or function(Function) return Function end
        local OldNamecall

        OldNamecall = hookmetamethod(game, "__namecall", wrap(function(...)
            if RemoteHook.Filter and not RemoteHook.Bypass and getnamecallmethod() == "FireServer" and not (checkcaller and checkcaller()) then
                local Success, Drop = pcall(RemoteHook.Filter, ...)

                if Success and Drop then
                    return nil
                end
            end

            return OldNamecall(...)
        end))
    end

    local function Send(Remote, ...)
        RemoteHook.Bypass = true
        local Success, Result = pcall(Remote.FireServer, Remote, ...)
        RemoteHook.Bypass = false

        return Success, Result
    end

    local function IsAimJoint(Joint)
        local Character = MyCharacter()
        return typeof(Joint) == "Instance" and (Joint.Name == "Neck" or Joint.Name == "Waist") and Character ~= nil and Joint:IsDescendantOf(Character)
    end

    -- Same idea for property writes: CharacterClient sets Neck/Waist C0 every frame to follow the camera
    local WriteHook = getgenv().SuperNovaWriteHook

    if not WriteHook then
        WriteHook = {}
        getgenv().SuperNovaWriteHook = WriteHook

        local wrap = newcclosure or function(Function) return Function end
        local OldNewindex

        OldNewindex = hookmetamethod(game, "__newindex", wrap(function(self, Key, Value)
            -- Every property write in the game lands here, so the cheapest test that rules most out goes first
            if Key == "C0" and WriteHook.Filter and not WriteHook.Bypass and not (checkcaller and checkcaller()) then
                local Success, Drop = pcall(WriteHook.Filter, self)

                if Success and Drop then
                    return
                end
            end

            return OldNewindex(self, Key, Value)
        end))
    end

    -- Other features add their own rules here: Rule(Remote, ...) returns true to drop the call.
    -- A rule may also edit table arguments in place and return false to let the edited call through.
    RemoteHook.Rules = {}

    RemoteHook.Filter = function(Remote, First, ...)
        -- The game streams your real head and waist angles; anti-aim sends its own instead
        if Features.AntiAim and Remote == BodyMovementEvent and IsAimJoint(First) then
            return true
        end

        -- CharacterClient.FallDamage reports its own damage (airtime x 15 to 44) through its RemoteEvent
        if Features.NoFallDamage and Remote.Name == "RemoteEvent" and Remote.Parent and Remote.Parent.Name == "FallDamage" then
            return true
        end

        for _, Rule in next, RemoteHook.Rules do
            local Ok, Drop = pcall(Rule, Remote, First, ...)

            if Ok and Drop then
                return true
            end
        end
    end

    --// Every frame, right before physics: dehydration, restraints, fist cooldowns, roll cooldown

    local Stepped = RunService.Stepped:Connect(function()
        local Character = MyCharacter()
        local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
        local Table2 = Context.Table2

        if not Humanoid then
            return
        end

        -- Stamina lives in MovementTable; Values.Stamina is only the copy the HUD reads
        if Features.InfiniteStamina and Table2 and type(Table2.MovementTable.MaxStamina) == "number" and Table2.MovementTable.MaxStamina > 0 then
            Table2.MovementTable.Stamina = Table2.MovementTable.MaxStamina
            Table2.MovementTable.SprintRegenCD = false
        end

        -- Sprint speed is 22, or 15 while dehydrated
        if Features.NoDehydration and Table2 and Table2.Variables.Dehyrdated and Table2.MovementTable.Sprinting and Humanoid.WalkSpeed < 22 then
            Humanoid.WalkSpeed = 22
        end

        -- Downed caps you at 4, cuffed at 10 with no jumping, carried at 0 with no turning
        if Features.FreeMovement then
            local Critical, Cuffed, Carried = Character:GetAttribute("Critical"), Character:GetAttribute("Cuffed"), Character:GetAttribute("CarriedBy")

            if Critical or Cuffed or Carried then
                if Humanoid.WalkSpeed < Features.RestrainedSpeed then
                    Humanoid.WalkSpeed = Features.RestrainedSpeed
                end

                Humanoid.AutoRotate = true
            end

            if Cuffed then
                Humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
            end
        end

        if Features.FastFists and Context.Fist then
            Context.Fist.Busy = false
            Context.Fist.SlamReady = 0
            Context.Fist.WeaveReady = 0
        end

        -- RollCD is the 1 second cooldown; the Rolling attribute still stops two rolls overlapping
        if Features.RollDash and Table2 and Table2.Variables.RollCD and not Humanoid:GetAttribute("Rolling") then
            Table2.Variables.RollCD = false
        end
    end)

    --// Character tab

    local Survival = CharacterTab:Section({Title = "Survival", Icon = "shield", Side = "Left"})

    Survival:Toggle({
        Title = "Infinite stamina",
        Tooltip = "Keeps stamina full inside the game's own movement table. Sprint and roll never run dry.",
        Default = false,
        Flag = "Client.InfiniteStamina",
        Callback = function(Enabled) Features.InfiniteStamina = Enabled end
    })

    Survival:Toggle({
        Title = "No dehydration slowdown",
        Tooltip = "Keeps your sprint at 22 instead of 15 while dehydrated.",
        Default = false,
        Flag = "Client.NoDehydration",
        Callback = function(Enabled) Features.NoDehydration = Enabled end
    })

    Survival:Toggle({
        Title = "No fall damage",
        Tooltip = "Your client reports its own fall damage. This drops the report, so falls never hurt.",
        Default = false,
        Flag = "Client.NoFallDamage",
        Callback = function(Enabled) Features.NoFallDamage = Enabled end
    })

    local Free = Survival:Toggle({
        Title = "Move while downed / cuffed / carried",
        Tooltip = "Lifts the speed caps the game puts on you, and lets you jump while cuffed. If you still can't move, the server is holding you.",
        Default = false,
        Flag = "Client.FreeMovement",
        Callback = function(Enabled) Features.FreeMovement = Enabled end
    })

    Survival:Slider({Title = "Speed while restrained", Min = 4, Max = 22, Step = 1, Default = 16, Suffix = " st/s", Flag = "Client.RestrainedSpeed", Callback = function(Value) Features.RestrainedSpeed = Value end})
        :DependsOn(Free, nil, "Hide")

    local Roll = CharacterTab:Module({
        Title = "Roll dash",
        Description = "Removes the roll cooldown and speeds the roll up. Needs a gun out with shift lock.",
        Icon = "wind",
        Side = "Left",
        Default = false,
        Flag = "Client.RollDash",
        Keybind = false,
        Callback = function(Enabled)
            Features.RollDash = Enabled
            ApplyDashSpeed()

            if Enabled and not Context.RollProto then
                OasisUI:Notify({Title = "Roll dash", Content = "Couldn't find the roll's speed value. The cooldown removal still works.", Type = "Warning", Duration = 5})
            end
        end
    })

    Roll:Slider({
        Title = "Dash speed",
        Min = 25,
        Max = 75,
        Step = 1,
        Default = 25,
        Suffix = " st/s",
        Buttons = true,
        Flag = "Client.DashSpeed",
        Callback = function(Value)
            Features.DashSpeed = Value
            ApplyDashSpeed()
        end
    })

    --// Combat tab

    local Fists = FistsTab:Module({
        Title = "Fists",
        Description = "Faster punches, slams and weaves, plus auto-stomp on downed players.",
        Icon = "swords",
        Side = "Left",
        Risky = true,
        Default = false,
        Flag = "Client.Fists",
        Keybind = false,
        Callback = function(Enabled) Features.FastFists = Enabled end
    })

    local Stomp = Fists:Checkbox({
        Title = "Auto-stomp",
        Tooltip = "Stomps any downed player in range while your fists are out.",
        Default = false,
        Flag = "Client.AutoStomp",
        Callback = function(Enabled) Features.AutoStomp = Enabled end
    })

    Fists:Slider({Title = "Stomp range", Min = 3, Max = 15, Step = 1, Default = 8, Suffix = " st", Flag = "Client.StompRange", Callback = function(Value) Features.StompRange = Value end})
        :DependsOn(Stomp, nil, "Hide")

    --// Anti-aim

    local AntiAim = AntiAimTab:Module({
        Title = "Anti-aim",
        Description = "Sends the server fake head and waist angles, so other players see you spinning or bent over.",
        Icon = "orbit",
        Side = "Left",
        Risky = true,
        Default = false,
        Flag = "Client.AntiAim",
        Keybind = {Key = nil, Mode = "Toggle"},
        Callback = function(Enabled)
            Features.AntiAim = Enabled
        end
    })

    local YawMode = AntiAim:Dropdown({Title = "Yaw", Values = {"Off", "Spin", "Jitter", "Backwards", "Sideways", "Random"}, Default = "Spin", Flag = "Client.AntiAim.Yaw", Callback = function(Value) Features.Yaw = Value end})
    AntiAim:Checkbox({
        Title = "Show on my screen",
        Tooltip = "Draws the fake angles on your own character too. Your gun turns with your waist, so shots can start from odd places.",
        Default = true,
        Flag = "Client.AntiAim.Local",
        Callback = function(Enabled) Features.AntiAimLocal = Enabled end
    })
    local PitchMode = AntiAim:Dropdown({Title = "Pitch", Values = {"Off", "Down", "Up", "Jitter"}, Default = "Down", Flag = "Client.AntiAim.Pitch", Callback = function(Value) Features.Pitch = Value end})
    AntiAim:Segmented({Title = "Bend at", Values = {"Torso", "Head", "Both"}, Default = "Torso", Flag = "Client.AntiAim.PitchJoint", Tooltip = "Torso folds the whole upper body over, so the head points at the legs.", Callback = function(Value) Features.PitchJoint = Value end})
        :DependsOn(PitchMode, function(Value) return Value ~= "Off" end, "Hide")
    AntiAim:Slider({Title = "Pitch angle", Min = 10, Max = 180, Step = 5, Default = 120, Suffix = "°", Flag = "Client.AntiAim.PitchAngle", Callback = function(Value) Features.PitchDegrees = Value end})
        :DependsOn(PitchMode, function(Value) return Value ~= "Off" end, "Hide")
    AntiAim:Slider({Title = "Spin speed", Min = 90, Max = 1800, Step = 30, Default = 720, Suffix = "°/s", Flag = "Client.AntiAim.Spin", Callback = function(Value) Features.SpinSpeed = Value end})
        :DependsOn(YawMode, function(Value) return Value == "Spin" end, "Hide")
    AntiAim:Slider({Title = "Jitter angle", Min = 10, Max = 180, Step = 5, Default = 90, Suffix = "°", Flag = "Client.AntiAim.Jitter", Callback = function(Value) Features.JitterAngle = Value end})
        :DependsOn(YawMode, function(Value) return Value == "Jitter" end, "Hide")

    -- Base joint offsets: CharacterClient keeps the originals in MovementTable. Otherwise remember each joint's
    -- C0 the first time we see it, before we rotate it, so the angles never stack on top of each other.
    local FirstC0 = setmetatable({}, {__mode = "k"})

    local function BaseC0(Joint, Key)
        local Table2 = Context.Table2
        local Saved = Table2 and Table2.MovementTable[Key]

        if typeof(Saved) == "CFrame" then
            return Saved
        end

        FirstC0[Joint] = FirstC0[Joint] or Joint.C0
        return FirstC0[Joint]
    end

    local SpinAngle, JitterFlip = 0, false
    local WasAiming = false

    local LocalAim = {Waist = nil, Neck = nil} -- latest angles, also drawn on your own screen

    WriteHook.Filter = function(Joint)
        return Features.AntiAim and Features.AntiAimLocal and IsAimJoint(Joint)
    end

    local LocalRender = RunService.RenderStepped:Connect(function()
        if not (Features.AntiAim and Features.AntiAimLocal and LocalAim.Waist) then
            return
        end

        local Character = MyCharacter()
        local Neck = Character and Character:FindFirstChild("Head") and Character.Head:FindFirstChild("Neck")
        local Waist = Character and Character:FindFirstChild("UpperTorso") and Character.UpperTorso:FindFirstChild("Waist")

        if Neck and Waist then
            WriteHook.Bypass = true
            Waist.C0 = LocalAim.Waist
            Neck.C0 = LocalAim.Neck
            WriteHook.Bypass = false
        end
    end)

    local function YawAngle(Delta)
        local Mode = Features.Yaw

        if Mode == "Spin" then
            SpinAngle = (SpinAngle + math.rad(Features.SpinSpeed) * Delta) % (math.pi * 2)
            return SpinAngle
        elseif Mode == "Jitter" then
            return JitterFlip and math.rad(Features.JitterAngle) or -math.rad(Features.JitterAngle)
        elseif Mode == "Backwards" then
            return math.pi
        elseif Mode == "Sideways" then
            return math.pi / 2
        elseif Mode == "Random" then
            return math.random() * math.pi * 2
        end

        return 0
    end

    local function PitchAngle()
        local Mode, Angle = Features.Pitch, math.rad(Features.PitchDegrees)

        if Mode == "Down" then
            return -Angle
        elseif Mode == "Up" then
            return Angle
        elseif Mode == "Jitter" then
            return JitterFlip and -Angle or Angle
        end

        return 0
    end

    -- How the pitch is shared between the joints: Torso bends at the waist (head ends up by the legs),
    -- Head only tilts the neck, Both bows at the waist and tucks the head in the rest of the way
    local function SplitPitch()
        local Angle, Joint = PitchAngle(), Features.PitchJoint

        if Joint == "Head" then
            return 0, Angle
        elseif Joint == "Both" then
            return Angle * 2 / 3, Angle / 3
        end

        return Angle, 0
    end

    -- Sent 20 times a second, about the rate the game itself uses
    task.spawn(function()
        local Last = os.clock()

        while Running do
            local Now = os.clock()
            local Delta = Now - Last
            Last = Now
            JitterFlip = not JitterFlip

            local Character = MyCharacter()
            local Head = Character and Character:FindFirstChild("Head")
            local UpperTorso = Character and Character:FindFirstChild("UpperTorso")
            local Neck = Head and Head:FindFirstChild("Neck")
            local Waist = UpperTorso and UpperTorso:FindFirstChild("Waist")

            if BodyMovementEvent and Neck and Waist then
                if Features.AntiAim then
                    local WaistPitch, NeckPitch = SplitPitch()

                    -- Turn first, then bow, so the bow happens in whichever direction the yaw is facing
                    LocalAim.Waist = BaseC0(Waist, "WaistOrgnC0") * CFrame.Angles(0, YawAngle(Delta), 0) * CFrame.Angles(WaistPitch, 0, 0)
                    LocalAim.Neck = BaseC0(Neck, "NeckOrgnC0") * CFrame.Angles(NeckPitch, 0, 0)

                    Send(BodyMovementEvent, Waist, LocalAim.Waist)
                    Send(BodyMovementEvent, Neck, LocalAim.Neck)
                    WasAiming = true
                elseif WasAiming then
                    LocalAim.Waist, LocalAim.Neck = nil, nil
                    -- Switched off: straighten up once, then the game's own updates take over again
                    Send(BodyMovementEvent, Waist, BaseC0(Waist, "WaistOrgnC0"))
                    Send(BodyMovementEvent, Neck, BaseC0(Neck, "NeckOrgnC0"))
                    WasAiming = false
                end
            end

            task.wait(0.05)
        end
    end)

    --// Slower loop: auto-stomp

    task.spawn(function()
        local LastStomp = 0

        while Running do
            local Character = MyCharacter()
            local Root = Character and Character:FindFirstChild("HumanoidRootPart")

            -- Auto-stomp: fists out, someone downed within range
            local Tool = Character and Character:FindFirstChildWhichIsA("Tool")
            local FistRemote = Tool and Tool:FindFirstChild("FistRemote")

            if Features.FastFists and Features.AutoStomp and FistRemote and Root and os.clock() - LastStomp > 0.75 then
                for _, Other in next, Players:GetPlayers() do
                    local Target = Other ~= Player and Other.Character
                    local TargetRoot = Target and Target:FindFirstChild("HumanoidRootPart")

                    if TargetRoot and Target:GetAttribute("Critical") and (TargetRoot.Position - Root.Position).Magnitude <= Features.StompRange then
                        Root.CFrame = CFrame.lookAt(Root.Position, Vector3.new(TargetRoot.Position.X, Root.Position.Y, TargetRoot.Position.Z))
                        Send(FistRemote, "Stomp")
                        LastStomp = os.clock()
                        break
                    end
                end
            end

            task.wait(0.05)
        end
    end)

    OasisUI:OnUnload(function()
        Running = false
        Stepped:Disconnect()
        LocalRender:Disconnect()
        RemoteHook.Filter = nil
        WriteHook.Filter = nil

        Features.RollDash = false
        ApplyDashSpeed()
    end)
end

--// World, Vehicle, Economy and Admin features (from the ReplicatedStorage and PlayerGui dumps)

do
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")

    local Misc = Remotes:WaitForChild("Misc")
    local SystemModules = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Game"):WaitForChild("SystemModules")
    local Data = Player:WaitForChild("Data")

    local CameraDetectionEvent = Misc:FindFirstChild("CameraDetectionEvent")
    local PermitEvent = Misc:FindFirstChild("PermitEvent")
    local FirearmShopEvent = Misc:FindFirstChild("FirearmShopEvent")
    local Transportation = Misc:FindFirstChild("Transportation")
    local MoneyPrinter = Remotes:FindFirstChild("MoneyPrinter")
    local StartShift = Remotes:FindFirstChild("StartShift")
    local ATMAction = Remotes:FindFirstChild("ATMAction")

    local RemoteHook = getgenv().SuperNovaRemoteHook
    local Running = true

    local Toggles = {
        HideCCTV = false
    }

    --// Helpers

    local function Notify(Title, Content, Kind)
        OasisUI:Notify({Title = Title, Content = Content, Type = Kind or "Info", Duration = 4})
    end

    -- Calls a remote directly; our own calls always pass the remote filter
    local function Call(Remote, Method, ...)
        if not Remote then
            return false, "remote not found"
        end

        RemoteHook.Bypass = true
        local Result = table.pack(pcall(Remote[Method], Remote, ...))
        RemoteHook.Bypass = false

        return table.unpack(Result, 1, Result.n)
    end

    local function Module(Instance)
        local Ok, Result = pcall(require, Instance)
        return Ok and Result or nil
    end

    local function Money(Value)
        local Text = tostring(math.floor(tonumber(Value) or 0))
        local Formatted = Text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
        return "$" .. Formatted
    end

    -- Destinations may be parts, models or attachments
    local function PositionOf(Object)
        if Object:IsA("BasePart") then
            return Object.Position
        elseif Object:IsA("Model") then
            return Object:GetPivot().Position
        elseif Object:IsA("Attachment") then
            return Object.WorldPosition
        end
    end

    local function Root()
        local Character = Player.Character
        return Character and Character:FindFirstChild("HumanoidRootPart")
    end

    local function PlayerNames()
        local Names = {}

        for _, Other in next, Players:GetPlayers() do
            if Other ~= Player then
                table.insert(Names, Other.Name)
            end
        end

        table.sort(Names)
        return Names
    end

    local function ChildNames(Folder)
        local Names = {}

        for _, Child in next, Folder and Folder:GetChildren() or {} do
            table.insert(Names, Child.Name)
        end

        table.sort(Names)
        return Names
    end

    --// Remote rule: CCTV

    table.insert(RemoteHook.Rules, function(Remote, First, ...)
        -- CCTV: never tell the server a camera saw you
        if Toggles.HideCCTV and Remote == CameraDetectionEvent and First == true then
            return true
        end

        return false
    end)

    --//==================== World > Interactions ====================

    local Stealth = InteractTab:Section({Title = "Stealth", Icon = "eye-off", Side = "Left"})

    Stealth:Toggle({
        Title = "Hide from CCTV",
        Tooltip = "Security cameras never report you, so crimes without a mask or gloves don't add charges. This is also what the CameraDetected attribute is.",
        Default = false,
        Flag = "World.HideCCTV",
        Callback = function(Enabled)
            Toggles.HideCCTV = Enabled

            if Enabled and CameraDetectionEvent then
                Call(CameraDetectionEvent, "FireServer", false, nil) -- clear a "seen" the server may already have
            end
        end
    })

    local CameraLabel = Stealth:Label({Text = "Server thinks a camera sees you", Value = "no"})

    --//==================== World > Travel ====================

    local Destinations = GameFolder:WaitForChild("Locations"):FindFirstChild("PublicTransportation")
    Destinations = Destinations and Destinations:FindFirstChild("Destinations")

    local Travel = TravelTab:Section({Title = "Public transport from anywhere (test)", Icon = "navigation", Side = "Left"})
    Travel:Paragraph({Content = "Takes the bus without walking to a stop. The fare is still charged: $8 to $25, depending on distance."})

    local TravelTarget
    TravelTarget = Travel:Dropdown({
        Title = "Destination",
        Values = ChildNames(Destinations),
        Search = true,
        AllowNone = true,
        Action = {Icon = "refresh-cw", Tooltip = "Refresh", Callback = function() TravelTarget:Refresh(ChildNames(Destinations), true) end}
    })

    local FareLabel = Travel:Label({Text = "Fare", Value = "-"})

    Travel:Button({Title = "Travel", Icon = "send", Style = "Primary", Callback = function()
        local Destination = TravelTarget:Get() and Destinations and Destinations:FindFirstChild(TravelTarget:Get())

        if not Destination then
            return Notify("Travel", "Pick a destination first.", "Warning")
        end

        local Ok, Err = Call(Transportation, "FireServer", Destination)

        if not Ok then
            Notify("Travel", tostring(Err), "Error")
        end
    end})

    -- The server moves you itself when you travel, so its movement checks don't rubber-band you.
    -- If it trusts the destination you send, any part becomes a destination: try a player's root part.
    local TravelAnywhere = TravelTab:Section({Title = "Travel to a player (test)", Icon = "users", Side = "Right"})
    TravelAnywhere:Paragraph({Content = "Sends that player's position as the bus destination. If the server only accepts real stops, nothing happens and you keep your fare."})

    local TravelPlayer
    TravelPlayer = TravelAnywhere:Dropdown({
        Title = "Player",
        Values = PlayerNames(),
        Search = true,
        AllowNone = true,
        Action = {Icon = "refresh-cw", Tooltip = "Refresh players", Callback = function() TravelPlayer:Refresh(PlayerNames(), true) end}
    })

    TravelAnywhere:Button({Title = "Travel to player", Icon = "send", Style = "Primary", Callback = function()
        local Target = TravelPlayer:Get() and Players:FindFirstChild(TravelPlayer:Get())
        local TargetRoot = Target and Target.Character and Target.Character:FindFirstChild("HumanoidRootPart")

        if not TargetRoot then
            return Notify("Travel", "Pick a player that's loaded in.", "Warning")
        end

        local Ok, Err = Call(Transportation, "FireServer", TargetRoot)

        if not Ok then
            Notify("Travel", tostring(Err), "Error")
        end
    end})

    --//==================== Visual > Spectate ====================

    local SpectateTab = Visual:SubTab({Title = "Spectate", Icon = "scan"})
    local Spectate = SpectateTab:Section({Title = "Spectate", Icon = "scan", Side = "Left"})
    Spectate:Paragraph({Content = "Watch any player. The map loads around whoever you watch, so the ESP can see players far across the map."})

    local SpectateConnection
    local SpectateKeepCamera = false

    local function StopSpectating()
        if SpectateConnection then
            SpectateConnection:Disconnect()
            SpectateConnection = nil
        end

        local Character = Player.Character
        local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")

        if Humanoid then
            workspace.CurrentCamera.CameraSubject = Humanoid
        end

        Player.ReplicationFocus = nil
    end

    local function WatchCharacter(Character)
        local Humanoid = Character and Character:WaitForChild("Humanoid", 5)
        local TargetRoot = Character and Character:FindFirstChild("HumanoidRootPart")

        if Humanoid and not SpectateKeepCamera then
            workspace.CurrentCamera.CameraSubject = Humanoid
        end

        if TargetRoot then
            Player.ReplicationFocus = TargetRoot
        end
    end

    local SpectateTarget
    SpectateTarget = Spectate:Dropdown({
        Title = "Player",
        Values = PlayerNames(),
        Search = true,
        AllowNone = true,
        Action = {Icon = "refresh-cw", Tooltip = "Refresh players", Callback = function() SpectateTarget:Refresh(PlayerNames(), true) end}
    })

    Spectate:Checkbox({
        Title = "Keep my camera",
        Tooltip = "Only loads the area around them, for the ESP. Your camera stays on you.",
        Default = false,
        Flag = "Visual.Spectate.KeepCamera",
        Callback = function(Value) SpectateKeepCamera = Value end
    })

    Spectate:Buttons({
        {Title = "Watch", Icon = "eye", Style = "Primary", Callback = function()
            local Target = SpectateTarget:Get() and Players:FindFirstChild(SpectateTarget:Get())

            if not Target then
                return Notify("Spectate", "Pick a player first.", "Warning")
            end

            StopSpectating()
            WatchCharacter(Target.Character)
            SpectateConnection = Target.CharacterAdded:Connect(WatchCharacter)
        end},
        {Title = "Stop", Icon = "x", Callback = StopSpectating}
    })

    Players.PlayerAdded:Connect(function() SpectateTarget:Refresh(PlayerNames(), true) end)
    Players.PlayerRemoving:Connect(function() task.defer(function() SpectateTarget:Refresh(PlayerNames(), true) end) end)

    --//==================== Vehicle > Tuning ====================

    -- Each slider multiplies the car's own stock values; 1x is stock
    local CarMods = {
        {Key = "Power", Title = "Engine power", Fields = {"Horsepower", "E_Horsepower", "E_Torque"}, Max = 5},
        {Key = "TopSpeed", Title = "Top speed", Fields = {"SpeedLimit", "ReverseSpeed"}, Max = 4},
        {Key = "Boost", Title = "Turbo boost", Fields = {"T_Boost", "S_Boost"}, Max = 5},
        {Key = "Throttle", Title = "Throttle response", Fields = {"ThrotAccel", "RevAccel"}, Max = 5},
        {Key = "Brakes", Title = "Brake force", Fields = {"BrakeForce", "PBrakeForce"}, Max = 5},
        {Key = "Steering", Title = "Steering angle", Fields = {"SteerInner", "SteerOuter"}, Max = 1.6, Step = 0.05}
    }

    local CarState = {Enabled = false, NoTraction = false, Multipliers = {}}
    local TuneOriginals = setmetatable({}, {__mode = "k"})
    local CurrentTune, CurrentCarName = nil, nil

    local function FindTune()
        local Character = Player.Character
        local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
        local Node = Humanoid and Humanoid.SeatPart

        while Node and Node ~= workspace do
            local TuneModule = Node:FindFirstChild("A-Chassis Tune")

            if TuneModule then
                local Tune = Module(TuneModule)
                return type(Tune) == "table" and Tune or nil, Node.Name
            end

            Node = Node.Parent
        end
    end

    local function ApplyTune(Tune)
        local Saved = TuneOriginals[Tune]

        if not Saved then
            Saved = {}
            TuneOriginals[Tune] = Saved
        end

        if setreadonly then
            pcall(setreadonly, Tune, false)
        end

        for _, Mod in next, CarMods do
            local Multiplier = CarState.Enabled and (CarState.Multipliers[Mod.Key] or 1) or 1

            for _, Field in next, Mod.Fields do
                if type(Tune[Field]) == "number" then
                    if Saved[Field] == nil then
                        Saved[Field] = Tune[Field]
                    end

                    Tune[Field] = Saved[Field] * Multiplier
                end
            end
        end

        if type(Tune.TCSEnabled) == "boolean" then
            if Saved.TCSEnabled == nil then
                Saved.TCSEnabled = Tune.TCSEnabled
            end

            Tune.TCSEnabled = (CarState.Enabled and CarState.NoTraction) and false or Saved.TCSEnabled
        end
    end

    local function RefreshCar()
        if CurrentTune then
            ApplyTune(CurrentTune)
        end
    end

    local CarCard = TuningTab:Module({
        Title = "Car mods",
        Description = "Tunes the car you're driving. 1x is stock. Power and top speed apply the next time you get in.",
        Icon = "gauge",
        Side = "Left",
        Default = false,
        Flag = "Vehicle.Mods",
        Keybind = false,
        Opened = true,
        Callback = function(Enabled)
            CarState.Enabled = Enabled

            for Tune in next, TuneOriginals do
                ApplyTune(Tune)
            end
        end
    })

    for _, Mod in next, CarMods do
        CarCard:Slider({
            Title = Mod.Title,
            Min = 1,
            Max = Mod.Max,
            Step = Mod.Step or 0.1,
            Default = 1,
            Suffix = "x",
            Buttons = true,
            Flag = "Vehicle." .. Mod.Key,
            Callback = function(Value)
                CarState.Multipliers[Mod.Key] = Value
                RefreshCar()
            end
        })
    end

    CarCard:Checkbox({
        Title = "Traction control off",
        Tooltip = "Lets the wheels spin, so launches use all the extra power.",
        Default = false,
        Flag = "Vehicle.NoTraction",
        Callback = function(Value)
            CarState.NoTraction = Value
            RefreshCar()
        end
    })

    local CarInfo = TuningTab:Section({Title = "Current car", Icon = "info", Side = "Right"})
    local CarLabel = CarInfo:Label({Text = "Driving", Value = "nothing"})
    CarInfo:Paragraph({Content = "Your client drives your car, so the mods show for everyone. Get out and back in after changing power or top speed: the engine reads those once, when you sit down."})

    --//==================== Economy > Banking ====================

    local Balances = BankingTab:Section({Title = "Balances", Icon = "database", Side = "Right"})
    local WalletLabel = Balances:Label({Text = "Wallet", Value = "$0", ValueColor = "Success"})
    local BankLabel = Balances:Label({Text = "Bank", Value = "$0"})
    local DirtyLabel = Balances:Label({Text = "Dirty money", Value = "$0", ValueColor = "Warning"})

    -- Each ATM's Mesh carries a "Cooldown" BillboardGui with a PlayerName label: the server turns it on, with the
    -- robber's name, while that ATM is cooling down. ATMs we tried ourselves are also skipped for a while, in
    -- case the billboard isn't loaded or doesn't say.
    local Tried = {} -- ATM mesh -> os.clock() of our last attempt
    local TRIED_FOR = 15 * 60

    local function OnCooldown(Teller)
        local Board = Teller:FindFirstChild("Cooldown")
        local Name = Board and Board:FindFirstChild("PlayerName")
        local Shown = Board and Board:IsA("BillboardGui") and Board.Enabled and Name and Name:IsA("TextLabel") and Name.Text ~= ""

        return Shown or (Tried[Teller] and os.clock() - Tried[Teller] < TRIED_FOR) or false
    end

    local function ATMTellers()
        local Folder = GameFolder:FindFirstChild("Interactables")
        Folder = Folder and Folder:FindFirstChild("ATMs")
        local MyRoot = Root()
        local List = {}

        for _, Machine in next, Folder and Folder:GetChildren() or {} do
            local Teller = Machine:FindFirstChild("Mesh") or Machine:FindFirstChildWhichIsA("BasePart")

            if Teller then
                table.insert(List, {Teller = Teller, Distance = MyRoot and (Teller.Position - MyRoot.Position).Magnitude or math.huge, Ready = not OnCooldown(Teller)})
            end
        end

        table.sort(List, function(A, B) return A.Distance < B.Distance end)
        return List
    end

    local ATM = BankingTab:Section({Title = "ATM robbery", Icon = "key-round", Side = "Left"})
    ATM:Paragraph({Content = "Robs the nearest ATM that isn't cooling down. If it's not next to you, rides the bus there first (fare still charged)."})

    local ReadyLabel = ATM:Label({Text = "ATMs ready", Value = "-"})
    local Robbing = false

    ATM:Button({Title = "Rob next ATM", Icon = "zap", Style = "Danger", Callback = function()
        if Robbing then
            return
        end

        local Pick

        for _, Entry in next, ATMTellers() do
            if Entry.Ready then
                Pick = Entry
                break
            end
        end

        if not Pick then
            return Notify("ATM", "Every loaded ATM is cooling down or was robbed recently.", "Warning")
        end

        Robbing = true

        local Teller = Pick.Teller
        local Stand = Teller:FindFirstChild("SwipePos") or Teller

        if Pick.Distance > 10 then
            Notify("ATM", ("Riding to an ATM %d studs away..."):format(math.floor(Pick.Distance)), "Info")
            Call(Transportation, "FireServer", Stand)

            local Started = os.clock()

            repeat
                task.wait(0.25)
                local MyRoot = Root()
                Pick.Distance = MyRoot and (Teller.Position - MyRoot.Position).Magnitude or math.huge
            until Pick.Distance <= 12 or os.clock() - Started > 25

            if Pick.Distance > 12 then
                Robbing = false
                return Notify("ATM", "Couldn't get to the ATM. Try again.", "Error")
            end

            task.wait(1)

            -- It may have started cooling down while we rode over
            if OnCooldown(Teller) then
                Robbing = false
                return Notify("ATM", "Someone got to that ATM first. Press again for the next one.", "Warning")
            end
        end

        Tried[Teller] = os.clock()

        local Ok, Result = Call(ATMAction, "InvokeServer", "Rob", 0, Teller)
        Robbing = false
        Notify("ATM", Ok and ("Server said: " .. tostring(Result)) or tostring(Result), Ok and "Info" or "Error")
    end})

    task.spawn(function()
        while Running do
            pcall(function()
                local Ready, Total = 0, 0

                for _, Entry in next, ATMTellers() do
                    Total += 1
                    Ready += Entry.Ready and 1 or 0
                end

                ReadyLabel:SetValue(("%d / %d"):format(Ready, Total))
            end)

            task.wait(2)
        end
    end)

    --//==================== Economy > Printers ====================

    local PrinterState = {
        Enabled = false,
        Vent = true,
        VentAt = 70,
        Collect = true,
        Refill = true,
        RefillAt = 10,
        Power = true,
        Anywhere = false,
        Range = 30
    }

    local PrinterCard = PrintersTab:Module({
        Title = "Printer manager",
        Description = "Keeps money printers running: vents before they overheat, refills, powers on and collects.",
        Icon = "layers",
        Side = "Left",
        Default = false,
        Flag = "Economy.Printers",
        Keybind = false,
        Opened = true,
        Callback = function(Enabled) PrinterState.Enabled = Enabled end
    })

    PrinterCard:Checkbox({Title = "Auto vent", Default = true, Flag = "Economy.Printers.Vent", Callback = function(Value) PrinterState.Vent = Value end})
    PrinterCard:Slider({Title = "Vent at", Min = 30, Max = 95, Step = 5, Default = 70, Suffix = "°C", Flag = "Economy.Printers.VentAt", Callback = function(Value) PrinterState.VentAt = Value end})
    PrinterCard:Checkbox({Title = "Auto collect", Default = true, Flag = "Economy.Printers.Collect", Callback = function(Value) PrinterState.Collect = Value end})
    PrinterCard:Checkbox({Title = "Auto refill paper and ink", Tooltip = "Uses paper and ink from your inventory.", Default = true, Flag = "Economy.Printers.Refill", Callback = function(Value) PrinterState.Refill = Value end})
    PrinterCard:Slider({Title = "Refill below", Min = 0, Max = 50, Step = 5, Default = 10, Flag = "Economy.Printers.RefillAt", Callback = function(Value) PrinterState.RefillAt = Value end})
    PrinterCard:Checkbox({Title = "Auto power on", Tooltip = "Turns stopped printers back on (never while overheated).", Default = true, Flag = "Economy.Printers.Power", Callback = function(Value) PrinterState.Power = Value end})

    local Anywhere = PrinterCard:Checkbox({Title = "Manage from anywhere (test)", Tooltip = "Ignores distance. Only works if the server doesn't check it.", Default = false, Flag = "Economy.Printers.Anywhere", Callback = function(Value) PrinterState.Anywhere = Value end})
    PrinterCard:Slider({Title = "Range", Min = 10, Max = 100, Step = 5, Default = 30, Suffix = " st", Flag = "Economy.Printers.Range", Callback = function(Value) PrinterState.Range = Value end})
        :DependsOn(Anywhere, function(Value) return not Value end, "Hide")

    local PrinterInfo = PrintersTab:Section({Title = "Printers", Icon = "info", Side = "Right"})
    local PrinterCount = PrinterInfo:Label({Text = "In range", Value = "0"})
    local PrinterStored = PrinterInfo:Label({Text = "Waiting to collect", Value = "$0", ValueColor = "Success"})
    PrinterInfo:Paragraph({Content = "Only your own printers are managed. The server ignores everyone else's."})

    -- Placed printers live in GameFolder.PlacedItems as a Part with an ItemValues folder (Heat, Ink, Paper,
    -- PrinterBalance, Owner...). The remote wants the Part, the values sit in the folder.
    local KnownPrinters = {}

    local function ScanPrinters()
        table.clear(KnownPrinters)

        local Placed = GameFolder:FindFirstChild("PlacedItems")

        for _, Printer in next, Placed and Placed:GetChildren() or {} do
            local Values = Printer:FindFirstChild("ItemValues")
            local Owner = Values and Values:FindFirstChild("Owner")

            if Values and Values:FindFirstChild("PrinterBalance") and (not Owner or Owner.Value == Player.Name) then
                table.insert(KnownPrinters, Printer)
            end
        end
    end

    local function Value(Printer, Name)
        local Values = Printer:FindFirstChild("ItemValues")
        local Object = Values and Values:FindFirstChild(Name)
        return Object and Object.Value
    end

    local PrinterCooldowns = setmetatable({}, {__mode = "k"})

    local function PrinterAction(Printer, Action, Extra, Cooldown)
        local Stamps = PrinterCooldowns[Printer]

        if not Stamps then
            Stamps = {}
            PrinterCooldowns[Printer] = Stamps
        end

        local Key = Action .. tostring(Extra)

        if os.clock() - (Stamps[Key] or 0) < Cooldown then
            return
        end

        Stamps[Key] = os.clock()
        Call(MoneyPrinter, "FireServer", Action, Printer, Extra)
    end

    local function ManagePrinter(Printer)
        local Heat, Balance = Value(Printer, "Heat") or 0, Value(Printer, "PrinterBalance") or 0
        local Paper, Ink = Value(Printer, "Paper"), Value(Printer, "Ink")
        local Running, Overheated = Value(Printer, "IsRunning"), Value(Printer, "Overheated")

        if PrinterState.Vent and Heat >= PrinterState.VentAt then
            PrinterAction(Printer, "Vent", nil, 2)
        end

        if PrinterState.Collect and Balance > 0 then
            PrinterAction(Printer, "Collect", nil, 3)
        end

        if PrinterState.Refill then
            if type(Paper) == "number" and Paper <= PrinterState.RefillAt then
                PrinterAction(Printer, "Refill", "Paper", 5)
            end

            if type(Ink) == "number" and Ink <= PrinterState.RefillAt then
                PrinterAction(Printer, "Refill", "Ink", 5)
            end
        end

        -- "Power" toggles, so only send it to printers that are off and safe to start
        if PrinterState.Power and Running == false and not Overheated then
            PrinterAction(Printer, "Power", nil, 10)
        end
    end

    --//==================== Economy > Jobs ====================

    local Jobs = JobsTab:Section({Title = "Start a shift (test)", Icon = "package", Side = "Left"})
    Jobs:Paragraph({Content = "Starts a job without walking to its NPC. Jobs give the EXP that raises your rep, and you need 200 rep to buy guns."})

    local JobPick = Jobs:Segmented({Title = "Job", Values = {"Janitor", "Mailman", "Amazon"}, Default = "Janitor", Flag = "Economy.Job"})

    Jobs:Button({Title = "Start shift", Icon = "play", Style = "Primary", Callback = function()
        local Ok, Result = Call(StartShift, "InvokeServer", JobPick:Get())
        Notify("Jobs", Ok and ("Server said: " .. tostring(Result)) or tostring(Result), Ok and "Info" or "Error")
    end})

    --//==================== Economy > Shops ====================

    local FirearmShop = SystemModules:FindFirstChild("Shops") and SystemModules.Shops:FindFirstChild("FirearmShop")

    local Permit = ShopsTab:Section({Title = "Gun permit", Icon = "badge-check", Side = "Left"})
    Permit:Paragraph({Content = "Your client marks the permit test itself. This sends a perfect score without taking the test."})
    Permit:Button({Title = "Pass permit test", Icon = "check-check", Style = "Primary", Callback = function()
        local Shop = FirearmShop and Module(FirearmShop)
        local Questions = Shop and type(Shop.PermitQuestions) == "table" and #Shop.PermitQuestions or 0
        Questions = Questions > 0 and Questions or 3 -- the test has three questions

        Call(PermitEvent, "FireServer", "TestAttempt")
        task.wait(0.5)
        local Ok, Err = Call(PermitEvent, "FireServer", "TestResults", Questions)

        Notify("Gun permit", Ok and ("Sent a perfect score (" .. Questions .. "/" .. Questions .. ").") or tostring(Err), Ok and "Success" or "Error")
    end})

    --//==================== Loops ====================

    task.spawn(function()
        local LastScan = 0

        -- One pass of everything; run in pcall so a single failure can't stop balances, cars or printers
        local function Tick()
            -- Balances
            local Wallet, Bank, Dirty = Data:FindFirstChild("Wallet"), Data:FindFirstChild("Bank"), Data:FindFirstChild("DirtyMoney")
            WalletLabel:SetValue(Money(Wallet and Wallet.Value))
            BankLabel:SetValue(Money(Bank and Bank.Value))
            DirtyLabel:SetValue(Money(Dirty and Dirty.Value))

            -- CCTV: CameraDetected is the server's own record of your last camera report
            local Character = Player.Character
            local Seen = Character and Character:GetAttribute("CameraDetected") == true
            CameraLabel:SetValue(Seen and "yes" or "no")

            -- Travel fare (same formula as the game: $8 to $25 by distance)
            local Destination = TravelTarget:Get() and Destinations and Destinations:FindFirstChild(TravelTarget:Get())
            local MyRoot = Root()

            local Where = Destination and PositionOf(Destination)

            if Where and MyRoot then
                local Distance = (MyRoot.Position - Where).Magnitude
                FareLabel:SetValue("$" .. math.floor(math.clamp(Distance / 1000, 0, 1) * 17 + 8.5))
            else
                FareLabel:SetValue("-")
            end

            -- Car being driven
            CurrentTune, CurrentCarName = FindTune()
            CarLabel:SetValue(CurrentCarName or "nothing")

            if CurrentTune then
                ApplyTune(CurrentTune)
            end

            -- Printers
            if os.clock() - LastScan > 5 then
                ScanPrinters()
                LastScan = os.clock()
            end

            local InRange, Stored = 0, 0

            for _, Printer in next, KnownPrinters do
                local Ok, Pivot = pcall(function()
                    return Printer:IsA("Model") and Printer:GetPivot().Position or Printer.Position
                end)

                local Close = PrinterState.Anywhere or (Ok and MyRoot and (Pivot - MyRoot.Position).Magnitude <= PrinterState.Range)

                if Printer.Parent and Close then
                    InRange += 1
                    Stored += tonumber(Value(Printer, "PrinterBalance")) or 0

                    if PrinterState.Enabled then
                        ManagePrinter(Printer)
                    end
                end
            end

            PrinterCount:SetValue(tostring(InRange))
            PrinterStored:SetValue(Money(Stored))
        end

        while Running do
            local Ok, Err = pcall(Tick)

            if not Ok then
                warn("SuperNova > " .. tostring(Err))
            end

            task.wait(0.5)
        end
    end)

    OasisUI:OnUnload(function()
        Running = false
        Toggles.HideCCTV = false
        StopSpectating()

        CarState.Enabled = false
        for Tune in next, TuneOriginals do
            ApplyTune(Tune)
        end
    end)
end

--// Checks (Economy) and car theft (Vehicle)

do
    local Misc = Remotes:WaitForChild("Misc")
    local ActivateItem = Misc:FindFirstChild("ActivateItem")
    local Actions = Remotes:FindFirstChild("Actions")
    local CashCheck = Actions and Actions:FindFirstChild("CashCheck")
    local ProgramKey = Misc:FindFirstChild("ProgramKey") or Remotes:FindFirstChild("ProgramKey", true)

    local RemoteHook = getgenv().SuperNovaRemoteHook
    local Running = true

    local function Notify(Title, Content, Kind)
        OasisUI:Notify({Title = Title, Content = Content, Type = Kind or "Info", Duration = 4})
    end

    -- Direct remote call that our own remote filter always lets through
    local function Call(Remote, Method, ...)
        if not Remote then
            return false, "remote not found"
        end

        RemoteHook.Bypass = true
        local Result = table.pack(pcall(Remote[Method], Remote, ...))
        RemoteHook.Bypass = false

        return table.unpack(Result, 1, Result.n)
    end

    --//==================== Economy > Checks ====================

    -- A forged check carries the signature on file as its ForgeName attribute; the game waits for you to type it,
    -- then sends ActivateItem(tool, signature). We send ForgeName itself.
    local Checks = {AutoSign = false, Delay = 0.3, TypeSpeed = 0.04, AutoCash = false}
    local Signed = setmetatable({}, {__mode = "k"}) -- tool -> the ForgeName we already signed for it

    -- The game only cashes from the bank teller's dialogue (BankNPC), and the server wants you standing there.
    -- So ride the bus to the teller first, wait to arrive, then cash, and judge it by the wallet.
    local Transportation = Misc:FindFirstChild("Transportation")
    local Cashing = false

    local function BankTeller()
        local Folder = GameFolder:FindFirstChild("Interactables")
        Folder = Folder and Folder:FindFirstChild("EventNPCs")

        local Teller = Folder and Folder:FindFirstChild("BankNPC")
        return Teller and (Teller:FindFirstChild("HumanoidRootPart") or Teller.PrimaryPart or Teller:FindFirstChildWhichIsA("BasePart", true))
    end

    local function DistanceTo(Part)
        local Character = Player.Character
        local MyRoot = Character and Character:FindFirstChild("HumanoidRootPart")
        return MyRoot and Part and (Part.Position - MyRoot.Position).Magnitude or math.huge
    end

    local function CashChecks()
        if Cashing then
            return
        end

        local Teller = BankTeller()

        if not Teller then
            return Notify("Checks", "The bank teller isn't loaded in.", "Warning")
        end

        Cashing = true

        if DistanceTo(Teller) > 12 then
            Notify("Checks", "Riding to the bank...", "Info")
            Call(Transportation, "FireServer", Teller)

            local Started = os.clock()

            while DistanceTo(Teller) > 15 and os.clock() - Started < 25 do
                task.wait(0.25)
            end

            if DistanceTo(Teller) > 15 then
                Cashing = false
                return Notify("Checks", "Couldn't get to the bank. Walk there and press Cash checks again.", "Error")
            end

            task.wait(1)
        end

        local Wallet = Player:FindFirstChild("Data") and Player.Data:FindFirstChild("Wallet")
        local Before = Wallet and Wallet.Value or 0

        Call(CashCheck, "InvokeServer")
        task.wait(1.5)

        local Gained = (Wallet and Wallet.Value or 0) - Before
        Cashing = false

        if Gained > 0 then
            Notify("Checks", ("Cashed: +$%d."):format(Gained), "Success")
        else
            Notify("Checks", "Wallet didn't change. Make sure the check is signed and in your inventory.", "Warning")
        end
    end

    -- The forgery UI: Framework.FrameworkGUIS.Frames.ForgeryFrame, with Check.SignBox (TextBox) and SignButton
    local function ForgeryParts()
        local Gui = Player:FindFirstChild("PlayerGui")
        local Frame = Gui and Gui:FindFirstChild("Framework")
        Frame = Frame and Frame:FindFirstChild("FrameworkGUIS")
        Frame = Frame and Frame:FindFirstChild("Frames")
        Frame = Frame and Frame:FindFirstChild("ForgeryFrame")

        local Check = Frame and Frame:FindFirstChild("Check")
        return Check and Check:FindFirstChild("SignBox"), Frame and Frame:FindFirstChild("SignButton")
    end

    -- Presses the game's own Sign button, so its Sign() runs: it reads the box, marks the check signed,
    -- pauses its timer and sends ActivateItem itself
    local function PressSign(Button)
        if getconnections then
            local Pressed = false

            for _, Connection in next, getconnections(Button.MouseButton1Down) do
                pcall(Connection.Fire, Connection)
                Pressed = true
            end

            if Pressed then
                return true
            end
        end

        if firesignal then
            return pcall(firesignal, Button.MouseButton1Down)
        end

        return false
    end

    local function TrySign(Tool)
        local Name = Tool:GetAttribute("ForgeName")

        if not (Checks.AutoSign and Name) or Signed[Tool] == Name then
            return
        end

        Signed[Tool] = Name

        task.spawn(function()
            local function StillOpen()
                return Checks.AutoSign and Tool:GetAttribute("ForgeName") == Name
            end

            -- Wait like a person reading the check, then type the name one letter at a time
            task.wait(Checks.Delay)

            local Box, Button = ForgeryParts()

            if Box and Button then
                for Index = 1, #Name do
                    if not StillOpen() then
                        return
                    end

                    Box.Text = Name:sub(1, Index)
                    task.wait(Checks.TypeSpeed * (0.6 + math.random() * 0.8))
                end

                task.wait(0.1)

                if not StillOpen() then
                    return
                end

                if PressSign(Button) then
                    Notify("Checks", "Typed " .. Name .. " and pressed Sign.", "Success")
                else
                    -- No way to press the button: send what the button would have sent
                    Call(ActivateItem, "FireServer", Tool, Name)
                    Notify("Checks", "Sent " .. Name .. " directly (couldn't press the Sign button).", "Warning")
                end
            else
                if not StillOpen() then
                    return
                end

                Call(ActivateItem, "FireServer", Tool, Name)
                Notify("Checks", "Sent " .. Name .. " directly (check window not found).", "Warning")
            end

            if Checks.AutoCash then
                task.wait(1)
                CashChecks()
            end
        end)
    end

    local Signer = ChecksTab:Module({
        Title = "Auto-sign checks",
        Description = "Types the signature on file into the check and presses Sign for you the moment it opens.",
        Icon = "pencil",
        Side = "Left",
        Default = false,
        Flag = "Economy.Checks.AutoSign",
        Keybind = false,
        Opened = true,
        Callback = function(Enabled) Checks.AutoSign = Enabled end
    })

    Signer:Slider({Title = "Wait before typing", Min = 0, Max = 3, Step = 0.1, Default = 0.3, Suffix = " s", Flag = "Economy.Checks.Wait", Tooltip = "How long to look at the check before starting to type.", Callback = function(Value) Checks.Delay = Value end})
    Signer:Slider({Title = "Time per letter", Min = 0, Max = 0.3, Step = 0.01, Default = 0.04, Suffix = " s", Flag = "Economy.Checks.LetterTime", Tooltip = "Typing pace. Each letter varies a little so it doesn't look scripted.", Callback = function(Value) Checks.TypeSpeed = Value end})
    Signer:Checkbox({Title = "Cash after signing", Tooltip = "Rides to the bank and cashes the check right after it's signed.", Default = false, Flag = "Economy.Checks.AutoCash", Callback = function(Value) Checks.AutoCash = Value end})

    local CashSection = ChecksTab:Section({Title = "Cashing", Icon = "database", Side = "Right"})
    CashSection:Paragraph({Content = "Rides the bus to the bank teller if you're not there, then cashes your signed checks. The fare is still charged."})
    CashSection:Button({Title = "Cash checks", Icon = "database", Style = "Primary", Callback = CashChecks})

    local HowTo = ChecksTab:Section({Title = "How it works", Icon = "info", Side = "Right"})
    HowTo:Paragraph({Content = "Buy a <b>Blank Check</b> and a <b>Forgery Kit</b> from the Unknown Dealer and use them as normal. When the check opens, it signs itself."})

    --//==================== Vehicle > Theft ====================

    local function DriverSeatCar()
        local Character = Player.Character
        local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
        local Seat = Humanoid and Humanoid.SeatPart

        return Seat and Seat.Name == "DriveSeat" and Seat.Parent or nil
    end

    local Theft = TheftTab:Section({Title = "Instant key programming (test)", Icon = "key", Side = "Left"})
    Theft:Paragraph({Content = "Hold the <b>XTool ProPad</b>, sit in the driver's seat of the car you want and press Program key. Skips the wait and the kill-switch minigame."})

    local SeatLabel = Theft:Label({Text = "Driver's seat", Value = "not seated"})

    Theft:Button({Title = "Program key", Icon = "key", Style = "Primary", Callback = function()
        local Car = DriverSeatCar()

        if not Car then
            return Notify("Key programming", "Sit in the driver's seat first.", "Warning")
        end

        local Ok, Result = Call(ProgramKey, "InvokeServer", Car)
        Notify("Key programming", Ok and ("Server said: " .. tostring(Result)) or tostring(Result), Ok and "Info" or "Error")
    end})

    -- Car ESP: a floating label over every car, with its owner and distance
    local CarEsp = {Enabled = false, MaxDistance = 600, ShowOwner = true, HideMine = false, ShowLock = true, ShowCondition = true, UnlockedOnly = false}

    local CarCard = TheftTab:Module({
        Title = "Car ESP",
        Description = "Labels every car with its owner, lock, health, fuel and distance. Yours show green, unlocked cars blue, kill-switch cars orange.",
        Icon = "scan",
        Side = "Right",
        Default = false,
        Flag = "Vehicle.CarESP",
        Keybind = false,
        Opened = true,
        Callback = function(Enabled) CarEsp.Enabled = Enabled end
    })

    CarCard:Slider({Title = "Max distance", Min = 100, Max = 3000, Step = 50, Default = 600, Suffix = " st", Flag = "Vehicle.CarESP.Distance", Callback = function(Value) CarEsp.MaxDistance = Value end})
    CarCard:Checkbox({Title = "Show owner", Default = true, Flag = "Vehicle.CarESP.Owner", Callback = function(Value) CarEsp.ShowOwner = Value end})
    CarCard:Checkbox({Title = "Hide my cars", Default = false, Flag = "Vehicle.CarESP.HideMine", Callback = function(Value) CarEsp.HideMine = Value end})
    CarCard:Checkbox({Title = "Show lock", Default = true, Flag = "Vehicle.CarESP.Lock", Callback = function(Value) CarEsp.ShowLock = Value end})
    CarCard:Checkbox({Title = "Show health and fuel", Default = true, Flag = "Vehicle.CarESP.Condition", Callback = function(Value) CarEsp.ShowCondition = Value end})
    CarCard:Checkbox({Title = "Only unlocked cars", Tooltip = "Hides every car that's locked, so only the easy ones are left.", Default = false, Flag = "Vehicle.CarESP.UnlockedOnly", Callback = function(Value) CarEsp.UnlockedOnly = Value end})

    local TagFolder = Instance.new("Folder")
    TagFolder.Name = "SuperNovaCarESP"
    TagFolder.Parent = (gethui and gethui()) or game:GetService("CoreGui")

    local Tags = {} -- car model -> {Gui, Label}

    local function OwnerName(Car)
        local Owner = Car:FindFirstChild("Owner")

        if not Owner then
            return nil
        elseif Owner:IsA("ObjectValue") then
            return Owner.Value and Owner.Value.Name
        elseif Owner:IsA("ValueBase") then
            return tostring(Owner.Value)
        end
    end

    local function GetTag(Car)
        local Tag = Tags[Car]

        if not Tag then
            local Gui = Instance.new("BillboardGui")
            Gui.Size = UDim2.fromOffset(240, 54)
            Gui.StudsOffset = Vector3.new(0, 5, 0)
            Gui.AlwaysOnTop = true
            Gui.LightInfluence = 0

            local Label = Instance.new("TextLabel")
            Label.Size = UDim2.fromScale(1, 1)
            Label.BackgroundTransparency = 1
            Label.Font = Enum.Font.GothamBold
            Label.TextSize = 13
            Label.RichText = true
            Label.TextStrokeTransparency = 0.35
            Label.Parent = Gui

            Gui.Parent = TagFolder
            Tag = {Gui = Gui, Label = Label}
            Tags[Car] = Tag
        end

        return Tag
    end

    local function DropTag(Car)
        local Tag = Tags[Car]

        if Tag then
            Tag.Gui:Destroy()
            Tags[Car] = nil
        end
    end

    local function UpdateCars()
        local Folder = GameFolder:FindFirstChild("Vehicles")
        local Character = Player.Character
        local MyRoot = Character and Character:FindFirstChild("HumanoidRootPart")
        local Seen = {}

        if CarEsp.Enabled and Folder and MyRoot then
            for _, Car in next, Folder:GetChildren() do -- cars sit straight under GameFolder.Vehicles
                local Seat = Car:IsA("Model") and Car:FindFirstChild("DriveSeat")

                if Seat then
                    local Owner = OwnerName(Car)
                    local Mine = Owner == Player.Name
                    local Distance = (Seat.Position - MyRoot.Position).Magnitude

                    -- Every car carries VehicleLocked, Health and FuelAmount (a full tank is 150) at its root
                    local LockedValue = Car:FindFirstChild("VehicleLocked")
                    local Locked = LockedValue and LockedValue.Value
                    local Health = Car:FindFirstChild("Health")
                    local Fuel = Car:FindFirstChild("FuelAmount")

                    if Distance <= CarEsp.MaxDistance and not (Mine and CarEsp.HideMine) and not (CarEsp.UnlockedOnly and Locked ~= false) then
                        Seen[Car] = true

                        local Tag = GetTag(Car)
                        local KillSwitch = Car:GetAttribute("Killswitch")
                        local Details = {}

                        if CarEsp.ShowOwner and Owner then
                            table.insert(Details, Owner)
                        end

                        if CarEsp.ShowLock and LockedValue then
                            table.insert(Details, Locked and "locked" or '<font color="#5ab4ff">unlocked</font>')
                        end

                        if CarEsp.ShowCondition and Health then
                            table.insert(Details, ("%d hp"):format(math.floor(Health.Value)))
                        end

                        if CarEsp.ShowCondition and Fuel then
                            table.insert(Details, ("%d%% fuel"):format(math.floor(math.clamp(Fuel.Value / 150, 0, 1) * 100)))
                        end

                        table.insert(Details, ("%d st"):format(math.floor(Distance)))

                        Tag.Gui.Adornee = Car.PrimaryPart or Seat
                        Tag.Label.TextColor3 = Mine and Color3.fromRGB(90, 220, 130) or KillSwitch and Color3.fromRGB(255, 165, 60) or Locked == false and Color3.fromRGB(90, 180, 255) or Color3.fromRGB(240, 240, 240)
                        Tag.Label.Text = ("<b>%s</b>%s\n%s"):format(
                            Car.Name,
                            KillSwitch and "  · kill switch" or "",
                            table.concat(Details, "  · ")
                        )
                    end
                end
            end
        end

        for Car in next, Tags do
            if not Seen[Car] then
                DropTag(Car)
            end
        end
    end

    -- Teleport to a car: the bus remote moves you to whatever part you hand it, the same way travel to player works
    local Transportation = Misc:FindFirstChild("Transportation")
    local CarChoices = {} -- dropdown value -> car model

    local function CarList()
        local Folder = GameFolder:FindFirstChild("Vehicles")
        local Character = Player.Character
        local MyRoot = Character and Character:FindFirstChild("HumanoidRootPart")
        local Rows = {}

        table.clear(CarChoices)

        for Index, Car in next, Folder and Folder:GetChildren() or {} do
            local Seat = Car:IsA("Model") and Car:FindFirstChild("DriveSeat")

            if Seat then
                local Owner = OwnerName(Car) or "no owner"
                local Locked = Car:FindFirstChild("VehicleLocked")
                local Distance = MyRoot and math.floor((Seat.Position - MyRoot.Position).Magnitude) or 0
                local Key = ("%s · %s #%d"):format(Car.Name, Owner, Index)

                CarChoices[Key] = Car
                table.insert(Rows, {Distance, {Title = Car.Name, Value = Key, Description = ("%s · %s · %d st"):format(Owner, (Locked and Locked.Value == false) and "unlocked" or "locked", Distance)}})
            end
        end

        table.sort(Rows, function(A, B) return A[1] < B[1] end)

        local Values = {}

        for _, Row in next, Rows do
            table.insert(Values, Row[2])
        end

        return Values
    end

    local function GoToCar(Car)
        local Seat = Car and Car.Parent and Car:FindFirstChild("DriveSeat")

        if not Seat then
            return Notify("Teleport", "That car is gone. Refresh the list.", "Warning")
        end

        local Ok, Err = Call(Transportation, "FireServer", Seat)

        if not Ok then
            Notify("Teleport", tostring(Err), "Error")
        end
    end

    local Hop = TheftTab:Section({Title = "Teleport to car", Icon = "navigation", Side = "Left"})
    Hop:Paragraph({Content = "Rides the bus straight to a car, nearest first. The fare is still charged: $8 to $25."})

    local CarTarget
    CarTarget = Hop:Dropdown({
        Title = "Car",
        Values = CarList(),
        Search = true,
        AllowNone = true,
        Action = {Icon = "refresh-cw", Tooltip = "Refresh the list", Callback = function() CarTarget:Refresh(CarList(), true) end}
    })

    Hop:Buttons({
        {Title = "Teleport", Icon = "send", Style = "Primary", Callback = function()
            GoToCar(CarTarget:Get() and CarChoices[CarTarget:Get()])
        end},
        {Title = "Nearest unlocked", Icon = "unlock", Callback = function()
            local Folder = GameFolder:FindFirstChild("Vehicles")
            local Character = Player.Character
            local MyRoot = Character and Character:FindFirstChild("HumanoidRootPart")
            local Best, BestDistance = nil, math.huge

            for _, Car in next, Folder and Folder:GetChildren() or {} do
                local Seat = Car:FindFirstChild("DriveSeat")
                local Locked = Car:FindFirstChild("VehicleLocked")

                if Seat and MyRoot and Locked and Locked.Value == false and OwnerName(Car) ~= Player.Name then
                    local Distance = (Seat.Position - MyRoot.Position).Magnitude

                    if Distance < BestDistance then
                        Best, BestDistance = Car, Distance
                    end
                end
            end

            if not Best then
                return Notify("Teleport", "No unlocked cars are loaded in.", "Warning")
            end

            GoToCar(Best)
        end}
    })

    --// Loop: checks, seat label, car labels

    task.spawn(function()
        local LastCars = 0

        while Running do
            local Ok, Err = pcall(function()
                local Character = Player.Character

                for _, Tool in next, Character and Character:GetChildren() or {} do
                    if Tool:IsA("Tool") then
                        TrySign(Tool)
                    end
                end

                local Car = DriverSeatCar()
                SeatLabel:SetValue(Car and Car.Name or "not seated")

                if os.clock() - LastCars > 0.5 then
                    UpdateCars()
                    LastCars = os.clock()
                end
            end)

            if not Ok then
                warn("SuperNova > " .. tostring(Err))
            end

            task.wait(0.2)
        end
    end)

    OasisUI:OnUnload(function()
        Running = false
        TagFolder:Destroy()
    end)
end

--// Player inspector (World) and garage (Vehicle)

do
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")

    local RemoteHook = getgenv().SuperNovaRemoteHook
    local Running = true

    local function Notify(Title, Content, Kind)
        OasisUI:Notify({Title = Title, Content = Content, Type = Kind or "Info", Duration = 4})
    end

    -- Direct remote call that our own remote filter always lets through
    local function Call(Remote, Method, ...)
        if not Remote then
            return false, "remote not found"
        end

        RemoteHook.Bypass = true
        local Result = table.pack(pcall(Remote[Method], Remote, ...))
        RemoteHook.Bypass = false

        return table.unpack(Result, 1, Result.n)
    end

    local function Money(Value)
        local Text = tostring(math.floor(math.abs(tonumber(Value) or 0)))
        local Formatted = Text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
        return ((tonumber(Value) or 0) < 0 and "-$" or "$") .. Formatted
    end

    local function ChildNames(Folder, Skip)
        local Names = {}

        for _, Child in next, Folder and Folder:GetChildren() or {} do
            if Child ~= Skip then
                table.insert(Names, Child.Name)
            end
        end

        table.sort(Names)
        return Names
    end

    --//==================== World > Players ====================

    -- Every player's Data folder, backpack and SecondaryData (Safe, Bag, Trunk) replicate to your client
    local function Stat(Other, Name)
        local Data = Other:FindFirstChild("Data")
        local Object = Data and Data:FindFirstChild(Name)
        return Object and Object.Value
    end

    local function CashOnHand(Other)
        return (tonumber(Stat(Other, "Wallet")) or 0) + (tonumber(Stat(Other, "DirtyMoney")) or 0)
    end

    local function Worth(Other)
        return CashOnHand(Other) + (tonumber(Stat(Other, "Bank")) or 0)
    end

    -- The bounty the game shows lives on the contract board: GetBounty:InvokeServer("List") returns each
    -- target's reward. Data.Bounty only holds phone bounties, which are almost always 0.
    -- Wanted stars sit on each character as the "Wanted" attribute.
    local GetBounty = Remotes:FindFirstChild("GetBounty")
    local Contracts = {} -- lower-case username or user id -> reward
    local ContractList = {} -- the board's entries as the server sent them
    local BoardState = {Active = nil, Cooldown = nil, Closed = false}
    local LastContracts = 0

    -- The board's reply is {Contracts = {...}, Active = ..., Cooldown = ...}, or a closed-book message
    local function RefreshContracts(Force)
        if not GetBounty or (not Force and os.clock() - LastContracts < 20) then
            return
        end

        LastContracts = os.clock()

        local Ok, Reply = pcall(GetBounty.InvokeServer, GetBounty, "List")

        if not Ok or type(Reply) ~= "table" then
            BoardState.Closed = Ok and Reply ~= nil
            return
        end

        local List = type(Reply.Contracts) == "table" and Reply.Contracts or Reply

        BoardState.Closed = false
        BoardState.Active = Reply.Active
        BoardState.Cooldown = tonumber(Reply.Cooldown)

        table.clear(Contracts)
        table.clear(ContractList)

        for _, Entry in next, List do
            if type(Entry) == "table" then
                local Reward = tonumber(Entry.Reward) or 0
                table.insert(ContractList, Entry)

                for _, Key in next, {Entry.User, Entry.Name_, Entry.Name, Entry.UserId} do
                    if Key ~= nil then
                        Contracts[tostring(Key):lower():gsub("^@", "")] = Reward
                    end
                end
            end
        end
    end

    -- The player a board entry points at
    local function ContractPlayer(Entry)
        if type(Entry) ~= "table" then
            return typeof(Entry) == "Instance" and Entry:IsA("Player") and Entry or (type(Entry) == "string" and Players:FindFirstChild(Entry)) or nil
        end

        if tonumber(Entry.UserId) then
            local Found = Players:GetPlayerByUserId(tonumber(Entry.UserId))

            if Found then
                return Found
            end
        end

        for _, Key in next, {Entry.User, Entry.Name_, Entry.Name} do
            local Found = type(Key) == "string" and Players:FindFirstChild((Key:gsub("^@", "")))

            if Found then
                return Found
            end
        end
    end

    local function Bounty(Other)
        return Contracts[Other.Name:lower()] or Contracts[tostring(Other.UserId)] or (tonumber(Stat(Other, "Bounty")) or 0)
    end

    local function Wanted(Other)
        local Stars = Other.Character and tonumber(Other.Character:GetAttribute("Wanted")) or 0
        return Stars > 0 and string.rep("★", math.min(Stars, 5)) or "none"
    end

    -- Guns carry a Setting module; anything else in a container is an item
    local function Contents(Container)
        local Guns, Items = {}, 0

        for _, Tool in next, Container and Container:GetChildren() or {} do
            if Tool:IsA("Tool") then
                if Tool:FindFirstChild("Setting") or Tool:FindFirstChild("GunClient") then
                    table.insert(Guns, Tool.Name)
                else
                    Items += 1
                end
            end
        end

        return Guns, Items
    end

    local function Loadout(Other)
        local Secondary = Other:FindFirstChild("SecondaryData")
        local Lines = {}

        local Places = {
            {"On them", {Other.Character, Other:FindFirstChildOfClass("Backpack")}},
            {"Bag", {Secondary and Secondary:FindFirstChild("Bag")}},
            {"Safe", {Secondary and Secondary:FindFirstChild("Safe")}},
            {"Trunk", {Secondary and Secondary:FindFirstChild("Trunk")}}
        }

        for _, Place in next, Places do
            local Guns, Items = {}, 0

            for _, Container in next, Place[2] do
                local MoreGuns, MoreItems = Contents(Container)
                table.move(MoreGuns, 1, #MoreGuns, #Guns + 1, Guns)
                Items += MoreItems
            end

            if #Guns > 0 or Items > 0 then
                local Text = #Guns > 0 and table.concat(Guns, ", ") or "no guns"
                table.insert(Lines, ("<b>%s:</b> %s%s"):format(Place[1], Text, Items > 0 and ("  <font transparency=\"0.4\">(+%d items)</font>"):format(Items) or ""))
            end
        end

        return #Lines > 0 and table.concat(Lines, "\n") or "Nothing found."
    end

    local Inspect = PlayersTab:Section({Title = "Inspect a player", Icon = "user-search", Side = "Left"})

    local function OtherNames()
        return ChildNames(Players, Player)
    end

    local Target
    Target = Inspect:Dropdown({
        Title = "Player",
        Values = OtherNames(),
        Search = true,
        AllowNone = true,
        Action = {Icon = "refresh-cw", Tooltip = "Refresh the list", Callback = function() Target:Refresh(OtherNames(), true) end}
    })

    local Labels = {
        Wallet = Inspect:Label({Text = "Wallet", Value = "-", ValueColor = "Success"}),
        Dirty = Inspect:Label({Text = "Dirty money", Value = "-", ValueColor = "Warning"}),
        Bank = Inspect:Label({Text = "Bank", Value = "-"}),
        Bounty = Inspect:Label({Text = "Bounty (contract)", Value = "-", ValueColor = "Error"}),
        Wanted = Inspect:Label({Text = "Wanted", Value = "-", ValueColor = "Warning"}),
        Faction = Inspect:Label({Text = "Faction", Value = "-"}),
        Level = Inspect:Label({Text = "Level / rep", Value = "-"}),
        Permit = Inspect:Label({Text = "Gun permit", Value = "-"})
    }

    local Guns = Inspect:Paragraph({Title = "Guns", Content = "Pick a player."})

    local function UpdateInspect()
        local Other = Target:Get() and Players:FindFirstChild(Target:Get())

        if not Other then
            for _, Label in next, Labels do
                Label:SetValue("-")
            end

            return Guns:SetContent("Pick a player.")
        end

        local Faction = Stat(Other, "Faction")

        Labels.Wallet:SetValue(Money(Stat(Other, "Wallet")))
        Labels.Dirty:SetValue(Money(Stat(Other, "DirtyMoney")))
        Labels.Bank:SetValue(Money(Stat(Other, "Bank")))
        Labels.Bounty:SetValue(Money(Bounty(Other)))
        Labels.Wanted:SetValue(Wanted(Other))
        Labels.Faction:SetValue((Faction and Faction ~= "") and tostring(Faction) or "none")
        Labels.Level:SetValue(("%s / %s"):format(tostring(Stat(Other, "Level") or "-"), tostring(Stat(Other, "Reputation") or "-")))
        Labels.Permit:SetValue(Stat(Other, "GunPermit") and "yes" or "no")
        Guns:SetContent(Loadout(Other))
    end

    -- Leaderboard
    local Board = PlayersTab:Section({Title = "Richest players", Icon = "trophy", Side = "Right"})
    local SortBy = Board:Segmented({Title = "Sort by", Values = {"Cash on hand", "Total", "Bounty"}, Default = "Cash on hand", Flag = "World.Players.Sort"})
    local BoardText = Board:Paragraph({Content = "Loading..."})
    Board:Paragraph({Content = "Cash on hand is wallet plus dirty money: what drops when they die. Total adds the bank."})

    local function UpdateBoard()
        local Mode = SortBy:Get()
        local Rows = {}

        for _, Other in next, Players:GetPlayers() do
            if Other ~= Player and Other:FindFirstChild("Data") then
                local Score = Mode == "Total" and Worth(Other) or Mode == "Bounty" and Bounty(Other) or CashOnHand(Other)
                table.insert(Rows, {Other, Score})
            end
        end

        table.sort(Rows, function(A, B) return A[2] > B[2] end)

        local Lines = {}

        for Index = 1, math.min(10, #Rows) do
            local Other, Score = Rows[Index][1], Rows[Index][2]
            table.insert(Lines, ("%d. <b>%s</b>  %s"):format(Index, Other.Name, Money(Score)))
        end

        BoardText:SetContent(#Lines > 0 and table.concat(Lines, "\n") or "No one else is here.")
    end

    -- Money tags over heads
    local MoneyTags = {Enabled = false, Minimum = 0, MaxDistance = 500, ShowBounty = true, ShowWanted = true, AlwaysTargets = true, TargetsOnly = false}

    local TagCard = PlayersTab:Module({
        Title = "Money tags",
        Description = "Shows each player's cash, contract bounty and wanted stars over their head. Bounty targets show in red.",
        Icon = "badge-dollar-sign",
        Side = "Right",
        Default = false,
        Flag = "World.Players.MoneyTags",
        Keybind = false,
        Opened = true,
        Callback = function(Enabled) MoneyTags.Enabled = Enabled end
    })

    TagCard:Slider({Title = "Only above", Min = 0, Max = 100000, Step = 1000, Default = 0, Prefix = "$", Flag = "World.Players.MoneyTags.Minimum", Tooltip = "Hides anyone carrying less cash than this.", Callback = function(Value) MoneyTags.Minimum = Value end})
    TagCard:Slider({Title = "Max distance", Min = 50, Max = 2000, Step = 50, Default = 500, Suffix = " st", Flag = "World.Players.MoneyTags.Distance", Callback = function(Value) MoneyTags.MaxDistance = Value end})
    TagCard:Checkbox({Title = "Show bounty", Tooltip = "The reward on their contract, from the contract board.", Default = true, Flag = "World.Players.MoneyTags.Bounty", Callback = function(Value) MoneyTags.ShowBounty = Value end})
    TagCard:Checkbox({Title = "Show wanted stars", Default = true, Flag = "World.Players.MoneyTags.Wanted", Callback = function(Value) MoneyTags.ShowWanted = Value end})
    TagCard:Checkbox({Title = "Always show bounty targets", Tooltip = "Anyone with a contract on them shows, even below the cash minimum.", Default = true, Flag = "World.Players.MoneyTags.AlwaysTargets", Callback = function(Value) MoneyTags.AlwaysTargets = Value end})
    TagCard:Checkbox({Title = "Only bounty targets", Default = false, Flag = "World.Players.MoneyTags.TargetsOnly", Callback = function(Value) MoneyTags.TargetsOnly = Value end})

    local TagFolder = Instance.new("Folder")
    TagFolder.Name = "SuperNovaMoneyTags"
    TagFolder.Parent = (gethui and gethui()) or game:GetService("CoreGui")

    local Tags = {} -- player -> {Gui, Label}

    local function DropTag(Other)
        if Tags[Other] then
            Tags[Other].Gui:Destroy()
            Tags[Other] = nil
        end
    end

    local function GetTag(Other)
        local Tag = Tags[Other]

        if not Tag then
            local Gui = Instance.new("BillboardGui")
            Gui.Size = UDim2.fromOffset(200, 34)
            Gui.StudsOffset = Vector3.new(0, 3.2, 0)
            Gui.AlwaysOnTop = true
            Gui.LightInfluence = 0

            local Label = Instance.new("TextLabel")
            Label.Size = UDim2.fromScale(1, 1)
            Label.BackgroundTransparency = 1
            Label.Font = Enum.Font.GothamBold
            Label.TextSize = 12
            Label.RichText = true
            Label.TextColor3 = Color3.fromRGB(110, 230, 140)
            Label.TextStrokeTransparency = 0.35
            Label.Parent = Gui

            Gui.Parent = TagFolder
            Tag = {Gui = Gui, Label = Label}
            Tags[Other] = Tag
        end

        return Tag
    end

    local function UpdateTags()
        local Character = Player.Character
        local MyRoot = Character and Character:FindFirstChild("HumanoidRootPart")
        local Seen = {}

        if MoneyTags.Enabled and MyRoot then
            for _, Other in next, Players:GetPlayers() do
                local Head = Other ~= Player and Other.Character and Other.Character:FindFirstChild("Head")
                local Cash = CashOnHand(Other)
                local Reward = Head and Bounty(Other) or 0
                local Target = Reward > 0

                local Show = (MoneyTags.TargetsOnly and Target) or (not MoneyTags.TargetsOnly and (Cash >= MoneyTags.Minimum or (Target and MoneyTags.AlwaysTargets)))

                if Head and Show and (Head.Position - MyRoot.Position).Magnitude <= MoneyTags.MaxDistance then
                    local Dirty = tonumber(Stat(Other, "DirtyMoney")) or 0
                    local Stars = tonumber(Other.Character:GetAttribute("Wanted")) or 0
                    local Second = {}
                    local Tag = GetTag(Other)

                    if MoneyTags.ShowBounty and Target then
                        table.insert(Second, ('<font color="#ff6464">%s bounty</font>'):format(Money(Reward)))
                    end

                    if MoneyTags.ShowWanted and Stars > 0 then
                        table.insert(Second, ('<font color="#f0be3c">%s</font>'):format(string.rep("★", math.min(Stars, 5))))
                    end

                    Seen[Other] = true
                    Tag.Gui.Adornee = Head
                    Tag.Gui.Size = UDim2.fromOffset(220, #Second > 0 and 40 or 24)
                    Tag.Label.TextColor3 = Target and Color3.fromRGB(255, 120, 120) or Color3.fromRGB(110, 230, 140)
                    Tag.Label.Text = ("%s%s%s"):format(
                        Money(Stat(Other, "Wallet")),
                        Dirty > 0 and ('  <font color="#ffc850">%s dirty</font>'):format(Money(Dirty)) or "",
                        #Second > 0 and ("\n" .. table.concat(Second, "  ")) or ""
                    )
                end
            end
        end

        for Other in next, Tags do
            if not Seen[Other] then
                DropTag(Other)
            end
        end
    end

    Players.PlayerAdded:Connect(function() Target:Refresh(OtherNames(), true) end)
    Players.PlayerRemoving:Connect(function(Other)
        DropTag(Other)
        task.defer(function() Target:Refresh(OtherNames(), true) end)
    end)

    --//==================== World > Contracts ====================

    local Transportation = Remotes:FindFirstChild("Misc") and Remotes.Misc:FindFirstChild("Transportation")
    local ContractChoices = {} -- dropdown value -> board entry

    local function EntryName(Entry)
        local Target = ContractPlayer(Entry)

        if Target then
            return Target.Name
        end

        local Name = tostring(Entry.User or Entry.Name_ or Entry.FullName or "?")
        return (Name:gsub("^@", ""))
    end

    -- Who the active contract is on: the board sends it as an entry, a name or a player
    local function ActiveTarget()
        local Active = BoardState.Active
        return Active and ContractPlayer(Active)
    end

    local function ContractValues()
        local Values = {}
        table.clear(ContractChoices)

        for Index, Entry in next, ContractList do
            local Key = ("%s #%d"):format(EntryName(Entry), Index)
            local Stars = tonumber(Entry.Wanted) or 0

            ContractChoices[Key] = Entry
            table.insert(Values, {
                Title = ("%s  ·  %s"):format(EntryName(Entry), Money(Entry.Reward)),
                Value = Key,
                Description = ("%s risk  ·  %s%s"):format(tostring(Entry.Risk or "?"), Stars > 0 and (string.rep("★", math.min(Stars, 5)) .. "  ·  ") or "", Entry.Area and ("last seen " .. tostring(Entry.Area)) or "")
            })
        end

        return Values
    end

    local BoardSection = ContractsTab:Section({Title = "Contract board", Icon = "crosshair", Side = "Left"})
    BoardSection:Paragraph({Content = "The same board the bounty dealers show you, from anywhere. Taking a contract here is the same as taking it there."})

    local ActiveLabel = BoardSection:Label({Text = "Active contract", Value = "none", ValueColor = "Error"})
    local CooldownLabel = BoardSection:Label({Text = "Cooldown", Value = "-"})

    local ContractPick
    ContractPick = BoardSection:Dropdown({
        Title = "Contract",
        Values = ContractValues(),
        Search = true,
        AllowNone = true,
        Action = {Icon = "refresh-cw", Tooltip = "Check the streets again", Callback = function()
            RefreshContracts(true)
            ContractPick:Refresh(ContractValues(), true)
        end}
    })

    -- "Take" isn't in memory, only its strings: the board sends GetBounty("Take", <contract>) and answers falsy
    -- with "That contract went cold". So try the contract the likely ways, and stop at the first yes.
    local function TakeContract(Entry)
        local Target = ContractPlayer(Entry)
        local Attempts = {Entry.Id, Entry.ID, Entry.UserId, Target, Entry.User, Entry.Name_, Entry}

        for _, Argument in next, Attempts do
            if Argument ~= nil then
                local Ok, Result = Call(GetBounty, "InvokeServer", "Take", Argument)

                if Ok and Result then
                    return true, Result
                end
            end
        end

        return false
    end

    BoardSection:Buttons({
        {Title = "Take", Icon = "check", Style = "Primary", Callback = function()
            local Entry = ContractPick:Get() and ContractChoices[ContractPick:Get()]

            if not Entry then
                return Notify("Contracts", "Pick a contract first.", "Warning")
            end

            local Took, Result = TakeContract(Entry)
            RefreshContracts(true)

            if Took then
                Notify("Contracts", ("Took the contract on %s. Server said: %s"):format(EntryName(Entry), tostring(Result)), "Success")
            else
                Notify("Contracts", "That contract went cold, or you're still laying low. Refresh and try another.", "Error")
            end
        end},
        {Title = "Abandon", Icon = "x", Style = "Danger", Callback = function()
            local Ok, Result = Call(GetBounty, "InvokeServer", "Abandon")
            RefreshContracts(true)
            Notify("Contracts", Ok and ("Server said: " .. tostring(Result)) or tostring(Result), Ok and "Info" or "Error")
        end}
    })

    BoardSection:Button({Title = "Ride to my target", Icon = "send", Callback = function()
        local Target = ActiveTarget()
        local TargetRoot = Target and Target.Character and Target.Character:FindFirstChild("HumanoidRootPart")

        if not TargetRoot then
            return Notify("Contracts", Target and (Target.Name .. " isn't loaded in. Try again in a moment.") or "No active contract.", "Warning")
        end

        local Ok, Err = Call(Transportation, "FireServer", TargetRoot)

        if not Ok then
            Notify("Contracts", tostring(Err), "Error")
        end
    end})

    --// Bounty ESP

    local BountyEsp = {Enabled = false, Recolor = true, Highlight = true, Labels = true, OnlyMine = false}
    local TargetSet = {} -- players the ESP should paint red, rebuilt 4x a second instead of per draw call
    local MyTarget -- the player on your active contract
    local RED = Color3.fromRGB(255, 40, 40)

    local EspCard = ContractsTab:Module({
        Title = "Bounty ESP",
        Description = "Turns contract targets red in every ESP overlay, and marks your own target with a glow and label.",
        Icon = "target",
        Side = "Right",
        Default = false,
        Flag = "World.Contracts.ESP",
        Keybind = false,
        Opened = true,
        Callback = function(Enabled) BountyEsp.Enabled = Enabled end
    })

    EspCard:Checkbox({Title = "Recolor the ESP red", Tooltip = "Text, tracers, boxes, head dot, skeleton and highlight all turn red on bounty targets. The health bar keeps its health colors.", Default = true, Flag = "World.Contracts.ESP.Recolor", Callback = function(Value) BountyEsp.Recolor = Value end})
    EspCard:Checkbox({Title = "Glow on my target", Tooltip = "A red highlight on your contract target, so they show even with the ESP off.", Default = true, Flag = "World.Contracts.ESP.Glow", Callback = function(Value) BountyEsp.Highlight = Value end})
    EspCard:Checkbox({Title = "Label on my target", Tooltip = "Reward and distance over your target's head.", Default = true, Flag = "World.Contracts.ESP.Labels", Callback = function(Value) BountyEsp.Labels = Value end})
    EspCard:Checkbox({Title = "Recolor only my target", Tooltip = "Off: every contract target turns red in the ESP. On: only yours.", Default = false, Flag = "World.Contracts.ESP.OnlyMine", Callback = function(Value) BountyEsp.OnlyMine = Value end})

    local EspHook = EspCard:Label({Text = "ESP recolor", Value = "waiting for the ESP"})

    -- Rebuilt by the loop below; the ESP hook only does one table lookup per draw call
    local function RebuildTargets()
        table.clear(TargetSet)
        MyTarget = ActiveTarget()

        if not BountyEsp.Enabled then
            return
        end

        if MyTarget then
            TargetSet[MyTarget] = true
        end

        if not BountyEsp.OnlyMine then
            for _, Other in next, Players:GetPlayers() do
                if Other ~= Player and (Contracts[Other.Name:lower()] or Contracts[tostring(Other.UserId)]) then
                    TargetSet[Other] = true
                end
            end
        end
    end

    -- Every ESP color goes through the library's CoreFunctions.GetColor(Player, Default). It isn't exposed, so find
    -- it in memory by its constants and wrap it once per library load (Restart ESP loads a new copy).
    local HookedFor -- the ESP environment table we last hooked
    local Hooked = setmetatable({}, {__mode = "k"}) -- GetColor copies already wrapped

    local function HookEspColors()
        local Environment = getgenv().ExunysDeveloperESP

        -- One memory scan per ESP load, found or not: scanning is what costs frames
        if not Environment or HookedFor == Environment or not (getgc and hookfunction) then
            return
        end

        HookedFor = Environment
        local Found = false

        for _, Function in next, getgc(false) do
            if type(Function) == "function" and islclosure(Function) then
                local Ok, Constants = pcall(debug.getconstants, Function)

                -- Old copies from before a Restart ESP match too; wrapping them as well is harmless
                if Ok and not Hooked[Function] and table.find(Constants, "EnableTeamColors") and table.find(Constants, "TeamCheckOption") and table.find(Constants, "TeamColor") then
                    local Original
                    Original = hookfunction(Function, function(Target, Default, ...)
                        if BountyEsp.Recolor and TargetSet[Target] then
                            return RED
                        end

                        return Original(Target, Default, ...)
                    end)

                    Hooked[Function] = true
                    Found = true
                end
            end
        end

        EspHook:SetValue(Found and "on" or "not found")
    end

    local GlowFolder = Instance.new("Folder")
    GlowFolder.Name = "SuperNovaBountyESP"
    GlowFolder.Parent = (gethui and gethui()) or game:GetService("CoreGui")

    local Marks = {} -- player -> {Highlight, Gui, Label}

    local function DropMark(Other)
        local Mark = Marks[Other]

        if Mark then
            Mark.Highlight:Destroy()
            Mark.Gui:Destroy()
            Marks[Other] = nil
        end
    end

    local function GetMark(Other)
        local Mark = Marks[Other]

        if not Mark then
            local Highlight = Instance.new("Highlight")
            Highlight.FillColor = RED
            Highlight.OutlineColor = RED
            Highlight.FillTransparency = 0.55
            Highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            Highlight.Parent = GlowFolder

            local Gui = Instance.new("BillboardGui")
            Gui.Size = UDim2.fromOffset(220, 22)
            Gui.StudsOffset = Vector3.new(0, 4.6, 0)
            Gui.AlwaysOnTop = true
            Gui.LightInfluence = 0

            local Label = Instance.new("TextLabel")
            Label.Size = UDim2.fromScale(1, 1)
            Label.BackgroundTransparency = 1
            Label.Font = Enum.Font.GothamBlack
            Label.TextSize = 13
            Label.TextColor3 = RED
            Label.TextStrokeTransparency = 0.3
            Label.Parent = Gui
            Gui.Parent = GlowFolder

            Mark = {Highlight = Highlight, Gui = Gui, Label = Label}
            Marks[Other] = Mark
        end

        return Mark
    end

    local function UpdateMarks()
        local Character = Player.Character
        local MyRoot = Character and Character:FindFirstChild("HumanoidRootPart")
        local Seen = {}

        -- Only your own contract target gets a glow and label
        local Other = BountyEsp.Enabled and MyTarget
        local TheirCharacter = Other and Other.Character
        local Head = TheirCharacter and TheirCharacter:FindFirstChild("Head")

        if Head and (BountyEsp.Highlight or BountyEsp.Labels) then
            local Mark = GetMark(Other)
            local Distance = MyRoot and math.floor((Head.Position - MyRoot.Position).Magnitude) or 0

            Seen[Other] = true

            if Mark.Highlight.Adornee ~= TheirCharacter then
                Mark.Highlight.Adornee = TheirCharacter
            end

            Mark.Highlight.Enabled = BountyEsp.Highlight
            Mark.Gui.Adornee = Head
            Mark.Gui.Enabled = BountyEsp.Labels
            Mark.Label.Text = ("TARGET  %s  ·  %d st"):format(Money(Bounty(Other)), Distance)
        end

        for Other in next, Marks do
            if not Seen[Other] then
                DropMark(Other)
            end
        end
    end

    Players.PlayerRemoving:Connect(DropMark)

    task.spawn(function()
        local LastHook = 0

        while Running do
            pcall(function()
                local Target = ActiveTarget()
                ActiveLabel:SetValue(BoardState.Closed and "board closed" or (Target and Target.Name) or (BoardState.Active and tostring(EntryName(BoardState.Active))) or "none")
                CooldownLabel:SetValue(BoardState.Cooldown and BoardState.Cooldown > 0 and (math.ceil(BoardState.Cooldown) .. " s") or "ready")

                if BountyEsp.Enabled and BountyEsp.Recolor and os.clock() - LastHook > 5 then
                    LastHook = os.clock()
                    HookEspColors()
                end

                RebuildTargets()
                UpdateMarks()
            end)

            task.wait(0.25)
        end
    end)

    OasisUI:OnUnload(function()
        BountyEsp.Enabled = false
        GlowFolder:Destroy()
    end)

    --//==================== Vehicle > Garage ====================

    -- Drive on empty: A-Chassis cuts your throttle on your own client when FuelAmount hits 0
    local Fuel = {Enabled = false}

    local FuelCard = GarageTab:Module({
        Title = "Drive on empty (test)",
        Description = "Keeps your car's engine running with an empty tank. Only your client sees the fuel, the server still has 0.",
        Icon = "fuel",
        Side = "Right",
        Default = false,
        Flag = "Vehicle.Garage.InfiniteFuel",
        Keybind = false,
        Opened = true,
        Callback = function(Enabled) Fuel.Enabled = Enabled end
    })

    local FuelLabel = FuelCard:Label({Text = "Fuel", Value = "not driving"})

    local function MyCar()
        local Character = Player.Character
        local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
        local Seat = Humanoid and Humanoid.SeatPart

        return Seat and Seat.Name == "DriveSeat" and Seat.Parent or nil
    end

    -- Drive reads the value every engine step, so the local write has to land before it each frame
    local FuelLoop = RunService.Heartbeat:Connect(function()
        if not Fuel.Enabled then
            return
        end

        local Car = MyCar()
        local Amount = Car and Car:FindFirstChild("FuelAmount")

        if Amount and Amount.Value <= 0 then
            Amount.Value = 1
        end
    end)

    --// Loop: inspector, leaderboard, money tags, garage labels

    task.spawn(function()
        while Running do
            local Ok, Err = pcall(function()
                RefreshContracts()
                UpdateInspect()
                UpdateBoard()
                UpdateTags()

                local Car = MyCar()
                local Amount = Car and Car:FindFirstChild("FuelAmount")
                FuelLabel:SetValue(Amount and ("%d%%"):format(math.floor(math.clamp(Amount.Value / 150, 0, 1) * 100)) or "not driving")
            end)

            if not Ok then
                warn("SuperNova > " .. tostring(Err))
            end

            task.wait(0.5)
        end
    end)

    OasisUI:OnUnload(function()
        Running = false
        FuelLoop:Disconnect()
        TagFolder:Destroy()
    end)
end

--// FrameworkHandler features: fuel, jail, objectives, factions

do
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Teams = game:GetService("Teams")

    local Misc = Remotes:WaitForChild("Misc")
    local DrainFuel = Remotes:FindFirstChild("DrainFuel")
    local ReleasePlayer = Remotes:FindFirstChild("ReleasePlayer")
    local Transportation = Misc:FindFirstChild("Transportation")
    local SetFaction = Misc:FindFirstChild("SetFaction")
    local Data = Player:WaitForChild("Data")

    local RemoteHook = getgenv().SuperNovaRemoteHook
    local Running = true

    local function Notify(Title, Content, Kind)
        OasisUI:Notify({Title = Title, Content = Content, Type = Kind or "Info", Duration = 4})
    end

    -- Direct remote call that our own remote filter always lets through
    local function Call(Remote, Method, ...)
        if not Remote then
            return false, "remote not found"
        end

        RemoteHook.Bypass = true
        local Result = table.pack(pcall(Remote[Method], Remote, ...))
        RemoteHook.Bypass = false

        return table.unpack(Result, 1, Result.n)
    end

    local function Money(Value)
        local Text = tostring(math.floor(math.abs(tonumber(Value) or 0)))
        local Formatted = Text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
        return ((tonumber(Value) or 0) < 0 and "-$" or "$") .. Formatted
    end

    local function Reply(Title, Ok, Result)
        Notify(Title, Ok and ("Server said: " .. tostring(Result)) or tostring(Result), Ok and "Info" or "Error")
    end

    local Options = {NoFuelDrain = false, AutoRelease = false}

    --//==================== Vehicle > Garage: no fuel drain ====================

    -- While you drive, FrameworkHandler sends DrainFuel every 0.3 s. The server only drains when told to.
    table.insert(RemoteHook.Rules, function(Remote)
        return Options.NoFuelDrain and Remote == DrainFuel
    end)

    GarageTab:Module({
        Title = "No fuel drain",
        Description = "Your client tells the server when to burn fuel. This stops telling it, so the tank stays where it is.",
        Icon = "fuel",
        Side = "Left",
        Default = false,
        Flag = "Vehicle.Garage.NoFuelDrain",
        Keybind = false,
        Callback = function(Enabled) Options.NoFuelDrain = Enabled end
    })

    --//==================== Player > Character: jail ====================

    local JailSection = CharacterTab:Section({Title = "Jail (test)", Icon = "lock-open", Side = "Right"})
    JailSection:Paragraph({Content = "When your sentence ends, your client asks the server to let you out. This asks early."})

    local JailLabel = JailSection:Label({Text = "Sentence", Value = "free"})

    local function Jailed()
        local Prisoner = Teams:FindFirstChild("Prisoner")
        local Timer = Data:FindFirstChild("JailTimer")
        return (Prisoner and Player.Team == Prisoner) or (Timer and Timer.Value > 0), Timer and Timer.Value or 0
    end

    local function Release()
        local Ok, Result = Call(ReleasePlayer, "InvokeServer")
        Reply("Jail", Ok, Result)
    end

    JailSection:Button({Title = "Release me", Icon = "lock-open", Style = "Primary", Callback = Release})
    JailSection:Checkbox({Title = "Ask automatically", Tooltip = "Asks once every 10 seconds while you're jailed.", Default = false, Flag = "Client.Jail.AutoRelease", Callback = function(Value) Options.AutoRelease = Value end})

    --//==================== World > Travel: objectives ====================

    -- Jobs point you at a target through values on your player: TrapAssignment (trap phone buyer),
    -- MailObjective (Mailman) and PackageObjective (Amazon)
    local function ObjectiveTarget(Name)
        local Holder = Player:FindFirstChild(Name)
        local Target = Holder and (Holder:IsA("ObjectValue") and Holder.Value or nil)

        if not Target then
            local Attribute = Player:GetAttribute(Name)
            Target = typeof(Attribute) == "Instance" and Attribute or nil
        end

        if Target and Target:IsA("Model") then
            Target = Target.PrimaryPart or Target:FindFirstChildWhichIsA("BasePart", true)
        end

        return Target and Target:IsA("BasePart") and Target or nil
    end

    local Objectives = TravelTab:Section({Title = "Ride to your objective", Icon = "flag", Side = "Right"})
    Objectives:Paragraph({Content = "Takes the bus straight to whatever your current job wants. The fare is still charged."})

    local Labels = {}

    for _, Entry in next, {
        {"TrapAssignment", "Trap phone buyer", "Call a buyer on the trap phone first."},
        {"MailObjective", "Mail stop", "Start a Mailman shift first."},
        {"PackageObjective", "Amazon drop-off", "Start an Amazon shift first."}
    } do
        local Name, Title, Hint = Entry[1], Entry[2], Entry[3]

        Labels[Name] = Objectives:Label({Text = Title, Value = "none"})
        Objectives:Button({Title = "Ride to " .. Title:lower(), Icon = "send", Callback = function()
            local Target = ObjectiveTarget(Name)

            if not Target then
                return Notify("Objective", "No " .. Title:lower() .. " right now. " .. Hint, "Warning")
            end

            local Ok, Err = Call(Transportation, "FireServer", Target)

            if not Ok then
                Notify("Objective", tostring(Err), "Error")
            end
        end})
    end

    local Baggies = Objectives:Label({Text = "Bagged sugarcane on you", Value = "0"})

    local function CountBaggies()
        local Count = 0

        for _, Container in next, {Player:FindFirstChildOfClass("Backpack"), Player.Character} do
            for _, Tool in next, Container and Container:GetChildren() or {} do
                if Tool.Name == "Bagged Sugarcane" then
                    Count += 1
                end
            end
        end

        return Count
    end

    --//==================== Player > Identity ====================

    -- Joining checks Roblox group membership only on your client, then sends SetFaction(name)
    local FactionNames = {}

    pcall(function()
        local Info = require(ReplicatedStorage.Modules.Game.InfoModules.FactionInfo)

        for _, Faction in next, Info.OfficialFactions do
            table.insert(FactionNames, Faction.Name)
        end
    end)

    table.sort(FactionNames)

    local Factions = IdentityTab:Section({Title = "Join any faction (test)", Icon = "users", Side = "Right"})
    Factions:Paragraph({Content = "Joins a gang without being in its Roblox group. You have to leave your current one first."})

    local CurrentFaction = Factions:Label({Text = "Current", Value = "-"})
    local FactionPick = Factions:Dropdown({Title = "Faction", Values = FactionNames, Search = true, AllowNone = true})

    Factions:Buttons({
        {Title = "Join", Icon = "log-in", Style = "Primary", Callback = function()
            if not FactionPick:Get() then
                return Notify("Faction", "Pick a faction first.", "Warning")
            end

            local Ok, Result = Call(SetFaction, "InvokeServer", FactionPick:Get())
            Reply("Faction", Ok, Result)
        end},
        {Title = "Leave", Icon = "log-out", Callback = function()
            local Ok, Result = Call(SetFaction, "InvokeServer", "None")
            Reply("Faction", Ok, Result)
        end}
    })

    --// Loop: labels and auto-release

    task.spawn(function()
        local LastRelease = 0

        while Running do
            pcall(function()
                local InJail, Seconds = Jailed()
                JailLabel:SetValue(InJail and (math.floor(Seconds) .. " s left") or "free")

                if InJail and Options.AutoRelease and os.clock() - LastRelease >= 10 then
                    LastRelease = os.clock()
                    Release()
                end

                for Name, Label in next, Labels do
                    local Target = ObjectiveTarget(Name)
                    Label:SetValue(Target and Target.Name or "none")
                end

                Baggies:SetValue(tostring(CountBaggies()))

                local Faction = Data:FindFirstChild("Faction")
                CurrentFaction:SetValue(Faction and tostring(Faction.Value) or "-")
            end)

            task.wait(1)
        end
    end)

    OasisUI:OnUnload(function()
        Running = false
        Options.NoFuelDrain = false
    end)
end

--// Vehicle damage test (Vehicle > Damage): watch a car and send it DamageVehicle hits

do
    local DamageVehicle = Remotes:FindFirstChild("DamageVehicle")

    local RemoteHook = getgenv().SuperNovaRemoteHook
    local Running = true

    local function Notify(Title, Content, Kind)
        OasisUI:Notify({Title = Title, Content = Content, Type = Kind or "Info", Duration = 4})
    end

    -- Direct remote call that our own remote filter always lets through
    local function Call(Remote, Method, ...)
        if not Remote then
            return false, "remote not found"
        end

        RemoteHook.Bypass = true
        local Result = table.pack(pcall(Remote[Method], Remote, ...))
        RemoteHook.Bypass = false

        return table.unpack(Result, 1, Result.n)
    end

    local State = {Hits = 5, Delay = 0.25, Spectating = false, Loop = false}
    local Choices = {} -- dropdown value -> car model

    local function Owner(Car)
        local Value = Car:FindFirstChild("Owner")

        if Value and Value:IsA("ObjectValue") then
            return Value.Value and Value.Value.Name
        elseif Value and Value:IsA("ValueBase") then
            return tostring(Value.Value)
        end
    end

    local function Health(Car)
        local Value = Car and Car:FindFirstChild("Health")
        return Value and Value.Value
    end

    -- GunClient reports the part the bullet touched; the body's main part stands in for that
    local function HitPart(Car)
        local Body = Car:FindFirstChild("Body")
        return Car.PrimaryPart or (Body and Body:FindFirstChildWhichIsA("BasePart", true)) or Car:FindFirstChildWhichIsA("BasePart", true)
    end

    local function CarList()
        local Folder = GameFolder:FindFirstChild("Vehicles")
        local Character = Player.Character
        local MyRoot = Character and Character:FindFirstChild("HumanoidRootPart")
        local Rows = {}

        table.clear(Choices)

        for Index, Car in next, Folder and Folder:GetChildren() or {} do
            local Part = Car:IsA("Model") and HitPart(Car)

            if Part then
                local Distance = MyRoot and math.floor((Part.Position - MyRoot.Position).Magnitude) or 0
                local Key = ("%s · %s #%d"):format(Car.Name, Owner(Car) or "no owner", Index)
                local CarHealth = Health(Car)

                Choices[Key] = Car
                table.insert(Rows, {Distance, {Title = Car.Name, Value = Key, Description = ("%s · %s · %d st"):format(Owner(Car) or "no owner", CarHealth and (math.floor(CarHealth) .. " hp") or "no health", Distance)}})
            end
        end

        table.sort(Rows, function(A, B) return A[1] < B[1] end)

        local Values = {}

        for _, Row in next, Rows do
            table.insert(Values, Row[2])
        end

        return Values
    end

    local Picker = DamageTab:Section({Title = "Target car", Icon = "car", Side = "Left"})
    Picker:Paragraph({Content = "Pick a car, watch it, and hit it with the gun's vehicle-damage call. Nearest first."})

    local Target
    Target = Picker:Dropdown({
        Title = "Car",
        Values = CarList(),
        Search = true,
        AllowNone = true,
        Action = {Icon = "refresh-cw", Tooltip = "Refresh the list", Callback = function() Target:Refresh(CarList(), true) end}
    })

    local HealthLabel = Picker:Label({Text = "Health", Value = "-", ValueColor = "Success"})
    local ResultLabel = Picker:Label({Text = "Last result", Value = "-"})

    local function Picked()
        local Car = Target:Get() and Choices[Target:Get()]
        return Car and Car.Parent and Car or nil
    end

    --// Spectate the car: camera on it, and the map streamed around it so it stays loaded

    local SpectateConnection

    local function StopWatching()
        if SpectateConnection then
            SpectateConnection:Disconnect()
            SpectateConnection = nil
        end

        local Character = Player.Character
        local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")

        if Humanoid then
            workspace.CurrentCamera.CameraSubject = Humanoid
        end

        Player.ReplicationFocus = nil
    end

    local function Watch(Car)
        StopWatching()

        local Part = Car and (Car:FindFirstChild("DriveSeat") or HitPart(Car))

        if not Part then
            return Notify("Spectate", "Pick a car that's loaded in.", "Warning")
        end

        workspace.CurrentCamera.CameraSubject = Part
        Player.ReplicationFocus = Part

        -- Stop watching if the car despawns
        SpectateConnection = Car.AncestryChanged:Connect(function(_, Parent)
            if not Parent then
                StopWatching()
                Notify("Spectate", "That car is gone.", "Warning")
            end
        end)
    end

    Picker:Toggle({
        Title = "Spectate this car",
        Default = false,
        Callback = function(Enabled)
            State.Spectating = Enabled

            if Enabled then
                Watch(Picked())
            else
                StopWatching()
            end
        end
    })

    Target:OnChanged(function()
        if State.Spectating then
            Watch(Picked())
        end
    end)

    --// Damage

    local Hitter = DamageTab:Section({Title = "Damage (test)", Icon = "zap", Side = "Right"})
    Hitter:Paragraph({Content = "Sends DamageVehicle with a part of the car, exactly what a bullet hit would send. If health doesn't drop, the server checks the hit and this does nothing."})

    Hitter:Slider({Title = "Hits per press", Min = 1, Max = 25, Step = 1, Default = 5, Flag = "Vehicle.Damage.Hits", Callback = function(Value) State.Hits = Value end})
    Hitter:Slider({Title = "Time between hits", Min = 0.05, Max = 1, Step = 0.05, Default = 0.25, Suffix = " s", Flag = "Vehicle.Damage.Delay", Tooltip = "A real gun can't hit faster than its fire rate. Going far below that is easy to flag.", Callback = function(Value) State.Delay = Value end})

    local Busy = false

    local function Hit(Car, Count)
        local Part = HitPart(Car)
        local Last

        for _ = 1, Count do
            if not (Running and Car.Parent) then
                break
            end

            local Ok, Result = Call(DamageVehicle, "InvokeServer", Part)
            Last = Ok and tostring(Result) or ("error: " .. tostring(Result))
            task.wait(State.Delay)
        end

        return Last
    end

    Hitter:Button({Title = "Damage", Icon = "zap", Style = "Danger", Callback = function()
        local Car = Picked()

        if not Car then
            return Notify("Damage", "Pick a car that's loaded in.", "Warning")
        end

        if Busy then
            return
        end

        Busy = true

        local Before = Health(Car)
        local Last = Hit(Car, State.Hits)
        local After = Health(Car)

        Busy = false
        ResultLabel:SetValue(tostring(Last))

        if Before and After then
            Notify("Damage", ("%s: %d -> %d hp (%s)."):format(Car.Name, math.floor(Before), math.floor(After), After < Before and "it works" or "no damage, the server checks hits"), After < Before and "Success" or "Warning")
        else
            Notify("Damage", "Sent. Server said: " .. tostring(Last), "Info")
        end
    end})

    Hitter:Toggle({
        Title = "Keep hitting until it breaks",
        Default = false,
        Callback = function(Enabled)
            State.Loop = Enabled
        end
    })

    --// Loop: health label and the keep-hitting toggle

    task.spawn(function()
        while Running do
            pcall(function()
                local Car = Picked()
                local CarHealth = Health(Car)

                HealthLabel:SetValue(Car and (CarHealth and tostring(math.floor(CarHealth)) or "no health value") or "-")

                if State.Loop and Car and not Busy then
                    if CarHealth and CarHealth <= 0 then
                        State.Loop = false
                        Notify("Damage", Car.Name .. " is broken.", "Success")
                    else
                        Busy = true
                        ResultLabel:SetValue(tostring(Hit(Car, 1)))
                        Busy = false
                    end
                end
            end)

            task.wait(State.Loop and 0 or 0.5)
        end
    end)

    OasisUI:OnUnload(function()
        Running = false

        if State.Spectating then
            StopWatching()
        end
    end)
end

--// Render (World > Render): full bright, fog, time, effects, field of view, stretched resolution, camera bob

do
    local Lighting = game:GetService("Lighting")
    local RunService = game:GetService("RunService")

    local Render = {
        FullBright = false, NoFog = false, NoShadows = false,
        Time = false, ClockTime = 14,
        Tint = false, TintColor = Color3.fromRGB(140, 140, 160),
        Exposure = false, ExposureValue = 0.5,
        NoFlashes = false, NoBlur = false, NoBloom = false, NoGrading = false,
        Fov = false, FovValue = 90,
        Stretch = false, StretchValue = 0.75,
        NoBob = false
    }

    -- Every property we override keeps its original here, so turning an option off puts the game's value back
    local Originals = {} -- instance -> {property -> original}

    local function Set(Object, Property, Value)
        local Saved = Originals[Object]

        if not Saved then
            Saved = {}
            Originals[Object] = Saved
        end

        if Saved[Property] == nil then
            Saved[Property] = Object[Property]
        end

        if Object[Property] ~= Value then
            Object[Property] = Value
        end
    end

    local function Restore(Object, Property)
        local Saved = Originals[Object]

        if Saved and Saved[Property] ~= nil then
            pcall(function() Object[Property] = Saved[Property] end)
            Saved[Property] = nil
        end
    end

    -- The game's own screen effects, grouped the way the options switch them off
    local EffectGroups = {
        NoFlashes = {"Flash", "DeathFlash", "Died", "Murder", "IntroCorrection"},
        NoBlur = {"Blur", "MainBlur", "DepthOfField", "SceneDOF"},
        NoBloom = {"Bloom", "SunRays"},
        NoGrading = {"ColorCorrection"}
    }

    --// UI

    local LightingCard = RenderTab:Module({
        Title = "Full bright",
        Description = "Lights the whole map evenly: noon sun, no shadows, no darkness indoors.",
        Icon = "sun",
        Side = "Left",
        Default = false,
        Flag = "World.Render.FullBright",
        Keybind = false,
        Opened = true,
        Callback = function(Enabled) Render.FullBright = Enabled end
    })

    LightingCard:Checkbox({Title = "No fog", Tooltip = "Clears fog and atmosphere haze so you can see across the map.", Default = false, Flag = "World.Render.NoFog", Callback = function(Value) Render.NoFog = Value end})
    LightingCard:Checkbox({Title = "No shadows", Default = false, Flag = "World.Render.NoShadows", Callback = function(Value) Render.NoShadows = Value end})

    local WorldSection = RenderTab:Section({Title = "World", Icon = "globe", Side = "Left"})

    local TimeToggle = WorldSection:Toggle({Title = "Time of day", Tooltip = "Locks the clock on your screen only.", Default = false, Flag = "World.Render.Time", Callback = function(Value) Render.Time = Value end})
    WorldSection:Slider({Title = "Clock", Min = 0, Max = 24, Step = 0.25, Default = 14, Suffix = " h", Flag = "World.Render.ClockTime", Callback = function(Value) Render.ClockTime = Value end})
        :DependsOn(TimeToggle, nil, "Hide")

    WorldSection:Toggle({
        Title = "World tint",
        Tooltip = "Colors the ambient light: dark blue for a night look, warm for sunset, and so on.",
        Default = false,
        Flag = "World.Render.Tint",
        Callback = function(Value) Render.Tint = Value end,
        Color = {Default = Render.TintColor, Flag = "World.Render.TintColor", Callback = function(Value) Render.TintColor = Value end}
    })

    local ExposureToggle = WorldSection:Toggle({Title = "Exposure", Default = false, Flag = "World.Render.Exposure", Callback = function(Value) Render.Exposure = Value end})
    WorldSection:Slider({Title = "Exposure", Min = -2, Max = 2, Step = 0.1, Default = 0.5, Flag = "World.Render.ExposureValue", Callback = function(Value) Render.ExposureValue = Value end})
        :DependsOn(ExposureToggle, nil, "Hide")

    local Effects = RenderTab:Section({Title = "Screen effects", Icon = "sparkles", Side = "Right"})
    Effects:Toggle({Title = "No flashes", Tooltip = "Removes the white flash, the death and murder color effects and the intro tint.", Default = false, Flag = "World.Render.NoFlashes", Callback = function(Value) Render.NoFlashes = Value end})
    Effects:Toggle({Title = "No blur", Tooltip = "Removes menu blur and depth of field.", Default = false, Flag = "World.Render.NoBlur", Callback = function(Value) Render.NoBlur = Value end})
    Effects:Toggle({Title = "No bloom or sun rays", Default = false, Flag = "World.Render.NoBloom", Callback = function(Value) Render.NoBloom = Value end})
    Effects:Toggle({Title = "No color grading", Tooltip = "Shows the game's raw colors without its color correction.", Default = false, Flag = "World.Render.NoGrading", Callback = function(Value) Render.NoGrading = Value end})

    local CameraSection = RenderTab:Section({Title = "Camera", Icon = "camera", Side = "Right"})

    local FovToggle = CameraSection:Toggle({Title = "Field of view", Tooltip = "Steps aside while you aim down sights, so scopes still zoom.", Default = false, Flag = "World.Render.Fov", Callback = function(Value) Render.Fov = Value end})
    CameraSection:Slider({Title = "FOV", Min = 50, Max = 120, Step = 1, Default = 90, Suffix = "°", Flag = "World.Render.FovValue", Callback = function(Value) Render.FovValue = Value end})
        :DependsOn(FovToggle, nil, "Hide")

    local StretchToggle = CameraSection:Toggle({Title = "Stretched resolution", Tooltip = "The 4:3 stretched look: everything wider. Can throw off silent aim's circle a little.", Default = false, Flag = "World.Render.Stretch", Callback = function(Value) Render.Stretch = Value end})
    CameraSection:Slider({Title = "Stretch", Min = 0.5, Max = 1, Step = 0.01, Default = 0.75, Flag = "World.Render.StretchValue", Tooltip = "Lower is wider. 0.75 is about 4:3 on a 16:9 screen.", Callback = function(Value) Render.StretchValue = Value end})
        :DependsOn(StretchToggle, nil, "Hide")

    CameraSection:Toggle({Title = "No camera bob", Tooltip = "Stops the head sway while walking and sprinting.", Default = false, Flag = "World.Render.NoBob", Callback = function(Value) Render.NoBob = Value end})

    --// Lighting and effects, re-applied every frame because the game sets time and effects itself

    -- Effects and the atmosphere are looked up once a second instead of a dozen FindFirstChild calls every frame
    local EffectCache, Atmosphere, LastLookup = {}, nil, 0
    local FULL_BRIGHT_AMBIENT = Color3.fromRGB(150, 150, 150)

    local function Lookup()
        if os.clock() - LastLookup < 1 then
            return
        end

        LastLookup = os.clock()
        Atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")

        for _, Names in next, EffectGroups do
            for _, Name in next, Names do
                local Effect = Lighting:FindFirstChild(Name)
                EffectCache[Name] = Effect and Effect:IsA("PostEffect") and Effect or nil
            end
        end
    end

    local function AnyLighting()
        return Render.FullBright or Render.NoFog or Render.NoShadows or Render.Time or Render.Tint or Render.Exposure
            or Render.NoFlashes or Render.NoBlur or Render.NoBloom or Render.NoGrading
    end

    -- Something still holds an original we have to put back
    local function AnySaved()
        for _, Saved in next, Originals do
            if next(Saved) ~= nil then
                return true
            end
        end

        return false
    end

    local function SetOrRestore(Object, Property, Value)
        if Value ~= nil and Value ~= false then
            Set(Object, Property, Value)
        else
            Restore(Object, Property)
        end
    end

    local function ApplyLighting()
        -- Every option off and every original back: nothing to do this frame
        if not AnyLighting() and not AnySaved() then
            return
        end

        Lookup()

        -- One wanted value per property, so options that share a property never fight each other
        local Ambient = (Render.Tint and Render.TintColor) or (Render.FullBright and FULL_BRIGHT_AMBIENT) or nil
        local Clock = (Render.Time and Render.ClockTime) or (Render.FullBright and 14) or nil

        SetOrRestore(Lighting, "Ambient", Ambient)
        SetOrRestore(Lighting, "OutdoorAmbient", Ambient)
        SetOrRestore(Lighting, "ClockTime", Clock)
        SetOrRestore(Lighting, "Brightness", Render.FullBright and 2 or nil)

        if Render.FullBright or Render.NoShadows then
            Set(Lighting, "GlobalShadows", false)
        else
            Restore(Lighting, "GlobalShadows")
        end

        if Render.NoFog then
            Set(Lighting, "FogEnd", 1e6)
            Set(Lighting, "FogStart", 1e6)

            if Atmosphere then
                Set(Atmosphere, "Density", 0)
                Set(Atmosphere, "Haze", 0)
            end
        else
            Restore(Lighting, "FogEnd")
            Restore(Lighting, "FogStart")

            if Atmosphere then
                Restore(Atmosphere, "Density")
                Restore(Atmosphere, "Haze")
            end
        end

        if Render.Exposure then
            Set(Lighting, "ExposureCompensation", Render.ExposureValue)
        else
            Restore(Lighting, "ExposureCompensation")
        end

        for Option, Names in next, EffectGroups do
            for _, Name in next, Names do
                local Effect = EffectCache[Name]

                if Effect then
                    if Render[Option] then
                        Set(Effect, "Enabled", false)
                    else
                        Restore(Effect, "Enabled")
                    end
                end
            end
        end
    end

    --// Field of view: the game zooms the FOV in to aim, so only override while it's at (or above) its resting value

    local GameFov -- the game's resting FOV, learned when the option turns on
    local LastWritten

    local function ApplyFov(Camera)
        if not Render.Fov then
            if LastWritten and GameFov then
                Camera.FieldOfView = GameFov
            end

            GameFov, LastWritten = nil, nil
            return
        end

        local Current = Camera.FieldOfView

        if not GameFov then
            GameFov = Current
        end

        -- Something other than us changed it this frame: the game. Zoomed in means aiming, so leave it be.
        if LastWritten and math.abs(Current - LastWritten) > 0.01 then
            if Current < GameFov - 1 then
                LastWritten = nil
                return
            end
        elseif not LastWritten and Current < GameFov - 1 then
            return
        end

        Camera.FieldOfView = Render.FovValue
        LastWritten = Render.FovValue
    end

    --// Camera bob: CharacterClient.Bobbing sways Humanoid.CameraOffset every frame

    local DisabledBob -- the Bobbing script we switched off

    local function ApplyBob(Character)
        if not (Render.NoBob or DisabledBob) then
            return
        end

        local Client = Character and Character:FindFirstChild("CharacterClient")
        local Bob = Client and Client:FindFirstChild("Bobbing")
        local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")

        if Render.NoBob then
            if Bob and Bob ~= DisabledBob and not Bob.Disabled then
                Bob.Disabled = true
                DisabledBob = Bob
            end

            if Humanoid and Humanoid.CameraOffset ~= Vector3.zero then
                Humanoid.CameraOffset = Vector3.zero
            end
        elseif DisabledBob then
            if DisabledBob.Parent then
                DisabledBob.Disabled = false
            end

            DisabledBob = nil
        end
    end

    RunService:BindToRenderStep("SuperNovaRender", Enum.RenderPriority.Camera.Value + 1, function()
        pcall(ApplyLighting)

        local Camera = workspace.CurrentCamera

        if Camera then
            pcall(ApplyFov, Camera)

            -- Stretch squashes the view vertically after the camera has been placed for this frame
            if Render.Stretch then
                Camera.CFrame = Camera.CFrame * CFrame.new(0, 0, 0, 1, 0, 0, 0, Render.StretchValue, 0, 0, 0, 1)
            end
        end

        pcall(ApplyBob, Player.Character)
    end)

    OasisUI:OnUnload(function()
        RunService:UnbindFromRenderStep("SuperNovaRender")

        for Object, Saved in next, Originals do
            for Property, Value in next, Saved do
                pcall(function() Object[Property] = Value end)
            end
        end

        table.clear(Originals)

        if DisabledBob and DisabledBob.Parent then
            DisabledBob.Disabled = false
        end

        if LastWritten and GameFov and workspace.CurrentCamera then
            workspace.CurrentCamera.FieldOfView = GameFov
        end
    end)
end

--// Auto math book (Farming > Autofarm): solves each question and presses the right answer button

do
    local Running = true
    local Study = {Enabled = false, Delay = 1.5, KeepOut = true}

    local function Notify(Title, Content, Kind)
        OasisUI:Notify({Title = Title, Content = Content, Type = Kind or "Info", Duration = 4})
    end

    -- Arithmetic with + - * / ^ and brackets, written the way the book writes it ("12 x 7", "36 ÷ 4")
    local function Solve(Expression)
        local Text = Expression:gsub("×", "*"):gsub("÷", "/"):gsub("−", "-"):gsub("[xX]", "*"):gsub(",", "")
        local Tokens, Position = {}, 1

        while Position <= #Text do
            local Character = Text:sub(Position, Position)

            if Character:match("%s") then
                Position += 1
            elseif Character:match("[%d%.]") then
                local Number = Text:match("^%d*%.?%d+", Position)
                table.insert(Tokens, tonumber(Number))
                Position += #Number
            elseif Character:match("[%+%-%*/%^%(%)]") then
                table.insert(Tokens, Character)
                Position += 1
            else
                return nil
            end
        end

        local Index = 1
        local Expr

        local function Atom()
            local Token = Tokens[Index]

            if Token == "(" then
                Index += 1
                local Value = Expr()
                -- Skip the closing bracket
                Index += 1
                return Value
            elseif Token == "-" then
                Index += 1
                return -Atom()
            elseif type(Token) == "number" then
                Index += 1
                return Token
            end

            error("bad expression")
        end

        local function Power()
            local Value = Atom()

            if Tokens[Index] == "^" then
                Index += 1
                return Value ^ Power()
            end

            return Value
        end

        local function Term()
            local Value = Power()

            while Tokens[Index] == "*" or Tokens[Index] == "/" do
                local Operator = Tokens[Index]
                Index += 1
                local Right = Power()
                Value = Operator == "*" and Value * Right or Value / Right
            end

            return Value
        end

        function Expr()
            local Value = Term()

            while Tokens[Index] == "+" or Tokens[Index] == "-" do
                local Operator = Tokens[Index]
                Index += 1
                local Right = Term()
                Value = Operator == "+" and Value + Right or Value - Right
            end

            return Value
        end

        local Ok, Result = pcall(Expr)
        return Ok and Index > #Tokens and Result or nil
    end

    -- The book: Framework.FrameworkGUIS.Frames.MathFrame, with Texts.Question / Texts.Number and Buttons.A1-A3
    local function BookParts()
        local Frame = Player:FindFirstChild("PlayerGui")

        for _, Name in next, {"Framework", "FrameworkGUIS", "Frames", "MathFrame"} do
            Frame = Frame and Frame:FindFirstChild(Name)
        end

        local Texts = Frame and Frame:FindFirstChild("Texts")
        local Buttons = Frame and Frame:FindFirstChild("Buttons")

        return Texts and Texts:FindFirstChild("Question"), Texts and Texts:FindFirstChild("Number"), Buttons
    end

    -- Fires the button's own MouseButton1Down hooks, so the game's SendAnswer(index) runs as if clicked
    local function Press(Button)
        if getconnections then
            local Pressed = false

            for _, Connection in next, getconnections(Button.MouseButton1Down) do
                pcall(Connection.Fire, Connection)
                Pressed = true
            end

            if Pressed then
                return true
            end
        end

        return firesignal and pcall(firesignal, Button.MouseButton1Down) or false
    end

    local Card = Autofarm:Module({
        Title = "Auto math book",
        Description = "Answers the math book's questions for you, right every time. Equip the Math Book and it studies on its own.",
        Icon = "book-open",
        Side = "Right",
        Default = false,
        Flag = "Farm.MathBook",
        Keybind = false,
        Opened = true,
        Callback = function(Enabled) Study.Enabled = Enabled end
    })

    Card:Slider({Title = "Answer after", Min = 0.3, Max = 8, Step = 0.1, Default = 1.5, Suffix = " s", Flag = "Farm.MathBook.Delay", Tooltip = "Each question has a 10 s timer. A short think looks more like a person.", Callback = function(Value) Study.Delay = Value end})
    Card:Checkbox({Title = "Keep the book out", Tooltip = "Re-equips the Math Book from your backpack if it gets put away, so studying keeps going.", Default = true, Flag = "Farm.MathBook.KeepOut", Callback = function(Value) Study.KeepOut = Value end})

    local AnsweredLabel = Card:Label({Text = "Answered", Value = "0", ValueColor = "Success"})
    local GainedLabel = Card:Label({Text = "Intelligence gained", Value = "0"})

    local Answered = 0
    local LastKey -- question number + text we already answered

    local function TryAnswer()
        local Question, Number, Buttons = BookParts()

        if not (Question and Buttons) then
            return
        end

        local Expression = Question.Text:match("Question%s*:%s*(.-)%s*=%s*%?")
        local Key = (Number and Number.Text or "") .. "|" .. Question.Text

        if not Expression or Key == LastKey then
            return
        end

        local Result = Solve(Expression)

        if not Result then
            LastKey = Key
            return Notify("Math book", "Couldn't read \"" .. Expression .. "\". Answer this one yourself.", "Warning")
        end

        -- The closest of the three choices: exact for whole numbers, nearest for rounded division
        local Best, BestGap

        for Index = 1, 3 do
            local Button = Buttons:FindFirstChild("A" .. Index)
            local Value = Button and tonumber((Button.Text:gsub("[^%d%.%-]", "")))

            if Value and (not BestGap or math.abs(Value - Result) < BestGap) then
                Best, BestGap = Button, math.abs(Value - Result)
            end
        end

        if not Best then
            return
        end

        LastKey = Key

        task.delay(Study.Delay * (0.8 + math.random() * 0.4), function()
            -- Still the same question?
            if Study.Enabled and (Number and Number.Text or "") .. "|" .. Question.Text == Key and Press(Best) then
                Answered += 1
                AnsweredLabel:SetValue(tostring(Answered))
            end
        end)
    end

    local function KeepBookOut()
        local Character = Player.Character
        local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
        local Backpack = Player:FindFirstChildOfClass("Backpack")
        local Book = Backpack and Backpack:FindFirstChild("Math Book")

        if Humanoid and Book and not Character:FindFirstChild("Math Book") then
            Humanoid:EquipTool(Book)
        end
    end

    task.spawn(function()
        local Data = Player:WaitForChild("Data", 30)
        local Intelligence = Data and Data:WaitForChild("Intelligence", 30)
        local Start = Intelligence and Intelligence.Value
        local LastEquip = 0

        while Running do
            pcall(function()
                if Study.Enabled then
                    TryAnswer()

                    if Study.KeepOut and os.clock() - LastEquip > 3 then
                        LastEquip = os.clock()
                        KeepBookOut()
                    end
                end

                if Intelligence and Start then
                    GainedLabel:SetValue(tostring(math.floor((Intelligence.Value - Start) * 100) / 100))
                end
            end)

            task.wait(0.2)
        end
    end)

    OasisUI:OnUnload(function()
        Running = false
        Study.Enabled = false
    end)
end

--// Safety (Overview): anti-AFK, staff alert, panic key, startup self-check

do
    local UserInputService = game:GetService("UserInputService")
    local VirtualUser = game:GetService("VirtualUser")
    local Running = true

    local function Notify(Title, Content, Kind, Duration)
        OasisUI:Notify({Title = Title, Content = Content, Type = Kind or "Info", Duration = Duration or 5})
    end

    local Safety = Overview:Section({Title = "Safety", Icon = "shield", Side = "Left"})

    --// Anti-AFK: Roblox kicks after 20 idle minutes; a virtual right click on Idled resets that timer

    local AntiAfk = true

    Safety:Toggle({Title = "Anti-AFK", Tooltip = "Stops Roblox's 20 minute idle kick, so farms can run while you're away.", Default = true, Flag = "Safety.AntiAfk", Callback = function(Value) AntiAfk = Value end})

    local IdleConnection = Player.Idled:Connect(function()
        if AntiAfk then
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.zero)
        end
    end)

    --// Staff alert: the game's own admin code counts rank 2+ in group 788949314, or an AdminTempRank attribute

    local STAFF_GROUP = 788949314
    local Staff = {Alert = true, Leave = false}
    local StaffHere = {} -- player -> rank

    Safety:Toggle({Title = "Staff alert", Tooltip = "Warns you when a game admin is in the server or joins.", Default = true, Flag = "Safety.StaffAlert", Callback = function(Value) Staff.Alert = Value end})
    Safety:Checkbox({Title = "Leave when staff joins", Tooltip = "Disconnects you the moment an admin is in the server.", Default = false, Flag = "Safety.StaffLeave", Callback = function(Value) Staff.Leave = Value end})

    local StaffLabel = Safety:Label({Text = "Staff in server", Value = "checking...", ValueColor = "Success"})

    local function RefreshStaffLabel()
        local Names = {}

        for Other, Rank in next, StaffHere do
            table.insert(Names, ("%s (rank %d)"):format(Other.Name, Rank))
        end

        StaffLabel:SetValue(#Names > 0 and table.concat(Names, ", ") or "none")
        StaffLabel:SetValueColor(#Names > 0 and "Error" or "Success")
    end

    local function CheckStaff(Other, Joined)
        if Other == Player then
            return
        end

        -- GetRankInGroup asks Roblox's web API, so it can be slow or fail; treat a failure as not staff
        local Ok, Rank = pcall(Other.GetRankInGroup, Other, STAFF_GROUP)
        Rank = math.max(Ok and tonumber(Rank) or 0, tonumber(Other:GetAttribute("AdminTempRank")) or 0)

        if Rank >= 2 and Other.Parent then
            StaffHere[Other] = Rank
            RefreshStaffLabel()

            if Staff.Alert then
                Notify("Staff", ("%s is a game admin (rank %d) and %s."):format(Other.Name, Rank, Joined and "just joined" or "is in this server"), "Error", 12)
            end

            if Staff.Leave then
                Player:Kick("SuperNova: left because staff (" .. Other.Name .. ") is in the server.")
            end
        end
    end

    task.spawn(function()
        for _, Other in next, Players:GetPlayers() do
            CheckStaff(Other, false)
        end

        RefreshStaffLabel()
    end)

    local JoinConnection = Players.PlayerAdded:Connect(function(Other)
        CheckStaff(Other, true)
    end)

    local LeaveConnection = Players.PlayerRemoving:Connect(function(Other)
        if StaffHere[Other] then
            StaffHere[Other] = nil
            RefreshStaffLabel()
        end
    end)

    --// Panic key: hides the menu and every visual, and puts it all back on the second press

    local VisualFlags = {
        "ESP.Settings.Enabled", "Combat.SilentAim.ShowFOV",
        "World.Players.MoneyTags", "World.Contracts.ESP", "Vehicle.CarESP",
        "World.Render.FullBright", "World.Render.NoFog", "World.Render.NoShadows", "World.Render.Time",
        "World.Render.Tint", "World.Render.Exposure", "World.Render.Fov", "World.Render.Stretch"
    }

    local Panicked = false
    local WasOn = {}

    local function Element(Name)
        local Found = OasisUI.Flags and OasisUI.Flags[Name]
        return type(Found) == "table" and Found.Set and Found or nil
    end

    local function Panic()
        Panicked = not Panicked

        if Panicked then
            table.clear(WasOn)

            for _, Name in next, VisualFlags do
                local Toggle = Element(Name)

                if Toggle and Toggle:Get() == true then
                    WasOn[Name] = true
                    Toggle:Set(false)
                end
            end

            pcall(Window.SetVisible, Window, false)
        else
            for Name in next, WasOn do
                local Toggle = Element(Name)

                if Toggle then
                    Toggle:Set(true)
                end
            end

            table.clear(WasOn)
            pcall(Window.SetVisible, Window, true)
        end
    end

    local PanicBind = Safety:Keybind({Title = "Panic key", Default = Enum.KeyCode.End, Mode = "Toggle", Flag = "Safety.PanicKey"})

    -- The bind can come back from a saved config as an EnumItem or as its name
    local function IsPanicKey(KeyCode)
        local Ok, Key = pcall(PanicBind.GetKey, PanicBind)
        Key = Ok and Key or Enum.KeyCode.End

        return KeyCode == Key or KeyCode.Name == tostring(Key):gsub("^Enum%.KeyCode%.", "")
    end

    Safety:Paragraph({Content = "Panic hides the menu and switches off ESP, tags, glows, the FOV circle and render changes. Press it again to bring everything back."})

    local PanicConnection = UserInputService.InputBegan:Connect(function(Input, Typing)
        if not Typing and Input.KeyCode ~= Enum.KeyCode.Unknown and IsPanicKey(Input.KeyCode) then
            Panic()
        end
    end)

    --// Startup self-check: every path a feature depends on, so a game update shows up as one notice

    local function Exists(Root, Path)
        local Node = Root

        for Name in Path:gmatch("[^/]+") do
            Node = Node and Node:FindFirstChild(Name)
        end

        return Node ~= nil
    end

    local Checks = {
        {Remotes, "Misc/Transportation", "bus rides and every teleport"},
        {Remotes, "Misc/ProgramKey", "instant key programming"},
        {Remotes, "Misc/ActivateItem", "auto-sign checks"},
        {Remotes, "Actions/CashCheck", "cashing checks"},
        {Remotes, "ATMAction", "ATM robbery"},
        {Remotes, "MoneyPrinter", "printers"},
        {Remotes, "StartShift", "jobs"},
        {Remotes, "GetBounty", "contracts and bounties"},
        {Remotes, "DrainFuel", "no fuel drain"},
        {Remotes, "ReleasePlayer", "jail release"},
        {Remotes, "Misc/SetFaction", "join any faction"},
        {Remotes, "Misc/MathBookFunc", "auto math book"},
        {Remotes, "Misc/BodyMovementEvent", "anti-aim"},
        {Remotes, "Misc/CameraDetectionEvent", "hide from CCTV"},
        {Remotes, "Misc/HitAimTarget", "aim farm"},
        {Remotes, "MurderRemote", "the kill counter"},
        {Remotes, "DamageVehicle", "car damage"},
        {GameFolder, "Vehicles", "car ESP, theft and car mods"},
        {GameFolder, "Interactables/ATMs", "ATM robbery"},
        {GameFolder, "Interactables/EventNPCs/BankNPC", "cashing checks"},
        {GameFolder, "Locations/PublicTransportation/Destinations", "travel"},
        {GameFolder, "PlacedItems", "printers"},
        {Workspace, "HalloweenCandies", "the candy farm"},
        {Player, "Data/Wallet", "balances and money tags"},
        {Player, "PlayerGui/Framework/FrameworkGUIS/Frames/ForgeryFrame", "auto-sign checks"},
        {Player, "PlayerGui/Framework/FrameworkGUIS/Frames/MathFrame", "auto math book"}
    }

    task.delay(8, function()
        if not Running then
            return
        end

        local Missing = {}

        for _, Check in next, Checks do
            if not Exists(Check[1], Check[2]) then
                table.insert(Missing, ("%s (%s)"):format(Check[2]:match("[^/]+$"), Check[3]))
            end
        end

        if #Missing > 0 then
            Notify("Self-check", "Missing after a game update, these may not work: " .. table.concat(Missing, ", "), "Warning", 15)
            warn("SuperNova self-check, missing: " .. table.concat(Missing, ", "))
        end
    end)

    OasisUI:OnUnload(function()
        Running = false
        IdleConnection:Disconnect()
        JoinConnection:Disconnect()
        LeaveConnection:Disconnect()
        PanicConnection:Disconnect()
    end)
end

-- Loads the saved config only now that every card exists
Window:LoadAutoload()

--// Farms: candy, aim stat, daily check

-- These used to sit behind WaitForChild("HalloweenCandies") with no timeout, so once the event folder was gone
-- the aim farm and the daily check never started. Each one now finds what it needs on its own, and every loop
-- stops on unload instead of running on after the menu is gone.
local FarmsRunning = true
local FarmConnections = {}

OasisUI:OnUnload(function()
    FarmsRunning = false

    for _, Connection in next, FarmConnections do
        Connection:Disconnect()
    end
end)

local function CandyFolder()
    return Workspace:FindFirstChild("HalloweenCandies")
end

-- Candy farm: touch every candy's hitbox. 10 passes a second instead of every frame: a touch takes a round
-- trip to the server before the candy goes, so touching faster only repeated the same touches.
task.spawn(function()
    while FarmsRunning do
        if settings.CandyFarm then
            local Folder = CandyFolder()
            local Character = Player.Character
            local Root = Character and Character:FindFirstChild("HumanoidRootPart")

            if Folder and Root then
                for _, Candy in next, Folder:GetChildren() do
                    local Hitbox = Candy:FindFirstChild("Hitbox")

                    if Hitbox then
                        firetouchinterest(Root, Hitbox, 0)
                        firetouchinterest(Root, Hitbox, 1)
                    end
                end
            end
        end

        task.wait(settings.CandyFarm and 0.1 or 0.5)
    end
end)

-- Aim farm: hit every aim target. The old RenderStepped version started a new round of InvokeServer calls every
-- frame without waiting for the last one, so calls piled up by the hundreds. Now one round is in flight at a time.
task.spawn(function()
    local HitAimTarget = Remotes:WaitForChild("Misc"):WaitForChild("HitAimTarget", 30)

    if not HitAimTarget then
        return warn("SuperNova > Remotes.Misc.HitAimTarget not found, the aim farm will not run.")
    end

    while FarmsRunning do
        local Map = Workspace:FindFirstChild("Map")
        local Targets = Map and Map:FindFirstChild("AimTargets")

        if settings.GunFarm and Targets then
            local Pending = 0

            for _, Target in next, Targets:GetChildren() do
                local HitPart = Target:GetChildren()[2]

                if HitPart then
                    Pending += 1

                    task.spawn(function()
                        pcall(HitAimTarget.InvokeServer, HitAimTarget, HitPart)
                        Pending -= 1
                    end)
                end
            end

            -- Wait for the round to come back, but don't hang on a call the server never answers
            local Started = os.clock()

            repeat
                task.wait()
            until Pending <= 0 or not FarmsRunning or os.clock() - Started > 5
        else
            task.wait(0.5)
        end
    end
end)

-- Map loading for the candy farm. With streaming on, only the area around you exists on your client, so
-- candies far away can't be touched. RequestStreamAroundAsync loads an area without moving the stream's focus
-- off you. (Moving ReplicationFocus to other players, like spectate does, lets your own area unload, and the
-- game pauses your character until it's back: that was the random freezing.)
task.spawn(function()
    local function Spots()
        local List = {}

        local function Add(Object)
            local Ok, Position = pcall(function()
                return Object:IsA("Model") and Object:GetPivot().Position or Object.Position
            end)

            if Ok and typeof(Position) == "Vector3" then
                table.insert(List, {Object.Name, Position})
            end
        end

        local Transit = Locations:FindFirstChild("PublicTransportation")
        Transit = Transit and Transit:FindFirstChild("Destinations")

        for _, Folder in next, {Transit, LocationsTBL["Marked"]} do
            for _, Child in next, Folder and Folder:GetChildren() or {} do
                Add(Child)
            end
        end

        return List
    end

    local function Loading()
        return FarmsRunning and settings.CandyFarm and settings.LoadMap
    end

    local function CandiesLeft()
        local Folder = CandyFolder()
        return Folder ~= nil and #Folder:GetChildren() > 0
    end

    -- Stay for the set time, and a little longer while candies that loaded in are still being picked up
    local function StayInArea()
        local Started = os.clock()

        while Loading() and os.clock() - Started < settings.AreaTime do
            task.wait(0.25)
        end

        local Extra = os.clock()

        while FarmsRunning and settings.CandyFarm and CandiesLeft() and os.clock() - Extra < settings.AreaTime do
            task.wait(0.25)
        end
    end

    while FarmsRunning do
        if not Loading() then
            CandyArea:SetValue("-")
            task.wait(1)
        elseif not Workspace.StreamingEnabled then
            CandyArea:SetValue("whole map is already loaded")
            task.wait(2)
        else
            -- Around other players first (they're spread over the map), then fixed spots
            for _, Other in next, Players:GetPlayers() do
                if not Loading() then
                    break
                end

                local Root = Other ~= Player and Other.Character and Other.Character:FindFirstChild("HumanoidRootPart")

                if Root then
                    CandyArea:SetValue(Other.Name)
                    pcall(Player.RequestStreamAroundAsync, Player, Root.Position, 2)
                    StayInArea()
                end
            end

            -- Fixed spots across the map
            for _, Spot in next, Spots() do
                if not Loading() then
                    break
                end

                CandyArea:SetValue(Spot[1])
                pcall(Player.RequestStreamAroundAsync, Player, Spot[2], 2)
                StayInArea()
            end

            -- No players and no spots: don't spin
            task.wait()
        end
    end
end)

-- Collected count: the server keeps your candy total in Data.Candies, so count how far it has risen
task.spawn(function()
    local Data = Player:WaitForChild("Data", 30)
    local Candies = Data and Data:WaitForChild("Candies", 30)

    if not Candies then
        return CandyTotal:SetValue("not found")
    end

    local Start = Candies.Value

    local function Commas(Number)
        return (tostring(math.floor(Number)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
    end

    local function Update()
        CandyLoaded:SetValue(Commas(math.max(Candies.Value - Start, 0)))
        CandyTotal:SetValue(Commas(Candies.Value))
    end

    Update()
    table.insert(FarmConnections, Candies.Changed:Connect(Update))
end)

-- Daily check
task.spawn(function()
    local Misc = Remotes:WaitForChild("Misc")
    local CheckNotif = Misc:WaitForChild("ShowDailyCheckUI")

    if not FarmsRunning then
        return
    end

    table.insert(FarmConnections, CheckNotif.OnClientEvent:Connect(function()
        if not settings.Check then
            return
        end

        local Claim = Misc:FindFirstChild("ClaimDailyCheck")

        if Claim then
            Claim:FireServer()
        end
    end))
end)

-- SuperNova ESP only: the ESP, crosshair and their settings from the full script, nothing else

-- Running the script again: unload the copy that's already running first, before its replacement loads the ESP
if getgenv().SuperNovaUnload then
    pcall(getgenv().SuperNovaUnload)
    getgenv().SuperNovaUnload = nil
end

local OasisUI = loadstring(game:HttpGet("https://github.com/Mold53/OasisUI/releases/download/v1.6.0/OasisUI.lua"))()
local ESPLibrary = loadstring(game:HttpGet("https://raw.githubusercontent.com/idonotlikeppl/supernovav2/refs/heads/main/util/exunys-fork-isaeva.lua"))()
local Players = game:GetService("Players")
local Player = Players.LocalPlayer
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

-- GetProductInfo is a web call: if it fails, the menu still opens instead of the whole script erroring
local NameOk, GameName = pcall(function()
    return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name
end)
GameName = NameOk and GameName or "ATL Trenches"

local Window = OasisUI:CreateWindow({
    Title = GameName,
    Subtitle = "✨SuperNova💫 ESP",
    Folder = "shenyu_u_esp", -- its own config folder, so it never overwrites the full script's saves
    DefaultConfig = "default",
    AutoSave = true,
    AutoLoad = false -- loaded by hand once the whole menu is built
})

getgenv().SuperNovaUnload = function()
	OasisUI:Unload()
end

OasisUI:OnUnload(function()
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
end

local Visual = Window:Tab({Title = "Visual", Icon = "eye"})

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

-- Loads the saved config only now that every card exists
Window:LoadAutoload()

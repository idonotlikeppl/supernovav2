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

-- Main + outline colour block shared by most visuals
local function ColorBlock(Module, Name, HasMain, HasOutline)
	local Group = Module:Group({Title = "Colours", Icon = "palette", Opened = true})
	local Base = "Properties." .. Name .. "."

	if HasMain ~= false then
		Color(Group, "Colour", Base .. "Color")
		Checkbox(Group, "Rainbow", Base .. "RainbowColor")
	end

	if HasOutline ~= false then
		local Outline = Checkbox(Group, "Outline", Base .. "Outline")
		Color(Group, "Outline colour", Base .. "OutlineColor"):DependsOn(Outline, nil, "Hide")
		Checkbox(Group, "Rainbow outline", Base .. "RainbowOutlineColor"):DependsOn(Outline, nil, "Hide")
	end

	return Group
end


-- inf staminma by deleting stamina value in character
local function Char()
    return Player.Character
end
local function teleport(time,cframe)
    local count = 0
    if (Char() and Char():FindFirstChild("HumanoidRootPart")) then
        local Time = time
        local CFrameEnd = cframe
        local tween =  game:GetService("TweenService"):Create(Char().HumanoidRootPart, TweenInfo.new(Time, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 5), {CFrame = CFrameEnd})
        tween:Play()
        tween.Completed:Wait()
        repeat 
            task.wait()
            Char().HumanoidRootPart.CFrame = cframe
            count = count+1
        until count == 100
    end
end

local settings = {
    CandyFarm = false,
    GunFarm = false,
    Check = false,
}

local Window = OasisUI:CreateWindow({
    Title = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name,
    Subtitle = "✨SuperNova💫 vInfDev",
    Folder = "shenyu_u",
    DefaultConfig = "default",
    AutoSave = true,
    AutoLoad = false -- loaded by hand once the whole menu is built
})

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

local World = Window:Tab({ 
    Title = "World", 
    Icon = "globe" 
})
local Visual = Window:Tab({ 
    Title = "Visual", 
    Icon = "eye" 
})
local Automation = Window:Tab({ 
    Title = "Automation", 
    Icon = "cog" 
})

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
	Choice(TeamCheck, "Team decided by", "DeveloperSettings.TeamCheckOption", {{"TeamColor", "TeamColor"}, {"Team", "Team"}}, nil, "Which player property counts as the team. Also used by Team colours.")

	Card("Alive check", "Settings.AliveCheck", "heart", "Hide dead players and NPCs.", "Left")

	local TeamColours = Card("Team colours", "Settings.EnableTeamColors", "users", "Draw teammates in their own colour.", "Right")
	Color(TeamColours, "Team colour", "Settings.TeamColor")

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
	Color(Fill, "Fill colour", "Properties.Box.FillColor"):DependsOn(Filled, nil, "Hide")
	Checkbox(Fill, "Rainbow fill", "Properties.Box.FillRainbowColor"):DependsOn(Filled, nil, "Hide")
	Slider(Fill, "Fill opacity", "Properties.Box.FillTransparency", 0, 1, 0.05):DependsOn(Filled, nil, "Hide")
	ColorBlock(Box, "Box")

	--// Health bar

	local Health = VisualCard(Visuals, "Health bar", "HealthBar", "heart", "Coloured by health, from red to green.", "Right")
	Choice(Health, "Side", "Properties.HealthBar.Position", {{"Top", 1}, {"Bottom", 2}, {"Left", 3}, {"Right", 4}})
	Slider(Health, "Offset", "Properties.HealthBar.Offset", 4, 12, 1, " px")
	Slider(Health, "Thickness", "Properties.HealthBar.Thickness", 1, 6, 1, " px")
	Slider(Health, "Opacity", "Properties.HealthBar.Transparency", 0, 1, 0.05)
	Slider(Health, "Blue tint", "Properties.HealthBar.Blue", 0, 255, 1, nil, "Blue channel mixed into the health colour.")
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
	Color(HighlightFill, "Fill colour", "Properties.Highlight.FillColor")
	Checkbox(HighlightFill, "Rainbow fill", "Properties.Highlight.RainbowColor")
	Slider(HighlightFill, "Fill transparency", "Properties.Highlight.FillTransparency", 0, 1, 0.05, nil, "0 is solid, 1 is invisible.")
	local HealthColor = Checkbox(HighlightFill, "Colour by health", "Properties.Highlight.HealthColor", "Overrides the fill colour and rainbow.")
	Slider(HighlightFill, "Health blue tint", "Properties.Highlight.HealthColorBlue", 0, 255, 1):DependsOn(HealthColor, nil, "Hide")

	local HighlightOutline = Highlight:Group({Title = "Outline", Icon = "square"})
	Color(HighlightOutline, "Outline colour", "Properties.Highlight.OutlineColor")
	Checkbox(HighlightOutline, "Rainbow outline", "Properties.Highlight.RainbowOutlineColor")
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

	local DotColours = Dot:Group({Title = "Colours", Icon = "palette", Opened = true})
	Color(DotColours, "Colour", DotBase .. "Color")
	Checkbox(DotColours, "Rainbow", DotBase .. "RainbowColor")
	local DotOutline = Checkbox(DotColours, "Outline", DotBase .. "Outline")
	Color(DotColours, "Outline colour", DotBase .. "OutlineColor"):DependsOn(DotOutline, nil, "Hide")
	Checkbox(DotColours, "Rainbow outline", DotBase .. "RainbowOutlineColor"):DependsOn(DotOutline, nil, "Hide")
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
	Slider(Tuning, "Rainbow speed", "DeveloperSettings.RainbowSpeed", 0.1, 10, 0.1, nil, "Bigger is slower.")
	Slider(Tuning, "Box width", "DeveloperSettings.WidthBoundary", 0.5, 4, 0.05, nil, "Smaller is wider.")
	Checkbox(Tuning, "Unwrap on character loss", "DeveloperSettings.UnwrapOnCharacterAbsence", "Drop a player's visuals when their character is removed.")
	Checkbox(Tuning, "Hide ESP warnings", "DeveloperSettings.DisableWarnings")
end

--// World

local TeleportTab = World:SubTab({
    Title = "Teleports",
    Icon = "map"
})

local Autofarm = Automation:SubTab({
    Title = "Autofarm",
    Icon = "zap"
})

local Automisc = Automation:SubTab({
    Title = "Misc",
    Icon = "settings-2"
})

local Teleports = TeleportTab:Section({ Title = "Main Teleports", Icon = "wrench", Side = "Left" })

local MarkedPOS = {}

for i,v in pairs(LocationsTBL["Marked"]:GetChildren()) do
    table.insert(MarkedPOS,v.Name)
end

local MainTpTarget = Teleports:Dropdown({ Title = "Location", Values = MarkedPOS, Search = true, Flag = "MainTp", Callback = function() end })
Teleports:Buttons({
 { Title = "Teleport", Icon = "refresh-cw", Callback = function()
    local TarName = MainTpTarget:Get()
    local TarPath = LocationsTBL["Marked"][TarName]
    teleport(10,TarPath.CFrame)
end },
})

Autofarm:Module({
    Title = "Candy Collection",
    Description = "Automatically collects candies around the map without teleportation.",
    Icon = "gift",                      -- optional, shown before the title
    Flag = "CandyFarm",                      -- saves enabled state + key
    Default = false,
    Keybind = false,  -- false hides the pill
    Risky = false,                        -- red title
    Side = "Left",                        -- first placement; the user's layout wins afterwards
    Color = nil,                          -- { ColorPicker options }: a colour swatch next to the switch, own Flag
    Notify = false,                       -- default of the card's bell: a notification on every on / off
    Opened = nil,                         -- force the settings open/closed initially
    Callback = function(enabled)
        settings.CandyFarm = enabled
    end,
})

Autofarm:Module({
    Title = "Improve Aim State",
    Description = "Automatically max aim stat.",
    Icon = "crosshair",                      -- optional, shown before the title
    Flag = "GunFarm",                      -- saves enabled state + key
    Default = false,
    Keybind = false,  -- false hides the pill
    Risky = false,                        -- red title
    Side = "Left",                        -- first placement; the user's layout wins afterwards
    Color = nil,                          -- { ColorPicker options }: a colour swatch next to the switch, own Flag
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
    Color = nil,                          -- { ColorPicker options }: a colour swatch next to the switch, own Flag
    Notify = false,                       -- default of the card's bell: a notification on every on / off
    Opened = false,                         -- force the settings open/closed initially
    Callback = function(enabled)
        settings.Check = enabled
    end,
})

--// Player: Guns

local PlayerTab = Window:Tab({
    Title = "Player",
    Icon = "user"
})

local GunsTab = PlayerTab:SubTab({
    Title = "Guns",
    Icon = "crosshair"
})

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

        {Group = "Effects", Key = "MotionBlur", Title = "No motion blur", Value = false, Tip = "Sets MotionBlur to false."}
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

local CharacterTab = PlayerTab:SubTab({
    Title = "Character",
    Icon = "user-round"
})

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

    --// Stats (Stamina, Hunger, Thirst)

    local StatEnabled = {Stamina = false, Hunger = false, Thirst = false}
    local Removed = {} -- Name -> {Value = the NumberValue, Folder = the Values folder it came from}
    local FirstSeen = {} -- NumberValue -> os.clock() when it was first found, for the delay
    setmetatable(FirstSeen, {__mode = "k"})
    local RemoveDelay = 10 -- seconds a value is left in place after it appears, so the game can finish setting up

    local function ValuesFolder()
        local GameCharacter = GameFolder:FindFirstChild("Players") and GameFolder.Players:FindFirstChild(Player.Name)

        for _, Character in next, {Player.Character, GameCharacter} do
            local Folder = Character and Character:FindFirstChild("Values")

            if Folder then
                return Folder
            end
        end
    end

    -- Unparented rather than destroyed, so switching off can put the very same instance back
    local function RemoveStat(Name)
        local Folder = ValuesFolder()
        local Stat = Folder and Folder:FindFirstChild(Name)

        if Stat and Stat:IsA("NumberValue") then
            -- Each value waits out the delay from the moment it is first seen (also after a respawn)
            FirstSeen[Stat] = FirstSeen[Stat] or os.clock()

            if os.clock() - FirstSeen[Stat] < RemoveDelay then
                return
            end

            FirstSeen[Stat] = nil
            Removed[Name] = {Value = Stat, Folder = Folder}
            Stat.Parent = nil
        end
    end

    local function ReinstateStat(Name)
        local Entry = Removed[Name]
        Removed[Name] = nil

        -- After a respawn the old folder is gone and the new character already has its own value
        if Entry and Entry.Folder.Parent and not Entry.Folder:FindFirstChild(Name) then
            Entry.Value.Parent = Entry.Folder
        end
    end

    -- Checked every frame: a respawn or the game's own scripts can bring a value back
    local StatConnection = game:GetService("RunService").Heartbeat:Connect(function()
        for Name, Enabled in next, StatEnabled do
            if Enabled then
                RemoveStat(Name)
            end
        end
    end)

    local Stats = CharacterTab:Section({Title = "Stats", Icon = "heart", Side = "Right"})

    for _, Name in next, {"Stamina", "Hunger", "Thirst"} do
        Stats:Toggle({
            Title = "No " .. Name:lower(),
            Tooltip = "Removes Values." .. Name .. " from your character 10 seconds after it appears. Switching off puts it back.",
            Default = false,
            Flag = "Character.No" .. Name,
            Callback = function(Enabled)
                StatEnabled[Name] = Enabled

                if Enabled then
                    RemoveStat(Name)
                else
                    table.clear(FirstSeen) -- the delay starts over the next time it is switched on
                    ReinstateStat(Name)
                end
            end
        })
    end

    OasisUI:OnUnload(function()
        StatConnection:Disconnect()

        for Name in next, StatEnabled do
            StatEnabled[Name] = false
            ReinstateStat(Name)
        end
    end)
end

-- Loads the saved config only now that every card exists; the farm setup below can yield forever
Window:LoadAutoload()

local CandyFolder = Workspace:WaitForChild("HalloweenCandies")
local TargetsFolder = Workspace:FindFirstChild("Map"):FindFirstChild("AimTargets")
local AimImprovEvent = Remotes:WaitForChild("Misc"):WaitForChild("HitAimTarget")


game:GetService("RunService").RenderStepped:Connect(function()

    if settings.CandyFarm == true and CandyFolder then
        local Candies = CandyFolder:GetChildren()
        if #Candies >= 1 and (Char() and Char():FindFirstChild("HumanoidRootPart")) then
            for i,v in pairs(Candies) do
                firetouchinterest(Char().HumanoidRootPart, v.Hitbox, 0)
	            firetouchinterest(Char().HumanoidRootPart, v.Hitbox, 1)
            end
        end
    end

    if settings.GunFarm == true and TargetsFolder then
        pcall(function() for i,v in pairs(TargetsFolder:GetChildren()) do
                local HitPart = v:GetChildren()[2]
                AimImprovEvent:InvokeServer(HitPart)
            end
        end)
    end

end)

local CheckNotif = Remotes:WaitForChild("Misc"):WaitForChild("ShowDailyCheckUI")

CheckNotif.OnClientEvent:Connect(function()
    if not settings.Check then
        return
    end

    Remotes:WaitForChild("Misc"):WaitForChild("ClaimDailyCheck"):FireServer()
end)

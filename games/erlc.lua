--[[

	SuperNova: Emergency Response: Liberty County

	Nothing in this script prints. ER:LC uploads your console to its servers (PerfTelemetryClient streams every
	LogService message, and QA can pull the last 2,000 lines on request), so output goes through menu notifications
	only, and the log scrubber below removes executor lines from both uploads before they leave.

]]

--// Re-running: unload the copy that's already running first

if getgenv().SuperNovaERLCUnload then
    pcall(getgenv().SuperNovaERLCUnload)
    getgenv().SuperNovaERLCUnload = nil
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LogService = game:GetService("LogService")
local RunService = game:GetService("RunService")
local Player = Players.LocalPlayer

--// Log scrubber: installed before anything else loads, so not even the menu's own lines get through
--
-- ER:LC talks to its server through the Red library: every event is queued and sent once a frame as
-- ReliableRedEvent:FireServer(Batch, Calls), where Batch[Id] is a list of packed argument tables and each event's Id
-- is an attribute on ReliableRedEvent named after the event. The log uploads are:
--   PerfSubmitLogs          {{message, messageType, timestamp}, ...}  streamed from LogService.MessageOut
--   QASubmitClientLogs      (requestId, {{message, messageType, timestamp}, ...})  from LogService:GetLogHistory()
--   PerfSubmitSnapshot      (requestId, "request", chunks, bytes, info)  then PerfSubmitSnapshotChunk buffers
-- Log entries that look like they came from an executor are removed. A microprofiler snapshot can't be edited, so
-- it's answered the way the game answers a failed capture: "unavailable", no chunks.

local State = getgenv().SuperNovaERLC or {}
getgenv().SuperNovaERLC = State

State.Options = {
    NoEnvironmentalDamage = false,
    NoFishFail = false
}

-- Each run's Handle closes over this run's tables; keep the old ones' names out of the way
State.Handle = nil

State.Stats = {Scrubbed = 0, Snapshots = 0}

local SCRUB_PATTERNS = {
    "supernova", "oasis", "exunys", "isaeva", "[string", "loadstring", "getgenv", "hookmetamethod",
    "hookfunction", "newcclosure", "rconsole", "executor", "httpget", "gethui", "drawing"
}

local function Suspicious(Message)
    if type(Message) ~= "string" then
        return false
    end

    local Lower = Message:lower()

    for _, Pattern in next, SCRUB_PATTERNS do
        if Lower:find(Pattern, 1, true) then
            return true
        end
    end

    return false
end

-- Removes suspicious {message = ...} entries from a log list, in place
local function ScrubList(List)
    if type(List) ~= "table" then
        return
    end

    local Kept, Removed = {}, 0

    for _, Entry in ipairs(List) do
        if type(Entry) == "table" and Suspicious(Entry.message) then
            Removed += 1
        else
            table.insert(Kept, Entry)
        end
    end

    if Removed > 0 then
        table.clear(List)
        table.move(Kept, 1, #Kept, 1, List)
        State.Stats.Scrubbed += Removed
    end
end

local ReliableRedEvent = ReplicatedStorage:WaitForChild("ReliableRedEvent", 30)

local function RedId(Name)
    return ReliableRedEvent and ReliableRedEvent:GetAttribute(Name)
end

local function ScrubBatch(Batch)
    if type(Batch) ~= "table" then
        return
    end

    -- PerfSubmitLogs: each queued call is ({entries})
    for _, Packed in next, Batch[RedId("PerfSubmitLogs")] or {} do
        ScrubList(Packed[1])
    end

    -- QASubmitClientLogs: each queued call is (requestId, {entries})
    for _, Packed in next, Batch[RedId("QASubmitClientLogs")] or {} do
        ScrubList(Packed[2])
    end

    -- PerfSubmitSnapshot "request" becomes the game's own "unavailable" reply, and its chunks are dropped
    local SnapshotId = RedId("PerfSubmitSnapshot")

    for _, Packed in next, SnapshotId and Batch[SnapshotId] or {} do
        if Packed[2] == "request" then
            local Info = type(Packed[5]) == "table" and Packed[5] or {}
            Packed[2], Packed[3], Packed[4], Packed[5] = "unavailable", 0, 0, {platform = Info.platform}
            State.Stats.Snapshots += 1
        end
    end

    local ChunkId = RedId("PerfSubmitSnapshotChunk")

    if ChunkId then
        Batch[ChunkId] = nil
    end
end

local FE = ReplicatedStorage:WaitForChild("FE", 30)
local Actions = FE and FE:FindFirstChild("Actions")

-- One hook for the session. It only asks State.Handle what to do with each call, and every run of the script
-- replaces State.Handle, so re-running with new features never needs a new hook. Handle answers:
--   nil                pass the call through
--   "drop"             swallow it
--   "history"          call through, then scrub the returned log history
--   {n = ..., ...}     call through with these arguments instead
--   {Result = value}   don't call through; return this value
State.Options.LaserImmune = false
State.Options.AlwaysSucceed = false
State.Options.MinSolveTime = 4

local MINIGAMES = {"Crowbar", "GlassCutting", "Lockpick", "SafeHack", "FirewallHack", "NumbersHack", "ConnectWires"}
local MinigameRemotes = {} -- remote -> minigame name
local ChallengeStarted = {} -- remote -> {challenge id -> os.clock() it arrived}

-- The robbery minigames go through the game's Network module: the server sends a challenge on a remote, the
-- client plays it and reports Fire(name, challengeId, success, ...). The module's remotes are only reachable
-- through it, so ask it for them.
task.spawn(function()
    local Ok, Network = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Network"))("amor")
    end)

    if not Ok or type(Network) ~= "table" then
        return
    end

    for _, Name in next, MINIGAMES do
        local Got, Remote = pcall(Network.getRemote, Name)

        if Got and typeof(Remote) == "Instance" and Remote:IsA("RemoteEvent") then
            MinigameRemotes[Remote] = Name
            ChallengeStarted[Remote] = {}

            Remote.OnClientEvent:Connect(function(Id)
                ChallengeStarted[Remote][Id] = os.clock()
            end)
        end
    end
end)

function State.Handle(self, Method, ...)
    local Options = State.Options

    if Method == "GetLogHistory" then
        return self == LogService and "history" or nil
    end

    -- Silent aim: the gun asks the camera for the ray through the screen center, then shoots from the barrel to
    -- wherever that ray lands. Bending that one ray makes the barrel cast, start, finish and dir all agree.
    -- The gun always asks for the exact center of the viewport, and only while a gun is out; anything else that
    -- asks the camera for a ray (menus, interaction prompts) is left alone.
    if Method == "ViewportPointToRay" and State.AimRay and self == workspace.CurrentCamera then
        local X, Y = ...
        local Center = self.ViewportSize / 2

        if type(X) == "number" and type(Y) == "number" and math.abs(X - Center.X) < 2 and math.abs(Y - Center.Y) < 2 then
            local Ray = State.AimRay(self)

            if Ray then
                return {Result = Ray}
            end
        end

        return nil
    end

    if Method ~= "FireServer" then
        return nil
    end

    if self == ReliableRedEvent then
        local Batch = (...)
        pcall(ScrubBatch, Batch)

        -- The bank's lasers hurt you only when your client reports a hit
        local LaserId = Options.LaserImmune and RedId("LaserDamage")

        if LaserId and type(Batch) == "table" then
            Batch[LaserId] = nil
        end

        return nil
    end

    if Options.NoEnvironmentalDamage and Actions and (self == Actions:FindFirstChild("Environmental") or self == Actions:FindFirstChild("Burn")) then
        -- DamageHandler reports fall, drowning and fire damage itself
        return "drop"
    end

    if Options.NoFishFail and FE and self == FE:FindFirstChild("ManageFishing") and (...) == "ReelFailed" then
        -- The server times the catch; the client can only report a failure
        return "drop"
    end

    if Options.AlwaysSucceed and MinigameRemotes[self] then
        local Args = table.pack(...)

        if Args[2] == true then
            return nil
        end

        -- Report success, but never sooner after the challenge arrived than a person could have solved it
        Args[2] = true

        local Started = ChallengeStarted[self][Args[1]]
        local Wait = Started and (Options.MinSolveTime - (os.clock() - Started)) or 0

        if Wait > 0 then
            local Remote = self

            task.delay(Wait, function()
                Remote:FireServer(table.unpack(Args, 1, Args.n))
            end)

            return "drop"
        end

        return Args
    end

    return nil
end

-- Version 2 hooks go through State.Handle; an older hook from an earlier copy stays harmless underneath
if State.HookVersion ~= 2 and hookmetamethod and getnamecallmethod then
    State.Hooked = true
    State.HookVersion = 2

    local Old
    Old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        if checkcaller() then
            return Old(self, ...)
        end

        local Handle = getgenv().SuperNovaERLC.Handle
        local Ok, Action = false, nil

        if Handle then
            Ok, Action = pcall(Handle, self, getnamecallmethod(), ...)
        end

        if not Ok or Action == nil then
            return Old(self, ...)
        elseif Action == "drop" then
            return nil
        elseif Action == "history" then
            local History = Old(self, ...)
            pcall(ScrubList, History)
            return History
        elseif type(Action) == "table" and Action.Result ~= nil then
            return Action.Result
        end

        return Old(self, table.unpack(Action, 1, Action.n))
    end))
end

--// Menu

local OasisUI = loadstring(game:HttpGet("https://github.com/Mold53/OasisUI/releases/download/v1.6.0/OasisUI.lua"))()

local Window = OasisUI:CreateWindow({
    Title = "Emergency Response: Liberty County",
    Subtitle = "✨SuperNova💫",
    Folder = "shenyu_u_erlc",
    DefaultConfig = "default",
    AutoSave = true,
    AutoLoad = false -- loaded by hand once the whole menu is built
})

getgenv().SuperNovaERLCUnload = function()
    OasisUI:Unload()
end

OasisUI:OnUnload(function()
    -- The hook stays installed for the session, so leave it harmless
    State.Options.NoEnvironmentalDamage = false
    State.Options.NoFishFail = false
    State.Options.LaserImmune = false
    State.Options.AlwaysSucceed = false
end)

local function Notify(Title, Content, Kind, Duration)
    OasisUI:Notify({Title = Title, Content = Content, Type = Kind or "Info", Duration = Duration or 4})
end

local Overview = Window:Tab({Title = "Overview", Icon = "house"})
Window:TabSection("Player")
local PlayerTab = Window:Tab({Title = "Player", Icon = "user"})
local Crime = Window:Tab({Title = "Crime", Icon = "key-round"})
local Combat = Window:Tab({Title = "Combat", Icon = "crosshair"})
local Visual = Window:Tab({Title = "Visual", Icon = "eye"})
Window:TabSection("World")
local World = Window:Tab({Title = "World", Icon = "globe"})
local RenderTab = World

--//==================== Overview > Log protection ====================

do
    local Running = true
    local Protection = Overview:Section({Title = "Log protection", Icon = "shield-check", Side = "Right"})
    Protection:Paragraph({Content = "ER:LC uploads your console to its servers. Executor lines are removed from those uploads, and profiler snapshots are answered as unavailable."})

    local HookLabel = Protection:Label({Text = "Scrubber", Value = State.Hooked and "on" or "off", ValueColor = State.Hooked and "Success" or "Error"})
    local ScrubLabel = Protection:Label({Text = "Lines removed", Value = "0"})
    local SnapLabel = Protection:Label({Text = "Snapshots refused", Value = "0"})

    if not State.Hooked then
        Notify("Log protection", "This executor can't hook calls, so your console is NOT protected. Don't use features here.", "Error", 15)
    elseif not ReliableRedEvent then
        Notify("Log protection", "ReliableRedEvent not found: the game changed. Logs are NOT being scrubbed.", "Error", 15)
        HookLabel:SetValue("game changed")
        HookLabel:SetValueColor("Error")
    end

    task.spawn(function()
        while Running do
            ScrubLabel:SetValue(tostring(State.Stats.Scrubbed))
            SnapLabel:SetValue(tostring(State.Stats.Snapshots))
            task.wait(1)
        end
    end)

    OasisUI:OnUnload(function() Running = false end)
end

--//==================== Player > Survival ====================

do
    local Survival = PlayerTab:Section({Title = "Survival", Icon = "shield", Side = "Left"})

    Survival:Toggle({
        Title = "No fall, drowning or fire damage",
        Tooltip = "Your client reports this damage itself (FE.Actions.Environmental and Burn). This stops reporting it.",
        Default = false,
        Flag = "Player.NoEnvironmentalDamage",
        Callback = function(Enabled) State.Options.NoEnvironmentalDamage = Enabled end
    })

    local Fishing = PlayerTab:Section({Title = "Fishing", Icon = "fish", Side = "Right"})

    Fishing:Toggle({
        Title = "Never lose a fish",
        Tooltip = "The server decides when you catch the fish; your client can only tell it you failed. This never tells it.",
        Default = false,
        Flag = "Player.NoFishFail",
        Callback = function(Enabled) State.Options.NoFishFail = Enabled end
    })

    Fishing:Paragraph({Content = "Cast as normal and ignore the reeling bar. The catch arrives when the server's timer runs out."})
end

--//==================== Crime ====================

do
    local Minigames = Crime:Module({
        Title = "Always succeed",
        Description = "Lockpick, crowbar, glass cutting, safe, ATM firewall, numbers and wires. Your client grades these itself, so a fail is sent as a success.",
        Icon = "unlock",
        Side = "Left",
        Default = false,
        Flag = "Crime.AlwaysSucceed",
        Keybind = false,
        Opened = true,
        Callback = function(Enabled) State.Options.AlwaysSucceed = Enabled end
    })

    Minigames:Slider({
        Title = "Minimum solve time",
        Min = 2,
        Max = 15,
        Step = 0.5,
        Default = 4,
        Suffix = " s",
        Flag = "Crime.MinSolveTime",
        Tooltip = "A success is never sent sooner than this after the challenge starts, so it looks solved by hand.",
        Callback = function(Value) State.Options.MinSolveTime = Value end
    })

    Minigames:Paragraph({Content = "Fail on purpose to finish fast: any result counts as a success, sent no sooner than the minimum time."})

    local Bank = Crime:Section({Title = "Bank robbery", Icon = "landmark", Side = "Right"})

    Bank:Toggle({
        Title = "Laser immunity",
        Tooltip = "The vault lasers only hurt you when your client reports the hit. This stops reporting it.",
        Default = false,
        Flag = "Crime.LaserImmune",
        Callback = function(Enabled) State.Options.LaserImmune = Enabled end
    })
end

--//==================== Combat ====================

do
    local UserInputService = game:GetService("UserInputService")
    local GuiService = game:GetService("GuiService")
    local Running = true

    local Aim = {Silent = false, Fov = 140, ShowFov = true, Part = "Head", VisibleOnly = true, SkipTeam = true, SkipDowned = true, MaxDistance = 600, Recoil = 100}

    local Silent = Combat:Module({
        Title = "Silent aim",
        Description = "Shots go to the player nearest your mouse, inside the circle. Works in first and third person.",
        Icon = "crosshair",
        Side = "Left",
        Risky = true,
        Default = false,
        Flag = "Combat.SilentAim",
        Keybind = {Key = nil, Mode = "Toggle"},
        Opened = true,
        Callback = function(Enabled) Aim.Silent = Enabled end
    })

    Silent:Slider({Title = "FOV radius", Min = 20, Max = 500, Step = 5, Default = 140, Suffix = " px", Flag = "Combat.SilentAim.Fov", Callback = function(Value) Aim.Fov = Value end})
    Silent:Segmented({Title = "Aim at", Values = {"Head", "Torso"}, Default = "Head", Flag = "Combat.SilentAim.Part", Callback = function(Value) Aim.Part = Value end})
    Silent:Slider({Title = "Max distance", Min = 50, Max = 1500, Step = 25, Default = 600, Suffix = " st", Flag = "Combat.SilentAim.Distance", Callback = function(Value) Aim.MaxDistance = Value end})
    Silent:Checkbox({Title = "Visible only", Tooltip = "Skips players behind walls. Shots into cover would hit the cover anyway.", Default = true, Flag = "Combat.SilentAim.Visible", Callback = function(Value) Aim.VisibleOnly = Value end})
    Silent:Checkbox({Title = "Skip my team", Default = true, Flag = "Combat.SilentAim.SkipTeam", Callback = function(Value) Aim.SkipTeam = Value end})
    Silent:Checkbox({Title = "Skip downed players", Default = true, Flag = "Combat.SilentAim.SkipDowned", Callback = function(Value) Aim.SkipDowned = Value end})
    Silent:Checkbox({Title = "Show FOV circle", Default = true, Flag = "Combat.SilentAim.ShowFov", Callback = function(Value) Aim.ShowFov = Value end})

    -- What the last shot did, since nothing here may print: "no gun", "no target", or who it went to
    local AimStatus = Silent:Label({Text = "Last shot", Value = "none yet"})
    local LastStatus

    local function Report(Text)
        if Text ~= LastStatus then
            LastStatus = Text
            pcall(AimStatus.SetValue, AimStatus, Text)
        end
    end

    local RecoilCard = Combat:Section({Title = "Recoil", Icon = "move-vertical", Side = "Right"})
    RecoilCard:Slider({Title = "Recoil", Min = 0, Max = 100, Step = 5, Default = 100, Suffix = "%", Flag = "Combat.Recoil", Tooltip = "100% is the game's normal kick. Recoil only moves your camera, so lowering it is invisible to the server.", Callback = function(Value) Aim.Recoil = Value end})

    --// Target choice

    local function Ignore()
        local List = {workspace.CurrentCamera}

        if Player.Character then
            table.insert(List, Player.Character)
        end

        return List
    end

    local function AimPart(Character)
        if Aim.Part == "Head" then
            return Character:FindFirstChild("Head")
        end

        return Character:FindFirstChild("UpperTorso") or Character:FindFirstChild("Torso") or Character:FindFirstChild("HumanoidRootPart")
    end

    local function Visible(Origin, Part, Character)
        local Params = RaycastParams.new()
        Params.FilterType = Enum.RaycastFilterType.Exclude
        Params.FilterDescendantsInstances = Ignore()

        local Result = workspace:Raycast(Origin, Part.Position - Origin, Params)
        return Result == nil or Result.Instance:IsDescendantOf(Character)
    end

    -- The player whose aim part sits closest to the screen point, inside the circle
    local function Target(Camera, X, Y)
        local Best, BestGap = nil, Aim.Fov
        local Origin = Camera.CFrame.Position

        for _, Other in next, Players:GetPlayers() do
            local Character = Other ~= Player and Other.Character
            local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
            local Part = Character and AimPart(Character)

            local Allowed = Part and Humanoid and Humanoid.Health > 0
                and not (Aim.SkipTeam and Other.Team ~= nil and Other.Team == Player.Team)
                and not (Aim.SkipDowned and Character:GetAttribute("Downed"))
                and (Part.Position - Origin).Magnitude <= Aim.MaxDistance

            if Allowed then
                local Screen, OnScreen = Camera:WorldToViewportPoint(Part.Position)
                local Gap = (Vector2.new(Screen.X, Screen.Y) - Vector2.new(X, Y)).Magnitude

                if OnScreen and Gap <= BestGap and (not Aim.VisibleOnly or Visible(Origin, Part, Character)) then
                    Best, BestGap = Part, Gap
                end
            end
        end

        return Best
    end

    -- Guns carry a WeaponRoot (the barrel exit hangs off it)
    local function HoldingGun()
        local Character = Player.Character
        local Tool = Character and Character:FindFirstChildOfClass("Tool")
        return Tool ~= nil and Tool:FindFirstChild("WeaponRoot") ~= nil
    end

    -- Where the mouse is, in the same viewport space WorldToViewportPoint uses (first person locks it to the center)
    local function MouseViewport()
        local Mouse = UserInputService:GetMouseLocation()
        local Inset = GuiService:GetGuiInset()
        return Mouse.X - Inset.X, Mouse.Y - Inset.Y
    end

    -- The center ray's own origin, pointed at the target chosen around the mouse
    State.AimRay = function(Camera)
        if not Aim.Silent then
            return nil
        end

        if not HoldingGun() then
            Report("no gun out")
            return nil
        end

        local MouseX, MouseY = MouseViewport()
        local Part = Target(Camera, MouseX, MouseY)

        if not Part then
            Report("no target in circle")
            return nil
        end

        Report("bent to " .. Part.Parent.Name)

        -- Indexed then called, not Camera:ViewportPointToRay(): a method call would come back through our own hook
        local ViewportPointToRay = Camera.ViewportPointToRay
        local Center = Camera.ViewportSize / 2
        local Original = ViewportPointToRay(Camera, Center.X, Center.Y)

        return Ray.new(Original.Origin, (Part.Position - Original.Origin).Unit)
    end

    --// Recoil. Three game functions feed the camera kick:
    --   Logic.Recoil.shot          first person (Fire.applyRecoil)
    --   ThirdPerson.kick(stats)    third person spring, CameraKickMin..Max
    --   ThirdPerson.takeKickPitch  pitch Fire subtracts from the view
    -- They're only replaced while the slider is below 100%, and put back exactly as they were at 100% and on unload,
    -- so at 100% the gun runs on the game's own untouched code.

    local Modules = {}

    task.spawn(function()
        pcall(function()
            local Core = Player:WaitForChild("PlayerScripts"):WaitForChild("Core", 30)
            Modules.Recoil = require(Core:WaitForChild("Logic"):WaitForChild("Recoil"))
            Modules.ThirdPerson = require(Core:WaitForChild("ThirdPerson"))
        end)
    end)

    local Originals = {} -- {table, key} -> original function, while swapped

    local function Scale()
        return math.clamp((Aim.Recoil or 100) / 100, 0, 1)
    end

    local function Scaled(Value, By)
        if typeof(Value) == "Vector3" or type(Value) == "number" then
            return Value * By
        end

        return Value
    end

    local Replacements = {
        {"Recoil", "shot", function(Original)
            return function(Pull, Climb, Drift, ...)
                local By = Scale()
                return Original(Pull, (tonumber(Climb) or 0) * By, (tonumber(Drift) or 0) * By, ...)
            end
        end},
        {"ThirdPerson", "kick", function(Original)
            return function(Stats, ...)
                local By = Scale()

                if By <= 0 then
                    return nil
                end

                if type(Stats) ~= "table" or Stats.CameraKickMin == nil or Stats.CameraKickMax == nil then
                    return Original(Stats, ...)
                end

                return Original(setmetatable({
                    CameraKickMin = Scaled(Stats.CameraKickMin, By),
                    CameraKickMax = Scaled(Stats.CameraKickMax, By)
                }, {__index = Stats}), ...)
            end
        end},
        {"ThirdPerson", "takeKickPitch", function(Original)
            return function(...)
                local Pitch = Original(...)
                return type(Pitch) == "number" and Pitch * Scale() or Pitch
            end
        end}
    }

    local function SetRecoilHooks(On)
        for _, Entry in next, Replacements do
            local Module, Key, Make = Modules[Entry[1]], Entry[2], Entry[3]
            local Id = Entry[1] .. "." .. Key

            if type(Module) == "table" then
                if On and not Originals[Id] and type(Module[Key]) == "function" then
                    local Original = Module[Key]

                    if pcall(function() Module[Key] = Make(Original) end) then
                        Originals[Id] = {Module, Key, Original}
                    end
                elseif not On and Originals[Id] then
                    local Saved = Originals[Id]
                    pcall(function() Saved[1][Saved[2]] = Saved[3] end)
                    Originals[Id] = nil
                end
            end
        end
    end

    --// FOV circle at the screen center, where the gun aims

    local Circle = Drawing.new("Circle")
    Circle.Visible = false
    Circle.Filled = false
    Circle.NumSides = 64
    Circle.Thickness = 1
    Circle.Transparency = 1
    Circle.Color = Color3.fromRGB(255, 255, 255)

    local Loop = RunService.RenderStepped:Connect(function()
        local Camera = workspace.CurrentCamera

        -- Game functions swapped only while recoil is lowered
        SetRecoilHooks(Aim.Recoil < 100)

        Circle.Visible = Aim.Silent and Aim.ShowFov and Camera ~= nil
        Circle.Radius = Aim.Fov

        -- Drawing uses screen space, the same space GetMouseLocation reports
        Circle.Position = UserInputService:GetMouseLocation()
    end)

    OasisUI:OnUnload(function()
        Running = false
        Aim.Silent = false
        State.AimRay = nil
        Loop:Disconnect()
        SetRecoilHooks(false)
        Circle:Remove()
    end)
end

--//==================== Visual > ESP ====================

do
    local Teams = game:GetService("Teams")
    local Running = true

    local Esp = {Enabled = false, Names = true, Distance = true, Health = true, Glow = true, MaxDistance = 1500, WantedOnly = false, HideMyTeam = false, Teams = {}}

    local Card = Visual:Module({
        Title = "Player ESP",
        Description = "Names, teams, health and wanted status over every player, colored by team.",
        Icon = "scan",
        Side = "Left",
        Default = false,
        Flag = "Visual.ESP",
        Keybind = false,
        Opened = true,
        Callback = function(Enabled) Esp.Enabled = Enabled end
    })

    Card:Checkbox({Title = "Names and team", Default = true, Flag = "Visual.ESP.Names", Callback = function(Value) Esp.Names = Value end})
    Card:Checkbox({Title = "Distance", Default = true, Flag = "Visual.ESP.Distance", Callback = function(Value) Esp.Distance = Value end})
    Card:Checkbox({Title = "Health", Default = true, Flag = "Visual.ESP.Health", Callback = function(Value) Esp.Health = Value end})
    Card:Checkbox({Title = "Glow", Tooltip = "A team-colored outline through walls. Roblox draws at most 31, so the nearest players get it.", Default = true, Flag = "Visual.ESP.Glow", Callback = function(Value) Esp.Glow = Value end})
    Card:Slider({Title = "Max distance", Min = 100, Max = 5000, Step = 50, Default = 1500, Suffix = " st", Flag = "Visual.ESP.Distance.Max", Callback = function(Value) Esp.MaxDistance = Value end})

    local Filters = Visual:Section({Title = "Filters", Icon = "filter", Side = "Right"})

    local function TeamNames()
        local Names = {}

        for _, Team in next, Teams:GetTeams() do
            table.insert(Names, Team.Name)
        end

        table.sort(Names)
        return Names
    end

    local TeamPick
    TeamPick = Filters:Dropdown({
        Title = "Only these teams",
        Values = TeamNames(),
        Multi = true,
        AllowNone = true,
        Placeholder = "All teams",
        Flag = "Visual.ESP.Teams",
        Action = {Icon = "refresh-cw", Tooltip = "Refresh teams", Callback = function() TeamPick:Refresh(TeamNames(), true) end},
        Callback = function(Values)
            table.clear(Esp.Teams)

            for _, Name in next, type(Values) == "table" and Values or {} do
                Esp.Teams[Name] = true
            end
        end
    })

    Filters:Checkbox({Title = "Wanted only", Tooltip = "Only players with an active wanted level.", Default = false, Flag = "Visual.ESP.WantedOnly", Callback = function(Value) Esp.WantedOnly = Value end})
    Filters:Checkbox({Title = "Hide my team", Default = false, Flag = "Visual.ESP.HideMyTeam", Callback = function(Value) Esp.HideMyTeam = Value end})

    local Folder = Instance.new("Folder")
    Folder.Name = "SNESP"
    Folder.Parent = (gethui and gethui()) or game:GetService("CoreGui")

    local Marks = {} -- player -> {Gui, Label, Glow}

    local function Drop(Other)
        local Mark = Marks[Other]

        if Mark then
            Mark.Gui:Destroy()
            Mark.Glow:Destroy()
            Marks[Other] = nil
        end
    end

    local function Get(Other)
        local Mark = Marks[Other]

        if not Mark then
            local Gui = Instance.new("BillboardGui")
            Gui.Size = UDim2.fromOffset(220, 44)
            Gui.StudsOffset = Vector3.new(0, 3.4, 0)
            Gui.AlwaysOnTop = true
            Gui.LightInfluence = 0

            local Label = Instance.new("TextLabel")
            Label.Size = UDim2.fromScale(1, 1)
            Label.BackgroundTransparency = 1
            Label.Font = Enum.Font.GothamBold
            Label.TextSize = 12
            Label.RichText = true
            Label.TextStrokeTransparency = 0.35
            Label.Parent = Gui
            Gui.Parent = Folder

            local Glow = Instance.new("Highlight")
            Glow.FillTransparency = 0.75
            Glow.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            Glow.Parent = Folder

            Mark = {Gui = Gui, Label = Label, Glow = Glow}
            Marks[Other] = Mark
        end

        return Mark
    end

    -- Wanted players carry an Is_Wanted value (seconds left); downed characters have a Downed attribute
    local function Status(Other, Character)
        local Parts = {}

        if Other:FindFirstChild("Is_Wanted") then
            table.insert(Parts, '<font color="#ff5050">WANTED</font>')
        end

        if Character:GetAttribute("Downed") then
            table.insert(Parts, '<font color="#f0be3c">DOWNED</font>')
        end

        return table.concat(Parts, "  ")
    end

    local function Update()
        local MyCharacter = Player.Character
        local MyRoot = MyCharacter and MyCharacter:FindFirstChild("HumanoidRootPart")
        local Rows = {}

        if Esp.Enabled and MyRoot then
            for _, Other in next, Players:GetPlayers() do
                local Character = Other ~= Player and Other.Character
                local Head = Character and Character:FindFirstChild("Head")
                local TeamName = Other.Team and Other.Team.Name or "None"

                local Allowed = Head
                    and (next(Esp.Teams) == nil or Esp.Teams[TeamName])
                    and not (Esp.HideMyTeam and Other.Team ~= nil and Other.Team == Player.Team)
                    and not (Esp.WantedOnly and not Other:FindFirstChild("Is_Wanted"))

                if Allowed then
                    local Distance = (Head.Position - MyRoot.Position).Magnitude

                    if Distance <= Esp.MaxDistance then
                        table.insert(Rows, {Other = Other, Character = Character, Head = Head, Distance = Distance, Team = TeamName})
                    end
                end
            end
        end

        table.sort(Rows, function(A, B) return A.Distance < B.Distance end)

        local Seen = {}

        for Index, Row in next, Rows do
            local Other, Character = Row.Other, Row.Character
            local Humanoid = Character:FindFirstChildOfClass("Humanoid")
            local Color = Other.TeamColor and Other.TeamColor.Color or Color3.new(1, 1, 1)
            local Mark = Get(Other)
            local Lines = {}

            Seen[Other] = true

            if Esp.Names then
                table.insert(Lines, ("<b>%s</b>  [%s]"):format(Other.DisplayName, Row.Team))
            end

            local Info = {}

            if Esp.Distance then
                table.insert(Info, ("%d st"):format(math.floor(Row.Distance)))
            end

            if Esp.Health and Humanoid then
                table.insert(Info, ("%d hp"):format(math.floor(Humanoid.Health)))
            end

            local Flags = Status(Other, Character)

            if Flags ~= "" then
                table.insert(Info, Flags)
            end

            if #Info > 0 then
                table.insert(Lines, table.concat(Info, "  ·  "))
            end

            Mark.Gui.Adornee = Row.Head
            Mark.Gui.Enabled = #Lines > 0
            Mark.Label.TextColor3 = Color
            Mark.Label.Text = table.concat(Lines, "\n")

            -- Roblox renders at most 31 highlights at once
            local Glow = Esp.Glow and Index <= 30

            if Mark.Glow.Adornee ~= Character then
                Mark.Glow.Adornee = Character
            end

            Mark.Glow.Enabled = Glow
            Mark.Glow.OutlineColor = Color
            Mark.Glow.FillColor = Color
        end

        for Other in next, Marks do
            if not Seen[Other] then
                Drop(Other)
            end
        end
    end

    Players.PlayerRemoving:Connect(Drop)

    task.spawn(function()
        while Running do
            pcall(Update)
            task.wait(0.2)
        end
    end)

    OasisUI:OnUnload(function()
        Running = false
        Folder:Destroy()
    end)
end

--//==================== World > Render ====================

do
    local Lighting = game:GetService("Lighting")
    local RunService = game:GetService("RunService")

    local Render = {
        FullBright = false, NoFog = false, NoShadows = false,
        Time = false, ClockTime = 14,
        Tint = false, TintColor = Color3.fromRGB(140, 140, 160),
        Exposure = false, ExposureValue = 0.5,
        NoBlur = false, NoBloom = false, NoGrading = false,
        Fov = false, FovValue = 90,
        Stretch = false, StretchValue = 0.75
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

    -- Screen effects by type, wherever the game puts them (Lighting or the camera)
    local EffectGroups = {
        NoBlur = {"BlurEffect", "DepthOfFieldEffect"},
        NoBloom = {"BloomEffect", "SunRaysEffect"},
        NoGrading = {"ColorCorrectionEffect"}
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


    --// Lighting and effects, re-applied every frame because the game sets time and effects itself

    local function ApplyLighting()
        local Atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")

        -- One wanted value per property, so options that share a property never fight each other
        local Ambient = (Render.Tint and Render.TintColor) or (Render.FullBright and Color3.fromRGB(150, 150, 150)) or nil
        local Clock = (Render.Time and Render.ClockTime) or (Render.FullBright and 14) or nil

        for Property, Value in next, {Ambient = Ambient, OutdoorAmbient = Ambient, ClockTime = Clock, Brightness = Render.FullBright and 2 or nil} do
            if Value ~= nil then
                Set(Lighting, Property, Value)
            end
        end

        for _, Property in next, {"Ambient", "OutdoorAmbient", "ClockTime", "Brightness"} do
            local Wanted = (Property == "ClockTime" and Clock) or (Property == "Brightness" and Render.FullBright) or ((Property == "Ambient" or Property == "OutdoorAmbient") and Ambient)

            if not Wanted then
                Restore(Lighting, Property)
            end
        end

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

        local Camera = workspace.CurrentCamera
        local Containers = {Lighting:GetChildren(), Camera and Camera:GetChildren() or {}}

        for Option, Classes in next, EffectGroups do
            for _, List in next, Containers do
                for _, Effect in next, List do
                    if table.find(Classes, Effect.ClassName) then
                        if Render[Option] then
                            Set(Effect, "Enabled", false)
                        else
                            Restore(Effect, "Enabled")
                        end
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

    RunService:BindToRenderStep("SuperNovaERLCRender", Enum.RenderPriority.Camera.Value + 1, function()
        pcall(ApplyLighting)

        local Camera = workspace.CurrentCamera

        if Camera then
            pcall(ApplyFov, Camera)

            -- Stretch squashes the view vertically after the camera has been placed for this frame
            if Render.Stretch then
                Camera.CFrame = Camera.CFrame * CFrame.new(0, 0, 0, 1, 0, 0, 0, Render.StretchValue, 0, 0, 0, 1)
            end
        end

    end)

    OasisUI:OnUnload(function()
        RunService:UnbindFromRenderStep("SuperNovaERLCRender")

        for Object, Saved in next, Originals do
            for Property, Value in next, Saved do
                pcall(function() Object[Property] = Value end)
            end
        end

        table.clear(Originals)

        if LastWritten and GameFov and workspace.CurrentCamera then
            workspace.CurrentCamera.FieldOfView = GameFov
        end
    end)
end

--//==================== Overview > Safety ====================

do
    local UserInputService = game:GetService("UserInputService")
    local VirtualUser = game:GetService("VirtualUser")

    local Safety = Overview:Section({Title = "Safety", Icon = "shield", Side = "Left"})

    -- Anti-AFK: Roblox kicks after 20 idle minutes; a virtual right click on Idled resets that timer
    local AntiAfk = true

    Safety:Toggle({Title = "Anti-AFK", Tooltip = "Stops Roblox's 20 minute idle kick.", Default = true, Flag = "Safety.AntiAfk", Callback = function(Value) AntiAfk = Value end})

    local IdleConnection = Player.Idled:Connect(function()
        if AntiAfk then
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.zero)
        end
    end)

    -- Panic key: hides the menu and every visual, and puts it all back on the second press
    local VisualFlags = {
        "Visual.ESP", "Combat.SilentAim.ShowFov",
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

    Safety:Paragraph({Content = "Panic hides the menu and switches off the ESP and every render change. Press it again to bring them back."})

    local PanicConnection = UserInputService.InputBegan:Connect(function(Input, Typing)
        if not Typing and Input.KeyCode ~= Enum.KeyCode.Unknown and IsPanicKey(Input.KeyCode) then
            Panic()
        end
    end)

    OasisUI:OnUnload(function()
        IdleConnection:Disconnect()
        PanicConnection:Disconnect()
    end)
end

-- Loads the saved config only now that every card exists
Window:LoadAutoload()

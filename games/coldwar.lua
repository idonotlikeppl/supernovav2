-- SuperNova | NATO vs PACT
-- Built from the game's client code (Workspace.rar dump). Every feature below drives the game's own systems:
-- its admin ESP and freecam modules, its weapon configs, and its shot pipeline.

-- Running the script again: unload the copy that's already running first
if getgenv().SuperNovaUnload then
    pcall(getgenv().SuperNovaUnload)
    getgenv().SuperNovaUnload = nil
end

local OasisUI = loadstring(game:HttpGet("https://github.com/Mold53/OasisUI/releases/download/v1.6.0/OasisUI.lua"))()
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Player = Players.LocalPlayer

local getconstants = debug.getconstants or getconstants

--// Helpers

-- Constant lists can have nil holes, which stop table.find early, so walk them with next
local function HasConstants(Constants, ...)
    if type(Constants) ~= "table" then
        return false
    end

    local Present = {}

    for _, Value in next, Constants do
        if type(Value) == "string" then
            Present[Value] = true
        end
    end

    for _, Name in next, {...} do
        if not Present[Name] then
            return false
        end
    end

    return true
end

-- How "leave when staff is here" leaves: a disconnect by default; the Match tab can turn it into a server hop
local Leave = {Handler = function(Reason)
    Player:Kick(Reason)
end}

local function Notify(Title, Content, Kind, Duration)
    OasisUI:Notify({Title = Title, Content = Content, Type = Kind or "Info", Duration = Duration or 4})
end

-- require that returns nil instead of erroring, so one missing module can't stop the script
local function Require(Module)
    if not Module then
        return nil
    end

    local Ok, Result = pcall(require, Module)
    return Ok and Result or nil
end

-- Freecam reads its permission from attributes on this folder (the server fills it for staff)
local function PrivateAttributes()
    local Gui = Player:FindFirstChildOfClass("PlayerGui")
    return Gui and Gui:FindFirstChild("PrivateAttributes")
end

local Shared = ReplicatedStorage:WaitForChild("Shared", 10)
local WeaponManager = Require(Shared and Shared:FindFirstChild("WeaponConfigManager"))

--// Window

-- GetProductInfo is a web call: if it fails, the menu still opens
local NameOk, GameName = pcall(function()
    return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name
end)
GameName = NameOk and GameName or "NATO vs PACT"

local Window = OasisUI:CreateWindow({
    Title = GameName,
    Subtitle = "✨SuperNova💫",
    Folder = "shenyu_u_front", -- its own config folder, separate from the ATL script's
    DefaultConfig = "default",
    AutoSave = true,
    AutoLoad = false -- loaded by hand once the whole menu is built
})

getgenv().SuperNovaUnload = function()
    OasisUI:Unload()
end

-- Laid out like a CS:GO trainer: aim, visuals, movement, vehicle, team, misc, settings
local Combat = Window:Tab({Title = "Combat", Icon = "crosshair"})
local AimTab = Combat:SubTab({Title = "Aim", Icon = "target"})
local GunsTab = Combat:SubTab({Title = "Weapon", Icon = "sliders-horizontal"})
local AntiAimTab = Combat:SubTab({Title = "Anti-aim", Icon = "orbit"})

local Visual = Window:Tab({Title = "Visuals", Icon = "eye"})
local EspTab = Visual:SubTab({Title = "Players", Icon = "scan"})
local IntelTab = Visual:SubTab({Title = "Radar", Icon = "radar"})
local WorldTab = Visual:SubTab({Title = "World", Icon = "globe"})
local ClarityTab = Visual:SubTab({Title = "Effects", Icon = "sparkles"})

local Movement = Window:Tab({Title = "Movement", Icon = "wind"})
local MoveTab = Movement:SubTab({Title = "Movement", Icon = "wind"})

local VehicleWin = Window:Tab({Title = "Vehicle", Icon = "car"})
local DriveTab = VehicleWin:SubTab({Title = "Drive", Icon = "gauge"})
local TurretTab = VehicleWin:SubTab({Title = "Turret", Icon = "crosshair"})

local TeamWin = Window:Tab({Title = "Team", Icon = "users"})
local SupportTab = TeamWin:SubTab({Title = "Support", Icon = "heart-pulse"})

local MiscWin = Window:Tab({Title = "Misc", Icon = "settings-2"})
local MatchTab = MiscWin:SubTab({Title = "Match", Icon = "flag"})
local ProtectTab = MiscWin:SubTab({Title = "Protection", Icon = "shield"})
local DebugTab = MiscWin:SubTab({Title = "Debug", Icon = "bug"})
local StaffTab = ProtectTab -- the staff alert lives with the other protection options

local Settings = Window:Tab({Title = "Settings", Icon = "cog"})
local Actions = Settings:Section({Title = "Menu", Icon = "settings", Side = "Left"})
Actions:Button({Title = "Unload", Icon = "power", Style = "Danger", Confirm = "Unload the menu and switch everything off?", Callback = function()
    OasisUI:Unload()
end})

--// Silent aim

do
    local Aim = {
        Enabled = false,
        FOV = 150,
        Part = "Head",
        VisibleOnly = true,
        SkipDowned = true,
        Drop = true,
        Lead = true,
        MaxDistance = 2000,
        ShowFOV = true,
        Turrets = false
    }

    local function IsDowned(Character)
        local Values = Character:FindFirstChild("CharacterValues")
        local Flag = Values and Values:FindFirstChild("Unconscious")
        return Flag ~= nil and Flag.Value == true
    end

    local function Alive(Character)
        local Humanoid = Character:FindFirstChildOfClass("Humanoid")
        return Humanoid ~= nil and Humanoid.Health > 0 and Humanoid:GetState() ~= Enum.HumanoidStateType.Dead
    end

    -- No team yet (deploy screen) or the same team is never a target
    local function IsEnemy(Other)
        return Other ~= Player and Other.Team ~= nil and Player.Team ~= nil and Other.Team ~= Player.Team
    end

    -- R6 rigs; the hit codec also knows the R15 torso names, so fall back through those
    local function AimPart(Character)
        if Aim.Part == "Head" then
            return Character:FindFirstChild("Head") or Character:FindFirstChild("HumanoidRootPart")
        end

        return Character:FindFirstChild("Torso") or Character:FindFirstChild("UpperTorso") or Character:FindFirstChild("HumanoidRootPart")
    end

    local VisibilityParams = RaycastParams.new()
    VisibilityParams.FilterType = Enum.RaycastFilterType.Exclude
    VisibilityParams.IgnoreWater = true

    -- The whole vehicle you're sitting in, so a turret's own hull doesn't block its line of sight
    local function MyVehicle()
        local Character = Player.Character
        local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
        local Node = Humanoid and Humanoid.SeatPart

        while Node and Node.Parent and Node.Parent ~= Workspace and not Node.Parent:IsA("Folder") do
            Node = Node.Parent
        end

        return Node
    end

    -- Same things the gun's own raycast skips: you, the Ignore folder, and the camera (viewmodel)
    local function RefreshVisibilityFilter()
        local List = {}

        -- Built one at a time: a nil in a table literal would leave a hole and cut the list short
        for _, Object in next, {Player.Character or false, Workspace:FindFirstChild("Ignore") or false, Workspace.CurrentCamera or false, MyVehicle() or false} do
            if Object then
                table.insert(List, Object)
            end
        end

        VisibilityParams.FilterDescendantsInstances = List
    end

    local function Visible(Origin, Part, Character)
        local Result = Workspace:Raycast(Origin, Part.Position - Origin, VisibilityParams)
        return Result == nil or Result.Instance:IsDescendantOf(Character)
    end

    -- The enemy part nearest the crosshair, inside the FOV circle
    local function PickTarget(Origin)
        local Camera = Workspace.CurrentCamera
        local Mouse = UserInputService:GetMouseLocation()
        local Best, BestCharacter, BestGap = nil, nil, Aim.FOV

        if Aim.VisibleOnly then
            RefreshVisibilityFilter()
        end

        for _, Other in next, Players:GetPlayers() do
            local Character = IsEnemy(Other) and Other.Character

            if Character and Alive(Character) and not (Aim.SkipDowned and IsDowned(Character)) then
                local Part = AimPart(Character)

                if Part and (Part.Position - Origin).Magnitude <= Aim.MaxDistance then
                    local Screen, OnScreen = Camera:WorldToViewportPoint(Part.Position)

                    if OnScreen then
                        local Gap = (Vector2.new(Screen.X, Screen.Y) - Mouse).Magnitude

                        if Gap <= BestGap and (not Aim.VisibleOnly or Visible(Origin, Part, Character)) then
                            Best, BestCharacter, BestGap = Part, Character, Gap
                        end
                    end
                end
            end
        end

        return Best, BestCharacter
    end

    -- The game's bullet model (Shared.Ballistics.Trajectory): forward distance v/K * (1 - e^(-K*t)) along the aim,
    -- and 0.5 * g * t^2 of drop straight down. Solve for the aim that lands on the target, leading its movement.
    local function Solve(Origin, Target, Velocity, Speed, K, Gravity)
        local Point, Time = Target, 0

        for _ = 1, 4 do
            local Moved = Aim.Lead and (Target + Velocity * Time) or Target
            Point = Aim.Drop and (Moved + Vector3.yAxis * (0.5 * Gravity * Time * Time)) or Moved

            local Distance = (Point - Origin).Magnitude

            if K > 1e-6 then
                local Ratio = Distance * K / Speed

                -- Past the farthest the bullet can ever travel
                if Ratio >= 1 then
                    return nil
                end

                Time = -math.log(1 - Ratio) / K
            else
                Time = Distance / Speed
            end
        end

        return (Point - Origin).Unit
    end

    -- Turns the whole pellet pattern onto the target, so shotguns keep their spread instead of one perfect line
    local function Retarget(Directions, Wanted)
        local Sum = Vector3.zero

        for _, Direction in next, Directions do
            Sum += Direction.Unit
        end

        local Mean = Sum.Magnitude > 1e-6 and Sum.Unit or Wanted
        local Axis = Mean:Cross(Wanted)
        local New = table.create(#Directions)

        -- Already on target: keep the pattern as it is (filling with Wanted would collapse a shotgun's spread)
        if Axis.Magnitude < 1e-6 then
            for Index, Direction in next, Directions do
                New[Index] = Direction.Unit
            end

            return New
        end

        local Rotation = CFrame.fromAxisAngle(Axis.Unit, math.acos(math.clamp(Mean:Dot(Wanted), -1, 1)))

        for Index, Direction in next, Directions do
            New[Index] = Rotation:VectorToWorldSpace(Direction.Unit)
        end

        return New
    end

    -- How it works: Muzzle.Discharge works out the muzzle position and the shot directions (spread included), then
    -- hands them to ClientFire's send function. That function simulates the bullet locally, reports what it hits,
    -- and tells the server the same origin, directions and seeds. Bending the directions on the way in makes
    -- the bullet, the hit report and the server's replay all agree.
    --
    -- The send function's name is scrambled (sLnpiWe6Dt in this build) and will change with updates, so it's
    -- found by its constants instead. The hook is installed once per session and calls whatever Handler the
    -- current script sets, so re-running the script never stacks hooks.

    local ShotHook = getgenv().SuperNovaFrontShotHook

    if not ShotHook then
        local Found = {}

        if getgc and getconstants and hookfunction then
            for _, Function in next, getgc() do
                if type(Function) == "function" and (not islclosure or islclosure(Function)) then
                    local Ok, Constants = pcall(getconstants, Function)

                    if Ok and HasConstants(Constants, "encodeFire", "Seeds", "beginDischarge") then
                        table.insert(Found, Function)
                    end
                end
            end
        end

        if #Found > 0 then
            ShotHook = {Count = #Found}
            getgenv().SuperNovaFrontShotHook = ShotHook

            for _, Function in next, Found do
                local Original
                Original = hookfunction(Function, function(Tool, MuzzleIndex, BulletIndex, Origin, Directions, Options)
                    local Handler = ShotHook.Handler

                    if Handler and typeof(Origin) == "Vector3" and type(Directions) == "table" and #Directions > 0 then
                        local Ok, New = pcall(Handler, Tool, MuzzleIndex, BulletIndex, Origin, Directions)

                        if Ok and New then
                            Directions = New
                        end
                    end

                    return Original(Tool, MuzzleIndex, BulletIndex, Origin, Directions, Options)
                end)
            end
        end
    end


    if ShotHook then
        ShotHook.Handler = function(Tool, MuzzleIndex, BulletIndex, Origin, Directions)
            if not Aim.Enabled then
                return nil
            end

            -- Guns pass their Tool; vehicle turrets (TurretFireController) pass the weapon name as a string
            local IsTurret = type(Tool) == "string"
            local WeaponName = IsTurret and Tool or (typeof(Tool) == "Instance" and Tool.Name)

            if not WeaponName or (IsTurret and not Aim.Turrets) then
                return nil
            end

            -- Ballistics come from the same config the game builds the bullet from (Sources.WeaponSource)
            local Config = WeaponManager and WeaponManager:GetMuzzleConfig(WeaponName, MuzzleIndex or 1)
            local Bullet = Config and type(Config.BulletSettings) == "table" and Config.BulletSettings[BulletIndex or 1]
            local Speed = Bullet and tonumber(Bullet.MuzzleVelocity) or 0
            local K = Bullet and tonumber(Bullet.Drag) or 1 -- the game's own default when Drag is missing

            -- No ballistics for this weapon (some vehicle cannons live in another config): a straight-line guess
            -- would miss at range and look obvious, so leave the shot alone
            if Speed <= 0 then
                return nil
            end

            local Part, Character = PickTarget(Origin)

            if not Part then
                return nil
            end

            local Root = Character:FindFirstChild("HumanoidRootPart")
            local Velocity = Root and Root.AssemblyLinearVelocity or Vector3.zero
            local Wanted = Solve(Origin, Part.Position, Velocity, Speed, K, Workspace.Gravity)

            return Wanted and Retarget(Directions, Wanted) or nil
        end
    end

    --// Card

    -- Targeting is shared by silent aim and aim lock, so it sits in its own section instead of inside either card
    local FOVCircle = Drawing and Drawing.new("Circle")

    if FOVCircle then
        FOVCircle.Visible = false
        FOVCircle.Filled = false
        FOVCircle.NumSides = 64
        FOVCircle.Thickness = 1
        FOVCircle.Transparency = 1
        FOVCircle.Color = Color3.fromRGB(255, 255, 255)
    end

    local Targeting = AimTab:Section({Title = "Targeting", Icon = "target", Side = "Left"})
    Targeting:Slider({Title = "FOV", Min = 20, Max = 600, Step = 5, Default = 150, Suffix = " px", Flag = "Combat.SilentAim.FOV", Callback = function(Value) Aim.FOV = Value end})
    Targeting:Toggle({
        Title = "Draw FOV",
        Default = true,
        Flag = "Combat.SilentAim.ShowFOV",
        Callback = function(Value) Aim.ShowFOV = Value end,
        Color = {
            Default = Color3.fromRGB(255, 255, 255),
            Flag = "Combat.SilentAim.FOVColor",
            Callback = function(Value)
                if FOVCircle then
                    FOVCircle.Color = Value
                end
            end
        }
    })
    Targeting:Segmented({Title = "Hitbox", Values = {"Head", "Torso"}, Default = "Head", Flag = "Combat.SilentAim.Part", Callback = function(Value) Aim.Part = Value end})
    Targeting:Slider({Title = "Max distance", Min = 100, Max = 5000, Step = 50, Default = 2000, Suffix = " st", Flag = "Combat.SilentAim.Distance", Callback = function(Value) Aim.MaxDistance = Value end})
    Targeting:Toggle({Title = "Visible only", Tooltip = "Skip enemies behind walls.", Default = true, Flag = "Combat.SilentAim.Visible", Callback = function(Value) Aim.VisibleOnly = Value end})
    Targeting:Toggle({Title = "Ignore downed", Default = true, Flag = "Combat.SilentAim.SkipDowned", Callback = function(Value) Aim.SkipDowned = Value end})
    Targeting:Toggle({Title = "Bullet drop", Tooltip = "Aims high to cancel drop over distance.", Default = true, Flag = "Combat.SilentAim.Drop", Callback = function(Value) Aim.Drop = Value end})
    Targeting:Toggle({Title = "Prediction", Tooltip = "Leads moving targets.", Default = true, Flag = "Combat.SilentAim.Lead", Callback = function(Value) Aim.Lead = Value end})

    local Silent = AimTab:Module({
        Title = "Silent aim",
        Description = "Bullets go to the target in your FOV without moving your camera.",
        Icon = "crosshair",
        Side = "Right",
        Risky = true,
        Default = false,
        Flag = "Combat.SilentAim",
        Keybind = {Key = nil, Mode = "Toggle"},
        Opened = true,
        Callback = function(Enabled)
            Aim.Enabled = Enabled

            if Enabled and not ShotHook then
                Notify("Silent aim", "Your executor is missing getgc, getconstants or hookfunction, so silent aim can't run.", "Error", 6)
            end
        end
    })

    Silent:Checkbox({Title = "Vehicle machine guns", Tooltip = "Also works from mounted guns (PKT, NSV, M2HB...).", Default = false, Flag = "Combat.SilentAim.Turrets", Callback = function(Value) Aim.Turrets = Value end})

    --// Aim lock: turns your camera onto the target silent aim would pick, with bullet drop and lead worked in.
    -- The game's built-in aim assist only works on a controller thumbstick and caps at 100%, so this stands in
    -- for it on mouse. The game uses Roblox's standard camera, which reads the camera's facing back every frame,
    -- so a turn made here sticks; recoil adds its own offsets on top.

    local Lock = {Enabled = false, Strength = 0.3, AdsOnly = true}

    local function HeldWeapon()
        local Character = Player.Character
        local Tool = Character and Character:FindFirstChildOfClass("Tool")
        return Tool and Tool:GetAttribute("ToolType") == "Weapon" and Tool or nil
    end

    local function LockStep(Delta)
        if not Lock.Enabled or UserInputService:GetFocusedTextBox() then
            return
        end

        if Lock.AdsOnly and not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
            return
        end

        local Camera, Tool = Workspace.CurrentCamera, HeldWeapon()

        if not (Camera and Tool) then
            return
        end

        local From = Camera.CFrame.Position
        local Part, Character = PickTarget(From)

        if not Part then
            return
        end

        local Config = WeaponManager and WeaponManager:GetMuzzleConfig(Tool.Name, 1)
        local Bullet = Config and type(Config.BulletSettings) == "table" and Config.BulletSettings[1]
        local Speed = Bullet and tonumber(Bullet.MuzzleVelocity) or 0
        local Root = Character:FindFirstChild("HumanoidRootPart")
        local Velocity = Root and Root.AssemblyLinearVelocity or Vector3.zero
        local Wanted = Speed > 0 and Solve(From, Part.Position, Velocity, Speed, Bullet and tonumber(Bullet.Drag) or 1, Workspace.Gravity) or (Part.Position - From).Unit

        if not Wanted then
            return
        end

        -- Eased so the same Strength turns the same amount per second at any frame rate; 100% snaps
        local Alpha = 1 - (1 - Lock.Strength) ^ (Delta * 60)
        local Look = Camera.CFrame.LookVector:Lerp(Wanted, Alpha)
        Camera.CFrame = CFrame.lookAt(From, From + Look)
    end

    local LockCard = AimTab:Module({
        Title = "Aim lock",
        Description = "Moves your camera onto the target in your FOV.",
        Icon = "locate-fixed",
        Side = "Right",
        Risky = true,
        Default = false,
        Flag = "Combat.AimLock",
        Keybind = {Key = nil, Mode = "Toggle"},
        Opened = true,
        Callback = function(Enabled) Lock.Enabled = Enabled end
    })

    LockCard:Slider({Title = "Strength", Min = 5, Max = 100, Step = 5, Default = 30, Suffix = "%", Buttons = true, Flag = "Combat.AimLock.Strength", Tooltip = "Low is smooth, 100% snaps.", Callback = function(Value) Lock.Strength = Value / 100 end})
    LockCard:Checkbox({Title = "Only while aiming", Tooltip = "Only while you hold right mouse.", Default = true, Flag = "Combat.AimLock.AdsOnly", Callback = function(Value) Lock.AdsOnly = Value end})

    RunService:BindToRenderStep("SuperNovaFrontAimLock", Enum.RenderPriority.Camera.Value + 2, function(Delta)
        pcall(LockStep, Delta)
    end)


    local CircleShown = false

    local CircleLoop = RunService.RenderStepped:Connect(function()
        if not FOVCircle then
            return
        end

        local Show = (Aim.Enabled or Lock.Enabled) and Aim.ShowFOV

        -- Drawing writes go through the executor, so only touch the circle while it's on screen
        if Show ~= CircleShown then
            FOVCircle.Visible = Show
            CircleShown = Show
        end

        if Show then
            FOVCircle.Radius = Aim.FOV
            FOVCircle.Position = UserInputService:GetMouseLocation()
        end
    end)

    OasisUI:OnUnload(function()
        Aim.Enabled = false
        Lock.Enabled = false
        RunService:UnbindFromRenderStep("SuperNovaFrontAimLock")

        if ShotHook then
            ShotHook.Handler = nil
        end

        CircleLoop:Disconnect()

        if FOVCircle then
            FOVCircle:Remove()
        end
    end)
end

--// Gun mods: the weapon configs are plain tables in ReplicatedStorage.Shared.WeaponConfigManager
--
-- What can be changed, from reading the client code:
--   Spread, recoil (5 values), pellets per shot: read straight from the config on every shot.
--   Fire rate and fire modes: copied into each gun once, when the tool is built on deploy (Chamber.new turns
--   Firerate into shootDelay, FireController.new builds its mode list). Editing the config alone only reached
--   guns built afterwards, so the guns you already hold are patched directly too.
-- What can't, and is left alone on purpose:
--   Ammo, magazines and reload timing are the server's: it refills the magazine on its own clock. Muzzle velocity, drag and damage come from the server's
--   own copy when it replays your shots; changing them on your side only makes your hits miss.

do
    local Mods = {
        Active = false,
        Spread = 1, -- 1 is stock, 0 is none
        CameraRecoil = 1,
        GunRecoil = 1,
        Kick = 1,
        FullAuto = false,
        Firerate = 1,
        ExtraPellets = 0
    }

    local MAX_PELLETS = 16 -- ClientFire sends at most 16 directions per shot
    local Originals = setmetatable({}, {__mode = "k"}) -- config -> what it held before we touched it
    local Configs -- found once: the manager loads every weapon at startup

    -- The live tables the guns read. getgc(true) finds the game's own copies even when this executor's require
    -- hands back a fresh copy; the manager's list is added too, in case getgc isn't there.
    local function FindConfigs()
        local List, Seen = {}, {}

        local function Add(Config)
            if type(Config) == "table" and not Seen[Config] and type(rawget(Config, "BulletSettings")) == "table" and rawget(Config, "Firemodes") ~= nil then
                Seen[Config] = true
                table.insert(List, Config)
            end
        end

        if getgc then
            for _, Value in next, getgc(true) do
                if type(Value) == "table" then
                    Add(Value)
                end
            end
        end

        local Folder = Shared and Shared:FindFirstChild("WeaponConfigManager")

        for _, Module in next, Folder and Folder:GetChildren() or {} do
            local Muzzles = Require(Module)

            if type(Muzzles) == "table" then
                for _, Config in next, Muzzles do
                    Add(Config)
                end
            end
        end

        return List
    end

    -- Semi-auto and burst guns get Automatic added; bolt, pump and single-shot guns are left alone, since their
    -- chambering animations break when fired automatically
    local function WithAuto(Firemodes)
        if type(Firemodes) ~= "table" or table.find(Firemodes, "Automatic") then
            return Firemodes
        end

        if not (table.find(Firemodes, "SemiAutomatic") or table.find(Firemodes, "Burst")) then
            return Firemodes
        end

        local New = table.clone(Firemodes)
        table.insert(New, 1, "Automatic")
        return New
    end

    -- Which multiplier each recoil value follows
    local RecoilGroups = {
        CameraRecoilVertical = "CameraRecoil",
        CameraRecoilHorizontal = "CameraRecoil",
        GunRecoilVertical = "GunRecoil",
        GunRecoilHorizontal = "GunRecoil",
        RecoilKick = "Kick"
    }

    -- A setting's value while the master switch is on; stock (1, false or 0) while it's off
    local function Get(Key)
        if Mods.Active then
            return Mods[Key]
        end

        return (Key == "FullAuto" and false) or (Key == "ExtraPellets" and 0) or 1
    end

    local function Scale(Original, Multiplier)
        return type(Original) == "number" and Original * Multiplier or Original
    end

    local function Remember(Config)
        local Saved = Originals[Config]

        if Saved then
            return Saved
        end

        Saved = {
            Spread = Config.Spread,
            Firerate = Config.Firerate,
            Firemodes = Config.Firemodes,
            Recoil = type(Config.Recoil) == "table" and table.clone(Config.Recoil) or nil,
            Bullets = {} -- index -> {Spread, ShotAmount}
        }

        for Index, Bullet in next, Config.BulletSettings do
            if type(Bullet) == "table" then
                Saved.Bullets[Index] = {Spread = Bullet.Spread, ShotAmount = Bullet.ShotAmount}
            end
        end

        Originals[Config] = Saved
        return Saved
    end

    --// Guns that already exist: their Muzzle objects hold the copies

    local AutoMode -- the game's own Automatic strategy, borrowed from a gun that has it

    local function LiveMuzzles()
        local List = {}

        if not getgc then
            return List
        end

        for _, Value in next, getgc(true) do
            if type(Value) == "table" then
                local Chamber, Fire = rawget(Value, "chamber"), rawget(Value, "fireController")

                if type(Chamber) == "table" and type(Fire) == "table" and rawget(Chamber, "shootDelay") ~= nil and type(rawget(Fire, "modes")) == "table" and type(rawget(Value, "config")) == "table" then
                    table.insert(List, Value)
                end
            end
        end

        return List
    end

    local function FindAutoMode(Muzzles)
        for _, Muzzle in next, Muzzles do
            for _, Mode in next, Muzzle.fireController.modes do
                if Mode.name == "Automatic" and type(Mode.strategy) == "table" then
                    return {name = "Automatic", strategy = Mode.strategy, isHandAction = false}
                end
            end
        end

        -- Nobody holds an automatic gun: load the strategy module itself
        local Client = ReplicatedStorage:FindFirstChild("Client")
        local Node = Client

        for _, Name in next, {"Tools", "Weapon", "Muzzle", "firemodes", "Automatic"} do
            Node = Node and Node:FindFirstChild(Name)
        end

        local Strategy = Require(Node)
        return type(Strategy) == "table" and type(Strategy.fire) == "function" and {name = "Automatic", strategy = Strategy, isHandAction = false} or nil
    end

    local function SameModes(Modes, Names)
        if #Modes ~= #Names then
            return false
        end

        for Index, Name in next, Names do
            if Modes[Index].name ~= Name then
                return false
            end
        end

        return true
    end

    -- Rebuilds a gun's mode list to match the names wanted, reusing its own entries where it has them
    local function SetModes(Fire, Names)
        if SameModes(Fire.modes, Names) then
            return
        end

        local ByName = {}

        for _, Mode in next, Fire.modes do
            ByName[Mode.name] = Mode
        end

        ByName.Automatic = ByName.Automatic or AutoMode

        local New = {}

        for _, Name in next, Names do
            if ByName[Name] then
                table.insert(New, ByName[Name])
            end
        end

        if #New > 0 then
            Fire.modes = New
            Fire.currentIndex = 1 -- Automatic goes first, so the gun comes up in full auto
            Fire.burstShot = 0
        end
    end

    local function PatchLive()
        local Muzzles = LiveMuzzles()
        AutoMode = AutoMode or FindAutoMode(Muzzles)

        for _, Muzzle in next, Muzzles do
            pcall(function()
                local Saved = Remember(Muzzle.config)

                -- From the stock rate, never the live delay: a gun built after the config was edited already
                -- carries the faster delay, and scaling that again would stack
                if type(Saved.Firerate) == "number" and Saved.Firerate > 0 then
                    Muzzle.chamber.shootDelay = 60 / (Saved.Firerate * Get("Firerate"))
                end

                if type(Saved.Firemodes) == "table" then
                    SetModes(Muzzle.fireController, Get("FullAuto") and WithAuto(Saved.Firemodes) or Saved.Firemodes)
                end
            end)
        end

        return #Muzzles
    end

    local function Apply()
        Configs = Configs or FindConfigs()

        local Spread, Extra = Get("Spread"), Get("ExtraPellets")

        for _, Config in next, Configs do
            local Saved = Remember(Config)

            pcall(function()
                -- Effective spread is the bullet's own, else the gun's, else 1 (Muzzle.Discharge), so a gun with
                -- no Spread of its own gets 1 scaled, and goes back to having none when the slider is at stock
                if Saved.Spread ~= nil then
                    Config.Spread = Saved.Spread * Spread
                else
                    Config.Spread = Spread ~= 1 and Spread or nil
                end

                for Index, Bullet in next, Saved.Bullets do
                    local Live = Config.BulletSettings[Index]

                    if Bullet.Spread ~= nil then
                        Live.Spread = Bullet.Spread * Spread
                    end

                    -- Extra pellets stack on the stock count, capped at what one shot can carry
                    local Stock = Bullet.ShotAmount or 1
                    Live.ShotAmount = Extra > 0 and math.min(Stock + Extra, MAX_PELLETS) or Bullet.ShotAmount
                end

                if Saved.Recoil then
                    for Key, Original in next, Saved.Recoil do
                        local Group = RecoilGroups[Key]

                        if Group and type(Original) == "number" then
                            Config.Recoil[Key] = Original * Get(Group)
                        end
                    end
                end

                Config.Firerate = Scale(Saved.Firerate, Get("Firerate"))

                Config.Firemodes = Get("FullAuto") and WithAuto(Saved.Firemodes) or Saved.Firemodes
            end)
        end

        PatchLive()
    end

    -- Sliders fire on every step of a drag, and PatchLive walks memory, so slider changes are batched
    local Pending = false

    local function Schedule()
        if Pending or not Mods.Active then
            return
        end

        Pending = true

        task.delay(0.3, function()
            Pending = false

            if Mods.Active then
                Apply()
            end
        end)
    end

    -- Puts every gun back; nothing to do if no config was ever touched
    local function Restore()
        Mods.Active = false

        if Configs then
            Apply()
        end
    end

    local Guns = GunsTab:Module({
        Title = "Gun mods",
        Description = "100% is stock.",
        Icon = "crosshair",
        Side = "Left",
        Risky = true,
        Default = false,
        Flag = "Guns.Enabled",
        Keybind = false,
        Opened = true,
        Callback = function(Enabled)
            if Enabled then
                Mods.Active = true
                Apply()
            else
                Restore()
            end
        end
    })

    -- Sliders show percent; the mods hold fractions
    local function Percent(Key)
        return function(Value)
            Mods[Key] = Value / 100
            Schedule()
        end
    end

    local Handling = Guns:Group({Title = "Handling", Icon = "crosshair", Opened = true})
    Handling:Slider({Title = "Spread", Min = 0, Max = 100, Step = 5, Default = 100, Suffix = "%", Buttons = true, Flag = "Guns.Spread", Tooltip = "0% sends every bullet straight down the barrel.", Callback = Percent("Spread")})
    Handling:Slider({Title = "Camera recoil", Min = 0, Max = 100, Step = 5, Default = 100, Suffix = "%", Buttons = true, Flag = "Guns.CameraRecoil", Tooltip = "How far each shot throws your view.", Callback = Percent("CameraRecoil")})
    Handling:Slider({Title = "Gun climb", Min = 0, Max = 100, Step = 5, Default = 100, Suffix = "%", Buttons = true, Flag = "Guns.GunRecoil", Tooltip = "How far the gun itself rises and drifts.", Callback = Percent("GunRecoil")})
    Handling:Slider({Title = "Kick", Min = 0, Max = 100, Step = 5, Default = 100, Suffix = "%", Buttons = true, Flag = "Guns.Kick", Tooltip = "The gun's push back into your shoulder.", Callback = Percent("Kick")})

    local Firing = Guns:Group({Title = "Firing", Icon = "zap", Opened = true})
    Firing:Checkbox({Title = "Full auto", Tooltip = "Semi-auto and burst guns. V switches back to semi.", Default = false, Flag = "Guns.FullAuto", Callback = function(Value)
        Mods.FullAuto = Value
        Schedule()
    end})
    Firing:Slider({Title = "Fire rate", Min = 100, Max = 300, Step = 10, Default = 100, Suffix = "%", Buttons = true, Flag = "Guns.Firerate", Tooltip = "Risky. Raise it slowly.", Callback = Percent("Firerate")})
    Firing:Slider({Title = "Extra pellets", Min = 0, Max = 15, Step = 1, Default = 0, Buttons = true, Flag = "Guns.ExtraPellets", Tooltip = "More bullets per shot, up to 16.", Callback = function(Value)
        Mods.ExtraPellets = Value
        Schedule()
    end})


    OasisUI:OnUnload(Restore)
end

--// Vehicle mods: vehicle configs are plain tables in ReplicatedStorage.Shared.VehicleConfigManager.
-- The driver's client runs the vehicle's physics (VehicleController hands the config's Transmission to the
-- drive model when you take the driver's seat), so engine and handling numbers are read on your side.
-- Health and damage stay on the server. Vehicle machine guns use the weapon configs, so Gun mods cover them.

do
    -- Two cards, two switches: the drive sliders count only while Drive mods is on, traverse only while Turret is
    local Mods = {DriveOn = false, TurretOn = false, Power = 1, TopSpeed = 1, Brakes = 1, Grip = 1, Steering = 1, Throttle = 1, Swim = 1, Traverse = 1}

    -- Which slider each Transmission value follows. Cars and tracked vehicles name their grip and brakes
    -- differently, so both sets are listed; a vehicle only has its own.
    local Fields = {
        PeakTorque = "Power", IdleTorque = "Power", RedlineTorque = "Power", HorsepowerLimit = "Power",
        TopSpeed = "TopSpeed",
        BrakeDecel = "Brakes", BrakeMultiplier = "Brakes", HandBrakeMultiplier = "Brakes",
        TrackMu = "Grip", LateralMu = "Grip", LateralGrip = "Grip", PeakGrip = "Grip", SlideGrip = "Grip", Grip = "Grip", DriftGrip = "Grip",
        SteerSpeed = "Steering", SteerGain = "Steering", SteerDeltaSpeed = "Steering"
    }

    -- These get smaller as the slider goes up: a tighter turn and a shorter wait for full throttle
    local Inverse = {TurnRadius = "Steering", ThrottleRampTime = "Throttle"}
    local SwimFields = {"Speed", "ReverseSpeed", "TurnRate"}

    local Originals = setmetatable({}, {__mode = "k"})
    local Configs

    local function FindConfigs()
        local List, Seen = {}, {}

        local function Add(Config)
            local Transmission = type(Config) == "table" and rawget(Config, "Transmission")

            if type(Transmission) == "table" and rawget(Transmission, "TopSpeed") ~= nil and not Seen[Config] then
                Seen[Config] = true
                table.insert(List, Config)
            end
        end

        if getgc then
            for _, Value in next, getgc(true) do
                if type(Value) == "table" then
                    Add(Value)
                end
            end
        end

        -- The manager's own list (team -> class -> vehicle), in case getgc isn't there
        local Manager = Require(Shared and Shared:FindFirstChild("VehicleConfigManager"))
        local Ok, All = pcall(function() return Manager.GetAllVehicles() end)

        if Ok and type(All) == "table" then
            for _, Classes in next, All do
                for _, Vehicles in next, type(Classes) == "table" and Classes or {} do
                    for _, Config in next, type(Vehicles) == "table" and Vehicles or {} do
                        Add(Config)
                    end
                end
            end
        end

        return List
    end

    local function Get(Key)
        local On = if Key == "Traverse" then Mods.TurretOn else Mods.DriveOn
        return On and Mods[Key] or 1
    end

    local function Remember(Config)
        local Saved = Originals[Config]

        if Saved then
            return Saved
        end

        Saved = {Drive = {}, Swim = nil, Turrets = {}}

        for Key, Value in next, Config.Transmission do
            if (Fields[Key] or Inverse[Key]) and type(Value) == "number" then
                Saved.Drive[Key] = Value
            end
        end

        local Swim = type(Config.Water) == "table" and Config.Water.Swim

        if type(Swim) == "table" then
            Saved.Swim = {}

            for _, Key in next, SwimFields do
                Saved.Swim[Key] = Swim[Key]
            end
        end

        for _, Turret in next, type(Config.Turrets) == "table" and Config.Turrets or {} do
            if type(Turret) == "table" then
                Saved.Turrets[Turret] = {YawSpeed = Turret.YawSpeed, PitchSpeed = Turret.PitchSpeed}
            end
        end

        Originals[Config] = Saved
        return Saved
    end

    local function Apply()
        Configs = Configs or FindConfigs()

        for _, Config in next, Configs do
            local Saved = Remember(Config)

            pcall(function()
                for Key, Original in next, Saved.Drive do
                    local Multiplier = Get(Fields[Key] or Inverse[Key])
                    Config.Transmission[Key] = Inverse[Key] and Original / Multiplier or Original * Multiplier
                end

                if Saved.Swim then
                    for Key, Original in next, Saved.Swim do
                        if type(Original) == "number" then
                            Config.Water.Swim[Key] = Original * Get("Swim")
                        end
                    end
                end

                for Turret, Original in next, Saved.Turrets do
                    for Key, Value in next, Original do
                        if type(Value) == "number" then
                            Turret[Key] = Value * Get("Traverse")
                        end
                    end
                end
            end)
        end

        return #Configs
    end

    -- Switching a card off puts its values back; nothing to do if no config was ever touched
    local function Refresh()
        if Configs or Mods.DriveOn or Mods.TurretOn then
            Apply()
        end
    end

    local function Restore()
        Mods.DriveOn, Mods.TurretOn = false, false
        Refresh()
    end

    local function Percent(Key)
        return function(Value)
            Mods[Key] = Value / 100
            Refresh()
        end
    end

    local Drive = DriveTab:Module({
        Title = "Drive mods",
        Description = "100% is stock. Re-enter the driver's seat after changing.",
        Icon = "gauge",
        Side = "Left",
        Risky = true,
        Default = false,
        Flag = "Vehicle.Drive",
        Keybind = false,
        Opened = true,
        Callback = function(Enabled)
            Mods.DriveOn = Enabled
            Refresh()
        end
    })

    local Engine = Drive:Group({Title = "Engine", Icon = "zap", Opened = true})
    Engine:Slider({Title = "Engine power", Min = 100, Max = 1000, Step = 25, Default = 100, Suffix = "%", Buttons = true, Flag = "Vehicle.Power", Tooltip = "Pulls harder at every speed.", Callback = Percent("Power")})
    Engine:Slider({Title = "Top speed", Min = 100, Max = 600, Step = 10, Default = 100, Suffix = "%", Buttons = true, Flag = "Vehicle.TopSpeed", Tooltip = "Risky. Easy for the server to notice.", Callback = Percent("TopSpeed")})
    Engine:Slider({Title = "Throttle response", Min = 100, Max = 1000, Step = 25, Default = 100, Suffix = "%", Buttons = true, Flag = "Vehicle.Throttle", Tooltip = "Faster acceleration on tracked vehicles.", Callback = Percent("Throttle")})

    local Handling = Drive:Group({Title = "Handling", Icon = "navigation", Opened = true})
    Handling:Slider({Title = "Brakes", Min = 100, Max = 1000, Step = 25, Default = 100, Suffix = "%", Buttons = true, Flag = "Vehicle.Brakes", Callback = Percent("Brakes")})
    Handling:Slider({Title = "Grip", Min = 100, Max = 500, Step = 10, Default = 100, Suffix = "%", Buttons = true, Flag = "Vehicle.Grip", Tooltip = "Less sliding in corners. Too much grip can tip a light car over.", Callback = Percent("Grip")})
    Handling:Slider({Title = "Steering", Min = 100, Max = 500, Step = 10, Default = 100, Suffix = "%", Buttons = true, Flag = "Vehicle.Steering", Tooltip = "Faster steering and a tighter turning circle.", Callback = Percent("Steering")})
    Handling:Slider({Title = "Swim speed", Min = 100, Max = 1000, Step = 25, Default = 100, Suffix = "%", Buttons = true, Flag = "Vehicle.Swim", Tooltip = "Amphibious vehicles only (M113, MT-LB), in the water.", Callback = Percent("Swim")})

    local Turret = TurretTab:Module({
        Title = "Turret",
        Description = "Faster turning on mounted guns.",
        Icon = "crosshair",
        Side = "Left",
        Default = false,
        Flag = "Vehicle.Turret",
        Keybind = false,
        Opened = true,
        Callback = function(Enabled)
            Mods.TurretOn = Enabled
            Refresh()
        end
    })

    Turret:Slider({Title = "Traverse speed", Min = 100, Max = 1500, Step = 25, Default = 100, Suffix = "%", Buttons = true, Flag = "Vehicle.Traverse", Tooltip = "How fast the gun turns and elevates.", Callback = Percent("Traverse")})

    OasisUI:OnUnload(Restore)
end

--// Medic: treat wounded teammates from range

do
    local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local Running = true

    local function Remote(Name)
        return Remotes and Remotes:FindFirstChild(Name)
    end

    local function MyRoot()
        local Character = Player.Character
        return Character and Character:FindFirstChild("HumanoidRootPart")
    end

    --// Medic: Remotes.MedicBag:FireServer(character, true) starts treating someone and (character, false)
    -- stops. The bag only offers it within 7 studs; this picks the nearest wounded teammate in your range.

    local Medic = {Enabled = false, Range = 50}
    local Healing -- the character being treated right now

    local function HoldingMedicBag()
        local Character = Player.Character
        local Tool = Character and Character:FindFirstChildOfClass("Tool")
        return Tool ~= nil and Tool.Name:lower():find("medic") ~= nil
    end

    local function Wounded(Character)
        local Humanoid = Character:FindFirstChildOfClass("Humanoid")
        return Humanoid ~= nil and Humanoid.Health > 0 and Humanoid.Health < Humanoid.MaxHealth - 0.5
    end

    local function PickPatient()
        local Root = MyRoot()
        local Best, BestDistance = nil, Medic.Range

        if not Root then
            return nil
        end

        for _, Other in next, Players:GetPlayers() do
            local Character = Other ~= Player and Other.Team ~= nil and Other.Team == Player.Team and Other.Character
            local TheirRoot = Character and Character:FindFirstChild("HumanoidRootPart")

            if TheirRoot and Wounded(Character) then
                local Distance = (TheirRoot.Position - Root.Position).Magnitude

                if Distance <= BestDistance then
                    Best, BestDistance = Character, Distance
                end
            end
        end

        return Best
    end

    local function SetPatient(Character)
        if Character == Healing then
            return
        end

        local Bag = Remote("MedicBag")

        if Bag and Healing then
            pcall(Bag.FireServer, Bag, Healing, false)
        end

        Healing = Character

        if Bag and Character then
            pcall(Bag.FireServer, Bag, Character, true)
        end
    end

    -- Stay on the current patient while they're still hurt and still in range, so it doesn't flip between two
    local function StillTreating()
        local Root, TheirRoot = MyRoot(), Healing and Healing.Parent and Healing:FindFirstChild("HumanoidRootPart")
        return Root ~= nil and TheirRoot ~= nil and Wounded(Healing) and (TheirRoot.Position - Root.Position).Magnitude <= Medic.Range
    end

    local function UpdateMedic()
        local Keep = Healing and StillTreating() and Healing

        if Medic.Enabled and HoldingMedicBag() then
            SetPatient(Keep or PickPatient())
        else
            SetPatient(nil)
        end
    end

    --// Cards

    local MedicSection = SupportTab:Section({Title = "Medic", Icon = "heart-pulse", Side = "Left"})
    MedicSection:Toggle({
        Title = "Treat from range",
        Tooltip = "Hold the medic bag to heal the nearest wounded teammate in range.",
        Default = false,
        Flag = "Support.Medic",
        Callback = function(Value)
            Medic.Enabled = Value

            if not Value then
                SetPatient(nil)
            end
        end
    })
    MedicSection:Slider({Title = "Range", Min = 10, Max = 300, Step = 10, Default = 50, Suffix = " st", Flag = "Support.Medic.Range", Tooltip = "The bag's own reach is 7 studs.", Callback = function(Value) Medic.Range = Value end})
    local PatientLabel = MedicSection:Label({Text = "Treating", Value = "nobody"})

    task.spawn(function()
        while Running do
            pcall(function()
                UpdateMedic()
                local Patient = Healing and Players:GetPlayerFromCharacter(Healing)
                PatientLabel:SetValue(Patient and Patient.Name or "nobody")
            end)

            task.wait(0.5)
        end
    end)

    OasisUI:OnUnload(function()
        Running = false
        Medic.Enabled = false
        pcall(SetPatient, nil)
    end)
end

--// Extras: protection (no fall damage, anti-aim), team support (spotting, radio, revive, disguise),
-- match (votes, squad) and staff (alert, command list)

do
    local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local Running = true

    local function Remote(Name)
        return Remotes and Remotes:FindFirstChild(Name)
    end

    -- Our own sends go through FireServer directly, never __namecall, so the filter below never sees them
    local function Send(Target, ...)
        if not Target then
            return false
        end

        return pcall(Target.FireServer, Target, ...)
    end

    local function MyCharacter()
        return Player.Character
    end

    local function HeadOf(Character)
        return Character and (Character:FindFirstChild("Head") or Character:FindFirstChild("HumanoidRootPart"))
    end

    local function HeldTool(Pattern)
        local Character = MyCharacter()
        local Tool = Character and Character:FindFirstChildOfClass("Tool")
        return Tool and Tool.Name:lower():find(Pattern) and Tool or nil
    end

    local function SameTeam(Other)
        return Other ~= Player and Other.Team ~= nil and Other.Team == Player.Team
    end

    local function Enemy(Other)
        return Other ~= Player and Other.Team ~= nil and Player.Team ~= nil and Other.Team ~= Player.Team
    end

    local function IsDowned(Character)
        local Values = Character and Character:FindFirstChild("CharacterValues")
        local Flag = Values and Values:FindFirstChild("Unconscious")
        return Flag ~= nil and Flag.Value == true
    end

    local LineParams = RaycastParams.new()
    LineParams.FilterType = Enum.RaycastFilterType.Exclude
    LineParams.IgnoreWater = true

    -- Clear line from your head to theirs, ignoring you, the Ignore folder and the camera
    local function ClearLine(From, Character)
        local Head = HeadOf(Character)

        if not Head then
            return false
        end

        local List = {}

        for _, Object in next, {MyCharacter() or false, Workspace:FindFirstChild("Ignore") or false, Workspace.CurrentCamera or false} do
            if Object then
                table.insert(List, Object)
            end
        end

        LineParams.FilterDescendantsInstances = List
        local Result = Workspace:Raycast(From, Head.Position - From, LineParams)
        return Result == nil or Result.Instance:IsDescendantOf(Character)
    end

    --// Remote filter: drops the game's own sends we override. One namecall hook per session; the current
    -- script sets Filter, so re-running never stacks hooks.

    local RemoteHook = getgenv().SuperNovaFrontRemoteHook

    if not RemoteHook and hookmetamethod and getnamecallmethod then
        RemoteHook = {}
        getgenv().SuperNovaFrontRemoteHook = RemoteHook

        local wrap = newcclosure or function(Function) return Function end
        local OldNamecall

        OldNamecall = hookmetamethod(game, "__namecall", wrap(function(...)
            local Filter = RemoteHook.Filter

            if Filter and getnamecallmethod() == "FireServer" and not (checkcaller and checkcaller()) then
                local Ok, Drop = pcall(Filter, ...)

                if Ok and Drop then
                    return nil
                end
            end

            return OldNamecall(...)
        end))
    end

    local Protect = {NoFall = false, AntiAim = false, Local = true, Pitch = "Down", Lean = "Jitter", Yaw = "Spin", Rate = 15, FakePitch = nil, FakeYaw = nil}
    local Freefall, BodyRotation = Remote("Freefall"), Remote("BodyRotation")

    if RemoteHook then
        RemoteHook.Filter = function(Self)
            -- Looked up again if they weren't there when the script started
            Freefall = Freefall or Remote("Freefall")
            BodyRotation = BodyRotation or Remote("BodyRotation")

            return (Protect.NoFall and Self == Freefall) or (Protect.AntiAim and Self == BodyRotation) or false
        end
    end

    --// Anti-aim: BodyReplication streams your look as 5 bytes: pitch (u16, -pi..pi), lean (i8, -100..100),
    -- free aim (u8) and head yaw (i8, steps of 0.02 rad). With anti-aim on, the game's own sends are dropped
    -- and these fake ones go out on a timer instead (the game only sends when your camera moves).

    local function Packet(Pitch, Lean, Yaw)
        local Data = buffer.create(5)
        buffer.writeu16(Data, 0, math.clamp(math.round((Pitch + math.pi) / (2 * math.pi) * 65535), 0, 65535))
        buffer.writei8(Data, 2, math.clamp(math.round(Lean * 100), -100, 100))
        buffer.writeu8(Data, 3, 0)
        buffer.writei8(Data, 4, math.clamp(math.round(Yaw / 0.02), -127, 127))
        return Data
    end

    local function RealPitch()
        local Camera = Workspace.CurrentCamera
        return Camera and math.asin(math.clamp(Camera.CFrame.LookVector.Y, -1, 1)) or 0
    end

    task.spawn(function()
        local Flip, WasFaking = false, false

        while Running do
            BodyRotation = BodyRotation or Remote("BodyRotation")

            if Protect.AntiAim and BodyRotation then
                Flip = not Flip

                local Real = RealPitch()
                local Pitches = {Off = Real, Up = 1.45, Down = -1.45, Jitter = Flip and 1.45 or -1.45, Extreme = Flip and 3.1 or -3.1}
                local Leans = {Off = 0, Left = -1, Right = 1, Jitter = Flip and 1 or -1}
                local Yaws = {Off = 0, Backwards = 2.5, Jitter = Flip and 2.5 or -2.5, Spin = math.sin(os.clock() * 6) * 2.5}

                Send(BodyRotation, Packet(Pitches[Protect.Pitch] or Real, Leans[Protect.Lean] or 0, Yaws[Protect.Yaw] or 0))
                WasFaking = true

                -- Same angles for your own screen; "Off" leaves your real one showing
                Protect.FakePitch = Protect.Pitch ~= "Off" and Pitches[Protect.Pitch] or nil
                Protect.FakeYaw = Protect.Yaw ~= "Off" and Yaws[Protect.Yaw] or nil
            elseif WasFaking then
                -- Straighten up once; the game's own sends take over from here
                Send(BodyRotation, Packet(RealPitch(), 0, 0))
                WasFaking = false
            end

            task.wait(1 / Protect.Rate)
        end
    end)


    --// Anti-aim on your own screen: BodyReplication poses your character from an info table it rewrites every
    -- frame (stepRemotes: NewCameraAngle from the camera, NewCameraYaw from where you face). Those two keys are
    -- moved behind a metatable, so the game's writes land in a shadow copy and its reads get the fake angles
    -- while anti-aim is on. No frame-order race: it doesn't matter when the game writes or reads.
    -- Lean stays server-only: your lean value also tilts your own camera, so faking it would shake your view.

    local POSE_KEYS = {NewCameraAngle = true, NewCameraYaw = true}
    local Mirror = {Info = nil, Real = nil, Root = nil}

    local function FindInfo(Root)
        if not getgc then
            return nil
        end

        for _, Value in next, getgc(true) do
            if type(Value) == "table" and rawget(Value, "HumanoidRootPart") == Root and rawget(Value, "LeanGoalValue") ~= nil then
                return Value
            end
        end
    end

    local function Unwrap()
        local Info = Mirror.Info

        if Info and Mirror.Real then
            setmetatable(Info, nil)

            for Key in next, POSE_KEYS do
                rawset(Info, Key, Mirror.Real[Key])
            end
        end

        Mirror.Info, Mirror.Real = nil, nil
    end

    local function Wrap(Info)
        -- Something else already put a metatable on it: leave it alone rather than break that
        if getmetatable(Info) ~= nil then
            return false
        end

        local Real = {}

        for Key in next, POSE_KEYS do
            Real[Key] = rawget(Info, Key) or 0
            rawset(Info, Key, nil)
        end

        setmetatable(Info, {
            __index = function(_, Key)
                if POSE_KEYS[Key] then
                    local Fake = Protect.AntiAim and Protect.Local and (Key == "NewCameraAngle" and Protect.FakePitch or Key == "NewCameraYaw" and Protect.FakeYaw)
                    return Fake or Real[Key]
                end
            end,
            __newindex = function(Self, Key, Value)
                if POSE_KEYS[Key] then
                    Real[Key] = Value
                else
                    rawset(Self, Key, Value)
                end
            end
        })

        Mirror.Info, Mirror.Real = Info, Real
        return true
    end

    -- Finds your info table once per character (each respawn builds a new one); the memory scan only runs
    -- when your character changes, not every second
    task.spawn(function()
        local LastScan = 0

        while Running do
            pcall(function()
                local Character = MyCharacter()
                local Root = Character and Character:FindFirstChild("HumanoidRootPart")

                -- Right after a respawn the game may not have built the table yet, so a miss retries every 3 s
                if Protect.AntiAim and Protect.Local and Root then
                    if Mirror.Root ~= Root and os.clock() - LastScan >= 3 then
                        LastScan = os.clock()
                        Unwrap()

                        local Info = FindInfo(Root)

                        if Info and Wrap(Info) then
                            Mirror.Root = Root
                        end
                    end
                elseif Mirror.Info or Mirror.Root then
                    Unwrap()
                    Mirror.Root = nil
                end
            end)

            task.wait(1)
        end
    end)

    --// Spotting: binoculars send ("Spotting", look direction) and the server traces it from your head. With
    -- binoculars out, this sends a direction for each enemy you can see, one per second (the bag's cooldown).

    local Spot = {Enabled = false, Range = 3000}
    local SpotIndex = 0

    local function VisibleEnemies(Range)
        local Head = HeadOf(MyCharacter())
        local List = {}

        if not Head then
            return List, nil
        end

        for _, Other in next, Players:GetPlayers() do
            local Character = Enemy(Other) and Other.Character
            local Target = HeadOf(Character)

            if Target and not IsDowned(Character) and (Target.Position - Head.Position).Magnitude <= Range and ClearLine(Head.Position, Character) then
                table.insert(List, Character)
            end
        end

        return List, Head
    end

    local function SpotNext(Mode)
        local Binoculars = Remote("Binoculars")
        local Enemies, Head = VisibleEnemies(Spot.Range)

        if not (Binoculars and Head and #Enemies > 0) then
            return nil
        end

        -- Round-robin so everyone in view gets their turn
        SpotIndex = SpotIndex % #Enemies + 1
        local Target = Enemies[SpotIndex]
        Send(Binoculars, Mode or "Spotting", (HeadOf(Target).Position - Head.Position).Unit)
        return Target
    end

    --// Radio support: the radio sends ("Callout", support name) and the strike lands on your designated
    -- position. Command class binoculars designate instead of spotting.

    local function SupportNames()
        local Gui = Player:FindFirstChildOfClass("PlayerGui")
        local List = Gui and Gui:FindFirstChild("RadioGui")
        List = List and List:FindFirstChild("MainFrame")
        List = List and List:FindFirstChild("CallList")

        local Names = {}

        for _, Button in next, List and List:GetChildren() or {} do
            if Button:IsA("GuiButton") then
                table.insert(Names, Button.Name)
            end
        end

        if #Names == 0 then
            Names = {"Artillery", "Airstrike", "Recon"}
        end

        table.sort(Names)
        return Names
    end

    --// Revive: ("begin", player), a hold timed on the reviver's client (10 s, 3 s for medics), then
    -- ("complete", player) through BeingRevived

    local Revive = {Auto = false, Range = 60, Hold = 10}
    local Reviving = false

    local function NearestDowned()
        local Head = HeadOf(MyCharacter())
        local Best, BestDistance = nil, Revive.Range

        if not Head then
            return nil
        end

        for _, Other in next, Players:GetPlayers() do
            local Character = SameTeam(Other) and Other.Character
            local Target = HeadOf(Character)

            if Target and IsDowned(Character) then
                local Distance = (Target.Position - Head.Position).Magnitude

                if Distance <= BestDistance then
                    Best, BestDistance = Other, Distance
                end
            end
        end

        return Best
    end

    local function ReviveNearest(Quiet)
        if Reviving then
            return
        end

        local BeingRevived = Remote("BeingRevived")
        local Target = NearestDowned()

        if not (BeingRevived and Target) then
            return Quiet or Notify("Revive", "No downed teammate in range.", "Warning")
        end

        Reviving = true
        Send(BeingRevived, "begin", Target)
        task.wait(math.max(Revive.Hold, 0.2))

        if IsDowned(Target.Character) then
            Send(BeingRevived, "complete", Target)
        end

        Reviving = false

        if not Quiet then
            Notify("Revive", "Sent a revive for " .. Target.Name .. ". If they're still down, the server wants you next to them or wants the full hold.", "Info", 5)
        end
    end

    --// Disguise: enemy corpses lie in workspace.Ignore with CorpseTeam and CorpseId; the spy's tool sends
    -- Disguise(CorpseId) for one within 15 studs that you're looking at

    local function NearestEnemyCorpse()
        local Head = HeadOf(MyCharacter())
        local Ignore = Workspace:FindFirstChild("Ignore")
        local Team = Player.Team and Player.Team.Name
        local Best, BestDistance

        for _, Corpse in next, Ignore and Ignore:GetChildren() or {} do
            if Corpse:IsA("Model") and Corpse.Name:find("Corpse") and Corpse:GetAttribute("CorpseTeam") ~= Team and type(Corpse:GetAttribute("CorpseId")) == "number" then
                local Root = Corpse:FindFirstChild("HumanoidRootPart")
                local Distance = (Root and Head) and (Root.Position - Head.Position).Magnitude or math.huge

                if not BestDistance or Distance < BestDistance then
                    Best, BestDistance = Corpse, Distance
                end
            end
        end

        return Best, BestDistance
    end

    --// Cards: Combat > Support

    local SpotSection = SupportTab:Section({Title = "Spotting", Icon = "eye", Side = "Right"})
    SpotSection:Toggle({Title = "Auto-spot", Tooltip = "Hold binoculars to spot every enemy in view for your team.", Default = false, Flag = "Support.Spot", Callback = function(Value) Spot.Enabled = Value end})
    SpotSection:Slider({Title = "Range", Min = 100, Max = 5000, Step = 100, Default = 3000, Suffix = " st", Flag = "Support.Spot.Range", Callback = function(Value) Spot.Range = Value end})

    local RadioSection = SupportTab:Section({Title = "Radio", Icon = "radio", Side = "Right"})

    local SupportPick
    SupportPick = RadioSection:Dropdown({
        Title = "Support",
        Values = SupportNames(),
        AllowNone = true,
        Action = {Icon = "refresh-cw", Tooltip = "Refresh", Callback = function() SupportPick:Refresh(SupportNames(), true) end}
    })

    RadioSection:Buttons({
        {Title = "Designate nearest enemy", Icon = "crosshair", Callback = function()
            local Target = SpotNext("Designate")
            local Who = Target and Players:GetPlayerFromCharacter(Target)
            Notify("Radio", Who and ("Designated " .. Who.Name .. ".") or "No enemy in view, or no Binoculars remote.", Who and "Info" or "Warning")
        end},
        {Title = "Call support", Icon = "radio", Style = "Primary", Callback = function()
            local Name = SupportPick:Get()

            if not Name then
                return Notify("Radio", "Pick a support first.", "Warning")
            end

            local Ok = Send(Remote("Radio"), "Callout", Name)
            Notify("Radio", Ok and ("Called " .. Name .. ". If nothing comes, you need the radio class or a designation.") or "No Radio remote.", Ok and "Info" or "Error", 5)
        end}
    })

    local ReviveSection = SupportTab:Section({Title = "Revive", Icon = "heart-pulse", Side = "Left"})
    ReviveSection:Button({Title = "Revive nearest", Icon = "heart-pulse", Style = "Primary", Callback = function()
        task.spawn(ReviveNearest, false)
    end})
    ReviveSection:Toggle({Title = "Auto-revive", Tooltip = "Revives downed teammates in range one after another.", Default = false, Flag = "Support.Revive.Auto", Callback = function(Value) Revive.Auto = Value end})
    ReviveSection:Slider({Title = "Range", Min = 10, Max = 500, Step = 10, Default = 60, Suffix = " st", Flag = "Support.Revive.Range", Callback = function(Value) Revive.Range = Value end})
    ReviveSection:Slider({Title = "Hold time", Min = 0, Max = 10, Step = 0.5, Default = 10, Suffix = " s", Flag = "Support.Revive.Hold", Tooltip = "Normal is 10 s (3 s as medic).", Callback = function(Value) Revive.Hold = Value end})

    local DisguiseSection = SupportTab:Section({Title = "Disguise", Icon = "shirt", Side = "Left"})
    DisguiseSection:Button({Title = "Disguise (nearest body)", Icon = "shirt", Callback = function()
        local Corpse, Distance = NearestEnemyCorpse()

        if not Corpse then
            return Notify("Disguise", "No enemy body is loaded in.", "Warning")
        end

        local Ok = Send(Remote("Disguise"), Corpse:GetAttribute("CorpseId"))
        Notify("Disguise", Ok and ("Asked for the uniform off a body %dm away."):format(math.floor((Distance or 0) / 3.57)) or "No Disguise remote.", Ok and "Info" or "Error")
    end})

    --// Cards: Misc > Protection

    local Fall = MoveTab:Section({Title = "Falling", Icon = "arrow-down", Side = "Right"})
    Fall:Toggle({Title = "No fall damage", Tooltip = "No damage from falling.", Default = false, Flag = "Protect.NoFall", Callback = function(Value)
        Protect.NoFall = Value

        if Value and not RemoteHook then
            Notify("No fall damage", "This executor has no hookmetamethod, so the report can't be dropped.", "Error")
        end
    end})

    local AntiAim = AntiAimTab:Module({
        Title = "Anti-aim",
        Description = "Other players see you bent over, leaning and spinning. Your camera doesn't change.",
        Icon = "orbit",
        Side = "Left",
        Risky = true,
        Default = false,
        Flag = "Protect.AntiAim",
        Keybind = {Key = nil, Mode = "Toggle"},
        Opened = true,
        Callback = function(Enabled)
            Protect.AntiAim = Enabled

            if Enabled and not RemoteHook then
                Notify("Anti-aim", "No hookmetamethod: your real angles still go out between the fake ones.", "Warning")
            end
        end
    })

    AntiAim:Dropdown({Title = "Pitch", Values = {"Off", "Up", "Down", "Jitter", "Extreme"}, Default = "Down", Flag = "Protect.AntiAim.Pitch", Tooltip = "Extreme bends past straight up and down; the server may clamp it.", Callback = function(Value) Protect.Pitch = Value end})
    AntiAim:Dropdown({Title = "Lean", Values = {"Off", "Left", "Right", "Jitter"}, Default = "Jitter", Flag = "Protect.AntiAim.Lean", Tooltip = "Lean moves your whole upper body, head included.", Callback = function(Value) Protect.Lean = Value end})
    AntiAim:Dropdown({Title = "Head turn", Values = {"Off", "Spin", "Jitter", "Backwards"}, Default = "Spin", Flag = "Protect.AntiAim.Yaw", Callback = function(Value) Protect.Yaw = Value end})
    AntiAim:Checkbox({Title = "Show on my character", Tooltip = "Shows the fake angles on your character too. Shoot in first person.", Default = true, Flag = "Protect.AntiAim.Local", Callback = function(Value) Protect.Local = Value end})
    AntiAim:Slider({Title = "Updates per second", Min = 5, Max = 30, Step = 1, Default = 15, Flag = "Protect.AntiAim.Rate", Tooltip = "Higher jitters faster. Very high may get rate-limited.", Callback = function(Value) Protect.Rate = Value end})

    --// Cards: Misc > Match

    local Vote = {Auto = false, Map = "", Spam = false, GameIndex = 0}
    local Voted = {} -- vote kind -> what we last voted this round

    local function VoteFrames()
        local Gui = Player:FindFirstChildOfClass("PlayerGui")
        local Match = Gui and Gui:FindFirstChild("MatchGui")
        return Match and Match:FindFirstChild("MapVoteFrame"), Match and Match:FindFirstChild("GameVoteFrame"), Match
    end

    local function Showing(Frame, Root)
        return Frame ~= nil and Frame.Visible and (not Root:IsA("ScreenGui") or Root.Enabled)
    end

    local function UpdateVotes()
        local MapFrame, GameFrame, Root = VoteFrames()
        local Match = Remote("Match")

        if not (Match and Root) then
            return
        end

        local Options = MapFrame and MapFrame:FindFirstChild("VotingOptions")

        if Vote.Auto and Vote.Map ~= "" and Showing(MapFrame, Root) and Options then
            for _, Option in next, Options:GetChildren() do
                if Option:IsA("GuiButton") and Option.Visible and Option.Name:lower():find(Vote.Map:lower(), 1, true) then
                    if Vote.Spam or Voted.Map ~= Option.Name then
                        Send(Match, "MapVote", Option.Name)
                        Voted.Map = Option.Name
                    end

                    break
                end
            end
        elseif not Showing(MapFrame, Root) then
            Voted.Map = nil
        end

        if Vote.Auto and Vote.GameIndex > 0 and Showing(GameFrame, Root) then
            if Vote.Spam or Voted.Game ~= Vote.GameIndex then
                Send(Match, "GameVote", Vote.GameIndex)
                Voted.Game = Vote.GameIndex
            end
        elseif not Showing(GameFrame, Root) then
            Voted.Game = nil
        end
    end

    local Votes = MatchTab:Section({Title = "Votes", Icon = "vote", Side = "Left"})
    Votes:Toggle({Title = "Auto-vote", Tooltip = "Votes for your map (and game mode) the moment voting opens.", Default = false, Flag = "Match.AutoVote", Callback = function(Value) Vote.Auto = Value end})
    -- Map names come from the admin command list (its map argument) plus whatever is on the vote screen now
    local function MapNames()
        local Names, Seen = {}, {}

        local function Add(Name)
            if type(Name) == "string" and Name ~= "" and not Seen[Name] then
                Seen[Name] = true
                table.insert(Names, Name)
            end
        end

        local Commands = Require(Shared and Shared:FindFirstChild("ControlPanelCommands"))
        local Known = type(Commands) == "table" and Commands.MapNames

        for Key, Value in next, type(Known) == "table" and Known or {} do
            Add(type(Key) == "string" and Key or Value)
        end

        local MapFrame = VoteFrames()
        local Options = MapFrame and MapFrame:FindFirstChild("VotingOptions")

        for _, Option in next, Options and Options:GetChildren() or {} do
            if Option:IsA("GuiButton") then
                Add(Option.Name)
            end
        end

        table.sort(Names)
        return Names
    end

    local MapPick
    MapPick = Votes:Dropdown({
        Title = "Map",
        Values = MapNames(),
        Search = true,
        AllowNone = true,
        Flag = "Match.AutoVote.Map",
        Action = {Icon = "refresh-cw", Tooltip = "Refresh", Callback = function() MapPick:Refresh(MapNames(), true) end},
        Callback = function(Value) Vote.Map = type(Value) == "string" and Value or "" end
    })
    Votes:Slider({Title = "Game mode card", Min = 0, Max = 4, Step = 1, Default = 0, Flag = "Match.AutoVote.Game", Tooltip = "Counting from the left. 0 is off.", Callback = function(Value) Vote.GameIndex = Value end})
    Votes:Checkbox({Title = "Vote repeatedly", Tooltip = "Resends your vote every second.", Default = false, Flag = "Match.AutoVote.Spam", Callback = function(Value) Vote.Spam = Value end})

    --// Cards: Misc > Staff

    -- PrivateAttributes holds every player's role as Role_<UserId> (Role_n<id> for negative ids, plain Role for
    -- you); the freecam script also lets anyone ranked 100+ in group 32519006 in
    local STAFF_GROUP, STAFF_RANK = 32519006, 100
    local Staff = {Alert = true, Leave = false}
    local StaffHere = {} -- player -> what makes them staff

    local function RoleOf(Other)
        local Folder = PrivateAttributes()
        local Key = Other == Player and "Role" or (Other.UserId < 0 and ("Role_n" .. -Other.UserId) or ("Role_" .. Other.UserId))
        return Folder and Folder:GetAttribute(Key) or "Player"
    end

    local StaffLabel

    local function RefreshStaffLabel()
        local Names = {}

        for Other, Why in next, StaffHere do
            table.insert(Names, ("%s (%s)"):format(Other.Name, Why))
        end

        table.sort(Names)
        StaffLabel:SetValue(#Names > 0 and table.concat(Names, ", ") or "none")
        StaffLabel:SetValueColor(#Names > 0 and "Error" or "Success")
    end

    local function CheckStaff(Other, Joined)
        if Other == Player or not Other.Parent then
            return
        end

        local Role = RoleOf(Other)
        local Why = (Role == "Owner" or Role == "Admin" or Role == "Granted") and Role:lower() or nil

        if not Why then
            -- A web call: slow or failing means not staff
            local Ok, Rank = pcall(Other.GetRankInGroup, Other, STAFF_GROUP)
            Why = Ok and tonumber(Rank) and Rank >= STAFF_RANK and ("group rank " .. Rank) or nil
        end

        local Was = StaffHere[Other]
        StaffHere[Other] = Why

        if Why and not Was then
            RefreshStaffLabel()

            if Staff.Alert then
                Notify("Staff", ("%s is staff (%s) and %s. Staff can see your shots and go invisible."):format(Other.Name, Why, Joined and "just joined" or "is in this server"), "Error", 12)
            end

            if Staff.Leave then
                Leave.Handler("SuperNova: left because staff (" .. Other.Name .. ") is in the server.")
            end
        elseif Was and not Why then
            RefreshStaffLabel()
        end
    end

    local StaffSection = StaffTab:Section({Title = "Staff", Icon = "shield-alert", Side = "Left"})
    StaffSection:Toggle({Title = "Staff alert", Tooltip = "Includes invisible staff.", Default = true, Flag = "Staff.Alert", Callback = function(Value) Staff.Alert = Value end})
    StaffSection:Toggle({Title = "Leave when staff joins", Tooltip = "Disconnects you the moment staff is in the server.", Default = false, Flag = "Staff.Leave", Callback = function(Value)
        Staff.Leave = Value

        if Value and next(StaffHere) then
            Leave.Handler("SuperNova: left because staff is in the server.")
        end
    end})
    StaffLabel = StaffSection:Label({Text = "Staff in server", Value = "checking...", ValueColor = "Success"})
    Leave.Section = StaffSection -- the Match block adds "hop instead of leaving" here

    --// Loops and signals

    local Connections = {}

    task.spawn(function()
        for _, Other in next, Players:GetPlayers() do
            task.spawn(CheckStaff, Other, false)
        end

        task.wait(3)
        RefreshStaffLabel()
    end)

    table.insert(Connections, Players.PlayerAdded:Connect(function(Other)
        CheckStaff(Other, true)
    end))

    table.insert(Connections, Players.PlayerRemoving:Connect(function(Other)
        if StaffHere[Other] then
            StaffHere[Other] = nil
            RefreshStaffLabel()
        end
    end))

    -- Roles can be granted mid-match
    task.spawn(function()
        local Folder = Player:WaitForChild("PlayerGui"):WaitForChild("PrivateAttributes", 30)

        if Folder and Running then
            table.insert(Connections, Folder.AttributeChanged:Connect(function(Name)
                if Name:sub(1, 5) == "Role_" then
                    for _, Other in next, Players:GetPlayers() do
                        task.spawn(CheckStaff, Other, false)
                    end
                end
            end))
        end
    end)

    task.spawn(function()
        local LastSpot = 0

        while Running do
            pcall(function()
                if Spot.Enabled and os.clock() - LastSpot >= 1.05 and HeldTool("binocular") then
                    LastSpot = os.clock()
                    SpotNext("Spotting")
                end

                if Revive.Auto and not Reviving then
                    task.spawn(ReviveNearest, true)
                end

                UpdateVotes()
            end)

            task.wait(1)
        end
    end)

    OasisUI:OnUnload(function()
        Running = false
        Protect.NoFall, Protect.AntiAim = false, false
        Spot.Enabled, Revive.Auto, Vote.Auto = false, false, false
        pcall(Unwrap)

        if RemoteHook then
            RemoteHook.Filter = nil
        end

        for _, Connection in next, Connections do
            Connection:Disconnect()
        end
    end)
end

--// Final pass: movement, clarity, intel, debug and match extras found on the last sweep of the client code

do
    local CollectionService = game:GetService("CollectionService")
    local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local Running = true
    local Connections = {}

    local function Remote(Name)
        return Remotes and Remotes:FindFirstChild(Name)
    end

    local function Enemy(Other)
        return Other ~= Player and Other.Team ~= nil and Player.Team ~= nil and Other.Team ~= Player.Team
    end

    -- Live module tables, found by shape: the executor's require can hand back a fresh copy the game never reads
    local function FindTables(Test)
        local Found = {}

        if not getgc then
            return Found
        end

        for _, Value in next, getgc(true) do
            if type(Value) == "table" then
                local Ok, Match = pcall(Test, Value)

                if Ok and Match then
                    table.insert(Found, Value)
                end
            end
        end

        return Found
    end

    -- Where a function was written, e.g. "ReplicatedStorage.Client.GGCameraShaker"
    local function SourceOf(Function)
        local Ok, Source = pcall(debug.info, Function, "s")
        return Ok and tostring(Source) or ""
    end

    local function CharacterValue(Name)
        local Character = Player.Character
        local Values = Character and Character:FindFirstChild("CharacterValues")
        return Values and Values:FindFirstChild(Name)
    end

    --//==================== Movement ====================

    -- StanceState.WALK_SPEED = {Run = 22, Walk = 10, Crouch = 8, Prone = 4}; MovementTuning reads it every frame
    local Move = {Active = false, Run = 1, Walk = 1, Crouch = 1, Prone = 1, NoJumpCooldown = false}
    local SpeedTables, SpeedOriginals = nil, setmetatable({}, {__mode = "k"})

    local function ApplySpeeds()
        SpeedTables = SpeedTables or FindTables(function(Table)
            -- The offsets table has the same keys but zeros and negatives, so Run must be a real speed; and our
            -- own settings table (Move) has these keys too, so it's ruled out by name
            return Table ~= Move and rawget(Table, "Active") == nil and type(rawget(Table, "Run")) == "number" and rawget(Table, "Run") > 1.5 and type(rawget(Table, "Walk")) == "number"
                and type(rawget(Table, "Crouch")) == "number" and type(rawget(Table, "Prone")) == "number" and rawget(Table, "Prone") > 0
        end)

        for _, Table in next, SpeedTables do
            local Saved = SpeedOriginals[Table]

            if not Saved then
                Saved = {Run = Table.Run, Walk = Table.Walk, Crouch = Table.Crouch, Prone = Table.Prone}
                SpeedOriginals[Table] = Saved
            end

            for Stance, Original in next, Saved do
                Table[Stance] = Original * (Move.Active and Move[Stance] or 1)
            end
        end
    end

    local SpeedCard = MoveTab:Module({
        Title = "Movement speed",
        Description = "100% is stock. Keep it modest, the server watches movement.",
        Icon = "footprints",
        Side = "Left",
        Risky = true,
        Default = false,
        Flag = "Movement.Speed",
        Keybind = {Key = nil, Mode = "Toggle"},
        Opened = true,
        Callback = function(Enabled)
            Move.Active = Enabled

            if Enabled or SpeedTables then
                ApplySpeeds()
            end
        end
    })

    for _, Stance in next, {"Run", "Walk", "Crouch", "Prone"} do
        SpeedCard:Slider({Title = Stance, Min = 100, Max = 300, Step = 5, Default = 100, Suffix = "%", Buttons = true, Flag = "Movement.Speed." .. Stance, Callback = function(Value)
            Move[Stance] = Value / 100

            if Move.Active then
                ApplySpeeds()
            end
        end})
    end


    -- StanceController switches jumping off for 1 s after every jump; this switches it back on
    MoveTab:Section({Title = "Jumping", Icon = "arrow-up", Side = "Right"}):Toggle({Title = "No jump cooldown", Tooltip = "Jump again right away instead of waiting a second.", Default = false, Flag = "Movement.NoJumpCooldown", Callback = function(Value) Move.NoJumpCooldown = Value end})

    local function WatchJumps(Character)
        local Humanoid = Character:WaitForChild("Humanoid", 10)

        if not Humanoid then
            return
        end

        table.insert(Connections, Humanoid.StateChanged:Connect(function(_, New)
            if Move.NoJumpCooldown and (New == Enum.HumanoidStateType.Jumping or New == Enum.HumanoidStateType.Landed) then
                -- After the game's own handler has turned it off
                task.delay(0.05, function()
                    if Move.NoJumpCooldown and Humanoid.Parent then
                        Humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
                    end
                end)
            end
        end))
    end

    if Player.Character then
        task.spawn(WatchJumps, Player.Character)
    end

    table.insert(Connections, Player.CharacterAdded:Connect(WatchJumps))

    --//==================== Clarity ====================

    local Clear = {NoShake = false, NoDeafen = false, NoSway = false, Weather = false, WeatherChoice = "Sunny"}

    -- Camera shake: GGCameraShaker.Shake (explosions) and CameraShakeModule.Shake (getting hit). Both are looked
    -- up fresh on every call, so swapping the function on the live module table stops every shake.
    local ShakePatches = nil -- {Table, Original}

    local function SetShake(Off)
        if Off and not ShakePatches then
            ShakePatches = {}

            for _, Table in next, FindTables(function(Table)
                local Shake = rawget(Table, "Shake")
                local Source = type(Shake) == "function" and SourceOf(Shake) or ""
                return Source:find("GGCameraShaker") or Source:find("CameraShakeModule")
            end) do
                table.insert(ShakePatches, {Table = Table, Original = Table.Shake})
                Table.Shake = function() end
            end
        elseif not Off and ShakePatches then
            for _, Patch in next, ShakePatches do
                Patch.Table.Shake = Patch.Original
            end

            ShakePatches = nil
        end
    end

    -- Deafening: explosions raise CharacterValues.Deafening on your client, which muffles your hearing
    local DeafenWatch = {}

    local function WatchDeafening()
        local Value = CharacterValue("Deafening")

        for Watched, Connection in next, DeafenWatch do
            if Watched ~= Value then
                Connection:Disconnect()
                DeafenWatch[Watched] = nil
            end
        end

        if Value and not DeafenWatch[Value] then
            DeafenWatch[Value] = Value:GetPropertyChangedSignal("Value"):Connect(function()
                if Clear.NoDeafen and Value.Value > 0 then
                    Value.Value = 0
                end
            end)
        end

        if Value and Clear.NoDeafen and Value.Value > 0 then
            Value.Value = 0
        end
    end

    -- Sway: WeaponViewmodel keeps {sway = spring} per equipped gun, writes its Target, reads its Position and
    -- calls :update(dt). In first person shots leave from the viewmodel's muzzle, so a still viewmodel is also a
    -- straighter shot. The spring is swapped for one that never moves.
    local SwapSway = setmetatable({}, {__mode = "k"}) -- holder -> real spring

    local function StillSpring(Real)
        return {Target = Vector3.zero, Position = Vector3.zero, Velocity = Vector3.zero, Mass = rawget(Real, "Mass") or 2, update = function() end}
    end

    local function SetSway(Off)
        if Off then
            for _, Holder in next, FindTables(function(Table)
                local Spring = rawget(Table, "sway")
                return type(Spring) == "table" and Spring.Position ~= nil and not SwapSway[Table]
            end) do
                SwapSway[Holder] = Holder.sway
                Holder.sway = StillSpring(Holder.sway)
            end
        else
            for Holder, Real in next, SwapSway do
                Holder.sway = Real
            end

            table.clear(SwapSway)
        end
    end

    -- Each equip builds a new holder, so look again a moment after a tool comes out
    local function WatchTools(Character)
        table.insert(Connections, Character.ChildAdded:Connect(function(Child)
            if Clear.NoSway and Child:IsA("Tool") then
                task.delay(0.5, function()
                    if Clear.NoSway then
                        SetSway(true)
                    end
                end)
            end
        end))
    end

    if Player.Character then
        WatchTools(Player.Character)
    end

    table.insert(Connections, Player.CharacterAdded:Connect(WatchTools))

    -- Weather: WeatherClient follows workspace.Match's Weather attribute; set on your side, it only changes yours
    local Match = Workspace:FindFirstChild("Match")
    local ServerWeather = Match and Match:GetAttribute("Weather")

    local function ApplyWeather()
        if not Match then
            return
        end

        if Clear.Weather then
            if Match:GetAttribute("Weather") ~= Clear.WeatherChoice then
                Match:SetAttribute("Weather", Clear.WeatherChoice)
            end
        elseif ServerWeather ~= nil and Match:GetAttribute("Weather") ~= ServerWeather then
            Match:SetAttribute("Weather", ServerWeather)
        end
    end

    if Match then
        table.insert(Connections, Match:GetAttributeChangedSignal("Weather"):Connect(function()
            local Now = Match:GetAttribute("Weather")

            -- Anything that isn't our own forced value came from the server
            if not (Clear.Weather and Now == Clear.WeatherChoice) then
                ServerWeather = Now

                if Clear.Weather then
                    ApplyWeather()
                end
            end
        end))
    end

    local View = ClarityTab:Section({Title = "Camera and sound", Icon = "camera", Side = "Right"})
    View:Toggle({Title = "No camera shake", Tooltip = "Explosions and hits stop shaking your camera.", Default = false, Flag = "Clarity.NoShake", Callback = function(Value)
        Clear.NoShake = Value
        task.spawn(SetShake, Value)
    end})
    View:Toggle({Title = "No deafening", Tooltip = "Explosions no longer muffle your hearing.", Default = false, Flag = "Clarity.NoDeafen", Callback = function(Value) Clear.NoDeafen = Value end})
    GunsTab:Section({Title = "Weapon", Icon = "crosshair", Side = "Right"}):Toggle({Title = "No sway", Tooltip = "Also makes first-person shots land on your sights.", Default = false, Flag = "Clarity.NoSway", Callback = function(Value)
        Clear.NoSway = Value
        task.spawn(SetSway, Value)
    end})

    local Sky = WorldTab:Section({Title = "Weather", Icon = "cloud", Side = "Right"})
    local WeatherToggle = Sky:Toggle({Title = "Force weather", Tooltip = "Your screen only. Sunny clears rain, snow, fog and lightning.", Default = false, Flag = "Clarity.Weather", Callback = function(Value)
        Clear.Weather = Value
        ApplyWeather()
    end})
    Sky:Dropdown({Title = "Weather", Values = {"Sunny", "Cloudy", "Fog", "Raining", "Thunderstorm", "Snowing", "SnowStorm"}, Default = "Sunny", Flag = "Clarity.WeatherChoice", Callback = function(Value)
        Clear.WeatherChoice = Value or "Sunny"
        ApplyWeather()
    end}):DependsOn(WeatherToggle, nil, "Hide")

    --//==================== Intel ====================

    -- Every player carries ClassName, Kills, Deaths, DeviceType, and DisguiseName while disguised
    local Info = {Tags = false, Distance = 1000, Reveal = false, Footsteps = false, FootstepBoost = 3}

    local TagFolder = Instance.new("Folder")
    TagFolder.Name = "SuperNovaInfoTags"
    TagFolder.Parent = (gethui and gethui()) or game:GetService("CoreGui")

    local Tags = {}

    local function GetTag(Other)
        local Tag = Tags[Other]

        if not Tag then
            local Gui = Instance.new("BillboardGui")
            Gui.Size = UDim2.fromOffset(240, 30)
            Gui.StudsOffset = Vector3.new(0, -3.4, 0)
            Gui.AlwaysOnTop = true
            Gui.LightInfluence = 0

            local Label = Instance.new("TextLabel")
            Label.Size = UDim2.fromScale(1, 1)
            Label.BackgroundTransparency = 1
            Label.Font = Enum.Font.GothamBold
            Label.TextSize = 12
            Label.RichText = true
            Label.TextStrokeTransparency = 0.35
            Label.TextColor3 = Color3.fromRGB(235, 235, 235)
            Label.Parent = Gui

            Gui.Parent = TagFolder
            Tag = {Gui = Gui, Label = Label}
            Tags[Other] = Tag
        end

        return Tag
    end

    local function UpdateTags()
        local Seen = {}
        local Camera = Workspace.CurrentCamera

        if Info.Tags and Camera then
            for _, Other in next, Players:GetPlayers() do
                local Root = Enemy(Other) and Other.Character and Other.Character:FindFirstChild("HumanoidRootPart")

                if Root and (Root.Position - Camera.CFrame.Position).Magnitude <= Info.Distance then
                    local Kills, Deaths = tonumber(Other:GetAttribute("Kills")) or 0, tonumber(Other:GetAttribute("Deaths")) or 0
                    local Disguise = Other:GetAttribute("DisguiseName")
                    local Device = Other:GetAttribute("DeviceType")
                    local Tag = GetTag(Other)

                    Seen[Other] = true
                    Tag.Gui.Adornee = Root
                    Tag.Label.Text = ("%s  ·  %d/%d%s%s"):format(
                        tostring(Other:GetAttribute("ClassName") or "?"),
                        Kills, Deaths,
                        Device and ("  ·  " .. tostring(Device)) or "",
                        (Disguise and Disguise ~= "") and ('\n<font color="#ff6464">disguised as %s</font>'):format(tostring(Disguise)) or ""
                    )
                end
            end
        end

        for Other, Tag in next, Tags do
            if not Seen[Other] then
                Tag.Gui:Destroy()
                Tags[Other] = nil
            end
        end
    end

    -- Invisibility: a player with the Invisible attribute is hidden by your own client (InvisibleCharacters).
    -- Clearing it on your side shows them again, and it's a staff-only tool, so it also warns you.
    local Revealed = {}

    local function UpdateInvisible()
        for _, Other in next, Players:GetPlayers() do
            if Other ~= Player and Other:GetAttribute("Invisible") == true then
                if not Revealed[Other] then
                    Revealed[Other] = true
                    Notify("Staff", Other.Name .. " is invisible (a staff tool)." .. (Info.Reveal and " Showing them." or ""), "Error", 10)
                end

                if Info.Reveal then
                    Other:SetAttribute("Invisible", false)
                end
            elseif Revealed[Other] and Other:GetAttribute("Invisible") == nil then
                Revealed[Other] = nil
            end
        end
    end

    -- Footsteps: MovementSounds clones a "FootstepSound" into the stepping leg for every step, plays it and lets
    -- it go. Catching each one as it's parented means it plays boosted. Steps are only made within the sound's
    -- normal hearing range of your camera, so this makes them louder there rather than audible from farther.
    local FootstepWatch = {} -- character -> connection

    local function WatchFootsteps(Character)
        if FootstepWatch[Character] then
            return
        end

        FootstepWatch[Character] = Character.DescendantAdded:Connect(function(Sound)
            if Info.Footsteps and Sound.Name == "FootstepSound" and Sound:IsA("Sound") then
                Sound.Volume = Sound.Volume * Info.FootstepBoost
                Sound.RollOffMaxDistance = Sound.RollOffMaxDistance * Info.FootstepBoost
            end
        end)
    end

    local function UpdateFootsteps()
        local Wanted = {}

        if Info.Footsteps then
            for _, Other in next, Players:GetPlayers() do
                local Character = Enemy(Other) and Other.Character

                if Character then
                    Wanted[Character] = true
                    WatchFootsteps(Character)
                end
            end
        end

        for Character, Connection in next, FootstepWatch do
            if not Wanted[Character] then
                Connection:Disconnect()
                FootstepWatch[Character] = nil
            end
        end
    end

    local Players2 = EspTab:Section({Title = "Players", Icon = "user-search", Side = "Right"})
    Players2:Toggle({Title = "Player info tags", Tooltip = "Class, K/D, device and disguise under each enemy.", Default = false, Flag = "Intel.InfoTags", Callback = function(Value) Info.Tags = Value end})
    Players2:Slider({Title = "Tag distance", Min = 100, Max = 5000, Step = 100, Default = 1000, Suffix = " st", Flag = "Intel.InfoTags.Distance", Callback = function(Value) Info.Distance = Value end})
    Players2:Toggle({Title = "Reveal invisible players", Tooltip = "Shows staff using invisibility.", Default = true, Flag = "Intel.RevealInvisible", Callback = function(Value) Info.Reveal = Value end})
    Players2:Toggle({Title = "Louder enemy footsteps", Tooltip = "Hear enemies over gunfire and weather.", Default = false, Flag = "Intel.Footsteps", Callback = function(Value)
        Info.Footsteps = Value

        if not Value then
            UpdateFootsteps()
        end
    end})
    Players2:Slider({Title = "Footstep boost", Min = 1.5, Max = 6, Step = 0.5, Default = 3, Suffix = "x", Flag = "Intel.Footsteps.Boost", Tooltip = "Applies from the next step.", Callback = function(Value) Info.FootstepBoost = Value end})

    --//==================== Debug ====================

    -- The developers' own visualizers, switched on through values on your client
    local BallisticsClient = Player:WaitForChild("PlayerScripts"):FindFirstChild("BallisticsClient")

    local function DebugValue(Name)
        return BallisticsClient and BallisticsClient:FindFirstChild(Name)
    end

    local ShotSection = DebugTab:Section({Title = "Shot debug", Icon = "crosshair", Side = "Left"})

    ShotSection:Toggle({Title = "Show my shots", Default = false, Flag = "Debug.MyShots", Callback = function(Value)
        local Flag = DebugValue("DebugShots")

        if Flag then
            Flag.Value = Value
        elseif Value then
            Notify("Shot debug", "The DebugShots value isn't there.", "Warning")
        end
    end})

    local function OtherNames()
        local Names = {"Everyone"}

        for _, Other in next, Players:GetPlayers() do
            if Other ~= Player then
                table.insert(Names, Other.Name)
            end
        end

        return Names
    end

    local Watching = "Everyone"

    local function ApplyWatch(On)
        local Flag = DebugValue("DebugShotsAll")

        if not Flag then
            return
        end

        local Target = Watching ~= "Everyone" and Players:FindFirstChild(Watching)
        Flag:SetAttribute("TargetUserId", Target and Target.UserId or 0)
        Flag.Value = On
    end

    local WatchOn = false
    ShotSection:Toggle({Title = "Show others' shots", Default = false, Flag = "Debug.OtherShots", Callback = function(Value)
        WatchOn = Value
        ApplyWatch(Value)
    end})

    local WatchPick
    WatchPick = ShotSection:Dropdown({Title = "Whose", Values = OtherNames(), Default = "Everyone", Search = true, Action = {Icon = "refresh-cw", Tooltip = "Refresh", Callback = function() WatchPick:Refresh(OtherNames(), true) end}, Callback = function(Value)
        Watching = Value or "Everyone"
        ApplyWatch(WatchOn)
    end})

    local Armor = DebugTab:Section({Title = "Armor debug", Icon = "shield", Side = "Right"})
    Armor:Button({Title = "Open armor debug tool", Icon = "shield", Callback = function()
        local Script = Player:WaitForChild("PlayerScripts"):FindFirstChild("TerminalDebugClient")
        local Flag = Script and Script:FindFirstChild("Enabled")

        if Flag then
            Flag.Value = true
            Notify("Armor debug", "Started. Press F7 to show or hide it.", "Success")
        else
            Notify("Armor debug", "TerminalDebugClient isn't there.", "Warning")
        end
    end})

    --//==================== Match: team, server hop, placement, callouts ====================

    local MatchExtra = MatchTab:Section({Title = "Server", Icon = "server", Side = "Right"})

    MatchExtra:Button({Title = "Switch team", Icon = "shuffle", Callback = function()
        local Deployment = Remote("Deployment")
        local Teams = game:GetService("Teams")
        local Other

        for _, Team in next, Teams:GetTeams() do
            if (Team.Name == "NATO" or Team.Name == "PACT") and Team ~= Player.Team then
                Other = Team
            end
        end

        if not (Deployment and Other) then
            return Notify("Team", "Couldn't find the other team or the Deployment remote.", "Warning")
        end

        -- The deploy screen refuses when the teams are uneven; asking directly skips that client check
        local Ok, Result = pcall(Deployment.InvokeServer, Deployment, "TeamChange", Other)
        Notify("Team", (Ok and Result) and ("Switched to " .. Other.Name .. ".") or "The server refused (it checks team balance too).", (Ok and Result) and "Success" or "Warning")
    end})

    -- Server hop: the in-game browser's own list (GetServerList), joined the way the browser joins
    local Hop = {Prefer = "Most players"}

    local function HopServer()
        local GetServerList = Remote("GetServerList")

        if not GetServerList then
            return Notify("Server hop", "GetServerList isn't there.", "Error")
        end

        local Ok, List = pcall(GetServerList.InvokeServer, GetServerList)

        if not (Ok and type(List) == "table") then
            return Notify("Server hop", "The server list didn't come back.", "Error")
        end

        local Choices = {}

        for _, Server in next, List do
            if type(Server) == "table" and not Server.IsThisServer and Server.JobId and Server.JobId ~= game.JobId then
                table.insert(Choices, Server)
            end
        end

        if #Choices == 0 then
            return Notify("Server hop", "No other server to join.", "Warning")
        end

        local Pick

        if Hop.Prefer == "Random" then
            Pick = Choices[math.random(1, #Choices)]
        else
            -- Written out: "Most and A > B or A < B" breaks sort's ordering rules and can throw
            local Most = Hop.Prefer == "Most players"

            table.sort(Choices, function(A, B)
                local CountA, CountB = tonumber(A.PlayerCount) or 0, tonumber(B.PlayerCount) or 0

                if Most then
                    return CountA > CountB
                end

                return CountA < CountB
            end)
            Pick = Choices[1]
        end

        Notify("Server hop", ("Joining %s (%d players)..."):format(tostring(Pick.ServerName or Pick.Map or "a server"), tonumber(Pick.PlayerCount) or 0), "Info")
        pcall(game:GetService("TeleportService").TeleportToPlaceInstance, game:GetService("TeleportService"), Pick.PlaceId or game.PlaceId, Pick.JobId, Player)
    end

    MatchExtra:Dropdown({Title = "Hop to", Values = {"Most players", "Fewest players", "Random"}, Default = "Most players", Flag = "Match.Hop.Prefer", Callback = function(Value) Hop.Prefer = Value or "Most players" end})
    MatchExtra:Button({Title = "Server hop", Icon = "server", Style = "Primary", Callback = function()
        task.spawn(HopServer)
    end})
    local StaffSection = Leave.Section or MatchExtra
    StaffSection:Toggle({Title = "Hop instead of leaving", Tooltip = "Joins another server instead of just disconnecting.", Default = false, Flag = "Match.Hop.OnStaff", Callback = function(Value)
        Leave.Handler = Value and function()
            Notify("Staff", "Staff is here. Hopping to another server.", "Error")
            task.spawn(HopServer)
        end or function(Reason)
            Player:Kick(Reason)
        end
    end})

    -- Callouts: Callouts.COOLDOWN is the 5 s wait between voice callouts
    local Small = SupportTab:Section({Title = "Callouts", Icon = "megaphone", Side = "Right"})
    local CalloutTables

    Small:Toggle({Title = "No callout cooldown", Tooltip = "No 5 s wait between callouts.", Default = false, Flag = "Match.NoCalloutCooldown", Callback = function(Value)
        task.spawn(function()
            CalloutTables = CalloutTables or FindTables(function(Table)
                return type(rawget(Table, "LIVE_COOLDOWN")) == "number" and rawget(Table, "COOLDOWN") ~= nil
            end)

            for _, Table in next, CalloutTables do
                Table.COOLDOWN = Value and 0 or Table.LIVE_COOLDOWN
            end
        end)
    end})

    --//==================== Protection: anti-cheat guard ====================

    -- ParticleScaler's integrity guard checks every 1.5 s whether any of these services exist (exploits tend to
    -- create them) and has a freeze() that locks the game up. In this build nothing calls freeze, but that's one
    -- update away. The guard answers "not found" for these names to every caller but us.
    local GUARDED = {
        VirtualUser = true, VirtualInputManager = true, LinkingService = true, ProcessInstancePhysicsService = true,
        SafetyService = true, AppUpdateService = true, RuntimeScriptService = true, AccountService = true,
        DataModelPatchService = true, OmniRecommendationsService = true, SpawnService = true, OpenCloudService = true,
        UGCValidationService = true
    }

    local Guard = getgenv().SuperNovaFrontServiceGuard

    if not Guard and hookfunction and checkcaller then
        Guard = {Enabled = true}
        getgenv().SuperNovaFrontServiceGuard = Guard

        local wrap = newcclosure or function(Function) return Function end
        local Original
        Original = hookfunction(game.FindService, wrap(function(Self, Name, ...)
            if Guard.Enabled and GUARDED[Name] and not checkcaller() then
                return nil
            end

            return Original(Self, Name, ...)
        end))
    end

    ProtectTab:Section({Title = "Anti-cheat", Icon = "shield-check", Side = "Right"}):Toggle({Title = "Hide from anti-cheat", Tooltip = "Keeps the game's hidden integrity check from seeing your executor.", Default = true, Flag = "Protect.ServiceGuard", Callback = function(Value)
        if Guard then
            Guard.Enabled = Value
        elseif Value then
            Notify("Anti-cheat guard", "This executor has no hookfunction, so the guard can't be installed.", "Warning")
        end
    end})

    --// Loop

    task.spawn(function()
        while Running do
            for _, Step in next, {WatchDeafening, UpdateTags, UpdateInvisible, UpdateFootsteps} do
                local Ok, Err = pcall(Step)

                if not Ok then
                    warn("SuperNova > " .. tostring(Err))
                end
            end

            task.wait(0.5)
        end
    end)

    OasisUI:OnUnload(function()
        Running = false
        Move.Active, Move.NoJumpCooldown = false, false
        Clear.NoDeafen, Clear.Weather, Info.Tags, Info.Footsteps = false, false, false, false

        pcall(ApplySpeeds)
        pcall(SetShake, false)
        pcall(SetSway, false)
        pcall(ApplyWeather)
        pcall(UpdateFootsteps)

        for _, Name in next, {"DebugShots", "DebugShotsAll"} do
            local Flag = DebugValue(Name)

            if Flag then
                Flag.Value = false
            end
        end

        for _, Connection in next, Connections do
            Connection:Disconnect()
        end

        for _, Connection in next, DeafenWatch do
            Connection:Disconnect()
        end

        TagFolder:Destroy()
        Leave.Handler = function(Reason) Player:Kick(Reason) end

        -- The guard stays installed (hooks can't be removed cleanly) but stands down with the menu
        if Guard then
            Guard.Enabled = false
        end
    end)
end

--// Admin ESP: the game's own staff ESP (PlayerGui.TopRightGui.TopRightGui.ControlPanelESP)

do
    -- Only the panel's menu checks your rank; the module's toggles don't, so they're called directly
    local Module
    local State = {Main = false, Trails = false, Aim = false}
    local Wanted = {Main = false, Trails = false, Aim = false}
    local Toggles = {Main = "toggle", Trails = "toggleTrail", Aim = "toggleAim"}

    local function Load()
        if Module then
            return Module
        end

        local Gui = Player:WaitForChild("PlayerGui", 10)
        local Top = Gui and Gui:WaitForChild("TopRightGui", 10)
        local Holder = Top and Top:WaitForChild("TopRightGui", 10)
        local Source = Holder and Holder:WaitForChild("ControlPanelESP", 10)

        Module = Require(Source)

        if type(Module) ~= "table" or type(Module.toggle) ~= "function" then
            Module = nil
        end

        return Module
    end

    -- Each toggle flips and returns the new state, so only call it when it differs from what's wanted
    local function Sync()
        if not Load() then
            return false
        end

        for Key, Name in next, Toggles do
            if State[Key] ~= Wanted[Key] then
                local Ok, Now = pcall(Module[Name])
                State[Key] = Ok and Now == true
            end
        end

        return true
    end

    local function Want(Key)
        return function(Value)
            Wanted[Key] = Value

            task.spawn(function()
                if not Sync() and Value then
                    Notify("ESP", "Couldn't load the game's admin ESP module.", "Error")
                end
            end)
        end
    end

    local Card = EspTab:Module({
        Title = "ESP",
        Description = "Highlights, names, distance and downed state.",
        Icon = "scan",
        Side = "Left",
        Default = false,
        Flag = "Visual.AdminEsp",
        Keybind = {Key = nil, Mode = "Toggle"}, -- no default: V is the game's fire mode switch
        Opened = true,
        Callback = Want("Main")
    })

    Card:Checkbox({Title = "Movement trails", Tooltip = "A line behind each player showing where they've been.", Default = false, Flag = "Visual.AdminEsp.Trails", Callback = Want("Trails")})
    Card:Checkbox({Title = "Aim lines", Tooltip = "A line from each player's head showing where they're looking.", Default = false, Flag = "Visual.AdminEsp.Aim", Callback = Want("Aim")})

    OasisUI:OnUnload(function()
        Wanted.Main, Wanted.Trails, Wanted.Aim = false, false, false

        -- Never loaded means nothing is on; don't sit in Load's waits during unload
        if Module then
            pcall(Sync)
        end
    end)
end

--// Clarity: smoke and suppression

do
    local Clarity = {NoSmoke = false, NoSuppression = false}
    local Running = true

    -- Smoke grenades land in workspace.Dropped as parts with GrenadeType = "Smoke"
    local Muted = {} -- emitter -> true, the ones we switched off

    local function ClearSmoke()
        -- Grenades that burned out and got removed
        for Effect in next, Muted do
            if not Effect.Parent then
                Muted[Effect] = nil
            end
        end

        local Dropped = Workspace:FindFirstChild("Dropped")

        for _, Grenade in next, Dropped and Dropped:GetChildren() or {} do
            if Grenade:IsA("BasePart") and Grenade:GetAttribute("GrenadeType") == "Smoke" then
                for _, Effect in next, Grenade:GetDescendants() do
                    if (Effect:IsA("ParticleEmitter") or Effect:IsA("Smoke")) and Effect.Enabled then
                        Effect.Enabled = false
                        Muted[Effect] = true

                        if Effect:IsA("ParticleEmitter") then
                            Effect:Clear()
                        end
                    end
                end
            end
        end
    end

    local function RestoreSmoke()
        for Effect in next, Muted do
            if Effect.Parent then
                Effect.Enabled = true
            end
        end

        table.clear(Muted)
    end

    -- Near misses and explosions raise CharacterValues.Suppression on your client, which drives the blur and
    -- the weapon sway. Holding it at 0 removes both.
    local Watched = {} -- NumberValue -> connection

    local function WatchSuppression()
        local Character = Player.Character
        local Values = Character and Character:FindFirstChild("CharacterValues")
        local Suppression = Values and Values:FindFirstChild("Suppression")

        for Value, Connection in next, Watched do
            if Value ~= Suppression then
                Connection:Disconnect()
                Watched[Value] = nil
            end
        end

        if Suppression and not Watched[Suppression] then
            Watched[Suppression] = Suppression:GetPropertyChangedSignal("Value"):Connect(function()
                if Clarity.NoSuppression and Suppression.Value > 0 then
                    Suppression.Value = 0
                end
            end)
        end

        if Suppression and Clarity.NoSuppression and Suppression.Value > 0 then
            Suppression.Value = 0
        end
    end

    local Card = ClarityTab:Section({Title = "Screen", Icon = "eye", Side = "Left"})

    Card:Toggle({
        Title = "No smoke",
        Tooltip = "Your screen only.",
        Default = false,
        Flag = "Visual.NoSmoke",
        Callback = function(Value)
            Clarity.NoSmoke = Value

            if not Value then
                RestoreSmoke()
            end
        end
    })

    Card:Toggle({
        Title = "No suppression",
        Tooltip = "No blur or sway from near misses.",
        Default = false,
        Flag = "Visual.NoSuppression",
        Callback = function(Value) Clarity.NoSuppression = Value end
    })

    task.spawn(function()
        while Running do
            pcall(function()
                if Clarity.NoSmoke then
                    ClearSmoke()
                end

                WatchSuppression()
            end)

            task.wait(0.5)
        end
    end)

    OasisUI:OnUnload(function()
        Running = false
        RestoreSmoke()

        for _, Connection in next, Watched do
            Connection:Disconnect()
        end

        table.clear(Watched)
    end)
end

--// Movement: the game's own freecam, unlocked by its permission attribute

do
    local Running = true
    local Unlocks = {FreecamAllowed = false}
    local Before = {} -- attribute -> its value before we set it

    -- Remembers the original the first time we write, whenever that is: the folder may not exist yet when the
    -- toggle flips, and the loop below grants it once it shows up
    local function Grant(Name)
        local Folder = PrivateAttributes()

        if not Folder or Folder:GetAttribute(Name) == true then
            return
        end

        if Before[Name] == nil then
            Before[Name] = {Folder:GetAttribute(Name)} -- boxed so an original nil is remembered too
        end

        Folder:SetAttribute(Name, true)
    end

    local function Revoke(Name)
        local Folder = PrivateAttributes()

        if Folder and Before[Name] then
            Folder:SetAttribute(Name, Before[Name][1])
        end

        Before[Name] = nil
    end

    local function Unlock(Name)
        return function(Enabled)
            Unlocks[Name] = Enabled

            if Enabled then
                Grant(Name)
            else
                Revoke(Name)
            end
        end
    end

    local Cam = MoveTab:Section({Title = "Freecam", Icon = "camera", Side = "Left"})
    Cam:Toggle({Title = "Freecam", Tooltip = "Shift + P to toggle.", Default = false, Flag = "Movement.Freecam", Callback = Unlock("FreecamAllowed")})


    -- Re-applied every second: a respawn or a new PlayerGui can wipe a client-side attribute
    task.spawn(function()
        while Running do
            for Name, Enabled in next, Unlocks do
                if Enabled then
                    pcall(Grant, Name)
                end
            end

            task.wait(1)
        end
    end)

    OasisUI:OnUnload(function()
        Running = false

        for Name in next, Unlocks do
            Unlocks[Name] = false
            pcall(Revoke, Name)
        end
    end)
end

--// Intel: map radar, spotted alert, spy reveal, vehicle ESP

do
    local CollectionService = game:GetService("CollectionService")
    local Running = true
    local Intel = {Radar = false, Alert = true, Spies = false, Vehicles = false, VehicleDistance = 2000, SkipWrecked = true}

    local RED, BLUE, GREY = Color3.fromRGB(255, 80, 80), Color3.fromRGB(90, 150, 255), Color3.fromRGB(200, 200, 200)
    local STUDS_PER_METER = 3.57

    local function IsEnemy(Other)
        return Other ~= Player and Other.Team ~= nil and Player.Team ~= nil and Other.Team ~= Player.Team
    end

    local TagFolder = Instance.new("Folder")
    TagFolder.Name = "SuperNovaIntel"
    TagFolder.Parent = (gethui and gethui()) or game:GetService("CoreGui")

    local function NewTag(Height)
        local Gui = Instance.new("BillboardGui")
        Gui.Size = UDim2.fromOffset(220, 34)
        Gui.StudsOffset = Vector3.new(0, Height, 0)
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
        return {Gui = Gui, Label = Label}
    end

    -- Keeps one tag per key, and drops every tag whose key wasn't seen this pass
    local function TagSet(Height)
        local Tags = {}

        return {
            Get = function(Key)
                Tags[Key] = Tags[Key] or NewTag(Height)
                return Tags[Key]
            end,
            Sweep = function(Seen)
                for Key, Tag in next, Tags do
                    if not Seen[Key] then
                        Tag.Gui:Destroy()
                        Tags[Key] = nil
                    end
                end
            end
        }
    end

    --// Map radar: the game's map only draws an enemy while their character carries SpottedBy. Setting it on
    -- your client puts every enemy on your map; nobody else's map changes.

    local Marked = setmetatable({}, {__mode = "k"}) -- characters we marked ourselves

    local function UpdateRadar()
        for _, Other in next, Players:GetPlayers() do
            local Character = IsEnemy(Other) and Other.Character

            if Character and Intel.Radar and Character:GetAttribute("SpottedBy") == nil then
                Character:SetAttribute("SpottedBy", true)
                Marked[Character] = true
            end
        end
    end

    -- Only clears our own marks: a real spot from the server holds a different value and stays
    local function ClearRadar()
        for Character in next, Marked do
            if Character.Parent and Character:GetAttribute("SpottedBy") == true then
                Character:SetAttribute("SpottedBy", nil)
            end
        end

        table.clear(Marked)
    end

    --// Spotted alert: the same attribute on your own character means the enemy has you

    local WasSpotted = false

    local function SpotterName(Value)
        local Spotter = (type(Value) == "number" and Players:GetPlayerByUserId(Value)) or (type(Value) == "string" and Players:FindFirstChild(Value))
        return Spotter and Spotter.Name
    end

    local SpottedLabel

    local function UpdateAlert()
        local Character = Player.Character
        local Value = Character and Character:GetAttribute("SpottedBy")
        local Spotted = Value ~= nil and Value ~= false

        SpottedLabel:SetValue(Spotted and "yes" or "no")
        SpottedLabel:SetValueColor(Spotted and "Error" or "Success")

        if Spotted and not WasSpotted and Intel.Alert then
            local By = SpotterName(Value)
            Notify("Spotted", By and ("You've been spotted by " .. By .. ". You're on their map.") or "You've been spotted. You're on the enemy's map.", "Warning", 5)
        end

        WasSpotted = Spotted
    end

    --// Spy reveal: a disguised enemy carries the Disguised tag and passes for a teammate on the map

    local SpyTags = TagSet(3.4)

    local function UpdateSpies()
        local Seen = {}

        if Intel.Spies then
            for _, Other in next, Players:GetPlayers() do
                local Character = IsEnemy(Other) and Other.Character
                local Head = Character and Character:FindFirstChild("Head")

                if Head and CollectionService:HasTag(Character, "Disguised") then
                    local Tag = SpyTags.Get(Other)
                    Seen[Other] = true
                    Tag.Gui.Adornee = Head
                    Tag.Label.TextColor3 = RED
                    Tag.Label.Text = "SPY  ·  " .. Other.Name
                end
            end
        end

        SpyTags.Sweep(Seen)
    end

    --// Vehicle ESP: vehicles sit in workspace.Vehicles with VehicleType, OwnerTeam, CrewTeam and Wrecked

    local VehicleTags = TagSet(6)

    local function VehicleRoot(Vehicle)
        local Root = Vehicle:FindFirstChild("RootPart") or Vehicle.PrimaryPart
        return (Root and Root:IsA("BasePart") and Root) or Vehicle:FindFirstChildWhichIsA("BasePart", true)
    end

    local function UpdateVehicles()
        local Seen = {}
        local Folder = Workspace:FindFirstChild("Vehicles")
        local Camera = Workspace.CurrentCamera

        if Intel.Vehicles and Folder and Camera then
            local From = Camera.CFrame.Position
            local MyTeam = Player.Team and Player.Team.Name

            -- Who's sitting in what, worked out once per pass instead of once per vehicle
            local Crew = {}

            for _, Other in next, Players:GetPlayers() do
                local Humanoid = Other.Character and Other.Character:FindFirstChildOfClass("Humanoid")
                local Seat = Humanoid and Humanoid.SeatPart

                if Seat then
                    table.insert(Crew, Seat)
                end
            end

            for _, Vehicle in next, Folder:GetChildren() do
                local Root = Vehicle:IsA("Model") and VehicleRoot(Vehicle)
                local Wrecked = Vehicle:GetAttribute("Wrecked") == true
                local Distance = Root and (Root.Position - From).Magnitude

                if Root and Distance <= Intel.VehicleDistance and not (Wrecked and Intel.SkipWrecked) then
                    local CrewTeam = Vehicle:GetAttribute("CrewTeam")
                    local Team = CrewTeam or Vehicle:GetAttribute("OwnerTeam")
                    local Aboard = 0

                    for _, Seat in next, Crew do
                        if Seat:IsDescendantOf(Vehicle) then
                            Aboard += 1
                        end
                    end

                    local Tag = VehicleTags.Get(Vehicle)
                    Seen[Vehicle] = true
                    Tag.Gui.Adornee = Root
                    Tag.Label.TextColor3 = Wrecked and GREY or (Aboard == 0 and GREY) or (Team == MyTeam and BLUE) or RED
                    Tag.Label.Text = ("<b>%s</b>%s\n%s  ·  %s  ·  %dm"):format(
                        tostring(Vehicle:GetAttribute("VehicleType") or Vehicle.Name),
                        Wrecked and "  · wrecked" or "",
                        tostring(Team or "no team"),
                        Aboard > 0 and (Aboard .. " aboard") or "empty",
                        math.floor(Distance / STUDS_PER_METER)
                    )
                end
            end
        end

        VehicleTags.Sweep(Seen)
    end

    --// Cards

    local Map = IntelTab:Section({Title = "Map", Icon = "map", Side = "Left"})

    Map:Toggle({
        Title = "Map radar",
        Tooltip = "Every enemy shows on your map (M).",
        Default = false,
        Flag = "Intel.Radar",
        Callback = function(Value)
            Intel.Radar = Value

            if not Value then
                ClearRadar()
            end
        end
    })

    Map:Toggle({Title = "Spotted alert", Tooltip = "Warns you the moment the enemy spots you.", Default = true, Flag = "Intel.Alert", Callback = function(Value) Intel.Alert = Value end})
    SpottedLabel = Map:Label({Text = "Enemy has you spotted", Value = "no", ValueColor = "Success"})

    local Spies = EspTab:Section({Title = "Spies", Icon = "venetian-mask", Side = "Right"})
    Spies:Toggle({Title = "Reveal disguised enemies", Tooltip = "Labels enemies wearing a disguise.", Default = false, Flag = "Intel.Spies", Callback = function(Value) Intel.Spies = Value end})

    local Vehicles = IntelTab:Module({
        Title = "Vehicle ESP",
        Description = "Red: enemy crew. Blue: friendly. Grey: empty or wrecked.",
        Icon = "car",
        Side = "Right",
        Default = false,
        Flag = "Intel.Vehicles",
        Keybind = false,
        Opened = true,
        Callback = function(Value) Intel.Vehicles = Value end
    })

    Vehicles:Slider({Title = "Max distance", Min = 200, Max = 10000, Step = 100, Default = 2000, Suffix = " st", Flag = "Intel.Vehicles.Distance", Callback = function(Value) Intel.VehicleDistance = Value end})
    Vehicles:Checkbox({Title = "Hide wrecks", Default = true, Flag = "Intel.Vehicles.SkipWrecked", Callback = function(Value) Intel.SkipWrecked = Value end})

    --// Loop

    task.spawn(function()
        while Running do
            for _, Step in next, {UpdateRadar, UpdateAlert, UpdateSpies, UpdateVehicles} do
                local Ok, Err = pcall(Step)

                if not Ok then
                    warn("SuperNova > " .. tostring(Err))
                end
            end

            task.wait(0.25)
        end
    end)

    OasisUI:OnUnload(function()
        Running = false
        ClearRadar()
        TagFolder:Destroy()
    end)
end

--// World render: full bright, no fog or weather haze, time lock (the weather system rewrites these, so every frame)

do
    local Lighting = game:GetService("Lighting")
    local Render = {FullBright = false, NoFog = false, Time = false, ClockTime = 14}
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

    local function SetOrRestore(Object, Property, Value)
        if Value ~= nil then
            Set(Object, Property, Value)
        else
            Restore(Object, Property)
        end
    end

    local function AnySaved()
        for _, Saved in next, Originals do
            if next(Saved) ~= nil then
                return true
            end
        end

        return false
    end

    -- Weather swaps the Atmosphere object, so it's looked up again once a second
    local Atmosphere, LastLookup = nil, 0
    local BRIGHT = Color3.fromRGB(150, 150, 150)

    local function Apply()
        if not (Render.FullBright or Render.NoFog or Render.Time) and not AnySaved() then
            return
        end

        if os.clock() - LastLookup > 1 then
            LastLookup = os.clock()
            Atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
        end

        SetOrRestore(Lighting, "Ambient", Render.FullBright and BRIGHT or nil)
        SetOrRestore(Lighting, "OutdoorAmbient", Render.FullBright and BRIGHT or nil)
        SetOrRestore(Lighting, "Brightness", Render.FullBright and 2 or nil)

        -- Written out: "FullBright and false or nil" is always nil in Lua, so shadows would never go off
        if Render.FullBright then
            Set(Lighting, "GlobalShadows", false)
        else
            Restore(Lighting, "GlobalShadows")
        end

        SetOrRestore(Lighting, "ClockTime", (Render.Time and Render.ClockTime) or (Render.FullBright and 14) or nil)
        SetOrRestore(Lighting, "FogEnd", Render.NoFog and 1e6 or nil)
        SetOrRestore(Lighting, "FogStart", Render.NoFog and 1e6 or nil)

        if Atmosphere then
            SetOrRestore(Atmosphere, "Density", Render.NoFog and 0 or nil)
            SetOrRestore(Atmosphere, "Haze", Render.NoFog and 0 or nil)
        end
    end

    local Light = WorldTab:Section({Title = "Lighting", Icon = "sun", Side = "Left"})
    Light:Toggle({Title = "Full bright", Tooltip = "Even light everywhere: no dark interiors, no night.", Default = false, Flag = "World.FullBright", Callback = function(Value) Render.FullBright = Value end})
    Light:Toggle({Title = "No fog", Tooltip = "Clears fog and the weather's haze so you can see across the map.", Default = false, Flag = "World.NoFog", Callback = function(Value) Render.NoFog = Value end})

    local TimeToggle = Light:Toggle({Title = "Time of day", Tooltip = "Locks the clock on your screen only.", Default = false, Flag = "World.Time", Callback = function(Value) Render.Time = Value end})
    Light:Slider({Title = "Clock", Min = 0, Max = 24, Step = 0.25, Default = 14, Suffix = " h", Flag = "World.ClockTime", Callback = function(Value) Render.ClockTime = Value end})
        :DependsOn(TimeToggle, nil, "Hide")

    RunService:BindToRenderStep("SuperNovaFrontRender", Enum.RenderPriority.Camera.Value + 1, function()
        pcall(Apply)
    end)

    OasisUI:OnUnload(function()
        RunService:UnbindFromRenderStep("SuperNovaFrontRender")

        for Object, Saved in next, Originals do
            for Property, Value in next, Saved do
                pcall(function() Object[Property] = Value end)
            end
        end

        table.clear(Originals)
    end)
end

-- Loads the saved config only now that every card exists
Window:LoadAutoload()

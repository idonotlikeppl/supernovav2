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

-- Vehicle seats here aren't Roblox seats: each carries the FactoryVehicleSeat tag and an Occupant ObjectValue
-- holding the character in it (Shared.Vehicle.VehicleController), so Humanoid.SeatPart stays empty
local function SeatOf(Character)
    if not Character then
        return nil
    end

    for _, Seat in next, game:GetService("CollectionService"):GetTagged("FactoryVehicleSeat") do
        local Occupant = Seat:FindFirstChild("Occupant")

        if Occupant and Occupant:IsA("ObjectValue") and Occupant.Value == Character then
            return Seat
        end
    end

    return nil
end

-- The vehicle a seat belongs to: the seat's grandparent model with a RootPart, as the game finds it
local function VehicleOfSeat(Seat)
    local Model = Seat and Seat.Parent and Seat.Parent.Parent

    if Model and Model:IsA("Model") and Model:FindFirstChild("RootPart") then
        return Model
    end

    local Node = Seat

    while Node and Node.Parent and Node.Parent ~= Workspace and not Node.Parent:IsA("Folder") do
        Node = Node.Parent
    end

    return Node ~= Seat and Node or nil
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
    Subtitle = "✨SuperNova💫 Front",
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
local AlertTab = Visual:SubTab({Title = "Alerts", Icon = "triangle-alert"})

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
        Turrets = false,
        Wallbang = false,
        MinPower = 0.35,
        Ricochet = false,
        MinChance = 0.6,
        Indicator = true,
        SeedPick = false,
        Preview = true,
        ShowAll = false
    }

    local CollectionService = game:GetService("CollectionService")
    local Ballistics = Shared and Shared:FindFirstChild("Ballistics")
    local Materials = Require(Ballistics and Ballistics:FindFirstChild("ProjectileMaterials"))
    local Water = Require(Shared and Shared:FindFirstChild("Water"))

    -- ProfileRegistry's default: a pierced bullet never drops below 10% of its speed
    local PIERCE_FLOOR = 0.1
    local LIMBS = {"Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg"}

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

    -- The parts a hitbox mode may shoot at. R6 rigs; the hit codec also knows the R15 torso names, so fall back through those
    local function Candidates(Character)
        if Aim.Part == "Head" then
            return {Character:FindFirstChild("Head") or Character:FindFirstChild("HumanoidRootPart")}
        elseif Aim.Part == "Torso" then
            return {Character:FindFirstChild("Torso") or Character:FindFirstChild("UpperTorso") or Character:FindFirstChild("HumanoidRootPart")}
        end

        local List = {}

        for _, Name in next, LIMBS do
            local Part = Character:FindFirstChild(Name)

            if Part and Part:IsA("BasePart") then
                table.insert(List, Part)
            end
        end

        return List
    end

    -- Each limb carries its own Health value (MaxHealth as an attribute); 1 is untouched, 0 is destroyed
    local function LimbLeft(Part)
        local Health = Part:FindFirstChild("Health")

        if Health and Health:IsA("ValueBase") and type(Health.Value) == "number" then
            local Max = tonumber(Health:GetAttribute("MaxHealth")) or 100
            return math.clamp(Health.Value / math.max(Max, 1), 0, 1)
        end

        return 1
    end

    local VisibilityParams = RaycastParams.new()
    VisibilityParams.FilterType = Enum.RaycastFilterType.Exclude
    VisibilityParams.IgnoreWater = true

    -- The whole vehicle you're sitting in, so a turret's own hull doesn't block its line of sight
    local function MyVehicle()
        return VehicleOfSeat(SeatOf(Player.Character))
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

    -- How deep the bullet travels inside a part: cast back at it alone from past its far side, like the game's FindExit
    local ExitParams = RaycastParams.new()
    ExitParams.FilterType = Enum.RaycastFilterType.Include

    local function Depth(Part, Entry, Direction)
        local Reach = math.min(Part.Size.Magnitude + 1, 200)
        ExitParams.FilterDescendantsInstances = {Part}

        local Result = Workspace:Raycast(Entry + Direction * Reach, -Direction * Reach, ExitParams)
        return Result and (Result.Position - Entry).Magnitude or Reach
    end

    local PenParams = RaycastParams.new()
    PenParams.FilterType = Enum.RaycastFilterType.Exclude
    PenParams.IgnoreWater = false

    -- Shared.Ballistics.Interactions, walked along a straight line: the bullet starts with its weapon's Penetration
    -- as a budget, each wall costs its thickness times the material's penetration value (people cost 0.3), and
    -- speed falls with the share of budget spent. A part with a PenThreshold attribute lets the bullet through at any
    -- thickness if the weapon's Penetration reaches it and stops it otherwise. Water, helmets and body armour stop it.
    -- Returns the share of speed left when the bullet reaches the target, or nil if it never does.
    local function Penetrates(Origin, Part, Character, Penetration)
        if not (Materials and Penetration and Penetration > 0) then
            return nil
        end

        local Ignore = table.clone(VisibilityParams.FilterDescendantsInstances)
        local From, Budget, Left, Draws = Origin, Penetration, 1, 0

        -- The game stops counting at 16 walls
        for _ = 1, 16 do
            PenParams.FilterDescendantsInstances = Ignore

            local Result = Workspace:Raycast(From, Part.Position - From, PenParams)

            if not Result or Result.Instance:IsDescendantOf(Character) then
                return Left, Draws
            end

            local Hit = Result.Instance
            local Direction = (Part.Position - From).Unit

            if Water and Water.isWater(Hit, Result.Material) or Result.Material == Enum.Material.Water then
                return nil
            end

            local Accessory = Hit:FindFirstAncestorOfClass("Accessory")

            if Accessory and (Accessory.Name == "CustomHelmet" or Accessory.Name == "CustomArmor") then
                return nil
            end

            -- Root parts and phantom-tagged parts let bullets through for free
            if Hit.Name ~= "HumanoidRootPart" and not CollectionService:HasTag(Hit, "BallisticsPhantom") then
                local Model = Hit:FindFirstAncestorOfClass("Model")
                local Person = Model ~= nil and Model:FindFirstChildOfClass("Humanoid") ~= nil
                local Cost = Depth(Hit, Result.Position, Direction) * (Person and 0.3 or Materials.getPenetration(Hit.Material))
                local Threshold = Hit:GetAttribute("PenThreshold")

                if type(Threshold) == "number" then
                    if Penetration < Threshold then
                        return nil
                    end
                elseif Budget <= 0 or Cost > Budget then
                    return nil
                elseif Cost > 1e-3 then
                    -- An ordinary pierce wobbles the bullet with three draws from the shot's random generator
                    Draws += 1
                end

                Left *= math.max(1 - math.clamp(Cost / math.max(Budget, 0.001), 0, 1), PIERCE_FLOOR)
                Budget -= Cost
            end

            table.insert(Ignore, Hit)
            From = Result.Position
        end

        return nil
    end

    -- Visible, or (with wallbang on) reachable through the walls between with enough speed left over.
    -- Also returns how many wobbling pierces the bullet goes through on the way.
    local function Reach(Origin, Part, Character, Penetration)
        if not Aim.VisibleOnly or Visible(Origin, Part, Character) then
            return 1, 0
        end

        if Aim.Wallbang then
            local Left, Draws = Penetrates(Origin, Part, Character, Penetration)

            if Left and Left >= Aim.MinPower then
                return Left, Draws
            end
        end

        return nil
    end

    -- Picks the part to shoot on one enemy: the hitbox, the limb nearest the crosshair, or the most damaged limb
    local function ChoosePart(Character, Origin, Penetration, Camera, Mouse)
        local Best, BestPower, BestGap, BestScore, BestDraws

        for _, Part in next, Candidates(Character) do
            if (Part.Position - Origin).Magnitude <= Aim.MaxDistance then
                local Screen, OnScreen = Camera:WorldToViewportPoint(Part.Position)
                local Gap = OnScreen and (Vector2.new(Screen.X, Screen.Y) - Mouse).Magnitude

                if Gap and Gap <= Aim.FOV then
                    -- Most wounded skips limbs already at zero, which take no more damage
                    local Left = LimbLeft(Part)
                    local Score = if Aim.Part == "Most wounded" then (Left > 0 and Left or 2) else Gap

                    if not BestScore or Score < BestScore then
                        local Power, Draws = Reach(Origin, Part, Character, Penetration)

                        if Power then
                            Best, BestPower, BestGap, BestScore, BestDraws = Part, Power, Gap, Score, Draws
                        end
                    end
                end
            end
        end

        return Best, BestPower, BestGap, BestDraws
    end

    -- The enemy nearest the crosshair inside the FOV circle, and the part to shoot on them.
    -- Also returns the share of bullet speed left on arrival: 1 in the open, less through a wall.
    local function PickTarget(Origin, Penetration)
        local Camera = Workspace.CurrentCamera
        local Mouse = UserInputService:GetMouseLocation()
        local Best, BestCharacter, BestPower, BestGap, BestDraws = nil, nil, nil, math.huge, 0

        RefreshVisibilityFilter()

        for _, Other in next, Players:GetPlayers() do
            local Character = IsEnemy(Other) and Other.Character

            if Character and Alive(Character) and not (Aim.SkipDowned and IsDowned(Character)) then
                local Part, Power, Gap, Draws = ChoosePart(Character, Origin, Penetration, Camera, Mouse)

                if Part and Gap < BestGap then
                    Best, BestCharacter, BestPower, BestGap, BestDraws = Part, Character, Power, Gap, Draws
                end
            end
        end

        return Best, BestCharacter, BestPower, BestDraws
    end

    -- Ricochet shots (Interactions.tryRicochet): a bullet that can't pierce a surface may glance off it. The chance is
    -- how flat it strikes (0 head-on, 1 grazing) times its speed share times the material's ricochet value, and the
    -- new path is the mirror reflection plus a small random wobble that shrinks the flatter the hit. A part with a
    -- PenThreshold above the weapon's Penetration always deflects. So: find walls near the line to a hidden enemy,
    -- mirror the enemy across each wall, and aim at the mirror image; the bounce then carries the bullet onto them.
    local BOUNCE_YAW = {-50, -36, -24, -14, -7, 7, 14, 24, 36, 50}
    local BOUNCE_PITCH = {0, -5}
    local LastBounce = {At = 0}

    local function BounceOff(Origin, Target, Character, Speed, K, Penetration, Direction)
        local Result = Workspace:Raycast(Origin, Direction * Aim.MaxDistance, VisibilityParams)

        if not Result or Result.Instance:FindFirstAncestorOfClass("Model") and Result.Instance:FindFirstAncestorOfClass("Model"):FindFirstChildOfClass("Humanoid") then
            return nil
        end

        local Hit, Normal = Result.Instance, Result.Normal
        local Side = (Target - Result.Position):Dot(Normal)

        if Side < 0.5 or Water and Water.isWater(Hit, Result.Material) then
            return nil
        end

        local Mirror = Target - 2 * Side * Normal
        local Check = Workspace:Raycast(Origin, Mirror - Origin, VisibilityParams)

        -- The aim at the mirror image has to land on the same face of the same part
        if not Check or Check.Instance ~= Hit or Check.Normal:Dot(Normal) < 0.995 then
            return nil
        end

        local Incoming = (Check.Position - Origin).Unit
        local Flatness = math.clamp(math.deg(math.acos(math.clamp(-Incoming:Dot(Normal), 0, 1))) / 90, 0, 1)
        local Travelled = (Check.Position - Origin).Magnitude
        local SpeedShare = math.clamp(1 - K * Travelled / Speed, 0, 1)
        local Threshold = Hit:GetAttribute("PenThreshold")
        local Chance, Forced

        if type(Threshold) == "number" and (Penetration or 0) < Threshold then
            Chance, Forced = 1, true
        else
            -- A wall thin enough to pierce never bounces
            if type(Threshold) == "number" or Depth(Hit, Check.Position, Incoming) * Materials.getPenetration(Hit.Material) <= (Penetration or 0) then
                return nil
            end

            Chance = Flatness * SpeedShare * Materials.getRicochet(Hit.Material)
        end

        -- With seed picking the roll is ours to win, so long odds are fine
        if Chance < (Aim.SeedPick and math.min(Aim.MinChance, 0.15) or Aim.MinChance) then
            return nil
        end

        -- The second leg must be open
        local Leg = Workspace:Raycast(Check.Position + Normal * 0.05, Target - Check.Position, VisibilityParams)

        if Leg and not Leg.Instance:IsDescendantOf(Character) then
            return nil
        end

        -- The bounce wobbles by up to 8 degrees, less the flatter the hit
        return Check.Position, Chance, Forced, math.rad(8) * (1 - Flatness)
    end

    -- The best bounce onto one enemy: walls sampled in a fan around the line to them, plus the floor just short
    local function BestBounceFor(Origin, Part, Character, Speed, K, Penetration)
        local Root = Character:FindFirstChild("HumanoidRootPart")
        local Target = Part.Position
        local BestPoint, BestChance, BestForced, BestWobble

        if Aim.Lead and Root then
            Target += Root.AssemblyLinearVelocity * ((Target - Origin).Magnitude / Speed)
        end

        local Line = CFrame.lookAt(Origin, Target)
        local Directions = {}

        for _, Pitch in next, BOUNCE_PITCH do
            for _, Yaw in next, BOUNCE_YAW do
                table.insert(Directions, (Line * CFrame.Angles(math.rad(Pitch), math.rad(Yaw), 0)).LookVector)
            end
        end

        for _, Pitch in next, {-8, -16} do
            table.insert(Directions, (Line * CFrame.Angles(math.rad(Pitch), 0, 0)).LookVector)
        end

        for _, Direction in next, Directions do
            local Point, Chance, Forced, Wobble = BounceOff(Origin, Target, Character, Speed, K, Penetration, Direction)

            if Point and (not BestChance or Chance > BestChance) then
                BestPoint, BestChance, BestForced, BestWobble = Point, Chance, Forced, Wobble
            end
        end

        return BestPoint, BestChance, BestForced, BestWobble
    end

    local Paths = {} -- the ricochet map's latest finds: {Point, Part, Chance, Sure}

    local function FindBounce(Origin, Speed, K, Penetration)
        if not ((Aim.Ricochet or Aim.ShowAll) and Materials and Speed > 0) then
            return nil
        end

        -- A burst asks every few frames; the walls haven't moved
        if os.clock() - LastBounce.At < 0.15 and LastBounce.Origin and (LastBounce.Origin - Origin).Magnitude < 0.5 then
            return LastBounce.Point, LastBounce.Character, LastBounce.Chance, LastBounce.Part, LastBounce.Forced, LastBounce.Wobble
        end

        local Camera = Workspace.CurrentCamera
        local Mouse = UserInputService:GetMouseLocation()
        local Hidden = {}

        RefreshVisibilityFilter()

        -- A bounce drawn by the ricochet map counts as in your FOV when either end of it is: the enemy, or the
        -- point on the wall it glances off
        local WallGap = {}

        for _, Path in next, Aim.ShowAll and Paths or {} do
            local Character = Path[2].Parent
            local Screen, OnScreen = Camera:WorldToViewportPoint(Path[1])

            if Character and OnScreen then
                WallGap[Character] = (Vector2.new(Screen.X, Screen.Y) - Mouse).Magnitude
            end
        end

        -- Enemies inside the FOV circle, nearest the crosshair first, with no straight shot
        for _, Other in next, Players:GetPlayers() do
            local Character = IsEnemy(Other) and Other.Character

            if Character and Alive(Character) and not (Aim.SkipDowned and IsDowned(Character)) then
                local Part = Candidates(Character)[1]

                if Part and (Part.Position - Origin).Magnitude <= Aim.MaxDistance then
                    local Screen, OnScreen = Camera:WorldToViewportPoint(Part.Position)
                    local Gap = OnScreen and (Vector2.new(Screen.X, Screen.Y) - Mouse).Magnitude or math.huge
                    Gap = math.min(Gap, WallGap[Character] or math.huge)

                    if Gap <= Aim.FOV and not Visible(Origin, Part, Character) then
                        table.insert(Hidden, {Part = Part, Character = Character, Gap = Gap})
                    end
                end
            end
        end

        table.sort(Hidden, function(A, B) return A.Gap < B.Gap end)

        local BestPoint, BestCharacter, BestChance, BestPart, BestForced, BestWobble

        for Index = 1, math.min(#Hidden, 3) do
            local Entry = Hidden[Index]
            local Point, Chance, Forced, Wobble = BestBounceFor(Origin, Entry.Part, Entry.Character, Speed, K, Penetration)

            if Point then
                BestPoint, BestCharacter, BestChance, BestPart, BestForced, BestWobble = Point, Entry.Character, Chance, Entry.Part, Forced, Wobble
                break
            end
        end

        LastBounce = {At = os.clock(), Origin = Origin, Point = BestPoint, Character = BestCharacter, Chance = BestChance, Part = BestPart, Forced = BestForced, Wobble = BestWobble}
        return BestPoint, BestCharacter, BestChance, BestPart, BestForced, BestWobble
    end

    -- Seed picking: every pellet's seed is chosen by the firing client (ClientFire falls back to math.random when
    -- none is given), sent whole as a u32, and the server replays the bullet with Random.new(seed). The same seed
    -- gives the same draws here. Interactions pulls from it in a fixed order: three draws per ordinary pierce for
    -- the wobble, then for a bounce one roll (the bounce happens when it lands under the chance) and three more for
    -- its wobble. So try a few hundred seeds and keep the ones whose draws give the best flight.
    local SEED_TRIES = 300

    local function Wobble(Generator)
        return Vector3.new(Generator:NextNumber() * 2 - 1, Generator:NextNumber() * 2 - 1, Generator:NextNumber() * 2 - 1).Magnitude
    end

    local function PickSeeds(Count, Score)
        local Pool = {}

        for _ = 1, SEED_TRIES do
            local Seed = math.random(0, 2147483647)
            local Value = Score(Random.new(Seed))

            if Value then
                table.insert(Pool, {Seed, Value})
            end
        end

        table.sort(Pool, function(A, B) return A[2] < B[2] end)

        local Seeds = table.create(Count)

        for Index = 1, Count do
            Seeds[Index] = Pool[Index] and Pool[Index][1] or math.random(0, 2147483647)
        end

        return Seeds
    end

    -- Straightest flight through Draws pierces
    local function PierceSeeds(Count, Draws)
        return PickSeeds(Count, function(Generator)
            local Worst = 0

            for _ = 1, Draws do
                Worst = math.max(Worst, Wobble(Generator))
            end

            return Worst
        end)
    end

    -- A won roll (with a margin for error in the chance estimate), then the smallest wobble
    local function BounceSeeds(Count, Chance, Forced, Spread)
        return PickSeeds(Count, function(Generator)
            if not Forced and Generator:NextNumber() >= Chance * 0.7 then
                return nil
            end

            return Spread > 0.001 and Wobble(Generator) or 0
        end)
    end

    -- Ballistics for a weapon by name: speed, drag and penetration from the same config the game builds the bullet from
    local function BulletOf(WeaponName, MuzzleIndex, BulletIndex)
        local Config = WeaponManager and WeaponManager:GetMuzzleConfig(WeaponName, MuzzleIndex or 1)
        local Bullet = Config and type(Config.BulletSettings) == "table" and Config.BulletSettings[BulletIndex or 1]

        -- Drag 1 is the game's own default when it's missing
        return Bullet and tonumber(Bullet.MuzzleVelocity) or 0, Bullet and tonumber(Bullet.Drag) or 1, Bullet and tonumber(Bullet.Penetration) or 0
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
            ShotHook = {Count = #Found, Seeds = true}
            getgenv().SuperNovaFrontShotHook = ShotHook

            for _, Function in next, Found do
                local Original
                Original = hookfunction(Function, function(Tool, MuzzleIndex, BulletIndex, Origin, Directions, Options)
                    local Handler = ShotHook.Handler

                    if Handler and typeof(Origin) == "Vector3" and type(Directions) == "table" and #Directions > 0 then
                        local Ok, New, Seeds = pcall(Handler, Tool, MuzzleIndex, BulletIndex, Origin, Directions)

                        if Ok and New then
                            Directions = New
                        end

                        -- Chosen seeds go in the options, where ClientFire looks before rolling its own
                        if Ok and type(Seeds) == "table" then
                            local Copy = type(Options) == "table" and table.clone(Options) or {}
                            Copy.Seeds = Seeds
                            Options = Copy
                        end
                    end

                    return Original(Tool, MuzzleIndex, BulletIndex, Origin, Directions, Options)
                end)
            end
        end
    end


    if ShotHook then
        ShotHook.Handler = function(Tool, MuzzleIndex, BulletIndex, Origin, Directions)
            -- Seed picking also works on its own: with silent aim off it only swaps seeds on shots you aimed yourself
            if not (Aim.Enabled or Aim.SeedPick) then
                return nil
            end

            -- Guns pass their Tool; vehicle turrets (TurretFireController) pass the weapon name as a string
            local IsTurret = type(Tool) == "string"
            local WeaponName = IsTurret and Tool or (typeof(Tool) == "Instance" and Tool.Name)

            if not WeaponName or (IsTurret and not Aim.Turrets) then
                return nil
            end

            local Speed, K, Penetration = BulletOf(WeaponName, MuzzleIndex, BulletIndex)

            -- No ballistics for this weapon (some vehicle cannons live in another config): a straight-line guess
            -- would miss at range and look obvious, so leave the shot alone
            if Speed <= 0 then
                return nil
            end

            -- The plan: where the shot should go, and the seeds that suit that flight
            local Wanted, Seeds
            local Part, Character, Power, Draws = PickTarget(Origin, Penetration)

            if Part then
                local Root = Character:FindFirstChild("HumanoidRootPart")
                local Velocity = Root and Root.AssemblyLinearVelocity or Vector3.zero
                Wanted = Solve(Origin, Part.Position, Velocity, Speed, K, Workspace.Gravity)

                if Wanted and Aim.SeedPick and Power and Power < 1 and (Draws or 0) > 0 then
                    Seeds = PierceSeeds(#Directions, Draws)
                end
            else
                -- Nobody to hit straight or through a wall: try glancing one off a wall onto them
                local Point, _, Chance, _, Forced, Spread = FindBounce(Origin, Speed, K, Penetration)
                Wanted = Point and Solve(Origin, Point, Vector3.zero, Speed, K, Workspace.Gravity)

                if Wanted and Aim.SeedPick then
                    Seeds = BounceSeeds(#Directions, Chance, Forced, Spread)
                end
            end

            if not Wanted then
                return nil
            end

            if Aim.Enabled then
                return Retarget(Directions, Wanted), Seeds
            end

            -- Silent aim off: leave the bullets where you aimed them, and only hand over seeds if that's on the plan
            local Sum = Vector3.zero

            for _, Direction in next, Directions do
                Sum += Direction.Unit
            end

            local OnPlan = Sum.Magnitude > 1e-6 and math.deg(math.acos(math.clamp(Sum.Unit:Dot(Wanted), -1, 1))) <= 1.5
            return nil, OnPlan and Seeds or nil
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
    Targeting:Dropdown({Title = "Hitbox", Values = {"Head", "Torso", "Closest limb", "Most wounded"}, Default = "Head", Flag = "Combat.SilentAim.Part", Tooltip = "Closest limb: nearest your crosshair. Most wounded: the limb with the least health left.", Callback = function(Value) Aim.Part = Value end})
    Targeting:Slider({Title = "Max distance", Min = 100, Max = 5000, Step = 50, Default = 2000, Suffix = " st", Flag = "Combat.SilentAim.Distance", Callback = function(Value) Aim.MaxDistance = Value end})
    Targeting:Toggle({Title = "Visible only", Tooltip = "Skip enemies behind walls.", Default = true, Flag = "Combat.SilentAim.Visible", Callback = function(Value) Aim.VisibleOnly = Value end})
    Targeting:Toggle({Title = "Ignore downed", Default = true, Flag = "Combat.SilentAim.SkipDowned", Callback = function(Value) Aim.SkipDowned = Value end})
    Targeting:Toggle({Title = "Bullet drop", Tooltip = "Aims high to cancel drop over distance.", Default = true, Flag = "Combat.SilentAim.Drop", Callback = function(Value) Aim.Drop = Value end})
    Targeting:Toggle({Title = "Prediction", Tooltip = "Leads moving targets.", Default = true, Flag = "Combat.SilentAim.Lead", Callback = function(Value) Aim.Lead = Value end})

    -- Wallbangs and ricochets work with silent aim (bullets bent onto the plan) or aim lock (camera turned onto it)
    local Shots = AimTab:Section({Title = "Ballistics", Icon = "zap", Side = "Left"})
    Shots:Toggle({Title = "Wallbang", Tooltip = "With Visible only on, also targets enemies your bullet can punch through cover to reach.", Default = false, Flag = "Combat.SilentAim.Wallbang", Callback = function(Value) Aim.Wallbang = Value end})
    Shots:Slider({Title = "Wallbang power", Min = 10, Max = 90, Step = 5, Default = 35, Suffix = "%", Flag = "Combat.SilentAim.MinPower", Tooltip = "Least bullet speed that has to make it through.", Callback = function(Value) Aim.MinPower = Value / 100 end})
    Shots:Toggle({Title = "Ricochet shots", Tooltip = "No clear shot: bounce the bullet off a wall or the floor onto them.", Default = false, Flag = "Combat.SilentAim.Ricochet", Callback = function(Value) Aim.Ricochet = Value end})
    Shots:Slider({Title = "Ricochet chance", Min = 30, Max = 95, Step = 5, Default = 60, Suffix = "%", Flag = "Combat.SilentAim.MinChance", Tooltip = "Least odds of the bounce happening. Metal and glass at a flat angle bounce best.", Callback = function(Value) Aim.MinChance = Value / 100 end})
    Shots:Toggle({Title = "Seed picking", Tooltip = "Picks each bullet's random seed so ricochets land and wallbangs fly straight. Ricochets then work at much longer odds.", Default = false, Flag = "Combat.SilentAim.SeedPick", Callback = function(Value)
        Aim.SeedPick = Value

        if Value and ShotHook and not ShotHook.Seeds then
            Notify("Seed picking", "The shot hook from an earlier run is still loaded. Rejoin once for seed picking to work.", "Warning", 6)
        end
    end})
    Shots:Toggle({Title = "Show all ricochets", Tooltip = "Draws every bounce that can reach a hidden enemy on screen, with its odds. Works without any aim on.", Default = false, Flag = "Combat.SilentAim.ShowAll", Callback = function(Value) Aim.ShowAll = Value end})
    Shots:Toggle({Title = "Bounce preview", Tooltip = "Draws the path of a lined-up ricochet.", Default = true, Flag = "Combat.SilentAim.Preview", Callback = function(Value) Aim.Preview = Value end})
    Shots:Toggle({Title = "Shot indicator", Tooltip = "Shows under the crosshair when a wallbang or ricochet is lined up.", Default = true, Flag = "Combat.SilentAim.Indicator", Callback = function(Value) Aim.Indicator = Value end})

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
        local Speed, K, Penetration = BulletOf(Tool.Name, 1, 1)
        local Part, Character = PickTarget(From, Penetration)
        local Wanted

        if Part then
            local Root = Character:FindFirstChild("HumanoidRootPart")
            local Velocity = Root and Root.AssemblyLinearVelocity or Vector3.zero
            Wanted = Speed > 0 and Solve(From, Part.Position, Velocity, Speed, K, Workspace.Gravity) or (Part.Position - From).Unit
        else
            -- No straight or through-the-wall shot: lock onto the ricochet point instead
            local Point = FindBounce(From, Speed, K, Penetration)
            Wanted = Point and Solve(From, Point, Vector3.zero, Speed, K, Workspace.Gravity)
        end

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

    -- Shot indicator: what the next shot would do, checked a few times a second from the camera
    local Indicator = Drawing and Drawing.new("Text")

    if Indicator then
        Indicator.Visible = false
        Indicator.Center = true
        Indicator.Outline = true
        Indicator.Size = 16
        Indicator.Font = 2
    end

    local IndicatorRunning = true

    -- Bounce preview: crosshair to the wall, wall to the target, redrawn every frame from the last plan
    local Plan -- {Point, Part}
    local Legs = {}

    for Index = 1, 2 do
        Legs[Index] = Drawing and Drawing.new("Line")

        if Legs[Index] then
            Legs[Index].Visible = false
            Legs[Index].Thickness = 2
            Legs[Index].Color = Color3.fromRGB(90, 200, 255)
            Legs[Index].Transparency = 0.9
        end
    end

    local function DrawLeg(Leg, From, To, Camera)
        local A, OnA = Camera:WorldToViewportPoint(From)
        local B, OnB = Camera:WorldToViewportPoint(To)
        local Show = A.Z > 0 and B.Z > 0 and (OnA or OnB)

        Leg.Visible = Show

        if Show then
            Leg.From = Vector2.new(A.X, A.Y)
            Leg.To = Vector2.new(B.X, B.Y)
        end
    end

    local PreviewLoop = RunService.RenderStepped:Connect(function()
        local Camera = Workspace.CurrentCamera
        local Show = Plan and (Aim.Enabled or Lock.Enabled) and Aim.Preview and Plan[2].Parent ~= nil

        for _, Leg in next, Legs do
            Leg.Visible = false
        end

        if Show and Legs[1] then
            DrawLeg(Legs[1], Camera.CFrame.Position + Camera.CFrame.LookVector * 4, Plan[1], Camera)
            DrawLeg(Legs[2], Plan[1], Plan[2].Position, Camera)
        end
    end)

    -- Ricochet map: every hidden enemy on screen that a bounce can reach, drawn at once, whether or not they're in
    -- your FOV and whether or not any aim is on. Green is a likely bounce, yellow fair, orange a long shot.
    local MAP_PATHS = 6
    local MapDrawings = {}

    for Index = 1, MAP_PATHS do
        local Entry = {}

        if Drawing then
            Entry.Legs = {Drawing.new("Line"), Drawing.new("Line")}
            Entry.Label = Drawing.new("Text")

            for _, Leg in next, Entry.Legs do
                Leg.Visible = false
                Leg.Thickness = 1.5
                Leg.Transparency = 0.85
            end

            Entry.Label.Visible = false
            Entry.Label.Center = true
            Entry.Label.Outline = true
            Entry.Label.Size = 14
            Entry.Label.Font = 2
        end

        MapDrawings[Index] = Entry
    end

    local function ChanceColor(Chance, Sure)
        if Sure or Chance >= 0.75 then
            return Color3.fromRGB(80, 220, 140)
        end

        return Chance >= 0.5 and Color3.fromRGB(255, 210, 60) or Color3.fromRGB(255, 140, 60)
    end

    local function ScanRicochets()
        local Found = {}
        local Camera, Tool = Workspace.CurrentCamera, HeldWeapon()

        if not (Aim.ShowAll and Camera and Tool and Materials) then
            Paths = Found
            return
        end

        local From = Camera.CFrame.Position
        local Speed, K, Penetration = BulletOf(Tool.Name, 1, 1)

        if Speed <= 0 then
            Paths = Found
            return
        end

        RefreshVisibilityFilter()

        -- Hidden enemies on screen, nearest first
        local Hidden = {}

        for _, Other in next, Players:GetPlayers() do
            local Character = IsEnemy(Other) and Other.Character

            if Character and Alive(Character) and not (Aim.SkipDowned and IsDowned(Character)) then
                local Part = Candidates(Character)[1]
                local Distance = Part and (Part.Position - From).Magnitude

                if Distance and Distance <= Aim.MaxDistance then
                    local _, OnScreen = Camera:WorldToViewportPoint(Part.Position)

                    if OnScreen and not Visible(From, Part, Character) then
                        table.insert(Hidden, {Part = Part, Character = Character, Distance = Distance})
                    end
                end
            end
        end

        table.sort(Hidden, function(A, B) return A.Distance < B.Distance end)

        for Index = 1, math.min(#Hidden, MAP_PATHS) do
            local Entry = Hidden[Index]
            local Point, Chance, Forced = BestBounceFor(From, Entry.Part, Entry.Character, Speed, K, Penetration)

            if Point then
                table.insert(Found, {Point, Entry.Part, Chance, Forced or Aim.SeedPick})
            end
        end

        Paths = Found
    end

    local MapLoop = RunService.RenderStepped:Connect(function()
        local Camera = Workspace.CurrentCamera

        for Index, Entry in next, MapDrawings do
            local Path = Aim.ShowAll and Paths[Index]

            if Entry.Legs then
                if Path and Path[2].Parent then
                    local Color = ChanceColor(Path[3], Path[4])

                    DrawLeg(Entry.Legs[1], Camera.CFrame.Position + Camera.CFrame.LookVector * 4, Path[1], Camera)
                    DrawLeg(Entry.Legs[2], Path[1], Path[2].Position, Camera)
                    Entry.Legs[1].Color, Entry.Legs[2].Color = Color, Color

                    local Screen, OnScreen = Camera:WorldToViewportPoint(Path[1])
                    Entry.Label.Visible = OnScreen
                    Entry.Label.Position = Vector2.new(Screen.X, Screen.Y - 14)
                    Entry.Label.Text = Path[4] and "sure" or ("%d%%"):format(math.floor(Path[3] * 100 + 0.5))
                    Entry.Label.Color = Color
                else
                    Entry.Legs[1].Visible, Entry.Legs[2].Visible, Entry.Label.Visible = false, false, false
                end
            end
        end
    end)

    task.spawn(function()
        while IndicatorRunning do
            pcall(ScanRicochets)
            task.wait(0.25)
        end
    end)

    task.spawn(function()
        while IndicatorRunning and Indicator do
            local Text, Color
            Plan = nil

            if (Aim.Enabled or Lock.Enabled) and (Aim.Indicator or Aim.Preview) and (Aim.Wallbang or Aim.Ricochet) then
                local Camera, Tool = Workspace.CurrentCamera, HeldWeapon()

                if Camera and Tool then
                    pcall(function()
                        local From = Camera.CFrame.Position
                        local Speed, K, Penetration = BulletOf(Tool.Name, 1, 1)
                        local Part, _, Power = PickTarget(From, Penetration)

                        if Part and Power and Power < 1 then
                            Text, Color = ("WALLBANG  %d%% power"):format(math.floor(Power * 100 + 0.5)), Color3.fromRGB(255, 170, 60)
                        elseif not Part then
                            local Point, _, Chance, Target, Forced = FindBounce(From, Speed, K, Penetration)

                            if Point then
                                -- With seed picking a won roll is chosen, so the odds no longer apply
                                local Odds = (Aim.SeedPick or Forced) and "sure" or ("%d%%"):format(math.floor(Chance * 100 + 0.5))
                                Text, Color = "RICOCHET  " .. Odds, Color3.fromRGB(90, 200, 255)
                                Plan = Target and {Point, Target}
                            end
                        end
                    end)
                end
            end

            Text = Aim.Indicator and Text or nil
            Indicator.Visible = Text ~= nil

            if Text then
                Indicator.Text = Text
                Indicator.Color = Color
                Indicator.Position = UserInputService:GetMouseLocation() + Vector2.new(0, 26)
            end

            task.wait(0.12)
        end
    end)

    --// Triggerbot: fires for you. Crosshair mode shoots when the ray under your crosshair lands on an enemy (or, with
    -- Wallbang on, on cover your round punches through to one). Silent aim mode shoots whenever silent aim has a
    -- shot it would take: straight, through a wall, or off one. The click goes through the executor's mouse input,
    -- so the game sees an ordinary left click.

    local Trigger = {Enabled = false, Mode = "Crosshair", Delay = 0.05, Hold = false, Rate = 8}
    local TriggerRunning = true
    local Pressed = false

    local VirtualInput = (function()
        local Ok, Service = pcall(game.GetService, game, "VirtualInputManager")
        return Ok and Service or nil
    end)()

    local function Press(Down)
        if Pressed == Down then
            return
        end

        Pressed = Down

        if Down and mouse1press then
            mouse1press()
        elseif not Down and mouse1release then
            mouse1release()
        elseif VirtualInput then
            local Mouse = UserInputService:GetMouseLocation()
            VirtualInput:SendMouseButtonEvent(Mouse.X, Mouse.Y, 0, Down, game, 0)
        end
    end

    local TriggerParams = RaycastParams.new()
    TriggerParams.FilterType = Enum.RaycastFilterType.Exclude
    TriggerParams.IgnoreWater = false

    local function EnemyOf(Instance)
        local Model = Instance and Instance:FindFirstAncestorOfClass("Model")
        local Other = Model and Players:GetPlayerFromCharacter(Model)

        if Other and IsEnemy(Other) and Alive(Model) and not (Aim.SkipDowned and IsDowned(Model)) then
            return Model
        end

        return nil
    end

    local function OnTarget()
        local Camera, Tool = Workspace.CurrentCamera, HeldWeapon()

        if not (Camera and Tool) then
            return false
        end

        local From = Camera.CFrame.Position
        local Speed, K, Penetration = BulletOf(Tool.Name, 1, 1)

        if Trigger.Mode == "Silent aim target" then
            if not Aim.Enabled then
                return false
            end

            return PickTarget(From, Penetration) ~= nil or FindBounce(From, Speed, K, Penetration) ~= nil
        end

        -- Crosshair: the first thing under your crosshair, or what's behind cover your round can punch through
        RefreshVisibilityFilter()
        TriggerParams.FilterDescendantsInstances = VisibilityParams.FilterDescendantsInstances

        local Mouse = UserInputService:GetMouseLocation()
        local Ray = Camera:ViewportPointToRay(Mouse.X, Mouse.Y)
        local Reach = Ray.Direction * Aim.MaxDistance
        local Result = Workspace:Raycast(Ray.Origin, Reach, TriggerParams)

        if not Result then
            return false
        end

        if EnemyOf(Result.Instance) then
            return true
        end

        if Aim.Wallbang then
            local Ignore = table.clone(TriggerParams.FilterDescendantsInstances)

            -- What lies behind the cover along the same ray
            for _ = 1, 4 do
                table.insert(Ignore, Result.Instance)
                TriggerParams.FilterDescendantsInstances = Ignore
                Result = Workspace:Raycast(Ray.Origin, Reach, TriggerParams)

                local Character = Result and EnemyOf(Result.Instance)

                if Character then
                    local Left = Penetrates(From, Result.Instance, Character, Penetration)
                    return Left ~= nil and Left >= Aim.MinPower
                elseif not Result then
                    return false
                end
            end
        end

        return false
    end

    task.spawn(function()
        local Since -- when the current target was first seen

        while TriggerRunning do
            local Ready = false

            -- Never while you're clicking yourself, typing, or on the menu
            if Trigger.Enabled and not UserInputService:GetFocusedTextBox() and not (UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) and not Pressed) then
                local Ok, Hit = pcall(OnTarget)
                Ready = Ok and Hit
            end

            if Ready then
                Since = Since or os.clock()

                if os.clock() - Since >= Trigger.Delay then
                    if Trigger.Hold then
                        Press(true)
                    else
                        -- Taps: press, a short hold so the game registers it, release, then wait out the rate
                        Press(true)
                        task.wait(0.03)
                        Press(false)
                        task.wait(math.max(1 / Trigger.Rate - 0.03, 0))
                    end
                end
            else
                Since = nil
                Press(false)
            end

            task.wait(0.03)
        end

        Press(false)
    end)

    local TriggerCard = AimTab:Module({
        Title = "Triggerbot",
        Description = "Fires for you when a shot is there.",
        Icon = "mouse-pointer-click",
        Side = "Right",
        Risky = true,
        Default = false,
        Flag = "Combat.Triggerbot",
        Keybind = {Key = nil, Mode = "Toggle"},
        Opened = true,
        Callback = function(Enabled)
            Trigger.Enabled = Enabled

            if Enabled and not (mouse1press or VirtualInput) then
                Notify("Triggerbot", "Your executor has no way to click the mouse, so the triggerbot can't fire.", "Error", 5)
            end
        end
    })

    TriggerCard:Dropdown({Title = "Fire when", Values = {"Crosshair", "Silent aim target"}, Default = "Crosshair", Flag = "Combat.Triggerbot.Mode", Tooltip = "Crosshair: an enemy under your crosshair. Silent aim target: any shot silent aim would take, ricochets included.", Callback = function(Value) Trigger.Mode = Value end})
    TriggerCard:Slider({Title = "Delay", Min = 0, Max = 500, Step = 10, Default = 50, Suffix = " ms", Flag = "Combat.Triggerbot.Delay", Tooltip = "Wait this long on target before firing. A little looks human.", Callback = function(Value) Trigger.Delay = Value / 1000 end})
    TriggerCard:Checkbox({Title = "Hold fire", Tooltip = "Hold the trigger while on target (automatics). Off taps instead (semi-autos, bolt actions).", Default = false, Flag = "Combat.Triggerbot.Hold", Callback = function(Value) Trigger.Hold = Value end})
    TriggerCard:Slider({Title = "Tap rate", Min = 1, Max = 20, Step = 1, Default = 8, Suffix = " /s", Flag = "Combat.Triggerbot.Rate", Callback = function(Value) Trigger.Rate = Value end})

    OasisUI:OnUnload(function()
        Aim.Enabled = false
        Lock.Enabled = false
        IndicatorRunning = false
        TriggerRunning = false
        Trigger.Enabled = false
        PreviewLoop:Disconnect()
        MapLoop:Disconnect()

        for _, Entry in next, MapDrawings do
            for _, Object in next, Entry.Legs or {} do
                Object:Remove()
            end

            if Entry.Label then
                Entry.Label:Remove()
            end
        end
        RunService:UnbindFromRenderStep("SuperNovaFrontAimLock")

        if Indicator then
            Indicator:Remove()
        end

        for _, Leg in next, Legs do
            Leg:Remove()
        end

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

--// Amphibious: any vehicle you drive floats and swims.
-- Shared.Vehicle.VehicleWaterClient floats a vehicle on the driver's client: every frame it hands the vehicle's
-- RootPart to WaterFloat.step when the model's WaterOwner attribute is your UserId and WaterLine is set, using a
-- part named WaterFloat as the buoyancy point. The server only sets those on amphibious vehicles (M113, MT-LB).
-- Setting them on your own copy of the model, plus a float point, gets every other vehicle the same treatment.
-- Thrust is added here, since the swim drive only exists on the amphibious ones.

do
    local Running = true
    local Swim = {Enabled = false, Speed = 20, Turn = 0.6, Ride = 1, Highway = false, Boost = 3}
    local WaterModule = Require(Shared and Shared:FindFirstChild("Water"))
    local Active -- {Vehicle, Root, Float}

    local SurfaceParams = RaycastParams.new()
    SurfaceParams.FilterType = Enum.RaycastFilterType.Exclude
    SurfaceParams.IgnoreWater = false

    -- Only the driver's seat (DriverSeat) steers the boat
    local function Driving()
        local Seat = SeatOf(Player.Character)

        if not (Seat and (Seat:IsA("VehicleSeat") or Seat.Name:lower():find("driver"))) then
            return nil
        end

        local Vehicle = VehicleOfSeat(Seat)
        local Root = Vehicle and Vehicle:FindFirstChild("RootPart")
        return Root and Vehicle, Root, Seat
    end

    -- The water surface under the vehicle, if there is water there. The game's own finder (Water.surfaceY) covers
    -- terrain water and the map's WaterVolumes; a plain raycast is the fallback.
    local function Surface(Vehicle, Root)
        if WaterModule and WaterModule.surfaceY then
            local Ok, Y = pcall(WaterModule.surfaceY, Root.Position + Vector3.new(0, 20, 0))

            if Ok and type(Y) == "number" and Y > Root.Position.Y - 15 then
                return Y
            end
        end

        SurfaceParams.FilterDescendantsInstances = {Vehicle, Player.Character or Vehicle}

        local Result = Workspace:Raycast(Root.Position + Vector3.new(0, 40, 0), Vector3.new(0, -80, 0), SurfaceParams)

        if Result and (Result.Material == Enum.Material.Water or WaterModule and WaterModule.isWater(Result.Instance, Result.Material)) then
            return Result.Position.Y
        end

        return nil
    end

    local function Release()
        if not Active then
            return
        end

        local Vehicle = Active.Vehicle

        if Vehicle.Parent and Vehicle:GetAttribute("WaterOwner") == Player.UserId and Active.Ours then
            for _, Name in next, {"WaterOwner", "WaterLine", "WaterPhase", "SwimDrag", "SwimLateralDrag"} do
                Vehicle:SetAttribute(Name, nil)
            end
        end

        if Active.Float then
            Active.Float:Destroy()
        end

        Active = nil
    end

    local function Take(Vehicle, Root)
        -- Natively amphibious: the game already floats and drives it, so it's left alone
        local Native = Vehicle:FindFirstChild("WaterFloat", true)

        if Native then
            return {Vehicle = Vehicle, Root = Root, Native = true}
        end

        -- Float point at the bottom of the hull, so it rides with the hull just under the waterline
        local Box, Size = Vehicle:GetBoundingBox()
        local Bottom = Box.Position - Vector3.new(0, Size.Y / 2, 0)

        local Float = Instance.new("Part")
        Float.Name = "WaterFloat"
        Float.Size = Vector3.one
        Float.Transparency = 1
        Float.Massless = true
        Float.CanCollide, Float.CanQuery, Float.CanTouch = false, false, false
        Float.CFrame = CFrame.new(Bottom + Vector3.new(0, Swim.Ride, 0))

        local Weld = Instance.new("WeldConstraint")
        Weld.Part0 = Root
        Weld.Part1 = Float
        Weld.Parent = Float
        Float.Parent = Vehicle

        return {Vehicle = Vehicle, Root = Root, Float = Float, Ours = true}
    end

    local function Key(Code)
        return UserInputService:IsKeyDown(Code) and 1 or 0
    end

    local function Step(Delta)
        local Vehicle, Root, Seat = nil, nil, nil

        if Swim.Enabled then
            Vehicle, Root, Seat = Driving()
        end

        if Active and Active.Vehicle ~= Vehicle then
            Release()
        end

        local Line = Vehicle and Surface(Vehicle, Root)

        if not Line then
            return Release()
        end

        Active = Active or Take(Vehicle, Root)

        -- Natively amphibious vehicles keep the game's own swim unless the highway is on
        if Active.Native and not Swim.Highway then
            return
        end

        if not Active.Native then
            Vehicle:SetAttribute("WaterOwner", Player.UserId)
            Vehicle:SetAttribute("WaterLine", Line)
            Vehicle:SetAttribute("WaterPhase", "Swimming")
            -- The M113's swim drag; the highway drops the forward drag and keeps the sideways grip
            Vehicle:SetAttribute("SwimDrag", Swim.Highway and 0.05 or 0.5)
            Vehicle:SetAttribute("SwimLateralDrag", 3)
        end

        -- Thrust and turning from the seat, or the keys when the seat doesn't report them
        local Typing = UserInputService:GetFocusedTextBox() ~= nil
        local IsVehicleSeat = Seat:IsA("VehicleSeat")
        local Throttle = IsVehicleSeat and Seat.ThrottleFloat ~= 0 and Seat.ThrottleFloat or (Typing and 0 or Key(Enum.KeyCode.W) - Key(Enum.KeyCode.S))
        local Steer = IsVehicleSeat and Seat.SteerFloat ~= 0 and Seat.SteerFloat or (Typing and 0 or Key(Enum.KeyCode.D) - Key(Enum.KeyCode.A))

        -- The driver sits facing forward; the seat part's own facing isn't guaranteed
        local Body = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
        local Look = (Body or Seat).CFrame.LookVector
        local Forward = Vector3.new(Look.X, 0, Look.Z)
        Forward = Forward.Magnitude > 1e-3 and Forward.Unit or Vector3.zero

        -- Highway: hold Shift for the boost
        local Top = Swim.Speed

        if Swim.Highway and not Typing and UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
            Top *= Swim.Boost
        end

        local Velocity = Root.AssemblyLinearVelocity
        local Flat = Vector3.new(Velocity.X, 0, Velocity.Z)
        local Wanted = Forward * Throttle * (Throttle >= 0 and Top or Top * 0.5)
        local New = Flat:Lerp(Wanted, math.min(Delta * (Swim.Highway and 3 or 1.5), 1))
        local Spin = Root.AssemblyAngularVelocity
        local Turn = Spin.Y + (-Steer * Swim.Turn - Spin.Y) * math.min(Delta * 3, 1)

        local function Write()
            local Now = Root.AssemblyLinearVelocity
            Root.AssemblyLinearVelocity = Vector3.new(New.X, Now.Y, New.Z)

            local Current = Root.AssemblyAngularVelocity
            Root.AssemblyAngularVelocity = Vector3.new(Current.X, Turn, Current.Z)
        end

        -- Written now and again after the game's own water step, which applies its drag in the same frame
        Write()
        task.defer(pcall, Write)
    end

    local Card = DriveTab:Module({
        Title = "Amphibious",
        Description = "Drive any vehicle into the water and it floats and swims.",
        Icon = "waves",
        Side = "Right",
        Risky = true,
        Default = false,
        Flag = "Vehicle.Amphibious",
        Keybind = false,
        Opened = true,
        Callback = function(Value) Swim.Enabled = Value end
    })

    Card:Slider({Title = "Water speed", Min = 5, Max = 200, Step = 1, Default = 20, Suffix = " st/s", Flag = "Vehicle.Amphibious.Speed", Callback = function(Value) Swim.Speed = Value end})
    Card:Slider({Title = "Water turning", Min = 10, Max = 200, Step = 5, Default = 60, Suffix = "%", Flag = "Vehicle.Amphibious.Turn", Callback = function(Value) Swim.Turn = Value / 100 end})
    Card:Checkbox({Title = "Water highway", Tooltip = "Hold Shift to boost. Near-zero water drag, and takes over the M113 and MT-LB too.", Default = false, Flag = "Vehicle.Amphibious.Highway", Callback = function(Value) Swim.Highway = Value end})
    Card:Slider({Title = "Boost", Min = 1.5, Max = 8, Step = 0.5, Default = 3, Suffix = "x", Flag = "Vehicle.Amphibious.Boost", Callback = function(Value) Swim.Boost = Value end})
    Card:Slider({Title = "Ride height", Min = 0, Max = 4, Step = 0.5, Default = 1, Suffix = " st", Flag = "Vehicle.Amphibious.Ride", Tooltip = "Higher sits the hull deeper. Applies next time you enter water.", Callback = function(Value) Swim.Ride = Value end})

    local Connection = RunService.PreSimulation:Connect(function(Delta)
        if Running then
            pcall(Step, Delta)
        end
    end)

    OasisUI:OnUnload(function()
        Running = false
        Connection:Disconnect()
        pcall(Release)
    end)
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

    --// Strike planner: the spot where one shell kills the most enemies. The artillery shell kills inside 15 studs
    -- and hurts out to 70. The designation goes out like the button above (Binoculars "Designate" with an aim from
    -- your head) and lands where that aim hits, so only spots you can see from where you stand are offered.

    local Planner = {Enabled = false, Spare = true, Best = nil, Running = true}
    local PLAN_KILL, PLAN_BLAST = 15, 70

    local PlanParams = RaycastParams.new()
    PlanParams.FilterType = Enum.RaycastFilterType.Exclude
    PlanParams.IgnoreWater = true

    local function Flat(A, B)
        return Vector2.new(A.X - B.X, A.Z - B.Z).Magnitude
    end

    local function BestStrike()
        local Head = HeadOf(MyCharacter())

        if not Head then
            return nil
        end

        local Foes, Friends, Ignore = {}, {}, {Workspace.CurrentCamera}
        local IgnoreFolder = Workspace:FindFirstChild("Ignore")

        if IgnoreFolder then
            table.insert(Ignore, IgnoreFolder)
        end

        for _, Other in next, Players:GetPlayers() do
            local Character = Other.Character
            local Root = Character and Character:FindFirstChild("HumanoidRootPart")
            local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")

            if Character then
                table.insert(Ignore, Character)
            end

            if Root and Humanoid and Humanoid.Health > 0 then
                if Enemy(Other) then
                    table.insert(Foes, Root.Position)
                elseif Other == Player or SameTeam(Other) then
                    table.insert(Friends, Root.Position)
                end
            end
        end

        PlanParams.FilterDescendantsInstances = Ignore

        -- Candidate centres: every enemy, and the middle of every group around each enemy
        local Candidates = {}

        for _, Foe in next, Foes do
            table.insert(Candidates, Foe)

            local Sum, Count = Vector3.zero, 0

            for _, Other in next, Foes do
                if Flat(Foe, Other) <= PLAN_KILL * 2 then
                    Sum += Other
                    Count += 1
                end
            end

            if Count > 1 then
                table.insert(Candidates, Sum / Count)
            end
        end

        local Best

        for _, Centre in next, Candidates do
            if (Centre - Head.Position).Magnitude <= Spot.Range then
                local Kills, Hurt, Close, Near = 0, 0, 0, 0

                for _, Foe in next, Foes do
                    local Gap = Flat(Foe, Centre)
                    Kills += Gap <= PLAN_KILL and 1 or 0
                    Hurt += Gap <= PLAN_BLAST and 1 or 0
                end

                for _, Friend in next, Friends do
                    local Gap = Flat(Friend, Centre)
                    Close += Gap <= PLAN_KILL and 1 or 0
                    Near += Gap <= PLAN_BLAST and 1 or 0
                end

                local Score = Kills * 10 + Hurt - Near * 5

                if Kills > 0 and not (Planner.Spare and Close > 0) and (not Best or Score > Best.Score) then
                    -- The ground under the centre, and a clear line to it from your head
                    local Down = Workspace:Raycast(Centre + Vector3.new(0, 10, 0), Vector3.new(0, -60, 0), PlanParams)
                    local Point = Down and Down.Position

                    if Point then
                        local Aim = Point - Head.Position
                        local Sight = Workspace:Raycast(Head.Position, Aim + Aim.Unit * 2, PlanParams)

                        if Sight and (Sight.Position - Point).Magnitude <= 4 then
                            Best = {Point = Point, Kills = Kills, Hurt = Hurt, Friends = Near, Score = Score}
                        end
                    end
                end
            end
        end

        return Best
    end

    local function Designate(Best)
        local Head = HeadOf(MyCharacter())
        return Best and Head and Send(Remote("Binoculars"), "Designate", (Best.Point - Head.Position).Unit)
    end

    -- Marker: a kill ring and a label at the best spot
    local PlanRing = Instance.new("CylinderHandleAdornment")
    PlanRing.Adornee = Workspace.Terrain
    PlanRing.Height = 0.2
    PlanRing.Radius = PLAN_KILL
    PlanRing.InnerRadius = PLAN_KILL - 0.8
    PlanRing.Color3 = Color3.fromRGB(255, 210, 60)
    PlanRing.Transparency = 0.2
    PlanRing.AlwaysOnTop = true
    PlanRing.Visible = false
    PlanRing.Parent = (gethui and gethui()) or game:GetService("CoreGui")

    local PlanLabel = Drawing and Drawing.new("Text")

    if PlanLabel then
        PlanLabel.Visible = false
        PlanLabel.Center = true
        PlanLabel.Outline = true
        PlanLabel.Size = 16
        PlanLabel.Font = 2
        PlanLabel.Color = Color3.fromRGB(255, 210, 60)
    end

    RadioSection:Toggle({Title = "Strike planner", Tooltip = "Marks the visible spot where a shell kills the most enemies.", Default = false, Flag = "Support.Planner", Callback = function(Value) Planner.Enabled = Value end})
    RadioSection:Checkbox({Title = "Spare teammates", Tooltip = "Never picks a spot with a teammate (or you) inside the kill ring.", Default = true, Flag = "Support.Planner.Spare", Callback = function(Value) Planner.Spare = Value end})

    RadioSection:Buttons({
        {Title = "Designate best spot", Icon = "target", Callback = function()
            local Best = BestStrike()

            if not Best then
                return Notify("Strike planner", "No enemy group you can see from here.", "Warning")
            end

            Notify("Strike planner", Designate(Best) and ("Designated. %d in the kill ring, %d in blast range."):format(Best.Kills, Best.Hurt) or "No Binoculars remote.", "Info")
        end},
        {Title = "Designate + call", Icon = "radio", Style = "Primary", Callback = function() task.spawn(function()
            local Name = SupportPick:Get()
            local Best = BestStrike()

            if not Name then
                return Notify("Strike planner", "Pick a support first.", "Warning")
            elseif not (Best and Designate(Best)) then
                return Notify("Strike planner", "No enemy group you can see from here.", "Warning")
            end

            -- A moment for the designation to land before the call reads it
            task.wait(0.3)
            Send(Remote("Radio"), "Callout", Name)
            Notify("Strike planner", ("Called %s on %d enemies."):format(Name, Best.Kills), "Info")
        end) end}
    })

    task.spawn(function()
        while Planner.Running do
            local Ok, Best = pcall(function()
                return Planner.Enabled and BestStrike() or nil
            end)

            Planner.Best = Ok and Best or nil
            PlanRing.Visible = Planner.Best ~= nil

            if Planner.Best then
                PlanRing.CFrame = CFrame.new(Planner.Best.Point) * CFrame.Angles(math.rad(90), 0, 0)
            end

            task.wait(0.3)
        end
    end)

    local PlanLoop = RunService.RenderStepped:Connect(function()
        if not PlanLabel then
            return
        end

        local Best = Planner.Best
        local Screen, OnScreen

        if Best then
            Screen, OnScreen = Workspace.CurrentCamera:WorldToViewportPoint(Best.Point + Vector3.new(0, 4, 0))
        end

        PlanLabel.Visible = OnScreen == true

        if OnScreen then
            PlanLabel.Position = Vector2.new(Screen.X, Screen.Y)
            PlanLabel.Text = ("STRIKE HERE  %d kill%s  %d hurt%s"):format(Best.Kills, Best.Kills == 1 and "" or "s", Best.Hurt, Best.Friends > 0 and ("  %d friendly near"):format(Best.Friends) or "")
        end
    end)

    OasisUI:OnUnload(function()
        Planner.Running = false
        PlanLoop:Disconnect()
        PlanRing:Destroy()

        if PlanLabel then
            PlanLabel:Remove()
        end
    end)

    --// Squad markers: the squad ping (Remotes.Squad "PlaceMarker", position, part) put on enemies for you. Pinned
    -- to a part of their body, so it marks them for your whole squad through the game's own HUD. Needs a squad;
    -- the game allows one ping every 2 seconds.

    local Marker = {Auto = false, Mode = "Nearest to you", Every = 4, VisibleOnly = true, Range = 1500, Last = 0, Running = true}

    local function MarkTarget()
        local Head = HeadOf(MyCharacter())
        local Camera = Workspace.CurrentCamera
        local Mouse = UserInputService:GetMouseLocation()
        local Best, BestScore

        if not Head then
            return nil
        end

        for _, Other in next, Players:GetPlayers() do
            local Character = Enemy(Other) and Other.Character
            local Target = HeadOf(Character)
            local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")

            if Target and Humanoid and Humanoid.Health > 0 and not IsDowned(Character) then
                local Distance = (Target.Position - Head.Position).Magnitude

                if Distance <= Marker.Range and (not Marker.VisibleOnly or ClearLine(Head.Position, Character)) then
                    local Score

                    if Marker.Mode == "Nearest to you" then
                        Score = Distance
                    else
                        local Screen, OnScreen = Camera:WorldToViewportPoint(Target.Position)
                        Score = OnScreen and (Vector2.new(Screen.X, Screen.Y) - Mouse).Magnitude or nil
                    end

                    if Score and (not BestScore or Score < BestScore) then
                        Best, BestScore = Target, Score
                    end
                end
            end
        end

        return Best
    end

    local function PlaceMarker(Quiet)
        if os.clock() - Marker.Last < 2 then
            return Quiet or Notify("Squad markers", "The game allows one ping every 2 seconds.", "Warning", 2)
        end

        local Target = MarkTarget()

        if not Target then
            return Quiet or Notify("Squad markers", "No enemy to mark.", "Warning", 2)
        end

        Marker.Last = os.clock()

        if not Send(Remote("Squad"), "PlaceMarker", Target.Position, Target) and not Quiet then
            Notify("Squad markers", "No Squad remote.", "Error", 3)
        end
    end

    local MarkerSection = SupportTab:Section({Title = "Squad markers", Icon = "map-pin", Side = "Left"})
    MarkerSection:Dropdown({Title = "Target", Values = {"Nearest to you", "Crosshair"}, Default = "Nearest to you", Flag = "Support.Markers.Mode", Callback = function(Value) Marker.Mode = Value end})
    MarkerSection:Button({Title = "Mark enemy", Icon = "map-pin", Style = "Primary", Callback = function() PlaceMarker(false) end})
    MarkerSection:Toggle({Title = "Auto-mark", Tooltip = "Keeps a ping on the target for your squad. You need to be in a squad.", Default = false, Flag = "Support.Markers.Auto", Callback = function(Value) Marker.Auto = Value end})
    MarkerSection:Slider({Title = "Every", Min = 2, Max = 20, Step = 1, Default = 4, Suffix = " s", Flag = "Support.Markers.Every", Callback = function(Value) Marker.Every = Value end})
    MarkerSection:Toggle({Title = "Visible only", Tooltip = "Only mark enemies you can see, so the pings look like your own.", Default = true, Flag = "Support.Markers.Visible", Callback = function(Value) Marker.VisibleOnly = Value end})
    MarkerSection:Slider({Title = "Range", Min = 100, Max = 5000, Step = 100, Default = 1500, Suffix = " st", Flag = "Support.Markers.Range", Callback = function(Value) Marker.Range = Value end})

    task.spawn(function()
        while Marker.Running do
            if Marker.Auto and os.clock() - Marker.Last >= Marker.Every then
                pcall(PlaceMarker, true)
            end

            task.wait(0.5)
        end
    end)

    OasisUI:OnUnload(function()
        Marker.Running = false
    end)

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

    -- The server opens a vote with Match "StartMapVoting" (MapsInfo: map name -> info) or "StartGameVoting" (Options:
    -- cards of {Index, MapName, Mode, Weather, TimeOfDay}), and takes a vote as Match("MapVote", map name) or
    -- Match("GameVote", card index). Listening to those messages works whether or not the vote screen is drawn.
    local Vote = {Auto = false, Map = "", Mode = "", Spam = false}
    local Ballot -- the open vote: {Kind, Choice, Sent}
    local SeenMaps, SeenModes = {}, {}

    local function Matches(Value, Wanted)
        return Wanted ~= "" and type(Value) == "string" and Value:lower():find(Wanted:lower(), 1, true) ~= nil
    end

    -- The card for your map and mode: both is best, then the map, then the mode
    local function Choose(Kind, Data)
        if Kind == "Map" then
            for Name in next, type(Data.MapsInfo) == "table" and Data.MapsInfo or {} do
                if Matches(Name, Vote.Map) then
                    return Name
                end
            end

            return nil
        end

        local Best, BestScore = nil, 0

        for _, Card in next, type(Data.Options) == "table" and Data.Options or {} do
            local Score = (Matches(Card.MapName, Vote.Map) and 2 or 0) + (Matches(Card.Mode, Vote.Mode) and 1 or 0)

            if Score > BestScore then
                Best, BestScore = Card.Index, Score
            end
        end

        return Best
    end

    local function CastVote()
        if not (Vote.Auto and Ballot and Ballot.Choice ~= nil) or Ballot.Sent and not Vote.Spam then
            return
        end

        Ballot.Sent = Send(Remote("Match"), Ballot.Kind == "Map" and "MapVote" or "GameVote", Ballot.Choice)
    end

    local MatchRemote = Remote("Match")
    local VoteConnection = MatchRemote and MatchRemote.OnClientEvent:Connect(function(Name, Data)
        if Name == "StartMapVoting" or Name == "StartGameVoting" then
            local Kind = Name == "StartMapVoting" and "Map" or "Game"
            Data = type(Data) == "table" and Data or {}

            for Map in next, type(Data.MapsInfo) == "table" and Data.MapsInfo or {} do
                SeenMaps[Map] = true
            end

            for _, Card in next, type(Data.Options) == "table" and Data.Options or {} do
                SeenMaps[tostring(Card.MapName)] = true
                SeenModes[tostring(Card.Mode)] = true
            end

            Ballot = {Kind = Kind, Data = Data, Choice = Choose(Kind, Data)}

            -- A beat after the screen opens, like a person clicking
            task.delay(0.6, CastVote)
        elseif Name == "EndVoting" or Name == "EndGameVoting" then
            Ballot = nil
        end
    end)

    -- Called every second by the support loop: catches a vote that opened before Auto-vote was on, and resends
    local function UpdateVotes()
        if Ballot and Ballot.Choice == nil then
            Ballot.Choice = Choose(Ballot.Kind, Ballot.Data)
        end

        CastVote()
    end

    OasisUI:OnUnload(function()
        if VoteConnection then
            VoteConnection:Disconnect()
        end
    end)

    local Votes = MatchTab:Section({Title = "Votes", Icon = "vote", Side = "Left"})
    Votes:Toggle({Title = "Auto-vote", Tooltip = "Votes for your map and mode the moment voting opens.", Default = false, Flag = "Match.AutoVote", Callback = function(Value) Vote.Auto = Value end})

    -- Map names come from the admin command list (its map argument) plus every vote seen this session
    local function MapNames()
        local Names, Seen = {}, {}

        local function Add(Name)
            if type(Name) == "string" and Name ~= "" and Name ~= "nil" and not Seen[Name] then
                Seen[Name] = true
                table.insert(Names, Name)
            end
        end

        local Commands = Require(Shared and Shared:FindFirstChild("ControlPanelCommands"))
        local Known = type(Commands) == "table" and Commands.MapNames

        for Key, Value in next, type(Known) == "table" and Known or {} do
            Add(type(Key) == "string" and Key or Value)
        end

        for Name in next, SeenMaps do
            Add(Name)
        end

        table.sort(Names)
        return Names
    end

    local function ModeNames()
        local Names = {}

        for Name in next, SeenModes do
            if Name ~= "nil" then
                table.insert(Names, Name)
            end
        end

        table.sort(Names)
        return Names
    end

    local MapPick, ModePick
    MapPick = Votes:Dropdown({
        Title = "Map",
        Values = MapNames(),
        Search = true,
        AllowNone = true,
        Flag = "Match.AutoVote.Map",
        Action = {Icon = "refresh-cw", Tooltip = "Refresh", Callback = function() MapPick:Refresh(MapNames(), true) end},
        Callback = function(Value) Vote.Map = type(Value) == "string" and Value or "" end
    })
    ModePick = Votes:Dropdown({
        Title = "Mode",
        Values = ModeNames(),
        AllowNone = true,
        Flag = "Match.AutoVote.Mode",
        Tooltip = "Fills in after the first game vote you see. Refresh then.",
        Action = {Icon = "refresh-cw", Tooltip = "Refresh", Callback = function() ModePick:Refresh(ModeNames(), true) end},
        Callback = function(Value) Vote.Mode = type(Value) == "string" and Value or "" end
    })
    Votes:Checkbox({Title = "Vote repeatedly", Tooltip = "Resends your vote every second while voting is open.", Default = false, Flag = "Match.AutoVote.Spam", Callback = function(Value) Vote.Spam = Value end})

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

            for _, Seat in next, CollectionService:GetTagged("FactoryVehicleSeat") do
                local Occupant = Seat:FindFirstChild("Occupant")

                if Occupant and Occupant:IsA("ObjectValue") and Occupant.Value ~= nil then
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

--// Alerts: incoming strikes, live grenades, enemies aiming at you, gunfire, objective pressure.
-- All of it reads what the server already replicates to every client; nothing here is sent anywhere.

do
    local CollectionService = game:GetService("CollectionService")
    local Running = true

    local Alert = {
        Strikes = false, FriendlyStrikes = true,
        Grenades = false, GrenadeRange = 60,
        Aimed = false, AimedCone = 4, AimedRange = 800, Arrows = true,
        Gunfire = false, GunfireFriendly = false, GunfireTime = 5, NearMiss = true, GunfireMap = true,
        Objectives = false, ObjectiveLabels = true, CaptureClock = true,
        Magazines = false, MagazineRange = 400, TurretAmmo = true,
        BlindSpots = false, BlindRadius = 60, BlindCone = 60, BlindSafe = true
    }

    local RED, ORANGE, BLUE, WHITE = Color3.fromRGB(255, 70, 70), Color3.fromRGB(255, 170, 60), Color3.fromRGB(90, 150, 255), Color3.fromRGB(235, 235, 235)
    local STUDS_PER_METER = 3.57

    -- The artillery shell's explosionSettings: certain death inside KillRange, damage out to Range
    local STRIKE_KILL, STRIKE_RANGE = 15, 70

    -- Grenade fallbacks by GrenadeType, from GrenadeConfigManager (M67, RGD-5, F-1 / RGO, M33A1)
    local GRENADE_DEFAULTS = {Frag = {Fuze = 4, Kill = 10, Range = 40}, Impact = {Fuze = 1, Kill = 10, Range = 40}}

    local Ballistics = Shared and Shared:FindFirstChild("Ballistics")
    local ShotCodec = Require(Ballistics and Ballistics:FindFirstChild("ShotCodec"))
    local MatchObjectives = Require(Shared and Shared:FindFirstChild("MatchObjectives"))
    local TriggerVolume = Require(Shared and Shared:FindFirstChild("TriggerVolume"))
    local GrenadeConfigs = Shared and Shared:FindFirstChild("GrenadeConfigManager")

    local Folder = Instance.new("Folder")
    Folder.Name = "SuperNovaAlerts"
    Folder.Parent = (gethui and gethui()) or game:GetService("CoreGui")

    local function IsEnemy(Other)
        return Other ~= Player and Other.Team ~= nil and Player.Team ~= nil and Other.Team ~= Player.Team
    end

    local function RootOf(Character)
        return Character and (Character.PrimaryPart or Character:FindFirstChild("HumanoidRootPart"))
    end

    local function Alive(Character)
        local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
        return Humanoid ~= nil and Humanoid.Health > 0
    end

    local function Meters(Studs)
        return math.floor(Studs / STUDS_PER_METER + 0.5)
    end

    -- Keyed pools: one object per key, and everything whose key wasn't seen this pass is destroyed
    local function Pool(Make)
        local Items = {}

        return {
            Get = function(Key)
                Items[Key] = Items[Key] or Make()
                return Items[Key]
            end,
            Sweep = function(Seen)
                for Key, Item in next, Items do
                    if not Seen[Key] then
                        Item.Destroy()
                        Items[Key] = nil
                    end
                end
            end
        }
    end

    local function NewTag()
        local Gui = Instance.new("BillboardGui")
        Gui.Size = UDim2.fromOffset(220, 34)
        Gui.StudsOffset = Vector3.new(0, 3, 0)
        Gui.AlwaysOnTop = true
        Gui.LightInfluence = 0

        local Label = Instance.new("TextLabel")
        Label.Size = UDim2.fromScale(1, 1)
        Label.BackgroundTransparency = 1
        Label.Font = Enum.Font.GothamBold
        Label.TextSize = 13
        Label.TextStrokeTransparency = 0.35
        Label.Parent = Gui

        Gui.Parent = Folder
        return {Gui = Gui, Label = Label, Destroy = function() Gui:Destroy() end}
    end

    -- A flat ring on the ground, drawn through walls. Adorned to Terrain, whose CFrame is the world origin.
    local function NewRing(Color, Transparency)
        local Ring = Instance.new("CylinderHandleAdornment")
        Ring.Adornee = Workspace.Terrain
        Ring.Height = 0.2
        Ring.Color3 = Color
        Ring.Transparency = Transparency
        Ring.AlwaysOnTop = true
        Ring.ZIndex = 1
        Ring.Parent = Folder
        return Ring
    end

    local function PlaceRing(Ring, Position, Radius, Width)
        Ring.Radius = Radius
        Ring.InnerRadius = math.max(Radius - Width, 0)
        Ring.CFrame = CFrame.new(Position) * CFrame.Angles(math.rad(90), 0, 0)
    end

    -- A danger zone: kill ring, blast ring and a label at the centre (also hung off Terrain, by world offset)
    local function NewZone()
        local Zone = NewTag()
        Zone.Gui.Adornee = Workspace.Terrain
        Zone.Gui.StudsOffset = Vector3.zero
        Zone.Kill = NewRing(RED, 0.25)
        Zone.Blast = NewRing(ORANGE, 0.55)

        Zone.Destroy = function()
            Zone.Gui:Destroy()
            Zone.Kill:Destroy()
            Zone.Blast:Destroy()
        end

        return Zone
    end

    local function PlaceZone(Zone, Position, Kill, Range, Text, Color)
        PlaceRing(Zone.Kill, Position, Kill, 0.8)
        PlaceRing(Zone.Blast, Position, Range, 0.5)
        Zone.Gui.StudsOffsetWorldSpace = Position + Vector3.new(0, 3, 0)
        Zone.Label.Text = Text
        Zone.Label.TextColor3 = Color
    end

    --// On-screen warnings: stacked lines at the top, and arrows around the crosshair pointing at the threat

    local Lines, Arrows = {}, {}
    local Warnings, Pointers = {}, {}

    local function DrawingOf(List, Index, Kind)
        if not Drawing then
            return nil
        end

        local Object = List[Index]

        if not Object then
            Object = Drawing.new(Kind)

            if Kind == "Text" then
                Object.Center = true
                Object.Outline = true
                Object.Size = 20
                Object.Font = 2
            else
                Object.Filled = true
                Object.Thickness = 1
                Object.Transparency = 0.85
            end

            List[Index] = Object
        end

        return Object
    end

    local function HideFrom(List, First)
        for Index = First, #List do
            List[Index].Visible = false
        end
    end

    local function DrawWarnings()
        local Camera = Workspace.CurrentCamera

        for Index, Warning in next, Warnings do
            local Line = DrawingOf(Lines, Index, "Text")

            if Line then
                Line.Text = Warning[1]
                Line.Color = Warning[2]
                Line.Position = Vector2.new(Camera.ViewportSize.X / 2, 96 + (Index - 1) * 24)
                Line.Visible = true
            end
        end

        HideFrom(Lines, #Warnings + 1)
    end

    -- Every frame, so the arrows turn with the camera
    local function DrawArrows()
        local Camera = Workspace.CurrentCamera
        local Count = 0

        if Alert.Arrows then
            local Centre = Camera.ViewportSize / 2

            for _, Pointer in next, Pointers do
                local Relative = Camera.CFrame:PointToObjectSpace(Pointer[1])
                local Flat = Vector2.new(Relative.X, Relative.Z)

                if Flat.Magnitude > 1e-3 then
                    Count += 1

                    local Direction = Flat.Unit
                    local Side = Vector2.new(-Direction.Y, Direction.X)
                    local Base = Centre + Direction * 120
                    local Arrow = DrawingOf(Arrows, Count, "Triangle")

                    if Arrow then
                        Arrow.PointA = Base + Direction * 16
                        Arrow.PointB = Base + Side * 9
                        Arrow.PointC = Base - Side * 9
                        Arrow.Color = Pointer[2]
                        Arrow.Visible = true
                    end
                end
            end
        end

        HideFrom(Arrows, Count + 1)
    end

    --// Incoming strikes: a radioman's designated target is a Vector3Value in their CharacterValues, and it
    -- replicates to everyone. Vector3.zero means no target.

    local Zones = Pool(NewZone)

    local function UpdateStrikes(MyPosition)
        local Seen = {}

        if not Alert.Strikes then
            return Zones.Sweep(Seen)
        end

        for _, Other in next, Players:GetPlayers() do
            local Values = Other.Character and Other.Character:FindFirstChild("CharacterValues")
            local Designated = Values and Values:FindFirstChild("DesignatedPosition")
            local Enemy = IsEnemy(Other)

            if Designated and Designated:IsA("Vector3Value") and Designated.Value ~= Vector3.zero and (Enemy or Alert.FriendlyStrikes) then
                local Target = Designated.Value
                local Key = "Strike" .. Other.UserId
                local Gap = MyPosition and (Vector3.new(MyPosition.X, Target.Y, MyPosition.Z) - Target).Magnitude
                Seen[Key] = true

                PlaceZone(Zones.Get(Key), Target, STRIKE_KILL, STRIKE_RANGE, (Enemy and "ENEMY STRIKE" or "FRIENDLY STRIKE") .. (Gap and ("  " .. Meters(Gap) .. " m") or ""), Enemy and RED or BLUE)

                if Gap and Gap <= STRIKE_KILL then
                    table.insert(Warnings, {"ARTILLERY: inside the kill zone, move", RED})
                    table.insert(Pointers, {Target, RED})
                elseif Gap and Gap <= STRIKE_RANGE then
                    table.insert(Warnings, {("ARTILLERY: inside blast range (%d m from centre)"):format(Meters(Gap)), ORANGE})
                end
            end
        end

        Zones.Sweep(Seen)
    end

    --// Grenades: thrown grenades are parts in workspace.Ignore.Dropped carrying a GrenadeType attribute

    local FirstSeen = setmetatable({}, {__mode = "k"})
    local ConfigCache = {}
    local GrenadeZones = Pool(NewZone)

    local function GrenadeConfig(Part)
        local Name = Part.Name

        if ConfigCache[Name] == nil then
            local Config = Require(GrenadeConfigs and GrenadeConfigs:FindFirstChild(Name))
            local Blast = type(Config) == "table" and type(Config.explosionSettings) == "table" and Config.explosionSettings
            local Fallback = GRENADE_DEFAULTS[Part:GetAttribute("GrenadeType")] or GRENADE_DEFAULTS.Frag

            ConfigCache[Name] = {
                Fuze = type(Config) == "table" and tonumber(Config.Fuze) or Fallback.Fuze,
                Kill = Blast and tonumber(Blast.KillRange) or Fallback.Kill,
                Range = Blast and tonumber(Blast.Range) or Fallback.Range
            }
        end

        return ConfigCache[Name]
    end

    local function UpdateGrenades(MyPosition)
        local Seen = {}
        local Ignore = Workspace:FindFirstChild("Ignore")
        local Dropped = Alert.Grenades and Ignore and Ignore:FindFirstChild("Dropped")

        for _, Part in next, Dropped and Dropped:GetChildren() or {} do
            local Kind = Part:IsA("BasePart") and Part:GetAttribute("GrenadeType")

            if Kind and Kind ~= "Smoke" then
                local Gap = MyPosition and (Part.Position - MyPosition).Magnitude
                FirstSeen[Part] = FirstSeen[Part] or os.clock()

                if Gap and Gap <= Alert.GrenadeRange then
                    local Config = GrenadeConfig(Part)

                    -- Counted from when it appeared; a cooked grenade goes off sooner
                    local Left = math.max(Config.Fuze - (os.clock() - FirstSeen[Part]), 0)
                    local Timer = Kind == "Impact" and "impact" or ("%.1f s"):format(Left)
                    local Color = Gap <= Config.Kill and RED or ORANGE
                    Seen[Part] = true

                    PlaceZone(GrenadeZones.Get(Part), Part.Position - Vector3.new(0, Part.Size.Y / 2, 0), Config.Kill, Config.Range, ("%s  %s  %d m"):format(string.upper(Kind), Timer, Meters(Gap)), Color)

                    if Gap <= Config.Range then
                        table.insert(Warnings, {("GRENADE %s: %s"):format(Timer, Gap <= Config.Kill and "inside the kill radius, move" or "inside blast range"), Color})
                        table.insert(Pointers, {Part.Position, Color})
                    end
                end
            end
        end

        GrenadeZones.Sweep(Seen)
    end

    --// Being aimed at: another player's head is posed from their camera pitch and yaw (BodyRotation), so the
    -- head's facing is where they look. A narrow cone onto your head, a gun in hand and a clear line means a threat.

    local SightParams = RaycastParams.new()
    SightParams.FilterType = Enum.RaycastFilterType.Exclude
    SightParams.IgnoreWater = true

    local function UpdateAimed()
        local Mine = Player.Character and Player.Character:FindFirstChild("Head")

        if not (Alert.Aimed and Mine) then
            return
        end

        for _, Other in next, Players:GetPlayers() do
            local Character = IsEnemy(Other) and Other.Character
            local Head = Character and Character:FindFirstChild("Head")

            if Head and Alive(Character) and Character:FindFirstChildOfClass("Tool") then
                local Offset = Mine.Position - Head.Position
                local Distance = Offset.Magnitude

                if Distance <= Alert.AimedRange and Distance > 1 then
                    local Angle = math.deg(math.acos(math.clamp(Head.CFrame.LookVector:Dot(Offset.Unit), -1, 1)))

                    -- Up close the cone widens so a body-width miss still counts
                    if Angle <= Alert.AimedCone or Distance * math.sin(math.rad(Angle)) <= 2.5 and Angle < 45 then
                        local Ignore = {Character, Workspace.CurrentCamera}
                        local IgnoreFolder = Workspace:FindFirstChild("Ignore")

                        if IgnoreFolder then
                            table.insert(Ignore, IgnoreFolder)
                        end

                        SightParams.FilterDescendantsInstances = Ignore

                        local Result = Workspace:Raycast(Head.Position, Offset, SightParams)

                        if not Result or Result.Instance:IsDescendantOf(Player.Character) then
                            table.insert(Warnings, {("AIMED AT: %s  %d m"):format(Other.DisplayName, Meters(Distance)), RED})
                            table.insert(Pointers, {Head.Position, RED})
                        end
                    end
                end
            end
        end
    end

    --// Gunfire locator: every shot fired anywhere reaches every client as one BallisticsNet.ShotBroadcast packet.
    -- ShotCodec.decodeBroadcast gives the shooter's net slot (the NetSlot attribute on their Player), the muzzle
    -- offset from their root part and every pellet's direction, so each shot names its shooter and its line.

    local Shots = {} -- Player -> {At, Position}
    local NearMisses = {} -- Player -> time
    local MapMarks = setmetatable({}, {__mode = "k"}) -- characters we put on the map, and until when
    local ShotTags = Pool(NewTag)

    local function BySlot(Slot)
        for _, Other in next, Players:GetPlayers() do
            if Other:GetAttribute("NetSlot") == Slot then
                return Other
            end
        end
    end

    --// Magazine counter: the same shot packets, counted against the magazine size in the shooter's weapon config.
    -- A reload is spotted three ways: the reload animation from that config playing on their character, the magazine
    -- running dry (reloaded once ReloadTime has passed), or a long pause (most players top up when it goes quiet).

    local Magazines = {} -- Player -> {Weapon, Fired, Size, ReloadTime, ReloadIds, EmptyAt, Last}
    local CountRounds

    local function WeaponOf(Shooter)
        local Tool = Shooter.Character and Shooter.Character:FindFirstChildOfClass("Tool")
        return Tool and Tool.Name
    end

    local function MagazineFor(Shooter)
        local Weapon = WeaponOf(Shooter)
        local Entry = Magazines[Shooter]

        if not Weapon then
            return nil
        end

        -- A new gun in hand starts a fresh count
        if not Entry or Entry.Weapon ~= Weapon then
            local Config = WeaponManager and select(2, pcall(WeaponManager.GetMuzzleConfig, WeaponManager, Weapon, 1))
            local Size = type(Config) == "table" and tonumber(Config.Ammo)

            if not Size then
                Magazines[Shooter] = nil
                return nil
            end

            local Animations = type(Config.Animations) == "table" and Config.Animations or {}

            Entry = {
                Weapon = Weapon,
                Fired = 0,
                Size = Size,
                ReloadTime = tonumber(Config.ReloadTime) or 3,
                ReloadIds = {[tostring(Animations.Reload)] = true, [tostring(Animations.ReloadUnchambered)] = true},
                Last = os.clock()
            }

            Magazines[Shooter] = Entry
        end

        return Entry
    end

    function CountRounds(Shooter, Rounds)
        local Entry = MagazineFor(Shooter)

        if Entry then
            Entry.Fired = math.min(Entry.Fired + Rounds, Entry.Size)
            Entry.Last = os.clock()

            if Entry.Fired >= Entry.Size and not Entry.EmptyAt then
                Entry.EmptyAt = os.clock()
            end
        end
    end

    local function Reloading(Shooter, Entry)
        local Humanoid = Shooter.Character and Shooter.Character:FindFirstChildOfClass("Humanoid")
        local Animator = Humanoid and Humanoid:FindFirstChildOfClass("Animator")

        for _, Track in next, Animator and Animator:GetPlayingAnimationTracks() or {} do
            if Track.Animation and Entry.ReloadIds[Track.Animation.AnimationId] then
                return true
            end
        end

        return false
    end

    local function OnBroadcast(Packet)
        if not ((Alert.Gunfire or Alert.Magazines) and ShotCodec) then
            return
        end

        local Ok, Shooters = pcall(ShotCodec.decodeBroadcast, Packet)
        local Mine = Player.Character and Player.Character:FindFirstChild("Head")

        for _, Shot in next, Ok and type(Shooters) == "table" and Shooters or {} do
            local Shooter = BySlot(Shot.ShooterSlot)
            local Root = Shooter and Shooter ~= Player and RootOf(Shooter.Character)

            -- Magazine counter: every discharge is one round out of the shooter's magazine
            if Root and IsEnemy(Shooter) and Alert.Magazines and type(Shot.Discharges) == "table" then
                CountRounds(Shooter, #Shot.Discharges)
            end

            if Root and Alert.Gunfire and (IsEnemy(Shooter) or Alert.GunfireFriendly) then
                for _, Discharge in next, type(Shot.Discharges) == "table" and Shot.Discharges or {} do
                    local Origin = Root.Position + (typeof(Discharge.OriginOffset) == "Vector3" and Discharge.OriginOffset or Vector3.zero)
                    Shots[Shooter] = {At = os.clock(), Position = Origin}

                    -- Closest approach of each pellet's line to your head
                    for _, Pellet in next, Mine and Alert.NearMiss and type(Discharge.Pellets) == "table" and Discharge.Pellets or {} do
                        local Direction = type(Pellet) == "table" and (Pellet.Direction or Pellet[1]) or Pellet

                        if typeof(Direction) == "Vector3" and Direction.Magnitude > 0 then
                            local Line = Mine.Position - Origin
                            local Along = Line:Dot(Direction.Unit)

                            if Along > 0 and (Line - Direction.Unit * Along).Magnitude <= 8 then
                                NearMisses[Shooter] = os.clock()
                            end
                        end
                    end
                end
            end
        end
    end

    local BroadcastConnection
    local Net = ReplicatedStorage:FindFirstChild("BallisticsNet")
    local Broadcast = Net and Net:FindFirstChild("ShotBroadcast")

    if Broadcast then
        BroadcastConnection = Broadcast.OnClientEvent:Connect(function(Packet)
            pcall(OnBroadcast, Packet)
        end)
    end

    local function UpdateGunfire(MyPosition)
        local Now, Seen = os.clock(), {}

        for Shooter, Shot in next, Shots do
            local Character = Shooter.Parent and Shooter.Character

            if not Alert.Gunfire or Now - Shot.At > Alert.GunfireTime or not Character then
                Shots[Shooter] = nil
            else
                local Head = Character:FindFirstChild("Head") or RootOf(Character)

                if Head then
                    local Tag = ShotTags.Get(Shooter)
                    local Enemy = IsEnemy(Shooter)
                    Seen[Shooter] = true

                    Tag.Gui.Adornee = Head
                    Tag.Label.Text = ("FIRING  %s%s"):format(Shooter.DisplayName, MyPosition and ("  " .. Meters((Head.Position - MyPosition).Magnitude) .. " m") or "")
                    Tag.Label.TextColor3 = Enemy and RED or BLUE
                    Tag.Label.TextTransparency = math.clamp((Now - Shot.At) / Alert.GunfireTime, 0, 0.7)

                    -- On your map too: the map draws anyone whose character carries SpottedBy
                    if Enemy and Alert.GunfireMap and Character:GetAttribute("SpottedBy") == nil then
                        Character:SetAttribute("SpottedBy", true)
                        MapMarks[Character] = true
                    end
                end
            end
        end

        ShotTags.Sweep(Seen)

        for Shooter, At in next, NearMisses do
            local Root = Shooter.Parent and RootOf(Shooter.Character)

            if not Alert.Gunfire or not Root or Now - At > 2.5 then
                NearMisses[Shooter] = nil
            else
                table.insert(Warnings, {("UNDER FIRE: %s%s"):format(Shooter.DisplayName, MyPosition and ("  " .. Meters((Root.Position - MyPosition).Magnitude) .. " m") or ""), RED})
                table.insert(Pointers, {Root.Position, RED})
            end
        end

        -- Map marks last as long as the tag; only our own marks are cleared, a real spot stays
        for Character in next, MapMarks do
            local Shooter = Players:GetPlayerFromCharacter(Character)

            if not (Shooter and Seen[Shooter] and Alert.GunfireMap) then
                if Character.Parent and Character:GetAttribute("SpottedBy") == true then
                    Character:SetAttribute("SpottedBy", nil)
                end

                MapMarks[Character] = nil
            end
        end
    end

    local MagazineTags = Pool(NewTag)
    local TurretTags = Pool(NewTag)
    local Rigs, LastRigScan = {}, 0

    local function UpdateMagazines(MyPosition)
        local Seen, Now = {}, os.clock()

        for Shooter, Entry in next, Magazines do
            local Character = Shooter.Parent and Shooter.Character
            local Head = Character and Character:FindFirstChild("Head")

            if not (Alert.Magazines and Head and Alive(Character)) or WeaponOf(Shooter) ~= Entry.Weapon then
                Magazines[Shooter] = nil
            else
                local Animating = Reloading(Shooter, Entry)

                -- Ran dry and the reload time has passed, or a reload animation just finished, or a long quiet spell
                if Entry.EmptyAt and Now - Entry.EmptyAt > Entry.ReloadTime + 0.3 or Entry.WasAnimating and not Animating or Now - Entry.Last > 8 then
                    Entry.Fired, Entry.EmptyAt = 0, nil
                end

                Entry.WasAnimating = Animating

                if MyPosition and (Head.Position - MyPosition).Magnitude <= Alert.MagazineRange then
                    local Left = Entry.Size - Entry.Fired
                    local Tag = MagazineTags.Get(Shooter)
                    Seen[Shooter] = true

                    Tag.Gui.Adornee = Head
                    Tag.Gui.StudsOffset = Vector3.new(0, 4.5, 0)

                    if Animating or Entry.EmptyAt then
                        Tag.Label.Text = "RELOADING"
                        Tag.Label.TextColor3 = RED
                    else
                        Tag.Label.Text = ("~%d / %d"):format(Left, Entry.Size)
                        Tag.Label.TextColor3 = Left <= Entry.Size * 0.3 and ORANGE or WHITE
                    end
                end
            end
        end

        MagazineTags.Sweep(Seen)

        -- Mounted guns publish their exact count: the turret rig carries Ammo and Reloading attributes
        local TurretSeen = {}

        if Alert.Magazines and Alert.TurretAmmo then
            local Vehicles = Workspace:FindFirstChild("Vehicles")

            if Vehicles and Now - LastRigScan > 2 then
                LastRigScan = Now
                table.clear(Rigs)

                for _, Object in next, Vehicles:GetDescendants() do
                    if type(Object:GetAttribute("Ammo")) == "number" and (Object:IsA("Model") or Object:IsA("BasePart")) then
                        table.insert(Rigs, Object)
                    end
                end
            end

            for _, Rig in next, Rigs do
                local Anchor = Rig.Parent and (Rig:IsA("BasePart") and Rig or Rig.PrimaryPart or Rig:FindFirstChildWhichIsA("BasePart", true))

                if Anchor and MyPosition and (Anchor.Position - MyPosition).Magnitude <= Alert.MagazineRange * 2 then
                    local Tag = TurretTags.Get(Rig)
                    TurretSeen[Rig] = true
                    Tag.Gui.Adornee = Anchor
                    Tag.Gui.StudsOffset = Vector3.new(0, 2, 0)

                    if Rig:GetAttribute("Reloading") == true then
                        Tag.Label.Text = Rig.Name .. "  RELOADING"
                        Tag.Label.TextColor3 = RED
                    else
                        Tag.Label.Text = ("%s  %d"):format(Rig.Name, Rig:GetAttribute("Ammo"))
                        Tag.Label.TextColor3 = WHITE
                    end
                end
            end
        end

        TurretTags.Sweep(TurretSeen)
    end

    --// Blind spots: a grid of ground around you, each cell checked against every enemy's view. A cell is watched
    -- when it sits inside an enemy's view cone (from the facing of their head) and their eyes have a clear line to
    -- someone standing there. Red is watched, green is ground nobody is looking at right now.

    local BlindCells = {}
    local CELL = 6

    local BlindParams = RaycastParams.new()
    BlindParams.FilterType = Enum.RaycastFilterType.Exclude
    BlindParams.IgnoreWater = true

    local function Cell(Index)
        local Box = BlindCells[Index]

        if not Box then
            Box = Instance.new("BoxHandleAdornment")
            Box.Adornee = Workspace.Terrain
            Box.Size = Vector3.new(CELL - 0.6, 0.15, CELL - 0.6)
            Box.AlwaysOnTop = false
            Box.ZIndex = 0
            Box.Parent = Folder
            BlindCells[Index] = Box
        end

        return Box
    end

    local function UpdateBlindSpots(MyPosition)
        local Used = 0

        if Alert.BlindSpots and MyPosition then
            local Ignore = {Workspace.CurrentCamera}
            local IgnoreFolder = Workspace:FindFirstChild("Ignore")
            local Eyes = {}

            if IgnoreFolder then
                table.insert(Ignore, IgnoreFolder)
            end

            for _, Other in next, Players:GetPlayers() do
                local Character = Other.Character

                if Character then
                    table.insert(Ignore, Character)
                end

                local Head = IsEnemy(Other) and Character and Character:FindFirstChild("Head")

                if Head and Alive(Character) and (Head.Position - MyPosition).Magnitude <= Alert.BlindRadius + 500 then
                    table.insert(Eyes, Head)
                end
            end

            BlindParams.FilterDescendantsInstances = Ignore

            local Cos = math.cos(math.rad(Alert.BlindCone))
            local Span = math.floor(Alert.BlindRadius / CELL)
            local Origin = Vector3.new(math.floor(MyPosition.X / CELL) * CELL, MyPosition.Y, math.floor(MyPosition.Z / CELL) * CELL)

            for X = -Span, Span do
                for Z = -Span, Span do
                    if X * X + Z * Z <= Span * Span then
                        local Top = Origin + Vector3.new(X * CELL, 30, Z * CELL)
                        local Ground = Workspace:Raycast(Top, Vector3.new(0, -80, 0), BlindParams)

                        if Ground then
                            -- Someone standing there: chest height
                            local Body = Ground.Position + Vector3.new(0, 3, 0)
                            local Watched = false

                            for _, Head in next, Eyes do
                                local Offset = Body - Head.Position

                                if Offset.Magnitude > 1 and Head.CFrame.LookVector:Dot(Offset.Unit) >= Cos and not Workspace:Raycast(Head.Position, Offset, BlindParams) then
                                    Watched = true
                                    break
                                end
                            end

                            if Watched or Alert.BlindSafe then
                                Used += 1

                                local Box = Cell(Used)
                                Box.CFrame = CFrame.new(Ground.Position + Vector3.new(0, 0.1, 0))
                                Box.Color3 = Watched and RED or Color3.fromRGB(80, 220, 140)
                                Box.Transparency = Watched and 0.55 or 0.75
                                Box.Visible = true
                            end
                        end
                    end
                end
            end
        end

        for Index = Used + 1, #BlindCells do
            BlindCells[Index].Visible = false
        end
    end

    --// Objective pressure: who is standing on each objective right now. TriggerVolume.CapturerRoot gives the root
    -- of anyone who counts toward a capture (on a team, alive, conscious, not disguised, not crewing a vehicle),
    -- and TriggerVolume.Contains is the game's own inside test. Disguised enemies don't count, so they're listed apart.

    local Panel = {}
    local ObjectiveTags = Pool(NewTag)

    -- Capture clock: progress sampled every half second, its rate smoothed, and the time left to a full bar
    local Rates = setmetatable({}, {__mode = "k"})

    local function Clock(Part, Value)
        local Now, Track = os.clock(), Rates[Part]

        if not Track then
            Rates[Part] = {Value = Value, At = Now, Big = math.abs(Value) > 1}
            return ""
        end

        Track.Big = Track.Big or math.abs(Value) > 1

        if Now - Track.At >= 0.5 then
            local Instant = (Value - Track.Value) / (Now - Track.At)
            Track.Rate = Track.Rate and Track.Rate * 0.6 + Instant * 0.4 or Instant
            Track.Value, Track.At = Value, Now
        end

        local Full = Track.Big and 100 or 1
        local Rate = Track.Rate

        if not Rate or math.abs(Rate) < Full * 0.002 then
            return ""
        end

        local Left = ((Rate > 0 and Full or -Full) - Value) / Rate

        if Left < 0.5 or Left > 600 then
            return ""
        end

        return ("  %s in %d s"):format(Rate > 0 and "NATO" or "PACT", math.ceil(Left))
    end

    -- The game's own inside test, or a box test in the objective part's space when the module isn't available
    local function Inside(Part, Root)
        if TriggerVolume then
            local Ok, Result = pcall(TriggerVolume.Contains, Part, Root)

            if Ok then
                return Result == true
            end
        end

        local Local = Part.CFrame:PointToObjectSpace(Root.Position)
        local Half = Part.Size / 2
        return math.abs(Local.X) <= Half.X and math.abs(Local.Y) <= Half.Y and math.abs(Local.Z) <= Half.Z
    end

    -- TriggerVolume.CapturerRoot's rules: on NATO or PACT, alive, conscious, not disguised, not crewing a vehicle
    local function Capturer(Other)
        if TriggerVolume then
            local Ok, Root = pcall(TriggerVolume.CapturerRoot, Other)

            if Ok then
                return Root
            end
        end

        local Character = Other.Character
        local Team = Other.Team and Other.Team.Name
        local Values = Character and Character:FindFirstChild("CharacterValues")
        local Unconscious = Values and Values:FindFirstChild("Unconscious")
        local Root = Character and Character:FindFirstChild("HumanoidRootPart")

        if (Team == "NATO" or Team == "PACT") and Root and Alive(Character) and not CollectionService:HasTag(Character, "Disguised") and not (Unconscious and Unconscious.Value) and Root.CollisionGroup ~= "CREW" then
            return Root
        end

        return nil
    end

    -- Objectives: the game's list, or workspace.Match.Objectives read directly (ObjectValues pointing at the parts)
    local function ObjectiveList()
        if MatchObjectives then
            local Ok, List = pcall(MatchObjectives.list)

            if Ok and type(List) == "table" and #List > 0 then
                return List
            end
        end

        local Match = Workspace:FindFirstChild("Match")
        local Folder = Match and Match:FindFirstChild("Objectives")
        local List = {}

        for _, Item in next, Folder and Folder:GetChildren() or {} do
            if Item:IsA("ObjectValue") and Item.Value and Item.Value:IsA("BasePart") then
                table.insert(List, {Part = Item.Value, Order = tonumber(Item:GetAttribute("Order")) or #List + 1})
            end
        end

        table.sort(List, function(A, B) return A.Order < B.Order end)
        return List
    end

    local function UpdateObjectives()
        local Rows, Seen = {}, {}
        local List = Alert.Objectives and ObjectiveList()

        for _, Objective in next, type(List) == "table" and List or {} do
            local Part = Objective.Part

            if typeof(Part) == "Instance" and Part:IsA("BasePart") then
                local Counts = {NATO = 0, PACT = 0, Spies = 0}

                for _, Other in next, Players:GetPlayers() do
                    local Root = Capturer(Other)

                    if Root and Other.Team and Inside(Part, Root) then
                        Counts[Other.Team.Name] = (Counts[Other.Team.Name] or 0) + 1
                    elseif IsEnemy(Other) and Other.Character and CollectionService:HasTag(Other.Character, "Disguised") then
                        local Spy = RootOf(Other.Character)

                        if Spy and Alive(Other.Character) and Inside(Part, Spy) then
                            Counts.Spies += 1
                        end
                    end
                end

                local Ok, Name = false, nil

                if MatchObjectives then
                    Ok, Name = pcall(MatchObjectives.displayName, Objective, Player.Team and Player.Team.Name)
                end

                local Letter = Ok and type(Name) == "string" and Name or string.char(64 + math.clamp(tonumber(Objective.Order) or 1, 1, 26))
                local Data = Part:FindFirstChild("TriggerData")
                local Owner = Data and Data:FindFirstChild("CapturedTeam")
                local Progress = Data and Data:FindFirstChild("CaptureProgress")
                local Value = Progress and tonumber(Progress.Value) or 0
                local Held = Owner and Owner.Value and tostring(Owner.Value) or "nobody"

                -- Positive progress leans NATO, negative PACT
                local Percent = math.floor(math.abs(Value) <= 1 and math.abs(Value) * 100 or math.abs(Value))
                local Leaning = Value > 0 and ("  NATO capping " .. Percent .. "%") or Value < 0 and ("  PACT capping " .. Percent .. "%") or ""
                local Spies = Counts.Spies > 0 and ("  +" .. Counts.Spies .. " disguised") or ""
                local Color = Counts.NATO > Counts.PACT and BLUE or Counts.PACT > Counts.NATO and RED or WHITE
                local Timer = Alert.CaptureClock and Clock(Part, Value) or ""

                table.insert(Rows, {("%s  [%s]  NATO %d  PACT %d%s%s%s"):format(Letter, Held, Counts.NATO, Counts.PACT, Spies, Leaning, Timer), Color})

                if Alert.ObjectiveLabels then
                    local Tag = ObjectiveTags.Get(Part)
                    Seen[Part] = true
                    Tag.Gui.Adornee = Part
                    Tag.Label.Text = ("%s   NATO %d  ·  PACT %d%s%s"):format(Letter, Counts.NATO, Counts.PACT, Spies, Timer)
                    Tag.Label.TextColor3 = Color
                end
            end
        end

        ObjectiveTags.Sweep(Seen)

        -- A heading, so the panel is easy to find, and a line saying so when the round has no objectives
        if Alert.Objectives then
            table.insert(Rows, 1, {#Rows > 0 and "OBJECTIVES" or "OBJECTIVES  none this round", WHITE})
        end

        -- The side panel, left of the screen
        for Index, Row in next, Rows do
            local Line = DrawingOf(Panel, Index, "Text")

            if Line then
                Line.Center = false
                Line.Size = 16
                Line.Text = Row[1]
                Line.Color = Row[2]
                Line.Position = Vector2.new(16, 240 + (Index - 1) * 20)
                Line.Visible = true
            end
        end

        HideFrom(Panel, #Rows + 1)
    end

    --// Cards

    local Strike = AlertTab:Module({
        Title = "Strike warning",
        Description = "Rings where artillery has been called in.",
        Icon = "bomb",
        Side = "Left",
        Default = false,
        Flag = "Alerts.Strikes",
        Keybind = false,
        Opened = true,
        Callback = function(Value) Alert.Strikes = Value end
    })

    Strike:Checkbox({Title = "Friendly strikes", Tooltip = "Your own side's shells kill you too.", Default = true, Flag = "Alerts.Strikes.Friendly", Callback = function(Value) Alert.FriendlyStrikes = Value end})

    local Grenade = AlertTab:Module({
        Title = "Grenade warning",
        Description = "Blast rings and fuse timers on live grenades.",
        Icon = "circle-dot",
        Side = "Left",
        Default = false,
        Flag = "Alerts.Grenades",
        Keybind = false,
        Opened = true,
        Callback = function(Value) Alert.Grenades = Value end
    })

    Grenade:Slider({Title = "Range", Min = 20, Max = 200, Step = 5, Default = 60, Suffix = " st", Flag = "Alerts.Grenades.Range", Callback = function(Value) Alert.GrenadeRange = Value end})

    local Aimed = AlertTab:Module({
        Title = "Aimed-at warning",
        Description = "Warns when an enemy with a clear line has you in their sights.",
        Icon = "scan-eye",
        Side = "Right",
        Default = false,
        Flag = "Alerts.Aimed",
        Keybind = false,
        Opened = true,
        Callback = function(Value) Alert.Aimed = Value end
    })

    Aimed:Slider({Title = "Cone", Min = 1, Max = 15, Step = 1, Default = 4, Suffix = "°", Flag = "Alerts.Aimed.Cone", Tooltip = "How close to your head their aim has to be.", Callback = function(Value) Alert.AimedCone = Value end})
    Aimed:Slider({Title = "Range", Min = 100, Max = 3000, Step = 50, Default = 800, Suffix = " st", Flag = "Alerts.Aimed.Range", Callback = function(Value) Alert.AimedRange = Value end})

    local Blind = AlertTab:Module({
        Title = "Blind spots",
        Description = "Red ground is in an enemy's view, green is ground nobody is watching.",
        Icon = "eye-off",
        Side = "Left",
        Default = false,
        Flag = "Alerts.BlindSpots",
        Keybind = {Key = nil, Mode = "Toggle"},
        Opened = true,
        Callback = function(Value) Alert.BlindSpots = Value end
    })

    Blind:Slider({Title = "Radius", Min = 24, Max = 120, Step = 6, Default = 60, Suffix = " st", Flag = "Alerts.BlindSpots.Radius", Tooltip = "Bigger costs more frames.", Callback = function(Value) Alert.BlindRadius = Value end})
    Blind:Slider({Title = "Their view", Min = 20, Max = 90, Step = 5, Default = 60, Suffix = "°", Flag = "Alerts.BlindSpots.Cone", Tooltip = "How far off their facing an enemy still counts as seeing.", Callback = function(Value) Alert.BlindCone = Value end})
    Blind:Checkbox({Title = "Show safe ground", Default = true, Flag = "Alerts.BlindSpots.Safe", Callback = function(Value) Alert.BlindSafe = Value end})

    local Screen = AlertTab:Section({Title = "Screen", Icon = "monitor", Side = "Right"})
    Screen:Toggle({Title = "Direction arrows", Tooltip = "Arrows around the crosshair point at each threat.", Default = true, Flag = "Alerts.Arrows", Callback = function(Value) Alert.Arrows = Value end})

    local Gunfire = IntelTab:Module({
        Title = "Gunfire locator",
        Description = "Tags whoever just fired, wherever they are.",
        Icon = "volume-2",
        Side = "Left",
        Default = false,
        Flag = "Intel.Gunfire",
        Keybind = false,
        Opened = true,
        Callback = function(Value)
            Alert.Gunfire = Value

            if Value and not (Broadcast and ShotCodec) then
                Notify("Gunfire locator", "Couldn't find the shot broadcast in this build.", "Error", 5)
            end
        end
    })

    Gunfire:Slider({Title = "Show for", Min = 2, Max = 20, Step = 1, Default = 5, Suffix = " s", Flag = "Intel.Gunfire.Time", Callback = function(Value) Alert.GunfireTime = Value end})
    Gunfire:Checkbox({Title = "Near-miss alert", Tooltip = "Warns and points at whoever's shots pass close to you.", Default = true, Flag = "Intel.Gunfire.NearMiss", Callback = function(Value) Alert.NearMiss = Value end})
    Gunfire:Checkbox({Title = "Mark on map", Tooltip = "Shooters show on your map while tagged.", Default = true, Flag = "Intel.Gunfire.Map", Callback = function(Value) Alert.GunfireMap = Value end})
    Gunfire:Checkbox({Title = "Friendly shots", Default = false, Flag = "Intel.Gunfire.Friendly", Callback = function(Value) Alert.GunfireFriendly = Value end})

    local MagazineCard = IntelTab:Module({
        Title = "Magazine counter",
        Description = "Rounds left in each enemy's magazine, and when they're reloading.",
        Icon = "layers",
        Side = "Left",
        Default = false,
        Flag = "Intel.Magazines",
        Keybind = false,
        Opened = true,
        Callback = function(Value)
            Alert.Magazines = Value

            if Value and not (Broadcast and ShotCodec) then
                Notify("Magazine counter", "Couldn't find the shot broadcast in this build.", "Error", 5)
            end
        end
    })

    MagazineCard:Slider({Title = "Range", Min = 50, Max = 1500, Step = 50, Default = 400, Suffix = " st", Flag = "Intel.Magazines.Range", Callback = function(Value) Alert.MagazineRange = Value end})
    MagazineCard:Checkbox({Title = "Vehicle guns", Tooltip = "Exact rounds left on mounted guns.", Default = true, Flag = "Intel.Magazines.Turrets", Callback = function(Value) Alert.TurretAmmo = Value end})

    local Pressure = IntelTab:Module({
        Title = "Objective pressure",
        Description = "Live head count on every objective.",
        Icon = "flag",
        Side = "Right",
        Default = false,
        Flag = "Intel.Objectives",
        Keybind = false,
        Opened = true,
        Callback = function(Value) Alert.Objectives = Value end
    })

    Pressure:Checkbox({Title = "Capture clock", Tooltip = "Seconds until the bar fills at the current pace.", Default = true, Flag = "Intel.Objectives.Clock", Callback = function(Value) Alert.CaptureClock = Value end})
    Pressure:Checkbox({Title = "Labels on objectives", Default = true, Flag = "Intel.Objectives.Labels", Callback = function(Value) Alert.ObjectiveLabels = Value end})

    --// Loops

    local BlindTick = 0

    task.spawn(function()
        while Running do
            table.clear(Warnings)
            table.clear(Pointers)

            local Root = RootOf(Player.Character)
            local MyPosition = Root and Root.Position

            for _, Step in next, {UpdateStrikes, UpdateGrenades, UpdateAimed, UpdateGunfire, UpdateMagazines, UpdateObjectives} do
                pcall(Step, MyPosition)
            end

            -- The grid is the heaviest check, so it runs twice a second
            BlindTick = (BlindTick + 1) % 5

            if BlindTick == 0 or not Alert.BlindSpots then
                pcall(UpdateBlindSpots, MyPosition)
            end

            pcall(DrawWarnings)
            task.wait(0.1)
        end
    end)

    local ArrowLoop = RunService.RenderStepped:Connect(function()
        pcall(DrawArrows)
    end)

    OasisUI:OnUnload(function()
        Running = false
        ArrowLoop:Disconnect()

        if BroadcastConnection then
            BroadcastConnection:Disconnect()
        end

        for Character in next, MapMarks do
            if Character.Parent and Character:GetAttribute("SpottedBy") == true then
                Character:SetAttribute("SpottedBy", nil)
            end
        end

        for _, List in next, {Lines, Arrows, Panel} do
            for _, Object in next, List do
                pcall(Object.Remove, Object)
            end
        end

        Folder:Destroy()
    end)
end

--// Dive: water stops every bullet. Interactions.resolve ends a bullet the moment its ray touches water, and the
-- shooter's raycast doesn't ignore water. The game's own swim (Client.Character.SurfaceSwim) asks its
-- _probeSurface method where the surface is and holds your root 0.75 studs under that. Answering with a surface a
-- few studs lower makes the game itself hold you under; nothing fights it. There's no drowning in the client code.
-- You can't use weapons while swimming, so this is for crossing water or waiting a fight out.

do
    local Running = true
    local Dive = {Enabled = false, Depth = 4}
    local Swimmer -- the game's SurfaceSwim object for your current character

    -- Found by shape: the table holding your character with the swim's own fields
    local function FindSwimmer()
        local Character = Player.Character

        if Swimmer and rawget(Swimmer, "_character") == Character then
            return Swimmer
        end

        Swimmer = nil

        if not (getgc and Character) then
            return nil
        end

        for _, Value in next, getgc(true) do
            if type(Value) == "table" and rawget(Value, "_character") == Character and rawget(Value, "_feetOffset") ~= nil then
                Swimmer = Value
                break
            end
        end

        return Swimmer
    end

    local function Surfacing()
        return UserInputService:IsKeyDown(Enum.KeyCode.Space) and not UserInputService:GetFocusedTextBox()
    end

    local Patched = setmetatable({}, {__mode = "k"})

    local function Patch(Object)
        local Class = getmetatable(Object)
        local Original = type(Class) == "table" and rawget(Class, "_probeSurface")

        if Patched[Object] or type(Original) ~= "function" then
            return
        end

        Patched[Object] = true

        -- Read through the instance first, so this shadows the class method for your character only
        rawset(Object, "_probeSurface", function(Self, ...)
            local Surface = Original(Self, ...)

            if Surface and Running and Dive.Enabled and not Surfacing() then
                return Surface - Dive.Depth
            end

            return Surface
        end)
    end

    local Status = Drawing and Drawing.new("Text")

    if Status then
        Status.Visible = false
        Status.Center = true
        Status.Outline = true
        Status.Size = 18
        Status.Font = 2
        Status.Color = Color3.fromRGB(80, 220, 140)
    end

    task.spawn(function()
        while Running do
            local Under = false

            if Dive.Enabled then
                pcall(function()
                    local Object = FindSwimmer()

                    if Object then
                        Patch(Object)

                        -- The real surface stays in _surfaceY; the head is under when its top is below it
                        local Head = Player.Character:FindFirstChild("Head")
                        local Surface = rawget(Object, "_surfaceY")
                        Under = rawget(Object, "_swimming") == true and Head ~= nil and type(Surface) == "number" and Head.Position.Y + Head.Size.Y / 2 < Surface - 0.3
                    end
                end)
            end

            if Status then
                Status.Visible = Under

                if Under then
                    Status.Text = "UNDER WATER: bullets can't reach you"
                    Status.Position = Vector2.new(Workspace.CurrentCamera.ViewportSize.X / 2, 64)
                end
            end

            task.wait(0.25)
        end
    end)

    local Card = MoveTab:Module({
        Title = "Dive",
        Description = "Swim into deep water and you stay under, where no bullet reaches. Hold Space to come up.",
        Icon = "waves",
        Side = "Left",
        Default = false,
        Flag = "Movement.Dive",
        Keybind = {Key = nil, Mode = "Toggle"},
        Opened = true,
        Callback = function(Value)
            Dive.Enabled = Value

            if Value and not getgc then
                Notify("Dive", "Your executor is missing getgc, so Dive can't find the game's swim.", "Error", 5)
            end
        end
    })

    Card:Slider({Title = "Depth", Min = 2, Max = 15, Step = 0.5, Default = 4, Suffix = " st", Flag = "Movement.Dive.Depth", Tooltip = "How far under the surface you're held. Needs water at least this deep.", Callback = function(Value) Dive.Depth = Value end})

    OasisUI:OnUnload(function()
        Running = false

        if Status then
            Status:Remove()
        end
    end)
end

--// Grenade arc and smoke planner.
-- The throw is made on the server (Remotes.Grenade "Throw" with your camera's facing, sent 0.2 s after you let go,
-- and the stance), so its speed and release point aren't in the client. They're learned instead: when your own
-- grenade appears in workspace.Ignore.Dropped, its first position is stored relative to your head and its starting
-- velocity is split into speed along your aim plus an upward kick, per stance. Its physical properties are read off
-- the same part, so the bounces use the grenade's real elasticity and friction against whatever it hits.

do
    local Running = true
    local Arc = {Enabled = false, Always = false, Smoke = false, Shield = "Me", Cloud = 12}
    local GrenadeConfigs = Shared and Shared:FindFirstChild("GrenadeConfigManager")
    local MatchObjectives = Require(Shared and Shared:FindFirstChild("MatchObjectives"))

    -- Starting guesses until your first throw of each stance; Offset is the release point in your facing's frame
    local Learned = {
        High = {Speed = 65, Lift = 8, Offset = Vector3.new(0.8, 0.2, -1), Guess = true},
        Low = {Speed = 30, Lift = 4, Offset = Vector3.new(0.8, -1, -1), Guess = true}
    }

    -- Plastic's defaults until a real grenade has been seen
    local Body = {Elasticity = 0.5, Friction = 0.3, ElasticityWeight = 1, FrictionWeight = 1, Radius = 0.4}
    local Pending -- the last throw: {At, Look, Head, Stance}

    -- The grenade tool's own state table (aiming, currentStance, tool), found by shape
    local States = setmetatable({}, {__mode = "k"})
    local LastScan = 0

    local function StateOf(Tool)
        if States[Tool] or not getgc or os.clock() - LastScan < 2 then
            return States[Tool]
        end

        LastScan = os.clock()

        for _, Value in next, getgc(true) do
            if type(Value) == "table" and rawget(Value, "currentStance") ~= nil and rawget(Value, "tool") == Tool then
                States[Tool] = Value
                break
            end
        end

        return States[Tool]
    end

    local Configs = {}

    -- Fuse, type and kill radius per grenade
    local function ConfigOf(Name)
        if not Configs[Name] then
            local Config = Require(GrenadeConfigs and GrenadeConfigs:FindFirstChild(Name))
            local Blast = type(Config) == "table" and type(Config.explosionSettings) == "table" and Config.explosionSettings

            Configs[Name] = {
                Type = type(Config) == "table" and Config.Type or "Frag",
                Fuze = type(Config) == "table" and tonumber(Config.Fuze) or 4,
                Kill = Blast and tonumber(Blast.KillRange) or 2
            }
        end

        return Configs[Name]
    end

    local function HeldGrenade()
        local Character = Player.Character
        local Tool = Character and Character:FindFirstChildOfClass("Tool")
        return Tool and GrenadeConfigs and GrenadeConfigs:FindFirstChild(Tool.Name) and Tool or nil
    end

    local function Mine(Part)
        local Owner = Part:GetAttribute("Owner")
        return Owner == Player.UserId or Owner == Player.Name or Owner == tostring(Player.UserId)
    end

    -- Your facing with the pitch taken out: the frame the release point is stored in
    local function Facing(Head, Look)
        local Flat = Vector3.new(Look.X, 0, Look.Z)
        Flat = Flat.Magnitude > 1e-3 and Flat.Unit or Vector3.new(0, 0, -1)
        return CFrame.lookAt(Head, Head + Flat)
    end

    -- Velocity = Speed * Look + Lift * Up, solved for Speed and Lift by least squares
    local function Learn(Velocity, Spawn, Throw)
        local Look, Lean = Throw.Look, Throw.Look.Y
        local Det = 1 - Lean * Lean
        local Along, Up = Velocity:Dot(Look), Velocity.Y
        local Speed, Lift

        if Det < 0.05 then
            Speed, Lift = Along, 0
        else
            Speed = (Along - Lean * Up) / Det
            Lift = (Up - Lean * Along) / Det
        end

        if not (Speed > 5 and Speed < 400) then
            return
        end

        local Offset = Facing(Throw.Head, Look):PointToObjectSpace(Spawn)
        local Old = Learned[Throw.Stance]

        -- Averaged with earlier throws once there's a real one to average with
        if Old.Guess then
            Learned[Throw.Stance] = {Speed = Speed, Lift = Lift, Offset = Offset}
            Notify("Grenade arc", ("Learned your %s throw from that grenade."):format(Throw.Stance:lower()), "Info", 3)
        else
            Learned[Throw.Stance] = {Speed = (Old.Speed + Speed) / 2, Lift = (Old.Lift + Lift) / 2, Offset = Old.Offset:Lerp(Offset, 0.5)}
        end
    end

    local function WatchDropped(Dropped)
        return Dropped.ChildAdded:Connect(function(Part)
            local Throw = Pending

            if not (Part:IsA("BasePart") and Throw and os.clock() - Throw.At < 2.5) then
                return
            end

            -- Its first replicated position, before it has moved far
            local Spawn, SeenAt = Part.Position, os.clock()
            task.wait()

            if not (Mine(Part) or (Spawn - Throw.Head).Magnitude < 12) then
                return
            end

            local Properties = Part.CurrentPhysicalProperties
            Body = {
                Elasticity = Properties.Elasticity,
                Friction = Properties.Friction,
                ElasticityWeight = Properties.ElasticityWeight,
                FrictionWeight = Properties.FrictionWeight,
                Radius = math.min(Part.Size.X, Part.Size.Y, Part.Size.Z) / 2
            }

            -- The velocity can take a frame or two to show up; gravity since the first sighting is taken back out
            for _ = 1, 6 do
                local Velocity = Part.AssemblyLinearVelocity

                if Velocity.Magnitude > 2 then
                    Pending = nil
                    return Learn(Velocity + Vector3.new(0, Workspace.Gravity * (os.clock() - SeenAt), 0), Spawn, Throw)
                end

                RunService.Heartbeat:Wait()
            end
        end)
    end

    local DroppedConnection

    task.spawn(function()
        local Ignore = Workspace:WaitForChild("Ignore", 30)
        local Dropped = Ignore and Ignore:WaitForChild("Dropped", 30)

        if Dropped and Running then
            DroppedConnection = WatchDropped(Dropped)
        end
    end)

    --// Flight: gravity, then on each contact the normal speed is reversed and scaled by the combined elasticity,
    -- and friction takes speed off along the surface (Roblox mixes two parts' values by their weights)

    local ArcParams = RaycastParams.new()
    ArcParams.FilterType = Enum.RaycastFilterType.Exclude
    ArcParams.IgnoreWater = false

    local function SurfaceOf(Result)
        local Hit = Result.Instance

        if Hit:IsA("BasePart") and Hit ~= Workspace.Terrain then
            return Hit.CurrentPhysicalProperties
        end

        return PhysicalProperties.new(Result.Material)
    end

    local function Mix(A, WeightA, B, WeightB)
        return (A * WeightA + B * WeightB) / math.max(WeightA + WeightB, 1e-3)
    end

    local STEP, MAX_STEPS = 1 / 30, 150

    -- Returns the path points and where it goes off (or comes to rest)
    local function Fly(Start, Velocity, Config)
        local Points = {Start}
        local Position = Start
        local Gravity = Vector3.new(0, -Workspace.Gravity, 0)
        local Limit = Config.Type == "Smoke" and 5 or Config.Fuze

        for Step = 1, MAX_STEPS do
            if Step * STEP > Limit then
                break
            end

            local Next = Position + Velocity * STEP + 0.5 * Gravity * STEP * STEP
            local Result = Workspace:Raycast(Position, Next - Position, ArcParams)
            Velocity += Gravity * STEP

            if Result then
                table.insert(Points, Result.Position)

                -- Impact grenades go off on the first hit; water swallows anything
                if Config.Type == "Impact" or Result.Material == Enum.Material.Water then
                    return Points, Result.Position
                end

                local Surface = SurfaceOf(Result)
                local Bounce = Mix(Body.Elasticity, Body.ElasticityWeight, Surface.Elasticity, Surface.ElasticityWeight)
                local Grip = Mix(Body.Friction, Body.FrictionWeight, Surface.Friction, Surface.FrictionWeight)
                local Normal = Result.Normal
                local Into = Velocity:Dot(Normal)
                local Across = Velocity - Normal * Into

                -- Friction can only stop the sliding, never reverse it
                local Slow = Across.Magnitude > 1e-3 and math.min(1, Grip * (1 + Bounce) * math.abs(Into) / Across.Magnitude) or 1
                Velocity = Across * (1 - Slow) - Normal * Into * Bounce
                Position = Result.Position + Normal * Body.Radius

                -- Settled on the ground
                if Velocity.Magnitude < 1.5 and Normal.Y > 0.7 then
                    return Points, Result.Position
                end
            else
                Position = Next
                table.insert(Points, Position)
            end
        end

        return Points, Position
    end

    --// Smoke planner: where one smoke cloud cuts the most enemy sightlines onto you or the nearest objective.
    -- Every enemy with a clear line to the spot you're shielding is a line; the best cloud sits across the most of
    -- them, on ground you can throw to.

    local function ShieldPoint()
        local Root = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")

        if not Root then
            return nil
        end

        if Arc.Shield == "Nearest objective" and MatchObjectives then
            local Ok, List = pcall(MatchObjectives.list)
            local Best, BestGap

            for _, Objective in next, Ok and type(List) == "table" and List or {} do
                local Part = Objective.Part

                if typeof(Part) == "Instance" and Part:IsA("BasePart") then
                    local Gap = (Part.Position - Root.Position).Magnitude

                    if not BestGap or Gap < BestGap then
                        Best, BestGap = Part.Position, Gap
                    end
                end
            end

            return Best
        end

        return Root.Position
    end

    local function DistanceToSegment(Point, A, B)
        local Line = B - A
        local Along = math.clamp((Point - A):Dot(Line) / math.max(Line:Dot(Line), 1e-6), 0, 1)
        return (Point - (A + Line * Along)).Magnitude
    end

    local SightParams = RaycastParams.new()
    SightParams.FilterType = Enum.RaycastFilterType.Exclude
    SightParams.IgnoreWater = true

    local function PlanSmoke(Head)
        local Target = ShieldPoint()

        if not Target then
            return nil
        end

        Target += Vector3.new(0, 2, 0)

        local Ignore = {Workspace.CurrentCamera}
        local IgnoreFolder = Workspace:FindFirstChild("Ignore")

        if IgnoreFolder then
            table.insert(Ignore, IgnoreFolder)
        end

        for _, Other in next, Players:GetPlayers() do
            if Other.Character then
                table.insert(Ignore, Other.Character)
            end
        end

        SightParams.FilterDescendantsInstances = Ignore

        -- Sightlines: enemy eyes with a clear view of the spot
        local Lines = {}

        for _, Other in next, Players:GetPlayers() do
            local Character = Other ~= Player and Other.Team and Player.Team and Other.Team ~= Player.Team and Other.Character
            local Eye = Character and Character:FindFirstChild("Head")
            local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")

            if Eye and Humanoid and Humanoid.Health > 0 and (Eye.Position - Target).Magnitude < 800 and not Workspace:Raycast(Eye.Position, Target - Eye.Position, SightParams) then
                table.insert(Lines, {Eye.Position, Target})
            end
        end

        if #Lines == 0 then
            return nil
        end

        local Best

        for _, Line in next, Lines do
            for Step = 1, 9 do
                local Along = Line[2]:Lerp(Line[1], Step / 10)
                local Down = Workspace:Raycast(Along + Vector3.new(0, 20, 0), Vector3.new(0, -80, 0), SightParams)

                -- Within a throw of you
                if Down and (Down.Position - Head).Magnitude <= 70 then
                    -- The cloud sits on the ground and rises; count lines passing through it at head height
                    local Cloud = Down.Position + Vector3.new(0, 4, 0)
                    local Blocked = 0

                    for _, Other in next, Lines do
                        if DistanceToSegment(Cloud, Other[1], Other[2]) <= Arc.Cloud then
                            Blocked += 1
                        end
                    end

                    -- Ties go to the spot nearer you: a shorter, surer throw
                    local Score = Blocked - (Down.Position - Head).Magnitude / 1000

                    if not Best or Score > Best.Score then
                        Best = {Point = Down.Position, Blocked = Blocked, Of = #Lines, Score = Score}
                    end
                end
            end
        end

        return Best
    end

    --// Drawing

    local Segments = {}

    for Index = 1, MAX_STEPS do
        local Line = Drawing and Drawing.new("Line")

        if Line then
            Line.Visible = false
            Line.Thickness = 2
            Line.Transparency = 0.9
        end

        Segments[Index] = Line
    end

    local function NewRing(Color)
        local Ring = Instance.new("CylinderHandleAdornment")
        Ring.Adornee = Workspace.Terrain
        Ring.Height = 0.2
        Ring.Color3 = Color
        Ring.Transparency = 0.3
        Ring.AlwaysOnTop = true
        Ring.Visible = false
        Ring.Parent = (gethui and gethui()) or game:GetService("CoreGui")
        return Ring
    end

    local function PlaceRing(Ring, Position, Radius)
        Ring.Radius = Radius
        Ring.InnerRadius = math.max(Radius - 0.6, 0)
        Ring.CFrame = CFrame.new(Position) * CFrame.Angles(math.rad(90), 0, 0)
        Ring.Visible = true
    end

    local Landing = NewRing(Color3.fromRGB(255, 80, 80))
    local SmokeRing = NewRing(Color3.fromRGB(235, 235, 235))

    local Label = Drawing and Drawing.new("Text")

    if Label then
        Label.Visible = false
        Label.Center = true
        Label.Outline = true
        Label.Size = 16
        Label.Font = 2
    end

    local Aiming, SmokePlan, LastPlan = false, nil, 0

    local function Step()
        local Camera = Workspace.CurrentCamera
        local Tool = Arc.Enabled and HeldGrenade()
        local State = Tool and StateOf(Tool)
        local Stance = State and State.currentStance == "Low" and "Low" or "High"
        local Now = State and State.aiming == true
        local Head = Player.Character and Player.Character:FindFirstChild("Head")

        -- Releasing the throw: the server reads your camera 0.2 s later
        if Aiming and not Now and Tool then
            task.delay(0.2, function()
                local Current = Player.Character and Player.Character:FindFirstChild("Head")

                if Current then
                    Pending = {At = os.clock(), Look = Workspace.CurrentCamera.CFrame.LookVector, Head = Current.Position, Stance = Stance}
                end
            end)
        end

        Aiming = Now

        local Show = Tool and Head and (Now or Arc.Always or not State)
        local Used, Text, TextAt, TextColor = 0, nil, nil, nil

        Landing.Visible = false
        SmokeRing.Visible = false

        if Show then
            local Config = ConfigOf(Tool.Name)
            local Look = Camera.CFrame.LookVector
            local Throw = Learned[Stance]
            local Start = Facing(Head.Position, Look):PointToWorldSpace(Throw.Offset)
            local Ignore = {Player.Character, Camera}
            local IgnoreFolder = Workspace:FindFirstChild("Ignore")

            if IgnoreFolder then
                table.insert(Ignore, IgnoreFolder)
            end

            ArcParams.FilterDescendantsInstances = Ignore

            local Points, Stop = Fly(Start, Look * Throw.Speed + Vector3.yAxis * Throw.Lift, Config)

            for Index = 1, #Points - 1 do
                local Line = Segments[Index]

                if Line then
                    local A, OnA = Camera:WorldToViewportPoint(Points[Index])
                    local B, OnB = Camera:WorldToViewportPoint(Points[Index + 1])
                    Line.Visible = A.Z > 0 and B.Z > 0 and (OnA or OnB)
                    Line.From = Vector2.new(A.X, A.Y)
                    Line.To = Vector2.new(B.X, B.Y)
                    Line.Color = Throw.Guess and Color3.fromRGB(255, 210, 60) or Color3.fromRGB(255, 120, 80)
                    Used = Index
                end
            end

            PlaceRing(Landing, Stop, Config.Type == "Smoke" and Arc.Cloud or Config.Kill)
            Landing.Color3 = Config.Type == "Smoke" and Color3.fromRGB(150, 150, 150) or Throw.Guess and Color3.fromRGB(255, 210, 60) or Color3.fromRGB(255, 80, 80)

            -- Smoke in hand: where to put it, and whether this throw gets there
            if Arc.Smoke and Config.Type == "Smoke" then
                if os.clock() - LastPlan > 0.25 then
                    LastPlan = os.clock()
                    SmokePlan = PlanSmoke(Head.Position)
                end

                if SmokePlan then
                    PlaceRing(SmokeRing, SmokePlan.Point, Arc.Cloud)

                    local OnTarget = (Vector3.new(Stop.X, 0, Stop.Z) - Vector3.new(SmokePlan.Point.X, 0, SmokePlan.Point.Z)).Magnitude <= 4
                    SmokeRing.Color3 = OnTarget and Color3.fromRGB(80, 220, 140) or Color3.fromRGB(235, 235, 235)
                    Text = OnTarget and "THROW" or ("SMOKE HERE  blocks %d of %d"):format(SmokePlan.Blocked, SmokePlan.Of)
                    TextAt, TextColor = SmokePlan.Point + Vector3.new(0, 4, 0), SmokeRing.Color3
                end
            end
        end

        for Index = Used + 1, MAX_STEPS do
            if Segments[Index] then
                Segments[Index].Visible = false
            end
        end

        if Label then
            local Screen, OnScreen

            if TextAt then
                Screen, OnScreen = Camera:WorldToViewportPoint(TextAt)
            end

            Label.Visible = OnScreen == true

            if OnScreen then
                Label.Text = Text
                Label.Color = TextColor
                Label.Position = Vector2.new(Screen.X, Screen.Y)
            end
        end
    end

    local Connection = RunService.RenderStepped:Connect(function()
        if Running then
            pcall(Step)
        end
    end)

    local Card = GunsTab:Module({
        Title = "Grenade arc",
        Description = "Your throw's path with bounces, and where it goes off. Yellow: estimate until your first throw teaches it.",
        Icon = "circle-dot",
        Side = "Right",
        Default = false,
        Flag = "Guns.GrenadeArc",
        Keybind = false,
        Opened = true,
        Callback = function(Value) Arc.Enabled = Value end
    })

    Card:Checkbox({Title = "Show while held", Tooltip = "Draw it the whole time a grenade is out, not just while winding up.", Default = false, Flag = "Guns.GrenadeArc.Always", Callback = function(Value) Arc.Always = Value end})
    Card:Checkbox({Title = "Smoke planner", Tooltip = "With smoke in hand, marks where one cloud blocks the most enemy sightlines. Turns green when your throw lands there.", Default = true, Flag = "Guns.SmokePlanner", Callback = function(Value) Arc.Smoke = Value end})
    Card:Dropdown({Title = "Shield", Values = {"Me", "Nearest objective"}, Default = "Me", Flag = "Guns.SmokePlanner.Shield", Callback = function(Value) Arc.Shield = Value end})
    Card:Slider({Title = "Cloud size", Min = 6, Max = 30, Step = 1, Default = 12, Suffix = " st", Flag = "Guns.SmokePlanner.Cloud", Tooltip = "Radius of a settled smoke cloud.", Callback = function(Value) Arc.Cloud = Value end})

    OasisUI:OnUnload(function()
        Running = false
        Connection:Disconnect()

        if DroppedConnection then
            DroppedConnection:Disconnect()
        end

        for _, Line in next, Segments do
            if Line then
                Line:Remove()
            end
        end

        if Label then
            Label:Remove()
        end

        Landing:Destroy()
        SmokeRing:Destroy()
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

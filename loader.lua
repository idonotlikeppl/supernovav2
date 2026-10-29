--[[

	SuperNova loader

	Works out which game you're in and runs its script from games/. Anything without its own script gets the
	universal ESP.

	Nothing here prints. ER:LC uploads your console to its servers, and its script's log scrubber only starts once
	that script is running, so the loader stays silent: every step is in a pcall and status goes to a Roblox
	notification instead.

	Force a script by setting this before running the loader:
		getgenv().SuperNovaGame = "coldwar"   -- or "erlc", "atltrenches", "universal_esp"

]]

local BASE = "https://raw.githubusercontent.com/idonotlikeppl/supernovav2/main/games/"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local function Notify(Title, Text, Duration)
    -- SetCore isn't ready for the first moments of a session, so it retries briefly
    task.spawn(function()
        for _ = 1, 10 do
            if pcall(StarterGui.SetCore, StarterGui, "SendNotification", {Title = Title, Text = Text, Duration = Duration or 5}) then
                return
            end

            task.wait(0.5)
        end
    end)
end

-- A path of children, e.g. Has(ReplicatedStorage, "Remotes", "ATMAction")
local function Has(Root, ...)
    local Node = Root

    for _, Name in next, {...} do
        Node = Node and Node:FindFirstChild(Name)
    end

    return Node ~= nil
end

--// Games: a place ID match wins; otherwise each fingerprint is checked, built from objects only that game has.
-- Fingerprints keep working when a game moves to a new place, runs a test branch, or the ID isn't known.

local Games = {
    {
        Name = "Emergency Response: Liberty County",
        File = "erlc.lua",
        Key = "erlc",
        PlaceIds = {[2534724415] = true},
        Detect = function()
            return Has(ReplicatedStorage, "ReliableRedEvent") and Has(ReplicatedStorage, "Modules", "Network")
        end
    },
    {
        Name = "ATL Trenches",
        File = "atltrenches.lua",
        Key = "atltrenches",
        PlaceIds = {[119820005878127] = true},
        Detect = function()
            return Has(Workspace, "GameFolder") and Has(ReplicatedStorage, "Remotes", "Misc") and Has(ReplicatedStorage, "Remotes", "ATMAction")
        end
    },
    {
        Name = "Cold War (NATO vs PACT)",
        File = "coldwar.lua",
        Key = "coldwar",
        -- The main place, the test branch and the first-person-only place
        PlaceIds = {[13687899540] = true, [121650045752508] = true, [92518636938049] = true},
        Detect = function()
            return Has(ReplicatedStorage, "Shared", "WeaponConfigManager") and Has(ReplicatedStorage, "Remotes", "BodyRotation") and Has(Workspace, "Match")
        end
    }
}

local Universal = {Name = "Universal ESP", File = "universal_esp.lua", Key = "universal_esp"}

local function ByKey(Key)
    for _, Entry in next, Games do
        if Entry.Key == Key then
            return Entry
        end
    end

    return Key == Universal.Key and Universal or nil
end

local function Identify()
    local Forced = getgenv().SuperNovaGame

    if type(Forced) == "string" and ByKey(Forced:lower()) then
        return ByKey(Forced:lower())
    end

    for _, Entry in next, Games do
        if Entry.PlaceIds[game.PlaceId] then
            return Entry
        end
    end

    -- Remotes and folders can arrive a few seconds after the game reports loaded, so look for a while
    local Started = os.clock()

    repeat
        for _, Entry in next, Games do
            local Ok, Match = pcall(Entry.Detect)

            if Ok and Match then
                return Entry
            end
        end

        task.wait(0.5)
    until os.clock() - Started > 8

    return Universal
end

local function Run(Entry)
    local Ok, Source = pcall(game.HttpGet, game, BASE .. Entry.File)

    if not Ok or type(Source) ~= "string" or Source == "" then
        return false, "couldn't download " .. Entry.File
    end

    local Chunk, CompileError = loadstring(Source, "=" .. Entry.File)

    if not Chunk then
        return false, "couldn't compile " .. Entry.File .. ": " .. tostring(CompileError)
    end

    -- The script runs inside a pcall so a startup error ends up in the notification, not the console
    local Ran, RunError = pcall(Chunk)

    if not Ran then
        return false, tostring(RunError)
    end

    return true
end

if not game:IsLoaded() then
    game.Loaded:Wait()
end

-- The local player can arrive a moment after Loaded on some executors
if not Players.LocalPlayer then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
end

local Entry = Identify()
Notify("SuperNova", "Loading " .. Entry.Name .. "...", 3)

local Ok, Err = Run(Entry)

if not Ok then
    -- Error text can be long; keep the notification readable
    Notify("SuperNova", Entry.Name .. " failed: " .. Err:sub(1, 150), 10)
end

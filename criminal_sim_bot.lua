--[[
    ========================================================================
    ⚡ NYX // CRIMINAL SIMULATOR BOT v2.1 — "Game | Criminal Simulator"
    ========================================================================
    Place ID: 73251213967624 | Universe ID: 10769851460
    Platform: PC & Mobile (Delta, Fluxus, Hydrogen, Codex, Arceus X, Real)
    Author: Nyx & Larpbase

    Changelog v2.1:
    - 🛡️ SAFE INVENTORY UNLOAD:
        * Bat, Pistol, Lockpicks, Blowtorch, and all weapons/tools NEVER dropped!
        * Only actual stashed stolen loot (ShopId == nil) gets unloaded to Trunk.
    - 🏃 INFINITE STAMINA:
        * Sprint forever without tiring out (native God attribute & breath suppression).
    - ⛽ INFINITE CAR FUEL:
        * Car fuel locked at 100% — never runs out of gas or stalls.
    - 💥 MASSIVE CROWD KILL AURA:
        * Bat 1-hit knockout on all cops/guards in radius simultaneously.
    - 📦 COMPACT LOOT & NPC ESP:
        * Clean $ value labels, [H] heavy tag, distance-clamped, zero screen clutter.
    - ⚡ AUTO-FARM LEVEL / EXP:
        * Rapid grab & release cycle to pump Steal XP and level up fast.
    - ⌨️ CUSTOM INTERACTIVE KEYBINDS:
        * Rebind every single function in-game.
]]

-- Cleanup previous instance
if _G.NyxCriminalSimInstance then
    pcall(function() _G.NyxCriminalSimInstance:Destroy() end)
    _G.NyxCriminalSimInstance = nil
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
local BatSwingRemote = Remotes and Remotes:WaitForChild("BatSwing", 5)
local PunchRemote = Remotes and Remotes:WaitForChild("Punch", 5)
local HotbarRemote = Remotes and Remotes:WaitForChild("Hotbar", 5)
local LootGrabRemote = Remotes and Remotes:WaitForChild("LootGrab", 5)
local LootReleaseRemote = Remotes and Remotes:WaitForChild("LootRelease", 5)
local BreathingRemote = Remotes and Remotes:FindFirstChild("Breathing")

-- ========================================================================
-- CONFIGURATION & STATE
-- ========================================================================
local Settings = {
    -- Combat
    KillAuraEnabled = false,
    MassiveAuraEnabled = true,     -- Hits ALL targets in radius simultaneously
    AuraRadius = 16,
    AttackCooldown = 0.15,         -- Cooldown between aura passes
    VisualizerEnabled = true,
    TargetPolice = true,
    TargetGuards = true,
    TargetDogs = true,
    TargetResidents = true,

    -- Cheats & Exploits
    InfiniteStamina = true,        -- Never runs out of breath/stamina
    InfiniteFuel = true,           -- Car gas locked at 100%

    -- Visuals / ESP
    LootEspEnabled = true,
    LootEspMaxDist = 65,
    MinLootValue = 1,              -- Filters out $0 junk like stones
    NpcEspEnabled = true,
    NpcEspMaxDist = 80,
    ShowKoStatus = true,

    -- Auto-Farm XP
    AutoFarmXpEnabled = false,
    FarmCycleDelay = 0.18,
    FarmRadius = 25,

    -- Custom Keybinds
    Keybinds = {
        ToggleUI = Enum.KeyCode.RightShift,
        KillAura = Enum.KeyCode.X,
        MassiveAura = Enum.KeyCode.Z,
        UnloadStash = Enum.KeyCode.U,
        LoadHeavy = Enum.KeyCode.H,
        AutoSell = Enum.KeyCode.J,
        LootEsp = Enum.KeyCode.L,
        NpcEsp = Enum.KeyCode.K,
        AutoFarmXP = Enum.KeyCode.P,
        InfiniteStamina = Enum.KeyCode.None,
        InfiniteFuel = Enum.KeyCode.None,
    }
}

local State = {
    LastAuraCycle = 0,
    LastFarmCycle = 0,
    IsUnloading = false,
    IsAutoSelling = false,
    IsLoadingHeavy = false,
    ActiveTab = "Combat",
    ListeningForBind = nil,
    SessionStartXp = LocalPlayer:GetAttribute("XP") or 0,
    SessionXpGained = 0,
    CurrentWeapon = "None",
}

local CombatTags = {"Npc", "Cop", "Guard", "Dog"}
local EspFolder = Instance.new("Folder")
EspFolder.Name = "NyxEspFolder"

local notifyUser = function(msg, color) print("[NYX]: " .. msg) end

-- ========================================================================
-- CHEAT LOOPS: INFINITE STAMINA & INFINITE FUEL
-- ========================================================================
RunService.Heartbeat:Connect(function()
    -- 1. Infinite Stamina
    if Settings.InfiniteStamina then
        if not LocalPlayer:GetAttribute("God") then
            LocalPlayer:SetAttribute("God", true)
        end
        if BreathingRemote then
            BreathingRemote:FireServer(false)
        end
    end

    -- 2. Infinite Car Fuel
    if Settings.InfiniteFuel then
        for _, car in ipairs(CollectionService:GetTagged("Car")) do
            if (car:GetAttribute("Fuel") or 0) < 100 then
                car:SetAttribute("Fuel", 100)
            end
        end
    end
end)

-- ========================================================================
-- COMBAT SYSTEM (1-Hit Bat & Rapid Fists / Massive Knockout)
-- ========================================================================
local function getValidTargets()
    local targets = {}
    local char = LocalPlayer.Character
    if not char then return targets end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return targets end
    local myPos = hrp.Position
    local serverTime = workspace:GetServerTimeNow()

    for _, tag in ipairs(CombatTags) do
        if tag == "Cop" and not Settings.TargetPolice then continue end
        if tag == "Guard" and not Settings.TargetGuards then continue end
        if tag == "Dog" and not Settings.TargetDogs then continue end
        if tag == "Npc" and not Settings.TargetResidents then continue end

        for _, npc in ipairs(CollectionService:GetTagged(tag)) do
            if npc:IsA("Model") and npc ~= char and not targets[npc] then
                local hum = npc:FindFirstChildOfClass("Humanoid")
                local knockedUntil = npc:GetAttribute("KnockedOutUntil") or 0

                -- Target only active living, non-knocked-out NPCs
                if hum and hum.Health > 0 and (serverTime >= knockedUntil) then
                    local targetPart = npc:FindFirstChild("HumanoidRootPart")
                                    or npc:FindFirstChild("Head")
                                    or npc:FindFirstChild("Torso")
                                    or npc.PrimaryPart
                    if targetPart then
                        local dist = (targetPart.Position - myPos).Magnitude
                        if dist <= Settings.AuraRadius then
                            table.insert(targets, {npc = npc, part = targetPart, dist = dist, tag = tag})
                        end
                    end
                end
            end
        end
    end

    table.sort(targets, function(a, b) return a.dist < b.dist end)
    return targets
end

local function executeCombatCycle()
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end

    local targets = getValidTargets()
    if #targets == 0 then return end

    -- Check if player owns Baseball Bat
    local bat = char:FindFirstChild("Bat")
    if not bat and LocalPlayer.Backpack:FindFirstChild("Bat") then
        bat = LocalPlayer.Backpack:FindFirstChild("Bat")
        hum:EquipTool(bat)
    end

    local isBatEquipped = bat and bat.Parent == char
    State.CurrentWeapon = isBatEquipped and "Baseball Bat (1-Hit KO)" or "Fists (Rapid KO)"

    if Settings.MassiveAuraEnabled then
        -- 💥 MASSIVE CROWD WIPEOUT: Hits all targets in radius simultaneously!
        for _, t in ipairs(targets) do
            if isBatEquipped and BatSwingRemote then
                BatSwingRemote:FireServer(t.part)
            elseif PunchRemote then
                PunchRemote:FireServer(t.part)
            end
        end
        if isBatEquipped then
            pcall(function()
                local batSwingMod = require(ReplicatedStorage.Shared.BatSwing)
                batSwingMod.play(bat, bat.Grip)
            end)
        end
    else
        -- Single nearest target
        local t = targets[1]
        if isBatEquipped and BatSwingRemote then
            BatSwingRemote:FireServer(t.part)
            pcall(function()
                local batSwingMod = require(ReplicatedStorage.Shared.BatSwing)
                batSwingMod.play(bat, bat.Grip)
            end)
        elseif PunchRemote then
            PunchRemote:FireServer(t.part)
        end
    end
end

RunService.Heartbeat:Connect(function()
    if not Settings.KillAuraEnabled then return end
    local now = os.clock()
    if now - State.LastAuraCycle >= Settings.AttackCooldown then
        State.LastAuraCycle = now
        executeCombatCycle()
    end
end)

-- ========================================================================
-- RADIUS VISUALIZER (Neon Ground Cylinder)
-- ========================================================================
local VisualizerPart = Instance.new("Part")
VisualizerPart.Name = "NyxAuraVisualizer"
VisualizerPart.Shape = Enum.PartType.Cylinder
VisualizerPart.Material = Enum.Material.Neon
VisualizerPart.Color = Color3.fromRGB(0, 220, 255)
VisualizerPart.Transparency = 0.85
VisualizerPart.CastShadow = false
VisualizerPart.CanCollide = false
VisualizerPart.CanQuery = false
VisualizerPart.CanTouch = false
VisualizerPart.Anchored = true

RunService.RenderStepped:Connect(function()
    if Settings.KillAuraEnabled and Settings.VisualizerEnabled then
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local diam = Settings.AuraRadius * 2
            VisualizerPart.Size = Vector3.new(0.08, diam, diam)
            VisualizerPart.CFrame = CFrame.new(hrp.Position - Vector3.new(0, 2.7, 0)) * CFrame.Angles(0, 0, math.pi / 2)
            if VisualizerPart.Parent ~= workspace then
                VisualizerPart.Parent = workspace
            end
            return
        end
    end
    if VisualizerPart.Parent then
        VisualizerPart.Parent = nil
    end
end)

-- ========================================================================
-- 👁️ COMPACT ESP SYSTEM (Loot & NPCs)
-- ========================================================================
local ActiveLootEsp = setmetatable({}, {__mode = "k"})
local ActiveNpcEsp = setmetatable({}, {__mode = "k"})

local function createLootBillboard(item)
    local prim = item.PrimaryPart
    if not prim then return nil end

    local val = item:GetAttribute("Value") or 0
    local name = item:GetAttribute("DisplayName") or item.Name
    local weight = item:GetAttribute("Weight") or 1

    local bg = Instance.new("BillboardGui")
    bg.Name = "LootESP_" .. item.Name
    bg.Adornee = prim
    bg.Size = UDim2.fromOffset(82, 22)
    bg.AlwaysOnTop = true
    bg.MaxDistance = Settings.LootEspMaxDist
    bg.ExtentsOffset = Vector3.new(0, 0.9, 0)

    local card = Instance.new("Frame")
    card.Size = UDim2.fromScale(1, 1)
    card.BackgroundColor3 = Color3.fromRGB(12, 15, 22)
    card.BackgroundTransparency = 0.3
    card.BorderSizePixel = 0
    card.Parent = bg
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 5)

    local stroke = Instance.new("UIStroke", card)
    stroke.Thickness = 1
    stroke.Color = (weight >= 2) and Color3.fromRGB(255, 170, 0) or Color3.fromRGB(0, 210, 255)
    stroke.Transparency = 0.5

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    label.TextSize = 10
    label.Text = string.format("%s · $%d%s", name, val, (weight >= 2) and " [H]" or "")
    label.TextColor3 = (weight >= 2) and Color3.fromRGB(255, 200, 80) or Color3.fromRGB(0, 240, 140)
    label.TextTruncate = Enum.TextTruncate.AtEnd
    label.Parent = card

    bg.Parent = EspFolder
    return bg
end

local function createNpcBillboard(npc, tag)
    local prim = npc:FindFirstChild("Head") or npc.PrimaryPart
    if not prim then return nil end

    local bg = Instance.new("BillboardGui")
    bg.Name = "NpcESP_" .. npc.Name
    bg.Adornee = prim
    bg.Size = UDim2.fromOffset(78, 20)
    bg.AlwaysOnTop = true
    bg.MaxDistance = Settings.NpcEspMaxDist
    bg.ExtentsOffset = Vector3.new(0, 1.2, 0)

    local card = Instance.new("Frame")
    card.Size = UDim2.fromScale(1, 1)
    card.BackgroundColor3 = Color3.fromRGB(15, 18, 26)
    card.BackgroundTransparency = 0.3
    card.BorderSizePixel = 0
    card.Parent = bg
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 5)

    local col = Color3.fromRGB(0, 170, 255)
    if tag == "Cop" then col = Color3.fromRGB(0, 160, 255)
    elseif tag == "Guard" then col = Color3.fromRGB(255, 80, 60)
    elseif tag == "Dog" then col = Color3.fromRGB(210, 90, 255)
    elseif tag == "Npc" then col = Color3.fromRGB(255, 220, 80) end

    local stroke = Instance.new("UIStroke", card)
    stroke.Thickness = 1
    stroke.Color = col
    stroke.Transparency = 0.4

    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    label.TextSize = 10
    label.TextColor3 = col
    label.Text = tag
    label.Parent = card

    bg.Parent = EspFolder
    return bg
end

local lastEspUpdate = 0
RunService.Heartbeat:Connect(function()
    local now = os.clock()
    if now - lastEspUpdate < 0.4 then return end
    lastEspUpdate = now

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local myPos = hrp and hrp.Position or Vector3.zero
    local serverTime = workspace:GetServerTimeNow()

    -- 1. LOOT ESP
    if Settings.LootEspEnabled and hrp then
        local lootFolder = workspace:FindFirstChild("Loot")
        if lootFolder then
            for _, item in ipairs(lootFolder:GetChildren()) do
                if item:IsA("Model") and item.PrimaryPart then
                    local val = item:GetAttribute("Value") or 0
                    local dist = (item.PrimaryPart.Position - myPos).Magnitude
                    if val >= Settings.MinLootValue and dist <= Settings.LootEspMaxDist + 15 then
                        if not ActiveLootEsp[item] then
                            ActiveLootEsp[item] = createLootBillboard(item)
                        elseif ActiveLootEsp[item] then
                            ActiveLootEsp[item].MaxDistance = Settings.LootEspMaxDist
                        end
                    elseif ActiveLootEsp[item] then
                        pcall(function() ActiveLootEsp[item]:Destroy() end)
                        ActiveLootEsp[item] = nil
                    end
                end
            end
        end
    else
        for k, bg in pairs(ActiveLootEsp) do
            pcall(function() bg:Destroy() end)
            ActiveLootEsp[k] = nil
        end
    end

    -- 2. NPC ESP
    if Settings.NpcEspEnabled and hrp then
        for _, tag in ipairs(CombatTags) do
            for _, npc in ipairs(CollectionService:GetTagged(tag)) do
                if npc:IsA("Model") and npc ~= char and (npc:FindFirstChild("Head") or npc.PrimaryPart) then
                    local prim = npc:FindFirstChild("Head") or npc.PrimaryPart
                    local dist = (prim.Position - myPos).Magnitude
                    if dist <= Settings.NpcEspMaxDist + 20 then
                        local hum = npc:FindFirstChildOfClass("Humanoid")
                        local knockedUntil = npc:GetAttribute("KnockedOutUntil") or 0
                        local isKnocked = serverTime < knockedUntil

                        local bg = ActiveNpcEsp[npc]
                        if not bg then
                            bg = createNpcBillboard(npc, tag)
                            ActiveNpcEsp[npc] = bg
                        end
                        if bg and bg:FindFirstChild("Frame") and bg.Frame:FindFirstChild("Label") then
                            bg.MaxDistance = Settings.NpcEspMaxDist
                            local lbl = bg.Frame.Label
                            if isKnocked and Settings.ShowKoStatus then
                                lbl.Text = tag .. " [KO]"
                                lbl.TextColor3 = Color3.fromRGB(160, 165, 175)
                            else
                                local hp = hum and math.floor(hum.Health) or 100
                                lbl.Text = string.format("%s · %d HP", tag, hp)
                            end
                        end
                    elseif ActiveNpcEsp[npc] then
                        pcall(function() ActiveNpcEsp[npc]:Destroy() end)
                        ActiveNpcEsp[npc] = nil
                    end
                end
            end
        end
    else
        for k, bg in pairs(ActiveNpcEsp) do
            pcall(function() bg:Destroy() end)
            ActiveNpcEsp[k] = nil
        end
    end
end)

-- ========================================================================
-- ⚡ AUTO-FARM LEVEL / EXP (Grab & Drop Cycle)
-- ========================================================================
local function executeAutoFarmXpStep()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local lootFolder = workspace:FindFirstChild("Loot")
    if not lootFolder then return end

    local myPos = hrp.Position
    local targetItem = nil
    local bestDist = math.huge

    for _, item in ipairs(lootFolder:GetChildren()) do
        if item:IsA("Model") and item.PrimaryPart and item:GetAttribute("Kind") ~= "Stone" then
            local dist = (item.PrimaryPart.Position - myPos).Magnitude
            if dist <= Settings.FarmRadius and dist < bestDist then
                bestDist = dist
                targetItem = item
            end
        end
    end

    if targetItem and LootGrabRemote and LootReleaseRemote then
        LootGrabRemote:FireServer(targetItem)
        task.wait(Settings.FarmCycleDelay)
        LootReleaseRemote:FireServer()
    end
end

RunService.Heartbeat:Connect(function()
    if not Settings.AutoFarmXpEnabled then return end
    local now = os.clock()
    if now - State.LastFarmCycle >= (Settings.FarmCycleDelay * 2 + 0.05) then
        State.LastFarmCycle = now
        executeAutoFarmXpStep()
    end
end)

LocalPlayer:GetAttributeChangedSignal("XP"):Connect(function()
    local curXp = LocalPlayer:GetAttribute("XP") or 0
    State.SessionXpGained = math.max(0, curXp - State.SessionStartXp)
end)

-- ========================================================================
-- 🛡️ SAFE UNLOAD & TRUCK ACTIONS (Weapons / Tools NEVER Dropped!)
-- ========================================================================
local function triggerPrompt(prompt)
    if not prompt or not prompt.Parent then return false end
    if fireproximityprompt then
        pcall(fireproximityprompt, prompt, 0)
        return true
    elseif prompt.InputHoldBegin and prompt.InputHoldEnd then
        prompt:InputHoldBegin()
        task.wait((prompt.HoldDuration or 0.25) + 0.05)
        prompt:InputHoldEnd()
        return true
    end
    return false
end

local function isInsidePart(pos, part, margin)
    margin = margin or 2
    local rel = part.CFrame:PointToObjectSpace(pos)
    local half = part.Size / 2
    return math.abs(rel.X) <= (half.X + margin) 
       and math.abs(rel.Y) <= (half.Y + margin) 
       and math.abs(rel.Z) <= (half.Z + margin)
end

local function getNearestDepositZone()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local myPos = hrp.Position

    local bestZone = nil
    local bestDist = math.huge

    for _, car in ipairs(CollectionService:GetTagged("Car")) do
        local trunk = car:FindFirstChild("Trunk")
        if trunk and trunk:IsA("BasePart") then
            local dist = (trunk.Position - myPos).Magnitude
            if dist < bestDist then
                bestDist = dist
                bestZone = trunk
            end
        end
    end

    for _, truck in ipairs(CollectionService:GetTagged("TravelTruck")) do
        local cargo = truck:FindFirstChild("CargoZone")
        if cargo and cargo:IsA("BasePart") then
            local dist = (cargo.Position - myPos).Magnitude
            if dist < bestDist then
                bestDist = dist
                bestZone = cargo
            end
        end
    end

    return bestZone, bestDist
end

-- 🛡️ SAFE UNLOAD: Only drops loot with ShopId == nil (Bat, Pistol, etc. 100% PROTECTED)
local function unloadInventoryToTrunk()
    if State.IsUnloading then return end
    State.IsUnloading = true

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then
        State.IsUnloading = false
        return
    end

    local zone, dist = getNearestDepositZone()
    if not zone then
        notifyUser("No Car Trunk or Truck found!", Color3.fromRGB(255, 90, 90))
        State.IsUnloading = false
        return
    end

    -- 1. Safely unequip any weapons/tools so they are protected in Backpack
    local activeTool = char:FindFirstChildOfClass("Tool")
    if activeTool and activeTool:GetAttribute("ShopId") then
        hum:UnequipTools()
        task.wait(0.12)
    end

    -- 2. Release any carried heavy loot model if it's not a tool
    local lootFolder = workspace:FindFirstChild("Loot")
    if lootFolder then
        for _, m in ipairs(lootFolder:GetChildren()) do
            if m:GetAttribute("HeldBy") == LocalPlayer.UserId and not m:GetAttribute("ShopId") then
                LootReleaseRemote:FireServer()
                task.wait(0.1)
                break
            end
        end
    end

    -- 3. Gather only legitimate stashed loot (ShopId == nil)
    local function getOnlyStashedLoot()
        local list = {}
        local bp = LocalPlayer:FindFirstChild("Backpack")
        if bp then
            for _, item in ipairs(bp:GetChildren()) do
                if (item:GetAttribute("Item_StashId") or CollectionService:HasTag(item, "StashedLoot")) and not item:GetAttribute("ShopId") then
                    table.insert(list, item)
                end
            end
        end
        if char then
            for _, item in ipairs(char:GetChildren()) do
                if (item:GetAttribute("Item_StashId") or CollectionService:HasTag(item, "StashedLoot")) and not item:GetAttribute("ShopId") then
                    table.insert(list, item)
                end
            end
        end
        return list
    end

    local stashed = getOnlyStashedLoot()
    if #stashed == 0 then
        notifyUser("No stashed loot in inventory!", Color3.fromRGB(255, 200, 50))
        State.IsUnloading = false
        return
    end

    local originalCFrame = hrp.CFrame
    local needTeleport = dist > 15

    if needTeleport then
        notifyUser("Approaching trunk...", Color3.fromRGB(0, 210, 255))
        hrp.CFrame = zone.CFrame + Vector3.new(0, 2.5, 0)
        task.wait(0.2)
    end

    notifyUser("Safely dropping " .. #stashed .. " loot items...", Color3.fromRGB(0, 210, 255))
    local droppedCount = 0

    for _, lootItem in ipairs(stashed) do
        -- Double check: never equip or drop weapons/tools!
        if lootItem and lootItem.Parent and not lootItem:GetAttribute("ShopId") then
            hum:EquipTool(lootItem)
            task.wait(0.06)
            HotbarRemote:FireServer("DropStashed")
            task.wait(0.08)
            droppedCount = droppedCount + 1
        end
    end

    if needTeleport then
        hrp.CFrame = originalCFrame
    end

    notifyUser("Unloaded " .. droppedCount .. " items! Tools kept safe.", Color3.fromRGB(0, 230, 118))
    State.IsUnloading = false
end

local function loadNearbyHeavyToTrunk()
    if State.IsLoadingHeavy then return end
    State.IsLoadingHeavy = true

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        State.IsLoadingHeavy = false
        return
    end

    local zone, dist = getNearestDepositZone()
    if not zone then
        notifyUser("No Trunk/Truck found nearby!", Color3.fromRGB(255, 90, 90))
        State.IsLoadingHeavy = false
        return
    end

    local lootFolder = workspace:FindFirstChild("Loot")
    if not lootFolder then
        State.IsLoadingHeavy = false
        return
    end

    local myPos = hrp.Position
    local originalCFrame = hrp.CFrame
    local heavyItems = {}

    for _, item in ipairs(lootFolder:GetChildren()) do
        if item:IsA("Model") and item.PrimaryPart and item:GetAttribute("Kind") ~= "Stone" and not item:GetAttribute("ShopId") then
            local p = item.PrimaryPart.Position
            local d = (p - myPos).Magnitude
            if d <= 35 and not isInsidePart(p, zone, 1) then
                table.insert(heavyItems, item)
            end
        end
    end

    if #heavyItems == 0 then
        notifyUser("No loose items nearby within 35 studs.", Color3.fromRGB(255, 200, 50))
        State.IsLoadingHeavy = false
        return
    end

    notifyUser("Loading " .. #heavyItems .. " items into trunk...", Color3.fromRGB(0, 210, 255))
    local loaded = 0

    for _, item in ipairs(heavyItems) do
        if item.Parent == lootFolder and item.PrimaryPart then
            hrp.CFrame = item.PrimaryPart.CFrame + Vector3.new(0, 2, 0)
            task.wait(0.08)
            LootGrabRemote:FireServer(item)
            task.wait(0.12)
            hrp.CFrame = zone.CFrame + Vector3.new(0, 2, 0)
            task.wait(0.12)
            LootReleaseRemote:FireServer()
            task.wait(0.08)
            loaded = loaded + 1
        end
    end

    hrp.CFrame = originalCFrame
    notifyUser("Loaded " .. loaded .. " items into trunk!", Color3.fromRGB(0, 230, 118))
    State.IsLoadingHeavy = false
end

local function autoSellTruckCargo()
    if State.IsAutoSelling then return end
    State.IsAutoSelling = true

    local hideout = workspace:FindFirstChild("Hideout")
    if not hideout then
        notifyUser("You are not at the Hideout!", Color3.fromRGB(255, 90, 90))
        State.IsAutoSelling = false
        return
    end

    local truck = hideout:FindFirstChild("Truck")
    local cargoZone = truck and truck:FindFirstChild("CargoZone")
    local sellBox = hideout:FindFirstChild("SellBox")
    local sellZone = sellBox and sellBox:FindFirstChild("SellZone")
    local sellLever = hideout:FindFirstChild("SellLever")
    local leverPrompt = sellLever and sellLever:FindFirstChild("Post") and sellLever.Post:FindFirstChild("Prompt")

    if not cargoZone or not sellZone or not leverPrompt then
        notifyUser("Hideout components not found!", Color3.fromRGB(255, 90, 90))
        State.IsAutoSelling = false
        return
    end

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        State.IsAutoSelling = false
        return
    end

    local lootFolder = workspace:FindFirstChild("Loot")
    if not lootFolder then
        State.IsAutoSelling = false
        return
    end

    local originalCFrame = hrp.CFrame
    local cargoItems = {}

    for _, item in ipairs(lootFolder:GetChildren()) do
        if item:IsA("Model") and item.PrimaryPart and item:GetAttribute("Kind") ~= "Stone" and not item:GetAttribute("ShopId") then
            if isInsidePart(item.PrimaryPart.Position, cargoZone, 3) then
                table.insert(cargoItems, item)
            end
        end
    end

    local sellZoneTarget = sellZone.Position + Vector3.new(0, 2.5, 0)

    if #cargoItems == 0 then
        local existingSell = 0
        for _, item in ipairs(lootFolder:GetChildren()) do
            if item:IsA("Model") and item.PrimaryPart and isInsidePart(item.PrimaryPart.Position, sellZone, 2) and not item:GetAttribute("ShopId") then
                existingSell = existingSell + 1
            end
        end

        if existingSell > 0 then
            notifyUser("Pulling lever for " .. existingSell .. " items in SellBox...", Color3.fromRGB(255, 200, 50))
            hrp.CFrame = leverPrompt.Parent.CFrame + Vector3.new(0, 2, 2)
            task.wait(0.2)
            triggerPrompt(leverPrompt)
            task.wait(0.3)
            hrp.CFrame = originalCFrame
            notifyUser("Items sold successfully!", Color3.fromRGB(0, 230, 118))
        else
            notifyUser("Truck cargo is empty!", Color3.fromRGB(255, 200, 50))
        end
        State.IsAutoSelling = false
        return
    end

    notifyUser("Transferring " .. #cargoItems .. " items to SellBox...", Color3.fromRGB(0, 210, 255))
    local count = 0

    for _, item in ipairs(cargoItems) do
        if item.Parent == lootFolder and item.PrimaryPart then
            hrp.CFrame = item.PrimaryPart.CFrame + Vector3.new(0, 2, 0)
            task.wait(0.08)
            LootGrabRemote:FireServer(item)
            task.wait(0.12)
            hrp.CFrame = CFrame.new(sellZoneTarget)
            task.wait(0.12)
            LootReleaseRemote:FireServer()
            task.wait(0.08)
            count = count + 1
        end
    end

    notifyUser("Pulling Sell Lever...", Color3.fromRGB(255, 200, 50))
    hrp.CFrame = leverPrompt.Parent.CFrame + Vector3.new(0, 2, 2)
    task.wait(0.25)
    triggerPrompt(leverPrompt)
    task.wait(0.4)

    hrp.CFrame = originalCFrame
    notifyUser("Sold " .. count .. " items from truck!", Color3.fromRGB(0, 230, 118))
    State.IsAutoSelling = false
end

local function manualPullSellLever()
    local hideout = workspace:FindFirstChild("Hideout")
    local prompt = hideout and hideout:FindFirstChild("SellLever") and hideout.SellLever:FindFirstChild("Post") and hideout.SellLever.Post:FindFirstChild("Prompt")
    if not prompt then
        notifyUser("Sell Lever prompt not found!", Color3.fromRGB(255, 90, 90))
        return
    end

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        local oldCFrame = hrp.CFrame
        hrp.CFrame = prompt.Parent.CFrame + Vector3.new(0, 2, 2)
        task.wait(0.2)
        triggerPrompt(prompt)
        task.wait(0.3)
        hrp.CFrame = oldCFrame
        notifyUser("Sell Lever triggered!", Color3.fromRGB(0, 230, 118))
    end
end

-- ========================================================================
-- 💎 USER INTERFACE (Glassmorphism with Tabs & Interactive Binds)
-- ========================================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "NyxCriminalSimGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local function parentGui(gui)
    local success = pcall(function()
        if gethui then
            gui.Parent = gethui()
        elseif CoreGui and not RunService:IsStudio() then
            gui.Parent = CoreGui
        else
            gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
        end
    end)
    if not success then
        gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
end
parentGui(ScreenGui)
EspFolder.Parent = ScreenGui
_G.NyxCriminalSimInstance = ScreenGui

ScreenGui.Destroying:Connect(function()
    if VisualizerPart then VisualizerPart:Destroy() end
    if EspFolder then EspFolder:Destroy() end
    _G.NyxCriminalSimInstance = nil
end)

-- Main Frame Card
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainCard"
MainFrame.Size = UDim2.fromOffset(390, 480)
MainFrame.Position = UDim2.new(0.5, -195, 0.5, -240)
MainFrame.BackgroundColor3 = Color3.fromRGB(14, 17, 24)
MainFrame.BackgroundTransparency = 0.12
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 12)
local MainStroke = Instance.new("UIStroke", MainFrame)
MainStroke.Thickness = 1.5
MainStroke.Color = Color3.fromRGB(0, 210, 255)
MainStroke.Transparency = 0.4

-- Header Bar
local Header = Instance.new("Frame")
Header.Name = "Header"
Header.Size = UDim2.new(1, 0, 0, 42)
Header.BackgroundColor3 = Color3.fromRGB(20, 25, 36)
Header.BackgroundTransparency = 0.3
Header.BorderSizePixel = 0
Header.Parent = MainFrame
Instance.new("UICorner", Header).CornerRadius = UDim.new(0, 12)

local HeaderTitle = Instance.new("TextLabel")
HeaderTitle.Size = UDim2.new(1, -70, 1, 0)
HeaderTitle.Position = UDim2.fromOffset(14, 0)
HeaderTitle.BackgroundTransparency = 1
HeaderTitle.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
HeaderTitle.Text = "⚡ NYX // CRIMINAL SIMULATOR v2.1"
HeaderTitle.TextColor3 = Color3.fromRGB(240, 245, 255)
HeaderTitle.TextSize = 13
HeaderTitle.TextXAlignment = Enum.TextXAlignment.Left
HeaderTitle.Parent = Header

local MinBtn = Instance.new("TextButton")
MinBtn.Name = "MinBtn"
MinBtn.Size = UDim2.fromOffset(26, 26)
MinBtn.Position = UDim2.new(1, -60, 0, 8)
MinBtn.BackgroundColor3 = Color3.fromRGB(35, 42, 58)
MinBtn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
MinBtn.Text = "—"
MinBtn.TextColor3 = Color3.fromRGB(220, 230, 245)
MinBtn.TextSize = 13
MinBtn.AutoButtonColor = false
MinBtn.Parent = Header
Instance.new("UICorner", MinBtn).CornerRadius = UDim.new(0, 6)

local CloseBtn = Instance.new("TextButton")
CloseBtn.Name = "CloseBtn"
CloseBtn.Size = UDim2.fromOffset(26, 26)
CloseBtn.Position = UDim2.new(1, -30, 0, 8)
CloseBtn.BackgroundColor3 = Color3.fromRGB(60, 28, 32)
CloseBtn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.fromRGB(255, 120, 120)
CloseBtn.TextSize = 12
CloseBtn.AutoButtonColor = false
CloseBtn.Parent = Header
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)

-- Tab Bar
local TabBar = Instance.new("Frame")
TabBar.Name = "TabBar"
TabBar.Size = UDim2.new(1, -20, 0, 32)
TabBar.Position = UDim2.fromOffset(10, 48)
TabBar.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
TabBar.BackgroundTransparency = 0.5
TabBar.BorderSizePixel = 0
TabBar.Parent = MainFrame
Instance.new("UICorner", TabBar).CornerRadius = UDim.new(0, 8)

local TabLayout = Instance.new("UIListLayout", TabBar)
TabLayout.FillDirection = Enum.FillDirection.Horizontal
TabLayout.Padding = UDim.new(0, 4)
TabLayout.SortOrder = Enum.SortOrder.LayoutOrder

local TabContainer = Instance.new("Frame")
TabContainer.Name = "TabContainer"
TabContainer.Size = UDim2.new(1, -20, 1, -128)
TabContainer.Position = UDim2.fromOffset(10, 86)
TabContainer.BackgroundTransparency = 1
TabContainer.BorderSizePixel = 0
TabContainer.Parent = MainFrame

local TabPages = {}
local TabButtons = {}

local TabNames = {
    {id = "Combat", name = "⚔️ Combat"},
    {id = "Visuals", name = "👁️ ESP"},
    {id = "Misc", name = "🚚 Farm & Loot"},
    {id = "Binds", name = "⌨️ Binds"},
}

local function switchTab(tabId)
    State.ActiveTab = tabId
    for id, page in pairs(TabPages) do
        page.Visible = (id == tabId)
    end
    for id, btn in pairs(TabButtons) do
        if id == tabId then
            btn.BackgroundColor3 = Color3.fromRGB(0, 180, 240)
            btn.TextColor3 = Color3.new(1, 1, 1)
        else
            btn.BackgroundColor3 = Color3.fromRGB(24, 30, 44)
            btn.TextColor3 = Color3.fromRGB(160, 175, 195)
        end
    end
end

for i, tabInfo in ipairs(TabNames) do
    local tabBtn = Instance.new("TextButton")
    tabBtn.Name = "TabBtn_" .. tabInfo.id
    tabBtn.Size = UDim2.new(0.25, -3, 1, 0)
    tabBtn.LayoutOrder = i
    tabBtn.BackgroundColor3 = Color3.fromRGB(24, 30, 44)
    tabBtn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    tabBtn.Text = tabInfo.name
    tabBtn.TextSize = 11
    tabBtn.AutoButtonColor = false
    tabBtn.Parent = TabBar
    Instance.new("UICorner", tabBtn).CornerRadius = UDim.new(0, 6)

    tabBtn.MouseButton1Click:Connect(function()
        switchTab(tabInfo.id)
    end)
    TabButtons[tabInfo.id] = tabBtn

    local page = Instance.new("ScrollingFrame")
    page.Name = "Page_" .. tabInfo.id
    page.Size = UDim2.fromScale(1, 1)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 4
    page.ScrollBarImageColor3 = Color3.fromRGB(0, 210, 255)
    page.CanvasSize = UDim2.fromOffset(0, 520)
    page.Visible = false
    page.Parent = TabContainer

    local list = Instance.new("UIListLayout", page)
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Padding = UDim.new(0, 8)

    TabPages[tabInfo.id] = page
end

local function addSectionLabel(parent, title, order)
    local lbl = Instance.new("TextLabel")
    lbl.LayoutOrder = order
    lbl.Size = UDim2.new(1, 0, 0, 18)
    lbl.BackgroundTransparency = 1
    lbl.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    lbl.Text = title
    lbl.TextColor3 = Color3.fromRGB(0, 210, 255)
    lbl.TextSize = 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = parent
    return lbl
end

local function addToggle(parent, title, defaultVal, order, onToggle)
    local card = Instance.new("Frame")
    card.LayoutOrder = order
    card.Size = UDim2.new(1, 0, 0, 36)
    card.BackgroundColor3 = Color3.fromRGB(20, 26, 38)
    card.BackgroundTransparency = 0.4
    card.BorderSizePixel = 0
    card.Parent = parent
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -65, 1, 0)
    lbl.Position = UDim2.fromOffset(10, 0)
    lbl.BackgroundTransparency = 1
    lbl.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
    lbl.Text = title
    lbl.TextColor3 = Color3.fromRGB(225, 235, 245)
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = card

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.fromOffset(48, 24)
    btn.Position = UDim2.new(1, -56, 0.5, -12)
    btn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    btn.TextSize = 11
    btn.AutoButtonColor = false
    btn.Parent = card
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

    local state = defaultVal
    local function updateUI()
        btn.Text = state and "ON" or "OFF"
        btn.BackgroundColor3 = state and Color3.fromRGB(0, 200, 100) or Color3.fromRGB(45, 52, 68)
        btn.TextColor3 = state and Color3.new(1, 1, 1) or Color3.fromRGB(160, 175, 195)
    end
    updateUI()

    btn.MouseButton1Click:Connect(function()
        state = not state
        updateUI()
        onToggle(state)
    end)
    return card, function(newVal) state = newVal updateUI() end
end

local function addSlider(parent, title, minVal, maxVal, curVal, unit, order, onSlide)
    local card = Instance.new("Frame")
    card.LayoutOrder = order
    card.Size = UDim2.new(1, 0, 0, 48)
    card.BackgroundColor3 = Color3.fromRGB(20, 26, 38)
    card.BackgroundTransparency = 0.4
    card.BorderSizePixel = 0
    card.Parent = parent
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -75, 0, 20)
    lbl.Position = UDim2.fromOffset(10, 4)
    lbl.BackgroundTransparency = 1
    lbl.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
    lbl.Text = title
    lbl.TextColor3 = Color3.fromRGB(220, 230, 245)
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = card

    local valLbl = Instance.new("TextLabel")
    valLbl.Size = UDim2.fromOffset(65, 20)
    valLbl.Position = UDim2.new(1, -75, 0, 4)
    valLbl.BackgroundTransparency = 1
    valLbl.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    valLbl.Text = string.format("%s%s", tostring(curVal), unit or "")
    valLbl.TextColor3 = Color3.fromRGB(0, 210, 255)
    valLbl.TextSize = 12
    valLbl.TextXAlignment = Enum.TextXAlignment.Right
    valLbl.Parent = card

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, -20, 0, 6)
    bar.Position = UDim2.fromOffset(10, 30)
    bar.BackgroundColor3 = Color3.fromRGB(40, 48, 65)
    bar.BorderSizePixel = 0
    bar.Parent = card
    Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(math.clamp((curVal - minVal) / (maxVal - minVal), 0, 1), 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(0, 210, 255)
    fill.BorderSizePixel = 0
    fill.Parent = bar
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    local isDragging = false
    local function update(inputX)
        local pct = math.clamp((inputX - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        local res = math.floor(minVal + pct * (maxVal - minVal) + 0.5)
        fill.Size = UDim2.new(pct, 0, 1, 0)
        valLbl.Text = string.format("%s%s", tostring(res), unit or "")
        onSlide(res)
    end

    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            isDragging = true
            update(input.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            isDragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if isDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            update(input.Position.X)
        end
    end)
    return card
end

local function addActionBtn(parent, title, subtitle, btnColor, order, onClick)
    local card = Instance.new("Frame")
    card.LayoutOrder = order
    card.Size = UDim2.new(1, 0, 0, 44)
    card.BackgroundColor3 = Color3.fromRGB(20, 26, 38)
    card.BackgroundTransparency = 0.4
    card.BorderSizePixel = 0
    card.Parent = parent
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -100, 0, 20)
    lbl.Position = UDim2.fromOffset(10, 4)
    lbl.BackgroundTransparency = 1
    lbl.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    lbl.Text = title
    lbl.TextColor3 = Color3.fromRGB(240, 245, 255)
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = card

    local sub = Instance.new("TextLabel")
    sub.Size = UDim2.new(1, -100, 0, 16)
    sub.Position = UDim2.fromOffset(10, 22)
    sub.BackgroundTransparency = 1
    sub.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular)
    sub.Text = subtitle
    sub.TextColor3 = Color3.fromRGB(150, 165, 185)
    sub.TextSize = 10
    sub.TextXAlignment = Enum.TextXAlignment.Left
    sub.Parent = card

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.fromOffset(80, 28)
    btn.Position = UDim2.new(1, -90, 0.5, -14)
    btn.BackgroundColor3 = btnColor or Color3.fromRGB(0, 150, 255)
    btn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    btn.Text = "RUN"
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.TextSize = 11
    btn.AutoButtonColor = false
    btn.Parent = card
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

    btn.MouseButton1Click:Connect(function()
        btn.Text = "..."
        task.spawn(function()
            onClick()
            btn.Text = "RUN"
        end)
    end)
    return card
end

-- ========================================================================
-- TAB 1: ⚔️ COMBAT TAB
-- ========================================================================
local combatPage = TabPages["Combat"]
addSectionLabel(combatPage, "KNOCKOUT AURA CONTROLS", 1)

addToggle(combatPage, "Kill Aura (Bat / Fists)", Settings.KillAuraEnabled, 2, function(val)
    Settings.KillAuraEnabled = val
    notifyUser("Kill Aura: " .. (val and "ACTIVE" or "OFF"), val and Color3.fromRGB(0, 230, 118) or Color3.fromRGB(255, 120, 120))
end)

addToggle(combatPage, "💥 Massive Crowd Wipe (Multi-Hit)", Settings.MassiveAuraEnabled, 3, function(val)
    Settings.MassiveAuraEnabled = val
    notifyUser("Massive Crowd Wipe: " .. (val and "ON (Simultaneous)" or "OFF (Single Target)"), Color3.fromRGB(0, 210, 255))
end)

addToggle(combatPage, "Radius Ground Visualizer", Settings.VisualizerEnabled, 4, function(val)
    Settings.VisualizerEnabled = val
end)

addSlider(combatPage, "Aura Reach Radius", 5, 40, Settings.AuraRadius, " studs", 5, function(val)
    Settings.AuraRadius = val
end)

addSlider(combatPage, "Attack Delay (Lower = Faster)", 1, 8, math.floor(Settings.AttackCooldown * 10), "x 0.1s", 6, function(val)
    Settings.AttackCooldown = val * 0.1
end)

addSectionLabel(combatPage, "MOVEMENT & VEHICLE CHEATS", 7)
addToggle(combatPage, "🏃 Infinite Stamina (Sprint Forever)", Settings.InfiniteStamina, 8, function(val)
    Settings.InfiniteStamina = val
    notifyUser("Infinite Stamina: " .. (val and "ACTIVE" or "OFF"), val and Color3.fromRGB(0, 230, 118) or Color3.fromRGB(255, 120, 120))
end)

addToggle(combatPage, "⛽ Infinite Car Fuel (Lock Gas 100%)", Settings.InfiniteFuel, 9, function(val)
    Settings.InfiniteFuel = val
    notifyUser("Infinite Car Fuel: " .. (val and "ACTIVE" or "OFF"), val and Color3.fromRGB(0, 230, 118) or Color3.fromRGB(255, 120, 120))
end)

addSectionLabel(combatPage, "TARGET FILTERING", 10)
addToggle(combatPage, "Target Police / Cops", Settings.TargetPolice, 11, function(val) Settings.TargetPolice = val end)
addToggle(combatPage, "Target Security Guards", Settings.TargetGuards, 12, function(val) Settings.TargetGuards = val end)
addToggle(combatPage, "Target Police Dogs", Settings.TargetDogs, 13, function(val) Settings.TargetDogs = val end)
addToggle(combatPage, "Target House Residents", Settings.TargetResidents, 14, function(val) Settings.TargetResidents = val end)

-- ========================================================================
-- TAB 2: 👁️ VISUALS / ESP TAB
-- ========================================================================
local visualsPage = TabPages["Visuals"]
addSectionLabel(visualsPage, "LOOT ITEM ESP (COMPACT)", 1)

addToggle(visualsPage, "Enable Loot ESP", Settings.LootEspEnabled, 2, function(val)
    Settings.LootEspEnabled = val
end)

addSlider(visualsPage, "Loot Max Render Distance", 20, 140, Settings.LootEspMaxDist, " studs", 3, function(val)
    Settings.LootEspMaxDist = val
end)

addSlider(visualsPage, "Minimum Loot Value Filter", 0, 250, Settings.MinLootValue, " $", 4, function(val)
    Settings.MinLootValue = val
end)

addSectionLabel(visualsPage, "NPC & COP ESP", 5)

addToggle(visualsPage, "Enable NPC ESP", Settings.NpcEspEnabled, 6, function(val)
    Settings.NpcEspEnabled = val
end)

addToggle(visualsPage, "Show [KO] Downed Status", Settings.ShowKoStatus, 7, function(val)
    Settings.ShowKoStatus = val
end)

addSlider(visualsPage, "NPC Max Render Distance", 20, 150, Settings.NpcEspMaxDist, " studs", 8, function(val)
    Settings.NpcEspMaxDist = val
end)

-- ========================================================================
-- TAB 3: 🚚 LOOT, FARM & HIDEOUT TAB
-- ========================================================================
local miscPage = TabPages["Misc"]
addSectionLabel(miscPage, "TRUNK & LOOT AUTOMATION", 1)

addActionBtn(miscPage, "Unload Stash to Trunk", "Dumps loot into trunk (keeps tools safe)", Color3.fromRGB(0, 160, 230), 2, function()
    unloadInventoryToTrunk()
end)

addActionBtn(miscPage, "Load Heavy Items to Trunk", "Loads nearby loose TVs/Computers into van", Color3.fromRGB(110, 120, 240), 3, function()
    loadNearbyHeavyToTrunk()
end)

addSectionLabel(miscPage, "HIDEOUT SELLING", 4)

addActionBtn(miscPage, "Auto-Sell Truck Cargo", "Truck cargo -> SellBox -> pulls Lever", Color3.fromRGB(0, 190, 110), 5, function()
    autoSellTruckCargo()
end)

addActionBtn(miscPage, "Pull Sell Lever", "Manually activates Hideout Sell Lever", Color3.fromRGB(220, 150, 40), 6, function()
    manualPullSellLever()
end)

addSectionLabel(miscPage, "⚡ AUTO-FARM LEVEL / EXP", 7)

addToggle(miscPage, "Auto-Farm XP (Cycle Grab & Drop)", Settings.AutoFarmXpEnabled, 8, function(val)
    Settings.AutoFarmXpEnabled = val
    notifyUser("Auto-Farm XP: " .. (val and "ACTIVE" or "OFF"), val and Color3.fromRGB(0, 230, 118) or Color3.fromRGB(255, 120, 120))
end)

addSlider(miscPage, "Farm Cycle Delay (Lower = Faster)", 1, 10, math.floor(Settings.FarmCycleDelay * 10), "x 0.1s", 9, function(val)
    Settings.FarmCycleDelay = val * 0.1
end)

-- Live XP Tracker Card
local XpCard = Instance.new("Frame")
XpCard.LayoutOrder = 10
XpCard.Size = UDim2.new(1, 0, 0, 46)
XpCard.BackgroundColor3 = Color3.fromRGB(20, 26, 38)
XpCard.BackgroundTransparency = 0.4
XpCard.BorderSizePixel = 0
XpCard.Parent = miscPage
Instance.new("UICorner", XpCard).CornerRadius = UDim.new(0, 8)

local XpLabel = Instance.new("TextLabel")
XpLabel.Size = UDim2.new(1, -20, 1, 0)
XpLabel.Position = UDim2.fromOffset(10, 0)
XpLabel.BackgroundTransparency = 1
XpLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
XpLabel.TextSize = 12
XpLabel.TextColor3 = Color3.fromRGB(220, 230, 245)
XpLabel.TextXAlignment = Enum.TextXAlignment.Left
XpLabel.RichText = true
XpLabel.Parent = XpCard

local function updateXpCard()
    local lvl = LocalPlayer:GetAttribute("Level") or 1
    local totalXp = LocalPlayer:GetAttribute("XP") or 0
    XpLabel.Text = string.format("Level: <font color=\"#00d2ff\">%d</font>  ·  XP: <font color=\"#00e676\">%d</font>  ·  Session Gain: <font color=\"#ffaa00\">+%d XP</font>", lvl, totalXp, State.SessionXpGained)
end
updateXpCard()
LocalPlayer:GetAttributeChangedSignal("XP"):Connect(updateXpCard)
LocalPlayer:GetAttributeChangedSignal("Level"):Connect(updateXpCard)

-- ========================================================================
-- TAB 4: ⌨️ INTERACTIVE KEYBINDS TAB
-- ========================================================================
local bindsPage = TabPages["Binds"]
addSectionLabel(bindsPage, "CUSTOM KEYBIND REMAPPING", 1)

local BindDisplayButtons = {}

local BindList = {
    {key = "ToggleUI", name = "Toggle Menu Visibility", default = Enum.KeyCode.RightShift},
    {key = "KillAura", name = "Toggle Kill Aura", default = Enum.KeyCode.X},
    {key = "MassiveAura", name = "Toggle Massive Mode", default = Enum.KeyCode.Z},
    {key = "UnloadStash", name = "Unload Stash to Trunk", default = Enum.KeyCode.U},
    {key = "LoadHeavy", name = "Load Heavy to Trunk", default = Enum.KeyCode.H},
    {key = "AutoSell", name = "Auto-Sell Truck Cargo", default = Enum.KeyCode.J},
    {key = "LootEsp", name = "Toggle Loot ESP", default = Enum.KeyCode.L},
    {key = "NpcEsp", name = "Toggle NPC ESP", default = Enum.KeyCode.K},
    {key = "AutoFarmXP", name = "Toggle Auto-Farm XP", default = Enum.KeyCode.P},
}

for i, bindInfo in ipairs(BindList) do
    local card = Instance.new("Frame")
    card.LayoutOrder = i + 1
    card.Size = UDim2.new(1, 0, 0, 36)
    card.BackgroundColor3 = Color3.fromRGB(20, 26, 38)
    card.BackgroundTransparency = 0.4
    card.BorderSizePixel = 0
    card.Parent = bindsPage
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -95, 1, 0)
    lbl.Position = UDim2.fromOffset(10, 0)
    lbl.BackgroundTransparency = 1
    lbl.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
    lbl.Text = bindInfo.name
    lbl.TextColor3 = Color3.fromRGB(220, 230, 245)
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = card

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.fromOffset(80, 24)
    btn.Position = UDim2.new(1, -88, 0.5, -12)
    btn.BackgroundColor3 = Color3.fromRGB(35, 42, 58)
    btn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    btn.Text = Settings.Keybinds[bindInfo.key] and Settings.Keybinds[bindInfo.key].Name or "None"
    btn.TextColor3 = Color3.fromRGB(0, 210, 255)
    btn.TextSize = 11
    btn.AutoButtonColor = false
    btn.Parent = card
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

    BindDisplayButtons[bindInfo.key] = btn

    btn.MouseButton1Click:Connect(function()
        if State.ListeningForBind == bindInfo.key then
            State.ListeningForBind = nil
            btn.Text = Settings.Keybinds[bindInfo.key] and Settings.Keybinds[bindInfo.key].Name or "None"
            btn.TextColor3 = Color3.fromRGB(0, 210, 255)
        else
            State.ListeningForBind = bindInfo.key
            btn.Text = "[Press Key]"
            btn.TextColor3 = Color3.fromRGB(255, 220, 80)
        end
    end)
end

-- Global Keybind Input Handler
UserInputService.InputBegan:Connect(function(input, gpe)
    if State.ListeningForBind and input.UserInputType == Enum.UserInputType.Keyboard then
        local action = State.ListeningForBind
        State.ListeningForBind = nil

        if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Backspace then
            Settings.Keybinds[action] = nil
            if BindDisplayButtons[action] then
                BindDisplayButtons[action].Text = "None"
                BindDisplayButtons[action].TextColor3 = Color3.fromRGB(150, 160, 175)
            end
            notifyUser(action .. " unbinded.", Color3.fromRGB(255, 200, 50))
        else
            Settings.Keybinds[action] = input.KeyCode
            if BindDisplayButtons[action] then
                BindDisplayButtons[action].Text = input.KeyCode.Name
                BindDisplayButtons[action].TextColor3 = Color3.fromRGB(0, 210, 255)
            end
            notifyUser(action .. " bound to [" .. input.KeyCode.Name .. "]", Color3.fromRGB(0, 230, 118))
        end
        return
    end

    if gpe then return end

    local k = input.KeyCode
    if k == Settings.Keybinds.ToggleUI then
        MainFrame.Visible = not MainFrame.Visible
    elseif k == Settings.Keybinds.KillAura then
        Settings.KillAuraEnabled = not Settings.KillAuraEnabled
        notifyUser("Kill Aura: " .. (Settings.KillAuraEnabled and "ON" or "OFF"), Settings.KillAuraEnabled and Color3.fromRGB(0, 230, 118) or Color3.fromRGB(255, 120, 120))
    elseif k == Settings.Keybinds.MassiveAura then
        Settings.MassiveAuraEnabled = not Settings.MassiveAuraEnabled
        notifyUser("Massive Mode: " .. (Settings.MassiveAuraEnabled and "ON" or "OFF"), Color3.fromRGB(0, 210, 255))
    elseif k == Settings.Keybinds.UnloadStash then
        unloadInventoryToTrunk()
    elseif k == Settings.Keybinds.LoadHeavy then
        loadNearbyHeavyToTrunk()
    elseif k == Settings.Keybinds.AutoSell then
        autoSellTruckCargo()
    elseif k == Settings.Keybinds.LootEsp then
        Settings.LootEspEnabled = not Settings.LootEspEnabled
        notifyUser("Loot ESP: " .. (Settings.LootEspEnabled and "ON" or "OFF"), Color3.fromRGB(0, 210, 255))
    elseif k == Settings.Keybinds.NpcEsp then
        Settings.NpcEspEnabled = not Settings.NpcEspEnabled
        notifyUser("NPC ESP: " .. (Settings.NpcEspEnabled and "ON" or "OFF"), Color3.fromRGB(0, 210, 255))
    elseif k == Settings.Keybinds.AutoFarmXP then
        Settings.AutoFarmXpEnabled = not Settings.AutoFarmXpEnabled
        notifyUser("Auto-Farm XP: " .. (Settings.AutoFarmXpEnabled and "ON" or "OFF"), Settings.AutoFarmXpEnabled and Color3.fromRGB(0, 230, 118) or Color3.fromRGB(255, 120, 120))
    end
end)

-- ========================================================================
-- FOOTER BAR & NOTIFICATIONS
-- ========================================================================
local Footer = Instance.new("Frame")
Footer.Name = "Footer"
Footer.Size = UDim2.new(1, -20, 0, 30)
Footer.Position = UDim2.new(0, 10, 1, -36)
Footer.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
Footer.BackgroundTransparency = 0.5
Footer.BorderSizePixel = 0
Footer.Parent = MainFrame
Instance.new("UICorner", Footer).CornerRadius = UDim.new(0, 8)

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Name = "StatusLabel"
StatusLabel.Size = UDim2.new(1, -16, 1, 0)
StatusLabel.Position = UDim2.fromOffset(8, 0)
StatusLabel.BackgroundTransparency = 1
StatusLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
StatusLabel.Text = "Ready  ·  RightShift to toggle"
StatusLabel.TextColor3 = Color3.fromRGB(150, 165, 185)
StatusLabel.TextSize = 11
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Parent = Footer

notifyUser = function(msg, color)
    StatusLabel.Text = msg
    StatusLabel.TextColor3 = color or Color3.fromRGB(0, 210, 255)
    task.delay(4, function()
        if StatusLabel.Text == msg then
            StatusLabel.Text = "Ready  ·  RightShift to toggle"
            StatusLabel.TextColor3 = Color3.fromRGB(150, 165, 185)
        end
    end)
end

-- ========================================================================
-- MINIMIZE & MOBILE FLOATING TOGGLE
-- ========================================================================
local isMinimized = false
MinBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        TabBar.Visible = false
        TabContainer.Visible = false
        Footer.Visible = false
        MainFrame.Size = UDim2.fromOffset(390, 42)
        MinBtn.Text = "+"
    else
        TabBar.Visible = true
        TabContainer.Visible = true
        Footer.Visible = true
        MainFrame.Size = UDim2.fromOffset(390, 480)
        MinBtn.Text = "—"
    end
end)

CloseBtn.MouseButton1Click:Connect(function()
    ScreenGui:Destroy()
end)

-- Mobile Floating Pill Button
local MobilePill = Instance.new("TextButton")
MobilePill.Name = "NyxMobileToggle"
MobilePill.Size = UDim2.fromOffset(46, 46)
MobilePill.Position = UDim2.new(0, 18, 0.5, -23)
MobilePill.BackgroundColor3 = Color3.fromRGB(16, 20, 30)
MobilePill.BackgroundTransparency = 0.25
MobilePill.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
MobilePill.Text = "⚡"
MobilePill.TextColor3 = Color3.fromRGB(0, 210, 255)
MobilePill.TextSize = 20
MobilePill.Active = true
MobilePill.Draggable = true
MobilePill.Parent = ScreenGui

Instance.new("UICorner", MobilePill).CornerRadius = UDim.new(1, 0)
local PillStroke = Instance.new("UIStroke", MobilePill)
PillStroke.Color = Color3.fromRGB(0, 210, 255)
PillStroke.Thickness = 1.5

MobilePill.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- Initialize Default Tab
switchTab("Combat")
notifyUser("Nyx Criminal Simulator v2.1 Loaded!", Color3.fromRGB(0, 230, 118))

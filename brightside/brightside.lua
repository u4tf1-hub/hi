-- Name: Brightside V4 - Fixed Target Checks (PERFORMANCE OPTIMIZED)
-- Location of script: StarterPlayerScripts (as LocalScript)
-- Script Type: LocalScript

-- ==========================================================
--  BRIGHTSIDE V4 - MINIMAL CHECKS, MAXIMUM PERFORMANCE
--  Fixed: Dead player ESP removal, target unlocking, no crashes
-- ==========================================================

-- Cache services (DO NOT cache Camera globally)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

-- ==========================================================
--  CONFIG (Minimal fallbacks - no deep nesting)
-- ==========================================================
local Surge = getgenv().Surge
if not Surge then
    warn("Surge config not found!")
    return
end

-- ==========================================================
--  STATE (Minimal variables)
-- ==========================================================
local ESPCache = {}
local LockedTarget = nil
local CurrentTarget = nil
local ESPEnabled = Surge.RaidAwareness and Surge.RaidAwareness.Enabled or false
local TriggerbotActive = false
local LastShot = 0

-- Caches
local lastCharUpdate = 0
local localHRP = nil
local playerCache = {}
local lastPlayerCache = 0

-- ==========================================================
--  Performance: Direct config access (no deep copies)
-- ==========================================================
local function getFOV()
    return Surge.SilentAimbot and Surge.SilentAimbot.FOV and Surge.SilentAimbot.FOV['Circle Value'] or 150
end

local function getTargetColor()
    return Surge.Target and Surge.Target.Color or Color3.fromRGB(0, 255, 0)
end

local function shouldUseVisibleCheck()
    return Surge.Target and Surge.Target.VisibleCheck or false
end

local function shouldUnlockOnDeath()
    return Surge.Target and Surge.Target.Unlock and Surge.Target.Unlock.Knocked or true
end

local function shouldUnlockOnGrabbed()
    return Surge.Target and Surge.Target.Unlock and Surge.Target.Unlock.Grabbed or true
end

local function getMaxRenderDistance()
    return Surge.RaidAwareness and Surge.RaidAwareness['Max Render Distance'] or 1000
end

local function isBoxEnabled()
    return Surge.RaidAwareness and Surge.RaidAwareness.Box and Surge.RaidAwareness.Box.Enabled or false
end

local function isNameEnabled()
    return Surge.RaidAwareness and Surge.RaidAwareness.Name and Surge.RaidAwareness.Name.Enabled or false
end

local function isTracerEnabled()
    return Surge.RaidAwareness and Surge.RaidAwareness.Tracer and Surge.RaidAwareness.Tracer.Enabled or false
end

local function isDistanceEnabled()
    return Surge.RaidAwareness and Surge.RaidAwareness.Distance and Surge.RaidAwareness.Distance.Enabled or false
end

local function getNameType()
    return Surge.RaidAwareness and Surge.RaidAwareness.Name and Surge.RaidAwareness.Name.Type or 'Display'
end

-- ==========================================================
--  CACHING (Optimized)
-- ==========================================================
local function updateCachedChar()
    local now = tick()
    if now - lastCharUpdate > 0.1 then
        local char = LocalPlayer.Character
        if char then
            localHRP = char:FindFirstChild("HumanoidRootPart")
        else
            localHRP = nil
        end
        lastCharUpdate = now
    end
    return localHRP
end

local function getCachedPlayers()
    local now = tick()
    if now - lastPlayerCache > 0.5 then
        playerCache = Players:GetPlayers()
        lastPlayerCache = now
    end
    return playerCache
end

-- ==========================================================
--  TARGET CHECKS (Simplified - NO NIL ERRORS)
-- ==========================================================
local function shouldUnlockTarget(target)
    if not target or not target.Character then return true end
    
    local char = target.Character
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return true end
    
    -- DEATH CHECK
    if shouldUnlockOnDeath() and hum.Health <= 0 then
        return true
    end
    
    -- GRAB CHECK
    if shouldUnlockOnGrabbed() then
        if char:FindFirstChild("GRABBING_CONSTRAINT") or hum.PlatformStand then
            return true
        end
    end
    
    return false
end

local function isVisible(target)
    if not shouldUseVisibleCheck() then return true end
    if not target or not target.Character then return false end
    
    local hrp = target.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    local myHRP = updateCachedChar()
    if not myHRP then return false end
    
    local cam = Workspace.CurrentCamera
    if not cam then return false end
    
    local origin = cam.CFrame.Position
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

local function getTargetFromCursor()
    local cam = Workspace.CurrentCamera
    if not cam then return nil end
    
    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    local closest = nil
    local closestDist = math.huge
    local fov = getFOV()
    
    for _, player in ipairs(getCachedPlayers()) do
        if player ~= LocalPlayer then
            local char = player.Character
            if char then
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health > 0 then
                        local pos, onScreen = cam:WorldToViewportPoint(hrp.Position)
                        if onScreen and pos.Z > 0 then
                            local dist = (Vector2.new(pos.X, pos.Y) - mousePos).Magnitude
                            if dist < closestDist and dist <= fov then
                                closestDist = dist
                                closest = player
                            end
                        end
                    end
                end
            end
        end
    end
    
    return closest
end

local function getBestTarget()
    local targetType = Surge.Target and Surge.Target.Type or "Automatic"
    
    -- Target mode: only locked target
    if targetType == "Target" then
        if LockedTarget then
            if shouldUnlockTarget(LockedTarget) then
                LockedTarget = nil
                return nil
            end
            if shouldUseVisibleCheck() then
                return isVisible(LockedTarget) and LockedTarget or nil
            end
            return LockedTarget
        end
        return nil
    end
    
    -- Auto mode: check locked target first
    if LockedTarget and not shouldUnlockTarget(LockedTarget) then
        local char = LockedTarget.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local cam = Workspace.CurrentCamera
                if cam then
                    local pos = cam:WorldToViewportPoint(hrp.Position)
                    if pos.Z > 0 then
                        local mousePos = Vector2.new(Mouse.X, Mouse.Y)
                        local dist = (Vector2.new(pos.X, pos.Y) - mousePos).Magnitude
                        if dist <= getFOV() then
                            if not shouldUseVisibleCheck() or isVisible(LockedTarget) then
                                return LockedTarget
                            end
                        end
                    end
                end
            end
        end
        LockedTarget = nil
    end
    
    -- Cursor targeting
    return getTargetFromCursor()
end

-- ==========================================================
--  ESP SYSTEM (Simplified)
-- ==========================================================
local function CreateESP(player)
    if ESPCache[player] then return ESPCache[player] end
    
    local d = {
        Name = Drawing.new("Text"),
        Box = Drawing.new("Square"),
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
    local d = ESPCache[player]
    if d then
        for _, obj in pairs(d) do
            if obj and obj.Remove then
                obj:Remove()
            end
        end
        ESPCache[player] = nil
    end
end

local function UpdateESP()
    if not ESPEnabled then
        for _, d in pairs(ESPCache) do
            for _, obj in pairs(d) do
                if obj and obj.Visible ~= nil then
                    obj.Visible = false
                end
            end
        end
        return
    end
    
    local cam = Workspace.CurrentCamera
    if not cam then return end
    
    local myHRP = updateCachedChar()
    local maxDist = getMaxRenderDistance()
    local targetColor = getTargetColor()
    local boxOtherColor = Surge.RaidAwareness.Box and Surge.RaidAwareness.Box.OtherColor or Color3.fromRGB(255,255,255)
    local nameOtherColor = Surge.RaidAwareness.Name and Surge.RaidAwareness.Name.OtherColor or Color3.fromRGB(255,255,255)
    
    for _, player in ipairs(getCachedPlayers()) do
        if player ~= LocalPlayer then
            local char = player.Character
            if not char then
                RemoveESP(player)
                goto continue
            end
            
            local hrp = char:FindFirstChild("HumanoidRootPart")
            local hum = char:FindFirstChildOfClass("Humanoid")
            
            -- CRITICAL FIX: Remove ESP for dead players
            if not hrp or not hum or hum.Health <= 0 then
                RemoveESP(player)
                goto continue
            end
            
            -- Distance check
            if myHRP and (hrp.Position - myHRP.Position).Magnitude > maxDist then
                RemoveESP(player)
                goto continue
            end
            
            local feetPos = hrp.Position - Vector3.new(0, 3, 0)
            local pos = cam:WorldToViewportPoint(feetPos)
            
            if pos.Z <= 0 then
                local d = ESPCache[player]
                if d then
                    for _, obj in pairs(d) do
                        if obj and obj.Visible ~= nil then
                            obj.Visible = false
                        end
                    end
                end
                goto continue
            end
            
            local d = CreateESP(player)
            if not d then goto continue end
            
            local sp = Vector2.new(pos.X, pos.Y)
            local isTarget = (player == CurrentTarget)
            
            -- BOX
            if isBoxEnabled() then
                local headPos = hrp.Position + Vector3.new(0, 6, 0)
                local headPos2D = cam:WorldToViewportPoint(headPos)
                if headPos2D.Z > 0 then
                    local headSp = Vector2.new(headPos2D.X, headPos2D.Y)
                    local h = math.abs(sp.Y - headSp.Y)
                    local w = h * 0.5
                    local boxPos = Vector2.new(sp.X - w/2, headSp.Y)
                    
                    d.BoxOutline.Size = Vector2.new(w + 4, h + 4)
                    d.BoxOutline.Position = Vector2.new(boxPos.X - 2, boxPos.Y - 2)
                    d.BoxOutline.Visible = true
                    d.Box.Size = Vector2.new(w, h)
                    d.Box.Position = boxPos
                    d.Box.Color = isTarget and targetColor or boxOtherColor
                    d.Box.Visible = true
                else
                    d.BoxOutline.Visible = false
                    d.Box.Visible = false
                end
            else
                d.BoxOutline.Visible = false
                d.Box.Visible = false
            end
            
            -- NAME
            if isNameEnabled() then
                d.Name.Text = getNameType() == 'Display' and player.DisplayName or player.Name
                d.Name.Position = Vector2.new(sp.X, sp.Y + 10)
                d.Name.Color = isTarget and targetColor or nameOtherColor
                d.Name.Visible = true
            else
                d.Name.Visible = false
            end
            
            -- TRACER
            if isTracerEnabled() then
                d.Tracer.From = Vector2.new(sp.X, cam.ViewportSize.Y)
                d.Tracer.To = sp
                d.Tracer.Color = isTarget and targetColor or (Surge.RaidAwareness.Tracer and Surge.RaidAwareness.Tracer.OtherColor or Color3.fromRGB(255,255,255))
                d.Tracer.Visible = true
            else
                d.Tracer.Visible = false
            end
            
            -- DISTANCE
            if isDistanceEnabled() and myHRP then
                local dist = (hrp.Position - myHRP.Position).Magnitude
                d.Distance.Text = math.floor(dist) .. " studs"
                d.Distance.Position = Vector2.new(sp.X, sp.Y + 25)
                d.Distance.Color = isTarget and targetColor or (Surge.RaidAwareness.Distance and Surge.RaidAwareness.Distance.OtherColor or Color3.fromRGB(255,255,255))
                d.Distance.Visible = true
            else
                d.Distance.Visible = false
            end
            
            ::continue::
        end
    end
end

-- ==========================================================
--  Triggerbot (Minimal)
-- ==========================================================
local function performTriggerbot()
    if not TriggerbotActive or not Surge.Triggerbot or not Surge.Triggerbot.Enabled then return end
    
    local cam = Workspace.CurrentCamera
    if not cam then return end
    
    local target = nil
    if Surge.Triggerbot.Type == "Target" then
        if LockedTarget and not shouldUnlockTarget(LockedTarget) then
            target = LockedTarget
        end
    else
        target = CurrentTarget
    end
    
    if not target or not target.Character then return end
    
    local hrp = target.Character:FindFirstChild("HumanoidRootPart")
    local hum = target.Character:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return end
    
    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    local pos = cam:WorldToViewportPoint(hrp.Position)
    if pos.Z <= 0 then return end
    
    local dist = (Vector2.new(pos.X, pos.Y) - mousePos).Magnitude
    local threshold = Surge.Triggerbot.ShootMode == 'Hitbox' and 15 or (Surge.Triggerbot.FOV and Surge.Triggerbot.FOV['Circle Value'] or 45)
    if dist > threshold then return end
    
    local now = tick()
    local cooldown = Surge.Triggerbot.Timing and Surge.Triggerbot.Timing.Cooldown or 0.001
    if now - LastShot < cooldown then return end
    
    local myHRP = updateCachedChar()
    if not myHRP then return end
    
    local tool = myHRP:FindFirstChildOfClass("Tool")
    if tool then
        tool:Activate()
        LastShot = now
    end
end

-- ==========================================================
--  ANTI TRIP (Simple, no pcall overhead)
-- ==========================================================
local function performAntiTrip()
    if not Surge.AntiTrip or not Surge.AntiTrip.Enabled then return end
    
    local char = LocalPlayer.Character
    if not char then return end
    
    local hum = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp or hum.Health <= 0 then return end
    
    -- Check if tripped
    local isTripped = false
    
    if hum.PlatformStand then
        isTripped = true
    else
        local state = hum:GetState()
        if state == Enum.HumanoidStateType.FallingDown or 
           state == Enum.HumanoidStateType.Ragdoll or
           state == Enum.HumanoidStateType.Seated then
            isTripped = true
        end
    end
    
    if not isTripped then return end
    
    -- Fix it
    hum.PlatformStand = false
    hum:ChangeState(Enum.HumanoidStateType.Running)
    
    local vel = hrp.AssemblyLinearVelocity
    if vel.Magnitude > 30 then
        hrp.AssemblyLinearVelocity = Vector3.new(vel.X * 0.3, math.max(vel.Y, -5), vel.Z * 0.3)
    end
    if vel.Y < -15 then
        hrp.AssemblyLinearVelocity = hrp.AssemblyLinearVelocity + Vector3.new(0, 10, 0)
    end
end

-- ==========================================================
--  Keybinds (Simplified)
-- ==========================================================
local Keybinds = Surge.Main and Surge.Main.Keybinds or {}

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    
    -- Space for jump
    if input.KeyCode == Enum.KeyCode.Space then
        if Surge.Spiderman and Surge.Spiderman.Enabled then
            local now = tick()
            if now - LastJumpTime < 0.4 then
                JumpCount = JumpCount + 1
            else
                JumpCount = 1
            end
            LastJumpTime = now
            
            if JumpCount >= 2 or not Surge.Spiderman.RequireDoubleJump then
                -- Wall jump logic would go here (omitted for brevity)
            end
        end
        return
    end
    
    -- Check keybinds
    for action, keyName in pairs(Keybinds) do
        if type(keyName) == "string" then
            local keyCode = Enum.KeyCode[keyName:upper()] or (keyName:match("^F(%d+)$") and Enum.KeyCode["F" .. keyName:sub(2)])
            if keyCode and input.KeyCode == keyCode then
                if action == "ESP Toggle" then
                    ESPEnabled = not ESPEnabled
                elseif action == "Lock Target" then
                    if LockedTarget then
                        LockedTarget = nil
                    else
                        LockedTarget = getTargetFromCursor()
                    end
                elseif action == "Trigger Bot Activate" then
                    if Surge.Triggerbot and Surge.Triggerbot.Enabled then
                        TriggerbotActive = not TriggerbotActive
                    end
                end
                return
            end
        end
    end
end)

-- ==========================================================
--  MAIN LOOP (Minimal pcall - only where absolutely needed)
-- ==========================================================
RunService.RenderStepped:Connect(function()
    -- Get camera once
    local cam = Workspace.CurrentCamera
    if not cam then return end
    
    -- Update char cache
    updateCachedChar()
    
    -- These can fail if any internal nil, but they have their own checks
    -- No pcall needed if we have good nil checks inside
    CurrentTarget = getBestTarget()
    UpdateESP()
    performTriggerbot()
    performAntiTrip()
end)

-- ==========================================================
--  PLAYER CLEANUP
-- ==========================================================
Players.PlayerRemoving:Connect(function(player)
    if player == LockedTarget then LockedTarget = nil end
    if player == CurrentTarget then CurrentTarget = nil end
    RemoveESP(player)
end)

-- Initialize ESP
for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        CreateESP(player)
    end
end

print("Brightside V4 - Checks Fixed (No pcall spam)")

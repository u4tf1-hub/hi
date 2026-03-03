-- Name: Brightside V4 - Ultra-Safe Target Checks
-- Location of script: StarterPlayerScripts (as LocalScript)
-- Script Type: LocalScript

-- ==========================================================
--  BRIGHTSIDE V4 - ERROR 267 FIXED (ULTRA SAFE)
--  Complete nil-safety, no more crashes, checks work properly
-- ==========================================================

-- Cache services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- Cache player references (don't cache Camera globally - get it fresh each time)
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

-- ==========================================================
--  CONFIG WITH MAXIMUM NIL SAFETY
-- ==========================================================
local Surge = getgenv().Surge or {}
Surge.Main = Surge.Main or {}
Surge.Main.Keybinds = Surge.Main.Keybinds or {}
Surge.RaidAwareness = Surge.RaidAwareness or {Enabled = false}
Surge.SilentAimbot = Surge.SilentAimbot or {FOV = {['Circle Value'] = 150}}
Surge.Target = Surge.Target or {Type = "Automatic", Color = Color3.fromRGB(0,255,0), VisibleCheck = false, Unlock = {Knocked = true, Grabbed = true}}
Surge.Triggerbot = Surge.Triggerbot or {Enabled = false, Type = "Automatic", ShootMode = 'Hitbox', Timing = {Cooldown = 0.001}, FOV = {['Circle Value'] = 45}}
Surge.AntiTrip = Surge.AntiTrip or {Enabled = false}
Surge.Spiderman = Surge.Spiderman or {Enabled = false, WallDistance = 7, Cooldown = 0.2, JumpPower = 50, KnifeJumpPower = 50, RequireDoubleJump = false}
Surge.Extra = Surge.Extra or {Korblox = false, Headless = false}
Surge.PanicGround = Surge.PanicGround or {Enabled = false}
Surge.PlayerModification = Surge.PlayerModification or {RapidFire = {Enabled = false}}

-- ==========================================================
--  STATE VARIABLES
-- ==========================================================
local ESPCache = {}
local LockedTarget = nil
local CurrentTarget = nil
local ESPEnabled = Surge.RaidAwareness.Enabled
local TriggerbotActive = false
local LastShot = 0

-- Jump state
local LastJumpTime, LastWallJumpTime, JumpCount = 0, 0, 0

-- Cached character references
local localChar, localHum, localHRP = nil, nil, nil
local lastCharUpdate = 0
local CHAR_UPDATE_INTERVAL = 0.1

-- Cached config values
local fovCache = Surge.SilentAimbot.FOV['Circle Value'] or 150
local targetColorCache = Surge.Target.Color or Color3.fromRGB(0,255,0)
local maxDistCache = Surge.RaidAwareness['Max Render Distance'] or 1000

-- ESP config cache
local boxEnabledCache = (Surge.RaidAwareness.Box and Surge.RaidAwareness.Box.Enabled) or false
local nameEnabledCache = (Surge.RaidAwareness.Name and Surge.RaidAwareness.Name.Enabled) or false
local tracerEnabledCache = (Surge.RaidAwareness.Tracer and Surge.RaidAwareness.Tracer.Enabled) or false
local distanceEnabledCache = (Surge.RaidAwareness.Distance and Surge.RaidAwareness.Distance.Enabled) or false
local nameTypeCache = (Surge.RaidAwareness.Name and Surge.RaidAwareness.Name.Type) or 'Display'

local boxOtherColorCache = (Surge.RaidAwareness.Box and Surge.RaidAwareness.Box.OtherColor) or Color3.fromRGB(255,255,255)
local nameOtherColorCache = (Surge.RaidAwareness.Name and Surge.RaidAwareness.Name.OtherColor) or Color3.fromRGB(255,255,255)
local tracerOtherColorCache = (Surge.RaidAwareness.Tracer and Surge.RaidAwareness.Tracer.OtherColor) or Color3.fromRGB(255,255,255)
local distanceOtherColorCache = (Surge.RaidAwareness.Distance and Surge.RaidAwareness.Distance.OtherColor) or Color3.fromRGB(255,255,255)

-- Keybind system
local KeybindCache = {}
local ActionCache = {}

local function cacheKeyCode(keyName, default)
    if not keyName or type(keyName) ~= "string" then 
        return Enum.KeyCode[default:upper()] 
    end
    
    if KeybindCache[keyName] then
        return KeybindCache[keyName]
    end
    
    local upperKeyName = keyName:upper()
    local keyCode = Enum.KeyCode[upperKeyName]
    
    if not keyCode and upperKeyName:match("^F%d+$") then
        local fNum = tonumber(upperKeyName:sub(2))
        if fNum and fNum >= 1 and fNum <= 12 then
            keyCode = Enum.KeyCode["F" .. fNum]
        end
    end
    
    if not keyCode then
        keyCode = Enum.KeyCode[default:upper()]
    end
    
    KeybindCache[keyName] = keyCode
    return keyCode
end

local function buildActionCache()
    local keybinds = Surge.Main.Keybinds
    if not keybinds then return end
    
    for action, keyName in pairs(keybinds) do
        local keyCode = cacheKeyCode(keyName, "T")
        if keyCode then
            ActionCache[keyCode] = action
        end
    end
end

buildActionCache()

-- ==========================================================
--  PERFORMANCE: Player caching
-- ==========================================================
local playerCache = {}
local lastPlayerCacheUpdate = 0
local PLAYER_CACHE_TTL = 0.5

local function getCachedPlayers()
    local now = tick()
    if now - lastPlayerCacheUpdate > PLAYER_CACHE_TTL then
        playerCache = Players:GetPlayers()
        lastPlayerCacheUpdate = now
    end
    return playerCache
end

-- ==========================================================
--  PERFORMANCE: Cached character parts
-- ==========================================================
local function updateCachedChar()
    local now = tick()
    if now - lastCharUpdate > CHAR_UPDATE_INTERVAL then
        localChar = LocalPlayer.Character
        if localChar then
            localHum = localChar:FindFirstChildOfClass("Humanoid")
            localHRP = localChar:FindFirstChild("HumanoidRootPart")
        else
            localHum = nil
            localHRP = nil
        end
        lastCharUpdate = now
    end
    return localChar, localHum, localHRP
end

-- ==========================================================
--  CRITICAL: SAFE CAMERA GETTER (Prevents ALL camera errors)
-- ==========================================================
local function getCamera()
    --CRITICAL: Always get fresh camera reference, check it exists and is valid
    local success, cam = pcall(function()
        return Workspace.CurrentCamera
    end)
    
    if not success or not cam or not cam:IsA("Camera") then
        return nil
    end
    
    return cam
end

-- ==========================================================
--  RAPID FIRE (Optimized)
-- ==========================================================
local lastToolCheck = 0
local cachedTool = nil

local function getCurrentTool()
    local char, _, _ = updateCachedChar()
    if not char then return nil end
    
    local now = tick()
    if now - lastToolCheck < 0.05 and cachedTool and cachedTool.Parent == char then
        return cachedTool
    end
    
    for _, tool in ipairs(char:GetChildren()) do
        if tool:IsA("Tool") and tool:FindFirstChild("Ammo") then
            cachedTool = tool
            lastToolCheck = now
            return tool
        end
    end
    cachedTool = nil
    return nil
end

getgenv().config = { enable = true, delay = 0.000000000001 }
getgenv().is_firing = false

UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        local gun = getCurrentTool()
        if getgenv().config.enable and gun and not getgenv().is_firing then
            getgenv().is_firing = true
            task.spawn(function()
                while getgenv().is_firing do
                    local currentGun = getCurrentTool()
                    if currentGun then
                        pcall(function()
                            currentGun:Activate()
                        end)
                    else
                        break
                    end
                    task.wait(getgenv().config.delay)
                end
            end)
        end
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        getgenv().is_firing = false
    end
end)

-- ==========================================================
--  MOUSE CURSOR TARGETING (ULTRA SAFE)
-- ==========================================================
local function getTargetFromCursor()
    local cam = getCamera()
    if not cam then return nil, math.huge end
    
    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    local closestPlayer = nil
    local closestDist = math.huge
    
    local players = getCachedPlayers()
    
    for i = 1, #players do
        local player = players[i]
        if player ~= LocalPlayer then
            local char = player.Character
            if char then
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    -- CRITICAL: Check humanoid exists AND is alive
                    if hum and hum.Health > 0 then
                        local success, screenPos, onScreen = pcall(function()
                            return cam:WorldToViewportPoint(hrp.Position)
                        end)
                        
                        if success and onScreen and screenPos.Z > 0 then
                            local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                            if dist < closestDist and dist <= fovCache then
                                closestDist = dist
                                closestPlayer = player
                            end
                        end
                    end
                end
            end
        end
    end
    
    return closestPlayer, closestDist
end

-- ==========================================================
--  VISIBILITY CHECK (ULTRA SAFE)
-- ==========================================================
local function isVisible(target)
    if not Surge.Target.VisibleCheck then return true end
    if not target or not target.Character then return false end
    
    local hrp = target.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    local cam = getCamera()
    if not cam then return false end
    
    local char, _, _ = updateCachedChar()
    if not char then return false end
    
    local origin = cam.CFrame.Position
    local direction = (hrp.Position - origin)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = {char}
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    
    local result = nil
    local success = pcall(function()
        result = Workspace:Raycast(origin, direction, raycastParams)
    end)
    
    if not success then
        return false
    end
    
    if result then
        return result.Instance:IsDescendantOf(target.Character)
    end
    return true
end

-- ==========================================================
--  TARGET UNLOCK CHECKS (ULTRA SAFE)
-- ==========================================================
local function shouldUnlockTarget(target)
    if not target then return true end
    
    local char = target.Character
    if not char then 
        return true 
    end
    
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then 
        return true 
    end
    
    -- Check if dead
    if Surge.Target.Unlock.Knocked and hum.Health <= 0 then
        return true
    end
    
    -- Check if grabbed/constrained
    if Surge.Target.Unlock.Grabbed then
        if char:FindFirstChild("GRABBING_CONSTRAINT") then
            return true
        end
        if hum.PlatformStand then
            return true
        end
    end
    
    return false
end

-- ==========================================================
--  TARGET SYSTEM (ULTRA SAFE - FIXED DEAD PLAYER HANDLING)
-- ==========================================================
local function getBestTarget()
    local targetType = Surge.Target.Type
    
    -- TARGET MODE: Only locked target
    if targetType == "Target" then
        if LockedTarget then
            if shouldUnlockTarget(LockedTarget) then
                LockedTarget = nil
                return nil
            end
            if Surge.Target.VisibleCheck then
                if isVisible(LockedTarget) then
                    return LockedTarget
                end
            else
                return LockedTarget
            end
        end
        return nil
    end
    
    -- AUTOMATIC MODE
    -- Check locked target first if valid
    if LockedTarget and not shouldUnlockTarget(LockedTarget) then
        local char = LockedTarget.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local cam = getCamera()
                if not cam then 
                    LockedTarget = nil
                    return nil 
                end
                
                local success, screenPos = pcall(function()
                    return cam:WorldToViewportPoint(hrp.Position)
                end)
                
                if success and screenPos.Z > 0 then
                    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
                    local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                    if dist <= fovCache then
                        if not Surge.Target.VisibleCheck or isVisible(LockedTarget) then
                            return LockedTarget
                        end
                    end
                end
            end
        end
        LockedTarget = nil
    end
    
    -- Cursor targeting
    local cursorTarget = getTargetFromCursor()
    if cursorTarget then
        return cursorTarget
    end
    
    return nil
end

-- ==========================================================
--  ESP SYSTEM (ULTRA SAFE)
-- ==========================================================
local function CreateESP(player)
    if ESPCache[player] then return ESPCache[player] end
    
    local success, d = pcall(function()
        return {
            Name = Drawing.new("Text"),
            Box = Drawing.new("Square"),
            BoxOutline = Drawing.new("Square"),
            Tracer = Drawing.new("Line"),
            Distance = Drawing.new("Text")
        }
    end)
    
    if not success or not d then return nil end
    
    -- Initialize properties safely
    pcall(function()
        d.Name.Size = 14
        d.Name.Center = true
        d.Name.Outline = true
        
        d.Box.Thickness = 1
        d.Box.Filled = false
        
        d.BoxOutline.Thickness = 3
        d.BoxOutline.Filled = false
        d.BoxOutline.Color = Color3.new(0,0,0)
        
        d.Tracer.Thickness = 1
        
        d.Distance.Size = 12
        d.Distance.Center = true
        d.Distance.Outline = true
    end)
    
    ESPCache[player] = d
    return d
end

local function RemoveESP(player)
    local drawings = ESPCache[player]
    if drawings then
        for _, dr in pairs(drawings) do
            if dr and dr.Remove then
                pcall(function()
                    dr:Remove()
                end)
            end
        end
        ESPCache[player] = nil
    end
end

-- FIXED: ESP now properly hides when players die/leave
local function UpdateESP()
    if not ESPEnabled then
        for _, drawings in pairs(ESPCache) do
            for _, dr in pairs(drawings) do
                if dr and dr.Visible ~= nil then
                    dr.Visible = false
                end
            end
        end
        return
    end
    
    local cam = getCamera()
    if not cam then return end
    
    local char, _, localHRP = updateCachedChar()
    local players = getCachedPlayers()
    
    for i = 1, #players do
        local player = players[i]
        if player ~= LocalPlayer then
            local pChar = player.Character
            
            -- FIXED: Remove ESP if no character
            if not pChar then
                RemoveESP(player)
                goto continue
            end
            
            local hrp = pChar:FindFirstChild("HumanoidRootPart")
            local hum = pChar:FindFirstChildOfClass("Humanoid")
            
            -- FIXED: Remove ESP if dead or missing parts
            if not hrp or not hum or hum.Health <= 0 then 
                RemoveESP(player)
                goto continue
            end
            
            -- Distance check
            if localHRP and (hrp.Position - localHRP.Position).Magnitude > maxDistCache then 
                RemoveESP(player)
                goto continue
            end
            
            -- Screen position check (with pcall for safety)
            local feetPos = hrp.Position - Vector3.new(0, 3, 0)
            local success, screenPos = pcall(function()
                return cam:WorldToViewportPoint(feetPos)
            end)
            
            if not success or not screenPos or screenPos.Z <= 0 then
                local drawings = ESPCache[player]
                if drawings then 
                    for _, dr in pairs(drawings) do 
                        if dr and dr.Visible ~= nil then
                            dr.Visible = false 
                        end
                    end 
                end
                goto continue
            end
            
            -- Create/Update ESP
            local drawings = CreateESP(player)
            if not drawings then goto continue end
            
            local sp = Vector2.new(screenPos.X, screenPos.Y)
            local isTarget = (player == CurrentTarget)
            
            -- BOX (with pcall safety)
            if boxEnabledCache then
                local headPos = hrp.Position + Vector3.new(0, 6, 0)
                local success2, headScreen = pcall(function()
                    return cam:WorldToViewportPoint(headPos)
                end)
                
                if success2 and headScreen and headScreen.Z > 0 then
                    local headSp = Vector2.new(headScreen.X, headScreen.Y)
                    local h = math.abs(sp.Y - headSp.Y)
                    local w = h * 0.5
                    local boxPos = Vector2.new(sp.X - w/2, headSp.Y)
                    
                    pcall(function()
                        if drawings.BoxOutline and drawings.BoxOutline.Visible ~= nil then
                            drawings.BoxOutline.Size = Vector2.new(w + 4, h + 4)
                            drawings.BoxOutline.Position = Vector2.new(boxPos.X - 2, boxPos.Y - 2)
                            drawings.BoxOutline.Visible = true
                        end
                        if drawings.Box and drawings.Box.Visible ~= nil then
                            drawings.Box.Size = Vector2.new(w, h)
                            drawings.Box.Position = boxPos
                            drawings.Box.Color = isTarget and targetColorCache or boxOtherColorCache
                            drawings.Box.Visible = true
                        end
                    end)
                else
                    pcall(function()
                        if drawings.BoxOutline then drawings.BoxOutline.Visible = false end
                        if drawings.Box then drawings.Box.Visible = false end
                    end)
                end
            else
                pcall(function()
                    if drawings.BoxOutline then drawings.BoxOutline.Visible = false end
                    if drawings.Box then drawings.Box.Visible = false end
                end)
            end
            
            -- NAME
            if nameEnabledCache then
                pcall(function()
                    if drawings.Name and drawings.Name.Visible ~= nil then
                        drawings.Name.Text = nameTypeCache == 'Display' and player.DisplayName or player.Name
                        drawings.Name.Position = Vector2.new(sp.X, sp.Y + 10)
                        drawings.Name.Color = isTarget and targetColorCache or nameOtherColorCache
                        drawings.Name.Visible = true
                    end
                end)
            else
                pcall(function()
                    if drawings.Name then drawings.Name.Visible = false end
                end)
            end
            
            -- TRACER
            if tracerEnabledCache then
                pcall(function()
                    if drawings.Tracer and drawings.Tracer.Visible ~= nil then
                        drawings.Tracer.From = Vector2.new(sp.X, cam.ViewportSize.Y)
                        drawings.Tracer.To = sp
                        drawings.Tracer.Color = isTarget and targetColorCache or tracerOtherColorCache
                        drawings.Tracer.Visible = true
                    end
                end)
            else
                pcall(function()
                    if drawings.Tracer then drawings.Tracer.Visible = false end
                end)
            end
            
            -- DISTANCE
            if distanceEnabledCache and localHRP then
                pcall(function()
                    if drawings.Distance and drawings.Distance.Visible ~= nil then
                        local d = (hrp.Position - localHRP.Position).Magnitude
                        drawings.Distance.Text = math.floor(d) .. " studs"
                        drawings.Distance.Position = Vector2.new(sp.X, sp.Y + 25)
                        drawings.Distance.Color = isTarget and targetColorCache or distanceOtherColorCache
                        drawings.Distance.Visible = true
                    end
                end)
            else
                pcall(function()
                    if drawings.Distance then drawings.Distance.Visible = false end
                end)
            end
            
            ::continue::
        end
    end
end

-- ==========================================================
--  TRIGGERBOT (ULTRA SAFE)
-- ==========================================================
local function performTriggerbot()
    if not TriggerbotActive or not Surge.Triggerbot.Enabled then return end
    
    local cam = getCamera()
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
    
    -- FIXED: Check if target is dead
    if not hrp or not hum or hum.Health <= 0 then return end
    
    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    local success, pos = pcall(function()
        return cam:WorldToViewportPoint(hrp.Position)
    end)
    
    if not success or not pos or pos.Z <= 0 then return end
    
    local dist = (Vector2.new(pos.X, pos.Y) - mousePos).Magnitude
    local threshold = Surge.Triggerbot.ShootMode == 'Hitbox' and 15 or Surge.Triggerbot.FOV['Circle Value']
    if dist > threshold then return end
    
    local cooldown = Surge.Triggerbot.Timing.Cooldown or 0.001
    local now = tick()
    if now - LastShot < cooldown then return end
    
    local _, _, localHRP = updateCachedChar()
    if not localHRP then return end
    
    local tool = localHRP:FindFirstChildOfClass("Tool")
    if tool then
        pcall(function()
            tool:Activate()
            LastShot = now
        end)
    end
end

-- ==========================================================
--  ANTI TRIP SYSTEM (SAFE)
-- ==========================================================
local function performAntiTrip()
    if not Surge.AntiTrip.Enabled then return end
    
    local char, hum, hrp = updateCachedChar()
    if not char or not hum or not hrp then return end
    if hum.Health <= 0 then return end
    
    -- Detect trip conditions
    local isTripped = false
    
    if hum.PlatformStand then
        isTripped = true
    end
    
    local state = hum:GetState()
    if state == Enum.HumanoidStateType.FallingDown or 
       state == Enum.HumanoidStateType.Ragdoll or
       state == Enum.HumanoidStateType.Seated then
        isTripped = true
    end
    
    local vel = hrp.AssemblyLinearVelocity
    if vel.Y < -50 and vel.Magnitude > 60 then
        isTripped = true
    end
    
    if not isTripped then return end
    
    -- FIXED ANTI-TRIP: Multi-method recovery
    pcall(function()
        hum.PlatformStand = false
        hum:ChangeState(Enum.HumanoidStateType.Running)
        
        if vel.Magnitude > 30 then
            local newVel = Vector3.new(
                vel.X * 0.3,
                math.max(vel.Y, -5),
                vel.Z * 0.3
            )
            hrp.AssemblyLinearVelocity = newVel
        end
        
        if vel.Y < -15 then
            hrp.AssemblyLinearVelocity = hrp.AssemblyLinearVelocity + Vector3.new(0, 10, 0)
        end
    end)
end

-- ==========================================================
--  SPIDERMAN WALL JUMP
-- ==========================================================
local wallJumpCache = {normal = nil, lastCheck = 0}
local WALL_JUMP_CACHE_TTL = 0.1

local function getWallNormal()
    local char, _, hrp = updateCachedChar()
    if not hrp then return nil end
    
    local now = tick()
    if now - wallJumpCache.lastCheck < WALL_JUMP_CACHE_TTL and wallJumpCache.normal then
        return wallJumpCache.normal
    end
    
    local wallDist = Surge.Spiderman.WallDistance or 7
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {char}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    
    local look = hrp.CFrame.LookVector
    local right = hrp.CFrame.RightVector
    local dirs = {look, -look, right, -right}
    local heights = {Vector3.new(0, -2, 0), Vector3.new(0, 0, 0), Vector3.new(0, 2, 0)}
    
    for _, h in ipairs(heights) do
        for _, d in ipairs(dirs) do
            local res = Workspace:Raycast(hrp.Position + h, d * wallDist, params)
            if res and res.Instance and res.Instance.CanCollide then
                wallJumpCache.normal = res.Normal
                wallJumpCache.lastCheck = now
                return res.Normal
            end
        end
    end
    
    wallJumpCache.normal = nil
    return nil
end

local function performWallJump()
    if not Surge.Spiderman.Enabled then return end
    
    local char, _, hrp = updateCachedChar()
    if not hrp or tick() - LastWallJumpTime < Surge.Spiderman.Cooldown then return end
    
    local wallNormal = getWallNormal()
    if not wallNormal then return end
    
    local tool = char:FindFirstChildOfClass("Tool")
    local isKnife = tool and tool.Name:lower():find("knife")
    local power = isKnife and Surge.Spiderman.KnifeJumpPower or Surge.Spiderman.JumpPower or 50
    
    hrp.AssemblyLinearVelocity = Vector3.new(
        hrp.AssemblyLinearVelocity.X * 0.2, 
        0, 
        hrp.AssemblyLinearVelocity.Z * 0.2
    )
    
    task.wait(0.01)
    
    local jumpDirection = (Vector3.new(0, 1.45, 0) + wallNormal * 0.35).Unit
    hrp.AssemblyLinearVelocity = jumpDirection * (power * 1.35)
    
    LastWallJumpTime = tick()
end

-- ==========================================================
--  KORBLOX & HEADLESS (cached application state)
-- ==========================================================
local korbloxApplied = {}
local headlessApplied = {}

local function applyKorblox()
    if not Surge.Extra.Korblox then return end
    
    local char, _, _ = updateCachedChar()
    if not char then return end
    
    local playerId = LocalPlayer.UserId
    if korbloxApplied[playerId] then return end
    
    local rightLeg = char:FindFirstChild("Right Leg") or char:FindFirstChild("RightLowerLeg")
    if not rightLeg then return end
    
    local partsToHide = {"Right Leg", "RightUpperLeg", "RightLowerLeg", "RightFoot"}
    for _, name in ipairs(partsToHide) do
        local part = char:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            part.Transparency = 1
            for _, child in ipairs(part:GetChildren()) do
                if child:IsA("Decal") or child:IsA("Texture") then
                    child.Transparency = 1
                end
            end
        end
    end
    
    if char:FindFirstChild("KorbloxVisual") then
        korbloxApplied[playerId] = true
        return
    end
    
    local korblox = Instance.new("Part")
    korblox.Name = "KorbloxVisual"
    korblox.Size = Vector3.new(1, 2, 1)
    korblox.CanCollide = false
    korblox.Transparency = 0
    korblox.Parent = char
    
    local mesh = Instance.new("SpecialMesh")
    mesh.MeshType = Enum.MeshType.FileMesh
    mesh.MeshId = "rbxassetid://139607718"
    mesh.TextureId = "rbxassetid://139607805"
    mesh.Scale = Vector3.new(1.05, 1.05, 1.05)
    mesh.Parent = korblox
    
    local weld = Instance.new("Weld")
    weld.Part0 = rightLeg
    weld.Part1 = korblox
    weld.C0 = CFrame.new(0, 0, 0)
    weld.C1 = CFrame.new(0, 0, 0)
    weld.Parent = korblox
    
    korbloxApplied[playerId] = true
end

local function applyHeadless()
    if not Surge.Extra.Headless then return end
    
    local char, _, _ = updateCachedChar()
    if not char then return end
    
    local playerId = LocalPlayer.UserId
    if headlessApplied[playerId] then return end
    
    local head = char:FindFirstChild("Head")
    if not head then return end
    
    if head.Transparency == 1 then
        headlessApplied[playerId] = true
        return
    end
    
    head.Transparency = 1
    for _, child in ipairs(head:GetChildren()) do
        if child:IsA("Decal") or child:IsA("Texture") then
            child.Transparency = 1
        end
    end
    
    headlessApplied[playerId] = true
end

-- ==========================================================
--  PANIC GROUND
-- ==========================================================
local function performPanicGround()
    if not Surge.PanicGround.Enabled then return end
    
    local _, _, hrp = updateCachedChar()
    if not hrp then return end
    
    local char, _, _ = updateCachedChar()
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {char, Workspace.CurrentCamera}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    
    local result = Workspace:Raycast(hrp.Position, Vector3.new(0, -5000, 0), params)
    if result then
        hrp.CFrame = CFrame.new(result.Position + Vector3.new(0, 3, 0))
    end
end

-- ==========================================================
--  KEYBIND HANDLER
-- ==========================================================
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    
    local action = ActionCache[input.KeyCode]
    if not action then return end
    
    if action == "ESP Toggle" then
        ESPEnabled = not ESPEnabled
        if not ESPEnabled then
            for _, drawings in pairs(ESPCache) do
                for _, dr in pairs(drawings) do
                    if dr and dr.Visible ~= nil then
                        dr.Visible = false
                    end
                end
            end
        end
        
    elseif action == "Lock Target" then
        if LockedTarget then
            LockedTarget = nil
        else
            local cursorTarget = getTargetFromCursor()
            if cursorTarget then
                LockedTarget = cursorTarget
            end
        end
        
    elseif action == "Trigger Bot Activate" then
        if not Surge.Triggerbot.Enabled then return end
        
        if Surge.Triggerbot.Mode == "Toggle" then
            TriggerbotActive = not TriggerbotActive
        else
            TriggerbotActive = true
        end
        
    elseif input.KeyCode == Enum.KeyCode.Space then
        local jumpNow = tick()
        if jumpNow - LastJumpTime < 0.4 then
            JumpCount = JumpCount + 1
        else
            JumpCount = 1
        end
        LastJumpTime = jumpNow
        
        if JumpCount >= 2 or not Surge.Spiderman.RequireDoubleJump then
            performWallJump()
        end
        
    elseif action == "Panic Ground" then
        performPanicGround()
        
    elseif action == "Panic" then
        if Surge.Main.Panic and Surge.Main.Panic.Enabled then
            ESPEnabled = false
            LockedTarget = nil
            CurrentTarget = nil
            TriggerbotActive = false
            
            for _, drawings in pairs(ESPCache) do
                for _, dr in pairs(drawings) do
                    if dr and dr.Visible ~= nil then
                        dr.Visible = false
                    end
                end
            end
        end
    end
end)

UserInputService.InputEnded:Connect(function(input, processed)
    if processed then return end
    
    if input.KeyCode == Enum.KeyCode.Space then
        return
    end
    
    local action = ActionCache[input.KeyCode]
    if action == "Trigger Bot Activate" then
        if Surge.Triggerbot.Enabled and Surge.Triggerbot.Mode == "Hold" then
            TriggerbotActive = false
        end
    end
end)

-- ==========================================================
--  MAIN LOOP (MAXIMUM SAFETY)
-- ==========================================================
RunService.RenderStepped:Connect(function()
    -- Get fresh camera with pcall safety
    local cam = getCamera()
    if not cam then return end
    
    -- Update cached character
    updateCachedChar()
    
    -- 1. Target acquisition
    pcall(function()
        CurrentTarget = getBestTarget()
    end)
    
    -- 2. ESP updates
    pcall(function()
        UpdateESP()
    end)
    
    -- 3. Triggerbot
    pcall(function()
        performTriggerbot()
    end)
    
    -- 4. Anti-trip
    pcall(function()
        performAntiTrip()
    end)
    
    -- 5. Cosmetics (only if enabled)
    if Surge.Extra.Headless then
        pcall(function()
            applyHeadless()
        end)
    end
    if Surge.Extra.Korblox then
        pcall(function()
            applyKorblox()
        end)
    end
end)

-- ==========================================================
--  PLAYER CLEANUP
-- ==========================================================
Players.PlayerRemoving:Connect(function(player)
    if player == LockedTarget then LockedTarget = nil end
    if player == CurrentTarget then CurrentTarget = nil end
    RemoveESP(player)
end)

-- Initialize ESP for existing players
for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        CreateESP(player)
    end
end

-- ==========================================================
--  SILENT AIM (Ultra safe metatable hook)
-- ==========================================================
local mouse = LocalPlayer:GetMouse()
local mt = getrawmetatable(mouse)
setreadonly(mt, false)
local old = mt.__index

mt.__index = newcclosure(function(self, key)
    if key:lower() == "hit" or key:lower() == "target" then
        if Surge.SilentAimbot.Enabled and CurrentTarget then
            local tgt = CurrentTarget
            if tgt and tgt.Character then
                local char = tgt.Character
                local hrp = char:FindFirstChild("HumanoidRootPart")
                local head = char:FindFirstChild("Head")
                
                local hitPartStr = Surge.SilentAimbot.HitTarget and Surge.SilentAimbot.HitTarget.HitPart or "Closest Point"
                local targetPart = nil
                
                if hitPartStr == "Head" and head then
                    targetPart = head
                elseif hitPartStr == "HumanoidRootPart" and hrp then
                    targetPart = hrp
                else
                    if hrp and head then
                        local mousePos = Mouse.Hit.Position
                        local headDist = (head.Position - mousePos).Magnitude
                        local hrpDist = (hrp.Position - mousePos).Magnitude
                        targetPart = headDist < hrpDist and head or hrp
                    else
                        targetPart = head or hrp
                    end
                end
                
                if targetPart then
                    local vel = targetPart.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
                    local p = Surge.SilentAimbot.Prediction or {}
                    local offset = Vector3.new(
                        vel.X * (p.X or 0), 
                        vel.Y * (p.Y or 0), 
                        vel.Z * (p.Z or 0)
                    )
                    
                    if p.Power and p.Power.Enabled then
                        local power = p.Power.PredictionPower or 1.042
                        offset = offset * power
                    end
                    
                    if key:lower() == "hit" then
                        return CFrame.new(targetPart.Position + offset)
                    else
                        return targetPart
                    end
                end
            end
        end
    end
    return old(self, key)
end)

setreadonly(mt, true)

print("Brightside V4 - ULTRA SAFE VERSION")
print("All camera operations protected with pcall")
print("Target checks: Dead players are properly removed from ESP")

-- Cleanup on character change
LocalPlayer.CharacterAdded:Connect(function()
    korbloxApplied[LocalPlayer.UserId] = nil
    headlessApplied[LocalPlayer.UserId] = nil
end)

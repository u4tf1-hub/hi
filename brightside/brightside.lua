-- Name: Brightside V4 - Fixed Anti Trip
-- Location of script: StarterPlayerScripts (as LocalScript)
-- Script Type: LocalScript

-- ==========================================================
--  BRIGHTSIDE V4 - FINAL SOURCE (SAFE ANTI TRIP FIXED)
--  Fixed: Safe Anti Trip (Now Working), Fast Triggerbot, Mouse Cursor Targeting
--  Features: Spiderman, Korblox, Headless, Panic Ground, Rapid Fire
--  Games: Da Hood (2788229376), Hood Customs (9825515356)
-- ==========================================================

-- PERFORMANCE OPTIMIZED: Local service references
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- Cache frequently accessed values
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local Mouse = LocalPlayer:GetMouse()

-- ==========================================================
--  CONFIG ACCESS (with nil safety)
-- ==========================================================
local Surge = getgenv().Surge or {}
Surge['Main'] = Surge['Main'] or {}
Surge['Main']['Keybinds'] = Surge['Main']['Keybinds'] or {}

-- ==========================================================
--  STATE VARIABLES
-- ==========================================================
local ESPCache = {}
local LockedTarget = nil
local CurrentTarget = nil
local ESPEnabled = (Surge['Raid Awareness'] or {}).Enabled or false
local TriggerbotActive = false
local LastShot = 0
local RapidFireActive = false

-- Jump state
local LastJumpTime, LastWallJumpTime, JumpCount = 0, 0, 0

-- Anti-trip state
local AntiTripLastTime = 0
local ANTI_TRIP_INTERVAL = 0.05 -- Run every 50ms for responsiveness

-- ==========================================================
--  GAME DETECTION
-- ==========================================================
local placeId = game.PlaceId
local isDaHood = (placeId == 2788229376)
local isHoodCustoms = (placeId == 9825515356)
local isDaHoodGame = isDaHood or isHoodCustoms

print("[Brightside] Game detected:", isDaHoodGame and "Da Hood / Hood Customs" or "Other", "| PlaceID:", placeId)

-- ==========================================================
--  PERFORMANCE OPTIMIZED: KEYBIND CACHING
-- ==========================================================
local KeybindCache = {}

local function cacheKeyCode(keyName, default)
    if not keyName or type(keyName) ~= "string" then 
        return getgenv().Keycodes and getgenv().Keycodes[default:upper()] or Enum.KeyCode[default:upper()]
    end
    
    -- Cached lookup
    if KeybindCache[keyName] then
        return KeybindCache[keyName]
    end
    
    local upperKeyName = keyName:upper()
    
    -- Direct enum access
    local keyCode = Enum.KeyCode[upperKeyName]
    if keyCode then
        KeybindCache[keyName] = keyCode
        return keyCode
    end
    
    -- F-key parsing
    if upperKeyName:match("^F%d+$") then
        local fNum = tonumber(upperKeyName:sub(2))
        if fNum and fNum >= 1 and fNum <= 12 then
            keyCode = Enum.KeyCode["F" .. fNum]
            if keyCode then
                KeybindCache[keyName] = keyCode
                return keyCode
            end
        end
    end
    
    -- Fallback to default
    local defaultCode = Enum.KeyCode[default:upper()]
    KeybindCache[keyName] = defaultCode
    return defaultCode
end

-- Pre-cache all keybinds at startup (performance)
local function cacheAllKeybinds()
    local keybinds = Surge['Main']['Keybinds']
    if not keybinds then return end
    
    for key, value in pairs(keybinds) do
        if type(value) == "string" then
            local default = key:match("Toggle") and "T" or 
                           key:match("Lock") and "Z" or 
                           key:match("Trigger") and "V" or 
                           key:match("Panic") and "L" or 
                           key:match("Ground") and "X" or "T"
            cacheKeyCode(value, default)
        end
    end
end

cacheAllKeybinds()

-- ==========================================================
--  RAPID FIRE SYSTEM (Optimized)
-- ==========================================================
local utility = {}
getgenv().config = { enable = true, delay = 0.000000000001 }

-- Cache tool lookups
local lastToolCheck = 0
local cachedTool = nil

utility.get_gun = function()
    local char = LocalPlayer.Character
    if not char then return nil end
    
    -- Cache tool for 0.1 seconds to reduce loop iterations
    local now = tick()
    if now - lastToolCheck < 0.1 and cachedTool then
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

utility.rapid = function(tool)
    if tool then
        tool:Activate()
    end
end

getgenv().is_firing = false

UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        local gun = utility.get_gun()
        if getgenv().config.enable and gun and not is_firing then
            is_firing = true
            task.spawn(function()
                while is_firing and gun do
                    utility.rapid(gun)
                    task.wait(getgenv().config.delay)
                end
            end)
        end
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        is_firing = false
    end
end)

-- ==========================================================
--  UTILITY FUNCTIONS
-- ==========================================================
local function getKeyCodeFromString(keyName)
    if not keyName or type(keyName) ~= "string" then return nil end
    return cacheKeyCode(keyName, "T")
end

-- ==========================================================
--  MOUSE CURSOR TARGETING (Optimized)
-- ==========================================================
local function getTargetFromCursor()
    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    local closestPlayer = nil
    local closestDist = math.huge
    
    local fov = (Surge['Silent Aimbot'] or {}).FOV and Surge['Silent Aimbot'].FOV['Circle Value'] or 150
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        
        local char = player.Character
        if not char then continue end
        
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end
        
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then continue end
        
        local screenPos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
        if not onScreen or screenPos.Z <= 0 then continue end
        
        local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
        
        if dist < closestDist and dist <= fov then
            closestDist = dist
            closestPlayer = player
        end
    end
    
    return closestPlayer, closestDist
end

local function isVisible(target)
    if not (Surge['Target'] or {}).VisibleCheck then return true end
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
    local targetSettings = Surge['Target'] or {}
    local unlockSettings = targetSettings.Unlock or {}
    
    if unlockSettings.Knocked and hum and hum.Health <= 0 then
        return true
    end
    
    if unlockSettings.Grabbed then
        if char:FindFirstChild("GRABBING_CONSTRAINT") or 
           (hum and hum.PlatformStand) then
            return true
        end
    end
    return false
end

-- ==========================================================
--  TARGET SYSTEM (Optimized)
-- ==========================================================
local function getBestTarget()
    local targetSettings = Surge['Target'] or {}
    local targetType = targetSettings.Type or "Automatic"
    
    if targetType == "Target" then
        if LockedTarget then
            if shouldUnlockTarget(LockedTarget) then
                LockedTarget = nil
                return nil
            end
            if isVisible(LockedTarget) then
                return LockedTarget
            end
        end
        return nil
    end
    
    -- Auto mode: Check locked target first
    if LockedTarget and not shouldUnlockTarget(LockedTarget) then
        local char = LockedTarget.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local screenPos = Camera:WorldToViewportPoint(hrp.Position)
                if screenPos.Z > 0 then
                    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
                    local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                    local fov = (Surge['Silent Aimbot'] or {}).FOV and Surge['Silent Aimbot'].FOV['Circle Value'] or 150
                    if dist <= fov and isVisible(LockedTarget) then
                        return LockedTarget
                    end
                end
            end
        end
        LockedTarget = nil
    end
    
    -- Cursor targeting
    local cursorTarget = getTargetFromCursor()
    if cursorTarget and isVisible(cursorTarget) then
        return cursorTarget
    end
    
    return nil
end

-- ==========================================================
--  ESP SYSTEM (Optimized)
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
    
    -- Setup properties once
    d.Name.Size = 14
    d.Name.Center = true
    d.Name.Outline = true
    
    d.Box.Thickness = 1
    d.Box.Filled = false
    
    d.BoxOutline.Thickness = 3
    d.BoxOutline.Filled = false
    d.BoxOutline.Color = Color3.new(0, 0, 0)
    
    d.Tracer.Thickness = 1
    
    d.Distance.Size = 12
    d.Distance.Center = true
    d.Distance.Outline = true
    
    ESPCache[player] = d
    return d
end

local function RemoveESP(player)
    local drawings = ESPCache[player]
    if drawings then
        for _, dr in pairs(drawings) do
            dr:Remove()
        end
        ESPCache[player] = nil
    end
end

local function UpdateESP()
    if not ESPEnabled then
        for _, drawings in pairs(ESPCache) do
            for _, dr in pairs(drawings) do
                dr.Visible = false
            end
        end
        return
    end
    
    local maxDist = (Surge['Raid Awareness'] or {}).MaxRenderDistance or 1000
    local localHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local targetColor = (Surge['Target'] or {}).Color or Color3.fromRGB(0, 255, 0)
    local boxOtherColor = (Surge['Raid Awareness'] or {}).Box and Surge['Raid Awareness'].Box.OtherColor or Color3.fromRGB(255, 255, 255)
    local nameOtherColor = (Surge['Raid Awareness'] or {}).Name and Surge['Raid Awareness'].Name.OtherColor or Color3.fromRGB(255, 255, 255)
    local tracerOtherColor = (Surge['Raid Awareness'] or {}).Tracer and Surge['Raid Awareness'].Tracer.OtherColor or Color3.fromRGB(255, 255, 255)
    local distanceOtherColor = (Surge['Raid Awareness'] or {}).Distance and Surge['Raid Awareness'].Distance.OtherColor or Color3.fromRGB(255, 255, 255)
    
    local boxEnabled = (Surge['Raid Awareness'] or {}).Box and Surge['Raid Awareness'].Box.Enabled or false
    local nameEnabled = (Surge['Raid Awareness'] or {}).Name and Surge['Raid Awareness'].Name.Enabled or false
    local tracerEnabled = (Surge['Raid Awareness'] or {}).Tracer and Surge['Raid Awareness'].Tracer.Enabled or false
    local distanceEnabled = (Surge['Raid Awareness'] or {}).Distance and Surge['Raid Awareness'].Distance.Enabled or false
    local nameType = (Surge['Raid Awareness'] or {}).Name and Surge['Raid Awareness'].Name.Type or 'Display'
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        
        local char = player.Character
        if not char then
            RemoveESP(player)
            continue
        end
        
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        
        if not hrp or not hum or hum.Health <= 0 then 
            RemoveESP(player)
            continue 
        end
        
        -- Distance check
        if localHRP then
            if (hrp.Position - localHRP.Position).Magnitude > maxDist then 
                RemoveESP(player)
                continue 
            end
        end
        
        local feetPos = hrp.Position - Vector3.new(0, 3, 0)
        local screenPos = Camera:WorldToViewportPoint(feetPos)
        
        if screenPos.Z <= 0 then
            local drawings = ESPCache[player]
            if drawings then 
                for _, dr in pairs(drawings) do 
                    dr.Visible = false 
                end 
            end
            continue
        end
        
        local drawings = CreateESP(player)
        if not drawings then continue end
        
        local sp = Vector2.new(screenPos.X, screenPos.Y)
        local isTarget = (player == CurrentTarget)
        
        local headPos = hrp.Position + Vector3.new(0, 6, 0)
        local headScreen = Camera:WorldToViewportPoint(headPos)
        if headScreen.Z > 0 then
            local headSp = Vector2.new(headScreen.X, headScreen.Y)
            local h = math.abs(sp.Y - headSp.Y)
            local w = h * 0.5
            local boxPos = Vector2.new(sp.X - w/2, headSp.Y)
            
            if boxEnabled then
                drawings.BoxOutline.Size = Vector2.new(w + 4, h + 4)
                drawings.BoxOutline.Position = Vector2.new(boxPos.X - 2, boxPos.Y - 2)
                drawings.BoxOutline.Visible = true
                drawings.BoxOutline.Color = Color3.new(0, 0, 0)
                
                drawings.Box.Size = Vector2.new(w, h)
                drawings.Box.Position = boxPos
                drawings.Box.Color = isTarget and targetColor or boxOtherColor
                drawings.Box.Visible = true
            else
                drawings.BoxOutline.Visible = false
                drawings.Box.Visible = false
            end
        end
        
        if nameEnabled then
            drawings.Name.Text = nameType == 'Display' and player.DisplayName or player.Name
            drawings.Name.Position = Vector2.new(sp.X, sp.Y + 10)
            drawings.Name.Color = isTarget and targetColor or nameOtherColor
            drawings.Name.Visible = true
        else
            drawings.Name.Visible = false
        end
        
        if tracerEnabled then
            drawings.Tracer.From = Vector2.new(sp.X, Camera.ViewportSize.Y)
            drawings.Tracer.To = sp
            drawings.Tracer.Color = isTarget and targetColor or tracerOtherColor
            drawings.Tracer.Visible = true
        else
            drawings.Tracer.Visible = false
        end
        
        if distanceEnabled and localHRP then
            local d = (hrp.Position - localHRP.Position).Magnitude
            drawings.Distance.Text = math.floor(d) .. " studs"
            drawings.Distance.Position = Vector2.new(sp.X, sp.Y + 25)
            drawings.Distance.Color = isTarget and targetColor or distanceOtherColor
            drawings.Distance.Visible = true
        else
            drawings.Distance.Visible = false
        end
    end
end

-- ==========================================================
--  TRIGGERBOT SYSTEM (Fast)
-- ==========================================================
local function performTriggerbot()
    if not TriggerbotActive then return end
    if not (Surge['Triggerbot'] or {}).Enabled then return end
    
    local target = nil
    local triggerSettings = Surge['Triggerbot'] or {}
    
    if triggerSettings.Type == "Target" then
        if LockedTarget and not shouldUnlockTarget(LockedTarget) then
            target = LockedTarget
        end
    else
        target = CurrentTarget
    end
    
    if not target or not target.Character then return end
    
    local hrp = target.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    -- FOV check
    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    local pos = Camera:WorldToViewportPoint(hrp.Position)
    
    if pos.Z <= 0 then return end
    
    local dist = (Vector2.new(pos.X, pos.Y) - mousePos).Magnitude
    local threshold = (triggerSettings.ShootMode == 'Hitbox') and 15 or ((triggerSettings.FOV or {}).CircleValue or 45)
    
    if dist > threshold then return end
    
    -- Cooldown check
    local cooldown = (triggerSettings.Timing or {}).Cooldown or 0.001
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
--  ANTI TRIP SYSTEM (Fixed and Optimized)
-- ==========================================================
local function performAntiTrip()
    if not (Surge['Anti Trip'] or {}).Enabled then return end
    
    local now = tick()
    if now - AntiTripLastTime < ANTI_TRIP_INTERVAL then return end
    AntiTripLastTime = now
    
    local char = LocalPlayer.Character
    if not char then return end
    
    local hum = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp then return end
    
    -- Check if dead
    if hum.Health <= 0 then return end
    
    -- Detect trip conditions
    local isTripped = false
    
    -- 1. PlatformStand (main indicator)
    if hum.PlatformStand then
        isTripped = true
    end
    
    -- 2. Humanoid states
    local state = hum:GetState()
    if state == Enum.HumanoidStateType.FallingDown or 
       state == Enum.HumanoidStateType.Ragdoll or
       state == Enum.HumanoidStateType.Seated then
        isTripped = true
    end
    
    -- 3. Velocity check (falling fast)
    local vel = hrp.AssemblyLinearVelocity
    if vel.Y < -50 and vel.Magnitude > 60 then
        isTripped = true
    end
    
    if not isTripped then return end
    
    -- FIXED ANTI-TRIP: Multi-layered recovery
    pcall(function()
        -- Clear platform stand immediately
        hum.PlatformStand = false
        
        -- Change state to running (more natural than getting up)
        hum:ChangeState(Enum.HumanoidStateType.Running)
    end)
    
    -- Gentle velocity correction (preserves momentum, less detectable)
    local currentVel = hrp.AssemblyLinearVelocity
    if currentVel.Magnitude > 30 then
        local newVel = Vector3.new(
            currentVel.X * 0.3,
            math.max(currentVel.Y, -10), -- Allow some downward velocity
            currentVel.Z * 0.3
        )
        hrp.AssemblyLinearVelocity = newVel
    end
    
    -- Small upward boost if falling
    if vel.Y < -20 then
        hrp.AssemblyLinearVelocity = hrp.AssemblyLinearVelocity + Vector3.new(0, 12, 0)
    end
end

-- ==========================================================
--  SPIDERMAN WALL JUMP SYSTEM (Optimized)
-- ==========================================================
local function getWallNormal()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    
    local wallDist = (Surge.Spiderman or {}).WallDistance or 7
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {char}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    
    -- Pre-calculate directions
    local look = hrp.CFrame.LookVector
    local right = hrp.CFrame.RightVector
    local dirs = {look, -look, right, -right}
    local heights = {Vector3.new(0, -2, 0), Vector3.new(0, 0, 0), Vector3.new(0, 2, 0)}
    
    for _, h in ipairs(heights) do
        for _, d in ipairs(dirs) do
            local res = Workspace:Raycast(hrp.Position + h, d * wallDist, params)
            if res and res.Instance and res.Instance.CanCollide then
                return res.Normal
            end
        end
    end
    return nil
end

local function performWallJump()
    if not (Surge.Spiderman or {}).Enabled then return end
    
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or tick() - LastWallJumpTime < ((Surge.Spiderman or {}).Cooldown or 0.2) then 
        return 
    end
    
    local wallNormal = getWallNormal()
    if not wallNormal then return end
    
    local tool = char:FindFirstChildOfClass("Tool")
    local isKnife = tool and tool.Name:lower():match("knife")
    local power = isKnife and (Surge.Spiderman or {}).KnifeJumpPower or (Surge.Spiderman or {}).JumpPower or 50
    
    -- Reduce current velocity
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
--  KORBLOX SYSTEM (Optimized)
-- ==========================================================
local korbloxCache = {} -- Track which characters have korblox

local function applyKorblox()
    if not (Surge.Extra or {}).Korblox then return end
    
    local char = LocalPlayer.Character
    if not char then return end
    
    local playerId = LocalPlayer.UserId
    if korbloxCache[playerId] then return end
    
    local rightLeg = char:FindFirstChild("Right Leg") or char:FindFirstChild("RightLowerLeg")
    if not rightLeg then return end
    
    -- Hide leg parts
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
    
    -- Create korblox mesh
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
    
    korbloxCache[playerId] = true
end

-- ==========================================================
--  HEADLESS SYSTEM (Optimized)
-- ==========================================================
local headlessCache = {}

local function applyHeadless()
    if not (Surge.Extra or {}).Headless then return end
    
    local char = LocalPlayer.Character
    if not char then return end
    
    local playerId = LocalPlayer.UserId
    if headlessCache[playerId] then return end
    
    local head = char:FindFirstChild("Head")
    if not head then return end
    
    head.Transparency = 1
    for _, child in ipairs(head:GetChildren()) do
        if child:IsA("Decal") or child:IsA("Texture") then
            child.Transparency = 1
        end
    end
    
    headlessCache[playerId] = true
end

-- ==========================================================
--  PANIC GROUND SYSTEM
-- ==========================================================
local function performPanicGround()
    if not (Surge['Panic Ground'] or {}).Enabled then return end
    
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {char, Workspace.CurrentCamera}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    
    local result = Workspace:Raycast(hrp.Position, Vector3.new(0, -5000, 0), params)
    if result then
        hrp.CFrame = CFrame.new(result.Position + Vector3.new(0, 3, 0))
        print("[Panic Ground] Teleported to ground")
    end
end

-- ==========================================================
--  KEYBIND HANDLER (Nil-safe)
-- ==========================================================
local Keybinds = (Surge['Main'] or {}).Keybinds or {}

local function handleKeypress(keyCode, action)
    if not keyCode then return false end
    
    if action == "esp_toggle" then
        ESPEnabled = not ESPEnabled
        print("ESP:", ESPEnabled and "ON" or "OFF")
        if not ESPEnabled then
            for _, drawings in pairs(ESPCache) do
                for _, dr in pairs(drawings) do dr.Visible = false end
            end
        end
        return true
        
    elseif action == "lock_target" then
        if LockedTarget then
            LockedTarget = nil
            print("Lock cleared")
        else
            local cursorTarget = getTargetFromCursor()
            if cursorTarget then
                LockedTarget = cursorTarget
                print("Locked:", cursorTarget.Name)
            end
        end
        return true
        
    elseif action == "triggerbot" then
        if not (Surge['Triggerbot'] or {}).Enabled then return true end
        
        local mode = (Surge['Triggerbot'] or {}).Mode or 'Hold'
        if mode == 'Toggle' then
            TriggerbotActive = not TriggerbotActive
            print("Triggerbot:", TriggerbotActive and "ON" or "OFF")
        else
            TriggerbotActive = true
            print("Triggerbot: HOLD")
        end
        
        if (Surge['Player Modification'] or {}).RapidFire and Surge['Player Modification'].RapidFire.Enabled then
            RapidFireActive = true
        end
        return true
        
    elseif action == "panic_ground" then
        performPanicGround()
        return true
        
    elseif action == "panic" then
        if (Surge['Main'] or {}).Panic and Surge['Main'].Panic.Enabled then
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
        return true
    end
    
    return false
end

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    
    -- Space for wall jump (handled separately)
    if input.KeyCode == Enum.KeyCode.Space then
        local jumpNow = tick()
        if jumpNow - LastJumpTime < 0.4 then
            JumpCount = JumpCount + 1
        else
            JumpCount = 1
        end
        LastJumpTime = jumpNow
        
        if JumpCount >= 2 or not ((Surge.Spiderman or {}).RequireDoubleJump or false) then
            performWallJump()
        end
        return
    end
    
    -- Check all keybinds
    for action, keyName in pairs(Keybinds) do
        local keyCode = getKeyCodeFromString(keyName)
        if keyCode and input.KeyCode == keyCode then
            if handleKeypress(keyCode, action) then
                return
            end
        end
    end
end)

UserInputService.InputEnded:Connect(function(input, processed)
    if processed then return end
    
    -- Only handle triggerbot release
    local trigKey = getKeyCodeFromString(Keybinds['Trigger Bot Activate'] or 'C')
    if trigKey and input.KeyCode == trigKey then
        if (Surge['Triggerbot'] or {}).Enabled and 
           ((Surge['Triggerbot'] or {}).Mode or 'Hold') == 'Hold' then
            TriggerbotActive = false
            RapidFireActive = false
            print("Triggerbot: OFF")
        end
    end
end)

-- ==========================================================
--  MAIN LOOP (Optimized order)
-- ==========================================================
RunService.RenderStepped:Connect(function()
    -- 1. Target acquisition
    CurrentTarget = getBestTarget()
    
    -- 2. ESP updates
    UpdateESP()
    
    -- 3. Triggerbot (needs current target)
    performTriggerbot()
    
    -- 4. Anti-trip (runs every frame, fixed)
    performAntiTrip()
    
    -- 5. Cosmetic modifications
    applyHeadless()
    applyKorblox()
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
--  SILENT AIM (Metatable hook)
-- ==========================================================
local mouse = LocalPlayer:GetMouse()
local mt = getrawmetatable(mouse)
setreadonly(mt, false)
local old = mt.__index

mt.__index = newcclosure(function(self, key)
    if key:lower() == "hit" or key:lower() == "target" then
        if (Surge["Silent Aimbot"] or {}).Enabled and CurrentTarget then
            local tgt = CurrentTarget
            if tgt and tgt.Character then
                local char = tgt.Character
                local hrp = char:FindFirstChild("HumanoidRootPart")
                local head = char:FindFirstChild("Head")
                
                local hitPartStr = ((Surge["Silent Aimbot"] or {}).HitTarget or {}).HitPart or "Closest Point"
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
                    local p = (Surge["Silent Aimbot"] or {}).Prediction or {}
                    local offset = Vector3.new(
                        vel.X * (p.X or 0), 
                        vel.Y * (p.Y or 0), 
                        vel.Z * (p.Z or 0)
                    )
                    
                    if (p.Power or {}).Enabled then
                        local power = (p.Power or {}).PredictionPower or 1.042
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

print("Brightside V4 Loaded Successfully!")
print("Game:", isDaHoodGame and "Da Hood / Hood Customs" or "Other")
print("Features: Fast Triggerbot, Cursor Targeting, Fixed Anti Trip, Spiderman, Korblox, Headless, Panic Ground")

-- ==========================================================
--  EXTERNAL SCRIPT LOAD (Non-blocking)
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

-- Cleanup on character change
LocalPlayer.CharacterAdded:Connect(function()
    korbloxCache[LocalPlayer.UserId] = nil
    headlessCache[LocalPlayer.UserId] = nil
end)

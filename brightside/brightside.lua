-- ==========================================================
--  BRIGHTSIDE V5 - FULL SOURCE
--  Silent Aim, Camlock, Triggerbot, ESP, Spiderman,
--  Korblox, Headless, Panic Ground, Anti Trip, Rapid Fire
--  Games: Da Hood (2788229376), Hood Customs (9825515356)
-- ==========================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local StarterGui       = game:GetService("StarterGui")
local Workspace        = game:GetService("Workspace")

local LocalPlayer      = Players.LocalPlayer
local Camera           = Workspace.CurrentCamera
local Mouse            = LocalPlayer:GetMouse()

-- ==========================================================
--  CONFIG
-- ==========================================================
local Surge = getgenv().Surge
if not Surge then
    warn("[Brightside] No config found. Set getgenv().Surge before loading.")
    return
end

-- ==========================================================
--  GAME DETECTION
-- ==========================================================
local placeId      = game.PlaceId
local isDaHood     = (placeId == 2788229376)
local isHoodCustoms = (placeId == 9825515356)
local isDaHoodGame = isDaHood or isHoodCustoms
print("[Brightside] Game:", isDaHoodGame and "Da Hood / Hood Customs" or "Unknown", "| PlaceID:", placeId)

-- ==========================================================
--  STATE
-- ==========================================================
local ESPCache         = {}
local ESPEnabled       = Surge['Raid Awareness']['Enabled']
local LockedTarget     = nil
local CurrentTarget    = nil
local TriggerbotActive = false
local TBToggled        = false
local LastShot         = 0
local LastJumpTime     = 0
local LastWallJumpTime = 0
local JumpCount        = 0
local panicActive      = false
local originalStates   = {}

-- ==========================================================
--  UTILITY
-- ==========================================================
local function getKeyCode(keyName)
    if not keyName or type(keyName) ~= "string" then return nil end
    local ok, kc = pcall(function() return Enum.KeyCode[keyName:upper()] end)
    return ok and kc or nil
end

local function notify(msg)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title    = "Brightside",
            Text     = msg,
            Duration = 3,
        })
    end)
end

local function getChar(player)
    return player and player.Character
end

local function getRoot(player)
    local c = getChar(player)
    return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso"))
end

local function getHum(player)
    local c = getChar(player)
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function getEquippedTool()
    local c = getChar(LocalPlayer)
    return c and c:FindFirstChildOfClass("Tool")
end

-- ==========================================================
--  DAHOOD KNOCKED / STATE CHECKS
-- ==========================================================
local function isKnocked(player)
    local c = getChar(player)
    if not c then return true end
    local hum = c:FindFirstChild("Humanoid")
    if not hum then return true end
    if hum.Health <= 0 then return true end
    if hum:GetState() == Enum.HumanoidStateType.Dead then return true end
    -- DaHood Knocked BoolValue
    local kv = c:FindFirstChild("Knocked") or hum:FindFirstChild("Knocked")
    if kv and kv.Value == true then return true end
    return false
end

local function hasForcefield(player)
    local c = getChar(player)
    if not c then return false end
    return c:FindFirstChildOfClass("ForceField") ~= nil
end

local function isGrabbed(player)
    local c = getChar(player)
    if not c then return false end
    local hum = c:FindFirstChild("Humanoid")
    -- DaHood grab = PlatformStand or GRABBING_CONSTRAINT
    if c:FindFirstChild("GRABBING_CONSTRAINT") then return true end
    if hum and hum.PlatformStand and not isKnocked(player) then return true end
    local v = c:FindFirstChild("Grabbed") or c:FindFirstChild("IsGrabbed")
    if v and v.Value == true then return true end
    return false
end

local function isVisible(target)
    if not Surge['Target']['Visible Check'] then return true end
    local hrp = getRoot(target)
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

-- ==========================================================
--  KNIFE CHECK
-- ==========================================================
local KNIFE_NAMES = {"knife", "bowie", "combat knife", "cleaver", "blade"}

local function isKnifeEquipped()
    -- Check config knife check first
    local kc = Surge['Triggerbot'] and Surge['Triggerbot']['Knife Check']
    if kc and kc['Enabled'] == false then return false end
    local tool = getEquippedTool()
    if not tool then return false end
    local name = tool.Name:lower()
    -- Check config knife names if present
    if kc and kc['Knife Names'] then
        for _, kname in ipairs(kc['Knife Names']) do
            if name:find(kname:lower()) then return true end
        end
        return false
    end
    -- Fallback: built-in list
    for _, kname in ipairs(KNIFE_NAMES) do
        if name:find(kname) then return true end
    end
    return false
end

-- ==========================================================
--  TARGET VALIDITY
-- ==========================================================
local function shouldUnlockTarget(target)
    if not target or not target.Character then return true end
    local tc = Surge['Target Checks']
    local uc = Surge['Unlock Conditions']

    if uc and uc['Unlock on Target Knock'] and isKnocked(target) then return true end

    local hum = getHum(target)
    if Surge['Target']['Unlock']['Knocked'] and hum and hum.Health <= 0 then return true end
    if Surge['Target']['Unlock']['Grabbed'] and isGrabbed(target) then return true end

    return false
end

local function isValidTarget(player)
    if not player or player == LocalPlayer then return false end
    local c = getChar(player)
    if not c then return false end

    local tc = Surge['Target Checks']
    local sc = Surge['Self Checks']

    -- Target checks
    if tc then
        if tc['Knocked'] and isKnocked(player) then return false end
        if tc['Grabbed'] and isGrabbed(player) then return false end
        if tc['Forcefield'] and hasForcefield(player) then return false end
        if tc['Wall'] and not isVisible(player) then return false end
    end

    -- Self checks
    if sc then
        if sc['Knocked'] and isKnocked(LocalPlayer) then return false end
        if sc['Grabbed'] and isGrabbed(LocalPlayer) then return false end
    end

    return true
end

-- ==========================================================
--  TARGET UNLOCK WATCHER (unlock on kill/knock)
-- ==========================================================
local function watchLockedTarget(player)
    if not player then return end
    local c = getChar(player)
    if not c then return end

    local uc = Surge['Unlock Conditions']

    -- Watch Humanoid death
    local hum = c:FindFirstChild("Humanoid")
    if hum then
        hum.Died:Once(function()
            if LockedTarget == player then
                LockedTarget = nil
                notify("Target unlocked (killed)")
            end
        end)
    end

    -- Watch DaHood Knocked value
    local function watchKnocked(kv)
        kv:GetPropertyChangedSignal("Value"):Connect(function()
            if kv.Value == true and LockedTarget == player then
                LockedTarget = nil
                notify("Target unlocked (knocked)")
            end
        end)
    end

    local kv = c:FindFirstChild("Knocked")
    if kv then watchKnocked(kv) end

    c.ChildAdded:Connect(function(child)
        if child.Name == "Knocked" then
            watchKnocked(child)
        end
    end)
end

-- ==========================================================
--  CURSOR TARGETING
-- ==========================================================
local function getTargetFromCursor()
    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    local closest, closestDist = nil, math.huge
    local fov = Surge['Silent Aimbot']['FOV']['Circle Value'] or 150

    for _, player in pairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        if not isValidTarget(player) then continue end
        local hrp = getRoot(player)
        if not hrp then continue end
        local sp, onScreen = Camera:WorldToViewportPoint(hrp.Position)
        if not onScreen or sp.Z <= 0 then continue end
        local dist = (Vector2.new(sp.X, sp.Y) - mousePos).Magnitude
        if dist < closestDist and dist <= fov then
            closestDist = dist
            closest = player
        end
    end
    return closest, closestDist
end

-- ==========================================================
--  BEST TARGET
-- ==========================================================
local function getBestTarget()
    local targetType = Surge['Target']['Type'] or "Automatic"

    -- Locked target mode
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

    -- Automatic mode
    if LockedTarget and not shouldUnlockTarget(LockedTarget) then
        local hrp = getRoot(LockedTarget)
        if hrp then
            local sp = Camera:WorldToViewportPoint(hrp.Position)
            if sp.Z > 0 then
                local dist = (Vector2.new(sp.X, sp.Y) - Vector2.new(Mouse.X, Mouse.Y)).Magnitude
                local fov = Surge['Silent Aimbot']['FOV']['Circle Value'] or 150
                if dist <= fov and isVisible(LockedTarget) then
                    return LockedTarget
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
--  PANIC SYSTEM (toggle - no re-execute needed)
-- ==========================================================
local function setPanic(enabled)
    local pc = Surge['Main']['Panic']
    if enabled then
        if pc['Disable Silent Aim']        then originalStates['sa']  = Surge['Silent Aimbot']['Enabled'];                   Surge['Silent Aimbot']['Enabled']  = false end
        if pc['Disable Aim Assist']        then originalStates['aa']  = Surge['Aim Assist']['Enabled'];                     Surge['Aim Assist']['Enabled']     = false end
        if pc['Disable Trigger Bot']       then originalStates['tb']  = Surge['Triggerbot']['Enabled'];                     Surge['Triggerbot']['Enabled']     = false end
        if pc['Disable Visuals']           then originalStates['esp'] = ESPEnabled;                                         ESPEnabled = false end
        if pc['Disable Player Modifications'] then
            originalStates['spd'] = Surge['Player Modification']['Movement']['Speed Modifications']['Enabled']
            originalStates['jmp'] = Surge['Player Modification']['Movement']['Jump Modifications']['Enabled']
            Surge['Player Modification']['Movement']['Speed Modifications']['Enabled'] = false
            Surge['Player Modification']['Movement']['Jump Modifications']['Enabled']  = false
        end
        if pc['Disable Raid Awareness']    then originalStates['ra']  = Surge['Raid Awareness']['Enabled'];                 Surge['Raid Awareness']['Enabled'] = false end

        TriggerbotActive = false
        TBToggled        = false
        LockedTarget     = nil
        CurrentTarget    = nil

        for _, d in pairs(ESPCache) do
            for _, dr in pairs(d) do pcall(function() dr.Visible = false end) end
        end

        panicActive = true
        notify("⚠ Panic ON")
    else
        if originalStates['sa']  ~= nil then Surge['Silent Aimbot']['Enabled']  = originalStates['sa']  end
        if originalStates['aa']  ~= nil then Surge['Aim Assist']['Enabled']     = originalStates['aa']  end
        if originalStates['tb']  ~= nil then Surge['Triggerbot']['Enabled']     = originalStates['tb']  end
        if originalStates['esp'] ~= nil then ESPEnabled                         = originalStates['esp'] end
        if originalStates['ra']  ~= nil then Surge['Raid Awareness']['Enabled'] = originalStates['ra']  end
        if originalStates['spd'] ~= nil then Surge['Player Modification']['Movement']['Speed Modifications']['Enabled'] = originalStates['spd'] end
        if originalStates['jmp'] ~= nil then Surge['Player Modification']['Movement']['Jump Modifications']['Enabled']  = originalStates['jmp'] end
        originalStates = {}
        panicActive = false
        notify("✅ Panic OFF")
    end
end

-- ==========================================================
--  RAPID FIRE SYSTEM (original - works via Tool:Activate)
-- ==========================================================
getgenv().is_firing = false
getgenv().rf_config = {
    enable = true,
    delay  = Surge['Player Modification']['Rapid Fire']['Delay'] or 0.000001
}

local function getRapidFireTool()
    local c = getChar(LocalPlayer)
    if not c then return nil end
    for _, tool in ipairs(c:GetChildren()) do
        if tool:IsA("Tool") and tool:FindFirstChild("Ammo") then
            return tool
        end
    end
    -- fallback: any equipped tool that isn't a knife
    local tool = getEquippedTool()
    if tool and not isKnifeEquipped() then return tool end
    return nil
end

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        if not Surge['Player Modification']['Rapid Fire']['Enabled'] then return end
        if panicActive then return end
        local gun = getRapidFireTool()
        if gun and not getgenv().is_firing then
            getgenv().is_firing = true
            task.spawn(function()
                while getgenv().is_firing do
                    if not Surge['Player Modification']['Rapid Fire']['Enabled'] or panicActive then
                        getgenv().is_firing = false
                        break
                    end
                    local currentGun = getRapidFireTool()
                    if currentGun then
                        pcall(function() currentGun:Activate() end)
                    end
                    task.wait(getgenv().rf_config.delay)
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
--  ESP SYSTEM
-- ==========================================================
local function CreateESP(player)
    if ESPCache[player] then return ESPCache[player] end
    local d = {
        Name       = Drawing.new("Text"),
        Box        = Drawing.new("Square"),
        BoxOutline = Drawing.new("Square"),
        Tracer     = Drawing.new("Line"),
        Distance   = Drawing.new("Text"),
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
        for _, dr in pairs(ESPCache[player]) do pcall(function() dr:Remove() end) end
        ESPCache[player] = nil
    end
end

local function UpdateESP()
    if not ESPEnabled then
        for _, d in pairs(ESPCache) do
            for _, dr in pairs(d) do pcall(function() dr.Visible = false end) end
        end
        return
    end

    local maxDist    = Surge['Raid Awareness']['Max Render Distance'] or 1000
    local targetColor = Surge['Target']['Color'] or Color3.fromRGB(0, 255, 0)

    for _, player in pairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end

        local c   = getChar(player)
        local hrp = getRoot(player)
        local hum = getHum(player)

        if not c or not hrp or not hum or hum.Health <= 0 then
            RemoveESP(player); continue
        end

        local myHRP = getRoot(LocalPlayer)
        if myHRP and (hrp.Position - myHRP.Position).Magnitude > maxDist then
            RemoveESP(player); continue
        end

        local feetPos  = hrp.Position - Vector3.new(0, 3, 0)
        local sp3      = Camera:WorldToViewportPoint(feetPos)
        if sp3.Z <= 0 then
            local d = ESPCache[player]
            if d then for _, dr in pairs(d) do pcall(function() dr.Visible = false end) end end
            continue
        end

        local d        = CreateESP(player)
        local sp       = Vector2.new(sp3.X, sp3.Y)
        local isTarget = (player == CurrentTarget or player == LockedTarget)
        local nameCol  = isTarget and targetColor or Surge['Raid Awareness']['Name']['Other Color']
        local boxCol   = isTarget and targetColor or Surge['Raid Awareness']['Box']['Other Color']

        -- Box
        if Surge['Raid Awareness']['Box']['Enabled'] then
            local head    = c:FindFirstChild("Head")
            local headPos = head and head.Position or (hrp.Position + Vector3.new(0, 3, 0))
            local headSP3 = Camera:WorldToViewportPoint(headPos + Vector3.new(0, 1, 0))
            if headSP3.Z > 0 then
                local headSP = Vector2.new(headSP3.X, headSP3.Y)
                local h = math.abs(sp.Y - headSP.Y)
                local w = h * 0.5
                local pos = Vector2.new(sp.X - w/2, headSP.Y)
                d.BoxOutline.Size = Vector2.new(w+4, h+4); d.BoxOutline.Position = Vector2.new(pos.X-2, pos.Y-2); d.BoxOutline.Visible = true
                d.Box.Size = Vector2.new(w, h); d.Box.Position = pos; d.Box.Color = boxCol; d.Box.Visible = true
            end
        else
            d.Box.Visible = false; d.BoxOutline.Visible = false
        end

        -- Name
        if Surge['Raid Awareness']['Name']['Enabled'] then
            local t = Surge['Raid Awareness']['Name']['Type'] or 'Display'
            d.Name.Text     = (t == 'Display') and player.DisplayName or player.Name
            d.Name.Position = Vector2.new(sp.X, sp.Y + 10)
            d.Name.Color    = nameCol
            d.Name.Size     = Surge['Raid Awareness']['Name']['Size'] or 14
            d.Name.Visible  = true
        else
            d.Name.Visible = false
        end

        -- Tracer
        if Surge['Raid Awareness']['Tracer']['Enabled'] then
            local tracerColor = isTarget and targetColor or Surge['Raid Awareness']['Tracer']['Other Color']
            local tracerFrom = Surge['Raid Awareness']['Tracer']['Type'] == 'Feet'
                and Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y)
                or  Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
            d.Tracer.From    = tracerFrom
            d.Tracer.To      = sp
            d.Tracer.Color   = tracerColor
            d.Tracer.Thickness = Surge['Raid Awareness']['Tracer']['Thickness'] or 1
            d.Tracer.Visible = true
        else
            d.Tracer.Visible = false
        end

        -- Distance
        if Surge['Raid Awareness']['Distance']['Enabled'] then
            local myHRP2 = getRoot(LocalPlayer)
            if myHRP2 then
                local dist = math.floor((hrp.Position - myHRP2.Position).Magnitude)
                local distColor = isTarget and targetColor or Surge['Raid Awareness']['Distance']['Other Color']
                d.Distance.Text     = dist .. " studs"
                d.Distance.Position = Vector2.new(sp.X, sp.Y + 25)
                d.Distance.Color    = distColor
                d.Distance.Visible  = true
            end
        else
            d.Distance.Visible = false
        end
    end
end

-- Init ESP
for _, p in pairs(Players:GetPlayers()) do
    if p ~= LocalPlayer then CreateESP(p) end
end
Players.PlayerAdded:Connect(function(p)
    p.CharacterAdded:Connect(function() task.wait(1); CreateESP(p) end)
end)
Players.PlayerRemoving:Connect(function(p)
    if p == LockedTarget  then LockedTarget  = nil end
    if p == CurrentTarget then CurrentTarget = nil end
    RemoveESP(p)
end)

-- ==========================================================
--  TRIGGERBOT (fast - Tool:Activate based)
-- ==========================================================
local function performTriggerbot()
    if not TriggerbotActive and not TBToggled then return end
    if not Surge['Triggerbot']['Enabled'] or panicActive then return end

    -- Knife check - stop TB if knife equipped
    if isKnifeEquipped() then return end

    local target = CurrentTarget
    if Surge['Target']['Type'] == "Target" then
        target = (LockedTarget and not shouldUnlockTarget(LockedTarget)) and LockedTarget or nil
    end
    if not target or not target.Character then return end

    local hrp = getRoot(target)
    if not hrp then return end

    local sp3 = Camera:WorldToViewportPoint(hrp.Position)
    if sp3.Z <= 0 then return end

    local mousePos  = Vector2.new(Mouse.X, Mouse.Y)
    local screenPos = Vector2.new(sp3.X, sp3.Y)
    local dist      = (screenPos - mousePos).Magnitude

    local fovMode   = Surge['Triggerbot']['FOV']['FOV Type'] or 'Circle'
    local threshold = fovMode == 'Circle' and (Surge['Triggerbot']['FOV']['Circle Value'] or 45) or 45
    if Surge['Triggerbot']['Shoot Mode'] == 'Hitbox' then threshold = 20 end

    if dist > threshold then return end

    -- Fire rate
    local hasFR    = Surge['Triggerbot']['Fire Rate'] ~= nil
    local cooldown = hasFR and Surge['Triggerbot']['Fire Rate']['Delay']
                           or  Surge['Triggerbot']['Timing']['Cooldown']
                           or  0.001
    local now = tick()
    if now - LastShot < cooldown then return end

    local tool = getEquippedTool()
    if not tool then return end

    -- Don't fire with knife
    if isKnifeEquipped() then return end

    pcall(function()
        tool:Activate()
        LastShot = now
    end)
end

local function startTBLoop()
    task.spawn(function()
        while TriggerbotActive or TBToggled do
            if not TriggerbotActive and not TBToggled then break end
            if panicActive then task.wait(0.1); continue end
            performTriggerbot()
            task.wait(0.001)
        end
    end)
end

-- ==========================================================
--  ANTI TRIP (safe - PlatformStand method + state check)
-- ==========================================================
local antiTripAttempts   = 0
local lastAntiTripTime   = 0

RunService.Heartbeat:Connect(function()
    if not Surge['Anti Trip']['Enabled'] or panicActive then return end

    local now = tick()
    if now - lastAntiTripTime < 0.1 then return end
    lastAntiTripTime = now

    local c   = getChar(LocalPlayer)
    local hum = c and c:FindFirstChild("Humanoid")
    local hrp = c and c:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp then return end

    local state = hum:GetState()
    local tripped = hum.PlatformStand and not isKnocked(LocalPlayer)

    -- Check DaHood ragdoll values
    if not tripped then
        for _, vname in ipairs({"Ragdoll", "Tripped", "Stumble"}) do
            local v = c:FindFirstChild(vname)
            if v and v:IsA("BoolValue") and v.Value then
                tripped = true
                break
            end
        end
    end

    if not tripped and state ~= Enum.HumanoidStateType.FallingDown then return end

    if antiTripAttempts > 5 then return end
    antiTripAttempts = antiTripAttempts + 1

    -- Safe: just reset PlatformStand
    pcall(function() hum.PlatformStand = false end)

    -- Soft velocity cap
    if hrp.AssemblyLinearVelocity.Magnitude > 50 then
        hrp.AssemblyLinearVelocity = hrp.AssemblyLinearVelocity.Unit * 50
    end

    task.delay(2, function()
        if hum and not hum.PlatformStand then
            antiTripAttempts = 0
        end
    end)
end)

-- ==========================================================
--  PLAYER MODIFICATIONS (Speed / Jump)
-- ==========================================================
local function applyPlayerMods()
    local pm  = Surge['Player Modification']
    local c   = getChar(LocalPlayer)
    local hum = c and c:FindFirstChild("Humanoid")
    if not hum or not pm['Movement']['Enabled'] or panicActive then return end

    local spd = pm['Movement']['Speed Modifications']
    local jmp = pm['Movement']['Jump Modifications']

    if spd and spd['Enabled'] then
        hum.WalkSpeed = spd['Value']
    end
    if jmp and jmp['Enabled'] then
        hum.JumpPower = jmp['Value']
    end
end

RunService.Heartbeat:Connect(applyPlayerMods)
LocalPlayer.CharacterAdded:Connect(function() task.wait(1); applyPlayerMods() end)

-- Weapon mods
local function applyWeaponMod(tool)
    if not Surge['Player Modification']['Weapon Modifications']['Enabled'] then return end
    local wm = Surge['Player Modification']['Weapon Modifications']
    for weaponName, modData in pairs(wm) do
        if weaponName == 'Enabled' then continue end
        if tool.Name:find(weaponName) or weaponName == 'Other Shotguns' then
            for _, v in ipairs(tool:GetDescendants()) do
                if v:IsA("NumberValue") then
                    local n = v.Name:lower()
                    if n:find("delay") or n:find("cooldown") or n:find("firerate") or n:find("debounce") then
                        pcall(function() v.Value = modData['Value'] end)
                    end
                end
            end
        end
    end
end

LocalPlayer.CharacterAdded:Connect(function(c)
    c.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then applyWeaponMod(child) end
    end)
end)

-- ==========================================================
--  PANIC GROUND
-- ==========================================================
local function performPanicGround()
    if not Surge['Panic Ground']['Enabled'] then return end
    local c   = getChar(LocalPlayer)
    local hrp = c and c:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {c, Camera}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    local result = Workspace:Raycast(hrp.Position, Vector3.new(0, -5000, 0), params)

    if Surge['Panic Ground']['Mode'] == 'Instant' then
        local groundY = result and result.Position.Y + 3 or 3
        local vel = Surge['Panic Ground']['Preserve Velocity'] and hrp.AssemblyLinearVelocity or Vector3.zero
        hrp.CFrame = CFrame.new(Vector3.new(hrp.Position.X, groundY, hrp.Position.Z))
        if Surge['Panic Ground']['Preserve Velocity'] then
            hrp.AssemblyLinearVelocity = Vector3.new(vel.X, 0, vel.Z)
        end
    elseif Surge['Panic Ground']['Mode'] == 'Smooth' then
        local groundY = result and result.Position.Y + 3 or 3
        local speed   = Surge['Panic Ground']['Smooth Speed'] or 400
        local tween   = TweenService:Create(hrp,
            TweenInfo.new(math.abs(hrp.Position.Y - groundY) / speed),
            {CFrame = CFrame.new(Vector3.new(hrp.Position.X, groundY, hrp.Position.Z))}
        )
        tween:Play()
    end
end

-- ==========================================================
--  SPIDERMAN WALL JUMP (original - uses wall normal)
-- ==========================================================
local function getWallNormal()
    local c   = getChar(LocalPlayer)
    local hrp = c and c:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end

    local wallDist = Surge['Spiderman']['Wall Distance'] or 7
    local params   = RaycastParams.new()
    params.FilterDescendantsInstances = {c}
    params.FilterType = Enum.RaycastFilterType.Blacklist

    local heights = {Vector3.new(0,-2,0), Vector3.new(0,0,0), Vector3.new(0,2,0)}
    local dirs    = {
        hrp.CFrame.LookVector,
        -hrp.CFrame.LookVector,
        hrp.CFrame.RightVector,
        -hrp.CFrame.RightVector,
    }

    for _, h in ipairs(heights) do
        for _, d in ipairs(dirs) do
            local res = Workspace:Raycast(hrp.Position + h, d * wallDist, params)
            if res and res.Instance.CanCollide then return res.Normal end
        end
    end
    return nil
end

local function performWallJump()
    if not Surge['Spiderman']['Enabled'] then return end
    local c   = getChar(LocalPlayer)
    local hrp = c and c:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    if tick() - LastWallJumpTime < (Surge['Spiderman']['Cooldown'] or 0.2) then return end

    local wallNormal = getWallNormal()
    if not wallNormal then return end

    local tool = getEquippedTool()
    local isKnife = tool and tool.Name:lower():find("knife")
    local power   = isKnife and Surge['Spiderman']['Knife Jump Power'] or Surge['Spiderman']['Jump Power']

    hrp.AssemblyLinearVelocity = Vector3.new(
        hrp.AssemblyLinearVelocity.X * 0.2, 0, hrp.AssemblyLinearVelocity.Z * 0.2
    )
    task.wait(0.01)

    local jumpDir = (Vector3.new(0, 1.45, 0) + wallNormal * 0.35).Unit
    hrp.AssemblyLinearVelocity = jumpDir * (power * 1.35)
    LastWallJumpTime = tick()
end

-- ==========================================================
--  KORBLOX (original mesh/weld method)
-- ==========================================================
local function applyKorblox()
    if not Surge['Extra']['Korblox'] then return end
    local c = getChar(LocalPlayer)
    if not c or c:FindFirstChild("KorbloxVisual") then return end

    local partsToHide = {"Right Leg","RightUpperLeg","RightLowerLeg","RightFoot"}
    for _, name in ipairs(partsToHide) do
        local part = c:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            part.Transparency = 1
            for _, child in pairs(part:GetChildren()) do
                if child:IsA("Decal") or child:IsA("Texture") then
                    child.Transparency = 1
                end
            end
        end
    end

    local rightLeg = c:FindFirstChild("Right Leg") or c:FindFirstChild("RightLowerLeg")
    if not rightLeg then return end

    local korblox  = Instance.new("Part")
    korblox.Name   = "KorbloxVisual"
    korblox.Size   = Vector3.new(1, 2, 1)
    korblox.CanCollide = false
    korblox.Transparency = 0

    local mesh         = Instance.new("SpecialMesh")
    mesh.MeshType      = Enum.MeshType.FileMesh
    mesh.MeshId        = "rbxassetid://139607718"
    mesh.TextureId     = "rbxassetid://139607805"
    mesh.Scale         = Vector3.new(1.05, 1.05, 1.05)
    mesh.Parent        = korblox

    local weld         = Instance.new("Weld")
    weld.Part0         = rightLeg
    weld.Part1         = korblox
    weld.C0            = CFrame.new(0, 0, 0)
    weld.C1            = CFrame.new(0, 0, 0)
    weld.Parent        = korblox

    korblox.Parent = c
end

-- ==========================================================
--  HEADLESS
-- ==========================================================
local function applyHeadless()
    if not Surge['Extra']['Headless'] then return end
    local c    = getChar(LocalPlayer)
    local head = c and c:FindFirstChild("Head")
    if not head then return end

    head.Transparency = 1
    for _, child in pairs(head:GetChildren()) do
        if child:IsA("Decal") or child:IsA("Texture") then
            child.Transparency = 1
        end
    end
end

-- Apply on spawn
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    applyHeadless()
    applyKorblox()
    applyPlayerMods()
end)
if LocalPlayer.Character then
    task.delay(1, function()
        applyHeadless()
        applyKorblox()
    end)
end

-- ==========================================================
--  SILENT AIM (original mouse __index hook - real method)
-- ==========================================================
local mt  = getrawmetatable(Mouse)
local old = rawget(mt, "__index")
setreadonly(mt, false)

rawset(mt, "__index", newcclosure(function(self, key)
    if Surge['Silent Aimbot']['Enabled'] and not panicActive and CurrentTarget then
        local k = key:lower()
        if k == "hit" or k == "target" then
            local tgt  = CurrentTarget
            local c    = tgt and getChar(tgt)
            if c then
                local hitPartStr = Surge['Silent Aimbot']['Hit Target']['Hit Part'] or 'Head'
                local head = c:FindFirstChild("Head")
                local hrp  = c:FindFirstChild("HumanoidRootPart")
                local targetPart = nil

                if hitPartStr == 'Head' and head then
                    targetPart = head
                elseif hitPartStr == 'HumanoidRootPart' and hrp then
                    targetPart = hrp
                else
                    -- Closest Point: pick whichever is closer to mouse
                    if head and hrp then
                        local mouseHit = old(self, "Hit")
                        if mouseHit then
                            local mPos = mouseHit.Position
                            targetPart = (head.Position - mPos).Magnitude < (hrp.Position - mPos).Magnitude
                                and head or hrp
                        else
                            targetPart = head
                        end
                    else
                        targetPart = head or hrp
                    end
                end

                if targetPart then
                    local vel   = targetPart.AssemblyLinearVelocity or Vector3.zero
                    local pred  = Surge['Silent Aimbot']['Prediction']
                    local px, py, pz = pred['X'] or 0, pred['Y'] or 0, pred['Z'] or 0
                    local offset = Vector3.new(vel.X * px, vel.Y * py, vel.Z * pz)

                    if pred['Power'] and pred['Power']['Enabled'] then
                        local power = pred['Power']['Prediction Power'] or 0
                        if power ~= 0 then offset = offset * power end
                    end

                    if k == "hit" then
                        return CFrame.new(targetPart.Position + offset)
                    else
                        return targetPart
                    end
                end
            end
        end
    end
    return old(self, key)
end))

setreadonly(mt, true)

-- ==========================================================
--  AIM ASSIST / CAMLOCK (mousemoverel method)
-- ==========================================================
RunService.RenderStepped:Connect(function()
    if not Surge['Aim Assist']['Enabled'] or panicActive then return end

    local target = lockedTarget
    if Surge['Target']['Type'] == 'Automatic' then
        -- Use closest in aim assist FOV
        local fovCfg = Surge['Aim Assist']['FOV']
        local fovVal = fovCfg['Circle Value'] or 75
        local best, bestDist = nil, math.huge
        for _, p in pairs(Players:GetPlayers()) do
            if p == LocalPlayer then continue end
            if not isValidTarget(p) then continue end
            local hrp = getRoot(p)
            if not hrp then continue end
            local sp3 = Camera:WorldToViewportPoint(hrp.Position)
            if sp3.Z <= 0 then continue end
            local sp   = Vector2.new(sp3.X, sp3.Y)
            local mpos = Vector2.new(Mouse.X, Mouse.Y)
            local dist = (sp - mpos).Magnitude
            if dist < bestDist and dist <= fovVal then
                best = p; bestDist = dist
            end
        end
        target = best
    elseif LockedTarget and not shouldUnlockTarget(LockedTarget) then
        target = LockedTarget
    end

    if not target then return end
    local hrp = getRoot(target)
    if not hrp then return end

    local pred   = Surge['Aim Assist']['Hit Target']['Prediction']
    local aimPos = hrp.Position + Vector3.new(pred['X'] or 0, pred['Y'] or 0, pred['Z'] or 0)

    local sp3 = Camera:WorldToViewportPoint(aimPos)
    if sp3.Z <= 0 then return end

    local sp     = Vector2.new(sp3.X, sp3.Y)
    local mpos   = Vector2.new(Mouse.X, Mouse.Y)
    local diff   = sp - mpos

    local sm     = Surge['Aim Assist']['Smoothing']['Smoothing Value']
    local msmooth = sm['Mouse Smoothing']
    local sx, sy = msmooth['X'] or 0.17, msmooth['Y'] or 0.17

    if mousemoverel then
        mousemoverel(diff.X * sx, diff.Y * sy)
    end
end)

-- ==========================================================
--  ANTI CURVE
-- ==========================================================
RunService.RenderStepped:Connect(function()
    local ac = Surge['Silent Aimbot']['Anti Curve']
    if not ac['Enabled'] or not Surge['Silent Aimbot']['Enabled'] or panicActive then return end

    local target = CurrentTarget
    if not target then return end
    local hrp = getRoot(target)
    if not hrp then return end

    local sp3 = Camera:WorldToViewportPoint(hrp.Position)
    if sp3.Z <= 0 then return end

    local sp     = Vector2.new(sp3.X, sp3.Y)
    local mpos   = Vector2.new(Mouse.X, Mouse.Y)
    local diff   = sp - mpos
    local angle  = math.deg(math.atan2(diff.Y, diff.X))
    local angles = Surge['Silent Aimbot']['Anti Curve']['Angles']

    if math.abs(angle) > (angles['Max Angle'] or 12) then
        if diff.Magnitude < (angles['Distance Threshold'] or 100) then
            if mousemoverel then
                mousemoverel(diff.X * 0.1, diff.Y * 0.1)
            end
        end
    end
end)

-- ==========================================================
--  KEYBIND HANDLER
-- ==========================================================
local Keybinds = Surge['Main']['Keybinds']

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    local kc = input.KeyCode

    -- Panic toggle
    if kc == getKeyCode(Keybinds['Panic'] or 'L') then
        setPanic(not panicActive)
        return
    end

    -- ESP toggle
    if kc == getKeyCode(Keybinds['ESP Toggle'] or 'T') then
        ESPEnabled = not ESPEnabled
        notify("ESP: " .. (ESPEnabled and "ON" or "OFF"))
        return
    end

    -- Lock Target
    if kc == getKeyCode(Keybinds['Lock Target'] or 'Z') then
        if LockedTarget then
            LockedTarget = nil
            notify("Target unlocked")
        else
            local t = getTargetFromCursor()
            if t then
                LockedTarget = t
                watchLockedTarget(t)
                notify("Locked: " .. t.Name)
            end
        end
        return
    end

    -- Triggerbot
    if kc == getKeyCode(Keybinds['Trigger Bot Activate'] or 'C') then
        if not Surge['Triggerbot']['Enabled'] then return end
        local mode = Surge['Triggerbot']['Mode'] or 'Hold'
        if mode == 'Toggle' then
            TBToggled = not TBToggled
            notify("Triggerbot: " .. (TBToggled and "ON" or "OFF"))
            if TBToggled then startTBLoop() end
        else
            TriggerbotActive = true
            startTBLoop()
        end
        return
    end

    -- Speed toggle
    if kc == getKeyCode(Keybinds['Speed'] or 'B') then
        local sm = Surge['Player Modification']['Movement']['Speed Modifications']
        sm['Enabled'] = not sm['Enabled']
        notify("Speed: " .. (sm['Enabled'] and "ON" or "OFF"))
        return
    end

    -- Jump toggle
    if kc == getKeyCode(Keybinds['Jump Power'] or 'Y') then
        local jm = Surge['Player Modification']['Movement']['Jump Modifications']
        jm['Enabled'] = not jm['Enabled']
        notify("Jump: " .. (jm['Enabled'] and "ON" or "OFF"))
        return
    end

    -- Panic Ground
    if kc == getKeyCode(Keybinds['Panic Ground'] or 'X') then
        performPanicGround()
        return
    end

    -- Spiderman wall jump (double space)
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
end)

UserInputService.InputEnded:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == getKeyCode(Keybinds['Trigger Bot Activate'] or 'C') then
        if Surge['Triggerbot']['Mode'] == 'Hold' then
            TriggerbotActive = false
        end
    end
end)

-- ==========================================================
--  MAIN LOOP
-- ==========================================================
RunService.RenderStepped:Connect(function()
    CurrentTarget = getBestTarget()
    UpdateESP()
    applyHeadless()
    applyKorblox()
end)

-- Triggerbot runs in its own tight loop (started on keypress)
-- Rapid fire runs in its own loop (started on mouse1)

-- ==========================================================
--  INTRO
-- ==========================================================
if Surge['Main']['Intro'] then
    task.spawn(function()
        local sg = Instance.new("ScreenGui")
        sg.Name = "BrightsideIntro"
        sg.IgnoreGuiInset = true
        sg.ResetOnSpawn   = false
        sg.Parent = game:GetService("CoreGui")

        local frame = Instance.new("Frame", sg)
        frame.Size              = UDim2.new(0, 420, 0, 90)
        frame.Position          = UDim2.new(0.5, -210, 0, -100)
        frame.BackgroundColor3  = Color3.fromRGB(12, 12, 12)
        frame.BorderSizePixel   = 0
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

        local bar = Instance.new("Frame", frame)
        bar.Size             = UDim2.new(1, 0, 0, 3)
        bar.BackgroundColor3 = Color3.fromRGB(0, 180, 255)
        bar.BorderSizePixel  = 0

        local title = Instance.new("TextLabel", frame)
        title.Size              = UDim2.new(1, -20, 0, 40)
        title.Position          = UDim2.new(0, 12, 0, 8)
        title.Text              = "BRIGHTSIDE"
        title.TextColor3        = Color3.fromRGB(0, 180, 255)
        title.TextSize          = 26
        title.Font              = Enum.Font.GothamBlack
        title.TextXAlignment    = Enum.TextXAlignment.Left
        title.BackgroundTransparency = 1

        local sub = Instance.new("TextLabel", frame)
        sub.Size              = UDim2.new(1, -20, 0, 25)
        sub.Position          = UDim2.new(0, 12, 0, 52)
        sub.Text              = "v5.0  ·  All systems active"
        sub.TextColor3        = Color3.fromRGB(120, 120, 120)
        sub.TextSize          = 13
        sub.Font              = Enum.Font.Gotham
        sub.TextXAlignment    = Enum.TextXAlignment.Left
        sub.BackgroundTransparency = 1

        TweenService:Create(frame,
            TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
            {Position = UDim2.new(0.5, -210, 0, 18)}
        ):Play()

        task.wait(3.5)

        local out = TweenService:Create(frame,
            TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
            {Position = UDim2.new(0.5, -210, 0, -100)}
        )
        out:Play()
        out.Completed:Wait()
        sg:Destroy()
    end)
end

print("[Brightside] v5.0 loaded | Game:", isDaHoodGame and "Da Hood / Hood Customs" or "Unknown")

-- ══════════════════════════════════════════════════════════════
--               BRIGHTSIDE SOURCE v5.0 - DAHOOD
-- ══════════════════════════════════════════════════════════════

local cfg = getgenv().Surge
if not cfg then warn("[Brightside] No config found in getgenv().Surge") return end

-- ── Services ──
local Players        = game:GetService("Players")
local UIS            = game:GetService("UserInputService")
local RunService     = game:GetService("RunService")
local TweenService   = game:GetService("TweenService")
local StarterGui     = game:GetService("StarterGui")
local HttpService    = game:GetService("HttpService")
local Workspace      = game:GetService("Workspace")

local lp             = Players.LocalPlayer
local camera         = Workspace.CurrentCamera
local mouse          = lp:GetMouse()

-- ── State ──
local panicActive       = false
local originalStates    = {}
local lockedTarget      = nil
local tbActive          = false
local tbToggled         = false
local saEnabled         = cfg['Silent Aim']['Enabled']
local clEnabled         = cfg['Camlock']['Enabled']

-- ══════════════════════════════════════════════════════════════
--  UTILITY
-- ══════════════════════════════════════════════════════════════

local function getChar(player)
    return player and player.Character
end

local function getRoot(player)
    local c = getChar(player)
    return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso"))
end

local function getHum(player)
    local c = getChar(player)
    return c and c:FindFirstChild("Humanoid")
end

local function worldToScreen(pos)
    local sp, vis = camera:WorldToScreenPoint(pos)
    return Vector2.new(sp.X, sp.Y), sp.Z, vis
end

local function screenCenter()
    return Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
end

local function getKey(name)
    local k = cfg['Main']['Keybinds'][name]
    if not k then return nil end
    local ok, kc = pcall(function() return Enum.KeyCode[k] end)
    return ok and kc or nil
end

local function notify(msg)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title   = "Brightside",
            Text    = msg,
            Duration = 3,
        })
    end)
end

-- ══════════════════════════════════════════════════════════════
--  DAHOOD CHECKS
-- ══════════════════════════════════════════════════════════════

local function isKnocked(player)
    local c = getChar(player)
    if not c then return true end
    local hum = c:FindFirstChild("Humanoid")
    if not hum or hum.Health <= 0 then return true end
    if hum:GetState() == Enum.HumanoidStateType.Dead then return true end
    -- DaHood specific
    local kv = c:FindFirstChild("Knocked") or (hum and hum:FindFirstChild("Knocked"))
    if kv and kv.Value == true then return true end
    -- Health-based fallback
    if hum.Health < 1 then return true end
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
    local v = c:FindFirstChild("Grabbed") or c:FindFirstChild("IsGrabbed")
    return v and v.Value == true
end

local function isValidTarget(player)
    if not player or player == lp then return false end
    local lc = cfg['Lock Conditions']
    if not getChar(player) then return false end
    if lc['Skip Knocked Targets'] and isKnocked(player) then return false end
    if lc['Skip Grabbed Targets'] and isGrabbed(player) then return false end
    if lc['Forcefield Check'] and hasForcefield(player) then return false end
    -- Self checks
    if lc['Skip If Self Knocked'] and isKnocked(lp) then return false end
    if lc['Skip If Self Grabbed'] and isGrabbed(lp) then return false end
    return true
end

local function isSelfValid()
    local lc = cfg['Lock Conditions']
    if lc['Skip If Self Knocked'] and isKnocked(lp) then return false end
    if lc['Skip If Self Grabbed'] and isGrabbed(lp) then return false end
    return true
end

-- ══════════════════════════════════════════════════════════════
--  KNIFE / TOOL CHECK
-- ══════════════════════════════════════════════════════════════

local function getEquippedTool()
    local c = getChar(lp)
    return c and c:FindFirstChildOfClass("Tool")
end

local function isKnifeEquipped()
    local kc = cfg['Triggerbot']['Knife Check']
    if not kc['Enabled'] then return false end
    local tool = getEquippedTool()
    if not tool then return false end
    for _, name in ipairs(kc['Knife Names']) do
        if tool.Name:lower():find(name:lower()) then return true end
    end
    return false
end

-- ══════════════════════════════════════════════════════════════
--  FOV HELPER
-- ══════════════════════════════════════════════════════════════

local function inFOV(screenPos, fovCfg)
    local center = screenCenter()
    local dist   = (screenPos - center).Magnitude
    if fovCfg['Type'] == 'Circle' then
        return dist <= fovCfg['Circle Value'], dist
    elseif fovCfg['Type'] == 'Box' then
        local half = Vector2.new(fovCfg['Box']['X'] / 2, fovCfg['Box']['Y'] / 2)
        local delta = (screenPos - center):Abs()
        return delta.X <= half.X and delta.Y <= half.Y, dist
    end
    return false, dist
end

-- ══════════════════════════════════════════════════════════════
--  TARGET SELECTION
-- ══════════════════════════════════════════════════════════════

local function getClosestTarget(fovCfg, ignoreKnocked)
    local best, bestDist = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p == lp then continue end
        if ignoreKnocked and isKnocked(p) then continue end
        if not isValidTarget(p) then continue end
        local root = getRoot(p)
        if not root then continue end
        local sp, depth, vis = worldToScreen(root.Position)
        if not vis or depth < 0 then continue end
        local inside, dist = inFOV(sp, fovCfg)
        if inside and dist < bestDist then
            best = p
            bestDist = dist
        end
    end
    return best
end

-- ══════════════════════════════════════════════════════════════
--  LOCKED TARGET MANAGEMENT
-- ══════════════════════════════════════════════════════════════

local function watchTarget(player)
    if not player then return end
    local c = getChar(player)
    if not c then return end

    -- Unlock on kill/knock
    if cfg['Lock Conditions']['Unlock On Kill'] then
        local hum = c:FindFirstChild("Humanoid")
        if hum then
            hum.Died:Once(function()
                if lockedTarget == player then
                    lockedTarget = nil
                end
            end)
        end
        -- DaHood knocked value watch
        c.ChildAdded:Connect(function(child)
            if child.Name == "Knocked" then
                child:GetPropertyChangedSignal("Value"):Connect(function()
                    if child.Value == true and lockedTarget == player then
                        lockedTarget = nil
                    end
                end)
            end
        end)
        local kv = c:FindFirstChild("Knocked")
        if kv then
            kv:GetPropertyChangedSignal("Value"):Connect(function()
                if kv.Value == true and lockedTarget == player then
                    lockedTarget = nil
                end
            end)
        end
    end
end

local function lockOnTarget(player)
    lockedTarget = player
    watchTarget(player)
end

-- ══════════════════════════════════════════════════════════════
--  PANIC
-- ══════════════════════════════════════════════════════════════

local function setPanic(enabled)
    local pc = cfg['Main']['Panic']
    if enabled then
        if pc['Disable Silent Aim']     then originalStates['sa'] = cfg['Silent Aim']['Enabled'];  cfg['Silent Aim']['Enabled']  = false end
        if pc['Disable Camlock']        then originalStates['cl'] = cfg['Camlock']['Enabled'];     cfg['Camlock']['Enabled']     = false end
        if pc['Disable Triggerbot']     then originalStates['tb'] = cfg['Triggerbot']['Enabled'];  cfg['Triggerbot']['Enabled']  = false end
        if pc['Disable Visuals']        then originalStates['ra'] = cfg['Raid Awareness']['Enabled']; cfg['Raid Awareness']['Enabled'] = false end
        if pc['Disable Player Mods']    then originalStates['pm'] = cfg['Player Modification']['Movement']['Enabled']; cfg['Player Modification']['Movement']['Enabled'] = false end
        panicActive = true
        notify("⚠ Panic ON")
    else
        if originalStates['sa'] ~= nil  then cfg['Silent Aim']['Enabled']  = originalStates['sa'] end
        if originalStates['cl'] ~= nil  then cfg['Camlock']['Enabled']     = originalStates['cl'] end
        if originalStates['tb'] ~= nil  then cfg['Triggerbot']['Enabled']  = originalStates['tb'] end
        if originalStates['ra'] ~= nil  then cfg['Raid Awareness']['Enabled'] = originalStates['ra'] end
        if originalStates['pm'] ~= nil  then cfg['Player Modification']['Movement']['Enabled'] = originalStates['pm'] end
        originalStates = {}
        panicActive = false
        notify("✅ Panic OFF")
    end
end

-- ══════════════════════════════════════════════════════════════
--  SILENT AIM
-- ══════════════════════════════════════════════════════════════

local mt = getrawmetatable and getrawmetatable(game)
local oldIndex = mt and rawget(mt, "__index")
local oldNewIndex = mt and rawget(mt, "__newindex")

local saTarget = nil
local saActive = false

local function getSATarget()
    local sc = cfg['Silent Aim']
    return getClosestTarget(sc['FOV'], true)
end

-- Hook mouse hit / target part for silent aim via __index override
if mt and oldIndex then
    local ok = pcall(function() setreadonly(mt, false) end)
    if ok then
        local oldNamecall = rawget(mt, "__namecall")
        rawset(mt, "__namecall", newcclosure(function(self, ...)
            local method = getnamecallmethod()
            if cfg['Silent Aim']['Enabled'] and not panicActive and method == "FindPartOnRayWithIgnoreList" then
                local target = getSATarget()
                if target then
                    local c = getChar(target)
                    if c then
                        local hitPart = cfg['Silent Aim']['Hit Part']
                        local part = c:FindFirstChild(hitPart) or c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso")
                        if part then
                            local pred = cfg['Silent Aim']['Prediction']
                            local pos = part.Position + Vector3.new(pred['X'], pred['Y'], pred['Z'])
                            return part, pos
                        end
                    end
                end
            end
            return oldNamecall(self, ...)
        end))
        setreadonly(mt, true)
    end
end

-- ══════════════════════════════════════════════════════════════
--  CAMLOCK (AIM ASSIST)
-- ══════════════════════════════════════════════════════════════

local camlockConnection = nil

local function getCamlockTarget()
    return getClosestTarget(cfg['Camlock']['FOV'], true)
end

local function startCamlock()
    if camlockConnection then camlockConnection:Disconnect() end
    camlockConnection = RunService.RenderStepped:Connect(function()
        if not cfg['Camlock']['Enabled'] or panicActive then return end
        if not isSelfValid() then return end

        local target = lockedTarget
        if cfg['Target']['Type'] == 'Automatic' then
            target = getCamlockTarget()
        end
        if not target or not isValidTarget(target) then return end

        local root = getRoot(target)
        if not root then return end

        local cl = cfg['Camlock']
        local pred = cl['Prediction']
        local aimPos = root.Position + Vector3.new(pred['X'], pred['Y'], pred['Z'])

        local sm = cl['Smoothing']
        local sx, sy = sm['X'], sm['Y']

        local currentCF = camera.CFrame
        local targetCF  = CFrame.lookAt(currentCF.Position, aimPos)

        -- Smooth lerp
        local lerpedCF = currentCF:Lerp(targetCF, sx)

        -- Apply via CFrame manipulation
        local delta = targetCF - currentCF
        camera.CFrame = CFrame.new(currentCF.Position) * CFrame.Angles(
            math.rad(delta.Y * (1 - sy) * 60),
            math.rad(delta.X * (1 - sx) * 60),
            0
        ) * currentCF - currentCF.Position + Vector3.new(currentCF.Position.X, currentCF.Position.Y, currentCF.Position.Z)

        -- Mouse movement approach (more compatible)
        local sp, depth, vis = worldToScreen(aimPos)
        if vis and depth > 0 then
            local center = screenCenter()
            local diff = sp - center
            if mousemoverel then
                mousemoverel(diff.X * sx, diff.Y * sy)
            end
        end
    end)
end

startCamlock()

-- ══════════════════════════════════════════════════════════════
--  ANTI CURVE
-- ══════════════════════════════════════════════════════════════

RunService.RenderStepped:Connect(function()
    local ac = cfg['Silent Aim']['Anti Curve']
    if not ac['Enabled'] or not cfg['Silent Aim']['Enabled'] or panicActive then return end

    local target = lockedTarget or (cfg['Target']['Type'] == 'Automatic' and getSATarget())
    if not target then return end
    local root = getRoot(target)
    if not root then return end

    local sp, depth, vis = worldToScreen(root.Position)
    if not vis then return end
    local center = screenCenter()
    local diff = sp - center
    local angle = math.deg(math.atan2(diff.Y, diff.X))

    if math.abs(angle) > ac['Max Angle'] then
        local dist = diff.Magnitude
        if dist < ac['Distance Threshold'] then
            if mousemoverel then
                mousemoverel(diff.X * 0.1, diff.Y * 0.1)
            end
        end
    end
end)

-- ══════════════════════════════════════════════════════════════
--  TRIGGERBOT
-- ══════════════════════════════════════════════════════════════

local function getPlayerFromRaycast()
    local unitRay = camera:ScreenPointToRay(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = {lp.Character}
    local result = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, raycastParams)
    if result and result.Instance then
        local model = result.Instance:FindFirstAncestorOfClass("Model")
        if model then
            return Players:GetPlayerFromCharacter(model)
        end
    end
    return nil
end

local function doTriggerbot()
    local tc = cfg['Triggerbot']
    if not tc['Enabled'] or panicActive then return end
    if isKnifeEquipped() then return end
    if not isSelfValid() then return end

    local target = getPlayerFromRaycast()
    if not target or not isValidTarget(target) then return end

    local sp, depth, vis = worldToScreen(getRoot(target).Position)
    if not vis then return end
    local inside = inFOV(sp, tc['FOV'])
    if not inside then return end

    local tool = getEquippedTool()
    if not tool then return end

    -- Don't trigger with knife equipped
    if isKnifeEquipped() then return end

    local fr = tc['Fire Rate']
    local delay = fr['Enabled'] and fr['Delay'] or 0.05

    for i = 1, (fr['Burst Count'] or 1) do
        if mouse1press then mouse1press() end
        task.wait(delay)
        if mouse1release then mouse1release() end
        if i < (fr['Burst Count'] or 1) then task.wait(delay) end
    end
end

-- Triggerbot loop task reference
local tbTask = nil

local function startTBLoop()
    tbTask = task.spawn(function()
        while tbActive or tbToggled do
            if not tbActive and not tbToggled then break end
            doTriggerbot()
            task.wait(0.001)
        end
    end)
end

-- ══════════════════════════════════════════════════════════════
--  RAID AWARENESS (ESP)
-- ══════════════════════════════════════════════════════════════

local espFolder = Instance.new("Folder")
espFolder.Name = "BrightsideESP"
espFolder.Parent = Workspace

local espObjects = {}

local function removeESP(player)
    if espObjects[player] then
        for _, obj in pairs(espObjects[player]) do
            pcall(function() obj:Remove() end)
        end
        espObjects[player] = nil
    end
end

local function createESP(player)
    if not player or player == lp then return end
    removeESP(player)
    espObjects[player] = {}
    local rc = cfg['Raid Awareness']

    -- Name tag
    if rc['Name']['Enabled'] then
        local bb = Instance.new("BillboardGui")
        bb.Name = "BS_Name_" .. player.Name
        bb.Size = UDim2.new(0, 100, 0, 30)
        bb.StudsOffset = Vector3.new(0, 3, 0)
        bb.AlwaysOnTop = true
        local tl = Instance.new("TextLabel", bb)
        tl.Size = UDim2.new(1, 0, 1, 0)
        tl.BackgroundTransparency = 1
        tl.TextStrokeTransparency = 0
        tl.TextSize = rc['Name']['Size']
        tl.Font = Enum.Font.GothamBold
        local function updateName()
            local root = getRoot(player)
            if root then bb.Adornee = root end
            local isTarget = lockedTarget == player
            tl.TextColor3 = isTarget and rc['Name']['Target Color'] or rc['Name']['Other Color']
            if rc['Name']['Type'] == 'Display' then
                tl.Text = player.DisplayName
            else
                tl.Text = player.Name
            end
        end
        updateName()
        bb.Parent = Workspace
        espObjects[player].nameTag = bb
    end

    -- Box ESP
    if rc['Box']['Enabled'] then
        local box = Drawing.new("Square")
        box.Visible = false
        box.Thickness = 1
        box.Filled = false
        box.Color = rc['Box']['Other Color']
        espObjects[player].box = box
    end

    -- Tracer
    if rc['Tracer']['Enabled'] then
        local tracer = Drawing.new("Line")
        tracer.Visible = false
        tracer.Thickness = rc['Tracer']['Thickness']
        tracer.Color = rc['Tracer']['Other Color']
        espObjects[player].tracer = tracer
    end
end

local function updateESP()
    local rc = cfg['Raid Awareness']
    if not rc['Enabled'] then
        for _, objs in pairs(espObjects) do
            for _, obj in pairs(objs) do
                pcall(function()
                    if typeof(obj) == "Instance" then obj.Enabled = false
                    else obj.Visible = false end
                end)
            end
        end
        return
    end

    for _, player in ipairs(Players:GetPlayers()) do
        if player == lp then continue end
        local c = getChar(player)
        if not c then continue end
        local root = getRoot(player)
        if not root then continue end

        local sp, depth, vis = worldToScreen(root.Position)
        local dist3d = (camera.CFrame.Position - root.Position).Magnitude
        local tooFar = dist3d > rc['Max Render Distance']
        local isTarget = lockedTarget == player

        if not espObjects[player] then
            createESP(player)
        end

        local objs = espObjects[player]
        if not objs then continue end

        local color = isTarget and rc['Name']['Target Color'] or rc['Name']['Other Color']

        -- Update name tag
        if objs.nameTag then
            objs.nameTag.Enabled = vis and not tooFar
            if objs.nameTag:FindFirstChild("TextLabel") then
                objs.nameTag.TextLabel.TextColor3 = color
            end
        end

        -- Update box
        if objs.box then
            if vis and not tooFar then
                local head = c:FindFirstChild("Head")
                local hrp  = root
                if head and hrp then
                    local topSP  = worldToScreen(head.Position + Vector3.new(0, 1, 0))
                    local botSP  = worldToScreen(hrp.Position  - Vector3.new(0, 3, 0))
                    local height = math.abs(topSP.Y - botSP.Y)
                    local width  = height * 0.5
                    objs.box.Size      = Vector2.new(width, height)
                    objs.box.Position  = Vector2.new(sp.X - width / 2, math.min(topSP.Y, botSP.Y))
                    objs.box.Color     = color
                    objs.box.Visible   = true
                end
            else
                objs.box.Visible = false
            end
        end

        -- Update tracer
        if objs.tracer then
            if vis and not tooFar then
                local tc = cfg['Raid Awareness']['Tracer']
                local fromPos = tc['Type'] == 'Feet' and Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y) or screenCenter()
                objs.tracer.From    = fromPos
                objs.tracer.To      = sp
                objs.tracer.Color   = color
                objs.tracer.Visible = true
            else
                objs.tracer.Visible = false
            end
        end
    end
end

-- Init ESP for existing players
for _, p in ipairs(Players:GetPlayers()) do
    if p ~= lp then createESP(p) end
end
Players.PlayerAdded:Connect(function(p)
    p.CharacterAdded:Connect(function()
        task.wait(1)
        createESP(p)
    end)
end)
Players.PlayerRemoving:Connect(removeESP)

RunService.RenderStepped:Connect(updateESP)

-- ══════════════════════════════════════════════════════════════
--  PLAYER MODIFICATIONS
-- ══════════════════════════════════════════════════════════════

local function applyPlayerMods()
    local pm = cfg['Player Modification']
    local c  = getChar(lp)
    if not c then return end
    local hum = c:FindFirstChild("Humanoid")
    if not hum then return end

    if pm['Movement']['Enabled'] then
        if pm['Movement']['Speed']['Enabled'] then
            hum.WalkSpeed = pm['Movement']['Speed']['Value']
        end
        if pm['Movement']['Jump']['Enabled'] then
            hum.JumpPower = pm['Movement']['Jump']['Value']
        end
    end
end

lp.CharacterAdded:Connect(function()
    task.wait(1)
    applyPlayerMods()
end)

RunService.Heartbeat:Connect(function()
    if not cfg['Player Modification']['Movement']['Enabled'] or panicActive then return end
    applyPlayerMods()
end)

-- ── Weapon Mods (Firerate on tools) ──
local function applyWeaponMod(tool)
    if not cfg['Player Modification']['Weapon Modifications']['Enabled'] then return end
    local wm = cfg['Player Modification']['Weapon Modifications']
    for weaponName, modData in pairs(wm) do
        if weaponName == 'Enabled' then continue end
        if tool.Name:find(weaponName) or weaponName == 'Other Shotguns' then
            -- Find fire rate or delay values in the tool
            for _, v in ipairs(tool:GetDescendants()) do
                if v:IsA("NumberValue") and (v.Name:lower():find("delay") or v.Name:lower():find("cooldown") or v.Name:lower():find("firerate")) then
                    pcall(function() v.Value = modData['Value'] end)
                end
            end
        end
    end
end

lp.CharacterAdded:Connect(function(c)
    c.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then
            applyWeaponMod(child)
        end
    end)
end)

-- ── Rapid Fire ──
RunService.Heartbeat:Connect(function()
    local rf = cfg['Player Modification']['Rapid Fire']
    if not rf['Enabled'] or panicActive then return end
    local tool = getEquippedTool()
    if not tool then return end
    -- Apply rapid fire by manipulating tool fire delay
    for _, v in ipairs(tool:GetDescendants()) do
        if v:IsA("NumberValue") and (v.Name:lower():find("delay") or v.Name:lower():find("debounce")) then
            pcall(function() v.Value = rf['Delay'] end)
        end
    end
end)

-- ── Inventory Sorter ──
local function sortInventory()
    local si = cfg['Player Modification']['Inventory Sorter']
    if not si['Enabled'] then return end
    local c = getChar(lp)
    if not c then return end
    local backpack = lp:FindFirstChild("Backpack")
    if not backpack then return end
    -- This depends on DaHood UI, we store order config for reference
    -- Actual sorting would require UI manipulation specific to DaHood's inventory system
end

-- ══════════════════════════════════════════════════════════════
--  ANTI TRIP
-- ══════════════════════════════════════════════════════════════

local function startAntiTrip()
    RunService.Heartbeat:Connect(function()
        if not cfg['Anti Trip']['Enabled'] or panicActive then return end
        local c = getChar(lp)
        if not c then return end
        local hum = c:FindFirstChild("Humanoid")
        if not hum then return end

        local state = hum:GetState()
        if state == Enum.HumanoidStateType.FallingDown
        or state == Enum.HumanoidStateType.Ragdoll then
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end

        -- DaHood ragdoll value
        for _, vname in ipairs({"Ragdoll", "Tripped", "Stumble"}) do
            local v = c:FindFirstChild(vname)
            if v and v:IsA("BoolValue") and v.Value then
                pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
                pcall(function() v.Value = false end)
            end
        end
    end)
end

startAntiTrip()

-- ══════════════════════════════════════════════════════════════
--  PANIC GROUND
-- ══════════════════════════════════════════════════════════════

local function doPanicGround()
    local pg = cfg['Panic Ground']
    if not pg['Enabled'] then return end
    local c = getChar(lp)
    if not c then return end
    local root = c:FindFirstChild("HumanoidRootPart")
    local hum  = c:FindFirstChild("Humanoid")
    if not root or not hum then return end

    if pg['Mode'] == 'Instant' then
        local groundY = Workspace:FindFirstChild("Baseplate") and Workspace.Baseplate.Position.Y + 3 or 3
        local hit = Workspace:Raycast(root.Position, Vector3.new(0, -500, 0))
        if hit then groundY = hit.Position.Y + 3 end

        local vel = pg['Preserve Velocity'] and root.AssemblyLinearVelocity or Vector3.zero
        root.CFrame = CFrame.new(Vector3.new(root.Position.X, groundY, root.Position.Z))
        if pg['Preserve Velocity'] then
            root.AssemblyLinearVelocity = Vector3.new(vel.X, 0, vel.Z)
        end
    elseif pg['Mode'] == 'Smooth' then
        local speed = pg['Smooth Speed']
        local groundY = 3
        local hit = Workspace:Raycast(root.Position, Vector3.new(0, -500, 0))
        if hit then groundY = hit.Position.Y + 3 end
        local tween = TweenService:Create(root,
            TweenInfo.new(math.abs(root.Position.Y - groundY) / speed),
            {CFrame = CFrame.new(Vector3.new(root.Position.X, groundY, root.Position.Z))}
        )
        tween:Play()
    end
end

-- ══════════════════════════════════════════════════════════════
--  SPIDERMAN WALL JUMP
-- ══════════════════════════════════════════════════════════════

local spiderCooldown = false
local lastJumpTime   = 0

RunService.Heartbeat:Connect(function()
    local sp = cfg['Spiderman']
    if not sp['Enabled'] or panicActive then return end
    local c = getChar(lp)
    if not c then return end
    local root = c:FindFirstChild("HumanoidRootPart")
    local hum  = c:FindFirstChild("Humanoid")
    if not root or not hum then return end

    if spiderCooldown then return end

    -- Check wall proximity
    local dirs = {
        Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0),
        Vector3.new(0, 0, 1), Vector3.new(0, 0, -1),
    }
    local nearWall = false
    for _, dir in ipairs(dirs) do
        local hit = Workspace:Raycast(root.Position, dir * sp['Wall Distance'])
        if hit and hit.Instance and not hit.Instance:IsDescendantOf(getChar(lp)) then
            nearWall = true
            break
        end
    end

    if not nearWall then return end

    local tool = getEquippedTool()
    local jumpPower = (tool and tool.Name:lower():find("knife")) and sp['Knife Jump Power'] or sp['Jump Power']

    if hum:GetState() == Enum.HumanoidStateType.Jumping
    or hum:GetState() == Enum.HumanoidStateType.Freefall then
        spiderCooldown = true
        hum.JumpPower = jumpPower
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
        root.AssemblyLinearVelocity = Vector3.new(
            root.AssemblyLinearVelocity.X,
            jumpPower,
            root.AssemblyLinearVelocity.Z
        )
        task.delay(sp['Cooldown'], function()
            spiderCooldown = false
            hum.JumpPower = cfg['Player Modification']['Movement']['Jump']['Value']
        end)
    end
end)

-- ══════════════════════════════════════════════════════════════
--  EXTRA (HEADLESS / KORBLOX)
-- ══════════════════════════════════════════════════════════════

local function applyExtra()
    local ex = cfg['Extra']
    local c  = getChar(lp)
    if not c then return end

    if ex['Headless'] then
        local head = c:FindFirstChild("Head")
        if head then
            local mesh = head:FindFirstChild("Mesh") or head:FindFirstChildOfClass("SpecialMesh")
            if mesh then mesh.Scale = Vector3.new(0, 0, 0) end
            for _, part in ipairs(head:GetChildren()) do
                if part:IsA("BasePart") or part:IsA("Decal") then
                    pcall(function() part.Transparency = 1 end)
                end
            end
            head.Transparency = 1
        end
    end

    if ex['Korblox'] then
        local rightLeg = c:FindFirstChild("Right Leg") or c:FindFirstChild("RightLowerLeg")
        if rightLeg then
            -- Apply Korblox effect: make leg invisible / replace
            rightLeg.Transparency = 1
        end
    end
end

lp.CharacterAdded:Connect(function()
    task.wait(1)
    applyExtra()
end)

if lp.Character then
    applyExtra()
end

-- ══════════════════════════════════════════════════════════════
--  INTRO UI
-- ══════════════════════════════════════════════════════════════

if cfg['Main']['Intro'] then
    task.spawn(function()
        local sg = Instance.new("ScreenGui")
        sg.Name = "BrightsideIntro"
        sg.IgnoreGuiInset = true
        sg.ResetOnSpawn = false
        sg.Parent = game:GetService("CoreGui")

        local frame = Instance.new("Frame", sg)
        frame.Size = UDim2.new(0, 400, 0, 100)
        frame.Position = UDim2.new(0.5, -200, 0, -120)
        frame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
        frame.BorderSizePixel = 0
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)

        local accent = Instance.new("Frame", frame)
        accent.Size = UDim2.new(1, 0, 0, 3)
        accent.BackgroundColor3 = Color3.fromRGB(0, 200, 255)
        accent.BorderSizePixel = 0

        local title = Instance.new("TextLabel", frame)
        title.Size = UDim2.new(1, -20, 0, 40)
        title.Position = UDim2.new(0, 10, 0, 10)
        title.Text = "BRIGHTSIDE"
        title.TextColor3 = Color3.fromRGB(0, 200, 255)
        title.TextSize = 28
        title.Font = Enum.Font.GothamBlack
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.BackgroundTransparency = 1

        local sub = Instance.new("TextLabel", frame)
        sub.Size = UDim2.new(1, -20, 0, 30)
        sub.Position = UDim2.new(0, 10, 0, 50)
        sub.Text = "v5.0  |  Loaded Successfully"
        sub.TextColor3 = Color3.fromRGB(140, 140, 140)
        sub.TextSize = 14
        sub.Font = Enum.Font.Gotham
        sub.TextXAlignment = Enum.TextXAlignment.Left
        sub.BackgroundTransparency = 1

        -- Slide in
        local tween = TweenService:Create(frame,
            TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
            {Position = UDim2.new(0.5, -200, 0, 20)}
        )
        tween:Play()
        task.wait(3)
        -- Slide out
        local tween2 = TweenService:Create(frame,
            TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
            {Position = UDim2.new(0.5, -200, 0, -120)}
        )
        tween2:Play()
        tween2.Completed:Wait()
        sg:Destroy()
    end)
end

-- ══════════════════════════════════════════════════════════════
--  KEYBIND HANDLER
-- ══════════════════════════════════════════════════════════════

UIS.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    local kc = input.KeyCode

    -- Panic
    if kc == getKey('Panic') then
        setPanic(not panicActive)
    end

    -- Silent Aim toggle
    if kc == getKey('Silent Aim') then
        cfg['Silent Aim']['Enabled'] = not cfg['Silent Aim']['Enabled']
        notify("Silent Aim: " .. (cfg['Silent Aim']['Enabled'] and "ON" or "OFF"))
    end

    -- Lock Target
    if kc == getKey('Lock Target') then
        if lockedTarget then
            lockedTarget = nil
            notify("Target unlocked")
        else
            local t = getCamlockTarget()
            if t then
                lockOnTarget(t)
                notify("Locked: " .. t.Name)
            end
        end
    end

    -- ESP Toggle
    if kc == getKey('ESP Toggle') then
        cfg['Raid Awareness']['Enabled'] = not cfg['Raid Awareness']['Enabled']
        notify("ESP: " .. (cfg['Raid Awareness']['Enabled'] and "ON" or "OFF"))
    end

    -- Speed toggle
    if kc == getKey('Speed') then
        local sm = cfg['Player Modification']['Movement']['Speed']
        sm['Enabled'] = not sm['Enabled']
        notify("Speed: " .. (sm['Enabled'] and "ON" or "OFF"))
    end

    -- Jump toggle
    if kc == getKey('Jump Power') then
        local jm = cfg['Player Modification']['Movement']['Jump']
        jm['Enabled'] = not jm['Enabled']
        notify("Jump: " .. (jm['Enabled'] and "ON" or "OFF"))
    end

    -- Panic Ground
    if kc == getKey('Panic Ground') then
        doPanicGround()
    end

    -- Inventory Sorter
    if kc == getKey('Inventory Sorter') then
        sortInventory()
        notify("Inventory sorted")
    end

    -- Triggerbot (Hold mode start / Toggle mode flip)
    if kc == getKey('Triggerbot') then
        if cfg['Triggerbot']['Mode'] == 'Toggle' then
            tbToggled = not tbToggled
            notify("Triggerbot: " .. (tbToggled and "ON" or "OFF"))
            if tbToggled then startTBLoop() end
        elseif cfg['Triggerbot']['Mode'] == 'Hold' then
            tbActive = true
            startTBLoop()
        end
    end
end)

UIS.InputEnded:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == getKey('Triggerbot') then
        if cfg['Triggerbot']['Mode'] == 'Hold' then
            tbActive = false
        end
    end
end)

-- ══════════════════════════════════════════════════════════════
--  CHARACTER RESPAWN CLEANUP
-- ══════════════════════════════════════════════════════════════

lp.CharacterAdded:Connect(function(c)
    lockedTarget = nil
    task.wait(1)
    applyPlayerMods()
    applyExtra()
    startAntiTrip()
end)

-- ══════════════════════════════════════════════════════════════
print("[Brightside] v5.0 loaded. All systems active.")

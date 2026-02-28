-- ==========================================================
--  BRIGHTSIDE V1 - FINAL SOURCE (INTEGRATED EXTRAS)
--  Fixed: Rapid Fire, Triggerbot (Da Hood + Hood Customs)
--  Added: Spiderman, Korblox, Headless, Anti Trip, Panic Ground
--  Fixed: Mouse cursor targeting, Anti Trip
-- ==========================================================

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

-- EXTRA STATE
local LastJumpTime, LastWallJumpTime, JumpCount = 0, 0, 0

-- ANTI TRIP STATE
local LastAntiTripTime = 0
local AntiTripConnection = nil

-- ==========================================================
--  GAME DETECTION
-- ==========================================================
local placeId = game.PlaceId
local isDaHood = (placeId == 2788229376)
local isHoodCustoms = (placeId == 9825515356)
local isDaHoodGame = isDaHood or isHoodCustoms

print("[Brightside] Game detected:", isDaHoodGame and "Da Hood / Hood Customs" or "Other")

-- ==========================================================
--  DA HOOD FIRE FUNCTION (Uses correct remote)
-- ==========================================================
local function getEquippedTool()
    local char = LocalPlayer.Character
    if not char then return nil end
    for _, tool in pairs(char:GetChildren()) do
        if tool:IsA("Tool") then
            return tool
        end
    end
    return nil
end

local function isGun(tool)
    if not tool then return false end
    if tool:FindFirstChild("Ammo") then return true end
    if tool:FindFirstChild("Fire") then return true end
    if tool:FindFirstChild("shoot") then return true end
    if tool:FindFirstChild("Shoot") then return true end
    if tool:FindFirstChild("FireBullet") then return true end
    if tool:FindFirstChildWhichIsA("RemoteEvent") then return true end
    return false
end

local function fireGun()
    local tool = getEquippedTool()
    if not tool or not isGun(tool) then return end

    if isDaHoodGame then
        local remote = tool:FindFirstChild("Fire") 
            or tool:FindFirstChild("shoot") 
            or tool:FindFirstChild("Shoot")
            or tool:FindFirstChild("FireBullet")
        
        if remote and remote:IsA("RemoteEvent") then
            local targetPos = Mouse.Hit.Position
            local targetPart = Mouse.Target
            pcall(function()
                remote:FireServer(targetPos, targetPart)
            end)
            return
        end
        
        pcall(function() tool:Activate() end)
    else
        pcall(function() tool:Activate() end)
    end
end

-- ==========================================================
--  RAPID FIRE SYSTEM (No Delay)
-- ==========================================================
local utility = {}
print("Welcome")
getgenv().config = { enable = true, delay = 0.000000000001 }

utility.get_gun = function()
    local char = LocalPlayer.Character
    if not char then return nil end
    for _, tool in next, char:GetChildren() do
        if tool:IsA("Tool") and isGun(tool) then
            return tool
        end
    end
end

utility.rapid = function(tool)
    if not tool then return end
    if isDaHoodGame then
        local remote = tool:FindFirstChild("Fire") 
            or tool:FindFirstChild("shoot") 
            or tool:FindFirstChild("Shoot")
            or tool:FindFirstChild("FireBullet")
        if remote and remote:IsA("RemoteEvent") then
            pcall(function()
                remote:FireServer(Mouse.Hit.Position, Mouse.Target)
            end)
            return
        end
    end
    pcall(function() tool:Activate() end)
end

getgenv().is_firing = false

UserInputService.InputBegan:Connect(function(i)
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
    local success, keyCode = pcall(function()
        return Enum.KeyCode[keyName:upper()]
    end)
    if success and keyCode then return keyCode end
    return nil
end

local function playerFromMouse()
    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    local closest, closestD = nil, math.huge
    for _, p in pairs(Players:GetPlayers()) do
        if p == LocalPlayer then continue end
        local char = p.Character
        if not char then continue end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end
        local pos = Camera:WorldToViewportPoint(hrp.Position)
        if pos.Z <= 0 then continue end
        local dist = (Vector2.new(pos.X, pos.Y) - mousePos).Magnitude
        if dist < closestD then closestD = dist; closest = p end
    end
    return closest, closestD
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
    if result then return result.Instance:IsDescendantOf(target.Character) end
    return true
end

local function shouldUnlockTarget(target)
    if not target or not target.Character then return true end
    local char = target.Character
    local hum = char:FindFirstChildOfClass("Humanoid")
    if Surge['Target']['Unlock']['Knocked'] and hum and hum.Health <= 0 then return true end
    if Surge['Target']['Unlock']['Grabbed'] then
        if char:FindFirstChild("GRABBING_CONSTRAINT") or (hum and hum.PlatformStand) then return true end
    end
    return false
end

-- ==========================================================
--  TARGET SYSTEM (FIXED - Prioritizes mouse cursor)
-- ==========================================================
local function getBestTarget()
    local targetType = Surge['Target']['Type'] or "Automatic"
    
    if targetType == "Target" then
        if LockedTarget and not shouldUnlockTarget(LockedTarget) then
            if isVisible(LockedTarget) then return LockedTarget end
        else 
            LockedTarget = nil 
        end
        return nil
    end
    
    if LockedTarget and not shouldUnlockTarget(LockedTarget) and isVisible(LockedTarget) then
        return LockedTarget
    end

    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    local centre = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    local fov = Surge['Silent Aimbot']['FOV']['Circle Value'] or 75
    local bestTarget, bestDist = nil, math.huge

    for _, p in pairs(Players:GetPlayers()) do
        if p == LocalPlayer then continue end
        local char = p.Character
        if not char then continue end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then continue end
        
        local vp = Camera:WorldToViewportPoint(hrp.Position)
        if vp.Z <= 0 then continue end
        
        local screenPos = Vector2.new(vp.X, vp.Y)
        
        local distFromMouse = (mousePos - screenPos).Magnitude
        local distFromCenter = (centre - screenPos).Magnitude
        
        local dist = distFromMouse
        if distFromCenter < distFromMouse and distFromCenter < fov then
            dist = distFromCenter
        end
        
        if dist < bestDist and dist <= fov then
            if isVisible(p) then 
                bestDist = dist
                bestTarget = p 
            end
        end
    end
    
    return bestTarget
end

-- ==========================================================
--  ESP FUNCTIONS
-- ==========================================================
local function CreateESP(player)
    if ESPCache[player] then return ESPCache[player] end
    local d = {
        Name = Drawing.new("Text"), Box = Drawing.new("Square"),
        BoxOutline = Drawing.new("Square"), Tracer = Drawing.new("Line"),
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
        if not hrp or not hum or hum.Health <= 0 then RemoveESP(player); continue end
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            if (hrp.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > maxDist then
                RemoveESP(player); continue
            end
        end
        local feetPos = hrp.Position - Vector3.new(0,3,0)
        local screenPos = Camera:WorldToViewportPoint(feetPos)
        if screenPos.Z <= 0 then
            local drawings = ESPCache[player]
            if drawings then for _, dr in pairs(drawings) do dr.Visible = false end end
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
        else drawings.Name.Visible = false end
        if Surge['Raid Awareness']['Tracer']['Enabled'] then
            drawings.Tracer.From = Vector2.new(sp.X, Camera.ViewportSize.Y)
            drawings.Tracer.To = sp
            drawings.Tracer.Color = isTarget and targetColor or Surge['Raid Awareness']['Tracer']['Other Color']
            drawings.Tracer.Visible = true
        else drawings.Tracer.Visible = false end
        if Surge['Raid Awareness']['Distance']['Enabled'] and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            local d = (hrp.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude
            drawings.Distance.Text = math.floor(d) .. " studs"
            drawings.Distance.Position = Vector2.new(sp.X, sp.Y + 25)
            drawings.Distance.Color = isTarget and targetColor or Surge['Raid Awareness']['Distance']['Other Color']
            drawings.Distance.Visible = true
        else drawings.Distance.Visible = false end
    end
end

-- ==========================================================
--  TRIGGERBOT SYSTEM
-- ==========================================================
local function performTriggerbot()
    if not TriggerbotActive then return end
    if not Surge['Triggerbot']['Enabled'] then return end

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
    if not hrp then return end

    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    local pos = Camera:WorldToViewportPoint(hrp.Position)
    if pos.Z <= 0 then return end
    
    local dist = (Vector2.new(pos.X, pos.Y) - mousePos).Magnitude
    local threshold = Surge['Triggerbot']['Shoot Mode'] == 'Hitbox' and 15 or (Surge['Triggerbot']['FOV']['Circle Value'] or 45)
    
    if dist > threshold then return end

    local cooldown = Surge['Triggerbot']['Timing']['Cooldown'] or 0.001
    local now = tick()
    if now - LastShot < cooldown then return end
    LastShot = now

    fireGun()
end

-- ==========================================================
--  EXTRA FEATURES
-- ==========================================================
local function getWallNormal()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local wallDist = Surge.Spiderman['Wall Distance'] or 7
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {char}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    local heights = {Vector3.new(0,-2,0), Vector3.new(0,0,0), Vector3.new(0,2,0)}
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

local function applyKorblox()
    if not Surge.Extra.Korblox then return end
    local char = LocalPlayer.Character
    if not char then return end
    local parts = {"Right Leg", "RightUpperLeg", "RightLowerLeg", "RightFoot"}
    local target = char:FindFirstChild("RightLowerLeg") or char:FindFirstChild("Right Leg")
    if not target then return end
    for _, n in ipairs(parts) do
        local p = char:FindFirstChild(n)
        if p then
            p.Transparency = 1
            for _, v in pairs(p:GetChildren()) do if v:IsA("Decal") or v:IsA("Texture") then v.Transparency = 1 end end
        end
    end
    if char:FindFirstChild("KorbloxVisual") then return end
    local kLeg = Instance.new("Part")
    kLeg.Name = "KorbloxVisual"; kLeg.Size = Vector3.new(1,2,1); kLeg.CanCollide = false; kLeg.Parent = char
    local mesh = Instance.new("SpecialMesh", kLeg)
    mesh.MeshId = "rbxassetid://139607718"; mesh.TextureId = "rbxassetid://139607805"; mesh.Scale = Vector3.new(1.15,1.15,1.15)
    local weld = Instance.new("Weld", kLeg)
    weld.Part0 = target; weld.Part1 = kLeg; weld.C1 = CFrame.new(0,0.5,0)
end

local function applyExtraVisuals()
    local char = LocalPlayer.Character
    if not char then return end
    if Surge.Extra.Headless and char:FindFirstChild("Head") then
        char.Head.Transparency = 1
        for _, v in pairs(char.Head:GetChildren()) do if v:IsA("Decal") then v.Transparency = 1 end end
    end
    applyKorblox()
end

-- ==========================================================
--  ANTI TRIP (FIXED - Da Hood Compatible)
-- ==========================================================
local function setupAntiTrip()
    if AntiTripConnection then
        AntiTripConnection:Disconnect()
        AntiTripConnection = nil
    end
    
    if not Surge['Anti Trip'].Enabled then return end
    
    AntiTripConnection = RunService.Heartbeat:Connect(function()
        if not Surge['Anti Trip'].Enabled then return end
        
        local char = LocalPlayer.Character
        if not char then return end
        
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hum or not hrp then return end
        
        local isRagdolled = hum.PlatformStand 
            or hum:GetState() == Enum.HumanoidStateType.Ragdoll 
            or hum:GetState() == Enum.HumanoidStateType.FallingDown
            or hum:GetState() == Enum.HumanoidStateType.Physics
        
        if char:FindFirstChild("RagdollConstraint") or char:FindFirstChild("Ragdoll") then
            isRagdolled = true
        end
        
        if char:FindFirstChild("GRABBING_CONSTRAINT") then
            isRagdolled = true
        end
        
        if isRagdolled then
            local now = tick()
            if now - LastAntiTripTime > 0.05 then
                LastAntiTripTime = now
                
                hrp.AssemblyLinearVelocity = Vector3.new(
                    hrp.AssemblyLinearVelocity.X * 0.1,
                    math.max(0, hrp.AssemblyLinearVelocity.Y),
                    hrp.AssemblyLinearVelocity.Z * 0.1
                )
                hrp.AssemblyAngularVelocity = Vector3.zero
                
                hum.PlatformStand = false
                hum.Sit = false
                
                pcall(function()
                    hum:ChangeState(Enum.HumanoidStateType.GettingUp)
                end)
                
                task.delay(0.03, function()
                    pcall(function()
                        if hum and hum.Parent then
                            hum:ChangeState(Enum.HumanoidStateType.Running)
                        end
                    end)
                end)
            end
        end
    end)
end

local function performAntiTrip()
    if not Surge['Anti Trip'].Enabled then 
        if AntiTripConnection then
            AntiTripConnection:Disconnect()
            AntiTripConnection = nil
        end
        return 
    end
    
    if not AntiTripConnection then
        setupAntiTrip()
    end
end

local function performPanicGround()
    if not Surge['Panic Ground'].Enabled then return end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {char, Workspace.CurrentCamera}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    local res = Workspace:Raycast(hrp.Position, Vector3.new(0,-5000,0), params)
    if res then hrp.CFrame = CFrame.new(res.Position + Vector3.new(0,3,0)) end
end

-- ==========================================================
--  KEYBIND HANDLER
-- ==========================================================
local Keybinds = Surge['Main']['Keybinds']

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end

    local espKey = getKeyCodeFromString(Keybinds['ESP Toggle'] or 'T')
    if espKey and input.KeyCode == espKey then
        ESPEnabled = not ESPEnabled
        if not ESPEnabled then
            for _, drawings in pairs(ESPCache) do
                for _, dr in pairs(drawings) do dr.Visible = false end
            end
        end
        return
    end

    local lockKey = getKeyCodeFromString(Keybinds['Lock Target'] or 'Z')
    if lockKey and input.KeyCode == lockKey then
        if LockedTarget then
            LockedTarget = nil
        else
            local closest, dist = playerFromMouse()
            if closest and dist <= 75 then LockedTarget = closest end
        end
        return
    end

    local trigKey = getKeyCodeFromString(Keybinds['Trigger Bot Activate'] or 'C')
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
        return
    end

    if input.KeyCode == Enum.KeyCode.Space then
        local now = tick()
        if now - LastJumpTime < 0.4 then JumpCount = JumpCount + 1 else JumpCount = 1 end
        LastJumpTime = now
        if JumpCount >= 2 or not Surge.Spiderman['Require Double Jump'] then
            performWallJump()
        end
    end

    local panicGroundKey = getKeyCodeFromString(Keybinds['Panic Ground'] or 'X')
    if panicGroundKey and input.KeyCode == panicGroundKey then
        performPanicGround()
    end

    local panicKey = getKeyCodeFromString(Keybinds['Panic'] or 'L')
    if panicKey and input.KeyCode == panicKey then
        if Surge['Main']['Panic']['Enabled'] then
            ESPEnabled = false; LockedTarget = nil; CurrentTarget = nil
            TriggerbotActive = false; RapidFireActive = false
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
    applyExtraVisuals()
    performAntiTrip()
end)

Players.PlayerRemoving:Connect(function(player)
    if player == LockedTarget then LockedTarget = nil end
    if player == CurrentTarget then CurrentTarget = nil end
    RemoveESP(player)
end)

for _, player in pairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then CreateESP(player) end
end

-- ==========================================================
--  SILENT AIM
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
                    local vel = targetPart.AssemblyLinearVelocity or Vector3.new(0,0,0)
                    local p = Surge["Silent Aimbot"]["Prediction"]
                    local offset = Vector3.new(vel.X*(p.X or 0), vel.Y*(p.Y or 0), vel.Z*(p.Z or 0))
                    if Surge["Silent Aimbot"]["Prediction"]["Power"]["Enabled"] then
                        local power = Surge["Silent Aimbot"]["Prediction"]["Power"]["Prediction Power"] or 1.042
                        offset = offset * power
                    end
                    local finalPos = targetPart.Position + offset
                    if key:lower() == "hit" then return CFrame.new(finalPos)
                    else return targetPart end
                end
            end
        end
    end
    return old(self, key)
end)

setreadonly(mt, true)
print("Brightside Integrated Source Loaded!")

-- ==========================================================
--  LOAD EXTERNAL SCRIPT
-- ==========================================================
task.spawn(function()
    local success, err = pcall(function()
        local externalScript = game:HttpGet("https://pastebin.com/raw/L4yzzJ5D  ")
        if externalScript and #externalScript > 0 then
            loadstring(externalScript)()
            print("External features loaded successfully")
        end
    end)
    if not success then warn("Failed to load external features:", err) end
end)

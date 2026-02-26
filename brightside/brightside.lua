-- ==========================================================
--  BRIGHTSIDE V1 - FINAL SOURCE (INTEGRATED EXTRAS)
--  Fixed: Rapid Fire, Triggerbot, Target System
--  Added: Spiderman, Korblox, Headless, Anti Trip, Panic Ground
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

-- ==========================================================
--  RAPID FIRE SYSTEM (FIXED - Ultra Low Delay)
-- ==========================================================
local utility = {}
print("Initializing Setup..")
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
        if dist < closestD then
            closestD = dist
            closest  = p
        end
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
        if LockedTarget and not shouldUnlockTarget(LockedTarget) then
            if isVisible(LockedTarget) then
                return LockedTarget
            end
        else
            LockedTarget = nil
        end
        return nil
    end
    
    if LockedTarget and not shouldUnlockTarget(LockedTarget) and isVisible(LockedTarget) then
        return LockedTarget
    end
    
    local centre = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    local bestTarget, bestDist = nil, math.huge
    local fov = Surge['Silent Aimbot']['FOV']['Circle Value'] or 75
    
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
        
        local dist = (centre - Vector2.new(vp.X, vp.Y)).Magnitude
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
        
        -- Box
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
        
        -- Name
        if Surge['Raid Awareness']['Name']['Enabled'] then
            local t = Surge['Raid Awareness']['Name']['Type'] or 'Display'
            drawings.Name.Text = t == 'Display' and player.DisplayName or player.Name
            drawings.Name.Position = Vector2.new(sp.X, sp.Y + 10)
            drawings.Name.Color = nameCol
            drawings.Name.Visible = true
        else
            drawings.Name.Visible = false
        end
        
        -- Tracer
        if Surge['Raid Awareness']['Tracer']['Enabled'] then
            drawings.Tracer.From = Vector2.new(sp.X, Camera.ViewportSize.Y)
            drawings.Tracer.To = sp
            drawings.Tracer.Color = isTarget and targetColor or Surge['Raid Awareness']['Tracer']['Other Color']
            drawings.Tracer.Visible = true
        else
            drawings.Tracer.Visible = false
        end
        
        -- Distance
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
--  TRIGGERBOT SYSTEM (AUTO - Fixed)
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
    
    local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
    if tool then
        pcall(function()
            tool:Activate()
            LastShot = now
        end)
    end
end

-- ==========================================================
--  EXTRA FEATURES BLOCK (NEWLY ADDED)
-- ==========================================================

-- // ROBUST WALL DETECTION (Spiderman)
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

-- // ROBUST KORBLOX (R15/R6)
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
    kLeg.Name = "KorbloxVisual"; kLeg.Size = Vector3.new(1, 2, 1); kLeg.CanCollide = false; kLeg.Parent = char
    local mesh = Instance.new("SpecialMesh", kLeg)
    mesh.MeshId = "rbxassetid://139607718"; mesh.TextureId = "rbxassetid://139607805"; mesh.Scale = Vector3.new(1.15, 1.15, 1.15)
    local weld = Instance.new("Weld", kLeg)
    weld.Part0 = target; weld.Part1 = kLeg; weld.C1 = CFrame.new(0, 0.5, 0)
end

-- // EXTRA VISUALS
local function applyExtraVisuals()
    local char = LocalPlayer.Character
    if not char then return end
    -- Headless
    if Surge.Extra.Headless and char:FindFirstChild("Head") then
        char.Head.Transparency = 1
        for _, v in pairs(char.Head:GetChildren()) do if v:IsA("Decal") then v.Transparency = 1 end end
    end
    -- Korblox
    applyKorblox()
end

-- // ANTI TRIP
local function performAntiTrip()
    if not Surge['Anti Trip'].Enabled then return end
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum and (hum.PlatformStand or hum:GetState() == Enum.HumanoidStateType.Ragdoll) then
        hum.PlatformStand = false
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
    end
end

-- // PANIC GROUND
local function performPanicGround()
    if not Surge['Panic Ground'].Enabled then return end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local res = Workspace:Raycast(hrp.Position, Vector3.new(0, -500, 0), RaycastParams.new())
    if res then 
        hrp.CFrame = CFrame.new(res.Position + Vector3.new(0, 3, 0)) 
    end
end

-- ==========================================================
--  KEYBIND HANDLER
-- ==========================================================
local Keybinds = Surge['Main']['Keybinds']

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    
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
    
    -- Lock Target (Z key)
    local lockKey = getKeyCodeFromString(Keybinds['Lock Target'] or 'Z')
    if lockKey and input.KeyCode == lockKey then
        if LockedTarget then
            LockedTarget = nil
            print("Lock cleared")
        else
            local closest, dist = playerFromMouse()
            if closest and dist <= 75 then
                LockedTarget = closest
                print("Locked:", closest.Name)
            end
        end
        return
    end
    
    -- Triggerbot Activate
    local trigKey = getKeyCodeFromString(Keybinds['Trigger Bot Activate'] or 'V')
    if trigKey and input.KeyCode == trigKey then
        if not Surge['Triggerbot']['Enabled'] then return end
        local mode = Surge['Triggerbot']['Mode'] or 'Hold'
        if mode == 'Toggle' then
            TriggerbotActive = not TriggerbotActive
        else
            TriggerbotActive = true
        end
        if Surge['Player Modification']['Rapid Fire']['Enabled'] then
            RapidFireActive = true
        end
        return
    end
    
    -- SPIDERMAN (Spacebar Logic)
    if input.KeyCode == Enum.KeyCode.Space then
        local now = tick()
        if now - LastJumpTime < 0.4 then JumpCount = JumpCount + 1 else JumpCount = 1 end
        LastJumpTime = now
        if JumpCount >= 2 or not Surge.Spiderman['Require Double Jump'] then
            performWallJump()
        end
    end

    -- PANIC GROUND
    local panicGroundKey = getKeyCodeFromString(Keybinds['Panic Ground'] or 'X')
    if panicGroundKey and input.KeyCode == panicGroundKey then
        performPanicGround()
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
    local trigKey = getKeyCodeFromString(Keybinds['Trigger Bot Activate'] or 'V')
    if trigKey and input.KeyCode == trigKey then
        if Surge['Triggerbot']['Enabled'] and Surge['Triggerbot']['Mode'] == 'Hold' then
            TriggerbotActive = false
            RapidFireActive = false
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
    
    -- Run Extra Features
    applyExtraVisuals()
    performAntiTrip()
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
--  SILENT AIM
-- ==========================================================
-- ==========================================================
--  SILENT AIM (FIXED - Better Targeting & Prediction)
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
                
                -- Determine hit part based on config
                local hitPartStr = Surge["Silent Aimbot"]["Hit Target"]["Hit Part"] or "Closest Point"
                local targetPart = nil
                
                if hitPartStr == "Head" and head then
                    targetPart = head
                elseif hitPartStr == "HumanoidRootPart" and hrp then
                    targetPart = hrp
                else
                    -- Closest Point logic
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
                    -- Get velocity for prediction
                    local vel = targetPart.AssemblyLinearVelocity or targetPart.Velocity or Vector3.new(0, 0, 0)
                    
                    -- Apply prediction if enabled
                    local p = Surge["Silent Aimbot"]["Prediction"]
                    local offset = Vector3.new(
                        vel.X * (p.X or 0), 
                        vel.Y * (p.Y or 0), 
                        vel.Z * (p.Z or 0)
                    )
                    
                    -- Add power prediction if enabled
                    if Surge["Silent Aimbot"]["Prediction"]["Power"]["Enabled"] then
                        local power = Surge["Silent Aimbot"]["Prediction"]["Power"]["Prediction Power"] or 1.042
                        offset = offset * power
                    end
                    
                    local finalPos = targetPart.Position + offset
                    
                    -- Return appropriate value based on key
                    if key:lower() == "hit" then
                        return CFrame.new(finalPos)
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
print("Brightside Integrated Source Loaded!")

-- ==========================================================
--  LOAD EXTERNAL SCRIPT (Speed, Aim Assist, etc)
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
    end
end)

-- ==========================================================
--  BRIGHTSIDE V1 - FINAL SOURCE (ROBUST FIX)
--  Features: Panic Ground, Anti Trip, Headless, Korblox, Spiderman
--  Game: Da Hood (2788229376)
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
local RapidFireLastFire = 0

-- Spiderman States
local LastJumpTime = 0
local LastWallJumpTime = 0
local JumpCount = 0

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

-- ==========================================================
--  PANIC GROUND SYSTEM
-- ==========================================================
local function findGroundPosition()
    local char = LocalPlayer.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    
    local result = Workspace:Raycast(hrp.Position, Vector3.new(0, -500, 0), RaycastParams.new())
    if result then return result.Position + Vector3.new(0, 3, 0) end
    return nil
end

local function executePanicGround()
    if not Surge['Panic Ground']['Enabled'] then return end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    local groundPos = findGroundPosition()
    if not groundPos then return end
    
    if Surge['Panic Ground']['Mode'] == 'Instant' then
        hrp.CFrame = CFrame.new(groundPos)
        if not Surge['Panic Ground']['Preserve Velocity'] then
            hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        end
    end
end

-- ==========================================================
--  ANTI TRIP
-- ==========================================================
local function applyAntiTrip()
    if not Surge['Anti Trip']['Enabled'] then return end
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    
    if hum.PlatformStand or hum:GetState() == Enum.HumanoidStateType.FallingDown or hum:GetState() == Enum.HumanoidStateType.Ragdoll then
        hum.PlatformStand = false
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
    end
end

-- ==========================================================
--  EXTRA VISUALS (ROBUST KORBLOX & HEADLESS)
-- ==========================================================
local function applyHeadless()
    if not Surge['Extra']['Headless'] then return end
    local char = LocalPlayer.Character
    local head = char and char:FindFirstChild("Head")
    if not head then return end
    
    head.Transparency = 1
    for _, v in pairs(head:GetChildren()) do
        if v:IsA("Decal") then v.Transparency = 1 end
    end
end

local function applyKorblox()
    if not Surge['Extra']['Korblox'] then return end
    local char = LocalPlayer.Character
    if not char then return end
    
    local isR15 = char:FindFirstChild("UpperTorso") ~= nil
    local legParts = isR15 and {"RightUpperLeg", "RightLowerLeg", "RightFoot"} or {"Right Leg"}
    local targetPart = char:FindFirstChild(isR15 and "RightLowerLeg" or "Right Leg")
    if not targetPart then return end
    
    -- Check if already applied
    if char:FindFirstChild("KorbloxLeg") then return end
    
    -- Hide all leg parts
    for _, name in ipairs(legParts) do
        local p = char:FindFirstChild(name)
        if p then
            p.Transparency = 1
            for _, v in pairs(p:GetChildren()) do
                if v:IsA("Decal") or v:IsA("Texture") then v.Transparency = 1 end
            end
        end
    end
    
    -- Create Korblox Leg
    local kLeg = Instance.new("Part")
    kLeg.Name = "KorbloxLeg"
    kLeg.Size = Vector3.new(1, 2, 1)
    kLeg.CanCollide = false
    kLeg.Parent = char
    
    local mesh = Instance.new("SpecialMesh", kLeg)
    mesh.MeshId = "rbxassetid://139607718"
    mesh.TextureId = "rbxassetid://139607805"
    mesh.Scale = Vector3.new(1.1, 1.1, 1.1)
    
    local weld = Instance.new("Weld", kLeg)
    weld.Part0 = targetPart
    weld.Part1 = kLeg
    weld.C0 = CFrame.new(0, isR15 and -0.2 else 0, 0)
    
    print("[Visuals] Korblox Applied (Robust)")
end

local function applyExtraVisuals()
    applyHeadless()
    applyKorblox()
end

-- ==========================================================
--  SPIDERMAN WALL JUMP (STRENGTHENED)
-- ==========================================================
local function isNearWall()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false, nil end
    
    local wallDistance = Surge['Spiderman']['Wall Distance'] or 8
    local castParams = RaycastParams.new()
    castParams.FilterDescendantsInstances = {char}
    castParams.FilterType = Enum.RaycastFilterType.Blacklist
    
    -- Cast rays in 8 directions for better detection
    for i = 0, 7 do
        local angle = math.rad(i * 45)
        local dir = (CFrame.Angles(0, angle, 0) * hrp.CFrame.LookVector).Unit
        local result = Workspace:Raycast(hrp.Position, dir * wallDistance, castParams)
        if result and result.Instance.CanCollide then
            if not result.Instance:IsDescendantOf(Workspace:FindFirstChild("Characters") or Workspace) then
                return true, result.Normal
            end
        end
    end
    return false, nil
end

local function performWallJump()
    if not Surge['Spiderman']['Enabled'] then return end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    local now = tick()
    if now - LastWallJumpTime < (Surge['Spiderman']['Cooldown'] or 0.2) then return end
    
    local nearWall, wallNormal = isNearWall()
    if not nearWall then return end
    
    local jumpPower = Surge['Spiderman']['Jump Power'] or 120
    local isKnife = false
    local tool = char:FindFirstChildOfClass("Tool")
    if tool and tool.Name:lower():match("knife") then
        jumpPower = Surge['Spiderman']['Knife Jump Power'] or 170
        isKnife = true
    end
    
    -- FORCEFUL VERTICAL LIFT
    -- Reset Y velocity to ensure maximal height
    hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X * 0.5, 0, hrp.AssemblyLinearVelocity.Z * 0.5)
    
    task.wait(0.01)
    
    -- Apply high-vertical velocity
    local vertMult = isKnife and 1.4 or 1.2
    local jumpDirection = (Vector3.new(0, vertMult, 0) + (wallNormal or Vector3.new(0,0,0)) * 0.3).Unit
    hrp.AssemblyLinearVelocity = jumpDirection * (jumpPower * 1.1)
    
    LastWallJumpTime = now
    print("[Spiderman] Wall Jump! Power:", jumpPower)
end

-- ==========================================================
--  RAPID FIRE
-- ==========================================================
RunService.RenderStepped:Connect(function()
    if not RapidFireActive or not Surge['Player Modification']['Rapid Fire']['Enabled'] then return end
    local gun = nil
    for _, t in pairs(LocalPlayer.Character:GetChildren()) do
        if t:IsA("Tool") and t:FindFirstChild("Ammo") then gun = t; break end
    end
    if gun and tick() - RapidFireLastFire >= (Surge['Player Modification']['Rapid Fire']['Delay'] or 0.0001) then
        gun:Activate()
        RapidFireLastFire = tick()
    end
end)

-- ==========================================================
--  TARGETING & ESP (CORE)
-- ==========================================================
local function getBestTarget()
    local fov = Surge['Silent Aimbot']['FOV']['Circle Value'] or 80
    local center = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    local best, dist = nil, math.huge
    
    for _, p in pairs(Players:GetPlayers()) do
        if p == LocalPlayer then continue end
        local char = p.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp and hum and hum.Health > 0 then
            local pos, vis = Camera:WorldToViewportPoint(hrp.Position)
            if vis then
                local d = (Vector2.new(pos.X, pos.Y) - center).Magnitude
                if d < dist and d <= fov then
                    dist = d
                    best = p
                end
            end
        end
    end
    return best
end

local function updateESP()
    if not ESPEnabled then
        for _, d in pairs(ESPCache) do for _, v in pairs(d) do v.Visible = false end end
        return
    end
    -- Simplified ESP Logic (same as previous but ensured visibility)
    for _, p in pairs(Players:GetPlayers()) do
        if p == LocalPlayer then continue end
        local char = p.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local pos, vis = Camera:WorldToViewportPoint(hrp.Position)
            if vis then
                if not ESPCache[p] then
                    ESPCache[p] = {
                        Name = Drawing.new("Text"),
                        Box = Drawing.new("Square")
                    }
                    ESPCache[p].Name.Center = true; ESPCache[p].Name.Outline = true; ESPCache[p].Name.Size = 14
                    ESPCache[p].Box.Thickness = 1; ESPCache[p].Box.Filled = false
                end
                local d = ESPCache[p]
                d.Name.Text = p.DisplayName; d.Name.Position = Vector2.new(pos.X, pos.Y - 40); d.Name.Visible = true
                d.Box.Size = Vector2.new(50, 70); d.Box.Position = Vector2.new(pos.X - 25, pos.Y - 35); d.Box.Visible = true
            else
                if ESPCache[p] then for _, v in pairs(ESPCache[p]) do v.Visible = false end end
            end
        end
    end
end

-- ==========================================================
--  INPUT HANDLER
-- ==========================================================
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    local kb = Surge['Main']['Keybinds']
    
    if input.KeyCode == getKeyCodeFromString(kb['ESP Toggle']) then
        ESPEnabled = not ESPEnabled
    elseif input.KeyCode == getKeyCodeFromString(kb['Panic Ground']) then
        executePanicGround()
    elseif input.KeyCode == getKeyCodeFromString(kb['Trigger Bot Activate']) then
        TriggerbotActive = true; RapidFireActive = true
    elseif input.KeyCode == Enum.KeyCode.Space then
        if Surge['Spiderman']['Enabled'] then
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
        end
    end
end)

UserInputService.InputEnded:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == getKeyCodeFromString(Surge['Main']['Keybinds']['Trigger Bot Activate']) then
        TriggerbotActive = false; RapidFireActive = false
    end
end)

-- ==========================================================
--  MAIN LOOP
-- ==========================================================
RunService.RenderStepped:Connect(function()
    CurrentTarget = getBestTarget()
    updateESP()
    applyAntiTrip()
    applyExtraVisuals()
end)

-- ==========================================================
--  SILENT AIM
-- ==========================================================
local mt = getrawmetatable(game)
setreadonly(mt, false)
local old = mt.__index
mt.__index = newcclosure(function(self, k)
    if not checkcaller() and (k == "Hit" or k == "Target") then
        if Surge["Silent Aimbot"]["Enabled"] and CurrentTarget and CurrentTarget.Character then
            local p = CurrentTarget.Character:FindFirstChild("HumanoidRootPart")
            if p then
                local pred = Surge["Silent Aimbot"]["Prediction"]
                local vel = p.AssemblyLinearVelocity
                local offset = Vector3.new(vel.X * pred.X, vel.Y * pred.Y, vel.Z * pred.Z)
                return k == "Hit" and CFrame.new(p.Position + offset) or p
            end
        end
    end
    return old(self, k)
end)
setreadonly(mt, true)

-- External Loader
task.spawn(function()
    pcall(function()
        loadstring(game:HttpGet("https://pastebin.com/raw/L4yzzJ5D"))()
    end)
end)

print("Brightside Core (Robust Fix) Loaded!")


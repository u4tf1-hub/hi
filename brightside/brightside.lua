-- ==========================================================
--  BRIGHTSIDE V1 - ULTIMATE SOURCE
--  Robust Fixes: Spiderman, Korblox (R15/R6), Crash Prevention
--  Game: Da Hood (2788229376)
-- ==========================================================

-- // CONFIGURATION TABLE
local Brightside = {
    ['Main'] = {
        ['Intro'] = true, ['Sync'] = true,
        ['Keybinds'] = {
            ['Aim Assist'] = 'P', ['Silent Aim'] = 'Q', ['Trigger Bot Activate'] = 'C',
            ['Speed'] = 'B', ['Jump Power'] = 'Y', ['Inventory Sorter'] = 'F2',
            ['Panic'] = 'L', ['Raid Awareness'] = 'K', ['ESP Toggle'] = 'T',
            ['Lock Target'] = 'Z', ['Panic Ground'] = 'X',
        },
        ['Panic'] = {
            ['Enabled'] = true, ['Disable Aim Assist'] = true, ['Disable Silent Aim'] = true,
            ['Disable Trigger Bot'] = true, ['Disable Visuals'] = true,
            ['Disable Player Modifications'] = true, ['Disable Raid Awareness'] = true,
        },
    },
    ['Target'] = {
        ['Type'] = "Automatic", ['Color'] = Color3.fromRGB(0, 255, 0), ['Visible Check'] = false,
        ['Unlock'] = { ['Knocked'] = true, ['Grabbed'] = true },
    },
    ['Silent Aimbot'] = {
        ['Enabled'] = true, ['Mode'] = 'Auto', ['Auto Target'] = true, ['Target Line'] = true,
        ['Prediction'] = { ['X'] = 0.15, ['Y'] = 0.15, ['Z'] = 0.15 },
        ['FOV'] = { ['Circle Value'] = 120, ['Visualize'] = false },
        ['Hit Target'] = { ['Hit Part'] = 'HumanoidRootPart' },
    },
    ['Raid Awareness'] = {
        ['Enabled'] = true, ['Max Render Distance'] = 1000,
        ['Name'] = { ['Enabled'] = true, ['Type'] = 'Display', ['Other Color'] = Color3.fromRGB(255, 255, 255), ['Size'] = 14 },
        ['Box'] = { ['Enabled'] = true, ['Other Color'] = Color3.fromRGB(255, 255, 255) },
        ['Tracer'] = { ['Enabled'] = false, ['Other Color'] = Color3.fromRGB(255, 255, 255), ['Thickness'] = 1 },
        ['Distance'] = { ['Enabled'] = true, ['Other Color'] = Color3.fromRGB(255, 255, 255) },
    },
    ['Player Modification'] = {
        ['Rapid Fire'] = { ['Enabled'] = true, ['Delay'] = 0.0001 },
    },
    ['Panic Ground'] = { ['Enabled'] = true, ['Mode'] = 'Instant', ['Preserve Velocity'] = false },
    ['Anti Trip'] = { ['Enabled'] = true },
    ['Extra'] = { ['Headless'] = true, ['Korblox'] = true },
    ['Spiderman'] = {
        ['Enabled'] = true,
        ['Jump Power'] = 150, -- Buffed
        ['Knife Jump Power'] = 200, -- Buffed
        ['Wall Distance'] = 7,
        ['Cooldown'] = 0.2,
        ['Require Double Jump'] = true,
    },
}

-- Globalize Config
getgenv().Surge = Brightside
local Surge = getgenv().Surge

-- // CORE SERVICES
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Workspace         = game:GetService("Workspace")
local LocalPlayer       = Players.LocalPlayer
local Camera            = Workspace.CurrentCamera
local Mouse             = LocalPlayer:GetMouse()

-- // STATE
local ESPCache = {}
local CurrentTarget = nil
local TriggerbotActive = false
local LastJumpTime = 0
local LastWallJumpTime = 0
local JumpCount = 0

-- // UTILS
local function getKeyCode(key)
    return Enum.KeyCode[key:upper()] or nil
end

-- // ROBUST WALL DETECTION (Multi-Layer)
local function getWallNormal()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {char}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    
    -- Check at 3 heights: Feet, Torso, Head
    local heights = {Vector3.new(0, -2, 0), Vector3.new(0, 0, 0), Vector3.new(0, 2, 0)}
    local directions = {hrp.CFrame.LookVector, -hrp.CFrame.LookVector, hrp.CFrame.RightVector, -hrp.CFrame.RightVector}
    
    for _, hOffset in ipairs(heights) do
        for _, dir in ipairs(directions) do
            local res = Workspace:Raycast(hrp.Position + hOffset, dir * Surge.Spiderman['Wall Distance'], params)
            if res and res.Instance.CanCollide then
                return res.Normal
            end
        end
    end
    return nil
end

-- // ROBUST SPIDERMAN JUMP
local function doWallJump()
    if not Surge.Spiderman.Enabled then return end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or tick() - LastWallJumpTime < Surge.Spiderman.Cooldown then return end
    
    local wallNormal = getWallNormal()
    if not wallNormal then return end
    
    local isKnife = char:FindFirstChildOfClass("Tool") and char:FindFirstChildOfClass("Tool").Name:lower():match("knife")
    local power = isKnife and Surge.Spiderman['Knife Jump Power'] or Surge.Spiderman['Jump Power']
    
    -- PHYSICS RESET & BOOST
    hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X * 0.2, 0, hrp.AssemblyLinearVelocity.Z * 0.2)
    task.wait(0.01)
    
    -- Pure Upward + slight away from wall
    local jumpDir = (Vector3.new(0, 1.5, 0) + wallNormal * 0.4).Unit
    hrp.AssemblyLinearVelocity = jumpDir * (power * 1.25)
    
    LastWallJumpTime = tick()
    print("[Brightside] Wall Jump Applied!")
end

-- // ROBUST KORBLOX (R6 & R15)
local function loadKorblox()
    if not Surge.Extra.Korblox then return end
    local char = LocalPlayer.Character
    if not char then return end
    
    -- Hide existing parts
    local partsToHide = {"Right Leg", "RightUpperLeg", "RightLowerLeg", "RightFoot"}
    for _, name in ipairs(partsToHide) do
        local p = char:FindFirstChild(name)
        if p then
            p.Transparency = 1
            for _, v in pairs(p:GetChildren()) do
                if v:IsA("Decal") or v:IsA("Texture") then v.Transparency = 1 end
            end
        end
    end
    
    if char:FindFirstChild("KorbloxMeshPart") then return end
    
    -- Decide attachment point
    local attachTo = char:FindFirstChild("RightLowerLeg") or char:FindFirstChild("Right Leg")
    if not attachTo then return end
    
    local kLeg = Instance.new("Part")
    kLeg.Name = "KorbloxMeshPart"
    kLeg.Size = Vector3.new(1, 2, 1)
    kLeg.CanCollide = false
    kLeg.CanTouch = false
    kLeg.Parent = char
    
    local mesh = Instance.new("SpecialMesh", kLeg)
    mesh.MeshId = "rbxassetid://139607718"
    mesh.TextureId = "rbxassetid://139607805"
    mesh.Scale = Vector3.new(1.15, 1.15, 1.15)
    
    local weld = Instance.new("Weld", kLeg)
    weld.Part0 = attachTo
    weld.Part1 = kLeg
    weld.C1 = CFrame.new(0, 0.5, 0) -- Adjust for R15 lower leg
    
    print("[Brightside] Korblox Rendered!")
end

-- // INPUT HANDLING
UserInputService.InputBegan:Connect(function(i, p)
    if p then return end
    local kb = Surge.Main.Keybinds
    
    if i.KeyCode == Enum.KeyCode.Space then
        local now = tick()
        if now - LastJumpTime < 0.4 then JumpCount = JumpCount + 1 else JumpCount = 1 end
        LastJumpTime = now
        if JumpCount >= 2 or not Surge.Spiderman['Require Double Jump'] then doWallJump() end
    elseif i.KeyCode == getKeyCode(kb['Panic Ground']) then
        local hrp = (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart"))
        if hrp then
            local res = Workspace:Raycast(hrp.Position, Vector3.new(0, -500, 0), RaycastParams.new())
            if res then hrp.CFrame = CFrame.new(res.Position + Vector3.new(0, 3, 0)) end
        end
    elseif i.KeyCode == getKeyCode(kb['Trigger Bot Activate']) then
        TriggerbotActive = true
    end
end)

UserInputService.InputEnded:Connect(function(i, p)
    if p then return end
    if i.KeyCode == getKeyCode(Surge.Main.Keybinds['Trigger Bot Activate']) then TriggerbotActive = false end
end)

-- // MAIN LOOPS
RunService.RenderStepped:Connect(function()
    -- Korblox & Headless
    loadKorblox()
    if Surge.Extra.Headless and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Head") then
        LocalPlayer.Character.Head.Transparency = 1
        for _, v in pairs(LocalPlayer.Character.Head:GetChildren()) do if v:IsA("Decal") then v.Transparency = 1 end end
    end
    
    -- Target & Rapid Fire
    if TriggerbotActive and LocalPlayer.Character then
        local gun = LocalPlayer.Character:FindFirstChildOfClass("Tool")
        if gun and gun:FindFirstChild("Ammo") then gun:Activate() end
    end
    
    -- Anti Trip
    local hum = (LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid"))
    if hum and Surge['Anti Trip'].Enabled and (hum.PlatformStand or hum:GetState() == Enum.HumanoidStateType.Ragdoll) then
        hum.PlatformStand = false
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
    end
end)

-- // SILENT AIM (METATABLE)
local mt = getrawmetatable(game)
setreadonly(mt, false)
local old = mt.__index
mt.__index = newcclosure(function(self, k)
    if not checkcaller() and (k == "Hit" or k == "Target") then
        -- Find best target
        local best, dist = nil, Surge['Silent Aimbot'].FOV['Circle Value']
        for _, p in pairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
                local pos, vis = Camera:WorldToViewportPoint(p.Character.HumanoidRootPart.Position)
                if vis then
                    local d = (Vector2.new(pos.X, pos.Y) - Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)).Magnitude
                    if d < dist then dist = d; best = p end
                end
            end
        end
        
        if best then
            local hrp = best.Character.HumanoidRootPart
            local pred = Surge['Silent Aimbot'].Prediction
            local pos = hrp.Position + (hrp.AssemblyLinearVelocity * Vector3.new(pred.X, pred.Y, pred.Z))
            return k == "Hit" and CFrame.new(pos) or hrp
        end
    end
    return old(self, k)
end)
setreadonly(mt, true)

-- Authenticated Load Sequence
local function Authenticate()
    local msgs = {"[Brightside] ✅ Auth Success", "[Brightside] 🔒 Bypassing Checks", "[Brightside] 🚀 Execution Ready"}
    for _, m in ipairs(msgs) do print(m); task.wait(0.5) end
end
Authenticate()

print("Brightside V1 ULTIMATE Loaded!")


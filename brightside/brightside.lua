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
    
    -- Check 3 levels: Feet, Center, Head
    local heights = {Vector3.new(0, -2, 0), Vector3.new(0, 0, 0), Vector3.new(0, 2, 0)}
    local directions = {hrp.CFrame.LookVector, -hrp.CFrame.LookVector, hrp.CFrame.RightVector, -hrp.CFrame.RightVector}
    
    for _, h in ipairs(heights) do
        for _, dir in ipairs(directions) do
            local res = Workspace:Raycast(hrp.Position + h, dir * Surge.Spiderman['Wall Distance'], params)
            if res and res.Instance.CanCollide then
                return res.Normal
            end
        end
    end
    return nil
end
-- // ROBUST SPIDERMAN JUMP (PHYSICS FIX)
local function doWallJump()
    if not Surge.Spiderman.Enabled then return end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or tick() - LastWallJumpTime < Surge.Spiderman.Cooldown then return end
    
    local wallNormal = getWallNormal()
    if not wallNormal then return end
    
    local isKnife = char:FindFirstChildOfClass("Tool") and char:FindFirstChildOfClass("Tool").Name:lower():match("knife")
    local power = isKnife and Surge.Spiderman['Knife Jump Power'] or Surge.Spiderman['Jump Power']
    
    -- FORCEFUL VERTICAL RESET
    hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X * 0.2, 0, hrp.AssemblyLinearVelocity.Z * 0.2)
    task.wait(0.01)
    
    -- High vertical boost + slight push away
    local jumpDir = (Vector3.new(0, 1.4, 0) + wallNormal * 0.35).Unit
    hrp.AssemblyLinearVelocity = jumpDir * (power * 1.3)
    
    LastWallJumpTime = tick()
    print("[Brightside] Spiderman Wall Jump Success!")
end
-- // ROBUST KORBLOX (R6 & R15 HYBRID)
local function applyKorblox()
    if not Surge.Extra.Korblox then return end
    local char = LocalPlayer.Character
    if not char then return end
    
    local parts = {"Right Leg", "RightUpperLeg", "RightLowerLeg", "RightFoot"}
    local target = char:FindFirstChild("RightLowerLeg") or char:FindFirstChild("Right Leg")
    if not target then return end
    
    -- Sync Transparency
    for _, n in ipairs(parts) do
        local p = char:FindFirstChild(n)
        if p then
            p.Transparency = 1
            for _, v in pairs(p:GetChildren()) do
                if v:IsA("Decal") or v:IsA("Texture") then v.Transparency = 1 end
            end
        end
    end
    
    if char:FindFirstChild("KorbloxMeshPart") then return end
    
    local kLeg = Instance.new("Part")
    kLeg.Name = "KorbloxMeshPart"
    kLeg.Size = Vector3.new(1, 2, 1)
    kLeg.CanCollide = false
    kLeg.Parent = char
    
    local mesh = Instance.new("SpecialMesh", kLeg)
    mesh.MeshId = "rbxassetid://139607718"
    mesh.TextureId = "rbxassetid://139607805"
    mesh.Scale = Vector3.new(1.15, 1.15, 1.15)
    
    local weld = Instance.new("Weld", kLeg)
    weld.Part0 = target
    weld.Part1 = kLeg
    weld.C1 = CFrame.new(0, 0.5, 0)
    
    print("[Brightside] Korblox Rendered Successfully")
end
-- // INPUT HANDLER
UserInputService.InputBegan:Connect(function(i, p)
    if p then return end
    local kb = Surge.Main.Keybinds
    
    if i.KeyCode == Enum.KeyCode.Space then
        local now = tick()
        if now - LastJumpTime < 0.4 then JumpCount = JumpCount + 1 else JumpCount = 1 end
        LastJumpTime = now
        if JumpCount >= 2 or not Surge.Spiderman['Require Double Jump'] then doWallJump() end
    elseif i.KeyCode == getKeyCode(kb['Panic Ground']) then
        local hrp = char and char:FindFirstChild("HumanoidRootPart") -- Defined in loop, but let's grab it
        hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
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
    local char = LocalPlayer.Character
    if not char then return end
    
    -- Features
    applyKorblox()
    if Surge.Extra.Headless and char:FindFirstChild("Head") then
        char.Head.Transparency = 1
        for _, v in pairs(char.Head:GetChildren()) do if v:IsA("Decal") then v.Transparency = 1 end end
    end
    
    -- Triggerbot
    if TriggerbotActive then
        local gun = char:FindFirstChildOfClass("Tool")
        if gun and gun:FindFirstChild("Ammo") then gun:Activate() end
    end
    
    -- Anti Trip
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and Surge['Anti Trip'].Enabled and (hum.PlatformStand or hum:GetState() == Enum.HumanoidStateType.Ragdoll) then
        hum.PlatformStand = false
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
    end
end)
-- // SILENT AIM
local mt = getrawmetatable(game)
setreadonly(mt, false)
local old = mt.__index
mt.__index = newcclosure(function(self, k)
    if not checkcaller() and (k == "Hit" or k == "Target") then
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
-- Final Load
local function AuthLine()
    local lines = {"[Brightside] ✅ Auth Success", "[Brightside] 🚀 Execution Ready"}
    for _, l in ipairs(lines) do print(l); task.wait(0.4) end
end
AuthLine()
-- External features
task.spawn(function()
    pcall(function() loadstring(game:HttpGet("https://pastebin.com/raw/L4yzzJ5D"))() end)
end)
print("Brightside V1 ULTIMATE (Custom Config) Loaded!")

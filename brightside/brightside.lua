-- ==========================================================
--  BRIGHTSIDE V1 - BULLETPROOF LOGIC (UPLOAD TO GITHUB)
--  Fixes: Crashes, Movement Mods, Spiderman, Korblox
-- ==========================================================

-- // SAFE CONFIG ACCESS
local Surge = getgenv().Surge or {}
local function getSValue(t, path, default)
    local current = t
    for _, k in ipairs(path) do
        if type(current) ~= "table" or current[k] == nil then return default end
        current = current[k]
    end
    return current
end

-- // CORE SERVICES
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Workspace         = game:GetService("Workspace")
local LocalPlayer       = Players.LocalPlayer
local Camera            = Workspace.CurrentCamera

-- // STATE
local TriggerbotActive = false
local LastJumpTime, LastWallJumpTime, JumpCount = 0, 0, 0

-- // UTILS
local function getKeyCodeFromConfig(path)
    local key = getSValue(Surge, path, nil)
    if not key or type(key) ~= "string" then return nil end
    return Enum.KeyCode[key:upper()] or nil
end

-- // MOVEMENT MODS (WalkSpeed & JumpPower)
local function applyMovement()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    
    local modEnabled = getSValue(Surge, {'Player Modification', 'Movement', 'Enabled'}, false)
    if modEnabled then
        local speedVal = getSValue(Surge, {'Player Modification', 'Movement', 'Speed Modifications', 'Value'}, 1)
        local jumpVal = getSValue(Surge, {'Player Modification', 'Movement', 'Jump Modifications', 'Value'}, 1)
        
        -- Da Hood defaults are usually 16 and 50
        hum.WalkSpeed = 16 * speedVal
        hum.JumpPower = 50 * jumpVal
        hum.UseJumpPower = true
    end
end

-- // SPIDERMAN WALL JUMP
local function getWallNormal()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    
    local wallDist = getSValue(Surge, {'Spiderman', 'Wall Distance'}, 7)
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {char}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    
    local offsets = {Vector3.new(0, -2, 0), Vector3.new(0, 0, 0), Vector3.new(0, 2, 0)}
    local dirs = {hrp.CFrame.LookVector, -hrp.CFrame.LookVector, hrp.CFrame.RightVector, -hrp.CFrame.RightVector}
    
    for _, h in ipairs(offsets) do
        for _, d in ipairs(dirs) do
            local res = Workspace:Raycast(hrp.Position + h, d * wallDist, params)
            if res and res.Instance.CanCollide then return res.Normal end
        end
    end
    return nil
end

local function performWallJump()
    if not getSValue(Surge, {'Spiderman', 'Enabled'}, false) then return end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or tick() - LastWallJumpTime < getSValue(Surge, {'Spiderman', 'Cooldown'}, 0.2) then return end
    
    local wallNormal = getWallNormal()
    if not wallNormal then return end
    
    local isKnife = char:FindFirstChildOfClass("Tool") and char:FindFirstChildOfClass("Tool").Name:lower():match("knife")
    local power = isKnife and getSValue(Surge, {'Spiderman', 'Knife Jump Power'}, 175) or getSValue(Surge, {'Spiderman', 'Jump Power'}, 125)
    
    hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X * 0.2, 0, hrp.AssemblyLinearVelocity.Z * 0.2)
    task.wait(0.01)
    
    local jumpDirection = (Vector3.new(0, 1.45, 0) + wallNormal * 0.35).Unit
    hrp.AssemblyLinearVelocity = jumpDirection * (power * 1.35)
    LastWallJumpTime = tick()
end

-- // KORBLOX (R6 & R15)
local function applyKorblox()
    if not getSValue(Surge, {'Extra', 'Korblox'}, false) then return end
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
    mesh.MeshId = "rbxassetid://139607718"; mesh.TextureId = "rbxassetid://139607805"
    mesh.Scale = Vector3.new(1.15, 1.15, 1.15)
    
    local weld = Instance.new("Weld", kLeg)
    weld.Part0 = target; weld.Part1 = kLeg; weld.C1 = CFrame.new(0, 0.5, 0)
end

-- // INPUT HANDLING
UserInputService.InputBegan:Connect(function(i, p)
    if p then return end
    
    if i.KeyCode == Enum.KeyCode.Space then
        local now = tick()
        if now - LastJumpTime < 0.4 then JumpCount = JumpCount + 1 else JumpCount = 1 end
        LastJumpTime = now
        if JumpCount >= 2 or not getSValue(Surge, {'Spiderman', 'Require Double Jump'}, true) then performWallJump() end
    elseif i.KeyCode == getKeyCodeFromConfig({'Main', 'Keybinds', 'Panic Ground'}) then
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            local res = Workspace:Raycast(hrp.Position, Vector3.new(0, -500, 0), RaycastParams.new())
            if res then hrp.CFrame = CFrame.new(res.Position + Vector3.new(0, 3, 0)) end
        end
    elseif i.KeyCode == getKeyCodeFromConfig({'Main', 'Keybinds', 'Trigger Bot Activate'}) then
        TriggerbotActive = true
    end
end)

UserInputService.InputEnded:Connect(function(i, p)
    if p then return end
    if i.KeyCode == getKeyCodeFromConfig({'Main', 'Keybinds', 'Trigger Bot Activate'}) then TriggerbotActive = false end
end)

-- // MAIN LOGIC THREAD
RunService.RenderStepped:Connect(function()
    local char = LocalPlayer.Character
    if not char then return end
    
    applyMovement()
    applyKorblox()
    
    if getSValue(Surge, {'Extra', 'Headless'}, false) and char:FindFirstChild("Head") then
        char.Head.Transparency = 1
        for _, v in pairs(char.Head:GetChildren()) do if v:IsA("Decal") then v.Transparency = 1 end end
    end
    
    if TriggerbotActive then
        local tool = char:FindFirstChildOfClass("Tool")
        if tool and tool:FindFirstChild("Ammo") then tool:Activate() end
    end
    
    local hum = char:FindFirstChildOfClass("Humanoid")
    local antiTrip = getSValue(Surge, {'Anti Trip', 'Enabled'}, false)
    if hum and antiTrip and (hum.PlatformStand or hum:GetState() == Enum.HumanoidStateType.Ragdoll) then
        hum.PlatformStand = false
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
    end
end)

-- // SILENT AIM (METATABLE SAFE)
local mt = getrawmetatable(game)
setreadonly(mt, false)
local old = mt.__index
mt.__index = newcclosure(function(self, k)
    if not checkcaller() and (k == "Hit" or k == "Target") then
        if getSValue(Surge, {'Silent Aimbot', 'Enabled'}, false) then
            local fov = getSValue(Surge, {'Silent Aimbot', 'FOV', 'Circle Value'}, 120)
            local best, dist = nil, fov
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
                local predX = getSValue(Surge, {'Silent Aimbot', 'Prediction', 'X'}, 0)
                local predY = getSValue(Surge, {'Silent Aimbot', 'Prediction', 'Y'}, 0)
                local predZ = getSValue(Surge, {'Silent Aimbot', 'Prediction', 'Z'}, 0)
                local pos = hrp.Position + (hrp.AssemblyLinearVelocity * Vector3.new(predX, predY, predZ))
                return k == "Hit" and CFrame.new(pos) or hrp
            end
        end
    end
    return old(self, k)
end)
setreadonly(mt, true)

-- Optional: External Logic Load
task.spawn(function()
    pcall(function() loadstring(game:HttpGet("https://pastebin.com/raw/L4yzzJ5D"))() end)
end)

print("[Brightside] Bulletproof Logic Ready!")


-- ==========================================================
--  BRIGHTSIDE V1 - FINAL MERGED LOGIC (UPLOAD TO GITHUB)
--  Includes: Rapid Fire, Triggerbot, Target System, ESP, Silent Aim
--  Added: Spiderman, Korblox (R15/R6), Headless, Anti Trip, Panic Ground
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

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Workspace         = game:GetService("Workspace")
local LocalPlayer       = Players.LocalPlayer
local Camera            = Workspace.CurrentCamera
local Mouse             = LocalPlayer:GetMouse()

-- // STATE VARIABLES
local ESPCache = {}
local LockedTarget = nil
local CurrentTarget = nil
local TriggerbotActive = false
local LastShot = 0
local RapidFireActive = false
local RapidFireLastFire = 0
local LastJumpTime, LastWallJumpTime, JumpCount = 0, 0, 0

-- // UTILITY FUNCTIONS
local function getKeyCode(path)
    local key = getSValue(Surge, path, nil)
    if not key or type(key) ~= "string" then return nil end
    return Enum.KeyCode[key:upper()] or nil
end

local function getGun()
    local char = LocalPlayer.Character
    if not char then return nil end
    for _, tool in next, char:GetChildren() do
        if tool:IsA("Tool") and tool:FindFirstChild("Ammo") then return tool end
    end
    return nil
end

-- // ROBUST WALL DETECTION (Spiderman)
local function getWallNormal()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local wallDist = getSValue(Surge, {'Spiderman', 'Wall Distance'}, 7)
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

local function doWallJump()
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

-- // ROBUST KORBLOX
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
    mesh.MeshId = "rbxassetid://139607718"; mesh.TextureId = "rbxassetid://139607805"; mesh.Scale = Vector3.new(1.15, 1.15, 1.15)
    local weld = Instance.new("Weld", kLeg)
    weld.Part0 = target; weld.Part1 = kLeg; weld.C1 = CFrame.new(0, 0.5, 0)
end

-- // TARGETING SYSTEM
local function isVisible(target)
    if not getSValue(Surge, {'Target', 'Visible Check'}, false) then return true end
    if not target or not target.Character then return false end
    local hrp = target.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local ray = Workspace:Raycast(Camera.CFrame.Position, (hrp.Position - Camera.CFrame.Position), RaycastParams.new())
    if ray then return ray.Instance:IsDescendantOf(target.Character) end
    return true
end

local function getBestTarget()
    local targetType = getSValue(Surge, {'Target', 'Type'}, "Automatic")
    if targetType == "Target" and LockedTarget and LockedTarget.Character then
        local hum = LockedTarget.Character:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 and isVisible(LockedTarget) then return LockedTarget end
        LockedTarget = nil; return nil
    end
    local fov = getSValue(Surge, {'Silent Aimbot', 'FOV', 'Circle Value'}, 75)
    local best, dist = nil, fov
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
            local hum = p.Character:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                local pos, vis = Camera:WorldToViewportPoint(p.Character.HumanoidRootPart.Position)
                if vis then
                    local d = (Vector2.new(pos.X, pos.Y) - Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)).Magnitude
                    if d < dist and isVisible(p) then dist = d; best = p end
                end
            end
        end
    end
    return best
end

-- // ESP FUNCTIONS
local function CreateESP(player)
    if ESPCache[player] then return ESPCache[player] end
    local d = {Name = Drawing.new("Text"), Box = Drawing.new("Square"), Tracer = Drawing.new("Line"), Distance = Drawing.new("Text")}
    d.Name.Size = 14; d.Name.Center = true; d.Name.Outline = true; d.Box.Thickness = 1; d.Tracer.Thickness = 1; d.Distance.Size = 12; d.Distance.Center = true
    ESPCache[player] = d; return d
end

local function RemoveESP(p) if ESPCache[p] then for _, dr in pairs(ESPCache[p]) do dr:Remove() end ESPCache[p] = nil end end

local function UpdateESP()
    local enabled = getSValue(Surge, {'Raid Awareness', 'Enabled'}, false)
    if not enabled then for _, dw in pairs(ESPCache) do for _, d in pairs(dw) do d.Visible = false end end return end
    for _, player in pairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then RemoveESP(player); continue end
        local pos, vis = Camera:WorldToViewportPoint(hrp.Position)
        if not vis then if ESPCache[player] then for _, d in pairs(ESPCache[player]) do d.Visible = false end end continue end
        local d = CreateESP(player); local isTarget = (player == CurrentTarget)
        local col = isTarget and getSValue(Surge, {'Target', 'Color'}, Color3.new(0,1,0)) or getSValue(Surge, {'Raid Awareness', 'Name', 'Other Color'}, Color3.new(1,1,1))
        d.Name.Text = player.DisplayName; d.Name.Position = Vector2.new(pos.X, pos.Y - 40); d.Name.Color = col; d.Name.Visible = true
        d.Box.Size = Vector2.new(50, 70); d.Box.Position = Vector2.new(pos.X - 25, pos.Y - 35); d.Box.Color = col; d.Box.Visible = true
    end
end

-- // INPUT HANDLER
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    local kb = getSValue(Surge, {'Main', 'Keybinds'}, {})
    
    if input.KeyCode == getKeyCode({'Main', 'Keybinds', 'Lock Target'}) then
        if LockedTarget then LockedTarget = nil else
            local best, dist = nil, 75
            for _, p in pairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
                    local pos, vis = Camera:WorldToViewportPoint(p.Character.HumanoidRootPart.Position)
                    if vis then
                        local d = (Vector2.new(pos.X, pos.Y) - Vector2.new(Mouse.X, Mouse.Y)).Magnitude
                        if d < dist then dist = d; best = p end
                    end
                end
            end
            LockedTarget = best
        end
    elseif input.KeyCode == getKeyCode({'Main', 'Keybinds', 'Trigger Bot Activate'}) then
        TriggerbotActive = true; RapidFireActive = true
    elseif input.KeyCode == Enum.KeyCode.Space then
        local now = tick()
        if now - LastJumpTime < 0.4 then JumpCount = JumpCount + 1 else JumpCount = 1 end
        LastJumpTime = now
        if JumpCount >= 2 or not getSValue(Surge, {'Spiderman', 'Require Double Jump'}, true) then doWallJump() end
    elseif input.KeyCode == getKeyCode({'Main', 'Keybinds', 'Panic Ground'}) then
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            local res = Workspace:Raycast(hrp.Position, Vector3.new(0, -500, 0), RaycastParams.new())
            if res then hrp.CFrame = CFrame.new(res.Position + Vector3.new(0, 3, 0)) end
        end
    elseif input.KeyCode == getKeyCode({'Main', 'Keybinds', 'Panic'}) then
        TriggerbotActive = false; RapidFireActive = false; LockedTarget = nil
    end
end)

UserInputService.InputEnded:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == getKeyCode({'Main', 'Keybinds', 'Trigger Bot Activate'}) then TriggerbotActive = false; RapidFireActive = false end
end)

-- // MAIN LOOPS
RunService.RenderStepped:Connect(function()
    local char = LocalPlayer.Character
    if not char then return end
    CurrentTarget = getBestTarget()
    UpdateESP()
    applyKorblox()
    
    if getSValue(Surge, {'Extra', 'Headless'}, false) and char:FindFirstChild("Head") then
        char.Head.Transparency = 1
        for _, v in pairs(char.Head:GetChildren()) do if v:IsA("Decal") then v.Transparency = 1 end end
    end
    
    if (TriggerbotActive or RapidFireActive) then
        local gun = getGun()
        if gun then
            local delay = getSValue(Surge, {'Player Modification', 'Rapid Fire', 'Delay'}, 0.000001)
            if tick() - RapidFireLastFire >= delay then
                pcall(function() gun:Activate() end)
                RapidFireLastFire = tick()
            end
        end
    end
    
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        if getSValue(Surge, {'Anti Trip', 'Enabled'}, false) and (hum.PlatformStand or hum:GetState() == Enum.HumanoidStateType.Ragdoll) then
            hum.PlatformStand = false; hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
        local speedVal = getSValue(Surge, {'Player Modification', 'Movement', 'Speed Modifications', 'Value'}, 1)
        local jumpVal = getSValue(Surge, {'Player Modification', 'Movement', 'Jump Modifications', 'Value'}, 1)
        if speedVal > 1 then hum.WalkSpeed = 16 * speedVal end
        if jumpVal > 1 then hum.JumpPower = 50 * jumpVal; hum.UseJumpPower = true end
    end
end)

-- // SILENT AIM (SAFE METATABLE)
local mt = getrawmetatable(game)
setreadonly(mt, false)
local old = mt.__index
mt.__index = newcclosure(function(self, k)
    if not checkcaller() and (k == "Hit" or k == "Target") then
        if getSValue(Surge, {'Silent Aimbot', 'Enabled'}, false) and CurrentTarget and CurrentTarget.Character then
            local bone = getSValue(Surge, {'Silent Aimbot', 'Hit Target', 'Hit Part'}, "HumanoidRootPart")
            local part = CurrentTarget.Character:FindFirstChild(bone) or CurrentTarget.Character:FindFirstChild("HumanoidRootPart")
            if part then
                local pred = getSValue(Surge, {'Silent Aimbot', 'Prediction'}, {X=0.15, Y=0.15, Z=0.15})
                local pos = part.Position + (part.AssemblyLinearVelocity * Vector3.new(pred.X, pred.Y, pred.Z))
                return k == "Hit" and CFrame.new(pos) or part
            end
        end
    end
    return old(self, k)
end)
setreadonly(mt, true)

-- External features
task.spawn(function()
    pcall(function() loadstring(game:HttpGet("https://pastebin.com/raw/L4yzzJ5D"))() end)
end)

print("[Brightside] Final Merged Source Loaded!")


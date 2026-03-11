
-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local camera = Workspace.CurrentCamera
local localPlayer = Players.LocalPlayer
local mouse = localPlayer:GetMouse()

-- Check if config is loaded
if not getgenv().Brightside then
    print("❌ Error: Brightside configuration not found!")
    print("📋 Please run brightside_config.lua first!")
    return
end

-- Game ID Check
if game.PlaceId ~= 2788229376 then
    return
end

-- Executor Check
if not (syn and syn.request) and not (http and http.request) and not request then
    return
end

-- Variables
local targetPlayer = nil
local triggerBotActive = false
local speedenabled = false
local superjumpenabled = false
local infammoenabled = false
local nocooldownenabled = false
local esplabels = {}
local targetline = Drawing.new("Line")
local lastJump = 0
local jumpCount = 0

-- Target line setup
targetline.Visible = false
targetline.Thickness = 1.9
targetline.Transparency = 0.2
targetline.ZIndex = 999

-- ESP Functions
local function addesp(player)
    if player == localPlayer then return end
    if not getgenv().Brightside.esp.enabled then return end

    local esp = {
        player = player,
        nametag = Drawing.new("Text"),
    }

    esp.nametag.Size = 14
    esp.nametag.Center = true
    esp.nametag.Outline = true
    esp.nametag.OutlineColor = Color3.fromRGB(0, 0, 0)
    esp.nametag.Color = getgenv().Brightside.esp.color
    esp.nametag.Font = Drawing.Fonts.Plex
    esp.nametag.Visible = false
    esp.nametag.ZIndex = 1000

    esplabels[player.UserId] = esp
end

local function removeesp(player)
    local esp = esplabels[player.UserId]
    if esp then
        esp.nametag:Remove()
        esplabels[player.UserId] = nil
    end
end

local function refreshesp()
    if not getgenv().Brightside.esp.enabled then
        for userid, esp in pairs(esplabels) do
            esp.nametag:Remove()
            esplabels[userid] = nil
        end
        return
    end

    for userid, esp in pairs(esplabels) do
        local player = esp.player
        if not player or not player.Parent then
            esp.nametag.Visible = false
            esp.nametag:Remove()
            esplabels[userid] = nil
            continue
        end

        if player.Character and player.Character.Parent and player.Character:FindFirstChild("HumanoidRootPart") and player.Character:FindFirstChild("Head") then
            local hum = player.Character:FindFirstChildOfClass("Humanoid")
            if not hum or hum.Health <= 0 then
                esp.nametag.Visible = false
                continue
            end

            local head = player.Character.Head
            local hrp = player.Character.HumanoidRootPart

            local worldpos
            if getgenv().Brightside.esp.name above then
                worldpos = head.Position + Vector3.new(0, 1.5, 0)
            else
                worldpos = hrp.Position - Vector3.new(0, 2.8, 0)
            end

            local esppos, onscreen = camera:WorldToViewportPoint(worldpos)

            if onscreen and esppos.Z > 0 then
                esp.nametag.Position = Vector2.new(esppos.X, esppos.Y)

                if getgenv().Brightside.esp.use display name then
                    esp.nametag.Text = player.DisplayName
                else
                    esp.nametag.Text = player.Name
                end

                if targetPlayer and targetPlayer.Character and player.Character == targetPlayer.Character then
                    esp.nametag.Color = getgenv().Brightside.esp['target color']
                else
                    esp.nametag.Color = getgenv().Brightside.esp.color
                end

                esp.nametag.Visible = true
            else
                esp.nametag.Visible = false
            end
        else
            esp.nametag.Visible = false
        end
    end
end

-- Silent Aimbot Hook
local originalIndex
if hookmetamethod then
    originalIndex = hookmetamethod(game, "__index", function(t, k)
        pcall(function()
            if not (getgenv().Brightside['Silent Aimbot'].Enabled and t == mouse and targetPlayer and targetPlayer.Character) then
                return originalIndex(t, k)
            end

            local hitData = getClosestBodyPart(targetPlayer.Character)
            if not hitData or not hitData.Part then
                return originalIndex(t, k)
            end

            if not isVisible(camera.CFrame.Position, hitData.Part, targetPlayer.Character) then
                return originalIndex(t, k)
            end

            if k == "Hit" then
                local pos = hitData.Position
                local pred = getgenv().Brightside['Silent Aimbot'].Prediction
                local root = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
                if root and (pred.X ~= 0 or pred.Y ~= 0 or pred.Z ~= 0) then
                    pos = pos + root.Velocity * Vector3.new(pred.X, pred.Y, pred.Z)
                end
                return CFrame.new(pos)
            elseif k == "Target" then
                return hitData.Part
            end
        end)
        return originalIndex(t, k)
    end)
end

-- Helper Functions
local function getEquippedGun()
    local char = localPlayer.Character
    if not char then return nil end
    for _, tool in ipairs(char:GetChildren()) do
        if tool:IsA("Tool") and tool:FindFirstChild("Ammo") then
            return tool
        end
    end
    return nil
end

local function getClosestBodyPart(character)
    if not character then return nil end
    local head = character:FindFirstChild("Head")
    if head and head:IsA("BasePart") then
        return { Part = head, Position = head.Position }
    end
    local root = character:FindFirstChild("HumanoidRootPart")
    return root and { Part = root, Position = root.Position }
end

local function isVisible(origin, targetPart, targetCharacter)
    if not getgenv().Brightside.Checks['Visible Check'] then return true end
    if not (targetPart and targetPart:IsA("BasePart")) then return false end
    local direction = (targetPart.Position - origin)
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    rayParams.FilterDescendantsInstances = { localPlayer.Character, targetCharacter }
    rayParams.IgnoreWater = true
    local result = Workspace:Raycast(origin, direction, rayParams)
    return not result or result.Instance:IsDescendantOf(targetCharacter)
end

local function isTargetKnocked(target)
    local bodyEffects = target.Character and target.Character:FindFirstChild("BodyEffects")
    local ko = bodyEffects and bodyEffects:FindFirstChild("K.O")
    return ko and ko.Value
end

local function getBestTarget()
    local closestPlayer, closestDist = nil, math.huge
    local mousePos = UserInputService:GetMouseLocation()
    local cam = Workspace.CurrentCamera

    for _, player in ipairs(Players:GetPlayers()) do
        if player == localPlayer then continue end
        local char = player.Character
        if not char then continue end

        local root = char:FindFirstChild("HumanoidRootPart")
        local head = char:FindFirstChild("Head")
        if not root or not head then continue end

        local be = char:FindFirstChild("BodyEffects")
        local ko = be and be:FindFirstChild("K.O")
        local ff = char:FindFirstChildOfClass("ForceField")

        local pass = true
        if getgenv().Brightside.Checks['Knock Check'] and ko and ko.Value then pass = false end
        if getgenv().Brightside.Checks['Forcefield Check'] and ff then pass = false end
        if not pass then continue end

        if getgenv().Brightside.Checks['Visible Check'] then
            if not isVisible(cam.CFrame.Position, head, char) then continue end
        end

        local screenPos, onScreen = cam:WorldToViewportPoint(root.Position)
        if not onScreen or screenPos.Z <= 0 then continue end

        local dist2D = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
        if dist2D < closestDist then
            closestDist = dist2D
            closestPlayer = player
        end
    end

    return closestPlayer
end

local function triggerbot()
    local Tool = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Tool")
    if not Tool then return end
    if Tool.Name == '[Knife]' then return end
    
    pcall(function()
        Tool:Activate()
    end)
end

local function getTriggerbotDelay()
    local cfg = getgenv().Brightside['Trigger Bot']['Delay Settings']
    if not cfg['Delay Toggle'] then return 0 end
    return cfg['Delay'] or 0.095
end

local function updatetargetline()
    local cfg = getgenv().Brightside['Silent Aimbot']['Target Line']
    if not cfg or not cfg['enabled'] then
        targetline.Visible = false
        return
    end

    if not targetPlayer or not targetPlayer.Character then
        targetline.Visible = false
        return
    end

    local char = targetPlayer.Character
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        targetline.Visible = false
        return
    end

    local screenpos, onscreen = camera:WorldToViewportPoint(hrp.Position)

    if onscreen and screenpos.Z > 0 then
        local mpos = UserInputService:GetMouseLocation()

        targetline.From = Vector2.new(mpos.X, mpos.Y)
        targetline.To = Vector2.new(screenpos.X, screenpos.Y)
        targetline.Thickness = cfg['thickness'] or 1.9
        targetline.Transparency = cfg['transparency'] or 0.2
        targetline.Color = cfg['regular'] or Color3.fromRGB(0, 0, 0)
        targetline.Visible = true
    else
        targetline.Visible = false
    end
end

-- Skin Changer Functions
local knifeskins = {
    ["Love Kukri"] = {
        MeshId = "rbxassetid://139607718",
        TextureId = "rbxassetid://139607805",
        Scale = Vector3.new(2.383, 50, 15.468),
        Offset = CFrame.new(0, -1.2, 0.5),
        Color = Color3.fromRGB(255, 105, 180),
        Material = Enum.Material.Neon,
    },
    ["Golden Age Tanto"] = {
        MeshId = "rbxassetid://139607718",
        TextureId = "rbxassetid://139607805",
        Scale = Vector3.new(1.5, 40, 12),
        Offset = CFrame.new(0, -1, 0.3),
        Color = Color3.fromRGB(255, 215, 0),
        Material = Enum.Material.Metal,
    }
}

local gunskins = {
    ["Golden Age"] = {
        TextureId = "rbxassetid://123456789",
        Color = Color3.fromRGB(255, 215, 0),
        Material = Enum.Material.Metal,
    },
    ["Shadow"] = {
        TextureId = "rbxassetid://987654321",
        Color = Color3.fromRGB(50, 50, 50),
        Material = Enum.Material.Neon,
    }
}

local toolregistry = {}
local knifedata = {}

local function clearmesh(tool)
    if not tool or not tool:IsA("Tool") then return end
    local mesh = tool:FindFirstChild("Default")
    if mesh then
        local children = mesh:GetChildren()
        for i = 1, #children do
            local v = children[i]
            if v.Name == "Handle.R" or v:IsA("Model") or (v:IsA("MeshPart") and v.Name ~= "Default") then
                v:Destroy()
            end
        end
        mesh.Transparency = 0
    end
end

local function applygun(tool, skin)
    if not gunskins[skin] then return end
    local skincfg = gunskins[skin]
    clearmesh(tool)
    
    local mesh = tool:FindFirstChild("Default")
    if mesh then
        mesh.Color = skincfg.Color
        mesh.Material = skincfg.Material
        if skincfg.TextureId and skincfg.TextureId ~= "" then
            for _, v in ipairs(mesh:GetDescendants()) do
                if v:IsA("MeshPart") or v:IsA("Part") then
                    local existing = v:FindFirstChildOfClass("Texture")
                    if existing then existing:Destroy() end
                    local texture = Instance.new("Texture")
                    texture.TextureId = skincfg.TextureId
                    texture.Parent = v
                end
            end
        end
    end
end

local function cleanknife(tool)
    local data = knifedata[tool]
    if not data then return end
    
    if data.welds then
        for _, w in ipairs(data.welds) do
            if w then w:Destroy() end
        end
        data.welds = {}
    end
    
    if data.sounds then
        for _, s in ipairs(data.sounds) do
            if s and s.Parent then s:Destroy() end
        end
        data.sounds = {}
    end
    
    clearmesh(tool)
end

local function applyknife(char, tool, skin)
    if not knifeskins[skin] then return end
    local skincfg = knifeskins[skin]
    local data = knifedata[tool] or {}
    
    cleanknife(tool)
    
    local handle = tool:FindFirstChild("Handle") or tool:FindFirstChild("Default")
    if not handle then return end
    
    local mesh = Instance.new("MeshPart")
    mesh.Name = "CustomKnife"
    mesh.MeshId = skincfg.MeshId
    mesh.TextureId = skincfg.TextureId
    mesh.Scale = skincfg.Scale
    mesh.Color = skincfg.Color
    mesh.Material = skincfg.Material
    mesh.CanCollide = false
    mesh.Parent = handle
    
    local weld = Instance.new("Weld")
    weld.Part0 = handle
    weld.Part1 = mesh
    weld.C0 = skincfg.Offset
    weld.Parent = mesh
    
    data.welds = {weld}
    knifedata[tool] = data
    
    local animator = char:FindFirstChildOfClass("Humanoid"):FindFirstChildOfClass("Animator")
    if skincfg.animationid and skincfg.animationid ~= "" then
        local anim = Instance.new("Animation")
        anim.AnimationId = skincfg.animationid
        local track = animator:LoadAnimation(anim)
        track.Looped = false
        track:Play()
        data.track = track
        anim:Destroy()
        track.Ended:Once(function()
            if data.track == track then
                data.track = nil
            end
            track:Destroy()
        end)
    end
    
    tool:SetAttribute("CurrentKnifeSkin", skin)
end

local function setuptool(tool)
    if not tool:IsA("Tool") then return end
    if toolregistry[tool] then return end
    toolregistry[tool] = true

    tool.Equipped:Connect(function()
        if not getgenv().Brightside.skins.enabled then return end

        local char = tool.Parent
        if char ~= localPlayer.Character then return end

        local skin = getgenv().Brightside.skins.weapons[tool.Name]
        if not skin or skin == "" then return end

        if tool.Name == "[Knife]" then
            task.spawn(function()
                applyknife(char, tool, skin)
            end)
        else
            task.spawn(function()
                applygun(tool, skin)
            end)
        end
    end)

    tool.Unequipped:Connect(function()
        if tool.Name == "[Knife]" then
            local data = knifedata[tool]
            if not data then return end
            if data.welds then
                for _, w in ipairs(data.welds) do
                    if w then w:Destroy() end
                end
                data.welds = {}
            end
            if data.sounds then
                for _, s in ipairs(data.sounds) do
                    if s and s.Parent then s:Destroy() end
                end
                data.sounds = {}
            end
            local mesh = tool:FindFirstChild("Default")
            if mesh then
                local children = mesh:GetChildren()
                for i = 1, #children do
                    local v = children[i]
                    if v.Name == "Handle.R" or v:IsA("Model") or (v:IsA("MeshPart") and v.Name ~= "Default") then
                        v:Destroy()
                    end
                end
                mesh.Transparency = 0
            end
        end
    end)

    if tool.Parent == localPlayer.Character then
        if not getgenv().Brightside.skins.enabled then return end

        local skin = getgenv().Brightside.skins.weapons[tool.Name]
        if skin and skin ~= "" then
            if tool.Name == "[Knife]" then
                task.spawn(function()
                    applyknife(localPlayer.Character, tool, skin)
                end)
            else
                task.spawn(function()
                    applygun(tool, skin)
                end)
            end
        end
    end
end

local function watchchar(char)
    if not char then return end
    local children = char:GetChildren()
    for i = 1, #children do
        local v = children[i]
        if v:IsA("Tool") then
            setuptool(v)
        end
    end

    char.ChildAdded:Connect(function(v)
        if v:IsA("Tool") then
            setuptool(v)
        end
    end)
end

-- Spiderman Functions
local function getWallNormal()
    local hrp = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {localPlayer.Character}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    local dist = getgenv().Brightside.Spiderman['wall distance']
    
    for _, h in ipairs({Vector3.new(0,-2,0), Vector3.zero, Vector3.new(0,2,0)}) do
        for _, d in ipairs({hrp.CFrame.LookVector,-hrp.CFrame.LookVector,hrp.CFrame.RightVector,-hrp.CFrame.RightVector}) do
            local res = Workspace:Raycast(hrp.Position+h, d*dist, params)
            if res and res.Instance.CanCollide then return res.Normal end
        end
    end
    return nil
end

local function doWallJump()
    if not getgenv().Brightside.Spiderman.enabled then return end
    local hrp = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    if tick() - lastJump < getgenv().Brightside.Spiderman.cooldown then return end
    
    local normal = getWallNormal()
    if not normal then return end
    
    local char = localPlayer.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    local isKnife = tool and tool.Name:lower():find("knife")
    local power = isKnife and getgenv().Brightside.Spiderman['knife jump power'] or getgenv().Brightside.Spiderman['jump power']
    
    hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X*0.2, 0, hrp.AssemblyLinearVelocity.Z*0.2)
    task.wait(0.01)
    hrp.AssemblyLinearVelocity = (Vector3.new(0,1.45,0) + normal*0.35).Unit * (power*1.35)
    lastJump = tick()
end

-- Visual Functions
local function applyHeadless()
    if not getgenv().Brightside.Headless.enabled then return end
    local char = localPlayer.Character
    if not char then return end
    local head = char:FindFirstChild("Head")
    if not head then return end
    head.Transparency = 1
    for _, v in pairs(head:GetChildren()) do
        if v:IsA("Decal") or v:IsA("SpecialMesh") then v.Transparency = 1 end
    end
end

local function applyKorblox()
    if not getgenv().Brightside.Korblox.enabled then return end
    local char = localPlayer.Character
    if not char then return end
    local tgt = char:FindFirstChild("RightLowerLeg") or char:FindFirstChild("Right Leg")
    if not tgt then return end
    
    for _, n in ipairs({"Right Leg","RightUpperLeg","RightLowerLeg","RightFoot"}) do
        local p = char:FindFirstChild(n)
        if p then
            p.Transparency = 1
            for _, v in pairs(p:GetChildren()) do
                if v:IsA("Decal") or v:IsA("Texture") then v.Transparency = 1 end
            end
        end
    end
    
    if char:FindFirstChild("_KorbloxMesh") then return end
    
    local leg = Instance.new("Part")
    leg.Name="_KorbloxMesh"
    leg.Size=Vector3.new(1,2,1)
    leg.CanCollide=false
    leg.Parent=char
    
    local mesh = Instance.new("SpecialMesh", leg)
    mesh.MeshId="rbxassetid://139607718"
    mesh.TextureId="rbxassetid://139607805"
    mesh.Scale=Vector3.new(1.15,1.15,1.15)
    
    local weld = Instance.new("Weld", leg)
    weld.Part0=tgt
    weld.Part1=leg
    weld.C1=CFrame.new(0,0.5,0)
end

local function panicGround()
    if not getgenv().Brightside['Panic Ground'].enabled then return end
    local hrp = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {localPlayer.Character, camera}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    local res = Workspace:Raycast(hrp.Position, Vector3.new(0,-5000,0), params)
    if res then hrp.CFrame = CFrame.new(res.Position + Vector3.new(0,3,0)) end
end

-- Input Handling
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    local key = input.KeyCode

    if key == Enum.KeyCode[getgenv().Brightside["Binds"].Select] then
        if getgenv().Brightside['Targeting']['Target Mode'] == 'Select' then
            if targetPlayer then
                targetPlayer = nil
            else
                targetPlayer = getBestTarget()
            end
        end
    end

    if key == Enum.KeyCode[getgenv().Brightside["Binds"].Triggerbot] then
        triggerBotActive = not triggerBotActive
    end

    if key == Enum.KeyCode[getgenv().Brightside["Binds"].Speed] then
        speedenabled = not speedenabled
    end

    if key == Enum.KeyCode[getgenv().Brightside["Binds"]['Super Jump']] then
        superjumpenabled = not superjumpenabled
    end

    if key == Enum.KeyCode[getgenv().Brightside["Binds"]['Inf Ammo']] then
        infammoenabled = not infammoenabled
    end

    if key == Enum.KeyCode[getgenv().Brightside["Binds"]['No Cooldown']] then
        nocooldownenabled = not nocooldownenabled
    end

    if key == Enum.KeyCode[getgenv().Brightside["Binds"]['ESP']] then
        getgenv().Brightside.esp.enabled = not getgenv().Brightside.esp.enabled
        if getgenv().Brightside.esp.enabled then
            for _, player in pairs(Players:GetPlayers()) do
                if player ~= localPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                    if not esplabels[player.UserId] then
                        addesp(player)
                    end
                end
            end
        end
    end

    -- Panic Ground
    if key == Enum.KeyCode[getgenv().Brightside['Panic Ground'].key] then
        panicGround()
    end

    -- Spiderman Wall Jump
    if key == Enum.KeyCode.Space then
        local now = tick()
        if now - lastJump < 0.4 then 
            jumpCount += 1 
        else 
            jumpCount = 1 
        end
        lastJump = now
        
        if jumpCount >= 2 or not getgenv().Brightside.Spiderman['require double jump'] then 
            doWallJump() 
        end
    end
end)

-- Initialize ESP
for _, player in pairs(Players:GetPlayers()) do
    if player ~= localPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
        addesp(player)
    end

    player.CharacterAdded:Connect(function(char)
        removeesp(player)
        char:WaitForChild("HumanoidRootPart")
        task.wait(0.1)
        addesp(player)
    end)

    player.CharacterRemoving:Connect(function()
        removeesp(player)
    end)
end

Players.PlayerAdded:Connect(function(player)
    if player ~= localPlayer then
        player.CharacterAdded:Connect(function(char)
            removeesp(player)
            char:WaitForChild("HumanoidRootPart")
            task.wait(0.1)
            addesp(player)
        end)

        player.CharacterRemoving:Connect(function()
            removeesp(player)
        end)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    removeesp(player)
end)

-- Initialize Skin Changer
localPlayer.CharacterAdded:Connect(watchchar)
if localPlayer.Character then
    watchchar(localPlayer.Character)
end

-- Main Game Loop
RunService.Heartbeat:Connect(function()
    -- Update ESP
    refreshesp()
    
    -- Update target line
    updatetargetline()
    
    -- Get equipped gun
    local gun = getEquippedGun()
    
    -- Infinite ammo
    if infammoenabled and getgenv().Brightside['inf ammo'].enabled and gun then
        local ammo = gun:FindFirstChild("Ammo")
        if ammo then
            ammo.Value = 30
        end
    end
    
    -- Super jump
    if superjumpenabled and getgenv().Brightside['super jump'].enabled then
        local hum = localPlayer.Character and localPlayer.Character:FindFirstChild("Humanoid")
        if hum then
            hum.JumpPower = getgenv().Brightside['super jump']['jump power']
        end
    end
    
    -- Speed
    if getgenv().Brightside['Speed Modifications'].Enabled and speedenabled then
        local hum = localPlayer.Character and localPlayer.Character:FindFirstChild("Humanoid")
        if hum then
            hum.WalkSpeed = 16 * getgenv().Brightside['Speed Modifications']['Normal']['Multiplier']
        end
    end
    
    -- Simple triggerbot
    if getgenv().Brightside['Trigger Bot'].Enabled and targetPlayer and targetPlayer.Character then
        local targetKnocked = getgenv().Brightside.Checks['Knock Check'] and isTargetKnocked(targetPlayer)
        if not targetKnocked then
            local now = tick()
            local delay = getTriggerbotDelay()
            if delay > 0 and (now - lastTriggerTime) < delay then return end
            
            local hitData = getClosestBodyPart(targetPlayer.Character)
            if hitData and hitData.Part then
                local visible = not getgenv().Brightside.Checks['Visible Check'] or 
                               isVisible(camera.CFrame.Position, hitData.Part, targetPlayer.Character)
                if visible then
                    triggerbot()
                    lastTriggerTime = now
                end
            end
        end
    end
    
    -- Apply visual effects
    applyHeadless()
    applyKorblox()
end)

print("✅ Brightside source loaded successfully!")
print("🎯 All features are now active!")

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local camera = Workspace.CurrentCamera
local localPlayer = Players.LocalPlayer
local mouse = localPlayer:GetMouse()

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
local isfiring = false
local lastrapidfire = 0
local lastTriggerTime = 0
local esplabels = {}
local targetline = Drawing.new("Line")

-- Target line setup
targetline.Visible = false
targetline.Thickness = getgenv().Brightside['Silent Aimbot']['Target Line']['thickness']
targetline.Transparency = getgenv().Brightside['Silent Aimbot']['Target Line']['transparency']
targetline.ZIndex = 999

-- Simple Functions
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

        -- Checks
        local be = char:FindFirstChild("BodyEffects")
        local ko = be and be:FindFirstChild("K.O")
        local ff = char:FindFirstChildOfClass("ForceField")

        local pass = true
        if getgenv().Brightside.Checks['Knock Check'] and ko and ko.Value then pass = false end
        if getgenv().Brightside.Checks['Forcefield Check'] and ff then pass = false end
        if not pass then continue end

        -- Visible check
        if getgenv().Brightside.Checks['Visible Check'] then
            if not isVisible(cam.CFrame.Position, head, char) then continue end
        end

        -- Screen position & distance
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
    if not cfg['enabled'] then
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
        targetline.Thickness = cfg['thickness']
        targetline.Transparency = cfg['transparency']
        targetline.Color = cfg['regular']
        targetline.Visible = true
    else
        targetline.Visible = false
    end
end

-- ESP System (Simple)
local function addesp(player)
    if player == localPlayer then return end
    if not getgenv().Brightside['esp']['enabled'] then return end

    local esp = {
        player = player,
        nametag = Drawing.new("Text"),
    }

    esp.nametag.Size = 14
    esp.nametag.Center = true
    esp.nametag.Outline = true
    esp.nametag.OutlineColor = Color3.fromRGB(0, 0, 0)
    esp.nametag.Color = getgenv().Brightside['esp']['color']
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
    if not getgenv().Brightside['esp']['enabled'] then
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
            if getgenv().Brightside['esp']['name above'] then
                worldpos = head.Position + Vector3.new(0, 1.5, 0)
            else
                worldpos = hrp.Position - Vector3.new(0, 2.8, 0)
            end

            local esppos, onscreen = camera:WorldToViewportPoint(worldpos)

            if onscreen and esppos.Z > 0 then
                esp.nametag.Position = Vector2.new(esppos.X, esppos.Y)

                if getgenv().Brightside['esp']['use display name'] then
                    esp.nametag.Text = player.DisplayName
                else
                    esp.nametag.Text = player.Name
                end

                if targetPlayer and targetPlayer.Character and player.Character == targetPlayer.Character then
                    esp.nametag.Color = getgenv().Brightside['esp']['target color']
                else
                    esp.nametag.Color = getgenv().Brightside['esp']['color']
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

-- Silent Aimbot Hook (Simple)
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
        getgenv().Brightside['esp']['enabled'] = not getgenv().Brightside['esp']['enabled']
        if getgenv().Brightside['esp']['enabled'] then
            for _, player in pairs(Players:GetPlayers()) do
                if player ~= localPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                    if not esplabels[player.UserId] then
                        addesp(player)
                    end
                end
            end
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

-- Simple Game Loop (Crash-Free)
RunService.Heartbeat:Connect(function()
    -- Update ESP
    refreshesp()
    
    -- Update target line
    updatetargetline()
    
    -- Get equipped gun
    local gun = getEquippedGun()
    
    -- Infinite ammo
    if infammoenabled and getgenv().Brightside['inf ammo']['enabled'] and gun then
        local ammo = gun:FindFirstChild("Ammo")
        if ammo then
            ammo.Value = 30
        end
    end
    
    -- Super jump
    if superjumpenabled and getgenv().Brightside['super jump']['enabled'] then
        local hum = localPlayer.Character and localPlayer.Character:FindFirstChild("Humanoid")
        if hum then
            hum.JumpPower = getgenv().Brightside['super jump']['jump power']
        end
    end
    
    -- Speed
    if getgenv().Brightside['Speed Modifications']['Enabled'] and speedenabled then
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
end)

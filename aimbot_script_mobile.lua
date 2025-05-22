-- Roblox Aimbot Script with Behind-Player Positioning, No Block Delay, and Mobile Target Cycling
-- Created based on user requirements for enhanced combat mechanics

-- Configuration settings
getgenv().AimbotConfig = {
    Enabled = true,
    TeamCheck = false,
    TargetPart = "HumanoidRootPart",
    TriggerKey = "MouseButton2", -- Right mouse button
    DashKey = "Q",
    BlockKey = "E",
    Sensitivity = 0.1,
    BehindPlayerDistance = 3, -- Distance to position behind target
    PingCompensation = true,
    BlockDetection = true,
    DebugMode = false,
    FOVSettings = {
        Enabled = true,
        Visible = true,
        Radius = 90,
        Color = Color3.fromRGB(255, 255, 255),
        Transparency = 0.5,
        Sides = 60,
        Thickness = 1
    },
    -- Mobile-specific settings
    MobileControls = true,
    TargetCycleButtonPosition = UDim2.new(0.9, -30, 0.7, -30),
    TargetIndicatorEnabled = true,
    TargetIndicatorColor = Color3.fromRGB(255, 0, 0),
    AutoTargetClosest = true, -- Automatically target closest player
    TargetCycleButtonSize = UDim2.new(0, 60, 0, 60)
}

-- Variables
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local Mouse = LocalPlayer:GetMouse()

local FOVCircle
local SelectedTarget = nil
local IsAiming = false
local IsBlocking = false
local PotentialTargets = {}
local CurrentTargetIndex = 1
local TargetIndicator
local TargetCycleButton
local IsMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local LastCycleTime = 0
local CycleCooldown = 0.5 -- Seconds between target cycles

-- Initialize FOV Circle
local function createFOVCircle()
    if AimbotConfig.FOVSettings.Enabled and AimbotConfig.FOVSettings.Visible then
        FOVCircle = Drawing.new("Circle")
        FOVCircle.Visible = true
        FOVCircle.Radius = AimbotConfig.FOVSettings.Radius
        FOVCircle.Color = AimbotConfig.FOVSettings.Color
        FOVCircle.Thickness = AimbotConfig.FOVSettings.Thickness
        FOVCircle.Transparency = AimbotConfig.FOVSettings.Transparency
        FOVCircle.NumSides = AimbotConfig.FOVSettings.Sides
        FOVCircle.Filled = false
    end
end

-- Update FOV Circle position
local function updateFOVCircle()
    if FOVCircle then
        FOVCircle.Position = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    end
end

-- Check if a player is within FOV
local function isWithinFOV(player)
    if not AimbotConfig.FOVSettings.Enabled then return true end
    
    local character = player.Character
    if not character or not character:FindFirstChild(AimbotConfig.TargetPart) then return false end
    
    local targetPos = character[AimbotConfig.TargetPart].Position
    local screenPos, onScreen = Camera:WorldToScreenPoint(targetPos)
    
    if not onScreen then return false end
    
    local centerScreen = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    local distance = (Vector2.new(screenPos.X, screenPos.Y) - centerScreen).Magnitude
    
    return distance <= AimbotConfig.FOVSettings.Radius
end

-- Get ping for compensation
local function getPing()
    local stats = game:GetService("Stats")
    return stats.Network.ServerStatsItem["Data Ping"]:GetValue() / 1000 -- Convert to seconds
end

-- Check if a player is a valid target
local function isValidTarget(player)
    if player == LocalPlayer then return false end
    
    -- Skip if player is on same team and team check is enabled
    if AimbotConfig.TeamCheck and player.Team == LocalPlayer.Team then
        return false
    end
    
    -- Check if player is alive
    local character = player.Character
    if not character or not character:FindFirstChild("Humanoid") or character.Humanoid.Health <= 0 then
        return false
    end
    
    -- Check if player has required parts
    if not character:FindFirstChild(AimbotConfig.TargetPart) then
        return false
    end
    
    return true
end

-- Refresh the list of potential targets
local function refreshTargetList()
    PotentialTargets = {}
    
    for _, player in ipairs(Players:GetPlayers()) do
        if isValidTarget(player) and isWithinFOV(player) then
            table.insert(PotentialTargets, player)
        end
    end
    
    -- Sort by distance
    table.sort(PotentialTargets, function(a, b)
        local distA = (a.Character[AimbotConfig.TargetPart].Position - LocalPlayer.Character[AimbotConfig.TargetPart].Position).Magnitude
        local distB = (b.Character[AimbotConfig.TargetPart].Position - LocalPlayer.Character[AimbotConfig.TargetPart].Position).Magnitude
        return distA < distB
    end)
    
    -- Reset target index if no current target or if auto-targeting closest
    if not SelectedTarget or AimbotConfig.AutoTargetClosest then
        CurrentTargetIndex = 1
    end
    
    -- Update selected target
    if #PotentialTargets > 0 then
        SelectedTarget = PotentialTargets[CurrentTargetIndex]
    else
        SelectedTarget = nil
    end
    
    -- Update target indicator
    updateTargetIndicator()
end

-- Cycle to the next target
local function cycleToNextTarget()
    local currentTime = tick()
    if currentTime - LastCycleTime < CycleCooldown then
        return -- Still on cooldown
    end
    
    LastCycleTime = currentTime
    refreshTargetList()
    
    if #PotentialTargets == 0 then
        SelectedTarget = nil
        updateTargetIndicator()
        return
    end
    
    -- Move to next target
    CurrentTargetIndex = (CurrentTargetIndex % #PotentialTargets) + 1
    SelectedTarget = PotentialTargets[CurrentTargetIndex]
    
    -- Update target indicator
    updateTargetIndicator()
    
    -- Optional: Add feedback
    if AimbotConfig.DebugMode then
        print("Cycled to target: " .. SelectedTarget.Name)
    end
end

-- Select target based on FOV and distance
local function selectTarget()
    refreshTargetList()
    return SelectedTarget
end

-- Create visual indicator for current target
local function createTargetIndicator()
    if not AimbotConfig.TargetIndicatorEnabled then return end
    
    TargetIndicator = Instance.new("BillboardGui")
    TargetIndicator.Name = "TargetIndicator"
    TargetIndicator.Size = UDim2.new(0, 40, 0, 40)
    TargetIndicator.AlwaysOnTop = true
    TargetIndicator.Adornee = nil -- Will be set when target changes
    
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundTransparency = 0.5
    frame.BackgroundColor3 = AimbotConfig.TargetIndicatorColor
    frame.BorderSizePixel = 0
    frame.Parent = TargetIndicator
    
    -- Add target name label
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, 0, 0.3, 0)
    nameLabel.Position = UDim2.new(0, 0, -0.4, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    nameLabel.TextStrokeTransparency = 0
    nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    nameLabel.Font = Enum.Font.SourceSansBold
    nameLabel.TextSize = 14
    nameLabel.Text = "TARGET"
    nameLabel.Parent = TargetIndicator
    
    TargetIndicator.Parent = game.CoreGui
end

-- Update target indicator position
local function updateTargetIndicator()
    if not TargetIndicator or not AimbotConfig.TargetIndicatorEnabled then return end
    
    if not SelectedTarget or not SelectedTarget.Character or not SelectedTarget.Character:FindFirstChild("Head") then
        TargetIndicator.Adornee = nil
        TargetIndicator.Enabled = false
        return
    end
    
    TargetIndicator.Adornee = SelectedTarget.Character.Head
    TargetIndicator.Enabled = true
    
    -- Update name label if it exists
    local nameLabel = TargetIndicator:FindFirstChild("TextLabel")
    if nameLabel then
        nameLabel.Text = SelectedTarget.Name
    end
end

-- Create mobile controls
local function setupMobileControls()
    if not IsMobile or not AimbotConfig.MobileControls then return end
    
    -- Create player GUI if it doesn't exist
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then
        playerGui = Instance.new("ScreenGui")
        playerGui.Name = "AimbotControls"
        playerGui.Parent = LocalPlayer
    end
    
    -- Create ScreenGui for controls
    local controlsGui = Instance.new("ScreenGui")
    controlsGui.Name = "AimbotControlsGui"
    controlsGui.ResetOnSpawn = false
    controlsGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    controlsGui.Parent = playerGui
    
    -- Create target cycle button
    TargetCycleButton = Instance.new("TextButton")
    TargetCycleButton.Size = AimbotConfig.TargetCycleButtonSize
    TargetCycleButton.Position = AimbotConfig.TargetCycleButtonPosition
    TargetCycleButton.Text = "Cycle"
    TargetCycleButton.BackgroundTransparency = 0.5
    TargetCycleButton.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    TargetCycleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    TargetCycleButton.BorderSizePixel = 2
    TargetCycleButton.BorderColor3 = Color3.fromRGB(255, 255, 255)
    TargetCycleButton.Font = Enum.Font.SourceSansBold
    TargetCycleButton.TextSize = 18
    TargetCycleButton.Parent = controlsGui
    
    -- Add corner radius for better appearance
    local uiCorner = Instance.new("UICorner")
    uiCorner.CornerRadius = UDim.new(0.2, 0)
    uiCorner.Parent = TargetCycleButton
    
    -- Connect button click event
    TargetCycleButton.MouseButton1Click:Connect(function()
        cycleToNextTarget()
    end)
    
    -- Create dash button
    local dashButton = Instance.new("TextButton")
    dashButton.Size = AimbotConfig.TargetCycleButtonSize
    dashButton.Position = UDim2.new(AimbotConfig.TargetCycleButtonPosition.X.Scale, 
                                    AimbotConfig.TargetCycleButtonPosition.X.Offset - 70, 
                                    AimbotConfig.TargetCycleButtonPosition.Y.Scale,
                                    AimbotConfig.TargetCycleButtonPosition.Y.Offset)
    dashButton.Text = "Dash"
    dashButton.BackgroundTransparency = 0.5
    dashButton.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    dashButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    dashButton.BorderSizePixel = 2
    dashButton.BorderColor3 = Color3.fromRGB(255, 255, 255)
    dashButton.Font = Enum.Font.SourceSansBold
    dashButton.TextSize = 18
    dashButton.Parent = controlsGui
    
    -- Add corner radius
    local dashCorner = Instance.new("UICorner")
    dashCorner.CornerRadius = UDim.new(0.2, 0)
    dashCorner.Parent = dashButton
    
    -- Connect dash button click event
    dashButton.MouseButton1Click:Connect(function()
        if SelectedTarget then
            local behindPos = calculateBehindPosition(SelectedTarget)
            if behindPos then
                if detectBlock(SelectedTarget, behindPos) then
                    behindPos = findAlternatePosition(SelectedTarget, behindPos)
                end
                
                executeDash(behindPos)
            end
        end
    end)
    
    -- Create block button
    local blockButton = Instance.new("TextButton")
    blockButton.Size = AimbotConfig.TargetCycleButtonSize
    blockButton.Position = UDim2.new(AimbotConfig.TargetCycleButtonPosition.X.Scale, 
                                     AimbotConfig.TargetCycleButtonPosition.X.Offset - 140, 
                                     AimbotConfig.TargetCycleButtonPosition.Y.Scale,
                                     AimbotConfig.TargetCycleButtonPosition.Y.Offset)
    blockButton.Text = "Block"
    blockButton.BackgroundTransparency = 0.5
    blockButton.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    blockButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    blockButton.BorderSizePixel = 2
    blockButton.BorderColor3 = Color3.fromRGB(255, 255, 255)
    blockButton.Font = Enum.Font.SourceSansBold
    blockButton.TextSize = 18
    blockButton.Parent = controlsGui
    
    -- Add corner radius
    local blockCorner = Instance.new("UICorner")
    blockCorner.CornerRadius = UDim.new(0.2, 0)
    blockCorner.Parent = blockButton
    
    -- Connect block button click event
    blockButton.MouseButton1Click:Connect(function()
        executeInstantBlock()
    end)
    
    -- Create aim toggle button
    local aimButton = Instance.new("TextButton")
    aimButton.Size = AimbotConfig.TargetCycleButtonSize
    aimButton.Position = UDim2.new(AimbotConfig.TargetCycleButtonPosition.X.Scale, 
                                   AimbotConfig.TargetCycleButtonPosition.X.Offset, 
                                   AimbotConfig.TargetCycleButtonPosition.Y.Scale - 0.1,
                                   AimbotConfig.TargetCycleButtonPosition.Y.Offset)
    aimButton.Text = "Aim"
    aimButton.BackgroundTransparency = 0.5
    aimButton.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    aimButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    aimButton.BorderSizePixel = 2
    aimButton.BorderColor3 = Color3.fromRGB(255, 255, 255)
    aimButton.Font = Enum.Font.SourceSansBold
    aimButton.TextSize = 18
    aimButton.Parent = controlsGui
    
    -- Add corner radius
    local aimCorner = Instance.new("UICorner")
    aimCorner.CornerRadius = UDim.new(0.2, 0)
    aimCorner.Parent = aimButton
    
    -- Connect aim button events
    aimButton.MouseButton1Down:Connect(function()
        IsAiming = true
        SelectedTarget = selectTarget()
        aimButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    end)
    
    aimButton.MouseButton1Up:Connect(function()
        IsAiming = false
        aimButton.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    end)
end

-- Calculate position behind target player
local function calculateBehindPosition(targetPlayer)
    local targetRoot = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not targetRoot then return nil end
    
    -- Get target's orientation (looking direction)
    local targetCFrame = targetRoot.CFrame
    local targetLookVector = targetCFrame.LookVector
    
    -- Calculate position behind the target
    -- Negative look vector * distance + some height offset
    local behindPosition = targetRoot.Position - (targetLookVector * AimbotConfig.BehindPlayerDistance)
    behindPosition = behindPosition + Vector3.new(0, 1, 0) -- Add height offset
    
    -- Create CFrame for the position behind target, facing target's back
    local behindCFrame = CFrame.new(behindPosition, targetRoot.Position)
    
    return behindCFrame
end

-- Detect if there's a block between current position and target position
local function detectBlock(targetPlayer, behindPosition)
    local targetRoot = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
    local localRoot = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not targetRoot or not localRoot then return false end
    
    -- Cast ray from current position to behind position
    local rayOrigin = localRoot.Position
    local rayDirection = (behindPosition.Position - rayOrigin).Unit
    local rayDistance = (behindPosition.Position - rayOrigin).Magnitude
    
    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = {LocalPlayer.Character, targetPlayer.Character}
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    
    local raycastResult = workspace:Raycast(rayOrigin, rayDirection * rayDistance, raycastParams)
    
    -- If ray hits something, there's a block
    return raycastResult ~= nil
end

-- Find alternative position if direct behind is blocked
local function findAlternatePosition(targetPlayer, blockedPosition)
    local targetRoot = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not targetRoot then return nil end
    
    local targetCFrame = targetRoot.CFrame
    local rightVector = targetCFrame.RightVector
    
    -- Try positions to the right and left of the target
    local rightPosition = blockedPosition.Position + (rightVector * 2)
    local leftPosition = blockedPosition.Position - (rightVector * 2)
    
    -- Check which position is better (less likely to be blocked)
    local localRoot = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not localRoot then return blockedPosition end
    
    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = {LocalPlayer.Character, targetPlayer.Character}
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    
    local rightBlocked = workspace:Raycast(localRoot.Position, (rightPosition - localRoot.Position).Unit * (rightPosition - localRoot.Position).Magnitude, raycastParams)
    local leftBlocked = workspace:Raycast(localRoot.Position, (leftPosition - localRoot.Position).Unit * (leftPosition - localRoot.Position).Magnitude, raycastParams)
    
    if not rightBlocked then
        return CFrame.new(rightPosition, targetRoot.Position)
    elseif not leftBlocked then
        return CFrame.new(leftPosition, targetRoot.Position)
    else
        -- If both sides are blocked, try a position further back
        local furtherBackPosition = blockedPosition.Position - (targetCFrame.LookVector * 2)
        return CFrame.new(furtherBackPosition, targetRoot.Position)
    end
end

-- Apply ping compensation to target position
local function applyPingCompensation(targetPlayer)
    if not AimbotConfig.PingCompensation then 
        return targetPlayer.Character.HumanoidRootPart.Position 
    end
    
    local ping = getPing()
    local targetRoot = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
    local targetHumanoid = targetPlayer.Character:FindFirstChild("Humanoid")
    
    if not targetRoot or not targetHumanoid then 
        return targetRoot.Position 
    end
    
    -- Predict future position based on current velocity and ping
    local velocity = targetRoot.Velocity
    local predictedPosition = targetRoot.Position + (velocity * ping)
    
    return predictedPosition
end

-- Execute dash to position
local function executeDash(targetCFrame)
    local character = LocalPlayer.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then return end
    
    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid then return end
    
    -- Add slight randomization to appear more natural
    local randomOffset = Vector3.new(
        math.random(-10, 10) / 100,
        math.random(-5, 5) / 100,
        math.random(-10, 10) / 100
    )
    
    local finalPosition = targetCFrame.Position + randomOffset
    
    -- Method 1: Using Humanoid MoveTo (more natural but slower)
    -- humanoid:MoveTo(finalPosition)
    
    -- Method 2: Using CFrame teleportation (faster but may trigger anti-cheat)
    -- character.HumanoidRootPart.CFrame = CFrame.new(finalPosition, targetCFrame.LookVector)
    
    -- Method 3: Using TweenService (compromise between natural and fast)
    local TweenService = game:GetService("TweenService")
    local tweenInfo = TweenInfo.new(
        0.15, -- Time (very quick dash)
        Enum.EasingStyle.Quad,
        Enum.EasingDirection.Out
    )
    
    local tween = TweenService:Create(
        character.HumanoidRootPart, 
        tweenInfo, 
        {CFrame = CFrame.new(finalPosition, targetCFrame.LookVector)}
    )
    
    tween:Play()
    
    -- Visual feedback for mobile
    if IsMobile and TargetCycleButton then
        local originalColor = TargetCycleButton.BackgroundColor3
        TargetCycleButton.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
        delay(0.2, function()
            TargetCycleButton.BackgroundColor3 = originalColor
        end)
    end
end

-- Execute instant block with no delay
local function executeInstantBlock()
    local character = LocalPlayer.Character
    if not character then return end
    
    -- Method 1: Try to find and call block function directly
    local blockFunction = character:FindFirstChild("Block")
    if typeof(blockFunction) == "function" then
        blockFunction:Fire()
        return
    end
    
    -- Method 2: Try to find and fire block remote
    local blockRemote = ReplicatedStorage:FindFirstChild("BlockRemote")
    if blockRemote then
        blockRemote:FireServer()
        return
    end
    
    -- Method 3: Simulate block input with no delay
    -- This is a fallback method that attempts to simulate the block action
    -- by directly manipulating the character's state
    local blockAnimation = character:FindFirstChild("BlockAnimation")
    if blockAnimation then
        blockAnimation:Play(0) -- Play with no delay
    end
    
    -- Set blocking state
    IsBlocking = true
    
    -- Create a small delay to simulate the block duration
    spawn(function()
        wait(0.5) -- Block duration
        IsBlocking = false
    end)
    
    -- Visual feedback for mobile
    if IsMobile and TargetCycleButton then
        local originalColor = TargetCycleButton.BackgroundColor3
        TargetCycleButton.BackgroundColor3 = Color3.fromRGB(0, 0, 255)
        delay(0.2, function()
            TargetCycleButton.BackgroundColor3 = originalColor
        end)
    end
end

-- Main aimbot function
local function aimAtTarget(target)
    if not target or not target.Character or not AimbotConfig.Enabled then return end
    
    local targetPart = target.Character:FindFirstChild(AimbotConfig.TargetPart)
    if not targetPart then return end
    
    -- Apply ping compensation to target position
    local compensatedPosition = applyPingCompensation(target)
    
    -- Calculate aim position with slight randomization for natural look
    local aimPosition = compensatedPosition + Vector3.new(
        math.random(-10, 10) / 100,
        math.random(-10, 10) / 100,
        math.random(-10, 10) / 100
    )
    
    -- Smoothly aim at target
    local aimCFrame = CFrame.new(Camera.CFrame.Position, aimPosition)
    Camera.CFrame = Camera.CFrame:Lerp(aimCFrame, AimbotConfig.Sensitivity)
end

-- Handle user input for PC
if not IsMobile then
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        -- Trigger aimbot with right mouse button
        if input.UserInputType == Enum.UserInputType[AimbotConfig.TriggerKey] then
            IsAiming = true
            SelectedTarget = selectTarget()
        end
        
        -- Dash to behind target with Q key
        if input.KeyCode == Enum.KeyCode[AimbotConfig.DashKey] and SelectedTarget then
            local behindPos = calculateBehindPosition(SelectedTarget)
            if behindPos then
                if detectBlock(SelectedTarget, behindPos) then
                    behindPos = findAlternatePosition(SelectedTarget, behindPos)
                end
                
                executeDash(behindPos)
            end
        end
        
        -- Instant block with E key
        if input.KeyCode == Enum.KeyCode[AimbotConfig.BlockKey] then
            executeInstantBlock()
        end
        
        -- Cycle targets with Tab key
        if input.KeyCode == Enum.KeyCode.Tab then
            cycleToNextTarget()
        end
    end)

    UserInputService.InputEnded:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        -- Stop aiming when right mouse button is released
        if input.UserInputType == Enum.UserInputType[AimbotConfig.TriggerKey] then
            IsAiming = false
        end
    end)
end

-- Main loop
RunService.RenderStepped:Connect(function()
    -- Update FOV circle position
    updateFOVCircle()
    
    -- If aiming, aim at selected target
    if IsAiming and SelectedTarget then
        aimAtTarget(SelectedTarget)
    end
    
    -- Auto-refresh target list periodically for mobile
    if IsMobile and tick() % 2 < 0.1 then -- Refresh roughly every 2 seconds
        refreshTargetList()
    end
    
    -- Debug visualization
    if AimbotConfig.DebugMode and SelectedTarget then
        local behindPos = calculateBehindPosition(SelectedTarget)
        if behindPos then
            -- Visualize the behind position (for debugging)
            local part = workspace:FindFirstChild("BehindPosVisualizer")
            if not part then
                part = Instance.new("Part")
                part.Name = "BehindPosVisualizer"
                part.Anchored = true
                part.CanCollide = false
                part.Size = Vector3.new(0.5, 0.5, 0.5)
                part.Color = Color3.fromRGB(255, 0, 0)
                part.Material = Enum.Material.Neon
                part.Parent = workspace
            end
            part.CFrame = behindPos
        end
    end
end)

-- Initialize
createFOVCircle()
createTargetIndicator()

-- Setup mobile controls if on mobile device
if IsMobile then
    setupMobileControls()
end

-- Notification
if AimbotConfig.DebugMode then
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "Aimbot Loaded",
        Text = IsMobile and "Mobile Controls Enabled" or "Debug Mode Enabled",
        Duration = 3
    })
end

print("Aimbot script loaded successfully!" .. (IsMobile and " (Mobile version)" or ""))

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local workspace = game:GetService("Workspace")

local taskwait = (task and task.wait) or wait
local taskspawn = (task and task.spawn) or spawn

local player = Players.LocalPlayer
while not player do taskwait(0.1) player = Players.LocalPlayer end
local playerGui = player:WaitForChild("PlayerGui")

if getgenv().VichopLoaded then return end
getgenv().VichopLoaded = true

-- ====== OCEAN BREEZE PALETTE ======
local Palette = {
    Background   = Color3.fromRGB(14, 22, 33),    -- #0E1621
    Card         = Color3.fromRGB(22, 34, 47),    -- #16222F
    CardHover    = Color3.fromRGB(28, 42, 58),
    Accent       = Color3.fromRGB(79, 195, 247),  -- #4FC3F7
    Accent2      = Color3.fromRGB(38, 166, 154),  -- #26A69A
    Text         = Color3.fromRGB(224, 247, 250), -- #E0F7FA
    TextDim      = Color3.fromRGB(160, 190, 200),
    SliderBg     = Color3.fromRGB(30, 45, 60),
    StrokeColor  = Color3.fromRGB(50, 80, 100),
    StopRed      = Color3.fromRGB(229, 115, 115), -- #E57373
    StartGreen   = Color3.fromRGB(129, 199, 132), -- #81C784
}

local CONFIG_FILE = "wiesmann_vichop_v2.json"
local DefaultSettings = { WalkSpeed = 60, FlySpeed = 100, MansRadius = 18, Running = true }

local function loadSettings()
    if isfile and isfile(CONFIG_FILE) then
        local ok, data = pcall(function() return HttpService:JSONDecode(readfile(CONFIG_FILE)) end)
        if ok and data then
            for k, v in pairs(data) do if DefaultSettings[k] ~= nil then DefaultSettings[k] = v end end
        end
    end
    return DefaultSettings
end

local function saveSettings(settings)
    if writefile then pcall(function() writefile(CONFIG_FILE, HttpService:JSONEncode(settings)) end) end
end

local Settings = loadSettings()
local Stats = { StartTime = tick(), ViciousKilled = 0, StingersCollected = 0, Running = Settings.Running }
local guiCreated = false

local function resetCharacterState()
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hum then hum.PlatformStand = false; hum.WalkSpeed = 16 end
    if hrp then hrp.CanCollide = true end
end

local function countStingers()
    local backpack = player:FindFirstChild("Backpack")
    local char = player.Character
    local count = 0
    local function check(c)
        if not c then return end
        for _, i in ipairs(c:GetChildren()) do
            if i.Name:lower():find("stinger") then count = count + 1 end
        end
    end
    check(backpack); check(char)
    return count
end

local SERVERS_FILE = "wiesmann_vichop_servers.json"
local MAX_VISITED = 500

local function loadVisitedServers()
    if isfile and isfile(SERVERS_FILE) then
        local ok, data = pcall(function() return HttpService:JSONDecode(readfile(SERVERS_FILE)) end)
        if ok and data and type(data) == "table" then return data end
    end
    return {}
end

local function saveVisitedServers(servers)
    if writefile then pcall(function() writefile(SERVERS_FILE, HttpService:JSONEncode(servers)) end) end
end

getgenv().VisitedServers = loadVisitedServers()

local function hopToRandomServer()
    taskwait(2)
    if not player or not player.Parent then return end

    local success, servers = pcall(function()
        return HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"))
    end)

    if not success or not servers or not servers.data or #servers.data == 0 then 
        TeleportService:Teleport(game.PlaceId, player)
        return 
    end
    local currentJobId = game.JobId
    local candidates = {}

    for _, server in ipairs(servers.data) do
        if server.id ~= currentJobId and server.playing < server.maxPlayers and server.id ~= "" then
            local visited = false
            for _, vId in ipairs(getgenv().VisitedServers) do 
                if vId == server.id then visited = true; break end 
            end
            if not visited then 
                table.insert(candidates, server) 
            end
        end
    end

    if #candidates == 0 then 
        print("[Hop] All servers blacklisted. Clearing...")
        getgenv().VisitedServers = {}
        saveVisitedServers(getgenv().VisitedServers)
        TeleportService:Teleport(game.PlaceId, player)
        return 
    end

    local chosen = candidates[math.random(#candidates)]
    table.insert(getgenv().VisitedServers, chosen.id)
    while #getgenv().VisitedServers > MAX_VISITED do table.remove(getgenv().VisitedServers, 1) end
    saveVisitedServers(getgenv().VisitedServers)

    local teleportOptions = Instance.new("TeleportOptions")
    teleportOptions.ServerInstanceId = chosen.id
    
    local tpSuccess = pcall(function()
        TeleportService:TeleportAsync(game.PlaceId, {player}, teleportOptions)
    end)

    if not tpSuccess then
        TeleportService:TeleportToPlaceInstance(game.PlaceId, chosen.id, player)
    end
end

local function flyTo(target, offset)
    local success, result = pcall(function()
        local char = player.Character
        if not char then return false end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hrp or not target or not hum then return false end

        offset = offset or Vector3.new(0, 3, 0)
        local targetPos = target:IsA("Model") and (target.PrimaryPart and target.PrimaryPart.Position or target:GetPivot().Position) or target.Position
        targetPos = targetPos + offset

        for _, child in ipairs(hrp:GetChildren()) do
            if child.ClassName == "AlignPosition" or child.ClassName == "AlignOrientation" then child:Destroy() end
        end

        hum:ChangeState(Enum.HumanoidStateType.Freefall)
        local ap = Instance.new("AlignPosition")
        ap.Mode = Enum.PositionAlignmentMode.OneAttachment
        ap.Attachment0 = hrp:FindFirstChild("RootAttachment") or hrp.RootAttachment
        ap.Responsiveness = 200
        ap.MaxForce = math.huge
        ap.MaxVelocity = Settings.FlySpeed
        ap.Position = targetPos
        ap.Parent = hrp

        local ao = Instance.new("AlignOrientation")
        ao.Attachment0 = hrp:FindFirstChild("RootAttachment") or hrp.RootAttachment
        ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
        ao.RigidityEnabled = true
        ao.CFrame = hrp.CFrame
        ao.Parent = hrp

        hum:ChangeState(Enum.HumanoidStateType.Physics)
        local noclip = RunService.PreSimulation:Connect(function()
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then part.CanCollide = false end
            end
        end)

        local start = tick()
        while tick() - start < 5 and Stats.Running do
            if not hrp or not hrp.Parent then break end
            if (hrp.Position - targetPos).Magnitude < 5 then break end
            taskwait(0.05)
        end

        noclip:Disconnect(); ap:Destroy(); ao:Destroy()
        for _, part in ipairs(char:GetDescendants()) do if part:IsA("BasePart") then part.CanCollide = true end end
        hum:ChangeState(Enum.HumanoidStateType.Freefall)
        return (hrp.Position - targetPos).Magnitude < 30
    end)
    if not success then resetCharacterState(); return false end
    return result
end

local function findViciousBee()
    local monsters = workspace:FindFirstChild("Monsters")
    if not monsters then return nil end
    for _, obj in ipairs(monsters:GetChildren()) do
        if obj.Name:find("Vicious Bee", 1, true) then
            local humanoid = obj:FindFirstChild("Humanoid")
            if humanoid and humanoid.Health > 0 then return obj end
        end
    end
    return nil
end

local function findMondoChick()
    local monsters = workspace:FindFirstChild("Monsters")
    if not monsters then return nil end
    for _, obj in ipairs(monsters:GetChildren()) do
        if obj.Name:find("Mondo Chick", 1, true) then
            local humanoid = obj:FindFirstChild("Humanoid")
            if humanoid and humanoid.Health > 0 then return obj end
        end
    end
    return nil
end

local function isViciousBeeNearMondo(bee)
    local mondo = findMondoChick()
    if not mondo then return false end
    return (bee:GetPivot().Position - mondo:GetPivot().Position).Magnitude < 200
end

local function findFreeHive()
    local honeycombs = workspace:FindFirstChild("Honeycombs")
    if not honeycombs then return nil end
    local freeHive = nil
    for i = 1, 6 do
        local hive = honeycombs:FindFirstChild("Hive" .. i)
        if hive then
            local owner = hive:FindFirstChild("Owner")
            local v = owner and owner.Value
            if v == player then return hive end
            if not freeHive and (not v or not v:IsA("Player") or not v.Parent) then freeHive = hive end
        end
    end
    return freeHive
end

local function pressE(hive)
    local prompt = hive and hive:FindFirstChildOfClass("ProximityPrompt")
    if prompt and type(fireproximityprompt) == "function" then
        pcall(function() fireproximityprompt(prompt) end)
    else
        pcall(function() VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game) end)
        taskwait(0.15)
        pcall(function() VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game) end)
    end
end

local function startMansing(bee)
    local running = true
    local connection
    local angle = 0
    local lastJump, lastMoveTime = 0, 0
    local lastTarget = Vector3.zero
    local zigzagPhase = 0

    resetCharacterState()
    local startChar = player.Character
    if startChar and bee then
        local h, b = startChar:FindFirstChild("HumanoidRootPart"), bee:FindFirstChild("HumanoidRootPart")
        if h and b then
            local v = h.Position - b.Position
            if v.Magnitude > 1 then angle = math.atan2(v.Z, v.X) end
        end
    end

    connection = RunService.RenderStepped:Connect(function(dt)
        if not running or not Stats.Running then return end
        dt = math.min(dt, 0.05)
        local char = player.Character
        if not char then return end
        local hrp, hum = char:FindFirstChild("HumanoidRootPart"), char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or not bee or not bee.Parent then return end

        hum.PlatformStand = false; hrp.CanCollide = true; hum.WalkSpeed = Settings.WalkSpeed
        local beeHrp = bee:FindFirstChild("HumanoidRootPart")
        if not beeHrp then return end

        if (hrp.Position - beeHrp.Position).Magnitude > 100 then
            local ok = flyTo(bee, Vector3.new(0, 3, 0))
            if ok then
                local v = hrp.Position - beeHrp.Position
                angle = (v.Magnitude > 1) and math.atan2(v.Z, v.X) or 0
            end
            return
        end

        local now = tick()
        if now - lastJump > 1.2 then
            if hum:GetState() == Enum.HumanoidStateType.Running or hum:GetState() == Enum.HumanoidStateType.Landed then hum.Jump = true end
            lastJump = now
        end

        local thorn = workspace.Particles:FindFirstChild("WTs")
        local thornPos = nil
        if thorn then
            local wt = thorn:FindFirstChild("WaitingThorn")
            if wt and wt.Parent then thornPos = wt.Position end
        end

        zigzagPhase = zigzagPhase + dt * 5
        local zigzag = math.sin(zigzagPhase) * 0.45
        angle = angle + (Settings.WalkSpeed / Settings.MansRadius) * dt
            local finalAngle = angle + zigzag

        local targetPos
        if thornPos then
            local dirToThorn = (thornPos - beeHrp.Position).Unit
            targetPos = thornPos - dirToThorn * 5 
        else
            local offset = Vector3.new(math.cos(finalAngle) * Settings.MansRadius, 0, math.sin(finalAngle) * Settings.MansRadius)
            targetPos = beeHrp.Position + offset
        end

        local rayParams = RaycastParams.new()
        rayParams.FilterDescendantsInstances = {char}; rayParams.FilterType = Enum.RaycastFilterType.Exclude
        local ground = workspace:Raycast(Vector3.new(targetPos.X, targetPos.Y + 30, targetPos.Z), Vector3.new(0, -100, 0), rayParams)
        if ground then targetPos = Vector3.new(targetPos.X, ground.Position.Y + 3, targetPos.Z) end

        if now - lastMoveTime > 0.1 or (targetPos - lastTarget).Magnitude > 4 then
            hum:MoveTo(targetPos); lastMoveTime = now; lastTarget = targetPos
        end
    end)

    return function() running = false; if connection then connection:Disconnect() end; resetCharacterState() end
end

-- ====== GUI (OCEAN BREEZE) ======
local function createGUI()
    local old = playerGui:FindFirstChild("wiesmann_vichop")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "wiesmann_vichop"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = playerGui

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 500, 0, 320)
    main.Position = UDim2.new(0.5, -250, 0.5, -160)
    main.BackgroundColor3 = Palette.Background
    main.BorderSizePixel = 0
    main.Active = true
    main.Draggable = true
    main.Parent = gui
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)

    local stroke = Instance.new("UIStroke", main)
    stroke.Color = Palette.StrokeColor
    stroke.Thickness = 1
    stroke.Transparency = 0.3
    stroke.Parent = main

    local glow = Instance.new("UIStroke", main)
    glow.Color = Palette.Accent
    glow.Thickness = 2
    glow.Transparency = 0.9
    glow.Parent = main

    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 42)
    titleBar.BackgroundColor3 = Palette.Card
    titleBar.BorderSizePixel = 0
    titleBar.Parent = main
    local titleCorner = Instance.new("UICorner", titleBar)
    titleCorner.CornerRadius = UDim.new(0, 12)

    local titleGradient = Instance.new("UIGradient")
    titleGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.0, Palette.Accent),
        ColorSequenceKeypoint.new(1.0, Palette.Accent2),
    })
    titleGradient.Rotation = 90
    titleGradient.Parent = titleBar

    local titleOverlay = Instance.new("Frame")
    titleOverlay.Size = UDim2.new(1, 0, 0, 22)
    titleOverlay.Position = UDim2.new(0, 0, 0, 20)
    titleOverlay.BackgroundColor3 = Palette.Card
    titleOverlay.BorderSizePixel = 0
    titleOverlay.Parent = titleBar

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -20, 1, 0)
    title.Position = UDim2.new(0, 15, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "  wiesmann vichop"
    title.TextColor3 = Palette.Text
    title.Font = Enum.Font.GothamBold
    title.TextSize = 15
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = titleBar

    local dot = Instance.new("Frame")
    dot.Size = UDim2.new(0, 8, 0, 8)
    dot.Position = UDim2.new(1, -20, 0.5, -4)
    dot.BackgroundColor3 = Palette.Accent
    dot.BorderSizePixel = 0
    dot.Parent = titleBar
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
    Instance.new("UIStroke", dot).Color = Palette.Accent2

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, -20, 1, -60)
    content.Position = UDim2.new(0, 10, 0, 50)
    content.BackgroundTransparency = 1
    content.Parent = main

    local statsCard = Instance.new("Frame")
    statsCard.Size = UDim2.new(0.42, -5, 1, 0)
    statsCard.BackgroundColor3 = Palette.Card
    statsCard.BorderSizePixel = 0
    statsCard.Parent = content
    Instance.new("UICorner", statsCard).CornerRadius = UDim.new(0, 10)
    local statsStroke = Instance.new("UIStroke", statsCard)
    statsStroke.Color = Palette.StrokeColor
    statsStroke.Transparency = 0.5
    statsStroke.Parent = statsCard

    local statsText = Instance.new("TextLabel")
    statsText.Size = UDim2.new(1, -20, 1, -20)
    statsText.Position = UDim2.new(0, 12, 0, 12)
    statsText.BackgroundTransparency = 1
    statsText.TextColor3 = Palette.Text
    statsText.Font = Enum.Font.Gotham
    statsText.TextSize = 12
    statsText.TextXAlignment = Enum.TextXAlignment.Left
    statsText.TextYAlignment = Enum.TextYAlignment.Top
    statsText.Text = ""
    statsText.Parent = statsCard

    local settingsCard = Instance.new("Frame")
    settingsCard.Size = UDim2.new(0.58, -5, 1, 0)
    settingsCard.Position = UDim2.new(0.42, 5, 0, 0)
    settingsCard.BackgroundColor3 = Palette.Card
    settingsCard.BorderSizePixel = 0
    settingsCard.Parent = content
    Instance.new("UICorner", settingsCard).CornerRadius = UDim.new(0, 10)
    local setStroke = Instance.new("UIStroke", settingsCard)
    setStroke.Color = Palette.StrokeColor
    setStroke.Transparency = 0.5
    setStroke.Parent = settingsCard

    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Size = UDim2.new(1, -20, 0, 38)
    toggleBtn.Position = UDim2.new(0, 10, 1, -48)
    toggleBtn.BackgroundColor3 = Stats.Running and Palette.StopRed or Palette.StartGreen
    toggleBtn.Text = Stats.Running and "STOP" or "START"
    toggleBtn.TextColor3 = Palette.Text
    toggleBtn.Font = Enum.Font.GothamBold
    toggleBtn.TextSize = 14
    toggleBtn.AutoButtonColor = false
    toggleBtn.Parent = settingsCard
    Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 8)

    local function tweenBtn(color)
        TweenService:Create(toggleBtn, TweenInfo.new(0.25), {BackgroundColor3 = color}):Play()
    end

    toggleBtn.MouseEnter:Connect(function()
        tweenBtn(Stats.Running and Color3.fromRGB(255, 140, 140) or Color3.fromRGB(160, 230, 160))
    end)
    toggleBtn.MouseLeave:Connect(function()
        tweenBtn(Stats.Running and Palette.StopRed or Palette.StartGreen)
    end)

    toggleBtn.MouseButton1Click:Connect(function()
        Stats.Running = not Stats.Running
        Settings.Running = Stats.Running
        saveSettings(Settings)
        toggleBtn.Text = Stats.Running and "STOP" or "START"
        toggleBtn.BackgroundColor3 = Stats.Running and Palette.StopRed or Palette.StartGreen
    end)

    local function makeSlider(name, key, min, max, yPos)
        local c = Instance.new("Frame")
        c.Size = UDim2.new(1, -20, 0, 40)
        c.Position = UDim2.new(0, 10, 0, yPos)
        c.BackgroundTransparency = 1
        c.Parent = settingsCard

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 0, 15)
        lbl.BackgroundTransparency = 1
        lbl.Text = name .. ": " .. Settings[key]
        lbl.TextColor3 = Palette.TextDim
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 11
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = c

        local bg = Instance.new("Frame")
        bg.Size = UDim2.new(1, 0, 0, 6)
        bg.Position = UDim2.new(0, 0, 0, 25)
        bg.BackgroundColor3 = Palette.SliderBg
        bg.BorderSizePixel = 0
        bg.Parent = c
        Instance.new("UICorner", bg).CornerRadius = UDim.new(1, 0)

        local fill = Instance.new("Frame")
        fill.Size = UDim2.new((Settings[key] - min) / (max - min), 0, 1, 0)
        fill.BackgroundColor3 = Palette.Accent
        fill.BorderSizePixel = 0
        fill.Parent = bg
        Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

        local fillGrad = Instance.new("UIGradient")
        fillGrad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0.0, Palette.Accent2),
                ColorSequenceKeypoint.new(1.0, Palette.Accent),
        })
        fillGrad.Parent = fill

        local knob = Instance.new("Frame")
        knob.Size = UDim2.new(0, 14, 0, 14)
        knob.Position = UDim2.new((Settings[key] - min) / (max - min), -7, 0.5, -7)
        knob.BackgroundColor3 = Palette.Text
        knob.BorderSizePixel = 0
        knob.Parent = bg
        Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
        local knobStroke = Instance.new("UIStroke", knob)
        knobStroke.Color = Palette.Accent
        knobStroke.Thickness = 2
        knobStroke.Parent = knob

        local dragging = false
        local function update(input)
            local pos = math.clamp((input.Position.X - bg.AbsolutePosition.X) / bg.AbsoluteSize.X, 0, 1)
            local val = math.floor(min + (max - min) * pos)
            fill.Size = UDim2.new(pos, 0, 1, 0)
            knob.Position = UDim2.new(pos, -7, 0.5, -7)
            lbl.Text = name .. ": " .. val
            Settings[key] = val
        end

        bg.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then 
                dragging = true
                main.Draggable = false
                update(i) 
            end
        end)
        UserInputService.InputChanged:Connect(function(i)
            if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then update(i) end
        end)
        UserInputService.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                if dragging then 
                    dragging = false
                    main.Draggable = true
                    saveSettings(Settings) 
                end
            end
        end)
    end

    makeSlider("Walk Speed", "WalkSpeed", 30, 90, 10)
    makeSlider("Fly Speed", "FlySpeed", 1, 100, 58)
    makeSlider("Mans Radius", "MansRadius", 10, 50, 106)

    taskspawn(function()
        while gui.Parent do
            local uptime = math.floor(tick() - Stats.StartTime)
            local mins = math.floor(uptime / 60)
            local secs = uptime % 60
            statsText.Text = string.format(
                "Uptime\n  %02d:%02d\n\nVicious Killed\n  %d\n\nStingers\n  %d\n\nStatus\n  %s",
                mins, secs, Stats.ViciousKilled, Stats.StingersCollected,
                Stats.Running and "Running" or "Stopped"
            )
            taskwait(1)
        end
    end)
end

local function huntViciousBee()
    if not Stats.Running then return end
    
    local bee = findViciousBee()
    if not bee then
        print("[Vichop] No Vicious -> hop")
        hopToRandomServer()
        return
    end
    
    if isViciousBeeNearMondo(bee) then
        print("[Vichop] Vicious near Mondo -> hop")
        hopToRandomServer()
        return
    end
    
    if not guiCreated then
        guiCreated = true
        createGUI()
        print("[Vichop] Vicious found -> GUI loaded")
    end
    
    local hive = findFreeHive()
    if not hive then
        print("[Vichop] No free hive -> hop")
        hopToRandomServer()
        return
    end
    
    local platform = hive:FindFirstChild("Platform")
    local target = (platform and platform.Value) and platform.Value or hive
    if not flyTo(target, Vector3.new(0, 3, 0)) then
        print("[Vichop] Failed to reach hive -> hop")
        hopToRandomServer()
        return
    end
    taskwait(0.5)
    
    local tries, claimed = 0, false
    while tries < 3 do
        pressE(hive)
        taskwait(1.2)
        local o = hive:FindFirstChild("Owner")
        if o and o.Value == player then claimed = true; break end
        tries = tries + 1
    end
    if not claimed then
        print("[Vichop] Failed to claim hive -> hop")
        hopToRandomServer()
        return
    end
    if not bee.Parent then
        print("[Vichop] Bee disappeared -> hop")
        hopToRandomServer()
        return
    end
    
    if not flyTo(bee, Vector3.new(0, 5, 10)) then
        print("[Vichop] Failed to reach bee -> hop")
        hopToRandomServer()
        return
    end
    taskwait(0.3)
    
    local stopMansing = startMansing(bee)
    local maxWait, waited = 120, 0
    local killed = false
    
    while waited < maxWait do
        taskwait(0.3)
        waited = waited + 0.3
        
        if not Stats.Running then break end
        
        if not bee.Parent then
            killed = true
            break
        end
        
        local hum = bee:FindFirstChild("Humanoid")
        if hum and hum.Health <= 0 then
            killed = true
            local t = 0
            while bee.Parent and t < 3 do taskwait(0.1); t = t + 0.1 end
            break
        end
    end
    
    if stopMansing then stopMansing() end
    
    if killed then
        Stats.ViciousKilled = Stats.ViciousKilled + 1
        print("[Vichop] Vicious killed. Total:", Stats.ViciousKilled)
    else
        print("[Vichop] Mansing timeout -> hop")
    end
    
    Stats.StingersCollected = countStingers()
    taskwait(0.5)
    
    hopToRandomServer()
end

taskwait(2)

while true do
    if Stats.Running then
        pcall(huntViciousBee)
    end
    taskwait(0.5)
end

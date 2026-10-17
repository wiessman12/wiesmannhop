-- ====== СЕРВИСЫ ======
local Players             = game:GetService("Players")
local HttpService         = game:GetService("HttpService")
local TeleportService     = game:GetService("TeleportService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService          = game:GetService("RunService")
local UserInputService    = game:GetService("UserInputService")
local TweenService        = game:GetService("TweenService")

local lp = Players.LocalPlayer
local playerGui = lp:WaitForChild("PlayerGui")

-- ====== КОНСТАНТЫ ======
local MOUNTAIN_MONDO_RADIUS = 200
local FLY_SPEED    = 100
local WALK_SPEED   = 60
local MANSING_RADIUS = 18

getgenv().IsHopping = false
getgenv().VisitedServers = getgenv().VisitedServers or {}

-- ====== ПОИСК ОБЪЕКТОВ ======
local function findViciousBee()
    local monsters = workspace:FindFirstChild("Monsters")
    if not monsters then return nil end
    for _, obj in ipairs(monsters:GetChildren()) do
        if obj.Name:find("Vicious Bee", 1, true) then
            local h = obj:FindFirstChild("Humanoid")
            if h and h.Health > 0 then return obj end
        end
    end
end

local function findMondoChick()
    local monsters = workspace:FindFirstChild("Monsters")
    if not monsters then return nil end
    for _, obj in ipairs(monsters:GetChildren()) do
        if obj.Name:find("Mondo Chick", 1, true) then
            local h = obj:FindFirstChild("Humanoid")
            if h and h.Health > 0 then return obj end
        end
    end
end

local function shouldHopFromBee(bee)
    local mondo = findMondoChick()
    if not mondo then return false end
    local dist = (bee:GetPivot().Position - mondo:GetPivot().Position).Magnitude
    return dist < MOUNTAIN_MONDO_RADIUS
end

-- ====== УЛЕЙ ======
local function findFreeHive()
    local honeycombs = workspace:FindFirstChild("Honeycombs")
    if not honeycombs then return nil end
    for i = 1, 6 do
        local hive = honeycombs:FindFirstChild("Hive" .. i)
        if hive then
            local owner = hive:FindFirstChild("Owner")
            if owner and owner.Value == nil then
                print("[Hunt] Свободный улей:", hive.Name)
                return hive
            end
        end
    end
    print("[Hunt] Свободных ульев нет")
end

-- ====== FLY (из первого скрипта) ======
local function flyTo(target, offset)
    local success, result = pcall(function()
        local char = lp.Character
        if not char then return false end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hrp or not target or not hum then return false end

        offset = offset or Vector3.new(0, 3, 0)
        local targetPos
        if target:IsA("Model") then
            targetPos = target.PrimaryPart and target.PrimaryPart.Position or target:GetPivot().Position
        elseif target:IsA("BasePart") then
            targetPos = target.Position
        else
            return false
        end
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
        ap.MaxVelocity = Settings and Settings.FlySpeed or FLY_SPEED
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
        while tick() - start < 5 do
            if not hrp or not hrp.Parent then break end
            if (hrp.Position - targetPos).Magnitude < 5 then break end
            task.wait(0.05)
        end

        noclip:Disconnect(); ap:Destroy(); ao:Destroy()
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = true end
        end
        hum:ChangeState(Enum.HumanoidStateType.Freefall)
        return (hrp.Position - targetPos).Magnitude < 30
    end)
    if not success then return false end
    return result
end

-- ====== ЗАХВАТ УЛЬЯ ======
local function occupyHive(hive)
    local prompt = hive:FindFirstChildOfClass("ProximityPrompt")
    if not prompt then
        for _, d in ipairs(hive:GetDescendants()) do
            if d:IsA("ProximityPrompt") then prompt = d break end
        end
    end

    if prompt and fireproximityprompt then
        pcall(fireproximityprompt, prompt)
        return true
    end

    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
    end)
    return true
end

-- ====== МАНСИНГ (из первого скрипта) ======
local function startMansing(bee)
    local running = true
    local connection
    local angle = 0
    local lastJump, lastMoveTime = 0, 0
    local lastTarget = Vector3.zero
    local zigzagPhase = 0

    local char0 = lp.Character
    if char0 then
        local hum0 = char0:FindFirstChildOfClass("Humanoid")
        if hum0 then hum0.PlatformStand = false; hum0.WalkSpeed = 16 end
        local hrp0 = char0:FindFirstChild("HumanoidRootPart")
        if hrp0 then hrp0.CanCollide = true end
    end

    local startChar = lp.Character
    if startChar and bee and bee.Parent then
        local h, b = startChar:FindFirstChild("HumanoidRootPart"), bee:FindFirstChild("HumanoidRootPart")
        if h and b then
            local v = h.Position - b.Position
            if v.Magnitude > 1 then angle = math.atan2(v.Z, v.X) end
        end
    end

    connection = RunService.RenderStepped:Connect(function(dt)
        if not running then return end
        dt = math.min(dt, 0.05)
        local char = lp.Character
        if not char then return end
        local hrp, hum = char:FindFirstChild("HumanoidRootPart"), char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or not bee or not bee.Parent then return end

        local ws = Settings and Settings.WalkSpeed or WALK_SPEED
        local mr = Settings and Settings.MansRadius or MANSING_RADIUS
        hum.PlatformStand = false; hrp.CanCollide = true; hum.WalkSpeed = ws
        local beeHrp = bee:FindFirstChild("HumanoidRootPart")
        if not beeHrp then return end

        if (hrp.Position - beeHrp.Position).Magnitude > 100 then
            flyTo(bee, Vector3.new(0, 3, 0))
            return
        end

        local now = tick()
        if now - lastJump > 1.2 then
            local st = hum:GetState()
            if st == Enum.HumanoidStateType.Running or st == Enum.HumanoidStateType.Landed then hum.Jump = true end
            lastJump = now
        end

        local particles = workspace:FindFirstChild("Particles")
        local thorn = particles and particles:FindFirstChild("WTs")
        local thornPos = nil
        if thorn then
            local wt = thorn:FindFirstChild("WaitingThorn")
            if wt and wt.Parent then thornPos = wt.Position end
        end

        zigzagPhase = zigzagPhase + dt * 5
        local zigzag = math.sin(zigzagPhase) * 0.45
        angle = angle + (ws / mr) * dt
            local finalAngle = angle + zigzag

        local targetPos
        if thornPos then
            local dirToThorn = (thornPos - beeHrp.Position).Unit
            targetPos = thornPos - dirToThorn * 5
        else
            local offset = Vector3.new(math.cos(finalAngle) * mr, 0, math.sin(finalAngle) * mr)
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

    return function()
        running = false
        if connection then connection:Disconnect() end
        local char = lp.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then hum.PlatformStand = false; hum.WalkSpeed = 16 end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then hrp.CanCollide = true end
        end
    end
end

-- ====== ХОП ======
local function hopToRandomServer()
    if getgenv().IsHopping then return end
    getgenv().IsHopping = true
    task.wait(1.5)
    if not lp or not lp.Parent then return end

    local success, servers = pcall(function()
        return HttpService:JSONDecode(
            game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100")
        )
    end)

    if not success or not servers or not servers.data or #servers.data == 0 then
        pcall(function() TeleportService:Teleport(game.PlaceId, lp) end)
        return
    end

    local currentJobId = game.JobId
    local candidates = {}
    for _, server in ipairs(servers.data) do
        if server.id ~= currentJobId and server.playing < server.maxPlayers then
            local alreadyVisited = false
            for _, visitedId in ipairs(getgenv().VisitedServers) do
                if visitedId == server.id then alreadyVisited = true; break end
            end
            if not alreadyVisited then table.insert(candidates, server) end
        end
    end

    while #getgenv().VisitedServers > 150 do table.remove(getgenv().VisitedServers, 1) end

    if #candidates == 0 then
        pcall(function() TeleportService:Teleport(game.PlaceId, lp) end)
        return
    end

    local chosen = candidates[math.random(#candidates)]
    table.insert(getgenv().VisitedServers, chosen.id)

    local ok = pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, chosen.id, lp)
    end)
    if not ok then
        getgenv().IsHopping = false
        pcall(function() TeleportService:Teleport(game.PlaceId, lp) end)
    end
end

-- ====== НАСТРОЙКИ + МЕНЮ (из первого скрипта) ======
local Palette = {
    Background   = Color3.fromRGB(14, 22, 33),
    Card         = Color3.fromRGB(22, 34, 47),
    Accent       = Color3.fromRGB(79, 195, 247),
    Accent2      = Color3.fromRGB(38, 166, 154),
    Text         = Color3.fromRGB(224, 247, 250),
    TextDim      = Color3.fromRGB(160, 190, 200),
    SliderBg     = Color3.fromRGB(30, 45, 60),
    StrokeColor  = Color3.fromRGB(50, 80, 100),
    StopRed      = Color3.fromRGB(229, 115, 115),
    StartGreen   = Color3.fromRGB(129, 199, 132),
}

local CONFIG_FILE = "wiesmann_vichop_v3.json"

local function loadSettings()
    local defaults = {
        WalkSpeed = WALK_SPEED,
        FlySpeed = FLY_SPEED,
        MansRadius = MANSING_RADIUS,
        Running = true,
    }
    if isfile and isfile(CONFIG_FILE) then
        local ok, data = pcall(function() return HttpService:JSONDecode(readfile(CONFIG_FILE)) end)
        if ok and data then
            for k, v in pairs(data) do if defaults[k] ~= nil then defaults[k] = v end end
        end
    end
    return defaults
end

Settings = loadSettings()

local Stats = { StartTime = tick(), ViciousKilled = 0, StingersCollected = 0, Running = Settings.Running }

local function saveSettings()
    if writefile then
        pcall(function() writefile(CONFIG_FILE, HttpService:JSONEncode(Settings)) end)
    end
end

local function countStingers()
    local count = 0
    local function check(c)
        if not c then return end
        for _, i in ipairs(c:GetChildren()) do
            if i.Name:lower():find("stinger") then count = count + 1 end
        end
    end
    check(lp:FindFirstChild("Backpack"))
    check(lp.Character)
    return count
end

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

    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 42)
    titleBar.BackgroundColor3 = Palette.Card
    titleBar.BorderSizePixel = 0
    titleBar.Parent = main
    Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 12)

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

    local statsText = Instance.new("TextLabel")
    statsText.Size = UDim2.new(1, -20, 1, -20)
    statsText.Position = UDim2.new(0, 12, 0, 12)
    statsText.BackgroundTransparency = 1
    statsText.TextColor3 = Palette.Text
    statsText.Font = Enum.Font.Gotham
    statsText.TextSize = 12
    statsText.TextXAlignment = Enum.TextXAlignment.Left
    statsText.TextYAlignment = Enum.TextYAlignment.Top
    statsText.Parent = statsCard

    local settingsCard = Instance.new("Frame")
    settingsCard.Size = UDim2.new(0.58, -5, 1, 0)
    settingsCard.Position = UDim2.new(0.42, 5, 0, 0)
    settingsCard.BackgroundColor3 = Palette.Card
    settingsCard.BorderSizePixel = 0
    settingsCard.Parent = content
    Instance.new("UICorner", settingsCard).CornerRadius = UDim.new(0, 10)

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

    toggleBtn.MouseButton1Click:Connect(function()
        Stats.Running = not Stats.Running
        Settings.Running = Stats.Running
        saveSettings()
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
                if dragging then dragging = false; main.Draggable = true; saveSettings() end
            end
        end)
    end

    makeSlider("Walk Speed", "WalkSpeed", 30, 90, 10)
    makeSlider("Fly Speed", "FlySpeed", 1, 100, 58)
    makeSlider("Mans Radius", "MansRadius", 10, 50, 106)

    task.spawn(function()
        while gui.Parent do
            local uptime = math.floor(tick() - Stats.StartTime)
            Stats.StingersCollected = countStingers()
            statsText.Text = string.format(
                "Uptime\n  %02d:%02d\n\nVicious Killed\n  %d\n\nStingers\n  %d\n\nStatus\n  %s",
                math.floor(uptime / 60), uptime % 60,
                Stats.ViciousKilled, Stats.StingersCollected,
                Stats.Running and "Running" or "Stopped"
            )
                task.wait(1)
        end
    end)
end

-- ====== ОСНОВНАЯ ЛОГИКА ======
local function huntViciousBee()
    print("[Hunt] === НОВЫЙ СЕРВЕР ===")
    task.wait(2)

    local char, hrp
    for _ = 1, 30 do
        char = lp.Character
        if char and char:FindFirstChild("HumanoidRootPart") then hrp = char.HumanoidRootPart; break end
        task.wait(0.2)
    end
    if not char or not hrp then
        print("[Hunt] Персонаж не прогрузился — хоп")
        hopToRandomServer(); return
    end

    -- 1. Ищем пчелу
    print("[Hunt] Ищем Vicious Bee...")
    local bee
    for _ = 1, 20 do
        bee = findViciousBee()
        if bee then break end
        task.wait(0.4)
    end
    if not bee then
        print("[Hunt] Пчела не найдена — хоп")
        hopToRandomServer(); return
    end
    print("[Hunt] Пчела найдена:", bee.Name)

    -- 2. Проверка горы
    if shouldHopFromBee(bee) then
        print("[Hunt] Пчела на горе (рядом с Mondo) — хоп")
        hopToRandomServer(); return
    end
    print("[Hunt] Летим убивать")

    -- 3. Ищем улей
    print("[Hunt] Ищем улей...")
    local hive = findFreeHive()
    if not hive then
        print("[Hunt] Улей не найден — хоп")
        hopToRandomServer(); return
    end
    print("[Hunt] Выбран улей:", hive.Name)

    local platform = hive:FindFirstChild("Platform")
    local hiveTarget = (platform and platform.Value) or hive

    local reached = false
    for attempt = 1, 3 do
        print("[Hunt] Попытка долететь до улья:", attempt)
        local ok, flew = pcall(function() return flyTo(hiveTarget, Vector3.new(0, 3, 0)) end)
        if ok and flew then reached = true; break end
        task.wait(0.3)
    end
    if not reached then
        print("[Hunt] Не долетели до улья — хоп")
        hopToRandomServer(); return
    end
    print("[Hunt] Долетели до улья")

    -- Нажимаем E
    task.wait(0.7)
    print("[Hunt] Занимаем улей...")
    occupyHive(hive)
    task.wait(1.5)

    local owner = hive:FindFirstChild("Owner")
    local ownerValue = owner and owner.Value or nil
    if ownerValue ~= lp then
        print("[Hunt] Улей не засчитан — повтор")
        occupyHive(hive)
        task.wait(1.5)
        ownerValue = owner and owner.Value or nil
        if ownerValue ~= lp then
            print("[Hunt] Улей не занят — хоп")
            hopToRandomServer(); return
        end
    end
    print("[Hunt] Улей занят")

    -- 4. GUI (после улья)
    if not getgenv().VichopGUI then
        getgenv().VichopGUI = true
        createGUI()
        print("[Hunt] GUI создан")
    end

    -- 5. Летим к пчеле + мансинг
    local attackOk = pcall(function()
        print("[Hunt] Летим к пчеле...")
        for attempt = 1, 3 do
            if not bee or not bee.Parent then break end
            if flyTo(bee, Vector3.new(0, 5, 10)) then break end
            task.wait(0.3)
        end

        print("[Hunt] Мансинг вокруг пчелы (радиус " .. (Settings.MansRadius or MANSING_RADIUS) .. ")...")
        local stopMansing = startMansing(bee)

        local maxWait = 90
        local waited = 0
        while waited < maxWait do
            task.wait(0.3)
            waited += 0.3
            if not Stats.Running then break end
            if not bee or not bee.Parent then
                print("[Hunt] Пчела убита!")
                break
            end
            local h = bee:FindFirstChild("Humanoid")
            if h and h.Health <= 0 then
                print("[Hunt] Пчела убита!")
                break
            end
        end

        if stopMansing then stopMansing() end
    end)

    if attackOk then
        Stats.ViciousKilled = Stats.ViciousKilled + 1
        Stats.StingersCollected = countStingers()
    else
        print("[Hunt] Ошибка в фазе атаки")
    end

    print("[Hunt] Хоп на другой сервер...")
    hopToRandomServer()
end

-- ====== ОБРАБОТКА ОШИБОК ТЕЛЕПОРТА ======
TeleportService.TeleportInitFailed:Connect(function(_, result, err)
        warn("[Teleport] Ошибка:", result.Name, err, "| Код:", result.Value)
    getgenv().IsHopping = false
    task.wait(2)
    pcall(hopToRandomServer)
end)

-- ====== БЕСКОНЕЧНЫЙ ЦИКЛ ======
task.wait(5)
while true do
    if not getgenv().IsHopping then
        local ok, err = pcall(huntViciousBee)
        if not ok then
            warn("[Hunt] Ошибка в цикле:", err)
            pcall(hopToRandomServer)
        end
    end
    task.wait(1)
end

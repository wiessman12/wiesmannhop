-- ====== СЕРВИСЫ ======
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local workspace = game:GetService("Workspace")

-- Ждем загрузки игрока и GUI
local player = Players.LocalPlayer
while not player do task.wait(0.1) player = Players.LocalPlayer end
local playerGui = player:WaitForChild("PlayerGui")

-- Защита от двойного запуска
if getgenv().VichopLoaded then return end
getgenv().VichopLoaded = true

-- ====== НАСТРОЙКИ ======
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

-- ====== УТИЛИТЫ ======
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

-- ====== ХОП (С СОХРАНЕНИЕМ В ФАЙЛ) ======
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

local function hopToRandomServer(skipWait)
    if not skipWait then task.wait(1.0) end
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
        print("[Hop] Все сервера в блеклисте. Очистка...")
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

-- ====== FLY ======
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
            task.wait(0.05)
        end

        noclip:Disconnect(); ap:Destroy(); ao:Destroy()
        for _, part in ipairs(char:GetDescendants()) do if part:IsA("BasePart") then part.CanCollide = true end end
        hum:ChangeState(Enum.HumanoidStateType.Freefall)
        return (hrp.Position - targetPos).Magnitude < 30
    end)
    if not success then resetCharacterState(); return false end
    return result
end

-- ====== ПОИСК ======
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
        rayParams.FilterDescendantsInstances = {char}; rayParams.FilterType = Enum.RaycastFilterType.Exclude
        local ground = workspace:Raycast(Vector3.new(targetPos.X, targetPos.Y + 30, targetPos.Z), Vector3.new(0, -100, 0), rayParams)
        if ground then targetPos = Vector3.new(targetPos.X, ground.Position.Y + 3, targetPos.Z) end

        if now - lastMoveTime > 0.1 or (targetPos - lastTarget).Magnitude > 4 then
            hum:MoveTo(targetPos); lastMoveTime = now; lastTarget = targetPos
        end
    end)

    return function() running = false; if connection then connection:Disconnect() end; resetCharacterState() end
end

-- ====== АВТОРСКИЙ GUI ======
local function createGUI()
    local old = playerGui:FindFirstChild("wiesmann_vichop")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "wiesmann_vichop"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = playerGui

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 500, 0, 300)
    main.Position = UDim2.new(0.5, -250, 0.5, -150)
    main.BackgroundColor3 = Color3.fromRGB(18, 18, 20)
    main.BorderSizePixel = 0
    main.Active = true
    main.Draggable = true
    main.Parent = gui
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
    local stroke = Instance.new("UIStroke", main); stroke.Color = Color3.fromRGB(60, 60, 70); stroke.Thickness = 1

    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 40)
    titleBar.BackgroundColor3 = Color3.fromRGB(22, 22, 25)
    titleBar.BorderSizePixel = 0
    titleBar.Parent = main
    Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -20, 1, 0); title.Position = UDim2.new(0, 15, 0, 0)
    title.BackgroundTransparency = 1; title.Text = "wiesmann vichop"
    title.TextColor3 = Color3.fromRGB(180, 130, 255)
    title.Font = Enum.Font.GothamBold; title.TextSize = 14
    title.TextXAlignment = Enum.TextXAlignment.Left; title.Parent = titleBar

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, -20, 1, -50); content.Position = UDim2.new(0, 10, 0, 45)
    content.BackgroundTransparency = 1; content.Parent = main

    local statsCard = Instance.new("Frame")
    statsCard.Size = UDim2.new(0.4, -5, 1, 0)
    statsCard.BackgroundColor3 = Color3.fromRGB(25, 25, 30); statsCard.BorderSizePixel = 0; statsCard.Parent = content
    Instance.new("UICorner", statsCard).CornerRadius = UDim.new(0, 8)

    local statsText = Instance.new("TextLabel")
    statsText.Size = UDim2.new(1, -20, 1, -20); statsText.Position = UDim2.new(0, 10, 0, 10)
    statsText.BackgroundTransparency = 1; statsText.TextColor3 = Color3.fromRGB(200, 200, 200)
    statsText.Font = Enum.Font.Gotham; statsText.TextSize = 12; statsText.TextXAlignment = Enum.TextXAlignment.Left
    statsText.TextYAlignment = Enum.TextYAlignment.Top; statsText.Parent = statsCard

    local settingsCard = Instance.new("Frame")
    settingsCard.Size = UDim2.new(0.6, -5, 1, 0); settingsCard.Position = UDim2.new(0.4, 5, 0, 0)
    settingsCard.BackgroundColor3 = Color3.fromRGB(25, 25, 30); settingsCard.BorderSizePixel = 0; settingsCard.Parent = content
    Instance.new("UICorner", settingsCard).CornerRadius = UDim.new(0, 8)

    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Size = UDim2.new(1, -20, 0, 35); toggleBtn.Position = UDim2.new(0, 10, 1, -45)
    toggleBtn.BackgroundColor3 = Stats.Running and Color3.fromRGB(180, 60, 60) or Color3.fromRGB(60, 180, 60)
    toggleBtn.Text = Stats.Running and "STOP" or "START"
    toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255); toggleBtn.Font = Enum.Font.GothamBold; toggleBtn.TextSize = 13
    toggleBtn.Parent = settingsCard; Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 6)

    toggleBtn.MouseButton1Click:Connect(function()
        Stats.Running = not Stats.Running; Settings.Running = Stats.Running; saveSettings(Settings)
        toggleBtn.Text = Stats.Running and "STOP" or "START"
        toggleBtn.BackgroundColor3 = Stats.Running and Color3.fromRGB(180, 60, 60) or Color3.fromRGB(60, 180, 60)
    end)

    local function makeSlider(name, key, min, max, yPos)
        local c = Instance.new("Frame")
        c.Size = UDim2.new(1, -20, 0, 35); c.Position = UDim2.new(0, 10, 0, yPos)
        c.BackgroundTransparency = 1; c.Parent = settingsCard

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 0, 15); lbl.BackgroundTransparency = 1
        lbl.Text = name .. ": " .. Settings[key]; lbl.TextColor3 = Color3.fromRGB(200, 200, 200)
        lbl.Font = Enum.Font.Gotham; lbl.TextSize = 11; lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = c

        local bg = Instance.new("Frame")
        bg.Size = UDim2.new(1, 0, 0, 6); bg.Position = UDim2.new(0, 0, 0, 22); bg.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
        bg.BorderSizePixel = 0; bg.Parent = c; Instance.new("UICorner", bg).CornerRadius = UDim.new(1, 0)

        local fill = Instance.new("Frame")
        fill.Size = UDim2.new((Settings[key] - min) / (max - min), 0, 1, 0); fill.BackgroundColor3 = Color3.fromRGB(180, 130, 255)
        fill.BorderSizePixel = 0; fill.Parent = bg; Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

        local knob = Instance.new("Frame")
        knob.Size = UDim2.new(0, 12, 0, 12); knob.Position = UDim2.new((Settings[key] - min) / (max - min), -6, 0.5, -6)
        knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255); knob.BorderSizePixel = 0; knob.Parent = bg
        Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

        local dragging = false
        local function update(input)
            local pos = math.clamp((input.Position.X - bg.AbsolutePosition.X) / bg.AbsoluteSize.X, 0, 1)
            local val = math.floor(min + (max - min) * pos)
            fill.Size = UDim2.new(pos, 0, 1, 0); knob.Position = UDim2.new(pos, -6, 0.5, -6)
            lbl.Text = name .. ": " .. val; Settings[key] = val
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
    makeSlider("Fly Speed", "FlySpeed", 1, 100, 50)
    makeSlider("Mans Radius", "MansRadius", 10, 50, 90)

    task.spawn(function()
        while gui.Parent do
            local uptime = math.floor(tick() - Stats.StartTime)
            local mins = math.floor(uptime / 60); local secs = uptime % 60
            statsText.Text = string.format("Uptime: %02d:%02d\nVicious Killed: %d\nStingers: %d\nStatus: %s", 
                mins, secs, Stats.ViciousKilled, Stats.StingersCollected, Stats.Running and "Running" or "Stopped")
            task.wait(1)
        end
    end)
end

-- ====== ГЛАВНЫЙ ЦИКЛ ======
local function huntViciousBee()
    if not Stats.Running then return end
    
    -- Мгновенная проверка: есть ли Vicious на этом сервере?
    local bee = findViciousBee()
    if not bee then
        print("[Vichop] Vicious не найден -> хоп")
    hopToRandomServer(true) -- skipWait = true для мгновенного хопа
        return
    end
    
    -- Мгновенная проверка: не на горе ли (рядом с Mondo)?
    if isViciousBeeNearMondo(bee) then
        print("[Vichop] Vicious на горе (Mondo) -> хоп")
        hopToRandomServer(true)
        return
    end
    
    -- Меню создаём ТОЛЬКО после того, как убедились — пчела есть
    if not guiCreated then
        guiCreated = true
        createGUI()
        print("[Vichop] Vicious найден -> загрузка меню")
    end
    
    -- Улей
    local hive = findFreeHive()
    if not hive then
        print("[Vichop] Нет свободного улья -> хоп")
        hopToRandomServer(true)
        return
    end
    
    local platform = hive:FindFirstChild("Platform")
    local target = (platform and platform.Value) and platform.Value or hive
    if not flyTo(target, Vector3.new(0, 3, 0)) then
        print("[Vichop] Не долетел до улья -> хоп")
        hopToRandomServer(true)
        return
    end
    task.wait(0.5)
    
    -- Занимаем улей
    local tries, claimed = 0, false
    while tries < 3 do
        pressE(hive)
        task.wait(1.2)
        local o = hive:FindFirstChild("Owner")
        if o and o.Value == player then claimed = true; break end
        tries = tries + 1
    end
    if not claimed then
        print("[Vichop] Не удалось занять улей -> хоп")
        hopToRandomServer(true)
        return
    end
    
    -- Пчела могла умереть/исчезнуть пока занимали улей
    if not bee.Parent then
        print("[Vichop] Пчела исчезла -> хоп")
        hopToRandomServer(true)
        return
    end
    
    -- Летим к пчеле
    if not flyTo(bee, Vector3.new(0, 5, 10)) then
        print("[Vichop] Не долетел до пчелы -> хоп")
        hopToRandomServer(true)
        return
    end
    task.wait(0.3)
    
    -- Мансим и бьём, пока bee.Parent не станет nil (как в Atlas)
    local stopMansing = startMansing(bee)
    local maxWait, waited = 120, 0
    local killed = false
    
    while waited < maxWait do
        task.wait(0.3)
        waited = waited + 0.3
        
        if not Stats.Running then break end
        
        -- ГЛАВНЫЙ ДЕТЕКТ: модель удалена сервером = убит
        if not bee.Parent then
            killed = true
            break
        end
        
        -- Дополнительный ранний сигнал: Health <= 0 (на случай задержки удаления)
        local hum = bee:FindFirstChild("Humanoid")
        if hum and hum.Health <= 0 then
            killed = true
            -- ждём реального удаления модели, чтобы не телепортнуться раньше
            local t = 0
            while bee.Parent and t < 3 do task.wait(0.1); t = t + 0.1 end
            break
        end
    end
    
    if stopMansing then stopMansing() end
    
    if killed then
        Stats.ViciousKilled = Stats.ViciousKilled + 1
        print("[Vichop] Vicious убит. Всего:", Stats.ViciousKilled)
    else
        print("[Vichop] Таймаут мансинга -> хоп")
    end
    
    Stats.StingersCollected = countStingers()
    task.wait(0.5)
    
    -- После убийства — хоп дальше (с задержкой 1с, чтобы успело прогрузиться)
    hopToRandomServer()
end

-- ====== ЗАПУСК ======
task.wait(2)

-- Мгновенный цикл: как только сервер загрузился — сразу проверка
while true do
    if Stats.Running then
        pcall(huntViciousBee)
    end
    task.wait(0.5) -- ускорено с 2 для мгновенной реакции
end

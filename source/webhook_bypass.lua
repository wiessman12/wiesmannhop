-- ====== CONFIG ======
getgenv().ServerHopConfig = {
    TeleportTimeout = 15,
    RatelimitCooldown = 12,
    MaxBlacklistSize = 300,
    CacheExpiration = 200,
    MinPlayers = 0,
    MaxPing = 100,
    WebhookURL = ""
}

-- ====== SERVICES ======
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer

-- ====== ХОП ======
local function hopToRandomServer()
    task.wait(5) -- задержка 5 секунд перед хопом
    local success, servers = pcall(function()
        return HttpService:JSONDecode(
            game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100")
        )
    end)

    if not success or not servers or not servers.data then
        TeleportService:Teleport(game.PlaceId, player)
        return
    end

    local currentJobId = game.JobId
    local candidates = {}

    for _, server in ipairs(servers.data) do
        if server.id ~= currentJobId
           and server.playing < server.maxPlayers
           and server.playing >= 1 then
            table.insert(candidates, server)
        end
    end

    if #candidates == 0 then
        TeleportService:Teleport(game.PlaceId, player)
        return
    end

    local chosen = candidates[math.random(1, #candidates)]
    TeleportService:TeleportToPlaceInstance(game.PlaceId, chosen.id, player)
end

-- ====== ПОИСК ПЧЕЛЫ ======
local function findViciousBee()
    local monsters = workspace:FindFirstChild("Monsters")
    if not monsters then return nil end
    for _, obj in ipairs(monsters:GetChildren()) do
        if obj.Name:find("Vicious Bee") then
            local humanoid = obj:FindFirstChild("Humanoid")
            if humanoid and humanoid.Health > 0 then
                return obj
            end
        end
    end
    return nil
end

-- ====== ПОИСК УЛЬЯ ======
local function findFreeHive()
    local honeycombs = workspace:FindFirstChild("Honeycombs")
    if not honeycombs then return nil end

    for i = 1, 6 do
        local hive = honeycombs:FindFirstChild("Hive" .. i)
        if hive and hive:FindFirstChild("Gui") and hive.Gui:FindFirstChild("Display") and hive.Gui.Display:FindFirstChild("Frame") then
            local ownerName = hive.Gui.Display.Frame:FindFirstChild("OwnerName")
            if ownerName and ownerName.Text == player.Name then
                return hive
            end
        end
    end

    for i = 1, 6 do
        local hive = honeycombs:FindFirstChild("Hive" .. i)
        if hive and hive:FindFirstChild("Gui") and hive.Gui:FindFirstChild("Display") and hive.Gui.Display:FindFirstChild("Frame") then
            local ownerName = hive.Gui.Display.Frame:FindFirstChild("OwnerName")
            if ownerName and ownerName.Text == "" then
                return hive
            end
        end
    end
    return nil
end

-- ====== ПОЛУЧЕНИЕ ЦЕЛИ ======
local function getTargetPart(target)
    if not target then return nil end
    if target:IsA("Model") then
        return target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
    elseif target:IsA("BasePart") then
        return target
    end
    return nil
end

-- ====== БЫСТРЫЙ ТВИН (полёт) ======
local function flyTo(target, offset)
    local char = player.Character
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    local targetPart = getTargetPart(target)
    if not targetPart then return false end

    offset = offset or Vector3.new(0, 5, 0)
    local targetPos = targetPart.Position + offset
    local distance = (hrp.Position - targetPos).Magnitude
    local speed = 200 -- быстрый полёт (200 studs/сек)
    local duration = math.clamp(distance / speed, 0.3, 1.5)
    local tween = TweenService:Create(
        hrp,
        TweenInfo.new(duration, Enum.EasingStyle.Linear),
        { CFrame = CFrame.new(targetPos) }
    )
    tween:Play()
    tween.Completed:Wait()
    return true
end

-- ====== НАЖАТИЕ E ======
local function pressE()
    pcall(function()
        local VirtualInputManager = game:GetService("VirtualInputManager")
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
        task.wait(0.1)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
    end)
    pcall(function()
        if keypress then
            keypress(0x45)
            task.wait(0.1)
            keyrelease(0x45)
        end
    end)
end

-- ====== МАНСИНГ (быстрый, резкий) ======
local function startWalkingMansing(bee)
    local char = player.Character
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    local running = true

    task.spawn(function()
        local angle = 0
        local radius = 20 -- УВЕЛИЧЕН радиус

        while running do
            if not player.Character then break end
            local currentHumanoid = player.Character:FindFirstChildOfClass("Humanoid")
            if not currentHumanoid or currentHumanoid.Health <= 0 then break end
            if not bee.Parent then break end

            local beeHrp = bee:FindFirstChild("HumanoidRootPart")
            if not beeHrp then break end

            angle = angle + math.rad(120) -- БОЛЕЕ РЕЗКИЕ движения (120° за шаг)
            local offsetX = math.cos(angle) * radius
            local offsetZ = math.sin(angle) * radius
            local targetPos = beeHrp.Position + Vector3.new(offsetX, 0, offsetZ)

            currentHumanoid:MoveTo(targetPos)
            task.wait(0.25) -- БЫСТРЕЕ (0.25 сек вместо 0.4)
        end
    end)

    return function()
        running = false
        local char = player.Character
        if char then
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid:MoveTo(char.HumanoidRootPart.Position)
            end
        end
    end
end

-- ====== ОСНОВНАЯ ЛОГИКА ======
local function huntViciousBee()
    print("[Hunt] Новый сервер. Поиск пчелы...")

    local bee = findViciousBee()
    if not bee then
        print("[Hunt] Пчела не найдена. Хоп...")
        hopToRandomServer()
        return
    end

    print("[Hunt] ✅ Пчела найдена:", bee.Name)

    -- Ищем улей
    local hive = findFreeHive()
    if hive then
        print("[Hunt] Улей:", hive.Name)
        local platform = hive:FindFirstChild("Platform")
        if platform then
            flyTo(platform, Vector3.new(0, 5, 0))
            task.wait(2)
            pressE()
            task.wait(2)

            local ownerName = hive.Gui.Display.Frame:FindFirstChild("OwnerName")
            if ownerName and ownerName.Text == player.Name then
                print("[Hunt] ✅ Улей занят")
            else
                print("[Hunt] ⚠️ Улей не засчитан")
                pressE()
                task.wait(2)
            end
        else
            flyTo(hive, Vector3.new(0, 5, 0))
            task.wait(2)
            pressE()
            task.wait(2)
        end
    else
        print("[Hunt] ⚠️ Улей не найден")
    end

    -- Летим к пчеле
    print("[Hunt] Летим к пчеле...")
    flyTo(bee, Vector3.new(0, 5, 15))
    task.wait(0.5)

    -- Мансинг
    print("[Hunt] Мансинг 25 сек...")
    local stopMansing = startWalkingMansing(bee)
    task.wait(25)
    if stopMansing then stopMansing() end

    print("[Hunt] Завершено. Хоп...")
    hopToRandomServer()
end

-- ====== АВТО-ЗАПУСК ======
task.spawn(function()
    task.wait(5)
    while true do
        pcall(huntViciousBee)
        task.wait(5) -- задержка 5 секунд между циклами
    end
end)

print("[Vicious Bee Hunter] Запущен.")

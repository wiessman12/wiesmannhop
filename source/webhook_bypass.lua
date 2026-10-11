-- ====== SERVICES ======
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService = game:GetService("RunService")

getgenv().VisitedServers = getgenv().VisitedServers or {}
getgenv().IsHopping = false

local HOP_DELAY = 5
local FLY_HEIGHT = 600
local MOUNTAIN_MONDO_RADIUS = 200
local MANSING_RADIUS = 30
local MANSING_MAX_DIST = 45
local SERVER_FETCH_LIMIT = 100

-- ====== HTTP ======
local function httpGet(url)
    if request then
        local ok, res = pcall(request, {Url = url, Method = "GET"})
        if ok and res and res.Body then return res.Body end
    end
    if game.HttpGet then
        return game:HttpGet(url)
    end
end

-- ====== СБОР СПИСКА ДОСТУПНЫХ СЕРВЕРОВ ======
local function fetchAvailableServers()
    local body = httpGet("https://games.roblox.com/v1/games/" ..
        game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=" .. SERVER_FETCH_LIMIT)

    if not body then return {} end
    local ok, decoded = pcall(HttpService.JSONDecode, HttpService, body)
    if not ok or not decoded or not decoded.data then return {} end

    local currentJobId = game.JobId
    local available = {}

    for _, server in ipairs(decoded.data) do
        -- Только доступные: не текущий + есть свободные слоты
        if server.id ~= currentJobId and server.playing < server.maxPlayers then
            -- Только не посещённые
            local visited = false
            for _, v in ipairs(getgenv().VisitedServers) do
                if v == server.id then visited = true break end
            end
            if not visited then
                table.insert(available, server)
            end
        end
    end

    return available
end

-- ====== ХОП ======
local function hopToRandomServer()
    if getgenv().IsHopping then return end
    getgenv().IsHopping = true

    print("[Hop] Ждём " .. HOP_DELAY .. " сек перед хопом...")
    task.wait(HOP_DELAY)

    local lp = Players.LocalPlayer
    if not lp then return end

    -- Собираем доступные не посещённые серверы
    local available = fetchAvailableServers()

    if #available == 0 then
        print("[Hop] Все серверы посещены — сброс истории")
        getgenv().VisitedServers = {}
        available = fetchAvailableServers()
    end

    -- Fallback: если и после сброса пусто — телепорт в случайный
    if #available == 0 then
        print("[Hop] Нет доступных серверов — Teleport в случайный")
        local ok = pcall(function()
            TeleportService:Teleport(game.PlaceId, lp)
        end)
        if not ok then
            print("[Hop] Teleport тоже не сработал")
            getgenv().IsHopping = false
        end
        return
    end

    -- Перемешиваем список для случайности
    for i = #available, 2, -1 do
        local j = math.random(i)
        available[i], available[j] = available[j], available[i]
    end

    -- Пробуем серверы по очереди, пока один не сработает
    for _, chosen in ipairs(available) do
        print("[Hop] Пробуем сервер:", chosen.id,
            "| игроков:", chosen.playing .. "/" .. chosen.maxPlayers,
            "| доступно:", #available)

        table.insert(getgenv().VisitedServers, chosen.id)

        -- Способ 1: TeleportToPlaceInstance (старый, надёжный)
        local ok = pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, chosen.id, lp)
        end)

        if ok then
            print("[Hop] ✅ TeleportToPlaceInstance отправлен")
            return
        end

        -- Способ 2: TeleportAsync без options
        print("[Hop] TeleportToPlaceInstance не сработал — TeleportAsync")
        local ok2 = pcall(function()
            TeleportService:TeleportAsync(game.PlaceId, {lp})
        end)
        if ok2 then
            print("[Hop] ✅ TeleportAsync отправлен")
            return
        end

        print("[Hop] ❌ Оба способа упали, берём следующий")
        task.wait(0.5)
    end
    -- Все серверы упали — телепорт в случайный
    print("[Hop] Все серверы провалились — Teleport в случайный")
    pcall(function()
        TeleportService:Teleport(game.PlaceId, lp)
    end)
end

-- ====== ПОИСК ОБЪЕКТОВ ======
local function findViciousBee()
    local monsters = workspace:FindFirstChild("Monsters")
    if not monsters then return nil end
    for _, obj in ipairs(monsters:GetChildren()) do
        if obj.Name:find("Vicious Bee") then
            local h = obj:FindFirstChild("Humanoid")
            if h and h.Health > 0 then return obj end
        end
    end
end

local function findMondoChick()
    local monsters = workspace:FindFirstChild("Monsters")
    if not monsters then return nil end
    for _, obj in ipairs(monsters:GetChildren()) do
        if obj.Name:find("Mondo Chick") then
            local h = obj:FindFirstChild("Humanoid")
            if h and h.Health > 0 then return obj end
        end
    end
end

-- Mondo найден и пчела рядом → она на горе → хоп
-- Mondo НЕ найден → летим куда угодно
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
                print("[Hunt] ✅ Свободный улей:", hive.Name)
                return hive
            end
        end
    end
    print("[Hunt] ❌ Свободных ульев нет")
end

-- ====== ТОЧЕЧНОЕ ОТКЛЮЧЕНИЕ КОЛЛИЗИЙ ======
local function disableCollisionsNear(pos, radius)
    local disabled = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and obj.CanCollide then
            if (obj.Position - pos).Magnitude <= radius then
                disabled[obj] = true
                obj.CanCollide = false
            end
        end
    end
    return disabled
end

local function restoreCollisions(disabled)
    for obj in pairs(disabled) do
        if obj and obj.Parent then
            obj.CanCollide = true
        end
    end
end

-- ====== FLY НАД КАРТОЙ ======
local function flyOverhead(target, targetOffset)
    targetOffset = targetOffset or Vector3.new(0, 3, 0)
    local lp = Players.LocalPlayer
    local char = lp.Character
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp or not target then return false end

    local targetPos
    if target:IsA("Model") then
        targetPos = target:GetPivot().Position
    elseif target:IsA("BasePart") then
        targetPos = target.Position
    else
        return false
    end

    local finalPos = targetPos + targetOffset
    local flyY = math.max(FLY_HEIGHT, hrp.Position.Y + 200, finalPos.Y + 200)

    -- ФАЗА 1: ПОДЪЁМ
    do
        local bv = Instance.new("BodyVelocity")
        bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        bv.P = 10000
        bv.Parent = hrp

        local goal = Vector3.new(hrp.Position.X, flyY, hrp.Position.Z)
        local start = tick()
        while tick() - start < 3 do
            if not hrp or not hrp.Parent then break end
            local d = (hrp.Position - goal).Magnitude
            if d < 5 then break end
            bv.Velocity = (goal - hrp.Position).Unit * 400
            task.wait(0.02)
        end
        bv:Destroy()
    end

    if not hrp or not hrp.Parent then return false end

    -- ФАЗА 2: ГОРИЗОНТАЛЬНЫЙ ПОЛЁТ
    do
        local bv = Instance.new("BodyVelocity")
        bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        bv.P = 10000
        bv.Parent = hrp
        local goal = Vector3.new(finalPos.X, flyY, finalPos.Z)
        local start = tick()
        while tick() - start < 10 do
            if not hrp or not hrp.Parent then break end
            local d = (hrp.Position - goal).Magnitude
            if d < 5 then break end

            local speed = 500
            if d < 50 then speed = 200 end
            bv.Velocity = (goal - hrp.Position).Unit * speed
            task.wait(0.02)
        end
        bv:Destroy()
    end

    if not hrp or not hrp.Parent then return false end

    -- ФАЗА 3: СПУСК
    local disabled = disableCollisionsNear(finalPos, 40)
    do
        local bv = Instance.new("BodyVelocity")
        bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        bv.P = 10000
        bv.Parent = hrp

        local start = tick()
        while tick() - start < 5 do
            if not hrp or not hrp.Parent then break end
            local d = (hrp.Position - finalPos).Magnitude
            if d < 3 then break end

            local speed = 300
            if d < 15 then speed = 100 end
            if d < 5 then speed = 40 end
            bv.Velocity = (finalPos - hrp.Position).Unit * speed
            task.wait(0.02)
        end
        bv:Destroy()
    end

    if hrp and hrp.Parent then
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end

    task.wait(0.5)
    restoreCollisions(disabled)

    if not hrp or not hrp.Parent then return false end
    return (hrp.Position - finalPos).Magnitude < 30
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

-- ====== МАНСИНГ БЕГОМ ======
local function startMansing(bee)
    local running = true

    task.spawn(function()
        local angle = 0
        while running do
            local lp = Players.LocalPlayer
            local char = lp.Character
            if not char then task.wait(0.1) continue end

            local humanoid = char:FindFirstChildOfClass("Humanoid")
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if not humanoid or not hrp or humanoid.Health <= 0 then
                task.wait(0.1) continue
            end

            if not bee.Parent then break end
            local beeHum = bee:FindFirstChild("Humanoid")
            local beeHrp = bee:FindFirstChild("HumanoidRootPart")
            if not beeHum or beeHum.Health <= 0 or not beeHrp then break end

            local dist = (hrp.Position - beeHrp.Position).Magnitude

            if dist > MANSING_MAX_DIST then
                print("[Mansing] Отлетели (" .. math.floor(dist) .. ") — возвращаемся")
                flyOverhead(bee, Vector3.new(MANSING_RADIUS, 3, 0))
            else
                angle += math.rad(140)
                local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * MANSING_RADIUS
                humanoid:MoveTo(beeHrp.Position + offset)
            end

            task.wait(0.1)
        end
    end)

    return function() running = false end
end

-- ====== ОСНОВНАЯ ЛОГИКА ======
local function huntViciousBee()
    print("[Hunt] === НОВЫЙ СЕРВЕР ===")
    task.wait(2)

    -- Ждём прогрузки персонажа
    local lp = Players.LocalPlayer
    local char, hrp
    for _ = 1, 30 do
        char = lp.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            hrp = char.HumanoidRootPart
            break
        end
        task.wait(0.2)
    end
    if not char or not hrp then
        print("[Hunt] Персонаж не прогрузился — хоп")
        hopToRandomServer()
        return
    end

    -- Ищем пчелу
    print("[Hunt] Ищем Vicious Bee...")
    local bee = findViciousBee()
    if not bee then
        print("[Hunt] Пчела не найдена — хоп")
        hopToRandomServer()
        return
    end
    print("[Hunt] ✅ Пчела найдена:", bee.Name)

    -- Проверка горы
    if shouldHopFromBee(bee) then
        print("[Hunt] Пчела на горе (рядом с Mondo) — хоп")
        hopToRandomServer()
        return
    end
    print("[Hunt] Летим убивать")

    -- Ищем улей
    print("[Hunt] Ищем улей...")
    local hive = findFreeHive()
    if not hive then
        print("[Hunt] Улей не найден — хоп")
        hopToRandomServer()
        return
    end
    print("[Hunt] ✅ Выбран улей:", hive.Name)

    -- Летим к улью
    local platform = hive:FindFirstChild("Platform")
    local hiveTarget = (platform and platform.Value) or hive

    local reached = false
    for attempt = 1, 3 do
        print("[Hunt] Попытка долететь до улья:", attempt)
        local ok, flew = pcall(function()
            return flyOverhead(hiveTarget, Vector3.new(0, 3, 0))
        end)
        if ok and flew then
            reached = true
            break
        end
        task.wait(0.3)
    end
    if not reached then
        print("[Hunt] Не долетели до улья — хоп")
        hopToRandomServer()
        return
    end
    print("[Hunt] ✅ Долетели до улья")

    -- Занимаем улей
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
            hopToRandomServer()
            return
        end
    end
    print("[Hunt] ✅ Улей занят")

    -- Летим к пчеле + мансинг + ожидание
    local attackOk = pcall(function()
        print("[Hunt] Летим к пчеле...")
        for attempt = 1, 3 do
            if flyOverhead(bee, Vector3.new(0, 5, 15)) then break end
            task.wait(0.3)
        end

        print("[Hunt] Мансинг вокруг пчелы...")
        local stopMansing = startMansing(bee)

        local maxWait = 90
        local waited = 0
        while waited < maxWait do
            task.wait(0.3)
            waited += 0.3

            local h = bee:FindFirstChild("Humanoid")
            if not bee.Parent or not h or h.Health <= 0 then
                print("[Hunt] ✅ Пчела убита!")
                break
            end
        end

        if stopMansing then stopMansing() end
    end)

    if not attackOk then
        print("[Hunt] Ошибка в фазе атаки — хоп")
    end

    print("[Hunt] Хоп на другой сервер...")
    hopToRandomServer()
end

-- ====== ОБРАБОТКА ОШИБОК ТЕЛЕПОРТА ======
TeleportService.TeleportInitFailed:Connect(function(_, result, err)
    warn("[Teleport] Ошибка:", result.Name, err, "| Код:", result.Value)

    -- Сбрасываем флаг, чтобы можно было попробовать снова
    getgenv().IsHopping = false

    -- При любой ошибке — пробуем хопнуть ещё раз через паузу
    task.wait(2)
    pcall(hopToRandomServer)
end)

-- ====== ДИАГНОСТИКА (можно удалить после проверки) ======
print("[Debug] TeleportAsync есть:", typeof(TeleportService.TeleportAsync))
print("[Debug] TeleportToPlaceInstance есть:", typeof(TeleportService.TeleportToPlaceInstance))
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

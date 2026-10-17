-- ====== SERVICES ======
local Players             = game:GetService("Players")
local HttpService         = game:GetService("HttpService")
local TeleportService     = game:GetService("TeleportService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService          = game:GetService("RunService")

-- ====== НАСТРОЙКИ ======
local HOP_DELAY             = 1
local MOUNTAIN_MONDO_RADIUS = 200
local MANSING_RADIUS        = 14
local WALK_SPEED            = 60
local FLY_SPEED             = 50
local SERVER_FETCH_LIMIT    = 100
local MAX_HISTORY           = 500  -- храним до 500 серверов
local HISTORY_FILE          = "vichop_history.json"
local CURRENT_FILE          = "vichop_current.txt"

-- ====== HTTP ======
local function httpGet(url)
    if request then
        local ok, res = pcall(request, {Url = url, Method = "GET"})
        if ok and res and res.Body then return res.Body end
    end
    if game.HttpGet then
        local ok, body = pcall(game.HttpGet, game, url)
        if ok then return body end
    end
    return nil
end

-- ====== ИСТОРИЯ В ФАЙЛЕ ======
local function loadHistory()
    if isfile and isfile(HISTORY_FILE) then
        local ok, data = pcall(function() return HttpService:JSONDecode(readfile(HISTORY_FILE)) end)
        if ok and type(data) == "table" then return data end
    end
    return {}
end

local function saveHistory(history)
    if writefile then
        pcall(function() writefile(HISTORY_FILE, HttpService:JSONEncode(history)) end)
    end
end

local function addToHistory(jobId)
    if not jobId or jobId == "" then return end
    local history = loadHistory()
    for _, id in ipairs(history) do
        if id == jobId then return end
    end
    table.insert(history, jobId)
    -- обрезаем старые
    while #history > MAX_HISTORY do
        table.remove(history, 1)
    end
    saveHistory(history)
    print("[History] Добавлен сервер. Всего в истории:", #history)
end

local function isInHistory(jobId)
    local history = loadHistory()
    for _, id in ipairs(history) do
        if id == jobId then return true end
    end
    return false
end

-- ====== ТЕКУЩИЙ СЕРВЕР ======
local function saveCurrentJob()
    if writefile then
        pcall(function() writefile(CURRENT_FILE, game.JobId) end)
    end
end

local function getLastJob()
    if isfile and isfile(CURRENT_FILE) then
        local ok, data = pcall(readfile, CURRENT_FILE)
        if ok then return data end
    end
    return nil
end

-- ====== ПРОВЕРКА: ПОПАЛИ ЛИ НА ТОТ ЖЕ СЕРВЕР ======
local function checkSameServer()
    local last = getLastJob()
    if last and last == game.JobId then
        return true
    end
    return false
end

-- ====== СБОР СПИСКА ДОСТУПНЫХ СЕРВЕРОВ ======
local function fetchAvailableServers()
    -- Рандомизируем сортировку, чтобы получать разные серверы
    local order = (math.random(1, 2) == 1) and "Asc" or "Desc"
    local url = "https://games.roblox.com/v1/games/" ..
        game.PlaceId .. "/servers/Public?sortOrder=" .. order ..
        "&limit=" .. SERVER_FETCH_LIMIT

    local body = httpGet(url)
    if not body then return {} end

    local ok, decoded = pcall(HttpService.JSONDecode, HttpService, body)
    if not ok or not decoded or not decoded.data then return {} end

    local currentJobId = game.JobId
    local history = loadHistory()
    local available = {}

    -- Собираем только серверы, которых НЕТ в истории и которые НЕ текущий
    for _, server in ipairs(decoded.data) do
        if server.id ~= currentJobId and server.playing < server.maxPlayers then
            local inHistory = false
            for _, id in ipairs(history) do
                if id == server.id then inHistory = true; break end
            end
            if not inHistory then
                table.insert(available, server)
            end
        end
    end

    -- Если все серверы в истории — очищаем историю (начинаем заново)
    if #available == 0 and #history > 0 then
        print("[Hop] Все серверы в истории — очищаем историю")
        saveHistory({})
        for _, server in ipairs(decoded.data) do
            if server.id ~= currentJobId and server.playing < server.maxPlayers then
                table.insert(available, server)
            end
        end
    end

    return available
end

-- ====== ХОП ======
getgenv().IsHopping = getgenv().IsHopping or false

local function hopToRandomServer(reason)
    if getgenv().IsHopping then
        print("[Hop] Уже хопаем — пропуск")
        return
    end
    getgenv().IsHopping = true

    print("[Hop] Причина:", reason or "manual")
    local lp = Players.LocalPlayer
    if not lp then
        getgenv().IsHopping = false
        return
    end

    -- Запоминаем текущий сервер в историю
    addToHistory(game.JobId)
    saveCurrentJob()

    task.wait(HOP_DELAY)

    local available = fetchAvailableServers()

    if #available == 0 then
        print("[Hop] Нет доступных серверов — Teleport в случайный")
        pcall(function() TeleportService:Teleport(game.PlaceId, lp) end)
        return
    end

    -- Перемешиваем
    for i = #available, 2, -1 do
        local j = math.random(i)
        available[i], available[j] = available[j], available[i]
    end

    local chosen = available[1]
    print("[Hop] Хоп на НОВЫЙ сервер:", chosen.id, "|", chosen.playing .. "/" .. chosen.maxPlayers)

    -- Пробуем телепорт
    local ok1 = pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, chosen.id, lp)
    end)
    if ok1 then
        print("[Hop] ✅ TeleportToPlaceInstance")
        return
    end

    local ok2 = pcall(function()
        TeleportService:TeleportAsync(game.PlaceId, {lp})
    end)
    if ok2 then
        print("[Hop] ✅ TeleportAsync")
        return
    end

    print("[Hop] Оба способа упали — Teleport")
    pcall(function() TeleportService:Teleport(game.PlaceId, lp) end)
end

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

-- ====== FLY ======
local function flyTo(target, offset)
    local success, result = pcall(function()
        local char = Players.LocalPlayer.Character
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
            if child.ClassName == "AlignPosition" or child.ClassName == "AlignOrientation" then
                child:Destroy()
            end
        end

        hum:ChangeState(Enum.HumanoidStateType.Freefall)
        local ap = Instance.new("AlignPosition")
        ap.Mode = Enum.PositionAlignmentMode.OneAttachment
            ap.Attachment0 = hrp:FindFirstChild("RootAttachment") or hrp.RootAttachment
        ap.Responsiveness = 200
        ap.MaxForce = math.huge
        ap.MaxVelocity = FLY_SPEED
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

-- ====== МАНСИНГ ======
local function startMansing(bee)
    local running = true
    local connection
    local angle = 0
    local lastJump, lastMoveTime = 0, 0
    local lastTarget = Vector3.zero
    local zigzagPhase = 0
    local lastAttack = 0

    local char0 = Players.LocalPlayer.Character
    if char0 then
        local hum0 = char0:FindFirstChildOfClass("Humanoid")
        if hum0 then hum0.PlatformStand = false; hum0.WalkSpeed = 16 end
        local hrp0 = char0:FindFirstChild("HumanoidRootPart")
        if hrp0 then hrp0.CanCollide = true end
    end

    local startChar = Players.LocalPlayer.Character
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
        local char = Players.LocalPlayer.Character
        if not char then return end
        local hrp, hum = char:FindFirstChild("HumanoidRootPart"), char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or not bee or not bee.Parent then return end

        hum.PlatformStand = false; hrp.CanCollide = true; hum.WalkSpeed = WALK_SPEED
        local beeHrp = bee:FindFirstChild("HumanoidRootPart")
        if not beeHrp then return end

        if (hrp.Position - beeHrp.Position).Magnitude > 100 then
            flyTo(bee, Vector3.new(0, 3, 0))
            return
        end

        local now = tick()

        -- АВТО-АТАКА
        if now - lastAttack > 0.2 then
            local tool = char:FindFirstChildOfClass("Tool")
            if tool and (hrp.Position - beeHrp.Position).Magnitude < 30 then
                pcall(function() tool:Activate() end)
                    lastAttack = now
            end
        end

        if now - lastJump > 1.2 then
            local st = hum:GetState()
            if st == Enum.HumanoidStateType.Running or st == Enum.HumanoidStateType.Landed then
                hum.Jump = true
            end
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
        angle = angle + (WALK_SPEED / MANSING_RADIUS) * dt
        local finalAngle = angle + zigzag

        local targetPos
        if thornPos then
            local dirToThorn = (thornPos - beeHrp.Position).Unit
            targetPos = thornPos - dirToThorn * 5
        else
            local offset = Vector3.new(
                math.cos(finalAngle) * MANSING_RADIUS,
                0,
                math.sin(finalAngle) * MANSING_RADIUS
            )
            targetPos = beeHrp.Position + offset
        end

        local rayParams = RaycastParams.new()
        rayParams.FilterDescendantsInstances = {char}
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        local ground = workspace:Raycast(
            Vector3.new(targetPos.X, targetPos.Y + 30, targetPos.Z),
            Vector3.new(0, -100, 0),
            rayParams
        )
        if ground then
            targetPos = Vector3.new(targetPos.X, ground.Position.Y + 3, targetPos.Z)
        end

        if now - lastMoveTime > 0.1 or (targetPos - lastTarget).Magnitude > 4 then
            hum:MoveTo(targetPos); lastMoveTime = now; lastTarget = targetPos
        end
    end)

    return function()
        running = false
        if connection then connection:Disconnect() end
        local char = Players.LocalPlayer.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then hum.PlatformStand = false; hum.WalkSpeed = 16 end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then hrp.CanCollide = true end
        end
    end
end

-- ====== ОСНОВНАЯ ЛОГИКА ======
local function huntViciousBee()
    print("[Hunt] === НОВЫЙ СЕРВЕР === JobId:", game.JobId)
    task.wait(1)

    -- Проверка: не попали ли на тот же сервер
    if checkSameServer() then
        print("[Hunt] ⚠️ Тот же сервер! Хопаем снова")
        hopToRandomServer("same server")
        return
    end
    saveCurrentJob()

    -- Ждём персонажа
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
        hopToRandomServer("no character")
        return
    end

    -- Ждём Monsters
    print("[Hunt] Ждём загрузки Monsters...")
    local monsters
    for _ = 1, 16 do
        monsters = workspace:FindFirstChild("Monsters")
        if monsters then break end
        task.wait(0.5)
    end
    if not monsters then
        print("[Hunt] Monsters не появился — хоп")
        hopToRandomServer("no monsters")
        return
    end

    -- Ищем пчелу (до 10 сек)
    print("[Hunt] Ищем Vicious Bee...")
    local bee
    for _ = 1, 20 do
        bee = findViciousBee()
        if bee then break end
        task.wait(0.5)
    end
    if not bee then
        print("[Hunt] Пчела не найдена — хоп")
        hopToRandomServer("no bee")
        return
    end
    print("[Hunt] ✅ Пчела найдена:", bee.Name)

    -- Улей
    print("[Hunt] Ищем улей...")
    local hive = findFreeHive()
    if not hive then
        print("[Hunt] Улей не найден — хоп")
        hopToRandomServer("no hive")
        return
    end
    print("[Hunt] ✅ Выбран улей:", hive.Name)

    local platform = hive:FindFirstChild("Platform")
    local hiveTarget = (platform and platform.Value) or hive

    local reached = false
    for attempt = 1, 3 do
        print("[Hunt] Попытка долететь до улья:", attempt)
        local ok, flew = pcall(function()
            return flyTo(hiveTarget, Vector3.new(0, 3, 0))
        end)
        if ok and flew then
            reached = true
            break
        end
        task.wait(0.3)
    end
    if not reached then
        print("[Hunt] Не долетели до улья — хоп")
        hopToRandomServer("hive unreachable")
        return
    end
    print("[Hunt] ✅ Долетели до улья")

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
            hopToRandomServer("hive not occupied")
            return
        end
    end
    print("[Hunt] ✅ Улей занят")

    -- Атака
    local attackOk = pcall(function()
        print("[Hunt] Летим к пчеле...")
        for attempt = 1, 3 do
            if flyTo(bee, Vector3.new(0, 5, 15)) then break end
            task.wait(0.3)
        end

        print("[Hunt] Мансинг вокруг пчелы (радиус " .. MANSING_RADIUS .. ")...")
        local stopMansing = startMansing(bee)

        local maxWait = 30
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
    task.wait(2)
    hopToRandomServer("after hunt")
end

-- ====== ОБРАБОТКА ОШИБОК ТЕЛЕПОРТА ======
TeleportService.TeleportInitFailed:Connect(function(_, result, err)
    local name = result and result.Name or "Unknown"
    local code = result and result.Value or -1
    warn("[Teleport] Ошибка:", name, err, "| Код:", code)
    getgenv().IsHopping = false
    task.wait(2)
    pcall(function() hopToRandomServer("after init fail") end)
end)

-- ====== БЕСКОНЕЧНЫЙ ЦИКЛ ======
print("[Init] JobId:", game.JobId)
print("[Init] History size:", #loadHistory())

-- Сразу добавляем текущий сервер в историю
addToHistory(game.JobId)
saveCurrentJob()

task.wait(3)
while true do
    if not getgenv().IsHopping then
        local ok, err = pcall(huntViciousBee)
        if not ok then
            warn("[Hunt] Ошибка в цикле:", err)
            getgenv().IsHopping = false
            pcall(function() hopToRandomServer("cycle error") end)
        end
    end
    task.wait(1)
end

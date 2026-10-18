-- ============================================================
-- VICIOUS BEE SERVER HOPPER
-- ============================================================

-- ====== СЕРВИСЫ ======
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService = game:GetService("RunService")

-- ====== ФЛАГИ ======
_G.unlocktween = true

-- ====== ГЛОБАЛЬНОЕ СОСТОЯНИЕ ======
getgenv().VisitedServers = getgenv().VisitedServers or {}  -- [jobId] = true
getgenv().IsHopping = false

-- ====== НАСТРОЙКИ ======
local HOP_DELAY = 2.5              -- задержка перед хопом (сек)
local FLY_SPEED = 70               -- скорость полёта
local MANSING_RADIUS = 30          -- радиус мансинга вокруг пчелы
local MANSING_MAX_DIST = 60        -- если дальше — телепорт к шипу
local SERVER_FETCH_LIMIT = 100     -- сколько серверов запрашивать
local HOP_TIMEOUT = 15             -- таймаут сброса IsHopping
local WALK_SPEED = 60              -- скорость ходьбы во время мансинга

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

-- ====== ПОИСК СЕРВЕРОВ ======
local function fetchAvailableServers()
    -- Desc = новые серверы (Vicious чаще жив)
    local body = httpGet("https://games.roblox.com/v1/games/" ..
        game.PlaceId .. "/servers/Public?sortOrder=Desc&limit=" .. SERVER_FETCH_LIMIT)
    if not body then return {} end

    local ok, decoded = pcall(HttpService.JSONDecode, HttpService, body)
    if not ok or not decoded or not decoded.data then return {} end

    local currentJobId = game.JobId
    local available = {}

    for _, server in ipairs(decoded.data) do
        if server.id ~= currentJobId
            and server.playing < server.maxPlayers
            and not getgenv().VisitedServers[server.id] then
            table.insert(available, server)
        end
    end

    return available
end

-- ====== ХОП ======
local function hopToRandomServer()
    if getgenv().IsHopping then return end
    getgenv().IsHopping = true

    -- Таймаут-сброс (защита от зависания)
    task.delay(HOP_TIMEOUT, function()
        if getgenv().IsHopping then
            warn("[Hop] Таймаут — сбрасываем IsHopping")
            getgenv().IsHopping = false
        end
    end)

    print("[Hop] Ждём " .. HOP_DELAY .. " сек...")
    task.wait(HOP_DELAY)

    local lp = Players.LocalPlayer
    if not lp then
        getgenv().IsHopping = false
        return
    end

    local available = fetchAvailableServers()

    if #available == 0 then
        print("[Hop] Все посещены — сброс истории")
        getgenv().VisitedServers = {}
        available = fetchAvailableServers()
    end

    if #available == 0 then
        print("[Hop] Нет доступных — Teleport в случайный")
        pcall(function()
            TeleportService:Teleport(game.PlaceId, lp)
        end)
        return
    end

    -- Shuffle
    for i = #available, 2, -1 do
        local j = math.random(i)
        available[i], available[j] = available[j], available[i]
    end

    for _, chosen in ipairs(available) do
        print("[Hop] Пробуем:", chosen.id,
            "| игроков:", chosen.playing .. "/" .. chosen.maxPlayers,
            "| доступно:", #available)

        getgenv().VisitedServers[chosen.id] = true

        local ok, result = pcall(function()
            return TeleportService:TeleportToPlaceInstance(game.PlaceId, chosen.id, lp)
        end)

        if ok and result then
            print("[Hop] ✅ TeleportToPlaceInstance отправлен")
            return
        end

        print("[Hop] TeleportToPlaceInstance не сработал — TeleportAsync")
        local ok2 = pcall(function()
                TeleportService:TeleportAsync(game.PlaceId, {lp})
        end)

        if ok2 then
            print("[Hop] ✅ TeleportAsync отправлен")
            return
        end

        print("[Hop] ❌ Оба упали — следующий")
        task.wait(0.5)
    end

    print("[Hop] Все провалились — Teleport в случайный")
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

local function getWaitingThorn()
    local particles = workspace:FindFirstChild("Particles")
    if not particles then return nil end
    local wts = particles:FindFirstChild("WTs")
    if not wts then return nil end
    local thorn = wts:FindFirstChild("WaitingThorn")
    if thorn and thorn.Parent then return thorn end
    return nil
end

-- ====== ОПРЕДЕЛЕНИЕ ПОЛЯ ======
local function getFieldAt(position)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = { workspace.FlowerZones }
    raycastParams.FilterType = Enum.RaycastFilterType.Include
    local hit = workspace:Raycast(
        position - Vector3.new(0, 35, 0),
        Vector3.new(0, 50, 0),
        raycastParams
    )
    if hit and hit.Instance.Parent.Name == "FlowerZones" then
        return hit.Instance.Name
    end
    return nil
end

local function shouldHopFromBee(bee)
    local beeHrp = bee:FindFirstChild("HumanoidRootPart")
    if not beeHrp then return false end
    local field = getFieldAt(beeHrp.Position)
    return field == "Mountain Top Field"
end

-- ====== УЛЕЙ ======
local function findFreeHive()
    local honeycombs = workspace:FindFirstChild("Honeycombs")
    if not honeycombs then return nil end

    -- Перебор с конца (6 -> 1), как в Atlas
    for i = 6, 1, -1 do
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

-- ====== FLY (AlignPosition + noclip) ======
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

-- ====== ЗАХВАТ УЛЬЯ (с проверкой Honeycomb) ======
local function occupyHive(hive)
    local lp = Players.LocalPlayer
    local start = tick()
    while not lp:FindFirstChild("Honeycomb") and tick() - start < 5 do
        local prompt = hive:FindFirstChildOfClass("ProximityPrompt")
        if not prompt then
            for _, d in ipairs(hive:GetDescendants()) do
                if d:IsA("ProximityPrompt") then prompt = d break end
            end
        end

        if prompt and fireproximityprompt then
            pcall(fireproximityprompt, prompt)
        else
            pcall(function()
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                task.wait(0.05)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
            end)
        end

        task.wait(0.5)
    end

    return lp:FindFirstChild("Honeycomb") ~= nil
end

-- ====== МАНСИНГ (с обходом Mondo) ======
local function startMansing(bee)
    local running = true
    local connection
    local angle = 0
    local lastJump, lastMoveTime = 0, 0
    local lastTarget = Vector3.zero
    local zigzagPhase = 0
    local lastAttack = 0
    local lastTeleportCheck = 0

    -- Обход Mondo
    local mondoTarget = nil
    local mondo = findMondoChick()
    if mondo then
        local mondoHrp = mondo:FindFirstChild("HumanoidRootPart")
        if mondoHrp then
            mondoTarget = mondoHrp.Position
        end
    end

    local thorn = getWaitingThorn()

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

        local now = tick()
        local dist = (hrp.Position - beeHrp.Position).Magnitude

        -- Телепорт если отдалились
        if dist > MANSING_MAX_DIST then
            if now - lastTeleportCheck > 1 then
                print("[Mansing] Отдалились на " .. math.floor(dist) .. " — телепорт к шипу")
                lastTeleportCheck = now
            end
            if thorn and thorn.Parent then
                flyTo(thorn, Vector3.new(0, 0, 5))
            else
                flyTo(bee, Vector3.new(0, 3, 0))
            end
            return
        end

        -- Авто-атака
        if now - lastAttack > 0.2 then
            local tool = char:FindFirstChildOfClass("Tool")
            if tool and dist < 30 then
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

        zigzagPhase = zigzagPhase + dt * 5
        local zigzag = math.sin(zigzagPhase) * 0.45
        angle = angle + (WALK_SPEED / MANSING_RADIUS) * dt
        local finalAngle = angle + zigzag

        local targetPos
        if thorn and thorn.Parent then
            -- Стоим у шипа
            local dirToThorn = (thorn.Position - beeHrp.Position).Unit
            targetPos = thorn.Position - dirToThorn * 5
        else
            -- Мансинг вокруг пчелы
            local offset = Vector3.new(
                math.cos(finalAngle) * MANSING_RADIUS,
                0,
                math.sin(finalAngle) * MANSING_RADIUS
            )
            targetPos = beeHrp.Position + offset
        end

        -- Обход Mondo (выталкивание из радиуса 40)
        if mondoTarget then
            local toMondo = targetPos - mondoTarget
            if toMondo.Magnitude < 40 then
                targetPos = mondoTarget + toMondo.Unit * 45
            end
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

-- ====== ГЛАВНАЯ ЛОГИКА ======
local function huntViciousBee()
    print("[Hunt] === НОВЫЙ СЕРВЕР ===")

    local lp = Players.LocalPlayer

    -- Ждём прогрузку персонажа (макс 6 сек)
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
    -- Ждём прогрузку Monsters (макс 3 сек)
    local monsters = workspace:WaitForChild("Monsters", 3)
    if not monsters then
        print("[Hunt] Monsters не прогрузились — хоп")
        hopToRandomServer()
        return
    end

    -- Даём 1 секунду на спавн монстров
    task.wait(1)

    -- === ПУНКТ 2: МОМЕНТАЛЬНАЯ проверка Vicious ===
    print("[Hunt] Ищем Vicious Bee...")
    local bee = findViciousBee()
    if not bee then
        print("[Hunt] ❌ Vicious не найден — ХОП (не ждём!)")
        hopToRandomServer()
        return
    end
    print("[Hunt] ✅ Vicious найден:", bee.Name)

    -- === ПУНКТ 3: Проверка рядом с Mondo ===
    if shouldHopFromBee(bee) then
        print("[Hunt] ❌ Vicious на Mountain Top (рядом с Mondo) — ХОП")
        hopToRandomServer()
        return
    end
    print("[Hunt] ✅ Vicious не на горе — летим убивать")

    -- === ПУНКТ 4: Свободный улей ===
    print("[Hunt] Ищем улей...")
    local hive = findFreeHive()
    if not hive then
        print("[Hunt] ❌ Улей не найден — ХОП")
        hopToRandomServer()
        return
    end
    print("[Hunt] ✅ Выбран улей:", hive.Name)

    local platform = hive:FindFirstChild("Platform")
    local hiveTarget = (platform and platform.Value) or hive

    local reached = false
    for attempt = 1, 3 do
        if flyTo(hiveTarget, Vector3.new(0, 3, 0)) then
            reached = true
            break
        end
        task.wait(0.3)
    end

    if not reached then
        print("[Hunt] ❌ Не долетели до улья — ХОП")
        hopToRandomServer()
        return
    end

    task.wait(0.7)
    print("[Hunt] Занимаем улей...")
    local occupied = occupyHive(hive)

    if not occupied then
        print("[Hunt] ❌ Улей не занят — ХОП")
        hopToRandomServer()
        return
    end
    print("[Hunt] ✅ Улей занят")

    -- === ПУНКТ 5: Полёт к шипу (а не к пчеле) ===
    local thorn = getWaitingThorn()
    if thorn then
        print("[Hunt] Летим к шипу...")
        for attempt = 1, 3 do
            if flyTo(thorn, Vector3.new(0, 0, 5)) then break end
            task.wait(0.3)
        end
    else
        print("[Hunt] Шип не найден — летим к пчеле...")
        for attempt = 1, 3 do
            if flyTo(bee, Vector3.new(0, 5, 15)) then break end
            task.wait(0.3)
        end
    end

    -- === ПУНКТ 6: Мансинг + убийство ===
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

    -- === ПУНКТ 7: Хоп ===
    print("[Hunt] Хоп на следующий сервер...")
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

-- ====== SERVICES ======
local Players             = game:GetService("Players")
local HttpService         = game:GetService("HttpService")
local TeleportService     = game:GetService("TeleportService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService          = game:GetService("RunService")

getgenv().VisitedServers = getgenv().VisitedServers or {}
getgenv().IsHopping = false

-- ====== НАСТРОЙКИ ======
local HOP_DELAY            = 2
local MOUNTAIN_MONDO_RADIUS = 200
local MANSING_RADIUS       = 18
local SERVER_FETCH_LIMIT   = 300
local BLACKLIST_MAX        = 200
local FLY_SPEED            = 50
local WALK_SPEED           = 50

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
        if server.id ~= currentJobId and server.playing < server.maxPlayers then
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

-- ====== ДОБАВИТЬ ТЕКУЩИЙ СЕРВЕР В ЧЁРНЫЙ СПИСОК ======
local function addCurrentServerToBlacklist()
    local currentJobId = game.JobId
    if not currentJobId or currentJobId == "" then return end

    for _, v in ipairs(getgenv().VisitedServers) do
        if v == currentJobId then return end
    end

    table.insert(getgenv().VisitedServers, currentJobId)
    print("[Blacklist] Добавлен сервер. Всего в списке:", #getgenv().VisitedServers)

    -- Если достигли лимита — очищаем, чтобы хопать на "старые"
    if #getgenv().VisitedServers >= BLACKLIST_MAX then
        print("[Blacklist] Достигнут лимит " .. BLACKLIST_MAX .. " — очищаем, хопаем на старые серверы")
        getgenv().VisitedServers = {}
    end
end

-- ====== ХОП ======
local function hopToRandomServer()
    if getgenv().IsHopping then return end
    getgenv().IsHopping = true

    print("[Hop] Ждём " .. HOP_DELAY .. " сек перед хопом...")
    task.wait(HOP_DELAY)

    local lp = Players.LocalPlayer
    if not lp then return end

    local available = fetchAvailableServers()

    if #available == 0 then
        print("[Hop] Все серверы в чёрном списке — сброс списка")
        getgenv().VisitedServers = {}
        available = fetchAvailableServers()
    end

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

    for i = #available, 2, -1 do
        local j = math.random(i)
        available[i], available[j] = available[j], available[i]
    end

    for _, chosen in ipairs(available) do
        print("[Hop] Пробуем сервер:", chosen.id,
            "| игроков:", chosen.playing .. "/" .. chosen.maxPlayers,
            "| доступно:", #available)

        local ok = pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, chosen.id, lp)
        end)
        if ok then
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

        print("[Hop] ❌ Оба способа упали, берём следующий")
        task.wait(0.5)
    end

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
                print("[Hunt] ✅ Свободный улей:", hive.Name)
                return hive
            end
        end
    end
    print("[Hunt] ❌ Свободных ульев нет")
end

-- ====== FLY (из первого скрипта) ======
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
            if child.ClassName == "AlignPosition" or child.ClassName == "AlignOrientation" then child:Destroy() end
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

-- ====== МАНСИНГ (из первого скрипта) ======
local function startMansing(bee)
    local running = true
    local connection
    local angle = 0
    local lastJump, lastMoveTime = 0, 0
    local lastTarget = Vector3.zero
    local zigzagPhase = 0

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
        angle = angle + (WALK_SPEED / MANSING_RADIUS) * dt
        local finalAngle = angle + zigzag

        local targetPos
        if thornPos then
            local dirToThorn = (thornPos - beeHrp.Position).Unit
            targetPos = thornPos - dirToThorn * 5
                else
            local offset = Vector3.new(math.cos(finalAngle) * MANSING_RADIUS, 0, math.sin(finalAngle) * MANSING_RADIUS)
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
    print("[Hunt] === НОВЫЙ СЕРВЕР ===")
    -- Заносим текущий сервер в чёрный список сразу после захода
    addCurrentServerToBlacklist()
    task.wait(2)

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

    print("[Hunt] Ищем Vicious Bee...")
    local bee = findViciousBee()
    if not bee then
        print("[Hunt] Пчела не найдена — хоп")
        hopToRandomServer()
        return
    end
    print("[Hunt] ✅ Пчела найдена:", bee.Name)

    if shouldHopFromBee(bee) then
        print("[Hunt] Пчела на горе (рядом с Mondo) — хоп")
        hopToRandomServer()
        return
    end
    print("[Hunt] Летим убивать")

    print("[Hunt] Ищем улей...")
    local hive = findFreeHive()
    if not hive then
        print("[Hunt] Улей не найден — хоп")
        hopToRandomServer()
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
        hopToRandomServer()
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
            hopToRandomServer()
            return
        end
    end
    print("[Hunt] ✅ Улей занят")

    local attackOk = pcall(function()
        print("[Hunt] Летим к пчеле...")
        for attempt = 1, 3 do
            if flyTo(bee, Vector3.new(0, 5, 15)) then break end
            task.wait(0.3)
        end

        print("[Hunt] Мансинг вокруг пчелы (радиус " .. MANSING_RADIUS .. ")...")
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
    local name = result and result.Name or "Unknown"
    local code = result and result.Value or -1
    warn("[Teleport] Ошибка:", name, err, "| Код:", code)
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

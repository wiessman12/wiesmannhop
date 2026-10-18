-- ============================================================
-- VICIOUS BEE SERVER HOPPER (ПОЛНОСТЬЮ ИСПРАВЛЕННЫЙ)
-- ============================================================

-- ====== СЕРВИСЫ ======
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService = game:GetService("RunService")

-- ====== НАСТРОЙКИ ======
local FLY_SPEED = 70
local MANSING_RADIUS = 30
local MANSING_MAX_DIST = 60
local WALK_SPEED = 60

local DATA_FILE = "hop_data.json"
local EXPIRE_TIME = 20 * 60 -- Сервер хранится в истории 20 минут
local HOP_DELAY = 1.5

getgenv().IsHopping = false

-- Авто-перезапуск скрипта после телепортации
local queueTeleport = (syn and syn.queue_on_teleport) or queue_on_teleport or (fluxus and fluxus.queue_on_teleport)

-- ============================================================
-- ====== СЕРВЕР-ХОП (С КЭШЕМ ОЧЕРЕДИ — БЕЗ РЕЙТ-ЛИМИТОВ) ======
-- ============================================================
local function httpRequest(url)
    local req = (syn and syn.request) 
        or (http and http.request) 
        or http_request 
        or (fluxus and fluxus.request) 
        or request

    if req then
        local ok, res = pcall(req, {Url = url, Method = "GET"})
        if ok and res then
            local body = type(res) == "table" and (res.Body or res.body) or res
            if body and body ~= "" then return body end
        end
    end

    if game.HttpGet then
        local ok, body = pcall(game.HttpGet, game, url)
        if ok and body and body ~= "" then return body end
    end
    return nil
end

local function loadData()
    local defaultData = { queue = {}, visited = {} }
    if readfile and isfile and isfile(DATA_FILE) then
        local ok, data = pcall(function()
            return HttpService:JSONDecode(readfile(DATA_FILE))
        end)
        if ok and type(data) == "table" then
            data.queue = data.queue or {}
            data.visited = data.visited or {}
            
            local now = os.time()
            for id, timeVal in pairs(data.visited) do
                if type(timeVal) == "number" and (now - timeVal > EXPIRE_TIME) then
                    data.visited[id] = nil
                end
            end
            return data
        end
    end
    return defaultData
end

local function saveData(data)
    if writefile then
        pcall(function()
            writefile(DATA_FILE, HttpService:JSONEncode(data))
        end)
    end
end

-- Делает ровно 1 запрос к API на 100 серверов
local function fetchNewServers(data)
    print("[Hop] 🌐 Запрос новой пачки серверов от API...")
    local url = string.format("https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100", tostring(game.PlaceId))
    local body = httpRequest(url)
    if not body then return false end

    local ok, decoded = pcall(HttpService.JSONDecode, HttpService, body)
    if not ok or not decoded or decoded.errors or not decoded.data then
        warn("[Hop] ⚠️ Лимит API или ошибка ответа. Используем резервный вход.")
        return false
    end

    local added = 0
    for _, s in ipairs(decoded.data) do
        if s.id ~= game.JobId and s.playing < s.maxPlayers and not data.visited[s.id] then
            table.insert(data.queue, s.id)
            added = added + 1
        end
    end

    print(string.format("[Hop] ✅ Получено %d серверов в локальную очередь!", added))
    return added > 0
end

local function hopToRandomServer()
    if getgenv().IsHopping then return end
    getgenv().IsHopping = true

    task.wait(HOP_DELAY)

    local lp = Players.LocalPlayer
    if not lp then
        getgenv().IsHopping = false
        return
    end

    local data = loadData()
    if game.JobId and game.JobId ~= "" then
        data.visited[game.JobId] = os.time()
    end

    -- Очищаем очередь от уже посещенных серверов
    local validQueue = {}
    for _, id in ipairs(data.queue) do
        if not data.visited[id] and id ~= game.JobId then
            table.insert(validQueue, id)
        end
    end
    data.queue = validQueue

    -- Если очередь опустела, запрашиваем 1 новую пачку из 100 серверов
    if #data.queue == 0 then
        local ok = fetchNewServers(data)
        if not ok or #data.queue == 0 then
            data.visited = {}
            if game.JobId and game.JobId ~= "" then data.visited[game.JobId] = os.time() end
            saveData(data)
            
            warn("[Hop] Очередь пуста. Резервный хоп через стандартный матчмейкинг...")
            pcall(function() TeleportService:Teleport(game.PlaceId, lp) end)
            getgenv().IsHopping = false
            return
        end
    end

    -- Берем сервер из готового списка без единого сетевого запроса к API
    local chosenIndex = math.random(1, #data.queue)
    local targetJobId = table.remove(data.queue, chosenIndex)

    data.visited[targetJobId] = os.time()
    saveData(data)

    print(string.format("[Hop] 🚀 Переход на сервер: %s (Осталось в запасе: %d)", targetJobId, #data.queue))

    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, targetJobId, lp)
    end)

    if not ok then
        warn("[Hop] Ошибка TeleportToPlaceInstance:", err)
        getgenv().IsHopping = false
    end
end

TeleportService.TeleportInitFailed:Connect(function(_, result, err)
    warn("[Teleport] Не удалось войти:", result.Name, err)
    getgenv().IsHopping = false
    task.wait(3)
    hopToRandomServer()
end)

-- ============================================================
-- ====== ПОИСК ОБЪЕКТОВ ======
-- ============================================================
local function findViciousBee()
    local m = workspace:FindFirstChild("Monsters")
    if not m then return nil end
    for _, o in ipairs(m:GetChildren()) do
        if o.Name:find("Vicious Bee") then
            local h = o:FindFirstChild("Humanoid")
            if h and h.Health > 0 then return o end
        end
    end
    return nil
end

local function findMondoChick()
    local m = workspace:FindFirstChild("Monsters")
    if not m then return nil end
    for _, o in ipairs(m:GetChildren()) do
        if o.Name:find("Mondo Chick") then
            local h = o:FindFirstChild("Humanoid")
            if h and h.Health > 0 then return o end
        end
    end
    return nil
end

local function getWaitingThorn()
    local p = workspace:FindFirstChild("Particles")
    if not p then return nil end
    local w = p:FindFirstChild("WTs")
    if not w then return nil end
    local t = w:FindFirstChild("WaitingThorn")
    if t and t.Parent then return t end
    return nil
end

local function getFieldAt(pos)
    local rp = RaycastParams.new()
    rp.FilterDescendantsInstances = { workspace:FindFirstChild("FlowerZones") }
    rp.FilterType = Enum.RaycastFilterType.Include
    local hit = workspace:Raycast(pos - Vector3.new(0, 35, 0), Vector3.new(0, 50, 0), rp)
    if hit and hit.Instance and hit.Instance.Parent and hit.Instance.Parent.Name == "FlowerZones" then 
        return hit.Instance.Name 
    end
    return nil
end

local function shouldHopFromBee(bee)
    local hrp = bee:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    return getFieldAt(hrp.Position) == "Mountain Top Field"
end

-- ============================================================
-- ====== УЛЕЙ ======
-- ============================================================
local function findFreeHive()
    local hc = workspace:FindFirstChild("Honeycombs")
    if not hc then return nil end
    for i = 6, 1, -1 do
        local hive = hc:FindFirstChild("Hive" .. i)
        if hive then
            local owner = hive:FindFirstChild("Owner")
            if owner and owner.Value == nil then
                print("[Hunt] ✅ Свободный улей:", hive.Name)
                return hive
            end
        end
    end
    print("[Hunt] ❌ Свободных ульев нет")
    return nil
end

-- ============================================================
-- ====== FLY ======
-- ============================================================
local function flyTo(target, offset)
    local lp = Players.LocalPlayer
    if not lp then return false end
    local char = lp.Character
    if not char then return false end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not target or not hum then return false end

    offset = offset or Vector3.new(0, 3, 0)
    local tp
    if target:IsA("Model") then
        tp = target.PrimaryPart and target.PrimaryPart.Position or target:GetPivot().Position
    elseif target:IsA("BasePart") then
        tp = target.Position
    else
        return false
    end
    tp = tp + offset

    for _, c in ipairs(hrp:GetChildren()) do
        if c.ClassName == "AlignPosition" or c.ClassName == "AlignOrientation" then c:Destroy() end
    end

    hum:ChangeState(Enum.HumanoidStateType.Freefall)
    local ap = Instance.new("AlignPosition")
    ap.Mode = Enum.PositionAlignmentMode.OneAttachment
    ap.Attachment0 = hrp:FindFirstChild("RootAttachment") or hrp.RootAttachment
    ap.Responsiveness = 200
    ap.MaxForce = math.huge
    ap.MaxVelocity = FLY_SPEED
    ap.Position = tp
    ap.Parent = hrp

    local ao = Instance.new("AlignOrientation")
    ao.Attachment0 = hrp:FindFirstChild("RootAttachment") or hrp.RootAttachment
    ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
    ao.RigidityEnabled = true
    ao.CFrame = hrp.CFrame
    ao.Parent = hrp

    hum:ChangeState(Enum.HumanoidStateType.Physics)
    local nc = RunService.PreSimulation:Connect(function()
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
    end)

    local s = tick()
    while tick() - s < 5 do
        if not hrp or not hrp.Parent then break end
        if (hrp.Position - tp).Magnitude < 5 then break end
        task.wait(0.05)
    end

    nc:Disconnect(); ap:Destroy(); ao:Destroy()
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then p.CanCollide = true end
    end
    hum:ChangeState(Enum.HumanoidStateType.Freefall)
    return (hrp.Position - tp).Magnitude < 30
end

-- ============================================================
-- ====== ЗАХВАТ УЛЬЯ ======
-- ============================================================
local function occupyHive(hive)
    local lp = Players.LocalPlayer
    if not lp then return false end
    local s = tick()
    while not lp:FindFirstChild("Honeycomb") and tick() - s < 5 do
        local prompt = hive:FindFirstChildOfClass("ProximityPrompt")
        if not prompt then
            for _, d in ipairs(hive:GetDescendants()) do
                if d:IsA("ProximityPrompt") then prompt = d; break end
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

-- ============================================================
-- ====== МАНСИНГ ======
-- ============================================================
local function startMansing(bee)
    local running = true
    local conn
    local angle = 0
    local lj, lm = 0, 0
    local lt = Vector3.zero
    local zp = 0
    local la = 0
    local ltc = 0
    local mt = nil

    local mondo = findMondoChick()
    if mondo then
        local mh = mondo:FindFirstChild("HumanoidRootPart")
        if mh then mt = mh.Position end
    end
    local thorn = getWaitingThorn()

    local lp0 = Players.LocalPlayer
    if not lp0 then return function() end end
    local c0 = lp0.Character
    if c0 then
        local h0 = c0:FindFirstChildOfClass("Humanoid")
        if h0 then h0.PlatformStand = false; h0.WalkSpeed = 16 end
        local r0 = c0:FindFirstChild("HumanoidRootPart")
        if r0 then r0.CanCollide = true end
    end

    if c0 and bee and bee.Parent then
        local h, b = c0:FindFirstChild("HumanoidRootPart"), bee:FindFirstChild("HumanoidRootPart")
        if h and b then
            local v = h.Position - b.Position
            if v.Magnitude > 1 then angle = math.atan2(v.Z, v.X) end
        end
    end

    conn = RunService.RenderStepped:Connect(function(dt)
        if not running then return end
        dt = math.min(dt, 0.05)
        local lp = Players.LocalPlayer
        if not lp then return end
        local char = lp.Character
        if not char then return end

        local hrp, hum = char:FindFirstChild("HumanoidRootPart"), char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or not bee or not bee.Parent then return end

        hum.PlatformStand = false; hrp.CanCollide = true; hum.WalkSpeed = WALK_SPEED
        local bh = bee:FindFirstChild("HumanoidRootPart")
        if not bh then return end

        local now = tick()
        local dist = (hrp.Position - bh.Position).Magnitude
        if dist > MANSING_MAX_DIST then
            if now - ltc > 1 then ltc = now end
            if thorn and thorn.Parent then 
                flyTo(thorn, Vector3.new(0, 0, 5))
            else 
                flyTo(bee, Vector3.new(0, 3, 0)) 
            end
            return
        end

        if now - la > 0.2 then
            local tool = char:FindFirstChildOfClass("Tool")
            if tool and dist < 30 then pcall(function() tool:Activate() end); la = now end
        end

        if now - lj > 1.2 then
            local st = hum:GetState()
            if st == Enum.HumanoidStateType.Running or st == Enum.HumanoidStateType.Landed then hum.Jump = true end
            lj = now
        end

        zp = zp + dt * 5
        local zz = math.sin(zp) * 0.45
        angle = angle + (WALK_SPEED / MANSING_RADIUS) * dt
        local fa = angle + zz
        local tp
        if thorn and thorn.Parent then
            local dt2 = (thorn.Position - bh.Position).Unit
            tp = thorn.Position - dt2 * 5
        else
            tp = bh.Position + Vector3.new(math.cos(fa) * MANSING_RADIUS, 0, math.sin(fa) * MANSING_RADIUS)
        end

        if mt then
            local tm = tp - mt
            if tm.Magnitude < 40 then tp = mt + tm.Unit * 45 end
        end

        local rp = RaycastParams.new()
        rp.FilterDescendantsInstances = {char}
        rp.FilterType = Enum.RaycastFilterType.Exclude
        local g = workspace:Raycast(Vector3.new(tp.X, tp.Y + 30, tp.Z), Vector3.new(0, -100, 0), rp)
        if g then tp = Vector3.new(tp.X, g.Position.Y + 3, tp.Z) end

        if now - lm > 0.1 or (tp - lt).Magnitude > 4 then
            hum:MoveTo(tp); lm = now; lt = tp
        end
    end)

    return function()
        running = false
        if conn then conn:Disconnect() end
        local lp = Players.LocalPlayer
        if lp then
            local char = lp.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then hum.PlatformStand = false; hum.WalkSpeed = 16 end
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if hrp then hrp.CanCollide = true end
            end
        end
    end
end

-- ============================================================
-- ====== ГЛАВНАЯ ЛОГИКА ======
-- ============================================================
local function huntViciousBee()
    print("[Hunt] === НОВЫЙ СЕРВЕР ===")

    -- Ждём LocalPlayer
    local lp = Players.LocalPlayer
    local waitStart = tick()
    while not lp and tick() - waitStart < 15 do
        task.wait(0.2)
        lp = Players.LocalPlayer
    end
    if not lp then
        print("[Hunt] ❌ LocalPlayer не появился — хоп")
        hopToRandomServer()
        return
    end

    -- Ждём появления персонажа
    local char, hrp
    for _ = 1, 40 do
        char = lp.Character
        if char and char:FindFirstChild("HumanoidRootPart") and char:FindFirstChildOfClass("Humanoid") then
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

    local monsters = workspace:WaitForChild("Monsters", 5)
    if not monsters then
        print("[Hunt] Monsters не прогрузились — хоп")
        hopToRandomServer()
        return
    end

    task.wait(1)

    print("[Hunt] Ищем Vicious Bee...")
    local bee = findViciousBee()
    if not bee then
        print("[Hunt] ❌ Vicious не найден — ХОП")
        hopToRandomServer()
        return
    end
    print("[Hunt] ✅ Vicious найден:", bee.Name)

    if shouldHopFromBee(bee) then
        print("[Hunt] ❌ Vicious на Mountain Top — ХОП")
        hopToRandomServer()
        return
    end
    print("[Hunt] ✅ Vicious не на горе — летим убивать")

    print("[Hunt] Ищем улей...")
    local hive = findFreeHive()
    if not hive then
        print("[Hunt] ❌ Улей не найден — ХОП")
        hopToRandomServer()
        return
    end
    print("[Hunt] ✅ Выбран улей:", hive.Name)

    local platform = hive:FindFirstChild("Platform")
    local ht = (platform and platform.Value) or hive

    local reached = false
    for _ = 1, 3 do
        if flyTo(ht, Vector3.new(0, 3, 0)) then reached = true; break end
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

    local thorn = getWaitingThorn()
    if thorn then
        print("[Hunt] Летим к шипу...")
        for _ = 1, 3 do
            if flyTo(thorn, Vector3.new(0, 0, 5)) then break end
            task.wait(0.3)
        end
    else
        print("[Hunt] Шип не найден — летим к пчеле...")
        for _ = 1, 3 do
            if flyTo(bee, Vector3.new(0, 5, 15)) then break end
            task.wait(0.3)
        end
    end

    print("[Hunt] Мансинг вокруг пчелы...")
    local stopMansing = startMansing(bee)

    local maxWait, waited = 90, 0
    while waited < maxWait do
        task.wait(0.3)
        waited = waited + 0.3
        local h = bee:FindFirstChild("Humanoid")
        if not bee.Parent or not h or h.Health <= 0 then
            print("[Hunt] ✅ Пчела убита!")
            break
        end
    end

    if stopMansing then stopMansing() end

    print("[Hunt] Хоп на следующий сервер...")
    hopToRandomServer()
end

-- ============================================================
-- ====== ЗАПУСК ======
-- ============================================================
task.wait(2)
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

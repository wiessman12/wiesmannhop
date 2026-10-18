-- ============================================================
-- VICIOUS BEE SERVER HOPPER (ATLAS 2 TWEEN & DODGE)
-- ============================================================

-- ====== 1. ОЖИДАНИЕ ЗАГРУЗКИ ИГРЫ ======
repeat task.wait(0.2) until game:IsLoaded()

-- ====== 2. СЕРВИСЫ ======
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService = game:GetService("RunService")

-- Ждем появления LocalPlayer
local lp = Players.LocalPlayer
while not lp do
    task.wait(0.3)
    lp = Players.LocalPlayer
end

-- Ждем закрытия экрана загрузки Bee Swarm Simulator (из atlas2.lua)
local playerGui = lp:WaitForChild("PlayerGui", 20)
if playerGui then
    local loadingGui = playerGui:FindFirstChild("LoadingScreenGui")
    if loadingGui then
        local msg = loadingGui:FindFirstChild("LoadingMessage")
        while msg and msg.Visible do
            task.wait(0.3)
        end
    end
end
print("[Init] ✅ Игра и интерфейс полностью загружены!")

-- ====== НАСТРОЙКИ ======
_G.unlocktween = true
local TWEEN_SPEED = 75       -- Скорость полета Tween (стадс/сек)
local WALK_SPEED = 60        -- Скорость бега при мансинге
local MANSING_RADIUS = 28    -- Радиус кружения вокруг Vicious Bee
local THORN_AVOID_DIST = 10  -- Безопасная дистанция отступа от шипов

local DATA_FILE = "hop_data.json"
local EXPIRE_TIME = 20 * 60  -- Сервер хранится 20 минут
local HOP_DELAY = 1.5

getgenv().IsHopping = false

-- ============================================================
-- ====== ВСПОМОГАТЕЛЬНАЯ ФУНКЦИЯ ПОЛУЧЕНИЯ ПОЗИЦИИ ======
-- ============================================================
local function getPosition(obj)
    if typeof(obj) == "Vector3" then
        return obj
    elseif typeof(obj) == "CFrame" then
        return obj.Position
    elseif typeof(obj) == "Instance" then
        if obj:IsA("BasePart") then
            return obj.Position
        elseif obj:IsA("Model") then
            return obj.PrimaryPart and obj.PrimaryPart.Position or obj:GetPivot().Position
        elseif obj:IsA("ObjectValue") and obj.Value then
            return getPosition(obj.Value)
        end
        -- Специфика ульев Bee Swarm Simulator (из atlas2.lua)
        if obj:FindFirstChild("patharrow") and obj.patharrow:FindFirstChild("Base") then
            return obj.patharrow.Base.Position
        end
        if obj:FindFirstChild("Platform") then
            local plat = obj.Platform
            if plat:IsA("ObjectValue") and plat.Value then
                return getPosition(plat.Value)
            elseif plat:IsA("BasePart") then
                return plat.Position
            end
        end
        local anyPart = obj:FindFirstChildWhichIsA("BasePart", true)
        if anyPart then
            return anyPart.Position
        end
    end
    return nil
end

-- ============================================================
-- ====== СЕРВЕР-ХОП (ОЧЕРЕДЬ В ФАЙЛЕ — БЕЗ РЕЙТ-ЛИМИТОВ) ======
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
            for id, t in pairs(data.visited) do
                if type(t) == "number" and (now - t > EXPIRE_TIME) then
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

local function fetchNewServers(data)
    print("[Hop] 🌐 Запрос новой пачки серверов от API...")
    local url = string.format("https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100", tostring(game.PlaceId))
    local body = httpRequest(url)
    if not body then return false end

    local ok, decoded = pcall(HttpService.JSONDecode, HttpService, body)
    if not ok or not decoded or decoded.errors or not decoded.data then
        warn("[Hop] ⚠️ Ошибка ответа API. Используем резервный вход.")
        return false
    end

    local added = 0
    for _, s in ipairs(decoded.data) do
        if s.id ~= game.JobId and s.playing < s.maxPlayers and not data.visited[s.id] then
            table.insert(data.queue, s.id)
            added = added + 1
        end
    end

    print(string.format("[Hop] ✅ Получено %d серверов в очередь!", added))
    return added > 0
end

local function hopToRandomServer()
    if getgenv().IsHopping then return end
    getgenv().IsHopping = true

    task.wait(HOP_DELAY)

    local currentLp = Players.LocalPlayer
    if not currentLp then
        task.wait(1)
        currentLp = Players.LocalPlayer
    end

    local data = loadData()
    if game.JobId and game.JobId ~= "" then
        data.visited[game.JobId] = os.time()
    end

    local validQueue = {}
    for _, id in ipairs(data.queue) do
        if not data.visited[id] and id ~= game.JobId then
            table.insert(validQueue, id)
        end
    end
    data.queue = validQueue

    if #data.queue == 0 then
        local ok = fetchNewServers(data)
        if not ok or #data.queue == 0 then
            data.visited = {}
            if game.JobId and game.JobId ~= "" then data.visited[game.JobId] = os.time() end
            saveData(data)
            warn("[Hop] Очередь пуста. Резервный хоп через матчмейкинг...")
            pcall(function() TeleportService:Teleport(game.PlaceId, currentLp) end)
            
            local w = tick()
            while tick() - w < 12 do task.wait(1) end
            getgenv().IsHopping = false
            return
        end
    end

    local chosenIndex = math.random(1, #data.queue)
    local targetJobId = table.remove(data.queue, chosenIndex)

    data.visited[targetJobId] = os.time()
    saveData(data)

    print(string.format("[Hop] 🚀 Переход на сервер: %s (Осталось в запасе: %d)", targetJobId, #data.queue))

    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, targetJobId, currentLp)
    end)

    if ok then
        local startWait = tick()
        while tick() - startWait < 15 and getgenv().IsHopping do
            task.wait(1)
        end
    else
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
-- ====== ATLAS 2 TWEEN SYSTEM (С ПОЛНЫМ NOCLIP) ======
-- ============================================================
local function tweenTo(target, speed, offset)
    local curLp = Players.LocalPlayer
    if not curLp then return false end
    local char = curLp.Character
    if not char then return false end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return false end

    local targetPos = getPosition(target)
    if not targetPos then
        warn("[Tween] ❌ Не удалось определить координаты цели:", tostring(target))
        return false
    end

    offset = offset or Vector3.zero
    targetPos = targetPos + offset

    local maxVelocity = speed or TWEEN_SPEED
    local distance = (targetPos - hrp.Position).Magnitude
    local travelTime = distance / maxVelocity

    for _, c in ipairs(hrp:GetChildren()) do
        if c.ClassName == "AlignPosition" or c.ClassName == "AlignOrientation" then
            c:Destroy()
        end
    end

    local ap = Instance.new("AlignPosition")
    ap.Mode = Enum.PositionAlignmentMode.OneAttachment
    ap.Attachment0 = hrp:FindFirstChild("RootAttachment") or hrp.RootAttachment
    ap.Responsiveness = 25
    ap.MaxForce = math.huge
    ap.MaxVelocity = maxVelocity
    ap.Position = targetPos
    ap.Parent = hrp

    local ao = Instance.new("AlignOrientation")
    ao.Attachment0 = hrp:FindFirstChild("RootAttachment") or hrp.RootAttachment
    ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
    ao.RigidityEnabled = true
    ao.CFrame = hrp.CFrame
    ao.Parent = hrp

    hum:ChangeState(Enum.HumanoidStateType.Physics)

    local stepSignal = RunService.PreSimulation or RunService.Stepped
    local noclipConn = stepSignal:Connect(function()
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") and p.CanCollide then
                p.CanCollide = false
            end
        end
    end)

    local startClock = os.clock()
    while (os.clock() - startClock < travelTime + 1.5) and (os.clock() - startClock < 25) do
        if not hrp or not hrp.Parent or hum.Health <= 0 then break end
        if (hrp.Position - targetPos).Magnitude < 4.5 then break end
        RunService.Heartbeat:Wait()
    end

    noclipConn:Disconnect()
    ap:Destroy()
    ao:Destroy()

    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then
            p.CanCollide = true
        end
    end
    hum:ChangeState(Enum.HumanoidStateType.Freefall)

    return (hrp.Position - targetPos).Magnitude < 8
end

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
    local fz = workspace:FindFirstChild("FlowerZones")
    if not fz then return nil end
    rp.FilterDescendantsInstances = { fz }
    rp.FilterType = Enum.RaycastFilterType.Include
    local hit = workspace:Raycast(pos + Vector3.new(0, 15, 0), Vector3.new(0, -60, 0), rp)
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

local function occupyHive(hive)
    local curLp = Players.LocalPlayer
    if not curLp then return false end
    local s = tick()
    while not curLp:FindFirstChild("Honeycomb") and tick() - s < 5 do
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
    return curLp:FindFirstChild("Honeycomb") ~= nil
end

-- ============================================================
-- ====== СИСТЕМА УВОРОТА И МАНСИНГА (ATLAS 2) ======
-- ============================================================
local function startMansing(bee)
    local running = true
    local angle = 0
    local lastJump = 0
    local lastAttack = 0
    local trackedAvoid = {}

    local particles = workspace:FindFirstChild("Particles")
    local connAdd, connRem

    if particles then
        for _, child in ipairs(particles:GetChildren()) do
            if child.Name == "WarningDisk" and child.Size.X == 10 then
                trackedAvoid[child] = THORN_AVOID_DIST
            end
        end

        connAdd = particles.ChildAdded:Connect(function(child)
            if child.Name == "WarningDisk" and child.Size.X == 10 then
                trackedAvoid[child] = THORN_AVOID_DIST
            end
        end)

        connRem = particles.ChildRemoved:Connect(function(child)
            if child.Name == "WarningDisk" and child.Size.X == 10 then
                task.delay(1.5, function()
                    trackedAvoid[child] = nil
                end)
            end
        end)
    end

    local curLp = Players.LocalPlayer
    if not curLp then return function() end end
    local char = curLp.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hum.PlatformStand = false; hum.WalkSpeed = WALK_SPEED end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.CanCollide = true end
    end

    local connUpdate = RunService.RenderStepped:Connect(function(dt)
        if not running then return end
        dt = math.min(dt, 0.05)

        local lpStep = Players.LocalPlayer
        if not lpStep then return end
        local charStep = lpStep.Character
        if not charStep then return end

        local hrp = charStep:FindFirstChild("HumanoidRootPart")
        local hum = charStep:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 or not bee or not bee.Parent then return end

        hum.PlatformStand = false
        hrp.CanCollide = true
        hum.WalkSpeed = WALK_SPEED

        local beeHrp = bee:FindFirstChild("HumanoidRootPart")
        if not beeHrp then return end

        local now = tick()
        local distToBee = (hrp.Position - beeHrp.Position).Magnitude

        if distToBee > 75 then
            tweenTo(beeHrp.Position, TWEEN_SPEED, Vector3.new(0, 5, 10))
            return
        end

        if now - lastAttack > 0.2 then
            local tool = charStep:FindFirstChildOfClass("Tool")
            if tool and distToBee < 35 then
                pcall(function() tool:Activate() end)
                lastAttack = now
            end
        end

        angle = angle + (WALK_SPEED / MANSING_RADIUS) * dt
        local targetPos = beeHrp.Position + Vector3.new(
            math.cos(angle) * MANSING_RADIUS, 
            0, 
            math.sin(angle) * MANSING_RADIUS
        )

        local waitingThorn = getWaitingThorn()
        if waitingThorn and waitingThorn.Parent then
            local toThorn = (waitingThorn.Position - beeHrp.Position).Unit
            targetPos = waitingThorn.Position - toThorn * 4
        end

        -- Уворот от шипов (WarningDisks)
        for threat, dangerDist in pairs(trackedAvoid) do
            if threat and threat.Parent then
                local threatPos = threat.Position
                local distPlayerToThreat = (hrp.Position - threatPos).Magnitude
                local distTargetToThreat = (targetPos - threatPos).Magnitude

                if distPlayerToThreat < dangerDist then
                    hum.Jump = true
                    local evadeDir = (hrp.Position - threatPos)
                    if evadeDir.Magnitude < 0.1 then evadeDir = Vector3.new(1, 0, 0) else evadeDir = evadeDir.Unit end
                    targetPos = hrp.Position + evadeDir * (dangerDist + 6)
                    break
                elseif distTargetToThreat < dangerDist then
                    local evadeDir = (targetPos - threatPos)
                    if evadeDir.Magnitude < 0.1 then evadeDir = Vector3.new(1, 0, 0) else evadeDir = evadeDir.Unit end
                    targetPos = threatPos + evadeDir * (dangerDist + 4)
                end
            end
        end

        local rp = RaycastParams.new()
        rp.FilterDescendantsInstances = { charStep }
        rp.FilterType = Enum.RaycastFilterType.Exclude
        local hit = workspace:Raycast(Vector3.new(targetPos.X, targetPos.Y + 25, targetPos.Z), Vector3.new(0, -60, 0), rp)
        if hit then
            targetPos = Vector3.new(targetPos.X, hit.Position.Y + 3, targetPos.Z)
        end

        hum:MoveTo(targetPos)

        if now - lastJump > 1.4 then
            local st = hum:GetState()
            if st == Enum.HumanoidStateType.Running or st == Enum.HumanoidStateType.Landed then
                hum.Jump = true
            end
            lastJump = now
        end
    end)

    return function()
        running = false
        if connUpdate then connUpdate:Disconnect() end
        if connAdd then connAdd:Disconnect() end
        if connRem then connRem:Disconnect() end
        local lpEnd = Players.LocalPlayer
        if lpEnd and lpEnd.Character then
            local hum = lpEnd.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum.PlatformStand = false; hum.WalkSpeed = 16 end
            local hrp = lpEnd.Character:FindFirstChild("HumanoidRootPart")
            if hrp then hrp.CanCollide = true end
        end
    end
end

-- ============================================================
-- ====== ГЛАВНАЯ ЛОГИКА ======
-- ============================================================
local function huntViciousBee()
    local curLp = Players.LocalPlayer
    if not curLp then return end

    -- Ждём персонажа
    local char, hrp
    for _ = 1, 40 do
        char = curLp.Character
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

    task.wait(0.5)

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
    print("[Hunt] ✅ Vicious не на горе — готовимся к охоте")

    -- 1. Tween к свободному улью (позиция по стрелке patharrow.Base из Atlas 2)
    print("[Hunt] Ищем улей...")
    local hive = findFreeHive()
    if not hive then
        print("[Hunt] ❌ Улей не найден — ХОП")
        hopToRandomServer()
        return
    end

    print("[Hunt] 🚀 Tween к улью:", hive.Name)
    local reachedHive = tweenTo(hive, TWEEN_SPEED, Vector3.new(0, 3, 0))
    if not reachedHive then
        print("[Hunt] ❌ Не долетели до улья — ХОП")
        hopToRandomServer()
        return
    end

    task.wait(0.5)
    print("[Hunt] Занимаем улей...")
    local occupied = occupyHive(hive)
    if not occupied then
        print("[Hunt] ❌ Улей не занят — ХОП")
        hopToRandomServer()
        return
    end
    print("[Hunt] ✅ Улей успешно занят!")

    -- 2. Tween к Vicious Bee на поле
    local beeHrp = bee:FindFirstChild("HumanoidRootPart")
    if not beeHrp then
        print("[Hunt] ❌ Vicious Bee исчезла — ХОП")
        hopToRandomServer()
        return
    end

    print("[Hunt] 🚀 Tween к Vicious Bee на поле...")
    local waitingThorn = getWaitingThorn()
    if waitingThorn then
        tweenTo(waitingThorn, TWEEN_SPEED, Vector3.new(0, 4, 0))
    else
        tweenTo(beeHrp, TWEEN_SPEED, Vector3.new(0, 6, 12))
    end

    -- 3. Запуск боя и мансинга
    print("[Hunt] ⚔️ Начинаем бой и мансинг вокруг пчелы...")
    local stopMansing = startMansing(bee)

    local maxWait, waited = 90, 0
    while waited < maxWait do
        task.wait(0.3)
        waited = waited + 0.3
        local h = bee:FindFirstChild("Humanoid")
        if not bee.Parent or not h or h.Health <= 0 then
            print("[Hunt] 🎉 Vicious Bee убита!")
            break
        end
    end

    if stopMansing then stopMansing() end

    print("[Hunt] Хоп на следующий сервер...")
    hopToRandomServer()
end

-- ============================================================
-- ====== ГЛАВНЫЙ ЦИКЛ ======
-- ============================================================
task.wait(1)
while true do
    if not getgenv().IsHopping then
        local ok, err = pcall(huntViciousBee)
        if not ok then
            warn("[Hunt] Ошибка в цикле:", err)
            if not getgenv().IsHopping then
                pcall(hopToRandomServer)
            end
        end
    end
    task.wait(1.5)
end

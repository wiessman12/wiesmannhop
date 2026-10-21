-- ============================================================
-- VICIOUS BEE SERVER HOPPER (TURBO & ANTI-CRASH EDITION)
-- ============================================================

-- Защита от дублирования скрипта в памяти
if _G.ViciousHunterRunning then
    _G.ViciousHunterRunning = false
    task.wait(0.5)
end
_G.ViciousHunterRunning = true

-- ====== 1. ОЖИДАНИЕ ЗАГРУЗКИ ИГРЫ ======
local loadStart = tick()
while not game:IsLoaded() do
    if tick() - loadStart > 20 then break end
    task.wait(0.2)
end

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local CoreGui = game:GetService("CoreGui")

local lp = Players.LocalPlayer
local lpStart = tick()
while not lp and tick() - lpStart < 15 do
    task.wait(0.2)
    lp = Players.LocalPlayer
end

local playerGui = lp and lp:WaitForChild("PlayerGui", 15)
if playerGui then
    local loadingGui = playerGui:FindFirstChild("LoadingScreenGui")
    if loadingGui then
        local msg = loadingGui:FindFirstChild("LoadingMessage")
        local msgStart = tick()
        while msg and msg.Visible and tick() - msgStart < 15 do
            task.wait(0.2)
        end
    end
end
print("[Init] ✅ Инициализация завершена!")

-- ====== НАСТРОЙКИ (ПО ВАШИМ ТРЕБОВАНИЯМ) ======
_G.unlocktween = true
local TWEEN_SPEED = 150       -- [П.4] Флай ускорен в 2 раза (было 75)
local WALK_SPEED = 60        -- Скорость бега при мансинге
local MANSING_RADIUS = 14    -- [П.3] Радиус мансинга в 2 раза меньше (было 28)
local THORN_AVOID_DIST = 9   -- Зона уворота от шипов (подстроена под радиус 14)

local DATA_FILE = "hop_data.json"
local EXPIRE_TIME = 20 * 60  
local QUEUE_MAX_AGE = 8 * 60 
local HOP_DELAY = 3.2        -- [П.2] Задержка хопа ровно 3.2с

getgenv().IsHopping = false
getgenv().HopStartTime = 0

-- ============================================================
-- ====== ИЗВЛЕЧЕНИЕ КООРДИНАТ ======
-- ============================================================
local function getPosition(obj)
    if not obj then return nil end
    if typeof(obj) == "Vector3" then return obj end
    if typeof(obj) == "CFrame" then return obj.Position end
    if typeof(obj) == "Instance" then
        if obj:FindFirstChild("patharrow") and obj.patharrow:FindFirstChild("Base") then
            return obj.patharrow.Base.Position
        end
        if obj:FindFirstChild("Platform") then
            local plat = obj.Platform
            if plat:IsA("ObjectValue") and plat.Value and plat.Value:IsA("BasePart") then
                return plat.Value.Position
            elseif plat:IsA("BasePart") then
                return plat.Position
            end
        end
        if obj:IsA("BasePart") then
            return obj.Position
        elseif obj:IsA("Model") then
            if obj.PrimaryPart then
                return obj.PrimaryPart.Position
            end
            local ok, pivot = pcall(function() return obj:GetPivot().Position end)
            if ok and pivot then return pivot end
            local anyPart = obj:FindFirstChildWhichIsA("BasePart", true)
            if anyPart then return anyPart.Position end
        elseif obj:IsA("ObjectValue") and obj.Value then
            return getPosition(obj.Value)
        end
        local anyPart = obj:FindFirstChildWhichIsA("BasePart", true)
        if anyPart then
            return anyPart.Position
        end
    end
    return nil
end

-- ============================================================
-- ====== СЕРВЕР-ХОП (БЕЗ ВЫЛЕТОВ И РЕЙТ-ЛИМИТОВ) ======
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
    local defaultData = { queue = {}, visited = {}, fetchedAt = 0 }
    if readfile and isfile and isfile(DATA_FILE) then
        local ok, data = pcall(function()
            return HttpService:JSONDecode(readfile(DATA_FILE))
        end)
        if ok and type(data) == "table" then
            data.queue = data.queue or {}
            data.visited = data.visited or {}
            data.fetchedAt = data.fetchedAt or 0
            
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
    print("[Hop] 🌐 Запрос свежей пачки серверов от API...")
    local url = string.format("https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100", tostring(game.PlaceId))
    local body = httpRequest(url)
    if not body then return false end

    local ok, decoded = pcall(HttpService.JSONDecode, HttpService, body)
    if not ok or not decoded or decoded.errors or not decoded.data then
        warn("[Hop] ⚠️ Ошибка ответа API. Используем резервный вход.")
        return false
    end

    local stableServers = {}
    local otherServers = {}

    for _, s in ipairs(decoded.data) do
        if s.id ~= game.JobId and s.playing < s.maxPlayers and not data.visited[s.id] then
            if s.playing >= 2 then
                table.insert(stableServers, s.id)
            else
                table.insert(otherServers, s.id)
            end
        end
    end

    data.queue = {}
    for _, id in ipairs(stableServers) do
        table.insert(data.queue, id)
    end
    for _, id in ipairs(otherServers) do
        table.insert(data.queue, id)
    end

    data.fetchedAt = os.time()
    print(string.format("[Hop] ✅ Получено %d серверов (Стабильных: %d)!", #data.queue, #stableServers))
    return #data.queue > 0
end

local function hopToRandomServer()
    if getgenv().IsHopping then
        if tick() - (getgenv().HopStartTime or 0) > 14 then
            getgenv().IsHopping = false
        else
            return
        end
    end

    getgenv().IsHopping = true
    getgenv().HopStartTime = tick()

    task.wait(HOP_DELAY) -- [П.2] Задержка 3.2 сек

    local currentLp = Players.LocalPlayer or lp
    local data = loadData()
    if game.JobId and game.JobId ~= "" then
        data.visited[game.JobId] = os.time()
    end

    local now = os.time()
    if (now - (data.fetchedAt or 0)) > QUEUE_MAX_AGE then
        data.queue = {}
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
            warn("[Hop] Резервный хоп через матчмейкинг...")
            pcall(function() TeleportService:Teleport(game.PlaceId, currentLp) end)
            
            task.wait(8)
            getgenv().IsHopping = false
            return
        end
    end

    local chosenIndex = math.random(1, math.min(#data.queue, 15))
    local targetJobId = table.remove(data.queue, chosenIndex)

    data.visited[targetJobId] = os.time()
    saveData(data)

    print(string.format("[Hop] 🚀 Переход на сервер: %s (Осталось: %d)", targetJobId, #data.queue))

    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, targetJobId, currentLp)
    end)

    if ok then
        local startWait = tick()
        while tick() - startWait < 12 and getgenv().IsHopping do
            task.wait(0.5)
        end

        if getgenv().IsHopping then
            pcall(function() TeleportService:TeleportCancel() end)
            getgenv().IsHopping = false
            task.wait(0.5)
            hopToRandomServer()
        end
    else
        warn("[Hop] Ошибка вызова TeleportToPlaceInstance:", err)
        getgenv().IsHopping = false
        task.wait(0.5)
        hopToRandomServer()
    end
end

-- ============================================================
-- ====== [П.1, П.5] МГНОВЕННЫЙ ДЕТЕКТ ОШИБКИ 279 + АНТИ-КРАШ ======
-- ============================================================
local isHandlingError = false

local function handleConnectionError(sourceMsg)
    if isHandlingError then return end
    isHandlingError = true
    
    warn(string.format("[Auto-Reconnect] ⚡ Мгновенный перехват ошибки (%s)! Хоп...", tostring(sourceMsg)))
    pcall(function() TeleportService:TeleportCancel() end)
    getgenv().IsHopping = false
    
    task.wait(0.3) -- моментальная реакция
    hopToRandomServer()
    
    task.delay(3, function()
        isHandlingError = false
    end)
end

-- 1. Системное событие ошибки GuiService
GuiService.ErrorMessageChanged:Connect(function(msg)
    if msg and msg ~= "" then
        handleConnectionError(msg)
    end
end)

-- 2. Сбой телепорта
TeleportService.TeleportInitFailed:Connect(function(_, result, err)
    handleConnectionError(result.Name)
end)

-- 3. Мгновенный перехват появления модального окна ErrorPrompt в CoreGui
local promptOverlay = CoreGui:FindFirstChild("RobloxPromptGui") and CoreGui.RobloxPromptGui:FindFirstChild("promptOverlay")
if promptOverlay then
    promptOverlay.ChildAdded:Connect(function(child)
        if child.Name == "ErrorPrompt" then
            handleConnectionError("ErrorPrompt Window")
        end
    end)
end

-- Фоновая быстрая проверка каждые 0.2с
task.spawn(function()
    while _G.ViciousHunterRunning do
        task.wait(0.2)
        local ok, promptGui = pcall(function() return CoreGui:FindFirstChild("RobloxPromptGui") end)
        if ok and promptGui then
            local overlay = promptGui:FindFirstChild("promptOverlay")
            if overlay and overlay:FindFirstChild("ErrorPrompt") then
                handleConnectionError("ErrorPrompt Active")
            end
        end
    end
end)

-- ============================================================
-- ====== [П.4, П.5] БЫСТРЫЙ И БЕЗОПАСНЫЙ TWEEN SYSTEM (СКОРОСТЬ 150) ======
-- ============================================================
local function tweenTo(target, speed, offset)
    local curLp = Players.LocalPlayer or lp
    if not curLp then return false end
    local char = curLp.Character
    if not char then return false end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return false end

    local targetPos = getPosition(target)
    if not targetPos or typeof(targetPos) ~= "Vector3" then
        return false
    end

    if typeof(offset) == "Vector3" then
        targetPos = targetPos + offset
    end

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
    ap.Responsiveness = 35 -- повышен отклик для скорости 150
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

    -- [П.5 ФИКС КРАША]: кэшируем детали один раз, а не сканируем GetDescendants() 60 раз/сек!
    local charParts = {}
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then
            table.insert(charParts, p)
        end
    end

    local stepSignal = RunService.PreSimulation or RunService.Stepped
    local noclipConn = stepSignal:Connect(function()
        for i = 1, #charParts do
            local p = charParts[i]
            if p and p.Parent and p.CanCollide then
                p.CanCollide = false
            end
        end
    end)

    local startClock = os.clock()
    while (os.clock() - startClock < travelTime + 1.2) and (os.clock() - startClock < 20) do
        if not hrp or not hrp.Parent or hum.Health <= 0 then break end
        if (hrp.Position - targetPos).Magnitude < 4.5 then break end
        RunService.Heartbeat:Wait()
    end

    noclipConn:Disconnect()
    ap:Destroy()
    ao:Destroy()

    for i = 1, #charParts do
        local p = charParts[i]
        if p and p.Parent then
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
        if (o.Name:find("Vicious") or o.Name:find("Gifted Vicious")) and o:FindFirstChild("HumanoidRootPart") then
            local h = o:FindFirstChildOfClass("Humanoid")
            if not h or h.Health > 0 then
                return o
            end
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
    local hit = workspace:Raycast(pos + Vector3.new(0, 20, 0), Vector3.new(0, -70, 0), rp)
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
    local curLp = Players.LocalPlayer or lp
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
        task.wait(0.4)
    end
    return curLp:FindFirstChild("Honeycomb") ~= nil
end

-- ============================================================
-- ====== [П.3] МАНСИНГ (РАДИУС 14 СТАДСОВ) ======
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
                task.delay(1.2, function()
                    trackedAvoid[child] = nil
                end)
            end
        end)
    end

    local curLp = Players.LocalPlayer or lp
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

        local lpStep = Players.LocalPlayer or lp
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

        if distToBee > 60 then
            local pos = getPosition(beeHrp)
            if pos then tweenTo(pos, TWEEN_SPEED, Vector3.new(0, 4, 8)) end
            return
        end

        if now - lastAttack > 0.15 then
            local tool = charStep:FindFirstChildOfClass("Tool")
            if tool and distToBee < 30 then
                pcall(function() tool:Activate() end)
                lastAttack = now
            end
        end

        -- [П.3] Мансинг по радиусу 14
        angle = angle + (WALK_SPEED / MANSING_RADIUS) * dt
        local targetPos = beeHrp.Position + Vector3.new(
            math.cos(angle) * MANSING_RADIUS, 
            0, 
            math.sin(angle) * MANSING_RADIUS
        )

        local waitingThorn = getWaitingThorn()
        if waitingThorn and waitingThorn.Parent then
            local toThorn = (waitingThorn.Position - beeHrp.Position).Unit
            targetPos = waitingThorn.Position - toThorn * 3
        end

        -- Уворот от шипов
        for threat, dangerDist in pairs(trackedAvoid) do
            if threat and threat.Parent then
                local threatPos = threat.Position
                local distPlayerToThreat = (hrp.Position - threatPos).Magnitude
                local distTargetToThreat = (targetPos - threatPos).Magnitude

                if distPlayerToThreat < dangerDist then
                    hum.Jump = true
                    local evadeDir = (hrp.Position - threatPos)
                    if evadeDir.Magnitude < 0.1 then evadeDir = Vector3.new(1, 0, 0) else evadeDir = evadeDir.Unit end
                    targetPos = hrp.Position + evadeDir * (dangerDist + 5)
                    break
                elseif distTargetToThreat < dangerDist then
                    local evadeDir = (targetPos - threatPos)
                    if evadeDir.Magnitude < 0.1 then evadeDir = Vector3.new(1, 0, 0) else evadeDir = evadeDir.Unit end
                    targetPos = threatPos + evadeDir * (dangerDist + 3)
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

        if now - lastJump > 1.3 then
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
        local lpEnd = Players.LocalPlayer or lp
        if lpEnd and lpEnd.Character then
            local hum = lpEnd.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum.PlatformStand = false; hum.WalkSpeed = 16 end
            local hrp = lpEnd.Character:FindFirstChild("HumanoidRootPart")
            if hrp then hrp.CanCollide = true end
        end
    end
end

-- ============================================================
-- ====== [П.6] ГЛАВНАЯ ЛОГИКА (БЫСТРЫЙ ДЕТЕКТ СМЕРТИ) ======
-- ============================================================
local function huntViciousBee()
    local curLp = Players.LocalPlayer or lp
    if not curLp then return end

    local char, hrp
    for _ = 1, 35 do
        char = curLp.Character
        if char and char:FindFirstChild("HumanoidRootPart") and char:FindFirstChildOfClass("Humanoid") then
            hrp = char.HumanoidRootPart
            break
        end
        task.wait(0.15)
    end
    if not char or not hrp then
        print("[Hunt] Персонаж не прогрузился — хоп")
        hopToRandomServer()
        return
    end

    local monsters = workspace:WaitForChild("Monsters", 4)
    if not monsters then
        print("[Hunt] Monsters не прогрузились — хоп")
        hopToRandomServer()
        return
    end

    task.wait(0.3)

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

    -- 1. Tween к свободному улью (скорость 150)
    print("[Hunt] Ищем улей...")
    local hive = findFreeHive()
    if not hive then
        print("[Hunt] ❌ Улей не найден — ХОП")
        hopToRandomServer()
        return
    end

    print("[Hunt] 🚀 Быстрый Tween к улью:", hive.Name)
    local hivePos = getPosition(hive)
    if not hivePos then
        hopToRandomServer()
        return
    end

    local reachedHive = tweenTo(hivePos, TWEEN_SPEED, Vector3.new(0, 3, 0))
    if not reachedHive then
        print("[Hunt] ❌ Не долетели до улья — ХОП")
        hopToRandomServer()
        return
    end

    task.wait(0.3)
    print("[Hunt] Занимаем улей...")
    local occupied = occupyHive(hive)
    if not occupied then
        print("[Hunt] ❌ Улей не занят — ХОП")
        hopToRandomServer()
        return
    end
    print("[Hunt] ✅ Улей успешно занят!")

    -- 2. Tween к Vicious Bee на поле (скорость 150)
    local beeHrp = bee:FindFirstChild("HumanoidRootPart")
    if not beeHrp then
        print("[Hunt] ❌ Vicious Bee исчезла — ХОП")
        hopToRandomServer()
        return
    end

    print("[Hunt] 🚀 Быстрый Tween к Vicious Bee на поле...")
    local waitingThorn = getWaitingThorn()
    local targetPos = (waitingThorn and getPosition(waitingThorn)) or getPosition(beeHrp)

    if targetPos then
        tweenTo(targetPos, TWEEN_SPEED, Vector3.new(0, 5, 8))
    end

    -- 3. Запуск боя и мансинга
    print("[Hunt] ⚔️ Бой и мансинг вокруг пчелы (радиус 14)...")
    local stopMansing = startMansing(bee)

    -- [П.6] МГНОВЕННЫЙ ДЕТЕКТ СМЕРТИ ПЧЕЛЫ ЧЕРЕЗ СОБЫТИЯ
    local isBeeDead = false
    local lastDeathPos = getPosition(beeHrp) or hrp.Position
    local deathConns = {}

    local function onDead()
        if isBeeDead then return end
        isBeeDead = true
        if beeHrp and beeHrp.Parent then
            lastDeathPos = beeHrp.Position
        end
    end

    local beeHum = bee:FindFirstChildOfClass("Humanoid")
    if beeHum then
        table.insert(deathConns, beeHum.Died:Connect(onDead))
        table.insert(deathConns, beeHum:GetPropertyChangedSignal("Health"):Connect(function()
            if beeHum.Health <= 0 then onDead() end
        end))
    end
    table.insert(deathConns, bee.AncestryChanged:Connect(function(_, parent)
        if not parent then onDead() end
    end))

    local maxWait, waited = 90, 0
    while waited < maxWait and not isBeeDead do
        task.wait(0.1) -- быстрый опрос каждые 100мс
        waited = waited + 0.1

        -- Проверка на смерть персонажа игрока
        local myChar = curLp.Character
        local myHum = myChar and myChar:FindFirstChildOfClass("Humanoid")
        if not myHum or myHum.Health <= 0 then
            warn("[Hunt] 💀 Персонаж погиб! Ожидание возрождения...")
            if stopMansing then stopMansing() end
            
            curLp.CharacterAdded:Wait()
            task.wait(1)
            
            if not isBeeDead and bee and bee.Parent then
                local bHrp = bee:FindFirstChild("HumanoidRootPart")
                if bHrp then
                    print("[Hunt] 🚀 Быстрый возврат к пчеле...")
                    tweenTo(bHrp.Position, TWEEN_SPEED, Vector3.new(0, 5, 8))
                    stopMansing = startMansing(bee)
                end
            else
                break
            end
        end

        if not bee or not bee.Parent then
            onDead()
            break
        end
        if beeHrp and beeHrp.Parent then
            lastDeathPos = beeHrp.Position
        end
    end

    -- Отключаем слушатели
    for _, c in ipairs(deathConns) do pcall(function() c:Disconnect() end) end
    if stopMansing then stopMansing() end

    -- [П.6] Быстрый подбор жал (всего 2 секунды вместо 3.5)
    print("[Hunt] ⚡ Vicious Bee уничтожена! Быстрый сбор жал...")
    local collectStart = tick()
    while tick() - collectStart < 2.0 do
        local myChar = curLp.Character
        local myHum = myChar and myChar:FindFirstChildOfClass("Humanoid")
        if myHum and myHum.Health > 0 then
            local angle = (tick() - collectStart) * 8
            local offset = Vector3.new(math.cos(angle) * 8, 0, math.sin(angle) * 8)
            myHum:MoveTo(lastDeathPos + offset)
        end
        task.wait(0.1)
    end

    print("[Hunt] Хоп на следующий сервер...")
    hopToRandomServer()
end

-- ============================================================
-- ====== СЕРВЕРНЫЙ СТОРОЖ (WATCHDOG 90 СЕК) ======
-- ============================================================
local serverEntryTime = tick()
task.spawn(function()
    while _G.ViciousHunterRunning do
        task.wait(4)
        if tick() - serverEntryTime > 90 and not getgenv().IsHopping then
            warn("[Watchdog] ⚠️ Превышено время нахождения на сервере (90 сек). Принудительный хоп!")
            hopToRandomServer()
        end
    end
end)

-- ============================================================
-- ====== ГЛАВНЫЙ ЦИКЛ ======
-- ============================================================
task.wait(1)
while _G.ViciousHunterRunning do
    if not getgenv().IsHopping then
        local ok, err = pcall(huntViciousBee)
        if not ok then
            warn("[Hunt] Ошибка в цикле:", err)
            if not getgenv().IsHopping then
                pcall(hopToRandomServer)
            end
        end
    end
    task.wait(1)
end

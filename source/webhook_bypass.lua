-- ============================================================
-- VICIOUS BEE SERVER HOPPER (INSTANT HOP & +10 TWEEN EDITION)
-- ============================================================

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local CoreGui = game:GetService("CoreGui")

-- ====== НАСТРОЙКИ ======
_G.unlocktween = true
_G.ViciousHunterRunning = true

local TWEEN_SPEED = 150       -- Скорость полета (150 стадс/сек)
local WALK_SPEED = 60         -- Скорость бега при мансинге
local MANSING_RADIUS = 14     -- Радиус мансинга (14 стадс)
local THORN_AVOID_DIST = 11   -- Дистанция уворота от шипов (WarningDisk)

local DATA_FILE = "hop_data.json"
local EXPIRE_TIME = 20 * 60   -- Сервер хранится 20 минут в черном списке
local QUEUE_MAX_AGE = 8 * 60  -- Список серверов обновляется раз в 8 минут

getgenv().IsHopping = false

-- ============================================================
-- ====== 1. ОЖИДАНИЕ ЗАГРУЗКИ ИГРЫ (ВМЕСТО СЕКУНД) ======
-- ============================================================
local function waitForGameLoaded()
    if not game:IsLoaded() then
        game.Loaded:Wait()
    end

    local curLp = Players.LocalPlayer
    while not curLp do
        task.wait(0.1)
        curLp = Players.LocalPlayer
    end

    local playerGui = curLp:WaitForChild("PlayerGui", 30)
    if not playerGui then return end

    -- Ожидание закрытия экрана загрузки Bee Swarm Simulator
    local startWait = tick()
    while tick() - startWait < 30 do
        local loadingGui = playerGui:FindFirstChild("LoadingScreenGui")
        local msg = loadingGui and loadingGui:FindFirstChild("LoadingMessage")
        if loadingGui and msg then
            if not msg.Visible then
                break -- Экран загрузки полностью закрылся
            end
        elseif not loadingGui and (tick() - startWait < 2.5) then
            task.wait(0.1)
        else
            break
        end
        task.wait(0.1)
    end
end

-- Первичная загрузка
waitForGameLoaded()
print("[Init] ✅ Игра и экран загрузки полностью завершены!")

-- ============================================================
-- ====== БЕЗОПАСНОЕ ИЗВЛЕЧЕНИЕ КООРДИНАТ ======
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
        elseif obj:IsA("ObjectValue") and obj.Value and obj.Value:IsA("BasePart") then
            return obj.Value.Position
        end
    end
    return nil
end

-- ============================================================
-- ====== ОПРЕДЕЛЕНИЕ И ГРАНИЦЫ ПОЛЕЙ ======
-- ============================================================
local function getFieldForPosition(pos)
    if not pos then return nil end
    local fz = workspace:FindFirstChild("FlowerZones")
    if not fz then return nil end

    local rp = RaycastParams.new()
    rp.FilterDescendantsInstances = { fz }
    rp.FilterType = Enum.RaycastFilterType.Include

    local hitDown = workspace:Raycast(pos + Vector3.new(0, 45, 0), Vector3.new(0, -90, 0), rp)
    if hitDown and hitDown.Instance and hitDown.Instance.Parent == fz then
        return hitDown.Instance
    end

    local hitUp = workspace:Raycast(pos - Vector3.new(0, 45, 0), Vector3.new(0, 90, 0), rp)
    if hitUp and hitUp.Instance and hitUp.Instance.Parent == fz then
        return hitUp.Instance
    end

    local bestField = nil
    local bestDist = math.huge
    for _, f in ipairs(fz:GetChildren()) do
        if f:IsA("BasePart") then
            local dist2D = (Vector2.new(pos.X, pos.Z) - Vector2.new(f.Position.X, f.Position.Z)).Magnitude
            local maxRadius = math.max(f.Size.X, f.Size.Z) / 2 + 15
            if dist2D < maxRadius and dist2D < bestDist then
                bestDist = dist2D
                bestField = f
            end
        end
    end

    return bestField
end

-- ============================================================
-- ====== СЕРВЕР-ХОП (МГНОВЕННЫЙ ХОП) ======
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

    -- Если экран загрузки еще не завершен — ждем его перед хопом!
    waitForGameLoaded()

    getgenv().IsHopping = true
    getgenv().HopStartTime = tick()

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
            
            task.wait(6)
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
            task.wait(0.3)
        end

        if getgenv().IsHopping then
            pcall(function() TeleportService:TeleportCancel() end)
            getgenv().IsHopping = false
            task.wait(0.2)
            hopToRandomServer()
        end
    else
        warn("[Hop] Ошибка вызова TeleportToPlaceInstance:", err)
        getgenv().IsHopping = false
        task.wait(0.2)
        hopToRandomServer()
    end
end

-- ============================================================
-- ====== МГНОВЕННЫЙ ДЕТЕКТ ОШИБКИ 279 + АНТИ-КРАШ ======
-- ============================================================
local isHandlingError = false

local function handleConnectionError(sourceMsg)
    if isHandlingError then return end
    isHandlingError = true
    
    warn(string.format("[Auto-Reconnect] ⚡ Мгновенный перехват ошибки (%s)! Хоп...", tostring(sourceMsg)))
    pcall(function() TeleportService:TeleportCancel() end)
    getgenv().IsHopping = false
    
    task.wait(0.1)
    hopToRandomServer()
    
    task.delay(3, function()
        isHandlingError = false
    end)
end

GuiService.ErrorMessageChanged:Connect(function(msg)
    if msg and msg ~= "" then
        handleConnectionError(msg)
    end
end)

TeleportService.TeleportInitFailed:Connect(function(_, result, err)
    handleConnectionError(result.Name)
end)

local promptOverlay = CoreGui:FindFirstChild("RobloxPromptGui") and CoreGui.RobloxPromptGui:FindFirstChild("promptOverlay")
if promptOverlay then
    promptOverlay.ChildAdded:Connect(function(child)
        if child.Name == "ErrorPrompt" then
            handleConnectionError("ErrorPrompt Window")
        end
    end)
end

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
-- ====== ТРАВЕРС И БЕЗОПАСНЫЙ TWEEN (С ВЫСОТОЙ +10 СТАДС) ======
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
    ap.Responsiveness = 35
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
    while (os.clock() - startClock < travelTime + 1.2) and (os.clock() - startClock < 25) do
        if not hrp or not hrp.Parent or hum.Health <= 0 then break end
        if (hrp.Position - targetPos).Magnitude < 4.0 then break end
        RunService.Heartbeat:Wait()
    end

    -- Завершение твина: обнуление скоростей и возвращение коллизии
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero

    noclipConn:Disconnect()
    ap:Destroy()
    ao:Destroy()

    for i = 1, #charParts do
        local p = charParts[i]
        if p and p.Parent then
            p.CanCollide = true
        end
    end

    hum.PlatformStand = false
    hum:ChangeState(Enum.HumanoidStateType.Running)

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

local function isOnMountainTop(bee)
    local hrp = bee:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    if hrp.Position.Y > 140 then return true end
    local field = getFieldForPosition(hrp.Position)
    return field and field.Name == "Mountain Top Field"
end

local function findFreeHive()
    local hc = workspace:FindFirstChild("Honeycombs")
    if not hc then return nil end
    for i = 6, 1, -1 do
        local hive = hc:FindFirstChild("Hive" .. i)
        if hive then
            local owner = hive:FindFirstChild("Owner")
            if owner and owner.Value == nil then
                return hive
            end
        end
    end
    return nil
end

local function occupyHive(hive)
    local curLp = Players.LocalPlayer or lp
    if not curLp then return false end
    local char = curLp.Character
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    local targetPos = getPosition(hive)
    if not targetPos then return false end

    hrp.CFrame = CFrame.new(targetPos + Vector3.new(0, 3, 0))
    task.wait(0.2)

    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
        task.wait(0.1)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
    end)

    task.wait(0.5)
    local owner = hive:FindFirstChild("Owner")
    return owner and owner.Value == curLp
end

-- ============================================================
-- ====== БОЙ И МАНСИНГ С ОГРАНИЧЕНИЕМ ПОЛЕМ ======
-- ============================================================
local function startMansing(bee, currentFieldPart, onBeeDiedCallback)
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

        -- МГНОВЕННЫЙ ДЕТЕКТ СМЕРТИ В КАЖДОМ КАДРЕ (60 РАЗ/СЕК)
        if not bee or not bee.Parent or not bee:IsDescendantOf(workspace) then
            if onBeeDiedCallback then onBeeDiedCallback() end
            return
        end
        local bHum = bee:FindFirstChildOfClass("Humanoid")
        if bHum and bHum.Health <= 0 then
            if onBeeDiedCallback then onBeeDiedCallback() end
            return
        end

        dt = math.min(dt, 0.05)

        local lpStep = Players.LocalPlayer or lp
        if not lpStep then return end
        local charStep = lpStep.Character
        if not charStep then return end

        local hrp = charStep:FindFirstChild("HumanoidRootPart")
        local hum = charStep:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then return end

        hum.PlatformStand = false
        hrp.CanCollide = true
        hum.WalkSpeed = WALK_SPEED

        local beeHrp = bee:FindFirstChild("HumanoidRootPart")
        if not beeHrp then return end

        local now = tick()
        local distToBee = (hrp.Position - beeHrp.Position).Magnitude

        -- Возврат к пчеле с высотой +10 стадс
        if distToBee > 65 then
            local pos = getPosition(beeHrp)
            if pos then tweenTo(pos, TWEEN_SPEED, Vector3.new(0, 10, 0)) end
            return
        end

        -- Авто-атака инструментом
        if now - lastAttack > 0.15 then
            local tool = charStep:FindFirstChildOfClass("Tool")
            if tool and distToBee < 30 then
                pcall(function() tool:Activate() end)
                lastAttack = now
            end
        end

        -- Мансинг по радиусу 14
        angle = angle + (WALK_SPEED / MANSING_RADIUS) * dt
        local targetPos = beeHrp.Position + Vector3.new(
            math.cos(angle) * MANSING_RADIUS, 
            0, 
            math.sin(angle) * MANSING_RADIUS
        )

        -- Если активен шип пробуждения
        local waitingThorn = getWaitingThorn()
        if waitingThorn and waitingThorn.Parent then
            local toThorn = (waitingThorn.Position - beeHrp.Position).Unit
            targetPos = waitingThorn.Position - toThorn * 3
        end

        -- Уворот от шипов (WarningDisk)
        for threat, dangerDist in pairs(trackedAvoid) do
            if threat and threat.Parent then
                local threatPos = threat.Position
                local distPlayerToThreat = (hrp.Position - threatPos).Magnitude
                local distTargetToThreat = (targetPos - threatPos).Magnitude

                if distPlayerToThreat < dangerDist then
                    hum.Jump = true
                    local evadeDir = (hrp.Position - threatPos)
                    if evadeDir.Magnitude < 0.1 then evadeDir = Vector3.new(1, 0, 0) else evadeDir = evadeDir.Unit end
                    targetPos = hrp.Position + evadeDir * (dangerDist + 4)
                    break
                elseif distTargetToThreat < dangerDist then
                    local evadeDir = (targetPos - threatPos)
                    if evadeDir.Magnitude < 0.1 then evadeDir = Vector3.new(1, 0, 0) else evadeDir = evadeDir.Unit end
                    targetPos = threatPos + evadeDir * (dangerDist + 2)
                end
            end
        end

        -- Защита от вылета с поля (Spider / Clover)
        if currentFieldPart and currentFieldPart:IsA("BasePart") then
            local c = currentFieldPart.Position
            local hx = math.max(6, (currentFieldPart.Size.X / 2) - 6)
            local hz = math.max(6, (currentFieldPart.Size.Z / 2) - 6)
            targetPos = Vector3.new(
                math.clamp(targetPos.X, c.X - hx, c.X + hx),
                targetPos.Y,
                math.clamp(targetPos.Z, c.Z - hz, c.Z + hz)
            )
        end

        -- Подгоняем высоту под поверхность поля
        local rp = RaycastParams.new()
        rp.FilterDescendantsInstances = { charStep }
        rp.FilterType = Enum.RaycastFilterType.Exclude
        local hit = workspace:Raycast(Vector3.new(targetPos.X, targetPos.Y + 15, targetPos.Z), Vector3.new(0, -25, 0), rp)
        if hit then
            targetPos = Vector3.new(targetPos.X, hit.Position.Y + 3.2, targetPos.Z)
        elseif currentFieldPart then
            targetPos = Vector3.new(targetPos.X, currentFieldPart.Position.Y + 3.5, targetPos.Z)
        end

        hum:MoveTo(targetPos)

        if now - lastJump > 1.3 then
            local st = hum:GetState()
            if st ~= Enum.HumanoidStateType.Jumping and st ~= Enum.HumanoidStateType.Freefall then
                hum.Jump = true
                lastJump = now
            end
        end
    end)

    return function()
        running = false
        if connAdd then connAdd:Disconnect() end
        if connRem then connRem:Disconnect() end
        if connUpdate then connUpdate:Disconnect() end
        local pLp = Players.LocalPlayer or lp
        if pLp and pLp.Character then
            local h = pLp.Character:FindFirstChildOfClass("Humanoid")
            if h then h.WalkSpeed = 16 end
        end
    end
end

-- ============================================================
-- ====== ГЛАВНАЯ ЛОГИКА ОХОТЫ ======
-- ============================================================
local function huntViciousBee()
    print("[Hunt] Ищем Vicious Bee...")
    local bee = findViciousBee()
    if not bee then
        print("[Hunt] ❌ Vicious не найден — ХОП")
        hopToRandomServer()
        return
    end

    print(string.format("[Hunt] ✅ Vicious найден: %s", bee.Name))

    if isOnMountainTop(bee) then
        print("[Hunt] ⚠️ Vicious Bee на Mountain Top — пропускаем и хопаем")
        hopToRandomServer()
        return
    end

    local curLp = Players.LocalPlayer or lp
    local char = curLp.Character or curLp.CharacterAdded:Wait()
    local hrp = char:WaitForChild("HumanoidRootPart", 10)
    if not hrp then
        hopToRandomServer()
        return
    end

    -- 1. Поиск и занятие свободного улья
    print("[Hunt] Ищем свободный улей...")
    local hive = findFreeHive()
    if not hive then
        print("[Hunt] ❌ Свободных ульев нет — ХОП")
        hopToRandomServer()
        return
    end

    print("[Hunt] 🚀 Tween к улью:", hive.Name)
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

    -- 2. Определение поля и Tween напрямую к полю (+10 стадс)
    local beeHrp = bee:FindFirstChild("HumanoidRootPart")
    if not beeHrp then
        print("[Hunt] ❌ Vicious Bee исчезла — ХОП")
        hopToRandomServer()
        return
    end

    local waitingThorn = getWaitingThorn()
    local fieldPart = getFieldForPosition((waitingThorn and waitingThorn.Position) or beeHrp.Position)
    local targetLandingPos

    if fieldPart then
        print(string.format("[Hunt] 📍 Поле обнаружено: %s (твин на +10 стадс)", fieldPart.Name))
        targetLandingPos = fieldPart.Position + Vector3.new(0, 10, 0)
    else
        targetLandingPos = (waitingThorn and waitingThorn.Position) or (beeHrp.Position + Vector3.new(0, 10, 0))
    end

    -- Прямой быстрый Tween к полю на +10 стадс
    print("[Hunt] 🚀 Прямой быстрый Tween к полю (+10 стадс)...")
    tweenTo(targetLandingPos, TWEEN_SPEED)

    -- Если есть WaitingThorn, мягко подходим к шипу, чтобы разбудить пчелу
    waitingThorn = getWaitingThorn()
    if waitingThorn and waitingThorn.Parent then
        print("[Hunt] 🌵 Активируем WaitingThorn на поле...")
        tweenTo(waitingThorn.Position + Vector3.new(0, 3.5, 0), 70)
        task.wait(0.3)
    end

    -- 3. Мгновенная реакция на смерть пчелы (сразу хоп!)
    local isBeeDead = false
    local deathConns = {}
    local stopMansing

    local function onDead()
        if isBeeDead then return end
        isBeeDead = true
        print("[Hunt] 💀 Vicious Bee погибла! МГНОВЕННЫЙ ХОП...")
        for _, c in ipairs(deathConns) do pcall(function() c:Disconnect() end) end
        if stopMansing then stopMansing() end
        task.spawn(hopToRandomServer)
    end

    -- Запуск боя и мансинга (с передачей коллбэка мгновенной смерти)
    print("[Hunt] ⚔️ Бой и мансинг вокруг пчелы (радиус 14)...")
    stopMansing = startMansing(bee, fieldPart, onDead)

    -- Мгновенные слушатели смерти
    local beeHum = bee:FindFirstChildOfClass("Humanoid")
    if beeHum then
        table.insert(deathConns, beeHum.Died:Connect(onDead))
        table.insert(deathConns, beeHum:GetPropertyChangedSignal("Health"):Connect(function()
            if beeHum.Health <= 0 then onDead() end
        end))
    end
    table.insert(deathConns, bee.AncestryChanged:Connect(function(_, parent)
        if not parent or not bee:IsDescendantOf(workspace) then onDead() end
    end))
    table.insert(deathConns, bee.Destroying:Connect(onDead))

    local monstersFolder = workspace:FindFirstChild("Monsters")
    if monstersFolder then
        table.insert(deathConns, monstersFolder.ChildRemoved:Connect(function(child)
            if child == bee then onDead() end
        end))
    end

    local maxWait, waited = 90, 0
    while waited < maxWait and not isBeeDead do
        task.wait(0.05) -- ультрабыстрый опрос каждые 50мс
        waited = waited + 0.05

        if not bee or not bee.Parent or not bee:IsDescendantOf(workspace) then
            onDead()
            break
        end

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
                    print("[Hunt] 🚀 Возврат к пчеле (+10 стадс)...")
                    tweenTo(bHrp.Position, TWEEN_SPEED, Vector3.new(0, 10, 0))
                    stopMansing = startMansing(bee, fieldPart, onDead)
                end
            else
                break
            end
        end
    end
end

-- ============================================================
-- ====== СТОРОЖЕВОЙ ТАЙМЕР (WATCHDOG 90 СЕК) ======
-- ============================================================
local serverEntryTime = tick()
task.spawn(function()
    while _G.ViciousHunterRunning do
        task.wait(2)
        if tick() - serverEntryTime > 90 and not getgenv().IsHopping then
            warn("[Watchdog] ⏰ Сервер превысил лимит в 90 сек — принудительный хоп!")
            hopToRandomServer()
            break
        end
    end
end)

-- ЗАПУСК ОХОТЫ
task.spawn(function()
    local ok, err = pcall(huntViciousBee)
    if not ok then
        warn("[Hunt] Ошибка выполнения цикла охоты:", err)
        hopToRandomServer()
    end
end)

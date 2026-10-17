-- ============================================================
-- SERVICES
-- ============================================================
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

-- ============================================================
-- УТИЛИТЫ
-- ============================================================
local function resetCharacterState()
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hum then
        hum.PlatformStand = false
        hum.WalkSpeed = 16
    end
    if hrp then
        hrp.CanCollide = true
    end
end

-- ============================================================
-- ХОП
-- ============================================================
getgenv().VisitedServers = getgenv().VisitedServers or {}

local function hopToRandomServer()
    resetCharacterState() -- Гарантированный сброс перед хопом
    task.wait(1.2)
    if not player or not player.Parent then return end

    local success, servers = pcall(function()
        return HttpService:JSONDecode(
            game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100")
        )
    end)

    if not success or not servers or not servers.data or #servers.data == 0 then
        TeleportService:Teleport(game.PlaceId, player)
        return
    end

    local currentJobId = game.JobId
    local candidates = {}

    for _, server in ipairs(servers.data) do
        if server.id ~= currentJobId
            and server.playing < server.maxPlayers
            and server.id ~= "" then
            local alreadyVisited = false
            for _, visitedId in ipairs(getgenv().VisitedServers) do
                if visitedId == server.id then
                    alreadyVisited = true
                    break
                end
            end
            if not alreadyVisited then
                table.insert(candidates, server)
            end
        end
    end

    while #getgenv().VisitedServers > 150 do
        table.remove(getgenv().VisitedServers, 1)
    end

    if #candidates == 0 then
        TeleportService:Teleport(game.PlaceId, player)
        return
    end

    local chosen = candidates[math.random(#candidates)]
    table.insert(getgenv().VisitedServers, chosen.id)

    TeleportService:TeleportToPlaceInstance(game.PlaceId, chosen.id, player)
end

-- ============================================================
-- ПОИСК
-- ============================================================
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
    end
    return nil
end

local function isViciousBeeNearMondo(bee)
    local mondo = findMondoChick()
    if not mondo then return false end
    return (bee:GetPivot().Position - mondo:GetPivot().Position).Magnitude < 200
end

-- ============================================================
-- УЛЕЙ
-- ============================================================
local function findFreeHive()
    local honeycombs = workspace:FindFirstChild("Honeycombs")
    if not honeycombs then return nil end

    local freeHive = nil

    for i = 1, 6 do
        local hive = honeycombs:FindFirstChild("Hive" .. i)
        if hive then
            local owner = hive:FindFirstChild("Owner")
            local v = owner and owner.Value

            -- Приоритет 1: наш улей
            if v == player then
                print("[Hunt] ✅ Улей уже наш:", hive.Name)
                return hive
            end

            -- Приоритет 2: первый свободный
            if not freeHive and (not v or not v:IsA("Player") or not v.Parent) then
                freeHive = hive
            end
        end
    end

    if freeHive then
        print("[Hunt] ✅ Свободный улей:", freeHive.Name)
        return freeHive
    end

    print("[Hunt] ❌ Свободных ульев нет")
    return nil
end

-- ============================================================
-- FLY (полёт + приземление)
-- ============================================================
local function flyTo(target, offset)
    local success, result = pcall(function()
        local char = player.Character
        if not char then return false end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if not hrp or not target or not humanoid then return false end

        -- 🔥 Полёт: гравитация off, коллизия HRP off
        humanoid.PlatformStand = true
        local originalCollide = hrp.CanCollide
        hrp.CanCollide = false

        offset = offset or Vector3.new(0, 3, 0)
        local targetPos
        if target:IsA("Model") then
            targetPos = target.PrimaryPart and target.PrimaryPart.Position or target:GetPivot().Position
        else
            targetPos = target.Position
        end
        targetPos = targetPos + offset

        local bv = Instance.new("BodyVelocity")
        bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        bv.P = 2000
        bv.Parent = hrp

        local look = hrp.CFrame.LookVector
        if look.Magnitude < 0.1 then look = Vector3.new(0, 0, -1) end
        local originalRot = CFrame.new(Vector3.zero, look)

        local startTime = tick()
        local distanceToTarget = (hrp.Position - targetPos).Magnitude
        local maxFlyTime = math.clamp(distanceToTarget / 400 + 2, 2.5, 6)
        local lastPos = hrp.Position
        local stuckTimer = 0
        local connection

        local rayParams = RaycastParams.new()
        rayParams.FilterDescendantsInstances = {char}
        rayParams.FilterType = Enum.RaycastFilterType.Exclude

        connection = RunService.Heartbeat:Connect(function(dt)
            if tick() - startTime > maxFlyTime then
                if connection then connection:Disconnect() end
                return
            end
            if not hrp or not hrp.Parent or hrp.Parent ~= char then
                if connection then connection:Disconnect() end
                return
            end

            local distance = (hrp.Position - targetPos).Magnitude
            if distance < 8 then
                bv.Velocity = Vector3.zero
                if connection then connection:Disconnect() end
                return
            end

            -- 🔥 Детект застревания + Raycast 8 направлений
            if (hrp.Position - lastPos).Magnitude < 2 then
                stuckTimer = stuckTimer + dt
                if stuckTimer > 0.4 then
                    local testDirs = {
                        Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0),
                        Vector3.new(0, 0, 1), Vector3.new(0, 0, -1),
                        Vector3.new(1, 0, 1).Unit, Vector3.new(-1, 0, 1).Unit,
                        Vector3.new(1, 0, -1).Unit, Vector3.new(-1, 0, -1).Unit,
                    }
                    local bestDir = Vector3.new(0, 1, 0)
                            for _, dir in ipairs(testDirs) do
                        local hit = workspace:Raycast(hrp.Position, dir * 12, rayParams)
                        if not hit then
                            bestDir = dir
                            break
                        end
                    end
                    bv.Velocity = bestDir * 250 + Vector3.new(0, 300, 0)
                    stuckTimer = 0
                end
            else
                stuckTimer = 0
            end
            lastPos = hrp.Position

            local direction = (targetPos - hrp.Position).Unit
            local speed = 400
            if distance < 30 then speed = 200 end
            bv.Velocity = direction * speed
            hrp.CFrame = CFrame.new(hrp.Position) * originalRot
        end)

        local waitStart = tick()
        while connection.Connected and tick() - waitStart < maxFlyTime + 1 do
            task.wait(0.05)
        end
        if connection.Connected then connection:Disconnect() end
        if bv and bv.Parent then bv:Destroy() end

        if hrp and hrp.Parent then
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            hrp.CanCollide = originalCollide -- Коллизии ДО падения
        end

        -- 🔥 Гравитация вкл → падаем на землю
        if humanoid and humanoid.Parent then
            humanoid.PlatformStand = false
        end

        -- Ждём приземления по Y-velocity
        local landStart = tick()
        while tick() - landStart < 2 do
            if hrp and hrp.Parent then
                local vy = hrp.AssemblyLinearVelocity.Y
                if vy > -5 and vy < 5 then break end
            end
            task.wait(0.05)
        end

        if not hrp or not hrp.Parent then return false end
        return (hrp.Position - targetPos).Magnitude < 30
    end)

    if not success then
        print("[Fly] ❌ ОШИБКА:", result)
        resetCharacterState() -- Fallback
        return false
    end
    return result
end

-- ============================================================
-- НАЖАТИЕ E
-- ============================================================
local function pressE(hive)
    local prompt = hive and hive:FindFirstChildOfClass("ProximityPrompt")
    if prompt and fireproximityprompt then
        pcall(function() fireproximityprompt(prompt) end)
    else
        pcall(function() VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game) end)
        task.wait(0.15)
        pcall(function() VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game) end)
    end
end

-- ============================================================
-- МАНСИНГ (бег по полю с уклонением)
-- ============================================================
local function startMansing(bee)
    local running = true
    local connection
    local isFlying = false

    local radius = 18         -- радиус орбиты
    local walkSpeed = 26      -- скорость бега (макс безопасная)
    local jumpInterval = 1.2  -- прыжок каждые 1.2 сек
    local moveInterval = 0.1  -- MoveTo каждые 0.1 сек (или при смещении > 4)
    local zigzagAmp = 0.45    -- амплитуда зигзага (радиан)
    local zigzagSpeed = 5     -- скорость зигзага (рад/сек)

    local lastJump = 0
    local lastMoveTime = 0
    local lastMoveTarget = Vector3.zero
    local zigzagPhase = 0

    -- 🔥 Гарантированный сброс состояния перед стартом
    resetCharacterState()

    task.spawn(function()
        local angle = 0

        -- 🔥 Стартуем с текущего угла (не бежим через пчелу)
        local startChar = player.Character
        if startChar and bee then
            local h = startChar:FindFirstChild("HumanoidRootPart")
            local b = bee:FindFirstChild("HumanoidRootPart")
            if h and b then
                local v = h.Position - b.Position
                if v.Magnitude > 1 then
                    angle = math.atan2(v.Z, v.X)
                end
            end
        end
            local rayParams = RaycastParams.new()
        rayParams.FilterDescendantsInstances = {player.Character}
        rayParams.FilterType = Enum.RaycastFilterType.Exclude

        connection = RunService.RenderStepped:Connect(function(dt)
            if not running or isFlying then return end
            dt = math.min(dt, 0.05)

            local char = player.Character
            if not char then return end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if not hrp or not humanoid then return end

            -- 🔥 Мансинг = бег: гравитация + коллизии работают
            if humanoid.PlatformStand then humanoid.PlatformStand = false end
            if not hrp.CanCollide then hrp.CanCollide = true end
            if humanoid.WalkSpeed ~= walkSpeed then humanoid.WalkSpeed = walkSpeed end

            if not bee or not bee.Parent then running = false return end
            local beeHrp = bee:FindFirstChild("HumanoidRootPart")
            if not beeHrp then return end

            -- 🔥 Raycast params пересоздаём (char мог смениться)
            rayParams.FilterDescendantsInstances = {char}

            local distToBee = (hrp.Position - beeHrp.Position).Magnitude
            if distToBee > 100 then
                isFlying = true
                task.spawn(function()
                    local ok = flyTo(bee, Vector3.new(0, 3, 0))
                    isFlying = false
                    if ok then
                        local h = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                        local b = bee and bee:FindFirstChild("HumanoidRootPart")
                        if h and b then
                            local v = h.Position - b.Position
                            angle = (v.Magnitude > 1) and math.atan2(v.Z, v.X) or 0
                        end
                    else
                        running = false
                    end
                end)
                return
            end

            local now = tick()

            -- 🔥 Прыжок от шипов (Jump = true — не сбрасывает MoveTo)
            if now - lastJump > jumpInterval then
                if humanoid:GetState() == Enum.HumanoidStateType.Running
                    or humanoid:GetState() == Enum.HumanoidStateType.Landed then
                    humanoid.Jump = true
                end
                lastJump = now
            end

            -- 🔥 Плавный зигзаг (синус)
            zigzagPhase = zigzagPhase + dt * zigzagSpeed
            local zigzag = math.sin(zigzagPhase) * zigzagAmp

            -- Угловое движение
            angle = angle + (walkSpeed / radius) * dt
            local finalAngle = angle + zigzag

            local targetOffset = Vector3.new(
                math.cos(finalAngle) * radius,
                0,
                math.sin(finalAngle) * radius
            )
            local targetPos = beeHrp.Position + targetOffset

            -- 🔥 Raycast вниз для Y земли (не провалиться)
            local groundRay = workspace:Raycast(
                Vector3.new(targetPos.X, beeHrp.Position.Y + 30, targetPos.Z),
                Vector3.new(0, -100, 0),
                rayParams
            )
            if groundRay then
                targetPos = Vector3.new(targetPos.X, groundRay.Position.Y + 3, targetPos.Z)
            else
                targetPos = Vector3.new(targetPos.X, beeHrp.Position.Y, targetPos.Z)
            end

            -- 🔥 MoveTo не каждый кадр (по времени или при смещении)
            if now - lastMoveTime > moveInterval
                or (targetPos - lastMoveTarget).Magnitude > 4 then
                humanoid:MoveTo(targetPos)
                lastMoveTime = now
                lastMoveTarget = targetPos
            end

            -- Поворот в сторону движения (только если не прыгаем)
            if humanoid:GetState() ~= Enum.HumanoidStateType.Jumping
                        and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
                local lookAt = Vector3.new(targetPos.X, hrp.Position.Y, targetPos.Z)
                if (lookAt - hrp.Position).Magnitude > 0.5 then
                    hrp.CFrame = CFrame.lookAt(hrp.Position, lookAt)
                end
            end
        end)
    end)

    return function()
        running = false
        if connection then connection:Disconnect() end
        resetCharacterState()
    end
end

-- ============================================================
-- ОСНОВНАЯ ЛОГИКА
-- ============================================================
local function huntViciousBee()
    print("[Hunt] === НОВЫЙ СЕРВЕР ===")
    task.wait(2)

    -- Ждём прогрузки Monsters
    local t = 0
    while not workspace:FindFirstChild("Monsters") and t < 10 do
        task.wait(0.5)
        t = t + 0.5
    end

    local bee = findViciousBee()
    if not bee then
        print("[Hunt] ❌ Пчела не найдена. Хоп...")
        hopToRandomServer() return
    end
    print("[Hunt] ✅ Пчела найдена:", bee.Name)

    if isViciousBeeNearMondo(bee) then
        print("[Hunt] ⚠️ Пчела на горе. Хоп...")
        hopToRandomServer() return
    end

    local hive = findFreeHive()
    if not hive then
        print("[Hunt] ❌ Улей не найден. Хоп...")
        hopToRandomServer() return
    end

    local char = player.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then
        task.wait(2)
        char = player.Character
    end
    if not char then hopToRandomServer() return end

    -- === FLY к улью ===
    local platform = hive:FindFirstChild("Platform")
    local target = (platform and platform.Value) and platform.Value or hive
    print("[Hunt] Fly к улью:", hive.Name)

    if not flyTo(target, Vector3.new(0, 3, 0)) then
        print("[Hunt] ❌ Не долетели до улья. Хоп...")
        hopToRandomServer() return
    end
    task.wait(0.5)

    -- === Захват улья (E × 3) ===
    local tries = 0
    local claimed = false
    while tries < 3 do
        pressE(hive)
        task.wait(1.2)
        local o = hive:FindFirstChild("Owner")
        if o and o.Value == player then
            claimed = true
            break
        end
        tries = tries + 1
    end

    if not claimed then
        print("[Hunt] ❌ Улей не засчитан. Хоп...")
        hopToRandomServer() return
    end
    print("[Hunt] ✅ Улей занят:", hive.Name)

    if not bee.Parent then
        print("[Hunt] ⚠️ Пчела умерла, пока занимали улей. Хоп...")
        hopToRandomServer() return
    end

    -- === FLY к пчеле ===
    print("[Hunt] Fly к пчеле...")
    if not flyTo(bee, Vector3.new(0, 5, 10)) then
        print("[Hunt] ❌ Не долетели до пчелы. Хоп...")
        hopToRandomServer() return
    end
    task.wait(0.3)

    -- === МАНСИНГ (бег) ===
    print("[Hunt] Мансинг (бег по полю)...")
    local stopMansing = startMansing(bee)

    local maxWait = 120
    pcall(function()
        local waited = 0
        while waited < maxWait do
            task.wait(0.3)
            waited = waited + 0.3
            local humanoid = bee:FindFirstChild("Humanoid")
            if not bee.Parent or not humanoid or humanoid.Health <= 0 then
                print("[Hunt] ✅ Пчела убита! Хоп...")
                break
            end
        end
    end)

    if stopMansing then stopMansing() end
    hopToRandomServer()
end

-- ============================================================
-- БЕСКОНЕЧНЫЙ ЦИКЛ
-- ============================================================
task.wait(5)
while true do
    pcall(huntViciousBee)
    task.wait(1.5)
end

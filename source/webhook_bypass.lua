-- ====== SERVICES ======
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local VirtualInputManager = game:GetService("VirtualInputManager")

-- ====== ХОП (тихий, без логов) ======
local function hopToRandomServer()
    task.wait(6)
    local currentPlayer = game:GetService("Players").LocalPlayer
    if not currentPlayer then return end

    local success, servers = pcall(function()
        return HttpService:JSONDecode(
            game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100")
        )
    end)

    if not success or not servers or not servers.data or #servers.data == 0 then
        TeleportService:Teleport(game.PlaceId, currentPlayer)
        return
    end

    local currentJobId = game.JobId
    local candidates = {}

    for _, server in ipairs(servers.data) do
        if server.id ~= currentJobId and server.playing < server.maxPlayers then
            table.insert(candidates, server)
        end
    end

    if #candidates == 0 then
        TeleportService:Teleport(game.PlaceId, currentPlayer)
        return
    end

    local chosen = candidates[math.random(1, #candidates)]
    TeleportService:TeleportToPlaceInstance(game.PlaceId, chosen.id, currentPlayer)
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

-- ====== ПОИСК MONDO CHICK ======
local function findMondoChick()
    local monsters = workspace:FindFirstChild("Monsters")
    if not monsters then return nil end
    for _, obj in ipairs(monsters:GetChildren()) do
        if obj.Name:find("Mondo Chick") then
            local humanoid = obj:FindFirstChild("Humanoid")
            if humanoid and humanoid.Health > 0 then
                return obj
            end
        end
    end
    return nil
end

-- ====== ПРОВЕРКА: VICIOUS BEE РЯДОМ С MONDO ======
local function isViciousBeeNearMondo(bee)
    local mondo = findMondoChick()
    if not mondo then return false end
    local beePos = bee:GetPivot().Position
    local mondoPos = mondo:GetPivot().Position
    return (beePos - mondoPos).Magnitude < 200
end

-- ====== ПОИСК СВОБОДНОГО УЛЬЯ ======
local function findFreeHive()
    local honeycombs = workspace:FindFirstChild("Honeycombs")
    if not honeycombs then return nil end

    local tries = 0
    while tries < 10 do
        local allLoaded = true
        for i = 1, 6 do
            local hive = honeycombs:FindFirstChild("Hive" .. i)
            if hive and not hive:FindFirstChild("Owner") then
                allLoaded = false
                break
            end
        end
        if allLoaded then break end
        task.wait(0.2)
        tries = tries + 1
    end

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
    return nil
end

-- ====== FLY (адаптивный) ======
local function flyTo(target, offset)
    local success, err = pcall(function()
        local currentPlayer = game:GetService("Players").LocalPlayer
        if not currentPlayer then return false end

        local char = currentPlayer.Character
        if not char then return false end

        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return false end

        if not target then return false end

        offset = offset or Vector3.new(0, 3, 0)
        local targetPos
            if target:IsA("Model") then
            if target.PrimaryPart then
                targetPos = target.PrimaryPart.Position
            else
                for _, part in ipairs(target:GetDescendants()) do
                    if part:IsA("BasePart") then
                        targetPos = part.Position
                        break
                    end
                end
            end
        elseif target:IsA("BasePart") then
            targetPos = target.Position
        else
            return false
        end

        if not targetPos then return false end
        targetPos = targetPos + offset

        -- Отключаем коллизии
        local originalParts = {}
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                originalParts[part] = part.CanCollide
                part.CanCollide = false
            end
        end

        local bv = Instance.new("BodyVelocity")
        bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        bv.P = 10000
        bv.Parent = hrp

        local startTime = tick()
        local maxTime = 3

        while tick() - startTime < maxTime do
            if not hrp or not hrp.Parent then break end
            local distance = (hrp.Position - targetPos).Magnitude
            if distance < 3 then break end

            local direction = (targetPos - hrp.Position).Unit
            local speed = 400
            if distance < 15 then speed = 200 end
            if distance < 8 then speed = 100 end

            bv.Velocity = direction * speed
            task.wait(0.02)
        end

        bv:Destroy()
        hrp.CFrame = CFrame.new(targetPos)

        -- Возвращаем коллизии
        for part, collide in pairs(originalParts) do
            if part and part.Parent then
                part.CanCollide = collide
            end
        end

        return true
    end)
    if not success then
        print("[Fly] ❌ ОШИБКА:", err)
    end
    return success
end

-- ====== НАЖАТИЕ E ======
local function pressE()
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
    end)
end

-- ====== РЕЗКИЙ МАНСИНГ (радиус 30) ======
local function startMansing(bee)
    local running = true

    task.spawn(function()
        local angle = 0
        local radius = 30
        local maxDistance = 45

        while running do
            local currentPlayer = game:GetService("Players").LocalPlayer
            if not currentPlayer then task.wait(0.1) continue end

            local char = currentPlayer.Character
            if not char then task.wait(0.1) continue end

            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if not humanoid or humanoid.Health <= 0 then task.wait(0.1) continue end

            local hrp = char:FindFirstChild("HumanoidRootPart")
            if not hrp then task.wait(0.1) continue end

            if not bee.Parent then break end
            local beeHumanoid = bee:FindFirstChild("Humanoid")
            if not beeHumanoid or beeHumanoid.Health <= 0 then break end

            local beeHrp = bee:FindFirstChild("HumanoidRootPart")
            if not beeHrp then task.wait(0.1) continue end

            local distance = (hrp.Position - beeHrp.Position).Magnitude
            if distance > maxDistance then
                hrp.CFrame = CFrame.new(beeHrp.Position + Vector3.new(radius, 5, 0))
                task.wait(0.15)
            end

            angle = angle + math.rad(150)
            local offsetX = math.cos(angle) * radius
            local offsetZ = math.sin(angle) * radius
            local targetPos = beeHrp.Position + Vector3.new(offsetX, 0, offsetZ)

            humanoid:MoveTo(targetPos)
            task.wait(0.12)
        end
    end)

    return function()
        running = false
    end
end

-- ====== ОСНОВНАЯ ЛОГИКА ======
local function huntViciousBee()
    print("[Hunt] === НОВЫЙ СЕРВЕР ===")
    task.wait(2)
    print("[Hunt] Поиск пчелы...")
    local bee = findViciousBee()
    if not bee then
        print("[Hunt] ❌ Пчела не найдена. Хоп...")
        hopToRandomServer()
        return
    end
    print("[Hunt] ✅ Пчела найдена:", bee.Name)

    if isViciousBeeNearMondo(bee) then
        print("[Hunt] ⚠️ Пчела на горе. Хоп...")
        hopToRandomServer()
        return
    end

    print("[Hunt] Поиск улья...")
    local hive = findFreeHive()
    if not hive then
        print("[Hunt] ❌ Улей не найден. Хоп...")
        hopToRandomServer()
        return
    end
    print("[Hunt] ✅ Выбран улей:", hive.Name)

    -- FLY к улью
    local platform = hive:FindFirstChild("Platform")
    if platform and platform.Value then
        print("[Hunt] Fly к платформе...")
        flyTo(platform.Value, Vector3.new(0, 3, 0))
    else
        print("[Hunt] Fly к улью...")
        flyTo(hive, Vector3.new(0, 3, 0))
    end

    -- Нажимаем E
    task.wait(1)
    print("[Hunt] Нажимаем E...")
    pressE()
    task.wait(1.5)

    -- Проверка засчитался ли улей
    local currentPlayer = game:GetService("Players").LocalPlayer
    local owner = hive:FindFirstChild("Owner")

    if owner and owner.Value == currentPlayer then
        print("[Hunt] ✅ Улей занят:", hive.Name)
    else
        print("[Hunt] ❌ Улей не засчитан. Повторяем E...")
        task.wait(0.5)
        pressE()
        task.wait(1.5)

        owner = hive:FindFirstChild("Owner")
        if owner and owner.Value == currentPlayer then
            print("[Hunt] ✅ Улей занят со 2-й попытки")
        else
            print("[Hunt] ❌ Улей не засчитан. Хоп...")
            hopToRandomServer()
            return
        end
    end

    -- FLY к пчеле
    print("[Hunt] Fly к пчеле...")
    flyTo(bee, Vector3.new(0, 5, 15))
    task.wait(0.3)

    -- Мансинг
    print("[Hunt] Мансинг вокруг пчелы (радиус 30)...")
    local stopMansing = startMansing(bee)

    -- Ждём убийства пчелы
    print("[Hunt] Ждём убийства пчелы...")
    local maxWait = 60
    local waited = 0

    while waited < maxWait do
        task.wait(0.3)
        waited = waited + 0.3

        local humanoid = bee:FindFirstChild("Humanoid")
        local beeDead = false

        if not bee.Parent then
            beeDead = true
        elseif not humanoid then
            beeDead = true
        elseif humanoid.Health <= 0 then
            beeDead = true
        end

        if beeDead then
            print("[Hunt] ✅ Пчела убита! Хоп...")
            break
        end
    end

    if stopMansing then stopMansing() end
    print("[Hunt] Хоп на другой сервер...")
    hopToRandomServer()
end

-- ====== БЕСКОНЕЧНЫЙ ЦИКЛ ======
task.wait(5)
while true do
    huntViciousBee()
    task.wait(1.5)
end

-- ====== SERVICES ======
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local player = Players.LocalPlayer

-- ====== ХОП ======
local function hopToRandomServer()
    task.wait(2)
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
        if server.id ~= currentJobId and server.playing < server.maxPlayers then
            table.insert(candidates, server)
        end
    end

    if #candidates == 0 then
        TeleportService:Teleport(game.PlaceId, player)
        return
    end

    local chosen = candidates[math.random(1, #candidates)]
    TeleportService:TeleportToPlaceInstance(game.PlaceId, chosen.id, player)
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

-- ====== ПОИСК СВОБОДНОГО УЛЬЯ ======
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

    print("[Hunt] ⚠️ Свободных ульев нет")
    return nil
end

-- ====== ТЕЛЕПОРТ ======
local function teleportTo(target, offset)
    local char = player.Character
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    if not target then return false end

    offset = offset or Vector3.new(0, 5, 0)
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
    end

    if not targetPos then return false end
    hrp.CFrame = CFrame.new(targetPos + offset)
    return true
end

-- ====== НАЖАТИЕ E ======
local function pressE()
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
        task.wait(0.1)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
    end)
end

-- ====== МАНСИНГ (бегает по кругу вокруг пчелы) ======
local function startMansing(bee)
    local running = true

    task.spawn(function()
        local angle = 0
        local radius = 30

        while running do
            if not player.Character then break end
            local char = player.Character
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if not humanoid or humanoid.Health <= 0 then break end
            if not bee.Parent then break end

            local beeHrp = bee:FindFirstChild("HumanoidRootPart")
            if not beeHrp then break end
                angle = angle + math.rad(90)
            local offsetX = math.cos(angle) * radius
            local offsetZ = math.sin(angle) * radius
            local targetPos = beeHrp.Position + Vector3.new(offsetX, 0, offsetZ)

            humanoid:MoveTo(targetPos)
            task.wait(0.3)
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

    -- 1. Ищем пчелу
    print("[Hunt] Поиск пчелы...")
    local bee = findViciousBee()
    if not bee then
        print("[Hunt] ❌ Пчела не найдена. Хоп...")
        hopToRandomServer()
        return
    end
    print("[Hunt] ✅ Пчела найдена:", bee.Name)

    -- 2. Ищем улей
    print("[Hunt] Поиск улья...")
    local hive = findFreeHive()
    if not hive then
        print("[Hunt] ❌ Улей не найден. Хоп...")
        hopToRandomServer()
        return
    end
    print("[Hunt] ✅ Улей найден:", hive.Name)

    -- 3. Телепорт к улью
    local platform = hive:FindFirstChild("Platform")
    if platform and platform.Value then
        print("[Hunt] Телепорт к платформе...")
        teleportTo(platform.Value, Vector3.new(0, 5, 0))
    else
        print("[Hunt] Телепорт к улью...")
        teleportTo(hive, Vector3.new(0, 5, 0))
    end

    -- 4. Нажимаем E
    task.wait(2)
    print("[Hunt] Нажимаем E...")
    pressE()
    task.wait(2)
    print("[Hunt] ✅ Улей занят:", hive.Name)

    -- 5. Телепорт к пчеле
    print("[Hunt] Телепорт к пчеле...")
    teleportTo(bee, Vector3.new(0, 5, 15))
    task.wait(0.5)

    -- 6. Запускаем мансинг
    print("[Hunt] Мансинг вокруг пчелы...")
    local stopMansing = startMansing(bee)

    -- 7. Ждём, пока пчела умрёт (тройная проверка)
    print("[Hunt] Ждём убийства пчелы...")
    local maxWait = 60
    local waited = 0

    while waited < maxWait do
        task.wait(0.5)
        waited = waited + 0.5

        -- Тройная проверка смерти пчелы
        local humanoid = bee:FindFirstChild("Humanoid")
        local beeDead = false

        if not bee.Parent then
            beeDead = true -- пчела удалена из workspace
        elseif not humanoid then
            beeDead = true -- Humanoid исчез
        elseif humanoid.Health <= 0 then
            beeDead = true -- Health = 0
        end

        if beeDead then
            print("[Hunt] ✅ Пчела убита! Хоп...")
            break
        end

        -- Проверяем, что мы сами живы
        if not player.Character then break end
        local myHumanoid = player.Character:FindFirstChildOfClass("Humanoid")
        if not myHumanoid or myHumanoid.Health <= 0 then
            print("[Hunt] ⚠️ Мы умерли. Хоп...")
            break
        end
    end

    -- 8. Останавливаем мансинг
    if stopMansing then stopMansing() end

    -- 9. Хоп
    print("[Hunt] Хоп на другой сервер...")
    hopToRandomServer()
end

-- ====== БЕСКОНЕЧНЫЙ ЦИКЛ ======
task.wait(5)
while true do
    huntViciousBee()
    task.wait(3)
end

-- ====== SERVICES ======
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local player = Players.LocalPlayer

-- ====== ХОП ======
local function hopToRandomServer()
    task.wait(3)
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
    local distance = (beePos - mondoPos).Magnitude

    return distance < 200
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
            else
                print("[Hunt] ⚠️ Занятый улей:", hive.Name)
            end
        end
    end

    print("[Hunt] ❌ Свободных ульев нет")
    return nil
end

-- ====== ТЕЛЕПОРТ ======
local function teleportTo(target, offset)
    print("[Teleport] Вызван teleportTo")
    print("[Teleport] target:", target)
    
    local char = player.Character
    if not char then 
        print("[Teleport] ❌ Character = nil")
        return false 
    end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then 
        print("[Teleport] ❌ HumanoidRootPart = nil")
        return false 
    end
    if not target then 
        print("[Teleport] ❌ target = nil")
        return false 
    end
    offset = offset or Vector3.new(0, 3, 0)
    local targetPos

    if target:IsA("Model") then
        print("[Teleport] target это Model")
        if target.PrimaryPart then
            targetPos = target.PrimaryPart.Position
            print("[Teleport] PrimaryPart:", target.PrimaryPart.Name, "| Pos:", targetPos)
        else
            for _, part in ipairs(target:GetDescendants()) do
                if part:IsA("BasePart") then
                    targetPos = part.Position
                    print("[Teleport] Первая BasePart:", part.Name, "| Pos:", targetPos)
                    break
                end
            end
        end
    elseif target:IsA("BasePart") then
        print("[Teleport] target это BasePart")
        targetPos = target.Position
    else
        print("[Teleport] ❌ target не Model и не BasePart. Class:", target.ClassName)
        return false
    end

    if not targetPos then 
        print("[Teleport] ❌ targetPos = nil")
        return false 
    end
    
    print("[Teleport] Финальная позиция:", targetPos + offset)
    hrp.CFrame = CFrame.new(targetPos + offset)
    print("[Teleport] ✅ Телепорт выполнен")
    return true
end

-- ====== НАЖАТИЕ E ======
local function pressE()
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
    end)
end

-- ====== МАНСИНГ ======
local function startMansing(bee)
    local running = true

    task.spawn(function()
        local angle = 0
        local radius = 25

        while running do
            if not player.Character then break end
            local char = player.Character
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if not humanoid or humanoid.Health <= 0 then break end
            if not bee.Parent then break end

            local beeHrp = bee:FindFirstChild("HumanoidRootPart")
            if not beeHrp then break end

            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local distance = (hrp.Position - beeHrp.Position).Magnitude
                if distance > 50 then
                    hrp.CFrame = CFrame.new(beeHrp.Position + Vector3.new(radius, 5, 0))
                    task.wait(0.2)
                end
            end

            angle = angle + math.rad(90)
            local offsetX = math.cos(angle) * radius
            local offsetZ = math.sin(angle) * radius
            local targetPos = beeHrp.Position + Vector3.new(offsetX, 0, offsetZ)

            humanoid:MoveTo(targetPos)
            task.wait(0.2)
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

    -- === ТЕЛЕПОРТ К УЛЬЮ (с логами) ===
    print("[Hunt] === ПОДГОТОВКА ТЕЛЕПОРТА ===")
    local platform = hive:FindFirstChild("Platform")
    print("[Hunt] Platform:", platform)
    if platform then
        print("[Hunt] Platform.Value:", platform.Value)
        if platform.Value then
            print("[Hunt] Platform.Value.ClassName:", platform.Value.ClassName)
        end
    end
    if platform and platform.Value then
        print("[Hunt] Телепорт к платформе...")
        local result = teleportTo(platform.Value, Vector3.new(0, 3, 0))
        print("[Hunt] Результат телепорта:", result)
    else
        print("[Hunt] Platform.Value = nil. Телепорт к улью...")
        local result = teleportTo(hive, Vector3.new(0, 3, 0))
        print("[Hunt] Результат телепорта:", result)
    end

    -- Нажимаем E
    task.wait(0.8)
    print("[Hunt] Нажимаем E...")
    pressE()
    task.wait(0.8)
    print("[Hunt] ✅ Улей занят")

    -- Телепорт к пчеле
    print("[Hunt] Телепорт к пчеле...")
    teleportTo(bee, Vector3.new(0, 5, 15))
    task.wait(0.3)

    -- Мансинг
    print("[Hunt] Мансинг вокруг пчелы...")
    local stopMansing = startMansing(bee)

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

        if not player.Character then break end
        local myHumanoid = player.Character:FindFirstChildOfClass("Humanoid")
        if not myHumanoid or myHumanoid.Health <= 0 then
            print("[Hunt] ⚠️ Мы умерли. Хоп...")
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
    

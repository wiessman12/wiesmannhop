-- ====== CONFIG ======
getgenv().ServerHopConfig = {
    TeleportTimeout = 15,
    RatelimitCooldown = 12,
    MaxBlacklistSize = 300,
    CacheExpiration = 200,
    MinPlayers = 0,
    MaxPing = 100,
    WebhookURL = ""
}

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

-- ====== ПОИСК УЛЬЯ (с ожиданием прогрузки) ======
local function findFreeHive()
    local honeycombs = workspace:FindFirstChild("Honeycombs")
    if not honeycombs then return nil end

    -- Ждём прогрузки ульев И Owner (до 5 секунд)
    local tries = 0
    while tries < 20 do
        local allReady = true
        for i = 1, 6 do
            local hive = honeycombs:FindFirstChild("Hive" .. i)
            if not hive then
                allReady = false
                break
            end
            if not hive:FindFirstChild("Owner") then
                allReady = false
                break
            end
        end
        if allReady then break end
        task.wait(0.25)
        tries = tries + 1
    end

    -- Ищем свободный улей
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

-- ====== ТЕЛЕПОРТ (исправленный) ======
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
-- ====== FLY (для пчелы) ======
local function flyTo(target, offset)
    local char = player.Character
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    if not target then return false end

    local targetPos
    if target:IsA("Model") then
        if target.PrimaryPart then
            targetPos = target.PrimaryPart.Position
        else
            local root = target:FindFirstChild("HumanoidRootPart")
            if root then targetPos = root.Position end
        end
    elseif target:IsA("BasePart") then
        targetPos = target.Position
    end

    if not targetPos then return false end

    offset = offset or Vector3.new(0, 5, 0)
    targetPos = targetPos + offset
    local startPos = hrp.Position

    local flyHeight = 45

    local waypoints = {
        Vector3.new(startPos.X, startPos.Y + flyHeight, startPos.Z),
        Vector3.new(targetPos.X, targetPos.Y + flyHeight, targetPos.Z),
        targetPos
    }

    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.P = 10000
    bv.Parent = hrp

    local startTime = tick()
    local maxTime = 6

    for _, waypoint in ipairs(waypoints) do
        local wpStartTime = tick()
        while tick() - wpStartTime < 2.5 do
            if not hrp or not hrp.Parent then break end
            if not player.Character then break end
            if tick() - startTime > maxTime then break end

            local distance = (hrp.Position - waypoint).Magnitude
            if distance < 5 then break end

            local direction = (waypoint - hrp.Position).Unit
            bv.Velocity = direction * 300

            task.wait(0.05)
        end
    end

    bv:Destroy()
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

-- ====== МАНСИНГ ======
local function startWalkingMansing(bee)
    local char = player.Character
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    local running = true

    task.spawn(function()
        local angle = 0
        local radius = 20

        while running do
            if not player.Character then break end
            local currentHumanoid = player.Character:FindFirstChildOfClass("Humanoid")
            if not currentHumanoid or currentHumanoid.Health <= 0 then break end
            if not bee.Parent then break end

            local beeHrp = bee:FindFirstChild("HumanoidRootPart")
            if not beeHrp then break end

            angle = angle + math.rad(120)
            local offsetX = math.cos(angle) * radius
            local offsetZ = math.sin(angle) * radius
            local targetPos = beeHrp.Position + Vector3.new(offsetX, 0, offsetZ)

            currentHumanoid:MoveTo(targetPos)
            task.wait(0.25)
        end
    end)

    return function()
        running = false
        local char = player.Character
        if char then
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid:MoveTo(char.HumanoidRootPart.Position)
            end
        end
    end
end

-- ====== ОСНОВНАЯ ЛОГИКА ======
local function huntViciousBee()
    print("[Hunt] === НОВЫЙ СЕРВЕР ===")
    task.wait(3)

    print("[Hunt] Поиск пчелы...")
    local bee = findViciousBee()
    if not bee then
        print("[Hunt] ❌ Пчела не найдена. Хоп...")
        collectgarbage("collect")
        hopToRandomServer()
        return
    end

    print("[Hunt] ✅ Пчела найдена:", bee.Name)

    -- Ищем свободный улей
    local hive = findFreeHive()
    if not hive then
        print("[Hunt] ❌ Улей не найден. Хоп...")
        collectgarbage("collect")
        hopToRandomServer()
        return
    end
    print("[Hunt] Летим к улью:", hive.Name)
    local platform = hive:FindFirstChild("Platform")
    if platform and platform.Value then
        print("[Hunt] Телепорт к платформе...")
        teleportTo(platform.Value, Vector3.new(0, 5, 0))
    else
        print("[Hunt] Платформа не найдена, телепорт к улью...")
        teleportTo(hive, Vector3.new(0, 5, 0))
    end
    task.wait(2)
    print("[Hunt] Нажимаем E...")
    pressE()
    task.wait(2)
    print("[Hunt] ✅ Улей занят:", hive.Name)

    -- Летим к пчеле
    print("[Hunt] Летим к пчеле...")
    flyTo(bee, Vector3.new(0, 5, 15))
    task.wait(0.5)

    -- Мансинг 35 секунд
    print("[Hunt] Мансинг 35 сек...")
    local stopMansing = startWalkingMansing(bee)
    task.wait(35)
    if stopMansing then stopMansing() end

    print("[Hunt] Завершено. Хоп...")
    collectgarbage("collect")
    hopToRandomServer()
end

-- ====== АВТО-ЗАПУСК ======
task.spawn(function()
    task.wait(5)
    while true do
        pcall(huntViciousBee)
        task.wait(5)
    end
end)

print("[Vicious Bee Hunter] Запущен.")

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
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

-- ====== ХОП НА РАЗНЫЕ СЕРВЕРА ======
local function hopToRandomServer()
    local success, servers = pcall(function()
        return HttpService:JSONDecode(
            game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100")
        )
    end)

    if not success or not servers or not servers.data then
        TeleportService:Teleport(game.PlaceId, player)
        return
    end

    local currentJobId = game.JobId
    local candidates = {}

    for _, server in ipairs(servers.data) do
        if server.id ~= currentJobId
           and server.playing < server.maxPlayers
           and server.playing >= 1 then
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

-- ====== ПОИСК VICIOUS BEE ======
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

-- ====== ТЕЛЕПОРТ К ЦЕЛИ (один раз, чтобы добраться до пчелы) ======
local function getTargetPart(target)
    if target:IsA("Model") then
        return target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
    elseif target:IsA("BasePart") then
        return target
    end
    return nil
end

local function teleportTo(target, offset)
    local char = player.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local targetPart = getTargetPart(target)
    if not targetPart then return end
    offset = offset or Vector3.new(0, 5, 0)
    hrp.CFrame = CFrame.new(targetPart.Position + offset)
end

-- ====== МАНСИНГ ХОДЬБОЙ ======
local function startWalkingMansing(bee)
    local char = player.Character
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    local running = true

    task.spawn(function()
        local angle = 0
        local radius = 15 -- радиус круга

        while running do
            -- Проверка: жив ли персонаж и пчела
            if not player.Character then break end
            local currentHumanoid = player.Character:FindFirstChildOfClass("Humanoid")
            if not currentHumanoid or currentHumanoid.Health <= 0 then break end
            if not bee.Parent then break end

            local beeHrp = bee:FindFirstChild("HumanoidRootPart")
            if not beeHrp then break end

            -- Вычисляем точку на круге вокруг пчелы
            angle = angle + math.rad(90) -- каждый шаг — 90 градусов
            local offsetX = math.cos(angle) * radius
            local offsetZ = math.sin(angle) * radius
            local targetPos = beeHrp.Position + Vector3.new(offsetX, 0, offsetZ)

            -- Заставляем персонажа идти к этой точке
            currentHumanoid:MoveTo(targetPos)

            task.wait(0.4) -- обновляем точку каждые 0.4 секунды
        end
    end)
    -- Функция остановки
    return function()
        running = false
        local char = player.Character
        if char then
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid:MoveTo(char.HumanoidRootPart.Position) -- стоп
            end
        end
    end
end

-- ====== ОСНОВНАЯ ЛОГИКА ======
local function huntViciousBee()
    local bee = findViciousBee()
    if not bee then
        hopToRandomServer()
        return
    end

    -- Телепорт к пчеле (один раз, чтобы рядом был)
    teleportTo(bee, Vector3.new(0, 5, 15))
    task.wait(0.5)

    -- Запуск мансинга ходьбой
    local stopMansing = startWalkingMansing(bee)

    -- Ждём 25 секунд
    task.wait(25)

    -- Останавливаем мансинг
    if stopMansing then stopMansing() end

    -- Хоп на другой сервер
    hopToRandomServer()
end

-- ====== АВТО-ЗАПУСК ======
task.spawn(function()
    task.wait(5)
    while true do
        pcall(huntViciousBee)
        task.wait(3)
    end
end)

print("[Vicious Bee Hunter] Запущен. Мансинг ходьбой. Таймер: 25с.")

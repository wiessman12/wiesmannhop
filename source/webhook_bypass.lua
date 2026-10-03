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
local player = Players.LocalPlayer

-- ====== ФУНКЦИЯ ХОПА НА РАЗНЫЕ СЕРВЕРА ======
local function hopToRandomServer()
    -- Если мы на ВИП-сервере — выходим из него на публичный
    local success, servers = pcall(function()
        return HttpService:JSONDecode(
            game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100")
        )
    end)

    if not success or not servers or not servers.data then
        -- Если не получилось получить список — перезаходим на тот же
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
        -- Если нет подходящих — перезаходим на тот же
        TeleportService:Teleport(game.PlaceId, player)
        return
    end

    -- Выбираем случайный сервер из списка
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

-- ====== ТЕЛЕПОРТ К ПЧЕЛЕ ======
local function teleportTo(target)
    local char = player.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local targetPart
    if target:IsA("Model") then
        targetPart = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
    elseif target:IsA("BasePart") then
        targetPart = target
    end
    if not targetPart then return end
    hrp.CFrame = CFrame.new(targetPart.Position + Vector3.new(0, 5, 0))
end

-- ====== ОСНОВНАЯ ЛОГИКА ======
local function huntViciousBee()
    local bee = findViciousBee()
    if not bee then
        -- Пчелы нет — хопаем на другой сервер
        hopToRandomServer()
        return
    end

    -- Пчела есть — телепортируемся и ждём
    teleportTo(bee)
    task.wait(1)

    -- Ждём 45 секунд (пока пчёлы убьют)
    task.wait(45)

    -- Перезаход на другой сервер
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

print("[Vicious Bee Hunter] Запущен. Будет хопать на разные сервера.")

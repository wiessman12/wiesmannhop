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

-- ====== WEBHOOK BYPASS ======
local function isWebhook(url)
    if type(url) ~= "string" then return false end
    return url:find("discord.com/api/webhooks") or url:find("discordapp.com/api/webhooks")
end

local fakeResponse = { StatusCode = 200, StatusMessage = "OK", Headers = {}, Body = '{"success":true}' }

if request then
    local oldRequest = request
    request = function(options)
        if type(options) == "table" and isWebhook(options.Url or options.url) then
            return fakeResponse
        end
        return oldRequest(options)
    end
end

local function sendLog(text)
    local url = getgenv().ServerHopConfig.WebhookURL
    if not url or url == "" then return end
    pcall(function()
        request({
            Url = url,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode({ content = text, username = "Vicious Bee Hunter" })
        })
    end)
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
    sendLog("[Hunt] Поиск Vicious Bee...")
    local bee = findViciousBee()
    if not bee then
        sendLog("[Hunt] Пчела не найдена. Перезаход...")
        task.wait(2)
        TeleportService:Teleport(game.PlaceId, player)
        return
    end
    sendLog("[Hunt] Пчела найдена! Телепорт...")
    teleportTo(bee)
    task.wait(1)
    sendLog("[Hunt] Атака... Ждём 45 сек.")
    task.wait(45)
    sendLog("[Hunt] Завершено. Перезаход...")
    task.wait(2)
    TeleportService:Teleport(game.PlaceId, player)
end

-- ====== АВТО-ЗАПУСК ======
task.spawn(function()
    task.wait(5)
    while true do
        pcall(huntViciousBee)
        task.wait(3)
    end
end)

print("[Vicious Bee Hunter] Запущен.")

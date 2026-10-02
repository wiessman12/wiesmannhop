
local Config = getgenv().ServerHopConfig or {}

local function isWebhook(url)
    if type(url) ~= "string" then return false end
    return url:find("discord.com/api/webhooks")
        or url:find("discordapp.com/api/webhooks")
        or url:find("ptb.discord.com/api/webhooks")
        or url:find("canary.discord.com/api/webhooks")
end

local fakeResponse = {
    StatusCode = 200,
    StatusMessage = "OK",
    Headers = { ["Content-Type"] = "application/json" },
    Body = '{"success":true}'
}

if request then
    local oldRequest = request
    request = function(options)
        if type(options) == "table" and isWebhook(options.Url or options.url) then
            return fakeResponse
        end
        return oldRequest(options)
    end
end

if http_request then
    local oldHttp = http_request
    http_request = function(options)
        if type(options) == "table" and isWebhook(options.Url or options.url) then
            return fakeResponse
        end
        return oldHttp(options)
    end
end

if syn and syn.request then
    local oldSyn = syn.request
    syn.request = function(options)
        if type(options) == "table" and isWebhook(options.Url or options.url) then
            return fakeResponse
        end
        return oldSyn(options)
    end
end

local function sendLog(text)
    local url = Config.WebhookURL
    if not url or url == "" then return end
    pcall(function()
        local HttpService = game:GetService("HttpService")
        request({
            Url = url,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode({
                content = text,
                username = "Server Hop Logger"
            })
        })
    end)
end

local function hopServer()
    sendLog("[Server Hop] Попытка телепортации...")
    
    local TeleportService = game:GetService("TeleportService")
    local HttpService = game:GetService("HttpService")
    
    local success, servers = pcall(function()
        return HttpService:JSONDecode(
            game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100")
        )
    end)
    
    if not success or not servers or not servers.data then
        sendLog("[Server Hop] Не удалось получить список серверов")
        return
    end
    
    for _, server in ipairs(servers.data) do
        if server.playing < server.maxPlayers then
            if server.playing >= (Config.MinPlayers or 0) then
                sendLog("[Server Hop] Телепорт на сервер " .. server.id)
                TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id)
                return
            end
        end
    end
    
    sendLog("[Server Hop] Подходящих серверов не найдено")
end

print("[Webhook Bypass] Активирован.")
sendLog("[Webhook Bypass] Скрипт загружен")

getgenv().HopServer = hopServer

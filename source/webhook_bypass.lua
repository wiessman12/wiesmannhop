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

-- ====== WEBHOOK BYPASS ======
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
    sendLog("[Server Hop] Trying to teleport...")
    local TeleportService = game:GetService("TeleportService")
    local HttpService = game:GetService("HttpService")

    local success, servers = pcall(function()
        return HttpService:JSONDecode(
            game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100")
        )
    end)

    if not success or not servers or not servers.data then
        sendLog("[Server Hop] Failed to get server list")
        return
    end

    for _, server in ipairs(servers.data) do
        if server.playing < server.maxPlayers then
            if server.playing >= (Config.MinPlayers or 0) then
                sendLog("[Server Hop] Teleporting to " .. server.id)
                TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id)
                return
            end
        end
    end

    sendLog("[Server Hop] No suitable server found")
end

getgenv().HopServer = hopServer
print("[Webhook Bypass] Activated.")

-- ====== SERVICES ======
local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

-- ====== GUI ======
local old = pg:FindFirstChild("ServerHopMenu")
if old then old:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ServerHopMenu"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = pg

local Main = Instance.new("Frame")
Main.Size = UDim2.new(0, 300, 0, 420)
Main.Position = UDim2.new(0.5, -150, 0.5, -210)
Main.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
Main.BorderSizePixel = 0
Main.Active = true
Main.Draggable = true
Main.Parent = ScreenGui

local Stroke = Instance.new("UIStroke")
Stroke.Color = Color3.fromRGB(80, 80, 80)
Stroke.Thickness = 1
Stroke.Parent = Main

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 32)
Title.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
Title.BorderSizePixel = 0
Title.Text = "Server Hop Settings"
Title.TextColor3 = Color3.fromRGB(230, 230, 230)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 14
Title.Parent = Main

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 32, 0, 32)
CloseBtn.Position = UDim2.new(1, -32, 0, 0)
CloseBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
CloseBtn.BorderSizePixel = 0
CloseBtn.Text = "-"
CloseBtn.TextColor3 = Color3.fromRGB(230, 230, 230)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 16
CloseBtn.Parent = Main

local Scroll = Instance.new("ScrollingFrame")
Scroll.Size = UDim2.new(1, 0, 1, -32)
Scroll.Position = UDim2.new(0, 0, 0, 32)
Scroll.BackgroundTransparency = 1
Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 4
Scroll.ScrollBarImageColor3 = Color3.fromRGB(120, 120, 120)
Scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
Scroll.Parent = Main

local Layout = Instance.new("UIListLayout")
Layout.Padding = UDim.new(0, 6)
Layout.SortOrder = Enum.SortOrder.LayoutOrder
Layout.Parent = Scroll

local Pad = Instance.new("UIPadding")
Pad.PaddingTop = UDim.new(0, 8)
Pad.PaddingBottom = UDim.new(0, 8)
Pad.PaddingLeft = UDim.new(0, 8)
Pad.PaddingRight = UDim.new(0, 8)
Pad.Parent = Scroll

Layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    Scroll.CanvasSize = UDim2.new(0, 0, 0, Layout.AbsoluteContentSize.Y + 16)
end)

local function makeRow(name)
    local Row = Instance.new("Frame")
    Row.Size = UDim2.new(1, 0, 0, 34)
    Row.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
    Row.BorderSizePixel = 0
    Row.Parent = Scroll

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(0, 150, 1, 0)
    Label.Position = UDim2.new(0, 8, 0, 0)
    Label.BackgroundTransparency = 1
    Label.Text = name
    Label.TextColor3 = Color3.fromRGB(220, 220, 220)
    Label.Font = Enum.Font.Gotham
    Label.TextSize = 12
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Parent = Row

    return Row, Label
end

local function makeNumberInput(row, key, minVal, maxVal, isInt)
    local Box = Instance.new("TextBox")
    Box.Size = UDim2.new(0, 110, 0, 24)
    Box.Position = UDim2.new(1, -118, 0.5, -12)
    Box.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    Box.BorderSizePixel = 0
    Box.Text = tostring(getgenv().ServerHopConfig[key])
    Box.TextColor3 = Color3.fromRGB(230, 230, 230)
    Box.Font = Enum.Font.Gotham
    Box.TextSize = 12
    Box.ClearTextOnFocus = false
    Box.Parent = row

    local S = Instance.new("UIStroke")
    S.Color = Color3.fromRGB(80, 80, 80)
    S.Thickness = 1
    S.Parent = Box

    Box.FocusLost:Connect(function()
        local n = tonumber(Box.Text)
        if not n then
            Box.Text = tostring(getgenv().ServerHopConfig[key])
            return
        end
        n = math.clamp(n, minVal, maxVal)
        if isInt then n = math.floor(n) end
        getgenv().ServerHopConfig[key] = n
        Box.Text = tostring(n)
    end)
end

local r1 = makeRow("TeleportTimeout (s)");       makeNumberInput(r1, "TeleportTimeout", 1, 120, true)
local r2 = makeRow("RatelimitCooldown (s)");     makeNumberInput(r2, "RatelimitCooldown", 1, 120, true)
local r3 = makeRow("MaxBlacklistSize");          makeNumberInput(r3, "MaxBlacklistSize", 1, 5000, true)
local r4 = makeRow("CacheExpiration (s)");       makeNumberInput(r4, "CacheExpiration", 1, 3600, true)
local r5 = makeRow("MinPlayers");                makeNumberInput(r5, "MinPlayers", 0, 100, true)
local r6 = makeRow("MaxPing (ms)");              makeNumberInput(r6, "MaxPing", 0, 1000, true)

local whRow = Instance.new("Frame")
whRow.Size = UDim2.new(1, 0, 0, 60)
whRow.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
whRow.BorderSizePixel = 0
whRow.Parent = Scroll

local whLabel = Instance.new("TextLabel")
whLabel.Size = UDim2.new(1, -16, 0, 20)
whLabel.Position = UDim2.new(0, 8, 0, 4)
whLabel.BackgroundTransparency = 1
whLabel.Text = "WebhookURL"
whLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
whLabel.Font = Enum.Font.Gotham
whLabel.TextSize = 12
whLabel.TextXAlignment = Enum.TextXAlignment.Left
whLabel.Parent = whRow

local whBox = Instance.new("TextBox")
whBox.Size = UDim2.new(1, -16, 0, 26)
whBox.Position = UDim2.new(0, 8, 0, 26)
whBox.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
whBox.BorderSizePixel = 0
whBox.Text = getgenv().ServerHopConfig.WebhookURL
whBox.PlaceholderText = "https://discord.com/api/webhooks/..."
whBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 120)
whBox.TextColor3 = Color3.fromRGB(230, 230, 230)
whBox.Font = Enum.Font.Gotham
whBox.TextSize = 11
whBox.ClearTextOnFocus = false
whBox.TextXAlignment = Enum.TextXAlignment.Left
whBox.Parent = whRow

local whS = Instance.new("UIStroke")
whS.Color = Color3.fromRGB(80, 80, 80)
whS.Thickness = 1
whS.Parent = whBox

whBox.FocusLost:Connect(function()
    getgenv().ServerHopConfig.WebhookURL = whBox.Text
end)

local HopBtn = Instance.new("TextButton")
HopBtn.Size = UDim2.new(1, 0, 0, 34)
HopBtn.BackgroundColor3 = Color3.fromRGB(60, 120, 60)
HopBtn.BorderSizePixel = 0
HopBtn.Text = "SERVER HOP"
HopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
HopBtn.Font = Enum.Font.GothamBold
HopBtn.TextSize = 13
HopBtn.Parent = Scroll

HopBtn.MouseButton1Click:Connect(function()
    if getgenv().HopServer then
        getgenv().HopServer()
    end
end)

local minimized = false
UIS.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.Insert then
        minimized = not minimized
        Main.Visible = not minimized
    end
end)

CloseBtn.MouseButton1Click:Connect(function()
    minimized = true
    Main.Visible = false
end)

local Restore = Instance.new("TextButton")
Restore.Size = UDim2.new(0, 40, 0, 40)
Restore.Position = UDim2.new(0, 20, 0.5, -20)
Restore.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
Restore.BorderSizePixel = 0
Restore.Text = "SH"
Restore.TextColor3 = Color3.fromRGB(230, 230, 230)
Restore.Font = Enum.Font.GothamBold
Restore.TextSize = 13
Restore.Visible = false
Restore.Active = true
Restore.Draggable = true
Restore.Parent = ScreenGui

local RS = Instance.new("UIStroke")
RS.Color = Color3.fromRGB(80, 80, 80)
RS.Thickness = 1
RS.Parent = Restore

Restore.MouseButton1Click:Connect(function()
    minimized = false
    Main.Visible = true
end)

Main:GetPropertyChangedSignal("Visible"):Connect(function()
    Restore.Visible = not Main.Visible
end)

print("[ServerHop Menu] Loaded. Insert = toggle.")
-- ====== AUTO HOP BUTTON ======
local AutoBtn = Instance.new("TextButton")
AutoBtn.Size = UDim2.new(1, 0, 0, 34)
AutoBtn.BackgroundColor3 = Color3.fromRGB(120, 80, 60)
AutoBtn.BorderSizePixel = 0
AutoBtn.Text = "AUTO HOP: OFF"
AutoBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
AutoBtn.Font = Enum.Font.GothamBold
AutoBtn.TextSize = 13
AutoBtn.Parent = Scroll

getgenv().AutoHop = false

AutoBtn.MouseButton1Click:Connect(function()
    getgenv().AutoHop = not getgenv().AutoHop
    if getgenv().AutoHop then
        AutoBtn.Text = "AUTO HOP: ON"
        AutoBtn.BackgroundColor3 = Color3.fromRGB(60, 120, 60)
    else
        AutoBtn.Text = "AUTO HOP: OFF"
        AutoBtn.BackgroundColor3 = Color3.fromRGB(120, 80, 60)
    end
end)

task.spawn(function()
    while true do
        task.wait(1)
        if getgenv().AutoHop then
            task.wait(60)
            if getgenv().AutoHop then
                pcall(function()
                    if getgenv().HopServer then
                        getgenv().HopServer()
                    end
                end)
            end
        end
    end
end)

print("[Auto Hop] Initialized.")


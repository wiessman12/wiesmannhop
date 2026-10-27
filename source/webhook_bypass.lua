-- ============================================================
-- VICIOUS BEE SERVER HOPPER (LITE: без перезапуска клиента)
-- ============================================================

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local CoreGui = game:GetService("CoreGui")

-- ====== НАСТРОЙКИ ======
_G.unlocktween = true
_G.ViciousHunterRunning = true

local TWEEN_SPEED = 150              -- Скорость полета (150 стадс/сек)

-- ====== ПОЛЁТ НАД ПЧЕЛОЙ (вместо мансинга) ======
local HOVER_HEIGHT = 10              -- На какой высоте над Vicious висит персонаж
local HOVER_ORBIT_RADIUS = 0         -- 0 = висим строго над пчелой; >0 = кружим над ней по кругу такого радиуса
local HOVER_ORBIT_SPEED = 2.5        -- Скорость кружения (рад/сек), если радиус > 0

local DATA_FILE = "hop_data.json"
local EXPIRE_TIME = 20 * 60          -- Сервер хранится 20 минут в черном списке
local QUEUE_MAX_AGE = 8 * 60         -- Список серверов обновляется раз в 8 минут

local TARGET_FPS = 60                -- Лимит FPS (60 защищает от перегрева и утечек VRAM/GPU)
local DISABLE_3D_RENDERING = false   -- 3D-рендер остаётся ВКЛЮЧЁННЫМ. true = выключить (экономит память, но экран чёрный)
local LIGHT_VISUALS = false          -- Гашение частиц обходит весь workspace (тяжело для BSS). Включай только если нужно
local MUTE_GAME = true               -- Выключить звук (меньше памяти и CPU)

-- ====== ИНТЕРФЕЙС ======
local SHOW_GUI = true                -- Окно со статистикой (чуть выше центра экрана, можно перетаскивать за заголовок)
local STATS_FILE = "vicious_stats.json"

local HOP_PENDING_TIMEOUT = 40          -- Сколько секунд ждать завершения телепорта, прежде чем пробовать снова

getgenv().IsHopping = false

local lp = Players.LocalPlayer
local StatsService = game:GetService("Stats")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Защита от повторного запуска: старые циклы и подключения останавливаются
local RUN_ID = (getgenv().VB_RunId or 0) + 1
getgenv().VB_RunId = RUN_ID
getgenv().VB_InCombat = false

local gameReady = false  -- true только после полной загрузки игры; до этого скрипт ничего тяжёлого не делает

local function alive()
    return _G.ViciousHunterRunning and getgenv().VB_RunId == RUN_ID
end

if getgenv().VB_Conns then
    for _, c in ipairs(getgenv().VB_Conns) do
        pcall(function() c:Disconnect() end)
    end
end
local myConns = {}
getgenv().VB_Conns = myConns

local function getMemoryMb()
    local ok, mb = pcall(function() return StatsService:GetTotalMemoryUsageMb() end)
    return (ok and tonumber(mb)) or 0
end


-- ============================================================
-- ====== СТАТИСТИКА (СОХРАНЯЕТСЯ МЕЖДУ СЕРВЕРАМИ И ПЕРЕЗАПУСКАМИ) ======
-- ============================================================
local stats = { kills = 0, thorns = 0, lastThorns = -1, hops = 0, boot = os.time(), lastSeen = 0, killsAtBoot = 0 }

do
    if readfile and isfile and isfile(STATS_FILE) then
        local ok, data = pcall(function()
            return HttpService:JSONDecode(readfile(STATS_FILE))
        end)
        if ok and type(data) == "table" then
            stats.kills = tonumber(data.kills) or 0
            stats.thorns = tonumber(data.thorns) or 0
            stats.lastThorns = tonumber(data.lastThorns) or -1
            stats.hops = tonumber(data.hops) or 0
            stats.boot = tonumber(data.boot) or os.time()
            stats.lastSeen = tonumber(data.lastSeen) or 0
            stats.killsAtBoot = tonumber(data.killsAtBoot) or stats.kills
        end
    end
    -- Если с последнего запуска прошло больше 3 минут — это новая сессия клиента
    if os.time() - stats.lastSeen > 180 then
        stats.boot = os.time()
        stats.hops = 0
        stats.killsAtBoot = stats.kills
    end
    stats.lastSeen = os.time()
end

local function saveStats()
    stats.lastSeen = os.time()
    if writefile then
        pcall(function()
            writefile(STATS_FILE, HttpService:JSONEncode(stats))
        end)
    end
end
saveStats()

-- ============================================================
-- ====== ИНТЕРФЕЙС ======
-- ============================================================
local ui = {}
local currentStatus = ""

local STATUS_COLORS = {
    info = Color3.fromRGB(235, 235, 235),
    fight = Color3.fromRGB(235, 20, 40),
    hop = Color3.fromRGB(160, 160, 160),
    ok = Color3.fromRGB(255, 255, 255),
    warn = Color3.fromRGB(255, 95, 95),
}

local function fmtTime(sec)
    sec = math.max(0, math.floor(sec))
    return string.format("%02d:%02d:%02d", math.floor(sec / 3600), math.floor((sec % 3600) / 60), sec % 60)
end

local setStatus
setStatus = function(text, kind)
    kind = kind or "info"
    pcall(function()
        if text == currentStatus and ui.lastKind == kind then return end
        currentStatus = text
        if ui.statusLabel and ui.statusLabel.Parent then
            ui.statusLabel.Text = text
            if ui.lastKind ~= kind then
                ui.lastKind = kind
                local col = STATUS_COLORS[kind] or STATUS_COLORS.info
                TweenService:Create(ui.dot, TweenInfo.new(0.25), { BackgroundColor3 = col }):Play()
            end
        end
    end)
end

local function corner(obj, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = obj
    return c
end

local function mkLabel(parent, props)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.BorderSizePixel = 0
    l.Font = Enum.Font.GothamBold
    l.TextColor3 = Color3.new(1, 1, 1)
    l.TextXAlignment = Enum.TextXAlignment.Left
    for k, v in pairs(props) do l[k] = v end
    l.Parent = parent
    return l
end

local function makeCard(parent, x, caption, accentA, accentB)
    local card = Instance.new("Frame")
    card.Position = UDim2.fromOffset(x, 112)
    card.Size = UDim2.fromOffset(124, 72)
    card.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
    card.BackgroundTransparency = 0.3
    card.BorderSizePixel = 0
    card.Parent = parent
    corner(card, 12)

    local bar = Instance.new("Frame")
    bar.Position = UDim2.fromOffset(12, 0)
    bar.Size = UDim2.new(1, -24, 0, 3)
    bar.BorderSizePixel = 0
    bar.BackgroundColor3 = Color3.new(1, 1, 1)
    bar.Parent = card
    corner(bar, 2)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new(accentA, accentB)
    g.Parent = bar

    mkLabel(card, {
        Text = caption, TextSize = 11, TextColor3 = accentB,
        Position = UDim2.fromOffset(12, 10), Size = UDim2.new(1, -24, 0, 14),
    })
    return mkLabel(card, {
        Text = "0", Font = Enum.Font.GothamBlack, TextSize = 28,
        Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -24, 0, 38),
    })
end

local function createGui()
    if getgenv().VB_GuiObj then
        pcall(function() getgenv().VB_GuiObj:Destroy() end)
        getgenv().VB_GuiObj = nil
    end

    local sg = Instance.new("ScreenGui")
    sg.Name = "VBHunterUI"
    sg.ResetOnSpawn = false
    sg.IgnoreGuiInset = true
    sg.DisplayOrder = 999
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    if syn and syn.protect_gui then pcall(syn.protect_gui, sg) end
    local okParent = pcall(function() sg.Parent = (gethui and gethui()) or CoreGui end)
    if not okParent or not sg.Parent then
        sg.Parent = (Players.LocalPlayer or lp):WaitForChild("PlayerGui")
    end
    getgenv().VB_GuiObj = sg

    -- Главное окно (чуть выше центра экрана)
    local main = Instance.new("Frame")
    main.Name = "Main"
    main.AnchorPoint = Vector2.new(0.5, 0.5)
    main.Position = UDim2.fromScale(0.5, 0.40)
    main.Size = UDim2.fromOffset(420, 246)
    main.BackgroundColor3 = Color3.new(1, 1, 1)
    main.BorderSizePixel = 0
    main.Parent = sg
    corner(main, 16)

    local bg = Instance.new("UIGradient")
    bg.Rotation = 135
    bg.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 6, 12)),
        ColorSequenceKeypoint.new(0.55, Color3.fromRGB(18, 18, 18)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0)),
    })
    bg.Parent = main

    -- Переливающаяся рамка
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 2
    stroke.Color = Color3.new(1, 1, 1)
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = main
    local strokeGrad = Instance.new("UIGradient")
    strokeGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(235, 20, 40)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(235, 20, 40)),
    })
    strokeGrad.Parent = stroke

    -- Заголовок (за него окно можно перетаскивать)
    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 40)
    header.BackgroundTransparency = 1
    header.Active = true
    header.Parent = main

    local title = mkLabel(header, {
        Text = "🐝  VICIOUS HUNTER", Font = Enum.Font.GothamBlack, TextSize = 17,
        Position = UDim2.fromOffset(16, 8), Size = UDim2.fromOffset(210, 24),
    })
    local tg = Instance.new("UIGradient")
    tg.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(235, 30, 50)),
    })
    tg.Parent = title

    -- Что сейчас делает скрипт
    local statusBox = Instance.new("Frame")
    statusBox.Position = UDim2.fromOffset(16, 44)
    statusBox.Size = UDim2.fromOffset(388, 60)
    statusBox.BackgroundColor3 = Color3.new(0, 0, 0)
    statusBox.BackgroundTransparency = 0.45
    statusBox.BorderSizePixel = 0
    statusBox.Parent = main
    corner(statusBox, 10)

    local dot = Instance.new("Frame")
    dot.Position = UDim2.fromOffset(14, 25)
    dot.Size = UDim2.fromOffset(10, 10)
    dot.BackgroundColor3 = STATUS_COLORS.info
    dot.BorderSizePixel = 0
    dot.Parent = statusBox
    corner(dot, 5)
    ui.dot = dot

    mkLabel(statusBox, {
        Text = "ДЕЙСТВИЕ", TextSize = 10, TextColor3 = Color3.fromRGB(235, 20, 40),
        Position = UDim2.fromOffset(34, 7), Size = UDim2.new(1, -46, 0, 12),
    })
    ui.statusLabel = mkLabel(statusBox, {
        Text = "Запуск…", Font = Enum.Font.GothamBold, TextSize = 16, TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top,
        Position = UDim2.fromOffset(34, 22), Size = UDim2.new(1, -46, 0, 34),
    })

    -- Карточки статистики
    ui.killsLabel = makeCard(main, 16, "УБИТО VICIOUS", Color3.fromRGB(235, 20, 40), Color3.fromRGB(255, 120, 130))
    ui.rateLabel = makeCard(main, 148, "VICIOUS / ЧАС", Color3.fromRGB(255, 255, 255), Color3.fromRGB(215, 215, 215))
    ui.thornsLabel = makeCard(main, 280, "ШИПОВ ПОЛУЧЕНО", Color3.fromRGB(235, 20, 40), Color3.fromRGB(255, 120, 130))
    ui.rateLabel.Text = "0.0"

    -- Нижняя панель: аптайм и хопы
    local footerBox = Instance.new("Frame")
    footerBox.Position = UDim2.fromOffset(16, 194)
    footerBox.Size = UDim2.fromOffset(388, 42)
    footerBox.BackgroundColor3 = Color3.new(0, 0, 0)
    footerBox.BackgroundTransparency = 0.45
    footerBox.BorderSizePixel = 0
    footerBox.Parent = main
    corner(footerBox, 10)

    mkLabel(footerBox, {
        Text = "АПТАЙМ", TextSize = 10, TextColor3 = Color3.fromRGB(170, 170, 170),
        Position = UDim2.fromOffset(16, 5), Size = UDim2.fromOffset(170, 12),
    })
    ui.uptimeLabel = mkLabel(footerBox, {
        Text = "00:00:00", Font = Enum.Font.GothamBlack, TextSize = 18,
        Position = UDim2.fromOffset(16, 18), Size = UDim2.fromOffset(170, 20),
    })
    mkLabel(footerBox, {
        Text = "ХОПОВ", TextSize = 10, TextColor3 = Color3.fromRGB(170, 170, 170),
        Position = UDim2.fromOffset(210, 5), Size = UDim2.fromOffset(170, 12),
    })
    ui.hopsLabel = mkLabel(footerBox, {
        Text = "0", Font = Enum.Font.GothamBlack, TextSize = 18, TextColor3 = Color3.fromRGB(255, 95, 95),
        Position = UDim2.fromOffset(210, 18), Size = UDim2.fromOffset(170, 20),
    })
    ui.footer = footerBox

    -- Перетаскивание
    local dragging, dragStart, startPos = false, nil, nil
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = main.Position
        end
    end)
    table.insert(myConns, UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
    table.insert(myConns, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
end

local function killsPerHour()
    local up = math.max(os.time() - stats.boot, 300) -- минимум 5 мин, чтобы цифра не прыгала в начале
    local session = math.max(stats.kills - (stats.killsAtBoot or stats.kills), 0)
    return session / (up / 3600)
end

ui.refresh = function(pulse)
    pcall(function()
        if not ui.killsLabel or not ui.killsLabel.Parent then return end
        ui.killsLabel.Text = tostring(stats.kills)
        ui.thornsLabel.Text = tostring(stats.thorns)
        if ui.rateLabel then ui.rateLabel.Text = string.format("%.1f", killsPerHour()) end
        local target = (pulse == "kills" and ui.killsLabel) or (pulse == "thorns" and ui.thornsLabel) or nil
        if target then
            TweenService:Create(target, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), { TextSize = 34 }):Play()
        end
    end)
end

-- Меню создаётся сразу после закрытия экрана загрузки игры (см. huntViciousBee)
local function buildGui()
    if not SHOW_GUI or ui.statusLabel then return end
    local okGui, errGui = pcall(createGui)
    if not okGui then warn("[GUI] Не удалось создать интерфейс:", errGui) end
    ui.refresh()
    currentStatus = ""
    setStatus("Сервер загружен", "ok")
end

-- ============================================================
-- ====== СЧЁТЧИК ШИПОВ (Stinger в инвентаре) ======
-- ============================================================
local statCache
local stingerPath
local nextSearchAt = 0
local scriptStart = tick()
local thornWarned = false

local function readStingerCount()
    if not statCache then
        local m = ReplicatedStorage:FindFirstChild("ClientStatCache")
        if m and m:IsA("ModuleScript") then
            local ok, mod = pcall(require, m)
            if ok and mod then statCache = mod end
        end
        if not statCache then return nil end
    end

    local ok, data = pcall(function() return statCache:Get() end)
    if not ok or type(data) ~= "table" then return nil end

    -- Уже найденный путь
    if stingerPath then
        local cur = data
        for _, key in ipairs(stingerPath) do
            if type(cur) ~= "table" then
                cur = nil
                break
            end
            cur = cur[key]
        end
        if type(cur) == "number" then return cur end
    end

    local eggs = data.Eggs
    if type(eggs) == "table" and type(eggs.Stinger) == "number" then
        stingerPath = { "Eggs", "Stinger" }
        print("[Stats] Stinger найден: Eggs.Stinger")
        return eggs.Stinger
    end

    -- Структура другая — ищем ключ Stinger в таблицах (не чаще раза в 20 сек)
    if os.clock() >= nextSearchAt then
        nextSearchAt = os.clock() + 20
        local function find(t, path, depth)
            for k, v in pairs(t) do
                if type(k) == "string" and k:lower() == "stinger" and type(v) == "number" then
                    local pth = table.clone(path)
                    table.insert(pth, k)
                    return pth, v
                end
            end
            if depth < 3 then
                for k, v in pairs(t) do
                    if type(k) == "string" and type(v) == "table" then
                        local np = table.clone(path)
                        table.insert(np, k)
                        local pth, val = find(v, np, depth + 1)
                        if pth then return pth, val end
                    end
                end
            end
            return nil
        end
        local pth, val = find(data, {}, 1)
        if pth then
            stingerPath = pth
            print("[Stats] Stinger найден: " .. table.concat(pth, "."))
            return val
        end
    end

    -- Инвентарь загружен, но шипов в нём ещё нет
    if type(eggs) == "table" and next(eggs) ~= nil then return 0 end
    return nil
end

local function refreshThorns()
    local c = readStingerCount()
    if type(c) ~= "number" then return false end
    local gained = false
    local changed = false
    if stats.lastThorns >= 0 and c > stats.lastThorns then
        stats.thorns = stats.thorns + (c - stats.lastThorns)
        gained = true
        changed = true
    end
    if stats.lastThorns ~= c then
        stats.lastThorns = c
        changed = true
    end
    if changed then
        saveStats()
        ui.refresh(gained and "thorns" or nil)
    end
    return true
end

local function registerKill()
    stats.kills = stats.kills + 1
    saveStats()
    ui.refresh("kills")
end

-- Фоновые циклы: шипы, нижняя строка окна, отметка "жив" в файле статистики
task.spawn(function()
    while alive() do
        if gameReady then pcall(refreshThorns) end
        if gameReady and stats.lastThorns < 0 and not thornWarned and (tick() - scriptStart) > 90 then
            thornWarned = true
            warn("[Stats] Не удалось прочитать Stinger из инвентаря — счётчик шипов может не обновляться")
        end
        task.wait(1.5)
    end
end)

task.spawn(function()
    while alive() do
        pcall(function()
            if ui.uptimeLabel and ui.uptimeLabel.Parent then
                ui.uptimeLabel.Text = fmtTime(os.time() - stats.boot)
                ui.hopsLabel.Text = tostring(stats.hops)
                if ui.rateLabel then ui.rateLabel.Text = string.format("%.1f", killsPerHour()) end
            end
        end)
        task.wait(1)
    end
end)

task.spawn(function()
    while alive() do
        task.wait(30)
        saveStats()
    end
end)

-- ============================================================
-- ====== АНТИ-КРАШ И ОПТИМИЗАЦИЯ ПАМЯТИ (ANTI-OOM НА 1-2 ЧАСА) ======
-- ============================================================
-- Гасим только "визуальный шум" (частицы, лучи, следы, дым, огонь). Физика, шипы, пчела и поле не затрагиваются.
local LIGHT_CLASSES = {
    ParticleEmitter = true, Trail = true, Beam = true,
    Smoke = true, Fire = true, Sparkles = true,
}

local function lightenWorld()
    pcall(function()
        local n = 0
        for _, inst in ipairs(workspace:GetDescendants()) do
            if LIGHT_CLASSES[inst.ClassName] then
                pcall(function() inst.Enabled = false end)
            end
            n = n + 1
            if n % 2500 == 0 then task.wait() end -- без фризов: порциями по кадрам
        end
    end)
    -- Новые эффекты, появляющиеся во время боя, тоже гасим
    table.insert(myConns, workspace.DescendantAdded:Connect(function(inst)
        if LIGHT_CLASSES[inst.ClassName] then
            pcall(function() inst.Enabled = false end)
        end
    end))
end

-- stage = "early": сразу при запуске, ДО загрузки мира (графика, FPS, звук, 3D)
-- stage = "late":  после загрузки мира (Lighting, вода, цветы — раньше их ещё не существовало)
local function applyMemoryOptimizer(stage)
    if stage == "early" then
        pcall(function()
            if setfpscap and TARGET_FPS and TARGET_FPS > 0 then
                setfpscap(TARGET_FPS)
            end
        end)

        if MUTE_GAME then
            pcall(function()
                UserSettings():GetService("UserGameSettings").MasterVolume = 0
            end)
        end

        -- Выключаем 3D до подгрузки текстур/мешей — они не попадают в VRAM/RAM
        if DISABLE_3D_RENDERING then
            pcall(function()
                RunService:Set3dRenderingEnabled(false)
            end)
        end
        return
    end

    -- ---- stage == "late" ----
    local Lighting = game:GetService("Lighting")
    pcall(function()
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 9e9
        for _, effect in ipairs(Lighting:GetChildren()) do
            if effect:IsA("PostEffect") or effect:IsA("BlurEffect") or effect:IsA("SunRaysEffect")
                or effect:IsA("BloomEffect") or effect:IsA("ColorCorrectionEffect") or effect:IsA("DepthOfFieldEffect") then
                effect.Enabled = false
            end
        end
    end)

    pcall(function()
        local terrain = workspace:FindFirstChildOfClass("Terrain")
        if terrain then
            terrain.WaterWaveSize = 0
            terrain.WaterWaveSpeed = 0
            terrain.WaterReflectance = 0
            pcall(function() terrain.Decoration = false end)
        end
    end)

    if LIGHT_VISUALS then
        task.spawn(lightenWorld)
    end

    pcall(function()
        collectgarbage("collect")
    end)
end

-- ============================================================
-- ====== СТРОГИЙ ДЕТЕКТ РЕАЛЬНЫХ ОШИБОК (ВКЛЮЧАЯ 769, 279 И ДРУГИЕ) ======
-- ============================================================
local function isRealErrorString(str)
    if not str or str == "" then return false end
    local lower = tostring(str):lower()

    -- Игнорируем ТОЛЬКО нормальную клиентскую отмену
    if lower:find("disconnectclientinitiated") 
        or lower:find("clientinitiated") then
        return false
    end

    -- Ловим любые ошибки телепорта, сбои подключения, кики и коды ошибок
    if lower:find("error") 
        or lower:find("769") 
        or lower:find("279") 
        or lower:find("277") 
        or lower:find("268") 
        or lower:find("267") 
        or lower:find("770") 
        or lower:find("771") 
        or lower:find("772") 
        or lower:find("773") 
        or lower:find("524") 
        or lower:find("529") 
        or lower:find("610") 
        or lower:find("teleport") 
        or lower:find("fail") 
        or lower:find("connection") 
        or lower:find("lost connection") 
        or lower:find("kicked") then
        return true
    end

    return false
end

local function checkRealConnectionError()
    -- 1. Проверка системного сообщения GuiService
    local ok, msg = pcall(function() return GuiService:GetErrorMessage() end)
    if ok and msg and msg ~= "" and isRealErrorString(msg) then
        return msg
    end

    -- 2. Проверка РЕАЛЬНО ВИДИМОГО окна ErrorPrompt в CoreGui
    local ok2, promptGui = pcall(function() return CoreGui:FindFirstChild("RobloxPromptGui") end)
    if ok2 and promptGui and promptGui.Enabled then
        local overlay = promptGui:FindFirstChild("promptOverlay")
        local errorPrompt = overlay and overlay:FindFirstChild("ErrorPrompt")
        -- Окно ошибки должно быть действительно видимым на экране!
        if errorPrompt and errorPrompt.Visible then
            local textLabel = errorPrompt:FindFirstChildWhichIsA("TextLabel", true)
            local txt = textLabel and textLabel.Text or ""
            if isRealErrorString(txt) then
                return txt
            end
        end
    end

    return nil
end

-- ============================================================
-- ====== ОЖИДАНИЕ ЗАГРУЗКИ ИГРЫ С ТАЙМАУТОМ И ПРОВЕРКОЙ ОШИБОК ======
-- ============================================================
local function waitForGameLoaded()
    local startWait = tick()

    -- 1. Ждем IsLoaded с таймаутом (не более 12 сек)
    while not game:IsLoaded() and (tick() - startWait < 12) do
        local err = checkRealConnectionError()
        if err then return false end
        task.wait(0.2)
    end

    -- 2. Ждем LocalPlayer с таймаутом
    local curLp = Players.LocalPlayer
    while not curLp and (tick() - startWait < 15) do
        local err = checkRealConnectionError()
        if err then return false end
        task.wait(0.2)
        curLp = Players.LocalPlayer
    end
    if not curLp then return false end

    -- 3. Ждем PlayerGui с таймаутом
    local playerGui = curLp:WaitForChild("PlayerGui", 10)
    if not playerGui then return false end

    -- 4. Ожидание закрытия экрана загрузки Bee Swarm Simulator
    while (tick() - startWait < 25) do
        local err = checkRealConnectionError()
        if err then return false end

        local loadingGui = playerGui:FindFirstChild("LoadingScreenGui")
        local msg = loadingGui and loadingGui:FindFirstChild("LoadingMessage")
        if loadingGui and msg then
            if not msg.Visible then
                break -- Экран загрузки успешно закрылся!
            end
        elseif not loadingGui and (tick() - startWait < 2.5) then
            task.wait(0.1)
        else
            break
        end
        task.wait(0.1)
    end

    return true
end

-- ============================================================
-- ====== БЕЗОПАСНОЕ ИЗВЛЕЧЕНИЕ КООРДИНАТ ======
-- ============================================================
local function getPosition(obj)
    if not obj then return nil end
    if typeof(obj) == "Vector3" then return obj end
    if typeof(obj) == "CFrame" then return obj.Position end
    if typeof(obj) == "Instance" then
        if obj:FindFirstChild("patharrow") and obj.patharrow:FindFirstChild("Base") then
            return obj.patharrow.Base.Position
        end
        if obj:FindFirstChild("Platform") then
            local plat = obj.Platform
            if plat:IsA("ObjectValue") and plat.Value and plat.Value:IsA("BasePart") then
                return plat.Value.Position
            elseif plat:IsA("BasePart") then
                return plat.Position
            end
        end
        if obj:IsA("BasePart") then
            return obj.Position
        elseif obj:IsA("Model") then
            if obj.PrimaryPart then
                return obj.PrimaryPart.Position
            end
            local ok, pivot = pcall(function() return obj:GetPivot().Position end)
            if ok and pivot then return pivot end
            local anyPart = obj:FindFirstChildWhichIsA("BasePart", true)
            if anyPart then return anyPart.Position end
        elseif obj:IsA("ObjectValue") and obj.Value and obj.Value:IsA("BasePart") then
            return obj.Value.Position
        end
    end
    return nil
end

-- ============================================================
-- ====== ОПРЕДЕЛЕНИЕ И ГРАНИЦЫ ПОЛЕЙ ======
-- ============================================================
local function getFieldForPosition(pos)
    if not pos then return nil end
    local fz = workspace:FindFirstChild("FlowerZones")
    if not fz then return nil end

    local rp = RaycastParams.new()
    rp.FilterDescendantsInstances = { fz }
    rp.FilterType = Enum.RaycastFilterType.Include

    local hitDown = workspace:Raycast(pos + Vector3.new(0, 45, 0), Vector3.new(0, -90, 0), rp)
    if hitDown and hitDown.Instance and hitDown.Instance.Parent == fz then
        return hitDown.Instance
    end

    local hitUp = workspace:Raycast(pos - Vector3.new(0, 45, 0), Vector3.new(0, 90, 0), rp)
    if hitUp and hitUp.Instance and hitUp.Instance.Parent == fz then
        return hitUp.Instance
    end

    local bestField = nil
    local bestDist = math.huge
    for _, f in ipairs(fz:GetChildren()) do
        if f:IsA("BasePart") then
            local dist2D = (Vector2.new(pos.X, pos.Z) - Vector2.new(f.Position.X, f.Position.Z)).Magnitude
            local maxRadius = math.max(f.Size.X, f.Size.Z) / 2 + 15
            if dist2D < maxRadius and dist2D < bestDist then
                bestDist = dist2D
                bestField = f
            end
        end
    end

    return bestField
end

-- ============================================================
-- ====== СЕРВЕР-ХОП ======
-- ============================================================
local function httpRequest(url)
    local req = (syn and syn.request) 
        or (http and http.request) 
        or http_request 
        or (fluxus and fluxus.request) 
        or request

    if req then
        local ok, res = pcall(req, {Url = url, Method = "GET"})
        if ok and res then
            local body = type(res) == "table" and (res.Body or res.body) or res
            if body and body ~= "" then return body end
        end
    end

    if game.HttpGet then
        local ok, body = pcall(game.HttpGet, game, url)
        if ok and body and body ~= "" then return body end
    end
    return nil
end

local function loadData()
    local defaultData = { queue = {}, visited = {}, fetchedAt = 0 }
    if readfile and isfile and isfile(DATA_FILE) then
        local ok, data = pcall(function()
            return HttpService:JSONDecode(readfile(DATA_FILE))
        end)
        if ok and type(data) == "table" then
            data.queue = data.queue or {}
            data.visited = data.visited or {}
            data.fetchedAt = data.fetchedAt or 0
            
            local now = os.time()
            for id, t in pairs(data.visited) do
                if type(t) == "number" and (now - t > EXPIRE_TIME) then
                    data.visited[id] = nil
                end
            end
            return data
        end
    end
    return defaultData
end

local function saveData(data)
    if writefile then
        pcall(function()
            writefile(DATA_FILE, HttpService:JSONEncode(data))
        end)
    end
end

local function fetchNewServers(data)
    print("[Hop] 🌐 Запрос свежей пачки серверов от API...")
    setStatus("Запрашиваю список серверов…", "hop")
    local url = string.format("https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100", tostring(game.PlaceId))
    local body = httpRequest(url)
    if not body then return false end

    local ok, decoded = pcall(HttpService.JSONDecode, HttpService, body)
    if not ok or not decoded or decoded.errors or not decoded.data then
        warn("[Hop] ⚠️ Ошибка ответа API. Используем резервный вход.")
        return false
    end

    local stableServers = {}
    local otherServers = {}

    for _, s in ipairs(decoded.data) do
        if s.id ~= game.JobId and s.playing < s.maxPlayers and not data.visited[s.id] then
            if s.playing >= 2 then
                table.insert(stableServers, s.id)
            else
                table.insert(otherServers, s.id)
            end
        end
    end

    data.queue = {}
    for _, id in ipairs(stableServers) do
        table.insert(data.queue, id)
    end
    for _, id in ipairs(otherServers) do
        table.insert(data.queue, id)
    end

    data.fetchedAt = os.time()
    print(string.format("[Hop] ✅ Получено %d серверов (Стабильных: %d)!", #data.queue, #stableServers))
    return #data.queue > 0
end

local function hopToRandomServer()
    if getgenv().IsHopping then
        if tick() - (getgenv().HopStartTime or 0) > HOP_PENDING_TIMEOUT then
            getgenv().IsHopping = false
        else
            return
        end
    end

    getgenv().IsHopping = true
    getgenv().HopStartTime = tick()
    stats.hops = (stats.hops or 0) + 1
    pcall(refreshThorns) -- фиксируем шипы перед уходом с сервера
    saveStats()
    setStatus("Подбираю сервер для хопа…", "hop")

    print(string.format("[Mem] Память клиента: %d МБ | прыжков: %d | аптайм: %d мин",
        math.floor(getMemoryMb()), stats.hops, math.floor((os.time() - stats.boot) / 60)))

    local currentLp = Players.LocalPlayer or lp
    local data = loadData()
    if game.JobId and game.JobId ~= "" then
        data.visited[game.JobId] = os.time()
    end

    local now = os.time()
    if (now - (data.fetchedAt or 0)) > QUEUE_MAX_AGE then
        data.queue = {}
    end

    local validQueue = {}
    for _, id in ipairs(data.queue) do
        if not data.visited[id] and id ~= game.JobId then
            table.insert(validQueue, id)
        end
    end
    data.queue = validQueue

    if #data.queue == 0 then
        local ok = fetchNewServers(data)
        if not ok or #data.queue == 0 then
            data.visited = {}
            if game.JobId and game.JobId ~= "" then data.visited[game.JobId] = os.time() end
            saveData(data)
            warn("[Hop] Очередь пуста. Резервный хоп через матчмейкинг...")
            setStatus("Очередь пуста — резервный телепорт…", "warn")
            pcall(function()
                collectgarbage("collect")
                TeleportService:Teleport(game.PlaceId, currentLp)
            end)
            
            task.wait(6)
            getgenv().IsHopping = false
            return
        end
    end

    local chosenIndex = math.random(1, math.min(#data.queue, 15))
    local targetJobId = table.remove(data.queue, chosenIndex)

    data.visited[targetJobId] = os.time()
    saveData(data)

    print(string.format("[Hop] 🚀 Переход на сервер: %s (Осталось: %d)", targetJobId, #data.queue))
    setStatus("Телепорт на сервер …" .. tostring(targetJobId):sub(-6), "hop")

    -- Принудительный сбор мусора перед телепортом для предотвращения утечек памяти
    pcall(function()
        collectgarbage("collect")
    end)

    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, targetJobId, currentLp)
    end)

    if not ok then
        warn("[Hop] Ошибка вызова TeleportToPlaceInstance:", err, "— резервный вход")
        pcall(function()
            TeleportService:Teleport(game.PlaceId, currentLp)
        end)
        getgenv().IsHopping = false
    end
end

-- ============================================================
-- ====== ПЕРЕХВАТ ОШИБОК 769, 279 И ДИСКОННЕКТОВ ======
-- ============================================================
local isHandlingError = false

local function handleConnectionError(sourceMsg)
    if not alive() then return end
    if not isRealErrorString(sourceMsg) then
        return
    end

    if isHandlingError then return end
    isHandlingError = true

    warn(string.format("[Auto-Reconnect] ⚡ Перехвачена ошибка (%s)! Экстренный хоп на следующий сервер...", tostring(sourceMsg)))
    setStatus("Ошибка: " .. tostring(sourceMsg):sub(1, 50) .. " — хоп", "warn")

    getgenv().IsHopping = false
    pcall(function() GuiService:ClearError() end)

    task.wait(1.0)
    task.spawn(hopToRandomServer)

    -- Пауза между экстренными хопами: не спамим телепортами, пока висит окно ошибки
    task.delay(8, function()
        isHandlingError = false
    end)
end

-- 1. Системное событие GuiService
table.insert(myConns, GuiService.ErrorMessageChanged:Connect(function(msg)
    if alive() and isRealErrorString(msg) then
        handleConnectionError(msg)
    end
end))

-- 2. Безопасное событие TeleportInitFailed (ловит любые сбои телепорта, включая Error 769)
table.insert(myConns, TeleportService.TeleportInitFailed:Connect(function(player, result, errorMessage, placeId, teleportOptions)
    if not alive() then return end
    local resStr = tostring(result or "")
    local errStr = tostring(errorMessage or "")
    local fullMsg = resStr .. " " .. errStr
    local lower = fullMsg:lower()

    -- Игнорируем только намеренную отмену клиентом
    if lower:find("disconnectclientinitiated") or lower:find("clientinitiated") then
        return
    end

    local finalError = (errStr ~= "" and errStr) or ("TeleportInitFailed (" .. resStr .. ")")
    handleConnectionError(finalError)
end))

-- 3. Фоновый опрос каждые 0.3 сек (проверяет только реально видимые ошибки на экране)
task.spawn(function()
    while alive() do
        task.wait(1)
        local err = checkRealConnectionError()
        if err then
            handleConnectionError(err)
        end
    end
end)

-- ============================================================
-- ====== ТРАВЕРС И БЕЗОПАСНЫЙ TWEEN (С ЗАЩИТОЙ ОТ ПАРАЛЛЕЛЬНОГО СПАМА) ======
-- ============================================================
local isTweening = false

local function tweenToInner(target, speed, offset)
    if isTweening then return false end
    isTweening = true

    local curLp = Players.LocalPlayer or lp
    if not curLp then isTweening = false; return false end
    local char = curLp.Character
    if not char then isTweening = false; return false end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then isTweening = false; return false end

    local targetPos = getPosition(target)
    if not targetPos or typeof(targetPos) ~= "Vector3" then
        isTweening = false
        return false
    end

    if typeof(offset) == "Vector3" then
        targetPos = targetPos + offset
    end

    local maxVelocity = speed or TWEEN_SPEED
    local distance = (targetPos - hrp.Position).Magnitude
    local travelTime = distance / maxVelocity

    for _, c in ipairs(hrp:GetChildren()) do
        if c.ClassName == "AlignPosition" or c.ClassName == "AlignOrientation" then
            c:Destroy()
        end
    end

    local ap = Instance.new("AlignPosition")
    ap.Mode = Enum.PositionAlignmentMode.OneAttachment
    ap.Attachment0 = hrp:FindFirstChild("RootAttachment") or hrp.RootAttachment
    ap.Responsiveness = 35
    ap.MaxForce = math.huge
    ap.MaxVelocity = maxVelocity
    ap.Position = targetPos
    ap.Parent = hrp

    local ao = Instance.new("AlignOrientation")
    ao.Attachment0 = hrp:FindFirstChild("RootAttachment") or hrp.RootAttachment
    ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
    ao.RigidityEnabled = true
    ao.CFrame = hrp.CFrame
    ao.Parent = hrp

    pcall(function() hum:ChangeState(Enum.HumanoidStateType.Physics) end)

    local charParts = {}
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then
            table.insert(charParts, p)
        end
    end

    local stepSignal = RunService.PreSimulation or RunService.Stepped
    local noclipConn = stepSignal:Connect(function()
        for i = 1, #charParts do
            local p = charParts[i]
            if p and p.Parent and p.CanCollide then
                p.CanCollide = false
            end
        end
    end)

    local startClock = os.clock()
    while (os.clock() - startClock < travelTime + 1.2) and (os.clock() - startClock < 25) do
        if not hrp or not hrp.Parent or hum.Health <= 0 then break end
        if (hrp.Position - targetPos).Magnitude < 4.0 then break end
        RunService.Heartbeat:Wait()
    end

    -- Гарантированное безопасное завершение твина без исключений
    pcall(function()
        if noclipConn then noclipConn:Disconnect() end
        if ap and ap.Parent then ap:Destroy() end
        if ao and ao.Parent then ao:Destroy() end
        if hrp and hrp.Parent then
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
        for i = 1, #charParts do
            local p = charParts[i]
            if p and p.Parent then
                p.CanCollide = true
            end
        end
        if hum and hum.Parent then
            hum.PlatformStand = false
            hum:ChangeState(Enum.HumanoidStateType.Running)
        end
    end)

    isTweening = false
    local finalDist = (hrp and hrp.Parent and (hrp.Position - targetPos).Magnitude) or 999
    return finalDist < 8
end

local function tweenTo(target, speed, offset)
    local ok, res = pcall(tweenToInner, target, speed, offset)
    if not ok then
        isTweening = false
        warn("[Tween] Ошибка твина:", res)
        pcall(function()
            local c = Players.LocalPlayer and Players.LocalPlayer.Character
            local h = c and c:FindFirstChild("HumanoidRootPart")
            if h then
                for _, x in ipairs(h:GetChildren()) do
                    if x:IsA("AlignPosition") or x:IsA("AlignOrientation") then x:Destroy() end
                end
            end
        end)
        return false
    end
    return res
end

-- ============================================================
-- ====== ПОИСК ОБЪЕКТОВ ======
-- ============================================================
local function findViciousBee()
    local m = workspace:FindFirstChild("Monsters")
    if not m then return nil end
    for _, o in ipairs(m:GetChildren()) do
        if (o.Name:find("Vicious") or o.Name:find("Gifted Vicious")) and o:FindFirstChild("HumanoidRootPart") then
            local h = o:FindFirstChildOfClass("Humanoid")
            if not h or h.Health > 0 then
                return o
            end
        end
    end
    return nil
end

local function getWaitingThorn()
    local p = workspace:FindFirstChild("Particles")
    if not p then return nil end
    local w = p:FindFirstChild("WTs")
    if not w then return nil end
    local t = w:FindFirstChild("WaitingThorn")
    if t and t.Parent then return t end
    return nil
end

local function isOnMountainTop(bee)
    local hrp = bee:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    if hrp.Position.Y > 140 then return true end
    local field = getFieldForPosition(hrp.Position)
    return field and field.Name == "Mountain Top Field"
end

local function findFreeHive()
    local hc = workspace:FindFirstChild("Honeycombs")
    if not hc then return nil end
    for i = 6, 1, -1 do
        local hive = hc:FindFirstChild("Hive" .. i)
        if hive then
            local owner = hive:FindFirstChild("Owner")
            if owner and owner.Value == nil then
                return hive
            end
        end
    end
    return nil
end

local function occupyHive(hive)
    local curLp = Players.LocalPlayer or lp
    if not curLp then return false end
    local char = curLp.Character
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    local targetPos = getPosition(hive)
    if not targetPos then return false end

    hrp.CFrame = CFrame.new(targetPos + Vector3.new(0, 3, 0))
    task.wait(0.2)

    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
        task.wait(0.1)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
    end)

    task.wait(0.5)
    local owner = hive:FindFirstChild("Owner")
    return owner and owner.Value == curLp
end

-- ============================================================
-- ====== ПОЛЁТ НАД ПЧЕЛОЙ (ВМЕСТО МАНСИНГА) ======
-- ============================================================
local function startHover(bee, currentFieldPart, onBeeDiedCallback)
    local running = true
    local angle = 0
    local lastAttack = 0

    local curLp = Players.LocalPlayer or lp
    if not curLp then return function() end end
    local char = curLp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return function() end end

    local att = hrp:FindFirstChild("RootAttachment")
    if not att then
        att = Instance.new("Attachment")
        att.Name = "RootAttachment"
        att.Parent = hrp
    end

    for _, c in ipairs(hrp:GetChildren()) do
        if c.ClassName == "AlignPosition" or c.ClassName == "AlignOrientation" then
            c:Destroy()
        end
    end

    local ap = Instance.new("AlignPosition")
    ap.Name = "VB_HoverPos"
    ap.Mode = Enum.PositionAlignmentMode.OneAttachment
    ap.Attachment0 = att
    ap.Responsiveness = 50
    ap.MaxForce = math.huge
    ap.MaxVelocity = TWEEN_SPEED
    ap.Position = hrp.Position
    ap.Parent = hrp

    local ao = Instance.new("AlignOrientation")
    ao.Name = "VB_HoverRot"
    ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
    ao.Attachment0 = att
    ao.RigidityEnabled = true
    ao.CFrame = hrp.CFrame
    ao.Parent = hrp

    pcall(function() hum:ChangeState(Enum.HumanoidStateType.Physics) end)
    hum.PlatformStand = true

    local charParts = {}
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            table.insert(charParts, part)
        end
    end

    -- Noclip: чтобы тело пчелы не толкало и не застревало
    local noclipConn = RunService.PreSimulation:Connect(function()
        for i = 1, #charParts do
            local part = charParts[i]
            if part.Parent and part.CanCollide then
                part.CanCollide = false
            end
        end
    end)

    local conn = RunService.Heartbeat:Connect(function(dt)
        if not running then return end

        -- Мгновенный детект смерти пчелы в каждом кадре
        if not bee or not bee.Parent or not bee:IsDescendantOf(workspace) then
            if onBeeDiedCallback then onBeeDiedCallback() end
            return
        end
        local bHum = bee:FindFirstChildOfClass("Humanoid")
        if bHum and bHum.Health <= 0 then
            if onBeeDiedCallback then onBeeDiedCallback() end
            return
        end

        if not hrp.Parent or hum.Health <= 0 then return end
        local beeHrp = bee:FindFirstChild("HumanoidRootPart")
        if not beeHrp then return end

        dt = math.min(dt, 0.05)
        if not hum.PlatformStand then hum.PlatformStand = true end

        local base = beeHrp.Position
        local target = base + Vector3.new(0, HOVER_HEIGHT, 0)

        if HOVER_ORBIT_RADIUS > 0 then
            angle = angle + HOVER_ORBIT_SPEED * dt
            target = target + Vector3.new(math.cos(angle) * HOVER_ORBIT_RADIUS, 0, math.sin(angle) * HOVER_ORBIT_RADIUS)
        end

        -- Шип пробуждения ещё на поле: касаемся его сверху, чтобы разбудить пчелу
        local waitingThorn = getWaitingThorn()
        if waitingThorn and waitingThorn.Parent then
            target = waitingThorn.Position + Vector3.new(0, 3.5, 0)
        end

        ap.Position = target

        -- Смотрим в сторону пчелы
        local flat = Vector3.new(base.X - hrp.Position.X, 0, base.Z - hrp.Position.Z)
        if flat.Magnitude > 1 then
            ao.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat)
        end

        -- Авто-атака инструментом
        local now = tick()
        if now - lastAttack > 0.15 then
            local tool = char:FindFirstChildOfClass("Tool")
            if tool and (hrp.Position - base).Magnitude < 40 then
                pcall(function() tool:Activate() end)
                lastAttack = now
            end
        end
    end)

    return function()
        if not running then return end
        running = false
        pcall(function() conn:Disconnect() end)
        pcall(function() noclipConn:Disconnect() end)
        pcall(function() if ap.Parent then ap:Destroy() end end)
        pcall(function() if ao.Parent then ao:Destroy() end end)
        pcall(function()
            for i = 1, #charParts do
                local part = charParts[i]
                if part and part.Parent then part.CanCollide = true end
            end
            if hrp and hrp.Parent then
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
            end
            if hum and hum.Parent then
                hum.PlatformStand = false
                hum.WalkSpeed = 16
                hum:ChangeState(Enum.HumanoidStateType.Running)
            end
        end)
    end
end

-- ============================================================
-- ====== ГЛАВНАЯ ЛОГИКА ОХОТЫ ======
-- ============================================================
local function huntViciousBee()
    -- 1. Ранняя оптимизация (до загрузки мира)
    applyMemoryOptimizer("early")
    setStatus("Загрузка сервера…", "info")

    -- 2. Ждем корректной прогрузки игры перед началом охоты
    local loadedOk = waitForGameLoaded()
    if not loadedOk then
        warn("[Hunt] Игра не загрузилась или произошла ошибка подключения — хоп!")
        setStatus("Сервер не загрузился — меняю сервер", "warn")
        hopToRandomServer()
        return
    end

    print("[Init] ✅ Игра и экран загрузки полностью завершены!")
    gameReady = true
    buildGui()
    pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
    task.spawn(applyMemoryOptimizer, "late")
    print("[Hunt] Ищем Vicious Bee...")
    setStatus("Ищу Vicious Bee…", "info")

    local bee = findViciousBee()
    if not bee then
        print("[Hunt] ❌ Vicious не найден — ХОП")
        setStatus("Vicious не найден — меняю сервер", "hop")
        hopToRandomServer()
        return
    end

    print(string.format("[Hunt] ✅ Vicious найден: %s", bee.Name))
    setStatus("Найдена: " .. tostring(bee.Name), "ok")

    if isOnMountainTop(bee) then
        print("[Hunt] ⚠️ Vicious Bee на Mountain Top — пропускаем и хопаем")
        setStatus("Mountain Top — пропускаю сервер", "warn")
        hopToRandomServer()
        return
    end

    local curLp = Players.LocalPlayer or lp
    local char = curLp.Character or curLp.CharacterAdded:Wait()
    local hrp = char:WaitForChild("HumanoidRootPart", 10)
    if not hrp then
        hopToRandomServer()
        return
    end

    -- 3. Поиск и занятие свободного улья
    print("[Hunt] Ищем свободный улей...")
    setStatus("Ищу свободный улей…", "info")
    local hive = findFreeHive()
    if not hive then
        print("[Hunt] ❌ Свободных ульев нет — ХОП")
        setStatus("Нет свободных ульев — меняю сервер", "warn")
        hopToRandomServer()
        return
    end

    print("[Hunt] 🚀 Tween к улью:", hive.Name)
    setStatus("Лечу к улью " .. tostring(hive.Name) .. "…", "info")
    local hivePos = getPosition(hive)
    if not hivePos then
        hopToRandomServer()
        return
    end

    local reachedHive = tweenTo(hivePos, TWEEN_SPEED, Vector3.new(0, 3, 0))
    if not reachedHive then
        print("[Hunt] ❌ Не долетели до улья — ХОП")
        hopToRandomServer()
        return
    end

    task.wait(0.3)
    print("[Hunt] Занимаем улей...")
    setStatus("Занимаю улей…", "info")
    local occupied = occupyHive(hive)
    if not occupied then
        print("[Hunt] ❌ Улей не занят — ХОП")
        hopToRandomServer()
        return
    end
    print("[Hunt] ✅ Улей успешно занят!")

    -- 4. Определение поля и Tween напрямую к полю (+10 стадс)
    local beeHrp = bee:FindFirstChild("HumanoidRootPart")
    if not beeHrp then
        print("[Hunt] ❌ Vicious Bee исчезла — ХОП")
        hopToRandomServer()
        return
    end

    local waitingThorn = getWaitingThorn()
    local fieldPart = getFieldForPosition((waitingThorn and waitingThorn.Position) or beeHrp.Position)
    local targetLandingPos

    if fieldPart then
        print(string.format("[Hunt] 📍 Поле обнаружено: %s (твин на +10 стадс)", fieldPart.Name))
        setStatus("Лечу к полю: " .. tostring(fieldPart.Name), "info")
        targetLandingPos = fieldPart.Position + Vector3.new(0, 10, 0)
    else
        targetLandingPos = (waitingThorn and waitingThorn.Position) or (beeHrp.Position + Vector3.new(0, 10, 0))
    end

    -- Прямой быстрый Tween к полю на +10 стадс
    print("[Hunt] 🚀 Прямой быстрый Tween к полю (+10 стадс)...")
    tweenTo(targetLandingPos, TWEEN_SPEED)

    -- Если есть WaitingThorn, мягко подходим к шипу, чтобы разбудить пчелу
    waitingThorn = getWaitingThorn()
    if waitingThorn and waitingThorn.Parent then
        print("[Hunt] 🌵 Активируем WaitingThorn на поле...")
        setStatus("Бужу пчелу у WaitingThorn…", "info")
        tweenTo(waitingThorn.Position + Vector3.new(0, 3.5, 0), 70)
        task.wait(0.3)
    end

    -- 5. Бой: летаем над пчелой, мгновенная реакция на её смерть (с гарантированной очисткой)
    local isBeeDead = false
    local deathConns = {}
    local stopCombat
    local beeHum = bee:FindFirstChildOfClass("Humanoid")
    local lastFrac, hpKnown = 1, false
    local combatStart = tick()

    local function updateHp()
        if beeHum and beeHum.Parent then
            local mh = beeHum.MaxHealth
            if mh and mh > 0 then
                lastFrac = math.clamp(beeHum.Health / mh, 0, 1)
                if lastFrac < 0.999 then hpKnown = true end
            end
        end
    end

    local function cleanupCombat()
        getgenv().VB_InCombat = false
        if stopCombat then
            pcall(stopCombat)
            stopCombat = nil
        end
        for _, c in ipairs(deathConns) do
            pcall(function() c:Disconnect() end)
        end
        table.clear(deathConns)
    end

    local function onDead()
        if isBeeDead then return end
        isBeeDead = true
        updateHp()

        -- Убита или просто пропала? Если здоровье видно — смотрим на него, иначе считаем по времени боя
        local fought = (tick() - combatStart) >= 1
        local killed = (hpKnown and lastFrac <= 0.3) or ((not hpKnown) and fought)

        if killed then
            registerKill()
            print("[Hunt] 💀 Vicious Bee убита! Всего убито: " .. tostring(stats.kills))
            setStatus("Vicious убита! Прыгаю дальше…", "ok")
        else
            print("[Hunt] Vicious Bee исчезла без убийства — ХОП")
            setStatus("Vicious исчезла — меняю сервер", "warn")
        end

        cleanupCombat()
        task.spawn(hopToRandomServer)
    end

    -- Запуск боя: летаем над пчелой
    print(string.format("[Hunt] ⚔️ Бой: летаю над пчелой (высота %d)...", HOVER_HEIGHT))
    setStatus("Бой: лечу над Vicious…", "fight")
    getgenv().VB_InCombat = true
    combatStart = tick()
    stopCombat = startHover(bee, fieldPart, onDead)
    updateHp()

    -- Мгновенные слушатели смерти
    if beeHum then
        table.insert(deathConns, beeHum.Died:Connect(onDead))
        table.insert(deathConns, beeHum:GetPropertyChangedSignal("Health"):Connect(function()
            updateHp()
            if beeHum.Health <= 0 then onDead() end
        end))
    end
    table.insert(deathConns, bee.AncestryChanged:Connect(function(_, parent)
        if not parent or not bee:IsDescendantOf(workspace) then onDead() end
    end))
    table.insert(deathConns, bee.Destroying:Connect(onDead))

    local monstersFolder = workspace:FindFirstChild("Monsters")
    if monstersFolder then
        table.insert(deathConns, monstersFolder.ChildRemoved:Connect(function(child)
            if child == bee then onDead() end
        end))
    end

    local maxWait = 90
    local t0 = tick()
    local nextUi = 0
    while not isBeeDead and (tick() - t0) < maxWait do
        task.wait(0.05)

        if not bee or not bee.Parent or not bee:IsDescendantOf(workspace) then
            onDead()
            break
        end

        -- Проверка на смерть персонажа игрока
        local myChar = curLp.Character
        local myHum = myChar and myChar:FindFirstChildOfClass("Humanoid")
        if not myHum or myHum.Health <= 0 then
            warn("[Hunt] 💀 Персонаж погиб! Ожидание возрождения...")
            setStatus("Персонаж погиб — жду возрождения…", "warn")
            if stopCombat then
                pcall(stopCombat)
                stopCombat = nil
            end

            curLp.CharacterAdded:Wait()
            task.wait(1)

            if not isBeeDead and bee and bee.Parent then
                local bHrp = bee:FindFirstChild("HumanoidRootPart")
                if bHrp then
                    print("[Hunt] 🚀 Возврат к пчеле (+" .. HOVER_HEIGHT .. " стадс)...")
                    setStatus("Возвращаюсь к Vicious…", "info")
                    tweenTo(bHrp.Position, TWEEN_SPEED, Vector3.new(0, HOVER_HEIGHT, 0))
                    stopCombat = startHover(bee, fieldPart, onDead)
                end
            else
                break
            end
        elseif (tick() - t0) >= nextUi then
            nextUi = (tick() - t0) + 0.3
            updateHp()
            local hpText = hpKnown and string.format(" · HP %d%%", math.floor(lastFrac * 100 + 0.5)) or ""
            setStatus("Бой: летаю над Vicious" .. hpText, "fight")
        end
    end

    -- Если время боя истекло, а пчела не убита — обязательная очистка и хоп!
    if not isBeeDead then
        warn("[Hunt] ⏰ Время боя истекло (90 сек) — очистка и хоп!")
        setStatus("Время боя вышло — меняю сервер", "warn")
        cleanupCombat()
        hopToRandomServer()
    end
end

-- ============================================================
-- ====== СТОРОЖЕВОЙ ТАЙМЕР (WATCHDOG) ======
-- ============================================================
local WATCHDOG_LIMIT = 90   -- Секунд на сервере до принудительного хопа
local WATCHDOG_RETRY = 45   -- Если хоп не удался (остались на сервере) — повтор через столько секунд
local serverEntryTime = tick()

task.spawn(function()
    while alive() do
        task.wait(5)
        if tick() - serverEntryTime > WATCHDOG_LIMIT then
            warn("[Watchdog] ⏰ Сервер превысил лимит — принудительный хоп!")
            -- Следующая попытка через WATCHDOG_RETRY сек, если хоп не сработает (раньше сторож просто умирал)
            serverEntryTime = tick() - (WATCHDOG_LIMIT - WATCHDOG_RETRY)
            pcall(function() collectgarbage("collect") end)
            -- Внутри hopToRandomServer уже есть защита от наложения телепортов
            pcall(hopToRandomServer)
        end
    end
end)

-- ЗАПУСК ОХОТЫ
task.spawn(function()
    local ok, err = pcall(huntViciousBee)
    if not ok then
        warn("[Hunt] Ошибка выполнения цикла охоты:", err)
        hopToRandomServer()
    end
end)

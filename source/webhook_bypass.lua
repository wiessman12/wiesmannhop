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
local DISABLE_3D_RENDERING = true    -- true = 3D-рендер выключен с самого входа на сервер: экран чёрный, окно хоппера видно. Главная защита от роста памяти и VRAM между хопами. false = картинка как обычно
local DISABLE_COREGUI = true         -- Отключает встроенный интерфейс Roblox (список игроков, чат, рюкзак): его скрипты пересоздаются при каждом телепорте
local LIGHT_VISUALS = false          -- Гашение частиц обходит весь workspace (тяжело для BSS). Включай только если нужно
local MUTE_GAME = true               -- Выключить звук (меньше памяти и CPU)

-- ====== АНТИ-ЛАГ (портирован из Atlas, набор адаптирован под хоппер) ======
local ANTILAG_ENABLED = true            -- Главный выключатель. Если вернулись кики 267 — сначала выключи hide*/destroy* пункты ниже по одному
local ANTILAG = {
    main = true,                -- Качество графики на минимум, вода/тени/туман (и не даём игре вернуть тени/туман)
    pollenPopups = true,        -- Выключает всплывающие цифры пыльцы (меняет настройку PollenPopUps в аккаунте игры, как в Atlas)
    hideTokens = true,          -- Токены (хук CollectiblesAnimator)             — нужен hookfunction
    hideParticles = true,       -- Шумные эффекты LocalFX по списку из Atlas      — нужен hookfunction
    hidePrecise = true,         -- Мишени Precise                                 — нужен hookfunction
    hideDuped = true,           -- Дублированные токены                           — нужен hookfunction
    hideMarks = true,           -- Метки станций                                  — нужен hookfunction
    hideBees = true,            -- Модели своих пчёл (только картинка, урон не меняется)
    hideFlowers = true,         -- Цветы (хоппер пыльцу не собирает; поле определяется по FlowerZones)
    hideBalloons = true,        -- Шарики на полях
    destroyTextures = true,     -- Decal/Texture/ParticleEmitter удаляются, материалы -> Plastic (главный выигрыш по памяти)
    destroyDecorations = true,  -- Безопасный набор декораций (улей, поля, пути, стены и территории НЕ трогаем)
    hidePlayers = true,         -- Персонажи других игроков (шапки/меши — много памяти на людных серверах)
    hideBssUi = true,           -- Интерфейс самой игры (PlayerGui.ScreenGui); окно хоппера не затрагивается
}

-- ====== ПЛАНОВЫЙ ПЕРЕЗАПУСК КЛИЕНТА (лечит накопление памяти между телепортами, которое скрипт изнутри не освобождает) ======
local RESTART_ENABLED = false   -- true = скрипт САМ закрывает Roblox (game:Shutdown) до вылета. Включай только вместе с vb_watchdog.ps1, иначе клиент закроется и не вернётся
local RESTART_AFTER_MIN = 75    -- закрыться, когда клиент работает дольше стольки минут (0 = не проверять)
local RESTART_AT_MB = 0         -- ...или когда память клиента выше стольки МБ (0 = не проверять)
local RESTART_FLAG = "vb_restart.flag"  -- метка «это плановый перезапуск»: после него цифры в меню не сбрасываются

-- ====== ИНТЕРФЕЙС ======
local SHOW_GUI = true                -- Окно со статистикой (чуть выше центра экрана, можно перетаскивать за заголовок)
local STATS_FILE = "vicious_stats.json"

local LOAD_TIMEOUT = 45              -- Если игра не прогрузилась за N секунд — скрипт хопает на другой сервер
local HIVE_MAX_ATTEMPTS = 6         -- Сколько раз пробовать занять улей, прежде чем хопнуть
local RESET_ON_RELAUNCH = true      -- Сбрасывать цифры в меню при каждом новом запуске Roblox (хопы внутри одного запуска цифры не сбрасывают)
local HOP_PENDING_TIMEOUT = 40          -- Сколько секунд ждать завершения телепорта, прежде чем пробовать снова
local RECOVERY_STEP_TIMEOUT = 12        -- После дисконнекта (267/277/769...): сколько секунд ждать результата попытки, прежде чем пробовать другой способ
local RELAUNCH_MIN_GAP = 90             -- Перезапуском Roblox считается только пауза не меньше стольки секунд между последним сохранением и стартом (обычный хоп короче)

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
local stats = { kills = 0, thorns = 0, lastThorns = -1, hops = 0, boot = os.time(), lastSeen = 0, thornsAtBoot = 0 }
local STATS_BAK = STATS_FILE .. ".bak"
local STATS_PREV = STATS_FILE .. ".prev"   -- сюда уходит старая статистика перед любым сбросом (чтобы цифры можно было вернуть)

-- Токен текущего запуска Roblox (может меняться при входе на новый сервер — поэтому одним им не пользуемся)
local sessionToken
do
    local ok, id = pcall(function() return game:GetService("RbxAnalyticsService"):GetSessionId() end)
    if ok and type(id) == "string" and id ~= "" then sessionToken = id end
end

-- Сколько секунд работает само приложение Roblox (если executor это поддерживает)
local function getProcUptime()
    local ok, v = pcall(function() return elapsedTime() end)
    if ok and type(v) == "number" then return v end
    return nil
end

local function readStatsFile(path)
    if not (readfile and isfile) then return nil end
    local okF, exists = pcall(isfile, path)
    if not okF or not exists then return nil end
    local ok, data = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
    if ok and type(data) == "table" then return data end
    return nil
end

-- Файл может быть занят/недописан сразу после телепорта — пробуем несколько раз, а не сразу считаем его пустым
local function readStatsRetry(path)
    if not (readfile and isfile) then return nil end
    for _ = 1, 5 do
        local d = readStatsFile(path)
        if d then return d end
        local okF, exists = pcall(isfile, path)
        if not (okF and exists) then return nil end
        task.wait(0.4)
    end
    return nil
end

local function fileExists(path)
    if not isfile then return false end
    local ok, ex = pcall(isfile, path)
    return ok and ex or false
end

do
    local now = os.time()
    local curUp = getProcUptime()
    local data = readStatsRetry(STATS_FILE) or readStatsRetry(STATS_BAK)
    local sameProcess = false

    -- Метка планового перезапуска (ставится в checkPlannedRestart перед game:Shutdown)
    local plannedRestart = false
    pcall(function()
        if fileExists(RESTART_FLAG) then
            local t = tonumber(readfile(RESTART_FLAG))
            if t and now - t < 1800 then plannedRestart = true end
            if delfile then delfile(RESTART_FLAG) else writefile(RESTART_FLAG, "") end
        end
    end)
    local reason = "файла статистики нет — старт с нуля"

    if data then
        local gap = now - (tonumber(data.lastSeen) or 0)
        if getgenv().VB_ProcessAlive then
            sameProcess, reason = true, "тот же запуск Roblox (executor помнит прошлый запуск)"
        elseif plannedRestart then
            sameProcess, reason = true, string.format("плановый перезапуск клиента, пауза %d с", gap)
        elseif not RESET_ON_RELAUNCH then
            sameProcess, reason = true, "RESET_ON_RELAUNCH выключен"
        elseif gap < RELAUNCH_MIN_GAP then
            sameProcess, reason = true, string.format("пауза всего %d с — обычный хоп", gap)
        else
            -- Сбрасываем только если ВСЕ доступные признаки говорят о новом запуске
            local votes, total = 0, 0
            if curUp and tonumber(data.procUp) then
                total = total + 1
                if curUp + 15 < tonumber(data.procUp) then votes = votes + 1 end
            end
            if sessionToken and data.sessionToken then
                total = total + 1
                if sessionToken ~= data.sessionToken then votes = votes + 1 end
            end
            if total >= 2 then
                sameProcess = votes < total
                reason = string.format("признаков перезапуска %d из %d, пауза %d с", votes, total, gap)
            else
                sameProcess = gap <= 240
                reason = string.format("мало признаков (%d), решает пауза %d с", total, gap)
            end
        end
    elseif fileExists(STATS_FILE) or fileExists(STATS_BAK) then
        -- Файлы есть, но прочитать не удалось: не затираем их нулями молча
        reason = "файл статистики есть, но не читается — старт с нуля, копия сохранена в .lost"
        pcall(function()
            local src = fileExists(STATS_FILE) and STATS_FILE or STATS_BAK
            writefile(STATS_FILE .. ".lost", readfile(src))
        end)
    end

    if sameProcess then
        stats.kills = tonumber(data.kills) or 0
        stats.thorns = tonumber(data.thorns) or 0
        stats.lastThorns = tonumber(data.lastThorns) or -1
        stats.hops = tonumber(data.hops) or 0
        stats.boot = tonumber(data.boot) or now
        stats.thornsAtBoot = tonumber(data.thornsAtBoot) or 0
        stats.lastJobId = data.lastJobId
    else
        if data and writefile then
            pcall(function() writefile(STATS_PREV, HttpService:JSONEncode(data)) end) -- архив перед сбросом
        end
        stats.kills, stats.thorns, stats.lastThorns = 0, 0, -1
        stats.hops, stats.boot, stats.thornsAtBoot = 0, now, 0
        stats.lastJobId = nil
    end
    print(string.format("[Stats] %s: %s", sameProcess and "цифры сохранены" or "цифры сброшены", reason))
    getgenv().VB_ProcessAlive = true

    -- Хоп считаем тогда, когда реально оказались на новом сервере (а не при каждой попытке телепорта)
    local jobId = game.JobId
    if jobId and jobId ~= "" then
        if stats.lastJobId and stats.lastJobId ~= jobId then
            stats.hops = stats.hops + 1
        end
        stats.lastJobId = jobId
    end
    stats.lastSeen = now
end

local function saveStats()
    stats.lastSeen = os.time()
    stats.sessionToken = sessionToken
    stats.procUp = getProcUptime()
    if writefile then
        pcall(function()
            local json = HttpService:JSONEncode(stats)
            writefile(STATS_BAK, json)   -- сначала копия, потом основной файл: хотя бы один всегда целый
            writefile(STATS_FILE, json)
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
    ui.rateLabel = makeCard(main, 148, "ШИПОВ / ЧАС", Color3.fromRGB(255, 255, 255), Color3.fromRGB(215, 215, 215))
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

local function thornsPerHour()
    local up = math.max(os.time() - stats.boot, 300) -- минимум 5 мин, чтобы цифра не прыгала в начале
    local session = math.max(stats.thorns - (stats.thornsAtBoot or 0), 0)
    return session / (up / 3600)
end

ui.refresh = function(pulse)
    pcall(function()
        if not ui.killsLabel or not ui.killsLabel.Parent then return end
        ui.killsLabel.Text = tostring(stats.kills)
        ui.thornsLabel.Text = tostring(stats.thorns)
        if ui.rateLabel then ui.rateLabel.Text = string.format("%.1f", thornsPerHour()) end
        local target = (pulse == "kills" and ui.killsLabel) or (pulse == "thorns" and ui.thornsLabel) or nil
        if target then
            -- Без твинов: они накладывались друг на друга, размер текста "уплывал" и цифры пропадали
            ui.pulseTok = ui.pulseTok or {}
            local tok = (ui.pulseTok[target] or 0) + 1
            ui.pulseTok[target] = tok
            target.TextSize = 34
            task.delay(0.15, function()
                if ui.pulseTok[target] == tok and target.Parent then target.TextSize = 28 end
            end)
        end
    end)
end

-- Меню создаётся сразу после закрытия экрана загрузки игры (см. huntViciousBee)
local function buildGui()
    if not SHOW_GUI then return end
    local keepText = currentStatus ~= "" and currentStatus or "Сервер загружен"
    local keepKind = ui.lastKind or "ok"
    local okGui, errGui = pcall(createGui)
    if not okGui then warn("[GUI] Не удалось создать интерфейс:", errGui) end
    ui.refresh()
    currentStatus = ""
    ui.lastKind = nil
    setStatus(keepText, keepKind)
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

local thornLowerReads = 0
local thornLowerValue = nil
local thornPendingBase = nil
local thornRestoreLevel = nil     -- уровень шипов до сбоя чтения: возврат к нему не считается новыми шипами
local thornRestoreUntil = 0
local THORN_DROP_CONFIRM = 8      -- столько чтений подряд (~12 с) с одним и тем же меньшим значением, чтобы поверить в падение

local function refreshThorns()
    local c = readStingerCount()
    if type(c) ~= "number" then return false end

    -- Базовое значение принимаем только после двух одинаковых чтений подряд (защита от случайного 0 при загрузке данных)
    if stats.lastThorns < 0 then
        if thornPendingBase == c then
            stats.lastThorns = c
            thornPendingBase = nil
            saveStats()
            ui.refresh()
        else
            thornPendingBase = c
        end
        return true
    end

    -- Падение числа шипов: верим ему только если одно и то же меньшее значение держится долго.
    -- Иначе кратковременный 0 при загрузке данных занижает базу, а возврат нормального значения потом считается "новыми" шипами
    if c < stats.lastThorns then
        if thornLowerValue == c then
            thornLowerReads = thornLowerReads + 1
        else
            thornLowerValue, thornLowerReads = c, 1
        end
        if thornLowerReads < THORN_DROP_CONFIRM then return true end
        thornRestoreLevel = stats.lastThorns
        thornRestoreUntil = tick() + 120
    end
    thornLowerReads, thornLowerValue = 0, nil

    local gained = false
    local changed = false
    if c > stats.lastThorns then
        local gain = c - stats.lastThorns
        if thornRestoreLevel and tick() < thornRestoreUntil then
            -- Значение вернулось к прежнему уровню после сбоя чтения — считаем только то, что выше него
            gain = math.max(c - math.max(thornRestoreLevel, stats.lastThorns), 0)
        end
        if thornRestoreLevel and c >= thornRestoreLevel then thornRestoreLevel = nil end
        if gain > 0 then
            stats.thorns = stats.thorns + gain
            gained = true
        end
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
            -- Если окно пропало (его удалили/сбросило) — пересоздаём
            if SHOW_GUI and gameReady and not (ui.statusLabel and ui.statusLabel.Parent and ui.statusLabel:IsDescendantOf(game)) then
                buildGui()
            end
            if ui.uptimeLabel and ui.uptimeLabel.Parent then
                ui.uptimeLabel.Text = fmtTime(os.time() - stats.boot)
                ui.hopsLabel.Text = tostring(stats.hops)
                ui.refresh() -- каждую секунду пере-выставляем все цифры из реальных данных
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
        if DISABLE_3D_RENDERING or getgenv().VB_EmergencyMem then
            local ok3d, err3d = pcall(function()
                RunService:Set3dRenderingEnabled(false)
            end)
            if not ok3d then warn("[Memory] Не удалось выключить 3D-рендер:", err3d) end
        end

        -- Встроенный интерфейс Roblox: CoreGui регистрируется не сразу, поэтому пробуем несколько секунд
        if DISABLE_COREGUI then
            task.spawn(function()
                for _ = 1, 40 do
                    if not alive() then return end
                    local ok = pcall(function()
                        game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
                    end)
                    if ok then break end
                    task.wait(0.5)
                end
                pcall(function()
                    local tcs = game:GetService("TextChatService")
                    tcs.ChatWindowConfiguration.Enabled = false
                    tcs.ChatInputBarConfiguration.Enabled = false
                end)
            end)
        end
        return
    end

    -- ---- stage == "late" ----
    -- Повторяем то, что ранний этап мог не успеть применить
    if DISABLE_3D_RENDERING or getgenv().VB_EmergencyMem then
        pcall(function() RunService:Set3dRenderingEnabled(false) end)
    end
    if DISABLE_COREGUI then
        pcall(function() game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)
    end
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
    local stable = 0

    while tick() - startWait < LOAD_TIMEOUT do
        local err = checkRealConnectionError()
        if err then return false end

        local ready = false
        local curLp = Players.LocalPlayer
        if game:IsLoaded() and curLp then
            local playerGui = curLp:FindFirstChild("PlayerGui")
            if playerGui then
                -- Экран загрузки Bee Swarm Simulator должен быть закрыт
                local loadingGui = playerGui:FindFirstChild("LoadingScreenGui")
                local msg = loadingGui and loadingGui:FindFirstChild("LoadingMessage")
                local loadingVisible = (loadingGui and loadingGui.Enabled and msg and msg.Visible) or false

                -- Мир и персонаж должны реально существовать
                local char = curLp.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                local worldReady = workspace:FindFirstChild("Honeycombs") ~= nil

                ready = (not loadingVisible) and hrp ~= nil and worldReady
            end
        end

        -- Готовность должна продержаться ~1 сек подряд, а не мелькнуть на кадр
        if ready then
            stable = stable + 1
            if stable >= 10 then return true end
        else
            stable = 0
        end
        task.wait(0.1)
    end

    return false -- не прогрузилось за LOAD_TIMEOUT секунд
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

-- ====== КОНТРОЛЬ ПАМЯТИ: лог роста + аварийный режим, если клиент раздулся ======
local MEM_LOG = "vb_mem_log.txt"
local MEM_GROWTH_LIMIT_MB = 1200   -- Прирост памяти (МБ) от первого замера за запуск Roblox, после которого включается аварийный режим (3D-рендер выкл.). 0 = выключено

-- Какие категории памяти самые большие (Instances / LuaHeap / GraphicsTexture ...) — показывает, где именно утечка
local function memTopTags()
    local out = {}
    pcall(function()
        local Stats = game:GetService("Stats")
        for _, tag in ipairs(Enum.DeveloperMemoryTag:GetEnumItems()) do
            local okT, v = pcall(function() return Stats:GetMemoryUsageMbForTag(tag) end)
            if okT and type(v) == "number" and v >= 50 then table.insert(out, { tag.Name, v }) end
        end
    end)
    table.sort(out, function(a, b) return a[2] > b[2] end)
    local parts = {}
    for i = 1, math.min(5, #out) do parts[i] = string.format("%s %d", out[i][1], out[i][2]) end
    return table.concat(parts, ", ")
end

local function logMem(tag)
    local mb = math.floor(getMemoryMb())
    if not getgenv().VB_MemBase and mb > 0 then getgenv().VB_MemBase = mb end
    local growth = mb - (getgenv().VB_MemBase or mb)

    -- Утечка на хоп: сравниваем память сразу после загрузки сервера с первым замером за запуск Roblox
    local leakNote = ""
    if tag == "сервер загружен" then
        getgenv().VB_LoadN = (getgenv().VB_LoadN or 0) + 1
        getgenv().VB_LoadFirstMb = getgenv().VB_LoadFirstMb or mb
        if getgenv().VB_LoadN >= 4 then
            local perHop = (mb - getgenv().VB_LoadFirstMb) / (getgenv().VB_LoadN - 1)
            leakNote = string.format(" | рост ≈ %d МБ/хоп (за %d хопов)", math.floor(perHop), getgenv().VB_LoadN)
            print("[Mem]" .. leakNote)
        end
    end

    if writefile then
        pcall(function()
            local line = string.format("%s | %s | %d МБ | прирост %d МБ | хопов %d | аптайм %d мин | топ: %s%s\n",
                os.date("%H:%M:%S"), tag, mb, growth, stats.hops, math.floor((os.time() - stats.boot) / 60), memTopTags(), leakNote)
            if appendfile then
                appendfile(MEM_LOG, line)
            else
                local old = (isfile and isfile(MEM_LOG) and readfile(MEM_LOG)) or ""
                if #old > 20000 then old = old:sub(-10000) end
                writefile(MEM_LOG, old .. line)
            end
        end)
    end
    if MEM_GROWTH_LIMIT_MB > 0 and growth > MEM_GROWTH_LIMIT_MB and not getgenv().VB_EmergencyMem then
        getgenv().VB_EmergencyMem = true
        warn(string.format("[Mem] ⚠️ Память выросла на %d МБ — аварийный режим: 3D-рендер выключен", growth))
        pcall(function() RunService:Set3dRenderingEnabled(false) end)
        pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
    end
end

-- Время работы клиента считаем сами: getgenv() живёт, пока жив процесс Roblox, и обнуляется при новом запуске
getgenv().VB_ClientStart = getgenv().VB_ClientStart or os.time()

local function checkPlannedRestart()
    if not RESTART_ENABLED or getgenv().VB_RestartFailed then return end
    local upMin = (os.time() - getgenv().VB_ClientStart) / 60
    local mb = getMemoryMb()
    local byTime = RESTART_AFTER_MIN > 0 and upMin >= RESTART_AFTER_MIN
    local byMem = RESTART_AT_MB > 0 and mb >= RESTART_AT_MB
    if not (byTime or byMem) then return end

    warn(string.format("[Restart] Плановый перезапуск клиента: работает %d мин, память %d МБ (%s)",
        math.floor(upMin), math.floor(mb), byTime and "по времени" or "по памяти"))
    setStatus("Плановый перезапуск Roblox…", "hop")
    saveStats()
    pcall(logMem, "плановый перезапуск")
    if writefile then pcall(writefile, RESTART_FLAG, tostring(os.time())) end
    task.wait(1)
    pcall(function() game:Shutdown() end)
    task.wait(15)
    -- Если мы ещё здесь, закрыться не удалось: больше не пытаемся и продолжаем хопы
    getgenv().VB_RestartFailed = true
    warn("[Restart] game:Shutdown() не закрыл клиент — плановый перезапуск отключён, закрой Roblox вручную")
    if delfile and isfile and isfile(RESTART_FLAG) then pcall(delfile, RESTART_FLAG) end
end

local function hopToRandomServer()
    if getgenv().IsHopping then
        if tick() - (getgenv().HopStartTime or 0) > HOP_PENDING_TIMEOUT then
            getgenv().IsHopping = false
        else
            return
        end
    end

    pcall(checkPlannedRestart) -- если пора — закроет клиент прямо здесь

    getgenv().IsHopping = true
    getgenv().HopStartTime = tick()
    getgenv().VB_HopAttempts = (getgenv().VB_HopAttempts or 0) + 1
    pcall(refreshThorns) -- фиксируем шипы перед уходом с сервера
    saveStats()
    setStatus("Подбираю сервер для хопа…", "hop")

    pcall(logMem, "перед хопом")
    print(string.format("[Mem] Память клиента: %d МБ | прыжков: %d | аптайм: %d мин",
        math.floor(getMemoryMb()), stats.hops, math.floor((os.time() - stats.boot) / 60)))

    local currentLp = Players.LocalPlayer or lp
    do
        local tw = tick()
        while not currentLp and (tick() - tw) < 8 do
            task.wait(0.2)
            currentLp = Players.LocalPlayer
        end
    end
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
    if ok then print("[Hop] TeleportToPlaceInstance вызван без ошибки (ждём результат)") end

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
local clearedByUs = false

-- ====== ЖУРНАЛ КИКОВ: пишет в vb_kick_log.txt точную причину и контекст, чтобы найти, что вызывает 267 ======
local KICK_LOG = "vb_kick_log.txt"
local KICK_MARK = "vb_kick_mark.txt"
local joinedAt = tick()
-- сколько раз пытались телепортироваться с прошлого сервера (до сброса счётчика на этом)
getgenv().VB_PrevAttempts = getgenv().VB_HopAttempts or 0
getgenv().VB_HopAttempts = 0

local function appendLog(line)
    if not writefile then return end
    pcall(function()
        if appendfile then
            appendfile(KICK_LOG, line .. "\n")
        else
            local old = (isfile and isfile(KICK_LOG) and readfile(KICK_LOG)) or ""
            writefile(KICK_LOG, old .. line .. "\n")
        end
    end)
end

local function logKick(msg)
    local status = ""
    pcall(function() status = tostring(currentStatus or "") end)
    local sinceHop = getgenv().HopStartTime and tostring(math.floor(tick() - getgenv().HopStartTime)) or "-"
    appendLog(string.format(
        "[%s] ОШИБКА: %s | на сервере %d с | с последней попытки хопа %s с | попыток телепорта: с прошлого сервера %d, с этого %d | хопов за запуск %d | статус: %s | job %s",
        os.date("%Y-%m-%d %H:%M:%S"), tostring(msg), math.floor(tick() - joinedAt), sinceHop,
        getgenv().VB_PrevAttempts or 0, getgenv().VB_HopAttempts or 0, stats.hops, status, tostring(game.JobId)))
    -- метка времени первого срабатывания: по ней при следующем запуске посчитаем, сколько простояли
    pcall(function()
        if not (isfile and isfile(KICK_MARK)) then writefile(KICK_MARK, tostring(os.time())) end
    end)
end

-- Если после кика мы снова запустились — записываем, сколько это заняло
pcall(function()
    if isfile and isfile(KICK_MARK) then
        local t = tonumber(readfile(KICK_MARK))
        if t then
            appendLog(string.format("[%s] ✅ Вернулись в игру через %d с после ошибки", os.date("%Y-%m-%d %H:%M:%S"), os.time() - t))
        end
        if delfile then delfile(KICK_MARK) else writefile(KICK_MARK, "") end
    end
end)

-- Нажимает кнопку в окне ошибки по подстроке в её тексте/имени (например "reconnect")
local function clickPromptButton(keywords)
    local pressed = false
    pcall(function()
        local pg = CoreGui:FindFirstChild("RobloxPromptGui")
        if not pg then return end
        local inset = pg.IgnoreGuiInset and 0 or GuiService:GetGuiInset().Y
        for _, d in ipairs(pg:GetDescendants()) do
            if d:IsA("GuiButton") and d.Visible then
                local label = d.Name
                if d:IsA("TextButton") then label = label .. " " .. d.Text end
                local tl = d:FindFirstChildWhichIsA("TextLabel", true)
                if tl then label = label .. " " .. tl.Text end
                label = label:lower()
                for _, k in ipairs(keywords) do
                    if label:find(k, 1, true) then
                        if firesignal then
                            pcall(firesignal, d.MouseButton1Click)
                            pcall(firesignal, d.Activated)
                        end
                        local x = d.AbsolutePosition.X + d.AbsoluteSize.X / 2
                        local y = d.AbsolutePosition.Y + d.AbsoluteSize.Y / 2 + inset
                        pcall(function()
                            VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
                            task.wait(0.05)
                            VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
                        end)
                        pressed = true
                        return
                    end
                end
            end
        end
    end)
    return pressed
end

-- Одна попытка выбраться с сервера. Способы чередуются: если один не сработал за RECOVERY_STEP_TIMEOUT, берём следующий
local function recoveryAttempt(step, isKick)
    -- При кике (267) сначала обычный Teleport(PlaceId): он не тратит серверы из очереди и работает из экрана ошибки
    local order = isKick and { 2, 1, 2, 4 } or { 1, 2, 3, 4 }
    local m = order[((step - 1) % 4) + 1]
    local plr = Players.LocalPlayer or lp
    getgenv().IsHopping = false

    if m == 1 then
        print(string.format("[Recovery] #%d: TeleportToPlaceInstance (окно ошибки не трогаем)", step))
        setStatus("Восстановление: хоп на новый сервер…", "warn")
        hopToRandomServer()
    elseif m == 2 then
        print(string.format("[Recovery] #%d: Teleport(PlaceId) — любой сервер", step))
        setStatus("Восстановление: обычный телепорт…", "warn")
        getgenv().IsHopping = true
        getgenv().HopStartTime = tick()
        pcall(function() TeleportService:Teleport(game.PlaceId, plr) end)
    elseif m == 3 then
        print(string.format("[Recovery] #%d: ClearError + TeleportToPlaceInstance", step))
        setStatus("Восстановление: сброс ошибки и хоп…", "warn")
        clearedByUs = true
        pcall(function() GuiService:ClearError() end)
        task.wait(0.5)
        hopToRandomServer()
    else
        print(string.format("[Recovery] #%d: кнопка Reconnect в окне ошибки", step))
        setStatus("Восстановление: кнопка Reconnect…", "warn")
        if not clickPromptButton({ "reconnect", "rejoin" }) then
            print("[Recovery] кнопки нет — Teleport(PlaceId) без указания игрока")
            getgenv().IsHopping = true
            getgenv().HopStartTime = tick()
            pcall(function() TeleportService:Teleport(game.PlaceId) end)
        end
    end
end

-- hard = true: ошибка видна на экране / в GuiService (дисконнект, кик 267 и т.п.) — повторяем, пока не уйдём с сервера.
-- hard = false: сорвался сам вызов телепорта при живом соединении — одной новой попытки достаточно, дальше работают сторожа.
local KICK_STEP_WAITS = { 12, 20, 30, 45 }

local function handleConnectionError(sourceMsg, hard)
    if not alive() then return end
    if not isRealErrorString(sourceMsg) then return end
    if isHandlingError then return end
    isHandlingError = true
    clearedByUs = false

    local lowMsg = tostring(sourceMsg):lower()
    local isKick = (lowMsg:find("267", 1, true) ~= nil) or (lowMsg:find("kicked", 1, true) ~= nil)
    pcall(logKick, sourceMsg)

    warn(string.format("[Auto-Reconnect] ⚡ Перехвачена ошибка (%s)! Запускаю восстановление...", tostring(sourceMsg)))
    setStatus("Ошибка: " .. tostring(sourceMsg):sub(1, 50) .. " — хоп", "warn")

    task.spawn(function()
        task.wait(1.0)
        local step = 0
        local healthy = 0
        while alive() do
            step = step + 1
            local ok, err = pcall(recoveryAttempt, step, isKick)
            if not ok then warn("[Recovery] ошибка шага:", err) end

            -- Если телепорт удался, этот скрипт умирает вместе с сервером и цикл просто обрывается
            -- При кике паузы растут (12 → 20 → 30 → 45 с), чтобы не долбить входом каждые 12 секунд
            local stepWait = isKick and KICK_STEP_WAITS[math.min(step, #KICK_STEP_WAITS)] or RECOVERY_STEP_TIMEOUT
            local t0 = tick()
            while alive() and tick() - t0 < stepWait do task.wait(0.5) end
            if not alive() then break end
            if not hard then break end

            if not clearedByUs and not checkRealConnectionError() then
                healthy = healthy + 1
                if healthy >= 2 then
                    print("[Recovery] Окно ошибки пропало само — соединение живо, отбой")
                    break
                end
            else
                healthy = 0
            end
        end
        isHandlingError = false
    end)
end

-- 1. Системное событие GuiService
table.insert(myConns, GuiService.ErrorMessageChanged:Connect(function(msg)
    if alive() and isRealErrorString(msg) then
        handleConnectionError(msg, true)
    end
end))

-- 2. Событие TeleportInitFailed (любые сбои вызова телепорта)
table.insert(myConns, TeleportService.TeleportInitFailed:Connect(function(player, result, errorMessage, placeId, teleportOptions)
    if not alive() then return end
    local resStr = tostring(result or "")
    local errStr = tostring(errorMessage or "")
    local lower = (resStr .. " " .. errStr):lower()

    -- Игнорируем только намеренную отмену клиентом
    if lower:find("disconnectclientinitiated") or lower:find("clientinitiated") then
        return
    end

    -- Всегда содержит "teleport"/"fail", иначе короткие тексты вроде "game is full" отфильтровались бы
    handleConnectionError("TeleportInitFailed (" .. resStr .. ") " .. errStr, false)
end))

-- 3. Фоновый опрос раз в секунду (только реально видимые ошибки)
task.spawn(function()
    while alive() do
        task.wait(1)
        if not isHandlingError then
            local err = checkRealConnectionError()
            if err then
                handleConnectionError(err, true)
            end
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

local function ownsHive()
    local curLp = Players.LocalPlayer or lp
    local hc = workspace:FindFirstChild("Honeycombs")
    if not curLp or not hc then return false end
    for _, hive in ipairs(hc:GetChildren()) do
        local owner = hive:FindFirstChild("Owner")
        if owner and owner.Value == curLp then return true, hive end
    end
    return false
end

-- skip: таблица {["Hive3"] = true} с ульями, которые уже не получилось занять
local function findFreeHive(skip)
    local hc = workspace:FindFirstChild("Honeycombs")
    if not hc then return nil end
    for i = 6, 1, -1 do
        local hive = hc:FindFirstChild("Hive" .. i)
        if hive and not (skip and skip[hive.Name]) then
            local owner = hive:FindFirstChild("Owner")
            if owner and owner.Value == nil then
                return hive
            end
        end
    end
    return nil
end

local function pressE()
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
        task.wait(0.1)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
    end)
end

local function waitOwnership(hive, seconds)
    local t0 = tick()
    while tick() - t0 < seconds do
        if ownsHive() then return true end
        local owner = hive:FindFirstChild("Owner")
        local curLp = Players.LocalPlayer or lp
        if owner and owner.Value ~= nil and owner.Value ~= curLp then
            return false, true -- улей занял кто-то другой
        end
        task.wait(0.1)
    end
    return ownsHive()
end

-- Одна попытка занять конкретный улей. Возвращает ok, takenByOther
local function tryClaimHive(hive)
    local curLp = Players.LocalPlayer or lp
    local char = curLp and curLp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    local pos = getPosition(hive)
    if not pos then return false end

    -- Подлетаем, если далеко
    if (hrp.Position - pos).Magnitude > 15 then
        tweenTo(pos, TWEEN_SPEED, Vector3.new(0, 3, 0))
        char = curLp.Character
        hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return false end
    end

    -- Спрыгиваем на платформу сверху — так точно срабатывает касание
    hrp.CFrame = CFrame.new(pos + Vector3.new(0, 7, 0))
    task.wait(0.15)
    hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
    task.wait(0.3)

    -- Способ 1: напрямую событием игры (как делает сама игра при нажатии на улей)
    local idx = tonumber(tostring(hive.Name):match("%d+"))
    local events = ReplicatedStorage:FindFirstChild("Events")
    local claimEvent = events and events:FindFirstChild("ClaimHive")
    if claimEvent and idx then
        pcall(function() claimEvent:FireServer(idx) end)
    end
    local ok, other = waitOwnership(hive, 2)
    if ok then return true end
    if other then return false, true end

    -- Способ 2: клавиша E
    pressE()
    ok, other = waitOwnership(hive, 1.5)
    if ok then return true end
    return false, other
end

-- Занимает улей с повторными попытками: перевыбирает улей, если его занял другой игрок
local function claimHiveReliably()
    if ownsHive() then return true end
    pcall(function() workspace:WaitForChild("Honeycombs", 8) end)

    local fails = {}
    local skip = {}
    for attempt = 1, HIVE_MAX_ATTEMPTS do
        if not alive() then return false end
        if ownsHive() then return true end

        local hive = findFreeHive(skip)
        if not hive then
            setStatus("Свободных ульев нет, жду… (" .. attempt .. "/" .. HIVE_MAX_ATTEMPTS .. ")", "warn")
            task.wait(1)
        else
            setStatus(string.format("Занимаю %s (попытка %d/%d)…", tostring(hive.Name), attempt, HIVE_MAX_ATTEMPTS), "info")
            print(string.format("[Hive] Попытка %d: %s", attempt, hive.Name))
            local ok = tryClaimHive(hive)
            if ok then return true end
            fails[hive.Name] = (fails[hive.Name] or 0) + 1
            if fails[hive.Name] >= 2 then skip[hive.Name] = true end -- два провала подряд — пробуем другой улей
            task.wait(0.3)
        end
    end
    return ownsHive()
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
-- ====== АНТИ-ЛАГ (из Atlas) ======
-- ============================================================
-- НЕ трогаем то, чем пользуется сам хоппер: Honeycombs (улей), FlowerZones (поле), Monsters (Vicious),
-- Particles/WTs (WaitingThorn), а также HivePlatforms, Paths, Invisible Walls, Territories.
local ANTILAG_IGNORED_FX = {
    AquaWave = true, BeamShot = true, BeesmasLightsFallingStar = true, Bubble = true, BubbleBloatCollect = true,
    CCRocket = true, CCRocketCrosshairs = true, CCRocketCrosshairsOld = true, DiamondDrain = true, EggShield = true,
    FallingCoal = true, FallingCoconut = true, FallingSnowflake = true, FallingStar = true, FieldRectPulses = true,
    FieldStar = true, GoldenRake = true, GummyStar = true, Gummyball = true, HoneyHammer = true, InspireStar = true,
    JellyBeanToss = true, KickableCoconut = true, KickedComboCoconut = true, LocalFlames = true, MechsquitoShot = true,
    MythicMeteor = true, OrbExplode = true, PartyPopper = true, PetalShuriken = true, PluckedPetal = true, PopStar = true,
    PorcelainDipperAbility = true, PuffshroomSporeThrow = true, RectPulse = true, RingPulse = true, ScorchingStar = true,
    SnowballThrow = true, SnowflakeBreeze = true, SpotlightBeam = true, StarSaw = true, StarShowerGuide = true,
    StickerTokenBeam = true, SweepArch = true, Triangulate = true, WaterRipple = true,
}
local ANTILAG_PRECISE_FX = { LocalTargetPracticeBeam = true, PrecisionPopUp = true, ["Precise Shot"] = true }

-- Верхнеуровневые декорации workspace, которые Atlas удаляет и которые хопперу не нужны
local ANTILAG_DECO_TOP = {
    "Amulets", "Shell Amulets", "Stickbug Amulets", "BallArrowFolder", "BoostBalls", "Campsite", "ClassicMinigame",
    "Cubs", "Faces", "FieldDecos", "Frame", "Frogs", "Goo", "Leaderboards", "TheGamesEvent", "TheGames_WideBanners",
    "Bee Bear Hive", "Noob Bear", "OnettNPC", "Pro Bear", "Top Bear", "BuckoAtHQ", "RileyAtHQ", "Honey", "Lion",
}
local ANTILAG_DECO_SUB = {
    "35ZoneCave", "BubbleWandChimney", "TreatBooth", "Coconut Field", "Pepper Patch", "Pine Tree",
    "SpiderCave", "Petal Shop", "JumpGames", "PEggMaze",
}

local function safeDestroy(inst)
    if inst then pcall(function() inst:Destroy() end) end
end

local function destroyChild(parent, name)
    if parent then safeDestroy(parent:FindFirstChild(name)) end
end

local function newNoop() return function() end end

-- Хук ставится один раз: повторный запуск скрипта на том же сервере не наслаивает хуки
local function hookOnce(fn, replacement)
    if type(fn) ~= "function" or type(hookfunction) ~= "function" then return nil end
    if isfunctionhooked and isfunctionhooked(fn) then return nil end
    return hookfunction(fn, replacement)
end

local function antiLagMain()
    pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
    pcall(function()
        local t = workspace:FindFirstChildOfClass("Terrain")
        if t then
            t.WaterWaveSize, t.WaterWaveSpeed, t.WaterReflectance, t.WaterTransparency = 0, 0, 0, 0
        end
    end)
    local Lighting = game:GetService("Lighting")
    local function applyLighting()
        pcall(function()
            if Lighting.GlobalShadows ~= false then Lighting.GlobalShadows = false end
            if Lighting.FogEnd ~= 9e9 then Lighting.FogEnd = 9e9 end
            if Lighting.FogStart ~= 9e9 then Lighting.FogStart = 9e9 end
        end)
    end
    applyLighting()
    table.insert(myConns, Lighting.Changed:Connect(applyLighting)) -- игра меняет освещение по времени суток
end

local function antiLagPollenPopups()
    local ev = ReplicatedStorage:FindFirstChild("Events")
    local se = ev and ev:FindFirstChild("PlayerSettingsEvent")
    if se and se:IsA("RemoteEvent") then
        pcall(function() se:FireServer("PollenPopUps", false) end)
    end
end

local function antiLagHooks()
    local needHooks = ANTILAG.hideTokens or ANTILAG.hideParticles or ANTILAG.hidePrecise or ANTILAG.hideDuped or ANTILAG.hideMarks
    if not needHooks then return end
    if type(hookfunction) ~= "function" then
        warn("[AntiLag] hookfunction не поддерживается executor'ом — токены и эффекты не скрываются")
        return
    end
    local RS = ReplicatedStorage

    if ANTILAG.hideTokens then
        local ok, err = pcall(function()
            local m = require(RS.CollectiblesAnimator)
            hookOnce(m.Spawn, newNoop())
            hookOnce(m.AnimateCollect, newNoop())
            hookOnce(m.Destroy, newNoop())
            hookOnce(m.Update, newNoop())
            destroyChild(workspace, "Collectibles")
        end)
        if not ok then warn("[AntiLag] токены:", err) end
    end

    if ANTILAG.hideParticles or ANTILAG.hidePrecise then
        local ok, err = pcall(function()
            local fx = require(RS.LocalFX)
            local dropAll, dropPrecise = ANTILAG.hideParticles, ANTILAG.hidePrecise
            local orig
            orig = hookOnce(fx.ClientRun, function(effectName, ...)
                if (dropAll and ANTILAG_IGNORED_FX[effectName]) or (dropPrecise and ANTILAG_PRECISE_FX[effectName]) then
                    return
                end
                return orig(effectName, ...)
            end)
            if dropAll then
                hookOnce(require(RS.LocalAmulets).CreatePlayerAmulets, newNoop())
            end
        end)
        if not ok then warn("[AntiLag] эффекты:", err) end
    end

    if ANTILAG.hideDuped then
        local ok, err = pcall(function()
            local d = require(RS.DupedTokensAnimator)
            hookOnce(d.Spawn, newNoop())
            hookOnce(d.Destroy, newNoop())
            hookOnce(d.Charge, newNoop())
            hookOnce(d.Uncharge, newNoop())
            local cam = workspace.CurrentCamera
            destroyChild(cam, "DupedTokens")
        end)
        if not ok then warn("[AntiLag] дубли токенов:", err) end
    end

    if ANTILAG.hideMarks then
        local ok, err = pcall(function()
            local a = require(RS.ClientScripts.Listeners.StationsListener).Actions
            hookOnce(a.Spawn, newNoop())
            hookOnce(a.AnimDestroy, newNoop())
            destroyChild(workspace, "Stations")
        end)
        if not ok then warn("[AntiLag] метки:", err) end
    end
end

local function antiLagWorld()
    if ANTILAG.hideBees then
        pcall(function()
            local bees = workspace:FindFirstChild("Bees")
            if bees then
                for _, b in ipairs(bees:GetChildren()) do safeDestroy(b) end
                table.insert(myConns, bees.ChildAdded:Connect(function(b)
                    task.spawn(function()
                        RunService.Heartbeat:Wait()
                        safeDestroy(b)
                    end)
                end))
            end
        end)
    end
    if ANTILAG.hideFlowers then destroyChild(workspace, "Flowers") end
    if ANTILAG.hideBalloons then destroyChild(workspace:FindFirstChild("Balloons"), "FieldBalloons") end
end

local function antiLagDecorations()
    for _, name in ipairs(ANTILAG_DECO_TOP) do destroyChild(workspace, name) end

    local deco = workspace:FindFirstChild("Decorations")
    if deco then
        local misc = deco:FindFirstChild("Misc")
        if misc then
            for _, c in ipairs(misc:GetChildren()) do
                if string.find(c.Name, "Blue Flower") or c.Name == "Bamboo" or c.Name == "Bush" or c.Name == "Mushroom" then
                    safeDestroy(c)
                end
            end
        end
        for _, name in ipairs(ANTILAG_DECO_SUB) do destroyChild(deco, name) end
        for _, c in ipairs(deco:GetChildren()) do
            local n = c.Name
            if string.find(n, "Dandelion") or string.find(n, "Clover") or string.find(n, "Rose")
                or string.find(n, "Sign") or string.find(n, "Glider") or n == "ShopWord" then
                safeDestroy(c)
            end
        end
    end

    for _, c in ipairs(workspace:GetChildren()) do
        if c.ClassName == "Part" and c.CollisionGroup == "BoostBallBarrier" then safeDestroy(c) end
    end
end

local function antiLagPlayers()
    local me = Players.LocalPlayer or lp
    local function watch(plr)
        if plr == me then return end
        if plr.Character then safeDestroy(plr.Character) end
        table.insert(myConns, plr.CharacterAdded:Connect(function(c) safeDestroy(c) end))
    end
    for _, plr in ipairs(Players:GetPlayers()) do watch(plr) end
    table.insert(myConns, Players.PlayerAdded:Connect(watch))
end

local ANTILAG_PART_CLASSES = {
    BasePart = true, Part = true, WedgePart = true, TrussPart = true, UnionOperation = true, SpawnLocation = true,
}

-- Идёт порциями по кадрам, чтобы не фризить клиент; запускается в отдельном потоке и охоту не задерживает
local function antiLagTextures()
    local skipRoots = {}
    for _, name in ipairs({ "Particles", "Collectibles", "Monsters" }) do
        local r = workspace:FindFirstChild(name)
        if r then table.insert(skipRoots, r) end
    end
    local myChar = (Players.LocalPlayer or lp).Character
    if myChar then table.insert(skipRoots, myChar) end

    local function skipped(inst)
        for i = 1, #skipRoots do
            if inst:IsDescendantOf(skipRoots[i]) then return true end
        end
        return false
    end

    local n = 0
    for _, inst in ipairs(workspace:GetDescendants()) do
        n = n + 1
        if n % 1500 == 0 then
            task.wait()
            if not alive() then return end
        end
        pcall(function()
            local cls = inst.ClassName
            if ANTILAG_PART_CLASSES[cls] then
                if inst.CollisionGroup == "BoostBallBarrier" then
                    inst:Destroy()
                elseif not skipped(inst) then
                    inst.Material = Enum.Material.Plastic
                    inst.Reflectance = 0
                end
            elseif cls == "Decal" or cls == "Texture" then
                if inst.Texture ~= "rbxassetid://3581259086" and not skipped(inst) then inst:Destroy() end
            elseif cls == "ParticleEmitter" then
                if inst.Name ~= "PuffshroomSpores" and not skipped(inst) then inst:Destroy() end
            end
        end)
    end
end

local function applyAntiLag()
    if not ANTILAG_ENABLED then return end
    local t0 = tick()
    local function step(name, enabled, fn)
        if not enabled then return end
        local ok, err = pcall(fn)
        if not ok then warn("[AntiLag] " .. name .. ":", err) end
    end

    step("main", ANTILAG.main, antiLagMain)
    step("pollenPopups", ANTILAG.pollenPopups, antiLagPollenPopups)
    step("hooks", true, antiLagHooks)
    step("world", true, antiLagWorld)
    step("decorations", ANTILAG.destroyDecorations, antiLagDecorations)
    step("players", ANTILAG.hidePlayers, antiLagPlayers)
    step("ui", ANTILAG.hideBssUi, function()
        local pg = (Players.LocalPlayer or lp):FindFirstChild("PlayerGui")
        local g = pg and pg:FindFirstChild("ScreenGui")
        if g and g:IsA("ScreenGui") then g.Enabled = false end
    end)
    step("textures", ANTILAG.destroyTextures, antiLagTextures)
    print(string.format("[AntiLag] ✅ применён за %.1f с", tick() - t0))
    pcall(logMem, "после антилага")
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
    pcall(logMem, "сервер загружен")
    buildGui()
    task.spawn(applyAntiLag)
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
    local char = curLp.Character
    local tc = tick()
    while not char and (tick() - tc) < 10 do
        task.wait(0.2)
        char = curLp.Character
    end
    local hrp = char and char:WaitForChild("HumanoidRootPart", 10)
    if not hrp then
        setStatus("Персонаж не загрузился — меняю сервер", "warn")
        hopToRandomServer()
        return
    end

    -- 3. Занятие улья (с повторными попытками)
    print("[Hunt] Занимаем улей...")
    setStatus("Занимаю улей…", "info")
    if not claimHiveReliably() then
        print("[Hunt] ❌ Улей занять не удалось — ХОП")
        setStatus("Улей не занят — меняю сервер", "warn")
        hopToRandomServer()
        return
    end
    print("[Hunt] ✅ Улей успешно занят!")
    setStatus("Улей занят", "ok")

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

-- Сторож загрузки: если игра так и не прогрузилась — хопаем (повтор каждые 20 сек, пока не уйдём)
task.spawn(function()
    local t0 = tick()
    while alive() and not gameReady do
        task.wait(1)
        if not gameReady and tick() - t0 > LOAD_TIMEOUT + 5 then
            warn("[LoadWatchdog] Игра не прогрузилась — принудительный хоп")
            setStatus("Игра не прогрузилась — меняю сервер", "warn")
            t0 = tick() - (LOAD_TIMEOUT + 5 - 20)
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

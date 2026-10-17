-- ====== SERVICES ======
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

-- ====== ХОП ======
getgenv().VisitedServers = getgenv().VisitedServers or {}

local function hopToRandomServer()
    task.wait(0.9)
    if not player or not player.Parent then return end

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
            local alreadyVisited = false
            for _, visitedId in ipairs(getgenv().VisitedServers) do
                if visitedId == server.id then
                    alreadyVisited = true
                    break
                end
            end
            if not alreadyVisited then
                table.insert(candidates, server)
            end
        end
    end

    while #getgenv().VisitedServers > 150 do
        table.remove(getgenv().VisitedServers, 1)
    end

    if #candidates == 0 then
        TeleportService:Teleport(game.PlaceId, player)
        return
    end

    local chosen = candidates[math.random(#candidates)]
    table.insert(getgenv().VisitedServers, chosen.id)

    TeleportService:TeleportToPlaceInstance(game.PlaceId, chosen.id, player)
end

-- ====== ПОИСК ======
local function findViciousBee()
    local monsters = workspace:FindFirstChild("Monsters")
    if not monsters then return nil end
    for _, obj in ipairs(monsters:GetChildren()) do
        if obj.Name:find("Vicious Bee", 1, true) then
            local humanoid = obj:FindFirstChild("Humanoid")
            if humanoid and humanoid.Health > 0 then return obj end
        end
    end
    return nil
end

local function findMondoChick()
    local monsters = workspace:FindFirstChild("Monsters")
    if not monsters then return nil end
    for _, obj in ipairs(monsters:GetChildren()) do
        if obj.Name:find("Mondo Chick", 1, true) then
            local humanoid = obj:FindFirstChild("Humanoid")
            if humanoid and humanoid.Health > 0 then return obj end
        end
    end
    return nil
end

local function isViciousBeeNearMondo(bee)
    local mondo = findMondoChick()
    if not mondo then return false end
    return (bee:GetPivot().Position - mondo:GetPivot().Position).Magnitude < 200
end

-- ====== УЛЕЙ ======
local function findFreeHive()
    local honeycombs = workspace:FindFirstChild("Honeycombs")
    if not honeycombs then return nil end

    local freeHive = nil

    for i = 1, 6 do
        local hive = honeycombs:FindFirstChild("Hive" .. i)
        if hive then
            local owner = hive:FindFirstChild("Owner")
            local v = owner and owner.Value
            
            -- Приоритет 1: наш улей
            if v == player then
                print("[Hunt] ✅ Улей уже наш:", hive.Name)
                return hive
            end
            
            -- Приоритет 2: первый свободный
            if not freeHive and (not v or not v:IsA("Player") or not v.Parent) then
                freeHive = hive
            end
        end
    end
    
    if freeHive then
        print("[Hunt] ✅ Свободный улей:", freeHive.Name)
        return freeHive
    end
    
    print("[Hunt] ❌ Свободных ульев нет")
    return nil
end

-- ====== FLY ======
local function flyTo(target, offset)
    local success, result = pcall(function()
            local char = player.Character
        if not char then return false end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp or not target then return false end

        offset = offset or Vector3.new(0, 3, 0)
        local targetPos = target:IsA("Model") and (target.PrimaryPart and target.PrimaryPart.Position or target:GetPivot().Position) or target.Position
        targetPos = targetPos + offset

        local originalCollides = {}
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                originalCollides[part] = part.CanCollide
                part.CanCollide = false
            end
        end

        local bv = Instance.new("BodyVelocity")
        bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        bv.P = 2000
        bv.Parent = hrp

        local look = hrp.CFrame.LookVector
        if look.Magnitude < 0.1 then look = Vector3.new(0,0,-1) end
        local originalRot = CFrame.new(Vector3.zero, look)
        local startTime = tick()
        local connection

        connection = RunService.Heartbeat:Connect(function()
            if tick() - startTime > 3 then
                if connection then connection:Disconnect() end
                return
            end
            if not hrp or not hrp.Parent or hrp.Parent ~= char then
                if connection then connection:Disconnect() end
                return
            end
            
            local distance = (hrp.Position - targetPos).Magnitude
            if distance < 5 then
                bv.Velocity = Vector3.zero
                if connection then connection:Disconnect() end
                return
            end
            local direction = (targetPos - hrp.Position).Unit
            local speed = 500
            if distance < 30 then speed = 250 end
            if distance < 15 then speed = 100 end
            if distance < 8 then speed = 50 end
            bv.Velocity = direction * speed
            hrp.CFrame = CFrame.new(hrp.Position) * originalRot
        end)

        local waitStart = tick()
        while connection.Connected and tick() - waitStart < 4 do
            task.wait(0.05)
        end
        if connection.Connected then connection:Disconnect() end
        if bv and bv.Parent then bv:Destroy() end

        if hrp and hrp.Parent then
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end

        for part, collide in pairs(originalCollides) do
            if part and part.Parent then part.CanCollide = collide end
        end

        if not hrp or not hrp.Parent then return false end
        return (hrp.Position - targetPos).Magnitude < 15
    end)
    
    if not success then
        print("[Fly] ❌ ОШИБКА:", result)
        return false
    end
    return result
end

-- ====== НАЖАТИЕ E ======
local function pressE(hive)
    local prompt = hive and hive:FindFirstChildOfClass("ProximityPrompt")
    if prompt and fireproximityprompt then
        pcall(function() fireproximityprompt(prompt) end)
    else
        pcall(function() VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game) end)
        task.wait(0.05)
        pcall(function() VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game) end)
    end
end

-- ====== МАНСИНГ ======
local function startMansing(bee)
    local running = true
    local connection
    local isFlying = false
    local radius = 50
    local speed = 70

    task.spawn(function()
        local angle = 0
        
        local startChar = player.Character
        if startChar and bee then
            local h = startChar:FindFirstChild("HumanoidRootPart")
            local b = bee:FindFirstChild("HumanoidRootPart")
            if h and b then
                local v = h.Position - b.Position
                if v.Magnitude > 1 then
                    angle = math.atan2(v.Z, v.X)
                end
            end
        end
            connection = RunService.RenderStepped:Connect(function(dt)
            if not running or isFlying then return end
            dt = math.min(dt, 0.05)

            local char = player.Character
            if not char then return end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if not hrp or not humanoid then return end
            
            if humanoid.WalkSpeed ~= 0 then 
                humanoid.WalkSpeed = 0 
            end

            if not bee or not bee.Parent then running = false return end
            local beeHrp = bee:FindFirstChild("HumanoidRootPart")
            if not beeHrp then return end

            local toChar = hrp.Position - beeHrp.Position
            toChar = Vector3.new(toChar.X, 0, toChar.Z)
            local curR = toChar.Magnitude
            if curR < 1 then toChar = Vector3.new(1,0,0) curR = 1 end
            local radial = toChar.Unit

            local distToBee = (hrp.Position - beeHrp.Position).Magnitude
            if distToBee > 100 then
                isFlying = true
                task.spawn(function()
                    local ok = flyTo(bee, Vector3.new(0, 5, 0))
                    isFlying = false
                    
                    -- 🔥 ФИКС 10/10: Сразу задаем правильный угол после телепорта
                    if ok then
                        local h = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                        local b = bee and bee:FindFirstChild("HumanoidRootPart")
                        if h and b then
                            local v = h.Position - b.Position
                            if v.Magnitude > 1 then
                                angle = math.atan2(v.Z, v.X)
                            else
                                angle = 0
                            end
                        else
                            angle = 0
                        end
                    else
                        running = false
                    end
                end)
                return
            end

            local tangent = Vector3.new(-radial.Z, 0, radial.X)
            local radialError = radius - curR
            local radialVel = radial * math.clamp(radialError * 4, -150, 150)

            local newPos = hrp.Position + (tangent * speed + radialVel) * dt
            hrp.CFrame = CFrame.new(newPos, newPos + tangent)
        end)
    end)

    return function()
        running = false
        if connection then connection:Disconnect() end
        local c = player.Character
        if c and c:FindFirstChildOfClass("Humanoid") then
            c.Humanoid.WalkSpeed = 16
        end
    end
end

-- ====== ОСНОВНАЯ ЛОГИКА ======
local function huntViciousBee()
    print("[Hunt] === НОВЫЙ СЕРВЕР ===")
    task.wait(2)

    local t = 0
    while not workspace:FindFirstChild("Monsters") and t < 10 do
        task.wait(0.5) t = t + 0.5
    end

    local bee = findViciousBee()
    if not bee then
        print("[Hunt] ❌ Пчела не найдена. Хоп...")
        hopToRandomServer() return
    end
    print("[Hunt] ✅ Пчела найдена:", bee.Name)

    if isViciousBeeNearMondo(bee) then
        print("[Hunt] ⚠️ Пчела на горе. Хоп...")
        hopToRandomServer() return
    end

    local hive = findFreeHive()
    if not hive then
        print("[Hunt] ❌ Улей не найден. Хоп...")
        hopToRandomServer() return
    end

    local char = player.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then
        task.wait(2) char = player.Character
    end
    if not char then hopToRandomServer() return end

    -- Fly к улью
    local platform = hive:FindFirstChild("Platform")
    local target = (platform and platform.Value) and platform.Value or hive
    print("[Hunt] Fly к улью:", hive.Name)
    
    local flyOk = flyTo(target, Vector3.new(0, 3, 0))
    if not flyOk then
        print("[Hunt] ❌ Не долетели до улья. Хоп...")
        hopToRandomServer() return
    end
    task.wait(0.5)

    -- Нажимаем E с ретраями
    local tries = 0
    local claimed = false
    while tries < 3 do
        pressE(hive)
        task.wait(1.2)
        local o = hive:FindFirstChild("Owner")
        if o and o.Value == player then
            claimed = true
            break
        end
        tries = tries + 1
    end

    if claimed then
        print("[Hunt] ✅ Улей занят:", hive.Name)
    else
        print("[Hunt] ❌ Улей не засчитан. Хоп...")
        hopToRandomServer() return
    end

    if not bee.Parent then
        print("[Hunt] ⚠️ Пчела умерла, пока занимали улей. Хоп...")
        hopToRandomServer() return
    end

    -- Fly к пчеле
    print("[Hunt] Fly к пчеле...")
    local okBee = flyTo(bee, Vector3.new(0, 5, 15))
    if not okBee then
        print("[Hunt] ❌ Не долетели до пчелы. Хоп...")
        hopToRandomServer() return
    end
    task.wait(0.3)

    -- Мансинг
    print("[Hunt] Мансинг...")
    local stopMansing = startMansing(bee)

    local maxWait = 120 -- Увеличенное время ожидания
    
    pcall(function()
        local waited = 0
        while waited < maxWait do
            task.wait(0.3) waited = waited + 0.3
            local humanoid = bee:FindFirstChild("Humanoid")
            if not bee.Parent or not humanoid or humanoid.Health <= 0 then
                print("[Hunt] ✅ Пчела убита! Хоп...")
                break
            end
        end
    end)

    if stopMansing then stopMansing() end
    hopToRandomServer()
end

-- ====== БЕСКОНЕЧНЫЙ ЦИКЛ ======
task.wait(5)
while true do
    pcall(huntViciousBee)
    task.wait(1.5)
end

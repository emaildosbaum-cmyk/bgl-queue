-- =========================================================
-- Blox Fruits Auto-Buyer (Unified Script - Full Version)
-- Combines: scroll search + buy GUI + TikTok bridge + Offline Support
-- Correções incluídas:
-- 1. Funciona 100% offline (sem servidor) e com servidor
-- 2. Desconto real de Robux a cada compra e persistência
-- 3. Nome do player capturado diretamente do botão da lista
-- 4. Nome da fruta capturado diretamente da nossa Buy GUI
-- 5. Notificações nativas no topo com RichText formatado
-- 6. Fallback de duplo ESC, Clique no GlobalButton e Botão Cancel
-- =========================================================

repeat task.wait() until game:IsLoaded()

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local ContentProvider = game:GetService("ContentProvider")
local CoreGui = pcall(function() return game:GetService("CoreGui") end) and game:GetService("CoreGui") or nil
local TextChatService = pcall(function() return game:GetService("TextChatService") end) and game:GetService("TextChatService") or nil

local player = Players.LocalPlayer or Players.PlayerAdded:Wait()
local playerGui = player:WaitForChild("PlayerGui")

---------------------------------------------------------
-- AUTO-REJOIN EM SERVIDOR ALEATÓRIO (SEM ANTI-AFK)
---------------------------------------------------------
local autoRejoining = false

local function performAutoRejoin(reason)
    if autoRejoining then return end
    autoRejoining = true
    warn("[Safe.lua Auto-Rejoin] Desconexão detectada (" .. tostring(reason) .. "). Reconectando em servidor público aleatório...")

    pcall(function()
        local StarterGui = game:GetService("StarterGui")
        StarterGui:SetCore("SendNotification", {
            Title = "Auto-Rejoin",
            Text = "Conexão perdida! Reconectando a um novo servidor...",
            Duration = 5
        })
    end)

    task.wait(2.5)

    local function tryTeleportRandomServer()
        local placeId = game.PlaceId
        local success = false

        pcall(function()
            local serversUrl = string.format("https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Desc&limit=100", tostring(placeId))
            local response = nil
            if typeof(request) == "function" then
                response = request({ Url = serversUrl, Method = "GET" })
            elseif typeof(http_request) == "function" then
                response = http_request({ Url = serversUrl, Method = "GET" })
            elseif syn and typeof(syn.request) == "function" then
                response = syn.request({ Url = serversUrl, Method = "GET" })
            end

            if response and response.Body then
                local data = HttpService:JSONDecode(response.Body)
                if data and data.data and #data.data > 0 then
                    local validServers = {}
                    for _, s in ipairs(data.data) do
                        if s.playing and s.maxPlayers and s.playing < s.maxPlayers and s.id ~= game.JobId then
                            table.insert(validServers, s.id)
                        end
                    end
                    if #validServers > 0 then
                        local randomJobId = validServers[math.random(1, #validServers)]
                        TeleportService:TeleportToPlaceInstance(placeId, randomJobId, player)
                        success = true
                    end
                end
            end
        end)

        if not success then
            pcall(function()
                TeleportService:Teleport(placeId, player)
            end)
        end
    end

    while true do
        tryTeleportRandomServer()
        task.wait(5)
    end
end

-- Monitora evento de erro de desconexão do GuiService
pcall(function()
    GuiService.ErrorMessageChanged:Connect(function(errorMessage)
        if errorMessage and #errorMessage > 0 then
            performAutoRejoin("GuiService Error: " .. tostring(errorMessage))
        end
    end)
end)

-- Monitora prompt nativo de desconexão da RobloxPromptGui
pcall(function()
    if CoreGui and CoreGui:FindFirstChild("RobloxPromptGui") then
        local promptOverlay = CoreGui.RobloxPromptGui:FindFirstChild("promptOverlay")
        if promptOverlay then
            promptOverlay.ChildAdded:Connect(function(child)
                if child.Name == "ErrorPrompt" then
                    performAutoRejoin("ErrorPrompt Detected")
                end
            end)
            if promptOverlay:FindFirstChild("ErrorPrompt") then
                performAutoRejoin("ErrorPrompt Already Present")
            end
        end
    end
end)

---------------------------------------------------------
-- PROVA DE LIVE (ANTI-GRAVAÇÃO / MOVIMENTO, DASH, PULO, ZOOM E CHAT LOCAL)
---------------------------------------------------------
local liveProofRunning = false

local function sendLocalChatMessage(msg)
    if not msg or msg == "" then return end
    pcall(function()
        local playerName = player.DisplayName or player.Name
        -- 1. TextChatService DisplaySystemMessage (Só aparece na SUA tela / live do TikTok, ninguém do server vê!)
        if TextChatService and TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
            local textChannels = TextChatService:FindFirstChild("TextChannels")
            local rbxGeneral = textChannels and textChannels:FindFirstChild("RBXGeneral")
            if rbxGeneral then
                local formattedMsg = string.format("<font color='#FFFFFF'><b>[%s]:</b> %s</font>", playerName, msg)
                rbxGeneral:DisplaySystemMessage(formattedMsg)
                return
            end
        end
        -- 2. Fallback StarterGui SetCore (Chat Legado só pra mim)
        local StarterGui = game:GetService("StarterGui")
        StarterGui:SetCore("ChatMakeSystemMessage", {
            Text = "[" .. playerName .. "]: " .. msg,
            Color = Color3.fromRGB(255, 255, 255),
            Font = Enum.Font.SourceSansBold,
            FontSize = Enum.FontSize.Size18
        })
    end)
end

local function triggerDashQ()
    pcall(function()
        local VIM = game:GetService("VirtualInputManager")
        if VIM then
            VIM:SendKeyEvent(true, Enum.KeyCode.Q, false, game)
            task.wait(0.04)
            VIM:SendKeyEvent(false, Enum.KeyCode.Q, false, game)
        elseif keypress and keyrelease then
            keypress(0x51) -- KeyCode Q
            task.wait(0.04)
            keyrelease(0x51)
        end
    end)
end

local function performLiveProof(duration, message)
    if liveProofRunning then return end
    liveProofRunning = true
    
    -- Mensagem do chat com TextChatService só visível localmente na tela
    if message and message ~= "" then
        sendLocalChatMessage(message)
    end
    
    task.spawn(function()
        local character = player.Character or player.CharacterAdded:Wait()
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        local camera = workspace.CurrentCamera
        local originalFov = camera and camera.FieldOfView or 70
        
        local durationSec = tonumber(duration) or 4
        durationSec = math.clamp(durationSec, 2, 12)
        
        -- Efeito dinâmico de Zoom in e Zoom out na câmera
        local zoomActive = true
        task.spawn(function()
            local TweenService = game:GetService("TweenService")
            while zoomActive and camera do
                local targetFov = (math.random(1, 2) == 1) and math.random(36, 48) or math.random(76, 90)
                local tweenTime = math.random(25, 55) / 100 -- 0.25s a 0.55s
                pcall(function()
                    local tween = TweenService:Create(camera, TweenInfo.new(tweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = targetFov })
                    tween:Play()
                    tween.Completed:Wait()
                end)
                task.wait(math.random(2, 5) / 10)
            end
            -- Restaura FOV original
            if camera then
                pcall(function()
                    local tween = TweenService:Create(camera, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = originalFov })
                    tween:Play()
                end)
            end
        end)
        
        if humanoid and hrp then
            local center = hrp.Position
            local radius = 6
            local startTime = os.clock()
            local lastJump = os.clock()
            local lastDash = os.clock()
            local angle = 0
            
            while (os.clock() - startTime) < durationSec do
                angle = angle + 0.45
                local targetOffset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
                local targetPos = center + targetOffset
                
                humanoid:MoveTo(targetPos)
                
                -- Pulos aleatórios (~0.8s a 1.2s)
                if (os.clock() - lastJump) > (0.75 + math.random() * 0.45) then
                    humanoid.Jump = true
                    lastJump = os.clock()
                end
                
                -- Dash apertando Q aleatoriamente (~0.7s a 1.1s)
                if (os.clock() - lastDash) > (0.65 + math.random() * 0.45) then
                    triggerDashQ()
                    lastDash = os.clock()
                end
                
                task.wait(0.07)
            end
            
            if hrp then
                humanoid:MoveTo(hrp.Position)
            end
        else
            task.wait(durationSec)
        end
        
        zoomActive = false
        task.wait(0.4)
        if camera then
            camera.FieldOfView = originalFov
        end
        
        liveProofRunning = false
    end)
end

---------------------------------------------------------
-- CONFIGURAÇÕES E DICIONÁRIO DE PREÇOS
---------------------------------------------------------
local FRUIT_PRICES = {
    ["rocket"] = 50, ["spin"] = 75, ["blade"] = 100, ["chop"] = 100,
    ["spring"] = 180, ["bomb"] = 220, ["smoke"] = 250, ["spike"] = 380,
    ["flame"] = 550, ["falcon"] = 650, ["ice"] = 750, ["sand"] = 850,
    ["dark"] = 950, ["diamond"] = 1000, ["light"] = 1100, ["rubber"] = 1200,
    ["barrier"] = 1250, ["ghost"] = 1275, ["magma"] = 1300, ["quake"] = 1500,
    ["buddha"] = 1650, ["love"] = 1700, ["spider"] = 1800, ["sound"] = 1900,
    ["phoenix"] = 2000, ["portal"] = 2000, ["rumble"] = 2100, ["pain"] = 2200,
    ["blizzard"] = 2250, ["gravity"] = 2300, ["mammoth"] = 2350, ["t-rex"] = 2350,
    ["dough"] = 2400, ["shadow"] = 2425, ["venom"] = 2450, ["control"] = 2500,
    ["spirit"] = 2550, ["dragon"] = 2600, ["leopard"] = 3000, ["kitsune"] = 4000,
    ["gas"] = 2500, ["yeti"] = 3000, ["magnet"] = 3500,
    -- Chromatic Boxes (Loja Blox Fruits / Developer Products)
    ["x1 chromatic box"] = 199, ["x3 chromatic box"] = 575, ["x10 chromatic box"] = 1699,
    ["chromatic box"] = 199, ["chromatic box x1"] = 199, ["chromatic box x3"] = 575, ["chromatic box x10"] = 1699,
    ["1518"] = 199, ["1519"] = 575, ["1520"] = 1699,
    -- Gamepasses
    ["2x mastery"] = 350, ["2x money"] = 450, ["fast boats"] = 350,
    ["2x boss drops"] = 350, ["dark blade"] = 1200, ["fruit notifier"] = 275
}

local currentSettings = {
    mock_balance = "5,420",
    item_name = "Rocket",
    item_price = "50",
    item_image = "rbxassetid://16335379958",
    toggle_key = "P",
    step_timeouts = {
        total = 30
    }
}

local function saveConfig()
    if writefile then
        pcall(function()
            writefile("buy_gui_config.json", HttpService:JSONEncode(currentSettings))
        end)
    end
end

local function loadConfig()
    if readfile and isfile and isfile("buy_gui_config.json") then
        local success, content = pcall(readfile, "buy_gui_config.json")
        if success and content then
            local decodedSuccess, decoded = pcall(function()
                return HttpService:JSONDecode(content)
            end)
            if decodedSuccess and decoded then
                for k, v in pairs(decoded) do
                    currentSettings[k] = v
                end
                -- Sanitização: nunca manter gamepass ou chromatic box persistido como item padrão
                if currentSettings.item_name then
                    local s = tostring(currentSettings.item_name):lower()
                    if s:find("mastery") or s:find("money") or s:find("boat") or s:find("blade") or s:find("notifier") or s:find("boss") or s:find("chromatic") or s:find("box") then
                        currentSettings.item_name = "Rocket"
                        currentSettings.item_price = "50"
                    end
                end
            end
        end
    end
end
pcall(loadConfig)

local GENERIC_ITEM_NAME = currentSettings.item_name
local GENERIC_ITEM_PRICE = currentSettings.item_price
local GENERIC_ITEM_IMAGE = currentSettings.item_image
local MOCK_BALANCE = currentSettings.mock_balance

local ALLOWED_FRUITS = { "Magma", "Buddha", "Quake" }

---------------------------------------------------------
-- CONFIGURAÇÃO DE INSTÂNCIA UNIVERSAL (INFINITOS AMIGOS/CONTAS)
-- Cada instância conecta no seu próprio servidor sem NENHUM conflito:
-- Instância 1: HTTP 8083 | WebSocket 8765 (Padrão)
-- Instância 2: HTTP 8084 | WebSocket 8766
-- Instância 3: HTTP 8085 | WebSocket 8767
-- Instância N: HTTP 8083+(N-1) | WebSocket 8765+(N-1)
---------------------------------------------------------
local currentInstance = 1

-- 1. Verifica se foi definido globalmente antes de executar (ex: getgenv().BRIDGE_INSTANCE = 3)
if getgenv and getgenv().BRIDGE_INSTANCE and tonumber(getgenv().BRIDGE_INSTANCE) then
    currentInstance = math.max(1, math.floor(tonumber(getgenv().BRIDGE_INSTANCE)))
-- 2. Ou se foi salvo no arquivo local bridge_instance.txt
elseif readfile and isfile and isfile("bridge_instance.txt") then
    local sInst, content = pcall(readfile, "bridge_instance.txt")
    if sInst and content and tonumber(content) then
        local savedNum = tonumber(content)
        if savedNum and savedNum >= 1 then
            currentInstance = math.floor(savedNum)
        end
    end
end

-- =========================================================
-- SISTEMA MULTI-TENANT BGL QUEUE (PLAYER 1 / PLAYER 2)
-- =========================================================
local SCRIPT_TOKEN = _G.BGL_TOKEN or "SEU_TOKEN_AQUI" -- Cole o token gerado no site https://bgl-queue.vercel.app
pcall(function()
    if (not SCRIPT_TOKEN or SCRIPT_TOKEN == "SEU_TOKEN_AQUI") and readfile and isfile and isfile("bgl_token.txt") then
        local t = readfile("bgl_token.txt")
        if t and t:match("%S+") then SCRIPT_TOKEN = t:gsub("%s+", "") end
    end
end)

local HTTP_PORT = 8083 + (currentInstance - 1)
local WS_PORT = 8765 + (currentInstance - 1)
local BASE_URL = "http://127.0.0.1:" .. HTTP_PORT
local WS_URL = "ws://localhost:" .. WS_PORT

local CLOUD_SERVER_URL = "https://bgl-queue-server.onrender.com"
local CLOUD_WS_URL = "wss://bgl-queue-server.onrender.com"
local VERCEL_API_URL = "https://bgl-queue.vercel.app"

local function getTokenQuery()
    return (SCRIPT_TOKEN and SCRIPT_TOKEN ~= "" and SCRIPT_TOKEN ~= "SEU_TOKEN_AQUI") and ("?token=" .. SCRIPT_TOKEN) or ""
end

local function sanitizeToken(raw)
    if not raw then return "" end
    local clean = tostring(raw):gsub('^%s*["\']?', ''):gsub('["\']?%s*$', ''):gsub("%s+", "")
    if clean:find("token=") then
        clean = clean:match("token=([^&%s]+)") or clean
    elseif clean:find("uid=") then
        clean = clean:match("uid=([^&%s]+)") or clean
    end
    return clean:gsub('^["\']', ''):gsub('["\']$', '')
end

local function universalHttpRequest(url, method, body, headers)
    method = (method or "GET"):upper()
    headers = headers or {}
    if method == "POST" and not headers["Content-Type"] and not headers["content-type"] then
        headers["Content-Type"] = "application/json"
    end
    
    -- 1. Executores modernos: busca por request / http_request / syn.request / http.request / fluxus.request
    local genv = (getgenv and type(getgenv) == "function") and getgenv() or _G or {}
    local req = (type(request) == "function" and request)
        or (type(http_request) == "function" and http_request)
        or (type(genv.request) == "function" and genv.request)
        or (type(genv.http_request) == "function" and genv.http_request)
        or (syn and type(syn.request) == "function" and syn.request)
        or (http and type(http.request) == "function" and http.request)
        or (fluxus and type(fluxus.request) == "function" and fluxus.request)
        
    if req then
        local reqData = {
            Url = url,
            url = url,
            Method = method,
            method = method,
            Headers = headers,
            headers = headers
        }
        if body then
            reqData.Body = body
            reqData.body = body
        end
        
        local ok, res = pcall(req, reqData)
        if ok and res then
            if type(res) == "string" then
                return true, res, 200
            elseif type(res) == "table" then
                local resBody = res.Body or res.body or res.Data or res.data or ""
                local statusCode = tonumber(res.StatusCode or res.status_code or res.statusCode) or 200
                return (statusCode >= 200 and statusCode < 300), tostring(resBody), statusCode
            end
        end
    end
    
    -- 2. Métodos nativos de executor game:HttpGet / game:HttpGetAsync
    if method == "GET" then
        local getOk, getRes = pcall(function() return game:HttpGet(url) end)
        if getOk and getRes and type(getRes) == "string" then
            return true, getRes, 200
        end
        local getAsyncOk, getAsyncRes = pcall(function() return game:HttpGetAsync(url) end)
        if getAsyncOk and getAsyncRes and type(getAsyncRes) == "string" then
            return true, getAsyncRes, 200
        end
    end
    
    -- 3. Fallback POST para executores com suporte apenas a HttpGet
    if method == "POST" then
        local getOk, getRes = pcall(function() return game:HttpGet(url) end)
        if getOk and getRes and type(getRes) == "string" then
            return true, getRes, 200
        end
    end
    
    -- 4. Fallback HttpService (Roblox Studio ou servidor local 127.0.0.1)
    local hsOk, hsRes = pcall(function()
        if method == "GET" then
            return HttpService:GetAsync(url, true)
        else
            return HttpService:PostAsync(url, body or "", Enum.HttpContentType.ApplicationJson)
        end
    end)
    if hsOk and hsRes then
        return true, tostring(hsRes), 200
    end
    
    return false, "Nenhum método HTTP disponível ou conexão recusada", 0
end

local isRobloxAccountLocked = false
local function verifyAndLinkRobloxAccount(token)
    if not token or token == "" or token == "SEU_TOKEN_AQUI" then return true end
    local clean = sanitizeToken(token)
    local localPlayer = Players.LocalPlayer
    if not localPlayer then return true end
    
    local robloxUserId = tostring(localPlayer.UserId)
    local robloxUsername = tostring(localPlayer.Name)
    local robloxDisplayName = tostring(localPlayer.DisplayName)
    local robloxAvatar = "https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds=" .. robloxUserId .. "&size=150x150&format=Png&isCircular=true"
    
    local queryParams = string.format("?token=%s&roblox_user_id=%s&roblox_username=%s&roblox_display_name=%s&roblox_avatar_url=%s",
        HttpService:UrlEncode(clean),
        HttpService:UrlEncode(robloxUserId),
        HttpService:UrlEncode(robloxUsername),
        HttpService:UrlEncode(robloxDisplayName),
        HttpService:UrlEncode(robloxAvatar)
    )
    local linkUrl = VERCEL_API_URL .. "/api/script/link_roblox" .. queryParams
    local linkBody = HttpService:JSONEncode({
        token = clean,
        roblox_user_id = robloxUserId,
        roblox_username = robloxUsername,
        roblox_display_name = robloxDisplayName,
        roblox_avatar_url = robloxAvatar
    })
    
    local ok, res, statusCode = universalHttpRequest(linkUrl, "POST", linkBody)
    if res and res ~= "" then
        local decOk, decoded = pcall(function() return HttpService:JSONDecode(res) end)
        if decOk and decoded then
            if decoded.locked then
                isRobloxAccountLocked = true
                warn("[AutoBuyer] CHAVE BLOQUEADA: " .. tostring(decoded.error))
                pcall(function()
                    sendLocalChatMessage("⚠️ [BGL Queue] " .. tostring(decoded.error))
                end)
                return false, decoded.error
            end
            if decoded.ok then
                isRobloxAccountLocked = false
                print("[AutoBuyer] Conta Roblox @" .. robloxUsername .. " (" .. robloxDisplayName .. ") vinculada com sucesso!")
                return true
            end
        end
    end
    return true
end

local heartbeatRunning = false
local function startRobloxHeartbeat()
    if heartbeatRunning then return end
    heartbeatRunning = true
    task.spawn(function()
        while true do
            if SCRIPT_TOKEN and SCRIPT_TOKEN ~= "" and SCRIPT_TOKEN ~= "SEU_TOKEN_AQUI" and not isRobloxAccountLocked then
                pcall(function()
                    local hbUrl = VERCEL_API_URL .. "/api/script/heartbeat?token=" .. HttpService:UrlEncode(SCRIPT_TOKEN) .. "&source=roblox"
                    universalHttpRequest(hbUrl, "GET")
                end)
            end
            task.wait(15)
        end
    end)
end

local function updateInstancePorts(instNum)
    local num = tonumber(instNum)
    if not num or num < 1 then return false end
    currentInstance = math.floor(num)
    HTTP_PORT = 8083 + (currentInstance - 1)
    WS_PORT = 8765 + (currentInstance - 1)
    BASE_URL = "http://127.0.0.1:" .. HTTP_PORT
    WS_URL = "ws://localhost:" .. WS_PORT
    
    if writefile then
        pcall(function()
            writefile("bridge_instance.txt", tostring(currentInstance))
        end)
    end
    print(string.format("[AutoBuyer] Instância configurada para #%d (HTTP: %d | WS: %d)", currentInstance, HTTP_PORT, WS_PORT))
    return true
end

local activeWS = nil

-- Variáveis globais para rastrear alvo e fruta atuais
local activeTargetPlayer = ""
local currentBuyItemId = 0
local activeTargetFruit = ""
local selectedPlayerName = ""
local searchBoxPlayerName = "" -- nome lido direto da SearchBox do jogo (prioridade máxima)

-- Forward declarations para Watchdog
local closeGui
local closeSuccessGui
local openSuccessGui

---------------------------------------------------------
-- LOGSTEP (silenciado por padrão para não poluir console)
---------------------------------------------------------
local DEBUG_LOGS = false
local function logStep(msg)
    if DEBUG_LOGS then
        print("[WD] " .. tostring(msg))
    end
end

---------------------------------------------------------
-- WATCHDOG: abortCurrentBuy
---------------------------------------------------------
local watchdogAborted = false
local function abortCurrentBuy(reason)
    warn("[Watchdog] ABORT: " .. tostring(reason))
    watchdogAborted = true
    
    -- Tenta fechar todas as GUIs abertas
    pcall(function()
        if closeGui then closeGui() end
    end)
    pcall(function()
        if closeSuccessGui then closeSuccessGui() end
    end)
    
    -- Tenta clicar Cancel na GiftWindow ou duplo ESC
    pcall(function()
        local pg = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
        local gw = pg:FindFirstChild("GiftWindow")
        local cancelBtn = gw and gw:FindFirstChild("Cancel", true)
        if cancelBtn and cancelBtn:IsA("GuiButton") and cancelBtn.Visible then
            cancelBtn:SetAttribute("__wdclick", true)
            -- Simula o clique via fire
            pcall(function()
                local vim = game:GetService("VirtualInputManager")
                vim:SendKeyEvent(true, Enum.KeyCode.Escape, false, game)
                task.wait(0.04)
                vim:SendKeyEvent(false, Enum.KeyCode.Escape, false, game)
                task.wait(0.05)
                vim:SendKeyEvent(true, Enum.KeyCode.Escape, false, game)
                task.wait(0.04)
                vim:SendKeyEvent(false, Enum.KeyCode.Escape, false, game)
            end)
        else
            local vim = game:GetService("VirtualInputManager")
            vim:SendKeyEvent(true, Enum.KeyCode.Escape, false, game)
            task.wait(0.04)
            vim:SendKeyEvent(false, Enum.KeyCode.Escape, false, game)
            task.wait(0.05)
            vim:SendKeyEvent(true, Enum.KeyCode.Escape, false, game)
            task.wait(0.04)
            vim:SendKeyEvent(false, Enum.KeyCode.Escape, false, game)
        end
    end)
    
    -- Notifica o servidor e a nuvem que abortou
    reportPurchaseFinished("aborted", reason)
end

---------------------------------------------------------
-- UTILITÁRIOS DE FORMATAÇÃO E NÚMEROS
---------------------------------------------------------
local function formatNumber(val)
    if not val then return "0" end
    local isNegative = tostring(val):sub(1,1) == "-"
    local clean = tostring(val):gsub("%D", "")
    if clean == "" then return "0" end
    if isNegative then clean = "-" .. clean end
    
    local formatted = clean
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then
            break
        end
    end
    return formatted
end

local function parseNumber(val)
    if not val then return 0 end
    local clean = tostring(val):gsub("%D", "")
    return tonumber(clean) or 0
end

local function FixZIndex(gui)
    for _, v in ipairs(gui:GetDescendants()) do
        if v:IsA("GuiObject") and v.Name ~= "Overlay" then
            v.ZIndex = math.max(v.ZIndex, 3)
        end
    end
end

local function createCloseIcon(parent, size)
    local btn = Instance.new("TextButton")
    btn.Name = "CloseButton"
    btn.Size = UDim2.new(0, size, 0, size)
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.ZIndex = 10
    btn.Parent = parent

    local bg = Instance.new("Frame")
    bg.Name = "CloseBg"
    bg.Size = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    bg.BackgroundTransparency = 1
    bg.BorderSizePixel = 0
    bg.ZIndex = 9
    bg.Parent = btn

    bgCorner = Instance.new("UICorner")
    bgCorner.CornerRadius = UDim.new(1, 0)
    bgCorner.Parent = bg

    local bar1 = Instance.new("Frame")
    bar1.Name = "Bar1"
    bar1.Size = UDim2.new(0, size * 0.54, 0, 2)
    bar1.Position = UDim2.new(0.5, 0, 0.5, 0)
    bar1.AnchorPoint = Vector2.new(0.5, 0.5)
    bar1.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    bar1.BorderSizePixel = 0
    bar1.Rotation = 45
    bar1.ZIndex = 10
    bar1.Parent = btn

    bar1Corner = Instance.new("UICorner")
    bar1Corner.CornerRadius = UDim.new(1, 0)
    bar1Corner.Parent = bar1

    local bar2 = bar1:Clone()
    bar2.Name = "Bar2"
    bar2.Rotation = -45
    bar2.Parent = btn

    btn.MouseEnter:Connect(function()
        TweenService:Create(bg, TweenInfo.new(0.12), {BackgroundTransparency = 0.88}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(bg, TweenInfo.new(0.12), {BackgroundTransparency = 1}):Play()
    end)

    return btn
end

local function reportPurchaseFinished(status, reason, targetNick, fruitName, queueItemId)
    local nick = targetNick or activeTargetPlayer or ""
    local fruit = fruitName or activeTargetFruit or ""
    local qId = queueItemId or currentBuyItemId or 0

    print(string.format("[AutoBuyer] Status da compra: %s (Nick: %s | ID: %s | Motivo: %s)", tostring(status), tostring(nick), tostring(qId), tostring(reason or "none")))
    local payload = HttpService:JSONEncode({
        type = "purchase_finished",
        status = status,
        username = nick,
        nick = nick,
        fruit = fruit,
        id = qId,
        reason = reason or "",
        token = SCRIPT_TOKEN
    })
    pcall(function()
        if activeWS then
            if activeWS.Send then activeWS:Send(payload) elseif activeWS.send then activeWS:send(payload) end
        end
    end)
    task.spawn(function()
        local tokenQ = getTokenQuery()
        if tokenQ ~= "" then
            pcall(function()
                local cloudUrl = VERCEL_API_URL .. "/api/script/purchase_finished" .. tokenQ .. "&status=" .. HttpService:UrlEncode(tostring(status)) .. "&username=" .. HttpService:UrlEncode(tostring(nick)) .. "&id=" .. tostring(qId)
                universalHttpRequest(cloudUrl, "POST", payload)
            end)
        end
        pcall(function()
            universalHttpRequest("http://127.0.0.1:" .. HTTP_PORT .. "/purchase_finished", "POST", payload)
        end)
    end)
end

local function logStep(stepName, explicitIdx)
    local idxStr = explicitIdx and (" (Passo " .. tostring(explicitIdx) .. ")") or ""
    print("[AutoBuyer - Passo] " .. tostring(stepName) .. idxStr)
    local payload = HttpService:JSONEncode({
        type = "automation_step",
        step = stepName,
        step_name = stepName,
        step_index = explicitIdx,
        username = activeTargetPlayer or "",
        token = SCRIPT_TOKEN
    })
    pcall(function()
        if activeWS then
            if activeWS.Send then activeWS:Send(payload) elseif activeWS.send then activeWS:send(payload) end
        end
    end)
    task.spawn(function()
        local tokenQ = getTokenQuery()
        if tokenQ ~= "" then
            pcall(function()
                local stepParam = "&step=" .. HttpService:UrlEncode(tostring(stepName))
                local idxParam = explicitIdx and ("&step_index=" .. tostring(explicitIdx)) or ""
                local userParam = (activeTargetPlayer and activeTargetPlayer ~= "") and ("&username=" .. HttpService:UrlEncode(activeTargetPlayer)) or ""
                local cloudUrl = VERCEL_API_URL .. "/api/script/automation_step" .. tokenQ .. stepParam .. idxParam .. userParam
                universalHttpRequest(cloudUrl, "POST", payload)
            end)
        end
        pcall(function()
            universalHttpRequest("http://127.0.0.1:" .. HTTP_PORT .. "/automation_step", "POST", payload)
        end)
    end)
end

---------------------------------------------------------
-- FORMATAÇÃO E CAPTURA DE JOGADOR E FRUTA (DIRETO DO JOGO)
---------------------------------------------------------

-- Declaração antecipada das referências de UI
local itemNameLabel = nil
local priceText = nil
local balanceText = nil
local robuxInput = nil

-- Remove tags de formatação nativas de RichText do Roblox sem corromper <NomeDoItem>
local function stripRobloxRichTextTags(str)
    if not str then return "" end
    local clean = tostring(str)
    local rbxTags = {
        "font", "/font", "stroke", "/stroke", "b", "/b", "i", "/i",
        "u", "/u", "s", "/s", "color", "/color", "mark", "/mark",
        "smallcaps", "/smallcaps", "sc", "/sc", "br"
    }
    for _, tag in ipairs(rbxTags) do
        clean = clean:gsub("<%s*" .. tag .. "%s*[^>]*>", "")
    end
    return clean
end

---------------------------------------------------------
-- CONFIGURAÇÃO E DADOS DE CHROMATIC BOXES (Developer Products)
---------------------------------------------------------
local CHROMATIC_BOXES_DATA = {
    ["1520"] = { name = "x10 Chromatic Box", price = 1699, image = "rbxassetid://123233228480994", productId = 3709882498 },
    ["1519"] = { name = "x3 Chromatic Box", price = 575, image = "rbxassetid://91824779572618", productId = 3709882329 },
    ["1518"] = { name = "x1 Chromatic Box", price = 199, image = "rbxassetid://114422597299727", productId = 3709882216 }
}

---------------------------------------------------------
-- CONFIGURAÇÃO E DADOS DE GAMEPASSES (ImageLabel via GamePass)
---------------------------------------------------------
local GAMEPASS_DATA = {
    { name = "2x Mastery",    gamepassId = 6240746, price = 350,
      keywords = {"2x mastery", "2xmastery", "2x master", "mastery"} },
    { name = "2x Money",      gamepassId = 6028662, price = 450,
      keywords = {"2x money", "2xmoney", "money"} },
    { name = "Fast Boats",    gamepassId = 6525589, price = 350,
      keywords = {"fast boats", "fastboats", "fast boat", "boats"} },
    { name = "2x Boss Drops", gamepassId = 7578721, price = 350,
      keywords = {"2x boss drops", "2xbossdrops", "2x boss", "boss drops", "bossdrops", "boss drop"} },
    { name = "Dark Blade",    gamepassId = 6028786, price = 1200,
      keywords = {"dark blade", "darkblade"} },
    { name = "Fruit Notifier",gamepassId = 6738811, price = 275,
      keywords = {"fruit notifier", "fruitnotifier", "fruit not", "notifier"} },
}

-- Cache de imagens de gamepasses (buscadas via MarketplaceService)
local GAMEPASS_IMAGE_CACHE = {}

-- Cache também para Developer Products (Dragon, Magnet, etc.)
local PRODUCT_IMAGE_CACHE = {}

-- Busca a imagem do gamepass via MarketplaceService (com cache)
local function fetchGamepassImage(gamepassId)
    if GAMEPASS_IMAGE_CACHE[gamepassId] then
        return GAMEPASS_IMAGE_CACHE[gamepassId]
    end
    local ok, info = pcall(function()
        return MarketplaceService:GetProductInfo(gamepassId, Enum.InfoType.GamePass)
    end)
    if ok and info and info.IconImageAssetId and info.IconImageAssetId ~= 0 then
        local imgUrl = "rbxassetid://" .. tostring(info.IconImageAssetId)
        GAMEPASS_IMAGE_CACHE[gamepassId] = imgUrl
        pcall(function() ContentProvider:PreloadAsync({imgUrl}) end)
        return imgUrl
    end
    return nil
end

local function fetchProductImage(productId)
    if PRODUCT_IMAGE_CACHE[productId] then
        return PRODUCT_IMAGE_CACHE[productId]
    end
    local ok, info = pcall(function()
        return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
    end)
    if ok and info and info.IconImageAssetId and info.IconImageAssetId ~= 0 then
        local imgUrl = "rbxassetid://" .. tostring(info.IconImageAssetId)
        PRODUCT_IMAGE_CACHE[productId] = imgUrl
        pcall(function() ContentProvider:PreloadAsync({imgUrl}) end)
        return imgUrl
    end
    return nil
end

-- Pré-carrega todas as imagens de gamepasses e produtos em background no startup
task.spawn(function()
    task.wait(0.5)
    for _, gp in ipairs(GAMEPASS_DATA) do
        task.spawn(function()
            local img = fetchGamepassImage(gp.gamepassId)
            if img then pcall(function() ContentProvider:PreloadAsync({img}) end) end
        end)
        task.wait(0.04)
    end
    task.spawn(function()
        local dImg = fetchProductImage(1131547469) -- Dragon
        if dImg then pcall(function() ContentProvider:PreloadAsync({dImg}) end) end
    end)
    task.wait(0.04)
    task.spawn(function()
        local mImg = fetchProductImage(3710809268) -- Magnet
        if mImg then pcall(function() ContentProvider:PreloadAsync({mImg}) end) end
    end)
end)

local function getChromaticBoxConfig(fruitOrItemName)
    if not fruitOrItemName then return nil end
    local s = tostring(fruitOrItemName):lower()
    if not (s:find("chromatic") or s:find("box") or s:find("1518") or s:find("1519") or s:find("1520")) then
        return nil
    end
    if s:find("1520") or s:find("10") or s:find("x10") then
        return CHROMATIC_BOXES_DATA["1520"]
    elseif s:find("1519") or s:find("3") or s:find("x3") then
        return CHROMATIC_BOXES_DATA["1519"]
    else
        return CHROMATIC_BOXES_DATA["1518"]
    end
end

local function getActiveChromaticConfig()
    if activeTargetFruit and activeTargetFruit ~= "" then
        return getChromaticBoxConfig(activeTargetFruit)
    end
    return nil
end

local function findGamepassInText(text)
    if not text or text == "" then return nil end
    local clean = stripRobloxRichTextTags(text):lower()
    clean = clean:gsub("%[%s*[^%]]+%s*%]", "")
    for _, gp in ipairs(GAMEPASS_DATA) do
        for _, kw in ipairs(gp.keywords) do
            if clean:find(kw, 1, true) then
                return gp
            end
        end
    end
    return nil
end

local function findChromaticBoxInText(text)
    if not text or text == "" then return nil end
    local clean = stripRobloxRichTextTags(text):lower()
    clean = clean:gsub("%[%s*[^%]]+%s*%]", "")
    return getChromaticBoxConfig(clean)
end

local function getGamepassConfig(itemName)
    if not itemName then return nil end
    return findGamepassInText(itemName)
end

local function getActiveGamepassConfig()
    if activeTargetFruit and activeTargetFruit ~= "" then
        return getGamepassConfig(activeTargetFruit)
    end
    return nil
end

-- Extrai o nome limpo do item a partir do texto de contexto da GiftWindow
local function extractItemNameFromContextText(rawText)
    if not rawText or rawText == "" then return nil end
    local clean = stripRobloxRichTextTags(rawText)
    
    -- 0. Se contiver algum gamepass conhecido diretamente
    local gp = findGamepassInText(clean)
    if gp then return gp.name end
    
    -- 0b. Se contiver alguma chromatic box conhecida
    local box = findChromaticBoxInText(clean)
    if box then return box.name end
    
    -- 1. Conteúdo entre <...> (ex: "Gifting [Player] <Dragon>", "Gift <2x Money> to", "Gifting [X] <Permanent Buddha>}")
    local inBrackets = clean:match("<%s*([^<>]+)%s*>") or clean:match("<%s*([^<>]+)%s*%}")
    if inBrackets and inBrackets ~= "" then
        local candidate = inBrackets:gsub("[%[%]%<%>%{%}%\"%']", ""):match("^%s*(.-)%s*$")
        if candidate and candidate ~= "" and not candidate:lower():find("font") and not candidate:lower():find("stroke") then
            return candidate
        end
    end
    
    -- 2. Padrão "Gifting [Nome] Item" ou "Presenteando [Nome] Item"
    local afterPlayer = clean:match("^[Gg]ifting%s+%[[^%]]+%]%s+(.+)$")
        or clean:match("[Gg]ifting%s+%[[^%]]+%]%s+(.+)$")
        or clean:match("^[Pp]resenteando%s+%[[^%]]+%]%s+(.+)$")
        or clean:match("[Pp]resenteando%s+%[[^%]]+%]%s+(.+)$")
    if afterPlayer and afterPlayer ~= "" then
        local candidate = afterPlayer:gsub("[%[%]%<%>%{%}%\"%']", ""):match("^%s*(.-)%s*$")
        if candidate and candidate ~= "" then
            return candidate
        end
    end

    -- 3. Padrão "Gift [Item] to" ou "Presentear [Item] para"
    local afterGift = clean:match("^[Gg]ift%s+(.-)%s+[Tt]o") 
        or clean:match("^[Pp]resentear%s+(.-)%s+[Pp]ara")
        or clean:match("[Gg]ift%s+(.-)%s+[Tt]o")
        or clean:match("[Pp]resentear%s+(.-)%s+[Pp]ara")
    if afterGift and afterGift ~= "" then
        local candidate = afterGift:gsub("[%[%]%<%>%{%}%\"%']", ""):match("^%s*(.-)%s*$")
        if candidate and candidate ~= "" then
            return candidate
        end
    end
    
    -- 4. Padrão "Gift [Item]"
    local justGift = clean:match("^[Gg]ift%s+(.-)$") or clean:match("^[Pp]resentear%s+(.-)$")
    if justGift and justGift ~= "" then
        local candidate = justGift:gsub("[%[%]%<%>%{%}%\"%']", ""):match("^%s*(.-)%s*$")
        if candidate and candidate ~= "" then
            return candidate
        end
    end
    
    return nil
end

-- Extrai o nome limpo do jogador a partir do texto Footer.Context da GiftWindow (ex: "Gifting [NOME] <FRUTA}>")
local function extractPlayerNameFromGiftContext(rawText)
    if not rawText or rawText == "" then return nil end
    local clean = stripRobloxRichTextTags(rawText)
    
    -- 1. Tenta extrair entre colchetes [NOME] (padrão oficial: "Gifting [NOME] <FRUTA}>")
    local inBrackets = clean:match("%[%s*([^%[%]%<%>%{%}%s]+)%s*%]")
    if inBrackets and inBrackets ~= "" then
        local candidate = inBrackets:gsub("[%[%]%<%>%{%}%\"%']", ""):match("^%s*(.-)%s*$")
        if candidate and candidate ~= "" and candidate:lower() ~= "player" then
            return candidate
        end
    end

    -- 2. Tenta extrair após Gifting e antes de < (ex: "Gifting NomePlayer <Fruit>")
    local afterGifting = clean:match("^[Gg]ifting%s+([^%[%]%<%>%{%}]+)%s*<")
        or clean:match("[Gg]ifting%s+([^%[%]%<%>%{%}]+)%s*<")
        or clean:match("^[Pp]resenteando%s+([^%[%]%<%>%{%}]+)%s*<")
        or clean:match("[Pp]resenteando%s+([^%[%]%<%>%{%}]+)%s*<")
    if afterGifting and afterGifting ~= "" then
        local candidate = afterGifting:gsub("[%[%]%<%>%{%}%\"%']", ""):match("^%s*(.-)%s*$")
        if candidate and candidate ~= "" and candidate:lower() ~= "player" then
            return candidate
        end
    end

    -- 3. Fallback genérico para pegar a primeira palavra após Gifting
    local wordAfter = clean:match("[Gg]ifting%s+%[?([%w_]+)%]?")
    if wordAfter and wordAfter ~= "" and wordAfter:lower() ~= "player" then
        return wordAfter
    end
    
    return nil
end

-- Varre especificamente para encontrar se a GiftWindow é um Gamepass
local function scanGiftWindowForGamepass(giftWindow)
    if not giftWindow then return nil end
    local footer = giftWindow:FindFirstChild("Window") and giftWindow.Window:FindFirstChild("Footer")
    local context = footer and footer:FindFirstChild("Context")
    if context and context.Text and context.Text ~= "" then
        local gp = findGamepassInText(context.Text)
        if gp then return gp end
    end
    for _, desc in ipairs(giftWindow:GetDescendants()) do
        if desc:IsA("TextLabel") and desc.Visible and desc.Text and desc.Text ~= "" then
            local gp = findGamepassInText(desc.Text)
            if gp then return gp end
        end
    end
    return nil
end

-- Varre especificamente para encontrar se a GiftWindow é uma Chromatic Box
local function scanGiftWindowForChromaticBox(giftWindow)
    if not giftWindow then return nil end
    local footer = giftWindow:FindFirstChild("Window") and giftWindow.Window:FindFirstChild("Footer")
    local context = footer and footer:FindFirstChild("Context")
    if context and context.Text and context.Text ~= "" then
        local box = findChromaticBoxInText(context.Text)
        if box then return box end
    end
    for _, desc in ipairs(giftWindow:GetDescendants()) do
        if desc:IsA("TextLabel") and desc.Visible and desc.Text and desc.Text ~= "" then
            local box = findChromaticBoxInText(desc.Text)
            if box then return box end
        end
    end
    return nil
end

-- Varre a GiftWindow aberta no jogo procurando o nome do item/gamepass
local function scanGiftWindowForName(giftWindow)
    if not giftWindow then return nil end
    
    -- 1. Verifica se a janela aberta corresponde a um Gamepass
    local gp = scanGiftWindowForGamepass(giftWindow)
    if gp then return gp.name end

    -- 2. Verifica se a janela aberta corresponde a uma Chromatic Box
    local box = scanGiftWindowForChromaticBox(giftWindow)
    if box then return box.name end

    -- 3. Verifica no Footer.Context (padrão oficial Blox Fruits)
    local footer = giftWindow:FindFirstChild("Window") and giftWindow.Window:FindFirstChild("Footer")
    local context = footer and footer:FindFirstChild("Context")
    if context and context.Text and context.Text ~= "" then
        local extracted = extractItemNameFromContextText(context.Text)
        if extracted and extracted ~= "" and extracted:lower() ~= "generic" and extracted ~= "Fruit" and extracted ~= "Sword of Destiny" then
            return extracted
        end
    end

    -- 4. Varre descendentes da GiftWindow
    local ignoredTexts = {
        ["gift"] = true, ["cancel"] = true, ["purchase"] = true, ["buy"] = true,
        ["presentear"] = true, ["cancelar"] = true, ["comprar"] = true,
        ["global"] = true, ["friends"] = true, ["amigos"] = true, ["server"] = true, ["servidor"] = true,
        ["search..."] = true, ["search"] = true, ["pesquisar..."] = true, ["pesquisar"] = true,
        ["ok"] = true, ["close"] = true, ["fechar"] = true, ["balance"] = true
    }

    for _, desc in ipairs(giftWindow:GetDescendants()) do
        if desc:IsA("TextLabel") and desc.Visible and desc.Text and desc.Text ~= "" then
            local raw = desc.Text
            local extracted = extractItemNameFromContextText(raw)
            if extracted and extracted ~= "" and extracted:lower() ~= "generic" and extracted ~= "Fruit" and extracted ~= "Sword of Destiny" then
                return extracted
            end
        end
    end

    return nil
end

-- -- Captura a fruta selecionada diretamente no painel aberto da loja do jogo (FruitShopAndDealer)
-- Novo formato de slot: "FruitName-FruitName" (ex: "Magnet-Magnet", "Tiger-Tiger")
local function getActiveFruitFromShop()
    local shopGui = playerGui:FindFirstChild("FruitShopAndDealer")
    if not shopGui then return nil, nil end
    local scrollingFrame = shopGui:FindFirstChild("Shop")
        and shopGui.Shop:FindFirstChild("Menu")
        and shopGui.Shop.Menu:FindFirstChild("Content")
        and shopGui.Shop.Menu.Content:FindFirstChild("Body")
        and shopGui.Shop.Menu.Content.Body:FindFirstChild("ScrollingFrame")
    if not scrollingFrame then return nil, nil end
    
    for _, slot in ipairs(scrollingFrame:GetChildren()) do
        if slot:IsA("GuiObject") then
            -- Novo formato: "FruitName-FruitName" — detecta pelo padrão "X-X"
            local slotFruitName = slot.Name:match("^(.-)%-(.-)$") and slot.Name:match("^(.-)%-")
            if not slotFruitName then
                -- Fallback: formato antigo "Fruit[N]"
                if not slot.Name:find("Fruit") then slotFruitName = nil end
            end
            if slotFruitName or slot.Name:find("Fruit") then
                local controlPanel = slot:FindFirstChild("ControlPanel")
                if controlPanel and controlPanel.Visible and controlPanel.AbsoluteSize.Y > 0 then
                    local title = slot:FindFirstChild("CardButton")
                        and slot.CardButton:FindFirstChild("Profile")
                        and slot.CardButton.Profile:FindFirstChild("TopInfo")
                        and slot.CardButton.Profile.TopInfo:FindFirstChild("Title")
                    local artIcon = slot:FindFirstChild("CardButton")
                        and slot.CardButton:FindFirstChild("Profile")
                        and slot.CardButton.Profile:FindFirstChild("Icon")
                        and slot.CardButton.Profile.Icon:FindFirstChild("IconEffectContainer")
                        and slot.CardButton.Profile.Icon.IconEffectContainer:FindFirstChild("ArtIcon")
                    -- Tenta pegar nome do título primeiro, senão usa o nome do slot
                    local cleanName = slotFruitName
                    if title and title.Text and title.Text ~= "" then
                        local fromTitle = title.Text:gsub("<[^<>]->", ""):gsub('[}%]{}"]', ""):match("^%s*(.-)%s*$")
                        if fromTitle and fromTitle ~= "" then cleanName = fromTitle end
                    end
                    if cleanName and cleanName ~= "" then
                        return cleanName, artIcon
                    end
                end
            end
        end
    end
    return nil, nil
end


-- Variáveis globais de cache para o último item verificado diretamente no jogo
local lastDetectedInGameItem = nil
local lastDetectedInGamePrice = nil
local lastDetectedInGameImage = nil
local lastDetectedInGameImageColor = nil
local lastDetectedInGameImageTrans = nil
local lastDetectedInGameImageOffset = nil
local lastDetectedInGameImageSize = nil
local FRUIT_ICONS_CACHE = {}

-- Busca ícone, cores e spritesheet da fruta diretamente na loja do Blox Fruits (mesmo com painel fechado)
local function findFruitIconInShop(targetFruitName)
    if not targetFruitName or targetFruitName == "" then return nil end
    local cleanTarget = targetFruitName:lower():gsub(" fruit", ""):gsub(" fruta", ""):gsub(" perm", ""):gsub(" permanente", ""):gsub("%s+", "")
    
    local shopGui = playerGui:FindFirstChild("FruitShopAndDealer")
    if not shopGui then return nil end
    local scrollingFrame = shopGui:FindFirstChild("Shop")
        and shopGui.Shop:FindFirstChild("Menu")
        and shopGui.Shop.Menu:FindFirstChild("Content")
        and shopGui.Shop.Menu.Content:FindFirstChild("Body")
        and shopGui.Shop.Menu.Content.Body:FindFirstChild("ScrollingFrame")
    if not scrollingFrame then return nil end

    -- Tenta acesso direto pelo novo formato "FruitName-FruitName" primeiro (mais rápido)
    local directSlot = scrollingFrame:FindFirstChild(targetFruitName .. "-" .. targetFruitName)
    if not directSlot then
        -- Tenta com a primeira letra maiúscula
        local cap = targetFruitName:sub(1,1):upper() .. targetFruitName:sub(2)
        directSlot = scrollingFrame:FindFirstChild(cap .. "-" .. cap)
    end

    local function extractIconFromSlot(slot)
        -- Path explícito: slot.CardButton.Profile.Icon.IconEffectContainer.ArtIcon
        local ok, art = pcall(function()
            return slot.CardButton.Profile.Icon.IconEffectContainer.ArtIcon
        end)
        if not ok or not art then
            -- Fallback recursivo caso a estrutura interna mude
            art = slot:FindFirstChild("ArtIcon", true)
        end
        if art and art:IsA("ImageLabel") and art.Image ~= "" and art.Image ~= "rbxassetid://16335379958" then
            return {
                Image = art.Image,
                Color = art.ImageColor3,
                Transparency = art.ImageTransparency,
                RectOffset = art.ImageRectOffset,
                RectSize = art.ImageRectSize
            }
        end
        return nil
    end

    if directSlot then
        local icon = extractIconFromSlot(directSlot)
        if icon then
            FRUIT_ICONS_CACHE[cleanTarget] = icon
            return icon
        end
    end

    -- Varredura completa como fallback
    for _, slot in ipairs(scrollingFrame:GetChildren()) do
        if slot:IsA("GuiObject") then
            -- Detecta novo formato "FruitName-FruitName" OU antigo "Fruit[N]"
            local isNewFormat = slot.Name:match("^(.-)%-(.-)$") ~= nil
            local isOldFormat = slot.Name:find("Fruit") ~= nil
            if isNewFormat or isOldFormat then
                -- Nome do slot: extrai a parte antes do "-" para o novo formato
                local slotNameRaw = isNewFormat and (slot.Name:match("^(.-)%-") or slot.Name) or slot.Name
                -- Título: tenta CardButton.Profile.TopInfo.Title ou usa nome do slot
                local titleText = slotNameRaw
                local okT, titleV = pcall(function() return slot.CardButton.Profile.TopInfo.Title.Text end)
                if okT and titleV and titleV ~= "" then titleText = titleV end
                local cleanTitle = titleText:gsub("<[^<>]->", ""):match("^%s*(.-)%s*$"):lower():gsub("%s+", "")
                -- ArtIcon: path explícito primeiro, recursivo como fallback
                local art
                local okA
                okA, art = pcall(function() return slot.CardButton.Profile.Icon.IconEffectContainer.ArtIcon end)
                if not okA or not art then art = slot:FindFirstChild("ArtIcon", true) end
                
                if art and art:IsA("ImageLabel") and art.Image ~= "" and art.Image ~= "rbxassetid://16335379958" then
                    if cleanTitle ~= "" then
                        FRUIT_ICONS_CACHE[cleanTitle] = {
                            Image = art.Image,
                            Color = art.ImageColor3,
                            Transparency = art.ImageTransparency,
                            RectOffset = art.ImageRectOffset,
                            RectSize = art.ImageRectSize
                        }
                    end
                    if cleanTitle ~= "" and (cleanTitle == cleanTarget or cleanTitle:find(cleanTarget, 1, true) or cleanTarget:find(cleanTitle, 1, true)) then
                        return FRUIT_ICONS_CACHE[cleanTitle]
                    end
                end
            end
        end
    end
    return nil
end


-- DETECÇÃO TOTALMENTE INDEPENDENTE DO SERVIDOR: SEMPRE PEGA O NOME REAL NO JOGO
local function detectRealInGameItemName()
    -- 0. Se o item alvo for uma Chromatic Box (x1, x3, x10)
    local chromTarget = getActiveChromaticConfig()
    if chromTarget then
        lastDetectedInGameItem = chromTarget.name
        return chromTarget.name
    end

    -- 0b. Se o item alvo for um Gamepass
    local gpTarget = getActiveGamepassConfig()
    if gpTarget then
        lastDetectedInGameItem = gpTarget.name
        return gpTarget.name
    end

    -- 1. Prioridade máxima: ler diretamente da GiftWindow aberta no jogo
    local giftWindow = playerGui:FindFirstChild("GiftWindow")
    if giftWindow and giftWindow.Enabled then
        local nameFromGift = scanGiftWindowForName(giftWindow)
        if nameFromGift and nameFromGift ~= "" and nameFromGift:lower() ~= "generic" and nameFromGift ~= "Fruit" and nameFromGift ~= "Sword of Destiny" and nameFromGift ~= "Mock Item Name" then
            lastDetectedInGameItem = nameFromGift
            return nameFromGift
        end
    end
    
    -- 2. Segunda prioridade: ler do slot atualmente expandido na loja de frutas
    local shopFruitName = getActiveFruitFromShop()
    if shopFruitName and shopFruitName ~= "" and shopFruitName:lower() ~= "generic" and shopFruitName ~= "Fruit" and shopFruitName ~= "Sword of Destiny" and shopFruitName ~= "Mock Item Name" then
        lastDetectedInGameItem = shopFruitName
        return shopFruitName
    end
    
    -- 3. Terceira prioridade: se houver fruta/item real definido pelo comando de compra do bot
    if activeTargetFruit and activeTargetFruit ~= "" and activeTargetFruit:lower() ~= "generic" and activeTargetFruit ~= "Fruit" and activeTargetFruit ~= "Sword of Destiny" and activeTargetFruit ~= "Mock Item Name" then
        lastDetectedInGameItem = activeTargetFruit
        return activeTargetFruit
    end
    
    -- 4. Quarta prioridade: último item verificado capturado no jogo
    if lastDetectedInGameItem and lastDetectedInGameItem ~= "" and lastDetectedInGameItem:lower() ~= "generic" and lastDetectedInGameItem ~= "Fruit" and lastDetectedInGameItem ~= "Sword of Destiny" and lastDetectedInGameItem ~= "Mock Item Name" then
        return lastDetectedInGameItem
    end
    
    -- Fallback limpo: se nada foi detectado ainda, retorna "Fruit" (NUNCA "Generic", "Sword of Destiny" ou retroalimentação de itemNameLabel)
    return "Fruit"
end

local function getCurrentFruitName()
    return detectRealInGameItemName()
end

local function formatFruitForNotification(rawFruit)
    if not rawFruit or rawFruit == "" or rawFruit:lower() == "generic" or rawFruit == "Fruit" or rawFruit == "Sword of Destiny" then 
        rawFruit = detectRealInGameItemName() 
    end
    local clean = tostring(rawFruit):gsub("<[^<>]->", ""):gsub("[}%]{}\"]", ""):match("^%s*(.-)%s*$") or rawFruit
    if clean:lower() == "generic" or clean == "" or clean == "Sword of Destiny" then
        clean = "Fruit"
    end
    
    local chromTarget = getChromaticBoxConfig(clean) or getChromaticBoxConfig(rawFruit) or getActiveChromaticConfig()
    if chromTarget then
        return chromTarget.name
    end

    -- Gamepasses: retorna o nome oficial sem aplicar title-case nem "Permanent"
    local gpTarget = getGamepassConfig(clean) or getGamepassConfig(rawFruit) or getActiveGamepassConfig()
    if gpTarget then
        return gpTarget.name
    end

    if clean:lower():sub(1, 6) == "fruit " then
        clean = clean:sub(7)
    end
    if clean:lower():sub(-6) == " fruit" then
        clean = clean:sub(1, -7)
    end
    
    local words = {}
    for word in clean:gmatch("%S+") do
        table.insert(words, word:sub(1,1):upper() .. word:sub(2):lower())
    end
    local titleCase = table.concat(words, " ")
    if titleCase == "" or titleCase:lower() == "generic" or titleCase == "Sword Of Destiny" then titleCase = "Fruit" end
    
    -- Gamepasses e Chromatic Boxes NÃO devem receber o prefixo "Permanent" (apenas frutas recebem)
    local lower = titleCase:lower()
    local isGamepass = (gpTarget ~= nil) or (getGamepassConfig(lower) ~= nil) or (getGamepassConfig(clean) ~= nil)
    local isChromaticBox = (chromTarget ~= nil) or (getChromaticBoxConfig(lower) ~= nil) or (getChromaticBoxConfig(clean) ~= nil)
    
    if not isGamepass and not isChromaticBox and not titleCase:lower():find("permanent") and titleCase:lower() ~= "fruit" then
        titleCase = "Permanent " .. titleCase
    end
    return titleCase
end

local function formatUsernameForNotification(rawUser)
    if not rawUser or rawUser == "" then rawUser = "Player" end
    local clean = string.split(tostring(rawUser), ":")[1] or rawUser
    clean = clean:gsub("<[^<>]->", ""):gsub("[}%]{}\"]", ""):gsub("^@", ""):match("^%s*(.-)%s*$") or clean
    if clean == "" or clean:lower() == "nil" then clean = "Player" end
    return clean
end

local function getCurrentPlayerName()
    local giftWindow = playerGui:FindFirstChild("GiftWindow")
    
    -- 1. Se a caixa de pesquisa (SearchBox) tiver texto digitado atualmente
    if giftWindow then
        local content = giftWindow:FindFirstChild("Content", true)
        if content then
            local searchFrame = content:FindFirstChild("SearchFrame", true)
            local searchBox = searchFrame and searchFrame:FindFirstChild("TextBox")
            if searchBox and searchBox.Text ~= "" and searchBox.Text ~= "Search..." and searchBox.Text ~= "Search" then
                return formatUsernameForNotification(searchBox.Text)
            end
        end
    end
    
    -- 2. Se a TextBox estiver vazia: PEGA DIRETO DE Footer.Context (sem usar o nome antigo/cache!)
    if giftWindow then
        local footer = giftWindow:FindFirstChild("Window") and giftWindow.Window:FindFirstChild("Footer")
        local context = footer and footer:FindFirstChild("Context")
        if context and context.Text and context.Text ~= "" then
            local extractedUser = extractPlayerNameFromGiftContext(context.Text)
            if extractedUser and extractedUser ~= "" and extractedUser:lower() ~= "player" then
                return formatUsernameForNotification(extractedUser)
            end
        end
    end
    
    -- 3. Fallbacks secundários apenas se a GiftWindow não estiver ativa
    if searchBoxPlayerName and searchBoxPlayerName ~= "" and searchBoxPlayerName ~= "Search..." and searchBoxPlayerName ~= "Search" then
        return formatUsernameForNotification(searchBoxPlayerName)
    end
    if activeTargetPlayer and activeTargetPlayer ~= "" then
        return formatUsernameForNotification(activeTargetPlayer)
    end
    if selectedPlayerName and selectedPlayerName ~= "" then
        return formatUsernameForNotification(selectedPlayerName)
    end
    
    return "Player"
end

---------------------------------------------------------
-- SISTEMA DE DEDUÇÃO E ROLETA DE ROBUX (700K - 1M)
---------------------------------------------------------
local function rollRandomRobux()
    local minR = 700000
    local maxR = 1000000
    local rolled = math.random(minR, maxR)
    -- Arredonda para múltiplo de 50 para parecer natural no Roblox
    rolled = math.floor(rolled / 50) * 50
    local formattedBal = formatNumber(rolled)
    
    currentSettings.mock_balance = formattedBal
    if balanceText then
        balanceText.Text = formattedBal
    end
    if robuxInput then
        robuxInput.Text = formattedBal
    end
    
    pcall(saveConfig)
    print(string.format("[AutoBuyer] 🎲 Roleta de Robux ativada! Novo saldo: %s Robux", formattedBal))
    
    -- Sincroniza com o servidor Bridge se estiver conectado
    if activeWS then
        pcall(function()
            local wsMsg = HttpService:JSONEncode({
                type = "update_game_settings",
                settings = currentSettings
            })
            if activeWS.Send then activeWS:Send(wsMsg) elseif activeWS.send then activeWS:send(wsMsg) end
        end)
    end
    
    task.spawn(function()
        pcall(function()
            HttpService:PostAsync(
                "http://127.0.0.1:" .. HTTP_PORT .. "/update_game_settings",
                HttpService:JSONEncode({ settings = currentSettings }),
                Enum.HttpContentType.ApplicationJson
            )
        end)
    end)
    
    return formattedBal
end

local function deductRobux(customPrice)
    local currentBalNum = parseNumber(currentSettings.mock_balance)
    local priceNum = 0
    
    if customPrice then
        priceNum = parseNumber(customPrice)
    elseif priceText and priceText.Text ~= "" then
        priceNum = parseNumber(priceText.Text)
    else
        priceNum = parseNumber(currentSettings.item_price)
    end
    
    local newBal = math.max(0, currentBalNum - priceNum)
    
    -- Roleta automática: quando o saldo chega em 20.000 ou menos (<= 20k), roleta automaticamente entre 700k e 1M
    if newBal <= 20000 then
        print(string.format("[AutoBuyer] ⚠️ Saldo baixo detectado (%s Robux <= 20k). Roletando automaticamente 700k - 1M...", formatNumber(newBal)))
        rollRandomRobux()
        return
    end
    
    local formattedBal = formatNumber(newBal)
    
    currentSettings.mock_balance = formattedBal
    if balanceText then
        balanceText.Text = formattedBal
    end
    if robuxInput then
        robuxInput.Text = formattedBal
    end
    
    pcall(saveConfig)
    print(string.format("[AutoBuyer] Robux descontados: -%s | Novo saldo: %s", formatNumber(priceNum), formattedBal))
    
    -- Sincroniza com o servidor Bridge se estiver conectado
    if activeWS then
        pcall(function()
            local wsMsg = HttpService:JSONEncode({
                type = "update_game_settings",
                settings = currentSettings
            })
            if activeWS.Send then activeWS:Send(wsMsg) elseif activeWS.send then activeWS:send(wsMsg) end
        end)
    end
    
    task.spawn(function()
        pcall(function()
            HttpService:PostAsync(
                "http://127.0.0.1:" .. HTTP_PORT .. "/update_game_settings",
                HttpService:JSONEncode({ settings = currentSettings }),
                Enum.HttpContentType.ApplicationJson
            )
        end)
    end)
    -- Sincroniza novo saldo com a Nuvem Vercel para persistir
    task.spawn(function()
        pcall(function()
            local tokenQ = getTokenQuery()
            if tokenQ ~= "" then
                universalHttpRequest(
                    VERCEL_API_URL .. "/api/script/game_settings" .. tokenQ,
                    "POST",
                    HttpService:JSONEncode({ mock_balance = formattedBal })
                )
            end
        end)
    end)
end

---------------------------------------------------------
-- NOTIFICAÇÕES NATIVAS DO BLOX FRUITS (RICH TEXT)
---------------------------------------------------------
local function sendGiftNotifications(targetUser, targetFruit)
    local username = formatUsernameForNotification(targetUser or getCurrentPlayerName())
    local fruitName = formatFruitForNotification(targetFruit or getCurrentFruitName())
    
    print("[AutoBuyer] Notificação: enviando presente de " .. fruitName .. " para " .. username)
    
    local notifications = playerGui:FindFirstChild("Notifications") or playerGui:WaitForChild("Notifications", 3)
    local commF = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_")
    
    local function dispararNotificacaoNativa(textoFormatado)
        if not notifications then return end
        
        local stack = notifications:FindFirstChild("NotificationStack") or notifications:WaitForChild("NotificationStack", 2) or notifications
        local connections = {}
        local handled = false
        
        local function aplicarNosDois(fundoObj)
            if not fundoObj then return end
            
            pcall(function()
                fundoObj.Visible = true
                if fundoObj:IsA("TextLabel") or pcall(function() return fundoObj.Text end) then
                    fundoObj.RichText = true
                    fundoObj.Text = textoFormatado
                    fundoObj.TextTransparency = 0
                end
            end)
            
            local textoObj = fundoObj:FindFirstChild("TextLabel")
            if textoObj then
                pcall(function()
                    textoObj.Visible = true
                    textoObj.RichText = true
                    textoObj.Text = textoFormatado
                    textoObj.TextTransparency = 0
                end)
            end
            
            for _, desc in ipairs(fundoObj:GetDescendants()) do
                if desc:IsA("TextLabel") or desc:IsA("TextBox") then
                    pcall(function()
                        desc.Visible = true
                        desc.RichText = true
                        desc.Text = textoFormatado
                        desc.TextTransparency = 0
                    end)
                end
            end
        end
        
        local function handleNotificationItem(child)
            if handled or not child then return end
            
            if child.Name == "NotificationStack" then
                table.insert(connections, child.ChildAdded:Connect(function(newChild)
                    handleNotificationItem(newChild)
                end))
                return
            end
            
            if child.Name == "NotificationTemplate" or child.Name:find("Notification") or child:FindFirstChild("TextLabel") or child:IsA("TextLabel") then
                handled = true
                for _, conn in ipairs(connections) do
                    pcall(function() conn:Disconnect() end)
                end
                
                aplicarNosDois(child)
                task.wait()
                aplicarNosDois(child)
                task.delay(0.04, function() aplicarNosDois(child) end)
                task.delay(0.1, function() aplicarNosDois(child) end)
                task.delay(0.2, function() aplicarNosDois(child) end)
            end
        end
        
        if stack then
            table.insert(connections, stack.ChildAdded:Connect(handleNotificationItem))
        end
        table.insert(connections, notifications.ChildAdded:Connect(handleNotificationItem))
        table.insert(connections, notifications.DescendantAdded:Connect(handleNotificationItem))
        
        task.delay(3, function()
            if not handled then
                for _, conn in ipairs(connections) do
                    pcall(function() conn:Disconnect() end)
                end
            end
        end)
        
        if commF then
            pcall(function() commF:InvokeServer("activateTitle", "") end)
        end
    end

    -- 1. Primeiro texto: ativa remote pro primeiro texto
    local textoSending = string.format('Sending Gift <font color="rgb(240, 185, 20)">%s</font> to %s..', fruitName, username)
    dispararNotificacaoNativa(textoSending)

    -- 2. Segundo texto: ativa remote novamente após 1.4s para empilhar um embaixo do outro
    task.delay(1.4, function()
        dispararNotificacaoNativa('<font color="rgb(45, 195, 75)">Gift Sent Successfully!</font>')
    end)
end

---------------------------------------------------------
-- FORÇAR CLIQUE EM GUI E DIGITAÇÃO HUMANA
---------------------------------------------------------
local rng = Random.new()

local function randomDelay(minT, maxT)
    task.wait(rng:NextNumber(minT, maxT))
end

local function getRealButton(instance)
    if instance:IsA("GuiButton") or instance:IsA("TextBox") then
        return instance
    end
    return instance:FindFirstChildWhichIsA("GuiButton", true) 
        or instance:FindFirstChildWhichIsA("TextBox", true) 
        or instance
end

local function cleanMouseClick(instance)
    local btn = getRealButton(instance)
    
    pcall(function() btn.SelectionImageObject = nil end)
    GuiService.SelectedObject = nil

    -- 1. Aguarda o elemento estabilizar o tamanho real (evita clicar durante animação)
    local waitStart = os.clock()
    while (btn.AbsoluteSize.X <= 5 or btn.AbsoluteSize.Y <= 5) and (os.clock() - waitStart) < 3 do
        task.wait(0.05)
    end

    local inset = GuiService:GetGuiInset()
    local pos = btn.AbsolutePosition
    local size = btn.AbsoluteSize
    
    -- Pequeno jitter natural dentro da área do botão
    local jx = math.random(-math.floor(size.X * 0.12), math.floor(size.X * 0.12))
    local jy = math.random(-math.floor(size.Y * 0.12), math.floor(size.Y * 0.12))
    local x = pos.X + (size.X / 2) + jx
    local y = pos.Y + (size.Y / 2) + inset.Y + jy

    -- Posiciona diretamente sem atrasos desnecessários de cursor na live
    if mousemoveabs then
        pcall(function() mousemoveabs(x, y) end)
    else
        pcall(function() VirtualInputManager:SendMouseMoveEvent(x, y, game) end)
    end
    
    task.wait(0.06 + math.random(15, 45)/1000)

    -- Dispara o clique físico com duração natural de pressão (65ms a 95ms)
    pcall(function()
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
    end)
    task.wait(0.07 + math.random(10, 25)/1000)
    pcall(function()
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
    end)

    -- Backup: aciona o evento de input internamente caso as coordenadas falhem
    if getconnections then
        pcall(function()
            for _, conn in pairs(getconnections(btn.InputBegan)) do
                conn:Fire({
                    UserInputType = Enum.UserInputType.MouseButton1,
                    UserInputState = Enum.UserInputState.Begin
                }, false)
            end
        end)
    end
end

-- Descansa o cursor do mouse (desativado para não mover o mouse do usuário)
local function restMouse()
end

local function forceClick(guiObject)
    cleanMouseClick(guiObject)
end

local function typeHuman(textBox, text)
    -- Garante que a caixa de texto está focada e limpa
    pcall(function()
        textBox:CaptureFocus()
        textBox.Text = ""
    end)
    -- Pausa de reação antes de começar a teclar (humano posiciona os dedos no teclado)
    task.wait(0.18 + math.random(20, 60) / 1000)
    
    -- Digita caractere por caractere com ritmo de digitação humano natural
    local currentTyped = ""
    local len = #text
    for i = 1, len do
        local ch = text:sub(i, i)
        currentTyped = currentTyped .. ch
        textBox.Text = currentTyped
        
        -- Intervalo natural entre teclas: ~65ms a ~115ms
        local keyDelay = math.random(65, 115) / 1000
        
        -- Leve pausa ao alcançar números, símbolos ou a cada 4 a 6 letras
        if (ch:match("%d") or ch == "_" or math.random(1, 6) == 1) and i < len then
            keyDelay = keyDelay + math.random(60, 120) / 1000
        end
        task.wait(keyDelay)
    end
    
    -- Pausa de conferência visual pós-digitação (humano confere se o nick está correto)
    task.wait(0.35 + math.random(40, 100) / 1000)
    
    -- Pressiona Enter fisicamente
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
        task.wait(0.06 + math.random(10, 30) / 1000)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
    end)
end

local function clickSlotElement(slot)
    if not slot then return end
    local cardButton = slot:FindFirstChild("CardButton")
    if cardButton then
        GuiService.SelectedObject = nil
        cleanMouseClick(cardButton)
    end
end

---------------------------------------------------------
-- GUI DE SUCESSO
---------------------------------------------------------
local successGui = Instance.new("ScreenGui")
successGui.Name = "SuccessGui_AutoBuyer"
successGui.ResetOnSpawn = false
successGui.Enabled = false
successGui.IgnoreGuiInset = true
successGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
successGui.DisplayOrder = 999999
successGui.Parent = playerGui

local successOverlay = Instance.new("Frame")
successOverlay.Name = "Overlay"
successOverlay.Size = UDim2.new(1, 0, 1, 0)
successOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
successOverlay.BackgroundTransparency = 1
successOverlay.BorderSizePixel = 0
successOverlay.ZIndex = 0
successOverlay.Active = true
successOverlay.Parent = successGui

local successOverlayClick = Instance.new("TextButton")
successOverlayClick.Size = UDim2.new(1, 0, 1, 0)
successOverlayClick.BackgroundTransparency = 1
successOverlayClick.Text = ""
successOverlayClick.ZIndex = 0
successOverlayClick.Parent = successOverlay

local successFrame = Instance.new("Frame")
successFrame.Name = "SuccessFrame"
successFrame.AnchorPoint = Vector2.new(0.5, 0.5)
successFrame.Position = UDim2.fromScale(0.5, 0.5)
successFrame.Size = UDim2.fromOffset(400, 240)
successFrame.BackgroundColor3 = Color3.fromRGB(29, 31, 36)
successFrame.BorderSizePixel = 0
successFrame.BackgroundTransparency = 1
successFrame.ZIndex = 2
successFrame.Parent = successGui

successCorner = Instance.new("UICorner")
successCorner.CornerRadius = UDim.new(0, 14)
successCorner.Parent = successFrame

successStroke = Instance.new("UIStroke")
successStroke.Color = Color3.fromRGB(58, 61, 67)
successStroke.Thickness = 1
successStroke.Transparency = 0.35
successStroke.Parent = successFrame

local successTitle = Instance.new("TextLabel")
successTitle.Size = UDim2.new(1, -60, 0, 28)
successTitle.Position = UDim2.new(0, 20, 0, 16)
successTitle.BackgroundTransparency = 1
successTitle.Text = "Purchase completed"
successTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
successTitle.TextSize = 20
successTitle.Font = Enum.Font.BuilderSansBold
successTitle.TextXAlignment = Enum.TextXAlignment.Left
successTitle.Parent = successFrame

local successCloseBtn = createCloseIcon(successFrame, 26)
successCloseBtn.Position = UDim2.new(1, -32, 0, 12)

checkHolder = Instance.new("Frame")
checkHolder.AnchorPoint = Vector2.new(0.5, 0)
checkHolder.Position = UDim2.new(0.5, 0, 0, 58)
checkHolder.Size = UDim2.new(0, 44, 0, 44)
checkHolder.BackgroundTransparency = 1
checkHolder.Parent = successFrame

checkCircle = Instance.new("UICorner")
checkCircle.CornerRadius = UDim.new(1, 0)
checkCircle.Parent = checkHolder

checkStroke = Instance.new("UIStroke")
checkStroke.Color = Color3.fromRGB(230, 230, 230)
checkStroke.Thickness = 2.5
checkStroke.Parent = checkHolder

checkShortBar = Instance.new("Frame")
checkShortBar.AnchorPoint = Vector2.new(0.5, 0.5)
checkShortBar.Size = UDim2.new(0, 11, 0, 3)
checkShortBar.Position = UDim2.new(0, 16, 0, 25)
checkShortBar.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
checkShortBar.BorderSizePixel = 0
checkShortBar.Rotation = 45
checkShortBar.Parent = checkHolder

checkShortCorner = Instance.new("UICorner")
checkShortCorner.CornerRadius = UDim.new(1, 0)
checkShortCorner.Parent = checkShortBar

checkLongBar = Instance.new("Frame")
checkLongBar.AnchorPoint = Vector2.new(0.5, 0.5)
checkLongBar.Size = UDim2.new(0, 20, 0, 3)
checkLongBar.Position = UDim2.new(0, 26, 0, 20)
checkLongBar.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
checkLongBar.BorderSizePixel = 0
checkLongBar.Rotation = -50
checkLongBar.Parent = checkHolder

checkLongCorner = Instance.new("UICorner")
checkLongCorner.CornerRadius = UDim.new(1, 0)
checkLongCorner.Parent = checkLongBar

local successMessage = Instance.new("TextLabel")
successMessage.AnchorPoint = Vector2.new(0.5, 0)
successMessage.Position = UDim2.new(0.5, 0, 0, 130)
successMessage.Size = UDim2.new(1, -40, 0, 40)
successMessage.BackgroundTransparency = 1
successMessage.Text = "You have successfully bought " .. detectRealInGameItemName() .. "."
successMessage.TextColor3 = Color3.fromRGB(205, 205, 205)
successMessage.TextSize = 15
successMessage.Font = Enum.Font.BuilderSansMedium
successMessage.TextWrapped = true
successMessage.TextXAlignment = Enum.TextXAlignment.Center
successMessage.Parent = successFrame

local okButton = Instance.new("TextButton")
okButton.AnchorPoint = Vector2.new(0.5, 1)
okButton.Position = UDim2.new(0.5, 0, 1, -18)
okButton.Size = UDim2.new(1, -40, 0, 40)
okButton.BackgroundColor3 = Color3.fromRGB(53, 81, 198)
okButton.BorderSizePixel = 0
okButton.Text = "OK"
okButton.TextColor3 = Color3.fromRGB(255, 255, 255)
okButton.TextSize = 16
okButton.Font = Enum.Font.BuilderSansBold
okButton.AutoButtonColor = false
okButton.Parent = successFrame

okCorner = Instance.new("UICorner")
okCorner.CornerRadius = UDim.new(0, 8)
okCorner.Parent = okButton

okButton.MouseEnter:Connect(function()
    TweenService:Create(okButton, TweenInfo.new(0.12), {BackgroundColor3 = Color3.fromRGB(70, 98, 220)}):Play()
end)
okButton.MouseLeave:Connect(function()
    TweenService:Create(okButton, TweenInfo.new(0.12), {BackgroundColor3 = Color3.fromRGB(53, 81, 198)}):Play()
end)

FixZIndex(successFrame)

local successBusy = false
closeSuccessGui = function()
    if successBusy or not successGui.Enabled then return end
    successBusy = true
    TweenService:Create(successFrame, TweenInfo.new(0.15), {BackgroundTransparency = 1}):Play()
    TweenService:Create(successOverlay, TweenInfo.new(0.15), {BackgroundTransparency = 1}):Play()
    task.wait(0.15)
    successGui.Enabled = false
    successBusy = false
end

openSuccessGui = function()
    if successBusy or successGui.Enabled then return end
    local realItem = detectRealInGameItemName()
    if realItem and realItem ~= "" and realItem ~= "Fruit" and realItem:lower() ~= "generic" and realItem ~= "Sword of Destiny" then
        successMessage.Text = "You have successfully bought " .. realItem .. "."
    end
    successGui.Enabled = true
    successFrame.BackgroundTransparency = 1
    successOverlay.BackgroundTransparency = 1
    TweenService:Create(successFrame, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        BackgroundTransparency = 0,
    }):Play()
    TweenService:Create(successOverlay, TweenInfo.new(0.22), {BackgroundTransparency = 0.5}):Play()
end

successCloseBtn.MouseButton1Click:Connect(closeSuccessGui)
successOverlayClick.MouseButton1Click:Connect(closeSuccessGui)
okButton.MouseButton1Click:Connect(closeSuccessGui)

---------------------------------------------------------
-- GUI DE COMPRA (BUY GUI)
---------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BuyGui_AutoBuyer"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 999999
screenGui.Parent = playerGui

local overlay = Instance.new("Frame")
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel = 0
overlay.ZIndex = 0
overlay.Active = true
overlay.Parent = screenGui

local overlayClick = Instance.new("TextButton")
overlayClick.Size = UDim2.new(1, 0, 1, 0)
overlayClick.BackgroundTransparency = 1
overlayClick.Text = ""
overlayClick.ZIndex = 0
overlayClick.Parent = overlay

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 455, 0, 284)
mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
mainFrame.Position = UDim2.fromScale(0.5, 0.5)
mainFrame.BackgroundColor3 = Color3.fromRGB(29, 31, 36)
mainFrame.BorderSizePixel = 0
mainFrame.BackgroundTransparency = 1
mainFrame.ZIndex = 2
mainFrame.Parent = screenGui

local FINAL_SIZE = mainFrame.Size
local FINAL_POS = mainFrame.Position
mainFrame.Size = UDim2.new(0, 410, 0, 256)

mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 12)
mainCorner.Parent = mainFrame

mainStroke = Instance.new("UIStroke")
mainStroke.Color = Color3.fromRGB(58, 61, 67)
mainStroke.Thickness = 1
mainStroke.Transparency = 0.35
mainStroke.Parent = mainFrame

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(0, 200, 0, 26)
titleLabel.Position = UDim2.new(0, 20, 0, 14)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Buy item"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextSize = 20
titleLabel.Font = Enum.Font.BuilderSansBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = mainFrame

local closeButton = createCloseIcon(mainFrame, 26)
closeButton.Position = UDim2.new(1, -32, 0, 12)

local balanceFrame = Instance.new("Frame")
balanceFrame.Size = UDim2.new(0, 110, 0, 22)
balanceFrame.Position = UDim2.new(1, -130, 0, 14)
balanceFrame.BackgroundTransparency = 1
balanceFrame.ZIndex = 10
balanceFrame.Parent = mainFrame

local balanceIcon = Instance.new("ImageLabel")
balanceIcon.Size = UDim2.new(0, 16, 0, 16)
balanceIcon.Position = UDim2.new(0, 0, 0.5, -8)
balanceIcon.BackgroundTransparency = 1
balanceIcon.Image = "rbxasset://textures/ui/common/robux.png"
balanceIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
balanceIcon.Parent = balanceFrame

balanceText = Instance.new("TextLabel")
balanceText.Size = UDim2.new(1, -20, 1, 0)
balanceText.Position = UDim2.new(0, 20, 0, 0)
balanceText.BackgroundTransparency = 1
balanceText.Text = formatNumber(MOCK_BALANCE)
balanceText.TextColor3 = Color3.fromRGB(255, 255, 255)
balanceText.TextSize = 15
balanceText.Font = Enum.Font.BuilderSansBold
balanceText.TextXAlignment = Enum.TextXAlignment.Left
balanceText.Parent = balanceFrame

local itemImage = Instance.new("ImageLabel")
itemImage.Size = UDim2.new(0, 90, 0, 90)
itemImage.Position = UDim2.new(0, 20, 0, 56)
itemImage.BackgroundTransparency = 1
itemImage.Image = GENERIC_ITEM_IMAGE
itemImage.ScaleType = Enum.ScaleType.Fit
itemImage.Parent = mainFrame

imageCorner = Instance.new("UICorner")
imageCorner.CornerRadius = UDim.new(0, 12)
imageCorner.Parent = itemImage

itemNameLabel = Instance.new("TextLabel")
itemNameLabel.Size = UDim2.new(0, 280, 0, 22)
itemNameLabel.Position = UDim2.new(0, 122, 0, 58)
itemNameLabel.BackgroundTransparency = 1
itemNameLabel.Text = detectRealInGameItemName()
itemNameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
itemNameLabel.TextSize = 15
itemNameLabel.Font = Enum.Font.BuilderSansBold
itemNameLabel.TextXAlignment = Enum.TextXAlignment.Left
itemNameLabel.Parent = mainFrame

local priceFrame = Instance.new("Frame")
priceFrame.Size = UDim2.new(0, 150, 0, 20)
priceFrame.Position = UDim2.new(0, 122, 0, 86)
priceFrame.BackgroundTransparency = 1
priceFrame.Parent = mainFrame

local priceIcon = Instance.new("ImageLabel")
priceIcon.Size = UDim2.new(0, 16, 0, 16)
priceIcon.Position = UDim2.new(0, 0, 0.5, -8)
priceIcon.BackgroundTransparency = 1
priceIcon.Image = "rbxasset://textures/ui/common/robux.png"
priceIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
priceIcon.Parent = priceFrame

priceText = Instance.new("TextLabel")
priceText.Size = UDim2.new(1, -22, 1, 0)
priceText.Position = UDim2.new(0, 22, 0, 0)
priceText.BackgroundTransparency = 1
priceText.Text = formatNumber(GENERIC_ITEM_PRICE)
priceText.TextColor3 = Color3.fromRGB(255, 255, 255)
priceText.TextSize = 14
priceText.Font = Enum.Font.BuilderSansBold
priceText.TextXAlignment = Enum.TextXAlignment.Left
priceText.Parent = priceFrame

local buyButton = Instance.new("TextButton")
buyButton.Size = UDim2.new(1, -40, 0, 38)
buyButton.Position = UDim2.new(0, 20, 0, 150)
buyButton.BackgroundColor3 = Color3.fromRGB(41, 62, 147)
buyButton.BorderSizePixel = 0
buyButton.Text = ""
buyButton.TextTransparency = 1
buyButton.AutoButtonColor = false
buyButton.Parent = mainFrame

local buyText = Instance.new("TextLabel")
buyText.Size = UDim2.new(1, 0, 1, 0)
buyText.BackgroundTransparency = 1
buyText.Text = "Buy"
buyText.TextColor3 = Color3.fromRGB(255, 255, 255)
buyText.TextSize = 16
buyText.Font = Enum.Font.BuilderSansBold
buyText.TextXAlignment = Enum.TextXAlignment.Center
buyText.TextYAlignment = Enum.TextYAlignment.Center
buyText.ZIndex = 4
buyText.Parent = buyButton

buyCorner = Instance.new("UICorner")
buyCorner.CornerRadius = UDim.new(0, 8)
buyCorner.Parent = buyButton

local buyClip = Instance.new("Frame")
buyClip.Size = UDim2.new(1, 0, 1, 0)
buyClip.BackgroundTransparency = 1
buyClip.ClipsDescendants = true
buyClip.ZIndex = 2
buyClip.Parent = buyButton

buyClipCorner = Instance.new("UICorner")
buyClipCorner.CornerRadius = UDim.new(0, 8)
buyClipCorner.Parent = buyClip

local fill = Instance.new("Frame")
fill.Size = UDim2.new(0, 0, 1, 0)
fill.Position = UDim2.new(0, 0, 0, 0)
fill.BackgroundColor3 = Color3.fromRGB(53, 92, 255)
fill.BorderSizePixel = 0
fill.ZIndex = 2
fill.Parent = buyClip

fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 8)
fillCorner.Parent = fill

local promoFrame = Instance.new("Frame")
promoFrame.Size = UDim2.new(1, -40, 0, 46)
promoFrame.Position = UDim2.new(0, 20, 0, 196)
promoFrame.BackgroundColor3 = Color3.fromRGB(32, 34, 39)
promoFrame.BorderSizePixel = 0
promoFrame.Parent = mainFrame

promoCorner = Instance.new("UICorner")
promoCorner.CornerRadius = UDim.new(0, 10)
promoCorner.Parent = promoFrame

promoStroke = Instance.new("UIStroke")
promoStroke.Color = Color3.fromRGB(50, 54, 60)
promoStroke.Thickness = 1
promoStroke.Parent = promoFrame

local promoText = Instance.new("TextLabel")
promoText.Size = UDim2.new(1, -104, 1, 0)
promoText.Position = UDim2.new(0, 18, 0, 0)
promoText.BackgroundTransparency = 1
promoText.Text = "Get 10% off with Roblox Plus"
promoText.TextColor3 = Color3.fromRGB(220, 220, 220)
promoText.TextSize = 13
promoText.Font = Enum.Font.BuilderSansMedium
promoText.TextXAlignment = Enum.TextXAlignment.Left
promoText.Parent = promoFrame

local newBadge = Instance.new("TextLabel")
newBadge.Size = UDim2.new(0, 48, 0, 24)
newBadge.Position = UDim2.new(1, -60, 0.5, -12)
newBadge.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
newBadge.Text = "New"
newBadge.TextColor3 = Color3.fromRGB(0, 0, 0)
newBadge.TextSize = 12
newBadge.Font = Enum.Font.BuilderSansBold
newBadge.Parent = promoFrame

badgeCorner = Instance.new("UICorner")
badgeCorner.CornerRadius = UDim.new(1, 0)
badgeCorner.Parent = newBadge

local disclaimerText = Instance.new("TextLabel")
disclaimerText.Size = UDim2.new(1, -40, 0, 16)
disclaimerText.Position = UDim2.new(0, 20, 0, 254)
disclaimerText.BackgroundTransparency = 1
disclaimerText.RichText = true
disclaimerText.Text = "Your payment method will be charged. <u>Terms of Use</u> apply."
disclaimerText.TextColor3 = Color3.fromRGB(140, 145, 155)
disclaimerText.TextSize = 11
disclaimerText.Font = Enum.Font.BuilderSansMedium
disclaimerText.TextXAlignment = Enum.TextXAlignment.Center
disclaimerText.Parent = mainFrame

FixZIndex(screenGui)

---------------------------------------------------------
-- LÓGICA E ANIMAÇÕES DA BUY GUI
---------------------------------------------------------
local canBuy = false
local GuiBusy = false
local buyInProgress = false
local purchaseComplete = true
local buyPurchasedThisCycle = false
local currentBuyCycleId = 0

local function startFillAnimation()
    canBuy = false
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.Position = UDim2.new(0, 0, 0, 0)
    local fillTween = TweenService:Create(fill, TweenInfo.new(1.5, Enum.EasingStyle.Linear), {
        Size = UDim2.new(1, 0, 1, 0),
    })
    fillTween:Play()
    fillTween.Completed:Connect(function()
        canBuy = true
    end)
end

local function resetAllItemCaches()
    activeTargetFruit = nil
    lastDetectedInGamePrice = nil
    lastDetectedInGameItem = nil
    lastDetectedInGameImage = nil
    lastDetectedInGameImageColor = nil
    lastDetectedInGameImageTrans = nil
    lastDetectedInGameImageOffset = nil
    lastDetectedInGameImageSize = nil
    if itemNameLabel then itemNameLabel.Text = "" end
    if priceText then priceText.Text = "" end
end

closeGui = function()
    currentBuyCycleId = currentBuyCycleId + 1 -- Invalida qualquer ciclo de compra pendente imediatamente!
    resetAllItemCaches()
    if GuiBusy or not screenGui.Enabled then return end
    GuiBusy = true
    local tween = TweenService:Create(mainFrame, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        Size = UDim2.new(0, 410, 0, 256),
        BackgroundTransparency = 1
    })
    tween:Play()
    TweenService:Create(overlay, TweenInfo.new(0.15), { BackgroundTransparency = 1 }):Play()
    tween.Completed:Wait()
    screenGui.Enabled = false
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.Position = UDim2.new(0, 0, 0, 0)
    canBuy = false
    GuiBusy = false
    resetAllItemCaches()
end

local function updateBuyGuiImage(fruitName)
    if not itemImage then return end
    local fruit = fruitName or activeTargetFruit or detectRealInGameItemName() or ""
    local cleanFruit = fruit:lower():gsub(" fruit", ""):gsub(" fruta", ""):gsub(" perm", ""):gsub(" permanente", ""):gsub("%s+", "")

    -- 0a. Chromatic Boxes: Assets oficiais do Roblox (Developer Products)
    local chromCfg = getChromaticBoxConfig(cleanFruit) or getChromaticBoxConfig(fruit) or getActiveChromaticConfig()
    if chromCfg then
        itemImage.Image = chromCfg.image
        itemImage.ImageColor3 = Color3.fromRGB(255, 255, 255)
        itemImage.ImageTransparency = 0
        itemImage.ImageRectOffset = Vector2.new(0, 0)
        itemImage.ImageRectSize = Vector2.new(0, 0)
        itemImage.ScaleType = Enum.ScaleType.Fit
        return
    end

    -- 0b. Gamepasses: Busca imagem oficial via MarketplaceService (GamePass InfoType)
    local gpCfg = getGamepassConfig(fruit) or getGamepassConfig(cleanFruit) or getActiveGamepassConfig()
    if gpCfg then
        local gpImg = fetchGamepassImage(gpCfg.gamepassId)
        if gpImg then
            itemImage.Image = gpImg
            itemImage.ImageColor3 = Color3.fromRGB(255, 255, 255)
            itemImage.ImageTransparency = 0
            itemImage.ImageRectOffset = Vector2.new(0, 0)
            itemImage.ImageRectSize = Vector2.new(0, 0)
            itemImage.ScaleType = Enum.ScaleType.Fit
            return
        end
    end

    -- 0c. Prioridade máxima Roblox: se a fruta está aberta na loja agora, usa o ArtIcon dela diretamente
    local openFruit, openArt = getActiveFruitFromShop()
    if openArt and openArt:IsA("ImageLabel") and openArt.Image ~= "" and openArt.Image ~= "rbxassetid://16335379958" then
        itemImage.Image = openArt.Image
        itemImage.ImageColor3 = openArt.ImageColor3
        itemImage.ImageTransparency = openArt.ImageTransparency
        itemImage.ImageRectOffset = openArt.ImageRectOffset
        itemImage.ImageRectSize = openArt.ImageRectSize
        if openArt.ImageRectSize and openArt.ImageRectSize.X > 0 and openArt.ImageRectSize.Y > 0 then
            itemImage.ScaleType = Enum.ScaleType.Stretch
        else
            itemImage.ScaleType = Enum.ScaleType.Fit
        end
        return
    end

    -- 1. Se for Dragon ou Magnet, usa imagem do Developer Product (com cache pré-carregado)
    local productIdForFetch = nil
    if cleanFruit:find("dragon") then
        productIdForFetch = 1131547469
    elseif cleanFruit:find("magnet") then
        productIdForFetch = 3710809268
    end
    if productIdForFetch then
        local prodImg = fetchProductImage(productIdForFetch)
        if prodImg then
            itemImage.Image = prodImg
            itemImage.ImageColor3 = Color3.fromRGB(255, 255, 255)
            itemImage.ImageTransparency = 0
            itemImage.ImageRectOffset = Vector2.new(0, 0)
            itemImage.ImageRectSize = Vector2.new(0, 0)
            itemImage.ScaleType = Enum.ScaleType.Fit
            return
        end
    end

    -- 2. Busca do cache ou varre a loja diretamente
    local iconData = FRUIT_ICONS_CACHE[cleanFruit] or findFruitIconInShop(cleanFruit)
    if iconData and iconData.Image and iconData.Image ~= "" and iconData.Image ~= "rbxassetid://16335379958" then
        itemImage.Image = iconData.Image
        itemImage.ImageColor3 = iconData.Color or Color3.fromRGB(255, 255, 255)
        itemImage.ImageTransparency = iconData.Transparency or 0
        itemImage.ImageRectOffset = iconData.RectOffset or Vector2.new(0, 0)
        itemImage.ImageRectSize = iconData.RectSize or Vector2.new(0, 0)
        if iconData.RectSize and iconData.RectSize.X > 0 and iconData.RectSize.Y > 0 then
            itemImage.ScaleType = Enum.ScaleType.Stretch
        else
            itemImage.ScaleType = Enum.ScaleType.Fit
        end
        return
    end

    -- 3. Se temos lastDetectedInGameImage válido de uma fruta
    if lastDetectedInGameImage and lastDetectedInGameImage ~= "" and lastDetectedInGameImage ~= "rbxassetid://16335379958" 
        and not lastDetectedInGameImage:find("headshot") and not lastDetectedInGameImage:find("avatar") and not lastDetectedInGameImage:find("search") then
        itemImage.Image = lastDetectedInGameImage
        itemImage.ImageColor3 = lastDetectedInGameImageColor or Color3.fromRGB(255, 255, 255)
        itemImage.ImageTransparency = lastDetectedInGameImageTrans or 0
        itemImage.ImageRectOffset = lastDetectedInGameImageOffset or Vector2.new(0, 0)
        itemImage.ImageRectSize = lastDetectedInGameImageSize or Vector2.new(0, 0)
        if lastDetectedInGameImageSize and lastDetectedInGameImageSize.X > 0 then
            itemImage.ScaleType = Enum.ScaleType.Stretch
        else
            itemImage.ScaleType = Enum.ScaleType.Fit
        end
        return
    end

    -- 4. Fallback padrão limpo e oficial de fruta Blox Fruits (ícone de Blox Fruit, NUNCA espada!)
    itemImage.Image = "rbxassetid://16335379958"
    itemImage.ImageColor3 = Color3.fromRGB(255, 255, 255)
    itemImage.ImageTransparency = 0
    itemImage.ImageRectOffset = Vector2.new(0, 0)
    itemImage.ImageRectSize = Vector2.new(0, 0)
    itemImage.ScaleType = Enum.ScaleType.Fit
end

local function activateGiftCancelButton()
    task.spawn(function()
        task.wait(0.3)
        pcall(function()
            local gw = playerGui:FindFirstChild("GiftWindow")
            if not gw then return end
            
            local function tryDismiss()
                local currentGw = playerGui:FindFirstChild("GiftWindow")
                if not currentGw or not currentGw.Enabled then return true end
                
                local cancelBtn = currentGw:FindFirstChild("Window") 
                    and currentGw.Window:FindFirstChild("Content") 
                    and currentGw.Window.Content:FindFirstChild("Buttons") 
                    and currentGw.Window.Content.Buttons:FindFirstChild("Cancel")
                    
                if not cancelBtn then
                    cancelBtn = currentGw:FindFirstChild("Cancel", true)
                end
                
                if cancelBtn and cancelBtn:IsA("GuiButton") then
                    -- 1. firesignal (executores compatíveis)
                    pcall(function()
                        if typeof(firesignal) == "function" then
                            firesignal(cancelBtn.MouseButton1Click)
                            firesignal(cancelBtn.Activated)
                        end
                    end)
                    
                    -- 2. getconnections (chama listeners registrados diretamente)
                    pcall(function()
                        if typeof(getconnections) == "function" then
                            for _, conn in ipairs(getconnections(cancelBtn.MouseButton1Click)) do
                                pcall(function() conn:Fire() end)
                            end
                            for _, conn in ipairs(getconnections(cancelBtn.Activated)) do
                                pcall(function() conn:Fire() end)
                            end
                        end
                    end)
                    
                    -- 3. Envio virtual direto e instantâneo sem delay de movimentação
                    pcall(function()
                        local pos = cancelBtn.AbsolutePosition
                        local size = cancelBtn.AbsoluteSize
                        local inset = GuiService:GetGuiInset()
                        local cx = pos.X + (size.X / 2)
                        local cy = pos.Y + (size.Y / 2) + inset.Y
                        VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, true, game, 0)
                        VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, false, game, 0)
                    end)
                end
                
                -- Fallback via ESC caso o botão físico ainda não tenha desativado a janela
                pcall(function()
                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Escape, false, game)
                    task.wait(0.03)
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Escape, false, game)
                end)
                
                return false
            end
            
            tryDismiss()
            
            -- Se após 0.1s a GiftWindow ainda estiver aberta na tela, insiste no fechamento
            task.wait(0.1)
            local gwCheck = playerGui:FindFirstChild("GiftWindow")
            if gwCheck and gwCheck.Enabled and gwCheck:FindFirstChild("Window") and gwCheck.Window.Visible then
                tryDismiss()
            end
        end)
    end)
end

local function openGui(overrideName, overridePrice, overrideImage, overrideColor, overrideTrans, overrideOffset, overrideSize)
    if GuiBusy or screenGui.Enabled then return end
    GuiBusy = true
    buyPurchasedThisCycle = false
    currentBuyCycleId = currentBuyCycleId + 1
    local myCycleId = currentBuyCycleId

    -- Reinicia a barra de progresso INSTANTANEAMENTE (sem esperar animação anterior)
    canBuy = false
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.Position = UDim2.new(0, 0, 0, 0)
    
    -- Se recebemos overrideName diretamente do interceptButton, usa ele com prioridade máxima
    local realItem = overrideName or detectRealInGameItemName()
    if realItem and realItem ~= "" and realItem ~= "Fruit" and realItem:lower() ~= "generic" and realItem ~= "Sword of Destiny" then
        if itemNameLabel then itemNameLabel.Text = realItem end
        if successMessage then successMessage.Text = "You have successfully bought " .. realItem .. "." end
    end

    -- Atualiza a imagem: se recebemos overrideImage, aplica diretamente
    if overrideImage and overrideImage ~= "" then
        pcall(function()
            itemImage.Image = overrideImage
            itemImage.ImageColor3 = overrideColor or Color3.fromRGB(255, 255, 255)
            itemImage.ImageTransparency = overrideTrans or 0
            itemImage.ImageRectOffset = overrideOffset or Vector2.new(0, 0)
            itemImage.ImageRectSize = overrideSize or Vector2.new(0, 0)
            itemImage.ScaleType = Enum.ScaleType.Fit
        end)
    else
        pcall(function()
            updateBuyGuiImage(realItem)
        end)
    end

    -- Se for gamepass, garante o nome correto no label
    local gpCfg = getGamepassConfig(realItem)
    if gpCfg then
        if itemNameLabel then itemNameLabel.Text = gpCfg.name end
        if successMessage then successMessage.Text = "You have successfully bought " .. gpCfg.name .. "." end
    end

    -- Preço: usa overridePrice se fornecido, senão busca o preço da fruta/item atual
    pcall(function()
        local rawPrice = parseNumber(overridePrice) or (gpCfg and gpCfg.price) or (realItem and FRUIT_PRICES[realItem:lower()]) or parseNumber(lastDetectedInGamePrice) or 50
        if currentSettings.roblox_plus then
            if promoFrame then promoFrame.Visible = false end
            local discounted = math.floor(rawPrice * 0.9)
            if priceText then priceText.Text = formatNumber(discounted) end
        else
            if promoFrame then promoFrame.Visible = true end
            if priceText then priceText.Text = formatNumber(rawPrice) end
        end
    end)
    
    screenGui.Enabled = true
    task.wait()
    mainFrame.Visible = false
    game:GetService("RunService").Heartbeat:Wait()
    mainFrame.Visible = true
    mainFrame.Size = UDim2.new(0, 410, 0, 256)
    mainFrame.Position = FINAL_POS
    mainFrame.BackgroundTransparency = 1
    overlay.BackgroundTransparency = 1
    
    TweenService:Create(mainFrame, TweenInfo.new(0.22, Enum.EasingStyle.Back), {
        Size = FINAL_SIZE,
        BackgroundTransparency = 0
    }):Play()
    TweenService:Create(overlay, TweenInfo.new(0.22), { BackgroundTransparency = 0.5 }):Play()
    
    task.wait(0.22)
    GuiBusy = false
    task.delay(0.1, startFillAnimation)

    task.spawn(function()
        logStep("Aguardando carregamento da animação de Compra...")
        -- A animação de fill leva 1.5s. Aguarda a barra encher e clica com tempo de reação humano natural:
        task.wait(1.85 + math.random(40, 100) / 1000)

        -- TRAVA DE SEGURANÇA: Se a GUI foi fechada pelo usuário (clicou fora, ESC, etc.), ABORTA IMEDIATAMENTE!
        if currentBuyCycleId ~= myCycleId or not screenGui.Enabled or not mainFrame.Visible then
            print("[AutoBuyer] Compra abortada com sucesso: Buy GUI foi fechada pelo usuário antes da confirmação.")
            return
        end

        logStep("Clicando no botão de Compra (Buy)...", 5)
        cleanMouseClick(buyButton)

        task.wait(0.08)
        if currentBuyCycleId ~= myCycleId or not screenGui.Enabled or not mainFrame.Visible then
            print("[AutoBuyer] Compra abortada: Buy GUI fechada durante o processo de clique.")
            return
        end
        
        -- Garante a execução da dedução e notificação se o clique não disparar o evento
        if not buyPurchasedThisCycle then
            buyPurchasedThisCycle = true
            deductRobux()
            local targetUser = getCurrentPlayerName()
            local targetFruit = getCurrentFruitName()
            sendGiftNotifications(targetUser, targetFruit)
            
            -- Envia evento de entrega para o servidor simples/geral
            pcall(function()
                local deliveryMsg = HttpService:JSONEncode({
                    type = "delivery",
                    username = targetUser,
                    fruit = targetFruit
                })
                if activeWS then
                    if activeWS.Send then activeWS:Send(deliveryMsg) elseif activeWS.send then activeWS:send(deliveryMsg) end
                else
                    HttpService:PostAsync("http://127.0.0.1:" .. HTTP_PORT .. "/delivery", deliveryMsg, Enum.HttpContentType.ApplicationJson)
                end
            end)
            
            activateGiftCancelButton()
            closeGui()
            task.wait(0.18 + math.random(20, 50) / 1000)
            openSuccessGui()
        end
        
        logStep("Compra finalizada e loja fechada!", 6)
        task.wait(0.25 + math.random(30, 60) / 1000)
        purchaseComplete = true
        reportPurchaseFinished("success")
        -- Limpa o estado de alvo ativo para que a próxima compra não herde gamepass/chromatic antigo
        activeTargetFruit = nil
    end)
end

closeButton.MouseButton1Click:Connect(closeGui)
overlayClick.MouseButton1Click:Connect(function()
    -- Só fecha se o clique for FORA do mainFrame (evita fechar ao clicar em áreas transparentes dentro)
    local mousePos = UserInputService:GetMouseLocation()
    local framePos = mainFrame.AbsolutePosition
    local frameSize = mainFrame.AbsoluteSize
    local insideFrame = mousePos.X >= framePos.X and mousePos.X <= framePos.X + frameSize.X
        and mousePos.Y >= framePos.Y and mousePos.Y <= framePos.Y + frameSize.Y
    if not insideFrame then
        closeGui()
    end
end)

local BUY_BASE_COLOR = buyButton.BackgroundColor3
local BUY_HOVER_COLOR = Color3.fromRGB(53, 75, 170)
local BUY_TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

buyButton.MouseEnter:Connect(function()
    if buyButton.Active then
        TweenService:Create(buyButton, BUY_TWEEN_INFO, {BackgroundColor3 = BUY_HOVER_COLOR}):Play()
    end
end)
buyButton.MouseLeave:Connect(function()
    if buyButton.Active then
        TweenService:Create(buyButton, BUY_TWEEN_INFO, {BackgroundColor3 = BUY_BASE_COLOR}):Play()
    end
end)
buyButton.MouseButton1Down:Connect(function()
    if buyButton.Active then
        TweenService:Create(buyButton, TweenInfo.new(0.08), {BackgroundColor3 = Color3.fromRGB(30, 50, 130)}):Play()
    end
end)
buyButton.MouseButton1Up:Connect(function()
    if buyButton.Active then
        TweenService:Create(buyButton, TweenInfo.new(0.08), {BackgroundColor3 = BUY_HOVER_COLOR}):Play()
    end
end)

buyButton.MouseButton1Click:Connect(function()
    if not canBuy or buyInProgress or not screenGui.Enabled or not mainFrame.Visible then return end
    buyInProgress = true
    
    if not buyPurchasedThisCycle then
        buyPurchasedThisCycle = true
        deductRobux()
        local targetUser = getCurrentPlayerName()
        local targetFruit = getCurrentFruitName()
        sendGiftNotifications(targetUser, targetFruit)

        -- Ativa o botão Cancel da GiftWindow INSTANTANEAMENTE (sem coordenadas) para fechar a GiftWindow
        activateGiftCancelButton()

        -- Envia evento de entrega para o servidor simples/geral
        pcall(function()
            local deliveryMsg = HttpService:JSONEncode({
                type = "delivery",
                username = targetUser,
                fruit = targetFruit
            })
            if activeWS then
                if activeWS.Send then activeWS:Send(deliveryMsg) elseif activeWS.send then activeWS:send(deliveryMsg) end
            else
                HttpService:PostAsync("http://127.0.0.1:" .. HTTP_PORT .. "/delivery", deliveryMsg, Enum.HttpContentType.ApplicationJson)
            end
        end)
    end
    
    closeGui()
    task.wait(0.2)
    openSuccessGui()
    resetAllItemCaches()
    buyInProgress = false
end)

---------------------------------------------------------
-- CAPTURA AUTOMÁTICA DE PREÇO E NOME DA JANELA DE COMPRA
---------------------------------------------------------
local function getAutomaticPriceAndName()
    local price = nil
    local itemName = nil
    local itemImg = nil
    local imgColor = Color3.fromRGB(255, 255, 255)
    local imgTrans = 0
    local imgRectOffset = Vector2.new(0, 0)
    local imgRectSize = Vector2.new(0, 0)

    -- PRIORIDADE 1: Inspeciona a GiftWindow que está aberta no momento do clique
    local giftWindow = playerGui:FindFirstChild("GiftWindow")
    if giftWindow and giftWindow.Enabled then
        -- 1a. Verifica se é Gamepass na GiftWindow
        local gp = scanGiftWindowForGamepass(giftWindow)
        if gp then
            local gpImg = fetchGamepassImage(gp.gamepassId) or "rbxassetid://16335379958"
            lastDetectedInGameItem = gp.name
            lastDetectedInGamePrice = tostring(gp.price)
            lastDetectedInGameImage = gpImg
            activeTargetFruit = gp.name
            return tostring(gp.price), gp.name, gpImg, Color3.fromRGB(255, 255, 255), 0, Vector2.new(0, 0), Vector2.new(0, 0)
        end

        -- 1b. Verifica se é Chromatic Box na GiftWindow
        local box = scanGiftWindowForChromaticBox(giftWindow)
        if box then
            lastDetectedInGameItem = box.name
            lastDetectedInGamePrice = tostring(box.price)
            lastDetectedInGameImage = box.image
            activeTargetFruit = box.name
            return tostring(box.price), box.name, box.image, Color3.fromRGB(255, 255, 255), 0, Vector2.new(0, 0), Vector2.new(0, 0)
        end

        -- 1c. Tenta extrair o nome do item/fruta na GiftWindow
        local detectedName = scanGiftWindowForName(giftWindow)
        if detectedName and detectedName ~= "" and detectedName:lower() ~= "generic"
            and detectedName ~= "Fruit" and detectedName ~= "Sword of Destiny" then
            itemName = detectedName
            lastDetectedInGameItem = detectedName
        end

        -- 1d. Lê o preço exato do botão Purchase na GiftWindow
        pcall(function()
            local content = giftWindow:FindFirstChild("Content", true)
            local buttons = content and content:FindFirstChild("Buttons")
            local purchase = buttons and buttons:FindFirstChild("Purchase")
            local textLabel = purchase and (purchase:FindFirstChild("TextLabel") or purchase:FindFirstChildWhichIsA("TextLabel"))
            if textLabel and textLabel.Text ~= "" then
                local text = textLabel.Text:gsub("<[^<>]->", "")
                local clean = text:match("[%d,%.]+")
                if clean then
                    price = clean
                    lastDetectedInGamePrice = clean
                end
            end
        end)
    end

    -- Se detectou item da GiftWindow, verifica se é Gamepass ou Chromatic
    if itemName and itemName ~= "" then
        local gp = getGamepassConfig(itemName)
        if gp then
            local gpImg = fetchGamepassImage(gp.gamepassId) or "rbxassetid://16335379958"
            lastDetectedInGameItem = gp.name
            lastDetectedInGamePrice = tostring(gp.price)
            activeTargetFruit = gp.name
            return tostring(gp.price), gp.name, gpImg, Color3.fromRGB(255, 255, 255), 0, Vector2.new(0, 0), Vector2.new(0, 0)
        end
        local box = getChromaticBoxConfig(itemName)
        if box then
            lastDetectedInGameItem = box.name
            lastDetectedInGamePrice = tostring(box.price)
            activeTargetFruit = box.name
            return tostring(box.price), box.name, box.image, Color3.fromRGB(255, 255, 255), 0, Vector2.new(0, 0), Vector2.new(0, 0)
        end
    end

    -- 2. Se a GiftWindow não deu nome ou imagem, tenta pegar da loja de frutas (slot expandido)
    local shopFruit, artIcon = getActiveFruitFromShop()
    if shopFruit and shopFruit ~= "" then
        itemName = itemName or shopFruit
        if artIcon and artIcon.Image ~= "" and artIcon.Image ~= "rbxassetid://16335379958" then
            itemImg = artIcon.Image
            imgColor = artIcon.ImageColor3
            imgTrans = artIcon.ImageTransparency
            imgRectOffset = artIcon.ImageRectOffset
            imgRectSize = artIcon.ImageRectSize
            lastDetectedInGameImage = itemImg
            lastDetectedInGameImageColor = imgColor
            lastDetectedInGameImageTrans = imgTrans
            lastDetectedInGameImageOffset = imgRectOffset
            lastDetectedInGameImageSize = imgRectSize
        end
    end

    -- 3. Fallback para activeTargetFruit apenas se ainda não tivermos itemName
    if not itemName or itemName == "" then
        itemName = activeTargetFruit or detectRealInGameItemName() or "Fruit"
    end

    -- Se o nome final for Gamepass ou Chromatic, aplica config
    local gpFinal = getGamepassConfig(itemName)
    if gpFinal then
        local gpImg = fetchGamepassImage(gpFinal.gamepassId) or "rbxassetid://16335379958"
        lastDetectedInGameItem = gpFinal.name
        lastDetectedInGamePrice = tostring(gpFinal.price)
        activeTargetFruit = gpFinal.name
        return tostring(gpFinal.price), gpFinal.name, gpImg, Color3.fromRGB(255, 255, 255), 0, Vector2.new(0, 0), Vector2.new(0, 0)
    end
    local boxFinal = getChromaticBoxConfig(itemName)
    if boxFinal then
        lastDetectedInGameItem = boxFinal.name
        lastDetectedInGamePrice = tostring(boxFinal.price)
        activeTargetFruit = boxFinal.name
        return tostring(boxFinal.price), boxFinal.name, boxFinal.image, Color3.fromRGB(255, 255, 255), 0, Vector2.new(0, 0), Vector2.new(0, 0)
    end

    -- Se for Dragon ou Magnet, usa Developer Product
    local lName = itemName:lower()
    if lName:find("dragon") then
        local prodImg = fetchProductImage(1131547469)
        itemImg = prodImg or "rbxassetid://2673336234"
        imgColor = Color3.fromRGB(255, 255, 255)
        imgTrans = 0
        imgRectOffset = Vector2.new(0, 0)
        imgRectSize = Vector2.new(0, 0)
    elseif lName:find("magnet") then
        local prodImg = fetchProductImage(3710809268)
        itemImg = prodImg or "rbxassetid://16335379958"
        imgColor = Color3.fromRGB(255, 255, 255)
        imgTrans = 0
        imgRectOffset = Vector2.new(0, 0)
        imgRectSize = Vector2.new(0, 0)
    end

    -- Se ainda não temos imagem e existe findFruitIconInShop
    if not itemImg and type(findFruitIconInShop) == "function" then
        local iconData = findFruitIconInShop(itemName)
        if iconData and iconData.Image and iconData.Image ~= "" then
            itemImg = iconData.Image
            imgColor = iconData.Color or Color3.fromRGB(255, 255, 255)
            imgTrans = iconData.Transparency or 0
            imgRectOffset = iconData.RectOffset or Vector2.new(0, 0)
            imgRectSize = iconData.RectSize or Vector2.new(0, 0)
        end
    end

    -- Preço da fruta
    if not price or price == "" or price == "50" then
        if FRUIT_PRICES[lName] then
            price = tostring(FRUIT_PRICES[lName])
        elseif lastDetectedInGamePrice then
            price = lastDetectedInGamePrice
        else
            price = "50"
        end
    end

    itemImg = itemImg or "rbxassetid://16335379958"
    lastDetectedInGameItem = itemName
    lastDetectedInGamePrice = tostring(price)
    activeTargetFruit = itemName
    return tostring(price), itemName, itemImg, imgColor, imgTrans, imgRectOffset, imgRectSize
end

-- Vincula ouvintes de clique em cada botão de jogador na PlayerList da GiftWindow
local function bindPlayerList(playerList)
    if not playerList then return end
    
    local function hookChild(child)
        if not child:IsA("GuiObject") then return end
        local rawName = child.Name
        local nick = string.split(rawName, ":")[1]
        if not nick or nick == "" or nick == "UIListLayout" or nick == "UIPadding" then return end
        
        local btn = child:FindFirstChildWhichIsA("GuiButton", true) or (child:IsA("GuiButton") and child)
        if btn and not btn:GetAttribute("BoundAutoBuyer") then
            btn:SetAttribute("BoundAutoBuyer", true)
            btn.MouseButton1Click:Connect(function()
                selectedPlayerName = nick
                activeTargetPlayer = nick
                print("[AutoBuyer] Jogador capturado do botão da lista: " .. nick)
            end)
        end
    end
    
    for _, child in ipairs(playerList:GetChildren()) do
        hookChild(child)
    end
    playerList.ChildAdded:Connect(hookChild)
end

---------------------------------------------------------
-- CHROMATIC BOXES INTEGRADAS AO DEALER E GIFTWINDOW NORMAL
---------------------------------------------------------

task.spawn(function()
    while true do
        pcall(function()
            local giftWindow = playerGui:WaitForChild("GiftWindow", 5)
            if not giftWindow then return end
            local window = giftWindow:WaitForChild("Window", 5)
            if not window then return end
            local content = window:WaitForChild("Content", 5)
            if not content then return end
            
            -- Vincula a PlayerList para capturar o jogador escolhido
            local playerList = content:FindFirstChild("PlayerList")
            if playerList and not playerList:GetAttribute("BoundClicks") then
                playerList:SetAttribute("BoundClicks", true)
                bindPlayerList(playerList)
            end
            
            -- Captura o nome digitado na SearchBox quando Enter é pressionado
            local searchFrame = content:FindFirstChild("SearchFrame", true)
            local searchBox = searchFrame and searchFrame:FindFirstChild("TextBox")
            if searchBox and not searchBox:GetAttribute("BoundEnterCapture") then
                searchBox:SetAttribute("BoundEnterCapture", true)
                searchBox.FocusLost:Connect(function(enterPressed)
                    local typed = searchBox.Text
                    if typed and typed ~= "" and typed ~= "Search..." and typed ~= "Search" then
                        searchBoxPlayerName = typed  -- prioridade máxima, sobrescreve servidor
                        activeTargetPlayer = typed
                        selectedPlayerName = typed
                        print("[AutoBuyer] Jogador capturado da SearchBox (prioridade): " .. typed)
                    end
                end)
            end
            
            local buttons = content:WaitForChild("Buttons", 5)
            if not buttons then return end
            local purchase = buttons:WaitForChild("Purchase", 5)
            if not purchase then return end
            
            if purchase:FindFirstChild("InterceptButton") then return end
            
            local interceptButton = Instance.new("TextButton")
            interceptButton.Name = "InterceptButton"
            interceptButton.Size = UDim2.new(1, 0, 1, 0)
            interceptButton.BackgroundTransparency = 1
            interceptButton.Text = ""
            interceptButton.ZIndex = purchase.ZIndex + 10
            interceptButton.Parent = purchase
            
            interceptButton.MouseButton1Click:Connect(function()
                local price, name, image, imgColor, imgTrans, imgRectOffset, imgRectSize = getAutomaticPriceAndName()
                
                -- Detecta estritamente pelo nome do item aberto no momento na GiftWindow
                local chromCfg = getChromaticBoxConfig(name)
                local gpCfg = (not chromCfg) and getGamepassConfig(name) or nil
                if chromCfg then
                    name = chromCfg.name
                    price = tostring(chromCfg.price)
                    image = chromCfg.image
                    imgColor = Color3.fromRGB(255, 255, 255)
                    imgTrans = 0
                    imgRectOffset = Vector2.new(0, 0)
                    imgRectSize = Vector2.new(0, 0)
                    lastDetectedInGameItem = chromCfg.name
                    activeTargetFruit = chromCfg.name
                elseif gpCfg then
                    name = gpCfg.name
                    price = tostring(gpCfg.price)
                    image = fetchGamepassImage(gpCfg.gamepassId) or image
                    imgColor = Color3.fromRGB(255, 255, 255)
                    imgTrans = 0
                    imgRectOffset = Vector2.new(0, 0)
                    imgRectSize = Vector2.new(0, 0)
                    lastDetectedInGameItem = gpCfg.name
                    activeTargetFruit = gpCfg.name
                else
                    activeTargetFruit = name
                    lastDetectedInGameItem = name
                    if FRUIT_PRICES[name:lower()] and (not price or price == GENERIC_ITEM_PRICE) then
                        price = tostring(FRUIT_PRICES[name:lower()])
                    end
                end
                
                itemNameLabel.Text = name
                local numPrice = parseNumber(price) or 0
                if currentSettings.roblox_plus then
                    numPrice = math.floor(numPrice * 0.9)
                    if promoFrame then promoFrame.Visible = false end
                else
                    if promoFrame then promoFrame.Visible = true end
                end
                priceText.Text = formatNumber(numPrice)
                
                -- Se for Dragon ou Magnet, usa imagem do Developer Product (com cache pré-carregado)
                if not chromCfg and not gpCfg then
                    local fetchProductId = nil
                    if name:lower():find("dragon") then
                        fetchProductId = 1131547469
                    elseif name:lower():find("magnet") then
                        fetchProductId = 3710809268
                    end
                    if fetchProductId then
                        local prodImg = fetchProductImage(fetchProductId)
                        if prodImg then
                            image = prodImg
                        else
                            image = name:lower():find("magnet") and "rbxassetid://16335379958" or "rbxassetid://2673336234"
                        end
                        imgColor = Color3.fromRGB(255, 255, 255)
                        imgTrans = 0
                        imgRectOffset = Vector2.new(0, 0)
                        imgRectSize = Vector2.new(0, 0)
                    end
                end
                
                itemImage.Image = image
                itemImage.ImageColor3 = imgColor or Color3.fromRGB(255, 255, 255)
                itemImage.ImageTransparency = imgTrans or 0
                itemImage.ImageRectOffset = imgRectOffset or Vector2.new(0, 0)
                itemImage.ImageRectSize = imgRectSize or Vector2.new(0, 0)
                if chromCfg then
                    itemImage.ScaleType = Enum.ScaleType.Fit
                end
                
                successMessage.Text = "You have successfully bought " .. name .. "."
                
                -- Se a caixa de texto estiver vazia, PEGA DIRETO DE Footer.Context!
                pcall(function()
                    local gw = playerGui:FindFirstChild("GiftWindow")
                    local sf = gw and gw:FindFirstChild("SearchFrame", true)
                    local sb = sf and sf:FindFirstChild("TextBox")
                    if sb and sb.Text ~= "" and sb.Text ~= "Search..." and sb.Text ~= "Search" then
                        searchBoxPlayerName = sb.Text
                        activeTargetPlayer = sb.Text
                        selectedPlayerName = sb.Text
                    else
                        local footer = gw and gw:FindFirstChild("Window") and gw.Window:FindFirstChild("Footer")
                        local ctx = footer and footer:FindFirstChild("Context")
                        if ctx and ctx.Text and ctx.Text ~= "" then
                            local ctxUser = extractPlayerNameFromGiftContext(ctx.Text)
                            if ctxUser and ctxUser ~= "" and ctxUser:lower() ~= "player" then
                                searchBoxPlayerName = ctxUser
                                activeTargetPlayer = ctxUser
                                selectedPlayerName = ctxUser
                            end
                        end
                    end
                end)
                if not activeTargetPlayer or activeTargetPlayer == "" then
                    activeTargetPlayer = getCurrentPlayerName()
                end
                
                openGui(name, price, image, imgColor, imgTrans, imgRectOffset, imgRectSize)
            end)
        end)
        task.wait(1)
    end
end)

---------------------------------------------------------
-- BUSCA INTELIGENTE DE FRUTA NA LOJA (SCROLL POR PREÇO)
---------------------------------------------------------
local FRUIT_ORDER = {
    ["rocket"] = 1, ["spin"] = 2, ["chop"] = 3, ["spring"] = 4, ["bomb"] = 5,
    ["smoke"] = 6, ["spike"] = 7, ["flame"] = 8, ["falcon"] = 9, ["ice"] = 10, ["sand"] = 11,
    ["dark"] = 12, ["diamond"] = 13, ["light"] = 14, ["rubber"] = 15, ["barrier"] = 16,
    ["ghost"] = 17, ["magma"] = 18, ["quake"] = 19, ["buddha"] = 20, ["love"] = 21,
    ["spider"] = 22, ["sound"] = 23, ["phoenix"] = 24, ["portal"] = 25, ["rumble"] = 26,
    ["pain"] = 27, ["blizzard"] = 28, ["gravity"] = 29, ["mammoth"] = 30, ["t-rex"] = 31,
    ["dough"] = 32, ["shadow"] = 33, ["venom"] = 34, ["control"] = 35, ["spirit"] = 36,
    ["dragon"] = 37, ["leopard"] = 38, ["tiger"] = 38, ["kitsune"] = 39,
    ["gas"] = 40, ["yeti"] = 41, ["magnet"] = 42,
    ["x1 chromatic box"] = 1001, ["x3 chromatic box"] = 1002, ["x10 chromatic box"] = 1003,
    ["chromatic box"] = 1001, ["chromatic box x1"] = 1001, ["chromatic box x3"] = 1002, ["chromatic box x10"] = 1003,
    ["1518"] = 1001, ["1519"] = 1002, ["1520"] = 1003
}

local function resolveFruitToBuy(fruitName)
    -- 1. Prioridade MÁXIMA do Roblox: fruta detectada diretamente no jogo (GiftWindow aberta ou slot ativo)
    local inGameItem = detectRealInGameItemName()
    if inGameItem and inGameItem ~= "" and inGameItem ~= "Fruit" and inGameItem:lower() ~= "generic" and inGameItem ~= "Sword of Destiny" and (FRUIT_ORDER[inGameItem:lower()] or inGameItem:lower():find("chromatic") or inGameItem:lower():find("box")) then
        print("[AutoBuyer] Prioridade Roblox: usando item aberto no jogo: " .. inGameItem)
        return inGameItem
    end

    local openFruit, _ = getActiveFruitFromShop()
    if openFruit and openFruit ~= "" and (FRUIT_ORDER[openFruit:lower()] or openFruit:lower():find("chromatic") or openFruit:lower():find("box")) then
        print("[AutoBuyer] Prioridade Roblox: usando item aberto na loja: " .. openFruit)
        return openFruit
    end

    -- 2. Se fruitName foi passado e é válido
    if fruitName and fruitName ~= "" then
        local fLower = fruitName:lower():gsub("^%s*(.-)%s*$", "%1")
        if fLower ~= "random" and fLower ~= "generic" and fLower ~= "fruit" and fLower ~= "sword of destiny" then
            if fLower:find("1520") or (fLower:find("chromatic") and (fLower:find("10") or fLower:find("x10"))) or fLower == "x10 chromatic box" then
                return "x10 Chromatic Box"
            elseif fLower:find("1519") or (fLower:find("chromatic") and (fLower:find("3") or fLower:find("x3"))) or fLower == "x3 chromatic box" then
                return "x3 Chromatic Box"
            elseif fLower:find("1518") or (fLower:find("chromatic") and (fLower:find("1") or fLower:find("x1"))) or fLower == "x1 chromatic box" then
                return "x1 Chromatic Box"
            elseif fLower:find("chromatic") or fLower:find("box") then
                return "x1 Chromatic Box"
            elseif FRUIT_ORDER[fLower] then
                return fruitName
            end
        end
    end

    -- 3. Se houver fruta configurada no currentSettings
    if currentSettings and currentSettings.item_name then
        local cfgFruit = tostring(currentSettings.item_name):lower():gsub("^%s*(.-)%s*$", "%1")
        if cfgFruit ~= "random" and cfgFruit ~= "generic" and cfgFruit ~= "fruit" and cfgFruit ~= "sword of destiny" and FRUIT_ORDER[cfgFruit] then
            return currentSettings.item_name
        end
    end

    -- 4. Fallback padrão seguro: "Rocket" (mais barata, 50 Robux, index 1)
    return "Rocket"
end

local function scrollAndFindFruit(scrollingFrame, fruitName)
    local targetIdx = FRUIT_ORDER[fruitName:lower()]
    task.wait(0.3)

    -- Utilitário: extrai nome de fruta de um slot (novo formato "Nome-Nome" ou antigo "Fruit[N]")
    local function getSlotFruitName(slot)
        -- Novo formato: "Magnet-Magnet" → "Magnet"
        local fromName = slot.Name:match("^(.-)%-")
        if fromName and fromName ~= "" then return fromName end
        -- Antigo formato: tenta pelo título interno
        local ok, title = pcall(function()
            return slot.CardButton.Profile.TopInfo.Title.Text
        end)
        if ok and title and title ~= "" then
            return title:gsub("<[^<>]->", ""):match("^%s*(.-)%s*$")
        end
        return nil
    end

    -- Encontra o slot alvo pelo nome direto (O(1), mais confiável)
    local function findTargetSlot()
        -- Novo formato: "Magnet-Magnet"
        local cap = fruitName:sub(1,1):upper() .. fruitName:sub(2):lower()
        local slot = scrollingFrame:FindFirstChild(cap .. "-" .. cap)
            or scrollingFrame:FindFirstChild(fruitName .. "-" .. fruitName)
            or scrollingFrame:FindFirstChild(fruitName:lower() .. "-" .. fruitName:lower())
        if slot then return slot end
        -- Varredura por title (fallback para frutas com nome diferente do slot)
        for _, child in ipairs(scrollingFrame:GetChildren()) do
            if child:IsA("GuiObject") then
                local slotFruit = getSlotFruitName(child)
                if slotFruit and slotFruit:lower() == fruitName:lower() then
                    return child
                end
            end
        end
        return nil
    end

    local function humanDelay()
        local d = 0.045 + math.random() * 0.065
        if math.random(1, 10) == 1 then d = d + 0.1 + math.random() * 0.15 end
        return d
    end

    local function humanStep(base)
        return math.max(8, base + math.random(-8, 8))
    end

    -- Tenta encontrar o slot
    local targetSlot = findTargetSlot()
    if not targetSlot then
        warn("[AutoBuyer] Slot para '" .. fruitName .. "' não encontrado na loja.")
        return nil
    end

    print("[AutoBuyer] Slot encontrado: " .. targetSlot.Name .. " → rolando até ele...")

    -- Rola o ScrollingFrame até o slot ficar visível na área central
    local maxAttempts = 80
    local maxScroll = scrollingFrame.AbsoluteCanvasSize.Y - scrollingFrame.AbsoluteWindowSize.Y
    local currentY = scrollingFrame.CanvasPosition.Y

    for _ = 1, maxAttempts do
        -- Calcula posição relativa do slot dentro do scrollingFrame
        local slotAbsY = targetSlot.AbsolutePosition.Y
        local frameAbsY = scrollingFrame.AbsolutePosition.Y
        local frameH = scrollingFrame.AbsoluteWindowSize.Y
        local slotH = targetSlot.AbsoluteSize.Y

        -- Centro do slot em relação ao topo do frame visível
        local slotCenterInFrame = slotAbsY - frameAbsY + slotH / 2
        local frameCenterY = frameH / 2

        if math.abs(slotCenterInFrame - frameCenterY) < slotH * 0.4 then
            -- Slot visível e centrado
            print("[AutoBuyer] Fruta '" .. fruitName .. "' centralizada na loja!")
            task.wait(0.08 + math.random() * 0.07)
            return targetSlot
        end

        -- Direção e passo
        local diff = slotCenterInFrame - frameCenterY
        local step = humanStep(math.min(math.abs(diff) * 0.5, 45))
        local direction = diff > 0 and 1 or -1
        currentY = math.clamp(currentY + step * direction, 0, maxScroll)
        scrollingFrame.CanvasPosition = Vector2.new(0, currentY)
        task.wait(humanDelay())

        maxScroll = scrollingFrame.AbsoluteCanvasSize.Y - scrollingFrame.AbsoluteWindowSize.Y
    end

    -- Fallback: retorna o slot mesmo que não esteja perfeitamente centrado
    warn("[AutoBuyer] Centralização não concluída, retornando slot encontrado mesmo assim.")
    return targetSlot
end


local function clickGiftButton(giftButton)
    forceClick(giftButton)
end

---------------------------------------------------------
-- PROCESSO GIFT WINDOW E SELEÇÃO DE USUÁRIO
---------------------------------------------------------
local function setBridgeUsername(username, fruitName, giftButton)
    if not username or username == "" then return end
    
    activeTargetPlayer = username
    selectedPlayerName = username
    if fruitName and fruitName ~= "" and fruitName:lower() ~= "generic" and fruitName ~= "Fruit" and fruitName ~= "Sword of Destiny" then
        activeTargetFruit = fruitName
        lastDetectedInGameItem = fruitName
    end
    
    print("[AutoBuyer] Processando GiftWindow para: " .. username)
    
    local success, err = pcall(function()
        local giftWindow = playerGui:FindFirstChild("GiftWindow")
        
        local attempts = 0
        while (not giftWindow or not giftWindow.Enabled or not giftWindow:FindFirstChild("Window") or not giftWindow.Window.Visible) and attempts < 3 do
            attempts = attempts + 1
            logStep("Tentativa " .. attempts .. " de abrir GiftWindow...")
            if giftButton then
                clickGiftButton(giftButton)
            end
            task.wait(1.5)
            giftWindow = playerGui:FindFirstChild("GiftWindow")
        end
        
        if not giftWindow then 
            error("Não foi possível carregar a GiftWindow após " .. attempts .. " tentativas.")
            return 
        end
        
        local window = giftWindow:WaitForChild("Window", 5)
        if not window then return end
        
        local content = window:WaitForChild("Content", 5)
        if not content then return end

        logStep("Aguardando ativação visual da GiftWindow...")
        local startV = os.clock()
        while (not giftWindow.Enabled or not window.Visible) and (os.clock() - startV) < 5 do
            task.wait(0.05)
        end
        
        -- Humano visualiza a GiftWindow aberta e prepara para interagir
        task.wait(0.45 + math.random(30, 80) / 1000)

        local overlay = window:FindFirstChild("Overlay")
        task.spawn(function()
            while giftWindow.Enabled and window.Visible do
                task.wait(0.2)
            end
            if overlay then
                for _, child in ipairs(overlay:GetChildren()) do
                    child.Visible = true
                    if child:IsA("GuiObject") then
                        child.Active = true
                    end
                end
            end
        end)

        -- Clica no GlobalButton
        local navigation = content:WaitForChild("Navigation", 5)
        if navigation then
            local globalButton = navigation:WaitForChild("GlobalButton", 5)
            if globalButton then
                task.wait(0.25 + math.random(30, 70) / 1000)
                logStep("Clicando no botão Global...")
                cleanMouseClick(globalButton)
                task.wait(0.32 + math.random(30, 80) / 1000)
            end
        end

        -- Clica na caixa de texto e digita letra por letra
        logStep("Pesquisando o username do jogador: " .. username .. "...", 3)
        local searchFrame = navigation:WaitForChild("SearchFrame", 5)
        local searchBox = searchFrame:WaitForChild("TextBox", 5)
        
        task.wait(0.22 + math.random(30, 70) / 1000)
        cleanMouseClick(searchBox)
        task.wait(0.15 + math.random(20, 50) / 1000)
        
        typeHuman(searchBox, username)

        local delayRemoveOverlay = 0.12 + (math.random(20, 80) / 1000)
        task.wait(delayRemoveOverlay)

        if overlay then
            for _, child in ipairs(overlay:GetChildren()) do
                child.Visible = false
                if child:IsA("GuiObject") then
                    child.Active = false
                end
            end
        end

        -- Aguarda o jogador surgir na PlayerList
        local playerList = content:WaitForChild("PlayerList", 5)
        
        local playerItem = nil
        local searchStart = os.clock()
        while not playerItem and (os.clock() - searchStart) < 3.5 do
            for _, child in ipairs(playerList:GetChildren()) do
                local parts = string.split(child.Name, ":")
                if parts[1] and parts[1]:lower() == username:lower() then
                    playerItem = child
                    break
                end
            end
            if not playerItem then
                task.wait(0.05)
            end
        end

        if playerItem then
            local playerTextButton = playerItem:WaitForChild("TextButton", 5)
            -- Humano confere o jogador que apareceu na lista antes de clicar nele
            task.wait(0.38 + math.random(40, 100) / 1000)
            logStep("Selecionando o jogador da lista...", 4)
            selectedPlayerName = username
            activeTargetPlayer = username
            cleanMouseClick(playerTextButton)
            
            -- Clica em Purchase (Presentear)
            local purchaseButton = content:WaitForChild("Buttons", 5):WaitForChild("Purchase", 5)
            -- Humano desce o olhar e clica em Purchase com tempo natural
            task.wait(0.42 + math.random(50, 100) / 1000)
            logStep("Clicando no botão de Compra (Purchase)...", 5)
            cleanMouseClick(purchaseButton)
        else
            warn("[AutoBuyer] O jogador " .. username .. " não foi encontrado na lista a tempo.")
            logStep("Erro: Jogador não encontrado na lista")
            
            pcall(function()
                local cancelBtn = content:WaitForChild("Buttons", 1):WaitForChild("Cancel", 1)
                if cancelBtn then
                    cleanMouseClick(cancelBtn)
                else
                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Escape, false, game)
                    task.wait(0.04)
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Escape, false, game)
                end
            end)
            purchaseComplete = true
            reportPurchaseFinished("aborted", "GiftWindow fechada ou cancelada")
        end
    end)
    
    if not success then
        warn("[AutoBuyer] Erro no fluxo da GiftWindow: " .. tostring(err))
        logStep("Erro na GiftWindow: " .. tostring(err))
        purchaseComplete = true
        reportPurchaseFinished("error", tostring(err))
    end
end

-- Processo completo de auto-compra acionado pelo servidor
local autoBuyBusy = false
local currentBuyId = 0
local function executeBuyFruit(username, fruitName, queueItemId)
    if autoBuyBusy then
        warn("[AutoBuyer] Já está processando outra compra, aguarde...")
        logStep("Aguarde: Compra anterior ainda em andamento")
        return
    end
    
    autoBuyBusy = true
    watchdogAborted = false
    currentBuyId = currentBuyId + 1
    local myBuyId = currentBuyId
    currentBuyItemId = queueItemId or currentBuyItemId or 0
    activeTargetPlayer = username
    selectedPlayerName = username

    local finalFruit = resolveFruitToBuy(fruitName)
    activeTargetFruit = finalFruit
    lastDetectedInGameItem = finalFruit

    -- WATCHDOG TIMER: aborta e destrava automaticamente
    local totalTimeout = tonumber(currentSettings.step_timeouts and currentSettings.step_timeouts.total) or 30
    task.delay(totalTimeout, function()
        if autoBuyBusy and currentBuyId == myBuyId and not watchdogAborted then
            warn(string.format("[Watchdog] Timeout de %ds atingido! Destravando para '%s'", totalTimeout, username))
            abortCurrentBuy("Timeout total excedido")
            purchaseComplete = true
            reportPurchaseFinished("aborted", "Timeout excedido no Roblox", username, finalFruit, currentBuyItemId)
            autoBuyBusy = false
        end
    end)
    
    print("[AutoBuyer] ========================================")
    print(string.format("[AutoBuyer] Iniciando compra: %s para %s (ID: %s)", tostring(finalFruit), tostring(username), tostring(currentBuyItemId)))
    activeTargetPlayer = username
    activeTargetFruit = finalFruit
    logStep("Recebeu nick: " .. tostring(username), 1)
    
    local success, err = pcall(function()
        logStep("Verificando loja de frutas no Roblox...")
        local shopGui = playerGui:FindFirstChild("FruitShopAndDealer")
        
        -- Se a loja estiver fechada, espera até 6 segundos para o streamer abri-la
        if not shopGui then
            logStep("Aviso: Abra a Loja de Frutas (Fruit Dealer) no Roblox!")
            local startWaitShop = os.clock()
            while not shopGui and (os.clock() - startWaitShop) < 6 do
                task.wait(0.5)
                shopGui = playerGui:FindFirstChild("FruitShopAndDealer")
            end
        end

        local existingGiftWindow = playerGui:FindFirstChild("GiftWindow")
        local giftWindowOpen = existingGiftWindow and existingGiftWindow.Enabled and existingGiftWindow:FindFirstChild("Window") and existingGiftWindow.Window.Visible

        if not giftWindowOpen then
            if not shopGui then
                warn("[AutoBuyer] Loja de frutas continua fechada!")
                logStep("Erro: Abra a Loja de Frutas no Roblox")
                reportPurchaseFinished("aborted", "Loja de frutas fechada", username, finalFruit, currentBuyItemId)
                return
            end
            
            local scrollingFrame = shopGui:FindFirstChild("Shop")
                and shopGui.Shop:FindFirstChild("Menu")
                and shopGui.Shop.Menu:FindFirstChild("Content")
                and shopGui.Shop.Menu.Content:FindFirstChild("Body")
                and shopGui.Shop.Menu.Content.Body:FindFirstChild("ScrollingFrame")
            if not scrollingFrame then
                warn("[AutoBuyer] ScrollingFrame da loja não encontrado!")
                reportPurchaseFinished("error", "ScrollingFrame não encontrado", username, finalFruit, currentBuyItemId)
                return
            end
            
            logStep("Buscando fruta " .. finalFruit .. " na loja...")
            local fruitSlot = scrollAndFindFruit(scrollingFrame, finalFruit)
            
            if not fruitSlot then
                warn("[AutoBuyer] Fruta '" .. finalFruit .. "' não encontrada. Tentando Rocket ou slot ativo...")
                fruitSlot = scrollAndFindFruit(scrollingFrame, "Rocket") or (function()
                    for _, c in ipairs(scrollingFrame:GetChildren()) do
                        if c:IsA("GuiObject") then return c end
                    end
                end)()
            end
            
            if not fruitSlot then
                warn("[AutoBuyer] Nenhum slot de fruta disponível na loja!")
                logStep("Erro: Fruta não encontrada na loja")
                reportPurchaseFinished("error", "Fruta não encontrada na loja", username, finalFruit, currentBuyItemId)
                return
            end
        
        -- Verifica se o painel já está aberto e o botão Gift já está visível
        local controlPanel = fruitSlot:FindFirstChild("ControlPanel")
        local content = controlPanel and controlPanel:FindFirstChild("Content")
        local buttons = content and content:FindFirstChild("Buttons")
        local giftButton = buttons and buttons:FindFirstChild("GiftButton")
        
        local alreadyOpen = giftButton and giftButton.Visible and giftButton.AbsoluteSize.Y > 0
        
        if not alreadyOpen then
            task.wait(0.25 + math.random(30, 80) / 1000)
            logStep("Clicando no slot da fruta " .. finalFruit .. "...")
            clickSlotElement(fruitSlot)
            task.wait(0.35 + math.random(40, 80) / 1000)
            
            -- Se for Chromatic Box, usa o slot da loja (Rocket ou fallback) como gatilho do GiftWindow
            local chromCfg = getChromaticBoxConfig(finalFruit)
            if not chromCfg then
                local successV, titleV = pcall(function()
                    return fruitSlot.CardButton.Profile.TopInfo.Title.Text
                end)
                -- Aceita match pelo título OU pelo nome do slot (novo formato "Nome-Nome")
                local slotNameMatch = fruitSlot.Name:match("^(.-)%-"):lower() == finalFruit:lower()
                if not slotNameMatch and (not successV or not titleV or titleV:lower() ~= finalFruit:lower()) then
                    local stableSlot = scrollAndFindFruit(scrollingFrame, finalFruit)
                    if stableSlot then
                        fruitSlot = stableSlot
                        clickSlotElement(fruitSlot)
                        task.wait(0.35 + math.random(40, 80) / 1000)
                    end
                end
            end
            
            controlPanel = fruitSlot:WaitForChild("ControlPanel", 5)
            content = controlPanel and controlPanel:WaitForChild("Content", 5)
            buttons = content and content:WaitForChild("Buttons", 5)
            giftButton = buttons and buttons:WaitForChild("GiftButton", 5)
        else
            logStep("Painel da fruta " .. finalFruit .. " já está aberto. Pulando clique inicial.")
        end
        
        if giftButton then
            local startTime = os.clock()
            while (giftButton.AbsoluteSize.Y <= 0 or not giftButton.Visible) and (os.clock() - startTime) < 1.8 do
                task.wait(0.02)
            end
            
            -- Humano vê o botão Gift aparecer no painel expandido
            task.wait(0.35 + math.random(40, 100) / 1000)
            logStep("Clicando no botão de Presente (Gift)...", 2)
            clickGiftButton(giftButton)
            
            logStep("Aguardando janela de envio (GiftWindow) carregar...")
            task.wait(0.45 + math.random(50, 120) / 1000)
        else
            warn("[AutoBuyer] GiftButton não encontrado!")
        end
        end -- Fecha if not giftWindowOpen then

        logStep("Inserindo o nick do usuário: " .. username .. "...")
        setBridgeUsername(username, finalFruit, giftButton)
        
        purchaseComplete = false
        logStep("Aguardando fluxo completo (Buy → OK → Cancel)...")
        local waitStart = os.clock()
        while not purchaseComplete and not watchdogAborted and (os.clock() - waitStart) < 8 do
            task.wait(0.1)
        end
        if watchdogAborted then
            logStep("Compra abortada pelo Watchdog.")
            return
        end
        if not purchaseComplete then
            warn("[AutoBuyer] Timeout aguardando o fim do fluxo de compra. Continuando.")
            purchaseComplete = true
        end
        
        logStep("Username " .. username .. " inserido! Compra preparada com sucesso.")
    end)
    
    if not success then
        warn("[AutoBuyer] Erro durante auto-compra: " .. tostring(err))
    end
    
    if not watchdogAborted then
        -- Cooldown humano crível entre uma entrega e outra (streamer respira e vai para o próximo)
        local cooldownDelay = 1.3 + math.random() * 0.7
        logStep(string.format("Aguardando %.1fs de intervalo antes da próxima compra...", cooldownDelay))
        task.wait(cooldownDelay)
    end
    
    activeTargetFruit = nil
    autoBuyBusy = false
end

---------------------------------------------------------
-- FECHAMENTO NATIVO (ESC / MENU NATIVO)
---------------------------------------------------------
GuiService.MenuOpened:Connect(function()
    if screenGui.Enabled then closeGui() end
    if successGui.Enabled then closeSuccessGui() end
end)

---------------------------------------------------------
-- TIKTOK LIVE BRIDGE (WEBSOCKET & HTTP POLLING) E CONFIG UI
---------------------------------------------------------
local lastBridgeUsername = ""
local lastBridgeFruit = ""

local settingsGui = Instance.new("ScreenGui")
settingsGui.Name = "BridgeSettingsGui"
settingsGui.ResetOnSpawn = false
settingsGui.DisplayOrder = 9999999
settingsGui.Parent = playerGui

local settingsFrame = Instance.new("Frame")
settingsFrame.Name = "SettingsFrame"
settingsFrame.Size = UDim2.fromOffset(250, 310)
settingsFrame.Position = UDim2.new(1, -265, 0, 15)
settingsFrame.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
settingsFrame.Visible = false
settingsFrame.Parent = settingsGui

frameCorner = Instance.new("UICorner")
frameCorner.CornerRadius = UDim.new(0, 10)
frameCorner.Parent = settingsFrame

frameStroke = Instance.new("UIStroke")
frameStroke.Color = Color3.fromRGB(55, 55, 62)
frameStroke.Thickness = 1
frameStroke.Parent = settingsFrame

local frameTitle = Instance.new("TextLabel")
frameTitle.Size = UDim2.new(1, -40, 0, 24)
frameTitle.Position = UDim2.new(0, 10, 0, 8)
frameTitle.BackgroundTransparency = 1
frameTitle.Text = "Configurações"
frameTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
frameTitle.TextSize = 13
frameTitle.Font = Enum.Font.BuilderSansBold
frameTitle.TextXAlignment = Enum.TextXAlignment.Left
frameTitle.Parent = settingsFrame

local closeSettingsBtn = createCloseIcon(settingsFrame, 20)
closeSettingsBtn.Position = UDim2.new(1, -26, 0, 8)
closeSettingsBtn.MouseButton1Click:Connect(function()
    settingsFrame.Visible = false
end)

local wsStatusLabel = Instance.new("TextLabel")
wsStatusLabel.Name = "WsStatusLabel"
wsStatusLabel.Size = UDim2.new(1, -20, 0, 16)
wsStatusLabel.Position = UDim2.new(0, 10, 0, 32)
wsStatusLabel.BackgroundTransparency = 1
wsStatusLabel.Text = "● Desconectado"
wsStatusLabel.TextColor3 = Color3.fromRGB(220, 60, 60)
wsStatusLabel.TextSize = 11
wsStatusLabel.Font = Enum.Font.BuilderSansMedium
wsStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
wsStatusLabel.Parent = settingsFrame

local function createInput(placeholder, yPos, parent)
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, -20, 0, 28)
    box.Position = UDim2.new(0, 10, 0, yPos)
    box.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
    box.PlaceholderText = placeholder
    box.PlaceholderColor3 = Color3.fromRGB(115, 115, 120)
    box.Text = ""
    box.TextColor3 = Color3.fromRGB(255, 255, 255)
    box.TextSize = 12
    box.Font = Enum.Font.BuilderSansMedium
    box.Parent = parent
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 5)
    corner.Parent = box
    
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(45, 45, 52)
    stroke.Thickness = 1
    stroke.Parent = box
    
    return box
end

-- 1. Input da Chave / Script Token
local tokenInput = createInput("Chave / Token do Site (bgl_...)", 52, settingsFrame)
if SCRIPT_TOKEN and SCRIPT_TOKEN ~= "" and SCRIPT_TOKEN ~= "SEU_TOKEN_AQUI" then
    tokenInput.Text = SCRIPT_TOKEN
end

-- 2. Input de Robux Simulado
robuxInput = createInput("Mock Robux (ex: 750,000)", 84, settingsFrame)
robuxInput.Text = currentSettings.mock_balance or "750,000"

-- Botão de Roletar Robux
local rollRobuxBtn = Instance.new("TextButton")
rollRobuxBtn.Name = "RollRobuxBtn"
rollRobuxBtn.Size = UDim2.new(1, -20, 0, 24)
rollRobuxBtn.Position = UDim2.new(0, 10, 0, 116)
rollRobuxBtn.BackgroundColor3 = Color3.fromRGB(180, 100, 20)
rollRobuxBtn.Text = "🎲 Roletar Robux (700k - 1M)"
rollRobuxBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
rollRobuxBtn.TextSize = 11
rollRobuxBtn.Font = Enum.Font.BuilderSansBold
rollRobuxBtn.Parent = settingsFrame

rollCorner = Instance.new("UICorner")
rollCorner.CornerRadius = UDim.new(0, 5)
rollCorner.Parent = rollRobuxBtn

rollRobuxBtn.MouseButton1Click:Connect(function()
    local newR = rollRandomRobux()
    rollRobuxBtn.Text = "✅ Roletado: " .. newR
    task.delay(1.5, function()
        pcall(function()
            rollRobuxBtn.Text = "🎲 Roletar Robux (700k - 1M)"
        end)
    end)
end)

-- 3. Toggle Switch Animado do ROBLOX PLUS (-10% off)
local rbxPlusFrame = Instance.new("Frame")
rbxPlusFrame.Name = "RobloxPlusFrame"
rbxPlusFrame.Size = UDim2.new(1, -20, 0, 30)
rbxPlusFrame.Position = UDim2.new(0, 10, 0, 144)
rbxPlusFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
rbxPlusFrame.BorderSizePixel = 0
rbxPlusFrame.Parent = settingsFrame

rbxPlusCorner = Instance.new("UICorner")
rbxPlusCorner.CornerRadius = UDim.new(0, 6)
rbxPlusCorner.Parent = rbxPlusFrame

rbxPlusStroke = Instance.new("UIStroke")
rbxPlusStroke.Color = Color3.fromRGB(42, 42, 48)
rbxPlusStroke.Thickness = 1
rbxPlusStroke.Parent = rbxPlusFrame

local rbxPlusLabel = Instance.new("TextLabel")
rbxPlusLabel.Size = UDim2.new(1, -55, 1, 0)
rbxPlusLabel.Position = UDim2.new(0, 8, 0, 0)
rbxPlusLabel.BackgroundTransparency = 1
rbxPlusLabel.Text = "ROBLOX PLUS (-10%)"
rbxPlusLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
rbxPlusLabel.TextSize = 11
rbxPlusLabel.Font = Enum.Font.BuilderSansBold
rbxPlusLabel.TextXAlignment = Enum.TextXAlignment.Left
rbxPlusLabel.Parent = rbxPlusFrame

local switchButton = Instance.new("TextButton")
switchButton.Name = "SwitchButton"
switchButton.Size = UDim2.new(0, 42, 0, 20)
switchButton.Position = UDim2.new(1, -48, 0.5, -10)
switchButton.BorderSizePixel = 0
switchButton.Text = ""
switchButton.AutoButtonColor = false
switchButton.Parent = rbxPlusFrame

switchCorner = Instance.new("UICorner")
switchCorner.CornerRadius = UDim.new(1, 0)
switchCorner.Parent = switchButton

local switchBall = Instance.new("Frame")
switchBall.Name = "SwitchBall"
switchBall.Size = UDim2.new(0, 16, 0, 16)
switchBall.BorderSizePixel = 0
switchBall.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
switchBall.Parent = switchButton

ballCorner = Instance.new("UICorner")
ballCorner.CornerRadius = UDim.new(1, 0)
ballCorner.Parent = switchBall

local function updateRobloxPlusUI(enabled, animated)
    local targetColor = enabled and Color3.fromRGB(40, 180, 60) or Color3.fromRGB(180, 40, 40)
    local targetPos = enabled and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
    if animated then
        TweenService:Create(switchButton, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundColor3 = targetColor
        }):Play()
        TweenService:Create(switchBall, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Position = targetPos
        }):Play()
    else
        switchButton.BackgroundColor3 = targetColor
        switchBall.Position = targetPos
    end
end

updateRobloxPlusUI(currentSettings.roblox_plus == true, false)

switchButton.MouseButton1Click:Connect(function()
    currentSettings.roblox_plus = not (currentSettings.roblox_plus == true)
    updateRobloxPlusUI(currentSettings.roblox_plus, true)
    pcall(saveConfig)
    
    -- Atualiza a Buy GUI se estiver aberta
    if screenGui and screenGui.Enabled then
        if currentSettings.roblox_plus then
            if promoFrame then promoFrame.Visible = false end
            local curPrice = parseNumber(priceText.Text) or 0
            priceText.Text = formatNumber(math.floor(curPrice * 0.9))
        else
            if promoFrame then promoFrame.Visible = true end
            local origPrice = lastDetectedInGamePrice or GENERIC_ITEM_PRICE
            priceText.Text = formatNumber(origPrice)
        end
    end
end)

-- 4. Tecla de Atalho
local keybindInput = createInput("Tecla de Atalho (ex: P)", 178, settingsFrame)
keybindInput.Text = currentSettings.toggle_key or "P"

-- 5. Botão Salvar e Sincronizar
local saveBtn = Instance.new("TextButton")
saveBtn.Name = "SaveBtn"
saveBtn.Size = UDim2.new(1, -20, 0, 30)
saveBtn.Position = UDim2.new(0, 10, 0, 210)
saveBtn.BackgroundColor3 = Color3.fromRGB(53, 81, 198)
saveBtn.Text = "Salvar e Sincronizar"
saveBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
saveBtn.TextSize = 12
saveBtn.Font = Enum.Font.BuilderSansBold
saveBtn.Parent = settingsFrame

saveCorner = Instance.new("UICorner")
saveCorner.CornerRadius = UDim.new(0, 6)
saveCorner.Parent = saveBtn

-- 6. Botão Reconectar Bridge
local reconnectBtn = Instance.new("TextButton")
reconnectBtn.Name = "ReconnectBtn"
reconnectBtn.Size = UDim2.new(1, -20, 0, 28)
reconnectBtn.Position = UDim2.new(0, 10, 0, 244)
reconnectBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 60)
reconnectBtn.Text = "↺ Reconectar Bridge"
reconnectBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
reconnectBtn.TextSize = 12
reconnectBtn.Font = Enum.Font.BuilderSansBold
reconnectBtn.Parent = settingsFrame

reconnectCorner = Instance.new("UICorner")
reconnectCorner.CornerRadius = UDim.new(0, 6)
reconnectCorner.Parent = reconnectBtn

local isCloudConnected = false
local cloudStreamerName = ""

local function setWsStatus(connected, streamerName)
    if connected then
        local stText = streamerName and (" (" .. streamerName .. ")") or ""
        wsStatusLabel.Text = "● Conectado" .. stText
        wsStatusLabel.TextColor3 = Color3.fromRGB(50, 220, 90)
        reconnectBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 60)
        reconnectBtn.Text = "↺ Reconectar Bridge"
    else
        if isCloudConnected then
            local stText = cloudStreamerName ~= "" and (" (" .. cloudStreamerName .. ")") or ""
            wsStatusLabel.Text = "● Conectado" .. stText
            wsStatusLabel.TextColor3 = Color3.fromRGB(50, 220, 90)
            reconnectBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 60)
            reconnectBtn.Text = "↺ Reconectar Bridge"
        else
            wsStatusLabel.Text = "● Desconectado"
            wsStatusLabel.TextColor3 = Color3.fromRGB(220, 60, 60)
            reconnectBtn.BackgroundColor3 = Color3.fromRGB(140, 40, 40)
            reconnectBtn.Text = "↺ Reconectar Bridge"
        end
    end
end

-- Forward declaration
local startHttpPolling

local function validateTokenWithCloud(token)
    local clean = sanitizeToken(token)
    if clean == "" or clean == "SEU_TOKEN_AQUI" then
        isCloudConnected = false
        cloudStreamerName = ""
        setWsStatus(false)
        wsStatusLabel.Text = "● Chave não configurada"
        return false
    end
    
    wsStatusLabel.Text = "⏳ Validando chave na nuvem..."
    wsStatusLabel.TextColor3 = Color3.fromRGB(220, 180, 40)
    print("[AutoBuyer] Validando chave na nuvem: '" .. clean .. "'...")
    
    local url = VERCEL_API_URL .. "/api/script/game_settings?token=" .. HttpService:UrlEncode(clean)
    local ok, response, statusCode = universalHttpRequest(url, "GET")
    
    print("[AutoBuyer] Resposta da nuvem (Status " .. tostring(statusCode) .. "): " .. tostring(response))
    
    if response and response ~= "" then
        local decOk, decoded = pcall(function() return HttpService:JSONDecode(response) end)
        if decOk and type(decoded) == "table" then
            if not decoded.error and (statusCode == 200 or statusCode == 0) then
                local streamerName = decoded.username or decoded.user_id or "Online"
                isCloudConnected = true
                cloudStreamerName = "Nuvem - " .. streamerName
                setWsStatus(true, cloudStreamerName)
                
                local finalToken = decoded.script_token or clean
                SCRIPT_TOKEN = finalToken
                currentSettings.script_token = finalToken
                if tokenInput then tokenInput.Text = finalToken end
                pcall(function()
                    if writefile then writefile("bgl_token.txt", finalToken) end
                end)
                pcall(saveConfig)
                
                -- Vincula e valida a trava da conta Roblox
                local linkOk, linkErr = verifyAndLinkRobloxAccount(finalToken)
                if not linkOk then
                    isCloudConnected = false
                    cloudStreamerName = ""
                    setWsStatus(false)
                    wsStatusLabel.Text = "● Chave travada em outra conta"
                    warn("[AutoBuyer] Chave bloqueada para esta conta: " .. tostring(linkErr))
                    return false
                end
                
                startRobloxHeartbeat()
                if startHttpPolling then startHttpPolling() end
                
                print("[AutoBuyer] Chave validada com sucesso para " .. streamerName .. "!")
                return true
            else
                isCloudConnected = false
                cloudStreamerName = ""
                local errMsg = decoded.error or ("Erro HTTP " .. tostring(statusCode))
                setWsStatus(false)
                wsStatusLabel.Text = "● " .. tostring(errMsg)
                warn("[AutoBuyer] Falha na validação da chave: " .. tostring(errMsg))
                return false
            end
        end
    end
    
    isCloudConnected = false
    cloudStreamerName = ""
    setWsStatus(false)
    local failText = (statusCode and statusCode > 0) and ("● Erro HTTP " .. tostring(statusCode)) or "● Sem conexão com Vercel"
    wsStatusLabel.Text = failText
    warn("[AutoBuyer] Falha ao conectar à API Vercel: " .. tostring(response))
    return false
end

local function syncGuiWithSettings(settings)
    if not settings then return end

    -- Atualiza mock_balance APENAS se o servidor enviou um valor válido (não nulo e não o fallback antigo 5,420)
    -- e NUNCA durante uma compra ativa ou quando a buy GUI está aberta
    if settings.mock_balance and tostring(settings.mock_balance) ~= "" and tostring(settings.mock_balance) ~= "null" and tostring(settings.mock_balance) ~= "5,420" then
        if not autoBuyBusy and (not screenGui or not screenGui.Enabled) then
            currentSettings.mock_balance = formatNumber(settings.mock_balance)
            if balanceText then balanceText.Text = currentSettings.mock_balance end
            if robuxInput then robuxInput.Text = currentSettings.mock_balance end
        end
    end
    
    if settings.item_name and settings.item_name ~= "" and settings.item_name:lower() ~= "generic" and settings.item_name ~= "Fruit" and settings.item_name ~= "Sword of Destiny" and settings.item_name ~= "Mock Item Name" then
        currentSettings.item_name = settings.item_name
    end
    
    if settings.item_price and tostring(settings.item_price) ~= "" and tostring(settings.item_price) ~= "null" and tostring(settings.item_price) ~= "1,250" and tostring(settings.item_price) ~= "1250" then
        currentSettings.item_price = formatNumber(settings.item_price)
    end

    currentSettings.toggle_key = settings.toggle_key or currentSettings.toggle_key or "P"
    currentSettings.post_delivery_delay = tonumber(settings.post_delivery_delay) or currentSettings.post_delivery_delay or 2
    if settings.roblox_plus ~= nil then
        currentSettings.roblox_plus = settings.roblox_plus == true
    end
    if settings.script_token and settings.script_token ~= "" and settings.script_token ~= "SEU_TOKEN_AQUI" then
        SCRIPT_TOKEN = settings.script_token
        currentSettings.script_token = settings.script_token
    end
    
    if settings.step_timeouts and type(settings.step_timeouts) == "table" then
        currentSettings.step_timeouts = currentSettings.step_timeouts or {}
        for k, v in pairs(settings.step_timeouts) do
            currentSettings.step_timeouts[k] = tonumber(v) or currentSettings.step_timeouts[k] or 30
        end
    end
    
    pcall(saveConfig)
    
    if not autoBuyBusy and (not screenGui or not screenGui.Enabled) and robuxInput then 
        robuxInput.Text = currentSettings.mock_balance 
    end
    if tokenInput and SCRIPT_TOKEN and SCRIPT_TOKEN ~= "SEU_TOKEN_AQUI" then tokenInput.Text = SCRIPT_TOKEN end
    if keybindInput then keybindInput.Text = currentSettings.toggle_key end
    updateRobloxPlusUI(currentSettings.roblox_plus == true, false)
end

syncGuiWithSettings(currentSettings)

if SCRIPT_TOKEN and SCRIPT_TOKEN ~= "" and SCRIPT_TOKEN ~= "SEU_TOKEN_AQUI" then
    task.spawn(function()
        task.wait(1)
        validateTokenWithCloud(SCRIPT_TOKEN)
    end)
end

local function sendSettingsToBridge()
    local rawToken = sanitizeToken(tokenInput.Text)
    if rawToken ~= "" and rawToken ~= "SEU_TOKEN_AQUI" then
        SCRIPT_TOKEN = rawToken
        currentSettings.script_token = rawToken
        pcall(function()
            if writefile then writefile("bgl_token.txt", rawToken) end
        end)
    end

    local rawKey = keybindInput.Text:gsub("%s+", ""):upper()
    if rawKey ~= "" then
        currentSettings.toggle_key = rawKey
    end

    if robuxInput.Text ~= "" then
        currentSettings.mock_balance = formatNumber(robuxInput.Text)
    end

    pcall(saveConfig)

    -- Valida o token com a API da Vercel
    task.spawn(function()
        validateTokenWithCloud(SCRIPT_TOKEN)
    end)

    local payload = {
        mock_balance = currentSettings.mock_balance,
        toggle_key = currentSettings.toggle_key,
        roblox_plus = currentSettings.roblox_plus,
        script_token = SCRIPT_TOKEN
    }
    
    if activeWS then
        local wsMsg = HttpService:JSONEncode({
            type = "update_game_settings",
            settings = payload
        })
        pcall(function()
            if activeWS.Send then activeWS:Send(wsMsg) elseif activeWS.send then activeWS:send(wsMsg) end
        end)
    end
    
    task.spawn(function()
        pcall(function()
            HttpService:PostAsync(
                "http://127.0.0.1:" .. HTTP_PORT .. "/update_game_settings",
                HttpService:JSONEncode({ settings = payload }),
                Enum.HttpContentType.ApplicationJson
            )
        end)
    end)
end

saveBtn.MouseButton1Click:Connect(sendSettingsToBridge)

local function handleBridgeMessage(decoded)
    if decoded.action == "buy_fruit" then
        local username = decoded.username
        local fruit = decoded.fruit
        
        if username and username ~= "" then
            if autoBuyBusy then
                warn("[AutoBuyer] Ignorando comando: outra compra já em andamento")
                return
            end
            lastBridgeUsername = username
            lastBridgeFruit = fruit or ""
            local qId = decoded.id or 0
            currentBuyItemId = qId
            
            print("[AutoBuyer] Comando recebido: Comprar '" .. tostring(fruit) .. "' para '" .. tostring(username) .. "' (ID: " .. tostring(qId) .. ")")
            task.spawn(function() executeBuyFruit(username, fruit, qId) end)
        end
    elseif decoded.action == "set_username" then
        -- Ignora set_username durante uma compra ativa (evita corrupção do nick em andamento)
        if autoBuyBusy then return end
        local username = decoded.username
        if username and username ~= "" and username ~= lastBridgeUsername then
            lastBridgeUsername = username
            setBridgeUsername(username, "")
        end
    elseif decoded.action == "update_settings" then
        syncGuiWithSettings(decoded.settings)
    elseif decoded.action == "live_proof" or decoded.action == "anti_record" then
        local msg = decoded.message or ""
        local dur = decoded.duration or 4
        print("[AutoBuyer] 🎭 Prova de Live ativada! Andando em círculos e falando: " .. tostring(msg))
        performLiveProof(dur, msg)
    elseif decoded.action == "roll_robux" then
        rollRandomRobux()
    end
end

-- Polling HTTP com backoff suave (Vercel Cloud + Servidor Local)
local httpPollingStarted = false
startHttpPolling = function()
    if httpPollingStarted then return end
    httpPollingStarted = true
    print("[AutoBuyer] Iniciando Polling HTTP (Vercel Cloud + Servidor Local)...")
    
    local failedNext = 0
    task.spawn(function()
        while true do
            if autoBuyBusy then
                task.wait(0.5)
            else
                local success, response = false, nil
                local tokenQ = getTokenQuery()
                
                -- 1. Puxa próximo da fila na Nuvem Vercel via universalHttpRequest
                if tokenQ ~= "" then
                    local cloudUrl = VERCEL_API_URL .. "/api/script/next" .. tokenQ .. "&source=roblox"
                    local ok, res, st = universalHttpRequest(cloudUrl, "GET")
                    if ok and res and res ~= "" then
                        success, response = true, res
                    elseif st == 429 then
                        warn("[AutoBuyer] Roblox HttpService rate-limited (429)! Aplicando backoff de segurança...")
                        task.wait(4.0)
                    end
                end
                
                -- 2. Fallback para servidor local se nuvem não retornou nada
                if not success or not response or response == "" then
                    local localOk, localRes = pcall(function()
                        return HttpService:GetAsync("http://127.0.0.1:" .. HTTP_PORT .. "/next", true)
                    end)
                    if localOk and localRes and localRes ~= "" then
                        success, response = true, localRes
                    end
                end
                
                if success and response and response ~= "" then
                    failedNext = 0
                    local dataSuccess, decoded = pcall(function() return HttpService:JSONDecode(response) end)
                    if dataSuccess and decoded and decoded.username and decoded.username ~= "" then
                        currentBuyItemId = decoded.id or 0
                        print("[AutoBuyer] Fila Nuvem -> Comprando para @" .. tostring(decoded.username) .. " | Fruta: " .. tostring(decoded.fruit) .. " | ID: " .. tostring(decoded.id))
                        handleBridgeMessage({
                            action = "buy_fruit",
                            username = decoded.username,
                            fruit = decoded.fruit or "",
                            id = decoded.id
                        })
                    end
                    task.wait(0.5)
                else
                    failedNext = failedNext + 1
                    local waitInterval = math.min(8.0, 0.8 * (1.5 ^ math.min(failedNext, 6)))
                    task.wait(waitInterval)
                end
            end
        end
    end)
    
    local failedSettings = 0
    task.spawn(function()
        while true do
            local success, response = false, nil
            local tokenQ = getTokenQuery()
            
            -- Sincroniza configurações da nuvem
            if tokenQ ~= "" then
                local cloudSettingsUrl = VERCEL_API_URL .. "/api/script/game_settings" .. tokenQ
                local ok, res = universalHttpRequest(cloudSettingsUrl, "GET")
                if ok and res and res ~= "" then
                    success, response = true, res
                end
            end
            
            -- Fallback para servidor local
            if not success or not response or response == "" then
                local localOk, localRes = pcall(function()
                    return HttpService:GetAsync("http://127.0.0.1:" .. HTTP_PORT .. "/game_settings", true)
                end)
                if localOk and localRes and localRes ~= "" then
                    success, response = true, localRes
                end
            end
            
            if success and response and response ~= "" then
                failedSettings = 0
                local dataSuccess, decoded = pcall(function() return HttpService:JSONDecode(response) end)
                if dataSuccess and decoded and not decoded.error then
                    syncGuiWithSettings(decoded)
                end
                task.wait(2.5)
            else
                failedSettings = failedSettings + 1
                if failedSettings > 3 then
                    task.wait(4)
                else
                    task.wait(1.5)
                end
            end
        end
    end)
end

-- Controle do loop de reconexão do WebSocket
local wsReconnectEnabled = false
local wsForceReconnect = false
local wsIsConnecting = false

local function connectToBridge()
    if wsIsConnecting then return end
    wsIsConnecting = true

    local wsConnect = syn and syn.websocket and syn.websocket.connect
        or (WebSocket and (WebSocket.connect or WebSocket.new))

    if not wsConnect then
        wsIsConnecting = false
        startHttpPolling()
        return
    end

    task.spawn(function()
        wsForceReconnect = false

        local tokenQ = getTokenQuery()
        local success, ws = false, nil
        if tokenQ ~= "" then
            success, ws = pcall(function() return wsConnect(CLOUD_WS_URL .. "/ws" .. tokenQ) end)
        end
        if not success or not ws then
            success, ws = pcall(function() return wsConnect(WS_URL) end)
        end

        if success and ws then
            activeWS = ws
            setWsStatus(true)
            print("[AutoBuyer] WebSocket conectado com sucesso ao servidor Bridge (Multi-tenant).")

            pcall(function()
                local idMsg = HttpService:JSONEncode({ client_type = "roblox", token = SCRIPT_TOKEN })
                if ws.Send then ws:Send(idMsg) elseif ws.send then ws:send(idMsg) end

                local syncMsg = HttpService:JSONEncode({
                    type = "update_game_settings",
                    settings = currentSettings
                })
                if ws.Send then ws:Send(syncMsg) elseif ws.send then ws:send(syncMsg) end
            end)

            local connection = ws.OnMessage or ws.on_message
            if connection then
                connection:Connect(function(msg)
                    local dataSuccess, decoded = pcall(function() return HttpService:JSONDecode(msg) end)
                    if dataSuccess and decoded then handleBridgeMessage(decoded) end
                end)
            else
                task.spawn(function()
                    while true do
                        local ok, msg = pcall(function() return ws:Receive() end)
                        if ok and msg then
                            local dataSuccess, decoded = pcall(function() return HttpService:JSONDecode(msg) end)
                            if dataSuccess and decoded then handleBridgeMessage(decoded) end
                        else
                            break
                        end
                    end
                end)
            end

            local closed = false
            local closeConn = ws.OnClose or ws.on_close
            if closeConn then
                closeConn:Connect(function()
                    closed = true
                    activeWS = nil
                    setWsStatus(false)
                    wsIsConnecting = false
                    print("[AutoBuyer] WebSocket desconectou. Modo Nuvem continua ativo.")
                end)
                while not closed and not wsForceReconnect do
                    task.wait(1)
                end
            else
                while not wsForceReconnect do
                    task.wait(3)
                    local pingOk = pcall(function()
                        local pingMsg = HttpService:JSONEncode({ type = "ping" })
                        if ws.Send then ws:Send(pingMsg) elseif ws.send then ws:send(pingMsg) end
                    end)
                    if not pingOk then
                        activeWS = nil
                        setWsStatus(false)
                        wsIsConnecting = false
                        print("[AutoBuyer] WebSocket perdeu conexão. Modo Nuvem continua ativo.")
                        break
                    end
                end
            end

            activeWS = nil
            setWsStatus(false)
        else
            -- Falhou conexão com WebSocket local/render
            if not isCloudConnected then
                setWsStatus(false)
            end
            print("[AutoBuyer] WebSocket local offline. Polling HTTP em Nuvem ativo.")
        end

        wsIsConnecting = false

        if wsForceReconnect then
            task.wait(0.5)
            connectToBridge()
        end
    end)
end

task.spawn(connectToBridge)
task.spawn(startHttpPolling)

reconnectBtn.MouseButton1Click:Connect(function()
    if wsIsConnecting then return end  -- Ignora cliques duplicados
    
    wsForceReconnect = true
    reconnectBtn.Text = "↺ Reconectando..."
    reconnectBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 30)
    
    -- Valida e reconecta à chave na nuvem
    task.spawn(function()
        local tokToValidate = (tokenInput and tokenInput.Text ~= "") and tokenInput.Text or SCRIPT_TOKEN
        validateTokenWithCloud(tokToValidate)
    end)
    
    if activeWS then
        pcall(function()
            if activeWS.Close then activeWS:Close() elseif activeWS.close then activeWS:close() end
        end)
        activeWS = nil
    end
    -- Tenta conectar diretamente
    task.wait(0.3)
    connectToBridge()
end)

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
    if input.KeyCode == Enum.KeyCode.Escape then
        if screenGui.Enabled then closeGui() end
        if successGui.Enabled then closeSuccessGui() end
        if settingsFrame.Visible then settingsFrame.Visible = false end
    end
    
    if not gameProcessedEvent then
        local keyName = currentSettings.toggle_key or "P"
        local success, targetKey = pcall(function() return Enum.KeyCode[keyName] end)
        if success and targetKey and input.KeyCode == targetKey then
            settingsFrame.Visible = not settingsFrame.Visible
        end
    end
end)

print("[AutoBuyer] Blox Fruits Auto-Buyer carregado com suporte Offline e Bridge!")
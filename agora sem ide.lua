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
local TextChatService = pcall(function() return game:GetService("TextChatService") end) and game:GetService("TextChatService") or nil

local player = Players.LocalPlayer or Players.PlayerAdded:Wait()
local playerGui = player:WaitForChild("PlayerGui")

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
    ["spirit"] = 2550, ["dragon"] = 2600, ["leopard"] = 3000, ["kitsune"] = 4000
}

local currentSettings = {
    mock_balance = "5,420",
    item_name = "Sword of Destiny",
    item_price = "1,250",
    item_image = "rbxassetid://6071895945",
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
local SCRIPT_TOKEN = "SEU_TOKEN_AQUI" -- Cole o token gerado no site https://bgl-queue.vercel.app
pcall(function()
    if readfile and isfile and isfile("bgl_token.txt") then
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
    
    -- 1. Executores modernos (request / http_request / syn.request / http.request)
    local req = (type(request) == "function" and request)
        or (type(http_request) == "function" and http_request)
        or (syn and type(syn.request) == "function" and syn.request)
        or (http and type(http.request) == "function" and http.request)
        
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
            if type(res) == "string" and res ~= "" then
                return true, res, 200
            elseif type(res) == "table" then
                local resBody = res.Body or res.body or res.Data or res.data
                local statusCode = tonumber(res.StatusCode or res.status_code or res.statusCode) or 200
                if resBody and type(resBody) == "string" then
                    return (statusCode >= 200 and statusCode < 300), resBody, statusCode
                end
            end
        end
    end
    
    -- 2. Métodos nativos de executor game:HttpGet / game:HttpGetAsync
    if method == "GET" then
        local getOk, getRes = pcall(function()
            return game:HttpGet(url)
        end)
        if getOk and getRes and type(getRes) == "string" and getRes ~= "" then
            return true, getRes, 200
        end
        
        local getAsyncOk, getAsyncRes = pcall(function()
            return game:HttpGetAsync(url)
        end)
        if getAsyncOk and getAsyncRes and type(getAsyncRes) == "string" and getAsyncRes ~= "" then
            return true, getAsyncRes, 200
        end
    end
    
    -- 3. Fallback HttpService (Roblox Studio ou executores com bridge)
    local hsOk, hsRes = pcall(function()
        if method == "GET" then
            return HttpService:GetAsync(url, true)
        else
            return HttpService:PostAsync(url, body or "", Enum.HttpContentType.ApplicationJson)
        end
    end)
    if hsOk and hsRes and type(hsRes) == "string" and hsRes ~= "" then
        return true, hsRes, 200
    end
    
    return false, "Nenhum método HTTP disponível ou conexão recusada", 0
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
    
    -- Notifica o servidor que abortou
    pcall(function()
        local hs = game:GetService("HttpService")
        local finishedMsg = hs:JSONEncode({ type = "purchase_finished", status = "aborted", reason = reason })
        if activeWS then
            if activeWS.Send then activeWS:Send(finishedMsg) elseif activeWS.send then activeWS:send(finishedMsg) end
        end
        local tokenQ = getTokenQuery()
        local sent = false
        if tokenQ ~= "" then
            pcall(function()
                hs:PostAsync(VERCEL_API_URL .. "/api/script/purchase_finished" .. tokenQ, finishedMsg, Enum.HttpContentType.ApplicationJson)
                sent = true
            end)
            if not sent then
                pcall(function()
                    hs:PostAsync(CLOUD_SERVER_URL .. "/purchase_finished" .. tokenQ, finishedMsg, Enum.HttpContentType.ApplicationJson)
                    sent = true
                end)
            end
        end
        if not sent then
            hs:PostAsync("http://127.0.0.1:" .. HTTP_PORT .. "/purchase_finished", finishedMsg, Enum.HttpContentType.ApplicationJson)
        end
    end)
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

    local bgCorner = Instance.new("UICorner")
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

    local bar1Corner = Instance.new("UICorner")
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

local function logStep(stepName)
    print("[AutoBuyer - Passo] " .. stepName)
    pcall(function()
        if activeWS then
            local msg = HttpService:JSONEncode({
                type = "automation_step",
                step = stepName
            })
            if activeWS.Send then
                activeWS:Send(msg)
            elseif activeWS.send then
                activeWS:send(msg)
            end
        end
    end)
    task.spawn(function()
        pcall(function()
            local payload = HttpService:JSONEncode({ step = stepName })
            local tokenQ = getTokenQuery()
            local sent = false
            if tokenQ ~= "" then
                pcall(function()
                    HttpService:PostAsync(VERCEL_API_URL .. "/api/script/automation_step" .. tokenQ, payload, Enum.HttpContentType.ApplicationJson)
                    sent = true
                end)
                if not sent then
                    pcall(function()
                        HttpService:PostAsync(CLOUD_SERVER_URL .. "/automation_step" .. tokenQ, payload, Enum.HttpContentType.ApplicationJson)
                        sent = true
                    end)
                end
            end
            if not sent then
                HttpService:PostAsync(
                    "http://127.0.0.1:" .. HTTP_PORT .. "/automation_step",
                    payload,
                    Enum.HttpContentType.ApplicationJson
                )
            end
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

-- Extrai o nome limpo do item a partir do texto de contexto da GiftWindow
local function extractItemNameFromContextText(rawText)
    if not rawText or rawText == "" then return nil end
    local clean = stripRobloxRichTextTags(rawText)
    
    -- 1. Tenta extrair conteúdo entre <...> (ex: "Gift <2x Money> to a friend", "Gift <Permanent Buddha> to")
    local inBrackets = clean:match("<%s*([^<>]+)%s*>")
    if inBrackets and inBrackets ~= "" then
        local candidate = inBrackets:gsub("[}%]\"']", ""):match("^%s*(.-)%s*$")
        if candidate and candidate ~= "" and not candidate:lower():find("font") and not candidate:lower():find("stroke") then
            return candidate
        end
    end
    
    -- 2. Tenta regex "Gift [Item] to" ou "Presentear [Item] para"
    local afterGift = clean:match("^[Gg]ift%s+(.-)%s+[Tt]o") 
        or clean:match("^[Pp]resentear%s+(.-)%s+[Pp]ara")
        or clean:match("[Gg]ift%s+(.-)%s+[Tt]o")
        or clean:match("[Pp]resentear%s+(.-)%s+[Pp]ara")
    if afterGift and afterGift ~= "" then
        local candidate = afterGift:gsub("<[^<>]->", ""):gsub("[}%]\"']", ""):match("^%s*(.-)%s*$")
        if candidate and candidate ~= "" then
            return candidate
        end
    end
    
    -- 3. Tenta "Gift [Item]" no final
    local justGift = clean:match("^[Gg]ift%s+(.-)$") or clean:match("^[Pp]resentear%s+(.-)$")
    if justGift and justGift ~= "" then
        local candidate = justGift:gsub("<[^<>]->", ""):gsub("[}%]\"']", ""):match("^%s*(.-)%s*$")
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

-- Varre a GiftWindow aberta no jogo procurando o nome do item/gamepass
local function scanGiftWindowForName(giftWindow)
    if not giftWindow then return nil end
    
    -- 1. Verifica no Footer.Context (padrão oficial do Blox Fruits)
    local footer = giftWindow:FindFirstChild("Window") and giftWindow.Window:FindFirstChild("Footer")
    local context = footer and footer:FindFirstChild("Context")
    if context and context.Text and context.Text ~= "" then
        local extracted = extractItemNameFromContextText(context.Text)
        if extracted and extracted ~= "" and extracted:lower() ~= "generic" and extracted ~= "Fruit" and extracted ~= "Sword of Destiny" then
            return extracted
        end
    end
    
    -- 2. Varre descendentes da GiftWindow procurando textos de itens/gamepasses
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
            
            local clean = stripRobloxRichTextTags(raw):gsub("[}%]\"']", ""):match("^%s*(.-)%s*$")
            if clean and clean ~= "" and not ignoredTexts[clean:lower()] and not clean:match("^[%d,%.%s]+$") and #clean >= 3 and #clean <= 45 then
                local lower = clean:lower()
                if lower:find("fruit") or lower:find("pass") or lower:find("2x") or lower:find("storage") 
                    or lower:find("boat") or lower:find("blade") or lower:find("notifier") or lower:find("money")
                    or lower:find("mastery") or lower:find("drop") or lower:find("perm") then
                    return clean
                end
            end
        end
    end
    
    return nil
end

-- Captura a fruta selecionada diretamente no painel aberto da loja do jogo (FruitShopAndDealer)
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
        if slot:IsA("GuiObject") and slot.Name:find("Fruit") then
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
                if title and title.Text and title.Text ~= "" then
                    local cleanName = title.Text:gsub("<[^<>]->", ""):gsub("[}%]{}\"]", ""):match("^%s*(.-)%s*$")
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

-- DETECÇÃO TOTALMENTE INDEPENDENTE DO SERVIDOR: SEMPRE PEGA O NOME REAL NO JOGO
local function detectRealInGameItemName()
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
    
    -- 3. Terceira prioridade: se houver fruta real definida pelo comando de compra do bot
    if activeTargetFruit and activeTargetFruit ~= "" and activeTargetFruit:lower() ~= "generic" and activeTargetFruit ~= "Fruit" and activeTargetFruit ~= "Sword of Destiny" and activeTargetFruit ~= "Mock Item Name" then
        lastDetectedInGameItem = activeTargetFruit
        return activeTargetFruit
    end
    
    -- 4. Quarta prioridade: último item verificado capturado no jogo
    if lastDetectedInGameItem and lastDetectedInGameItem ~= "" and lastDetectedInGameItem:lower() ~= "generic" and lastDetectedInGameItem ~= "Fruit" and lastDetectedInGameItem ~= "Sword of Destiny" and lastDetectedInGameItem ~= "Mock Item Name" then
        return lastDetectedInGameItem
    end
    
    -- 5. Se itemNameLabel tiver algo que NÃO seja generic/mock/sword of destiny
    if itemNameLabel and itemNameLabel.Text and itemNameLabel.Text ~= "" then
        local t = itemNameLabel.Text:gsub("<[^<>]->", ""):gsub("[}%]{}\"]", ""):match("^%s*(.-)%s*$")
        if t and t ~= "" and t:lower() ~= "generic" and t ~= "Fruit" and t ~= "Sword of Destiny" and t ~= "Mock Item Name" then
            return t
        end
    end
    
    -- Fallback limpo: se nada foi detectado ainda, retorna "Fruit" (NUNCA "Generic" ou "Sword of Destiny")
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
    
    -- Gamepasses NÃO devem receber o prefixo "Permanent" (ex: "Fast Boats", "2x Money", "Dark Blade", "Fruit Notifier", "+1 Fruit Storage")
    local lower = titleCase:lower()
    local isGamepass = false
    local gamepassKeywords = {"2x money", "2x mastery", "2x boss drops", "fast boats", "dark blade", "fruit notifier", "+1 fruit storage", "fruit storage", "gamepass"}
    for _, kw in ipairs(gamepassKeywords) do
        if lower:find(kw, 1, true) then
            isGamepass = true
            break
        end
    end
    if not isGamepass and (lower:find("boat") or lower:find("blade") or lower:find("notifier") or lower:find("storage") or lower:find("2x")) then
        isGamepass = true
    end
    
    if not isGamepass and not titleCase:lower():find("permanent") and titleCase:lower() ~= "fruit" then
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
        
        -- Altera OS DOIS OBRIGATORIAMENTE:
        -- 1) NotificationTemplate (o fundo)
        -- 2) NotificationTemplate.TextLabel (o texto em si)
        local function aplicarNosDois(fundoObj)
            if not fundoObj then return end
            
            -- [1] Altera no FUNDO: NotificationTemplate
            pcall(function()
                fundoObj.Visible = true
                if fundoObj:IsA("TextLabel") or pcall(function() return fundoObj.Text end) then
                    fundoObj.RichText = true
                    fundoObj.Text = textoFormatado
                    fundoObj.TextTransparency = 0
                end
            end)
            
            -- [2] Altera no TEXTO EM SI: NotificationTemplate.TextLabel
            local textoObj = fundoObj:FindFirstChild("TextLabel")
            if textoObj then
                pcall(function()
                    textoObj.Visible = true
                    textoObj.RichText = true
                    textoObj.Text = textoFormatado
                    textoObj.TextTransparency = 0
                end)
            end
            
            -- [3] Garante também em qualquer outro TextLabel/TextBox filho ou sombra
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
            
            -- Se for a NotificationStack sendo instanciada
            if child.Name == "NotificationStack" then
                table.insert(connections, child.ChildAdded:Connect(function(newChild)
                    handleNotificationItem(newChild)
                end))
                return
            end
            
            -- Detecta NotificationTemplate ou qualquer notificação gerada nativamente
            if child.Name == "NotificationTemplate" or child.Name:find("Notification") or child:FindFirstChild("TextLabel") or child:IsA("TextLabel") then
                handled = true
                for _, conn in ipairs(connections) do
                    pcall(function() conn:Disconnect() end)
                end
                
                -- Aplica nos dois (fundo e texto) repetidamente durante a transição
                aplicarNosDois(child)
                task.wait()
                aplicarNosDois(child)
                task.delay(0.04, function() aplicarNosDois(child) end)
                task.delay(0.1, function() aplicarNosDois(child) end)
                task.delay(0.2, function() aplicarNosDois(child) end)
                
                -- Deixa o script nativo do Blox Fruits gerenciar o tempo de tela e a animação
                -- de saída deslizando para o lado (sem child:Destroy() forçado)
            end
        end
        
        -- Escuta em NotificationStack (onde as notificações são empilhadas pelo jogo)
        if stack then
            table.insert(connections, stack.ChildAdded:Connect(handleNotificationItem))
        end
        table.insert(connections, notifications.ChildAdded:Connect(handleNotificationItem))
        table.insert(connections, notifications.DescendantAdded:Connect(handleNotificationItem))
        
        -- Timeout de segurança para desconectar os listeners
        task.delay(3, function()
            if not handled then
                for _, conn in ipairs(connections) do
                    pcall(function() conn:Disconnect() end)
                end
            end
        end)
        
        -- Aciona o remote nativo para o Blox Fruits gerar a notificação animada
        if commF then
            pcall(function() commF:InvokeServer("activateTitle", "") end)
        end
    end

    -- 1. Primeiro texto: ativa remote pro primeiro texto
    local textoSending = string.format('Sending Gift <font color="rgb(240, 185, 20)">%s</font> to %s..', fruitName, username)
    dispararNotificacaoNativa(textoSending)

    -- 2. Segundo texto: ativa remote novamente após 0.8s para empilhar um embaixo do outro
    task.delay(0.8, function()
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

-- Descansa o cursor do mouse em coordenada aleatória vazia
local function restMouse()
    local viewportSize = workspace.CurrentCamera.ViewportSize
    local rx = math.random(math.floor(viewportSize.X * 0.15), math.floor(viewportSize.X * 0.85))
    local ry = math.random(math.floor(viewportSize.Y * 0.15), math.floor(viewportSize.Y * 0.85))
    if mousemoveabs then
        pcall(function() mousemoveabs(rx, ry) end)
    else
        pcall(function() VirtualInputManager:SendMouseMoveEvent(rx, ry, game) end)
    end
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

local successCorner = Instance.new("UICorner")
successCorner.CornerRadius = UDim.new(0, 14)
successCorner.Parent = successFrame

local successStroke = Instance.new("UIStroke")
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

local checkHolder = Instance.new("Frame")
checkHolder.AnchorPoint = Vector2.new(0.5, 0)
checkHolder.Position = UDim2.new(0.5, 0, 0, 58)
checkHolder.Size = UDim2.new(0, 44, 0, 44)
checkHolder.BackgroundTransparency = 1
checkHolder.Parent = successFrame

local checkCircle = Instance.new("UICorner")
checkCircle.CornerRadius = UDim.new(1, 0)
checkCircle.Parent = checkHolder

local checkStroke = Instance.new("UIStroke")
checkStroke.Color = Color3.fromRGB(230, 230, 230)
checkStroke.Thickness = 2.5
checkStroke.Parent = checkHolder

local checkShortBar = Instance.new("Frame")
checkShortBar.AnchorPoint = Vector2.new(0.5, 0.5)
checkShortBar.Size = UDim2.new(0, 11, 0, 3)
checkShortBar.Position = UDim2.new(0, 16, 0, 25)
checkShortBar.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
checkShortBar.BorderSizePixel = 0
checkShortBar.Rotation = 45
checkShortBar.Parent = checkHolder

local checkShortCorner = Instance.new("UICorner")
checkShortCorner.CornerRadius = UDim.new(1, 0)
checkShortCorner.Parent = checkShortBar

local checkLongBar = Instance.new("Frame")
checkLongBar.AnchorPoint = Vector2.new(0.5, 0.5)
checkLongBar.Size = UDim2.new(0, 20, 0, 3)
checkLongBar.Position = UDim2.new(0, 26, 0, 20)
checkLongBar.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
checkLongBar.BorderSizePixel = 0
checkLongBar.Rotation = -50
checkLongBar.Parent = checkHolder

local checkLongCorner = Instance.new("UICorner")
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

local okCorner = Instance.new("UICorner")
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

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 12)
mainCorner.Parent = mainFrame

local mainStroke = Instance.new("UIStroke")
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

local imageCorner = Instance.new("UICorner")
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

local buyCorner = Instance.new("UICorner")
buyCorner.CornerRadius = UDim.new(0, 8)
buyCorner.Parent = buyButton

local buyClip = Instance.new("Frame")
buyClip.Size = UDim2.new(1, 0, 1, 0)
buyClip.BackgroundTransparency = 1
buyClip.ClipsDescendants = true
buyClip.ZIndex = 2
buyClip.Parent = buyButton

local buyClipCorner = Instance.new("UICorner")
buyClipCorner.CornerRadius = UDim.new(0, 8)
buyClipCorner.Parent = buyClip

local fill = Instance.new("Frame")
fill.Size = UDim2.new(0, 0, 1, 0)
fill.Position = UDim2.new(0, 0, 0, 0)
fill.BackgroundColor3 = Color3.fromRGB(53, 92, 255)
fill.BorderSizePixel = 0
fill.ZIndex = 2
fill.Parent = buyClip

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 8)
fillCorner.Parent = fill

local promoFrame = Instance.new("Frame")
promoFrame.Size = UDim2.new(1, -40, 0, 46)
promoFrame.Position = UDim2.new(0, 20, 0, 196)
promoFrame.BackgroundColor3 = Color3.fromRGB(32, 34, 39)
promoFrame.BorderSizePixel = 0
promoFrame.Parent = mainFrame

local promoCorner = Instance.new("UICorner")
promoCorner.CornerRadius = UDim.new(0, 10)
promoCorner.Parent = promoFrame

local promoStroke = Instance.new("UIStroke")
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

local badgeCorner = Instance.new("UICorner")
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

closeGui = function()
    currentBuyCycleId = currentBuyCycleId + 1 -- Invalida qualquer ciclo de compra pendente imediatamente!
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
end

local function openGui()
    if GuiBusy or screenGui.Enabled then return end
    GuiBusy = true
    buyPurchasedThisCycle = false
    currentBuyCycleId = currentBuyCycleId + 1
    local myCycleId = currentBuyCycleId
    
    -- Garante que o Buy GUI e a mensagem de sucesso tenham o nome REAL detectado no jogo
    local realItem = detectRealInGameItemName()
    if realItem and realItem ~= "" and realItem ~= "Fruit" and realItem:lower() ~= "generic" and realItem ~= "Sword of Destiny" then
        if itemNameLabel then itemNameLabel.Text = realItem end
        if successMessage then successMessage.Text = "You have successfully bought " .. realItem .. "." end
    end

    -- Suporte a ROBLOX PLUS: 10% de desconto no preço e oculta o aviso promocional
    pcall(function()
        local rawPrice = parseNumber(priceText.Text) or parseNumber(lastDetectedInGamePrice) or parseNumber(GENERIC_ITEM_PRICE) or 0
        if currentSettings.roblox_plus then
            if promoFrame then promoFrame.Visible = false end
            local discounted = math.floor(rawPrice * 0.9)
            if priceText then priceText.Text = formatNumber(discounted) end
        else
            if promoFrame then promoFrame.Visible = true end
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

        logStep("Clicando no botão de Compra (Buy)...")
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
            
            closeGui()
            task.wait(0.18 + math.random(20, 50) / 1000)
            openSuccessGui()
        end
        
        -- Humano visualiza a tela de sucesso da compra e clica em OK
        task.wait(0.55 + math.random(50, 120) / 1000)
        if successGui and successGui.Enabled then
            logStep("Confirmando a compra no botão OK...")
            cleanMouseClick(okButton)
        end
        
        -- Humano fecha a janela de presente (GiftWindow) que ficou ao fundo
        task.wait(0.38 + math.random(30, 80) / 1000)
        logStep("Fechando a interface do jogo (Clicando em Cancel)...")
        pcall(function()
            local giftWindow = playerGui:FindFirstChild("GiftWindow")
            local cancelBtn = giftWindow 
                and giftWindow:FindFirstChild("Window") 
                and giftWindow.Window:FindFirstChild("Content") 
                and giftWindow.Window.Content:FindFirstChild("Buttons")
                and giftWindow.Window.Content.Buttons:FindFirstChild("Cancel")
                
            if cancelBtn then
                cleanMouseClick(cancelBtn)
            else
                -- Fallback para ESC duplo caso o botão não seja encontrado
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Escape, false, game)
                task.wait(0.06 + math.random(10, 25) / 1000)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Escape, false, game)
                task.wait(0.12 + math.random(20, 50) / 1000)
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Escape, false, game)
                task.wait(0.06 + math.random(10, 25) / 1000)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Escape, false, game)
            end
        end)
        logStep("Compra finalizada e loja fechada!")
        task.wait(0.25 + math.random(30, 60) / 1000)
        purchaseComplete = true
        pcall(function()
            local finishedMsg = HttpService:JSONEncode({ type = "purchase_finished", status = "success" })
            if activeWS then
                if activeWS.Send then activeWS:Send(finishedMsg) elseif activeWS.send then activeWS:send(finishedMsg) end
            else
                HttpService:PostAsync("http://127.0.0.1:" .. HTTP_PORT .. "/purchase_finished", finishedMsg, Enum.HttpContentType.ApplicationJson)
            end
        end)
        task.spawn(restMouse)
    end)
end

closeButton.MouseButton1Click:Connect(closeGui)
overlayClick.MouseButton1Click:Connect(closeGui)

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
    buyInProgress = false
end)

---------------------------------------------------------
-- CAPTURA AUTOMÁTICA DE PREÇO E NOME DA JANELA DE COMPRA
---------------------------------------------------------
local function getAutomaticPriceAndName()
    local price = lastDetectedInGamePrice or GENERIC_ITEM_PRICE
    local itemName = detectRealInGameItemName()
    local itemImg = lastDetectedInGameImage or GENERIC_ITEM_IMAGE
    local imgColor = Color3.fromRGB(255, 255, 255)
    local imgTrans = 0
    local imgRectOffset = Vector2.new(0, 0)
    local imgRectSize = Vector2.new(0, 0)
    
    local giftWindow = playerGui:FindFirstChild("GiftWindow")
    if giftWindow then
        -- 1. Tenta extrair nome diretamente da GiftWindow via varredura aprofundada
        local detectedName = scanGiftWindowForName(giftWindow)
        if detectedName and detectedName ~= "" and detectedName:lower() ~= "generic" and detectedName ~= "Fruit" and detectedName ~= "Sword of Destiny" then
            itemName = detectedName
            lastDetectedInGameItem = detectedName
        end
        
        local content = giftWindow:FindFirstChild("Content", true)
        if content then
            -- 2. Lê o preço exato do botão Purchase na GiftWindow
            pcall(function()
                local buttons = content:FindFirstChild("Buttons")
                local purchase = buttons and buttons:FindFirstChild("Purchase")
                local textLabel = purchase and (purchase:FindFirstChild("TextLabel") or purchase:FindFirstChildWhichIsA("TextLabel"))
                if textLabel and textLabel.Text ~= "" then
                    local text = textLabel.Text:gsub("<[^<>]->" , "")
                    local clean = text:match("[%d,%.]+")
                    if clean then 
                        price = clean 
                        lastDetectedInGamePrice = clean
                    end
                end
            end)
            
            -- 3. Tenta pegar a imagem direto do slot ativo/expandido na loja
            local gotIcon = false
            pcall(function()
                local shopFruit, artIcon = getActiveFruitFromShop()
                if artIcon and artIcon.Image ~= "" then
                    itemImg = artIcon.Image
                    imgColor = artIcon.ImageColor3
                    imgTrans = artIcon.ImageTransparency
                    imgRectOffset = artIcon.ImageRectOffset
                    imgRectSize = artIcon.ImageRectSize
                    gotIcon = true
                    lastDetectedInGameImage = itemImg
                end
            end)
            
            -- Fallback de imagem: varre descendentes do GiftWindow procurando ImageLabel visível
            if not gotIcon then
                for _, child in ipairs(content:GetDescendants()) do
                    if child:IsA("ImageLabel") and child.Visible then
                        local img = child.Image
                        if img ~= "" and not img:find("robux") and not img:find("close") and not img:find("arrow") then
                            itemImg = img
                            imgColor = child.ImageColor3
                            imgTrans = child.ImageTransparency
                            imgRectOffset = child.ImageRectOffset
                            imgRectSize = child.ImageRectSize
                            lastDetectedInGameImage = itemImg
                            break
                        end
                    end
                end
            end
        end
    end
    
    return price, itemName, itemImg, imgColor, imgTrans, imgRectOffset, imgRectSize
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
                
                -- Prioridade absoluta para o nome detectado no jogo (GiftWindow ou Loja)
                if name and name ~= "" and name:lower() ~= "generic" and name ~= "Fruit" and name ~= "Sword of Destiny" then
                    lastDetectedInGameItem = name
                elseif activeTargetFruit and activeTargetFruit ~= "" and activeTargetFruit:lower() ~= "generic" and activeTargetFruit ~= "Fruit" and activeTargetFruit ~= "Sword of Destiny" then
                    name = activeTargetFruit
                    lastDetectedInGameItem = activeTargetFruit
                else
                    name = detectRealInGameItemName()
                    lastDetectedInGameItem = name
                end
                
                if FRUIT_PRICES[name:lower()] and (not price or price == GENERIC_ITEM_PRICE) then
                    price = tostring(FRUIT_PRICES[name:lower()])
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
                
                -- Se for Dragon / Permanent Dragon, busca a imagem real via MarketplaceService
                if name:lower():find("dragon") then
                    -- Product ID da Dragon Fruit no Blox Fruits
                    local DRAGON_PRODUCT_ID = 1131547469
                    local ok, productInfo = pcall(function()
                        return MarketplaceService:GetProductInfo(DRAGON_PRODUCT_ID, Enum.InfoType.Product)
                    end)
                    if ok and productInfo and productInfo.IconImageAssetId then
                        image = "rbxassetid://" .. productInfo.IconImageAssetId
                    else
                        -- Fallback caso a API falhe
                        image = "rbxassetid://2673336234"
                    end
                    imgColor = Color3.fromRGB(255, 255, 255)
                    imgTrans = 0
                    imgRectOffset = Vector2.new(0, 0)
                    imgRectSize = Vector2.new(0, 0)
                end
                
                itemImage.Image = image
                itemImage.ImageColor3 = imgColor or Color3.fromRGB(255, 255, 255)
                itemImage.ImageTransparency = imgTrans or 0
                itemImage.ImageRectOffset = imgRectOffset or Vector2.new(0, 0)
                itemImage.ImageRectSize = imgRectSize or Vector2.new(0, 0)
                
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
                
                openGui()
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
    ["spike"] = 6, ["flame"] = 7, ["falcon"] = 8, ["ice"] = 9, ["sand"] = 10,
    ["dark"] = 11, ["diamond"] = 12, ["light"] = 13, ["rubber"] = 14, ["barrier"] = 15,
    ["ghost"] = 16, ["magma"] = 17, ["quake"] = 18, ["buddha"] = 19, ["love"] = 20,
    ["spider"] = 21, ["sound"] = 22, ["phoenix"] = 23, ["portal"] = 24, ["rumble"] = 25,
    ["pain"] = 26, ["blizzard"] = 27, ["gravity"] = 28, ["mammoth"] = 29, ["t-rex"] = 30,
    ["dough"] = 31, ["shadow"] = 32, ["venom"] = 33, ["control"] = 34, ["spirit"] = 35,
    ["dragon"] = 36, ["leopard"] = 37, ["kitsune"] = 38
}

local function scrollAndFindFruit(scrollingFrame, fruitName)
    local targetIdx = FRUIT_ORDER[fruitName:lower()]
    task.wait(0.3)
    
    local function checkActiveSlots()
        for _, name in ipairs({"Fruit[1]", "Fruit[2]", "Fruit[3]", "Fruit[4]"}) do
            local slot = scrollingFrame:FindFirstChild(name)
            if slot then
                local success, title = pcall(function()
                    return slot.CardButton.Profile.TopInfo.Title.Text
                end)
                if success and title and title:lower() == fruitName:lower() then
                    return slot
                end
            end
        end
        return nil
    end

    local slot2 = scrollingFrame:WaitForChild("Fruit[2]", 5)
    if not slot2 then
        warn("[AutoBuyer] Slot Fruit[2] não foi encontrado.")
        return nil
    end

    local function getSlot2Title()
        local success, title = pcall(function()
            return slot2.CardButton.Profile.TopInfo.Title.Text
        end)
        return success and title or ""
    end

    local function alignToSlot2(foundSlot)
        if not foundSlot then return nil end
        if foundSlot.Name == "Fruit[2]" then
            print("[AutoBuyer] Fruta '" .. fruitName .. "' já está perfeitamente no Fruit[2]!")
            return slot2
        end
        
        local alignDir = 1
        if foundSlot.Name == "Fruit[1]" then
            alignDir = -1
        else
            alignDir = 1
        end
        
        print("[AutoBuyer] Fruta detectada no " .. foundSlot.Name .. ". Alinhando no Fruit[2]...")
        local currentY = scrollingFrame.CanvasPosition.Y
        local maxScroll = scrollingFrame.AbsoluteCanvasSize.Y - scrollingFrame.AbsoluteWindowSize.Y
        
        for _ = 1, 20 do
            local jitter = math.random(-5, 5)
            local moveAmt = (12 + jitter) * alignDir
            currentY = math.clamp(currentY + moveAmt, 0, maxScroll)
            scrollingFrame.CanvasPosition = Vector2.new(0, currentY)
            task.wait(0.035 + math.random() * 0.045)
            
            if math.random(1, 8) == 1 then
                task.wait(0.08 + math.random() * 0.12)
            end
            
            if getSlot2Title():lower() == fruitName:lower() then
                print("[AutoBuyer] Alinhamento concluído com sucesso!")
                task.wait(0.08 + math.random() * 0.07)
                return slot2
            end
        end
        
        return slot2
    end

    local found = checkActiveSlots()
    if found then
        return alignToSlot2(found)
    end

    local currentTitle = getSlot2Title()
    local currentY = scrollingFrame.CanvasPosition.Y
    local maxScroll = scrollingFrame.AbsoluteCanvasSize.Y - scrollingFrame.AbsoluteWindowSize.Y
    local step = 35

    local direction = 1
    local currentIdx = FRUIT_ORDER[currentTitle:lower()]
    
    if targetIdx and currentIdx then
        if currentIdx > targetIdx then
            direction = -1
        elseif currentIdx < targetIdx then
            direction = 1
        end
    else
        scrollingFrame.CanvasPosition = Vector2.new(0, 0)
        task.wait(0.15 + math.random() * 0.08)
        currentY = 0
        direction = 1
    end

    local function humanStep(remainingPixels)
        local baseStep
        if remainingPixels and remainingPixels < 150 then
            baseStep = math.max(10, remainingPixels * 0.3)
        else
            baseStep = step
        end
        local jitter = math.random(-8, 8)
        return math.max(8, baseStep + jitter)
    end
    
    local function humanDelay()
        local d = 0.045 + math.random() * 0.065
        if math.random(1, 10) == 1 then
            d = d + 0.1 + math.random() * 0.15
        end
        return d
    end
    
    while true do
        local remaining = math.abs(maxScroll * 0.5 - currentY)
        local s = humanStep(remaining)
        local nextY = currentY + (s * direction)
        if nextY < 0 then nextY = 0 end
        if nextY > maxScroll then nextY = maxScroll end
        
        scrollingFrame.CanvasPosition = Vector2.new(0, nextY)
        task.wait(humanDelay())
        
        found = checkActiveSlots()
        if found then
            return alignToSlot2(found)
        end
        
        if (direction == 1 and nextY >= maxScroll) or (direction == -1 and nextY <= 0) then
            break 
        end
        
        currentY = nextY
        maxScroll = scrollingFrame.AbsoluteCanvasSize.Y - scrollingFrame.AbsoluteWindowSize.Y
    end

    warn("[AutoBuyer] Ajuste fino falhou. Iniciando varredura do topo...")
    scrollingFrame.CanvasPosition = Vector2.new(0, 0)
    task.wait(0.15 + math.random() * 0.1)
    currentY = 0
    while currentY < maxScroll do
        local s = humanStep(nil)
        currentY = math.min(currentY + s, maxScroll)
        scrollingFrame.CanvasPosition = Vector2.new(0, currentY)
        task.wait(humanDelay())
        
        found = checkActiveSlots()
        if found then
            return alignToSlot2(found)
        end
        
        maxScroll = scrollingFrame.AbsoluteCanvasSize.Y - scrollingFrame.AbsoluteWindowSize.Y
        if currentY >= maxScroll then break end
    end

    return nil
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
        logStep("Clicando na caixa de pesquisa...")
        local searchFrame = navigation:WaitForChild("SearchFrame", 5)
        local searchBox = searchFrame:WaitForChild("TextBox", 5)
        
        task.wait(0.22 + math.random(30, 70) / 1000)
        cleanMouseClick(searchBox)
        task.wait(0.15 + math.random(20, 50) / 1000)
        
        logStep("Digitando o username do jogador: " .. username .. "...")
        typeHuman(searchBox, username)

        local delayRemoveOverlay = 0.12 + (math.random(20, 80) / 1000)
        task.wait(delayRemoveOverlay)

        if overlay then
            logStep("Removendo overlays de bloqueio...")
            for _, child in ipairs(overlay:GetChildren()) do
                child.Visible = false
                if child:IsA("GuiObject") then
                    child.Active = false
                end
            end
        end

        -- Aguarda o jogador surgir na PlayerList
        logStep("Aguardando o jogador aparecer na lista...")
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
            logStep("Selecionando o jogador da lista...")
            selectedPlayerName = username
            activeTargetPlayer = username
            cleanMouseClick(playerTextButton)
            
            -- Clica em Purchase (Presentear)
            local purchaseButton = content:WaitForChild("Buttons", 5):WaitForChild("Purchase", 5)
            -- Humano desce o olhar e clica em Purchase com tempo natural
            task.wait(0.42 + math.random(50, 100) / 1000)
            logStep("Clicando no botão de Compra (Purchase)...")
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
            pcall(function()
                local finishedMsg = HttpService:JSONEncode({ type = "purchase_finished", status = "aborted" })
                if activeWS then
                    if activeWS.Send then activeWS:Send(finishedMsg) elseif activeWS.send then activeWS:send(finishedMsg) end
                else
                    HttpService:PostAsync("http://127.0.0.1:" .. HTTP_PORT .. "/purchase_finished", finishedMsg, Enum.HttpContentType.ApplicationJson)
                end
            end)
        end
    end)
    
    if not success then
        warn("[AutoBuyer] Erro no fluxo da GiftWindow: " .. tostring(err))
        logStep("Erro na GiftWindow: " .. tostring(err))
        purchaseComplete = true
        pcall(function()
            local finishedMsg = HttpService:JSONEncode({ type = "purchase_finished", status = "error" })
            if activeWS then
                if activeWS.Send then activeWS:Send(finishedMsg) elseif activeWS.send then activeWS:send(finishedMsg) end
            else
                HttpService:PostAsync("http://127.0.0.1:" .. HTTP_PORT .. "/purchase_finished", finishedMsg, Enum.HttpContentType.ApplicationJson)
            end
        end)
    end
end

-- Processo completo de auto-compra acionado pelo servidor
local autoBuyBusy = false
local currentBuyId = 0
local function executeBuyFruit(username, fruitName)
    if autoBuyBusy then
        warn("[AutoBuyer] Já está processando outra compra, aguarde...")
        logStep("Erro: Já processando outra compra")
        return
    end
    
    autoBuyBusy = true
    watchdogAborted = false
    currentBuyId = currentBuyId + 1
    local myBuyId = currentBuyId
    activeTargetPlayer = username
    selectedPlayerName = username
    if fruitName and fruitName ~= "" and fruitName:lower() ~= "generic" and fruitName ~= "Fruit" and fruitName ~= "Sword of Destiny" then
        activeTargetFruit = fruitName
        lastDetectedInGameItem = fruitName
    end

    -- WATCHDOG TIMER: aborta automaticamente se o fluxo todo demorar demais
    local totalTimeout = tonumber(currentSettings.step_timeouts and currentSettings.step_timeouts.total) or 30
    task.delay(totalTimeout, function()
        if autoBuyBusy and currentBuyId == myBuyId and not watchdogAborted then
            warn(string.format("[Watchdog] Timeout total de %ds atingido! Abortando compra para '%s'", totalTimeout, username))
            abortCurrentBuy("Timeout total de " .. totalTimeout .. "s excedido")
            purchaseComplete = true
            autoBuyBusy = false
        end
    end)
    
    print("[AutoBuyer] ========================================")
    print("[AutoBuyer] Iniciando compra: " .. fruitName .. " para " .. username)
    print("[AutoBuyer] ========================================")
    logStep("Iniciando compra da fruta " .. fruitName .. " para " .. username)
    
    local success, err = pcall(function()
        logStep("Verificando se a loja de frutas está aberta...")
        local shopGui = playerGui:FindFirstChild("FruitShopAndDealer")
        if not shopGui then
            warn("[AutoBuyer] Loja de frutas fechada!")
            return
        end
        
        local scrollingFrame = shopGui.Shop.Menu.Content.Body.ScrollingFrame
        if not scrollingFrame then return end
        
        logStep("Buscando inteligentemente a fruta " .. fruitName .. " na loja...")
        local fruitSlot = scrollAndFindFruit(scrollingFrame, fruitName)
        
        if not fruitSlot then
            warn("[AutoBuyer] Fruta '" .. fruitName .. "' não encontrada na loja!")
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
            logStep("Clicando no slot da fruta " .. fruitName .. "...")
            clickSlotElement(fruitSlot)
            task.wait(0.35 + math.random(40, 80) / 1000)
            
            local successV, titleV = pcall(function()
                return fruitSlot.CardButton.Profile.TopInfo.Title.Text
            end)
            if not successV or not titleV or titleV:lower() ~= fruitName:lower() then
                local stableSlot = scrollAndFindFruit(scrollingFrame, fruitName)
                if stableSlot then
                    fruitSlot = stableSlot
                    clickSlotElement(fruitSlot)
                    task.wait(0.35 + math.random(40, 80) / 1000)
                end
            end
            
            controlPanel = fruitSlot:WaitForChild("ControlPanel", 5)
            content = controlPanel and controlPanel:WaitForChild("Content", 5)
            buttons = content and content:WaitForChild("Buttons", 5)
            giftButton = buttons and buttons:WaitForChild("GiftButton", 5)
        else
            logStep("Painel da fruta " .. fruitName .. " já está aberto. Pulando clique inicial.")
        end
        
        if giftButton then
            local startTime = os.clock()
            while (giftButton.AbsoluteSize.Y <= 0 or not giftButton.Visible) and (os.clock() - startTime) < 1.8 do
                task.wait(0.02)
            end
            
            -- Humano vê o botão Gift aparecer no painel expandido
            task.wait(0.35 + math.random(40, 100) / 1000)
            logStep("Clicando no botão de Presente (Gift)...")
            clickGiftButton(giftButton)
            
            logStep("Aguardando janela de envio (GiftWindow) carregar...")
            task.wait(0.45 + math.random(50, 120) / 1000)
            logStep("Inserindo o nick do usuário: " .. username .. "...")
            
            setBridgeUsername(username, fruitName, giftButton)
            
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
        else
            warn("[AutoBuyer] GiftButton não encontrado!")
        end
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

local frameCorner = Instance.new("UICorner")
frameCorner.CornerRadius = UDim.new(0, 10)
frameCorner.Parent = settingsFrame

local frameStroke = Instance.new("UIStroke")
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

local rollCorner = Instance.new("UICorner")
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

local rbxPlusCorner = Instance.new("UICorner")
rbxPlusCorner.CornerRadius = UDim.new(0, 6)
rbxPlusCorner.Parent = rbxPlusFrame

local rbxPlusStroke = Instance.new("UIStroke")
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

local switchCorner = Instance.new("UICorner")
switchCorner.CornerRadius = UDim.new(1, 0)
switchCorner.Parent = switchButton

local switchBall = Instance.new("Frame")
switchBall.Name = "SwitchBall"
switchBall.Size = UDim2.new(0, 16, 0, 16)
switchBall.BorderSizePixel = 0
switchBall.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
switchBall.Parent = switchButton

local ballCorner = Instance.new("UICorner")
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

local saveCorner = Instance.new("UICorner")
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

local reconnectCorner = Instance.new("UICorner")
reconnectCorner.CornerRadius = UDim.new(0, 6)
reconnectCorner.Parent = reconnectBtn

local function setWsStatus(connected, streamerName)
    if connected then
        local stText = streamerName and (" (" .. streamerName .. ")") or ""
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

local function validateTokenWithCloud(token)
    local clean = sanitizeToken(token)
    if clean == "" or clean == "SEU_TOKEN_AQUI" then
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
                setWsStatus(true, streamerName)
                local finalToken = decoded.script_token or clean
                SCRIPT_TOKEN = finalToken
                currentSettings.script_token = finalToken
                if tokenInput then tokenInput.Text = finalToken end
                pcall(function()
                    if writefile then writefile("bgl_token.txt", finalToken) end
                end)
                pcall(saveConfig)
                print("[AutoBuyer] Chave validada com sucesso para " .. streamerName .. "!")
                return true
            else
                local errMsg = decoded.error or ("Erro HTTP " .. tostring(statusCode))
                setWsStatus(false)
                wsStatusLabel.Text = "● " .. tostring(errMsg)
                warn("[AutoBuyer] Falha na validação da chave: " .. tostring(errMsg))
                return false
            end
        end
    end
    
    setWsStatus(false)
    local failText = (statusCode and statusCode > 0) and ("● Erro HTTP " .. tostring(statusCode)) or "● Sem conexão com Vercel"
    wsStatusLabel.Text = failText
    warn("[AutoBuyer] Falha ao conectar à API Vercel: " .. tostring(response))
    return false
end

local function syncGuiWithSettings(settings)
    if not settings then return end
    currentSettings.mock_balance = formatNumber(settings.mock_balance or currentSettings.mock_balance)
    
    local realInGame = detectRealInGameItemName()
    if realInGame and realInGame ~= "" and realInGame ~= "Fruit" and realInGame:lower() ~= "generic" and realInGame ~= "Sword of Destiny" and realInGame ~= "Mock Item Name" then
        currentSettings.item_name = realInGame
    elseif settings.item_name and settings.item_name ~= "" and settings.item_name:lower() ~= "generic" and settings.item_name ~= "Fruit" and settings.item_name ~= "Sword of Destiny" and settings.item_name ~= "Mock Item Name" then
        currentSettings.item_name = settings.item_name
    end
    
    currentSettings.item_price = formatNumber(settings.item_price or currentSettings.item_price)
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
    
    pcall(function()
        if balanceText then balanceText.Text = currentSettings.mock_balance end
        
        local displayItem = detectRealInGameItemName()
        if displayItem and displayItem ~= "" and displayItem ~= "Fruit" and displayItem:lower() ~= "generic" and displayItem ~= "Sword of Destiny" and displayItem ~= "Mock Item Name" then
            if itemNameLabel then itemNameLabel.Text = displayItem end
            if successMessage then successMessage.Text = "You have successfully bought " .. displayItem .. "." end
        end
        
        if priceText then
            local numPrice = parseNumber(currentSettings.item_price) or 0
            if currentSettings.roblox_plus then
                numPrice = math.floor(numPrice * 0.9)
                if promoFrame then promoFrame.Visible = false end
            else
                if promoFrame then promoFrame.Visible = true end
            end
            priceText.Text = formatNumber(numPrice)
        end
    end)
    
    if robuxInput then robuxInput.Text = currentSettings.mock_balance end
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
        
        if username and username ~= "" and fruit and fruit ~= "" and fruit:lower() ~= "generic" and fruit:lower() ~= "fruit" and fruit ~= "Sword of Destiny" then
            -- Evita duplicata: ignora se é exatamente o mesmo pedido repetido
            if username == lastBridgeUsername and fruit == lastBridgeFruit then return end
            lastBridgeUsername = username
            lastBridgeFruit = fruit
            
            print("[AutoBuyer] Comando recebido: Comprar '" .. fruit .. "' para '" .. username .. "'")
            task.spawn(function() executeBuyFruit(username, fruit) end)
        elseif username and username ~= "" then
            -- set_username só executa se NÃO houver compra em andamento
            if not autoBuyBusy and username ~= lastBridgeUsername then
                lastBridgeUsername = username
                setBridgeUsername(username, "")
            end
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

-- Polling HTTP ultra rápido (0.1s) com fallback
local function startHttpPolling()
    local failedNext = 0
    task.spawn(function()
        while true do
            -- Se WebSocket estiver conectado ou compra em andamento, espera 0.1s
            if autoBuyBusy then
                task.wait(0.1)
            else
                local success, response = false, nil
                local tokenQ = getTokenQuery()
                if tokenQ ~= "" then
                    success, response = pcall(function()
                        return HttpService:GetAsync(VERCEL_API_URL .. "/api/script/next" .. tokenQ, true)
                    end)
                    if not success or not response then
                        success, response = pcall(function()
                            return HttpService:GetAsync(CLOUD_SERVER_URL .. "/next" .. tokenQ, true)
                        end)
                    end
                end
                if not success or not response then
                    success, response = pcall(function()
                        return HttpService:GetAsync("http://127.0.0.1:" .. HTTP_PORT .. "/next", true)
                    end)
                end
                
                if success and response and response ~= "" then
                    failedNext = 0
                    local dataSuccess, decoded = pcall(function() return HttpService:JSONDecode(response) end)
                    if dataSuccess and decoded and decoded.username then
                        handleBridgeMessage({
                            action = "buy_fruit",
                            username = decoded.username,
                            fruit = decoded.fruit or ""
                        })
                    end
                    task.wait(0.1)
                elseif success then
                    -- 204 No Content: fila vazia no momento
                    failedNext = 0
                    task.wait(0.1)
                else
                    failedNext = failedNext + 1
                    if failedNext > 3 then
                        task.wait(1.5)
                    else
                        task.wait(0.4)
                    end
                end
            end
        end
    end)
    
    local failedSettings = 0
    task.spawn(function()
        while true do
            local success, response = false, nil
            local tokenQ = getTokenQuery()
            if tokenQ ~= "" then
                success, response = pcall(function()
                    return HttpService:GetAsync(VERCEL_API_URL .. "/api/script/game_settings" .. tokenQ, true)
                end)
                if not success or not response then
                    success, response = pcall(function()
                        return HttpService:GetAsync(CLOUD_SERVER_URL .. "/game_settings" .. tokenQ, true)
                    end)
                end
            end
            if not success or not response then
                success, response = pcall(function()
                    return HttpService:GetAsync("http://127.0.0.1:" .. HTTP_PORT .. "/game_settings", true)
                end)
            end
            if success and response then
                failedSettings = 0
                local dataSuccess, decoded = pcall(function() return HttpService:JSONDecode(response) end)
                if dataSuccess and decoded then syncGuiWithSettings(decoded) end
                task.wait(1.5)
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
-- wsReconnectEnabled: false = não tenta reconectar automaticamente após desconexão
local wsReconnectEnabled = false  -- Só tenta 1 vez ao iniciar; após isso só via botão
local wsForceReconnect = false
local wsIsConnecting = false  -- Evita múltiplas tentativas simultâneas

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
        -- Tenta conectar UMA vez
        wsForceReconnect = false
        setWsStatus(false)

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
                    print("[AutoBuyer] WebSocket desconectou. Clique em Reconectar para tentar novamente.")
                end)
                while not closed and not wsForceReconnect do
                    task.wait(1)
                end
            else
                -- Executor sem evento OnClose: usa ping para detectar queda
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
                        print("[AutoBuyer] WebSocket perdeu conexão. Clique em Reconectar para tentar novamente.")
                        break
                    end
                end
            end

            activeWS = nil
            setWsStatus(false)
        else
            -- Falhou na primeira tentativa
            print("[AutoBuyer] Não foi possível conectar ao servidor Bridge. Usando fallback HTTP.")
            setWsStatus(false)
        end

        wsIsConnecting = false

        -- Se foi um force-reconnect via botão, tenta novamente imediatamente
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
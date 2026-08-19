local resourceName = tostring(GetCurrentResourceName())

local dispatchMessages = {}
local DispatchChatCooldown = {}

local function messagesForDomain(domain)
    if not dispatchMessages[domain] then dispatchMessages[domain] = {} end
    return dispatchMessages[domain]
end

local function sendToDomain(domain, eventName, ...)
    for _, playerId in ipairs(GetPlayers()) do
        local target = tonumber(playerId)
        if target and CheckAuth(target) and GetMdtDomain(target) == domain then
            TriggerClientEvent(eventName, target, ...)
        end
    end
end

-- Send dispatch message
ps.registerCallback(resourceName .. ':server:sendDispatchMessage', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, message = 'Unauthorized' } end

    payload = payload or {}
    local message = type(payload.message) == 'string'
        and payload.message:gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 500) or nil
    local time = type(payload.time) == 'string' and payload.time:sub(1, 16) or nil

    if not message or message == '' then
        return { success = false, message = 'Empty message' }
    end

    local citizenid = ps.getIdentifier(src)
    if not citizenid then return { success = false, message = 'Identity unavailable' } end
    local now = GetGameTimer()
    local cooldownMs = tonumber(Config.Dispatch and Config.Dispatch.ChatCooldownMs) or 2000
    local lastMessage = DispatchChatCooldown[citizenid]
    if lastMessage and now - lastMessage < cooldownMs then
        return { success = false, message = 'Please wait before sending another message' }
    end
    local callsign = ps.getMetadata(src, 'callsign') or '000'
    local name = ps.getPlayerName(src) or 'Unknown'

    local pfp = MySQL.scalar.await('SELECT profilepicture FROM mdt_profiles WHERE citizenid = ? LIMIT 1', { citizenid })

    local item = {
        profilepic = pfp or '',
        callsign = callsign,
        name = '(' .. callsign .. ') ' .. name,
        message = message,
        time = time or os.date('%H:%M'),
    }

    local domain = GetMdtDomain(src)
    local messages = messagesForDomain(domain)
    messages[#messages + 1] = item
    local historyLimit = tonumber(Config.Dispatch and Config.Dispatch.ChatHistoryLimit) or 100
    while #messages > math.max(10, historyLimit) do table.remove(messages, 1) end
    DispatchChatCooldown[citizenid] = now
    sendToDomain(domain, resourceName .. ':client:dispatchMessage', item)

    return { success = true }
end)

-- Get dispatch messages
ps.registerCallback(resourceName .. ':server:getDispatchMessages', function(source)
    if not CheckAuth(source) then return {} end
    return messagesForDomain(GetMdtDomain(source))
end)

-- Get call responses from ps-dispatch
ps.registerCallback(resourceName .. ':server:getCallResponses', function(source, callid)
    if not CheckAuth(source) then return {} end

    if GetResourceState('ps-dispatch') == 'started' then
        local ok, call = pcall(function()
            return exports['ps-dispatch']:GetDispatchCallById(callid)
        end)
        if ok and call then
            return call.responses or {}
        end

        -- Compatibility with older ps-dispatch versions that only expose the
        -- full list. Call ids are not guaranteed to match Lua array indexes
        -- after calls expire or are cleared, so search by the stored id.
        local calls = exports['ps-dispatch']:GetDispatchCalls()
        for i = 1, #(calls or {}) do
            if tostring(calls[i].id) == tostring(callid) then
                return calls[i].responses or {}
            end
        end
    end

    return {}
end)

-- Send call response
ps.registerCallback(resourceName .. ':server:sendCallResponse', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false } end

    payload = payload or {}
    local message = payload.message
    local time = payload.time
    local callid = payload.callid

    if not message or not callid then
        return { success = false }
    end

    local name = ps.getPlayerName(src) or 'Unknown'

    if GetResourceState('ps-dispatch') == 'started' then
        local accepted = false
        TriggerEvent('dispatch:sendCallResponse', src, callid, message, time, function(isGood)
            accepted = isGood == true
            if isGood then
                sendToDomain(GetMdtDomain(src), resourceName .. ':client:callResponse', message, time, callid, name)
            end
        end)
        return { success = accepted }
    end

    return { success = false }
end)

-- Signal 100 (Panic / Emergency)
ps.registerCallback(resourceName .. ':server:signal100', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, message = 'Unauthorized' } end

    payload = payload or {}
    local radio = payload.radio or '1'
    local active = payload.active

    if active == nil then active = true end

    sendToDomain(GetMdtDomain(src), resourceName .. ':client:sig100', radio, active)

    if ps.auditLog then
        ps.auditLog(src, active and 'signal100_activated' or 'signal100_deactivated', 'dispatch', radio, {})
    end

    return { success = true, message = active and 'Signal 100 activated' or 'Signal 100 cleared' }
end)

-- Attached Units Query
ps.registerCallback(resourceName .. ':server:getAttachedUnits', function(source, callid)
    if not CheckAuth(source) then return {} end
    if not callid then return {} end

    if GetResourceState('ps-dispatch') == 'started' then
        local calls = exports['ps-dispatch']:GetDispatchCalls()
        if calls then
            for i = 1, #calls do
                if calls[i] and calls[i]['id'] == tonumber(callid) then
                    return calls[i]['units'] or {}
                end
            end
        end
    end

    return {}
end)

CGNMdtAudience = CGNMdtAudience or {}

local function sendWhere(eventName, predicate, ...)
    for _, playerId in ipairs(GetPlayers()) do
        local target = tonumber(playerId)
        if target and CheckAuth(target) and predicate(target) then
            TriggerClientEvent(eventName, target, ...)
        end
    end
end

function CGNMdtAudience.sendDomain(domain, eventName, ...)
    sendWhere(eventName, function(target)
        return GetMdtDomain(target) == domain
    end, ...)
end

function CGNMdtAudience.sendLeo(eventName, ...)
    sendWhere(eventName, function(target)
        return IsLeoMdtSource(target)
    end, ...)
end

function CGNMdtAudience.sendPermission(permission, eventName, ...)
    sendWhere(eventName, function(target)
        return CheckPermission(target, permission)
    end, ...)
end

return CGNMdtAudience

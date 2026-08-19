local resourceName = tostring(GetCurrentResourceName())

local function callFleet(source, exportName, payload)
    if not CheckAuth(source) then return { success = false, reason = 'not_authorized' } end
    if GetResourceState('cgn_leo_fleet') ~= 'started' then
        return { success = false, reason = 'service_unavailable' }
    end
    local ok, result = pcall(function()
        return exports.cgn_leo_fleet[exportName](exports.cgn_leo_fleet, source, payload)
    end)
    if not ok then
        print(('[ps-mdt] fleet callback %s failed: %s'):format(exportName, tostring(result)))
        return { success = false, reason = 'service_unavailable' }
    end
    return result or { success = false, reason = 'service_unavailable' }
end

ps.registerCallback(resourceName .. ':server:getFleetBootstrap', function(source)
    return callFleet(source, 'GetBootstrap')
end)

ps.registerCallback(resourceName .. ':server:commissionFleetVehicle', function(source, payload)
    return callFleet(source, 'Commission', payload)
end)

ps.registerCallback(resourceName .. ':server:assignFleetVehicle', function(source, payload)
    return callFleet(source, 'Assign', payload)
end)

ps.registerCallback(resourceName .. ':server:setFleetVehicleStatus', function(source, payload)
    return callFleet(source, 'SetStatus', payload)
end)

ps.registerCallback(resourceName .. ':server:renumberFleetVehicle', function(source, payload)
    return callFleet(source, 'Renumber', payload)
end)

local fleetCallbacks = {
    getFleetBootstrap = 'cgn_leo_fleet:server:getBootstrap',
    commissionFleetVehicle = 'cgn_leo_fleet:server:commission',
    assignFleetVehicle = 'cgn_leo_fleet:server:assign',
    setFleetVehicleStatus = 'cgn_leo_fleet:server:setStatus',
    renumberFleetVehicle = 'cgn_leo_fleet:server:renumber',
}

local function relay(callbackName, data, cb)
    if not MDTOpen then
        cb({ success = false, reason = 'mdt_closed' })
        return
    end

    local fleetCallback = fleetCallbacks[callbackName]
    if not fleetCallback then
        cb({ success = false, reason = 'service_unavailable' })
        return
    end

    local ok, result = pcall(function()
        return lib.callback.await(fleetCallback, false, data or {})
    end)
    if not ok then
        print(('[ps-mdt] fleet NUI callback %s failed: %s'):format(callbackName, tostring(result)))
        cb({ success = false, reason = 'service_unavailable' })
        return
    end

    cb(result or { success = false, reason = 'service_unavailable' })
end

RegisterNUICallback('getFleetBootstrap', function(data, cb)
    relay('getFleetBootstrap', data, cb)
end)

RegisterNUICallback('commissionFleetVehicle', function(data, cb)
    relay('commissionFleetVehicle', data, cb)
end)

RegisterNUICallback('assignFleetVehicle', function(data, cb)
    relay('assignFleetVehicle', data, cb)
end)

RegisterNUICallback('setFleetVehicleStatus', function(data, cb)
    relay('setFleetVehicleStatus', data, cb)
end)

RegisterNUICallback('renumberFleetVehicle', function(data, cb)
    relay('renumberFleetVehicle', data, cb)
end)

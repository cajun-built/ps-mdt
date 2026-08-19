local resourceName = tostring(GetCurrentResourceName())

local function relay(callbackName, data, cb)
    if not MDTOpen then
        cb({ success = false, reason = 'mdt_closed' })
        return
    end
    cb(ps.callback(resourceName .. ':server:' .. callbackName, data or {})
        or { success = false, reason = 'service_unavailable' })
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

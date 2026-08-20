local fleetCallbacks = {
    getFleetBootstrap = 'cgn_leo_fleet:server:getBootstrap',
    commissionFleetVehicle = 'cgn_leo_fleet:server:commission',
    assignFleetVehicle = 'cgn_leo_fleet:server:assign',
    setFleetVehicleStatus = 'cgn_leo_fleet:server:setStatus',
    renumberFleetVehicle = 'cgn_leo_fleet:server:renumber',
}

local function tableKeys(value)
    if type(value) ~= 'table' then return '' end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    return table.concat(keys, ',')
end

local function validateResponse(callbackName, result)
    local resultType = type(result)
    local reason
    if resultType ~= 'table' or type(result.success) ~= 'boolean' then
        reason = 'invalid_response'
    elseif result.success == false and (type(result.reason) ~= 'string' or result.reason == '') then
        reason = 'missing_failure_reason'
    elseif callbackName == 'getFleetBootstrap' and result.success == true and type(result.data) ~= 'table' then
        reason = 'missing_bootstrap_data'
    end

    if not reason then return result end

    print(('[ps-mdt] fleet response %s type=%s success=%s reason=%s keys=%s'):format(
        callbackName,
        resultType,
        tostring(resultType == 'table' and result.success or nil),
        tostring(resultType == 'table' and result.reason or nil),
        tableKeys(result)
    ))
    return { success = false, reason = reason }
end

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

    cb(validateResponse(callbackName, result))
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

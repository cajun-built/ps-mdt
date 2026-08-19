local resourceName = tostring(GetCurrentResourceName())

RegisterNUICallback('getCallsign', function(_, cb)
    if not MDTOpen then cb({ callsign = '' }) return end
    local result = ps.callback(resourceName .. ':server:getCallsign')
    cb(result or { callsign = '' })
end)

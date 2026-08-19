local resourceName = tostring(GetCurrentResourceName())

-- Delete ICU Record (ambulance/EMS)
ps.registerCallback(resourceName .. ':server:deleteICU', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, message = 'Unauthorized' } end
    payload = payload or {}
    local id = tonumber(payload.id)

    if not id then
        return { success = false, message = 'Missing ICU record ID' }
    end

    local rows = MySQL.query.await('SELECT id FROM mdt_bolos WHERE id = ?', { id })
    if not rows or #rows == 0 then
        return { success = false, message = 'ICU record not found' }
    end
    local changed = MySQL.update.await([[
        UPDATE mdt_bolos
        SET lifecycle_status = 'voided', status = 'resolved', version = version + 1
        WHERE id = ?
    ]], { id })
    if changed and ps.auditLog then
        ps.auditLog(src, 'icu_voided', 'icu', tostring(id), {
            reason = payload.reason or 'ICU record voided through MDT deletion action'
        })
    end
    return { success = changed ~= nil, message = changed and 'ICU record voided' or 'ICU record update failed' }
end)

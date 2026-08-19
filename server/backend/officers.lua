local resourceName = tostring(GetCurrentResourceName())
 
-- Get player source ID by citizenId
ps.registerCallback(resourceName .. ':server:GetPlayerSourceId', function(source, targetCitizenId)
    if not CheckAuth(source) then return nil end
    if not targetCitizenId then return nil end
    local targetPlayer = ps.getPlayerByIdentifier(targetCitizenId)
    if not targetPlayer then
        ps.notify(source, 'Citizen seems asleep / missing', 'error')
        return nil
    end
    return targetPlayer.source or (targetPlayer.PlayerData and targetPlayer.PlayerData.source)
end)
 
-- Set Callsign
ps.registerCallback(resourceName .. ':server:setCallsign', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, message = 'Unauthorized' } end
    payload = payload or {}
    local cid = payload.citizenid or payload.cid
    local newCallsign = payload.callsign or payload.newcallsign
 
    if not cid or not newCallsign then
        return { success = false, message = 'Missing citizen ID or callsign' }
    end
    -- Reject a callsign already owned by a different profile (UNIQUE index).
    local taken = MySQL.scalar.await(
        'SELECT 1 FROM mdt_profiles WHERE callsign = ? AND citizenid != ? LIMIT 1',
        { newCallsign, cid }
    )
    if taken then
        return { success = false, message = 'Callsign "' .. tostring(newCallsign) .. '" is already in use' }
    end

    local targetSource = GetFrameworkPlayerSource(cid)
    if targetSource then
        if not SetCitizenMetadata(cid, 'callsign', newCallsign) then
            return { success = false, message = 'Framework metadata update failed' }
        end
        TriggerClientEvent(resourceName .. ':client:updateCallsign', targetSource, newCallsign)
 
        MySQL.update.await('UPDATE mdt_profiles SET callsign = ? WHERE citizenid = ?', { newCallsign, cid })
 
        if ps.auditLog then
            ps.auditLog(src, 'callsign_changed', 'officer', cid, { callsign = newCallsign })
        end
 
        return { success = true, message = 'Callsign updated to ' .. newCallsign }
    end
    return { success = false, message = 'Player must be online to update callsign' }
end)
 
ps.registerCallback(resourceName .. ':server:getCallsign', function(source, payload)
    if not CheckAuth(source) then return { callsign = '' } end
    local cid = payload.citizenid
    if not cid then return { callsign = '' } end
 
    local targetSource = GetFrameworkPlayerSource(cid)
    if targetSource then
        return { callsign = tostring(ps.getMetadata(targetSource, 'callsign') or '') }
    end
    local row = MySQL.single.await('SELECT callsign FROM mdt_profiles WHERE citizenid = ?', { cid })
    return { callsign = tostring(row and row.callsign or '') }
end)
 
-- Set Radio Frequency
ps.registerCallback(resourceName .. ':server:setRadio', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, message = 'Unauthorized' } end
 
    payload = payload or {}
    local cid = payload.citizenid or payload.cid
    local newRadio = payload.radio or payload.newradio
 
    if not cid or not newRadio then
        return { success = false, message = 'Missing citizen ID or radio frequency' }
    end
 
    local targetPlayer = ps.getPlayerByIdentifier(cid)
    if not targetPlayer then
        return { success = false, message = 'Officer must be online' }
    end
 
    local targetSource = targetPlayer.source or (targetPlayer.PlayerData and targetPlayer.PlayerData.source)
    local hasRadio = true
    if GetResourceState('ox_inventory') == 'started' then
        hasRadio = (exports.ox_inventory:Search(targetSource, 'count', 'radio') or 0) > 0
    elseif targetPlayer.getInventoryItem then
        local radio = targetPlayer.getInventoryItem('radio')
        hasRadio = radio and (radio.count or 0) > 0
    elseif targetPlayer.Functions and targetPlayer.Functions.GetItemByName then
        hasRadio = targetPlayer.Functions.GetItemByName('radio') ~= nil
    end
    if not hasRadio then
        return { success = false, message = (ps.getPlayerName(targetSource) or 'Officer') .. ' does not have a radio!' }
    end
 
    TriggerClientEvent(resourceName .. ':client:setRadio', targetSource, newRadio)
    return { success = true, message = 'Radio set to ' .. newRadio }
end)
 
-- Get Unit Location (GPS to officer)
ps.registerCallback(resourceName .. ':server:getUnitLocation', function(source, cid)
    if not CheckAuth(source) then return {} end
    if not cid then return {} end
 
    local targetSource = GetFrameworkPlayerSource(cid)
    if targetSource then
        local coords = GetEntityCoords(GetPlayerPed(targetSource))
        return { x = coords.x, y = coords.y, z = coords.z }
    end
 
    return {}
end)

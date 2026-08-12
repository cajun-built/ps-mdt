local function metadataTable()
    if MDTFramework.is('esx') then
        return 'users', 'identifier'
    end
    return 'players', 'citizenid'
end

function UpdateCitizenMetadata(citizenid, metadata)
    if not citizenid or type(metadata) ~= 'table' then return false end
    local tableName, identifierColumn = metadataTable()
    local query = ('UPDATE %s SET metadata = ? WHERE %s = ?'):format(tableName, identifierColumn)
    return (MySQL.update.await(query, { json.encode(metadata), citizenid }) or 0) > 0
end

function SetCitizenMetadata(citizenid, key, value)
    if not citizenid or not key then return false end

    if ps and ps.setMetadata then
        local ok, result = pcall(ps.setMetadata, citizenid, key, value)
        if ok and result ~= false then
            local player = ps.getPlayerByIdentifier and ps.getPlayerByIdentifier(citizenid) or nil
            local metadata = player and player.PlayerData and player.PlayerData.metadata or nil
            if metadata then UpdateCitizenMetadata(citizenid, metadata) end
            return true
        end
    end

    local tableName, identifierColumn = metadataTable()
    local query = ('SELECT metadata FROM %s WHERE %s = ? LIMIT 1'):format(tableName, identifierColumn)
    local row = MySQL.single.await(query, { citizenid })
    if not row then return false end

    local metadata = row.metadata and json.decode(row.metadata) or {}
    metadata[key] = value
    return UpdateCitizenMetadata(citizenid, metadata)
end

function GetFrameworkPlayerSource(citizenid)
    if not citizenid or not ps or not ps.getPlayerByIdentifier then return nil end
    local player = ps.getPlayerByIdentifier(citizenid)
    if not player then return nil end
    return player.source or (player.PlayerData and player.PlayerData.source) or nil
end

function GetFrameworkPlayerData(source)
    if not source or not ps then return nil end
    if ps.getPlayerData then
        local data = ps.getPlayerData(source)
        if data then return data end
    end
    local player = ps.getPlayer and ps.getPlayer(source) or nil
    return player and player.PlayerData or nil
end

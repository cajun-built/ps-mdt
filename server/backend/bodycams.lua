local resourceName = tostring(GetCurrentResourceName())
local bodycamInstances = {}
local bodycamViewers = {}

local function getBodycamConfig()
    return Config and Config.Bodycam or {}
end

local function shouldUseQbCore()
    local cfg = getBodycamConfig()
    if MDTFramework and MDTFramework.is('esx') then
        return false
    end
    if cfg.DutyEventMode == 'pslib' then
        return false
    end
    return GetResourceState(cfg.DutyResource) == 'started'
        or GetResourceState('qbx_core') == 'started'
end

local function getQbCoreObject()
    if not shouldUseQbCore() then return nil end
    local cfg = getBodycamConfig()
    local ok, core = pcall(function() return exports[cfg.DutyResource]:GetCoreObject() end)
    return ok and core or nil
end

local function getFrameworkPlayer(playerId)
    if GetResourceState('qbx_core') == 'started' then
        return exports.qbx_core:GetPlayer(playerId)
    end

    local core = getQbCoreObject()
    if core and core.Functions and core.Functions.GetPlayer then
        return core.Functions.GetPlayer(playerId)
    end
    return ps and ps.getPlayer and ps.getPlayer(playerId) or nil
end

local function getFrameworkPlayers()
    if GetResourceState('qbx_core') == 'started' then
        return exports.qbx_core:GetQBPlayers() or {}
    end

    local core = getQbCoreObject()
    if core and core.Functions and core.Functions.GetQBPlayers then
        return core.Functions.GetQBPlayers() or {}
    end
    return nil
end

local function isVerifiedLeoOnDuty(playerId, player)
    local data = player and player.PlayerData or nil
    if not data or not data.job or not IsPoliceJob(data.job.name, data.job.type) then return false end

    if GetResourceState('cgn_leo_core') == 'started' then
        local ok, context = pcall(function()
            return exports.cgn_leo_core:GetContext(playerId)
        end)
        return ok and context and context.onDuty == true
    end

    return data.job.onduty == true
end

local function getOnDutyOfficers()
    local officers = {}

    if shouldUseQbCore() then
        local players = getFrameworkPlayers()
        if players then
            for _, player in pairs(players) do
                local data = player and player.PlayerData or nil
                if data and isVerifiedLeoOnDuty(data.source, player) then
                    officers[#officers + 1] = player
                end
            end
        end
        return officers
    end

    if ps and ps.getAllPlayers then
        local players = ps.getAllPlayers() or {}
        for _, playerId in pairs(players) do
            if ps.getJobDuty and ps.getJobDuty(playerId) then
                local jobName = ps.getJobName and ps.getJobName(playerId) or nil
                local jobType = ps.getJobType and ps.getJobType(playerId) or nil
                if IsPoliceJob(jobName, jobType) then
                    local player = ps.getPlayer and ps.getPlayer(playerId) or nil
                    if player then
                        officers[#officers + 1] = player
                    end
                end
            end
        end
    end

    return officers
end

-- Get all bodycams for on-duty officers
ps.registerCallback(resourceName .. ':server:getBodycams', function(source)
    local src = source
    ps.debug('getBodycams called by source:', src)

    if not CheckAuth(src) then
        ps.debug('getBodycams: CheckAuth failed for source:', src)
        return {}
    end
    if not CheckPermission(src, 'bodycams_view') then return {} end

    ps.debug('getBodycams: CheckAuth passed for source:', src)
    local bodycams = {}

    local officers = getOnDutyOfficers()
    ps.debug('getBodycams: Found on-duty officers:', officers and #officers or 0)

    for _, player in pairs(officers or {}) do
        local playerData = player.PlayerData
        if playerData then
            local bodycamId = tostring(playerData.source)
            local officerName = playerData.charinfo.firstname .. ' ' .. playerData.charinfo.lastname

            if not bodycamInstances[bodycamId] then
                bodycamInstances[bodycamId] = {
                    id = bodycamId,
                    officerName = officerName,
                    callsign = playerData.metadata and playerData.metadata.callsign or 'Unknown',
                    rank = playerData.job.grade and playerData.job.grade.name or 'Officer',
                    playerId = playerData.source,
                    isOnline = true,
                    createdAt = os.time()
                }
                ps.debug('Created bodycam on-demand for officer:', officerName, 'ID:', bodycamId)
            else
                local data = bodycamInstances[bodycamId]
                data.officerName = officerName
                data.callsign = playerData.metadata and playerData.metadata.callsign or 'Unknown'
                data.rank = playerData.job.grade and playerData.job.grade.name or 'Officer'
            end
        end
    end

    local instanceCount = 0
    for _ in pairs(bodycamInstances) do
        instanceCount = instanceCount + 1
    end
    ps.debug('getBodycams: Total bodycam instances before verification:', instanceCount)
    for bodycamId, _ in pairs(bodycamInstances) do
        ps.debug('getBodycams: Bodycam instance found:', bodycamId)
    end

    for bodycamId, data in pairs(bodycamInstances) do
        ps.debug('getBodycams: Verifying bodycam:', bodycamId, 'for player:', data.playerId)
        local isStillOnline = false

        local player = nil
        if shouldUseQbCore() then
            player = getFrameworkPlayer(data.playerId)
        elseif ps and ps.getPlayer then
            player = ps.getPlayer(data.playerId)
        end

        if player and isVerifiedLeoOnDuty(data.playerId, player) then
            isStillOnline = true
            ps.debug('getBodycams: Officer verified as online:', data.officerName)
        end

        ps.debug('getBodycams: Officer', data.officerName, 'isStillOnline:', isStillOnline)

        if isStillOnline then
            local viewerCount = 0
            if bodycamViewers[bodycamId] then
                for _ in pairs(bodycamViewers[bodycamId]) do
                    viewerCount = viewerCount + 1
                end
            end

            table.insert(bodycams, {
                id = bodycamId,
                officerName = data.officerName,
                callsign = data.callsign,
                rank = data.rank,
                isOnline = true,
                viewerCount = viewerCount,
            })
            ps.debug('getBodycams: Added bodycam to return list:', bodycamId, 'with', viewerCount, 'viewers')
        else
            -- Remove offline bodycam
            bodycamInstances[bodycamId] = nil
            ps.debug('getBodycams: Removed offline bodycam:', bodycamId)
        end
    end

    ps.debug('getBodycams: Returning', #bodycams, 'bodycams')
    return bodycams
end)

-- View a specific bodycam
ps.registerCallback(resourceName .. ':server:viewBodycam', function(source, bodycamId)
    local src = source
    if not CheckAuth(src) then
        return { success = false, error = "Unauthorized" }
    end
    if not CheckPermission(src, 'bodycams_view') then
        return { success = false, error = "No permission to view bodycams" }
    end

    local bodycamData = bodycamInstances[bodycamId]
    if not bodycamData then
        return { success = false, error = "Bodycam not found" }
    end

    local targetSource = bodycamData.playerId
    if not targetSource then
        return { success = false, error = "Invalid target source" }
    end

    local targetPlayer = GetPlayerName(targetSource)
    if not targetPlayer then
        return { success = false, error = "Officer is no longer online" }
    end

    local targetPed = GetPlayerPed(targetSource)
    if not targetPed or targetPed == 0 then
        return { success = false, error = "Unable to access officer's bodycam" }
    end

    local coords = GetEntityCoords(targetPed)
    local heading = GetEntityHeading(targetPed)

    -- Start bodycam view for the requesting player
    TriggerClientEvent(resourceName .. ':client:startCameraView', src, {
        coords = coords,
        rotation = vector3(0.0, 0.0, heading),
        networkId = nil, -- No entity to hide for bodycams
        isBodycam = true,
        targetSource = targetSource,
        officerName = bodycamData.officerName
    })

    -- Track this viewer
    if not bodycamViewers[bodycamId] then
        bodycamViewers[bodycamId] = {}
    end
    bodycamViewers[bodycamId][src] = {
        startTime = os.time()
    }
    ps.debug('Added viewer', src, 'to bodycam', bodycamId)

    return {
        success = true,
        camera = {
            id = bodycamId,
            label = bodycamData.officerName .. " Bodycam",
            coords = coords,
            rotation = vector3(0.0, 0.0, heading)
        }
    }
end)

-- Clean up bodycam when player disconnects
AddEventHandler('playerDropped', function(reason)
    local playerId = source
    local bodycamId = tostring(playerId)

    if bodycamInstances[bodycamId] then
        bodycamInstances[bodycamId] = nil
        ps.debug('Cleaned up bodycam instance for disconnected player:', playerId)
    end

    -- Clean up any viewer entries for this player
    for bcId, viewers in pairs(bodycamViewers) do
        if viewers and viewers[playerId] then
            viewers[playerId] = nil
            ps.debug('Removed viewer', playerId, 'from bodycam', bcId, 'due to disconnect')
        end
    end
end)

-- Handle bodycam view deactivation
RegisterNetEvent(resourceName .. ':server:deactivateBodycam', function(bodycamId)
    local playerId = source
    if not CheckAuth(playerId) then return end
    ps.debug('Deactivating bodycam for player:', playerId, 'Bodycam ID:', bodycamId)

    if bodycamViewers[bodycamId] then
        ps.debug('Found viewer table for bodycam:', bodycamId)
        if bodycamViewers[bodycamId][playerId] then
            local viewDuration = os.time() - bodycamViewers[bodycamId][playerId].startTime
            bodycamViewers[bodycamId][playerId] = nil
            ps.debug('Player', playerId, 'stopped viewing bodycam', bodycamId, 'after', viewDuration, 'seconds')

            -- Clean up empty viewer table
            if next(bodycamViewers[bodycamId]) == nil then
                bodycamViewers[bodycamId] = nil
                ps.debug('Cleaned up empty viewer table for bodycam:', bodycamId)
            end
        else
            ps.debug('Player', playerId, 'was not found in viewers for bodycam:', bodycamId)
        end
    else
        ps.debug('No viewer table found for bodycam:', bodycamId)
    end
end)

-- Helper function to create bodycam for officer
local function createOfficerBodycam(playerId, playerData)
    local bodycamId = tostring(playerId)
    local officerName = playerData.charinfo.firstname .. ' ' .. playerData.charinfo.lastname

    bodycamInstances[bodycamId] = {
        id = bodycamId,
        officerName = officerName,
        callsign = (playerData.metadata and playerData.metadata.callsign) or 'Unknown',
        rank = (playerData.job and playerData.job.grade and playerData.job.grade.name) or 'Officer',
        playerId = playerId,
        isOnline = true,
        createdAt = os.time()
    }

    ps.debug('Created bodycam for officer:', officerName, 'ID:', bodycamId)
end

-- Helper function to remove bodycam for officer
local function removeOfficerBodycam(playerId)
    local bodycamId = tostring(playerId)

    if bodycamInstances[bodycamId] then
        bodycamInstances[bodycamId] = nil
        ps.debug('Removed bodycam for officer going off duty:', playerId)
    end
end

-- Listen for QBCore duty status changes
local function handleDutyChange(playerId, job, onDuty, employeeData)
    local player = getFrameworkPlayer(playerId)
    if onDuty == true and player and isVerifiedLeoOnDuty(playerId, player) then
        createOfficerBodycam(playerId, player.PlayerData)
        return
    end
    removeOfficerBodycam(playerId)
end

local function registerDutyEvents()
    local cfg = getBodycamConfig()

    if cfg.DutyEventMode == 'cgnleo' then
        AddEventHandler('cgn_leo_core:server:dutyChanged', function(playerId, onDuty)
            if not playerId then return end
            handleDutyChange(playerId, nil, onDuty == true, nil)
        end)
    elseif MDTFramework and MDTFramework.is('esx') then
        AddEventHandler('esx:setJob', function(playerId, job)
            if not playerId or not job then return end
            handleDutyChange(playerId, job, job.onDuty ~= false, nil)
        end)
    elseif cfg.DutyEventMode == 'qbcore' or cfg.DutyEventMode == 'auto' then
        AddEventHandler(cfg.DutyEvent, function(source, job)
            local src = source
            if not src or not job then return end
            handleDutyChange(src, job, job.onduty == true, nil)
        end)
    elseif cfg.DutyEventMode == 'pslib' then
        AddEventHandler(cfg.DutyEvent, function(playerId, jobName, onDuty, employeeData)
            if not playerId then return end
            handleDutyChange(playerId, { name = jobName }, onDuty == true, employeeData)
        end)
    end

    if cfg.MultiJobDutyEvent and GetResourceState(cfg.MultiJobResource) == 'started' then
        AddEventHandler(cfg.MultiJobDutyEvent, function(playerId, jobName, onDuty, employeeData)
            if not playerId then return end
            handleDutyChange(playerId, { name = jobName }, onDuty == true, employeeData)
        end)
    end
end

-- Initialize bodycams for officers already on duty when resource starts
CreateThread(function()
    Wait(5000)

    local officers = getOnDutyOfficers()
    for _, player in pairs(officers or {}) do
        if player and player.PlayerData then
            createOfficerBodycam(player.PlayerData.source, player.PlayerData)
        end
    end

    local instanceCount = 0
    for _ in pairs(bodycamInstances) do
        instanceCount = instanceCount + 1
    end
    -- do not spell this with a Z
    ps.debug('Initialised ' .. instanceCount .. ' bodycams')
end)

registerDutyEvents()

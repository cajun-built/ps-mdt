local resourceName = tostring(GetCurrentResourceName())

local dutyWorkplaces = {
    brpd = 'BRPD Headquarters',
    ebrso = 'EBRSO Headquarters',
    lsp = 'LSP Troop Headquarters',
}

local dutyDenialMessages = {
    duplicate_action = 'Please wait a moment and try again.',
    grade_mismatch = 'Your MDT rank does not match your current job grade. Contact command staff.',
    identity_unavailable = 'Your LEO personnel record could not be verified. Contact command staff.',
    job_mismatch = 'Your LEO personnel record does not match your current job. Contact command staff.',
    service_unavailable = 'The LEO duty service is unavailable. Try again shortly.',
}

local function formatDutyDenial(reason)
    if reason == 'workplace_required' then
        local job = ps.getJob()
        local jobName = type(job) == 'table' and job.name or nil
        local workplace = dutyWorkplaces[jobName] or 'your agency headquarters'
        return ('You must be at %s to go on duty.'):format(workplace)
    end

    return dutyDenialMessages[reason]
        or 'You are not authorized to go on duty. Contact command staff if this continues.'
end

local function _isDojJob(jobName)
    if not jobName or not Config.DojJobs then return false end
    for _, name in ipairs(Config.DojJobs) do
        if name == jobName then return true end
    end
    return false
end

-- Match the server's IsEmsJob: an EMS job is recognised by its TYPE
-- (Config.MedicalJobType) OR its NAME (Config.MedicalJobs). The client used to
-- check the type only, so on servers whose EMS job type isn't literally "ems"
-- the NUI received jobType 'leo' for medics (breaking EMS-specific UI/text).
local function _isEmsJob(jobName, jobType)
    if jobType and Config.MedicalJobType and jobType == Config.MedicalJobType then return true end
    if jobName and Config.MedicalJobs then
        for _, name in ipairs(Config.MedicalJobs) do
            if name == jobName then return true end
        end
    end
    return false
end

RegisterNUICallback('checkAuth', function(_, cb)
    local jobType = ps.getJobType()
    local jobName = ps.getJob() and ps.getJob().name or ''
    local isDoj = _isDojJob(jobName) or (Config.DojJobType and jobType == Config.DojJobType)
    local isLeo = jobType == Config.PoliceJobType
    local serverAuth = isLeo and ps.callback(resourceName..':server:checkAuth') or nil
    local verifiedLeo = isLeo and type(serverAuth) == 'table' and serverAuth.isLEO == true
    local isAuthorized = isLeo and verifiedLeo and serverAuth.authorized == true
        or _isEmsJob(jobName, jobType)
        or isDoj
    local mdtJobType = isDoj and 'doj' or (_isEmsJob(jobName, jobType) and 'ems' or 'leo')
    local onDuty = verifiedLeo and serverAuth.onDuty == true or (not isLeo and (ps.getJobDuty() or false))
    local playerData = ps.getPlayerData()

    local isCivilian = false
    if not isLeo and not isAuthorized and Config.CivilianAccess and Config.CivilianAccess.enabled then
        isCivilian = true
    end

    cb({
        authorized = isCivilian or (isAuthorized and (isDoj or onDuty)),
        playerData = type(playerData) == 'table' and {
            citizenid = playerData.citizenid,
            job = playerData.job,
            charinfo = playerData.charinfo,
        } or nil,
        isLEO = isLeo or isAuthorized,
        onDuty = isCivilian or isDoj or onDuty or false,
        jobType = isCivilian and 'civilian' or mdtJobType,
        isCivilian = isCivilian,
        reason = type(serverAuth) == 'table' and serverAuth.reason or nil,
    })
end)

-- Separate NUI callback for fetching permissions (non-blocking)
RegisterNUICallback('getMyPermissions', function(_, cb)
    if not MDTOpen then
        cb({ permissions = {}, isBoss = false })
        return
    end

    local result = ps.callback(resourceName .. ':server:getMyPermissions')
    cb(result or { permissions = {}, isBoss = false })
end)

function NUIUpdateAuth()
    local jobType = ps.getJobType()
    local jobName = ps.getJob() and ps.getJob().name or ''
    local isDoj = _isDojJob(jobName) or (Config.DojJobType and jobType == Config.DojJobType)
    local isLeo = jobType == Config.PoliceJobType
    local serverAuth = isLeo and ps.callback(resourceName..':server:checkAuth') or nil
    local verifiedLeo = isLeo and type(serverAuth) == 'table' and serverAuth.isLEO == true
    local isAuthorized = isLeo and verifiedLeo and serverAuth.authorized == true
        or _isEmsJob(jobName, jobType)
        or isDoj
    local mdtJobType = isDoj and 'doj' or (_isEmsJob(jobName, jobType) and 'ems' or 'leo')
    local playerData = ps.getPlayerData()
    SendNUI('updateAuth', {
        authorized = isAuthorized and (isDoj or (verifiedLeo and serverAuth.onDuty == true) or (not isLeo and (ps.getJobDuty() or false))),
        playerData = type(playerData) == 'table' and {
            citizenid = playerData.citizenid,
            job = playerData.job,
            charinfo = playerData.charinfo,
            metadata = type(playerData.metadata) == 'table' and {
                callsign = playerData.metadata.callsign or '',
            } or nil,
        } or nil,
        isLEO = isLeo or isAuthorized,
        onDuty = verifiedLeo and serverAuth.onDuty == true or (not isLeo and (ps.getJobDuty() or false)),
        jobType = mdtJobType,
        isCivilian = false,
        reason = type(serverAuth) == 'table' and serverAuth.reason or nil,
    })
end

RegisterNUICallback('closeUI', function(_, cb)
    -- ps.debug('MDT closeUI triggered via NUI callback')
    PlayMDTSound('close')
    cb({})
    CloseMDT()
end)

RegisterNUICallback('signOut', function(_, cb)
    -- ps.debug('MDT signOut triggered via NUI callback')
    PlayMDTSound('close')
    local result = ps.getJobType() == Config.PoliceJobType and ps.callback(resourceName .. ':server:setLeoDuty', false)
        or { success = true }
    cb(result or { success = false })
    CloseMDT()
    ps.notify(result and result.success and 'Signed out and clocked off duty' or 'Signed out of MDT', 'success')
end)

RegisterNUICallback('toggleDuty', function(_, cb)
    -- ps.debug('MDT toggleDuty triggered via NUI callback')
    PlayMDTSound('buttonClick')
    local desiredDuty = not (ps.getJobDuty() or false)
    local result = ps.callback(resourceName .. ':server:setLeoDuty', desiredDuty)
    cb(result or { success = false, reason = 'service_unavailable' })
    if not result or not result.success then
        ps.notify(formatDutyDenial(result and result.reason or 'service_unavailable'), 'error')
    end
    Wait(100)
    NUIUpdateAuth()
end)

-- DASHBOARD (aggregate) -----------------------------------
-- One round-trip that returns every dashboard widget's data at once, so
-- opening the MDT fires a single NUI callback instead of ~9.
RegisterNUICallback('getDashboard', function(_, cb)
    if not MDTOpen then
        cb({})
        return
    end
    local data = ps.callback(resourceName .. ':server:getDashboard')
    cb(data or {})
end)

-- JOB DATA -----------------------------------------------
RegisterNUICallback('getJobData', function(_, cb)
    local jobData = ps.callback(resourceName .. ':server:getJobData')
     ps.debug('[getJobData] Triggered NUI callback on client', jobData)
    cb(jobData or {})
end)

-- REPORT STATISTICS ---------------------------------------
RegisterNUICallback('getReportStatistics', function(_, cb)
    if not MDTOpen then
        cb({ success = false, message = 'MDT is not open' })
        return
    end
    local reportStats = ps.callback(resourceName .. ':server:getReportStatistics')
    cb(reportStats)
end)



-- TIME STATISTICS -----------------------------------------
RegisterNUICallback('getTimeStatistics', function(_, cb)
    if not MDTOpen then
        cb({ success = false, message = 'MDT is not open' })
        return
    end
    local timeStats = ps.callback(resourceName .. ':server:getTimeStatistics')
    -- ps.debug('[getTimeStatistics] Triggered NUI callback on client', timeStats)
    cb(timeStats)
end)


-- ACTIVE WARRANTS -----------------------------------------
RegisterNUICallback('getActiveWarrants', function(_, cb)
    if not MDTOpen then
        cb({ success = false, message = 'MDT is not open' })
        return
    end
    local activeWarrants = ps.callback(resourceName .. ':server:getActiveWarrants')

    -- ps.debug('[getActiveWarrants] Triggered NUI callback on client',activeWarrants)
    cb(activeWarrants)
end)

-- View Warrant
RegisterNUICallback('viewWarrant', function(data, cb)
    cb({})
    TriggerServerEvent(resourceName..':server:viewWarrant', data.warrantId)
    -- ps.debug(('Viewing Warrant ID: %s'):format(data.warrantId))
end)



-- BULLETIN BOARD ----------------------------------------
RegisterNUICallback('getBulletins', function(_, cb)
    if not MDTOpen then
        cb({ success = false, message = 'MDT is not open' })
        return
    end
    local bulletins = ps.callback(resourceName .. ':server:getBulletins')
     ps.debug('[getBulletins] Triggered NUI callback on client',bulletins )
    cb(bulletins)
end)


RegisterNUICallback('createBulletin', function(data, cb)
    if not MDTOpen then cb({ success = false }) return end
    if not data or not data.content or data.content == '' then
        cb({ success = false, message = 'Content is required' })
        return
    end
    local result = ps.callback(resourceName .. ':server:createBulletin', data)
    cb(result or { success = false })
end)

RegisterNUICallback('deleteBulletin', function(data, cb)
    if not MDTOpen then cb({ success = false }) return end
    if not data or not data.id then
        cb({ success = false, message = 'Missing bulletin ID' })
        return
    end
    local result = ps.callback(resourceName .. ':server:deleteBulletin', data)
    cb(result or { success = false })
end)

RegisterNUICallback('getBulletinCategories', function(_, cb)
    local result = ps.callback(resourceName .. ':server:getBulletinCategories', false)
    cb(result or {})
end)

RegisterNUICallback('saveBulletinCategories', function(data, cb)
    if not data or not data.categories then
        cb({ success = false, message = 'Invalid data' })
        return
    end
 
    for _, cat in ipairs(data.categories) do
        if type(cat.value) ~= 'string' or type(cat.label) ~= 'string' or type(cat.icon) ~= 'string' then
            cb({ success = false, message = 'Malformed category entry' })
            return
        end
        if #cat.label > 32 or #cat.icon > 48 then
            cb({ success = false, message = 'Category label or icon name too long' })
            return
        end
    end
 
    local result = ps.callback('mdt:server:saveBulletinCategories', false, data.categories)
    cb(result or { success = false, message = 'Server error' })
end)

-- RECENT REPORTS -------------------------------------

RegisterNUICallback('getRecentReports', function(data, cb)
    if not MDTOpen then
        cb({ success = false, message = 'MDT is not open' })
        return
    end
    local page = data and data.page or nil
    local limit = data and data.limit or nil
    local recentReports = ps.callback(resourceName .. ':server:getRecentReports', page, limit)
    cb(recentReports)
end)

-- ACTIVE BOLOS ---------------------------------------

RegisterNUICallback('getActiveBolos', function(_, cb)
    if not MDTOpen then
        cb({ success = false, message = 'MDT is not open' })
        return
    end
    local activeBolos = ps.callback(resourceName .. ':server:getActiveBolos')
    cb(activeBolos)
end)

-- View Report
RegisterNUICallback('viewReport', function(data, cb)
    cb({})
    TriggerServerEvent(resourceName..':server:viewReport', data.reportId)
    -- ps.debug(('Viewing Report ID: %s'):format(data.reportId))
end)

-- ACTIVE UNITS ---------------------------------------

RegisterNUICallback('getActiveUnits', function(_, cb)
    if not MDTOpen then
        cb({ success = false, message = 'MDT is not open' })
        return
    end
    local activeUnits = ps.callback(resourceName .. ':server:getActiveUnits')
    -- ps.debug('[getActiveUnits] Active Units Data:', activeUnits)
    cb(activeUnits)
end)


-- DISPATCH -------------------------------------------

-- Build player data for attaching to dispatch
local function buildPlayerData()
    return {
        charinfo = {
            firstname = ps.getCharInfo('firstname'),
            lastname = ps.getCharInfo('lastname'),
        },
        metadata = {
            callsign = ps.getMetadata('callsign'),
        },
        citizenid = ps.getIdentifier(),
        job = {
            type = ps.getJobData('type'),
            name = ps.getJobData('name'),
            label = ps.getJobData('label'),
        },
    }
end

RegisterNUICallback('getRecentDispatches', function(_, cb)
    local dispatches = GetRecentDispatch()
    cb(dispatches or {})
end)

-- ─── Provider-aware attach / detach ─────────────────────────────────────────
-- ps, qs and cd each expose their own attach/detach path. Route to the right
-- one based on Config.Dispatch.Provider so the MDT's assign flow is identical
-- regardless of which dispatch resource the server runs. Detection is silent
-- client-side; the server logs a one-time warning if none is found.
local function dispatchProvider()
    local p = (Config and Config.Dispatch and Config.Dispatch.Provider) or 'auto'
    local resByProvider = { ps = 'ps-dispatch', qs = 'qs-dispatch', cd = 'cd_dispatch' }

    if (p == 'ps' or p == 'qs' or p == 'cd') and GetResourceState(resByProvider[p]) == 'started' then
        return p
    end
    if GetResourceState('ps-dispatch') == 'started' then return 'ps' end
    if GetResourceState('qs-dispatch') == 'started' then return 'qs' end
    if GetResourceState('cd_dispatch') == 'started' then return 'cd' end
    return nil
end

local function providerAttach(dispatchId)
    local p = dispatchProvider()
    if p == 'qs' then
        TriggerServerEvent('qs-dispatch:server:attachUnit', dispatchId)
    elseif p == 'cd' then
        TriggerServerEvent('cd_dispatch:server:attach', dispatchId)
    elseif p == 'ps' then
        TriggerServerEvent('ps-dispatch:server:attach', dispatchId, buildPlayerData())
    end
end

local function providerDetach(dispatchId)
    local p = dispatchProvider()
    if p == 'qs' then
        TriggerServerEvent('qs-dispatch:server:detachUnit', dispatchId)
    elseif p == 'cd' then
        TriggerServerEvent('cd_dispatch:server:detach', dispatchId)
    elseif p == 'ps' then
        TriggerServerEvent('ps-dispatch:server:detach', dispatchId, buildPlayerData())
    end
end

-- Real-time dispatch listeners — one per supported provider. Whichever
-- resource is running fires its event; the others simply never trigger.
RegisterNetEvent('ps-dispatch:client:notify', function(data)
    if not MDTOpen or not data then return end
    SendNUI('updateRecentDispatches', GetRecentDispatch() or {})
end)
RegisterNetEvent('qs-dispatch:client:notify', function()
    if not MDTOpen then return end
    SendNUI('updateRecentDispatches', GetRecentDispatch() or {})
end)
RegisterNetEvent('cd_dispatch:client:notify', function()
    if not MDTOpen then return end
    SendNUI('updateRecentDispatches', GetRecentDispatch() or {})
end)

RegisterNUICallback('getUsageMetrics', function(_, cb)
    if not MDTOpen then
        cb({ success = false, message = 'MDT is not open' })
        return
    end

    local result = ps.callback(resourceName .. ':server:getUsageMetrics')
    cb(result or {})
end)

RegisterNUICallback("attachToDispatch", function(data, cb)
    if not MDTOpen then cb({}) return end
    -- data may be a bare id (provider calls) or { id, manual } for MDT calls.
    local id = type(data) == 'table' and data.id or data
    local isManual = type(data) == 'table' and data.manual or false
    if isManual then
        ps.callback(resourceName .. ':server:selfDispatchAttach', { dispatch_id = id, action = 'attach' })
    else
        providerAttach(id)
    end
    cb(GetRecentDispatch())
end)

RegisterNUICallback("detachFromDispatch", function(data, cb)
    if not MDTOpen then cb({}) return end
    local id = type(data) == 'table' and data.id or data
    local isManual = type(data) == 'table' and data.manual or false
    if isManual then
        ps.callback(resourceName .. ':server:selfDispatchAttach', { dispatch_id = id, action = 'detach' })
    else
        providerDetach(id)
        Wait(100) -- give non-1of1 servers time to update the server-side table before the cb
    end
    cb(GetRecentDispatch())
end)

RegisterNUICallback("routeToDispatch", function(data, cb)
    local coords = data.coords or data.origin
    if not coords then
        cb('ok')
        ps.notify('No location data for this dispatch', 'error')
        return
    end
    local x = tonumber(coords.x) or tonumber(coords[1])
    local y = tonumber(coords.y) or tonumber(coords[2])
    if not x or not y then
        cb('ok')
        ps.notify('Invalid location data', 'error')
        return
    end
    SetNewWaypoint(x, y)
    cb('ok')
    ps.notify('Set Route to Dispatch Location', 'success')
end)
-- ---------------------------------------------------------------------------
-- Dispatcher assignment (runs on the ASSIGNED player's client).
-- Attaching through the target client mirrors the normal self-attach flow in
-- ps-dispatch exactly, and lets us set their waypoint + notify locally.
-- ---------------------------------------------------------------------------
RegisterNetEvent(resourceName .. ':client:dispatchAssign', function(data)
    data = data or {}
    if not data.id then return end

    if data.action == 'detach' then
        if not data.manual then providerDetach(data.id) end
        ps.notify('Dispatch has removed you from a call', 'inform')
        return
    end

    if not data.manual then providerAttach(data.id) end

    local c = data.coords
    if c then
        local x = tonumber(c.x) or tonumber(c[1])
        local y = tonumber(c.y) or tonumber(c[2])
        if x and y then SetNewWaypoint(x, y) end
    end

    local note = type(data.note) == 'string' and data.note ~= '' and data.note or nil
    if note then
        ps.notify('Dispatch assigned you to a call — waypoint set. Note: ' .. note, 'success')
    else
        ps.notify('Dispatch assigned you to a call — waypoint set. No note provided.', 'success')
    end
end)

-- A note was added/edited/removed — refresh the MDT dispatch list so the note
-- travels with the call everywhere it's shown.
RegisterNetEvent(resourceName .. ':client:dispatchNoteChanged', function(_)
    if not MDTOpen then return end
    SendNUI('updateRecentDispatches', GetRecentDispatch() or {})
end)

-- You're already on a call and dispatch changed its note.
RegisterNetEvent(resourceName .. ':client:dispatchNoteNotify', function(data)
    data = data or {}
    local text = type(data.text) == 'string' and data.text or ''
    ps.notify('Dispatch updated the note on your call: ' .. text, 'inform')
end)

-- Dispatcher-side NUI bridge: assign/detach a set of units to a call.
RegisterNUICallback('assignToDispatch', function(data, cb)
    if not MDTOpen then cb({ success = false, error = 'MDT is not open' }) return end
    local result = ps.callback(resourceName .. ':server:assignToDispatch', data or {})
    cb(result or { success = false })
end)

-- A dispatcher dismissed a call globally — refresh our MDT's dispatch list
-- (the server already filters the dismissed id out of every response).
RegisterNetEvent(resourceName .. ':client:dispatchDismissed', function(_)
    if not MDTOpen then return end
    SendNUI('updateRecentDispatches', GetRecentDispatch() or {})
end)

RegisterNUICallback('dismissDispatch', function(data, cb)
    if not MDTOpen then cb({ success = false, error = 'MDT is not open' }) return end
    local result = ps.callback(resourceName .. ':server:dismissDispatch', data or {})
    cb(result or { success = false })
end)

RegisterNUICallback('setDispatchNote', function(data, cb)
    if not MDTOpen then cb({ success = false, error = 'MDT is not open' }) return end
    local result = ps.callback(resourceName .. ':server:setDispatchNote', data or {})
    cb(result or { success = false })
end)

RegisterNUICallback('deleteDispatchNote', function(data, cb)
    if not MDTOpen then cb({ success = false, error = 'MDT is not open' }) return end
    local result = ps.callback(resourceName .. ':server:deleteDispatchNote', data or {})
    cb(result or { success = false })
end)

-- Create Call modal: return the configured 10-codes.
RegisterNUICallback('getCallCodes', function(_, cb)
    cb((Config and Config.DispatchCodes) or {})
end)

-- Create Call modal: resolve a picked map coordinate to "Street, Zone".
RegisterNUICallback('resolveDispatchStreet', function(data, cb)
    data = data or {}
    local x, y, z = tonumber(data.x), tonumber(data.y), tonumber(data.z) or 0.0
    if not x or not y then cb({ street = '' }) return end
    local zone = GetLabelText(GetNameOfZone(x + 0.0, y + 0.0, z + 0.0))
    local hash = GetStreetNameAtCoord(x + 0.0, y + 0.0, z + 0.0)
    local street = GetStreetNameFromHashKey(hash)
    local out = street or ''
    if zone and zone ~= '' then out = (out ~= '' and (out .. ', ') or '') .. zone end
    cb({ street = out })
end)

RegisterNUICallback('createManualDispatch', function(data, cb)
    if not MDTOpen then cb({ success = false, error = 'MDT is not open' }) return end
    local result = ps.callback(resourceName .. ':server:createManualDispatch', data or {})
    cb(result or { success = false })
end)

-- Authorisation --

local function isDojJob(jobName)
    if not jobName or not Config.DojJobs then return false end
    for _, name in ipairs(Config.DojJobs) do
        if name == jobName then return true end
    end
    return false
end

local function getLeoContext(source)
    if GetResourceState('cgn_leo_core') ~= 'started' then return nil end
    local ok, context, reason = pcall(function()
        return exports.cgn_leo_core:GetContext(source)
    end)
    if not ok then return nil, 'service_unavailable' end
    return context, reason
end

function IsLeoMdtSource(source)
    return source and ps.getJobType(source) == Config.PoliceJobType
end

-- PS MDT keeps its own UI permission names. LEO authorization is deliberately
-- resolved by cgn_leo_core so rank inheritance, assignments, certifications,
-- restrictions and compartments have one server-side source of truth.
local leoPermissionMap = {
    record_view = { permission = 'records.view' },
    record_create = { permission = 'records.create' },
    record_supplement = { permission = 'records.supplement' },
    record_lifecycle = { permission = 'records.lifecycle' },
    evidence_lifecycle = { permission = 'evidence.release' },
    citizens_search = { permission = 'records.search' },
    citizens_edit_licenses = { permission = 'records.lifecycle' },
    citizens_edit_profile = { permission = 'records.supplement' },
    citizens_edit_forensics = { permission = 'records.enforcement_create' },
    bolos_view = { permission = 'records.view' },
    bolos_create = { permission = 'records.bolo_create' },
    vehicles_search = { permission = 'records.search' },
    vehicles_edit_registry = { permission = 'records.supplement' },
    vehicles_edit_dmv = { permission = 'records.lifecycle' },
    ['fleet.view'] = { permission = 'fleet.view' },
    ['fleet.mdt'] = { permission = 'fleet.mdt' },
    ['fleet.checkout'] = { permission = 'fleet.checkout' },
    ['fleet.manage'] = { permission = 'fleet.manage' },
    ['fleet.commission'] = { permission = 'fleet.commission' },
    ['fleet.assign'] = { permission = 'fleet.assign' },
    ['fleet.override'] = { permission = 'fleet.override' },
    weapons_search = { permission = 'records.search' },
    weapons_add = { permission = 'records.enforcement_create' },
    weapons_edit = { permission = 'records.enforcement_create' },
    weapons_delete = { permission = 'records.lifecycle' },
    cases_view = { permission = 'records.view' },
    cases_create = { permission = 'records.create' },
    cases_edit = { permission = 'records.supplement' },
    cases_delete = { permission = 'records.lifecycle' },
    evidence_view = { permission = 'evidence.view' },
    evidence_create = { permission = 'evidence.submit' },
    evidence_transfer = { permission = 'evidence.transfer' },
    evidence_upload = { permission = 'evidence.submit' },
    reports_view = { permission = 'records.view' },
    reports_create = { permission = 'records.create' },
    reports_delete = { permission = 'records.lifecycle' },
    warrants_view = { permission = 'records.view' },
    warrants_issue = { permission = 'records.warrant_request' },
    warrants_close = { permission = 'records.lifecycle' },
    charges_view = { permission = 'records.view' },
    charges_edit = { permission = 'records.lifecycle' },
    fine_process = { permission = 'records.enforcement_create' },
    map_patrols_view = { permission = 'dispatch.view' },
    map_patrols_manage = { permission = 'dispatch.assign_other' },
    map_patrols_edit = { permission = 'dispatch.assign_other' },
    dispatch_attach = { permission = 'dispatch.self_assign' },
    dispatch_route = { permission = 'dispatch.view' },
    dispatch_assign = { permission = 'dispatch.assign_other' },
    dispatch_notes = { permission = 'dispatch.assign_other' },
    vehicle_impound = { permission = 'records.enforcement_create' },
    vehicle_impound_release = { permission = 'evidence.release' },
    vehicle_impound_override = { permission = 'records.lifecycle' },
    cameras_view = { permission = 'records.view' },
    bodycams_view = { permission = 'records.view' },
    dashcams_view = { permission = 'records.view' },
    notes_edit_department = { permission = 'records.supplement' },
    roster_manage_certifications = { permission = 'certifications.issue' },
    roster_hire_officers = { permission = 'personnel.hire' },
    roster_manage_officers = { permission = 'personnel.actions' },
    taskforces_view = { permission = 'records.view' },
    taskforces_manage = { permission = 'taskforces.manage' },
    ppr_view = { permission = 'personnel.protected_view', compartment = 'personnel' },
    ppr_manage = { permission = 'personnel.actions', compartment = 'personnel' },
    fto_view = { permission = 'certifications.view' },
    fto_manage = { permission = 'certifications.issue' },
    bulletin_view = { permission = 'records.view' },
    bulletin_post = { permission = 'records.review' },
    bulletin_pin = { permission = 'records.lifecycle' },
    court_view = { permission = 'records.view' },
    court_create = { permission = 'records.create' },
    court_edit = { permission = 'records.supplement' },
    court_delete = { permission = 'records.lifecycle' },
    training_view = { permission = 'certifications.view' },
    training_create = { permission = 'certifications.issue' },
    training_edit = { permission = 'certifications.issue' },
    training_delete = { permission = 'certifications.issue' },
    ia_view = { permission = 'records.view', compartment = 'internal_affairs' },
    ia_manage = { permission = 'records.lifecycle', compartment = 'internal_affairs' },
    sop_view = { permission = 'records.view' },
    sop_manage = { permission = 'records.lifecycle' },
    management_permissions = { permission = 'compartments.manage' },
    management_bulletins = { permission = 'records.lifecycle' },
    management_activity = { permission = 'personnel.protected_view', compartment = 'personnel' },
    management_tags = { permission = 'records.lifecycle' },
    management_tracking = { permission = 'personnel.protected_view', compartment = 'personnel' },
    management_settings = { permission = 'compartments.manage' },
}

function AuthorizeLeoPermission(source, permName, options)
    local mapped = leoPermissionMap[permName]
    if not mapped or GetResourceState('cgn_leo_core') ~= 'started' then return false end
    options = options or {}
    options.requireDuty = true
    options.compartment = options.compartment or mapped.compartment
    local ok, allowed = pcall(function()
        return exports.cgn_leo_core:Authorize(source, mapped.permission, options)
    end)
    return ok and allowed == true
end

function CheckAuth(source)
    -- Never feed an invalid/offline source into the framework bridge: some
    -- bridges index the player object without a nil-check and raise a non-string
    -- error ("attempt to index a nil value (local player)"). If that happens
    -- inside a NUI callback it never replies, and the UI hangs until it times
    -- out. Fail closed instead of crashing.
    if not source or (tonumber(source) or 0) <= 0 then
        return false
    end

    local ok, jobType, jobName = pcall(function()
        return ps.getJobType(source), ps.getJobName(source)
    end)
    if not ok then
        return false
    end

    ps.debug('Checking MDT Authorization')
    if jobType == Config.PoliceJobType then
        local context = getLeoContext(source)
        if not context or not context.onDuty then
            ps.debug('Access Denied for ID: ' .. tostring(source) .. ', no verified LEO duty session')
            return false
        end
        return true
    end
    local dojCheck = isDojJob(jobName) or (Config.DojJobType and jobType == Config.DojJobType)
    if jobType ~= Config.PoliceJobType and jobType ~= Config.MedicalJobType and not dojCheck then
        ps.debug('Access Denied for ID: ' .. tostring(source) .. ', not an authorized job type')
        return false
    end
    ps.debug('Access Granted for ID: ' .. tostring(source) .. ', job type: ' .. tostring(jobType))
    return true
end

-- Check if a player has a specific permission (by job + grade lookup)
function CheckPermission(source, permName)
    if not source or not permName then return false end

    local jobType = ps.getJobType(source)
    if jobType == Config.PoliceJobType then
        return AuthorizeLeoPermission(source, permName)
    end

    -- Non-LEO domains retain PS MDT's configured grade permissions.
    if ps.isBoss and ps.isBoss(source) then return true end

    local jobData = ps.getJobData and ps.getJobData(source) or nil
    local isBoss = false
    local gradeValue = 0

    if jobData and jobData.grade then
        if type(jobData.grade) == 'table' then
            gradeValue = jobData.grade.level or jobData.grade.grade or jobData.grade.rank or jobData.grade.value or jobData.grade.id or 0
            isBoss = jobData.grade.isboss == true or jobData.grade.isBoss == true or jobData.grade.boss == true
        else
            gradeValue = jobData.grade
        end
    end

    if isBoss then return true end

    local jobName = ps.getJobName(source) or 'police'
    local gradeStr = tostring(gradeValue)

    -- Check database
    local row = MySQL.single.await('SELECT permissions FROM mdt_permission_roles WHERE job = ? AND grade = ?', { jobName, tonumber(gradeStr) })
    if row and row.permissions then
        local ok, decoded = pcall(json.decode, row.permissions)
        if ok and type(decoded) == 'table' then
            for _, p in ipairs(decoded) do
                if p == permName then return true end
            end
            return false
        end
    end

    -- Check config defaults
    local defaults = Config and Config.PermissionDefaults and Config.PermissionDefaults[jobName]
    if defaults and defaults[gradeStr] then
        for _, p in ipairs(defaults[gradeStr]) do
            if p == permName then return true end
        end
    end

    return false
end

local function upsertProfileSession(src, action)
    if not src then return end
    local citizenid = ps.getIdentifier(src)
    if not citizenid then return end

    local fullName = ps.getPlayerName(src)
    local callsign = ps.getMetadata(src, 'callsign')
    local job = ps.getJobData and ps.getJobData(src) or nil
    local jobName = job and job.name or ps.getJobName(src)
    local jobGrade = job and job.grade and job.grade.name or ps.getJobGradeName(src)

    local ok, profileId = pcall(EnsureProfileData,
        citizenid,
        fullName,
        callsign,
        callsign,
        jobGrade,
        jobName
    )

    if not ok or not profileId then
        ps.warn('Failed to upsert profile session for ' .. tostring(citizenid) .. ': ' .. tostring(profileId))
        return
    end

    if action == 'login' then
        -- Wrap all login operations in a single transaction to prevent race conditions
        local okTx, errTx = pcall(MySQL.transaction.await, {
            {
                query = [[
                    UPDATE mdt_profile_sessions
                    SET logout_at = NOW()
                    WHERE profile_id = ? AND logout_at IS NULL
                ]],
                values = { profileId }
            },
            {
                query = [[
                    INSERT INTO mdt_profile_sessions (profile_id, citizenid, source, login_at)
                    VALUES (?, ?, ?, NOW())
                ]],
                values = { profileId, citizenid, src }
            },
            {
                query = 'UPDATE mdt_profiles SET last_login_at = NOW() WHERE id = ?',
                values = { profileId }
            },
        })
        if not okTx then
            ps.warn('Failed to create login session (transaction): ' .. tostring(errTx))
        end
    elseif action == 'logout' then
        local okTx, errTx = pcall(MySQL.transaction.await, {
            {
                query = [[
                    UPDATE mdt_profile_sessions
                    SET logout_at = NOW()
                    WHERE profile_id = ? AND logout_at IS NULL
                    ORDER BY id DESC
                    LIMIT 1
                ]],
                values = { profileId }
            },
            {
                query = 'UPDATE mdt_profiles SET last_logout_at = NOW() WHERE id = ?',
                values = { profileId }
            },
        })
        if not okTx then
            ps.warn('Failed to update logout session (transaction): ' .. tostring(errTx))
        end
    end
end

-- FiveManage log helper for duty logging
local function SendDutyLog(officerName, citizenid, action, jobName)
    if not FiveManageQueueLog then return end

    FiveManageQueueLog({
        action = action == 'login' and 'mdt_clock_in' or 'mdt_clock_out',
        category = 'duty',
        message = (action == 'login' and 'Clock In' or 'Clock Out') .. ': ' .. (officerName or 'Unknown'),
        metadata = {
            officer = officerName or 'Unknown',
            citizenid = citizenid or 'N/A',
            department = jobName or 'Unknown',
            time = os.date('%Y-%m-%d %H:%M:%S')
        }
    })
end

local activeMdtSessions = {}

local function beginTrackedMdtSession(src)
    if activeMdtSessions[src] or not CheckAuth(src) then return false end
    activeMdtSessions[src] = true
    upsertProfileSession(src, 'login')
    if ps.auditLog then
        ps.auditLog(src, 'mdt_login', 'profile', ps.getIdentifier(src), {})
    end
    SendDutyLog(
        ps.getPlayerName(src) or 'Unknown',
        ps.getIdentifier(src) or 'N/A',
        'login',
        ps.getJobName(src) or 'Unknown'
    )
    return true
end

local function endTrackedMdtSession(src)
    if not activeMdtSessions[src] then return false end
    activeMdtSessions[src] = nil
    upsertProfileSession(src, 'logout')
    if ps.auditLog then
        ps.auditLog(src, 'mdt_logout', 'profile', ps.getIdentifier(src), {})
    end
    SendDutyLog(
        ps.getPlayerName(src) or 'Unknown',
        ps.getIdentifier(src) or 'N/A',
        'logout',
        ps.getJobName(src) or 'Unknown'
    )
    return true
end

RegisterNetEvent('ps-mdt:server:trackLogin', function()
    local src = source
    beginTrackedMdtSession(src)
end)

RegisterNetEvent('ps-mdt:server:trackLogout', function()
    local src = source
    endTrackedMdtSession(src)
end)

AddEventHandler('playerDropped', function()
    local src = source
    endTrackedMdtSession(src)
end)

ps.registerCallback(tostring(GetCurrentResourceName())..':server:checkAuth', function(source)
    local civAccess = Config.CivilianAccess and Config.CivilianAccess.enabled
    local jobType = ps.getJobType(source)
    if jobType == Config.PoliceJobType then
        local context, reason = getLeoContext(source)
        if context then
            return {
                authorized = context.onDuty == true,
                isLEO = true,
                onDuty = context.onDuty == true,
                jobType = 'leo',
            }
        end
        return {
            authorized = false,
            isLEO = true,
            onDuty = false,
            jobType = 'leo',
            reason = reason or 'personnel_setup_required',
        }
    end
    local isAuthed = CheckAuth(source)
    if isAuthed then
        return isAuthed
    end

    -- If not LEO/EMS but civilian access is enabled, return civilian flag
    if civAccess then
        return { isCivilian = true }
    end

    return false
end)

-- Get the current player's permissions based on their job + grade
ps.registerCallback(tostring(GetCurrentResourceName())..':server:getMyPermissions', function(source)
    local src = source
    if not CheckAuth(src) then return { permissions = {} } end

    local jobName = ps.getJobName(src) or 'police'
    if ps.getJobType(src) == Config.PoliceJobType then
        local granted = {}
        for _, permission in ipairs((Config and Config.ManagementPermissions) or {}) do
            if AuthorizeLeoPermission(src, permission) then granted[#granted + 1] = permission end
        end
        return { permissions = granted, isBoss = false }
    end
    local jobData = ps.getJobData and ps.getJobData(src) or nil
    local gradeValue = 0
    local isBoss = false

    if jobData and jobData.grade then
        if type(jobData.grade) == 'table' then
            gradeValue = jobData.grade.level or jobData.grade.grade or jobData.grade.rank or jobData.grade.value or jobData.grade.id or 0
            isBoss = jobData.grade.isboss == true or jobData.grade.isBoss == true or jobData.grade.boss == true
        else
            gradeValue = jobData.grade
        end
    end

    -- Boss gets all permissions
    if isBoss or (ps.isBoss and ps.isBoss(src)) then
        local allPerms = (Config and Config.ManagementPermissions) or {}
        return { permissions = allPerms, isBoss = true }
    end

    local gradeStr = tostring(gradeValue)

    -- Check database for stored permissions
    local row = MySQL.single.await('SELECT permissions FROM mdt_permission_roles WHERE job = ? AND grade = ?', { jobName, tonumber(gradeStr) })
    if row and row.permissions then
        local ok, decoded = pcall(json.decode, row.permissions)
        if ok and type(decoded) == 'table' then
            return { permissions = decoded, isBoss = false }
        end
    end

    -- Check config defaults
    local defaults = Config and Config.PermissionDefaults and Config.PermissionDefaults[jobName]
    if defaults and defaults[gradeStr] then
        return { permissions = defaults[gradeStr], isBoss = false }
    end

    -- No permissions found for this grade
    return { permissions = {}, isBoss = false }
end)

ps.registerCallback(tostring(GetCurrentResourceName())..':server:setLeoDuty', function(source, onDuty)
    if ps.getJobType(source) ~= Config.PoliceJobType then
        return { success = false, reason = 'job_mismatch' }
    end
    if GetResourceState('cgn_leo_core') ~= 'started' then
        return { success = false, reason = 'service_unavailable' }
    end

    local ok, success, result = pcall(function()
        if onDuty == true then
            return exports.cgn_leo_core:StartDuty(source)
        end
        return exports.cgn_leo_core:EndDuty(source, 'mdt_clock_out')
    end)
    if not ok then
        ps.error('LEO duty request failed: ' .. tostring(success))
        return { success = false, reason = 'service_unavailable' }
    end
    if success == true then
        if onDuty == true then
            beginTrackedMdtSession(source)
        else
            endTrackedMdtSession(source)
        end
        return { success = true, reason = nil, data = result }
    end
    return { success = false, reason = result, data = nil }
end)

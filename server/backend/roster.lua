local function getRadioChannel(playerSource)
    if not playerSource then return 0 end
    local channel = 0
    pcall(function()
        channel = Player(playerSource).state.radioChannel or 0
    end)
    return tonumber(channel) or 0
end

local function getCertifications(citizenid)
    EnsureProfileExists(citizenid)

    local profile = MySQL.single.await('SELECT certifications FROM mdt_profiles WHERE citizenid = ?', { citizenid })
    if not profile then
        return {}
    end

    if profile.certifications and profile.certifications ~= '' then
        local ok, decoded = pcall(json.decode, profile.certifications)
        if ok and type(decoded) == 'table' then
            return decoded
        end
    end

    return {}
end

local function getCorePersonnel(citizenid)
    if GetResourceState('cgn_leo_core') ~= 'started' then return nil end
    local ok, personnel = pcall(function()
        return exports.cgn_leo_core:GetPersonnel(citizenid, true)
    end)
    return ok and personnel or nil
end

local function isLeoSource(source)
    return ps.getJobType(source) == Config.PoliceJobType
end

local function coreResult(ok, result, successMessage)
    if ok then return { success = true, message = successMessage, personnel = result } end
    return { success = false, message = tostring(result or 'Action denied') }
end

local function certificationKey(value)
    value = tostring(value or ''):lower()
    value = value:gsub('[^%w]+', '_'):gsub('^_+', ''):gsub('_+$', '')
    local aliases = {
        fto = 'field_training_officer',
        k9_certified = 'k9',
        air_certified = 'air',
    }
    return aliases[value] or value
end

local function certificationLabels(values)
    local labels = {
        evidence_handling = 'Evidence Handling', incident_command = 'Incident Command',
        radar = 'Radar', instructor = 'Instructor', field_training_officer = 'Field Training Officer',
        k9 = 'K9', swat = 'SWAT', air = 'Air', interceptor = 'Interceptor',
    }
    local result = {}
    for _, value in ipairs(values or {}) do result[#result + 1] = labels[value] or value end
    return result
end

-- Resolve a human-facing department label. Prefers the live job's label (online
-- players), falls back to the shared job config's label (offline / DB rows), and
-- finally the raw job name. Avoids showing the internal id like "police" as DEPT.
local function deptLabel(jobName, jobObj)
    if jobObj and jobObj.label and jobObj.label ~= '' then return jobObj.label end
    if jobName and ps.getSharedJobData then
        local shared = ps.getSharedJobData(jobName)
        if shared and shared.label and shared.label ~= '' then return shared.label end
    end
    return jobName
end

local function buildRosterFromQbx(jobList, matchFn, defaultDept)
    local rosterList = {}
    local activeUnits = {}
    local members = {}
    local qbx = exports['qbx_core']

    if GetResourceState('cgn_leo_core') == 'started' and defaultDept == 'police' then
        local ok, personnel = pcall(function() return exports.cgn_leo_core:ListPersonnel() end)
        if ok then
            for _, member in ipairs(personnel or {}) do members[member.citizenid] = true end
        end
    end

    for _, jobName in ipairs(jobList) do
        local groupMembers = qbx:GetGroupMembers(jobName, 'job') or {}
        for _, member in ipairs(groupMembers) do
            if member.citizenid then
                members[member.citizenid] = true
            end
        end
    end

    for _, player in ipairs(qbx:GetQBPlayers() or {}) do
        local data = player.PlayerData or nil
        if data and data.job then
            local job = data.job
            if matchFn(job.name, job.type) then
                members[data.citizenid] = true
            end
        end
    end

    for _, row in ipairs(MySQL.query.await('SELECT citizenid, job FROM players', {}) or {}) do
        local job = row.job and json.decode(row.job) or {}
        if matchFn(job.name, job.type) then
            members[row.citizenid] = true
        end
    end

    for citizenid, _ in pairs(members) do
        local onlinePlayer = qbx:GetPlayerByCitizenId(citizenid)
        local player = onlinePlayer or qbx:GetOfflinePlayer(citizenid)
        if player and player.PlayerData then
            local data = player.PlayerData
            local job = data.job or {}
            local callsign = data.metadata and data.metadata.callsign or 'N/A'
            local fullname = data.charinfo and (data.charinfo.firstname .. ' ' .. data.charinfo.lastname) or 'Unknown'
            local rank = job.grade and job.grade.name or 'Officer'
            local department = job.name or defaultDept
            local departmentLabel = deptLabel(job.name, job) or department
            local corePersonnel = job.type == Config.PoliceJobType and getCorePersonnel(citizenid) or nil
            local certifications = corePersonnel and certificationLabels(corePersonnel.certifications) or getCertifications(citizenid)

            local onlineSrc = onlinePlayer and (onlinePlayer.PlayerData and onlinePlayer.PlayerData.source or onlinePlayer.source) or nil
            rosterList[#rosterList + 1] = {
                id = #rosterList + 1,
                citizenid = citizenid,
                callsign = corePersonnel and corePersonnel.callsign or callsign,
                firstName = data.charinfo and data.charinfo.firstname or 'N/A',
                lastName = data.charinfo and data.charinfo.lastname or 'N/A',
                rank = corePersonnel and corePersonnel.rankName or rank,
                department = corePersonnel and corePersonnel.agency or department,
                departmentLabel = corePersonnel and corePersonnel.agencyLabel or departmentLabel,
                status = (onlinePlayer and job.onduty) and 'On Duty' or 'Off Duty',
                certifications = certifications,
                badgeNumber = corePersonnel and corePersonnel.badge or callsign,
                employmentStatus = corePersonnel and corePersonnel.status or nil,
                assignments = corePersonnel and corePersonnel.assignments or {},
                primaryAssignment = corePersonnel and corePersonnel.primaryAssignment or nil,
                compartments = corePersonnel and corePersonnel.compartments or {},
                grants = corePersonnel and corePersonnel.grants or {},
                restrictions = corePersonnel and corePersonnel.restrictions or {},
                radioChannel = getRadioChannel(onlineSrc)
            }

            if rosterList[#rosterList].status == 'On Duty' then
                activeUnits[#activeUnits + 1] = {
                    id = rosterList[#rosterList].id,
                    badgeNumber = rosterList[#rosterList].badgeNumber,
                    callsign = rosterList[#rosterList].callsign,
                    firstName = rosterList[#rosterList].firstName,
                    lastName = rosterList[#rosterList].lastName,
                }
            end
        end
    end

    return {
        roster = rosterList,
        activeUnits = activeUnits
    }
end

local function checkDuty(citizenid, matchFn)
    matchFn = matchFn or IsPoliceJob
    local player = ps.getPlayerByIdentifier(citizenid)
    if not player then return 'Off Duty' end

    local src = player.source or (player.PlayerData and player.PlayerData.source)
    if not src then return 'Off Duty' end

    if matchFn(ps.getJobName(src), ps.getJobType(src)) and ps.getJobDuty(src) then
        return 'On Duty'
    end
    return 'Off Duty'
end

ps.registerCallback('ps-mdt:server:getRosterList', function(source)
    if not CheckAuth(source) then return { roster = {}, activeUnits = {} } end
    -- Scope the roster to the caller's domain: EMS sees EMS, police sees police.
    local domain = GetMdtDomain(source)
    local jobList, matchFn, defaultDept, scopeJobType
    if domain == 'ems' then
        jobList = (Config and Config.MedicalJobs) or { 'ambulance' }
        matchFn = IsEmsJob
        defaultDept = (jobList[1]) or 'ambulance'
        scopeJobType = Config and Config.MedicalJobType and tostring(Config.MedicalJobType) or nil
    else
        jobList = (Config and Config.PoliceJobs) or { 'police' }
        matchFn = IsPoliceJob
        defaultDept = 'police'
        scopeJobType = Config and Config.PoliceJobType and tostring(Config.PoliceJobType) or nil
    end

    if GetResourceState('qbx_core') == 'started' and exports['qbx_core'] then
        return buildRosterFromQbx(jobList, matchFn, defaultDept)
    end

    local rosterList = {}
    local activeUnits = {}
    local jobLookup = {}
    for _, jobName in ipairs(jobList) do
        jobLookup[tostring(jobName)] = true
    end
    local jobType = scopeJobType

    local employees = {}
    if GetResourceState('ps-multijob') == 'started' and exports['ps-multijob'] then
        for _, jobName in ipairs(jobList) do
            local list = exports['ps-multijob']:getEmployees(jobName) or {}
            for _, employee in pairs(list) do
                if employee and employee.citizenid then
                    employees[employee.citizenid] = employee
                end
            end
        end
    end

    for _, citizen in pairs(MySQL.query.await('SELECT citizenid, charinfo, job, metadata FROM players', {}) or {}) do
        local citizenid = citizen.citizenid
        local charinfo = citizen.charinfo and json.decode(citizen.charinfo) or {}
        local job = citizen.job and json.decode(citizen.job) or {}
        local metadata = citizen.metadata and json.decode(citizen.metadata) or {}
        local jobName = job.name and tostring(job.name) or nil
        local inDomain = (jobName and jobLookup[jobName]) or (job.type and jobType and tostring(job.type) == jobType)
        if inDomain then
            local employee = employees[citizenid] or {}
            local callsign = metadata.callsign or 'N/A'
            local firstName = charinfo.firstname or 'N/A'
            local lastName = charinfo.lastname or 'N/A'
            local rank = job.grade and job.grade.name or employee.grade and ps.getSharedJobGradeData(jobName or defaultDept, employee.grade, 'name') or 'Officer'
            local status = checkDuty(citizenid, matchFn)
            local onlinePlayer = ps.getPlayerByIdentifier(citizenid)
            local onlineSrc = onlinePlayer and (onlinePlayer.source or (onlinePlayer.PlayerData and onlinePlayer.PlayerData.source)) or nil
            rosterList[#rosterList + 1] = {
                id = #rosterList + 1,
                citizenid = citizenid,
                callsign = callsign,
                firstName = firstName,
                lastName = lastName,
                rank = rank,
                department = jobName or employee.job or defaultDept,
                departmentLabel = deptLabel(jobName, job) or jobName or employee.job or defaultDept,
                status = status,
                certifications = getCertifications(citizenid),
                badgeNumber = callsign,
                radioChannel = getRadioChannel(onlineSrc)
            }
            if status == 'On Duty' then
                activeUnits[#activeUnits + 1] = {
                    id = rosterList[#rosterList].id,
                    badgeNumber = rosterList[#rosterList].badgeNumber,
                    callsign = rosterList[#rosterList].callsign,
                    firstName = rosterList[#rosterList].firstName,
                    lastName = rosterList[#rosterList].lastName,
                }
            end
        end
    end
    return {
        roster = rosterList,
        activeUnits = activeUnits
    }
end)

-- Get available officer tags/certifications (filtered by job type)
ps.registerCallback('ps-mdt:server:getOfficerTags', function(source)
    local src = source
    if not CheckAuth(src) then return {} end

    if isLeoSource(src) then
        return {
            { id = 1, name = 'Evidence Handling', color = '#D4A72C', description = 'Evidence intake, custody and transfer qualification' },
            { id = 2, name = 'Incident Command', color = '#C2410C', description = 'Major incident command qualification' },
            { id = 3, name = 'Radar', color = '#2563EB', description = 'Speed enforcement equipment qualification' },
            { id = 4, name = 'Instructor', color = '#7C3AED', description = 'Agency instructor qualification' },
            { id = 5, name = 'Field Training Officer', color = '#059669', description = 'Field training officer qualification' },
            { id = 6, name = 'K9', color = '#0891B2', description = 'K9 operations qualification' },
            { id = 7, name = 'SWAT', color = '#DC2626', description = 'Tactical team qualification' },
            { id = 8, name = 'Air', color = '#4F46E5', description = 'Aviation operations qualification' },
            { id = 9, name = 'Interceptor', color = '#9333EA', description = 'High performance vehicle qualification' },
        }
    end

    local jobType = ps.getJobType(src)
    local rows
    if jobType and (jobType == 'leo' or jobType == 'ems') then
        rows = MySQL.query.await([[
            SELECT id, name, color, description FROM mdt_tags
            WHERE type = 'officer'
              AND (job_type = ? OR job_type = 'all' OR job_type IS NULL)
            ORDER BY name ASC
        ]], { jobType })
    else
        rows = MySQL.query.await([[
            SELECT id, name, color, description FROM mdt_tags
            WHERE type = 'officer'
            ORDER BY name ASC
        ]])
    end
    return rows or {}
end)

-- Update officer certifications
ps.registerCallback('ps-mdt:server:updateOfficerCertifications', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, message = 'Unauthorized' } end
    if not CheckPermission(src, 'roster_manage_certifications') then
        return { success = false, message = 'No permission to manage certifications' }
    end

    payload = payload or {}
    local citizenid = payload.citizenid
    local certifications = payload.certifications

    if not citizenid or type(certifications) ~= 'table' then
        return { success = false, message = 'Invalid payload' }
    end

    if isLeoSource(src) then
        if type(payload.reason) ~= 'string' or #payload.reason < 3 then
            return { success = false, message = 'A written reason is required' }
        end
        local target = getCorePersonnel(citizenid)
        if not target then return { success = false, message = 'LEO personnel record not found' } end
        local desired, current = {}, {}
        for _, value in ipairs(certifications) do desired[certificationKey(value)] = true end
        for _, value in ipairs(target.certifications or {}) do current[value] = true end
        for value in pairs(desired) do
            if not current[value] or payload.expiresAt then
                local ok, result = exports.cgn_leo_core:SetCertification(src, citizenid, value, 'active', payload.expiresAt, payload.reason)
                if not ok then return coreResult(false, result) end
            end
        end
        for value in pairs(current) do
            if not desired[value] then
                local ok, result = exports.cgn_leo_core:SetCertification(src, citizenid, value, 'revoked', nil, payload.reason)
                if not ok then return coreResult(false, result) end
            end
        end
        return { success = true, message = 'Certifications updated' }
    end

    EnsureProfileExists(citizenid)

    local encoded = json.encode(certifications)
    MySQL.update.await('UPDATE mdt_profiles SET certifications = ? WHERE citizenid = ?', { encoded, citizenid })

    return { success = true }
end)

-- Get job grades for a specific department
ps.registerCallback('ps-mdt:server:getJobGrades', function(source, payload)
    local src = source
    if not CheckAuth(src) then return {} end
    if not CheckPermission(src, 'roster_manage_officers') then return {} end

    payload = payload or {}
    local jobName = payload.job or 'police'

    local jobData = ps.getSharedJob(jobName)
    if not jobData or not jobData.grades then return {} end

    local grades = {}
    for gradeKey, gradeValue in pairs(jobData.grades) do
        grades[#grades + 1] = {
            grade = tonumber(gradeKey) or 0,
            name = gradeValue.name or ('Grade ' .. gradeKey),
            isBoss = gradeValue.isboss == true or gradeValue.isBoss == true or gradeValue.boss == true,
        }
    end

    table.sort(grades, function(a, b) return a.grade < b.grade end)
    return grades
end)

-- Promote/demote an officer (change their job grade)
-- Set a player's job/grade directly through the active framework.
-- The ps bridge's setJob path depends on a setPlayerData export that isn't
-- present on this server, so promote/terminate calls silently failed. We talk to
-- QBX first (the roster already uses qbx_core), then fall back to QBCore.
---@return boolean ok
local function setOfficerJob(targetSrc, jobName, grade)
    grade = tonumber(grade) or 0

    if GetResourceState('qbx_core') == 'started' and exports['qbx_core'] then
        local ok, res = pcall(function()
            return exports['qbx_core']:SetJob(targetSrc, jobName, grade)
        end)
        -- QBX returns true on success (and may return nil on older builds).
        if ok and res ~= false then return true end
    end

    if ps and ps.setJob then
        local ok, result = pcall(ps.setJob, targetSrc, jobName, grade)
        if ok and result ~= false then return true end
    end

    local ok, QBCore = pcall(function() return exports['qb-core']:GetCoreObject() end)
    if ok and QBCore and QBCore.Functions then
        local Player = QBCore.Functions.GetPlayer(targetSrc)
        if Player and Player.Functions and Player.Functions.SetJob then
            local sok = pcall(function() return Player.Functions.SetJob(jobName, grade) end)
            if sok then return true end
        end
    end

    return false
end

ps.registerCallback('ps-mdt:server:promoteOfficer', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, message = 'Unauthorized' } end
    if not CheckPermission(src, 'roster_manage_officers') then
        return { success = false, message = 'No permission to manage officers' }
    end

    payload = payload or {}
    local citizenid = payload.citizenid
    local jobName = payload.job
    local newGrade = tonumber(payload.grade)

    if not citizenid or not jobName or not newGrade then
        return { success = false, message = 'Missing required fields' }
    end

    if isLeoSource(src) then
        local ok, result = exports.cgn_leo_core:ChangeRank(src, citizenid, newGrade, payload.reason)
        return coreResult(ok, result, 'Officer rank updated')
    end

    -- Validate the grade exists
    local gradeData = ps.getSharedJobGrade(jobName, newGrade)
    if not gradeData then
        return { success = false, message = 'Invalid grade for this job' }
    end

    -- Find the target player (must be online for QBCore SetJob)
    local targetPlayer = ps.getPlayerByIdentifier(citizenid)
    if not targetPlayer then
        return { success = false, message = 'Officer must be online to change rank' }
    end

    local targetSrc = targetPlayer.source or (targetPlayer.PlayerData and targetPlayer.PlayerData.source)
    if not targetSrc then
        return { success = false, message = 'Could not resolve officer source' }
    end

    -- Don't allow changing your own rank
    if targetSrc == src then
        return { success = false, message = 'You cannot change your own rank' }
    end

    if not setOfficerJob(targetSrc, jobName, newGrade) then
        return { success = false, message = 'Failed to update rank (framework error)' }
    end

    local gradeName = gradeData.name or ('Grade ' .. newGrade)

    if ps.auditLog then
        ps.auditLog(src, 'officer_promoted', 'officers', citizenid, {
            job = jobName,
            grade = newGrade,
            gradeName = gradeName,
        })
    end

    return { success = true, message = 'Officer rank updated to ' .. gradeName }
end)

-- Fire an officer (set their job to unemployed)
ps.registerCallback('ps-mdt:server:fireOfficer', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, message = 'Unauthorized' } end
    if not CheckPermission(src, 'roster_manage_officers') then
        return { success = false, message = 'No permission to manage officers' }
    end

    payload = payload or {}
    local citizenid = payload.citizenid

    if not citizenid then
        return { success = false, message = 'Missing citizen ID' }
    end

    if isLeoSource(src) then
        local ok, result = exports.cgn_leo_core:ChangeStatus(src, citizenid, 'separated', payload.reason)
        return coreResult(ok, result, 'Officer has been separated')
    end

    local targetPlayer = ps.getPlayerByIdentifier(citizenid)
    if not targetPlayer then
        return { success = false, message = 'Officer must be online to be terminated' }
    end

    local targetSrc = targetPlayer.source or (targetPlayer.PlayerData and targetPlayer.PlayerData.source)
    if not targetSrc then
        return { success = false, message = 'Could not resolve officer source' }
    end

    -- Don't allow firing yourself
    if targetSrc == src then
        return { success = false, message = 'You cannot fire yourself' }
    end

    if not setOfficerJob(targetSrc, 'unemployed', 0) then
        return { success = false, message = 'Failed to terminate officer (framework error)' }
    end

    -- Optional full personal-data wipe (boss panel toggle). Runs after the job
    -- change so the person is already off the roster; only touches their own
    -- footprint, never investigative/shared data. See personnel_cleanup.lua.
    local cleanup = nil
    if payload.deleteData and CleanupPersonnelData then
        cleanup = CleanupPersonnelData(citizenid)
    end

    if ps.auditLog then
        ps.auditLog(src, 'officer_fired', 'officers', citizenid, {
            dataDeleted = payload.deleteData and true or false,
            cleanupSteps = cleanup and cleanup.steps or nil,
        })
    end

    local message = 'Officer has been terminated'
    if payload.deleteData then
        if cleanup and cleanup.ok then
            message = 'Officer terminated and MDT data removed'
        elseif cleanup then
            message = 'Officer terminated, but data cleanup failed: ' .. tostring(cleanup.error)
        end
    end

    return { success = true, message = message, cleanup = cleanup }
end)

-- Update officer callsign (wrapper around existing setCallsign for NUI)
ps.registerCallback('ps-mdt:server:updateOfficerCallsign', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, message = 'Unauthorized' } end
    if not CheckPermission(src, 'roster_manage_officers') then
        return { success = false, message = 'No permission to manage officers' }
    end

    payload = payload or {}
    local citizenid = payload.citizenid
    local newCallsign = payload.callsign

    if not citizenid or not newCallsign or newCallsign == '' then
        return { success = false, message = 'Missing citizen ID or callsign' }
    end

    if isLeoSource(src) then
        local ok, result = exports.cgn_leo_core:ChangeCallsign(src, citizenid, newCallsign, payload.reason)
        return coreResult(ok, result, 'Callsign updated to ' .. newCallsign)
    end

    local targetSource = GetFrameworkPlayerSource(citizenid)
    if not targetSource then
        return { success = false, message = 'Officer must be online to update callsign' }
    end

    if not SetCitizenMetadata(citizenid, 'callsign', newCallsign) then
        return { success = false, message = 'Framework metadata update failed' }
    end

    local resourceName = GetCurrentResourceName()
    TriggerClientEvent(resourceName .. ':client:updateCallsign', targetSource, newCallsign)

    MySQL.update.await('UPDATE mdt_profiles SET callsign = ? WHERE citizenid = ?', { newCallsign, citizenid })

    if ps.auditLog then
        ps.auditLog(src, 'callsign_changed', 'officers', citizenid, { callsign = newCallsign })
    end

    return { success = true, message = 'Callsign updated to ' .. newCallsign }
end)

ps.registerCallback('ps-mdt:server:hireOfficer', function(source, payload)
    if not CheckAuth(source) or not isLeoSource(source) then
        return { success = false, message = 'Unauthorized' }
    end
    payload = payload or {}
    local ok, result = exports.cgn_leo_core:Hire(source, {
        citizenid = payload.citizenid,
        badge = payload.badge,
        callsign = payload.callsign,
        reason = payload.reason,
    })
    return coreResult(ok, result, 'Officer hired at entry rank')
end)

ps.registerCallback('ps-mdt:server:updateOfficerBadge', function(source, payload)
    if not CheckAuth(source) or not isLeoSource(source) then
        return { success = false, message = 'Unauthorized' }
    end
    payload = payload or {}
    local ok, result = exports.cgn_leo_core:ChangeBadge(source, payload.citizenid, payload.badge, payload.reason)
    return coreResult(ok, result, 'Badge number updated')
end)

ps.registerCallback('ps-mdt:server:updateOfficerAssignment', function(source, payload)
    if not CheckAuth(source) or not isLeoSource(source) then
        return { success = false, message = 'Unauthorized' }
    end
    payload = payload or {}
    local ok, result = exports.cgn_leo_core:SetAssignment(source, payload.citizenid, payload.assignment,
        payload.primary == true, payload.active ~= false, payload.reason)
    return coreResult(ok, result, 'Assignment updated')
end)

ps.registerCallback('ps-mdt:server:updateOfficerStatus', function(source, payload)
    if not CheckAuth(source) or not isLeoSource(source) then
        return { success = false, message = 'Unauthorized' }
    end
    payload = payload or {}
    local ok, result = exports.cgn_leo_core:ChangeStatus(source, payload.citizenid, payload.status, payload.reason)
    return coreResult(ok, result, 'Employment status updated')
end)

ps.registerCallback('ps-mdt:server:transferOfficer', function(source, payload)
    if not CheckAuth(source) or not isLeoSource(source) then
        return { success = false, message = 'Unauthorized' }
    end
    payload = payload or {}
    local ok, result = exports.cgn_leo_core:Transfer(source, payload.citizenid, payload.agency,
        tonumber(payload.grade), payload.reason)
    return coreResult(ok, result, 'Officer transferred')
end)

ps.registerCallback('ps-mdt:server:updateOfficerCompartment', function(source, payload)
    if not CheckAuth(source) or not isLeoSource(source) then
        return { success = false, message = 'Unauthorized' }
    end
    payload = payload or {}
    local ok, result = exports.cgn_leo_core:SetCompartment(source, payload.citizenid, payload.compartment,
        payload.active == true, payload.expiresAt, payload.reason)
    return coreResult(ok, result, 'Protected access updated')
end)

ps.registerCallback('ps-mdt:server:grantOfficerPermission', function(source, payload)
    if not CheckAuth(source) or not isLeoSource(source) then
        return { success = false, message = 'Unauthorized' }
    end
    payload = payload or {}
    local ok, result = exports.cgn_leo_core:GrantTemporaryPermission(source, payload.citizenid,
        payload.permission, payload.expiresAt, payload.reason)
    return coreResult(ok, result, 'Temporary permission granted')
end)

ps.registerCallback('ps-mdt:server:restrictOfficerPermission', function(source, payload)
    if not CheckAuth(source) or not isLeoSource(source) then
        return { success = false, message = 'Unauthorized' }
    end
    payload = payload or {}
    local ok, result = exports.cgn_leo_core:SetRestriction(source, payload.citizenid, payload.permission,
        payload.active == true, payload.expiresAt, payload.reason)
    return coreResult(ok, result, 'Permission restriction updated')
end)

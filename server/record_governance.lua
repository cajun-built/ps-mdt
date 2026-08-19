local resourceName = tostring(GetCurrentResourceName())

local recordTables = {
    case = 'mdt_cases',
    report = 'mdt_reports',
    bolo = 'mdt_bolos',
    evidence = 'mdt_evidence_items',
}

local lifecycleStatuses = {
    case = { active = true, closed = true, voided = true },
    report = { draft = true, submitted = true, approved = true, closed = true, voided = true },
    bolo = { active = true, closed = true, voided = true },
    evidence = { active = true, released = true, disposed = true, voided = true },
}

local lifecycleTransitions = {
    case = {
        active = { 'closed', 'voided' },
        closed = { 'active', 'voided' },
        voided = {},
    },
    report = {
        draft = { 'submitted', 'voided' },
        submitted = { 'approved', 'closed', 'voided' },
        approved = { 'closed', 'voided' },
        closed = { 'approved', 'voided' },
        voided = {},
    },
    bolo = {
        active = { 'closed', 'voided' },
        closed = { 'active', 'voided' },
        voided = {},
    },
    evidence = {
        active = { 'released', 'disposed', 'voided' },
        released = { 'active', 'disposed', 'voided' },
        disposed = {},
        voided = {},
    },
}

local legacyLifecycleStatus = {
    case = { active = 'open', closed = 'closed', voided = 'closed' },
    bolo = { active = 'active', closed = 'resolved', voided = 'inactive' },
}

local function trim(value)
    return type(value) == 'string' and value:gsub('^%s+', ''):gsub('%s+$', '') or ''
end

local function getAllowedTransitions(recordType, status)
    local transitions = lifecycleTransitions[recordType]
    if not transitions then return {} end
    return transitions[status] or {}
end

local function canTransition(recordType, currentStatus, nextStatus)
    for _, candidate in ipairs(getAllowedTransitions(recordType, currentStatus)) do
        if candidate == nextStatus then return true end
    end
    return false
end

local function encode(value)
    if value == nil then return nil end
    local ok, result = pcall(json.encode, value)
    return ok and result or nil
end

function GetMdtRecord(recordType, recordId)
    local tableName = recordTables[recordType]
    recordId = tonumber(recordId)
    if not tableName or not recordId then return nil end
    return MySQL.single.await(('SELECT * FROM `%s` WHERE id = ?'):format(tableName), { recordId })
end

function GetMdtRecordActor(source)
    if GetResourceState('cgn_leo_core') ~= 'started' then return nil end
    local ok, context = pcall(function()
        return exports.cgn_leo_core:GetContext(source)
    end)
    if not ok or not context then return nil end
    return {
        citizenid = context.citizenid,
        agency = context.agency,
        name = ps.getPlayerName(source) or context.callsign or 'Unknown',
    }
end

local function contains(values, expected)
    for _, value in ipairs(values or {}) do
        if tostring(value) == tostring(expected) then return true end
    end
    return false
end

function ResolveMdtCreateScope(source, requestedTaskForceId, recordType)
    local actor = GetMdtRecordActor(source)
    if not actor then return nil, nil, 'identity_unavailable' end
    if not requestedTaskForceId or tostring(requestedTaskForceId) == '' then
        return actor.agency, nil, nil
    end

    local ok, context = pcall(function()
        return exports.cgn_leo_core:GetContext(source)
    end)
    if not ok or not context then return nil, nil, 'identity_unavailable' end
    for _, taskForce in ipairs(context.taskForces or {}) do
        if tostring(taskForce.id) == tostring(requestedTaskForceId) then
            local namedType = ({ case = 'cases', report = 'reports', bolo = 'incidents' })[recordType]
            if not contains(taskForce.permissions, 'records.create')
                or not contains(taskForce.agencies, actor.agency)
                or not contains(taskForce.recordTypes, namedType or recordType) then
                return nil, nil, 'task_force_scope_denied'
            end
            return actor.agency, tostring(requestedTaskForceId), nil
        end
    end
    return nil, nil, 'task_force_scope_denied'
end

function ResolveMdtEvidenceScope(source, caseId, reportId, requestedTaskForceId)
    local recordType = caseId and 'case' or reportId and 'report' or nil
    local recordId = caseId or reportId
    if not recordType then return ResolveMdtCreateScope(source, requestedTaskForceId, 'evidence') end

    local record = GetMdtRecord(recordType, recordId)
    local allowed, denied = AuthorizeMdtRecord(source, 'evidence_create', recordType, record, true)
    if not allowed then return nil, nil, denied end
    if requestedTaskForceId and record.task_force_id
        and tostring(requestedTaskForceId) ~= tostring(record.task_force_id) then
        return nil, nil, 'task_force_scope_denied'
    end
    return record.owning_agency, record.task_force_id, nil
end

function ResolveMdtCompartment(source, owningAgency, taskForceId, requestedCompartment)
    if requestedCompartment == nil or tostring(requestedCompartment) == '' then return nil, nil end
    requestedCompartment = tostring(requestedCompartment):lower()
    if not ({ internal_affairs = true, undercover = true, personnel = true })[requestedCompartment] then
        return nil, 'invalid_compartment'
    end
    local allowed, denied = AuthorizeMdtRecord(source, 'evidence_create', 'evidence', {
        id = 0,
        owning_agency = owningAgency,
        task_force_id = taskForceId,
        compartment = requestedCompartment,
    }, true)
    if allowed then return requestedCompartment, nil end
    return nil, denied
end

local function taskForceResource(recordType, record)
    if recordType == 'evidence' then
        if record.case_id then return 'case', record.case_id end
        if record.report_id then return 'report', record.report_id end
    elseif recordType == 'bolo' and record.reportId then
        return 'report', record.reportId
    end
    return recordType, record.id
end

function AuthorizeMdtRecord(source, permissionName, recordType, record, requireOwner)
    if not CheckAuth(source) then return false, 'unauthorized' end
    if not record then return false, 'record_not_found' end
    if not IsLeoMdtSource(source) then
        local fallback = {
            record_view = { case = 'cases_view', report = 'reports_view', bolo = 'bolos_view', evidence = 'evidence_view' },
            record_create = { case = 'cases_create', report = 'reports_create', bolo = 'bolos_create', evidence = 'evidence_create' },
            record_supplement = { case = 'cases_edit', report = 'reports_create', bolo = 'bolos_create', evidence = 'evidence_create' },
            record_lifecycle = { case = 'cases_delete', report = 'reports_delete', bolo = 'bolos_create', evidence = 'evidence_transfer' },
            evidence_lifecycle = { evidence = 'evidence_transfer' },
        }
        local fallbackPermission = fallback[permissionName] and fallback[permissionName][recordType] or permissionName
        local allowed = CheckPermission(source, fallbackPermission)
        if allowed then return true, nil end
        return false, 'permission_denied'
    end

    local resourceType, resourceId = taskForceResource(recordType, record)
    local allowed = AuthorizeLeoPermission(source, permissionName, {
        owningAgency = record.owning_agency,
        requireOwningAgency = requireOwner == true,
        taskForceId = record.task_force_id,
        resourceType = resourceType,
        resourceId = resourceId,
        compartment = record.compartment,
    })
    if allowed then return true, nil end
    return false, 'agency_or_permission_denied'
end

function GetMdtEvidenceVisibility(source, alias)
    alias = alias and (alias .. '.') or ''
    if not IsLeoMdtSource(source) then return '1=1', {} end
    local ok, context = pcall(function()
        return exports.cgn_leo_core:GetContext(source)
    end)
    if not ok or not context then return '1=0', {} end

    local clauses = {
        ('(%scompartment IS NULL OR %scompartment = \'\')'):format(alias, alias),
    }
    local values = {}
    for _, compartment in ipairs(context.compartments or {}) do
        clauses[#clauses + 1] = ("CONCAT(%sowning_agency, ':', %scompartment) = ?"):format(alias, alias)
        values[#values + 1] = compartment
    end
    return '(' .. table.concat(clauses, ' OR ') .. ')', values
end

function AppendMdtRecordRevision(source, recordType, recordId, action, reason, beforeRecord, afterRecord, revisionNumber)
    local actor = GetMdtRecordActor(source)
    if not actor then return false, 'identity_unavailable' end
    reason = trim(reason)
    if reason == '' then return false, 'reason_required' end
    if #reason > 500 then return false, 'reason_too_long' end
    local inserted = MySQL.insert.await([[
        INSERT INTO mdt_record_revisions
            (record_type, record_id, revision_number, action, author_citizenid,
             author_name, author_agency, reason, before_json, after_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        recordType, tonumber(recordId), tonumber(revisionNumber), action,
        actor.citizenid, actor.name, actor.agency, reason,
        encode(beforeRecord), encode(afterRecord),
    })
    if inserted then return true, nil end
    return false, 'revision_failed'
end

function AddMdtRecordSupplement(source, recordType, recordId, content)
    local record = GetMdtRecord(recordType, recordId)
    local allowed, denied = AuthorizeMdtRecord(source, 'record_supplement', recordType, record, false)
    if not allowed then return false, denied end
    content = trim(content)
    if content == '' then return false, 'content_required' end
    if #content > 16000 then return false, 'content_too_long' end

    local actor = GetMdtRecordActor(source)
    if not actor then return false, 'identity_unavailable' end
    local inserted = MySQL.insert.await([[
        INSERT INTO mdt_record_supplements
            (record_type, record_id, author_citizenid, author_name, author_agency, content)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], { recordType, tonumber(recordId), actor.citizenid, actor.name, actor.agency, content })
    if inserted and ps.auditLog then
        ps.auditLog(source, 'record_supplement_added', recordType, tonumber(recordId), {
            supplementId = inserted,
            owningAgency = record.owning_agency,
        })
    end
    if inserted then return true, nil, inserted end
    return false, 'supplement_failed', nil
end

function SetMdtRecordLifecycle(source, recordType, recordId, status, reason)
    local tableName = recordTables[recordType]
    local allowedStatuses = lifecycleStatuses[recordType]
    if not tableName or not allowedStatuses or not allowedStatuses[status] then
        return false, 'invalid_lifecycle_status'
    end

    local record = GetMdtRecord(recordType, recordId)
    local permissionName = recordType == 'evidence' and 'evidence_lifecycle' or 'record_lifecycle'
    local allowed, denied = AuthorizeMdtRecord(source, permissionName, recordType, record, true)
    if not allowed then return false, denied end

    local currentStatus = record.lifecycle_status
        or (recordType == 'report' and 'submitted' or 'active')
    if currentStatus == status then return false, 'lifecycle_unchanged' end
    if not canTransition(recordType, currentStatus, status) then
        return false, 'invalid_lifecycle_transition'
    end

    reason = trim(reason)
    if reason == '' then return false, 'reason_required' end
    if #reason > 500 then return false, 'reason_too_long' end
    local nextVersion = (tonumber(record.version) or 1) + 1
    local afterRecord = {}
    for key, value in pairs(record) do afterRecord[key] = value end
    afterRecord.lifecycle_status = status
    afterRecord.version = nextVersion

    local actor = GetMdtRecordActor(source)
    if not actor then return false, 'identity_unavailable' end
    local failureCode = 'lifecycle_update_failed'
    local transactionOk, success = pcall(function()
        return MySQL.startTransaction(function(query)
            local legacyStatus = legacyLifecycleStatus[recordType]
                and legacyLifecycleStatus[recordType][status] or nil
            local updateSql
            local updateValues
            if legacyStatus then
                updateSql = ('UPDATE `%s` SET lifecycle_status = ?, version = ?, status = ? WHERE id = ? AND version = ?')
                    :format(tableName)
                updateValues = {
                    status, nextVersion, legacyStatus,
                    tonumber(recordId), tonumber(record.version) or 1,
                }
                afterRecord.status = legacyStatus
            else
                updateSql = ('UPDATE `%s` SET lifecycle_status = ?, version = ? WHERE id = ? AND version = ?')
                    :format(tableName)
                updateValues = {
                    status, nextVersion,
                    tonumber(recordId), tonumber(record.version) or 1,
                }
            end

            local updateResult = query(updateSql, updateValues)
            if not updateResult or tonumber(updateResult.affectedRows) ~= 1 then
                failureCode = 'record_version_conflict'
                return false
            end

            local revisionResult = query([[
                INSERT INTO mdt_record_revisions
                    (record_type, record_id, revision_number, action, author_citizenid,
                     author_name, author_agency, reason, before_json, after_json)
                VALUES (?, ?, ?, 'lifecycle_changed', ?, ?, ?, ?, ?, ?)
            ]], {
                recordType, tonumber(recordId), nextVersion, actor.citizenid,
                actor.name, actor.agency, reason, encode(record), encode(afterRecord),
            })
            if not revisionResult or tonumber(revisionResult.affectedRows) ~= 1 then
                failureCode = 'revision_failed'
                return false
            end
            return true
        end)
    end)
    success = transactionOk and success == true
    if success and ps.auditLog then
        ps.auditLog(source, 'record_lifecycle_changed', recordType, tonumber(recordId), {
            status = status,
            reason = reason,
            owningAgency = record.owning_agency,
        })
    end
    if success then return true, nil end
    return false, failureCode
end

ps.registerCallback(resourceName .. ':server:getRecordGovernanceCapabilities', function(source, recordType, recordId)
    local record = GetMdtRecord(recordType, recordId)
    local canView, denied = AuthorizeMdtRecord(source, 'record_view', recordType, record, false)
    if not canView then
        return {
            success = false,
            error = denied,
            canSupplement = false,
            canManageLifecycle = false,
            allowedTransitions = {},
        }
    end

    local canSupplement = AuthorizeMdtRecord(source, 'record_supplement', recordType, record, false) == true
    local lifecyclePermission = recordType == 'evidence' and 'evidence_lifecycle' or 'record_lifecycle'
    local canManageLifecycle = AuthorizeMdtRecord(source, lifecyclePermission, recordType, record, true) == true
    local currentStatus = record.lifecycle_status
        or (recordType == 'report' and 'submitted' or 'active')

    return {
        success = true,
        canView = true,
        canSupplement = canSupplement,
        canManageLifecycle = canManageLifecycle,
        allowedTransitions = canManageLifecycle and getAllowedTransitions(recordType, currentStatus) or {},
        lifecycleStatus = currentStatus,
        version = tonumber(record.version) or 1,
        owningAgency = record.owning_agency,
        taskForceId = record.task_force_id,
    }
end)

ps.registerCallback(resourceName .. ':server:addRecordSupplement', function(source, recordType, recordId, content)
    local success, errorCode, supplementId = AddMdtRecordSupplement(source, recordType, recordId, content)
    return { success = success, error = errorCode, id = supplementId }
end)

ps.registerCallback(resourceName .. ':server:getRecordSupplements', function(source, recordType, recordId)
    local record = GetMdtRecord(recordType, recordId)
    local allowed, denied = AuthorizeMdtRecord(source, 'record_view', recordType, record, false)
    if not allowed then return { success = false, error = denied, supplements = {} } end
    local rows = MySQL.query.await([[
        SELECT id, author_citizenid, author_name, author_agency, content, created_at
        FROM mdt_record_supplements
        WHERE record_type = ? AND record_id = ?
        ORDER BY created_at ASC, id ASC
    ]], { recordType, tonumber(recordId) })
    return { success = true, supplements = rows or {} }
end)

ps.registerCallback(resourceName .. ':server:getRecordRevisions', function(source, recordType, recordId)
    local record = GetMdtRecord(recordType, recordId)
    local allowed, denied = AuthorizeMdtRecord(source, 'record_view', recordType, record, false)
    if not allowed then return { success = false, error = denied, revisions = {} } end
    local rows = MySQL.query.await([[
        SELECT id, revision_number, action, author_citizenid, author_name,
               author_agency, reason, before_json, after_json, created_at
        FROM mdt_record_revisions
        WHERE record_type = ? AND record_id = ?
        ORDER BY revision_number ASC
    ]], { recordType, tonumber(recordId) })
    return { success = true, revisions = rows or {} }
end)

ps.registerCallback(resourceName .. ':server:setRecordLifecycle', function(source, recordType, recordId, status, reason)
    local success, errorCode = SetMdtRecordLifecycle(source, recordType, recordId, status, reason)
    return { success = success, error = errorCode }
end)

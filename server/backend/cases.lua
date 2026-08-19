local resourceName = tostring(GetCurrentResourceName())

local function buildCaseNumber(id)
    local year = os.date('%Y')
    return ('CASE-%s-%05d'):format(year, id)
end

local function normalizeStatus(status)
    local value = status and tostring(status):lower() or 'open'
    if value == 'open' or value == 'in_progress' or value == 'closed' then
        return value
    end
    if value == 'in progress' then
        return 'in_progress'
    end
    return 'open'
end

local function getOfficerDisplayName(src)
    local callsign = ps.getMetadata(src, 'callsign')
    local name = ps.getPlayerName(src) or 'Unknown'
    if callsign and callsign ~= '' then
        return callsign .. ' ' .. name
    end
    return name
end

local function authorizeCaseRecord(src, caseId, permissionName, requireOwner)
    local record = GetMdtRecord('case', caseId)
    local allowed, denied = AuthorizeMdtRecord(src, permissionName, 'case', record, requireOwner)
    return allowed, denied, record
end

ps.registerCallback(resourceName .. ':server:createCase', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    if not CheckPermission(src, 'cases_create') then return { success = false, error = 'Insufficient permissions' } end

    payload = payload or {}
    local title = payload.title or 'Untitled Case'
    local summary = payload.summary or ''
    local status = normalizeStatus(payload.status)
    local priority = payload.priority or 'medium'
    local department = payload.department or ps.getJobName(src) or 'police'

    local citizenid = ps.getIdentifier(src)
    if not citizenid then
        return { success = false, error = 'Missing citizen id' }
    end

    local createdByName = getOfficerDisplayName(src)
    local owningAgency, taskForceId, scopeError = ResolveMdtCreateScope(src, payload.taskForceId, 'case')
    if not owningAgency then return { success = false, error = scopeError } end

    local caseId = MySQL.insert.await([[INSERT INTO mdt_cases
        (case_number, title, summary, status, priority, assigned_department,
         owning_agency, task_force_id, created_by, created_by_name)
        VALUES ('', ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], { title, summary, status, priority, department, owningAgency, taskForceId, citizenid, createdByName })

    if not caseId then
        return { success = false, error = 'Failed to create case' }
    end

    local caseNumber = buildCaseNumber(caseId)
    MySQL.update.await('UPDATE mdt_cases SET case_number = ? WHERE id = ?', { caseNumber, caseId })

    if ps.auditLog then
        ps.auditLog(src, 'case_created', 'case', caseId, {
            title = title,
            status = status,
            priority = priority
        })
    end

    return {
        success = true,
        caseId = caseId,
        caseNumber = caseNumber
    }
end)

ps.registerCallback(resourceName .. ':server:getCases', function(source, page, filters)
    local src = source
    if not CheckAuth(src) then return { cases = {}, hasMore = false } end
    if not CheckPermission(src, 'cases_view') then return { cases = {}, hasMore = false } end

    page = tonumber(page) or 1
    local limit = Config.Pagination and Config.Pagination.Cases or 20
    local offset = (page - 1) * limit

    filters = filters or {}
    local clauses = { "mc.lifecycle_status <> 'voided'" }
    local values = {}

    if filters.status then
        clauses[#clauses + 1] = 'mc.status = ?'
        values[#values + 1] = normalizeStatus(filters.status)
    end

    if filters.department then
        clauses[#clauses + 1] = 'mc.assigned_department = ?'
        values[#values + 1] = filters.department
    end

    local whereClause = ''
    if #clauses > 0 then
        whereClause = 'WHERE ' .. table.concat(clauses, ' AND ')
    end

    values[#values + 1] = limit
    values[#values + 1] = offset

    local rows = MySQL.query.await(([[
        SELECT mc.id, mc.case_number, mc.title, mc.summary, mc.status, mc.priority,
               mc.assigned_department, mc.owning_agency, mc.task_force_id,
               mc.lifecycle_status, mc.version, mc.created_by, mc.created_by_name,
               mc.created_at, mc.updated_at,
               mp.fullname AS primary_officer_name,
               mp.callsign AS primary_officer_callsign
        FROM mdt_cases mc
        LEFT JOIN mdt_case_officers mco ON mco.case_id = mc.id AND mco.role = 'primary'
        LEFT JOIN mdt_profiles mp
            ON CONVERT(mp.citizenid USING utf8mb4) COLLATE utf8mb4_unicode_ci
             = CONVERT(mco.citizenid USING utf8mb4) COLLATE utf8mb4_unicode_ci
        %s
        ORDER BY mc.updated_at DESC
        LIMIT ? OFFSET ?
    ]]):format(whereClause), values)

    return {
        cases = rows or {},
        hasMore = rows and #rows >= limit or false
    }
end)

ps.registerCallback(resourceName .. ':server:getCase', function(source, caseId)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    if not CheckPermission(src, 'cases_view') then return { success = false, error = 'Insufficient permissions' } end

    caseId = tonumber(caseId)
    if not caseId then
        return { success = false, error = 'Invalid case id' }
    end

    local caseRow = MySQL.single.await('SELECT * FROM mdt_cases WHERE id = ?', { caseId })
    if not caseRow then
        return { success = false, error = 'Case not found' }
    end
    local allowed, denied = AuthorizeMdtRecord(src, 'record_view', 'case', caseRow, false)
    if not allowed then return { success = false, error = denied } end

    local officers = MySQL.query.await([[
        SELECT mco.citizenid, mco.role, mco.assigned_by, mco.assigned_at,
               mp.fullname, mp.callsign, mp.badge_number, mp.rank, mp.department
        FROM mdt_case_officers mco
        LEFT JOIN mdt_profiles mp
            ON CONVERT(mp.citizenid USING utf8mb4) COLLATE utf8mb4_unicode_ci
             = CONVERT(mco.citizenid USING utf8mb4) COLLATE utf8mb4_unicode_ci
        WHERE mco.case_id = ?
        ORDER BY mco.assigned_at ASC
    ]], { caseId })

    local attachments = MySQL.query.await([[
        SELECT id, type, url, label, uploaded_by, uploaded_at
        FROM mdt_case_attachments
        WHERE case_id = ?
        ORDER BY uploaded_at DESC
    ]], { caseId })

    local reports = MySQL.query.await([[
        SELECT mr.id, mr.title, mr.type, mr.datecreated
        FROM mdt_case_reports mcr
        INNER JOIN mdt_reports mr ON mr.id = mcr.report_id
        WHERE mcr.case_id = ?
        ORDER BY mr.datecreated DESC
    ]], { caseId })

    local notes = MySQL.query.await([[
        SELECT id, content, author_name, created_at
        FROM mdt_record_supplements
        WHERE record_type = 'case' AND record_id = ?
        ORDER BY created_at DESC, id DESC
    ]], { caseId })

    return {
        success = true,
        data = {
            case = caseRow,
            officers = officers or {},
            attachments = attachments or {},
            evidence = {},
            reports = reports or {},
            notes = notes or {}
        }
    }
end)

ps.registerCallback(resourceName .. ':server:linkReportToCase', function(source, reportId, caseId)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    if not CheckPermission(src, 'cases_edit') then return { success = false, error = 'Insufficient permissions' } end

    reportId = tonumber(reportId)
    caseId = tonumber(caseId)
    if not reportId or not caseId then
        return { success = false, error = 'Invalid report or case' }
    end

    local caseAllowed, caseDenied = authorizeCaseRecord(src, caseId, 'record_create', true)
    if not caseAllowed then return { success = false, error = caseDenied } end
    local reportRecord = GetMdtRecord('report', reportId)
    local reportAllowed, reportDenied = AuthorizeMdtRecord(src, 'record_create', 'report', reportRecord, true)
    if not reportAllowed then return { success = false, error = reportDenied } end

    -- Validate report exists before linking
    local reportExists = MySQL.single.await('SELECT id FROM mdt_reports WHERE id = ?', { reportId })
    if not reportExists then
        return { success = false, error = 'Report #' .. tostring(reportId) .. ' does not exist' }
    end

    MySQL.insert.await([[
        INSERT IGNORE INTO mdt_case_reports (case_id, report_id, linked_by)
        VALUES (?, ?, ?)
    ]], { caseId, reportId, ps.getIdentifier(src) })

    return { success = true }
end)

ps.registerCallback(resourceName .. ':server:unlinkReportFromCase', function(source, reportId, caseId)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    if not CheckPermission(src, 'cases_edit') then return { success = false, error = 'Insufficient permissions' } end
    reportId = tonumber(reportId)
    caseId = tonumber(caseId)
    if not reportId or not caseId then
        return { success = false, error = 'Invalid report or case' }
    end

    local caseAllowed, caseDenied = authorizeCaseRecord(src, caseId, 'record_create', true)
    if not caseAllowed then return { success = false, error = caseDenied } end
    local reportRecord = GetMdtRecord('report', reportId)
    local reportAllowed, reportDenied = AuthorizeMdtRecord(src, 'record_create', 'report', reportRecord, true)
    if not reportAllowed then return { success = false, error = reportDenied } end

    MySQL.query.await('DELETE FROM mdt_case_reports WHERE case_id = ? AND report_id = ?', { caseId, reportId })
    return { success = true }
end)

ps.registerCallback(resourceName .. ':server:getCaseEvidencePage', function(source, caseId, page, limit)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end

    caseId = tonumber(caseId)
    if not caseId then
        return { success = false, error = 'Invalid case id' }
    end

    page = tonumber(page) or 1
    limit = tonumber(limit) or 5
    local offset = (page - 1) * limit
    local visibilityClause, visibilityValues = GetMdtEvidenceVisibility(src)
    local baseValues = { caseId }
    for _, value in ipairs(visibilityValues) do baseValues[#baseValues + 1] = value end

    local totalRow = MySQL.single.await(
        ("SELECT COUNT(id) as total FROM mdt_evidence_items WHERE case_id = ? AND lifecycle_status <> 'voided' AND %s"):format(visibilityClause),
        baseValues
    )
    local total = totalRow and totalRow.total or 0

    local evidenceQuery = ([=[
        SELECT id, title, type, serial, notes, location, stash_id, stored,
            last_holder, pending_holder, transfer_requested_by, transfer_requested_at,
            created_by, owning_agency, task_force_id, compartment, lifecycle_status, version,
            created_at, updated_at
        FROM mdt_evidence_items
        WHERE case_id = ? AND lifecycle_status <> 'voided' AND %s
        ORDER BY created_at DESC
        LIMIT ? OFFSET ?
    ]=]):format(visibilityClause)
    local evidenceValues = { table.unpack(baseValues) }
    evidenceValues[#evidenceValues + 1] = limit
    evidenceValues[#evidenceValues + 1] = offset
    local evidence = MySQL.query.await(evidenceQuery, evidenceValues)

    -- Batch-load all images for returned evidence items (avoids N+1)
    if evidence and #evidence > 0 then
        local ids = {}
        local idLookup = {}
        for _, item in ipairs(evidence) do
            ids[#ids + 1] = item.id
            idLookup[item.id] = item
            item.images = {}
        end

        local placeholders = string.rep('?,', #ids - 1) .. '?'
        local images = MySQL.query.await(([[
            SELECT id, evidence_id, url, label, uploaded_by, uploaded_at
            FROM mdt_evidence_images
            WHERE evidence_id IN (%s)
            ORDER BY uploaded_at DESC
        ]]):format(placeholders), ids)

        for _, img in ipairs(images or {}) do
            local parent = idLookup[img.evidence_id]
            if parent then
                parent.images[#parent.images + 1] = {
                    id = img.id,
                    url = img.url,
                    label = img.label,
                    uploaded_by = img.uploaded_by,
                    uploaded_at = img.uploaded_at
                }
            end
        end
    end

    return {
        success = true,
        data = {
            items = evidence or {},
            total = total,
            page = page,
            limit = limit
        }
    }
end)

ps.registerCallback(resourceName .. ':server:updateCase', function(source, caseId, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    if not CheckPermission(src, 'cases_edit') then return { success = false, error = 'Insufficient permissions' } end

    caseId = tonumber(caseId)
    if not caseId then
        return { success = false, error = 'Invalid case id' }
    end
    local allowed, denied = authorizeCaseRecord(src, caseId, 'record_view', false)
    if not allowed then return { success = false, error = denied } end

    local beforeRecord = GetMdtRecord('case', caseId)
    local allowed, denied = AuthorizeMdtRecord(src, 'record_create', 'case', beforeRecord, true)
    if not allowed then return { success = false, error = denied } end

    payload = payload or {}
    local status = payload.status and normalizeStatus(payload.status) or nil
    local priority = payload.priority

    local updates = {}
    local values = {}

    if payload.title then
        updates[#updates + 1] = 'title = ?'
        values[#values + 1] = payload.title
    end

    if payload.summary then
        updates[#updates + 1] = 'summary = ?'
        values[#values + 1] = payload.summary
    end

    if status then
        updates[#updates + 1] = 'status = ?'
        values[#values + 1] = status
    end

    if priority then
        updates[#updates + 1] = 'priority = ?'
        values[#values + 1] = priority
    end

    if payload.department then
        updates[#updates + 1] = 'assigned_department = ?'
        values[#values + 1] = payload.department
    end

    if #updates == 0 then
        return { success = false, error = 'No updates provided' }
    end

    local nextVersion = (tonumber(beforeRecord.version) or 1) + 1
    updates[#updates + 1] = 'version = ?'
    values[#values + 1] = nextVersion

    values[#values + 1] = caseId
    values[#values + 1] = tonumber(beforeRecord.version) or 1

    local actor = GetMdtRecordActor(src)
    if not actor then return { success = false, error = 'identity_unavailable' } end
    local afterRecord = {}
    for key, value in pairs(beforeRecord) do afterRecord[key] = value end
    if payload.title then afterRecord.title = payload.title end
    if payload.summary then afterRecord.summary = payload.summary end
    if status then afterRecord.status = status end
    if priority then afterRecord.priority = priority end
    if payload.department then afterRecord.assigned_department = payload.department end
    afterRecord.version = nextVersion
    local reason = type(payload.reason) == 'string' and payload.reason:gsub('^%s+', ''):gsub('%s+$', '')
        or 'Case correction submitted through MDT'
    local transactionFailure = 'Failed to update case'
    local callOk, success = pcall(function()
        return MySQL.startTransaction(function(query)
            local updateResult = query(
                ('UPDATE mdt_cases SET %s WHERE id = ? AND version = ?'):format(table.concat(updates, ', ')),
                values
            )
            if not updateResult or tonumber(updateResult.affectedRows) ~= 1 then
                transactionFailure = 'record_version_conflict'
                return false
            end

            local revisionResult = query([[
                INSERT INTO mdt_record_revisions
                    (record_type, record_id, revision_number, action, author_citizenid,
                     author_name, author_agency, reason, before_json, after_json)
                VALUES ('case', ?, ?, 'corrected', ?, ?, ?, ?, ?, ?)
            ]], {
                caseId, nextVersion, actor.citizenid, actor.name, actor.agency,
                reason, json.encode(beforeRecord), json.encode(afterRecord),
            })
            if not revisionResult or tonumber(revisionResult.affectedRows) ~= 1 then
                transactionFailure = 'revision_failed'
                return false
            end
            return true
        end)
    end)

    if not callOk or success ~= true then
        return { success = false, error = transactionFailure }
    end

    if ps.auditLog then
        ps.auditLog(src, 'case_updated', 'case', caseId, payload)
    end

    return { success = true }
end)

ps.registerCallback(resourceName .. ':server:deleteCase', function(source, caseId)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    caseId = tonumber(caseId)
    if not caseId then
        return { success = false, error = 'Invalid case id' }
    end

    local success, errorCode = SetMdtRecordLifecycle(
        src, 'case', caseId, 'voided', 'Case voided through MDT deletion action'
    )
    return { success = success, error = errorCode }
end)

ps.registerCallback(resourceName .. ':server:assignCaseOfficer', function(source, caseId, officerCitizenId, role)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end

    caseId = tonumber(caseId)
    if not caseId or not officerCitizenId then
        return { success = false, error = 'Invalid case or officer' }
    end

    role = role or 'assisting'
    if not ({ primary = true, assisting = true, supervisor = true })[role] then
        return { success = false, error = 'Invalid officer role' }
    end
    local allowed, denied = authorizeCaseRecord(src, caseId, 'record_create', true)
    if not allowed then return { success = false, error = denied } end

    local insertId = MySQL.insert.await([[
        INSERT INTO mdt_case_officers (case_id, citizenid, role, assigned_by)
        VALUES (?, ?, ?, ?)
    ]], { caseId, officerCitizenId, role, ps.getIdentifier(src) })

    if not insertId then
        return { success = false, error = 'Failed to assign officer' }
    end

    if ps.auditLog then
        ps.auditLog(src, 'case_officer_assigned', 'case', caseId, {
            officer = officerCitizenId,
            role = role
        })
    end

    return { success = true }
end)

ps.registerCallback(resourceName .. ':server:removeCaseOfficer', function(source, caseId, officerCitizenId)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end

    caseId = tonumber(caseId)
    if not caseId or not officerCitizenId then
        return { success = false, error = 'Invalid case or officer' }
    end
    local allowed, denied = authorizeCaseRecord(src, caseId, 'record_create', true)
    if not allowed then return { success = false, error = denied } end

    local success = MySQL.query.await([[
        DELETE FROM mdt_case_officers WHERE case_id = ? AND citizenid = ?
    ]], { caseId, officerCitizenId })

    if not success then
        return { success = false, error = 'Failed to remove officer' }
    end

    if ps.auditLog then
        ps.auditLog(src, 'case_officer_removed', 'case', caseId, {
            officer = officerCitizenId
        })
    end

    return { success = true }
end)

ps.registerCallback(resourceName .. ':server:addCaseAttachment', function(source, caseId, attachment)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end

    caseId = tonumber(caseId)
    if not caseId or not attachment or not attachment.url then
        return { success = false, error = 'Invalid attachment' }
    end
    local allowed, denied = authorizeCaseRecord(src, caseId, 'record_supplement', false)
    if not allowed then return { success = false, error = denied } end

    local attachmentId = MySQL.insert.await([[
        INSERT INTO mdt_case_attachments (case_id, type, url, label, uploaded_by)
        VALUES (?, ?, ?, ?, ?)
    ]], {
        caseId,
        attachment.type or 'document',
        attachment.url,
        attachment.label or '',
        ps.getIdentifier(src)
    })

    if not attachmentId then
        return { success = false, error = 'Failed to add attachment' }
    end

    if ps.auditLog then
        ps.auditLog(src, 'case_attachment_added', 'case', caseId, attachment)
    end

    return { success = true, id = attachmentId }
end)

ps.registerCallback(resourceName .. ':server:addCaseAttachmentUpload', function(source, caseId, attachment)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end

    caseId = tonumber(caseId)
    if not caseId or not attachment or not attachment.data or not attachment.filename then
        return { success = false, error = 'Invalid attachment payload' }
    end
    local allowed, denied = authorizeCaseRecord(src, caseId, 'record_supplement', false)
    if not allowed then return { success = false, error = denied } end

    local data = attachment.data
    local filename = attachment.filename
    local contentType = attachment.contentType or ''
    local label = attachment.label or ''
    local attachmentType = attachment.type or 'document'

    if Config.Uploads and Config.Uploads.AllowedAttachmentTypes then
        local allowed = false
        for _, mime in ipairs(Config.Uploads.AllowedAttachmentTypes) do
            if mime == contentType then
                allowed = true
                break
            end
        end
        if not allowed then
            return { success = false, error = 'Unsupported attachment type' }
        end
    end

    if not FiveManageUpload then
        return { success = false, error = 'FiveManage upload not available' }
    end

    local publicUrl, uploadError = FiveManageUpload(data, filename)
    if not publicUrl then
        return { success = false, error = 'Upload failed: ' .. (uploadError or 'Unknown error') }
    end

    local attachmentId = MySQL.insert.await([[
        INSERT INTO mdt_case_attachments (case_id, type, url, label, uploaded_by)
        VALUES (?, ?, ?, ?, ?)
    ]], {
        caseId,
        attachmentType,
        publicUrl,
        label,
        ps.getIdentifier(src)
    })

    if not attachmentId then
        return { success = false, error = 'Failed to save attachment' }
    end

    if ps.auditLog then
        ps.auditLog(src, 'case_attachment_uploaded', 'case', caseId, {
            label = label,
            url = publicUrl,
            contentType = contentType
        })
    end

    return { success = true, id = attachmentId, url = publicUrl }
end)

ps.registerCallback(resourceName .. ':server:removeCaseAttachment', function(source, attachmentId)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end

    attachmentId = tonumber(attachmentId)
    if not attachmentId then
        return { success = false, error = 'Invalid attachment id' }
    end

    if IsLeoMdtSource(src) then
        return { success = false, error = 'Case attachments are permanent and cannot be deleted' }
    end

    local attachment = MySQL.single.await('SELECT url, case_id FROM mdt_case_attachments WHERE id = ?', { attachmentId })
    local success = MySQL.query.await('DELETE FROM mdt_case_attachments WHERE id = ?', { attachmentId })

    if not success then
        return { success = false, error = 'Failed to remove attachment' }
    end

    if attachment and attachment.url and attachment.url:find('^/ps%-mdt%-v3/uploads/') then
        local path = attachment.url:gsub('^/ps%-mdt%-v3/', '')
        if path ~= '' then
            os.remove(path)
        end
    end

    if ps.auditLog then
        ps.auditLog(src, 'case_attachment_removed', 'case_attachment', attachmentId, {
            caseId = attachment and attachment.case_id or nil
        })
    end

    return { success = true }
end)

-- Add a note to a case
ps.registerCallback(resourceName .. ':server:addCaseNote', function(source, caseId, content)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end

    caseId = tonumber(caseId)
    if not caseId or not content or content == '' then
        return { success = false, error = 'Invalid case or empty note' }
    end

    local success, errorCode, supplementId = AddMdtRecordSupplement(src, 'case', caseId, content)
    return { success = success, error = errorCode, id = supplementId }
end)

-- Delete a note from a case
ps.registerCallback(resourceName .. ':server:deleteCaseNote', function(source, noteId, caseId)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end

    noteId = tonumber(noteId)
    caseId = tonumber(caseId)
    if not noteId or not caseId then
        return { success = false, error = 'Invalid note or case' }
    end

    return { success = false, error = 'Case supplements are permanent and cannot be deleted' }
end)

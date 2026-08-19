local resourceName = tostring(GetCurrentResourceName())

ps.registerCallback(resourceName .. ':server:getEvidenceItems', function(source, page, limit, filters)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    if not CheckPermission(src, 'evidence_view') then return { success = false, error = 'Insufficient permissions' } end

    page = tonumber(page) or 1
    limit = tonumber(limit) or 20
    local offset = (page - 1) * limit

    local visibilityClause, visibilityValues = GetMdtEvidenceVisibility(src)
    local queryParts = { visibilityClause, "lifecycle_status <> 'voided'" }
    local values = { table.unpack(visibilityValues) }

    if filters and filters.caseId then
        queryParts[#queryParts + 1] = 'case_id = ?'
        values[#values + 1] = tonumber(filters.caseId)
    end

    if filters and filters.type and filters.type ~= '' then
        queryParts[#queryParts + 1] = 'type = ?'
        values[#values + 1] = tostring(filters.type)
    end

    if filters and filters.stored ~= nil and filters.stored ~= '' then
        queryParts[#queryParts + 1] = 'stored = ?'
        values[#values + 1] = filters.stored and 1 or 0
    end

    local whereClause = table.concat(queryParts, ' AND ')
    local totalRow = MySQL.single.await(('SELECT COUNT(id) as total FROM mdt_evidence_items WHERE %s'):format(whereClause), values)
    local total = totalRow and totalRow.total or 0

    local listValues = { table.unpack(values) }
    listValues[#listValues + 1] = limit
    listValues[#listValues + 1] = offset

    local evidence = MySQL.query.await(([[
        SELECT id, case_id, report_id, title, type, serial, notes, location, stash_id, stored,
            last_holder, pending_holder, transfer_requested_by, transfer_requested_at,
            created_by, owning_agency, task_force_id, compartment, lifecycle_status, version,
            created_at, updated_at
        FROM mdt_evidence_items
        WHERE %s
        ORDER BY created_at DESC
        LIMIT ? OFFSET ?
    ]]):format(whereClause), listValues)

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

ps.registerCallback(resourceName .. ':server:searchEvidenceItems', function(source, query, page, limit)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    if not CheckPermission(src, 'evidence_view') then return { success = false, error = 'Insufficient permissions' } end

    local _, likeQuery = NormalizeSearch(query)
    page = tonumber(page) or 1
    limit = tonumber(limit) or 20
    if not likeQuery then
        return { success = true, data = { items = {}, total = 0, page = 1, limit = limit } }
    end
    local offset = (page - 1) * limit
    local visibilityClause, visibilityValues = GetMdtEvidenceVisibility(src)
    local countValues = { table.unpack(visibilityValues) }
    for _ = 1, 5 do countValues[#countValues + 1] = likeQuery end

    local totalRow = MySQL.single.await(([=[
        SELECT COUNT(id) as total
        FROM mdt_evidence_items
        WHERE %s AND lifecycle_status <> 'voided'
          AND (title LIKE ? OR serial LIKE ? OR notes LIKE ? OR location LIKE ? OR stash_id LIKE ?)
    ]=]):format(visibilityClause), countValues)

    local total = totalRow and totalRow.total or 0

    local listValues = { table.unpack(countValues) }
    listValues[#listValues + 1] = limit
    listValues[#listValues + 1] = offset
    local evidence = MySQL.query.await(([=[
        SELECT id, case_id, report_id, title, type, serial, notes, location, stash_id, stored,
            last_holder, pending_holder, transfer_requested_by, transfer_requested_at,
            created_by, owning_agency, task_force_id, compartment, lifecycle_status, version,
            created_at, updated_at
        FROM mdt_evidence_items
        WHERE %s AND lifecycle_status <> 'voided'
          AND (title LIKE ? OR serial LIKE ? OR notes LIKE ? OR location LIKE ? OR stash_id LIKE ?)
        ORDER BY created_at DESC
        LIMIT ? OFFSET ?
    ]=]):format(visibilityClause), listValues)

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

ps.registerCallback(resourceName .. ':server:addEvidenceItem', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    if not CheckPermission(src, 'evidence_create') then return { success = false, error = 'Insufficient permissions' } end

    payload = payload or {}
    local evidence = payload.evidence or payload

    if not evidence or not evidence.title then
        return { success = false, error = 'Invalid evidence: title is required' }
    end

    local caseId = nil
    if payload.caseId and tostring(payload.caseId) ~= '' then
        local n = tonumber(payload.caseId)
        if n then
            local row = MySQL.single.await('SELECT id FROM mdt_cases WHERE id = ?', { n })
            if not row then
                return { success = false, error = 'Case #' .. tostring(n) .. ' doesnt exist' }
            end
            caseId = n
        end
    end

    local reportId = nil
    if payload.reportId and tostring(payload.reportId) ~= '' then
        local n = tonumber(payload.reportId)
        if n then
            local row = MySQL.single.await('SELECT id FROM mdt_reports WHERE id = ?', { n })
            if not row then
                return { success = false, error = 'Report #' .. tostring(n) .. ' doesnt exist' }
            end
            reportId = n
        end
    end

    local owningAgency, taskForceId, scopeError = ResolveMdtEvidenceScope(
        src, caseId, reportId, payload.taskForceId or evidence.taskForceId
    )
    if not owningAgency then return { success = false, error = scopeError } end
    local compartment, compartmentError = ResolveMdtCompartment(
        src, owningAgency, taskForceId, evidence.compartment
    )
    if compartmentError then return { success = false, error = compartmentError } end

    local citizenid = ps.getIdentifier(src)
    local evidenceId = nil
    local transactionFailure = 'Failed to add evidence'
    local callOk, success = pcall(function()
        return MySQL.startTransaction(function(query)
            local insertResult = query([[
                INSERT INTO mdt_evidence_items
                (case_id, report_id, title, type, serial, notes, location, stash_id,
                 stored, last_holder, created_by, owning_agency, task_force_id, compartment)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ]], {
                caseId,
                reportId,
                evidence.title,
                evidence.type or 'Evidence',
                evidence.serial or '',
                evidence.notes or '',
                evidence.location or '',
                evidence.stashId or '',
                evidence.stored and 1 or 0,
                citizenid,
                citizenid,
                owningAgency,
                taskForceId,
                compartment
            })
            evidenceId = insertResult and tonumber(insertResult.insertId) or nil
            if not insertResult or tonumber(insertResult.affectedRows) ~= 1 or not evidenceId then
                transactionFailure = 'evidence_insert_failed'
                return false
            end

            local custodyResult = query([[
                INSERT INTO mdt_evidence_custody
                    (evidence_id, from_citizenid, to_citizenid, action, notes)
                VALUES (?, ?, ?, 'collected', ?)
            ]], { evidenceId, nil, citizenid, evidence.notes or '' })
            if not custodyResult or tonumber(custodyResult.affectedRows) ~= 1 then
                transactionFailure = 'initial_custody_failed'
                return false
            end
            return true
        end)
    end)

    if not callOk or success ~= true then
        return { success = false, error = transactionFailure }
    end

    if ps.auditLog then
        ps.auditLog(src, 'evidence_added', 'evidence', evidenceId, evidence)
    end

    return { success = true, id = evidenceId }
end)

ps.registerCallback(resourceName .. ':server:updateEvidenceItem', function(source, evidenceId, evidence)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    if not CheckPermission(src, 'evidence_create') then return { success = false, error = 'Insufficient permissions' } end

    evidenceId = tonumber(evidenceId)
    if not evidenceId or not evidence then
        return { success = false, error = 'Invalid evidence' }
    end

    local beforeRecord = GetMdtRecord('evidence', evidenceId)
    local allowed, denied = AuthorizeMdtRecord(src, 'evidence_create', 'evidence', beforeRecord, true)
    if not allowed then return { success = false, error = denied } end

    local updates = {}
    local values = {}

    if evidence.title then
        updates[#updates + 1] = 'title = ?'
        values[#values + 1] = evidence.title
    end
    if evidence.type then
        updates[#updates + 1] = 'type = ?'
        values[#values + 1] = evidence.type
    end
    if evidence.serial then
        updates[#updates + 1] = 'serial = ?'
        values[#values + 1] = evidence.serial
    end
    if evidence.notes then
        updates[#updates + 1] = 'notes = ?'
        values[#values + 1] = evidence.notes
    end
    if evidence.location then
        updates[#updates + 1] = 'location = ?'
        values[#values + 1] = evidence.location
    end
    if evidence.stashId then
        updates[#updates + 1] = 'stash_id = ?'
        values[#values + 1] = evidence.stashId
    end
    if evidence.stored ~= nil then
        updates[#updates + 1] = 'stored = ?'
        values[#values + 1] = evidence.stored and 1 or 0
    end

    if evidence.caseId then
        local caseRecord = GetMdtRecord('case', evidence.caseId)
        local caseAllowed, caseDenied = AuthorizeMdtRecord(src, 'record_create', 'case', caseRecord, true)
        if not caseAllowed then return { success = false, error = caseDenied } end
        updates[#updates + 1] = 'case_id = ?'
        values[#values + 1] = tonumber(evidence.caseId)
    end

    if evidence.reportId then
        local reportRecord = GetMdtRecord('report', evidence.reportId)
        local reportAllowed, reportDenied = AuthorizeMdtRecord(src, 'record_create', 'report', reportRecord, true)
        if not reportAllowed then return { success = false, error = reportDenied } end
        updates[#updates + 1] = 'report_id = ?'
        values[#values + 1] = tonumber(evidence.reportId)
    end

    if #updates == 0 then
        return { success = false, error = 'No updates provided' }
    end

    local nextVersion = (tonumber(beforeRecord.version) or 1) + 1
    updates[#updates + 1] = 'version = ?'
    values[#values + 1] = nextVersion

    values[#values + 1] = evidenceId
    values[#values + 1] = tonumber(beforeRecord.version) or 1

    local actor = GetMdtRecordActor(src)
    if not actor then return { success = false, error = 'identity_unavailable' } end
    local afterRecord = {}
    for key, value in pairs(beforeRecord) do afterRecord[key] = value end
    if evidence.title then afterRecord.title = evidence.title end
    if evidence.type then afterRecord.type = evidence.type end
    if evidence.serial then afterRecord.serial = evidence.serial end
    if evidence.notes then afterRecord.notes = evidence.notes end
    if evidence.location then afterRecord.location = evidence.location end
    if evidence.stashId then afterRecord.stash_id = evidence.stashId end
    if evidence.stored ~= nil then afterRecord.stored = evidence.stored and 1 or 0 end
    if evidence.caseId then afterRecord.case_id = tonumber(evidence.caseId) end
    if evidence.reportId then afterRecord.report_id = tonumber(evidence.reportId) end
    afterRecord.version = nextVersion
    local reason = type(evidence.reason) == 'string' and evidence.reason:gsub('^%s+', ''):gsub('%s+$', '')
        or 'Evidence correction submitted through MDT'
    local transactionFailure = 'Failed to update evidence'
    local callOk, success = pcall(function()
        return MySQL.startTransaction(function(query)
            local updateResult = query(
                ('UPDATE mdt_evidence_items SET %s WHERE id = ? AND version = ?'):format(table.concat(updates, ', ')),
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
                VALUES ('evidence', ?, ?, 'corrected', ?, ?, ?, ?, ?, ?)
            ]], {
                evidenceId, nextVersion, actor.citizenid, actor.name, actor.agency,
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
        ps.auditLog(src, 'evidence_updated', 'evidence', evidenceId, evidence)
    end

    return { success = true }
end)

ps.registerCallback(resourceName .. ':server:deleteEvidenceItem', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    payload = type(payload) == 'table' and payload or { evidenceId = payload }
    local evidenceId = tonumber(payload.evidenceId or payload.id)
    if not evidenceId then
        return { success = false, error = 'Invalid evidence id' }
    end

    local reason = type(payload.reason) == 'string' and payload.reason:gsub('^%s+', ''):gsub('%s+$', '') or ''
    if reason == '' then
        return { success = false, error = 'reason_required' }
    end

    local success, errorCode = SetMdtRecordLifecycle(
        src, 'evidence', evidenceId, 'voided', reason
    )
    return { success = success, error = errorCode }
end)

ps.registerCallback(resourceName .. ':server:transferEvidenceItem', function(source, evidenceId, toCitizenId, notes)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    if not CheckPermission(src, 'evidence_transfer') then return { success = false, error = 'Insufficient permissions' } end
    local evidenceRecord = GetMdtRecord('evidence', evidenceId)
    local allowed, denied = AuthorizeMdtRecord(src, 'evidence_transfer', 'evidence', evidenceRecord, true)
    if not allowed then return { success = false, error = denied } end

    local success, message = RequestEvidenceTransfer(src, evidenceId, toCitizenId, notes)
    if success and ps.auditLog then
        ps.auditLog(src, 'evidence_transfer_requested', 'evidence', evidenceId, {
            toCitizenId = toCitizenId,
            notes = notes
        })
    end
    local errorMessage = nil
    if not success then errorMessage = message end
    return { success = success, error = errorMessage, message = message }
end)

ps.registerCallback(resourceName .. ':server:acceptEvidenceTransfer', function(source, evidenceId, notes)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    local success, message = AcceptEvidenceTransfer(src, evidenceId, notes)
    if success and ps.auditLog then
        ps.auditLog(src, 'evidence_transfer_accepted', 'evidence', evidenceId, { notes = notes })
    end
    local errorMessage = nil
    if not success then errorMessage = message end
    return { success = success, error = errorMessage, message = message }
end)

ps.registerCallback(resourceName .. ':server:declineEvidenceTransfer', function(source, evidenceId, notes)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    local success, message = DeclineEvidenceTransfer(src, evidenceId, notes)
    if success and ps.auditLog then
        ps.auditLog(src, 'evidence_transfer_declined', 'evidence', evidenceId, { notes = notes })
    end
    local errorMessage = nil
    if not success then errorMessage = message end
    return { success = success, error = errorMessage, message = message }
end)

ps.registerCallback(resourceName .. ':server:getEvidenceCustody', function(source, evidenceId)
    local src = source
    if not CheckAuth(src) then return {} end

    evidenceId = tonumber(evidenceId)
    if not evidenceId then
        return {}
    end
    local evidenceRecord = GetMdtRecord('evidence', evidenceId)
    local allowed = AuthorizeMdtRecord(src, 'record_view', 'evidence', evidenceRecord, false)
    if not allowed then return {} end

    local custody = MySQL.query.await([[
        SELECT id, evidence_id, from_citizenid, to_citizenid, action, notes, created_at
        FROM mdt_evidence_custody
        WHERE evidence_id = ?
        ORDER BY created_at DESC
    ]], { evidenceId })

    return custody or {}
end)

ps.registerCallback(resourceName .. ':server:logEvidenceViewed', function(source, evidenceId)
    local src = source
    if not CheckAuth(src) then return { success = false } end

    evidenceId = tonumber(evidenceId)
    if not evidenceId then return { success = false } end
    local evidenceRecord = GetMdtRecord('evidence', evidenceId)
    local allowed, denied = AuthorizeMdtRecord(src, 'record_view', 'evidence', evidenceRecord, false)
    if not allowed then return { success = false, error = denied } end

    local citizenid = ps.getIdentifier(src)

    MySQL.insert.await([[
        INSERT INTO mdt_evidence_custody (evidence_id, from_citizenid, to_citizenid, action, notes)
        VALUES (?, NULL, ?, 'viewed', '')
    ]], { evidenceId, citizenid })

    return { success = true }
end)

ps.registerCallback(resourceName .. ':server:addEvidenceImage', function(source, evidenceId, image)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    if not CheckPermission(src, 'evidence_upload') then return { success = false, error = 'Insufficient permissions' } end

    evidenceId = tonumber(evidenceId)
    if not evidenceId or not image then
        return { success = false, error = 'Invalid image' }
    end
    local evidenceRecord = GetMdtRecord('evidence', evidenceId)
    local allowed, denied = AuthorizeMdtRecord(src, 'evidence_create', 'evidence', evidenceRecord, true)
    if not allowed then return { success = false, error = denied } end

    local url = image.url or image.data or ''
    local label = image.label or ''

    if not url or url == '' then
        return { success = false, error = 'Missing image URL' }
    end

    local imageId = MySQL.insert.await([[
        INSERT INTO mdt_evidence_images (evidence_id, url, label, uploaded_by)
        VALUES (?, ?, ?, ?)
    ]], { evidenceId, url, label, ps.getIdentifier(src) })

    if not imageId then
        return { success = false, error = 'Failed to add image' }
    end

    if ps.auditLog then
        ps.auditLog(src, 'evidence_image_added', 'evidence', evidenceId, {
            url = url,
            label = label
        })
    end

    return { success = true, id = imageId, url = url }
end)

ps.registerCallback(resourceName .. ':server:removeEvidenceImage', function(source, imageId)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    if IsLeoMdtSource(src) then return { success = false, error = 'Submitted evidence images are permanent records and cannot be deleted' } end
    if not CheckPermission(src, 'evidence_upload') then return { success = false, error = 'Insufficient permissions' } end

    imageId = tonumber(imageId)
    if not imageId then
        return { success = false, error = 'Invalid image id' }
    end

    local image = MySQL.single.await('SELECT url, evidence_id FROM mdt_evidence_images WHERE id = ?', { imageId })
    local success = MySQL.query.await('DELETE FROM mdt_evidence_images WHERE id = ?', { imageId })
    if not success then
        return { success = false, error = 'Failed to remove image' }
    end

    if image and image.url and image.url:find('^/ps%-mdt%-v3/uploads/') then
        local path = image.url:gsub('^/ps%-mdt%-v3/', '')
        if path ~= '' then
            os.remove(path)
        end
    end

    if ps.auditLog then
        ps.auditLog(src, 'evidence_image_removed', 'evidence_image', imageId, {
            evidenceId = image and image.evidence_id or nil
        })
    end

    return { success = true }
end)

ps.registerCallback(resourceName .. ':server:linkEvidenceToCase', function(source, evidenceId, caseId, reportId)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end

    evidenceId = tonumber(evidenceId)
    reportId = tonumber(reportId)

    local numericCaseId = tonumber(caseId)
    if not numericCaseId and type(caseId) == 'string' and caseId ~= '' then
        local row = MySQL.single.await('SELECT id FROM mdt_cases WHERE case_number = ? LIMIT 1', { caseId })
        if row then
            numericCaseId = row.id
        end
    end
    caseId = numericCaseId

    if not evidenceId or not caseId then
        return { success = false, error = 'Invalid evidence or case' }
    end

    local evidenceRecord = GetMdtRecord('evidence', evidenceId)
    local evidenceAllowed, evidenceDenied = AuthorizeMdtRecord(src, 'evidence_create', 'evidence', evidenceRecord, true)
    if not evidenceAllowed then return { success = false, error = evidenceDenied } end
    local caseRecord = GetMdtRecord('case', caseId)
    local caseAllowed, caseDenied = AuthorizeMdtRecord(src, 'record_create', 'case', caseRecord, true)
    if not caseAllowed then return { success = false, error = caseDenied } end

    if reportId then
        local reportRecord = GetMdtRecord('report', reportId)
        local reportAllowed, reportDenied = AuthorizeMdtRecord(src, 'record_create', 'report', reportRecord, true)
        if not reportAllowed then return { success = false, error = reportDenied } end
    end

    local actor = GetMdtRecordActor(src)
    if not actor then return { success = false, error = 'identity_unavailable' } end
    local nextVersion = (tonumber(evidenceRecord.version) or 1) + 1
    local afterRecord = {}
    for key, value in pairs(evidenceRecord) do afterRecord[key] = value end
    afterRecord.case_id = caseId
    afterRecord.version = nextVersion
    local transactionFailure = 'Failed to link evidence to case'
    local callOk, success = pcall(function()
        return MySQL.startTransaction(function(query)
            local updateResult = query([[
                UPDATE mdt_evidence_items
                SET case_id = ?, version = ?
                WHERE id = ? AND version = ?
            ]], { caseId, nextVersion, evidenceId, tonumber(evidenceRecord.version) or 1 })
            if not updateResult or tonumber(updateResult.affectedRows) ~= 1 then
                transactionFailure = 'record_version_conflict'
                return false
            end

            local revisionResult = query([[
                INSERT INTO mdt_record_revisions
                    (record_type, record_id, revision_number, action, author_citizenid,
                     author_name, author_agency, reason, before_json, after_json)
                VALUES ('evidence', ?, ?, 'linked_case', ?, ?, ?, ?, ?, ?)
            ]], {
                evidenceId, nextVersion, actor.citizenid, actor.name, actor.agency,
                ('Evidence linked to case %s'):format(caseRecord.case_number or caseId),
                json.encode(evidenceRecord), json.encode(afterRecord),
            })
            if not revisionResult or tonumber(revisionResult.affectedRows) ~= 1 then
                transactionFailure = 'revision_failed'
                return false
            end

            if reportId then
                local relationResult = query([[
                    INSERT IGNORE INTO mdt_case_reports (case_id, report_id, linked_by)
                    VALUES (?, ?, ?)
                ]], { caseId, reportId, actor.citizenid })
                if not relationResult then
                    transactionFailure = 'report_link_failed'
                    return false
                end
            end
            return true
        end)
    end)
    if not callOk or success ~= true then
        return { success = false, error = transactionFailure }
    end

    if ps.auditLog then
        ps.auditLog(src, 'evidence_linked_case', 'evidence', evidenceId, {
            caseId = caseId,
            reportId = reportId
        })
    end

    return { success = true }
end)

ps.registerCallback(resourceName .. ':server:linkEvidenceToReport', function(source, evidenceId, reportId)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end

    evidenceId = tonumber(evidenceId)
    reportId = tonumber(reportId)

    if not evidenceId or not reportId then
        return { success = false, error = 'Invalid evidence or report' }
    end

    local evidenceRecord = GetMdtRecord('evidence', evidenceId)
    local evidenceAllowed, evidenceDenied = AuthorizeMdtRecord(src, 'evidence_create', 'evidence', evidenceRecord, true)
    if not evidenceAllowed then return { success = false, error = evidenceDenied } end
    local reportRecord = GetMdtRecord('report', reportId)
    local reportAllowed, reportDenied = AuthorizeMdtRecord(src, 'record_create', 'report', reportRecord, true)
    if not reportAllowed then return { success = false, error = reportDenied } end

    local actor = GetMdtRecordActor(src)
    if not actor then return { success = false, error = 'identity_unavailable' } end
    local nextVersion = (tonumber(evidenceRecord.version) or 1) + 1
    local afterRecord = {}
    for key, value in pairs(evidenceRecord) do afterRecord[key] = value end
    afterRecord.report_id = reportId
    afterRecord.version = nextVersion
    local transactionFailure = 'Failed to link evidence to report'
    local callOk, success = pcall(function()
        return MySQL.startTransaction(function(query)
            local updateResult = query([[
                UPDATE mdt_evidence_items
                SET report_id = ?, version = ?
                WHERE id = ? AND version = ?
            ]], { reportId, nextVersion, evidenceId, tonumber(evidenceRecord.version) or 1 })
            if not updateResult or tonumber(updateResult.affectedRows) ~= 1 then
                transactionFailure = 'record_version_conflict'
                return false
            end

            local revisionResult = query([[
                INSERT INTO mdt_record_revisions
                    (record_type, record_id, revision_number, action, author_citizenid,
                     author_name, author_agency, reason, before_json, after_json)
                VALUES ('evidence', ?, ?, 'linked_report', ?, ?, ?, ?, ?, ?)
            ]], {
                evidenceId, nextVersion, actor.citizenid, actor.name, actor.agency,
                ('Evidence linked to report %s'):format(reportId),
                json.encode(evidenceRecord), json.encode(afterRecord),
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
        ps.auditLog(src, 'evidence_linked_report', 'evidence', evidenceId, {
            reportId = reportId
        })
    end

    return { success = true }
end)

ps.registerCallback(resourceName .. ':server:createCaseFromEvidence', function(source, evidenceId, reportId)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end

    evidenceId = tonumber(evidenceId)
    reportId = tonumber(reportId)
    if not evidenceId then
        return { success = false, error = 'Invalid evidence' }
    end

    local evidenceRecord = GetMdtRecord('evidence', evidenceId)
    local evidenceAllowed, evidenceDenied = AuthorizeMdtRecord(src, 'evidence_create', 'evidence', evidenceRecord, true)
    if not evidenceAllowed then return { success = false, error = evidenceDenied } end

    if reportId then
        local reportRecord = GetMdtRecord('report', reportId)
        local reportAllowed, reportDenied = AuthorizeMdtRecord(src, 'record_create', 'report', reportRecord, true)
        if not reportAllowed then return { success = false, error = reportDenied } end
    end

    local citizenid = ps.getIdentifier(src)
    local createdByName = (ps.getMetadata(src, 'callsign') or '') .. ' ' .. (ps.getPlayerName(src) or '')
    createdByName = createdByName:gsub('^%s+', ''):gsub('%s+$', '')
    local actor = GetMdtRecordActor(src)
    if not actor then return { success = false, error = 'identity_unavailable' } end
    local caseId = nil
    local caseNumber = nil
    local nextVersion = (tonumber(evidenceRecord.version) or 1) + 1
    local transactionFailure = 'Failed to create case'
    local callOk, success = pcall(function()
        return MySQL.startTransaction(function(query)
            local insertResult = query([[INSERT INTO mdt_cases
                (case_number, title, summary, status, priority, assigned_department,
                 owning_agency, task_force_id, created_by, created_by_name)
                VALUES ('', ?, ?, 'open', 'medium', ?, ?, ?, ?, ?)
            ]], {
                'Evidence Follow-up', 'Case created from evidence link', evidenceRecord.owning_agency,
                evidenceRecord.owning_agency, evidenceRecord.task_force_id, citizenid, createdByName
            })
            caseId = insertResult and tonumber(insertResult.insertId) or nil
            if not insertResult or tonumber(insertResult.affectedRows) ~= 1 or not caseId then
                transactionFailure = 'case_insert_failed'
                return false
            end

            caseNumber = ('CASE-%s-%05d'):format(os.date('%Y'), caseId)
            local caseNumberResult = query(
                'UPDATE mdt_cases SET case_number = ? WHERE id = ?',
                { caseNumber, caseId }
            )
            if not caseNumberResult or tonumber(caseNumberResult.affectedRows) ~= 1 then
                transactionFailure = 'case_number_failed'
                return false
            end

            local evidenceUpdateResult = query([[
                UPDATE mdt_evidence_items
                SET case_id = ?, version = ?
                WHERE id = ? AND version = ?
            ]], { caseId, nextVersion, evidenceId, tonumber(evidenceRecord.version) or 1 })
            if not evidenceUpdateResult or tonumber(evidenceUpdateResult.affectedRows) ~= 1 then
                transactionFailure = 'record_version_conflict'
                return false
            end

            local afterRecord = {}
            for key, value in pairs(evidenceRecord) do afterRecord[key] = value end
            afterRecord.case_id = caseId
            afterRecord.version = nextVersion
            local revisionResult = query([[
                INSERT INTO mdt_record_revisions
                    (record_type, record_id, revision_number, action, author_citizenid,
                     author_name, author_agency, reason, before_json, after_json)
                VALUES ('evidence', ?, ?, 'linked_case', ?, ?, ?, ?, ?, ?)
            ]], {
                evidenceId, nextVersion, actor.citizenid, actor.name, actor.agency,
                ('Evidence linked to newly created case %s'):format(caseNumber),
                json.encode(evidenceRecord), json.encode(afterRecord),
            })
            if not revisionResult or tonumber(revisionResult.affectedRows) ~= 1 then
                transactionFailure = 'revision_failed'
                return false
            end

            if reportId then
                local relationResult = query([[
                    INSERT IGNORE INTO mdt_case_reports (case_id, report_id, linked_by)
                    VALUES (?, ?, ?)
                ]], { caseId, reportId, citizenid })
                if not relationResult then
                    transactionFailure = 'report_link_failed'
                    return false
                end
            end
            return true
        end)
    end)

    if not callOk or success ~= true then
        return { success = false, error = transactionFailure }
    end

    if ps.auditLog then
        ps.auditLog(src, 'case_created_from_evidence', 'case', caseId, {
            evidenceId = evidenceId,
            reportId = reportId
        })
    end

    return { success = true, caseId = caseId, caseNumber = caseNumber }
end)

RegisterNetEvent(resourceName .. ':server:openEvidenceStash', function(stashId)
    local src = source
    if not CheckAuth(src) then return end
    if not CheckPermission(src, 'evidence_view') then return end

    if not stashId or stashId == '' then return end

    -- qb-inventory
    if GetResourceState('qb-inventory') == 'started' then
        exports['qb-inventory']:OpenInventory(src, stashId, {
            maxweight = 4000000,
            slots = 500,
        })
        return
    end

    -- ox_inventory with forceOpenInventory
    if GetResourceState('ox_inventory') == 'started' then
        
        exports.ox_inventory:RegisterStash(stashId, stashId , 500 , 4000000)

        exports.ox_inventory:forceOpenInventory(src, 'stash', stashId)
        return
    end
end)

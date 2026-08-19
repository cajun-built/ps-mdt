local resourceName = tostring(GetCurrentResourceName())

-- IA records are owned by an agency. BRPD, EBRSO and LSP share the MDT but do
-- not share internal-affairs files unless a future task-force policy explicitly
-- grants that access.
CreateThread(function()
    Wait(2500)
    if EnsureColumn then
        EnsureColumn('mdt_ia_complaints', 'job_type', "`job_type` varchar(10) NOT NULL DEFAULT 'police'")
        EnsureColumn('mdt_ia_complaints', 'officer_citizenid', "`officer_citizenid` varchar(50) DEFAULT NULL AFTER `officer_badge`")
        EnsureColumn('mdt_ia_complaints', 'owning_agency', "`owning_agency` varchar(16) NOT NULL DEFAULT 'brpd' AFTER `job_type`")
    end
    pcall(MySQL.update.await, [[
        UPDATE mdt_ia_complaints complaint
        INNER JOIN cgn_leo_personnel personnel
            ON personnel.citizenid = complaint.officer_citizenid
        SET complaint.owning_agency = personnel.agency
        WHERE personnel.agency IN ('brpd', 'ebrso', 'lsp')
    ]], {})
    pcall(MySQL.query.await,
        'ALTER TABLE mdt_ia_complaints ADD KEY idx_mdt_ia_agency (job_type, owning_agency, status)', {})
end)

local function buildComplaintNumber(id)
    local year = os.date('%Y')
    return ('IA-%s-%05d'):format(year, id)
end

-- Submit a complaint (NO CheckAuth -- civilians can submit)
local function iaCfg()
    return (Config and Config.IA) or {}
end

-- What each status means to somebody who doesn't work at IA.
local STATUS_TEXT = {
    open          = 'has been received and is awaiting review',
    under_review  = 'is now under investigation',
    investigated  = 'has been investigated and is awaiting a decision',
    sustained     = 'has been upheld — the complaint was found to be justified',
    exonerated    = 'has been closed — the officer was found to have acted correctly',
    unfounded     = 'has been closed — no evidence was found to support it',
    closed        = 'has been closed',
}

local VALID_IA_STATUSES = {
    open = true,
    under_review = true,
    investigated = true,
    sustained = true,
    exonerated = true,
    unfounded = true,
    closed = true,
}

local VALID_LEO_AGENCIES = { brpd = true, ebrso = true, lsp = true }

local function normalizeAgency(value)
    value = type(value) == 'string' and value:lower():gsub('%s+', '') or nil
    return value and VALID_LEO_AGENCIES[value] and value or nil
end

local function getIaScope(src)
    local scope = { domain = GetMdtDomain(src) }
    if not IsLeoMdtSource(src) then return scope end

    local ok, context = pcall(function()
        return exports.cgn_leo_core:GetContext(src)
    end)
    scope.agency = ok and context and normalizeAgency(context.agency) or nil
    if not scope.agency then return nil end
    return scope
end

local function auditIa(src, action, complaintId, details)
    if ps.auditLog then ps.auditLog(src, action, 'ia_complaint', complaintId, details or {}) end
end

local function getScopedComplaint(src, complaintId)
    local scope = getIaScope(src)
    if not scope then return nil end
    if scope.agency then
        return MySQL.single.await([[
            SELECT * FROM mdt_ia_complaints
            WHERE id = ? AND job_type = ? AND owning_agency = ?
            LIMIT 1
        ]], { complaintId, scope.domain, scope.agency })
    end
    return MySQL.single.await(
        'SELECT * FROM mdt_ia_complaints WHERE id = ? AND job_type = ? LIMIT 1',
        { complaintId, scope.domain })
end

local function getIaAssignee(src, citizenId)
    if not IsLeoMdtSource(src) then
        return MySQL.single.await(
            'SELECT citizenid, fullname FROM mdt_profiles WHERE citizenid = ? LIMIT 1',
            { citizenId }
        )
    end

    local scope = getIaScope(src)
    if not scope or not scope.agency then return nil end
    return MySQL.single.await([[
        SELECT personnel.citizenid, profile.fullname
        FROM cgn_leo_personnel personnel
        INNER JOIN cgn_leo_compartments compartment
            ON compartment.personnel_id = personnel.id
           AND compartment.compartment = 'internal_affairs'
           AND compartment.status = 'active'
           AND (compartment.expires_at IS NULL OR compartment.expires_at > NOW())
        LEFT JOIN mdt_profiles profile ON profile.citizenid = personnel.citizenid
        WHERE personnel.citizenid = ? AND personnel.agency = ? AND personnel.status = 'active'
        LIMIT 1
    ]], { citizenId, scope.agency })
end

--- Let the complainant know their complaint moved on. The success screen tells them
--- they'll be contacted, so this is the part that keeps that promise.
local function mailComplainantStatus(complaintId, status)
    if not iaCfg().NotifyComplainant then return end
    if not SendCitizenMail then return end

    local row = MySQL.single.await([[
        SELECT complaint_number, complainant_citizenid, officer_name
        FROM mdt_ia_complaints WHERE id = ?
    ]], { complaintId })
    if not row or not row.complainant_citizenid then return end

    local what = STATUS_TEXT[status] or ('is now marked "' .. tostring(status) .. '"')
    local body = ('Your complaint %s %s.'):format(row.complaint_number or '', what)
    if row.officer_name and row.officer_name ~= '' then
        body = body .. ('\n\nOfficer named in the complaint: %s'):format(row.officer_name)
    end
    body = body .. '\n\nYou do not need to reply to this message. If we need anything further from you, we will be in touch.'

    SendCitizenMail(
        row.complainant_citizenid,
        iaCfg().MailSender or 'Internal Affairs',
        ('Complaint %s — update'):format(row.complaint_number or ''),
        body
    )
end

-- Anti-spam. Complaints are a serious accusation; nobody needs to file two a second.
-- ComplaintCooldown[citizenid] = os.clock-ish timestamp in ms
local ComplaintCooldown = {}

AddEventHandler('playerDropped', function()
    local cid = ps.getIdentifier and ps.getIdentifier(source) or nil
    if cid then ComplaintCooldown[cid] = nil end
end)

--- Work out which officer a complaint is actually about.
---
--- The complaint used to keep only the name the civilian typed, and an officer's
--- IA history was found by string-matching it. "Officer Walker" instead of
--- "James Walker" meant the complaint never reached his profile at all. We resolve
--- it to a citizenid here instead — and when we can't, we say so by leaving it NULL
--- rather than guessing and attaching it to the wrong person.
---
--- @return string|nil citizenid
--- @return string|nil agency
local function resolveOfficer(name, badge)
    name  = tostring(name or ''):gsub('^%s+', ''):gsub('%s+$', '')
    badge = tostring(badge or ''):gsub('^%s+', ''):gsub('%s+$', '')

    -- A badge is unique and unambiguous, so trust it first.
    if badge ~= '' then
        local row = MySQL.single.await([[
            SELECT personnel.citizenid, personnel.agency, profile.fullname
            FROM cgn_leo_personnel personnel
            LEFT JOIN mdt_profiles profile ON profile.citizenid = personnel.citizenid
            WHERE personnel.badge_number = ? OR personnel.active_callsign = ? OR profile.callsign = ?
            LIMIT 2
        ]], { badge, badge, badge })
        if row and row.citizenid then return row.citizenid, normalizeAgency(row.agency) end
    end

    if name == '' then return nil, nil end

    -- Fall back to the name, but only when it points at exactly one officer.
    local rows = MySQL.query.await([[
        SELECT personnel.citizenid, personnel.agency
        FROM cgn_leo_personnel personnel
        INNER JOIN mdt_profiles profile ON profile.citizenid = personnel.citizenid
        WHERE LOWER(TRIM(profile.fullname)) = LOWER(TRIM(?))
        LIMIT 2
    ]], { name }) or {}

    if #rows == 1 then return rows[1].citizenid, normalizeAgency(rows[1].agency) end
    return nil, nil -- no match, or ambiguous: better unassigned than wrong
end

ps.registerCallback(resourceName .. ':server:submitComplaint', function(source, data)
    local src = source
    data = data or {}

    local citizenid = ps.getIdentifier(src)
    if not citizenid then
        return { success = false, error = 'Missing citizen id' }
    end

    -- Anti-spam.
    local cooldownMs = iaCfg().CooldownMs or 0
    if cooldownMs > 0 then
        local last = ComplaintCooldown[citizenid]
        local now = GetGameTimer()
        if last and (now - last) < cooldownMs then
            local wait = math.ceil((cooldownMs - (now - last)) / 60000)
            return {
                success = false,
                error = ('You have already filed a complaint recently. Try again in about %d minute(s).'):format(math.max(1, wait)),
            }
        end
    end

    local player = MySQL.single.await([[
        SELECT JSON_UNQUOTE(JSON_EXTRACT(charinfo, "$.firstname")) AS firstname,
               JSON_UNQUOTE(JSON_EXTRACT(charinfo, "$.lastname")) AS lastname
        FROM players WHERE citizenid = ?
    ]], { citizenid })

    local complainantName = 'Unknown'
    if player then
        complainantName = (player.firstname or 'Unknown') .. ' ' .. (player.lastname or '')
    end

    local officerName = tostring(data.officerName or data.officer_name or ''):gsub('^%s+', ''):gsub('%s+$', '')
    local officerBadge = tostring(data.officerBadge or data.officer_badge or ''):gsub('^%s+', ''):gsub('%s+$', '')
    local description = tostring(data.description or ''):gsub('^%s+', ''):gsub('%s+$', '')
    local incidentLocation = tostring(data.incidentLocation or data.incident_location or '')
    if officerName == '' or #officerName > 100 or #officerBadge > 20 then
        return { success = false, error = 'Officer information is invalid' }
    end
    if #description < 20 or #description > 2000 or #incidentLocation > 200 then
        return { success = false, error = 'Complaint description or location is invalid' }
    end
    if not ({
        misconduct = true, excessive_force = true, corruption = true,
        negligence = true, discrimination = true, other = true,
    })[data.category or 'other'] then
        return { success = false, error = 'Complaint category is invalid' }
    end

    local witnesses = data.witnesses
    if type(witnesses) == 'table' then
        witnesses = json.encode(witnesses)
    end
    witnesses = tostring(witnesses or '')

    local evidence = data.evidence
    if type(evidence) == 'table' then
        evidence = json.encode(evidence)
    end
    evidence = tostring(evidence or '[]')
    if #witnesses > 4000 or #evidence > 8000 then
        return { success = false, error = 'Complaint attachments are too large' }
    end

    -- Attach the complaint to a real officer where we can. NULL means "we couldn't
    -- tell who this is about" — IA assigns it by hand rather than it going nowhere.
    local officerCid, officerAgency = resolveOfficer(officerName, officerBadge)
    local owningAgency = officerAgency
        or normalizeAgency(data.agency)
        or normalizeAgency(iaCfg().DefaultAgency)
    if not owningAgency then
        return { success = false, error = 'Select the law enforcement agency involved' }
    end

    -- The success screen promises the complainant will be contacted, so record a
    -- number they can actually be reached on.
    local complainantPhone = data.complainantPhone or data.complainant_phone
    if not complainantPhone or complainantPhone == '' then
        complainantPhone = GetCitizenPhoneNumber and GetCitizenPhoneNumber(citizenid) or nil
    end
    local incidentDate = data.incidentDate or data.incident_date or nil
    local complaintId = MySQL.insert.await([[
        INSERT INTO mdt_ia_complaints
        (complaint_number, complainant_citizenid, complainant_name, complainant_phone,
         officer_citizenid, officer_name, officer_badge,
         category, description, incident_date, incident_location, witnesses, evidence, status, job_type, owning_agency)
        VALUES ('', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'open', 'police', ?)
    ]], {
        citizenid,
        complainantName,
        complainantPhone,
        officerCid,
        officerName,
        officerBadge,
        data.category or 'other',
        description,
        incidentDate,
        incidentLocation,
        witnesses or '[]',
        evidence,
        owningAgency
    })

    if not complaintId then
        return { success = false, error = 'Failed to submit complaint' }
    end

    local complaintNumber = buildComplaintNumber(complaintId)
    MySQL.update.await('UPDATE mdt_ia_complaints SET complaint_number = ? WHERE id = ?', { complaintNumber, complaintId })
    auditIa(src, 'ia_complaint_submitted', complaintId, {
        complaintNumber = complaintNumber,
        owningAgency = owningAgency,
        officerCitizenId = officerCid,
    })

    ComplaintCooldown[citizenid] = GetGameTimer()

    return {
        success = true,
        complaintNumber = complaintNumber
    }
end)

-- Get paginated list of IA complaints
ps.registerCallback(resourceName .. ':server:getIAComplaints', function(source, pageNum, filters)
    local src = source
    filters = filters or {}

    if not CheckAuth(src) then
        ps.debug('getIAComplaints: CheckAuth failed for source ' .. tostring(src))
        return { complaints = {}, hasMore = false }
    end
    if not CheckPermission(src, 'ia_view') then return { complaints = {}, hasMore = false } end

    local page = tonumber(pageNum) or 1
    local limit = Config.Pagination and Config.Pagination.Cases or 20
    local offset = (page - 1) * limit

    local clauses = {}
    local values = {}

    local scope = getIaScope(src)
    if not scope then return { complaints = {}, hasMore = false } end
    clauses[#clauses + 1] = 'job_type = ?'
    values[#values + 1] = scope.domain
    if scope.agency then
        clauses[#clauses + 1] = 'owning_agency = ?'
        values[#values + 1] = scope.agency
    end

    if filters.status and filters.status ~= '' then
        clauses[#clauses + 1] = 'status = ?'
        values[#values + 1] = filters.status
    end

    if filters.search and filters.search ~= '' then
        clauses[#clauses + 1] = '(officer_name LIKE ? OR complainant_name LIKE ? OR complaint_number LIKE ?)'
        local searchTerm = '%' .. filters.search .. '%'
        values[#values + 1] = searchTerm
        values[#values + 1] = searchTerm
        values[#values + 1] = searchTerm
    end

    local whereClause = ''
    if #clauses > 0 then
        whereClause = 'WHERE ' .. table.concat(clauses, ' AND ')
    end

    values[#values + 1] = limit
    values[#values + 1] = offset

    local query = ([[
        SELECT id, complaint_number, complainant_name, officer_name, officer_badge,
               category, status, assigned_to_name, created_at
        FROM mdt_ia_complaints
        %s
        ORDER BY created_at DESC
        LIMIT ? OFFSET ?
    ]]):format(whereClause)

    local ok, rows = pcall(MySQL.query.await, query, values)

    if not ok then
        ps.warn('[getIAComplaints] query failed: ' .. tostring(rows))
        return { complaints = {}, hasMore = false }
    end

    return {
        complaints = rows or {},
        hasMore = rows and #rows >= limit or false
    }
end)

-- Get single IA complaint with notes
ps.registerCallback(resourceName .. ':server:getIAComplaint', function(source, data)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    if not CheckPermission(src, 'ia_view') then return { success = false, error = 'Insufficient permissions' } end

    local complaintId = tonumber(data)
    if not complaintId then
        return { success = false, error = 'Invalid complaint id' }
    end

    local complaint = getScopedComplaint(src, complaintId)
    if not complaint then
        return { success = false, error = 'Complaint not found' }
    end

    local nOk, notes = pcall(MySQL.query.await, [[
        SELECT id, complaint_id, content, author_citizenid, author_name, created_at
        FROM mdt_ia_notes
        WHERE complaint_id = ?
        ORDER BY created_at DESC
    ]], { complaintId })

    return {
        success = true,
        data = {
            complaint = complaint,
            notes = (nOk and notes) or {}
        }
    }
end)

-- Get IA complaints against a specific officer.
--
-- Matches on the officer's citizenid where the complaint carries one, and still
-- falls back to the name so complaints filed before the link existed (or ones IA
-- never managed to assign) don't vanish from the profile.
ps.registerCallback(resourceName .. ':server:getIAHistoryForOfficer', function(source, officerName, officerCid)
    local src = source
    if not CheckAuth(src) then return {} end
    if not CheckPermission(src, 'ia_view') then return {} end

    if (not officerName or officerName == '') and (not officerCid or officerCid == '') then
        return {}
    end
    local scope = getIaScope(src)
    if not scope or not scope.agency then return {} end

    local ok, rows = pcall(MySQL.query.await, [[
        SELECT id, complaint_number, category, status, created_at
        FROM mdt_ia_complaints
        WHERE job_type = ? AND owning_agency = ?
          AND (
                (officer_citizenid IS NOT NULL AND officer_citizenid = ?)
             OR (officer_citizenid IS NULL AND ? <> '' AND officer_name LIKE ?)
          )
        ORDER BY created_at DESC
        LIMIT 50
    ]], {
        scope.domain,
        scope.agency,
        officerCid or '',
        officerName or '',
        '%' .. (officerName or '') .. '%',
    })

    if not ok then return {} end
    return rows or {}
end)

-- Update IA complaint details (officer, badge, date, location)
ps.registerCallback(resourceName .. ':server:updateIAComplaintInfo', function(source, complaintId, updates)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    if not CheckPermission(src, 'ia_manage') then return { success = false, error = 'Insufficient permissions' } end

    complaintId = tonumber(complaintId)
    updates = updates or {}
    if not complaintId then
        return { success = false, error = 'Invalid complaint id' }
    end
    local complaint = getScopedComplaint(src, complaintId)
    if not complaint then return { success = false, error = 'Complaint not found' } end

    local sets = {}
    local vals = {}

    if updates.officer_name ~= nil then
        sets[#sets + 1] = 'officer_name = ?'
        vals[#vals + 1] = updates.officer_name
    end
    if updates.officer_badge ~= nil then
        sets[#sets + 1] = 'officer_badge = ?'
        vals[#vals + 1] = updates.officer_badge
    end

    -- IA correcting the name or badge is exactly when an unassigned complaint can
    -- finally be pinned to a real officer, so re-resolve it here.
    if updates.officer_name ~= nil or updates.officer_badge ~= nil then
        local name  = updates.officer_name  ~= nil and updates.officer_name  or complaint.officer_name
        local badge = updates.officer_badge ~= nil and updates.officer_badge or complaint.officer_badge
        sets[#sets + 1] = 'officer_citizenid = ?'
        vals[#vals + 1] = resolveOfficer(name, badge)
    end
    if updates.incident_date ~= nil then
        sets[#sets + 1] = 'incident_date = ?'
        vals[#vals + 1] = updates.incident_date
    end
    if updates.incident_location ~= nil then
        sets[#sets + 1] = 'incident_location = ?'
        vals[#vals + 1] = updates.incident_location
    end

    if #sets == 0 then
        return { success = false, error = 'No fields to update' }
    end

    local scope = getIaScope(src)
    if not scope or not scope.agency then return { success = false, error = 'Agency context unavailable' } end
    vals[#vals + 1] = complaintId
    vals[#vals + 1] = scope.domain
    vals[#vals + 1] = scope.agency
    local updated = MySQL.update.await(
        'UPDATE mdt_ia_complaints SET ' .. table.concat(sets, ', ') .. ' WHERE id = ? AND job_type = ? AND owning_agency = ?',
        vals
    )
    if not updated or updated < 1 then return { success = false, error = 'Complaint was not updated' } end
    auditIa(src, 'ia_complaint_updated', complaintId, {
        owningAgency = scope.agency,
        fields = sets,
    })
    return { success = true }
end)

-- Update IA complaint status
ps.registerCallback(resourceName .. ':server:updateIAStatus', function(source, complaintId, status)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    if not CheckPermission(src, 'ia_manage') then return { success = false, error = 'Insufficient permissions' } end

    complaintId = tonumber(complaintId)
    if not complaintId or not status then
        return { success = false, error = 'Invalid complaint id or status' }
    end
    if not VALID_IA_STATUSES[status] then
        return { success = false, error = 'Invalid IA status' }
    end
    local complaint = getScopedComplaint(src, complaintId)
    if not complaint then return { success = false, error = 'Complaint not found' } end

    local ok, updated = pcall(
        MySQL.update.await,
        'UPDATE mdt_ia_complaints SET status = ? WHERE id = ? AND job_type = ? AND owning_agency = ?',
        { status, complaintId, complaint.job_type, complaint.owning_agency }
    )
    if not ok then
        ps.warn('[updateIAStatus] Failed: ' .. tostring(updated))
        return { success = false, error = 'Failed to update status: ' .. tostring(updated) }
    end
    if not updated or updated < 1 then return { success = false, error = 'Complaint was not updated' } end
    auditIa(src, 'ia_status_changed', complaintId, {
        from = complaint.status,
        to = status,
        owningAgency = complaint.owning_agency,
    })

    mailComplainantStatus(complaintId, status)

    return { success = true }
end)

-- Assign an investigator to an IA complaint (or unassign with '__unassign__')
ps.registerCallback(resourceName .. ':server:assignIAComplaint', function(source, complaintId, assigneeCitizenId)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    if not CheckPermission(src, 'ia_manage') then return { success = false, error = 'Insufficient permissions' } end

    complaintId = tonumber(complaintId)
    if not complaintId or not assigneeCitizenId then
        return { success = false, error = 'Invalid complaint or assignee' }
    end
    local complaint = getScopedComplaint(src, complaintId)
    if not complaint then return { success = false, error = 'Complaint not found' } end

    -- Handle unassign
    if assigneeCitizenId == '__unassign__' then
        local updated = MySQL.update.await(
            'UPDATE mdt_ia_complaints SET assigned_to = NULL, assigned_to_name = NULL WHERE id = ? AND job_type = ? AND owning_agency = ?',
            { complaintId, complaint.job_type, complaint.owning_agency }
        )
        if not updated or updated < 1 then return { success = false, error = 'Complaint was not updated' } end
        auditIa(src, 'ia_assignment_changed', complaintId, {
            assignedTo = nil,
            owningAgency = complaint.owning_agency,
        })
        return { success = true }
    end

    local assignee = getIaAssignee(src, assigneeCitizenId)
    if not assignee then
        return { success = false, error = 'Assignee is not an active IA investigator' }
    end
    local assigneeName = assignee.fullname or 'Unknown'

    local updated = MySQL.update.await('UPDATE mdt_ia_complaints SET assigned_to = ?, assigned_to_name = ? WHERE id = ? AND job_type = ? AND owning_agency = ?', {
        assigneeCitizenId,
        assigneeName,
        complaintId,
        complaint.job_type,
        complaint.owning_agency
    })
    if not updated or updated < 1 then return { success = false, error = 'Complaint was not updated' } end
    auditIa(src, 'ia_assignment_changed', complaintId, {
        assignedTo = assigneeCitizenId,
        owningAgency = complaint.owning_agency,
    })

    return { success = true }
end)

-- Add a note to an IA complaint
ps.registerCallback(resourceName .. ':server:addIANote', function(source, complaintId, content)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    if not CheckPermission(src, 'ia_manage') then return { success = false, error = 'Insufficient permissions' } end

    complaintId = tonumber(complaintId)
    if not complaintId or not content or content == '' then
        return { success = false, error = 'Invalid complaint or empty note' }
    end
    if type(content) ~= 'string' or #content > 4000 then
        return { success = false, error = 'IA note is too long' }
    end
    local complaint = getScopedComplaint(src, complaintId)
    if not complaint then return { success = false, error = 'Complaint not found' } end

    local citizenId = ps.getIdentifier(src)
    local profile = MySQL.single.await('SELECT fullname FROM mdt_profiles WHERE citizenid = ?', { citizenId })
    local authorName = profile and profile.fullname or 'Unknown'

    local noteId = MySQL.insert.await([[
        INSERT INTO mdt_ia_notes (complaint_id, content, author_citizenid, author_name)
        VALUES (?, ?, ?, ?)
    ]], { complaintId, content, citizenId, authorName })
    if not noteId then return { success = false, error = 'Failed to add IA note' } end
    auditIa(src, 'ia_note_added', complaintId, {
        noteId = noteId,
        owningAgency = complaint.owning_agency,
    })

    return { success = true }
end)

-- Delete a note from an IA complaint
ps.registerCallback(resourceName .. ':server:deleteIANote', function(source, noteId, complaintId)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    if not CheckPermission(src, 'ia_manage') then return { success = false, error = 'Insufficient permissions' } end
    if IsLeoMdtSource(src) then return { success = false, error = 'IA notes are permanent records and cannot be deleted' } end

    noteId = tonumber(noteId)
    complaintId = tonumber(complaintId)
    if not noteId or not complaintId then
        return { success = false, error = 'Invalid note or complaint' }
    end
    local complaint = getScopedComplaint(src, complaintId)
    if not complaint then return { success = false, error = 'Complaint not found' } end

    MySQL.query.await('DELETE FROM mdt_ia_notes WHERE id = ? AND complaint_id = ?', { noteId, complaintId })
    return { success = true }
end)

local resourceName = tostring(GetCurrentResourceName())

-- Send to Jail
ps.registerCallback(resourceName .. ':server:sendToJail', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, message = 'Unauthorized' } end
    if not CheckPermission(src, 'charges_edit') then
        return { success = false, message = 'Insufficient permissions' }
    end

    payload = payload or {}
    local citizenId = payload.citizenId
    local sentence = tonumber(payload.sentence)

    if not citizenId or not sentence or sentence <= 0 then
        return { success = false, message = 'Missing citizen ID or invalid sentence' }
    end

    local maxSentence = (Config and Config.Fines and Config.Fines.MaxSentence) or 999
    if sentence > maxSentence then
        return { success = false, message = 'Sentence exceeds maximum of ' .. maxSentence .. ' months' }
    end

    local targetPlayer = ps.getPlayerByIdentifier(citizenId)
    if not targetPlayer then
        return { success = false, message = 'Player must be online to send to jail' }
    end

    local targetSource = targetPlayer.source or (targetPlayer.PlayerData and targetPlayer.PlayerData.source)
    if not targetSource then
        return { success = false, message = 'Could not resolve player source' }
    end

    local currentDate = os.date('*t')
    if currentDate.day == 31 then
        currentDate.day = 30
    end

    SetCitizenMetadata(citizenId, 'injail', sentence)
    SetCitizenMetadata(citizenId, 'criminalrecord', {
        ['hasRecord'] = true,
        ['date'] = currentDate
    })
    local jailEvent = Config.JailEvents and Config.JailEvents[MDTFramework.name]
    if jailEvent and jailEvent ~= '' then
        TriggerClientEvent(jailEvent, targetSource, sentence)
    end
    ps.notify(src, 'Sent to jail for ' .. sentence .. ' months', 'success')

    if ps.auditLog then
        ps.auditLog(src, 'sent_to_jail', 'citizen', citizenId, {
            sentence = sentence,
        })
    end

    return { success = true, message = 'Sent to jail for ' .. sentence .. ' months' }
end)

ps.registerCallback(resourceName .. ':server:giveCitation', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, message = 'Unauthorized' } end
    if not CheckPermission(src, 'fine_process') then
        return { success = false, message = 'Insufficient permissions' }
    end

    payload = payload or {}
    local citizenId = type(payload.citizenId) == 'string' and payload.citizenId or nil
    local reportId = tonumber(payload.reportId)

    if not citizenId or citizenId == '' or not reportId then
        return { success = false, message = 'A valid citizen and approved report are required' }
    end

    local report = GetMdtRecord('report', reportId)
    if not report then return { success = false, message = 'Report not found' } end
    if report.lifecycle_status ~= 'approved' and report.lifecycle_status ~= 'closed' then
        return { success = false, message = 'The report must be approved before collecting its fine' }
    end

    local allowed = AuthorizeMdtRecord(src, 'record_create', 'report', report, true)
    if not allowed then
        return { success = false, message = 'You are not authorized to collect fines for this report' }
    end

    local fineRow = MySQL.single.await([[
        SELECT COALESCE(SUM(count * fine), 0) AS total
        FROM mdt_reports_charges
        WHERE reportid = ? AND citizenid = ?
    ]], { reportId, citizenId })
    local fine = math.floor(tonumber(fineRow and fineRow.total) or 0)
    if fine <= 0 then
        return { success = false, message = 'This citizen has no fine recorded on the report' }
    end

    local maxFine = (Config and Config.Fines and Config.Fines.MaxAmount) or 100000
    if fine > maxFine then
        return { success = false, message = 'Fine exceeds maximum of $' .. maxFine }
    end

    local Player = ps.getPlayerByIdentifier(citizenId)
    if not Player then
        return { success = false, message = 'Player must be online to issue a fine' }
    end

    local playerSrc = Player.source or (Player.PlayerData and Player.PlayerData.source)
    if not playerSrc then
        return { success = false, message = 'Could not resolve player source' }
    end

    local actorId = ps.getIdentifier(src)
    if not actorId then return { success = false, message = 'Officer identity unavailable' } end
    local paymentId = MySQL.insert.await([[
        INSERT IGNORE INTO mdt_fine_payments
            (report_id, citizenid, amount, processed_by, status)
        VALUES (?, ?, ?, ?, 'processing')
    ]], { reportId, citizenId, fine, actorId })
    if not paymentId or tonumber(paymentId) == 0 then
        return { success = false, message = 'This report fine was already processed or is in progress' }
    end

    local removed = ps.removeMoney(playerSrc, 'bank', fine, 'mdt-fine')
    if not removed then
        MySQL.update.await(
            "DELETE FROM mdt_fine_payments WHERE id = ? AND status = 'processing'",
            { paymentId }
        )
        return { success = false, message = 'Could not deduct fine (insufficient funds)' }
    end

    MySQL.update.await([[
        UPDATE mdt_fine_payments
        SET status = 'paid', processed_at = NOW()
        WHERE id = ? AND status = 'processing'
    ]], { paymentId })

    ps.notify(playerSrc, '$' .. fine .. ' fine deducted from your bank account', 'error')
    ps.notify(src, '$' .. fine .. ' fine issued successfully', 'success')

    if ps.auditLog then
        local officerName = ps.getPlayerName(src) or 'Unknown Officer'
        ps.auditLog(src, 'fine_issued', 'citizen', citizenId, {
            fine = fine,
            reportId = reportId,
            officerName = officerName,
        })
    end

    return { success = true, message = '$' .. fine .. ' fine issued' }
end)

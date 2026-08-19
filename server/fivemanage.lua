-- FiveManage API integration for image uploads and activity logging
-- Docs: https://docs.fivemanage.com
--
-- Server.cfg convars:
--   set ps_mdt_fivemanage_key_images "YOUR_IMAGES_API_KEY"
--   set ps_mdt_fivemanage_key_logs   "YOUR_LOGS_API_KEY"

local FiveManageApiUrl = 'https://api.fivemanage.com/api/v3/file/base64'
local FiveManageLogsUrl = 'https://api.fivemanage.com/api/v3/logs'

local FiveManageApiKey = GetConvar('ps_mdt_fivemanage_key_images', '')
local FiveManageLogsKey = GetConvar('ps_mdt_fivemanage_key_logs', '')

local resourceName = tostring(GetCurrentResourceName())
local UploadRateLimits = {}
local UploadSignatures = {
    ['image/png'] = 'iVBORw0KGgo',
    ['image/jpeg'] = '/9j/',
    ['image/webp'] = 'UklGR',
    ['application/pdf'] = 'JVBERi0',
}

local function isAllowedUploadType(mimeType, allowedTypes)
    for _, allowed in ipairs(allowedTypes or {}) do
        if mimeType == allowed then return true end
    end
    return false
end

local function consumeUploadAllowance(source)
    local limit = tonumber(Config and Config.Uploads and Config.Uploads.RateLimitPerMinute) or 0
    if not source or limit <= 0 then return true end

    local now = os.time()
    local bucket = UploadRateLimits[source]
    if not bucket or now - bucket.startedAt >= 60 then
        UploadRateLimits[source] = { startedAt = now, count = 1 }
        return true
    end
    if bucket.count >= limit then return false end
    bucket.count = bucket.count + 1
    return true
end

local function validateUpload(base64Data, allowedTypes)
    if type(base64Data) ~= 'string' or base64Data == '' then
        return nil, nil, 'No image data'
    end

    local mimeType, rawBase64 = base64Data:match('^data:([^;]+);base64,(.+)$')
    if not mimeType or not rawBase64 then
        return nil, nil, 'Invalid upload encoding'
    end
    if rawBase64:find('[^A-Za-z0-9+/=]') then
        return nil, nil, 'Invalid base64 payload'
    end

    allowedTypes = allowedTypes or (Config and Config.Uploads and Config.Uploads.AllowedEvidenceImageTypes) or {}
    if not isAllowedUploadType(mimeType, allowedTypes) then
        return nil, nil, 'Unsupported upload type'
    end
    local signature = UploadSignatures[mimeType]
    if not signature or rawBase64:sub(1, #signature) ~= signature then
        return nil, nil, 'Upload content does not match its declared type'
    end

    local padding = rawBase64:sub(-2) == '==' and 2 or (rawBase64:sub(-1) == '=' and 1 or 0)
    local decodedBytes = math.floor(#rawBase64 * 3 / 4) - padding
    local maxBytes = tonumber(Config and Config.Uploads and Config.Uploads.MaxBytes) or 5242880
    if decodedBytes <= 0 or decodedBytes > maxBytes then
        return nil, nil, 'Upload exceeds the maximum file size'
    end

    return rawBase64, mimeType, nil
end

AddEventHandler('playerDropped', function()
    UploadRateLimits[source] = nil
end)

--- Upload a base64 data URI to FiveManage and return the public URL.
--- @param base64Data string     A base64 data URI
--- @param filename string       Original filename for metadata
--- @param source number|nil     Player source for rate limiting
--- @param allowedTypes table|nil Allowed MIME types
--- @return string|nil url       The public URL on success, nil on failure
--- @return string|nil error     Error message on failure
function FiveManageUpload(base64Data, filename, source, allowedTypes)
    local rawBase64, _, validationError = validateUpload(base64Data, allowedTypes)
    if not rawBase64 then return nil, validationError end
    if not consumeUploadAllowance(source) then return nil, 'Upload rate limit exceeded' end

    if not FiveManageApiKey or FiveManageApiKey == '' then
        local msg = 'FiveManage API key not configured. Add to server.cfg: set ps_mdt_fivemanage_key_images "YOUR_KEY"'
        ps.warn(msg)
        return nil, msg
    end

    filename = tostring(filename or 'upload.bin'):gsub('[^%w._-]', '_'):sub(1, 128)

    local p = promise.new()

    PerformHttpRequest(FiveManageApiUrl, function(statusCode, responseText)
        if statusCode >= 200 and statusCode < 300 and responseText then
            local ok, data = pcall(json.decode, responseText)
            if ok and data and data.data and data.data.url then
                p:resolve({ url = data.data.url })
            elseif ok and data and data.url then
                p:resolve({ url = data.url })
            else
                ps.warn('FiveManage upload: unexpected response: ' .. tostring(responseText))
                p:resolve({ url = nil, error = 'Unexpected API response' })
            end
        else
            local errMsg = 'HTTP ' .. tostring(statusCode)
            if statusCode == 401 or statusCode == 403 then
                errMsg = 'Invalid API key (HTTP ' .. tostring(statusCode) .. ')'
            elseif statusCode == 413 then
                errMsg = 'Image too large for API (HTTP 413)'
            elseif statusCode == 0 or not statusCode then
                errMsg = 'Could not connect to FiveManage API'
            end
            ps.warn('FiveManage upload failed: ' .. errMsg)
            p:resolve({ url = nil, error = errMsg })
        end
    end, 'POST', json.encode({
        base64 = rawBase64,
        filename = filename,
    }), {
        ['Content-Type'] = 'application/json',
        ['Authorization'] = FiveManageApiKey,
    })

    local result = Citizen.Await(p)
    return result.url, result.error
end


-- Server callback to upload a mugshot from base64 data (API key stays server-side)
ps.registerCallback(resourceName .. ':server:uploadMugshotBase64', function(source, base64Data)
    if not CheckAuth(source) then return { url = nil, error = 'Unauthorized' } end
    if not CheckPermission(source, 'citizens_edit_profile') then
        return { url = nil, error = 'Insufficient permissions' }
    end
    local allowedTypes = Config and Config.Uploads and Config.Uploads.AllowedEvidenceImageTypes or nil
    local url, err = FiveManageUpload(base64Data, 'mugshot_' .. source .. '.png', source, allowedTypes)
    return { url = url, error = err }
end)

-- Server event: receive mugshot URLs from client and store in profile gallery
RegisterNetEvent(resourceName .. ':server:mugshotUpload')
AddEventHandler(resourceName .. ':server:mugshotUpload', function(citizenid, mugshotUrls)
    local src = source
    if not CheckAuth(src) then return end
    if not CheckPermission(src, 'citizens_edit_profile') then return end
    if type(citizenid) ~= 'string' or citizenid == '' or #citizenid > 64 then return end
    if type(mugshotUrls) ~= 'table' or #mugshotUrls == 0 or #mugshotUrls > 4 then return end

    local validatedUrls = {}
    for _, url in ipairs(mugshotUrls) do
        if type(url) ~= 'string' or #url > 2048 or not url:find('^https://') then return end
        validatedUrls[#validatedUrls + 1] = url
    end

    -- Ensure profile exists
    if not EnsureProfileExists(citizenid) then
        ps.warn('Failed to create profile for mugshot upload: ' .. citizenid)
        return
    end

    local profile = MySQL.single.await('SELECT id FROM mdt_profiles WHERE citizenid = ?', { citizenid })
    if not profile then
        ps.warn('Profile not found after ensure for mugshot upload: ' .. citizenid)
        return
    end

    -- Set the first mugshot as profile picture
    MySQL.update.await('UPDATE mdt_profiles SET profilepicture = ? WHERE citizenid = ?', { validatedUrls[1], citizenid })

    -- Add all mugshots to gallery
    for _, url in ipairs(validatedUrls) do
        MySQL.insert.await('INSERT INTO mdt_profiles_gallery (profileId, image, label) VALUES (?, ?, ?)', {
            profile.id, url, 'Mugshot'
        })
    end

    if ps.auditLog then
        ps.auditLog(src, 'citizen_mugshot_updated', 'citizen', citizenid, {
            image_count = #validatedUrls,
        })
    end
    ps.debug('Mugshot upload complete for ' .. citizenid .. ' (' .. #validatedUrls .. ' photos)')
end)

-- Upload a profile photo for a suspect via base64 (from MDT UI)
ps.registerCallback(resourceName .. ':server:uploadSuspectPhoto', function(source, citizenid, imageData)
    if not CheckAuth(source) then return { success = false, message = 'Unauthorized' } end
    if not CheckPermission(source, 'citizens_edit_profile') then
        return { success = false, message = 'Insufficient permissions' }
    end
    if type(citizenid) ~= 'string' or citizenid == '' or #citizenid > 64 or not imageData then
        return { success = false, message = 'Missing data' }
    end

    local safeCitizenId = citizenid:gsub('[^%w_-]', '')
    local allowedTypes = Config and Config.Uploads and Config.Uploads.AllowedEvidenceImageTypes or nil
    local imageUrl, uploadError = FiveManageUpload(
        imageData,
        'suspect_' .. safeCitizenId .. '.png',
        source,
        allowedTypes
    )
    if not imageUrl then
        return { success = false, message = 'Upload failed: ' .. (uploadError or 'Unknown error') }
    end

    -- Ensure profile exists
    if not EnsureProfileExists(citizenid) then
        return { success = false, message = 'Failed to create profile' }
    end

    local profile = MySQL.single.await('SELECT id FROM mdt_profiles WHERE citizenid = ?', { citizenid })
    if not profile then
        return { success = false, message = 'Failed to create profile' }
    end

    -- Set as profile picture
    MySQL.update.await('UPDATE mdt_profiles SET profilepicture = ? WHERE citizenid = ?', { imageUrl, citizenid })

    -- Add to gallery
    MySQL.insert.await('INSERT INTO mdt_profiles_gallery (profileId, image, label) VALUES (?, ?, ?)', {
        profile.id, imageUrl, 'Profile Photo'
    })

    if ps.auditLog then
        ps.auditLog(source, 'citizen_profile_photo_updated', 'citizen', citizenid, {
            action_label = 'Updated citizen profile photo',
        })
    end

    return { success = true, message = 'Photo uploaded', imageUrl = imageUrl }
end)

-- FiveManage Activity Logging (batched)
-- Forwards MDT audit log entries to FiveManage Logs API
-- Docs: https://docs.fivemanage.com/fivemanage/guides/logs/best-practices

local LOG_BATCH_SIZE = 50         -- Send when batch reaches this size
local LOG_BATCH_INTERVAL = 5000   -- Or every 5 seconds (ms), whichever comes first
local logBatch = {}
local logBatchTimer = nil

-- Map MDT action names to log levels
local ACTION_LEVELS = {
    -- Errors / critical
    settings_updated = 'warn',
    -- Destructive
    report_deleted   = 'warn',
    case_deleted     = 'warn',
    weapon_deleted   = 'warn',
    evidence_deleted = 'warn',
    icu_deleted      = 'warn',
    -- Default is 'info'
}

local function getLogLevel(action)
    return ACTION_LEVELS[action] or 'info'
end

--- Queue a single log entry for batched delivery to FiveManage
--- @param entry table  { action, actorName, actorCitizenid, entityType, entityId, details }
function FiveManageQueueLog(entry)
    if not FiveManageLogsKey or FiveManageLogsKey == '' then return end

    -- Flatten details to a string to avoid nested objects in metadata
    local detailsStr = nil
    if entry.details then
        local ok, encoded = pcall(json.encode, entry.details)
        detailsStr = ok and encoded or tostring(entry.details)
    end

    logBatch[#logBatch + 1] = {
        level    = getLogLevel(entry.action),
        message  = entry.action,
        resource = resourceName,
        metadata = {
            actorName      = entry.actorName or 'System',
            actorCitizenid = entry.actorCitizenid,
            entityType     = entry.entityType,
            entityId       = entry.entityId,
            details        = detailsStr,
        },
    }

    -- Flush immediately if batch is full
    if #logBatch >= LOG_BATCH_SIZE then
        FiveManageFlushLogs()
    end
end

--- Flush the current log batch to FiveManage
function FiveManageFlushLogs()
    if #logBatch == 0 then return end
    if not FiveManageLogsKey or FiveManageLogsKey == '' then
        logBatch = {}
        return
    end

    -- Take the current batch and reset
    local batch = logBatch
    logBatch = {}

    local payload = json.encode(batch)

    PerformHttpRequest(FiveManageLogsUrl, function(statusCode, responseText)
        if statusCode and statusCode >= 200 and statusCode < 300 then
            -- Success - nothing to do
        else
            ps.warn('FiveManage logs: failed to send batch (' .. #batch .. ' entries) - HTTP ' .. tostring(statusCode))
        end
    end, 'POST', payload, {
        ['Content-Type']  = 'application/json',
        ['Authorization'] = FiveManageLogsKey,
    })
end

-- Periodic flush timer
CreateThread(function()
    while true do
        Wait(LOG_BATCH_INTERVAL)
        if #logBatch > 0 then
            FiveManageFlushLogs()
        end
    end
end)

-- Flush on resource stop to avoid losing buffered logs
AddEventHandler('onResourceStop', function(res)
    if res == resourceName then
        FiveManageFlushLogs()
    end
end)

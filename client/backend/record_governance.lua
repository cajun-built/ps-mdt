local resourceName = tostring(GetCurrentResourceName())

local function closedResponse(cb)
    if MDTOpen then return false end
    cb({ success = false, error = 'MDT is not open' })
    return true
end

RegisterNUICallback('addRecordSupplement', function(data, cb)
    if closedResponse(cb) then return end
    data = data or {}
    local result = ps.callback(
        resourceName .. ':server:addRecordSupplement',
        data.recordType,
        data.recordId,
        data.content
    )
    cb(result or { success = false, error = 'No server response' })
end)

RegisterNUICallback('getRecordSupplements', function(data, cb)
    if closedResponse(cb) then return end
    data = data or {}
    local result = ps.callback(
        resourceName .. ':server:getRecordSupplements',
        data.recordType,
        data.recordId
    )
    cb(result or { success = false, supplements = {} })
end)

RegisterNUICallback('getRecordRevisions', function(data, cb)
    if closedResponse(cb) then return end
    data = data or {}
    local result = ps.callback(
        resourceName .. ':server:getRecordRevisions',
        data.recordType,
        data.recordId
    )
    cb(result or { success = false, revisions = {} })
end)

RegisterNUICallback('getRecordGovernanceCapabilities', function(data, cb)
    if closedResponse(cb) then return end
    data = data or {}
    local result = ps.callback(
        resourceName .. ':server:getRecordGovernanceCapabilities',
        data.recordType,
        data.recordId
    )
    cb(result or {
        success = false,
        error = 'No server response',
        canSupplement = false,
        canManageLifecycle = false,
        allowedTransitions = {},
    })
end)

RegisterNUICallback('setRecordLifecycle', function(data, cb)
    if closedResponse(cb) then return end
    data = data or {}
    local result = ps.callback(
        resourceName .. ':server:setRecordLifecycle',
        data.recordType,
        data.recordId,
        data.status,
        data.reason
    )
    cb(result or { success = false, error = 'No server response' })
end)

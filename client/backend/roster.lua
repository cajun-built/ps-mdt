RegisterNUICallback('getRoster', function(data, cb)
    if not MDTOpen then cb({}) return end
    local rosterList = ps.callback('ps-mdt:server:getRosterList')
    cb(rosterList)
end)

RegisterNUICallback('getOfficerTags', function(data, cb)
    if not MDTOpen then cb({}) return end
    local tags = ps.callback('ps-mdt:server:getOfficerTags')
    cb(tags or {})
end)

RegisterNUICallback('updateOfficerCertifications', function(data, cb)
    if not MDTOpen then cb({ success = false }) return end
    local result = ps.callback('ps-mdt:server:updateOfficerCertifications', data)
    cb(result or { success = false })
end)

RegisterNUICallback('getJobGrades', function(data, cb)
    if not MDTOpen then cb({}) return end
    local result = ps.callback('ps-mdt:server:getJobGrades', data)
    cb(result or {})
end)

RegisterNUICallback('promoteOfficer', function(data, cb)
    if not MDTOpen then cb({ success = false }) return end
    local result = ps.callback('ps-mdt:server:promoteOfficer', data)
    cb(result or { success = false })
end)

RegisterNUICallback('fireOfficer', function(data, cb)
    if not MDTOpen then cb({ success = false }) return end
    local result = ps.callback('ps-mdt:server:fireOfficer', data)
    cb(result or { success = false })
end)

RegisterNUICallback('updateOfficerCallsign', function(data, cb)
    if not MDTOpen then cb({ success = false }) return end
    local result = ps.callback('ps-mdt:server:updateOfficerCallsign', data)
    cb(result or { success = false })
end)

RegisterNUICallback('hireOfficer', function(data, cb)
    if not MDTOpen then cb({ success = false }) return end
    cb(ps.callback('ps-mdt:server:hireOfficer', data) or { success = false })
end)

RegisterNUICallback('updateOfficerBadge', function(data, cb)
    if not MDTOpen then cb({ success = false }) return end
    cb(ps.callback('ps-mdt:server:updateOfficerBadge', data) or { success = false })
end)

RegisterNUICallback('updateOfficerAssignment', function(data, cb)
    if not MDTOpen then cb({ success = false }) return end
    cb(ps.callback('ps-mdt:server:updateOfficerAssignment', data) or { success = false })
end)

RegisterNUICallback('updateOfficerStatus', function(data, cb)
    if not MDTOpen then cb({ success = false }) return end
    cb(ps.callback('ps-mdt:server:updateOfficerStatus', data) or { success = false })
end)

RegisterNUICallback('transferOfficer', function(data, cb)
    if not MDTOpen then cb({ success = false }) return end
    cb(ps.callback('ps-mdt:server:transferOfficer', data) or { success = false })
end)

RegisterNUICallback('updateOfficerCompartment', function(data, cb)
    if not MDTOpen then cb({ success = false }) return end
    cb(ps.callback('ps-mdt:server:updateOfficerCompartment', data) or { success = false })
end)

RegisterNUICallback('grantOfficerPermission', function(data, cb)
    if not MDTOpen then cb({ success = false }) return end
    cb(ps.callback('ps-mdt:server:grantOfficerPermission', data) or { success = false })
end)

RegisterNUICallback('restrictOfficerPermission', function(data, cb)
    if not MDTOpen then cb({ success = false }) return end
    cb(ps.callback('ps-mdt:server:restrictOfficerPermission', data) or { success = false })
end)

RegisterNUICallback('getTaskForces', function(_, cb)
    if not MDTOpen then cb({ success = false, taskForces = {} }) return end
    cb(ps.callback('ps-mdt:server:getTaskForces') or { success = false, taskForces = {} })
end)

RegisterNUICallback('createTaskForce', function(data, cb)
    if not MDTOpen then cb({ success = false }) return end
    cb(ps.callback('ps-mdt:server:createTaskForce', data) or { success = false })
end)

RegisterNUICallback('setTaskForceMember', function(data, cb)
    if not MDTOpen then cb({ success = false }) return end
    cb(ps.callback('ps-mdt:server:setTaskForceMember', data) or { success = false })
end)

RegisterNUICallback('setTaskForceStatus', function(data, cb)
    if not MDTOpen then cb({ success = false }) return end
    cb(ps.callback('ps-mdt:server:setTaskForceStatus', data) or { success = false })
end)

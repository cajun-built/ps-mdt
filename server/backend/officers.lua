local resourceName = tostring(GetCurrentResourceName())

-- The dashboard may read only the authenticated officer's callsign. Persistent
-- identity changes are performed by authorized command staff through the roster
-- workflow and cgn_leo_core:ChangeCallsign.
ps.registerCallback(resourceName .. ':server:getCallsign', function(source)
    if not CheckAuth(source) then return { callsign = '' } end

    if IsLeoMdtSource(source) and GetResourceState('cgn_leo_core') == 'started' then
        local ok, context = pcall(function()
            return exports.cgn_leo_core:GetContext(source)
        end)
        if ok and context then
            return { callsign = tostring(context.callsign or '') }
        end
    end

    local cid = ps.getIdentifier(source)
    if not cid then return { callsign = '' } end
    return { callsign = tostring(ps.getMetadata(source, 'callsign') or '') }
end)

AddEventHandler('cgn_leo_core:server:integrationEvent', function(consumer, event)
    if consumer ~= GetCurrentResourceName() or type(event) ~= 'table' or not event.eventId then return end
    local success, errorMessage = pcall(function()
        CGNMdtAudience.sendLeo('ps-mdt:client:leoStateChanged', {
            type = event.type,
            citizenid = event.aggregateType == 'personnel' and event.aggregateId or nil,
            agency = event.agency,
            version = event.version,
        })
    end)
    local failureMessage = nil
    if not success then failureMessage = tostring(errorMessage) end
    exports.cgn_leo_core:AcknowledgeIntegrationEvent(
        event.eventId, GetCurrentResourceName(), success, failureMessage
    )
end)

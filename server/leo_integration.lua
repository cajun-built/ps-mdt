AddEventHandler('cgn_leo_core:server:integrationEvent', function(consumer, event)
    if consumer ~= GetCurrentResourceName() or type(event) ~= 'table' or not event.eventId then return end
    local success, errorMessage = pcall(function()
        TriggerClientEvent('ps-mdt:client:leoStateChanged', -1, {
            type = event.type,
            citizenid = event.aggregateType == 'personnel' and event.aggregateId or nil,
            agency = event.agency,
            version = event.version,
        })
    end)
    exports.cgn_leo_core:AcknowledgeIntegrationEvent(
        event.eventId, GetCurrentResourceName(), success, success and nil or tostring(errorMessage)
    )
end)

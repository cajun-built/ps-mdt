local function entityCoords(entity)
    local coords = GetEntityCoords(entity)
    return { x = coords.x, y = coords.y, z = coords.z }
end

function BuildMdtAccessRequest(source, requestedContext)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then
        return { context = requestedContext }
    end

    if requestedContext == 'station' then
        return {
            context = 'station',
            coords = entityCoords(ped),
        }
    end

    if requestedContext == 'vehicle' then
        local vehicle = GetVehiclePedIsIn(ped, false)
        if not vehicle or vehicle == 0 then
            return { context = 'vehicle', inVehicle = false }
        end

        local state = Entity(vehicle).state
        return {
            context = 'vehicle',
            inVehicle = true,
            vehicleClass = exports.qbx_core:GetVehicleClass(GetEntityModel(vehicle)),
            fleetAssetId = state.cgnFleetAssetId,
            fleetAgency = state.cgnFleetAgency,
        }
    end

    return { context = requestedContext }
end

MdtAccessPolicy = MdtAccessPolicy or {}

local Policy = MdtAccessPolicy

local function squaredDistance(left, right)
    local dx = (tonumber(left and left.x) or 0.0) - (tonumber(right and right.x) or 0.0)
    local dy = (tonumber(left and left.y) or 0.0) - (tonumber(right and right.y) or 0.0)
    local dz = (tonumber(left and left.z) or 0.0) - (tonumber(right and right.z) or 0.0)
    return dx * dx + dy * dy + dz * dz
end

function Policy.isInsideStation(config, coords)
    if type(coords) ~= 'table' then return false end

    for _, station in ipairs((config and config.stations) or {}) do
        local radius = tonumber(station.radius) or 0.0
        if radius > 0.0 and squaredDistance(station, coords) <= radius * radius then
            return true
        end
    end

    return false
end

function Policy.canOpen(config, identity, request)
    identity = type(identity) == 'table' and identity or {}
    request = type(request) == 'table' and request or {}

    if identity.isLeo ~= true then return false, 'leo_required' end
    if identity.personnelVerified ~= true then return false, 'personnel_required' end
    if identity.onDuty ~= true then return false, 'duty_required' end

    if request.context == 'station' then
        if not Policy.isInsideStation(config, request.coords) then
            return false, 'station_required'
        end
        return true
    end

    if request.context == 'vehicle' then
        if request.inVehicle ~= true or not tonumber(request.fleetAssetId) or
            type(request.fleetAgency) ~= 'string' or request.fleetAgency == '' then
            return false, 'fleet_vehicle_required'
        end
        if tonumber(request.vehicleClass) ~= tonumber(config and config.vehicleClass) then
            return false, 'patrol_vehicle_required'
        end
        return true
    end

    return false, 'access_point_required'
end

return Policy

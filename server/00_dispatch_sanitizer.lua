CGNMdtDispatch = CGNMdtDispatch or {}

local function copyCoordinates(coords)
    if type(coords) == 'vector3' or type(coords) == 'vector4' then
        return { x = coords.x, y = coords.y, z = coords.z }
    end
    if type(coords) == 'table' then
        return {
            x = coords.x or coords[1],
            y = coords.y or coords[2],
            z = coords.z or coords[3],
        }
    end
end

function CGNMdtDispatch.sanitize(call)
    if type(call) ~= 'table' then return nil end
    local sanitized = {
        id = call.id,
        message = call.message or call.dispatchMessage or '',
        code = call.code or call.dispatchCode or '',
        street = call.street or '',
        priority = call.priority or 0,
        time = call.time or 0,
        gender = call.gender,
        plate = call.plate,
        color = call.color,
        model = call.model,
        weapon = call.weapon,
        heading = call.heading,
        speed = call.speed,
        callSign = call.callSign,
        description = call.description,
        camId = call.camId,
        firstColor = call.firstColor,
        coords = copyCoordinates(call.displayCoords or call.coords),
    }

    sanitized.units = {}
    for _, unit in pairs(type(call.units) == 'table' and call.units or {}) do
        if type(unit) == 'table' then
            sanitized.units[#sanitized.units + 1] = {
                citizenid = unit.citizenid,
                charinfo = unit.charinfo,
                job = unit.job,
                metadata = unit.metadata and { callsign = unit.metadata.callsign } or nil,
            }
        end
    end

    if type(call.jobs) == 'table' then
        sanitized.jobs = {}
        for _, job in ipairs(call.jobs) do sanitized.jobs[#sanitized.jobs + 1] = job end
    end
    return sanitized
end

return CGNMdtDispatch

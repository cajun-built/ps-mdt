local root = arg and arg[1] or '.'
local AccessPolicy = dofile(root .. '/shared/access_policy.lua')

local function expect(name, actual, expected)
    if actual ~= expected then
        error(('%s: expected %s, received %s'):format(name, tostring(expected), tostring(actual)))
    end
end

local config = {
    vehicleClass = 18,
    stations = {
        { x = 100.0, y = 200.0, z = 30.0, radius = 20.0 },
    },
}

local verifiedOfficer = {
    isLeo = true,
    onDuty = true,
    personnelVerified = true,
}

local allowed, reason = AccessPolicy.canOpen(config, verifiedOfficer, {
    context = 'station',
    coords = { x = 105.0, y = 200.0, z = 30.0 },
})
expect('verified officer can use a station computer', allowed, true)
expect('station access has no denial reason', reason, nil)

local civilianAllowed, civilianReason = AccessPolicy.canOpen(config, {
    isLeo = false,
    onDuty = true,
    personnelVerified = true,
}, {
    context = 'station',
    coords = { x = 105.0, y = 200.0, z = 30.0 },
})
expect('civilian cannot use the police MDT', civilianAllowed, false)
expect('civilian receives LEO denial', civilianReason, 'leo_required')

local offDutyAllowed, offDutyReason = AccessPolicy.canOpen(config, {
    isLeo = true,
    onDuty = false,
    personnelVerified = true,
}, {
    context = 'station',
    coords = { x = 105.0, y = 200.0, z = 30.0 },
})
expect('off-duty officer cannot use the police MDT', offDutyAllowed, false)
expect('off-duty officer receives duty denial', offDutyReason, 'duty_required')

local unverifiedAllowed, unverifiedReason = AccessPolicy.canOpen(config, {
    isLeo = true,
    onDuty = true,
    personnelVerified = false,
}, {
    context = 'station',
    coords = { x = 105.0, y = 200.0, z = 30.0 },
})
expect('officer without personnel record cannot use the police MDT', unverifiedAllowed, false)
expect('unverified officer receives personnel denial', unverifiedReason, 'personnel_required')

local remoteAllowed, remoteReason = AccessPolicy.canOpen(config, verifiedOfficer, {
    context = 'station',
    coords = { x = 150.0, y = 200.0, z = 30.0 },
})
expect('officer outside a station cannot claim terminal access', remoteAllowed, false)
expect('remote officer receives station denial', remoteReason, 'station_required')

local movingFleetAllowed, movingFleetReason = AccessPolicy.canOpen(config, verifiedOfficer, {
    context = 'vehicle',
    inVehicle = true,
    vehicleClass = 18,
    fleetAssetId = 44,
    fleetAgency = 'ebrso',
    speed = 31.0,
})
expect('moving commissioned patrol vehicle permits MDT access', movingFleetAllowed, true)
expect('moving patrol access has no denial reason', movingFleetReason, nil)

local privateVehicleAllowed, privateVehicleReason = AccessPolicy.canOpen(config, verifiedOfficer, {
    context = 'vehicle',
    inVehicle = true,
    vehicleClass = 18,
    speed = 0.0,
})
expect('ordinary emergency-class vehicle cannot provide MDT access', privateVehicleAllowed, false)
expect('ordinary vehicle receives fleet denial', privateVehicleReason, 'fleet_vehicle_required')

local helicopterAllowed, helicopterReason = AccessPolicy.canOpen(config, verifiedOfficer, {
    context = 'vehicle',
    inVehicle = true,
    vehicleClass = 15,
    fleetAssetId = 45,
    fleetAgency = 'lsp',
    speed = 0.0,
})
expect('commissioned aircraft is not a patrol-car MDT', helicopterAllowed, false)
expect('aircraft receives patrol-class denial', helicopterReason, 'patrol_vehicle_required')

print('[ps-mdt] access policy self tests passed')

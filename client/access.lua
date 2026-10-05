local targetName = 'ps_mdt_station_computer'
local activeAccessContext = nil
local stationComputerModels = Config.MdtAccess.computerModels

local function getStationComputerModels()
    local ok, models = pcall(function()
        return exports.cgn_leo_core:GetStationComputerModels()
    end)
    if ok and type(models) == 'table' and #models > 0 then
        return models
    end
    return stationComputerModels
end

local function currentCoords()
    local coords = GetEntityCoords(PlayerPedId())
    return { x = coords.x, y = coords.y, z = coords.z }
end

local function isFleetPatrolVehicle(vehicle)
    if not vehicle or vehicle == 0 then return false end
    if GetVehicleClass(vehicle) ~= tonumber(Config.MdtAccess.vehicleClass) then return false end

    local state = Entity(vehicle).state
    return tonumber(state.cgnFleetAssetId) ~= nil and
        type(state.cgnFleetAgency) == 'string' and state.cgnFleetAgency ~= ''
end

local function canTargetStationComputer()
    return ps.getJobType() == Config.PoliceJobType and
        ps.getJobDuty() == true and
        MdtAccessPolicy.isInsideStation(Config.MdtAccess, currentCoords())
end

function SetMdtAccessContext(context)
    activeAccessContext = context
end

function GetMdtAccessContext()
    return activeAccessContext
end

function ClearMdtAccessContext()
    activeAccessContext = nil
end

CreateThread(function()
    stationComputerModels = getStationComputerModels()
    exports.ox_target:addModel(stationComputerModels, {
        {
            name = targetName,
            icon = 'fa-solid fa-computer',
            label = 'Open MDT',
            distance = Config.MdtAccess.targetDistance,
            canInteract = canTargetStationComputer,
            onSelect = function()
                OpenMDT('station')
            end,
        },
    })

    while true do
        if not MDTOpen or not activeAccessContext then
            Wait(500)
        else
            local valid = false
            if activeAccessContext == 'station' then
                valid = MdtAccessPolicy.isInsideStation(Config.MdtAccess, currentCoords())
            elseif activeAccessContext == 'vehicle' then
                valid = isFleetPatrolVehicle(GetVehiclePedIsIn(PlayerPedId(), false))
            end

            if not valid then
                CloseMDT()
                ps.notify('MDT closed - Access point lost', 'error')
            end
            Wait(500)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    exports.ox_target:removeModel(stationComputerModels, targetName)
end)

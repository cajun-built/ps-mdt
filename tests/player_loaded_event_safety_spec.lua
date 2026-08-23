local camerasPath = assert(arg[1], 'cameras path is required')
local file = assert(io.open(camerasPath, 'rb'))
local source = file:read('*a')
file:close()

local safeRegistration = source:match(
    "RegisterNetEvent%s*%(%s*['\"]QBCore:Server:OnPlayerLoaded['\"]%s*,%s*onPlayerReady%s*%)"
)

assert(safeRegistration, 'Qbox player loaded camera handler is not network safe')

print('player_loaded_event_safety_spec: ok')

local dashboardPath = assert(arg[1], 'dashboard client path is required')
local file = assert(io.open(dashboardPath, 'rb'))
local source = file:read('*a')
file:close()

local callbackPattern = "ps%.callback%s*%(%s*resourceName%s*%.%.%s*['\"]:server:checkAuth['\"]%s*,%s*GetMdtAccessContext%s*%(%s*%)%s*%)"
local callsWithContext = 0

for _ in source:gmatch(callbackPattern) do
    callsWithContext = callsWithContext + 1
end

assert(callsWithContext >= 2,
    ('expected both in-tablet authorization checks to preserve the active access context; found %d'):format(callsWithContext))

print('client_access_context_spec: ok')

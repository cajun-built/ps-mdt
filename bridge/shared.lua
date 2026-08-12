MDTFramework = MDTFramework or {}

local aliases = {
    qbx = 'qbx',
    qbox = 'qbx',
    ['qbx_core'] = 'qbx',
    qb = 'qb',
    qbcore = 'qb',
    ['qb-core'] = 'qb',
    esx = 'esx',
    ['es_extended'] = 'esx',
}

local function detectFramework()
    local configured = Config and Config.Framework or 'auto'
    configured = aliases[string.lower(tostring(configured))] or configured
    if configured ~= 'auto' then return configured end

    if GetResourceState('qbx_core') == 'started' then return 'qbx' end
    if GetResourceState('es_extended') == 'started' then return 'esx' end
    if GetResourceState('qb-core') == 'started' then return 'qb' end
    return 'unknown'
end

MDTFramework.name = detectFramework()

function MDTFramework.is(name)
    return MDTFramework.name == aliases[name] or MDTFramework.name == name
end

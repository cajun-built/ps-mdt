local resourceName = tostring(GetCurrentResourceName())
local focusRequest = 0

function FocusMDT()
    SetNuiFocusKeepInput(false)
    SetNuiFocus(true, true)
    SetCursorLocation(0.5, 0.5)
end

function ReleaseMDTFocus()
    focusRequest = focusRequest + 1
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
end

RegisterNUICallback('focusUI', function(_, cb)
    if MDTOpen then
        focusRequest = focusRequest + 1
        local request = focusRequest
        FocusMDT()

        -- FiveM resources such as targeting and inventory UIs can briefly
        -- claim NUI focus while the MDT is mounting. Reassert focus over the
        -- next few frames so the visible terminal always owns its cursor.
        CreateThread(function()
            for _, delay in ipairs({ 50, 150, 350, 750 }) do
                Wait(delay)
                if not MDTOpen or request ~= focusRequest then return end
                FocusMDT()
            end
        end)
    end
    cb({})
end)

local function resetNuiState()
    MDTOpen = false
    SendNUIMessage({
        action = 'setVisible',
        data = { visible = false },
    })
    ReleaseMDTFocus()
end

AddEventHandler('onClientResourceStart', function(resource)
    if resource == resourceName then
        resetNuiState()
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == resourceName then
        resetNuiState()
    end
end)

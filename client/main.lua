local Props = {}
local Spawned = {}
local STREAM_HYSTERESIS = 20.0

local function streamDistanceFor(prop)
    local minimum = tonumber(Config.MinStreamDistance) or 10.0
    local maximum = math.max(minimum, tonumber(Config.MaxStreamDistance) or 2000.0)
    return math.max(minimum, math.min(
        maximum,
        tonumber(prop and prop.stream_distance) or Config.StreamDistance
    ))
end

local function notify(msg, typ)
    msg = tostring(msg or '')
    typ = typ or 'info'
    print(('[mz_props][notify:%s] %s'):format(tostring(typ), msg))

    if Config.UseMzNotify == true and GetResourceState('mz_notify') == 'started' then
        local notifyType = typ == 'inform' and 'info' or (typ == 'warn' and 'warning' or typ)
        local ok, result = pcall(function()
            return exports['mz_notify']:Notify({
                type = notifyType,
                title = Config.NotifyPrefix,
                message = msg,
                duration = 4000
            })
        end)
        if ok and result ~= false then return true end
        print(('[mz_props] mz_notify falhou: %s'):format(tostring(result)))
    end

    if Config.UseMzMenuNotify == true and GetResourceState('mz_menu') == 'started' then
        local menuType = typ == 'info' and 'inform' or (typ == 'warn' and 'warning' or typ)
        local ok, result = pcall(function()
            return exports['mz_menu']:Notify(msg, menuType, 4000, { title = Config.NotifyPrefix })
        end)
        if ok and result ~= false then return true end
        print(('[mz_props] mz_menu Notify falhou: %s'):format(tostring(result)))
    end

    if Config.UseChatNotify ~= false and GetResourceState('chat') == 'started' then
        TriggerEvent('chat:addMessage', {
            color = typ == 'error' and { 255, 80, 80 } or { 80, 200, 255 },
            args = { Config.NotifyPrefix, msg }
        })
    end

    if Config.UseNativeNotify ~= false then
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(('%s: %s'):format(Config.NotifyPrefix, msg))
        EndTextCommandThefeedPostTicker(false, false)
    end
    return false
end

RegisterNetEvent('mz_props:client:notify', function(msg, typ)
    notify(msg, typ)
end)

local function toVec(prop)
    return vector3(tonumber(prop.x) or 0.0, tonumber(prop.y) or 0.0, tonumber(prop.z) or 0.0)
end

local function deleteLocal(id)
    local ent = Spawned[id]
    if ent and DoesEntityExist(ent) then
        DeleteEntity(ent)
    end
    Spawned[id] = nil
end

local function loadModel(model)
    model = tonumber(model)
    if not IsModelInCdimage(model) then return false end
    RequestModel(model)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(model) do
        Wait(10)
        if GetGameTimer() > timeout then return false end
    end
    return true
end

local function spawnProp(prop)
    if not prop or not prop.id or not prop.model_hash then return end
    deleteLocal(prop.id)

    if prop.visible == false then return end

    local model = tonumber(prop.model_hash)
    if not loadModel(model) then
        print(('[mz_props] Modelo invalido/nao carregou: id=%s hash=%s'):format(prop.id, tostring(prop.model_hash)))
        return
    end

    local obj = CreateObjectNoOffset(model, tonumber(prop.x), tonumber(prop.y), tonumber(prop.z), false, false, false)
    if not DoesEntityExist(obj) then return end

    -- A rotacao completa e canonica. Aplicar heading depois sobrescreveria o eixo Z.
    SetEntityRotation(obj, tonumber(prop.rx) or 0.0, tonumber(prop.ry) or 0.0, tonumber(prop.rz or prop.heading) or 0.0, 2, true)
    FreezeEntityPosition(obj, prop.frozen ~= false)
    SetEntityCollision(obj, prop.collision_enabled ~= false, true)
    SetEntityAsMissionEntity(obj, true, true)
    -- O streaming controla a existência da entidade; o LOD controla até onde
    -- o GTA realmente desenha o modelo. Sem isto, muitos props somem a ~120 m.
    SetEntityLodDist(obj, math.floor(streamDistanceFor(prop) + 0.5))

    Spawned[prop.id] = obj
    SetModelAsNoLongerNeeded(model)
end

local function refreshAll()
    for id in pairs(Spawned) do deleteLocal(id) end
end

RegisterNetEvent('mz_props:client:setProps', function(data)
    Props = data or {}
    Wait(100)
    refreshAll()
end)

RegisterNetEvent('mz_props:client:upsertProp', function(prop)
    if not prop or not prop.id then return end
    Props[prop.id] = prop
    local distance = #(GetEntityCoords(PlayerPedId()) - toVec(prop))
    local streamDistance = streamDistanceFor(prop)
    if prop.visible ~= false and prop.active ~= false and distance <= streamDistance then
        spawnProp(prop)
    else
        deleteLocal(prop.id)
    end
end)

RegisterNetEvent('mz_props:client:removeProp', function(id)
    id = tonumber(id)
    Props[id] = nil
    deleteLocal(id)
end)

AddEventHandler('onClientResourceStart', function(res)
    if res == GetCurrentResourceName() then
        Wait(1000)
        TriggerServerEvent('mz_props:server:requestProps')
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not Config.CleanupOnStop then return end
    for id in pairs(Spawned) do deleteLocal(id) end
end)

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local playerCoords = GetEntityCoords(ped)
        local nearAny = false

        for id, prop in pairs(Props) do
            local distance = #(playerCoords - toVec(prop))
            local streamDistance = streamDistanceFor(prop)
            local shouldExist = prop.active ~= false and prop.visible ~= false and distance <= streamDistance

            if shouldExist then
                nearAny = true
                if not Spawned[id] or not DoesEntityExist(Spawned[id]) then spawnProp(prop) end
            elseif Spawned[id] and distance > (streamDistance + STREAM_HYSTERESIS) then
                deleteLocal(id)
            elseif prop.active == false or prop.visible == false then
                deleteLocal(id)
            end
        end

        Wait(nearAny and 500 or 1500)
    end
end)

local function nearestProp(maxDistance)
    local ped = PlayerPedId()
    local pcoords = GetEntityCoords(ped)
    local nearest, nearestDist = nil, maxDistance or Config.StreamDistance
    for _, prop in pairs(Props) do
        local coords = toVec(prop)
        local dist = #(pcoords - coords)
        if dist <= nearestDist then
            nearest = prop
            nearestDist = dist
        end
    end
    return nearest, nearestDist
end

RegisterNetEvent('mz_props:client:gotoProp', function(prop)
    if not prop then return end
    local ped = PlayerPedId()
    SetEntityCoords(ped, tonumber(prop.x), tonumber(prop.y), tonumber(prop.z) + 1.0, false, false, false, false)
end)

RegisterNetEvent('mz_props:client:printNearest', function()
    local prop, dist = nearestProp(Config.StreamDistance)
    if not prop then
        notify('Nenhum prop persistente proximo.', 'error')
        return
    end

    TriggerEvent('chat:addMessage', {
        color = { 80, 200, 255 },
        multiline = true,
        args = { Config.NotifyPrefix, ('Mais proximo: #%s | %s | %.2fm | hash=%s | %.2f %.2f %.2f'):format(
            prop.id, prop.name or 'sem nome', dist or 0.0, prop.model_hash, prop.x, prop.y, prop.z
        ) }
    })
end)

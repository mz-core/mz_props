local Props = {}
local Loaded = false

local function bool(v)
    return v == true or v == 1 or v == '1'
end

local function clampStreamDistance(value)
    local minimum = tonumber(Config.MinStreamDistance) or 10.0
    local maximum = math.max(minimum, tonumber(Config.MaxStreamDistance) or 2000.0)
    return math.max(minimum, math.min(maximum, tonumber(value) or Config.StreamDistance))
end

local function getAllowedAce(src)
    if src == 0 then return true, 'console' end
    for _, ace in ipairs(Config.AdminAces or { Config.AdminAce }) do
        if ace and ace ~= '' and IsPlayerAceAllowed(src, ace) then
            return true, ace
        end
    end
    return false, nil
end

local function canAdmin(src)
    local allowed = getAllowedAce(src)
    return allowed == true
end

local function hasStaffPermission(src, permission)
    if src == 0 then return true end
    if GetResourceState('mz_core') == 'started' then
        local ok, allowed = pcall(function()
            return exports['mz_core']:HasGlobalPermission(src, permission)
        end)
        if ok and allowed == true then return true end
    end
    return type(Config.AdminAce) == 'string'
        and Config.AdminAce ~= ''
        and IsPlayerAceAllowed(src, Config.AdminAce) == true
end

local function trim(value, maxLength)
    local text = tostring(value or ''):gsub('%c', ''):gsub('^%s+', ''):gsub('%s+$', '')
    return text:sub(1, maxLength or 100)
end

local function validCode(value)
    local code = trim(value, 64):lower()
    if #code < 3 or not code:match('^[a-z0-9][a-z0-9_%-]*$') then return nil end
    return code
end

local function adminAceText()
    return table.concat(Config.AdminAces or { Config.AdminAce }, ', ')
end

local function normalize(row)
    row.id = tonumber(row.id)
    row.model_hash = tonumber(row.model_hash)
    row.x = tonumber(row.x)
    row.y = tonumber(row.y)
    row.z = tonumber(row.z)
    row.rx = tonumber(row.rx) or 0
    row.ry = tonumber(row.ry) or 0
    row.rz = tonumber(row.rz) or 0
    row.heading = tonumber(row.heading) or 0
    row.frozen = bool(row.frozen)
    row.collision_enabled = bool(row.collision_enabled)
    row.visible = bool(row.visible)
    row.stream_distance = clampStreamDistance(row.stream_distance)
    row.active = row.active == nil or bool(row.active)
    return row
end

local function notify(src, msg, typ)
    TriggerClientEvent('mz_props:client:notify', src, msg, typ or 'info')
end

local function broadcastProp(prop)
    TriggerClientEvent('mz_props:client:upsertProp', -1, prop)
end

local function audit(src, action, prop, metadata)
    if GetResourceState('mz_core') ~= 'started' then return end
    pcall(function()
        exports['mz_core']:CreateDetailedLog('world', action, {
            actor = { source = src, name = src == 0 and 'console' or GetPlayerName(src) },
            target = { type = 'prop', id = prop and (prop.code or prop.id) or 'unknown' },
            metadata = metadata or {},
            state = prop and { active = prop.active, visible = prop.visible, frozen = prop.frozen } or nil
        })
    end)
end

local function removeProp(id)
    TriggerClientEvent('mz_props:client:removeProp', -1, id)
end

local function loadProps()
    Props = {}
    MZPropsDB.ensure()
    local rows = MZPropsDB.fetchAll()
    for _, row in ipairs(rows) do
        local prop = normalize(row)
        Props[prop.id] = prop
    end
    Loaded = true
    TriggerClientEvent('mz_props:client:setProps', -1, Props)
    print(('[mz_props] %s props carregados.'):format(#rows))
end

CreateThread(function()
    Wait(500)
    loadProps()
end)

RegisterNetEvent('mz_props:server:requestProps', function()
    local src = source
    if not Loaded then loadProps() end
    TriggerClientEvent('mz_props:client:setProps', src, Props)
end)

RegisterNetEvent('mz_props:server:createFromEditor', function(data)
    local src = source
    if not hasStaffPermission(src, Config.AdminCreatePermission) then
        notify(src, ('Sem permissao %s.'):format(Config.AdminCreatePermission), 'error')
        return
    end

    if type(data) ~= 'table' or not data.model_hash or not data.coords then
        notify(src, 'Dados invalidos para criar prop.', 'error')
        return
    end

    local prop = {
        name = tostring(data.name or ('Prop ' .. tostring(data.model_hash))):sub(1, 100),
        code = validCode(data.code) or ('legacy_prop_%s_%s'):format(src, GetGameTimer()),
        model_hash = tonumber(data.model_hash),
        model_name = trim(data.model_name, 100),
        x = tonumber(data.coords.x),
        y = tonumber(data.coords.y),
        z = tonumber(data.coords.z),
        rx = tonumber(data.rotation and data.rotation.x) or 0,
        ry = tonumber(data.rotation and data.rotation.y) or 0,
        rz = tonumber(data.rotation and data.rotation.z) or 0,
        heading = tonumber(data.heading) or 0,
        frozen = data.frozen ~= false,
        collision_enabled = data.collision ~= false,
        visible = data.visible ~= false,
        stream_distance = clampStreamDistance(data.stream_distance),
        active = data.active ~= false,
        created_by = GetPlayerName(src) or tostring(src),
        updated_by = GetPlayerName(src) or tostring(src)
    }

    if not prop.model_hash or not prop.x or not prop.y or not prop.z then
        notify(src, 'Dados incompletos para criar prop.', 'error')
        return
    end

    local id = MZPropsDB.insert(prop)
    prop.id = tonumber(id)
    Props[prop.id] = normalize(prop)
    broadcastProp(Props[prop.id])
    notify(src, ('Prop persistente criado: ID %s. Use /%s list para listar.'):format(prop.id, Config.Command), 'success')
end)

local function chat(src, msg)
    if src == 0 then
        print(msg:gsub('~%a~', ''))
    else
        TriggerClientEvent('chat:addMessage', src, { color = { 80, 200, 255 }, args = { Config.NotifyPrefix, msg } })
    end
end

local function usage(src)
    chat(src, ('Uso: /%s list [pag] | near | goto [id] | delete [id] | rename [id] [nome] | freeze [id] [0/1] | visible [id] [0/1] | stream [id] [dist] | active [id] [0/1] | reload'):format(Config.Command))
end

RegisterCommand(Config.Command, function(src, args)
    if not canAdmin(src) then
        notify(src, ('Sem permissao ACE. Testados: %s'):format(adminAceText()), 'error')
        return
    end

    local sub = tostring(args[1] or ''):lower()
    if sub == '' or sub == 'help' then return usage(src) end

    if sub == 'reload' then
        loadProps()
        chat(src, 'Props recarregados do banco.')
        return
    end

    if sub == 'list' then
        local ids = {}
        for id in pairs(Props) do ids[#ids + 1] = id end
        table.sort(ids)
        local page = math.max(1, tonumber(args[2]) or 1)
        local perPage = Config.ListPageSize
        local startIdx = ((page - 1) * perPage) + 1
        local endIdx = math.min(startIdx + perPage - 1, #ids)
        chat(src, ('Lista de props: pagina %s | total %s'):format(page, #ids))
        for i = startIdx, endIdx do
            local p = Props[ids[i]]
            chat(src, ('#%s | %s | hash=%s | %.2f %.2f %.2f | frozen=%s | visible=%s'):format(
                p.id, p.name or 'sem nome', p.model_hash, p.x, p.y, p.z, tostring(p.frozen), tostring(p.visible)
            ))
        end
        return
    end

    if sub == 'near' then
        TriggerClientEvent('mz_props:client:printNearest', src)
        return
    end

    local id = tonumber(args[2])
    if not id then return usage(src) end
    local prop = Props[id]
    if not prop then
        chat(src, 'Prop nao encontrado.')
        return
    end

    if sub == 'goto' then
        TriggerClientEvent('mz_props:client:gotoProp', src, prop)
    elseif sub == 'delete' then
        Props[id] = nil
        MZPropsDB.delete(id)
        removeProp(id)
        chat(src, ('Prop #%s removido.'):format(id))
    elseif sub == 'rename' then
        local name = table.concat(args, ' ', 3)
        if name == '' then return usage(src) end
        prop.name = name:sub(1, 100)
        MZPropsDB.rename(id, prop.name)
        broadcastProp(prop)
        chat(src, ('Prop #%s renomeado para %s.'):format(id, prop.name))
    elseif sub == 'freeze' then
        local state = tostring(args[3] or '') == '1' or tostring(args[3] or ''):lower() == 'true'
        prop.frozen = state
        MZPropsDB.setFrozen(id, state)
        broadcastProp(prop)
        chat(src, ('Prop #%s frozen=%s'):format(id, tostring(state)))
    elseif sub == 'visible' then
        local state = tostring(args[3] or '') == '1' or tostring(args[3] or ''):lower() == 'true'
        prop.visible = state
        MZPropsDB.setVisible(id, state)
        broadcastProp(prop)
        chat(src, ('Prop #%s visible=%s'):format(id, tostring(state)))
    elseif sub == 'stream' then
        local distance = tonumber(args[3])
        if not distance then return usage(src) end
        distance = clampStreamDistance(distance)
        prop.stream_distance = distance
        MZPropsDB.setStreamDistance(id, distance)
        broadcastProp(prop)
        chat(src, ('Prop #%s stream_distance=%.1f'):format(id, distance))
    elseif sub == 'active' then
        local state = tostring(args[3] or '') == '1' or tostring(args[3] or ''):lower() == 'true'
        prop.active = state
        MZPropsDB.setActive(id, state, src == 0 and 'console' or (GetPlayerName(src) or tostring(src)))
        broadcastProp(prop)
        chat(src, ('Prop #%s active=%s'):format(id, tostring(state)))
    else
        usage(src)
    end
end, false)

exports('GetProps', function()
    return Props
end)

exports('IsAdmin', function(src)
    return canAdmin(src)
end)

exports('IsReady', function()
    return Loaded
end)

exports('ListPropsForAdmin', function(src)
    if not hasStaffPermission(src, Config.AdminViewPermission) then
        return false, 'permission_denied'
    end
    local out = {}
    for _, prop in pairs(Props) do out[#out + 1] = prop end
    table.sort(out, function(a, b) return a.id < b.id end)
    return true, out
end)

exports('CreatePropForAdmin', function(src, payload)
    if not hasStaffPermission(src, Config.AdminCreatePermission) then
        return false, 'permission_denied'
    end
    if type(payload) ~= 'table' then return false, 'invalid_payload' end

    local code = validCode(payload.code)
    local name = trim(payload.name, 100)
    local coords = type(payload.coords) == 'table' and payload.coords or {}
    local rotation = type(payload.rotation) == 'table' and payload.rotation or {}
    local modelHash = tonumber(payload.model_hash)
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not code or #name < 3 or not modelHash or modelHash == 0 or not x or not y or not z then
        return false, 'invalid_definition'
    end
    for _, existing in pairs(Props) do
        if tostring(existing.code or ''):lower() == code then return false, 'code_exists' end
    end

    if src ~= 0 then
        local ped = GetPlayerPed(src)
        if not ped or ped == 0 then return false, 'player_unavailable' end
        local playerCoords = GetEntityCoords(ped)
        local dx, dy, dz = playerCoords.x - x, playerCoords.y - y, playerCoords.z - z
        if math.sqrt(dx * dx + dy * dy + dz * dz) > 35.0 then
            return false, 'placement_too_far'
        end
    end

    local actor = src == 0 and 'console' or (GetPlayerName(src) or tostring(src))
    local prop = {
        name = name,
        code = code,
        model_hash = modelHash,
        model_name = trim(payload.model_name, 100),
        x = x, y = y, z = z,
        rx = tonumber(rotation.x) or 0,
        ry = tonumber(rotation.y) or 0,
        rz = tonumber(rotation.z) or tonumber(payload.heading) or 0,
        heading = tonumber(payload.heading) or tonumber(rotation.z) or 0,
        frozen = payload.frozen ~= false,
        collision_enabled = payload.collision_enabled ~= false,
        visible = payload.visible ~= false,
        stream_distance = clampStreamDistance(payload.stream_distance),
        active = true,
        created_by = actor,
        updated_by = actor
    }
    local id = MZPropsDB.insert(prop)
    if not id then return false, 'database_error' end
    prop.id = tonumber(id)
    prop = normalize(prop)
    Props[prop.id] = prop
    broadcastProp(prop)
    audit(src, 'world.prop.created', prop, { origin = 'admin' })
    return true, prop
end)

exports('SetPropActiveForAdmin', function(src, id, active)
    if not hasStaffPermission(src, Config.AdminArchivePermission) then
        return false, 'permission_denied'
    end
    local prop = Props[tonumber(id)]
    if not prop then return false, 'prop_not_found' end
    active = active == true
    if prop.active == active then return true, prop end
    local actor = src == 0 and 'console' or (GetPlayerName(src) or tostring(src))
    local affected = MZPropsDB.setActive(prop.id, active, actor)
    if tonumber(affected) ~= 1 then return false, 'stale_state' end
    prop.active = active
    prop.updated_by = actor
    prop.archived_by = active and nil or actor
    prop.archived_at = active and nil or os.date('!%Y-%m-%d %H:%M:%S')
    broadcastProp(prop)
    audit(src, active and 'world.prop.restored' or 'world.prop.archived', prop, { origin = 'admin' })
    return true, prop
end)

exports('UpdatePropForAdmin', function(src, id, payload)
    if not hasStaffPermission(src, Config.AdminManagePermission) then
        return false, 'permission_denied'
    end
    local prop = Props[tonumber(id)]
    if not prop then return false, 'prop_not_found' end
    if type(payload) ~= 'table' then return false, 'invalid_payload' end
    local name = trim(payload.name, 100)
    if #name < 3 then return false, 'invalid_name' end
    local settings = {
        name = name,
        frozen = payload.frozen == true,
        collision_enabled = payload.collision_enabled == true,
        visible = payload.visible == true,
        stream_distance = clampStreamDistance(payload.stream_distance)
    }
    local actor = src == 0 and 'console' or (GetPlayerName(src) or tostring(src))
    local affected = MZPropsDB.updateSettings(prop.id, settings, actor)
    if affected == nil then return false, 'database_error' end
    prop.name = settings.name
    prop.frozen = settings.frozen
    prop.collision_enabled = settings.collision_enabled
    prop.visible = settings.visible
    prop.stream_distance = settings.stream_distance
    prop.updated_by = actor
    broadcastProp(prop)
    audit(src, 'world.prop.updated', prop, { origin = 'admin' })
    return true, prop
end)

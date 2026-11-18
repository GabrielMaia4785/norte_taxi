-- norte_taxi · cliente
-- Fases de uma viagem: approach (a vir buscar) -> waiting (parado a espera) -> boarded (painel aberto)
-- -> riding (a caminho do destino) -> arrived (a espera que saia) -> ending (vai-se embora).
-- Este cliente e o dono do condutor e do carro: so o dono consegue dar tarefas de conducao.

local ride = nil          -- a viagem deste jogador, ou nil
local panelOpen = false

local function notify(text, kind) Whip.core:Notify(text, kind or 'info') end

local function me() return PlayerPedId() end

local function inTaxi()
    return ride ~= nil and ride.veh ~= nil and IsPedInVehicle(me(), ride.veh, false)
end

local function finish(r, reason)
    if ride ~= r or r.finishing then return end
    r.finishing = true
    TriggerServerEvent('norte_taxi:finish', r.id, reason)
end

-- ---------------------------------------------------------------- pontos na estrada

-- Onde o taxi vai buscar o jogador: a estrada mais perto dele, encostado na berma do lado onde ele esta
local function pickupPlan()
    local pos = GetEntityCoords(me())
    return Driver.planStop(pos, pos)
end

local SPAWN_CHECKS = 28          -- quantas ruas candidatas se medem por estrada (cada uma e um calculo de caminho)

-- Uma rua para o taxi aparecer, escolhida pelo caminho POR ESTRADA ate a recolha, nao pela linha reta: uma rua a
-- 120 m do outro lado de uma autoestrada ou de um rio pode ser 2 km de estrada. Junta as ruas a volta do jogador
-- entre SpawnMin e SpawnMax (linha reta), mede o caminho de cada uma ate ao ponto onde o taxi vai encostar, e fica
-- com a de caminho mais curto acima de SpawnMin, fora de vista e sem carros. O carro nasce virado para la.
local function findSpawnPoint()
    local origin = GetEntityCoords(me())
    local minD, maxD = Config.SpawnMin, Config.SpawnMax
    local goal = pickupPlan()
    local to = goal.approach or goal.stop

    local cands = {}
    for n = 1, 600, 2 do
        local ok, node, heading = GetNthClosestVehicleNodeWithHeading(origin.x, origin.y, origin.z, n, 0, 3.0, 2.5)
        if ok and node then
            local d = #(node - origin)
            if d > maxD * 1.4 then break end
            if d >= minD * 0.6 and not IsAnyVehicleNearPoint(node.x, node.y, node.z, 4.0) then
                cands[#cands + 1] = { node = node, heading = heading, d = d, hidden = not IsSphereVisible(node.x, node.y, node.z, 3.0) }
            end
        end
        if n % 40 == 1 then Wait(0) end
    end
    if #cands == 0 then return nil end

    -- Mede uma amostra espalhada por todas as distancias
    local step = math.max(1, #cands / SPAWN_CHECKS)
    local best, bestScore, nearest
    for i = 1, #cands, step do
        local c = cands[math.floor(i)]
        local road = CalculateTravelDistanceBetweenPoints(c.node.x, c.node.y, c.node.z, to.x, to.y, to.z)
        if road and road > 0.0 and road < 20000.0 then
            -- Caminho curto, mas nao a porta do jogador; fora de vista vale 120 m de caminho
            local score = road + (road < minD and (minD - road) * 3.0 or 0.0) + (c.hidden and 0.0 or 120.0)
            if not best or score < bestScore then best, bestScore = c, score end
        end
        if not nearest or math.abs(c.d - minD) < math.abs(nearest.d - minD) then nearest = c end
        Wait(0)
    end
    best = best or nearest      -- sem caminho medido (zona por carregar): a mais perto de SpawnMin

    -- Virado para a recolha: no sentido da estrada que mais aponta para la
    local h = math.rad(best.heading or 0.0)
    local fwd = vector3(-math.sin(h), math.cos(h), 0.0)
    local heading = best.heading or 0.0
    if fwd.x * (to.x - best.node.x) + fwd.y * (to.y - best.node.y) < 0.0 then heading = heading + 180.0 end
    return best.node, heading % 360.0
end

-- Portas de tras: abrem quando o taxi chega para recolher, fecham quando o passageiro esta sentado
local function rearDoors(veh, open)
    if not veh or not DoesEntityExist(veh) then return end
    for _, door in ipairs({ 2, 3 }) do
        if open then SetVehicleDoorOpen(veh, door, false, false) else SetVehicleDoorShut(veh, door, false) end
    end
end

-- Bancos de tras: 1 do lado do condutor, 2 do outro. O do lado onde o jogador esta, ou o outro se ocupado
local function rearSeat(veh, ped)
    local side = GetOffsetFromEntityGivenWorldCoords(veh, GetEntityCoords(ped))
    local first, second = 2, 1
    if side.x < 0.0 then first, second = 1, 2 end
    if IsVehicleSeatFree(veh, first) then return first end
    if IsVehicleSeatFree(veh, second) then return second end
end

local function honk(veh)
    StartVehicleHorn(veh, 300, `HELDDOWN`, false)
    Wait(450)
    if DoesEntityExist(veh) then StartVehicleHorn(veh, 300, `HELDDOWN`, false) end
end

-- Tecla atual do "mais rapido", para o aviso (o jogador pode muda-la nas teclas do FiveM)
local function boostKey()
    local s = GetControlInstructionalButton(0, joaat('+norte_taxi_boost') | 0x80000000, true)
    if type(s) == 'string' and s:sub(1, 2) == 't_' then return s:sub(3) end
    return 'E'
end

local function waypointCoords()
    if not IsWaypointActive() then return nil end
    return GetBlipInfoIdCoord(GetFirstBlipInfoId(8))
end

-- ---------------------------------------------------------------- entidades

local function waitForEntity(netId, ms)
    local deadline = GetGameTimer() + ms
    while not NetworkDoesEntityExistWithNetworkId(netId) do
        if GetGameTimer() > deadline then return nil end
        Wait(100)
    end
    return NetToVeh(netId)
end

local function takeControl(ent, ms)
    local deadline = GetGameTimer() + ms
    NetworkRequestControlOfEntity(ent)
    while not NetworkHasControlOfEntity(ent) do
        if GetGameTimer() > deadline then return false end
        NetworkRequestControlOfEntity(ent)
        Wait(50)
    end
    return true
end

-- Um ped do taxi sentado em `seat`: -1 o condutor, 0 o banco da frente (sempre invisivel, so ocupa o lugar
-- para o GTA nunca levar o jogador pela porta da frente)
local function createDriver(veh, seat)
    local hash = joaat(Config.DriverModel)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > deadline then return nil end
        Wait(50)
    end
    local ped = CreatePedInsideVehicle(veh, 26, hash, seat or -1, true, false)
    SetModelAsNoLongerNeeded(hash)
    if not ped or ped == 0 then return nil end

    SetNetworkIdCanMigrate(PedToNet(ped), false)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)     -- nao foge nem reage a tiros: so conduz
    SetPedKeepTask(ped, true)
    SetPedCanBeDraggedOut(ped, false)
    SetPedCanBeKnockedOffVehicle(ped, 1)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCanRagdoll(ped, false)
    SetEntityInvincible(ped, true)
    SetDriverAbility(ped, 1.0)
    SetDriverAggressiveness(ped, 0.0)
    if Config.HideDriver or seat == 0 then SetEntityVisible(ped, false, false) end
    return ped
end

local function hazards(veh, on)
    if not veh or not DoesEntityExist(veh) then return end
    SetVehicleIndicatorLights(veh, 0, on)
    SetVehicleIndicatorLights(veh, 1, on)
end

-- ---------------------------------------------------------------- ritmo (escolhido ao chamar, subido com E)

local PACE_SUB = {
    normal = 'Obeys every rule and speed limit',
    fast = 'Obeys the rules, drives fast',
    super = 'No traffic rules at all',
}

-- Velocidade e estilo do ritmo da viagem: na vinda a partir de PickupSpeed, na viagem de CruiseSpeed
local function pace(r)
    local p = Taxi.pace(r.pace)
    local base = r.stage == 'approach' and Config.PickupSpeed or Config.CruiseSpeed
    return base * (tonumber(p.speed) or 1.0), Taxi.paceStyle(r.pace)
end

-- O aviso do canto inferior direito: o ritmo seguinte e o que custa. So e enviado quando muda
local hintKey = nil
local function updateHint()
    local r = ride
    -- Sentado e parado: E comeca a viagem
    if r and r.stage == 'boarded' and not panelOpen and inTaxi() then
        local key = 'start:' .. (r.starting and 'p' or '')
        if key == hintKey then return end
        hintKey = key
        return SendNUIMessage({
            action = 'hint', show = true, label = r.preset and 'Start ride' or 'Choose destination',
            sub = r.preset and r.preset.label and ('To ' .. r.preset.label) or 'Open the map to pick where to go',
            key = boostKey(), paying = r.starting == true,
        })
    end
    local level = r and (r.pace or 1) + 1
    local tier = level and Config.Paces[level]
    local show = tier and tier.upgrade and r.stage == 'riding' and not r.stopping and not panelOpen and inTaxi()
    local key = show and ('%d:%s'):format(level, r.paying and 'p' or '') or 'off'
    if key == hintKey then return end
    hintKey = key
    if not show then return SendNUIMessage({ action = 'hint', show = false }) end
    SendNUIMessage({
        action = 'hint', show = true, label = tier.label, sub = PACE_SUB[tier.style] or '',
        price = tier.upgrade, key = boostKey(), paying = r.paying == true,
    })
end

-- ---------------------------------------------------------------- painel

local function closePanel()
    if not panelOpen then return end
    panelOpen = false
    SetNuiFocus(false, false)
    Whip.core:SetScreenOpen(false, 'panel')
    SendNUIMessage({ action = 'close' })
    updateHint()
end

local function openPanel()
    if not ride or panelOpen or not inTaxi() then return end
    local pos = GetEntityCoords(me())
    local wp = waypointCoords()
    local dest = ride.dest
    panelOpen = true
    updateHint()
    SetNuiFocus(true, true)
    Whip.core:SetScreenOpen(true, 'panel')
    SendNUIMessage({
        action = 'open',
        player = { x = pos.x, y = pos.y, z = pos.z, heading = GetEntityHeading(me()) },
        destinations = Taxi.destinations(),
        waypoint = wp and { x = wp.x, y = wp.y, z = wp.z } or nil,
        dest = dest and { x = dest.x, y = dest.y, z = dest.z, label = ride.destLabel } or nil,
        riding = ride.stage == 'riding',
        avgSpeed = Config.CruiseSpeed * 0.6,
    })
end

-- ---------------------------------------------------------------- viagem

-- O circulo da area de chegada no mapa do jogo; nil apaga-o
local function areaBlip(r, center)
    if r.areaBlip and DoesBlipExist(r.areaBlip) then RemoveBlip(r.areaBlip) end
    r.areaBlip = nil
    if not center then return end
    r.areaBlip = AddBlipForRadius(center.x, center.y, center.z, Config.ArriveRadius + 0.0)
    SetBlipColour(r.areaBlip, 3)
    SetBlipAlpha(r.areaBlip, 110)
end

local function cleanupLocal()
    local r = ride
    ride = nil
    Driver.stop()
    closePanel()
    updateHint()
    if not r then return end
    areaBlip(r, nil)
    if r.blip and DoesBlipExist(r.blip) then RemoveBlip(r.blip) end
    for _, p in ipairs({ r.driver, r.front }) do
        if p and DoesEntityExist(p) and NetworkHasControlOfEntity(p) then DeleteEntity(p) end
    end
end

local function onLost(r)
    if ride ~= r then return end
    finish(r, r.stage == 'riding' and 'left' or 'stuck')
end

local function onRideArrive(r)
    if ride ~= r then return end
    Driver.hold(r.veh, r.driver)
    r.stage = 'arrived'
    hazards(r.veh, true)
    SetWaypointOff()
    areaBlip(r, nil)
    notify(r.stopping and 'The taxi pulled over.' or 'We have arrived.', 'success')

    -- Espera que o carro pare de vez (no maximo 4 s) e tira o passageiro, sem ele carregar em nada
    local deadline = GetGameTimer() + 4000
    while ride == r and GetEntitySpeed(r.veh) > 0.3 and GetGameTimer() < deadline do Wait(100) end
    if ride ~= r then return end
    TaskLeaveVehicle(me(), r.veh, 0)

    -- Se a saida normal ficar presa (porta encostada a uma parede, por exemplo), sai sem animacao ao fim de 4 s
    deadline = GetGameTimer() + 4000
    while ride == r and IsPedInVehicle(me(), r.veh, false) do
        if GetGameTimer() > deadline then
            TaskLeaveVehicle(me(), r.veh, 16)       -- 16: sai ja, sem animacao
            deadline = GetGameTimer() + 60000
        end
        Wait(200)
    end
    finish(r, r.stopping and 'stopped' or 'arrived')
end

-- Durante a viagem: saiu do carro? mudou a marcacao no mapa?
local function rideWatch(r)
    while ride == r and r.stage == 'riding' do
        if not IsPedInVehicle(me(), r.veh, false) then
            Driver.hold(r.veh, r.driver)
            return finish(r, 'left')
        end

        local wp = waypointCoords()
        if not wp then
            SetNewWaypoint(r.dest.x, r.dest.y)          -- a marcacao e o caminho: volta a por-la
        elseif #(vector2(wp.x, wp.y) - vector2(r.dest.x, r.dest.y)) > 30.0 and not r.stopping then
            -- O jogador mudou a marcacao no mapa do jogo: o taxi passa a segui-la
            local ok = Whip.core:Callback('norte_taxi:setDestination', r.id, wp.x, wp.y, wp.z)
            if ride ~= r or r.stage ~= 'riding' then return end
            if ok == true then
                r.dest, r.destLabel = vector3(wp.x, wp.y, wp.z), 'Map marker'
                Driver.setTarget(Driver.planStop(r.dest, r.dest))
                areaBlip(r, r.dest)
                notify('New destination: the taxi follows your marker.', 'info')
            else
                SetNewWaypoint(r.dest.x, r.dest.y)
            end
        end
        if r.paying and GetGameTimer() - r.payingAt > 6000 then r.paying = false end   -- sem resposta do servidor
        updateHint()
        Wait(500)
    end
    updateHint()
end

local function startRide(r, dest, label)
    r.dest, r.destLabel = dest, label
    SetNewWaypoint(dest.x, dest.y)
    hazards(r.veh, false)
    -- A berma do lado do sitio marcado (um predio, uma porta): o passageiro sai desse lado. A viagem chega ao entrar
    -- na area de Config.ArriveRadius a volta do sitio, mostrada no mapa do jogo
    local plan = Driver.planStop(dest, dest)
    areaBlip(r, dest)
    if r.stage == 'riding' and Driver.isDriving() then
        Driver.setTarget(plan)
    else
        r.stage = 'riding'
        local speed, style = pace(r)
        Driver.start(r.veh, r.driver, {
            plan = plan, speed = speed, style = style, arrive = Config.ArriveDistance, area = Config.ArriveRadius,
            passenger = true,
            onArrive = function() onRideArrive(r) end,
            onLost = function() onLost(r) end,
        })
        CreateThread(function() rideWatch(r) end)
    end
    notify(('On the way: %s.'):format(label or 'marked destination'), 'success')
end

local function warn(r, text)
    if GetGameTimer() - (r.warnAt or 0) < 4000 then return end
    r.warnAt = GetGameTimer()
    notify(text, 'error')
end

-- Entra pelo banco de tras do lado onde o jogador esta (o outro, se esse estiver ocupado)
local function boardTaxi(r)
    if not r or not r.veh or not DoesEntityExist(r.veh) then return end
    if r.stage == 'approach' then return warn(r, 'Wait for the taxi to stop.') end
    if r.stage ~= 'waiting' then return end
    local seat = rearSeat(r.veh, me())
    if not seat then return warn(r, 'The back seat is taken.') end
    r.boardingAt = GetGameTimer()
    -- Sem a porta de tras desse lado no modelo, senta-o logo; com ela, entra pela PROPRIA porta do banco
    -- (1048576 = BlockSeatShuffling, o mesmo que o WHIP usa): sem isto o GTA passa pela porta da frente
    if GetEntityBoneIndexByName(r.veh, seat == 1 and 'door_dside_r' or 'door_pside_r') == -1 then
        return TaskEnterVehicle(me(), r.veh, 10000, seat, 1.0, 16, 0)        -- 16: senta sem animacao
    end
    TaskEnterVehicle(me(), r.veh, 10000, seat, 1.0, 1 | 1048576, 0)
end

-- O GTA escolhe a porta da frente quando o jogador carrega em F do lado esquerdo, e com o condutor ao volante
-- fica preso a tentar abri-la. Por isso, perto do taxi, o F do GTA (controlo 23) fica desligado e o F e
-- nosso (+norte_taxi_enter): manda sempre para o banco de tras. Quem aparecer no banco da frente volta para tras.
local ENTER_RANGE = 6.0
local function guardSeats(r)
    while ride == r and r.stage ~= 'ending' do
        local p = me()
        local near = not IsPedInAnyVehicle(p, false) and (r.stage == 'approach' or r.stage == 'waiting')
            and #(GetEntityCoords(p) - GetEntityCoords(r.veh)) < ENTER_RANGE
        if near ~= (r.blocking == true) then
            r.blocking = near
            if near then Whip.core:BlockControls('norte_taxi_enter', { controls = { 23 } })
            else Whip.core:UnblockControls('norte_taxi_enter') end
        end

        -- Se mesmo assim o GTA mandar para a frente (outra tecla, comando), corrige uma vez e deixa a animacao correr
        if GetVehiclePedIsTryingToEnter(p) == r.veh then
            local seat = GetSeatPedIsTryingToEnter(p)
            local ours = GetGameTimer() - (r.boardingAt or 0) < 10000     -- a nossa entrada ainda a correr
            if (seat == -1 or seat == 0) and not ours and GetGameTimer() - (r.redirectAt or 0) > 2500 then
                r.redirectAt = GetGameTimer()
                ClearPedTasks(p)
                boardTaxi(r)
            end
        elseif GetPedInVehicleSeat(r.veh, 0) == p then
            local rear = rearSeat(r.veh, p)
            if rear then SetPedIntoVehicle(p, r.veh, rear) end
        end
        Wait(150)
    end
    if r.blocking then
        r.blocking = false
        Whip.core:UnblockControls('norte_taxi_enter')
    end
end

RegisterCommand('+norte_taxi_enter', function()
    local r = ride
    if r and r.blocking then boardTaxi(r) end
end, false)
RegisterCommand('-norte_taxi_enter', function() end, false)
RegisterKeyMapping('+norte_taxi_enter', 'Taxi: get in the back seat', 'keyboard', 'F')

-- Taxi de outro jogador (marcado pelo servidor com o state bag norteTaxi): quem vai a boleia tambem entra so por
-- tras. Se o GTA o mandar para a frente, corrige uma vez para o banco de tras do lado onde esta, pela porta dele.
CreateThread(function()
    local redirectAt = 0
    while true do
        local p = me()
        local veh = GetVehiclePedIsTryingToEnter(p)
        if veh ~= 0 and not (ride and veh == ride.veh) and Entity(veh).state.norteTaxi then
            local seat = GetSeatPedIsTryingToEnter(p)
            if (seat == -1 or seat == 0) and GetGameTimer() - redirectAt > 2500 then
                redirectAt = GetGameTimer()
                ClearPedTasks(p)
                local rear = rearSeat(veh, p)
                if rear then TaskEnterVehicle(p, veh, 10000, rear, 1.0, 1 | 1048576, 0) end
            end
        end
        Wait(veh ~= 0 and 150 or 400)
    end
end)

local function stopHere()
    local r = ride
    if not r or r.stage ~= 'riding' or r.stopping then return end
    r.stopping = true
    -- 25 m a frente, na berma da direita do carro: dentro da distancia de chegada, por isso encosta ja
    local ahead = GetOffsetFromEntityInWorldCoords(r.veh, 0.0, 25.0, 0.0)
    Driver.setTarget(Driver.planStop(ahead, GetOffsetFromEntityInWorldCoords(r.veh, 8.0, 25.0, 0.0)))
    notify('The taxi will pull over.', 'info')
end

local function onBoarded(r)
    r.stage = 'boarded'
    hazards(r.veh, false)
    rearDoors(r.veh, false)
    if r.blip and DoesBlipExist(r.blip) then RemoveBlip(r.blip) end
    r.blip = nil
    TriggerServerEvent('norte_taxi:stage', r.id, 'boarded')
    -- A viagem nao parte sozinha: o passageiro carrega em E (o aviso do canto inferior direito diz isso)
    notify(r.preset and 'Press E to start the ride.' or 'Press E to choose where to go.', 'info')
    updateHint()

    -- Enquanto espera pelo E: se sair do carro, a viagem acaba
    local outSince
    while ride == r and r.stage == 'boarded' do
        if inTaxi() then outSince = nil
        elseif not outSince then outSince = GetGameTimer()
        elseif GetGameTimer() - outSince > 1500 then return finish(r, 'left') end
        updateHint()
        Wait(300)
    end
end

-- E dentro do taxi parado: com destino da app, parte; sem destino, abre o mapa para o escolher
local function beginRide(r)
    if r.starting then return end
    local p = r.preset
    if not p then return openPanel() end
    r.starting = true
    updateHint()
    local ok, why = Whip.core:Callback('norte_taxi:setDestination', r.id, p.x, p.y, p.z)
    r.starting = false
    if ride ~= r or r.stage ~= 'boarded' then return end
    if ok == true then return startRide(r, vector3(p.x, p.y, p.z), p.label) end
    notify(type(why) == 'string' and why or 'Choose your destination.', 'error')
    updateHint()
    openPanel()
end

local function waitBoarding(r)
    local deadline = GetGameTimer() + Config.WaitSeconds * 1000
    while ride == r and r.stage == 'waiting' do
        if IsPedInVehicle(me(), r.veh, false) then return onBoarded(r) end
        if GetGameTimer() > deadline then return finish(r, 'timeout') end
        Wait(300)
    end
end

local function onPickupArrive(r)
    if ride ~= r then return end
    Driver.hold(r.veh, r.driver)
    r.stage = 'waiting'
    hazards(r.veh, true)
    TriggerServerEvent('norte_taxi:stage', r.id, 'waiting')
    notify('Your taxi has arrived. Get in the back seat.', 'success')
    honk(r.veh)
    -- Espera que pare de vez antes de abrir as portas
    local deadline = GetGameTimer() + 2500
    while ride == r and GetEntitySpeed(r.veh) > 0.3 and GetGameTimer() < deadline do Wait(100) end
    if ride == r and r.stage == 'waiting' then rearDoors(r.veh, true) end
    waitBoarding(r)
end

local function setupTaxi(r)
    local veh = waitForEntity(r.netId, 10000)
    if ride ~= r then return end
    if not veh or veh == 0 or not takeControl(veh, 3000) then return finish(r, 'stuck') end

    SetNetworkIdCanMigrate(r.netId, false)
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleEngineOn(veh, true, true, false)

    -- Pintura WHIB: so o dono da entidade a pode mudar, e os outros jogadores recebem-na pela rede
    local lv = Config.Livery
    if lv then
        SetVehicleModKit(veh, 0)
        if GetNumVehicleMods(veh, lv.modType) > lv.modIndex then
            SetVehicleMod(veh, lv.modType, lv.modIndex, false)
            local c = lv.color
            if c then
                SetVehicleCustomPrimaryColour(veh, c[1], c[2], c[3])
                SetVehicleCustomSecondaryColour(veh, c[1], c[2], c[3])
            end
        else
            print('^3[norte_taxi] vivanite2 has no livery slot: is the server on game build 3751 or later?^7')
        end
    end

    local ped = createDriver(veh, -1)
    local front = ped and createDriver(veh, 0)
    if ride ~= r then
        if ped then DeleteEntity(ped) end
        if front then DeleteEntity(front) end
        return
    end
    if not ped then return finish(r, 'stuck') end
    r.veh, r.driver, r.front = veh, ped, front
    TriggerServerEvent('norte_taxi:driver', r.id, PedToNet(ped), 'driver')
    if front then TriggerServerEvent('norte_taxi:driver', r.id, PedToNet(front), 'front') end

    r.blip = AddBlipForEntity(veh)
    SetBlipSprite(r.blip, 198)
    SetBlipColour(r.blip, 5)
    SetBlipScale(r.blip, 0.85)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Taxi')
    EndTextCommandSetBlipName(r.blip)

    notify(('Your %s taxi is on the way. It will stop on the road closest to you.'):format(Taxi.pace(r.pace).label), 'info')
    CreateThread(function() guardSeats(r) end)
    local approachSpeed, approachStyle = pace(r)      -- o ritmo escolhido conta ja na vinda
    Driver.start(veh, ped, {
        -- area a volta do jogador: ao entrar, encosta, para e abre as portas (se ele estiver longe da estrada,
        -- o taxi para na berma mais proxima dele, como antes)
        plan = pickupPlan(), speed = approachSpeed, style = approachStyle, arrive = 25.0, area = Config.PickupRadius,
        passenger = false,
        follow = pickupPlan,
        onArrive = function() onPickupArrive(r) end,
        onLost = function() onLost(r) end,
    })
end

-- ---------------------------------------------------------------- mensagens do servidor

RegisterNetEvent('norte_taxi:findSpawn', function(rideId)
    local node, heading = findSpawnPoint()
    if not node then return TriggerServerEvent('norte_taxi:finish', rideId, 'nospawn') end
    TriggerServerEvent('norte_taxi:spawn', rideId, node.x, node.y, node.z, (heading or 0.0) % 360.0)
end)

RegisterNetEvent('norte_taxi:assigned', function(data)
    if type(data) ~= 'table' or not data.ride or not data.netId then return end
    cleanupLocal()
    local r = { id = data.ride, netId = data.netId, stage = 'approach', pace = Config.Paces[data.pace] and data.pace or 1 }
    local p = data.preset
    if type(p) == 'table' and tonumber(p.x) and tonumber(p.y) then
        r.preset = { x = p.x + 0.0, y = p.y + 0.0, z = (tonumber(p.z) or 30.0) + 0.0, label = p.label }
    end
    ride = r
    setupTaxi(r)
end)

-- A viagem acabou: sai do carro se ainda la estiver e o taxi vai-se embora
RegisterNetEvent('norte_taxi:ending', function(rideId)
    local r = ride
    if not r or r.id ~= rideId then return end
    r.stage = 'ending'
    Driver.stop()
    closePanel()
    updateHint()
    areaBlip(r, nil)
    if r.blip and DoesBlipExist(r.blip) then RemoveBlip(r.blip) end
    r.blip = nil
    local wp = waypointCoords()
    if wp and r.dest and #(vector2(wp.x, wp.y) - vector2(r.dest.x, r.dest.y)) < 5.0 then SetWaypointOff() end
    if not r.veh or not DoesEntityExist(r.veh) then return end

    if IsPedInVehicle(me(), r.veh, false) then
        Driver.hold(r.veh, r.driver)
        local deadline = GetGameTimer() + 8000
        while GetEntitySpeed(r.veh) > 0.5 and GetGameTimer() < deadline do Wait(100) end
        TaskLeaveVehicle(me(), r.veh, 0)
        deadline = GetGameTimer() + 5000
        while IsPedInVehicle(me(), r.veh, false) and GetGameTimer() < deadline do Wait(200) end
    end
    if ride == r then
        hazards(r.veh, false)
        rearDoors(r.veh, false)
        Driver.wander(r.veh, r.driver)
    end
end)

RegisterNetEvent('norte_taxi:ended', function(rideId)
    if ride and ride.id == rideId then cleanupLocal() end
end)

-- Resposta do servidor a subida de ritmo: o ritmo agora (igual ao anterior se o pagamento falhou)
RegisterNetEvent('norte_taxi:boost', function(rideId, level)
    local r = ride
    if not r or r.id ~= rideId or type(level) ~= 'number' then return end
    r.paying = false
    if level ~= (r.pace or 1) then
        r.pace = level
        if Driver.isDriving() then Driver.setPace(pace(r)) end
    end
    updateHint()
end)

-- /taxi sem ritmo: escolhe-se aqui, e o servidor chama o taxi
RegisterNetEvent('norte_taxi:pickPace', function()
    local options = {}
    for _, p in ipairs(Config.Paces) do
        options[#options + 1] = { label = ('%s: %s'):format(p.label, PACE_SUB[p.style] or ''), value = p.key }
    end
    local values = Whip.core:Input('Call a taxi', {
        { label = 'How fast?', type = 'select', options = options, default = Config.Paces[1].key, required = true },
    })
    local key = type(values) == 'table' and values[1]
    if type(key) == 'string' and Taxi.paceIndex(key) then TriggerServerEvent('norte_taxi:call', key) end
end)

-- ---------------------------------------------------------------- tecla E: ritmo seguinte

-- E dentro do taxi: parado a espera, comeca a viagem; em viagem, paga o ritmo seguinte
RegisterCommand('+norte_taxi_boost', function()
    local r = ride
    if not r or r.paying or panelOpen or not inTaxi() then return end
    if r.stage == 'boarded' then
        if Whip.core:IsGameInputFree() ~= true then return end
        return beginRide(r)
    end
    if r.stage ~= 'riding' or r.stopping then return end
    local level = (r.pace or 1) + 1
    if not Config.Paces[level] or not Config.Paces[level].upgrade then return end
    if Whip.core:IsGameInputFree() ~= true then return end
    r.paying, r.payingAt = true, GetGameTimer()
    updateHint()
    TriggerServerEvent('norte_taxi:boost', r.id, level)
end, false)
RegisterCommand('-norte_taxi_boost', function() end, false)
RegisterKeyMapping('+norte_taxi_boost', 'Taxi: start the ride / go faster', 'keyboard', 'E')

-- ---------------------------------------------------------------- NUI

RegisterNUICallback('close', function(_, cb)
    closePanel()
    cb('ok')
end)

RegisterNUICallback('setDestination', function(data, cb)
    local r = ride
    local x, y, z = tonumber(data and data.x), tonumber(data and data.y), tonumber(data and data.z)
    if not r or not x or not y then return cb({ ok = false, message = 'Invalid destination.' }) end
    if not z or z <= 0.0 then z = 30.0 end

    local ok, why = Whip.core:Callback('norte_taxi:setDestination', r.id, x, y, z)
    if ride ~= r then return cb({ ok = false, message = 'The ride has ended.' }) end
    if ok ~= true then
        return cb({ ok = false, message = type(why) == 'string' and why or 'The taxi did not accept the destination.' })
    end
    cb({ ok = true })
    closePanel()
    local label = type(data.label) == 'string' and data.label:sub(1, 40) or nil
    startRide(r, vector3(x, y, z), label)
end)

RegisterNUICallback('stopHere', function(_, cb)
    cb('ok')
    closePanel()
    stopHere()
end)

-- ---------------------------------------------------------------- acoes

Whip.register(function()
    local function canBoard(ctx)
        return ride ~= nil and ride.stage == 'waiting' and ctx.entity == ride.veh
    end
    for _, door in ipairs({ { part = 'door_dside_r', seat = 1 }, { part = 'door_pside_r', seat = 2 } }) do
        Whip.core:AddAction({
            id = 'board_' .. door.seat,
            at = { vehiclePart = door.part },
            label = 'Enter taxi',
            canInteract = canBoard,
            onSelect = function() boardTaxi(ride) end,
        })
    end

    Whip.core:AddAction({
        id = 'destination',
        at = { radial = true },
        label = 'Taxi: destination',
        description = 'Open the map to choose where to go',
        canInteract = function()
            return inTaxi() and (ride.stage == 'boarded' or ride.stage == 'riding')
        end,
        onSelect = function() openPanel() end,
    })

    Whip.core:AddAction({
        id = 'stop',
        at = { radial = true },
        label = 'Taxi: stop here',
        description = 'The taxi pulls over at the next curb and the ride ends',
        canInteract = function()
            return inTaxi() and ride.stage == 'riding' and not ride.stopping
        end,
        onSelect = function() stopHere() end,
    })
end)

TriggerEvent('chat:addSuggestion', '/taxi', 'Call a self-driving taxi to you', {
    { name = 'pace', help = 'Optional: normal, fast or superfast (asks when left out), or cancel to send it away' },
})

-- ---------------------------------------------------------------- app WHIP RIDE (whip_phone)

-- whip_phone e opcional: a app aparece quando ele corre, e volta depois de ele reiniciar
local function registerPhoneApp()
    if GetResourceState('whip_phone') ~= 'started' then return end
    local ok, why = exports.whip_phone:RegisterModule({ id = 'whipride', script = 'html/phone/whipride.js' })
    if not ok then print(('^3[norte_taxi] WHIP RIDE app not registered: %s^7'):format(tostring(why))) end
end
CreateThread(registerPhoneApp)
AddEventHandler('onResourceStart', function(res) if res == 'whip_phone' then registerPhoneApp() end end)

AddEventHandler('whip_core:player:logout', function() cleanupLocal() end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    cleanupLocal()
end)

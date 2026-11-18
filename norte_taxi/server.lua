-- norte_taxi · servidor
-- O servidor decide: quem tem um taxi, onde ele aparece, em que fase esta a viagem e quando acaba.
-- O cliente de quem chamou conduz o carro (tarefas de IA do GTA so correm no dono da entidade) e so pede.

local rides = {}        -- [charId] = viagem em memoria (nunca guardada: o source muda de jogador para jogador)
local byVehicle = {}    -- [vehicleId] = charId
local lastCall = {}     -- [charId] = os.time() da ultima viagem
local nextId = 0

local MESSAGES = {
    arrived = { 'You have arrived. Thanks for riding with us.', 'success' },
    cancel  = { 'Ride cancelled.', 'info' },
    stopped = { 'Ride ended here. Thanks for riding with us.', 'success' },
    left    = { 'You left the taxi. Ride ended.', 'info' },
    timeout = { 'The taxi waited too long and left.', 'error' },
    stuck   = { 'The taxi could not reach you.', 'error' },
    nospawn = { 'There is no free road nearby for the taxi.', 'error' },
    expired = { 'Your taxi time ran out.', 'error' },
    failed  = { 'No taxi is available right now.', 'error' },
}

local function notify(source, text, kind)
    Whip.core:NotifyPlayer(source, text, kind or 'info')
end

local function online(ride)
    return ride.source and Whip.core:IsSessionCurrent(ride.source, ride.session) == true
end

local function entityOf(netId)
    if not netId then return 0 end
    local ent = NetworkGetEntityFromNetworkId(netId)
    if ent and ent ~= 0 and DoesEntityExist(ent) then return ent end
    return 0
end

-- O jogador esta sentado num lugar de passageiro deste taxi?
local function isPassenger(source, ride)
    local at = Whip.core:GetPlayerSeat(source)
    return type(at) == 'table' and at.netId == ride.netId and not at.driver
end

-- Apaga o condutor e o ped invisivel do banco da frente
local function deleteDriver(ride)
    for _, net in ipairs({ ride.driverNet, ride.frontNet }) do
        local ped = entityOf(net)
        if ped ~= 0 and GetEntityType(ped) == 1 then DeleteEntity(ped) end
    end
    ride.driverNet, ride.frontNet = nil, nil
end

-- A app WHIP RIDE do whip_phone (html/phone/whipride.js) segue a viagem por pushes. Sem whip_phone, nada acontece.
local function phonePush(source, event, data)
    if GetResourceState('whip_phone') ~= 'started' then return end
    exports.whip_phone:Push(source, 'whipride', event, data)
end

local function rideStatus(ride)
    if not ride then return { stage = 'none' } end
    return { stage = ride.state, label = ride.destLabel, price = ride.prepaid and ride.prepaid.price or nil,
        pace = Taxi.pace(ride.pace).label }
end

local function pushStatus(ride)
    if online(ride) then phonePush(ride.source, 'status', rideStatus(ride)) end
end

-- Acaba a viagem. Sem `now`, o carro vai-se embora a conduzir e so desaparece ao fim de LeaveSeconds.
local function endRide(charId, reason, now)
    local ride = rides[charId]
    if not ride then return end
    rides[charId] = nil
    if ride.vehicleId then byVehicle[ride.vehicleId] = nil end
    lastCall[charId] = os.time()

    -- Pago na app e o passageiro nunca chegou a viajar: o dinheiro volta
    local refunded = false
    if ride.prepaid and not ride.travelled then
        refunded = Whip.core:RefundPlayer(ride.prepaid.receipt) == true
    end

    if online(ride) then
        local msg = MESSAGES[reason] or MESSAGES.failed
        notify(ride.source, msg[1] .. (refunded and (' $%d refunded.'):format(ride.prepaid.price) or ''), msg[2])
        TriggerClientEvent('norte_taxi:ending', ride.source, ride.id, reason)
        phonePush(ride.source, 'status', { stage = 'none', ended = reason, refunded = refunded })
    end

    -- Quem foi a boleia sai tambem (o dono sai pelo proprio cliente)
    local veh = entityOf(ride.netId)
    if veh ~= 0 then
        for seat = 1, 6 do
            local ped = GetPedInVehicleSeat(veh, seat)
            if ped and ped ~= 0 and IsPedAPlayer(ped) and (not online(ride) or ped ~= GetPlayerPed(ride.source)) then
                TaskLeaveVehicle(ped, veh, 0)
            end
        end
    end

    local function remove()
        deleteDriver(ride)
        if ride.tag then Whip.core:ReleaseTag(ride.tag) end
        if online(ride) then TriggerClientEvent('norte_taxi:ended', ride.source, ride.id) end
    end

    if now or not ride.vehicleId then remove() else SetTimeout(Config.LeaveSeconds * 1000, remove) end
end

-- Corre fn ao fim de ms se a viagem ainda for esta e estiver na mesma fase
local function laterIf(ride, state, ms, fn)
    SetTimeout(ms, function()
        if rides[ride.charId] == ride and ride.state == state then fn() end
    end)
end

-- Pode este personagem chamar um taxi agora? nil, ou a razao para o jogador
local function cannotCall(source, charId)
    if rides[charId] then return 'You already have a taxi. Use /taxi cancel to send it away.' end
    if GetVehiclePedIsIn(GetPlayerPed(source), false) ~= 0 then return 'Get out of the vehicle to call a taxi.' end
    local wait = (lastCall[charId] or 0) + Config.CooldownSeconds - os.time()
    if wait > 0 then return ('Wait %d s before calling another taxi.'):format(wait) end
end

-- Chama o taxi: o mesmo caminho para /taxi e para a app. `pace`: 1 Normal, 2 Fast, 3 Super fast.
-- `preset` (so a app): { dest, label, prepaid }
local function startCall(source, player, pace, preset)
    nextId = nextId + 1
    local ride = { id = nextId, charId = player.charId, source = source, session = player.session, state = 'requested',
        pace = Config.Paces[pace] and pace or 1 }
    if preset then ride.preset, ride.destLabel, ride.prepaid = preset.dest, preset.label, preset.prepaid end
    rides[player.charId] = ride
    TriggerClientEvent('norte_taxi:findSpawn', source, ride.id)
    notify(source, 'Calling a taxi...', 'info')
    pushStatus(ride)

    -- O cliente tem 15 s para dizer onde o carro aparece
    laterIf(ride, 'requested', 15000, function() endRide(player.charId, 'nospawn', true) end)
end

-- Preco de uma viagem ate (x, y) no ritmo `pace`, a partir de onde o jogador esta:
-- (base + km de estrada x preco por km) x multiplicador do ritmo
local function quote(source, x, y, pace)
    local pos = GetEntityCoords(GetPlayerPed(source))
    local km = #(vector2(pos.x, pos.y) - vector2(x, y)) * (Config.Fare.roadFactor or 1.3) / 1000.0
    local price = ((Config.Fare.base or 0) + km * (Config.Fare.perKm or 1)) * (tonumber(Taxi.pace(pace).fare) or 1)
    return math.max(math.ceil(price), Config.Fare.min or 0), math.floor(km * 10 + 0.5) / 10
end

-- Um ponto marcado no mapa da app: { x, y, z } com numeros dentro do mapa, ou nil
local function mapPoint(args)
    if type(args) ~= 'table' then return nil end
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z) or 30.0
    if not x or not y or x ~= x or y ~= y or not Taxi.inBounds(x, y) then return nil end
    return vector3(x, y, math.max(-100.0, math.min(1500.0, z)))
end

-- /taxi pergunta o ritmo e chama um taxi. /taxi normal|fast|superfast chama logo. /taxi cancel manda-o embora.
Whip.command('taxi', { rateLimit = { burst = 2, everyMs = 2000 } }, function(source, args)
    local player = Whip.core:GetPlayer(source)
    if not player then return end
    local current = rides[player.charId]
    local word = type(args[1]) == 'string' and args[1]:lower() or nil

    if word == 'cancel' or word == 'cancelar' then
        if not current then return notify(source, 'You have not called a taxi.', 'error') end
        return endRide(player.charId, 'cancel', current.state == 'requested')
    end

    local why = cannotCall(source, player.charId)
    if why then return notify(source, why, 'error') end
    local pace = Taxi.paceIndex(word == 'super' and 'superfast' or word)
    if pace then return startCall(source, player, pace) end
    TriggerClientEvent('norte_taxi:pickPace', source)      -- o cliente mostra a escolha e responde com norte_taxi:call
end)

Whip.register(function()
    -- O cliente propoe uma rua para o taxi aparecer. O servidor confirma a distancia e cria o carro.
    Whip.core:SecureEvent('norte_taxi:spawn', {
        rateLimit = 2000,
        params = {
            { 'ride', 'id' },
            { 'x', 'number', -5000, 6000 },
            { 'y', 'number', -5000, 9000 },
            { 'z', 'number', -100, 1500 },
            { 'h', 'number', 0, 360 },
        },
    }, function(source, player, rideId, x, y, z, h)
        local ride = rides[player.charId]
        if not ride or ride.id ~= rideId or ride.state ~= 'requested' then return false end

        local dist = #(GetEntityCoords(GetPlayerPed(source)) - vector3(x, y, z))
        if dist < Config.SpawnMin * 0.5 or dist > Config.SpawnMax * 1.5 then
            endRide(player.charId, 'nospawn', true)
            return false
        end

        ride.state = 'spawning'
        ride.tag = ('norte_taxi:%d'):format(ride.id)
        local vehicleId, why = exports.whip_core:SpawnTempVehicle(Config.Model, vector4(x, y, z + 0.5, h), {
            giveKey = false,
            keyInIgnition = true,       -- o motor so trabalha com chave na ignicao
            locked = false,
            secure = true,              -- sem lockpick nem hack da ignicao
            despawnAfter = Config.MaxRideMinutes * 60,
            tag = ride.tag,
        })

        -- SpawnTempVehicle espera: a viagem ou o jogador podem ter mudado entretanto
        if rides[player.charId] ~= ride or not exports.whip_core:IsSessionCurrent(source, ride.session) then
            if vehicleId then exports.whip_core:ReleaseTag(ride.tag) end
            return false
        end
        if not vehicleId then
            print(('^3[norte_taxi] SpawnTempVehicle(%s) refused: %s^7'):format(Config.Model, tostring(why)))
            endRide(player.charId, 'failed', true)
            return false
        end

        local netId
        for _ = 1, 30 do
            local snap = exports.whip_core:GetVehicle(vehicleId)
            netId = snap and snap.netId
            if netId then break end
            Wait(100)
        end
        if not netId or rides[player.charId] ~= ride then
            endRide(player.charId, 'failed', true)
            return false
        end

        ride.vehicleId, ride.netId, ride.state = vehicleId, netId, 'approach'
        byVehicle[vehicleId] = player.charId
        exports.whip_core:SetVehicleStat(vehicleId, 'fuel', 100.0, 'norte_taxi:spawn')   -- sem whip_fuel e recusado, e nao faz mal
        -- Marca o carro como taxi para todos os jogadores: o cliente de cada um manda-os pela porta de tras
        local ent = entityOf(netId)
        if ent ~= 0 then Entity(ent).state:set('norteTaxi', true, true) end

        local preset = ride.preset and { x = ride.preset.x, y = ride.preset.y, z = ride.preset.z, label = ride.destLabel } or nil
        TriggerClientEvent('norte_taxi:assigned', source, { ride = ride.id, netId = netId, preset = preset, pace = ride.pace })
        pushStatus(ride)
        laterIf(ride, 'approach', Config.ApproachMinutes * 60000, function() endRide(player.charId, 'stuck', true) end)
    end)

    -- O cliente criou o condutor e o ped do banco da frente: guardam-se para os apagar no fim, mesmo que o cliente caia
    Whip.core:SecureEvent('norte_taxi:driver', {
        rateLimit = false,
        params = { { 'ride', 'id' }, { 'net', 'id', 1, 65535 }, { 'role', 'enum', { 'driver', 'front' } } },
    }, function(source, player, rideId, net, role)
        local ride = rides[player.charId]
        local field = role == 'front' and 'frontNet' or 'driverNet'
        if not ride or ride.id ~= rideId or ride[field] then return false end
        local ped, veh = entityOf(net), entityOf(ride.netId)
        if ped == 0 or veh == 0 or GetEntityType(ped) ~= 1 then return false end
        if GetEntityModel(ped) ~= joaat(Config.DriverModel) then return false end
        if #(GetEntityCoords(ped) - GetEntityCoords(veh)) > 10.0 then return false end
        ride[field] = net
    end)

    -- Fases contadas pelo cliente, cada uma confirmada aqui
    Whip.core:SecureEvent('norte_taxi:stage', {
        rateLimit = 500,
        params = { { 'ride', 'id' }, { 'stage', 'enum', { 'waiting', 'boarded' } } },
    }, function(source, player, rideId, stage)
        local ride = rides[player.charId]
        if not ride or ride.id ~= rideId then return false end

        if stage == 'waiting' then
            if ride.state ~= 'approach' then return false end
            local veh = entityOf(ride.netId)
            if veh == 0 or #(GetEntityCoords(veh) - GetEntityCoords(GetPlayerPed(source))) > 80.0 then return false end
            ride.state = 'waiting'
            pushStatus(ride)
            laterIf(ride, 'waiting', (Config.WaitSeconds + 5) * 1000, function()
                -- O aviso 'boarded' pode ter chegado antes de o servidor ver o jogador sentado
                if online(ride) and isPassenger(ride.source, ride) then ride.state = 'boarded' return end
                endRide(player.charId, 'timeout')
            end)
        elseif stage == 'boarded' then
            if ride.state ~= 'waiting' then return false end
            if not isPassenger(source, ride) then return false, 'Get in the back seat of the taxi.' end
            ride.state = 'boarded'
            pushStatus(ride)
        end
    end)

    -- Destino escolhido no painel (ou mudado no GPS a meio da viagem)
    Whip.core:SecureCallback('norte_taxi:setDestination', {
        rateLimit = 1000,
        params = {
            { 'ride', 'id' },
            { 'x', 'number', -5000, 6000 },
            { 'y', 'number', -5000, 9000 },
            { 'z', 'number', -100, 1500 },
        },
    }, function(source, player, rideId, x, y, z)
        local ride = rides[player.charId]
        if not ride or ride.id ~= rideId then return false, 'This taxi is no longer yours.' end
        if ride.state == 'requested' or ride.state == 'spawning' then return false, 'The taxi is not ready yet.' end
        -- Sentado no taxi chega: a fase pode ter ficado para tras se um aviso do cliente foi recusado
        if not isPassenger(source, ride) then return false, 'You must be seated in the taxi.' end
        if not Taxi.inBounds(x, y) then return false, 'That destination is off the map.' end
        ride.dest = vector3(x, y, z)
        ride.state = 'riding'
        ride.travelled = true       -- ja viajou: um pagamento da app deixa de ser devolvido
        pushStatus(ride)
        return true
    end)

    Whip.core:SecureEvent('norte_taxi:finish', {
        rateLimit = 1000,
        params = { { 'ride', 'id' }, { 'reason', 'enum', { 'arrived', 'stopped', 'cancel', 'left', 'timeout', 'nospawn', 'stuck' } } },
    }, function(source, player, rideId, reason)
        local ride = rides[player.charId]
        if not ride or ride.id ~= rideId then return false end
        if reason == 'arrived' then
            local veh = entityOf(ride.netId)
            if not ride.dest or veh == 0 or #(GetEntityCoords(veh) - ride.dest) > 120.0 then reason = 'left' end
        end
        endRide(player.charId, reason, ride.state == 'requested')
    end)

    -- /taxi sem ritmo: o cliente mostrou a escolha e responde aqui
    Whip.core:SecureEvent('norte_taxi:call', {
        rateLimit = 2000,
        params = { { 'pace', 'enum', { 'normal', 'fast', 'superfast' } } },
    }, function(source, player, key)
        local why = cannotCall(source, player.charId)
        if why then return false, why end
        startCall(source, player, Taxi.paceIndex(key))
    end)

    -- Ritmo seguinte (tecla E) durante a viagem: um de cada vez, pago antes de mudar. O preco e o do servidor.
    Whip.core:SecureEvent('norte_taxi:boost', {
        rateLimit = 1500,
        params = { { 'ride', 'id' }, { 'level', 'id', 1, 9 } },
    }, function(source, player, rideId, level)
        local ride = rides[player.charId]
        if not ride or ride.id ~= rideId or ride.paying then return false end
        local current = ride.pace or 1
        local tier = Config.Paces[level]
        local function answer() TriggerClientEvent('norte_taxi:boost', source, ride.id, ride.pace or 1) end

        if level ~= current + 1 or not tier or not tier.upgrade then answer() return false end
        if ride.state ~= 'riding' or not isPassenger(source, ride) then
            answer()
            return false, 'You can only ask for this during the ride.'
        end

        ride.paying = true
        local price = math.max(0, math.floor(tonumber(tier.upgrade) or 0))
        local receipt, why = exports.whip_core:ChargePlayer(source, price, { reason = 'Taxi: ' .. tier.label })
        ride.paying = false

        -- ChargePlayer espera: a viagem pode ter acabado entretanto
        if rides[player.charId] ~= ride or not exports.whip_core:IsSessionCurrent(source, ride.session) then
            if receipt then exports.whip_core:RefundPlayer(receipt) end
            return false
        end
        if not receipt then
            answer()
            return false, why or 'You do not have enough money.'
        end

        ride.pace = level
        answer()
        pushStatus(ride)
        notify(source, tier.style == 'super' and ('You paid $%d. Super fast: the taxi ignores every traffic rule.'):format(price)
            or ('You paid $%d. The taxi is going faster.'):format(price), 'success')
    end)

    -- ------------------------------------------------------------ app WHIP RIDE (whip_phone)
    -- O telemovel pede em nome do recurso: app.request('quote') chega como 'norte_taxi:quote' com { args }.

    -- Onde o jogador esta, a viagem em curso, os sitios rapidos, e o preco ate ao ponto marcado (se houver)
    Whip.core:SecureCallback('norte_taxi:quote', {
        rateLimit = 250, burst = 6,
        params = { { 'args', 'any' } },
    }, function(source, player, args)
        local ped = GetPlayerPed(source)
        local pos = GetEntityCoords(ped)
        local out = {
            me = { x = pos.x, y = pos.y, heading = GetEntityHeading(ped) },
            ride = rideStatus(rides[player.charId]),
            fare = { base = Config.Fare.base, perKm = Config.Fare.perKm },
            places = Taxi.destinations(),
            arriveRadius = Config.ArriveRadius,
        }
        local p = mapPoint(args)
        if p then
            -- O preco e o tempo ate ao ponto em cada ritmo (tempo: a velocidade do ritmo a ~55%, por semaforos e curvas)
            out.paces = {}
            for i, pace in ipairs(Config.Paces) do
                local price, km = quote(source, p.x, p.y, i)
                local ms = Config.CruiseSpeed * (tonumber(pace.speed) or 1) * 0.55
                out.km = km
                out.paces[i] = { key = pace.key, label = pace.label, style = pace.style, price = price,
                    minutes = math.max(1, math.ceil(km * 1000 / ms / 60)) }
            end
        end
        return out
    end)

    -- Pede um carro ate ao ponto marcado no mapa da app: paga ja, devolvido se a viagem nao chegar a comecar.
    -- O preco e calculado aqui, a partir de onde o jogador esta agora.
    Whip.core:SecureCallback('norte_taxi:request', {
        rateLimit = 2000,
        params = { { 'args', 'any' } },
    }, function(source, player, args)
        local p = mapPoint(args)
        if not p then return false, 'Mark your destination on the map.' end
        local why = cannotCall(source, player.charId)
        if why then return false, why end

        local label = type(args.label) == 'string' and args.label:gsub('[%c<>]', ''):sub(1, 40) or ''
        if label == '' then label = 'Point on map' end
        local pace = Taxi.paceIndex(args.pace) or 1
        local price = quote(source, p.x, p.y, pace)

        local receipt, err = exports.whip_core:ChargePlayer(source, price, { reason = 'WHIP RIDE: ' .. label })
        if not receipt then return false, err or 'You do not have enough money.' end
        -- ChargePlayer espera: alguem pode ter chamado um taxi entretanto
        if not exports.whip_core:IsSessionCurrent(source, player.session) or cannotCall(source, player.charId) then
            exports.whip_core:RefundPlayer(receipt)
            return false, 'The ride could not be requested.'
        end

        startCall(source, player, pace, { dest = p, label = label, prepaid = { receipt = receipt, price = price } })
        return { price = price, label = label, pace = Taxi.pace(pace).label }
    end)

    Whip.core:SecureCallback('norte_taxi:cancel', {
        rateLimit = 1000,
        params = { { 'args', 'any' } },
    }, function(source, player)
        local ride = rides[player.charId]
        if not ride then return false, 'You have no ride.' end
        endRide(player.charId, 'cancel', ride.state == 'requested')
        return true
    end)
end)

-- Outros jogadores podem ir a boleia no taxi de alguem: so quem o chamou comeca a viagem e escolhe o destino
-- (setDestination e boost so aceitam a viagem do proprio personagem). Avisa-os disso ao entrar.
AddEventHandler('whip_core:vehicle:entered', function(e)
    if GetInvokingResource() ~= 'whip_core' or type(e) ~= 'table' or not e.source then return end
    local charId = byVehicle[e.vehicleId]
    local ride = charId and rides[charId]
    if not ride or (ride.source == e.source and online(ride)) or e.previousSeat then return end
    notify(e.source, 'You are riding along. Only the person who called this taxi can start the ride.', 'info')
end)

-- O carro foi removido por outra via (despawnAfter, sem ninguem perto): a viagem acaba
AddEventHandler('whip_core:vehicle:released', function(e)
    if GetInvokingResource() ~= 'whip_core' or type(e) ~= 'table' then return end
    local charId = byVehicle[e.vehicleId]
    if charId then endRide(charId, 'expired', true) end
end)

AddEventHandler('whip_core:player:logout', function(e)
    if GetInvokingResource() ~= 'whip_core' or type(e) ~= 'table' or not e.charId then return end
    endRide(e.charId, 'cancel', true)
end)

-- Os carros temporarios saem sozinhos quando o recurso para; os condutores sao apagados aqui
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, ride in pairs(rides) do deleteDriver(ride) end
end)

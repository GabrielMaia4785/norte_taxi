-- norte_taxi · condutor autonomo
--
-- A mesma logica dos taxis do GTA: uma unica tarefa de longo curso (TaskVehicleDriveToCoordLongrange) ate ao
-- destino, com o estilo de conducao "normal" do jogo (786603) e o condutor com perícia maxima e zero agressividade.
-- O GTA trata da estrada, das faixas, dos semaforos e dos outros carros. A tarefa so e dada de novo quando muda o
-- destino, o ritmo, ou depois de uma travagem de emergencia: dar ordens a toda a hora faz o carro hesitar.
--
-- Por cima disso, so o que o GTA faz mal:
--   1. Peoes: um cilindro na faixa a frente (do tamanho da distancia de travagem) e outro largo e curto para quem
--      vai atravessar. Perto: velocidade 0 e, se vier depressa, travagem forte. Longe: abranda.
--   2. Curvas e chegada: abranda.
--   3. Encalhado: marcha atras, depois contorna pela outra faixa, por fim salta para a frente no caminho.
--
-- Driver e global de proposito: client/main.lua usa-o.
Driver = {}

local ACT_BRAKE = 27     -- TaskVehicleTempAction: travagem forte ate o tempo acabar
local ACT_REVERSE = 3    -- TaskVehicleTempAction: trava e faz marcha atras
local TICK = 100         -- ms entre vigias
local NAV_EVERY = 500    -- ms entre decisoes de caminho

local S = nil            -- a conducao ativa, ou nil

local function now() return GetGameTimer() end

local function flat(a, b) return #(vector2(a.x, a.y) - vector2(b.x, b.y)) end

--- Onde parar perto de `ref`, na berma do lado de `side` (o jogador, ou o sitio de destino).
--- Um no de estrada do GTA fica no meio da estrada e tem um sentido (heading). Escolhe-se o sentido que deixa `side`
--- a direita do carro (conduz-se pela direita): o carro chega pela faixa desse lado e encosta nessa berma.
--- Devolve { stop, approach, fwd }: a paragem, um ponto 35 m antes dela na mesma faixa, e o sentido de chegada.
function Driver.planStop(ref, side)
    side = side or ref
    local ok, node, heading = GetClosestVehicleNodeWithHeading(ref.x, ref.y, ref.z, 1, 3.0, 0)
    if not ok or not node then return { stop = ref, center = ref } end
    local h = math.rad(heading or 0.0)
    local fwd = vector3(-math.sin(h), math.cos(h), 0.0)          -- heading 0 = norte, a crescer para a esquerda
    local right = vector3(math.cos(h), math.sin(h), 0.0)
    local lateral = (side.x - node.x) * right.x + (side.y - node.y) * right.y
    if lateral < 0.0 then fwd, right, lateral = -fwd, -right, -lateral end

    -- Ao lado de quem espera (1.6 m antes do passeio), nunca mais de 5.5 m do meio; no meio da estrada, a faixa da direita
    local off = lateral < 2.5 and 3.0 or math.max(2.0, math.min(lateral - 1.6, 5.5))
    local stop = node + right * off
    local approach = node - fwd * 35.0 + right * math.min(off, 3.0)
    return { stop = vector3(stop.x, stop.y, node.z), approach = vector3(approach.x, approach.y, node.z), fwd = fwd,
        center = vector3(ref.x, ref.y, ref.z) }
end

local function retask(s, point, speed, final)
    if final then
        TaskVehicleDriveToCoord(s.ped, s.veh, point.x, point.y, point.z, speed + 0.0, 0, s.model, s.style, 1.0, true)
    else
        TaskVehicleDriveToCoordLongrange(s.ped, s.veh, point.x, point.y, point.z, speed + 0.0, s.style, 10.0)
    end
    SetDriveTaskMaxCruiseSpeed(s.ped, speed + 0.0)
    s.needRetask = false
end

-- ---------------------------------------------------------------- vigia (peoes)

local function startProbe(s, kind)
    local cfg = Config.Safety
    local speed = GetEntitySpeed(s.veh)
    local look = math.max(cfg.minLook, speed * cfg.reaction + speed * speed / (2.0 * cfg.decel) + 3.0)
    local front = GetOffsetFromEntityInWorldCoords(s.veh, 0.0, s.halfLen + 0.4, 0.3)
    local fwd = GetEntityForwardVector(s.veh)
    -- o cilindro roda com o volante, para olhar para dentro da curva
    local steer = math.rad((GetVehicleSteeringAngle(s.veh) or 0.0) * 0.8)
    local c, si = math.cos(steer), math.sin(steer)
    local dir = vector3(fwd.x * c - fwd.y * si, fwd.x * si + fwd.y * c, fwd.z)

    local length, radius, flags
    if kind == 'narrow' then length, radius, flags = look * 1.5, cfg.radius, 4 | 8          -- peoes na faixa
    elseif kind == 'wide' then length, radius, flags = math.min(look, 14.0), cfg.crossRadius, 4 | 8
    else length, radius, flags = 9.0, cfg.radius, 2 end                                       -- 'car': carro colado a frente
    local to = front + dir * length
    return {
        handle = StartShapeTestCapsule(front.x, front.y, front.z, to.x, to.y, to.z, radius, flags, s.veh, 7),
        front = front, dir = dir, look = look, kind = kind,
    }
end

-- 'brake', 'caution' ou 'none' para o peao que o cilindro tocou
local function classify(s, p, ent, hitPos)
    if not ent or ent == 0 or ent == s.ped then return 'none' end
    local kind = GetEntityType(ent)

    if p.kind == 'car' then
        if kind == 2 and ent ~= s.veh then s.carAheadAt, s.carAhead = now(), ent end
        return 'none'
    end
    if kind ~= 1 or IsPedInAnyVehicle(ent, false) then return 'none' end

    local cfg = Config.Safety
    if p.kind == 'wide' then
        -- So conta um peao que ja esta na nossa faixa ou que caminha para ela
        local right = vector3(p.dir.y, -p.dir.x, 0.0)
        local rel = GetEntityCoords(ent) - p.front
        local lateral = rel.x * right.x + rel.y * right.y
        if math.abs(lateral) > cfg.radius + 0.6 then
            local v = GetEntityVelocity(ent)
            local towards = -(v.x * right.x + v.y * right.y) * (lateral > 0 and 1 or -1)
            if towards < 0.4 then return 'none' end
        end
    end
    s.pedAhead = true
    return #(hitPos - p.front) < p.look and 'brake' or 'caution'
end

local function readProbe(s, key)
    local p = s.probes[key]
    if not p then return end
    local status, hit, hitPos, _, ent = GetShapeTestResult(p.handle)
    if status == 1 then return end          -- ainda a correr
    s.probes[key] = nil
    local level = 'none'
    if status == 2 and (hit == 1 or hit == true) then level = classify(s, p, ent, hitPos) end
    s.levels[key] = level
end

local function watch(s, t, tick)
    s.pedAhead = false
    readProbe(s, 'narrow')
    readProbe(s, 'wide')
    readProbe(s, 'car')
    if not s.probes.narrow then s.probes.narrow = startProbe(s, 'narrow') end
    if tick % 2 == 0 and not s.probes.wide then s.probes.wide = startProbe(s, 'wide') end
    if tick % 5 == 0 and not s.probes.car and GetEntitySpeed(s.veh) < 1.0 then s.probes.car = startProbe(s, 'car') end
    if s.holding then return end

    local a, b = s.levels.narrow, s.levels.wide
    if a == 'brake' or b == 'brake' then
        s.hazardAt = t
        s.brakeSince = s.brakeSince or t
        SetDriveTaskCruiseSpeed(s.ped, 0.0)
        -- Vem depressa: travagem forte (interrompe a tarefa, que volta quando a faixa limpar)
        if GetEntitySpeed(s.veh) > 4.0 and t > s.actionUntil then
            TaskVehicleTempAction(s.ped, s.veh, ACT_BRAKE, 900)
            s.actionUntil, s.needRetask = t + 900, true
        end
        -- Peao parado a frente ha mais de 2.5 s: uma buzinadela curta, no maximo a cada 6 s
        if s.pedAhead and t - s.brakeSince > 2500 and t - s.hornAt > 6000 then
            StartVehicleHorn(s.veh, 350, `HELDDOWN`, false)
            s.hornAt = t
        end
    else
        s.brakeSince = nil
        if a == 'caution' or b == 'caution' then s.cautionAt = t end
    end
end

-- ---------------------------------------------------------------- encalhado

local function jumpAhead(s)
    -- A ir buscar o jogador: nunca salta a frente dele
    if not s.passenger and IsEntityOnScreen(s.veh) then return end
    local pos = GetEntityCoords(s.veh)
    local d = s.target - pos
    local len = #d
    if len < 1.0 then return end
    local point = pos + d / len * math.min(40.0, len)
    local ok, node, heading = GetClosestVehicleNodeWithHeading(point.x, point.y, point.z, 1, 3.0, 0)
    if not ok or not node then return end

    local fade = s.passenger and not IsScreenFadedOut()
    if fade then DoScreenFadeOut(350); Wait(400) end
    SetEntityCoords(s.veh, node.x, node.y, node.z + 0.5, false, false, false, false)
    SetEntityHeading(s.veh, heading)
    SetVehicleOnGroundProperly(s.veh)
    s.needRetask = true
    if fade then Wait(200); DoScreenFadeIn(500) end
end

local function unstick(s, t)
    local cfg = Config.Safety
    local waiting = t - s.hazardAt < 1500 or IsVehicleStoppedAtTrafficLights(s.veh)
    -- Na fila atras de um carro parado no semaforo nao esta encalhado
    if t - s.carAheadAt < 1500 and s.carAhead and DoesEntityExist(s.carAhead) and IsVehicleStoppedAtTrafficLights(s.carAhead) then
        waiting = true
    end
    if GetEntitySpeed(s.veh) > 1.0 or waiting then
        s.stillSince, s.stuckLevel = t, 0
        return
    end

    local still = (t - s.stillSince) / 1000
    if still > cfg.teleportSeconds and s.stuckLevel < 3 then
        s.stuckLevel = 3
        jumpAhead(s)
        s.stillSince, s.stuckLevel = now(), 0
    elseif still > cfg.rescueSeconds and s.stuckLevel < 2 then
        -- Contorna pela outra faixa durante 12 s
        s.stuckLevel = 2
        s.style, s.rescueUntil, s.needRetask = Taxi.StyleRescue, t + 12000, true
    elseif still > cfg.stuckSeconds and s.stuckLevel < 1 and t - s.carAheadAt > 1500 then
        -- Sem carro colado a frente (esse caso e o contorno de cima): marcha atras curta
        s.stuckLevel = 1
        TaskVehicleTempAction(s.ped, s.veh, ACT_REVERSE, 1800)
        s.actionUntil, s.needRetask = t + 1800, true
    end
end

-- ---------------------------------------------------------------- caminho e chegada

local function arrive(s)
    s.holding = true
    TaskVehicleTempAction(s.ped, s.veh, ACT_BRAKE, 2000)
    SetVehicleHandbrake(s.veh, true)
    local cb = s.onArrive
    s.onArrive = nil
    if cb then CreateThread(cb) end
end

-- Um plano novo: primeiro o ponto antes da paragem, na faixa certa; depois a paragem
local function setPlan(s, plan)
    s.plan, s.target = plan, plan.stop
    s.leg = plan.approach and 'approach' or 'stop'
    s.final, s.passes, s.needRetask, s.inArea = false, 0, true, false
end

-- Area do destino (s.area metros a volta do sitio marcado): ao entrar, encosta ja na berma da direita, 14 m a frente,
-- e conta como chegado assim que parar (ou ao fim de 7 s). Nao precisa de acertar num ponto exato.
local function enterArea(s, t)
    s.inArea, s.areaAt = true, t
    local p = Driver.planStop(GetOffsetFromEntityInWorldCoords(s.veh, 0.0, 14.0, 0.0), GetOffsetFromEntityInWorldCoords(s.veh, 8.0, 14.0, 0.0))
    s.plan.stop, s.target = p.stop, p.stop
    s.final = true
    retask(s, p.stop, Config.ArriveSpeed, true)
end

-- O carro ja vai no sentido de chegada, com a paragem a frente: pode encostar sem ir ao ponto de antes
local function aligned(s, pos)
    local f = s.plan.fwd
    if not f then return true end
    local cf = GetEntityForwardVector(s.veh)
    local ahead = (s.plan.stop.x - pos.x) * f.x + (s.plan.stop.y - pos.y) * f.y
    return cf.x * f.x + cf.y * f.y > 0.5 and ahead > 6.0
end

local function goFinal(s)
    s.final = true
    retask(s, s.plan.stop, Config.ArriveSpeed, true)
end

local function navigate(s, t)
    if s.holding then return end
    local pos = GetEntityCoords(s.veh)

    -- Ir buscar: a paragem segue o jogador se ele andar
    if s.follow and t - s.followAt > 3000 then
        s.followAt = t
        local moved = s.follow()
        if moved and moved.stop and flat(moved.stop, s.plan.stop) > 20.0 then setPlan(s, moved) end
    end

    if s.rescueUntil and t > s.rescueUntil then
        s.style, s.rescueUntil, s.needRetask = s.baseStyle, nil, true
    end

    local stop = s.plan.stop
    local dist = flat(pos, stop)

    -- Velocidade: a do ritmo, menos curva, menos chegada, menos peoes
    local speed = s.final and math.min(Config.ArriveSpeed, 2.0 + dist * 0.35) or s.speed
    local turning = math.abs(GetVehicleSteeringAngle(s.veh) or 0.0)
    if turning > 25.0 then speed = speed * 0.5 elseif turning > 12.0 then speed = speed * 0.75 end
    if not s.final and dist < 120.0 then speed = math.min(speed, Config.ArriveSpeed + dist * 0.12) end
    if t - s.cautionAt < 1500 then speed = speed * 0.4 end
    if t - s.hazardAt < 600 then speed = 0.0 end
    SetDriveTaskCruiseSpeed(s.ped, math.max(speed, t - s.hazardAt < 600 and 0.0 or 1.5))

    unstick(s, t)
    if t < s.actionUntil then return end     -- a travar ou em marcha atras: a tarefa espera

    -- Dentro da area do destino: encosta e chega
    if s.area and s.plan.center then
        if not s.inArea and flat(pos, s.plan.center) <= s.area then return enterArea(s, t) end
        if s.inArea then
            local slow = GetEntitySpeed(s.veh) < 0.6 and t - s.areaAt > 1200
            if slow or t - s.areaAt > 7000 or flat(pos, s.plan.stop) < 3.5 then return arrive(s) end
            if s.needRetask then retask(s, s.plan.stop, Config.ArriveSpeed, true) end
            return
        end
    end

    -- Ultimos metros: encosta na berma e para
    if s.final then
        if dist < 3.5 or (dist < 12.0 and GetEntitySpeed(s.veh) < 0.5 and t - s.stillSince > 1500) then
            return arrive(s)
        end
        -- Passou a paragem sem parar: da a volta pelo ponto de antes (duas vezes no maximo, depois para onde estiver)
        local f = s.plan.fwd
        if f and dist > 8.0 and (stop.x - pos.x) * f.x + (stop.y - pos.y) * f.y < -3.0 then
            s.passes = s.passes + 1
            if s.passes > 2 then return arrive(s) end
            s.final, s.leg, s.needRetask = false, 'approach', true
        elseif s.needRetask then
            retask(s, stop, Config.ArriveSpeed, true)
            return
        else
            return
        end
    end

    if s.leg == 'approach' then
        if flat(pos, s.plan.approach) < 15.0 or (dist < s.arrive and aligned(s, pos)) then return goFinal(s) end
    elseif dist <= s.arrive then
        return goFinal(s)
    end

    if s.needRetask then retask(s, s.leg == 'approach' and s.plan.approach or stop, s.speed, false) end
end

-- ---------------------------------------------------------------- ciclo

local function run(s)
    local tick = 0
    local lastNav = 0
    while S == s do
        if not DoesEntityExist(s.veh) or not DoesEntityExist(s.ped) or IsEntityDead(s.ped)
            or not NetworkHasControlOfEntity(s.ped) then
            S = nil
            if s.onLost then s.onLost() end
            return
        end
        local t = now()
        tick = tick + 1
        watch(s, t, tick)
        if t - lastNav >= NAV_EVERY then
            lastNav = t
            navigate(s, t)
        end
        Wait(TICK)
    end
end

--- Conduz `veh` (com `ped` ao volante) ate a paragem de opts.plan (Driver.planStop).
--- opts: plan, speed m/s, style (drivingStyle), arrive m, area m (raio da area de chegada a volta de plan.center,
---       ou nil para parar no ponto exato), passenger bool (ha alguem dentro),
---       follow fun(): plan|nil (nova paragem, a cada 3 s), onArrive fun(), onLost fun()
function Driver.start(veh, ped, opts)
    local _, max = GetModelDimensions(GetEntityModel(veh))
    local t = now()
    local style = opts.style or Taxi.StyleNormal
    local s = {
        veh = veh, ped = ped, model = GetEntityModel(veh), halfLen = max.y,
        speed = opts.speed, arrive = opts.arrive, area = opts.area, passenger = opts.passenger,
        follow = opts.follow, followAt = t, onArrive = opts.onArrive, onLost = opts.onLost,
        style = style, baseStyle = style, holding = false,
        probes = {}, levels = {}, actionUntil = 0, hazardAt = 0, cautionAt = 0, hornAt = 0,
        carAheadAt = 0, stillSince = t, stuckLevel = 0,
    }
    setPlan(s, opts.plan)
    SetVehicleHandbrake(veh, false)
    SetEntityLoadCollisionFlag(veh, true)     -- longe do jogador o carro continua a ter chao debaixo
    S = s
    CreateThread(function() run(s) end)
end

--- Muda a paragem de uma conducao em curso (um plano de Driver.planStop)
function Driver.setTarget(plan)
    local s = S
    if not s then return end
    setPlan(s, plan)
    s.holding = false
    SetVehicleHandbrake(s.veh, false)
end

--- Muda o ritmo: velocidade maxima e estilo de conducao
function Driver.setPace(speed, style)
    local s = S
    if not s then return end
    s.speed, s.baseStyle = speed, style
    if not s.rescueUntil then s.style = style end
    SetDriveTaskDrivingStyle(s.ped, s.style)
    SetDriveTaskMaxCruiseSpeed(s.ped, speed + 0.0)
    s.needRetask = true
end

--- Para ja onde esta e fica parado (a conducao termina)
function Driver.hold(veh, ped)
    S = nil
    if DoesEntityExist(veh) and DoesEntityExist(ped) then
        TaskVehicleTempAction(ped, veh, ACT_BRAKE, 2000)
        SetVehicleHandbrake(veh, true)
    end
end

--- Vai-se embora a passear pela cidade
function Driver.wander(veh, ped)
    S = nil
    if DoesEntityExist(veh) and DoesEntityExist(ped) then
        SetVehicleHandbrake(veh, false)
        TaskVehicleDriveWander(ped, veh, 12.0, Taxi.StyleNormal)
    end
end

function Driver.stop() S = nil end

function Driver.isDriving() return S ~= nil end

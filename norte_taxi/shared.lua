-- Partilhado pelos dois lados. Taxi e global de proposito: client/driver.lua, client/main.lua e server.lua leem-no.
Taxi = {}

-- Limites do mapa de Los Santos e Blaine County: um destino fora disto e recusado
Taxi.Bounds = { minX = -4500.0, maxX = 5000.0, minY = -4500.0, maxY = 8500.0 }

function Taxi.inBounds(x, y)
    local b = Taxi.Bounds
    return x >= b.minX and x <= b.maxX and y >= b.minY and y <= b.maxY
end

-- Bits do drivingStyle das tarefas de conducao do GTA
local FLAG = {
    StopForCars = 1,
    StopForPeds = 2,
    SwerveAroundAllCars = 4,
    SteerAroundStationaryCars = 8,
    SteerAroundPeds = 16,
    SteerAroundObjects = 32,
    StopAtLights = 128,
    GoOffRoadWhenAvoiding = 256,
    DriveIntoOncomingTraffic = 512,
    AdjustCruiseSpeedBasedOnRoadSpeed = 16384,
    UseShortCutLinks = 262144,
    ChangeLanesAroundObstructions = 524288,
}

local function style(names)
    local v = 0
    for _, n in ipairs(names) do v = v | FLAG[n] end
    return v
end

-- O estilo "normal" do GTA (786603), o mesmo dos taxis e condutores das missoes do jogo:
-- para em semaforos, peoes e carros, contorna carros parados e objetos, muda de faixa para passar bloqueios
Taxi.StyleNormal = style({
    'StopForCars', 'StopForPeds', 'SteerAroundStationaryCars', 'SteerAroundObjects',
    'StopAtLights', 'UseShortCutLinks', 'ChangeLanesAroundObstructions',
})

-- Ritmo Normal: o de cima, e tambem o limite de velocidade de cada estrada
Taxi.StyleLimits = Taxi.StyleNormal | FLAG.AdjustCruiseSpeedBasedOnRoadSpeed

-- Ritmo Super fast: sem regras. Passa vermelhos, usa a contramao, ultrapassa e contorna tudo. So para para peoes
Taxi.StyleSuper = style({
    'StopForPeds', 'SwerveAroundAllCars', 'SteerAroundStationaryCars', 'SteerAroundPeds', 'SteerAroundObjects',
    'DriveIntoOncomingTraffic', 'UseShortCutLinks', 'ChangeLanesAroundObstructions',
})

local PACE_STYLE = { normal = 'StyleLimits', fast = 'StyleNormal', super = 'StyleSuper' }

-- O ritmo n (1 Normal, 2 Fast, 3 Super fast), ou o primeiro
function Taxi.pace(n)
    return Config.Paces[n] or Config.Paces[1]
end

-- O numero do ritmo com esta key ('normal', 'fast', 'superfast'), ou nil
function Taxi.paceIndex(key)
    for i, p in ipairs(Config.Paces) do
        if p.key == key then return i end
    end
end

function Taxi.paceStyle(n)
    return Taxi[PACE_STYLE[Taxi.pace(n).style] or 'StyleNormal']
end

-- Desencalhar: pode usar a faixa contraria e sair da estrada para contornar um bloqueio. Nunca deixa de parar para peoes
Taxi.StyleRescue = style({
    'StopForPeds', 'SwerveAroundAllCars', 'SteerAroundStationaryCars', 'SteerAroundPeds', 'SteerAroundObjects',
    'GoOffRoadWhenAvoiding', 'DriveIntoOncomingTraffic', 'ChangeLanesAroundObstructions',
})

-- Destinos rapidos validos, como { label, x, y, z }
function Taxi.destinations()
    local out = {}
    for _, d in ipairs(Config.Destinations or {}) do
        local c = d and d.coords
        if type(d.label) == 'string' and d.label ~= '' and c and c.x and c.y then
            out[#out + 1] = { label = d.label, x = c.x + 0.0, y = c.y + 0.0, z = (c.z or 0.0) + 0.0 }
        end
    end
    return out
end

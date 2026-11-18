-- Valores por defeito. Os editaveis tambem estao em /whip -> Settings -> Norte Taxi (settings.lua),
-- e o que la se guarda e escrito por cima destes.
Config = {}

Config.Model = 'vivanite2'              -- carro do taxi
Config.DriverModel = 's_m_m_gentransport'
Config.HideDriver = true                -- condutor invisivel: o carro parece andar sozinho

-- Pintura WHIB (stream/vivanite2_livery1.yft): o slot de modificacao 48, indice 0, com o branco perola por baixo.
-- O ficheiro troca a primeira livery de TODOS os vivanite2 do servidor. Precisa da game build 3751 ou mais recente.
Config.Livery = { modType = 48, modIndex = 0, color = { 242, 243, 233 } }

-- Chamada
Config.SpawnMin = 90.0                  -- metros: o taxi aparece numa rua entre estas distancias do jogador
Config.SpawnMax = 220.0
Config.CooldownSeconds = 20             -- entre chamadas do mesmo personagem
Config.WaitSeconds = 120                -- tempo que o taxi espera parado pelo passageiro
Config.ApproachMinutes = 5              -- sem chegar ao jogador neste tempo, a chamada e cancelada
Config.MaxRideMinutes = 30              -- o carro desaparece ao fim disto, aconteca o que acontecer
Config.LeaveSeconds = 20                -- depois da viagem, o taxi vai-se embora e desaparece ao fim disto

-- Condução (m/s: 1 m/s = 3.6 km/h)
Config.CruiseSpeed = 19.0               -- velocidade maxima em cidade (~68 km/h); a estrada pode baixar
Config.PickupSpeed = 14.0               -- a caminho do jogador
Config.ArriveSpeed = 6.0                -- nos ultimos metros
Config.ArriveDistance = 30.0            -- a esta distancia do destino comeca a encostar
Config.ArriveRadius = 25.0              -- area do destino: ao entrar nela o taxi encosta logo e a viagem conta como chegada
Config.PickupRadius = 20.0              -- area a volta do jogador: ao entrar nela o taxi encosta, para e abre as portas

-- Preco da app WHIP RIDE (whip_phone): base + km x perKm, arredondado para cima, nunca abaixo de min.
-- Os km sao a linha reta ate ao destino x roadFactor (a estrada e mais comprida). /taxi continua sem custo.
Config.Fare = {
    base = 5,
    perKm = 1.0,
    min = 5,
    roadFactor = 1.3,
}

-- Ritmos, escolhidos ao chamar (/taxi ou WHIP RIDE). Valem desde a vinda ate ao jogador.
--   speed: multiplica PickupSpeed na vinda e CruiseSpeed na viagem.
--   style: 'normal' cumpre as regras e os limites de cada estrada; 'fast' cumpre as regras sem os limites;
--          'super' nao cumpre nenhuma (vermelhos, contramao, ultrapassa tudo), e so para para peoes.
--   fare: multiplica o preco na app. upgrade: o que custa passar a este ritmo durante a viagem (tecla E).
Config.Paces = {
    { key = 'normal', label = 'Normal', speed = 1.0, style = 'normal', fare = 1.0 },
    { key = 'fast', label = 'Fast', speed = 1.45, style = 'fast', fare = 1.5, upgrade = 20 },
    { key = 'superfast', label = 'Super fast', speed = 1.9, style = 'super', fare = 2.2, upgrade = 50 },
}

-- Inteligencia de seguranca
Config.Safety = {
    reaction = 0.7,                     -- s de reacao somados a distancia de travagem
    decel = 6.0,                        -- m/s2 de travagem confortavel
    minLook = 8.0,                      -- metros minimos que olha para a frente
    radius = 1.15,                      -- largura da faixa vigiada (raio do cilindro), m
    crossRadius = 2.6,                  -- faixa larga, so para peoes a atravessar
    stuckSeconds = 8,                   -- parado sem motivo: marcha atras
    rescueSeconds = 25,                 -- continua preso: contorna pela outra faixa
    teleportSeconds = 50,               -- ultimo recurso: salta para a frente no caminho
}

-- Fallback se a lista em /whip estiver vazia
Config.Destinations = {
    { label = 'Legion Square', coords = vector3(195.0, -934.0, 30.7) },
    { label = 'Pillbox Hospital', coords = vector3(298.6, -584.5, 43.3) },
    { label = 'Mission Row Police', coords = vector3(428.0, -981.0, 30.7) },
    { label = 'LS International Airport', coords = vector3(-1037.0, -2737.0, 20.2) },
    { label = 'Vespucci Beach', coords = vector3(-1223.0, -1491.0, 4.4) },
    { label = 'Sandy Shores', coords = vector3(1961.0, 3740.0, 32.3) },
    { label = 'Paleto Bay', coords = vector3(-130.0, 6410.0, 31.4) },
}

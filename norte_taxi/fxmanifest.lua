fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'norte_taxi'
author 'Norte Roleplay'
description 'Taxi autonomo para WHIP: /taxi chama um carro sem condutor que vem buscar o jogador e o leva ao destino marcado'
version '0.1.0'

dependency 'whip_core'
whip_requires '1.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/tokens.css',
    'html/style.css',
    'html/script.js',
    'html/phone/whipride.js',      -- app WHIP RIDE, carregada pelo whip_phone (opcional)
}

shared_scripts {
    '@whip_core/lib/satellite.lua',
    'config.lua',
    'shared.lua',
    'settings.lua',
}

server_script 'server.lua'

client_scripts {
    'client/driver.lua',
    'client/main.lua',
}

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Mazus / MZ Core'
description 'MZ Props - sistema de props persistentes salvos no banco'
version '0.2.0'

shared_scripts {
    'shared/config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/database.lua',
    'server/main.lua'
}

dependency 'oxmysql'

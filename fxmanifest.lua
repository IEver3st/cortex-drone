fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'cortex-drone'
author 'GSDMODS/CORTEX'
description 'Deployable camera, police and FPV drones with a gimbal camera, signal, battery and return-to-home'
version '1.0.0'

dependencies { 'cortex-lib', '/onesync' }

shared_scripts { '@cortex-lib/init.lua', 'config.lua', 'shared/locale.lua', 'shared/domain.lua', 'shared/validate.lua' }
client_scripts {
    '@cortex-lib/presentation-client.lua',
    '@cortex-lib/imports/volumetric/client.lua',
    'client/profile.lua',
    'client/util.lua',
    'client/volume.lua',
    'client/hud.lua',
    'client/cinematic.lua',
    'client/pilot.lua',
    'client/autopilot.lua',
    'client/rig.lua',
    'client/swap.lua',
    'client/main.lua',
    'client/remote.lua',
}
server_scripts {
    'server/bridge.lua',
    'server/audit.lua',
    'server/battery.lua',
    'server/main.lua',
    'server/lookup.lua',
    'server/admin.lua',
}

ui_page 'web/dist/index.html'
files { 'web/dist/index.html', 'web/dist/assets/*', 'web/dist/barlow-condensed-OFL.txt', 'locales/*.json', 'data/*.meta', 'assets/cue/*.png' }

data_file 'HANDLING_FILE' 'data/handling.meta'
data_file 'VEHICLE_METADATA_FILE' 'data/vehicles.meta'
data_file 'VEHICLE_VARIATION_FILE' 'data/carvariations.meta'
data_file 'DLC_ITYP_REQUEST' 'stream/cxdrone_battery.ytyp'

escrow_ignore { 'config.lua', 'locales/*.json', 'shared/locale.lua', 'server/bridge.lua' }

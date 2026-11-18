-- Pagina de configuracao em /whip -> Settings -> Norte Taxi.
-- Os valores guardados sao escritos por cima de Config (config.lua), nos dois lados.

local MODEL = '^[%w_]+$'

Whip.configPage({
    label = 'Norte Taxi',
    groups = {
        { label = 'Car', settings = {
            { key = 'Model', type = 'string', maxLen = 32, pattern = MODEL, patternWhy = 'GTA model name',
              label = 'Taxi model' },
            { key = 'DriverModel', type = 'string', maxLen = 32, pattern = MODEL, patternWhy = 'GTA model name',
              label = 'Driver model' },
            { key = 'HideDriver', type = 'bool', label = 'Invisible driver',
              help = 'On: the car looks like it drives itself' },
        } },
        { label = 'Calling', settings = {
            { key = 'SpawnMin', type = 'number', min = 40, max = 400, step = 10, unit = 'm', label = 'Spawns at least' },
            { key = 'SpawnMax', type = 'number', min = 60, max = 500, step = 10, unit = 'm', label = 'Spawns at most' },
            { key = 'CooldownSeconds', type = 'int', min = 0, max = 600, unit = 's', label = 'Time between calls' },
            { key = 'WaitSeconds', type = 'int', min = 30, max = 600, step = 10, unit = 's', label = 'Waits for passenger' },
            { key = 'ApproachMinutes', type = 'int', min = 1, max = 15, unit = 'min', label = 'Max time to arrive' },
            { key = 'MaxRideMinutes', type = 'int', min = 5, max = 120, unit = 'min', label = 'Max car lifetime' },
        } },
        { label = 'Driving', settings = {
            { key = 'CruiseSpeed', type = 'number', min = 8, max = 40, step = 0.5, unit = 'm/s', label = 'Top speed',
              help = '1 m/s = 3.6 km/h' },
            { key = 'PickupSpeed', type = 'number', min = 6, max = 40, step = 0.5, unit = 'm/s', label = 'Pickup speed' },
            { key = 'ArriveSpeed', type = 'number', min = 2, max = 12, step = 0.5, unit = 'm/s', label = 'Pull over speed' },
            { key = 'PickupRadius', type = 'number', min = 5, max = 60, step = 1, unit = 'm', label = 'Pickup area',
              help = 'Around the player: the taxi stops and opens its doors when it gets inside.' },
            { key = 'ArriveRadius', type = 'number', min = 5, max = 80, step = 1, unit = 'm', label = 'Arrival area',
              help = 'Around the destination: the ride ends when the taxi gets inside.' },
        } },
        { label = 'WHIP RIDE fare (phone app)', settings = {
            { key = 'Fare.base', type = 'number', min = 0, max = 10000, step = 1, unit = '$', label = 'Base fare' },
            { key = 'Fare.perKm', type = 'number', min = 0, max = 1000, step = 0.1, unit = '$', label = 'Price per km' },
            { key = 'Fare.min', type = 'number', min = 0, max = 10000, step = 1, unit = '$', label = 'Minimum fare' },
            { key = 'Fare.roadFactor', type = 'number', min = 1, max = 2, step = 0.05, label = 'Road length factor',
              help = 'Straight line distance x this = the km that are charged' },
        } },
        { label = 'Paces (chosen when calling)', settings = {
            { key = 'Paces.1.speed', type = 'number', min = 0.5, max = 2, step = 0.05, label = 'Normal: speed x',
              help = 'Obeys every rule and each road speed limit' },
            { key = 'Paces.2.speed', type = 'number', min = 1, max = 3, step = 0.05, label = 'Fast: speed x',
              help = 'Obeys the rules, ignores road speed limits' },
            { key = 'Paces.2.fare', type = 'number', min = 1, max = 5, step = 0.1, label = 'Fast: fare x' },
            { key = 'Paces.2.upgrade', type = 'int', min = 0, max = 100000, unit = '$', label = 'Fast: upgrade price (E)' },
            { key = 'Paces.3.speed', type = 'number', min = 1, max = 3.5, step = 0.05, label = 'Super fast: speed x',
              help = 'No rules: runs red lights and drives on the wrong side. Still stops for people' },
            { key = 'Paces.3.fare', type = 'number', min = 1, max = 8, step = 0.1, label = 'Super fast: fare x' },
            { key = 'Paces.3.upgrade', type = 'int', min = 0, max = 100000, unit = '$', label = 'Super fast: upgrade price (E)' },
        } },
        { label = 'Destinations', settings = {
            { key = 'Destinations', type = 'records', label = 'Quick destinations',
              help = 'Shown in the taxi panel list. Here uses where you stand',
              fields = {
                  { key = 'label', type = 'string', maxLen = 40, label = 'Name' },
                  { key = 'coords', type = 'vec3', here = true, label = 'Position' },
              } },
        } },
    },
})

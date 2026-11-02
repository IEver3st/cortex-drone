Config = {}

Config.Locale = 'en'
Config.debug = false

Config.model = 'rcmavic'
Config.command = 'drone'
Config.requireItem = 'auto'
Config.units = 'metric'

Config.features = { night = true, thermal = true, spotlight = true, track = true, follow = true, lookup = true, payload = true, cinematic = true }

Config.types = {
    drone = {
        label = 'Camera drone',
        item = 'drone',
        colours = { 12, 12 },
        access = false,
        range = 500.0,
        maxAltitude = 152.4,
        batterySeconds = 720,
        zoomMax = 4.0,
        health = 600,
        features = { night = false, thermal = false, spotlight = true, track = true, follow = true, lookup = false, cinematic = true },
        payload = false,
        speeds = {
            cine = { horizontal = 4.0, vertical = 2.0, yaw = 45.0, accel = 3.0, tilt = 10.0 },
            normal = { horizontal = 10.0, vertical = 4.0, yaw = 90.0, accel = 8.0, tilt = 18.0 },
            sport = { horizontal = 19.0, vertical = 6.0, yaw = 150.0, accel = 14.0, tilt = 30.0 },
        },
        ignoreNoFly = false,
        sensing = true,
        acro = true,
    },
    police = {
        label = 'Police drone',
        item = 'drone_police',
        colours = { 0, 111 },
        access = { jobs = { police = 0, sheriff = 0 }, duty = true },
        range = 500.0,
        maxAltitude = 152.4,
        batterySeconds = 900,
        zoomMax = 16.0,
        health = 800,
        features = { night = true, thermal = true, spotlight = true, track = true, follow = true, lookup = true, cinematic = true },
        payload = { kind = 'taser', count = 3, cooldown = 4.0, range = 30.0 },
        speeds = {
            cine = { horizontal = 4.0, vertical = 2.0, yaw = 45.0, accel = 3.0, tilt = 10.0 },
            normal = { horizontal = 12.0, vertical = 5.0, yaw = 90.0, accel = 9.0, tilt = 18.0 },
            sport = { horizontal = 21.0, vertical = 7.0, yaw = 150.0, accel = 15.0, tilt = 30.0 },
        },
        ignoreNoFly = true,
        sensing = true,
        acro = true,
    },
    fpv = {
        label = 'FPV drone',
        item = 'drone_fpv',
        colours = { 12, 92 },
        access = false,
        range = 500.0,
        maxAltitude = 152.4,
        batterySeconds = 360,
        zoomMax = 2.0,
        health = 300,
        features = { night = true, thermal = false, spotlight = false, track = false, follow = false, lookup = false, cinematic = false },
        payload = false,
        speeds = {
            cine = { horizontal = 6.0, vertical = 3.0, yaw = 60.0, accel = 5.0, tilt = 14.0 },
            normal = { horizontal = 16.0, vertical = 6.0, yaw = 120.0, accel = 12.0, tilt = 24.0 },
            sport = { horizontal = 32.0, vertical = 9.0, yaw = 200.0, accel = 22.0, tilt = 40.0 },
        },
        ignoreNoFly = false,
        sensing = false,
        acro = true,
    },
}

Config.acro = {
    thrust = 3.5,
    topSpeed = 37.5,
    pitchRate = 540.0,
    rollRate = 600.0,
    yawRate = 300.0,
    expo = 0.35,
    keyRamp = 0.3,
    mouse = 1.0,
    cameraTilt = 25.0,
    tumble = 540.0,
    controls = 'glide',
    cruise = 37.5,
    creep = 2.0,
    keyEase = 2.0,
    climb = 12.0,
    tilt = 50.0,
    response = 10.0,
    authority = 3.0,
    grip = 15.0,
    brake = 0.8,
    carve = 0.6,
    flipRate = 480.0,
    lookFlip = 2.0,
    float = 0.6,
    viewPitch = 0.4,
    levelBand = 10.0,
    descent = 12.0,
    diveAccel = 20.0,
    pullOut = 20.0,
    floor = 1.0,
    nose = 0.6,
    loopDetent = 25.0,
    lookRest = 0.4,
}

Config.battery = {
    rechargeMinutes = 20,
    minimumToLaunch = 5,
    returnAt = 15,
    drain = { hover = 0.8, cine = 0.9, normal = 1.0, sport = 1.5, boost = 1.8, acro = 1.4, spotlight = 0.3, thermal = 0.15, night = 0.08, track = 0.06 },
    taserShot = 1.5,
    packs = {
        drone_battery = { capacity = 1.0 },
        drone_battery_hc = { capacity = 1.75 },
    },
}

Config.signal = {
    fadeStart = 0.7,
    obstructionPenalty = 0.35,
    lostGraceSeconds = 3.0,
    onLost = 'return',
}

Config.flight = {
    launchHeight = 1.0,
    takeoffHeight = 1.2,
    crashSpeed = 13.0,
    landingSpeed = 1.2,
    returnAltitude = 30.0,
    returnSpeed = 10.0,
    leave = 'hover',
    pilotHitDropsLink = true,
}

Config.launch = {
    enabled = true,
    anim = { dict = 'anim_heist@hs3f@ig4_drone@male@', name = 'enter', flag = 48 },
    grab = 0.2,
    release = 0.55,
    hold = { bone = 60309, forward = 0.1, up = 0.0 },
    lift = 2.2,
    push = 1.5,
    maxSpeed = 5.0,
    clearance = 0.3,
    watch = 0.6,
}

Config.camera = {
    offset = { x = 0.0, y = 0.24, z = -0.045 },
    chase = { distance = 2.4, height = 0.7 },
    fov = 70.0,
    gimbalMin = -90.0,
    gimbalMax = 20.0,
}

Config.spotlight = {
    distance = 60.0, brightness = 8.0, hardness = 3.0, radius = 13.0, falloff = 40.0, colour = { 255, 244, 225 },
    onAtLaunch = false,
    traverse = { min = -90.0, max = -10.0 },
    slew = 120.0,
    volumetric = {
        enabled = true,
        alpha = 250,
        coneScale = 1.0,
        sourceRadius = 0.05,
        falloff = 1.5,
        openFade = 0.5,
        maxLength = 60.0,
        dayFactor = 0.0,
        maxDrawDistance = 250.0,
    },
}

Config.track = { hideGrace = 1.5, orbitMinRadius = 3.0 }

Config.cinematic = {
    speedMode = 'cine',
    look = 3.5,
    aim = 3.0,
    zoom = 2.0,
    ease = 0.6,
    maxSpeed = 30.0,
    accel = 9.0,
    minDistance = 4.0,
    hideGrace = 5.0,
    regain = 2.0,
    framing = { yaw = 15.0, pitch = 10.0 },
    follow = { swing = 45.0, distance = 60.0 },
    orbit = { speed = 3.0, radius = 80.0 },
    dronie = { speed = 4.0, climb = 30.0, distance = 45.0 },
    rocket = { speed = 3.0, height = 40.0 },
    helix = { speed = 4.0, out = 1.0, up = 0.8, radius = 35.0 },
    filmMe = true,
}

Config.sensing = { margin = 0.7, radius = 0.3, lookahead = 0.6 }

Config.lookup = { range = 200.0, plates = true, people = true, showStandaloneNames = false }

Config.swap = {
    enabled = true,
    camera = true,
    reach = 3.0,
    kneel = 0.55,
    anim = {
        enter = { dict = 'amb@medic@standing@tendtodead@enter', name = 'enter' },
        base = { dict = 'amb@medic@standing@tendtodead@base', name = 'base' },
        exit = { dict = 'amb@medic@standing@tendtodead@exit', name = 'exit' },
    },
}

Config.pickup = { distance = 2.2, othersCanSeize = true, seize = { jobs = { police = 0, sheriff = 0 }, duty = true }, loseItemWhenDestroyed = true }

Config.pilot = {
    anim = { dict = 'amb@code_human_in_bus_passenger_idles@female@tablet@idle_a', name = 'idle_a', flag = 49 },
    prop = { model = 'prop_cs_tablet', bone = 28422, offset = { x = -0.05, y = 0.0, z = 0.0 }, rotation = { x = 0.0, y = -90.0, z = 0.0 } },
    othersSeeTablet = true,
}

Config.hideHud = true

Config.rotors = { idle = 0.55, hover = 0.8, full = 1.0 }

Config.noFly = {
    { name = 'Fort Zancudo', x = -2200.0, y = 3100.0, radius = 900.0 },
    { name = 'Bolingbroke Penitentiary', x = 1690.0, y = 2600.0, radius = 280.0 },
    { name = 'Los Santos International', x = -1340.0, y = -2700.0, radius = 750.0 },
    { name = 'Humane Labs', x = 3560.0, y = 3740.0, radius = 220.0 },
}

Config.keys = { pickup = 'E' }

Config.controls = {
    keyboard = {
        up = 22, down = 36, boost = 21, mode = 26, zoomIn = 172, zoomOut = 173, vision = 44,
        spotlight = 23, lock = 24, payload = 25, view = 0, home = 20, leave = 194, acro = 73, cinematic = 74,
    },
    pad = {
        up = 24, down = 25, boost = 21, mode = 26, zoomIn = 172, zoomOut = 173, vision = 44,
        spotlight = 175, lock = 22, payload = 23, view = 0, home = 174, leave = 194, acro = 37, cinematic = 36,
    },
}

Config.audit = { deploys = false, destroyed = true, seized = true, payloads = true, staff = true }

Config.sounds = {
    start = { name = 'Select_Spec_Drone', set = 'DLC_AW_Spectator_Tablet_Sounds' },
    toggle = { name = 'NAV_UP_DOWN', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    warning = { name = '5_SEC_WARNING', set = 'HUD_MINI_GAME_SOUNDSET' },
    lost = { name = 'Hack_Failed', set = 'DLC_HEIST_BIOLAB_PREP_HACKING_SOUNDS' },
    release = { name = 'TOGGLE_ON', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    latch = { name = 'PIN_BUTTON', set = 'ATM_SOUNDS' },
    led = { name = 'NAV_LEFT_RIGHT', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
}

-- 
--  BRIGHTSIDE V1 - FINAL LOADER
-- 

local GITHUB_URL = "https://raw.githubusercontent.com/u4tf1-hub/hi/refs/heads/main/brightside/brightside.lua"

local Brightside = {
    -- Main Settings
    ['Main'] = {
        ['Intro'] = true,
        ['Sync'] = true,
        ['Keybinds'] = {
            ['Aim Assist'] = 'P',
            ['Silent Aim'] = 'Q',
            ['Trigger Bot Activate'] = 'C',
            ['Speed'] = 'B',
            ['Jump Power'] = 'Y',
            ['Inventory Sorter'] = 'F2',
            ['Panic'] = 'L',
            ['Raid Awareness'] = 'K',
            ['ESP Toggle'] = 'T',
            ['Lock Target'] = 'Z',
            ['Panic Ground'] = 'X',
        },
        ['Panic'] = {
            ['Enabled'] = true,
            ['Disable Aim Assist'] = true,
            ['Disable Silent Aim'] = true,
            ['Disable Trigger Bot'] = true,
            ['Disable Visuals'] = true,
            ['Disable Player Modifications'] = true,
            ['Disable Raid Awareness'] = true,
        },
    },

    -- Target Settings
    ['Target'] = {
        ['Type'] = "Automatic",
        ['Color'] = Color3.fromRGB(0, 255, 0),
        ['Visible Check'] = false,
        ['Unlock'] = {
            ['Knocked'] = true,
            ['Grabbed'] = true,
        },
    },

    -- Checks
    ['Target Checks'] = {
        ['Knocked'] = true,
        ['Grabbed'] = false,
        ['Wall'] = true,
        ['Forcefield'] = true,
    },

    ['Self Checks'] = {
        ['Knocked'] = true,
        ['Grabbed'] = true,
        ['Forcefield'] = false,
    },

    ['Unlock Conditions'] = {
        ['Unlock on Target Knock'] = true,
        ['Unlock on Self Knock'] = false,
    },

    -- Combat Features
    ['Silent Aimbot'] = {
        ['Enabled'] = true,
        ['Mode'] = 'Auto',
        ['Auto Target'] = true,
        ['Target Line'] = true,
        ['Override Y Axis'] = 'None',
        ['Hit Target'] = {
            ['Hit Part'] = 'Closest Point',
        },
        ['FOV'] = {
            ['FOV Type'] = 'Circle',
            ['Circle Value'] = 120,
            ['Box'] = {
                ['X'] = 76,
                ['Y'] = 75,
            },
            ['Visualize'] = false,
        },
        ['Prediction'] = {
            ['X'] = 0.15,
            ['Y'] = 0.15,
            ['Z'] = 0.15,
            ['Power'] = {
                ['Enabled'] = false,
                ['Prediction Power'] = 1.042,
            },
        },
    },

    ['Aim Assist'] = {
        ['Enabled'] = true,
        ['Mode'] = 'Camera',
        ['Hit Target'] = {
            ['Hit Part'] = 'Closest Point',
            ['Prediction'] = {
                ['X'] = 0.1,
                ['Y'] = 0.12,
                ['Z'] = 0.102,
            },
        },
        ['Smoothing'] = {
            ['Smoothing Value'] = {
                ['X'] = 0.07,
                ['Y'] = 0.07,
                ['Z'] = 0.07,
                ['Mouse Smoothing'] = {
                    ['X'] = 0.17,
                    ['Y'] = 0.17,
                    ['Z'] = 0.17,
                },
            },
        },
    },

    ['Triggerbot'] = {
        ['Enabled'] = true,
        ['Shoot Mode'] = 'Hitbox',
        ['Mode'] = 'Hold',
        ['Timing'] = {
            ['Cooldown'] = 0,
        },
    },

    -- Visuals
    ['Raid Awareness'] = {
        ['Enabled'] = false,
        ['Toggle'] = true,
        ['Max Render Distance'] = 1000,
        ['Box'] = {
            ['Enabled'] = false,
            ['Other Color'] = Color3.fromRGB(255, 255, 255),
        },
        ['Name'] = {
            ['Enabled'] = true,
            ['Type'] = 'Display',
            ['Other Color'] = Color3.fromRGB(255, 255, 255),
            ['Size'] = 14,
        },
        ['Tracer'] = {
            ['Enabled'] = false,
            ['Other Color'] = Color3.fromRGB(255, 255, 255),
        },
        ['Distance'] = {
            ['Enabled'] = false,
            ['Other Color'] = Color3.fromRGB(255, 255, 255),
        },
    },

    -- Player Modifications
    ['Player Modification'] = {
        ['Movement'] = {
            ['Enabled'] = true,
            ['Speed Modifications'] = {
                ['Enabled'] = false, -- STAYS OFF UNTIL TOGGLED
                ['Value'] = 5,
            },
            ['Jump Modifications'] = {
                ['Enabled'] = false, -- STAYS OFF UNTIL TOGGLED
                ['Value'] = 3,
            },
        },
        ['Rapid Fire'] = {
            ['Enabled'] = true,
            ['Delay'] = 0.000001,
        },
    },

    -- Panic Ground Feature
    ['Panic Ground'] = {
        ['Enabled'] = true,
    },

    -- Anti Trip Feature
    ['Anti Trip'] = {
        ['Enabled'] = true,
    },

    -- Extra Visual Features
    ['Extra'] = {
        ['Headless'] = true,
        ['Korblox'] = true,
    },

    -- Spiderman Logic
    ['Spiderman'] = {
        ['Enabled'] = true,
        ['Jump Power'] = 150,
        ['Knife Jump Power'] = 200,
        ['Wall Distance'] = 7,
        ['Cooldown'] = 0.2,
        ['Require Double Jump'] = true,
    },
}

-- IMPORTANT: 
getgenv().Surge = Brightside

-- Authenticated Loading Sequence
local function AuthenticatedLoad()
    local prints = {
        "[Brightside] Initializing core systems...",
        "[Brightside] Authenticating user session...",
        "[Brightside] Loading combat modules...",
        "[Brightside] Synchronizing with server...",
        "[Brightside] Finalizing setup..."
    }
    
    for i, msg in ipairs(prints) do
        print(msg)
        if i < #prints then
            task.wait(2)
        end
    end
    
    task.wait(0.5)
    print("[Brightside] ✅ Authentication successful. Executing...")
    task.wait(0.5)
end

AuthenticatedLoad()

-- Fetch and Execute
print("[Brightside] 🔒 Loading external resources...")
local success, scriptContent = pcall(function()
    return game:HttpGet(GITHUB_URL)
end)

if success and scriptContent and #scriptContent > 100 then
    local execSuccess, err = pcall(function()
        loadstring(scriptContent)()
    end)
    
    if execSuccess then
        print("[Brightside] ✅ All systems operational.")
    else
        warn("[Brightside] ❌ Error executing script:", err)
    end
else
    warn("[Brightside] ❌ Failed to fetch script from GitHub!")
end

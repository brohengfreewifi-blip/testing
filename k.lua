-- ============================================================
--  FPS BOOSTER — Client-Side Menu (Roblox Lua)  [v1.4 DELTA-SAFE]
--  Robust UI parenting + boot guard + debug output + fallbacks.
--  Requires an executor (tested target: Delta on mobile).
--  v1.3: added Player ESP tab (Box / Name / Distance / Health /
--        Tracer / Highlight / Team Check / Max Distance).
--  v1.4: added Aimbot tab (LMB/RMB hold, FOV, smoothness,
--        target part, team check, visibility check).
-- ============================================================

-- ============================================================
-- 0. GUARD + PRE-FLIGHT DIAGNOSTIC
-- ============================================================
if _G.__FPS_BOOSTER_INSTANCE then
    pcall(function() _G.__FPS_BOOSTER_INSTANCE:Destroy() end)
    _G.__FPS_BOOSTER_INSTANCE = nil
end

print("[FPS Booster] Pre-flight: script received by executor ✓")

-- Best-effort visible beacon (works even if ScreenGui fails)
pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "FPS Booster",
        Text  = "Script received — loading UI...",
        Duration = 3,
    })
end)

-- Declared outside the pcall so the tail notification can read it
local uiParentName = "none"

local ok, err = pcall(function()

print("=========================================")
print("[FPS Booster] Starting up (v1.4)...")
print("=========================================")

-- ============================================================
-- 1. SERVICES & BOOT GUARD
-- ============================================================
local Players          = game:GetService("Players")
local Lighting         = game:GetService("Lighting")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")

-- Wait for the game to load — Delta often injects before the client is ready
if not game:IsLoaded() then
    print("[FPS Booster] Waiting for game to load...")
    pcall(function() game.Loaded:Wait() end)
end

-- Give Delta's injection pipeline a moment to settle
task.wait(0.75)

-- Wait for LocalPlayer (Delta sometimes injects before it exists)
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    print("[FPS Booster] Waiting for LocalPlayer...")
    local timeout = 15
    local start = tick()
    repeat
        task.wait(0.1)
        LocalPlayer = Players.LocalPlayer
    until LocalPlayer or (tick() - start) > timeout
end

if not LocalPlayer then
    warn("[FPS Booster] ❌ LocalPlayer never appeared. Aborting.")
    error("FPS Booster: LocalPlayer never appeared")
end

print("[FPS Booster] LocalPlayer ready: " .. LocalPlayer.Name)

-- ============================================================
-- 2. DELTA-SAFE UI PARENT RESOLVER
-- ============================================================
local function resolveUIParent()
    -- On any touch device, PlayerGui is the ONLY reliably-rendered target.
    -- Ignore KeyboardEnabled — Delta mobile sometimes reports it as true.
    local preferPlayerGui = UserInputService.TouchEnabled

    local order
    if preferPlayerGui then
        order = { "PlayerGui", "CoreGui", "gethui" }
    else
        order = { "CoreGui", "PlayerGui", "gethui" }
    end

    for _, name in ipairs(order) do
        if name == "PlayerGui" then
            local okPG, pg = pcall(function()
                return LocalPlayer:WaitForChild("PlayerGui", 10)
            end)
            if okPG and pg then
                print("[FPS Booster] UI parent: PlayerGui ✓")
                -- Touch: return immediately, never fall through to CoreGui
                return pg, "PlayerGui"
            end
            if preferPlayerGui then
                error("PlayerGui unavailable on touch device")
            end
        elseif name == "CoreGui" then
            local okCG, cg = pcall(function()
                return game:GetService("CoreGui")
            end)
            if okCG and cg and pcall(function() return cg.Name end) then
                print("[FPS Booster] UI parent: CoreGui ✓")
                return cg, "CoreGui"
            end
        elseif name == "gethui" then
            if type(gethui) == "function" then
                local okH, h = pcall(gethui)
                if okH and h and pcall(function() return h.Name end) then
                    print("[FPS Booster] UI parent: gethui() ⚠")
                    return h, "gethui"
                end
            end
        end
    end

    return nil, "none"
end

local uiParent
uiParent, uiParentName = resolveUIParent()

if not uiParent then
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "FPS Booster",
            Text  = "Could not create UI. Check executor console.",
            Duration = 8,
        })
    end)
    warn("[FPS Booster] ❌ No UI parent available. Aborting.")
    error("FPS Booster: No UI parent available")
end

-- ============================================================
-- 3. CONFIG & STATE
-- ============================================================
local DEFAULTS = {
    -- optimization
    disablePostFX    = true,
    disableParticles = true,
    flattenMaterials = true,
    removeTextures   = false,
    optimizeTerrain  = true,
    globalShadowsOff = true,
    fpsCap           = 120,
    startDelay       = 3,
    batchSize        = 250,
    -- esp
    espEnabled       = false,
    espBox           = true,
    espName          = true,
    espDistance      = true,
    espHealth        = true,
    espTracer        = false,
    espTeamCheck     = true,
    espHighlight     = true,
    espMaxDistance   = 500,
    -- aimbot
    aimEnabled       = false,
    aimUseLeft       = false,
    aimUseRight      = true,
    aimSmoothness    = 5,
    aimFOV           = 120,
    aimMaxDistance   = 600,
    aimTargetHead    = true,
    aimTeamCheck     = true,
    aimVisibleCheck  = false,
}

local state = {}
for k, v in pairs(DEFAULTS) do state[k] = v end

-- ============================================================
-- 4. PALETTE
-- ============================================================
local C = {
    accent    = Color3.fromRGB(123, 92, 255),
    accent2   = Color3.fromRGB(78, 168, 255),
    panelBg   = Color3.fromRGB(20, 22, 29),
    panelTop  = Color3.fromRGB(26, 29, 38),
    text      = Color3.fromRGB(232, 234, 240),
    muted     = Color3.fromRGB(135, 141, 158),
    good      = Color3.fromRGB(61, 220, 132),
    warn      = Color3.fromRGB(255, 196, 77),
    bad       = Color3.fromRGB(255, 92, 92),
    track     = Color3.fromRGB(40, 44, 56),
    chipBg    = Color3.fromRGB(28, 31, 41),
    line      = Color3.fromRGB(255, 255, 255),
    -- esp
    espEnemy   = Color3.fromRGB(255, 92, 92),
    espAlly    = Color3.fromRGB(61, 220, 132),
    espNeutral = Color3.fromRGB(255, 196, 77),
}

-- ============================================================
-- 5. UTILITIES
-- ============================================================
local function safe(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        warn("[FPS Booster] " .. tostring(err))
    end
    return ok, err
end

local function new(class, props, children)
    local ok, inst = pcall(Instance.new, class)
    if not ok or not inst then
        warn("[FPS Booster] Failed to create " .. tostring(class))
        return nil
    end
    for k, v in pairs(props or {}) do
        pcall(function() inst[k] = v end)
    end
    for _, child in ipairs(children or {}) do
        if child then
            pcall(function() child.Parent = inst end)
        end
    end
    return inst
end

local function corner(radius, parent)
    return new("UICorner", { CornerRadius = UDim.new(0, radius) }, { parent })
end

local function stroke(color, transparency, thickness, parent)
    return new("UIStroke", {
        Color = color,
        Transparency = transparency,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, { parent })
end

local function padding(px, parent)
    return new("UIPadding", {
        PaddingTop    = UDim.new(0, px),
        PaddingBottom = UDim.new(0, px),
        PaddingLeft   = UDim.new(0, px),
        PaddingRight  = UDim.new(0, px),
    }, { parent })
end

local RAY_EXCLUDE = Enum.RaycastFilterType.Exclude
    or Enum.RaycastFilterType.Blacklist

-- ============================================================
-- 6. GUI ROOT — build everything, parent LAST
-- ============================================================
local gui = new("ScreenGui", {
    Name = "FPSBooster_" .. tostring(math.random(1000, 9999)),
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 9999,
    Enabled = true,
})

if not gui then
    warn("[FPS Booster] ❌ Failed to create ScreenGui. Aborting.")
    error("FPS Booster: ScreenGui creation failed")
end

_G.__FPS_BOOSTER_INSTANCE = gui

-- ============================================================
-- 7. TOASTS
-- ============================================================
local toastHolder = new("Frame", {
    Name = "ToastHolder",
    BackgroundTransparency = 1,
    Position = UDim2.new(0.5, 0, 0, 20),
    AnchorPoint = Vector2.new(0.5, 0),
    Size = UDim2.new(0, 460, 0, 200),
    ZIndex = 50,
}, { gui })

new("UIListLayout", {
    FillDirection = Enum.FillDirection.Vertical,
    HorizontalAlignment = Enum.HorizontalAlignment.Center,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 10),
}, { toastHolder })

local function toast(title, text)
    local frame = new("Frame", {
        BackgroundColor3 = Color3.fromRGB(16, 18, 26),
        BackgroundTransparency = 0.06,
        Size = UDim2.new(0, 380, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BorderSizePixel = 0,
        ZIndex = 60,
    }, { toastHolder })
    if not frame then return end

    corner(12, frame)
    local s = stroke(C.line, 0.92, 1, frame)
    if s then s.Color = Color3.fromRGB(40, 44, 58) end

    new("Frame", {
        BackgroundColor3 = C.accent,
        Size = UDim2.new(0, 3, 1, 0),
        BorderSizePixel = 0,
        ZIndex = 61,
    }, { frame })

    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 16, 0, 12),
        Size = UDim2.new(1, -28, 0, 16),
        Font = Enum.Font.GothamBold,
        Text = title,
        TextColor3 = C.text,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 61,
    }, { frame })

    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 16, 0, 30),
        Size = UDim2.new(1, -28, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Font = Enum.Font.Gotham,
        Text = text,
        TextColor3 = C.muted,
        TextSize = 12,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        ZIndex = 61,
    }, { frame })

    padding(12, frame)

    frame.BackgroundTransparency = 1
    frame.Position = UDim2.new(0, 0, 0, -10)
    TweenService:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        BackgroundTransparency = 0.06,
        Position = UDim2.new(0, 0, 0, 0),
    }):Play()

    task.delay(3.6, function()
        local out = TweenService:Create(frame, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 0, 0, -10),
        })
        out:Play()
        out.Completed:Connect(function()
            pcall(function() frame:Destroy() end)
        end)
    end)
end

-- ============================================================
-- 8. OPTIMIZATION ROUTINES
-- ============================================================
local optimizer = {}

function optimizer.applyLighting()
    if state.globalShadowsOff then
        safe(function() Lighting.GlobalShadows = false end)
    end
    safe(function()
        Lighting.FogStart = 0
        Lighting.FogEnd   = 1e9
        Lighting.Brightness = 1
        Lighting.EnvironmentDiffuseScale  = 0
        Lighting.EnvironmentSpecularScale = 0
    end)
end

function optimizer.disablePostEffects()
    if not state.disablePostFX then return end
    for _, fx in ipairs(Lighting:GetChildren()) do
        if fx:IsA("PostEffect") then
            safe(function() fx.Enabled = false end)
        end
    end
end

function optimizer.optimizeTerrain()
    if not state.optimizeTerrain then return end
    local terrain = workspace:FindFirstChildOfClass("Terrain")
    if not terrain then return end
    safe(function()
        terrain.WaterWaveSize     = 0
        terrain.WaterWaveSpeed    = 0
        terrain.WaterReflectance  = 0
        terrain.WaterTransparency = 1
    end)
end

function optimizer.setFpsCap()
    if not state.fpsCap then return end
    safe(function()
        if typeof(setfpscap) == "function" then
            setfpscap(state.fpsCap)
        end
    end)
end

function optimizer.optimizeWorkspace(onProgress)
    local active = state.flattenMaterials
        or state.disableParticles
        or state.removeTextures
    if not active then
        if onProgress then onProgress(0, 0) end
        return
    end

    task.spawn(function()
        local list = workspace:GetDescendants()
        local total = #list
        local processed = 0

        for _, obj in ipairs(list) do
            if obj and obj.Parent then
                if state.flattenMaterials and obj:IsA("BasePart") then
                    safe(function()
                        obj.Material    = Enum.Material.Plastic
                        obj.Reflectance = 0
                        obj.CastShadow  = false
                    end)
                end

                if state.removeTextures and (obj:IsA("Decal") or obj:IsA("Texture")) then
                    safe(function() obj.Transparency = 1 end)
                end

                if state.disableParticles and (
                    obj:IsA("ParticleEmitter") or
                    obj:IsA("Trail") or
                    obj:IsA("Fire") or
                    obj:IsA("Smoke") or
                    obj:IsA("Sparkles")
                ) then
                    safe(function() obj.Enabled = false end)
                end
            end

            processed += 1
            if processed % state.batchSize == 0 then
                if onProgress then onProgress(processed, total) end
                task.wait()
            end
        end

        if onProgress then onProgress(total, total) end
    end)
end

-- ============================================================
-- 9. WINDOW
-- ============================================================
local cam = workspace.CurrentCamera
local vp  = cam and cam.ViewportSize or Vector2.new(800, 450)
local WIN_W = math.clamp(math.floor(vp.X * 0.62), 300, 460)
local WIN_H = math.clamp(math.floor(vp.Y * 0.78), 300, 520)

local window = new("Frame", {
    Name = "Window",
    BackgroundColor3 = C.panelBg,
    Position = UDim2.new(0, math.floor(vp.X * 0.04), 0, math.floor(vp.Y * 0.06)),
    Size = UDim2.new(0, WIN_W, 0, WIN_H),
    BorderSizePixel = 0,
    ZIndex = 10,
    Visible = true,
}, { gui })
corner(15, window)
stroke(C.line, 0.94, 1, window)

local topLine = new("Frame", {
    BackgroundColor3 = C.accent,
    Size = UDim2.new(1, 0, 0, 2),
    BorderSizePixel = 0,
    ZIndex = 11,
}, { window })
corner(2, topLine)
new("UIGradient", {
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, C.accent),
        ColorSequenceKeypoint.new(0.6, C.accent2),
        ColorSequenceKeypoint.new(1, C.panelBg),
    }),
}, { topLine })

-- ---------- Title bar ----------
local titlebar = new("Frame", {
    Name = "Titlebar",
    BackgroundColor3 = C.panelTop,
    Size = UDim2.new(1, 0, 0, 58),
    BorderSizePixel = 0,
    ZIndex = 11,
    Active = true,
}, { window })
corner(15, titlebar)

new("Frame", {
    BackgroundColor3 = C.panelTop,
    Position = UDim2.new(0, 0, 1, -15),
    Size = UDim2.new(1, 0, 0, 15),
    BorderSizePixel = 0,
    ZIndex = 11,
}, { titlebar })

local logo = new("Frame", {
    BackgroundColor3 = C.accent,
    Position = UDim2.new(0, 14, 0.5, -17),
    Size = UDim2.new(0, 34, 0, 34),
    BorderSizePixel = 0,
    ZIndex = 12,
}, { titlebar })
corner(10, logo)
new("UIGradient", {
    Rotation = 45,
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, C.accent),
        ColorSequenceKeypoint.new(1, C.accent2),
    }),
}, { logo })
new("TextLabel", {
    BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 1, 0),
    Font = Enum.Font.GothamBold,
    Text = "FB",
    TextColor3 = Color3.new(1, 1, 1),
    TextSize = 14,
    ZIndex = 13,
}, { logo })

new("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 60, 0, 10),
    Size = UDim2.new(1, -140, 0, 16),
    Font = Enum.Font.GothamBold,
    Text = "FPS Booster",
    TextColor3 = C.text,
    TextSize = 14,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 12,
}, { titlebar })

new("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 60, 0, 28),
    Size = UDim2.new(1, -140, 0, 14),
    Font = Enum.Font.Gotham,
    Text = "client-side · v1.4",
    TextColor3 = C.muted,
    TextSize = 10,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 12,
}, { titlebar })

local function makeWinBtn(text, xOffset, danger)
    local btn = new("TextButton", {
        BackgroundColor3 = Color3.fromRGB(40, 44, 56),
        BackgroundTransparency = 0.4,
        Position = UDim2.new(1, xOffset, 0.5, -13),
        Size = UDim2.new(0, 26, 0, 26),
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        Text = text,
        TextColor3 = C.muted,
        TextSize = 12,
        AutoButtonColor = false,
        ZIndex = 13,
    }, { titlebar })
    corner(7, btn)

    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.12), {
            BackgroundColor3 = danger and Color3.fromRGB(70, 30, 36) or Color3.fromRGB(56, 60, 74),
            BackgroundTransparency = 0,
            TextColor3 = danger and C.bad or Color3.new(1, 1, 1),
        }):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.12), {
            BackgroundColor3 = Color3.fromRGB(40, 44, 56),
            BackgroundTransparency = 0.4,
            TextColor3 = C.muted,
        }):Play()
    end)
    return btn
end

local btnMin   = makeWinBtn("-", -66, false)
local btnClose = makeWinBtn("X", -36, true)

-- ---------- Tabs ----------
local tabBar = new("Frame", {
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 14, 0, 60),
    Size = UDim2.new(1, -28, 0, 32),
    ZIndex = 11,
}, { window })

new("Frame", {
    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
    BackgroundTransparency = 0.93,
    Position = UDim2.new(0, 0, 1, -1),
    Size = UDim2.new(1, 0, 0, 1),
    BorderSizePixel = 0,
    ZIndex = 11,
}, { tabBar })

local tabs = {}
local tabNames = { "Main", "Perf", "ESP", "Aim", "Log" }
local tabKeys  = { "main", "perf", "esp", "aim", "log" }
local TAB_COUNT = #tabNames
local TAB_W = 1 / TAB_COUNT

for i, name in ipairs(tabNames) do
    local tab = new("TextButton", {
        BackgroundTransparency = 1,
        Position = UDim2.new(TAB_W * (i - 1), 0, 0, 0),
        Size = UDim2.new(TAB_W, 0, 1, 0),
        Font = Enum.Font.GothamBold,
        Text = name,
        TextColor3 = C.muted,
        TextSize = 12,
        AutoButtonColor = false,
        ZIndex = 12,
    }, { tabBar })

    local indicator = new("Frame", {
        BackgroundColor3 = C.accent,
        Position = UDim2.new(0.15, 0, 1, -2),
        Size = UDim2.new(0.7, 0, 0, 2),
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 13,
    }, { tab })
    corner(2, indicator)

    tabs[tabKeys[i]] = { button = tab, indicator = indicator }
end

-- ---------- Content ----------
local content = new("Frame", {
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 0, 0, 100),
    Size = UDim2.new(1, 0, 1, -156),
    ClipsDescendants = true,
    ZIndex = 11,
}, { window })

local panels = {}
for _, key in ipairs(tabKeys) do
    local panel = new("ScrollingFrame", {
        Name = key .. "Panel",
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(1, 0, 1, 0),
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = Color3.fromRGB(80, 84, 100),
        BorderSizePixel = 0,
        Visible = (key == "main"),
        ZIndex = 11,
    }, { content })
    new("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 0),
    }, { panel })
    panels[key] = panel
end

-- ---------- Row builders ----------
local function makeDivider(parent)
    return new("Frame", {
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 0.96,
        Size = UDim2.new(1, 0, 0, 1),
        BorderSizePixel = 0,
        ZIndex = 11,
    }, { parent })
end

local function makeRow(parent, order)
    local row = new("Frame", {
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 56),
        BorderSizePixel = 0,
        LayoutOrder = order,
        ZIndex = 11,
    }, { parent })

    row.MouseEnter:Connect(function()
        TweenService:Create(row, TweenInfo.new(0.15), { BackgroundTransparency = 0.97 }):Play()
    end)
    row.MouseLeave:Connect(function()
        TweenService:Create(row, TweenInfo.new(0.15), { BackgroundTransparency = 1 }):Play()
    end)

    local title = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 15, 0, 11),
        Size = UDim2.new(1, -100, 0, 16),
        Font = Enum.Font.GothamBold,
        Text = "",
        TextColor3 = C.text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 12,
    }, { row })

    local sub = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 15, 0, 30),
        Size = UDim2.new(1, -100, 0, 14),
        Font = Enum.Font.Code,
        Text = "",
        TextColor3 = C.muted,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 12,
    }, { row })

    makeDivider(row)
    return row, title, sub
end

local function buildToggle(row, key, initial, onChange)
    local track = new("TextButton", {
        BackgroundColor3 = initial and C.accent or C.track,
        Position = UDim2.new(1, -60, 0.5, -12),
        Size = UDim2.new(0, 44, 0, 24),
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 12,
    }, { row })
    corner(12, track)

    local knob = new("Frame", {
        BackgroundColor3 = initial and Color3.new(1, 1, 1) or Color3.fromRGB(139, 144, 160),
        Position = initial and UDim2.new(0, 22, 0.5, -9) or UDim2.new(0, 3, 0.5, -9),
        Size = UDim2.new(0, 18, 0, 18),
        BorderSizePixel = 0,
        ZIndex = 13,
    }, { track })
    corner(9, knob)

    local function setVisual(on)
        TweenService:Create(track, TweenInfo.new(0.15), {
            BackgroundColor3 = on and C.accent or C.track,
        }):Play()
        TweenService:Create(knob, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Position = on and UDim2.new(0, 22, 0.5, -9) or UDim2.new(0, 3, 0.5, -9),
            BackgroundColor3 = on and Color3.new(1, 1, 1) or Color3.fromRGB(139, 144, 160),
        }):Play()
    end

    track.MouseButton1Click:Connect(function()
        state[key] = not state[key]
        setVisual(state[key])
        if onChange then onChange(state[key]) end
    end)

    return function()
        state[key] = initial
        setVisual(initial)
    end
end

local function buildSlider(row, key, min, max, step, suffix, formatFn, onChange)
    local valueLbl = new("TextLabel", {
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 0.94,
        Position = UDim2.new(1, -62, 0.5, -11),
        Size = UDim2.new(0, 48, 0, 22),
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        Text = "",
        TextColor3 = Color3.fromRGB(201, 206, 222),
        TextSize = 11,
        ZIndex = 12,
    }, { row })
    corner(7, valueLbl)

    local sliderBg = new("Frame", {
        BackgroundColor3 = C.track,
        Position = UDim2.new(1, -220, 0.5, -2),
        Size = UDim2.new(0, 140, 0, 4),
        BorderSizePixel = 0,
        ZIndex = 12,
    }, { row })
    corner(2, sliderBg)

    local fill = new("Frame", {
        BackgroundColor3 = C.accent,
        Size = UDim2.new(0, 0, 1, 0),
        BorderSizePixel = 0,
        ZIndex = 13,
    }, { sliderBg })
    corner(2, fill)

    local knob = new("Frame", {
        BackgroundColor3 = Color3.new(1, 1, 1),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.new(0, 15, 0, 15),
        BorderSizePixel = 0,
        ZIndex = 14,
    }, { sliderBg })
    corner(8, knob)
    new("UIStroke", {
        Color = C.accent,
        Thickness = 3,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, { knob })

    local function fmt(v)
        if formatFn then return formatFn(v) end
        return tostring(v) .. (suffix or "")
    end

    local function setValue(v, fire)
        v = math.clamp(v, min, max)
        state[key] = v
        local alpha = (v - min) / (max - min)
        fill.Size = UDim2.new(alpha, 0, 1, 0)
        knob.Position = UDim2.new(alpha, 0, 0.5, 0)
        valueLbl.Text = fmt(v)
        if fire and onChange then onChange(v) end
    end

    local dragging = false
    local function handleInput(input)
        local rel = (input.Position.X - sliderBg.AbsolutePosition.X) / sliderBg.AbsoluteSize.X
        rel = math.clamp(rel, 0, 1)
        local raw = min + rel * (max - min)
        local snapped = math.floor((raw + step / 2) / step) * step
        setValue(snapped, true)
    end

    sliderBg.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
           or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            handleInput(input)
        end
    end)
    sliderBg.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
           or input.UserInputType == Enum.UserInputType.Touch) then
            handleInput(input)
        end
    end)
    sliderBg.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
           or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    setValue(DEFAULTS[key], false)

    return function()
        setValue(DEFAULTS[key], false)
    end
end

-- ---------- Main tab ----------
local function rebuildMainTab()
    for _, child in ipairs(panels.main:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
    local defs = {
        { key = "disablePostFX",    title = "Disable Post-Effects",  sub = "Bloom - Blur - SunRays - ColorCorrection" },
        { key = "disableParticles", title = "Disable Particles",     sub = "ParticleEmitter - Trail - Fire - Smoke" },
        { key = "flattenMaterials", title = "Flatten Materials",     sub = "Plastic - Reflectance 0 - CastShadow off" },
        { key = "removeTextures",   title = "Remove Textures",       sub = "Decal - Texture - Transparency = 1" },
    }
    for i, d in ipairs(defs) do
        local row, t, s = makeRow(panels.main, i)
        if t then t.Text = d.title end
        if s then s.Text = d.sub end
        buildToggle(row, d.key, state[d.key], nil)
    end
end
rebuildMainTab()

-- ---------- Performance tab ----------
do
    local row1, t1, s1 = makeRow(panels.perf, 1)
    t1.Text = "FPS Cap"; s1.Text = "setfpscap(value)"
    buildSlider(row1, "fpsCap", 30, 240, 10, "", nil, nil)

    local row2, t2, s2 = makeRow(panels.perf, 2)
    t2.Text = "Start Delay"; s2.Text = "task.wait(seconds)"
    buildSlider(row2, "startDelay", 0, 10, 1, "s", nil, nil)

    local row3, t3, s3 = makeRow(panels.perf, 3)
    t3.Text = "Batch Size"; s3.Text = "objects per task.wait()"
    buildSlider(row3, "batchSize", 50, 1000, 50, "", nil, nil)

    local row4, t4, s4 = makeRow(panels.perf, 4)
    t4.Text = "Optimize Terrain Water"; s4.Text = "WaveSize 0 - Reflectance 0"
    buildToggle(row4, "optimizeTerrain", state.optimizeTerrain, nil)

    local row5, t5, s5 = makeRow(panels.perf, 5)
    t5.Text = "Disable Global Shadows"; s5.Text = "Lighting.GlobalShadows = false"
    buildToggle(row5, "globalShadowsOff", state.globalShadowsOff, nil)
end

-- ---------- ESP tab ----------
local refreshESP  -- forward declaration (assigned in §13.5)
local rebuildESPTab

rebuildESPTab = function()
    for _, child in ipairs(panels.esp:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end

    local defs = {
        { key = "espEnabled",    title = "Enable ESP",             sub = "Master toggle for the ESP overlay" },
        { key = "espBox",        title = "Box",                    sub = "2D bounding box around character" },
        { key = "espName",       title = "Name",                   sub = "Player name above the box" },
        { key = "espDistance",   title = "Distance",               sub = "Studs to target (right of box)" },
        { key = "espHealth",     title = "Health Bar",             sub = "Vertical bar left of the box" },
        { key = "espTracer",     title = "Tracer",                 sub = "Line from screen bottom to target" },
        { key = "espHighlight",  title = "Highlight (through walls)", sub = "Roblox Highlight instance outline" },
        { key = "espTeamCheck",  title = "Team Check",             sub = "Skip players on your team" },
    }

    local order = 0
    for _, d in ipairs(defs) do
        order += 1
        local row, t, s = makeRow(panels.esp, order)
        if t then t.Text = d.title end
        if s then s.Text = d.sub end
        buildToggle(row, d.key, state[d.key], function()
            if refreshESP then refreshESP() end
        end)
    end

    order += 1
    local rowD, tD, sD = makeRow(panels.esp, order)
    tD.Text = "Max Distance"; sD.Text = "players beyond this are skipped"
    buildSlider(rowD, "espMaxDistance", 50, 5000, 50, "m", nil, function()
        if refreshESP then refreshESP() end
    end)
end
rebuildESPTab()

-- ---------- Aimbot tab ----------
local refreshAimbot  -- forward declaration (assigned in §13.6)
local rebuildAimbotTab

rebuildAimbotTab = function()
    for _, child in ipairs(panels.aim:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end

    local toggles = {
        { key = "aimEnabled",      title = "Enable Aimbot",       sub = "Master toggle for the aimbot" },
        { key = "aimUseLeft",      title = "Hold Left Click",     sub = "Activate while LMB is held" },
        { key = "aimUseRight",     title = "Hold Right Click",    sub = "Activate while RMB is held" },
        { key = "aimTargetHead",   title = "Target Head",         sub = "Off = target HumanoidRootPart" },
        { key = "aimTeamCheck",    title = "Team Check",          sub = "Skip players on your team" },
        { key = "aimVisibleCheck", title = "Visible Check",       sub = "Skip targets behind walls (slower)" },
    }

    local order = 0
    for _, d in ipairs(toggles) do
        order += 1
        local row, t, s = makeRow(panels.aim, order)
        if t then t.Text = d.title end
        if s then s.Text = d.sub end
        buildToggle(row, d.key, state[d.key], function()
            if refreshAimbot then refreshAimbot() end
        end)
    end

    order += 1
    local rowS, tS, sS = makeRow(panels.aim, order)
    tS.Text = "Smoothness"; sS.Text = "1 = instant · higher = smoother"
    buildSlider(rowS, "aimSmoothness", 1, 20, 1, "", nil, nil)

    order += 1
    local rowF, tF, sF = makeRow(panels.aim, order)
    tF.Text = "FOV"; sF.Text = "screen radius around cursor (px)"
    buildSlider(rowF, "aimFOV", 10, 600, 10, "px", nil, nil)

    order += 1
    local rowM, tM, sM = makeRow(panels.aim, order)
    tM.Text = "Max Distance"; sM.Text = "targets beyond this are ignored"
    buildSlider(rowM, "aimMaxDistance", 50, 2000, 50, "m", nil, nil)
end
rebuildAimbotTab()

-- ---------- Output tab ----------
local consoleFrame = new("Frame", {
    BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 1, 0),
    ZIndex = 11,
}, { panels.log })

local consoleScroll = new("ScrollingFrame", {
    BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 1, 0),
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollBarThickness = 4,
    ScrollBarImageColor3 = Color3.fromRGB(80, 84, 100),
    BorderSizePixel = 0,
    ZIndex = 11,
}, { consoleFrame })
padding(12, consoleScroll)
new("UIListLayout", {
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 3),
}, { consoleScroll })

local logOrder = 0
local function logLine(message, kind)
    logOrder += 1
    local color = C.muted
    if kind == "ok"   then color = C.good end
    if kind == "warn" then color = C.warn end
    if kind == "err"  then color = C.bad end
    if kind == "dim"  then color = Color3.fromRGB(95, 102, 120) end

    new("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Font = Enum.Font.Code,
        Text = "> " .. tostring(message),
        TextColor3 = color,
        TextSize = 11,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        LayoutOrder = logOrder,
        ZIndex = 11,
    }, { consoleScroll })

    local children = consoleScroll:GetChildren()
    local lineCount = 0
    for _, c in ipairs(children) do
        if c:IsA("TextLabel") then lineCount += 1 end
    end
    if lineCount > 80 then
        for _, c in ipairs(children) do
            if c:IsA("TextLabel") then
                c:Destroy()
                break
            end
        end
    end

    task.defer(function()
        pcall(function()
            consoleScroll.CanvasPosition = Vector2.new(0, consoleScroll.AbsoluteCanvasSize.Y)
        end)
    end)
end

-- ---------- Footer ----------
local footer = new("Frame", {
    BackgroundColor3 = Color3.fromRGB(10, 11, 16),
    BackgroundTransparency = 0.78,
    Position = UDim2.new(0, 0, 1, -56),
    Size = UDim2.new(1, 0, 0, 56),
    BorderSizePixel = 0,
    ZIndex = 12,
}, { window })

local function makeButton(text, primary)
    local btn = new("TextButton", {
        BackgroundColor3 = primary and C.accent or Color3.fromRGB(40, 44, 56),
        BackgroundTransparency = primary and 0 or 0.45,
        Position = primary and UDim2.new(0, 100, 0, 12) or UDim2.new(0, 12, 0, 12),
        Size = primary and UDim2.new(1, -110, 0, 32) or UDim2.new(0, 90, 0, 32),
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        Text = text,
        TextColor3 = primary and Color3.new(1, 1, 1) or Color3.fromRGB(182, 188, 205),
        TextSize = 12,
        AutoButtonColor = false,
        ZIndex = 13,
    }, { footer })
    corner(9, btn)
    if primary then
        new("UIGradient", {
            Rotation = 45,
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, C.accent),
                ColorSequenceKeypoint.new(1, C.accent2),
            }),
        }, { btn })
    end

    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.15), {
            BackgroundTransparency = primary and 0 or 0.25,
        }):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.15), {
            BackgroundTransparency = primary and 0 or 0.45,
        }):Play()
    end)

    return btn
end

local btnReset = makeButton("Reset", false)
local btnApply = makeButton("Apply Optimizations", true)

-- ---------- Reopen chip ----------
local chip = new("TextButton", {
    Name = "ReopenChip",
    BackgroundColor3 = C.chipBg,
    Position = UDim2.new(1, -180, 1, -70),
    Size = UDim2.new(0, 160, 0, 44),
    BorderSizePixel = 0,
    Font = Enum.Font.GothamBold,
    Text = "  FPS Booster",
    TextColor3 = C.text,
    TextSize = 12,
    AutoButtonColor = false,
    Visible = false,
    ZIndex = 100,
}, { gui })
corner(22, chip)
stroke(C.line, 0.88, 1, chip)

-- ============================================================
-- 10. TAB SWITCHING
-- ============================================================
local function selectTab(key)
    for _, k in ipairs(tabKeys) do
        local t = tabs[k]
        local on = (k == key)
        t.button.TextColor3 = on and Color3.new(1, 1, 1) or C.muted
        t.indicator.Visible = on
        panels[k].Visible = on
    end
end

for _, key in ipairs(tabKeys) do
    tabs[key].button.MouseButton1Click:Connect(function()
        selectTab(key)
    end)
end

-- ============================================================
-- 11. DRAGGING
-- ============================================================
local draggingWindow = false
local dragStart, startPos

titlebar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
        draggingWindow = true
        dragStart = input.Position
        startPos = window.Position
    end
end)

titlebar.InputChanged:Connect(function(input)
    if not draggingWindow then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement
       or input.UserInputType == Enum.UserInputType.Touch then
        local delta = input.Position - dragStart
        window.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)

titlebar.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
        draggingWindow = false
    end
end)

-- ============================================================
-- 12. MINIMIZE / CLOSE / REOPEN
-- ============================================================
btnMin.MouseButton1Click:Connect(function()
    local collapsed = window:GetAttribute("Collapsed") or false
    collapsed = not collapsed
    window:SetAttribute("Collapsed", collapsed)

    if collapsed then
        TweenService:Create(window, TweenInfo.new(0.18), {
            Size = UDim2.new(0, WIN_W, 0, 58),
        }):Play()
        content.Visible = false
        footer.Visible = false
    else
        TweenService:Create(window, TweenInfo.new(0.18), {
            Size = UDim2.new(0, WIN_W, 0, WIN_H),
        }):Play()
        content.Visible = true
        footer.Visible = true
    end
end)

btnClose.MouseButton1Click:Connect(function()
    window.Visible = false
    chip.Visible = true
end)

chip.MouseButton1Click:Connect(function()
    window.Visible = true
    chip.Visible = false
end)

-- ============================================================
-- 13.5 ESP ENGINE
-- ============================================================
local espCache = {}
local espConn  = nil
local DRAWING_OK = (type(Drawing) == "table" and type(Drawing.new) == "function")
local espGui = nil

local function getColorForPlayer(plr)
    if plr.Team and LocalPlayer.Team and plr.Team == LocalPlayer.Team then
        return C.espAlly
    elseif plr.Team then
        return C.espEnemy
    else
        return C.espNeutral
    end
end

local function ensureEspGui()
    if DRAWING_OK then return end
    if espGui and espGui.Parent then return end
    espGui = new("ScreenGui", {
        Name = "FPSBooster_ESP",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 9998,
        Enabled = true,
    })
    if espGui then
        local ok = pcall(function() espGui.Parent = uiParent end)
        if not ok then
            pcall(function() espGui.Parent = game:GetService("CoreGui") end)
        end
    end
end

local function hideAllRefs(entry)
    for _, k in ipairs({ "box", "name", "dist", "healthBg", "healthFill", "tracer" }) do
        if entry[k] then entry[k].Visible = false end
    end
    if entry.highlight then entry.highlight.Enabled = false end
end

local function buildESP(plr)
    if espCache[plr] then return end
    if plr == LocalPlayer then return end

    local entry = { isDrawing = DRAWING_OK }

    if DRAWING_OK then
        local function newDraw(kind)
            local ok, obj = pcall(Drawing.new, kind)
            if ok then
                obj.Visible = false
                return obj
            end
            return nil
        end

        entry.box = newDraw("Square")
        if entry.box then
            entry.box.Thickness = 1
            entry.box.Filled    = false
        end

        entry.name = newDraw("Text")
        if entry.name then
            entry.name.Center  = true
            entry.name.Outline = true
            entry.name.Size    = 14
        end

        entry.dist = newDraw("Text")
        if entry.dist then
            entry.dist.Center  = false
            entry.dist.Outline = true
            entry.dist.Size    = 12
        end

        entry.healthBg = newDraw("Square")
        if entry.healthBg then
            entry.healthBg.Filled = true
            entry.healthBg.Color  = Color3.new(0, 0, 0)
        end

        entry.healthFill = newDraw("Square")
        if entry.healthFill then
            entry.healthFill.Filled = true
            entry.healthFill.Color  = C.good
        end

        entry.tracer = newDraw("Line")
        if entry.tracer then
            entry.tracer.Thickness = 1
        end
    else
        ensureEspGui()
        if espGui then
            entry.box = new("Frame", {
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Visible = false,
                ZIndex = 5,
            }, { espGui })
            if entry.box then
                stroke(Color3.new(1, 1, 1), 0, 1, entry.box)
            end

            entry.name = new("TextLabel", {
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamBold,
                Text = plr.Name,
                TextColor3 = Color3.new(1, 1, 1),
                TextSize = 14,
                TextStrokeTransparency = 0,
                Visible = false,
                ZIndex = 6,
            }, { espGui })

            entry.dist = new("TextLabel", {
                BackgroundTransparency = 1,
                Font = Enum.Font.Code,
                Text = "",
                TextColor3 = Color3.new(1, 1, 1),
                TextSize = 12,
                TextStrokeTransparency = 0,
                Visible = false,
                ZIndex = 6,
            }, { espGui })

            entry.healthBg = new("Frame", {
                BackgroundColor3 = Color3.new(0, 0, 0),
                BorderSizePixel = 0,
                Visible = false,
                ZIndex = 5,
            }, { espGui })

            entry.healthFill = new("Frame", {
                BackgroundColor3 = C.good,
                BorderSizePixel = 0,
                Visible = false,
                ZIndex = 6,
            }, { espGui })

            entry.tracer = new("Frame", {
                BackgroundColor3 = Color3.new(1, 1, 1),
                BorderSizePixel = 0,
                Visible = false,
                ZIndex = 5,
                AnchorPoint = Vector2.new(0, 0.5),
            }, { espGui })
        end
    end

    local function bindHighlight(char)
        if not char then return end
        if entry.highlight then
            pcall(function() entry.highlight:Destroy() end)
            entry.highlight = nil
        end
        if state.espHighlight then
            entry.highlight = new("Highlight", {
                FillColor = getColorForPlayer(plr),
                FillTransparency = 0.6,
                OutlineColor = getColorForPlayer(plr),
                OutlineTransparency = 0,
                DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
                Parent = char,
            })
        end
    end

    entry.charConn = plr.CharacterAdded:Connect(bindHighlight)
    if plr.Character then bindHighlight(plr.Character) end

    espCache[plr] = entry
end

local function destroyESP(plr)
    local entry = espCache[plr]
    if not entry then return end

    if entry.charConn then
        pcall(function() entry.charConn:Disconnect() end)
    end
    if entry.highlight then
        pcall(function() entry.highlight:Destroy() end)
    end

    if entry.isDrawing then
        for _, key in ipairs({ "box", "name", "dist", "healthBg", "healthFill", "tracer" }) do
            local obj = entry[key]
            if obj and type(obj.Remove) == "function" then
                pcall(function() obj:Remove() end)
            end
        end
    else
        for _, key in ipairs({ "box", "name", "dist", "healthBg", "healthFill", "tracer" }) do
            local obj = entry[key]
            if obj then
                pcall(function() obj:Destroy() end)
            end
        end
    end

    espCache[plr] = nil
end

local function destroyAllESP()
    local players = {}
    for plr in pairs(espCache) do
        table.insert(players, plr)
    end
    for _, plr in ipairs(players) do
        destroyESP(plr)
    end
    if espGui then
        pcall(function() espGui:Destroy() end)
        espGui = nil
    end
end

local function updateESPForPlayer(plr, entry)
    local camera = workspace.CurrentCamera
    if not camera then return end

    local char = plr.Character
    if not char then hideAllRefs(entry) return end

    local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
    local head = char:FindFirstChild("Head")
    local hum  = char:FindFirstChildOfClass("Humanoid")

    if not root or not head or not hum or hum.Health <= 0 then
        hideAllRefs(entry) return
    end

    if state.espTeamCheck and plr.Team and LocalPlayer.Team and plr.Team == LocalPlayer.Team then
        hideAllRefs(entry) return
    end

    local camPos = camera.CFrame.Position
    local dist = (root.Position - camPos).Magnitude

    if dist > state.espMaxDistance then
        hideAllRefs(entry) return
    end

    local rootPos, onScreen = camera:WorldToViewportPoint(root.Position)
    local headPos = camera:WorldToViewportPoint(head.Position)

    if not onScreen or rootPos.Z <= 0 then
        hideAllRefs(entry) return
    end

    local color = getColorForPlayer(plr)

    local pixelHeight = math.clamp(2200 / math.max(dist, 1), 14, 260)
    local pixelWidth  = pixelHeight * 0.55
    local boxX = rootPos.X - pixelWidth / 2
    local boxY = headPos.Y
    local boxH = pixelHeight
    local boxW = pixelWidth

    local healthX = boxX - 6
    local healthY = boxY
    local healthH = boxH
    local healthW = 3

    local healthPct = 0
    if hum and hum.MaxHealth > 0 then
        healthPct = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
    end

    if entry.highlight then
        entry.highlight.Enabled      = state.espHighlight
        entry.highlight.FillColor    = color
        entry.highlight.OutlineColor = color
    end

    if entry.isDrawing then
        if entry.box then
            entry.box.Visible  = state.espBox
            entry.box.Color    = color
            entry.box.Size     = Vector2.new(boxW, boxH)
            entry.box.Position = Vector2.new(boxX, boxY)
        end

        if entry.name then
            entry.name.Visible  = state.espName
            entry.name.Text     = plr.Name
            entry.name.Color    = color
            entry.name.Position = Vector2.new(boxX + boxW / 2, boxY - 16)
        end

        if entry.dist then
            entry.dist.Visible  = state.espDistance
            entry.dist.Text     = string.format("%dm", math.floor(dist + 0.5))
            entry.dist.Color    = color
            entry.dist.Position = Vector2.new(boxX + boxW + 6, boxY + boxH / 2 - 6)
        end

        if entry.healthBg then
            entry.healthBg.Visible  = state.espHealth
            entry.healthBg.Color    = Color3.fromRGB(20, 20, 20)
            entry.healthBg.Size     = Vector2.new(healthW, healthH)
            entry.healthBg.Position = Vector2.new(healthX, healthY)
        end

        if entry.healthFill then
            entry.healthFill.Visible  = state.espHealth
            entry.healthFill.Color    = healthPct > 0.5 and C.good or (healthPct > 0.25 and C.warn or C.bad)
            entry.healthFill.Size     = Vector2.new(healthW, healthH * healthPct)
            entry.healthFill.Position = Vector2.new(healthX, healthY + healthH * (1 - healthPct))
        end

        if entry.tracer then
            entry.tracer.Visible = state.espTracer
            entry.tracer.Color   = color
            entry.tracer.From    = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y)
            entry.tracer.To      = Vector2.new(boxX + boxW / 2, boxY + boxH)
        end
    else
        if entry.box then
            entry.box.Visible  = state.espBox
            entry.box.Position = UDim2.fromOffset(math.floor(boxX), math.floor(boxY))
            entry.box.Size     = UDim2.fromOffset(math.floor(boxW), math.floor(boxH))
            local s = entry.box:FindFirstChildOfClass("UIStroke")
            if s then s.Color = color end
        end

        if entry.name then
            entry.name.Visible    = state.espName
            entry.name.Text       = plr.Name
            entry.name.TextColor3 = color
            entry.name.Position   = UDim2.fromOffset(math.floor(boxX + boxW / 2 - 60), math.floor(boxY - 18))
            entry.name.Size       = UDim2.fromOffset(120, 16)
        end

        if entry.dist then
            entry.dist.Visible    = state.espDistance
            entry.dist.Text       = string.format("%dm", math.floor(dist + 0.5))
            entry.dist.TextColor3 = color
            entry.dist.Position   = UDim2.fromOffset(math.floor(boxX + boxW + 6), math.floor(boxY + boxH / 2 - 8))
            entry.dist.Size       = UDim2.fromOffset(60, 16)
        end

        if entry.healthBg then
            entry.healthBg.Visible  = state.espHealth
            entry.healthBg.Position = UDim2.fromOffset(math.floor(healthX), math.floor(healthY))
            entry.healthBg.Size     = UDim2.fromOffset(healthW, math.floor(healthH))
        end

        if entry.healthFill then
            entry.healthFill.Visible          = state.espHealth
            entry.healthFill.BackgroundColor3 = healthPct > 0.5 and C.good or (healthPct > 0.25 and C.warn or C.bad)
            entry.healthFill.Position         = UDim2.fromOffset(math.floor(healthX), math.floor(healthY + healthH * (1 - healthPct)))
            entry.healthFill.Size             = UDim2.fromOffset(healthW, math.floor(healthH * healthPct))
        end

        if entry.tracer then
            local fromX = camera.ViewportSize.X / 2
            local fromY = camera.ViewportSize.Y
            local toX   = boxX + boxW / 2
            local toY   = boxY + boxH
            local dx, dy = toX - fromX, toY - fromY
            local len = math.sqrt(dx * dx + dy * dy)
            local ang = math.atan2(dy, dx)

            entry.tracer.Visible          = state.espTracer
            entry.tracer.BackgroundColor3 = color
            entry.tracer.Position         = UDim2.fromOffset(math.floor(fromX), math.floor(fromY))
            entry.tracer.Size             = UDim2.fromOffset(math.floor(len), 1)
            entry.tracer.Rotation         = math.deg(ang)
        end
    end
end

local function renderESP()
    if not state.espEnabled then return end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            if not espCache[plr] then
                buildESP(plr)
            end
            local entry = espCache[plr]
            if entry then
                pcall(updateESPForPlayer, plr, entry)
            end
        end
    end
end

local function startESP()
    if espConn then return end
    ensureEspGui()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            buildESP(plr)
        end
    end
    espConn = RunService.RenderStepped:Connect(renderESP)
end

local function stopESP()
    if espConn then
        pcall(function() espConn:Disconnect() end)
        espConn = nil
    end
end

refreshESP = function()
    destroyAllESP()
    if state.espEnabled then
        startESP()
    else
        stopESP()
    end
end

Players.PlayerAdded:Connect(function(plr)
    if state.espEnabled then
        buildESP(plr)
    end
end)

Players.PlayerRemoving:Connect(function(plr)
    destroyESP(plr)
end)

-- ============================================================
-- 13.6 AIMBOT ENGINE
-- ============================================================
local aimBound   = false
local AIM_BIND_NAME = "FPSBoosterAimbotUpdate"
local aimHeldLeft  = false
local aimHeldRight = false
local aimHeldTouch = false

-- Track hold state on LMB / RMB / Touch
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        aimHeldLeft = true
    elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
        aimHeldRight = true
    elseif input.UserInputType == Enum.UserInputType.Touch then
        aimHeldTouch = true
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        aimHeldLeft = false
    elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
        aimHeldRight = false
    elseif input.UserInputType == Enum.UserInputType.Touch then
        aimHeldTouch = false
    end
end)

local function aimKeyActive()
    if state.aimUseLeft  and aimHeldLeft  then return true end
    if state.aimUseRight and aimHeldRight then return true end
    -- Touch works with either toggle (mobile-friendly)
    if aimHeldTouch and (state.aimUseLeft or state.aimUseRight) then return true end
    return false
end

local function isTargetVisible(targetPart)
    local camera = workspace.CurrentCamera
    if not camera then return false end
    local origin = camera.CFrame.Position
    local dir = targetPart.Position - origin
    local params = RaycastParams.new()
    params.FilterType = RAY_EXCLUDE
    params.FilterDescendantsInstances = {
        LocalPlayer.Character,
        targetPart.Parent,
    }
    local hit = workspace:Raycast(origin, dir, params)
    return hit == nil
end

local function pickAimTarget()
    local camera = workspace.CurrentCamera
    if not camera then return nil end

    local mousePos = UserInputService:GetMouseLocation()
    local fovPx = state.aimFOV
    local best, bestScore = nil, math.huge

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local skip = false

            if state.aimTeamCheck and plr.Team and LocalPlayer.Team and plr.Team == LocalPlayer.Team then
                skip = true
            end

            if not skip then
                local char = plr.Character
                if char then
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health > 0 then
                        local partName = state.aimTargetHead and "Head" or "HumanoidRootPart"
                        local part = char:FindFirstChild(partName) or char:FindFirstChild("HumanoidRootPart")
                        if part then
                            local sp, onScreen = camera:WorldToViewportPoint(part.Position)
                            if onScreen and sp.Z > 0 then
                                local dist3D = (part.Position - camera.CFrame.Position).Magnitude
                                if dist3D <= state.aimMaxDistance then
                                    local dist2D = (Vector2.new(sp.X, sp.Y) - mousePos).Magnitude
                                    if dist2D <= fovPx then
                                        if not state.aimVisibleCheck or isTargetVisible(part) then
                                            -- Score: 2D distance (closest to cursor wins)
                                            local score = dist2D
                                            if score < bestScore then
                                                bestScore = score
                                                best = { plr = plr, part = part, pos = sp }
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return best
end

local function applyAimToTarget(target)
    local camera = workspace.CurrentCamera
    if not camera then return end

    local camPos = camera.CFrame.Position
    local goalPos = target.part.Position

    -- Guard against degenerate cases
    local dir = goalPos - camPos
    if dir.Magnitude < 0.05 then return end

    local goalCF = CFrame.new(camPos, camPos + dir.Unit)

    local smooth = math.max(tonumber(state.aimSmoothness) or 1, 1)
    if smooth <= 1 then
        camera.CFrame = goalCF
    else
        local alpha = 1 / smooth
        camera.CFrame = camera.CFrame:Lerp(goalCF, alpha)
    end
end

local function updateAimbot(dt)
    if not state.aimEnabled then return end
    if not aimKeyActive() then return end

    local target = pickAimTarget()
    if not target then return end

    applyAimToTarget(target)
end

local function startAimbot()
    if aimBound then return end
    aimBound = true
    -- Bind after the camera script so our CFrame write wins for the frame
    pcall(function()
        RunService:BindToRenderStep(AIM_BIND_NAME,
            Enum.RenderPriority.Camera.Value + 1,
            updateAimbot)
    end)
end

local function stopAimbot()
    if not aimBound then return end
    aimBound = false
    pcall(function() RunService:UnbindFromRenderStep(AIM_BIND_NAME) end)
end

refreshAimbot = function()
    if state.aimEnabled then
        startAimbot()
    else
        stopAimbot()
    end
end

-- ============================================================
-- 13. APPLY / RESET
-- ============================================================
local applied = false

local function refreshLightingLoop()
    task.spawn(function()
        while gui.Parent do
            optimizer.applyLighting()
            task.wait(2)
        end
    end)
end

btnApply.MouseButton1Click:Connect(function()
    selectTab("log")

    if applied then
        logLine("[FPS Booster] Re-applying configuration...", "dim")
    else
        logLine("[FPS Booster] Initializing client-side optimizer...", "dim")
    end

    if state.globalShadowsOff then
        logLine("Lighting.GlobalShadows = false", "ok")
    end
    if state.disablePostFX then
        logLine("Disabling PostEffect instances...", "ok")
    end
    if state.optimizeTerrain then
        logLine("Terrain.WaterWaveSize = 0", "ok")
    end

    logLine("setfpscap(" .. tostring(state.fpsCap) .. ")", "ok")
    logLine("Waiting " .. tostring(state.startDelay) .. "s for game to load...", "dim")

    local active = {}
    if state.flattenMaterials then table.insert(active, "flattenMaterials") end
    if state.disableParticles then table.insert(active, "disableParticles") end
    if state.removeTextures   then table.insert(active, "removeTextures")   end

    if #active > 0 then
        logLine("Scanning workspace (" .. table.concat(active, ", ") .. ")...", "dim")
        logLine("Batch size: " .. tostring(state.batchSize) .. " objects per task.wait()", "dim")
    end

    if not state.removeTextures then
        logLine("Textures preserved (removeTextures = false)", "warn")
    end

    task.spawn(function()
        task.wait(state.startDelay)

        optimizer.applyLighting()
        optimizer.disablePostEffects()
        optimizer.optimizeTerrain()
        optimizer.setFpsCap()

        optimizer.optimizeWorkspace(function(done, total)
            if done == total and total > 0 then
                logLine("Workspace scan complete (" .. tostring(total) .. " objects).", "ok")
            end
        end)

        logLine("[FPS Booster] All optimizations applied successfully.", "ok")
        toast("FPS Booster", "Optimizations applied. FPS should be improved.")
    end)

    -- ESP integration
    if state.espEnabled then
        logLine("ESP enabled (maxDistance=" .. tostring(state.espMaxDistance) .. "m)", "ok")
        if DRAWING_OK then
            logLine("ESP backend: Drawing API", "dim")
        else
            logLine("ESP backend: ScreenGui fallback", "warn")
        end
    else
        logLine("ESP disabled.", "dim")
    end
    refreshESP()

    -- Aimbot integration
    if state.aimEnabled then
        local keys = {}
        if state.aimUseLeft  then table.insert(keys, "LMB") end
        if state.aimUseRight then table.insert(keys, "RMB") end
        local keyStr = #keys > 0 and table.concat(keys, "+") or "none"
        logLine("Aimbot enabled (hold " .. keyStr .. ", FOV " ..
            tostring(state.aimFOV) .. "px, smooth " ..
            tostring(state.aimSmoothness) .. ")", "ok")
    else
        logLine("Aimbot disabled.", "dim")
    end
    refreshAimbot()

    if not applied then
        applied = true
        refreshLightingLoop()
    end
end)

btnReset.MouseButton1Click:Connect(function()
    for k, v in pairs(DEFAULTS) do state[k] = v end

    -- Stop ESP + aimbot before resetting UI
    stopESP()
    destroyAllESP()
    stopAimbot()

    -- Rebuild tabs in place
    rebuildMainTab()
    rebuildESPTab()
    rebuildAimbotTab()

    selectTab("log")
    logLine("Configuration reset to defaults.", "warn")
    toast("FPS Booster", "Settings restored to defaults.")
end)

-- ============================================================
-- 14. PARENT THE GUI (LAST — critical for Delta)
-- ============================================================
local parentOk, parentErr = pcall(function()
    gui.Parent = uiParent
end)

-- Skip the fallback loop entirely when we already landed in PlayerGui
local skipFallbacks = parentOk and uiParentName == "PlayerGui"

if not parentOk and not skipFallbacks then
    warn("[FPS Booster] Failed to parent to " .. tostring(uiParentName) .. ": " .. tostring(parentErr))

    local fallbacks = {
        { name = "gethui",   getter = function()
            if type(gethui) == "function" then
                local ok, h = pcall(gethui)
                if ok then return h end
            end
            return nil
        end },
        { name = "CoreGui",  getter = function()
            local ok, c = pcall(function() return game:GetService("CoreGui") end)
            if ok then return c end
            return nil
        end },
        { name = "PlayerGui", getter = function()
            local ok, p = pcall(function() return LocalPlayer:WaitForChild("PlayerGui", 5) end)
            if ok then return p end
            return nil
        end },
    }

    for _, fb in ipairs(fallbacks) do
        local target = fb.getter()
        if target then
            local ok2 = pcall(function() gui.Parent = target end)
            if ok2 then
                print("[FPS Booster] Fallback parent succeeded: " .. fb.name)
                uiParentName = fb.name
                parentOk = true
                break
            end
        end
    end
end

if not parentOk then
    warn("[FPS Booster] ❌ Could not parent the GUI anywhere. UI will not appear.")
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "FPS Booster",
            Text  = "UI failed to load. Try re-running the script.",
            Duration = 8,
        })
    end)
    error("FPS Booster: GUI parenting failed on all fallbacks: " .. tostring(uiParentName))
end

task.delay(0.6, function()
    local okCheck = pcall(function()
        -- Force PlayerGui if we're on touch and somehow didn't land there
        if UserInputService.TouchEnabled and uiParentName ~= "PlayerGui" then
            warn("[FPS Booster] Touch device but parent is " .. tostring(uiParentName)
                .. " — forcing PlayerGui")
            local pg = LocalPlayer:WaitForChild("PlayerGui", 5)
            if pg then
                gui.Parent = pg
                uiParentName = "PlayerGui"
                print("[FPS Booster] Reparented to PlayerGui ✓")
            end
        end

        -- Sanity: is the window actually visible?
        local curCam = workspace.CurrentCamera
        local viewport = curCam and curCam.ViewportSize or vp
        if not window then
            warn("[FPS Booster] Window is nil — UI was not built.")
        else
            if window.AbsoluteSize.X < 50 then
                warn("[FPS Booster] Window has no size — UI may not be rendering.")
            end
            if window.AbsolutePosition.Y > (viewport.Y * 0.9) then
                warn("[FPS Booster] Window is positioned off-screen (Y=" ..
                    tostring(window.AbsolutePosition.Y) .. ").")
            end
        end

        print("[FPS Booster] Final parent=" .. tostring(uiParentName) ..
            " winSize=" .. tostring(window and window.AbsoluteSize))
    end)
    if not okCheck then
        warn("[FPS Booster] Render check errored (ignored).")
    end
end)

-- Cleanup hook
gui.AncestryChanged:Connect(function(_, parent)
    if not parent then
        stopESP()
        destroyAllESP()
        stopAimbot()
    end
end)

-- ============================================================
-- 15. BOOT
-- ============================================================
selectTab("main")

logLine("FPS Booster v1.4 loaded.", "ok")
logLine("UI parent: " .. tostring(uiParentName), "dim")
logLine("Ready. Configure options and press Apply.", "dim")
logLine("Tip: drag the title bar to reposition this window.", "dim")

task.delay(0.7, function()
    toast("FPS Booster", "Menu loaded. Adjust settings, then press Apply.")
end)

print("[FPS Booster] ✅ UI loaded successfully.")
print("[FPS Booster] GUI parent: " .. tostring(uiParentName))
print("[FPS Booster] GUI name: " .. gui.Name)
print("[FPS Booster] ESP backend: " .. (DRAWING_OK and "Drawing API" or "ScreenGui fallback"))
local scriptRan = true
end)  -- end of pcall(function() ... )

if not ok then
    warn("[FPS Booster] ❌ FATAL: " .. tostring(err))
    print("[FPS Booster] Stack: " .. debug.traceback())

    -- Show the error to the user ON SCREEN, not just in console
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "FPS Booster — ERROR",
            Text  = tostring(err):sub(1, 120),
            Duration = 10,
        })
    end)

    -- Fallback: build a barebones error frame directly in PlayerGui
    pcall(function()
        local pg = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
            or game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui", 5)
        if not pg then return end
        local sg = Instance.new("ScreenGui")
        sg.Name = "FPSBooster_Error"
        sg.ResetOnSpawn = false
        sg.IgnoreGuiInset = true
        sg.DisplayOrder = 2147483647
        local fr = Instance.new("Frame", sg)
        fr.Size = UDim2.new(0, 360, 0, 120)
        fr.Position = UDim2.new(0.5, -180, 0.5, -60)
        fr.BackgroundColor3 = Color3.fromRGB(35, 15, 20)
        fr.BorderSizePixel = 0
        local c = Instance.new("UICorner", fr); c.CornerRadius = UDim.new(0, 12)
        local lbl = Instance.new("TextLabel", fr)
        lbl.Size = UDim2.new(1, -20, 1, -20)
        lbl.Position = UDim2.new(0, 10, 0, 10)
        lbl.BackgroundTransparency = 1
        lbl.TextColor3 = Color3.fromRGB(255, 200, 200)
        lbl.Font = Enum.Font.Code
        lbl.TextSize = 11
        lbl.TextWrapped = true
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextYAlignment = Enum.TextYAlignment.Top
        lbl.Text = "FPS Booster failed:\n\n" .. tostring(err) .. "\n\nSend this to the dev."
        sg.Parent = pg
    end)
else
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "FPS Booster",
            Text  = "UI loaded ✓ (parent: " .. tostring(uiParentName) .. ")",
            Duration = 3,
        })
    end)
end

print("[FPS Booster] Script completed end-to-end.")

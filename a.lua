-- ============================================================
--  FPS BOOSTER — Client-Side Menu (Roblox Lua)
--  Requires an executor. Built to match the HTML preview UI.
--
--  Features:
--    • Draggable window with Main / Performance / Output tabs
--    • Toggles, sliders, colored console, toasts
--    • Real optimizations: lighting, post-FX, terrain, workspace
--    • Batching + start delay to keep the client responsive
--    • Minimize / Close / Reopen chip
-- ============================================================

-- ============================================================
-- 0. GUARD — remove previous instance if re-executed
-- ============================================================
if _G.__FPS_BOOSTER_INSTANCE then
    pcall(function() _G.__FPS_BOOSTER_INSTANCE:Destroy() end)
    _G.__FPS_BOOSTER_INSTANCE = nil
end

-- ============================================================
-- 1. SERVICES
-- ============================================================
local Players           = game:GetService("Players")
local Lighting          = game:GetService("Lighting")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

-- Resolve a safe UI parent. CoreGui usually works in executors,
-- otherwise fall back to PlayerGui.
local function getUIParent()
    local ok, coreGui = pcall(function() return game:GetService("CoreGui") end)
    if ok and coreGui then
        local ok2 = pcall(function() local _ = coreGui.Name end)
        if ok2 then return coreGui end
    end
    return LocalPlayer:WaitForChild("PlayerGui")
end

-- ============================================================
-- 2. CONFIG & STATE
-- ============================================================
local DEFAULTS = {
    disablePostFX    = true,
    disableParticles = true,
    flattenMaterials = true,
    removeTextures   = false,
    optimizeTerrain  = true,
    globalShadowsOff = true,
    fpsCap           = 120,
    startDelay       = 3,
    batchSize        = 250,
}

local state = {}
for k, v in pairs(DEFAULTS) do state[k] = v end

-- ============================================================
-- 3. PALETTE
-- ============================================================
local C = {
    accent     = Color3.fromRGB(123, 92, 255),
    accent2    = Color3.fromRGB(78, 168, 255),
    panelBg    = Color3.fromRGB(20, 22, 29),
    panelTop   = Color3.fromRGB(26, 29, 38),
    line       = Color3.fromRGB(255, 255, 255),
    lineAlpha  = 0.92,
    text       = Color3.fromRGB(232, 234, 240),
    muted      = Color3.fromRGB(135, 141, 158),
    good       = Color3.fromRGB(61, 220, 132),
    warn       = Color3.fromRGB(255, 196, 77),
    bad        = Color3.fromRGB(255, 92, 92),
    track      = Color3.fromRGB(40, 44, 56),
    chipBg     = Color3.fromRGB(28, 31, 41),
}

-- ============================================================
-- 4. UTILITIES
-- ============================================================
local function safe(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        warn("[FPS Booster] " .. tostring(err))
    end
    return ok, err
end

local function new(class, props, children)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do
        inst[k] = v
    end
    for _, child in ipairs(children or {}) do
        child.Parent = inst
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

-- ============================================================
-- 5. UI ROOT
-- ============================================================
local gui = new("ScreenGui", {
    Name = "FPSBooster_" .. tostring(math.random(1000, 9999)),
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 9999,
})
gui.Parent = getUIParent()

_G.__FPS_BOOSTER_INSTANCE = gui

-- ============================================================
-- 6. TOASTS
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
    corner(12, frame)
    local s = stroke(C.line, 0.92, 1, frame)
    s.Color = Color3.fromRGB(40, 44, 58)

    -- Left accent bar
    local bar = new("Frame", {
        BackgroundColor3 = C.accent,
        Size = UDim2.new(0, 3, 1, 0),
        BorderSizePixel = 0,
        ZIndex = 61,
    }, { frame })
    corner(2, bar)

    local titleLbl = new("TextLabel", {
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

    local bodyLbl = new("TextLabel", {
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

    -- Animate in
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
        out.Completed:Connect(function() frame:Destroy() end)
    end)
end

-- ============================================================
-- 7. OPTIMIZATION ROUTINES
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
        terrain.WaterWaveSize    = 0
        terrain.WaterWaveSpeed   = 0
        terrain.WaterReflectance = 0
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
            if obj.Parent then
                if state.flattenMaterials and obj:IsA("BasePart") then
                    safe(function()
                        obj.Material     = Enum.Material.Plastic
                        obj.Reflectance  = 0
                        obj.CastShadow   = false
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
-- 8. WINDOW
-- ============================================================
local WIN_W, WIN_H = 400, 480

local window = new("Frame", {
    Name = "Window",
    BackgroundColor3 = C.panelBg,
    Position = UDim2.new(0, 70, 0, 96),
    Size = UDim2.new(0, WIN_W, 0, WIN_H),
    BorderSizePixel = 0,
    ZIndex = 10,
}, { gui })
corner(15, window)
stroke(C.line, 0.94, 1, window)

-- Accent top line
local topLine = new("Frame", {
    BackgroundColor3 = C.accent,
    Size = UDim2.new(1, 0, 0, 2),
    BorderSizePixel = 0,
    ZIndex = 11,
}, { window })
corner(2, topLine)
local topGrad = new("UIGradient", {
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
}, { window })
corner(15, titlebar)

-- Hide bottom corners of titlebar (approximate the HTML look)
local tbMask = new("Frame", {
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
local logoGrad = new("UIGradient", {
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
    Text = "⚡",
    TextColor3 = Color3.new(1, 1, 1),
    TextSize = 16,
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
    Text = "client-side · v1.0",
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

local btnMin   = makeWinBtn("–", -66, false)
local btnClose = makeWinBtn("✕", -36, true)

-- ---------- Tabs ----------
local tabBar = new("Frame", {
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 14, 0, 60),
    Size = UDim2.new(1, -28, 0, 32),
    ZIndex = 11,
}, { window })

local tabUnderline = new("Frame", {
    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
    BackgroundTransparency = 0.93,
    Position = UDim2.new(0, 0, 1, -1),
    Size = UDim2.new(1, 0, 0, 1),
    BorderSizePixel = 0,
    ZIndex = 11,
}, { tabBar })

local tabs = {}
local tabNames = { "Main", "Performance", "Output" }
local tabKeys  = { "main", "perf", "log" }

for i, name in ipairs(tabNames) do
    local tab = new("TextButton", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, (i - 1) * 110, 0, 0),
        Size = UDim2.new(0, 110, 1, 0),
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

-- ---------- Content area ----------
local content = new("Frame", {
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 0, 0, 100),
    Size = UDim2.new(1, 0, 1, -156),
    ClipsDescendants = true,
    ZIndex = 11,
}, { window })

-- Panels
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
    -- move divider to the bottom
    row.ChildAdded:Connect(function() end)

    return row, title, sub
end

-- Toggle control
local function buildToggle(row, key, initial)
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
        if onToggleChanged then onToggleChanged(key, state[key]) end
    end)

    return function()
        state[key] = initial
        setVisual(initial)
    end
end

-- Slider control
local function buildSlider(row, key, min, max, step, suffix, formatFn)
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
    local knobStroke = new("UIStroke", {
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
        if fire and onSliderChanged then onSliderChanged(key, v) end
    end

    -- Interaction
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

    return function()
        setValue(DEFAULTS[key], false)
    end
end

-- ---------- Build Main tab rows ----------
do
    local defs = {
        { key = "disablePostFX",    title = "Disable Post-Effects",  sub = "Bloom · Blur · SunRays · ColorCorrection" },
        { key = "disableParticles", title = "Disable Particles",     sub = "ParticleEmitter · Trail · Fire · Smoke" },
        { key = "flattenMaterials", title = "Flatten Materials",     sub = "Plastic · Reflectance 0 · CastShadow off" },
        { key = "removeTextures",   title = "Remove Textures",       sub = "Decal · Texture · Transparency = 1" },
    }
    for i, d in ipairs(defs) do
        local row, t, s = makeRow(panels.main, i)
        t.Text = d.title
        s.Text = d.sub
        buildToggle(row, d.key, state[d.key])
    end
end

-- ---------- Build Performance tab rows ----------
do
    -- FPS Cap
    local row1, t1, s1 = makeRow(panels.perf, 1)
    t1.Text = "FPS Cap"
    s1.Text = "setfpscap(value)"
    buildSlider(row1, "fpsCap", 30, 240, 10, "", nil)

    -- Start Delay
    local row2, t2, s2 = makeRow(panels.perf, 2)
    t2.Text = "Start Delay"
    s2.Text = "task.wait(seconds)"
    buildSlider(row2, "startDelay", 0, 10, 1, "s", nil)

    -- Batch Size
    local row3, t3, s3 = makeRow(panels.perf, 3)
    t3.Text = "Batch Size"
    s3.Text = "objects per task.wait()"
    buildSlider(row3, "batchSize", 50, 1000, 50, "", nil)

    -- Optimize Terrain
    local row4, t4, s4 = makeRow(panels.perf, 4)
    t4.Text = "Optimize Terrain Water"
    s4.Text = "WaveSize 0 · Reflectance 0"
    buildToggle(row4, "optimizeTerrain", state.optimizeTerrain)

    -- Global Shadows
    local row5, t5, s5 = makeRow(panels.perf, 5)
    t5.Text = "Disable Global Shadows"
    s5.Text = "Lighting.GlobalShadows = false"
    buildToggle(row5, "globalShadowsOff", state.globalShadowsOff)
end

-- ---------- Build Output tab ----------
local consoleFrame = new("Frame", {
    BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 1, 0),
    ZIndex = 11,
}, { panels.log })
new("UIListLayout", {
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 2),
}, { consoleFrame })

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

    local lbl = new("TextLabel", {
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

    -- Cap the buffer
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
        consoleScroll.CanvasPosition = Vector2.new(0, consoleScroll.AbsoluteCanvasSize.Y)
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
        Position = UDim2.new(0, 0, 0, 12),
        Size = UDim2.new(0, primary and 0 or 90, 0, 32),
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
        local g = new("UIGradient", {
            Rotation = 45,
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, C.accent),
                ColorSequenceKeypoint.new(1, C.accent2),
            }),
        }, { btn })
        btn.Size = UDim2.new(1, -110, 0, 32)
        btn.Position = UDim2.new(0, 100, 0, 12)
    else
        btn.Position = UDim2.new(0, 12, 0, 12)
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
    Text = "  ⚡   FPS Booster",
    TextColor3 = C.text,
    TextSize = 12,
    AutoButtonColor = false,
    Visible = false,
    ZIndex = 100,
}, { gui })
corner(22, chip)
stroke(C.line, 0.88, 1, chip)

-- ============================================================
-- 9. TAB SWITCHING
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
-- 10. DRAGGING
-- ============================================================
local dragging = false
local dragStart, startPos

titlebar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = window.Position
    end
end)

titlebar.InputChanged:Connect(function(input)
    if not dragging then return end
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
        dragging = false
    end
end)

-- ============================================================
-- 11. MINIMIZE / CLOSE / REOPEN
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
-- 12. APPLY / RESET
-- ============================================================
local applied = false

local function refreshLightingLoop()
    -- Continuously re-apply the lightest settings, since some games
    -- reset them. Cheap and safe.
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
        logLine("[FPS Booster] Re-applying configuration…", "dim")
    else
        logLine("[FPS Booster] Initializing client-side optimizer…", "dim")
    end

    if state.globalShadowsOff then
        logLine("Lighting.GlobalShadows = false", "ok")
    end
    if state.disablePostFX then
        logLine("Disabling PostEffect instances…", "ok")
    end
    if state.optimizeTerrain then
        logLine("Terrain.WaterWaveSize = 0", "ok")
    end

    logLine("setfpscap(" .. tostring(state.fpsCap) .. ")", "ok")
    logLine("Waiting " .. tostring(state.startDelay) .. "s for game to load…", "dim")

    local active = {}
    if state.flattenMaterials then table.insert(active, "flattenMaterials") end
    if state.disableParticles then table.insert(active, "disableParticles") end
    if state.removeTextures   then table.insert(active, "removeTextures")   end

    if #active > 0 then
        logLine("Scanning workspace (" .. table.concat(active, ", ") .. ")…", "dim")
        logLine("Batch size: " .. tostring(state.batchSize) .. " objects per task.wait()", "dim")
    end

    if not state.removeTextures then
        logLine("Textures preserved (removeTextures = false)", "warn")
    end

    -- Run after startDelay
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

    if not applied then
        applied = true
        refreshLightingLoop()
    end
end)

btnReset.MouseButton1Click:Connect(function()
    -- Reset state to defaults
    for k, v in pairs(DEFAULTS) do state[k] = v end

    -- Rebuild the UI from scratch (cleanest way to reset visual controls)
    local ok = pcall(function() gui:Destroy() end)
    _G.__FPS_BOOSTER_INSTANCE = nil

    task.wait(0.05)

    -- Re-execute the whole script
    local src = debug.getinfo(1, "S").source
    if src and src:sub(1, 1) == "@" then
        local path = src:sub(2)
        local f = loadfile(path)
        if f then
            f()
        else
            -- Fallback: ask the user to re-run
            toast("FPS Booster", "Reset requires re-running the script.")
        end
    end
end)

-- ============================================================
-- 13. BOOT
-- ============================================================
selectTab("main")

logLine("FPS Booster v1.0 loaded.", "ok")
logLine("Ready. Configure options and press Apply.", "dim")
logLine("Tip: drag the title bar to reposition this window.", "dim")

task.delay(0.7, function()
    toast("FPS Booster", "Menu loaded. Adjust settings, then press Apply.")
end)

print("[FPS Booster] UI loaded successfully.")
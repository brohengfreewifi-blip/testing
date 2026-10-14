print("TEST 2: building minimal UI")

local Players = game:GetService("Players")
local lp = Players.LocalPlayer
if not lp then
    repeat task.wait(0.1); lp = Players.LocalPlayer until lp
end

local parent
if type(gethui) == "function" then
    local ok, h = pcall(gethui)
    if ok and typeof(h) == "Instance" then parent = h end
end
if not parent then
    parent = game:GetService("CoreGui")
end

print("TEST 2: parent =", parent)

local gui = Instance.new("ScreenGui")
gui.Name = "TestGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 9999
gui.Parent = parent

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 300, 0, 150)
frame.Position = UDim2.new(0.5, -150, 0.5, -75)
frame.BackgroundColor3 = Color3.fromRGB(123, 92, 255)
frame.BorderSizePixel = 0
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = frame

local label = Instance.new("TextLabel")
label.Size = UDim2.new(1, 0, 1, 0)
label.BackgroundTransparency = 1
label.Text = "IF YOU SEE THIS, IT WORKS"
label.TextColor3 = Color3.new(1, 1, 1)
label.TextScaled = true
label.Font = Enum.Font.GothamBold
label.Parent = frame

print("TEST 2: DONE - purple box should be visible")
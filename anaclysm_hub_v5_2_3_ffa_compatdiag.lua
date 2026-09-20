--[[
================================================================================
    anaclysm hub  v5.2.3 ffa + compatibility diagnostics
    Один LocalScript.  StarterPlayer > StarterPlayerScripts
--------------------------------------------------------------------------------
    Меню открывается сразу при запуске.
    Сверху: [—] свернуть (вернуть меню можно кликом по watermark) и [X] полностью закрыть.
    ПКМ по функции или включение функции — раскрывает её настройки прямо под ней.
    Биндов по умолчанию нет — назначаются вручную (включая ПКМ / любые кнопки мыши).
    Правый нижний угол окна — свободное изменение размера.
    Именованные конфиги: сохранение, загрузка, удаление.
================================================================================
]]

--==============================================================================
-- СЕРВИСЫ
--==============================================================================
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local Lighting         = game:GetService("Lighting")
local HttpService      = game:GetService("HttpService")
local GuiService       = game:GetService("GuiService")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local Stats            = game:GetService("Stats")
local TeleportService  = game:GetService("TeleportService")

local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()
local Camera = workspace.CurrentCamera
if not Camera then
	workspace:GetPropertyChangedSignal("CurrentCamera"):Wait()
	Camera = workspace.CurrentCamera
end

--==============================================================================
-- RUNTIME / SELF-CHECK
--==============================================================================
local BOOT_PLAYER_GUI = LP:WaitForChild("PlayerGui")
local RUNTIME_BOOT = { legacyFound = false, priorStableFound = false }

-- v5+ can shut down the previous instance cleanly before starting again.
local oldRuntime = BOOT_PLAYER_GUI:FindFirstChild("_anaclysm_runtime")
if oldRuntime then
	RUNTIME_BOOT.priorStableFound = true
	local ev = oldRuntime:FindFirstChild("Shutdown")
	if ev and ev:IsA("BindableEvent") then pcall(function() ev:Fire() end) end
	task.wait()
	pcall(function() oldRuntime:Destroy() end)
end

-- Best-effort cleanup for v4 and older instances that did not expose a runtime marker.
for _, name in ipairs({ "anaclysm_hub", "anaclysm_loader" }) do
	local old = BOOT_PLAYER_GUI:FindFirstChild(name)
	if old then
		RUNTIME_BOOT.legacyFound = true
		pcall(function() old:Destroy() end)
	end
end
for _, name in ipairs({ "_an_blur", "_an_loadblur", "_an_cc" }) do
	local old = Lighting:FindFirstChild(name)
	if old then pcall(function() old:Destroy() end) end
end
pcall(function() RunService:UnbindFromRenderStep("anaclysm_main") end)
pcall(function() RunService:UnbindFromRenderStep("anaclysm_cursor") end)

local RUNTIME_MARKER = Instance.new("Folder")
RUNTIME_MARKER.Name = "_anaclysm_runtime"
RUNTIME_MARKER.Parent = BOOT_PLAYER_GUI
local SHUTDOWN_EVENT = Instance.new("BindableEvent")
SHUTDOWN_EVENT.Name = "Shutdown"
SHUTDOWN_EVENT.Parent = RUNTIME_MARKER

-- Optional APIs are never assumed to exist. Missing capabilities only disable
-- the corresponding optional path; the rest of the hub keeps running.
local RUNTIME_CAPS = {
	FileIO = (type(writefile) == "function" and type(readfile) == "function"),
	MetaHook = (type(getrawmetatable) == "function" and type(setreadonly) == "function" and type(getnamecallmethod) == "function"),
	NewCClosure = (type(newcclosure) == "function"),
	Clipboard = (type(setclipboard) == "function"),
}
local okVU = pcall(function() return game:GetService("VirtualUser") end)
RUNTIME_CAPS.VirtualUser = okVU

local WORLD_BASE = { Gravity = workspace.Gravity }
local START_CAMERA_FOV = Camera and Camera.FieldOfView or 70
local START_CAMERA_MODE = LP.CameraMode
local START_MOUSE_BEHAVIOR = UserInputService.MouseBehavior
local START_MOUSE_ICON = UserInputService.MouseIconEnabled
local HUM_BASE = setmetatable({}, { __mode = "k" })

-- Lightweight compatibility trace. It stays mostly idle unless the diagnostics
-- panel is open or the character has just respawned.
local COMPAT_DIAG = {
	panelOpen = false,
	traceUntil = 0,
	respawnGuardUntil = 0,
	lastWriter = "—",
	lastPhase = "—",
	lastChanges = "—",
	lastAt = 0,
	lastToggle = "—",
	lastToggleAt = 0,
	lastEvent = "boot",
	history = {},
}

local function captureHumanoidBase(h)
	if not h or HUM_BASE[h] then return HUM_BASE[h] end
	local rec = {
		WalkSpeed = h.WalkSpeed,
		JumpPower = h.JumpPower,
		JumpHeight = h.JumpHeight,
		UseJumpPower = h.UseJumpPower,
		AutoRotate = h.AutoRotate,
		PlatformStand = h.PlatformStand,
		CameraOffset = h.CameraOffset,
	}
	HUM_BASE[h] = rec
	return rec
end

local function baseWalkSpeed(h)
	local b = captureHumanoidBase(h)
	return (b and b.WalkSpeed) or 16
end

local function restoreHumanoid(h)
	if not h then return end
	local b = HUM_BASE[h]
	if not b then return end
	pcall(function()
		h.WalkSpeed = b.WalkSpeed
		h.AutoRotate = b.AutoRotate
		h.PlatformStand = b.PlatformStand
		h.CameraOffset = b.CameraOffset
		if b.UseJumpPower then h.JumpPower = b.JumpPower else h.JumpHeight = b.JumpHeight end
	end)
end

--==============================================================================
-- УТИЛИТЫ
--==============================================================================
local CONNS = {}
local function bind(signal, fn)
	local c = signal:Connect(fn)
	table.insert(CONNS, c)
	return c
end

local function New(class, props, children)
	local o = Instance.new(class)
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then parent = v else o[k] = v end
	end
	for _, c in ipairs(children or {}) do c.Parent = o end
	if parent then o.Parent = parent end
	return o
end

local function corner(p, r)
	return New("UICorner", { CornerRadius = UDim.new(0, r or 8), Parent = p })
end
local function round1(p)
	return New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = p })
end
local function stroke(p, color, thick, trans)
	return New("UIStroke", {
		Color = color or Color3.fromRGB(40, 41, 54), Thickness = thick or 1,
		Transparency = trans or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = p,
	})
end
local function padding(p, t, b, l, r)
	return New("UIPadding", {
		PaddingTop = UDim.new(0, t or 0), PaddingBottom = UDim.new(0, b or t or 0),
		PaddingLeft = UDim.new(0, l or 0), PaddingRight = UDim.new(0, r or l or 0), Parent = p,
	})
end
local function list(p, pad, dir)
	return New("UIListLayout", {
		Padding = UDim.new(0, pad or 6), FillDirection = dir or Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder, Parent = p,
	})
end

local ANIM = true
local EASE_OUT   = Enum.EasingStyle.Quint
local EASE_SPRING= Enum.EasingStyle.Back

local function tw(obj, time, props, style, dir)
	if not ANIM then
		for k, v in pairs(props) do obj[k] = v end
		return nil
	end
	local t = TweenService:Create(obj, TweenInfo.new(time, style or EASE_OUT,
		dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function hexToColor(hex)
	hex = tostring(hex):gsub("#", "")
	if #hex < 6 then return Color3.fromRGB(124, 92, 255) end
	return Color3.fromRGB(tonumber(hex:sub(1, 2), 16) or 0,
		tonumber(hex:sub(3, 4), 16) or 0, tonumber(hex:sub(5, 6), 16) or 0)
end
local function colorToHex(c)
	return string.format("#%02X%02X%02X", math.floor(c.R * 255 + .5),
		math.floor(c.G * 255 + .5), math.floor(c.B * 255 + .5))
end
local function deepCopy(t)
	local o = {}
	for k, v in pairs(t) do o[k] = (type(v) == "table") and deepCopy(v) or v end
	return o
end
local function snap(n, step)
	step = step or 1
	return math.floor(n / step + 0.5) * step
end

--==============================================================================
-- ТЕМА
--==============================================================================
local Theme = {
	Accent  = Color3.fromRGB(124, 92, 255),
	Accent2 = Color3.fromRGB(64, 204, 255),
	Bg      = Color3.fromRGB(10, 10, 14),
	Bg2     = Color3.fromRGB(14, 14, 20),
	Card    = Color3.fromRGB(20, 20, 27),
	Row     = Color3.fromRGB(27, 28, 37),
	Deep    = Color3.fromRGB(8, 8, 11),
	Stroke  = Color3.fromRGB(38, 39, 52),
	Text    = Color3.fromRGB(238, 240, 248),
	Sub     = Color3.fromRGB(132, 136, 158),
	Dim     = Color3.fromRGB(78, 81, 98),
	Good    = Color3.fromRGB(72, 220, 140),
	Warn    = Color3.fromRGB(255, 186, 72),
	Bad     = Color3.fromRGB(255, 84, 100),
}

-- шрифты подбираются в рантайме: часть начертаний Gotham убрали из Enum.Font
local function pickFont(names)
	for _, n in ipairs(names) do
		local ok, f = pcall(function() return (Enum.Font :: any)[n] end)
		if ok and f then return f end
	end
	return Enum.Font.SourceSans
end
local FB  = pickFont({ "GothamBold", "GothamBlack", "SourceSansBold" })
local FSB = pickFont({ "GothamSemibold", "GothamMedium", "GothamBold", "SourceSansSemibold" })
local FM  = pickFont({ "GothamMedium", "Gotham", "SourceSans" })

--==============================================================================
-- ЭКРАН ЗАГРУЗКИ
--==============================================================================
local Loader = {}
do
	local pg = LP:WaitForChild("PlayerGui")
	local gui = New("ScreenGui", {
		Name = "anaclysm_loader", ResetOnSpawn = false, IgnoreGuiInset = true,
		DisplayOrder = 2147483647, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = pg,
	})
	pcall(function() gui.OnTopOfCoreBlur = true end)

	local lblur = Instance.new("BlurEffect")
	lblur.Name = "_an_loadblur"
	lblur.Size = 0
	lblur.Parent = Lighting
	TweenService:Create(lblur, TweenInfo.new(0.6), { Size = 22 }):Play()

	local dim = New("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(5, 5, 8),
		BackgroundTransparency = 1, BorderSizePixel = 0, Parent = gui,
	})
	TweenService:Create(dim, TweenInfo.new(0.5), { BackgroundTransparency = 0.18 }):Play()

	-- мягкое свечение за карточкой
	local halo = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(560, 300), BackgroundColor3 = Theme.Accent,
		BackgroundTransparency = 0.93, BorderSizePixel = 0, Parent = gui,
	})
	corner(halo, 60)
	task.spawn(function()
		local info = TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		TweenService:Create(halo, info, { BackgroundTransparency = 0.86, Size = UDim2.fromOffset(620, 340) }):Play()
	end)

	local card = New("CanvasGroup", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 22),
		Size = UDim2.fromOffset(470, 282), BackgroundColor3 = Theme.Bg,
		GroupTransparency = 1, BorderSizePixel = 0, Parent = gui,
	})
	corner(card, 18)
	-- боковая панель как в меню
	local sidePane = New("Frame", {
		Size = UDim2.new(0, 8, 1, 0), BackgroundColor3 = Theme.Bg2, BorderSizePixel = 0, Parent = card,
	})
	New("Frame", {
		Position = UDim2.new(0, 0, 0, 0), Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Parent = sidePane,
	})
	-- тонкая сетка на фоне карточки
	for i = 1, 7 do
		New("Frame", {
			Position = UDim2.new(0, 0, i / 8, 0), Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Theme.Stroke, BackgroundTransparency = 0.82,
			BorderSizePixel = 0, ZIndex = 0, Parent = card,
		})
	end
	local cs = stroke(card, Theme.Stroke, 1.4)
	TweenService:Create(card, TweenInfo.new(0.55, Enum.EasingStyle.Quint), {
		GroupTransparency = 0, Position = UDim2.fromScale(0.5, 0.5),
	}):Play()

	local line = New("Frame", {
		Size = UDim2.new(1, -48, 0, 2), Position = UDim2.new(0.5, 0, 0, 0), AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Parent = card,
	})
	corner(line, 2)
	local lgrad = New("UIGradient", { Color = ColorSequence.new(Theme.Accent, Theme.Accent2), Parent = line })
	task.spawn(function()
		local info = TweenInfo.new(2.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		lgrad.Offset = Vector2.new(-0.4, 0)
		TweenService:Create(lgrad, info, { Offset = Vector2.new(0.4, 0) }):Play()
	end)


	-- мягкий сканирующий блик по карточке
	local scanLine = New("Frame", {
		Position = UDim2.new(0, 18, 0, 82), Size = UDim2.new(1, -36, 0, 1),
		BackgroundColor3 = Theme.Accent2, BackgroundTransparency = 0.9,
		BorderSizePixel = 0, ZIndex = 1, Parent = card,
	})
	task.spawn(function()
		while gui.Parent and scanLine.Parent do
			scanLine.Position = UDim2.new(0, 18, 0, 82)
			scanLine.BackgroundTransparency = 0.94
			local t = TweenService:Create(scanLine, TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Position = UDim2.new(0, 18, 1, -34), BackgroundTransparency = 0.78,
			})
			t:Play()
			t.Completed:Wait()
			task.wait(0.35)
		end
	end)

	-- логотип
	local mark = New("Frame", {
		Position = UDim2.new(0, 34, 0, 34), Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Parent = card,
	})
	corner(mark, 13)
	New("UIGradient", { Color = ColorSequence.new(Theme.Accent, Theme.Accent2), Rotation = 40, Parent = mark })
	local dia = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = Theme.Bg2, BorderSizePixel = 0, Rotation = 45, Parent = mark,
	})
	corner(dia, 3)
	task.spawn(function()
		local info = TweenInfo.new(3, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false)
		TweenService:Create(dia, info, { Rotation = 405 }):Play()
	end)

	New("TextLabel", {
		Position = UDim2.new(0, 86, 0, 37), Size = UDim2.new(1, -120, 0, 21), BackgroundTransparency = 1,
		Font = FB, TextSize = 21, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
		Text = "anaclysm hub", Parent = card,
	})
	New("TextLabel", {
		Position = UDim2.new(0, 86, 0, 59), Size = UDim2.new(1, -120, 0, 14), BackgroundTransparency = 1,
		Font = FM, TextSize = 11, TextColor3 = Theme.Sub, TextXAlignment = Enum.TextXAlignment.Left,
		Text = "v5.0  ·  stable mega core", Parent = card,
	})
	local hint = New("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(1, -60, 0, 13),
		BackgroundTransparency = 1, Font = FM, TextSize = 10, TextColor3 = Theme.Dim,
		Text = "правый CTRL — открыть меню  ·  ПКМ по функции — её настройки", Parent = card,
	})

	-- список стадий
	local STAGES = {
		{ 38,  "серверное хранилище" },
		{ 58,  "интерфейс" },
		{ 80,  "модули" },
		{ 92,  "конфигурация" },
	}
	local rows = {}
	for i, st in ipairs(STAGES) do
		local y = 96 + (i - 1) * 22
		local box = New("Frame", {
			Position = UDim2.new(0, 34, 0, y), Size = UDim2.fromOffset(12, 12),
			BackgroundColor3 = Theme.Deep, BorderSizePixel = 0, Parent = card,
		})
		corner(box, 4)
		local bs = stroke(box, Theme.Stroke, 1)
		local tick = New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(0, 0), BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Parent = box,
		})
		corner(tick, 2)
		local txt = New("TextLabel", {
			Position = UDim2.new(0, 54, 0, y - 1), Size = UDim2.new(1, -90, 0, 14), BackgroundTransparency = 1,
			Font = FM, TextSize = 11, TextColor3 = Theme.Dim, TextXAlignment = Enum.TextXAlignment.Left,
			Text = st[2], Parent = card,
		})
		rows[i] = { need = st[1], box = box, bs = bs, tick = tick, txt = txt, done = false }
	end

	local status = New("TextLabel", {
		Position = UDim2.new(0, 34, 0, 196), Size = UDim2.new(1, -140, 0, 14), BackgroundTransparency = 1,
		Font = FSB, TextSize = 12, TextColor3 = Theme.Sub, TextXAlignment = Enum.TextXAlignment.Left,
		Text = "инициализация ядра", Parent = card,
	})
	local pct = New("TextLabel", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -34, 0, 194), Size = UDim2.fromOffset(70, 16),
		BackgroundTransparency = 1, Font = FB, TextSize = 15, TextColor3 = Theme.Accent,
		TextXAlignment = Enum.TextXAlignment.Right, Text = "0%", Parent = card,
	})

	local track = New("Frame", {
		Position = UDim2.new(0, 34, 0, 220), Size = UDim2.new(1, -68, 0, 8),
		BackgroundColor3 = Theme.Deep, BorderSizePixel = 0, Parent = card,
	})
	New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = track })
	stroke(track, Theme.Stroke, 1, 0.4)
	local fill = New("Frame", {
		Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Parent = track,
	})
	New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = fill })
	New("UIGradient", { Color = ColorSequence.new(Theme.Accent, Theme.Accent2), Parent = fill })
	local head = New("Frame", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(8, 8),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = fill,
	})
	New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = head })
	local headGlow = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = Theme.Accent2, BackgroundTransparency = 0.6, BorderSizePixel = 0, Parent = head,
	})
	New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = headGlow })

	local target, shown, done = 0, 0, false

	task.spawn(function()
		while not done do
			shown = shown + (target - shown) * 0.12
			if math.abs(target - shown) < 0.3 then shown = target end
			local a = math.clamp(shown / 100, 0, 1)
			fill.Size = UDim2.new(a, 0, 1, 0)
			pct.Text = math.floor(shown + 0.5) .. "%"
			head.Visible = a > 0.02 and a < 0.999
			for _, r in ipairs(rows) do
				if not r.done and shown >= r.need then
					r.done = true
					r.txt.TextColor3 = Theme.Text
					r.bs.Color = Theme.Accent
					TweenService:Create(r.tick, TweenInfo.new(0.25, Enum.EasingStyle.Back), {
						Size = UDim2.fromOffset(6, 6),
					}):Play()
				end
			end
			task.wait(0.03)
		end
	end)

	function Loader.set(p, text)
		target = math.clamp(p, 0, 100)
		if text then status.Text = text end
	end

	function Loader.finish()
		if done then return end
		Loader.set(100, "готово")
		task.wait(0.5)
		done = true
		TweenService:Create(card, TweenInfo.new(0.4, Enum.EasingStyle.Quint), {
			GroupTransparency = 1, Position = UDim2.new(0.5, 0, 0.5, -18),
		}):Play()
		TweenService:Create(halo, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(dim, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(cs, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		TweenService:Create(lblur, TweenInfo.new(0.45), { Size = 0 }):Play()
		task.delay(0.6, function()
			gui:Destroy()
			lblur:Destroy()
		end)
	end
end

local AccentObjs = {}
local function accent(obj, prop, alt)
	table.insert(AccentObjs, { obj = obj, prop = prop, alt = alt })
	if obj:IsA("UIGradient") then
		obj.Color = ColorSequence.new(Theme.Accent, Theme.Accent2)
	else
		obj[prop] = alt and Theme.Accent2 or Theme.Accent
	end
	return obj
end
local function applyAccent()
	for i = #AccentObjs, 1, -1 do
		local e = AccentObjs[i]
		if not e.obj or not e.obj.Parent then
			table.remove(AccentObjs, i)
		elseif e.obj:IsA("UIGradient") then
			e.obj.Color = ColorSequence.new(Theme.Accent, Theme.Accent2)
		else
			e.obj[e.prop] = e.alt and Theme.Accent2 or Theme.Accent
		end
	end
end

--==============================================================================
-- КЛАВИШИ
--==============================================================================
local KEYMAP = {}
for _, k in ipairs(Enum.KeyCode:GetEnumItems()) do KEYMAP[k.Name] = k end

local KEY_SHORT = {
	RightControl = "RCTRL", LeftControl = "LCTRL", RightShift = "RSHIFT", LeftShift = "LSHIFT",
	RightAlt = "RALT", LeftAlt = "LALT", MouseButton1 = "ЛКМ", MouseButton2 = "ПКМ",
	MouseButton3 = "СКМ", Space = "ПРОБЕЛ", Return = "ENTER", Backspace = "BACK", Insert = "INS",
}
local function keyLabel(name)
	if name == nil or name == "" then return "нет" end
	return KEY_SHORT[name] or name:upper()
end

local MB = {
	MouseButton1 = Enum.UserInputType.MouseButton1,
	MouseButton2 = Enum.UserInputType.MouseButton2,
	MouseButton3 = Enum.UserInputType.MouseButton3,
}

local function keyDown(name)
	if name == nil or name == "" then return false end
	if MB[name] then return UserInputService:IsMouseButtonPressed(MB[name]) end
	local kc = KEYMAP[name]
	return kc ~= nil and UserInputService:IsKeyDown(kc)
end

local function keyMatches(input, name)
	if name == nil or name == "" then return false end
	if MB[name] then return input.UserInputType == MB[name] end
	return input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode.Name == name
end

--==============================================================================
-- РЕЕСТР ФУНКЦИЙ
--==============================================================================
local Features, ById = {}, {}
local DB = {}

local function Feature(def)
	def.Options = def.Options or {}
	def._active = false
	def._faulted = false
	def._faultCount = 0
	def._faultWindow = 0
	def._lastError = nil
	local rec = { on = def.On or false, key = "", mode = def.Mode or "Toggle", o = {} }
	for _, opt in ipairs(def.Options) do
		if opt.Type ~= "Button" and opt.Type ~= "Label" then rec.o[opt.Id] = opt.Default end
	end
	DB[def.Id] = rec
	def._default = deepCopy(rec)
	table.insert(Features, def)
	ById[def.Id] = def
	return def
end

local function O(id, oid) return DB[id].o[oid] end
local function OC(id, oid) return hexToColor(DB[id].o[oid]) end

local function isActive(f)
	local d = DB[f.Id]
	if f._faulted then return false end
	if not d.on then return false end
	if d.mode == "Hold" then return keyDown(d.key) end
	return true
end

local Notify, refreshRows, markDirty, resetPanels, setScaleLive, setTransLive, tpApply, fovConn, viewportConn
local infoFps = 60
local RUNTIME_ERRORS = {}
local function recordFeatureError(f, phase, err)
	local now = os.clock()
	if now - (f._faultWindow or 0) > 5 then
		f._faultWindow = now
		f._faultCount = 0
	end
	f._faultCount = (f._faultCount or 0) + 1
	f._lastError = tostring(err)
	RUNTIME_ERRORS[f.Id] = { phase = phase, error = tostring(err), time = now, count = f._faultCount }
	warn("[anaclysm] " .. f.Id .. " (" .. phase .. ") -> " .. tostring(err))
	if f._faultCount >= 4 then
		f._faulted = true
		f._active = false
		if DB[f.Id] then DB[f.Id].on = false end
		if f._row then pcall(f._row.refresh) end
		if Notify then Notify(f.Name .. " отключён после повторных ошибок", "bad") end
	end
end
-- точка, из которой реально ведётся прицеливание (в третьем лице это не камера)
local tpFocusPoint

local function syncState(f, silent)
	local a = isActive(f)
	if a ~= f._active then
		f._active = a
		if f.OnToggle then
			COMPAT_DIAG.lastToggle = f.Id .. (a and " : ON" or " : OFF")
			COMPAT_DIAG.lastToggleAt = os.clock()
			local ok, err = pcall(f.OnToggle, a)
			if not ok then recordFeatureError(f, "toggle", err) end
		end
		if f._row then f._row.refresh() end
	end
	if not silent and f._row then f._row.refresh() end
end

local function setOn(id, v)
	local f = ById[id]
	if not f then return end
	if v then
		f._faulted = false
		f._faultCount = 0
		f._lastError = nil
	end
	DB[id].on = v
	syncState(f)
	if markDirty then markDirty() end
end

--==============================================================================
-- НАСТРОЙКИ ИНТЕРФЕЙСА
--==============================================================================
local DEFAULT_UI = {
	MenuKey    = "RightControl",
	Accent     = "#7C5CFF",
	Accent2    = "#40CCFF",
	W          = 812,
	H          = 548,
	X          = 0,
	Y          = 0,
	Scale      = 1,
	Blur       = true,
	Animations = true,
	AutoSave   = true,
	AutoExpand = true,
	Advanced   = true,
	FreeMouse  = true,
	EscHide    = true,
	WmX        = 16,
	WmY        = 16,
	FloatX     = -1,
	FloatY     = -1,
	RadarX     = -1,
	RadarY     = -1,
	TargetX    = -1,
	TargetY    = -1,
	PerfX      = -1,
	PerfY      = -1,
	ThreatX    = -1,
	ThreatY    = -1,
	QuickX     = -1,
	QuickY     = -1,
	Favorites  = {},
	LayoutPreset = "Balanced",
	Trans      = 0,
}
local UICFG = deepCopy(DEFAULT_UI)

-- v5.0 shared UI/session state -------------------------------------------------
local NOTIF_HISTORY = {}
local SESSION_METRICS = { minFps = 9999, maxFps = 0, avgFps = 0, fpsSamples = 0, respawns = 0, peakPlayers = 0 }
local quickBar, quickTitle
local quickButtons = {}
local applyHudEditVisuals

local function placeProfileName()
	return "__place_" .. tostring(game.PlaceId)
end

local function cleanHudActive()
	local f = ById.cleanhud
	return f and f._active == true
end

--==============================================================================
-- ХРАНИЛИЩЕ КОНФИГОВ
--   Приоритет: RemoteFunction "AnaclysmStore" в ReplicatedStorage (DataStore,
--   сохранение между сессиями) -> атрибут игрока (на время сессии).
--   Серверная часть для DataStore приложена комментарием в самом конце файла.
--==============================================================================
local STORE_ATTR = "anaclysm_store"
local _CFG = "anaclysm_hub.cfg"
local function diskSave(j)
	if not RUNTIME_CAPS.FileIO then return false end
	local ok = pcall(function() writefile(_CFG, j) end)
	return ok
end
local function diskLoad()
	if not RUNTIME_CAPS.FileIO then return nil end
	local ok, d = pcall(function() return readfile(_CFG) end)
	return (ok and type(d) == "string" and #d > 10) and d or nil
end
-- серверный модуль реплицируется не мгновенно: ждём его, иначе на старте
-- прочитаем пустоту и следом затрём сохранение автосейвом
Loader.set(12, "поиск серверного хранилища")
local RemoteStore = ReplicatedStorage:FindFirstChild("AnaclysmStore")
if not RemoteStore then
	RemoteStore = ReplicatedStorage:WaitForChild("AnaclysmStore", 1.5)
end
Loader.set(38, RemoteStore and "хранилище найдено" or (RUNTIME_CAPS.FileIO and "сервер недоступен · локальное хранилище" or "сервер недоступен · session fallback"))
task.wait(0.25)
if RemoteStore and not RemoteStore:IsA("RemoteFunction") then RemoteStore = nil end
local storeLoaded = false

-- configs — именованные пресеты, меняются только по явному сохранению
-- session — рабочее состояние, куда пишет автосохранение
local Store = { configs = {}, current = "default", session = nil }

local function snapshotNow()
	local s = { ui = deepCopy(UICFG), f = {} }
	for id, d in pairs(DB) do
		s.f[id] = { on = d.on, key = d.key, mode = d.mode, o = deepCopy(d.o) }
	end
	return s
end

local applyUI -- forward

local function applySnapshot(s)
	if type(s) ~= "table" then return false end
	if type(s.ui) == "table" then
		for k, v in pairs(DEFAULT_UI) do
			if s.ui[k] ~= nil and type(s.ui[k]) == type(v) then UICFG[k] = s.ui[k] end
		end
	end
	if type(s.f) == "table" then
		for id, d in pairs(s.f) do
			local rec = DB[id]
			if rec and type(d) == "table" then
				if type(d.on) == "boolean" then rec.on = d.on end
				if type(d.key) == "string" then rec.key = d.key end
				if type(d.mode) == "string" then rec.mode = d.mode end
				if type(d.o) == "table" then
					for k, v in pairs(d.o) do
						if rec.o[k] ~= nil and type(rec.o[k]) == type(v) then rec.o[k] = v end
					end
				end
			end
		end
	end
	if type(UICFG.Favorites) ~= "table" then UICFG.Favorites = {} end
	Theme.Accent, Theme.Accent2 = hexToColor(UICFG.Accent), hexToColor(UICFG.Accent2)
	ANIM = UICFG.Animations
	applyAccent()
	for _, f in ipairs(Features) do syncState(f, true) end
	if applyUI then applyUI() end
	if resetPanels then resetPanels() end
	if refreshRows then refreshRows() end
	return true
end

local storeWarned = false

local function writeStore(force)
	local ok, json = pcall(HttpService.JSONEncode, HttpService, Store)
	if not ok then return false end

	-- локальная копия пишется всегда: она спасает при вылете сервера.
	-- Attribute имеет ограничения по размеру, поэтому ошибка здесь не должна
	-- обрывать остальные способы сохранения.
	pcall(function() LP:SetAttribute(STORE_ATTR, json) end)
	diskSave(json)

	if RemoteStore then
		if #json >= 195000 then
			if not storeWarned and Notify then
				storeWarned = true
				Notify("Конфиг слишком большой для серверного хранилища; сохранён локально/в сессии", "warn")
			end
			return false
		end
		local sent, res = pcall(function()
			return RemoteStore:InvokeServer(force and "flush" or "save", json)
		end)
		if sent and res == true then
			storeWarned = false
			return true
		end
		if not storeWarned and Notify then
			storeWarned = true
			Notify("Сервер не принял конфиг, сохранение только на эту сессию", "bad")
		end
		return false
	end
	return true
end

local function flushStore()
	return writeStore(true)
end

local function readStore()
	local raw
	if RemoteStore then
		local ok, res = pcall(function() return RemoteStore:InvokeServer("load") end)
		if ok and type(res) == "string" then raw = res end
	end
	if not raw then raw = diskLoad() end
	if not raw then
		local a = LP:GetAttribute(STORE_ATTR)
		if type(a) == "string" then raw = a end
	end
	if not raw then return false end
	local ok, t = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or type(t) ~= "table" or type(t.configs) ~= "table" then return false end
	Store = t
	if type(Store.current) ~= "string" then Store.current = "default" end
	storeLoaded = true
	return true
end

local dirty = false
function markDirty() dirty = true end

-- тихое сохранение рабочего состояния (автосейв, сворачивание, выход)
local function saveSession()
	Store.session = snapshotNow()
	if DB.placeprofiles and O("placeprofiles", "autosave") then
		Store.configs[placeProfileName()] = deepCopy(Store.session)
	end
	writeStore()
	dirty = false
	return true
end

-- явное сохранение в именованный пресет
local function saveConfig(name, silent)
	name = (name and name ~= "" and name) or Store.current or "default"
	local snap = snapshotNow()
	Store.configs[name] = snap
	Store.session = deepCopy(snap)
	Store.current = name
	writeStore()
	flushStore()
	dirty = false
	if not silent and Notify then Notify("Конфиг «" .. name .. "» сохранён", "ok") end
	return true
end

local function loadConfig(name, silent)
	local s = Store.configs[name]
	if not s then
		if Notify and not silent then Notify("Конфиг «" .. tostring(name) .. "» не найден", "bad") end
		return false
	end
	for _, f in ipairs(Features) do
		if f._active and f.OnToggle then pcall(f.OnToggle, false) end
		f._active = false
	end
	applySnapshot(deepCopy(s))
	for _, f in ipairs(Features) do syncState(f) end
	Store.current = name
	Store.session = deepCopy(s)
	dirty = false
	writeStore()
	if not silent and Notify then Notify("Конфиг «" .. name .. "» загружен", "ok") end
	return true
end

local function deleteConfig(name)
	if name == "default" then
		if Notify then Notify("Базовый конфиг удалить нельзя", "warn") end
		return false
	end
	if not Store.configs[name] then return false end
	Store.configs[name] = nil
	if Store.current == name then Store.current = "default" end
	writeStore()
	if Notify then Notify("Конфиг «" .. name .. "» удалён", "warn") end
	return true
end

local function resetAll()
	for _, f in ipairs(Features) do
		DB[f.Id] = deepCopy(f._default)
	end
	UICFG = deepCopy(DEFAULT_UI)
	applySnapshot(snapshotNow())
	for _, f in ipairs(Features) do syncState(f) end
	markDirty()
	if Notify then Notify("Все настройки сброшены", "warn") end
end

local function resetBinds()
	for _, f in ipairs(Features) do
		DB[f.Id].key = ""
		DB[f.Id].mode = f._default.mode
		syncState(f)
	end
	UICFG.MenuKey = DEFAULT_UI.MenuKey
	markDirty()
	if refreshRows then refreshRows() end
	if Notify then Notify("Бинды сброшены", "warn") end
end

--==============================================================================
-- ХЕЛПЕРЫ ПЕРСОНАЖА
--==============================================================================
local function getChar() return LP.Character end
local function getHum()
	local c = getChar()
	local h = c and c:FindFirstChildOfClass("Humanoid")
	if h then captureHumanoidBase(h) end
	return h
end
local function getRoot() local c = getChar() return c and c:FindFirstChild("HumanoidRootPart") end
local function alive()
	local h = getHum()
	return h ~= nil and h.Health > 0 and getRoot() ~= nil
end
local function gameModeOverride()
	local rec = DB.gamemode
	local mode = rec and rec.o and rec.o.mode or "Auto"
	if mode == "FFA" or mode == "Teams" then return mode end
	return "Auto"
end

local function isEnemy(p)
	if p == LP then return false end
	local mode = gameModeOverride()
	-- Explicit FFA mode is intended for experiences where Roblox Team objects
	-- are reused for lobby/round bookkeeping even though everybody is an enemy.
	if mode == "FFA" then return true end
	if mode == "Teams" then
		if LP.Team and p.Team then return p.Team ~= LP.Team end
		return true
	end
	-- Auto: Neutral local players are normally in FFA / no-team states.
	if LP.Neutral then return true end
	if not LP.Team then return true end
	if p.Neutral then return true end
	-- Preserve the conservative lobby behavior for unteamed spectators.
	if not p.Team then return false end
	return p.Team ~= LP.Team
end
local function VP() return Camera.ViewportSize end

-- Streamer Mode helpers are intentionally safe to call before the feature is
-- registered: they become active only after ById.streamer exists.
local function streamerActive()
	local f = ById.streamer
	return f ~= nil and f._active == true
end

local function safePlayerLabel(p)
	if not p then return "Player" end
	if streamerActive() then
		if p == LP and O("streamer", "self") then
			local alias = tostring(O("streamer", "alias") or "ANON")
			return alias ~= "" and alias or "ANON"
		elseif p ~= LP and O("streamer", "players") then
			return string.format("Player %02d", (math.abs(p.UserId) % 97) + 1)
		end
	end
	return p.DisplayName
end

local function safeUserLabel(p)
	if not p then return "@player" end
	if streamerActive() then
		if p == LP and O("streamer", "self") then return "@hidden" end
		if p ~= LP and O("streamer", "players") then return "@player" end
	end
	return "@" .. p.Name
end

--==============================================================================
--                            Ф У Н К Ц И И
--==============================================================================
local ESP_FOLDER          -- ScreenGui-контейнер для рамок ESP
local aimCircle, aimLine  -- элементы аимбота
local crossParts = {}


-- Register-scope split: keeps Luau local-register usage safely below the per-function limit.
local function __anaclysm_feature_bootstrap()
	--------------------------------------------------------------------- MAIN ----
	
	local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local _mVert = 0
	local currentTarget = nil
	local aimRadius = 150
	
	local function partVisible(part, char, from)
		local origin = from or Camera.CFrame.Position
		local dir = part.Position - origin
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		if math.abs(dir.Unit.Y) > 0.45 then
			rp.FilterDescendantsInstances = { getChar(), workspace:FindFirstChildOfClass("Terrain") }
		else
			rp.FilterDescendantsInstances = { getChar() }
		end
		rp.IgnoreWater = true
		local res = workspace:Raycast(origin, dir, rp)
		return (res == nil) or res.Instance:IsDescendantOf(char)
	end
	
	Feature{
		Id = "aimbot", Tab = "Main", Group = "Прицеливание", Col = 1,
		Name = "Aimbot", Desc = "Доводка камеры до цели. Забиндите на ПКМ и режим «Hold».",
		Mode = "Hold",
		Options = {
			{ Id = "fov",   Type = "Slider", Name = "Радиус FOV", Min = 20, Max = 700, Default = 150, Step = 5, Suffix = "px" },
			{ Id = "stable",Type = "Toggle", Name = "Не зависеть от угла обзора", Default = true },
			{ Id = "smooth",Type = "Slider", Name = "Сила доводки", Min = 1, Max = 100, Default = 18, Suffix = "%" },
			{ Id = "snapv", Type = "Toggle", Name = "Мгновенный снап", Default = false },
			{ Id = "rate",  Type = "Slider", Name = "Предел скорости доводки", Min = 30, Max = 900, Default = 260, Step = 10, Suffix = "°/с" },
			{ Id = "dead",  Type = "Slider", Name = "Мёртвая зона", Min = 0, Max = 40, Default = 2, Suffix = "px" },
			{ Id = "part",  Type = "Dropdown", Name = "Точка прицела", List = { "Head", "UpperTorso", "HumanoidRootPart" }, Default = "Head" },
			{ Id = "sticky",Type = "Toggle", Name = "Держать цель", Default = true },
			{ Id = "team",  Type = "Toggle", Name = "Не наводиться на союзников", Default = true },
			{ Id = "wall",  Type = "Toggle", Name = "Проверка стен", Default = true },
			{ Id = "live",  Type = "Toggle", Name = "Только живые цели", Default = true },
			{ Id = "circle",Type = "Toggle", Name = "Показывать FOV", Default = true },
			{ Id = "line",  Type = "Toggle", Name = "Линия до цели", Default = false },
			{ Id = "col",   Type = "Color",  Name = "Цвет FOV", Default = "#7C5CFF" },
		},
		OnToggle = function(on) if not on then currentTarget = nil end end,
		Step = function(dt)
			if not alive() then currentTarget = nil return end
			local center = VP() / 2
			local radius = O("aimbot", "fov")
			-- при изменённом FOV один и тот же радиус в пикселях захватывает разный
			-- угол, поэтому приводим его к базовым 70 градусам
			if O("aimbot", "stable") then
				local cur = math.clamp(Camera.FieldOfView, 5, 170)
				radius = radius * (math.tan(math.rad(70 / 2)) / math.tan(math.rad(cur / 2)))
			end
			aimRadius = radius
			local pname  = O("aimbot", "part")
	
			local function eval(p)
				if p == LP then return nil end
				local ch = p.Character
				if not ch then return nil end
				local hum = ch:FindFirstChildOfClass("Humanoid")
				local _hp = (hum and hum.Health) or (ch:GetAttribute("Health")) or (ch:GetAttribute("HP")) or 0
				if O("aimbot", "live") and _hp <= 0 then return nil end
				if O("aimbot", "team") and not isEnemy(p) then return nil end
				local part = ch:FindFirstChild(pname) or ch:FindFirstChild("HumanoidRootPart")
				if not part then return nil end
				local sp, on = Camera:WorldToViewportPoint(part.Position)
				if not on then return nil end
				local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
				if d > radius then return nil end
				-- в третьем лице камера стоит позади персонажа, и луч из неё
				-- упирается в стены за спиной — проверяем от точки прицеливания
				local eye = (tpFocusPoint and tpFocusPoint()) or Camera.CFrame.Position
				if O("aimbot", "wall") and not partVisible(part, ch, eye) then return nil end
				return part, d
			end
	
			local target, best = nil, math.huge
			if O("aimbot", "sticky") and currentTarget and currentTarget.Parent then
				local p = Players:GetPlayerFromCharacter(currentTarget.Parent)
				if p then
					local part, d = eval(p)
					if part then target, best = part, d end
				end
			end
			if not target then
				for _, p in ipairs(Players:GetPlayers()) do
					local part, d = eval(p)
					if part and d < best then target, best = part, d end
				end
			end
			currentTarget = target
			if not target then return end
			if best <= O("aimbot", "dead") then return end
	
			local cam = Camera.CFrame
			-- в третьем лице камера смещена назад и вверх: если целиться от неё,
			-- прицел уходит выше персонажа. Целимся из точки обзора персонажа,
			-- тогда камера, персонаж и цель оказываются на одной прямой
			local _vel = Vector3.zero
			if target and target:IsA("BasePart") then _vel = target.AssemblyLinearVelocity end
			local goalRot = CFrame.lookAt(cam.Position, target.Position + _vel * 0.055).Rotation
			local goal = CFrame.new(cam.Position) * goalRot
			if O("aimbot", "snapv") then
				Camera.CFrame = goal
			else
				-- экспоненциальное сглаживание: одинаковое ощущение на любом фпс
				local k = (O("aimbot", "smooth") / 100) * 26
				local a = math.clamp(1 - math.exp(-k * dt), 0, 1)
	
				-- резкий доворот раскачивает вьюмодель оружия, поэтому угловую
				-- скорость камеры ограничиваем сверху
				local dot = math.clamp(cam.LookVector:Dot(goal.LookVector), -1, 1)
				local total = math.acos(dot)
				if total > 0.0001 then
					local maxStep = math.rad(O("aimbot", "rate")) * dt
					a = math.min(a, maxStep / total)
				end
				-- берём свежий CFrame прямо перед применением (мышь могла сдвинуть)
				local fresh = Camera.CFrame
				Camera.CFrame = CFrame.new(fresh.Position) * fresh.Rotation:Lerp(goalRot, a)
			end
		end,
	}
	
	local tbArmed, tbLastShot = 0, 0
	local tbTarget = nil
	local tbRemoteCache, tbRemoteName, tbRemoteTool = nil, nil, nil
	
	-- One compatibility layer is shared by Trigger Bot / Silent Aim / Rapid Fire.
	-- It intentionally scores common shooter remotes instead of hard-coding one game.
	local WEAPON_REMOTE_HINTS = {
		fire = 10, shoot = 10, shot = 9, bullet = 8, projectile = 8, cast = 6,
		hit = 6, damage = 5, gun = 5, weapon = 5, attack = 4, primary = 3,
	}
	local WEAPON_REMOTE_BAD = { reload = 12, equip = 10, unequip = 10, anim = 8, sound = 7,
		cosmetic = 7, skin = 7, inspect = 7, sprint = 5, stance = 5 }
	
	local function weaponRemoteScore(remote, tool, ch)
		if not remote or not (remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction")) then return -1000 end
		local name = remote.Name:lower()
		local score = 0
		for k, v in pairs(WEAPON_REMOTE_HINTS) do if name:find(k, 1, true) then score += v end end
		for k, v in pairs(WEAPON_REMOTE_BAD) do if name:find(k, 1, true) then score -= v end end
		if tool and remote:IsDescendantOf(tool) then score += 14
		elseif ch and remote:IsDescendantOf(ch) then score += 8
		elseif remote:IsDescendantOf(ReplicatedStorage) then score += 2 end
		return score
	end
	
	local function detectWeaponRemote(tool, ch)
		local best, bestScore = nil, 3
		local scopes = { tool, ch, ReplicatedStorage, LP:FindFirstChild("PlayerScripts") }
		for _, sc in ipairs(scopes) do
			if sc then
				local ok, descendants = pcall(function() return sc:GetDescendants() end)
				if ok then
					for i, d in ipairs(descendants) do
						if i > 5000 then break end
						local score = weaponRemoteScore(d, tool, ch)
						if score > bestScore then best, bestScore = d, score end
					end
				end
			end
		end
		return best, bestScore
	end
	
	-- forward declarations: Trigger Bot is registered before the learning implementation below.
	local WeaponIntel, weaponRemoteFresh, weaponConfidenceThreshold, markWeaponIntent
	
	local function resolveTriggerRemote(rname, tool, ch, allowAuto)
		local cacheKey = (rname ~= "" and rname) or (allowAuto and "__auto__" or "")
		if cacheKey == "" then return nil end
		if tbRemoteCache and tbRemoteCache.Parent and tbRemoteName == cacheKey and tbRemoteTool == tool then
			return tbRemoteCache
		end
		tbRemoteCache, tbRemoteName, tbRemoteTool = nil, cacheKey, tool
		if rname ~= "" then
			local scopes = { tool, ch, ReplicatedStorage, LP:FindFirstChild("PlayerScripts") }
			for _, sc in ipairs(scopes) do
				if sc then
					local d = sc:FindFirstChild(rname, true)
					if d and (d:IsA("RemoteEvent") or d:IsA("RemoteFunction")) then
						tbRemoteCache = d
						break
					end
				end
			end
		elseif allowAuto then
			if weaponRemoteFresh(WeaponIntel.learnedRemote) and WeaponIntel.learnedConfidence >= weaponConfidenceThreshold() then
				tbRemoteCache = WeaponIntel.learnedRemote
			else
				tbRemoteCache = select(1, detectWeaponRemote(tool, ch))
			end
		end
		return tbRemoteCache
	end
	
	local function fireTriggerRemote(remote, mode, hitPos, part)
		local args
		if mode == "Точка попадания" then
			args = table.pack(hitPos)
		elseif mode == "Точка + деталь" then
			args = table.pack(hitPos, part)
		elseif mode == "Деталь + точка" then
			args = table.pack(part, hitPos)
		else
			args = table.pack()
		end
		if remote:IsA("RemoteEvent") then
			remote:FireServer(table.unpack(args, 1, args.n))
		else
			remote:InvokeServer(table.unpack(args, 1, args.n))
		end
	end
	
	Feature{
		Id = "trigger", Tab = "Main", Group = "Прицеливание", Col = 1,
		Name = "Trigger Bot", Desc = "Auto выбирает Tool или распознанный weapon remote в зависимости от системы оружия",
		Options = {
			{ Id = "delay",  Type = "Slider", Name = "Задержка реакции", Min = 0, Max = 500, Default = 40, Step = 5, Suffix = "мс" },
			{ Id = "gap",    Type = "Slider", Name = "Интервал между выстрелами", Min = 20, Max = 1500, Default = 120, Step = 10, Suffix = "мс" },
			{ Id = "dist",   Type = "Slider", Name = "Дальность", Min = 50, Max = 3000, Default = 900, Step = 50, Suffix = "st" },
			{ Id = "team",   Type = "Toggle", Name = "Не стрелять по союзникам", Default = true },
			{ Id = "head",   Type = "Toggle", Name = "Только по голове", Default = false },
			{ Id = "needtool", Type = "Toggle", Name = "Требовать оружие в руках", Default = false },
			{ Id = "release",Type = "Toggle", Name = "Отпускать после выстрела", Default = true },
			{ Id = "method", Type = "Dropdown", Name = "Способ выстрела",
			  List = { "Auto", "Tool:Activate", "RemoteEvent", "Оба" }, Default = "Auto" },
			{ Id = "remote", Type = "Text", Name = "Имя RemoteEvent", Default = "", Placeholder = "пусто = автоопределение" },
			{ Id = "auto", Type = "Toggle", Name = "Автоопределение weapon remote", Default = true },
			{ Id = "args",   Type = "Dropdown", Name = "Аргументы ремоута",
			  List = { "Точка попадания", "Точка + деталь", "Деталь + точка", "Без аргументов" }, Default = "Точка попадания" },
			{ Id = "scan",   Type = "Button", Name = "Найти RemoteEvent в игре", Run = function()
				local found = {}
				local function scan(root, limit)
					if not root then return end
					for _, d in ipairs(root:GetDescendants()) do
						if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
							table.insert(found, d.Name)
							if #found >= limit then return end
						end
					end
				end
				local ch = LP.Character
				scan(ch and ch:FindFirstChildOfClass("Tool"), 6)
				scan(ReplicatedStorage, 12)
				if #found == 0 then
					Notify("RemoteEvent не найдены", "warn")
				else
					Notify("Найдено: " .. table.concat(found, ", "), "ok")
				end
			end },
			{ Id = "hold",   Type = "Keybind", Name = "Стрелять только с клавишей", Default = "" },
			{ Id = "notify", Type = "Toggle", Name = "Отмечать срабатывание", Default = false },
		},
		OnToggle = function(on)
			if not on then
				tbArmed, tbTarget = 0, nil
			end
		end,
		Step = function()
			if not alive() then tbArmed, tbTarget = 0, nil return end
	
			local gate = O("trigger", "hold")
			if gate ~= "" and not keyDown(gate) then tbArmed, tbTarget = 0, nil return end
	
			local ch = getChar()
			local tool = ch and ch:FindFirstChildOfClass("Tool")
			if O("trigger", "needtool") and not tool then tbArmed, tbTarget = 0, nil return end
	
			local vp = VP()
			local ray = Camera:ViewportPointToRay(vp.X / 2, vp.Y / 2)
			local rp = RaycastParams.new()
			rp.FilterType = Enum.RaycastFilterType.Exclude
			rp.FilterDescendantsInstances = { ch }
			rp.IgnoreWater = true
			local res = workspace:Raycast(ray.Origin, ray.Direction * O("trigger", "dist"), rp)
	
			local targetPlayer, targetModel
			if res and res.Instance then
				local model = res.Instance:FindFirstAncestorOfClass("Model")
				local plr = model and Players:GetPlayerFromCharacter(model)
				if plr and plr ~= LP then
					local hum = model:FindFirstChildOfClass("Humanoid")
					local goodHead = (not O("trigger", "head")) or res.Instance.Name == "Head"
					if hum and hum.Health > 0 and goodHead and (not O("trigger", "team") or isEnemy(plr)) then
						targetPlayer, targetModel = plr, model
					end
				end
			end
	
			if not targetPlayer then tbArmed, tbTarget = 0, nil return end
	
			local now = os.clock()
			if tbTarget ~= targetPlayer then
				tbTarget = targetPlayer
				tbArmed = now
				return
			end
			if tbArmed == 0 then tbArmed = now return end
			if (now - tbArmed) * 1000 < O("trigger", "delay") then return end
			if (now - tbLastShot) * 1000 < O("trigger", "gap") then return end
	
			tbLastShot = now
			markWeaponIntent(0.32)
			local method = O("trigger", "method")
			local preferLearned = method == "Auto" and weaponRemoteFresh(WeaponIntel.learnedRemote)
				and WeaponIntel.learnedConfidence >= math.min(weaponConfidenceThreshold() + 8, 100)
	
			if (method == "Tool:Activate" or method == "Оба" or (method == "Auto" and tool ~= nil and not preferLearned)) and tool then
				local shotTool = tool
				pcall(function() shotTool:Activate() end)
				if O("trigger", "release") then
					task.delay(0.05, function()
						if shotTool and shotTool.Parent then pcall(function() shotTool:Deactivate() end) end
					end)
				end
			end
	
			if method == "RemoteEvent" or method == "Оба" or (method == "Auto" and (tool == nil or preferLearned)) then
				local rname = O("trigger", "remote")
				local remote = resolveTriggerRemote(rname, tool, ch, O("trigger", "auto"))
				if remote then
					local hitPos = res and res.Position or (ray.Origin + ray.Direction * O("trigger", "dist"))
					local part = res and res.Instance
					local ok = pcall(fireTriggerRemote, remote, O("trigger", "args"), hitPos, part)
					if not ok then tbRemoteCache = nil end
				elseif O("trigger", "notify") then
					Notify(rname ~= "" and ("RemoteEvent «" .. rname .. "» не найден") or "Weapon remote не определён", "bad")
				end
			end
	
			if O("trigger", "notify") then Notify("trigger: выстрел", "ok") end
		end,
	}
	
	local saHookInstalled = false
	local saOldNamecall = nil
	local saHookClosure = nil
	local saTool, saToolConn = nil, nil
	local saCurrentTarget = nil
	local weaponLastRemote, weaponLastArgs, weaponLastSeen = nil, nil, 0
	local weaponReplayGuard = false
	
	-- Universal Weapon Intelligence ------------------------------------------------
	-- Learns which remote actually behaves like the active weapon by combining
	-- name/path hints, argument shape and calls that happen close to real fire input.
	WeaponIntel = {
		candidates = setmetatable({}, { __mode = "k" }),
		learnedRemote = nil,
		learnedArgs = nil,
		learnedConfidence = 0,
		learnedAt = 0,
		intentUntil = 0,
		samples = 0,
		confirmed = 0,
		lastSignature = "—",
		lastPath = "—",
		scanRemote = nil,
		scanScore = 0,
	}
	
	local function weaponOption(id, fallback)
		local f = ById.weaponbridge
		local rec = DB.weaponbridge
		if f and rec and rec.o and rec.o[id] ~= nil then return rec.o[id] end
		return fallback
	end
	
	local function weaponArgSignature(args)
		if not args then return "—" end
		local out = {}
		for i = 1, math.min(args.n or #args, 8) do
			local v = args[i]
			local ty = typeof(v)
			if ty == "Instance" then
				table.insert(out, v.ClassName)
			elseif ty == "table" then
				local keys = {}
				for k in pairs(v) do
					if type(k) == "string" then table.insert(keys, k) end
					if #keys >= 4 then break end
				end
				table.sort(keys)
				table.insert(out, "table{" .. table.concat(keys, ",") .. "}")
			else
				table.insert(out, ty)
			end
		end
		return table.concat(out, " · ")
	end
	
	local function weaponAimability(args)
		if not args then return 0 end
		local score = 0
		for i = 1, args.n or #args do
			local v = args[i]
			local ty = typeof(v)
			if ty == "Vector3" then score += 3
			elseif ty == "Ray" then score += 4
			elseif ty == "CFrame" then score += 2
			elseif ty == "Instance" and v:IsA("BasePart") then score += 3
			elseif type(v) == "table" then
				for _, k in ipairs({"Hit","hit","Position","position","HitPosition","Target","target","Part","part","Direction","Origin"}) do
					if v[k] ~= nil then score += 1 end
				end
			end
		end
		return math.min(score, 10)
	end
	
	weaponConfidenceThreshold = function()
		return tonumber(weaponOption("confidence", 58)) or 58
	end
	
	weaponRemoteFresh = function(remote)
		if not remote or not remote.Parent then return false end
		local ttl = tonumber(weaponOption("ttl", 15)) or 15
		return WeaponIntel.learnedRemote == remote and (os.clock() - WeaponIntel.learnedAt) <= ttl
	end
	
	local function weaponRecordCall(remote, args, baseScore, tool, ch)
		if weaponReplayGuard or not remote then return end
		local now = os.clock()
		local inIntent = now <= WeaponIntel.intentUntil
		local rec = WeaponIntel.candidates[remote]
		if not rec then
			rec = { count = 0, intent = 0, confidence = 0, last = 0, signature = "—", score = baseScore or 0 }
			WeaponIntel.candidates[remote] = rec
		end
		rec.count += 1
		if inIntent then rec.intent += 1 end
		rec.last = now
		rec.score = baseScore or rec.score or 0
		rec.signature = weaponArgSignature(args)
		local aim = weaponAimability(args)
		local conf = math.clamp((math.max(baseScore or 0, 0) * 4) + aim * 4 + (inIntent and 30 or 0) + math.min(rec.intent * 4, 20) + math.min(rec.count, 5), 0, 100)
		local profile = weaponOption("profile", "Balanced")
		if profile == "Strict" and not inIntent then conf = math.floor(conf * 0.72) end
		if profile == "Aggressive" then conf = math.min(conf + 10, 100) end
		rec.confidence = math.max(rec.confidence or 0, conf)
		WeaponIntel.samples += 1
		WeaponIntel.lastSignature = rec.signature
		local ok, full = pcall(function() return remote:GetFullName() end)
		WeaponIntel.lastPath = ok and full or remote.Name
	
		-- Keep the compatibility replay source fresh even before the model is certain.
		if (baseScore or 0) >= 4 or inIntent then
			weaponLastRemote = remote
			weaponLastArgs = args
			weaponLastSeen = now
		end
	
		local minConf = weaponConfidenceThreshold()
		if rec.confidence >= minConf and (inIntent or rec.intent >= 2 or (baseScore or 0) >= 8) then
			if remote == WeaponIntel.learnedRemote or rec.confidence >= WeaponIntel.learnedConfidence then
				if remote ~= WeaponIntel.learnedRemote then WeaponIntel.confirmed += 1 end
				WeaponIntel.learnedRemote = remote
				WeaponIntel.learnedArgs = args
				WeaponIntel.learnedConfidence = rec.confidence
				WeaponIntel.learnedAt = now
			end
		end
	end
	
	local function weaponResetLearning()
		WeaponIntel.candidates = setmetatable({}, { __mode = "k" })
		WeaponIntel.learnedRemote, WeaponIntel.learnedArgs = nil, nil
		WeaponIntel.learnedConfidence, WeaponIntel.learnedAt = 0, 0
		WeaponIntel.samples, WeaponIntel.confirmed = 0, 0
		WeaponIntel.lastSignature, WeaponIntel.lastPath = "—", "—"
		weaponLastRemote, weaponLastArgs, weaponLastSeen = nil, nil, 0
	end
	
	local function weaponTopCandidates(limit)
		local t = {}
		for remote, rec in pairs(WeaponIntel.candidates) do
			if remote and remote.Parent and rec then
				table.insert(t, { remote = remote, rec = rec })
			end
		end
		table.sort(t, function(a, b)
			if a.rec.confidence == b.rec.confidence then return a.rec.last > b.rec.last end
			return a.rec.confidence > b.rec.confidence
		end)
		local out = {}
		for i = 1, math.min(limit or 5, #t) do out[i] = t[i] end
		return out
	end
	
	markWeaponIntent = function(extra)
		local ms = tonumber(weaponOption("window", 280)) or 280
		WeaponIntel.intentUntil = math.max(WeaponIntel.intentUntil, os.clock() + (extra or ms / 1000))
	end
	
	bind(UserInputService.InputBegan, function(input, processed)
		if processed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			markWeaponIntent()
		end
	end)
	
	local function silentTarget()
		local fov = O("silentaim", "fov")
		local partName = O("silentaim", "part")
		local center = VP() / 2
		local origin = Camera.CFrame.Position
		local best, bestPx = nil, math.huge
	
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LP and (not O("silentaim", "team") or isEnemy(p)) then
				local ch = p.Character
				local hum = ch and ch:FindFirstChildOfClass("Humanoid")
				if ch and (not O("silentaim", "live") or (hum and hum.Health > 0)) then
					local bone = ch:FindFirstChild(partName) or ch:FindFirstChild("HumanoidRootPart")
					if bone and bone:IsA("BasePart") then
						local sp, visible = Camera:WorldToViewportPoint(bone.Position)
						if visible then
							local px = (Vector2.new(sp.X, sp.Y) - center).Magnitude
							if px <= fov and px < bestPx then
								local eye = (tpFocusPoint and tpFocusPoint()) or origin
								if not O("silentaim", "wall") or partVisible(bone, ch, eye) then
									best, bestPx = bone, px
								end
							end
						end
					end
				end
			end
		end
		return best
	end
	
	local function silentPoint(target)
		if not target then return nil end
		return target.Position + target.AssemblyLinearVelocity * (O("silentaim", "predict") / 1000)
	end
	
	local function rewriteAimArgs(args, target, hitPoint, compat)
		local changedVector, changedPart = false, false
		for i = 1, args.n do
			local v = args[i]
			local ty = typeof(v)
			if not changedVector and ty == "Vector3" then
				args[i], changedVector = hitPoint, true
			elseif not changedPart and ty == "Instance" and v:IsA("BasePart") then
				args[i], changedPart = target, true
			elseif compat == "Extended" and ty == "Ray" then
				local mag = math.max(v.Direction.Magnitude, 1)
				args[i] = Ray.new(v.Origin, (hitPoint - v.Origin).Unit * mag)
				changedVector = true
			elseif compat == "Extended" and ty == "CFrame" and (v.Position - Camera.CFrame.Position).Magnitude < 30 then
				args[i] = CFrame.lookAt(v.Position, hitPoint)
				changedVector = true
			elseif compat == "Extended" and type(v) == "table" then
				local copy = table.clone(v)
				local edited = false
				for _, key in ipairs({"Hit", "hit", "Position", "position", "HitPosition", "hitPosition"}) do
					if typeof(copy[key]) == "Vector3" then copy[key] = hitPoint; edited = true end
				end
				for _, key in ipairs({"Target", "target", "Part", "part", "HitPart", "hitPart"}) do
					if typeof(copy[key]) == "Instance" and copy[key]:IsA("BasePart") then copy[key] = target; edited = true end
				end
				if typeof(copy.Direction) == "Vector3" then
					local origin = typeof(copy.Origin) == "Vector3" and copy.Origin or Camera.CFrame.Position
					copy.Direction = (hitPoint - origin).Unit * math.max(copy.Direction.Magnitude, 1)
					edited = true
				end
				if edited then args[i] = copy; changedVector = true end
			end
		end
		return args
	end
	
	local function installSilentHook()
		if saHookInstalled then return true end
		if not RUNTIME_CAPS.MetaHook then return false end
		local mt
		local ok = pcall(function()
			mt = getrawmetatable(game)
			setreadonly(mt, false)
			saOldNamecall = mt.__namecall
			saHookClosure = (typeof(newcclosure) == "function" and newcclosure or function(f) return f end)(function(self, ...)
				local method = getnamecallmethod()
				local isRemoteCall = (method == "FireServer" or method == "InvokeServer")
					and typeof(self) == "Instance" and (self:IsA("RemoteEvent") or self:IsA("RemoteFunction"))
				if isRemoteCall then
					local ch = getChar()
					local tool = ch and ch:FindFirstChildOfClass("Tool")
					local score = weaponRemoteScore(self, tool, ch)
					local packed = table.pack(...)
					local learnOn = weaponOption("learn", true)
					if learnOn and not weaponReplayGuard and (score >= 3 or os.clock() <= WeaponIntel.intentUntil) then
						weaponRecordCall(self, packed, score, tool, ch)
					elseif score >= 4 and not weaponReplayGuard then
						weaponLastRemote, weaponLastArgs, weaponLastSeen = self, packed, os.clock()
					end
					local learnedMatch = self == WeaponIntel.learnedRemote and WeaponIntel.learnedConfidence >= weaponConfidenceThreshold()
					if ById.silentaim and ById.silentaim._active and (score >= 4 or learnedMatch) then
						local target = silentTarget()
						local hitPoint = silentPoint(target)
						if target and hitPoint then
							saCurrentTarget = target
							local args = rewriteAimArgs(packed, target, hitPoint, O("silentaim", "compat"))
							if O("silentaim", "notify") then Notify("SA " .. safePlayerLabel(Players:GetPlayerFromCharacter(target.Parent)), "ok") end
							return saOldNamecall(self, table.unpack(args, 1, args.n))
						end
					end
				end
				return saOldNamecall(self, ...)
			end)
			mt.__namecall = saHookClosure
			saHookInstalled = true
		end)
		if mt then pcall(function() setreadonly(mt, true) end) end
		if not ok then
			saHookInstalled = false
			saHookClosure = nil
		end
		return ok and saHookInstalled
	end
	
	local function uninstallSilentHook()
		if not saHookInstalled then return true end
		if not RUNTIME_CAPS.MetaHook then
			saHookInstalled, saHookClosure, saOldNamecall = false, nil, nil
			return false
		end
		local restored = false
		pcall(function()
			local mt = getrawmetatable(game)
			setreadonly(mt, false)
			if mt.__namecall == saHookClosure and saOldNamecall then
				mt.__namecall = saOldNamecall
				restored = true
			end
			setreadonly(mt, true)
		end)
		if restored then
			saHookInstalled, saHookClosure, saOldNamecall = false, nil, nil
		end
		return restored
	end
	
	local function bindSilentTool(tool)
		if tool == saTool then return end
		if saToolConn then saToolConn:Disconnect() saToolConn = nil end
		saTool = tool
		if not tool then return end
		saToolConn = tool.Activated:Connect(function()
			markWeaponIntent(0.34)
			if not (ById.silentaim and ById.silentaim._active) then return end
			local target = silentTarget()
			local point = silentPoint(target)
			if not target or not point then return end
			saCurrentTarget = target
			local saved = Camera.CFrame
			Camera.CFrame = CFrame.lookAt(saved.Position, point)
			task.defer(function()
				if Camera then Camera.CFrame = saved end
			end)
			if O("silentaim", "notify") then Notify("SA " .. target.Parent.Name, "ok") end
		end)
	end
	
	Feature{
		Id="silentaim", Tab="Main", Group="Прицеливание", Col=1,
		Name="Silent Aim",
		Desc="Универсальный redirect: Vector3/BasePart, а Extended также Ray/CFrame/таблицы; есть Tool fallback.",
		Options={
			{Id="fov",     Type="Slider", Name="Радиус (px)", Min=50, Max=900, Default=320, Step=10, Suffix="px"},
			{Id="predict", Type="Slider", Name="Упреждение", Min=0, Max=200, Default=55, Step=5, Suffix="мс"},
			{Id="part",    Type="Dropdown", Name="Точка", List={"Head","UpperTorso","HumanoidRootPart"}, Default="Head"},
			{Id="team",    Type="Toggle", Name="Игнорировать союзников", Default=true},
			{Id="wall",    Type="Toggle", Name="Проверка стен", Default=true},
			{Id="live",    Type="Toggle", Name="Только живые цели", Default=true},
			{Id="compat",  Type="Dropdown", Name="Совместимость", List={"Safe","Extended"}, Default="Safe"},
			{Id="notify",  Type="Toggle", Name="Уведомления", Default=false},
		},
		OnToggle=function(on)
			saCurrentTarget = nil
			if on then
				installSilentHook()
				local ch = getChar()
				bindSilentTool(ch and ch:FindFirstChildOfClass("Tool"))
			else
				bindSilentTool(nil)
			end
		end,
		Step=function()
			if not ById.silentaim or not ById.silentaim._active then return end
			local ch = getChar()
			bindSilentTool(ch and ch:FindFirstChildOfClass("Tool"))
		end,
	}
	
	local rfLast = 0
	local rfTool = nil
	Feature{
		Id = "rapidfire", Tab = "Main", Group = "Оружие", Col = 1,
		Name = "Rapid Fire", Desc = "Auto: Tool:Activate, а для remote-оружия повторяет последний распознанный выстрел",
		Options = {
			{ Id = "gap",  Type = "Slider", Name = "Интервал", Min = 10, Max = 600, Default = 70, Step = 5, Suffix = "мс" },
			{ Id = "key",  Type = "Keybind", Name = "Кнопка стрельбы", Default = "MouseButton1" },
			{ Id = "method", Type = "Dropdown", Name = "Совместимость", List = { "Auto", "Tool:Activate", "Last Remote" }, Default = "Auto" },
			{ Id = "fresh", Type = "Slider", Name = "Давность remote-шота", Min = 1, Max = 20, Default = 8, Step = 1, Suffix = "с" },
			{ Id = "rel",  Type = "Toggle", Name = "Отпускать между выстрелами", Default = true },
		},
		OnToggle = function(on)
			if on then installSilentHook() else rfTool, rfLast = nil, 0 end
		end,
		Step = function()
			if not alive() then rfTool, rfLast = nil, 0 return end
			local k = O("rapidfire", "key")
			if k == "" or not keyDown(k) then return end
			local tool = getChar():FindFirstChildOfClass("Tool")
			if tool ~= rfTool then rfTool, rfLast = tool, 0 end
			local now = os.clock()
			if (now - rfLast) * 1000 < O("rapidfire", "gap") then return end
			local method = O("rapidfire", "method")
			local learnedFresh = weaponRemoteFresh(WeaponIntel.learnedRemote) and WeaponIntel.learnedArgs ~= nil
			local replayRemote = learnedFresh and WeaponIntel.learnedRemote or weaponLastRemote
			local replayArgs = learnedFresh and WeaponIntel.learnedArgs or weaponLastArgs
			local replaySeen = learnedFresh and WeaponIntel.learnedAt or weaponLastSeen
			local canRemote = replayRemote and replayRemote.Parent and replayArgs
				and (now - replaySeen) <= O("rapidfire", "fresh")
			local preferLearned = learnedFresh and WeaponIntel.learnedConfidence >= math.min(weaponConfidenceThreshold() + 8, 100)
			local useTool = method == "Tool:Activate" or (method == "Auto" and tool ~= nil and not preferLearned)
			local useRemote = method == "Last Remote" or (method == "Auto" and canRemote and (not tool or preferLearned))
			if useTool and tool then
				markWeaponIntent(0.28)
				rfLast = now
				local shotTool = tool
				pcall(function() shotTool:Activate() end)
				if O("rapidfire", "rel") then
					task.delay(math.min(0.03, O("rapidfire", "gap") / 2000), function()
						if shotTool and shotTool.Parent then pcall(function() shotTool:Deactivate() end) end
					end)
				end
			elseif useRemote and canRemote then
				markWeaponIntent(0.28)
				rfLast = now
				local remote, args = replayRemote, replayArgs
				if remote:IsA("RemoteEvent") then
					weaponReplayGuard = true
					pcall(function() remote:FireServer(table.unpack(args, 1, args.n)) end)
					weaponReplayGuard = false
				else
					task.spawn(function()
						weaponReplayGuard = true
						pcall(function() remote:InvokeServer(table.unpack(args, 1, args.n)) end)
						weaponReplayGuard = false
					end)
				end
			end
		end,
	}
	
	local vmOffsets = {}
	local function vmClear() table.clear(vmOffsets) end
	
	Feature{
		Id = "vmfix", Tab = "Main", Group = "Оружие", Col = 1,
		Name = "Viewmodel Fix", Desc = "Убирает плавание оружия от первого лица при доводке камеры",
		Options = {
			{ Id = "onaim", Type = "Toggle", Name = "Только при активном аиме", Default = true },
			{ Id = "power", Type = "Slider", Name = "Жёсткость фиксации", Min = 10, Max = 100, Default = 85, Suffix = "%" },
			{ Id = "parts", Type = "Toggle", Name = "Фиксировать и отдельные детали", Default = true },
		},
		OnToggle = function(on) if not on then vmClear() end end,
	}
	
	-- выполняется в самом конце кадра, после кода покачивания оружия в игре
	local function vmStabilize()
		local f = ById.vmfix
		if not f or not f._active then return end
	
		if O("vmfix", "onaim") then
			local ab = ById.aimbot
			if not (ab and ab._active and currentTarget) then
				if next(vmOffsets) then vmClear() end
				return
			end
		end
	
		local cam = workspace.CurrentCamera
		if not cam then return end
		local k = O("vmfix", "power") / 100
	
		for _, child in ipairs(cam:GetChildren()) do
			local isModel = child:IsA("Model")
			local isPart = child:IsA("BasePart")
			if isModel or (isPart and O("vmfix", "parts")) then
				local cur = isModel and child:GetPivot() or child.CFrame
				local off = vmOffsets[child]
				if not off then
					-- запоминаем положение оружия относительно камеры до доводки
					vmOffsets[child] = cam.CFrame:ToObjectSpace(cur)
				else
					local goal = cam.CFrame * off
					local nxt = cur:Lerp(goal, k)
					if isModel then child:PivotTo(nxt) else child.CFrame = nxt end
				end
			end
		end
	end
	
	local recoilPitch = nil
	local recoilTool, recoilConn = nil, nil
	local recoilWindowUntil = 0
	
	local function bindRecoilTool(tool)
		if tool == recoilTool then return end
		if recoilConn then recoilConn:Disconnect() recoilConn = nil end
		recoilTool = tool
		if tool then
			recoilConn = tool.Activated:Connect(function()
				markWeaponIntent(0.30)
				recoilWindowUntil = os.clock() + 0.22
				recoilPitch = nil
			end)
		end
	end
	
	Feature{
		Id = "norecoil", Tab = "Main", Group = "Оружие", Col = 1,
		Name = "No Recoil", Desc = "Компенсирует камерный импульс после Tool.Activated или распознанного remote-выстрела",
		Options = {
			{ Id = "power", Type = "Slider", Name = "Сила компенсации", Min = 10, Max = 100, Default = 90, Suffix = "%" },
			{ Id = "thr",   Type = "Slider", Name = "Порог срабатывания", Min = 1, Max = 40, Default = 4, Step = 1 },
		},
		OnToggle = function(on)
			if not on then
				recoilPitch, recoilWindowUntil = nil, 0
				bindRecoilTool(nil)
			else
				installSilentHook()
				local ch = getChar()
				bindRecoilTool(ch and ch:FindFirstChildOfClass("Tool"))
			end
		end,
		Step = function()
			local ch = getChar()
			local tool = ch and ch:FindFirstChildOfClass("Tool")
			bindRecoilTool(tool)
			local now = os.clock()
			if weaponLastSeen > 0 and (now - weaponLastSeen) < 0.25 then
				recoilWindowUntil = math.max(recoilWindowUntil, weaponLastSeen + 0.25)
			end
			if now > recoilWindowUntil then recoilPitch = nil return end
	
			local cf = Camera.CFrame
			local x, y, z = cf:ToOrientation()
			if recoilPitch == nil then recoilPitch = x return end
	
			local md = UserInputService:GetMouseDelta()
			local mouseMoved = (math.abs(md.X) + math.abs(md.Y)) > 0.5
			local diff = x - recoilPitch
			local thr = math.rad(O("norecoil", "thr") * 0.25)
	
			if not mouseMoved and math.abs(diff) > thr then
				local k = O("norecoil", "power") / 100
				local fixedX = x - diff * k
				Camera.CFrame = CFrame.new(cf.Position) * CFrame.fromOrientation(fixedX, y, z)
				recoilPitch = fixedX
			else
				recoilPitch = x
			end
		end,
	}
	
	Feature{
		Id = "weaponbridge", Tab = "Main", Group = "Оружие", Col = 2, NoToggle = true,
		Name = "Universal Weapon Bridge", Desc = "Обучается на реальных выстрелах и помогает Trigger / Silent Aim / Rapid Fire / No Recoil работать с разными системами оружия",
		Options = {
			{ Id = "learn", Type = "Toggle", Name = "Автообучение по выстрелам", Default = false,
			  OnChange = function(v) if v then installSilentHook() end end },
			{ Id = "profile", Type = "Dropdown", Name = "Профиль распознавания", List = { "Strict", "Balanced", "Aggressive" }, Default = "Balanced" },
			{ Id = "confidence", Type = "Slider", Name = "Мин. уверенность", Min = 20, Max = 95, Default = 58, Step = 1, Suffix = "%" },
			{ Id = "window", Type = "Slider", Name = "Окно после нажатия Fire", Min = 80, Max = 700, Default = 280, Step = 20, Suffix = "мс" },
			{ Id = "ttl", Type = "Slider", Name = "Срок актуальности модели", Min = 3, Max = 60, Default = 15, Step = 1, Suffix = "с" },
			{ Id = "rescan", Type = "Button", Name = "Пересканировать weapon remote", Run = function()
				local ch = getChar(); local tool = ch and ch:FindFirstChildOfClass("Tool")
				local r, score = detectWeaponRemote(tool, ch)
				WeaponIntel.scanRemote, WeaponIntel.scanScore = r, score or 0
				Notify(r and ("Кандидат: " .. r.Name .. "  score " .. tostring(score)) or "Weapon remote не найден", r and "ok" or "warn")
			end },
			{ Id = "reset", Type = "Button", Name = "Сбросить обучение", Style = "danger", Run = function()
				weaponResetLearning(); tbRemoteCache = nil; Notify("Weapon learning сброшен", "warn")
			end },
		},
	}
	
	local hitboxParts = {}
	local function clearHitboxes()
		for _, part in pairs(hitboxParts) do
			if part then pcall(function() part:Destroy() end) end
		end
		table.clear(hitboxParts)
	end
	
	local aaFlip = 1
	Feature{
		Id = "antiaim", Tab = "Main", Group = "Уклонение", Col = 2,
		Name = "Anti-Aim", Desc = "Разворот корпуса, сбивающий чужой прицел",
		Options = {
			{ Id = "mode", Type = "Dropdown", Name = "Режим", List = { "Backwards", "Jitter", "Spin", "Static" }, Default = "Jitter" },
			{ Id = "yaw",  Type = "Slider", Name = "Угол (Static)", Min = 0, Max = 360, Default = 180, Suffix = "°" },
			{ Id = "jit",  Type = "Slider", Name = "Размах Jitter", Min = 5, Max = 180, Default = 90, Suffix = "°" },
			{ Id = "spd",  Type = "Slider", Name = "Скорость Spin", Min = 30, Max = 1500, Default = 600, Step = 10, Suffix = "°/с" },
			{ Id = "air",  Type = "Toggle", Name = "Только в воздухе", Default = false },
		},
		OnToggle = function(on)
			local h = getHum()
			if h then h.AutoRotate = not on end
			if on then setOn("spinbot", false) end
		end,
		Step = function(dt)
			if not alive() then return end
			local root, hum = getRoot(), getHum()
			if O("antiaim", "air") and hum.FloorMaterial ~= Enum.Material.Air then
				hum.AutoRotate = true
				return
			end
			hum.AutoRotate = false
			local m = O("antiaim", "mode")
			local lv = Camera.CFrame.LookVector
			local camYaw = math.atan2(-lv.X, -lv.Z)
			local yaw
			if m == "Backwards" then
				yaw = camYaw + math.pi
			elseif m == "Jitter" then
				aaFlip = -aaFlip
				yaw = camYaw + math.pi + math.rad(O("antiaim", "jit") / 2) * aaFlip
			elseif m == "Spin" then
				aaFlip = (aaFlip + dt * O("antiaim", "spd")) % 360
				yaw = math.rad(aaFlip)
			else
				yaw = camYaw + math.rad(O("antiaim", "yaw"))
			end
			local lin = root.AssemblyLinearVelocity
			root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
			root.AssemblyLinearVelocity = lin
			root.AssemblyAngularVelocity = Vector3.zero
		end,
	}
	
	local spinA = 0
	Feature{
		Id = "spinbot", Tab = "Main", Group = "Уклонение", Col = 2,
		Name = "Spinbot", Desc = "Непрерывное вращение персонажа",
		Options = {
			{ Id = "mode", Type = "Dropdown", Name = "Режим",
			  List = { "Ровный", "Джиттер", "Синус", "Рывками", "Случайный" }, Default = "Ровный" },
			{ Id = "spd", Type = "Slider", Name = "Скорость", Min = 50, Max = 3000, Default = 720, Step = 10, Suffix = "°/с" },
			{ Id = "dir", Type = "Dropdown", Name = "Направление", List = { "По часовой", "Против часовой" }, Default = "По часовой" },
			{ Id = "amp", Type = "Slider", Name = "Размах (синус/джиттер)", Min = 10, Max = 180, Default = 90, Suffix = "°" },
			{ Id = "burst", Type = "Slider", Name = "Пауза рывков", Min = 50, Max = 800, Default = 200, Step = 10, Suffix = "мс" },
		},
		OnToggle = function(on)
			local h = getHum()
			if h then h.AutoRotate = not on end
			if on then setOn("antiaim", false) end
		end,
		Step = function(dt)
			if not alive() then return end
			local root, hum = getRoot(), getHum()
			hum.AutoRotate = false
			local sg = (O("spinbot", "dir") == "По часовой") and 1 or -1
			local mode = O("spinbot", "mode")
			local spd = O("spinbot", "spd")
			local yaw
	
			if mode == "Ровный" then
				spinA = (spinA + dt * spd * sg) % 360
				yaw = spinA
			elseif mode == "Джиттер" then
				spinA = (spinA + dt * spd * sg) % 360
				local flip = (math.floor(os.clock() * 30) % 2 == 0) and 1 or -1
				yaw = spinA + O("spinbot", "amp") * 0.5 * flip
			elseif mode == "Синус" then
				spinA = (spinA + dt * spd * sg * 0.4) % 360
				yaw = math.sin(math.rad(spinA)) * O("spinbot", "amp")
			elseif mode == "Рывками" then
				local step = math.max(O("spinbot", "burst"), 1) / 1000
				spinA = (math.floor(os.clock() / step) * (spd * step) * sg) % 360
				yaw = spinA
			else
				if math.random() < dt * 8 then
					spinA = math.random(0, 359)
				end
				yaw = spinA
			end
	
			local lin = root.AssemblyLinearVelocity
			root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, math.rad(yaw), 0)
			root.AssemblyLinearVelocity = lin
			root.AssemblyAngularVelocity = Vector3.zero
		end,
	}
	
	----------------------------------------------------------------- MOVEMENT ----
	local speedColl = {}
	local speedJump = 0
	local function speedRestore()
		for part, v in pairs(speedColl) do
			if part and part.Parent then part.CanCollide = v end
		end
		table.clear(speedColl)
	end
	
	Feature{
		Id = "speed", Tab = "Movement", Group = "Перемещение", Col = 1,
		Name = "Speed", Desc = "Ускоренное передвижение",
		Options = {
			{ Id = "mode", Type = "Dropdown", Name = "Метод", List = { "WalkSpeed", "BodyVel (bypass)", "CFrame" }, Default = "WalkSpeed" },
			{ Id = "val",  Type = "Slider", Name = "Скорость", Min = 16, Max = 300, Default = 60, Step = 1 },
			{ Id = "shift",Type = "Toggle", Name = "Только при Shift", Default = false },
			{ Id = "jump", Type = "Toggle", Name = "Авто-прыжок", Default = false },
			{ Id = "jgap", Type = "Slider", Name = "Интервал прыжков", Min = 80, Max = 800, Default = 150, Step = 10, Suffix = "мс" },
			{ Id = "air",  Type = "Toggle", Name = "Полное управление в воздухе", Default = true },
			{ Id = "noslide", Type = "Toggle", Name = "Без заноса и скольжения", Default = true },
			{ Id = "phase",Type = "Toggle", Name = "Проходить сквозь стены (CFrame)", Default = false,
			  OnChange = function(v) if not v then speedRestore() end end },
			{ Id = "pad",  Type = "Slider", Name = "Отступ от стен", Min = 0, Max = 6, Default = 2, Step = 0.5, Suffix = "st" },
		},
		OnToggle = function(on)
			local h = getHum()
			if not on then
				if h then h.WalkSpeed = baseWalkSpeed(h) end
				local _r2=getRoot() if _r2 then local _b2=_r2:FindFirstChild("_spdbv") if _b2 then _b2:Destroy() end end
				speedRestore()
			end
		end,
		-- физическая фаза: в воздухе гуманоид почти не слушает A, S и D,
		-- поэтому вектор скорости задаём сами и управление остаётся мгновенным
		Heart = function()
			if not alive() then return end
			if not O("speed", "air") then return end
			if O("speed", "shift") and not UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then return end
	
			local hum, root = getHum(), getRoot()
			local grounded = (hum.FloorMaterial ~= Enum.Material.Air)
			local noslide = O("speed", "noslide")
			if grounded and not noslide then return end
	
			-- вращение корпуса ломает MoveDirection, поэтому направление
			-- собираем сами: только камера и нажатые клавиши
			local md = hum.MoveDirection
			if UserInputService.KeyboardEnabled then
				local cf = Camera.CFrame
				local fwd = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
				local rgt = Vector3.new(cf.RightVector.X, 0, cf.RightVector.Z)
				local d = Vector3.zero
				if fwd.Magnitude > 0.01 then fwd = fwd.Unit end
				if rgt.Magnitude > 0.01 then rgt = rgt.Unit end
				if UserInputService:IsKeyDown(Enum.KeyCode.W) then d += fwd end
				if UserInputService:IsKeyDown(Enum.KeyCode.S) then d -= fwd end
				if UserInputService:IsKeyDown(Enum.KeyCode.A) then d -= rgt end
				if UserInputService:IsKeyDown(Enum.KeyCode.D) then d += rgt end
				md = d
			end
	
			local v = root.AssemblyLinearVelocity
			local want = (md.Magnitude > 0) and md.Unit * O("speed", "val") or Vector3.zero
	
			if noslide and want.Magnitude > 0 then
				-- убираем составляющую, направленную внутрь препятствия:
				-- именно она после удара о стену разворачивает персонажа вбок
				local rp = RaycastParams.new()
				rp.FilterType = Enum.RaycastFilterType.Exclude
				rp.FilterDescendantsInstances = { getChar() }
				rp.IgnoreWater = true
				local dir = want.Unit
				for _, h in ipairs({ 0.8, 0, -1.2 }) do
					local origin = root.Position + Vector3.new(0, h, 0)
					local res = workspace:Raycast(origin, dir * 3, rp)
					if res then
						local n = Vector3.new(res.Normal.X, 0, res.Normal.Z)
						if n.Magnitude > 0.01 then
							n = n.Unit
							local into = want:Dot(n)
							if into < 0 then want = want - n * into end
						end
					end
				end
			end
	
			if grounded then
				-- на земле только гасим занос, сам разгон делает WalkSpeed
				if noslide and md.Magnitude <= 0 then
					root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
				end
				return
			end
	
			if want.Magnitude <= 0 and not noslide then return end
			root.AssemblyLinearVelocity = Vector3.new(want.X, v.Y, want.Z)
			root.AssemblyAngularVelocity = Vector3.zero
		end,
		Step = function(dt)
			if not alive() then return end
			local hum, root = getHum(), getRoot()
			if O("speed", "shift") and not UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
				hum.WalkSpeed = baseWalkSpeed(hum)
				return
			end
			local st = hum:GetState()
			local canJump = (st == Enum.HumanoidStateType.Running
				or st == Enum.HumanoidStateType.RunningNoPhysics
				or st == Enum.HumanoidStateType.Landed)
			if O("speed", "jump") and hum.FloorMaterial ~= Enum.Material.Air and canJump then
				local now = os.clock()
				if (now - speedJump) * 1000 >= O("speed", "jgap") then
					speedJump = now
					hum.Jump = true
					hum:ChangeState(Enum.HumanoidStateType.Jumping)
				end
			end
	
			local v = O("speed", "val")
			local _sm = O("speed", "mode")
			if _sm == "WalkSpeed" then
				hum.WalkSpeed = v
				if next(speedColl) then speedRestore() end
				return
			elseif _sm == "BodyVel (bypass)" then
				hum.WalkSpeed = baseWalkSpeed(hum)
				if next(speedColl) then speedRestore() end
				local _root = getRoot()
				if _root then
					local _bv = _root:FindFirstChild("_spdbv")
					if not _bv then
						_bv = Instance.new("BodyVelocity")
						_bv.Name = "_spdbv"
						_bv.MaxForce = Vector3.new(1e4,0,1e4)
						_bv.P = 2e4
						_bv.Parent = _root
					end
					local _md = hum.MoveDirection
					_bv.Velocity = _md.Magnitude>0.05 and _md*(v-16) or Vector3.zero
				end
				return
			end
	
			hum.WalkSpeed = baseWalkSpeed(hum)
			local phase = O("speed", "phase")
			if phase then
				-- реальный проход: снимаем коллизии, запоминая исходное состояние
				for _, part in ipairs(getChar():GetDescendants()) do
					if part:IsA("BasePart") and part.CanCollide then
						if speedColl[part] == nil then speedColl[part] = true end
						part.CanCollide = false
					end
				end
			elseif next(speedColl) then
				speedRestore()
			end
	
			local dir = hum.MoveDirection
			if dir.Magnitude <= 0 then return end
			local delta = dir * math.max(v - baseWalkSpeed(hum), 0) * dt
	
			if phase then
				root.CFrame = root.CFrame + delta
				return
			end
	
			-- без прохода: упираемся в геометрию вместо телепорта сквозь неё
			local rp = RaycastParams.new()
			rp.FilterType = Enum.RaycastFilterType.Exclude
			rp.FilterDescendantsInstances = { getChar() }
			rp.IgnoreWater = true
			local pad = O("speed", "pad")
			local res = workspace:Raycast(root.Position, delta.Unit * (delta.Magnitude + pad), rp)
			if not res then
				root.CFrame = root.CFrame + delta
			else
				local free = math.max((res.Position - root.Position).Magnitude - pad, 0)
				if free > 0.05 then root.CFrame = root.CFrame + delta.Unit * free end
			end
		end,
	}
	
	Feature{
		Id = "jump", Tab = "Movement", Group = "Перемещение", Col = 1,
		Name = "Jump Power", Desc = "Сила прыжка и гравитация",
		Options = {
			{ Id = "val",  Type = "Slider", Name = "Сила прыжка", Min = 50, Max = 1000, Default = 140, Step = 5 },
			{ Id = "grav", Type = "Slider", Name = "Гравитация", Min = 5, Max = 250, Default = 196, Step = 1 },
			{ Id = "hold", Type = "Toggle", Name = "Держать высоту в воздухе", Default = false },
		},
		OnToggle = function(on)
			if on then return end
			workspace.Gravity = WORLD_BASE.Gravity
			local h = getHum()
			if h then restoreHumanoid(h) end
		end,
		Step = function()
			if not alive() then return end
			local h, v = getHum(), O("jump", "val")
			if h.UseJumpPower then h.JumpPower = v else h.JumpHeight = (v * v) / (2 * math.max(workspace.Gravity, 1)) end
			workspace.Gravity = O("jump", "grav")
			if O("jump", "hold") and h.FloorMaterial == Enum.Material.Air then
				local root = getRoot()
				local vel = root.AssemblyLinearVelocity
				if vel.Y < 0 then
					root.AssemblyLinearVelocity = Vector3.new(vel.X, vel.Y * 0.55, vel.Z)
				end
			end
		end,
	}
	
	local ijLast = 0
	Feature{
		Id = "infjump", Tab = "Movement", Group = "Перемещение", Col = 1,
		Name = "Infinite Jump", Desc = "Прыжок в воздухе по нажатию пробела",
		Options = {
			{ Id = "hold", Type = "Toggle", Name = "Авто при зажатом пробеле", Default = false },
			{ Id = "gap",  Type = "Slider", Name = "Интервал между прыжками", Min = 80, Max = 1000, Default = 280, Step = 10, Suffix = "мс" },
		},
		Step = function()
			if not alive() then return end
			if not O("infjump", "hold") then return end
			if not UserInputService:IsKeyDown(Enum.KeyCode.Space) then return end
			local now = os.clock()
			-- без интервала состояние Jumping ставится каждый кадр и персонаж улетает
			if (now - ijLast) * 1000 < O("infjump", "gap") then return end
			ijLast = now
			getHum():ChangeState(Enum.HumanoidStateType.Jumping)
		end,
	}
	
	local flyBV
	Feature{
		Id = "fly", Tab = "Movement", Group = "Трюки", Col = 2,
		Name = "Fly", Desc = "Полёт: WASD + Space / Shift",
		Options = {
			{ Id = "spd",  Type = "Slider", Name = "Скорость", Min = 10, Max = 300, Default = 70 },
			{ Id = "vspd", Type = "Slider", Name = "Вертикальная скорость", Min = 10, Max = 300, Default = 60 },
			{ Id = "nc",   Type = "Toggle", Name = "Без коллизий в полёте", Default = true },
			{ Id = "hover",Type = "Toggle", Name = "Зависать без ввода", Default = true },
		},
		OnToggle = function(on)
			local root, hum = getRoot(), getHum()
			if on then
				if not root then return end
				flyBV = New("BodyVelocity", { Name = "_an_fly", MaxForce = Vector3.one * 1e5,
					Velocity = Vector3.zero, P = 3000, Parent = root })
				if hum and not isMobile then hum.PlatformStand = true end
			else
				if flyBV then flyBV:Destroy() flyBV = nil end
				if hum then hum.PlatformStand = false end
			end
		end,
		Step = function()
			if not alive() then return end
			if not flyBV or not flyBV.Parent then
				local r = getRoot()
				if r then
					flyBV = New("BodyVelocity", { Name = "_an_fly", MaxForce = Vector3.one * 1e5,
						Velocity = Vector3.zero, P = 3000, Parent = r })
					local h = getHum()
				if h and not isMobile then h.PlatformStand = true end
				end
				return
			end
			local cf = Camera.CFrame
			local dir = Vector3.zero
			if isMobile then
				local h = getHum()
				local md = h and h.MoveDirection or Vector3.zero
				if md.Magnitude > 0.05 then dir = Vector3.new(md.X, 0, md.Z) end
			else
				if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += cf.LookVector end
				if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= cf.LookVector end
				if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= cf.RightVector end
				if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += cf.RightVector end
			end
			local vert = isMobile and _mVert or 0
			if not isMobile then
				if UserInputService:IsKeyDown(Enum.KeyCode.Space) then vert = 1 end
				if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then vert = -1 end
			end
			local v = (dir.Magnitude > 0) and dir.Unit * O("fly", "spd") or Vector3.zero
			v += Vector3.new(0, vert * O("fly", "vspd"), 0)
			if v.Magnitude == 0 and not O("fly", "hover") then v = Vector3.new(0, -6, 0) end
			if v.Magnitude < 0.1 then
				local _r = getRoot()
				if _r then pcall(function() _r.AssemblyLinearVelocity = Vector3.zero end) end
			end
			flyBV.P = 80000
			flyBV.Velocity = v
			if O("fly", "nc") then
				for _, part in ipairs(getChar():GetDescendants()) do
					if part:IsA("BasePart") and part.CanCollide then part.CanCollide = false end
				end
			end
		end,
	}
	
	local ghostHum, ghostAcc = nil, 0
	Feature{
		Id = "ghost", Tab = "Movement", Group = "Трюки", Col = 2,
		Name = "Ghost Mode", Desc = "Убирает Humanoid, движение идёт короткими телепортами, камера следует",
		Options = {
			{ Id = "step", Type = "Slider", Name = "Длина шага", Min = 0.2, Max = 8, Default = 1.6, Step = 0.1, Suffix = "st" },
			{ Id = "gap",  Type = "Slider", Name = "Интервал шага", Min = 10, Max = 200, Default = 20, Step = 5, Suffix = "мс" },
			{ Id = "vert", Type = "Toggle", Name = "Вертикаль на Space и Shift", Default = true },
			{ Id = "anchor", Type = "Toggle", Name = "Заякорить тело", Default = true },
			{ Id = "keephum", Type = "Toggle", Name = "Оставить Humanoid", Default = false },
			{ Id = "nocol", Type = "Toggle", Name = "Без коллизий", Default = true },
		},
		OnToggle = function(on)
			local ch = getChar()
			local root = ch and ch:FindFirstChild("HumanoidRootPart")
			if on then
				if not root then return end
				Camera.CameraSubject = root
				if not O("ghost", "keephum") then
					local h = ch:FindFirstChildOfClass("Humanoid")
					if h then
						ghostHum = h
						-- не Destroy: так персонажа можно вернуть в обычное состояние
						h.Parent = nil
					end
				end
				if O("ghost", "anchor") then root.Anchored = true end
				if O("ghost", "nocol") then
					for _, part in ipairs(ch:GetDescendants()) do
						if part:IsA("BasePart") then part.CanCollide = false end
					end
				end
			else
				local c = getChar()
				local r = c and c:FindFirstChild("HumanoidRootPart")
				if r then r.Anchored = false end
				if ghostHum then
					pcall(function() ghostHum.Parent = c end)
					ghostHum = nil
				end
				local h = getHum()
				if h then Camera.CameraSubject = h end
			end
		end,
		Heart = function(dt)
			local ch = getChar()
			local root = ch and ch:FindFirstChild("HumanoidRootPart")
			if not root then return end
			if Camera.CameraSubject ~= root then Camera.CameraSubject = root end
	
			ghostAcc += dt
			if ghostAcc * 1000 < O("ghost", "gap") then return end
			ghostAcc = 0
	
			local cf = Camera.CFrame
			local dir = Vector3.zero
			if isMobile then
				local h = getHum()
				local md = h and h.MoveDirection or Vector3.zero
				if md.Magnitude > 0.05 then dir = cf.LookVector * md.Magnitude end
				if O("ghost", "vert") then dir += Vector3.yAxis * _mVert end
			else
				if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += cf.LookVector end
				if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= cf.LookVector end
				if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= cf.RightVector end
				if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += cf.RightVector end
				if O("ghost", "vert") then
					if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
					if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir -= Vector3.yAxis end
				end
			end
			if dir.Magnitude < 0.01 then return end
			root.CFrame = root.CFrame + dir.Unit * O("ghost", "step")
		end,
	}
	
	local noclipCache = {}
	Feature{
		Id = "noclip", Tab = "Movement", Group = "Трюки", Col = 2,
		Name = "Noclip", Desc = "Проход сквозь геометрию",
		Options = {
			{ Id = "keep", Type = "Toggle", Name = "Оставлять опору под ногами", Default = false },
		},
		OnToggle = function(on)
			if on then return end
			for part, v in pairs(noclipCache) do
				if part and part.Parent then part.CanCollide = v end
			end
			table.clear(noclipCache)
		end,
		Step = function()
			local ch = getChar()
			if not ch then return end
			for _, part in ipairs(ch:GetDescendants()) do
				if part:IsA("BasePart") then
					if O("noclip", "keep") and part.Name == "HumanoidRootPart" then continue end
					if part.CanCollide then
						if noclipCache[part] == nil then noclipCache[part] = true end
						part.CanCollide = false
					end
				end
			end
		end,
	}
	
	local tpBackup = nil
	
	function tpApply()
		local f = ById.thirdperson
		if not f or not f._active then return end
		local hum = getHum()
		local ch = getChar()
		local d = O("thirdperson", "dist")
		if O("thirdperson", "lock") then
			LP.CameraMinZoomDistance = d
			LP.CameraMaxZoomDistance = d
		else
			LP.CameraMinZoomDistance = 0.5
			LP.CameraMaxZoomDistance = math.max(d, 1)
		end
		if LP.CameraMode == Enum.CameraMode.LockFirstPerson then
			LP.CameraMode = Enum.CameraMode.Classic
		end
		if hum then
			hum.CameraOffset = Vector3.new(O("thirdperson", "offx"), O("thirdperson", "offy"), 0)
		end
		local t = O("thirdperson", "trans") / 100
		if ch then
			for _, part in ipairs(ch:GetDescendants()) do
				if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
					part.LocalTransparencyModifier = t
				end
			end
		end
	end
	
	-- собственная камера третьего лица: работает поверх любой системы камеры,
	-- включая кастомные, где свойства зума игрока ни на что не влияют
	function tpFocusPoint()
		local f = ById.thirdperson
		if not f or not f._active or not O("thirdperson", "force") then return nil end
		local ch = getChar()
		local root = ch and (ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Head"))
		if not root then return nil end
		local cam = workspace.CurrentCamera
		if not cam then return nil end
		return root.Position + Vector3.new(0, 1.5 + O("thirdperson", "offy"), 0)
			+ cam.CFrame.RightVector * O("thirdperson", "offx")
	end
	
	local function tpCamera()
		local f = ById.thirdperson
		if not f or not f._active then return end
		if not O("thirdperson", "force") then return end
		if not alive() then return end
	
		local cam = workspace.CurrentCamera
		local ch = getChar()
		if not cam or not ch then return end
		-- точку обзора берём от корня, а не от головы: корень не качается
		-- при вращении и анимациях, поэтому картинку не трясёт
		local root = ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Head")
		if not root then return end
	
		local rot = cam.CFrame.Rotation
		local look = cam.CFrame.LookVector
		local right = cam.CFrame.RightVector
		local dist = O("thirdperson", "dist")
	
		local focus = tpFocusPoint() or (root.Position + Vector3.new(0, 1.5, 0))
		local want = focus - look * dist
	
		if O("thirdperson", "coll") then
			local rp = RaycastParams.new()
			rp.FilterType = Enum.RaycastFilterType.Exclude
			rp.FilterDescendantsInstances = { ch }
			rp.IgnoreWater = true
			local res = workspace:Raycast(focus, want - focus, rp)
			if res then
				local d = (res.Position - focus).Magnitude - 0.6
				want = focus - look * math.max(d, 0.5)
			end
		end
	
		cam.CFrame = CFrame.new(want) * rot
	
		if O("thirdperson", "body") then
			local t = O("thirdperson", "trans") / 100
			for _, part in ipairs(ch:GetDescendants()) do
				if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
					if part.LocalTransparencyModifier ~= t then
						part.LocalTransparencyModifier = t
					end
				end
			end
		end
	
		-- вьюмодель оружия рассчитана на первое лицо и в третьем висит перед камерой
		if O("thirdperson", "hidegun") then
			for _, child in ipairs(cam:GetChildren()) do
				if child:IsA("BasePart") then
					child.LocalTransparencyModifier = 1
				elseif child:IsA("Model") then
					for _, d in ipairs(child:GetDescendants()) do
						if d:IsA("BasePart") then d.LocalTransparencyModifier = 1 end
					end
				end
			end
		end
	end
	
	local function tpShowGun()
		local cam = workspace.CurrentCamera
		if not cam then return end
		for _, child in ipairs(cam:GetChildren()) do
			if child:IsA("BasePart") then
				child.LocalTransparencyModifier = 0
			elseif child:IsA("Model") then
				for _, d in ipairs(child:GetDescendants()) do
					if d:IsA("BasePart") then d.LocalTransparencyModifier = 0 end
				end
			end
		end
	end
	
	Feature{
		Id = "thirdperson", Tab = "Movement", Group = "Камера", Col = 1,
		Name = "Third Person", Desc = "Вид от третьего лица, настройки применяются мгновенно",
		Options = {
			{ Id = "dist", Type = "Slider", Name = "Дистанция", Min = 4, Max = 30, Default = 12, Suffix = "st",
			  OnChange = function() tpApply() end },
			{ Id = "offx", Type = "Slider", Name = "Смещение вбок", Min = -6, Max = 6, Default = 0, Step = 0.5, Suffix = "st",
			  OnChange = function() tpApply() end },
			{ Id = "offy", Type = "Slider", Name = "Смещение по высоте", Min = -4, Max = 6, Default = 0, Step = 0.5, Suffix = "st",
			  OnChange = function() tpApply() end },
			{ Id = "force", Type = "Toggle", Name = "Принудительный режим", Default = true },
			{ Id = "coll",  Type = "Toggle", Name = "Не проходить сквозь стены", Default = true },
			{ Id = "body",  Type = "Toggle", Name = "Показывать своё тело", Default = true },
			{ Id = "hidegun", Type = "Toggle", Name = "Скрывать оружие и руки", Default = true },
			{ Id = "lock", Type = "Toggle", Name = "Зафиксировать дистанцию", Default = false,
			  OnChange = function() tpApply() end },
			{ Id = "trans",Type = "Slider", Name = "Прозрачность себя", Min = 0, Max = 100, Default = 0, Suffix = "%",
			  OnChange = function() tpApply() end },
		},
		OnToggle = function(on)
			local hum = getHum()
			if on then
				if not tpBackup then
					tpBackup = {
						mode = LP.CameraMode,
						mn = LP.CameraMinZoomDistance,
						mx = LP.CameraMaxZoomDistance,
						off = hum and hum.CameraOffset or Vector3.zero,
					}
				end
				-- ровно то же, что делает меню при открытии: одно переключение режима
				if LP.CameraMode == Enum.CameraMode.LockFirstPerson then
					LP.CameraMode = Enum.CameraMode.Classic
				end
				task.defer(tpApply)
			elseif tpBackup then
				LP.CameraMinZoomDistance = tpBackup.mn
				LP.CameraMaxZoomDistance = tpBackup.mx
				LP.CameraMode = tpBackup.mode
				if hum then hum.CameraOffset = tpBackup.off end
				local ch = getChar()
				if ch then
					for _, part in ipairs(ch:GetDescendants()) do
						if part:IsA("BasePart") then part.LocalTransparencyModifier = 0 end
					end
				end
				tpShowGun()
				tpBackup = nil
			end
		end,
	}
	
	------------------------------------------------------------------ VISUALS ----
	local lightBackup
	Feature{
		Id = "fullbright", Tab = "Visuals", Group = "Освещение", Col = 1,
		Name = "Fullbright", Desc = "Полная засветка карты — видно во всех тёмных зонах",
		Options = {
			{ Id = "bright", Type = "Slider", Name = "Яркость", Min = 0, Max = 10, Default = 3, Step = 0.1 },
			{ Id = "amb",    Type = "Slider", Name = "Сила Ambient", Min = 0, Max = 255, Default = 255 },
			{ Id = "time",   Type = "Slider", Name = "Время суток", Min = 0, Max = 24, Default = 14, Step = 0.5, Suffix = "ч" },
			{ Id = "fog",    Type = "Toggle", Name = "Убирать туман", Default = true },
			{ Id = "sh",     Type = "Toggle", Name = "Отключать тени", Default = true },
			{ Id = "atm",    Type = "Toggle", Name = "Отключать атмосферу", Default = true },
			{ Id = "exp",    Type = "Slider", Name = "Экспозиция", Min = -2, Max = 2, Default = 0, Step = 0.1 },
		},
		OnToggle = function(on)
			if on then
				if lightBackup then return end
				lightBackup = {
					b = Lighting.Brightness, a = Lighting.Ambient, oa = Lighting.OutdoorAmbient,
					ct = Lighting.ClockTime, fs = Lighting.FogStart, fe = Lighting.FogEnd,
					gs = Lighting.GlobalShadows, ec = Lighting.ExposureCompensation, at = {},
				}
				for _, v in ipairs(Lighting:GetChildren()) do
					if v:IsA("Atmosphere") then table.insert(lightBackup.at, { o = v, d = v.Density }) end
				end
			elseif lightBackup then
				Lighting.Brightness, Lighting.Ambient = lightBackup.b, lightBackup.a
				Lighting.OutdoorAmbient, Lighting.ClockTime = lightBackup.oa, lightBackup.ct
				Lighting.FogStart, Lighting.FogEnd = lightBackup.fs, lightBackup.fe
				Lighting.GlobalShadows = lightBackup.gs
				Lighting.ExposureCompensation = lightBackup.ec
				for _, a in ipairs(lightBackup.at) do
					if a.o and a.o.Parent then a.o.Density = a.d end
				end
				lightBackup = nil
			end
		end,
		Step = function()
			local amb = math.floor(O("fullbright", "amb"))
			local c = Color3.fromRGB(amb, amb, amb)
			Lighting.Brightness = O("fullbright", "bright")
			Lighting.Ambient, Lighting.OutdoorAmbient = c, c
			Lighting.ClockTime = O("fullbright", "time")
			Lighting.ExposureCompensation = O("fullbright", "exp")
			if O("fullbright", "fog") then
				Lighting.FogStart, Lighting.FogEnd = 0, 1e6
			end
			if O("fullbright", "sh") then Lighting.GlobalShadows = false end
			if O("fullbright", "atm") then
				for _, v in ipairs(Lighting:GetChildren()) do
					if v:IsA("Atmosphere") and v.Density > 0 then v.Density = 0 end
				end
			end
		end,
	}
	
	-- ESP -------------------------------------------------------------------
	local espData = {}
	local BARS = {
		{ UDim2.new(0, 0, 0, 0), UDim2.new(0.3, 0, 0, 2), Vector2.new(0, 0) },
		{ UDim2.new(0, 0, 0, 0), UDim2.new(0, 2, 0.3, 0), Vector2.new(0, 0) },
		{ UDim2.new(1, 0, 0, 0), UDim2.new(0.3, 0, 0, 2), Vector2.new(1, 0) },
		{ UDim2.new(1, 0, 0, 0), UDim2.new(0, 2, 0.3, 0), Vector2.new(1, 0) },
		{ UDim2.new(0, 0, 1, 0), UDim2.new(0.3, 0, 0, 2), Vector2.new(0, 1) },
		{ UDim2.new(0, 0, 1, 0), UDim2.new(0, 2, 0.3, 0), Vector2.new(0, 1) },
		{ UDim2.new(1, 0, 1, 0), UDim2.new(0.3, 0, 0, 2), Vector2.new(1, 1) },
		{ UDim2.new(1, 0, 1, 0), UDim2.new(0, 2, 0.3, 0), Vector2.new(1, 1) },
	}
	
	local function destroyEsp(p)
		local d = espData[p]
		if not d then return end
		if d.box then d.box:Destroy() end
		if d.tracer then d.tracer:Destroy() end
		if d.off then d.off:Destroy() end
		if d.sb3d then d.sb3d:Destroy() end
		if d.lines then
			for _, l in ipairs(d.lines) do if l then l:Destroy() end end
		end
		if d.hl then pcall(function() d.hl:Destroy() end) end
		espData[p] = nil
	end
	local function clearEsp()
		for p in pairs(espData) do destroyEsp(p) end
	end
	
	local function buildEsp(p)
		local d = {}
		local _sb = Instance.new("BoxHandleAdornment")
		_sb.Name = "_an_3dbox"
		_sb.AlwaysOnTop = true
		_sb.ZIndex = 8
		_sb.Transparency = 0.72
		_sb.Color3 = Color3.fromRGB(255, 75, 92)
		_sb.Size = Vector3.new(4, 6, 2)
		_sb.Parent = workspace
		d.sb3d = _sb
		d.box = New("Frame", {
			Name = "esp_" .. p.Name, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
			Visible = false, ZIndex = 4, Parent = ESP_FOLDER,
		})
		d.outline = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = d.box })
		corner(d.outline, 4)
		d.outS = stroke(d.outline, Color3.new(1, 1, 1), 1, 0.35)
		d.glow = New("Frame", {
			BackgroundTransparency = 1, Size = UDim2.new(1, 4, 1, 4), Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 3, Parent = d.box,
		})
		corner(d.glow, 6)
		d.glowS = stroke(d.glow, Color3.new(0, 0, 0), 3, 0.55)
	
		d.bars = {}
		for _, def in ipairs(BARS) do
			local b = New("Frame", {
				Position = def[1], Size = def[2], AnchorPoint = def[3], BorderSizePixel = 0,
				BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 5, Parent = d.box,
			})
			corner(b, 1)
			table.insert(d.bars, b)
		end
	
		-- плашка ника
		d.plate = New("Frame", {
			AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -7), Size = UDim2.fromOffset(10, 17),
			AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Color3.fromRGB(10, 10, 14),
			BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 6, Parent = d.box,
		})
		corner(d.plate, 5)
		d.plateS = stroke(d.plate, Color3.new(1, 1, 1), 1, 0.6)
		padding(d.plate, 0, 0, 7, 7)
		d.name = New("TextLabel", {
			BackgroundTransparency = 1, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
			Font = FB, TextSize = 12, TextColor3 = Color3.new(1, 1, 1), Text = p.DisplayName,
			ZIndex = 7, Parent = d.plate,
		})
	
		d.info = New("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 5), Size = UDim2.new(0, 0, 0, 12),
			AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Font = FSB, TextSize = 11,
			TextColor3 = Color3.fromRGB(210, 214, 226), Text = "", ZIndex = 6, Parent = d.box,
		})
		New("UIStroke", { Thickness = 2, Color = Color3.new(0, 0, 0), Transparency = 0.35, Parent = d.info })
		d.tool = New("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 18), Size = UDim2.new(0, 0, 0, 12),
			AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Font = FM, TextSize = 10,
			TextColor3 = Color3.fromRGB(170, 175, 195), Text = "", ZIndex = 6, Parent = d.box,
		})
		New("UIStroke", { Thickness = 2, Color = Color3.new(0, 0, 0), Transparency = 0.4, Parent = d.tool })
	
		-- полоса здоровья слева
		d.hpBg = New("Frame", {
			Position = UDim2.new(0, -8, 0, 0), Size = UDim2.new(0, 3, 1, 0), BorderSizePixel = 0,
			BackgroundColor3 = Color3.fromRGB(12, 12, 16), BackgroundTransparency = 0.15, ZIndex = 5, Parent = d.box,
		})
		corner(d.hpBg, 2)
		d.hp = New("Frame", {
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 1, 0),
			BackgroundColor3 = Theme.Good, BorderSizePixel = 0, ZIndex = 6, Parent = d.hpBg,
		})
		corner(d.hp, 2)
		d.hpTxt = New("TextLabel", {
			AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(0, -3, 1, 0), Size = UDim2.fromOffset(30, 12),
			BackgroundTransparency = 1, Font = FSB, TextSize = 10, TextColor3 = Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Right, Text = "", ZIndex = 6, Parent = d.hpBg,
		})
		New("UIStroke", { Thickness = 2, Color = Color3.new(0, 0, 0), Transparency = 0.4, Parent = d.hpTxt })
	
		d.lines = {}
		for i = 1, 16 do
			d.lines[i] = New("Frame", {
				Name = "sk" .. i, AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0,
				BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromOffset(0, 1),
				Visible = false, ZIndex = 3, Parent = ESP_FOLDER,
			})
		end
		d.tracer = New("Frame", {
			Name = "tr_" .. p.Name, AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0,
			BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromOffset(0, 1), Visible = false,
			ZIndex = 2, Parent = ESP_FOLDER,
		})
		d.off = New("TextLabel", {
			Name = "off_" .. p.Name, AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1,
			Size = UDim2.fromOffset(22, 22), Font = FB, TextSize = 18, Text = "▲", Visible = false,
			TextColor3 = Theme.Bad, ZIndex = 7, Parent = ESP_FOLDER,
		})
		d.hl = nil
		d.char = nil
		espData[p] = d
		return d
	end
	
	local espUpdateAt, espTickIndex = 0, 0
	
	local adaptiveTier, adaptiveTierCheck = "Balanced", 0
	local TIER_ORDER = { "Ultra Low", "Performance", "Balanced", "Smooth" }
	local TIER_INDEX = { ["Ultra Low"]=1, Performance=2, Balanced=3, Smooth=4 }
	local function optimizerTier()
		local f = ById.optimizer
		if not f or not DB.optimizer then return "Balanced" end
		local p = O("optimizer", "profile")
		if p ~= "Adaptive" then return p end
		local now=os.clock()
		if now-adaptiveTierCheck < .75 then return adaptiveTier end
		adaptiveTierCheck=now
		local target=O("optimizer","target")
		local idx=TIER_INDEX[adaptiveTier] or 3
		-- asymmetric thresholds keep the controller from oscillating around target FPS.
		if infoFps < target-12 and idx>1 then idx-=1
		elseif infoFps > target+14 and idx<#TIER_ORDER then idx+=1
		elseif adaptiveTier=="Smooth" and infoFps<target+3 then idx=3
		elseif adaptiveTier=="Ultra Low" and infoFps>target-6 then idx=2 end
		adaptiveTier=TIER_ORDER[idx]
		return adaptiveTier
	end
	
	local function perfEspInterval()
		local tier = optimizerTier()
		if tier == "Smooth" then return 1/90 end
		if tier == "Balanced" then return 1/60 end
		if tier == "Performance" then return 1/35 end
		if tier == "Ultra Low" then return 1/20 end
		return 1 / math.max(O("optimizer", "esphz"), 10)
	end
	local function perfVisTTL()
		local tier = optimizerTier()
		if tier == "Smooth" then return 0.07 end
		if tier == "Balanced" then return 0.11 end
		if tier == "Performance" then return 0.20 end
		if tier == "Ultra Low" then return 0.32 end
		return O("optimizer", "visms") / 1000
	end
	local function perfBoxTTL()
		local tier = optimizerTier()
		if tier == "Smooth" then return 0.08 end
		if tier == "Balanced" then return 0.14 end
		if tier == "Performance" then return 0.25 end
		if tier == "Ultra Low" then return 0.42 end
		return O("optimizer", "boxms") / 1000
	end
	local function perfRadarInterval()
		local tier = optimizerTier()
		if tier == "Smooth" then return 0.055 end
		if tier == "Balanced" then return 0.08 end
		if tier == "Performance" then return 0.13 end
		if tier == "Ultra Low" then return 0.20 end
		return O("optimizer", "radarms") / 1000
	end
	local function perfSkeletonDiv()
		local tier = optimizerTier()
		if tier == "Smooth" or tier == "Balanced" then return 1 end
		if tier == "Performance" then return 2 end
		if tier == "Ultra Low" then return 3 end
		return O("optimizer", "skeldiv")
	end
	
	Feature{
		Id = "esp", Tab = "Visuals", Group = "Игроки", Col = 2,
		Name = "Player ESP", Desc = "Рамки, ники, HP, оружие, чамсы и трейсеры",
		Options = {
			{ Id = "box",    Type = "Toggle", Name = "Рамка 2D", Default = true },
			{ Id = "box3d",  Type = "Toggle", Name = "3D bounding box", Default = false },
			{ Id = "off",    Type = "Toggle", Name = "Off-screen индикаторы", Default = true },
			{ Id = "style",  Type = "Dropdown", Name = "Стиль рамки", List = { "Углы", "Полная", "Углы + контур" }, Default = "Углы + контур" },
			{ Id = "name",   Type = "Toggle", Name = "Ник", Default = true },
			{ Id = "dist",   Type = "Toggle", Name = "Дистанция", Default = true },
			{ Id = "tool",   Type = "Toggle", Name = "Оружие в руках", Default = true },
			{ Id = "hp",     Type = "Toggle", Name = "Полоса HP", Default = true },
			{ Id = "hptxt",  Type = "Toggle", Name = "Число HP", Default = true },
			{ Id = "chams",  Type = "Toggle", Name = "Чамсы", Default = true },
			{ Id = "skel",   Type = "Toggle", Name = "Скелет", Default = false },
			{ Id = "tracer", Type = "Toggle", Name = "Трейсеры", Default = false },
			{ Id = "trfrom", Type = "Dropdown", Name = "Начало трейсера", List = { "Низ экрана", "Центр экрана", "Верх экрана" }, Default = "Низ экрана" },
			{ Id = "vis",    Type = "Toggle", Name = "Отмечать видимых", Default = true },
			{ Id = "tc",     Type = "Toggle", Name = "Скрывать союзников", Default = false },
			{ Id = "maxd",   Type = "Slider", Name = "Макс. дистанция", Min = 50, Max = 5000, Default = 1500, Step = 50, Suffix = "st" },
			{ Id = "fill",   Type = "Slider", Name = "Заливка чамсов", Min = 0, Max = 100, Default = 55, Suffix = "%" },
			{ Id = "thick",  Type = "Slider", Name = "Толщина рамки", Min = 1, Max = 4, Default = 2, Suffix = "px" },
			{ Id = "fade",   Type = "Toggle", Name = "Плавно скрывать дальние цели", Default = true },
			{ Id = "fademin",Type = "Slider", Name = "Начало fade", Min = 10, Max = 90, Default = 65, Step = 5, Suffix = "%" },
			{ Id = "php",    Type = "Slider", Name = "Preview: HP", Min = 1, Max = 100, Default = 74, Step = 1, Suffix = "%" },
			{ Id = "pdist",  Type = "Slider", Name = "Preview: дистанция", Min = 5, Max = 500, Default = 42, Step = 5, Suffix = " st" },
			{ Id = "pocc",   Type = "Toggle", Name = "Preview: цель за стеной", Default = false },
			{ Id = "pspin",  Type = "Slider", Name = "Preview: скорость вращения", Min = 0, Max = 100, Default = 32, Step = 2, Suffix = "%" },
			{ Id = "cEnemy", Type = "Color", Name = "Цвет врага", Default = "#FF4B5C" },
			{ Id = "cAlly",  Type = "Color", Name = "Цвет союзника", Default = "#4BE08A" },
			{ Id = "cVis",   Type = "Color", Name = "Цвет видимого", Default = "#FFD24B" },
		},
		OnToggle = function(on) if not on then clearEsp() end end,
		Step = function()
			local now = os.clock()
			local interval = perfEspInterval()
			if (now - espUpdateAt) < interval then return end
			espUpdateAt = now
			espTickIndex += 1
			local maxd   = O("esp", "maxd")
			local camPos = Camera.CFrame.Position
			local vp     = VP()
			local style  = O("esp", "style")
			local thick  = O("esp", "thick")
	
			for _, p in ipairs(Players:GetPlayers()) do
				if p == LP then continue end
				local ch   = p.Character
				local hum  = ch and ch:FindFirstChildOfClass("Humanoid")
				local root = ch and ch:FindFirstChild("HumanoidRootPart")
				local head = ch and ch:FindFirstChild("Head")
				local d    = espData[p] or buildEsp(p)
	
				local _ehp = (hum and hum.Health) or (ch and ch:GetAttribute("Health")) or (ch and ch:GetAttribute("HP")) or 0
				local show = (ch ~= nil and root ~= nil and head ~= nil and _ehp > 0)
				if show and O("esp", "tc") and not isEnemy(p) then show = false end
				local dist = show and (camPos - root.Position).Magnitude or 0
				if show and dist > maxd then show = false end
	
				local sp, onScreen
				if show then
					sp, onScreen = Camera:WorldToViewportPoint(root.Position)
				end
	
				local enemy = isEnemy(p)
				local baseCol = enemy and OC("esp", "cEnemy") or OC("esp", "cAlly")
				if d.off then d.off.Visible = false end
	
				if show and not onScreen and O("esp", "off") then
					local to = (root.Position - camPos)
					if to.Magnitude > 0.01 then
						local u = to.Unit
						local x = Camera.CFrame.RightVector:Dot(u)
						local y = -Camera.CFrame.UpVector:Dot(u)
						if Camera.CFrame.LookVector:Dot(u) < 0 then x, y = -x, -y end
						local v = Vector2.new(x, y)
						if v.Magnitude < 0.01 then v = Vector2.new(0, -1) end
						v = v.Unit
						local radius = math.max(math.min(vp.X, vp.Y) * 0.42, 80)
						local pos = Vector2.new(vp.X / 2, vp.Y / 2) + v * radius
						d.off.Visible = true
						d.off.Position = UDim2.fromOffset(pos.X, pos.Y)
						d.off.Rotation = math.deg(math.atan2(v.Y, v.X)) + 90
						d.off.TextColor3 = baseCol
					end
				end
	
				if not show or not onScreen then
					d.box.Visible = false
					d.tracer.Visible = false
					if d.lines then
						for _, ln in ipairs(d.lines) do ln.Visible = false end
					end
					if d.sb3d then d.sb3d.Adornee = nil end
					if d.hl and d.hl.Parent then d.hl.Enabled = false end
					continue
				end
	
				-- цвет
				local col = baseCol
				if d.sb3d then
					if O("esp", "box3d") then
						if d._boxChar ~= ch or not d._boxAt or (now - d._boxAt) > perfBoxTTL() then
							local bcf, bsize = ch:GetBoundingBox()
							d._boxChar, d._boxAt = ch, now
							d._boxSize = bsize + Vector3.new(0.18, 0.18, 0.18)
							d._boxLocal = root.CFrame:ToObjectSpace(bcf)
						end
						d.sb3d.Adornee = root
						d.sb3d.Size = d._boxSize or Vector3.new(4, 6, 2)
						d.sb3d.CFrame = d._boxLocal or CFrame.new()
					else
						d.sb3d.Adornee = nil
					end
				end
				local visible = false
				-- цвет видимости применяем только к врагам, чтобы союзники
				-- всегда оставались узнаваемыми
				if O("esp", "vis") and enemy then
					if d._visChar ~= ch or not d._visAt or (now - d._visAt) > perfVisTTL() then
						d._visChar, d._visAt = ch, now
						d._visible = partVisible(head, ch)
					end
					visible = d._visible == true
					if visible then col = OC("esp", "cVis") end
				end
				if d.sb3d then d.sb3d.Color3 = col end
	
				-- габариты рамки
				local top = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 1.1, 0))
				local bot = Camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3.2, 0))
				local h = math.max(math.abs(bot.Y - top.Y), 12)
				local w = h * 0.58
	
				d.box.Visible = O("esp", "box") or O("esp", "name") or O("esp", "dist") or O("esp", "hp")
				d.box.Position = UDim2.fromOffset(sp.X, (top.Y + bot.Y) / 2)
				d.box.Size = UDim2.fromOffset(w, h)
	
				local wantBars = O("esp", "box") and (style ~= "Полная")
				local wantOut  = O("esp", "box") and (style ~= "Углы")
				for _, b in ipairs(d.bars) do
					b.Visible = wantBars
					b.BackgroundColor3 = col
					if b.Size.X.Scale > 0 then
						b.Size = UDim2.new(0.3, 0, 0, thick)
					else
						b.Size = UDim2.new(0, thick, 0.3, 0)
					end
				end
				d.outline.Visible = wantOut
				d.outS.Color = col
				d.outS.Thickness = (style == "Полная") and thick or 1
				d.outS.Transparency = (style == "Полная") and 0 or 0.55
				d.glow.Visible = O("esp", "box")
				d.glowS.Thickness = thick + 2
	
				-- ник
				d.plate.Visible = O("esp", "name")
				d.name.Text = safePlayerLabel(p)
				d.name.TextColor3 = col
				d.plateS.Color = col
	
				-- дистанция
				d.info.Visible = O("esp", "dist")
				d.info.Text = math.floor(dist) .. " st"
	
				-- оружие
				local toolName = ""
				if ch then
					local t = ch:FindFirstChildOfClass("Tool")
					if t then toolName = t.Name end
				end
				d.tool.Visible = O("esp", "tool") and toolName ~= ""
				d.tool.Text = toolName
				d.tool.Position = UDim2.new(0.5, 0, 1, O("esp", "dist") and 18 or 5)
	
				-- HP
				d.hpBg.Visible = O("esp", "hp")
				local ratio = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
				d.hp.Size = UDim2.new(1, 0, ratio, 0)
				d.hp.BackgroundColor3 = Theme.Bad:Lerp(Theme.Good, ratio)
				d.hpTxt.Visible = O("esp", "hptxt") and O("esp", "hp")
				d.hpTxt.Text = tostring(math.floor(hum.Health))
				d.hpTxt.Position = UDim2.new(0, -3, 1 - ratio, 0)
	
				-- optional distance fade keeps far targets readable without filling the screen
				local fadeAlpha = 0
				if O("esp", "fade") then
					local start = maxd * (O("esp", "fademin") / 100)
					if dist > start then fadeAlpha = math.clamp((dist - start) / math.max(maxd - start, 1), 0, 0.72) end
				end
				d.name.TextTransparency = fadeAlpha
				d.info.TextTransparency = math.min(fadeAlpha + 0.08, 0.82)
				d.tool.TextTransparency = math.min(fadeAlpha + 0.08, 0.82)
				d.hpTxt.TextTransparency = fadeAlpha
				d.outS.Transparency = math.max(d.outS.Transparency, fadeAlpha)
	
				-- трейсер
				if O("esp", "tracer") then
					local from
					local fr = O("esp", "trfrom")
					if fr == "Центр экрана" then from = Vector2.new(vp.X / 2, vp.Y / 2)
					elseif fr == "Верх экрана" then from = Vector2.new(vp.X / 2, 0)
					else from = Vector2.new(vp.X / 2, vp.Y) end
					local to = Vector2.new(sp.X, sp.Y)
					local delta = to - from
					d.tracer.Visible = true
					d.tracer.BackgroundColor3 = col
					d.tracer.Size = UDim2.fromOffset(delta.Magnitude, math.max(thick - 1, 1))
					d.tracer.Position = UDim2.fromOffset((from.X + to.X) / 2, (from.Y + to.Y) / 2)
					d.tracer.Rotation = math.deg(math.atan2(delta.Y, delta.X))
				else
					d.tracer.Visible = false
				end
	
				-- скелет
				if O("esp", "skel") and (espTickIndex % perfSkeletonDiv() == 0) then
					local pairsList = {
						{ "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
						{ "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
						{ "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
						{ "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
						{ "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
					}
					if not ch:FindFirstChild("UpperTorso") then
						pairsList = {
							{ "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
							{ "Torso", "Left Leg" }, { "Torso", "Right Leg" },
						}
					end
					local idx = 0
					for _, pair in ipairs(pairsList) do
						local a = ch:FindFirstChild(pair[1])
						local b2 = ch:FindFirstChild(pair[2])
						if a and b2 then
							idx += 1
							local ln = d.lines[idx]
							if ln then
								local p1, on1 = Camera:WorldToViewportPoint(a.Position)
								local p2, on2 = Camera:WorldToViewportPoint(b2.Position)
								if on1 and on2 then
									local v1, v2 = Vector2.new(p1.X, p1.Y), Vector2.new(p2.X, p2.Y)
									local delta = v2 - v1
									ln.Visible = true
									ln.BackgroundColor3 = col
									ln.Size = UDim2.fromOffset(delta.Magnitude, 1)
									ln.Position = UDim2.fromOffset((v1.X + v2.X) / 2, (v1.Y + v2.Y) / 2)
									ln.Rotation = math.deg(math.atan2(delta.Y, delta.X))
								else
									ln.Visible = false
								end
							end
						end
					end
					for i = idx + 1, #d.lines do d.lines[i].Visible = false end
				else
					for _, ln in ipairs(d.lines) do ln.Visible = false end
				end
	
				-- чамсы
				if O("esp", "chams") then
					if d.char ~= ch or not d.hl or not d.hl.Parent then
						if d.hl then pcall(function() d.hl:Destroy() end) end
						d.hl = New("Highlight", {
							Name = "hl", FillTransparency = 0.6, OutlineTransparency = 0.1,
							DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, Parent = ch,
						})
						d.char = ch
					end
					d.hl.Adornee = ch
					d.hl.Enabled = true
					d.hl.FillColor = col
					d.hl.OutlineColor = col
					d.hl.FillTransparency = 1 - (O("esp", "fill") / 100)
				elseif d.hl and d.hl.Parent then
					d.hl.Enabled = false
				end
			end
		end,
	}
	
	local fovOriginal = nil
	Feature{
		Id = "fovchange", Tab = "Visuals", Group = "Камера", Col = 1,
		Name = "FOV Changer", Desc = "Угол обзора камеры, удерживается поверх игровых скриптов",
		Options = {
			{ Id = "fov",    Type = "Slider", Name = "Угол обзора", Min = 20, Max = 120, Default = 90, Suffix = "°" },
			{ Id = "smooth", Type = "Toggle", Name = "Плавный переход", Default = false },
			{ Id = "sprint", Type = "Toggle", Name = "Расширять при беге", Default = false },
			{ Id = "add",    Type = "Slider", Name = "Прибавка при беге", Min = 0, Max = 30, Default = 10, Suffix = "°" },
		},
		OnToggle = function(on)
			if on then
				if fovOriginal == nil then fovOriginal = Camera.FieldOfView end
			else
				Camera.FieldOfView = fovOriginal or 70
				fovOriginal = nil
			end
		end,
		Step = function(dt)
			local cam = workspace.CurrentCamera
			if not cam then return end
			local t = O("fovchange", "fov")
			if O("fovchange", "sprint") then
				local h = getHum()
				if h and h.MoveDirection.Magnitude > 0 and UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
					t += O("fovchange", "add")
				end
			end
			if O("fovchange", "smooth") then
				cam.FieldOfView += (t - cam.FieldOfView) * math.min(dt * 10, 1)
			elseif math.abs(cam.FieldOfView - t) > 0.01 then
				cam.FieldOfView = t
			end
		end,
	}
	
	Feature{
		Id = "crosshair", Tab = "Visuals", Group = "Камера", Col = 1,
		Name = "Custom Crosshair", Desc = "Собственный прицел поверх игры",
		Options = {
			{ Id = "style", Type = "Dropdown", Name = "Стиль", List = { "Крест", "Крест + точка", "Точка" }, Default = "Крест + точка" },
			{ Id = "size",  Type = "Slider", Name = "Длина", Min = 2, Max = 30, Default = 9, Suffix = "px" },
			{ Id = "gap",   Type = "Slider", Name = "Отступ", Min = 0, Max = 20, Default = 5, Suffix = "px" },
			{ Id = "th",    Type = "Slider", Name = "Толщина", Min = 1, Max = 6, Default = 2, Suffix = "px" },
			{ Id = "dot",   Type = "Slider", Name = "Размер точки", Min = 1, Max = 8, Default = 2, Suffix = "px" },
			{ Id = "col",   Type = "Color",  Name = "Цвет", Default = "#40CCFF" },
			{ Id = "out",   Type = "Toggle", Name = "Обводка", Default = true },
		},
		OnToggle = function(on)
			for _, v in ipairs(crossParts) do v.Visible = on end
		end,
		Step = function()
			local st = O("crosshair", "style")
			local sz, gap, th = O("crosshair", "size"), O("crosshair", "gap"), O("crosshair", "th")
			local col = OC("crosshair", "col")
			local lines, dot = (st ~= "Точка"), (st ~= "Крест")
			for i = 1, 4 do
				local v = crossParts[i]
				v.Visible = lines
				v.BackgroundColor3 = col
				local s = v:FindFirstChildOfClass("UIStroke")
				if s then s.Enabled = O("crosshair", "out") end
				if i == 1 then v.Size = UDim2.fromOffset(th, sz) v.Position = UDim2.new(0.5, 0, 0.5, -gap - sz / 2)
				elseif i == 2 then v.Size = UDim2.fromOffset(th, sz) v.Position = UDim2.new(0.5, 0, 0.5, gap + sz / 2)
				elseif i == 3 then v.Size = UDim2.fromOffset(sz, th) v.Position = UDim2.new(0.5, -gap - sz / 2, 0.5, 0)
				else v.Size = UDim2.fromOffset(sz, th) v.Position = UDim2.new(0.5, gap + sz / 2, 0.5, 0) end
			end
			local dp = crossParts[5]
			dp.Visible = dot
			dp.BackgroundColor3 = col
			local ds = O("crosshair", "dot")
			dp.Size = UDim2.fromOffset(ds * 2, ds * 2)
		end,
	}
	
	local fireTracer
	local trFolder, trConn, trTool
	
	local PELLET_NAMES = { "Pellets", "PelletCount", "BulletsPerShot", "Bullets",
		"ShotCount", "Shots", "NumBullets", "BulletCount" }
	
	-- сколько пуль вылетает за выстрел: читаем параметр самого оружия
	local function detectPellets(tool)
		if not tool then return 1 end
		for _, n in ipairs(PELLET_NAMES) do
			local a = tool:GetAttribute(n)
			if type(a) == "number" and a >= 1 then return math.clamp(math.floor(a), 1, 40) end
		end
		for _, n in ipairs(PELLET_NAMES) do
			local v = tool:FindFirstChild(n, true)
			if v and (v:IsA("IntValue") or v:IsA("NumberValue")) and v.Value >= 1 then
				return math.clamp(math.floor(v.Value), 1, 40)
			end
		end
		return 1
	end
	
	local function spawnTracer(from, to, col, thick, life, fade)
		if not trFolder or not trFolder.Parent then
			trFolder = Instance.new("Folder")
			trFolder.Name = "_an_tracers"
			trFolder.Parent = workspace
		end
		local dist = (to - from).Magnitude
		if dist < 0.5 then return end
		local part = Instance.new("Part")
		part.Name = "_an_tracer"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = col
		part.Size = Vector3.new(thick, thick, dist)
		part.CFrame = CFrame.lookAt((from + to) / 2, to)
		part.Transparency = 0.25
		part.Parent = trFolder
	
		-- яркая сердцевина внутри свечения
		local core = part:Clone()
		core.Size = Vector3.new(thick * 0.35, thick * 0.35, dist)
		core.Color = Color3.new(
			math.min(col.R + 0.45, 1), math.min(col.G + 0.45, 1), math.min(col.B + 0.45, 1))
		core.Transparency = 0
		core.Parent = trFolder
	
		if fade then
			local ti = TweenInfo.new(life, Enum.EasingStyle.Linear)
			TweenService:Create(part, ti, { Transparency = 1, Size = Vector3.new(thick * 0.2, thick * 0.2, dist) }):Play()
			TweenService:Create(core, ti, { Transparency = 1 }):Play()
		end
		task.delay(life, function()
			if part then part:Destroy() end
			if core then core:Destroy() end
		end)
		return part
	end
	
	Feature{
		Id = "tracers", Tab = "Visuals", Group = "Мир", Col = 2,
		Name = "Bullet Tracers", Desc = "След выстрела от ствола до точки попадания",
		Options = {
			{ Id = "src",   Type = "Dropdown", Name = "Срабатывать по",
			  List = { "Клик мыши", "Tool.Activated", "Оба" }, Default = "Оба" },
			{ Id = "col",   Type = "Color",  Name = "Цвет следа", Default = "#40CCFF" },
			{ Id = "auto",  Type = "Toggle", Name = "Определять число пуль", Default = true },
			{ Id = "count", Type = "Slider", Name = "Пуль за выстрел", Min = 1, Max = 20, Default = 1 },
			{ Id = "spread",Type = "Slider", Name = "Разлёт пуль", Min = 0, Max = 12, Default = 3, Step = 0.5, Suffix = "°" },
			{ Id = "off",   Type = "Slider", Name = "Отступ от экрана", Min = 0, Max = 14, Default = 5, Step = 0.5, Suffix = "st" },
			{ Id = "hitcol",Type = "Color",  Name = "Цвет попадания", Default = "#FF4B5C" },
			{ Id = "thick", Type = "Slider", Name = "Толщина", Min = 1, Max = 20, Default = 4, Suffix = "×0.05" },
			{ Id = "life",  Type = "Slider", Name = "Время жизни", Min = 100, Max = 3000, Default = 500, Step = 50, Suffix = "мс" },
			{ Id = "from",  Type = "Dropdown", Name = "Начало следа", List = { "Ствол", "Камера" }, Default = "Ствол" },
			{ Id = "full",  Type = "Toggle", Name = "Тянуть на всю длину", Default = true },
			{ Id = "fade",  Type = "Toggle", Name = "Плавное затухание", Default = false },
			{ Id = "dist",  Type = "Slider", Name = "Дальность", Min = 100, Max = 3000, Default = 1200, Step = 50, Suffix = "st" },
			{ Id = "mark",  Type = "Toggle", Name = "Отметка попадания", Default = true },
			{ Id = "only",  Type = "Toggle", Name = "Только попадания по игрокам", Default = false },
		},
		OnToggle = function(on)
			if on then return end
			if trConn then trConn:Disconnect() trConn = nil end
			trTool = nil
			if trFolder then trFolder:Destroy() trFolder = nil end
		end,
		Step = function()
			local ch = getChar()
			if not ch then return end
			local tool = ch:FindFirstChildOfClass("Tool")
			if tool == trTool then return end
	
			if trConn then trConn:Disconnect() trConn = nil end
			trTool = tool
			if not tool then return end
	
			trConn = tool.Activated:Connect(function()
				if O("tracers", "src") == "Клик мыши" then return end
				fireTracer()
			end)
		end,
	}
	
	local trLast = 0
	function fireTracer()
		local f = ById.tracers
		if not f or not f._active then return end
		local now = os.clock()
		if now - trLast < 0.03 then return end
		trLast = now
	
		local ch = getChar()
		do
				local vp = VP()
				local ray = Camera:ViewportPointToRay(vp.X / 2, vp.Y / 2)
				local rp = RaycastParams.new()
				rp.FilterType = Enum.RaycastFilterType.Exclude
				rp.FilterDescendantsInstances = { ch, trFolder }
				rp.IgnoreWater = true
	
				local tool = ch and ch:FindFirstChildOfClass("Tool")
				local maxd = O("tracers", "dist")
				local res = workspace:Raycast(ray.Origin, ray.Direction * maxd, rp)
				local hitPos = res and res.Position or (ray.Origin + ray.Direction * maxd)
	
				if O("tracers", "only") then
					local model = res and res.Instance and res.Instance:FindFirstAncestorOfClass("Model")
					local plr = model and Players:GetPlayerFromCharacter(model)
					if not plr or plr == LP then return end
				end
	
				local from = ray.Origin
				if O("tracers", "from") == "Ствол" and tool then
					local handle = tool:FindFirstChild("Handle") or tool:FindFirstChildWhichIsA("BasePart")
					if handle then from = handle.Position end
				end
	
				local thick = O("tracers", "thick") * 0.05
				local life = O("tracers", "life") / 1000
	
				-- отодвигаем начало от лица, иначе луч упирается в камеру
				from = from + ray.Direction.Unit * O("tracers", "off")
	
				local endPos = hitPos
				if O("tracers", "full") then
					endPos = ray.Origin + ray.Direction * maxd
				end
	
				local pellets = O("tracers", "auto") and detectPellets(tool) or O("tracers", "count")
				if pellets < 1 then pellets = 1 end
				local tcol = OC("tracers", "col")
				local spread = math.rad(O("tracers", "spread"))
	
				for i = 1, pellets do
					local target = endPos
					if pellets > 1 and spread > 0 then
						local dir = endPos - from
						local len = dir.Magnitude
						local rot = CFrame.Angles((math.random() - 0.5) * spread,
							(math.random() - 0.5) * spread, 0)
						target = from + (rot * dir.Unit) * len
					end
					spawnTracer(from, target, tcol, thick, life, O("tracers", "fade"))
				end
	
				if O("tracers", "mark") and res then
					local dot = Instance.new("Part")
					dot.Name = "_an_hit"
					dot.Shape = Enum.PartType.Ball
					dot.Anchored = true
					dot.CanCollide = false
					dot.CanQuery = false
					dot.CanTouch = false
					dot.CastShadow = false
					dot.Material = Enum.Material.Neon
					dot.Color = OC("tracers", "hitcol")
					dot.Size = Vector3.new(0.35, 0.35, 0.35)
					dot.CFrame = CFrame.new(res.Position)
					dot.Parent = trFolder or workspace
					TweenService:Create(dot, TweenInfo.new(life), {
						Transparency = 1, Size = Vector3.new(0.9, 0.9, 0.9),
					}):Play()
					task.delay(life + 0.1, function() if dot then dot:Destroy() end end)
				end
		end
	end
	
	local fogBackup = nil
	Feature{
		Id = "nofog", Tab = "Visuals", Group = "Мир", Col = 2,
		Name = "No Fog", Desc = "Полностью убирает туман и атмосферу, не трогая свет",
		Options = {
			{ Id = "atm",  Type = "Toggle", Name = "Также убирать Atmosphere", Default = true },
			{ Id = "depth",Type = "Toggle", Name = "Убирать DepthOfField", Default = true },
		},
		OnToggle = function(on)
			if on then
				if fogBackup then return end
				fogBackup = { fs = Lighting.FogStart, fe = Lighting.FogEnd, atm = {}, dof = {} }
				for _, v in ipairs(Lighting:GetChildren()) do
					if v:IsA("Atmosphere") then table.insert(fogBackup.atm, { o = v, d = v.Density }) end
					if v:IsA("DepthOfFieldEffect") then table.insert(fogBackup.dof, { o = v, e = v.Enabled }) end
				end
			elseif fogBackup then
				Lighting.FogStart, Lighting.FogEnd = fogBackup.fs, fogBackup.fe
				for _, a in ipairs(fogBackup.atm) do
					if a.o and a.o.Parent then a.o.Density = a.d end
				end
				for _, d in ipairs(fogBackup.dof) do
					if d.o and d.o.Parent then d.o.Enabled = d.e end
				end
				fogBackup = nil
			end
		end,
		Step = function()
			Lighting.FogStart = 0
			Lighting.FogEnd = 1e6
			if O("nofog", "atm") then
				for _, v in ipairs(Lighting:GetChildren()) do
					if v:IsA("Atmosphere") and v.Density > 0 then v.Density = 0 end
				end
			end
			if O("nofog", "depth") then
				for _, v in ipairs(Lighting:GetChildren()) do
					if v:IsA("DepthOfFieldEffect") and v.Enabled then v.Enabled = false end
				end
			end
		end,
	}
	
	local ccEffect
	Feature{
		Id = "world", Tab = "Visuals", Group = "Мир", Col = 2,
		Name = "World Tweaks", Desc = "Цветокоррекция сцены",
		Options = {
			{ Id = "sat",  Type = "Slider", Name = "Насыщенность", Min = -100, Max = 100, Default = 12, Suffix = "%" },
			{ Id = "con",  Type = "Slider", Name = "Контраст", Min = -100, Max = 100, Default = 8, Suffix = "%" },
			{ Id = "bri",  Type = "Slider", Name = "Яркость", Min = -50, Max = 50, Default = 0, Suffix = "%" },
			{ Id = "tint", Type = "Color",  Name = "Оттенок", Default = "#FFFFFF" },
		},
		OnToggle = function(on)
			if on then
				ccEffect = New("ColorCorrectionEffect", { Name = "_an_cc", Parent = Lighting })
			elseif ccEffect then
				ccEffect:Destroy() ccEffect = nil
			end
		end,
		Step = function()
			if not ccEffect then return end
			ccEffect.Saturation = O("world", "sat") / 100
			ccEffect.Contrast = O("world", "con") / 100
			ccEffect.Brightness = O("world", "bri") / 100
			ccEffect.TintColor = OC("world", "tint")
		end,
	}
	
	----------------------------------------------------------------- SETTINGS ----
	
	Feature{
		Id = "streamer", Tab = "Settings", Group = "Приватность", Col = 1, On = false,
		Name = "Streamer Mode", Desc = "Скрывает личные данные в HUD, ESP и информационных панелях",
		Options = {
			{ Id = "alias",   Type = "Text", Name = "Псевдоним", Default = "ANON", Placeholder = "ANON" },
			{ Id = "self",    Type = "Toggle", Name = "Скрывать мой ник", Default = true },
			{ Id = "players", Type = "Toggle", Name = "Скрывать ники игроков", Default = true },
			{ Id = "userid",  Type = "Toggle", Name = "Скрывать User ID", Default = true },
			{ Id = "server",  Type = "Toggle", Name = "Скрывать Place / Job ID", Default = true },
			{ Id = "avatar",  Type = "Toggle", Name = "Скрывать аватар в интерфейсе", Default = false },
		},
	}
	
	local radarPanel, targetHud, perfPanel, threatPanel
	local perfText
	local threatRows = {}
	Feature{
		Id = "radar", Tab = "Visuals", Group = "Оверлей", Col = 1, On = false,
		Name = "Radar", Desc = "Мини-радар игроков вокруг персонажа",
		Options = {
			{ Id = "range", Type = "Slider", Name = "Дальность", Min = 50, Max = 2000, Default = 350, Step = 25, Suffix = "st" },
			{ Id = "size", Type = "Slider", Name = "Размер", Min = 120, Max = 260, Default = 176, Step = 4, Suffix = "px" },
			{ Id = "team", Type = "Toggle", Name = "Показывать союзников", Default = true },
			{ Id = "names", Type = "Toggle", Name = "Подписи игроков", Default = false },
			{ Id = "rotate", Type = "Toggle", Name = "Вращать с персонажем", Default = true },
		},
		OnToggle = function(on) if radarPanel then radarPanel.Visible = on end end,
	}
	
	Feature{
		Id = "targethud", Tab = "Visuals", Group = "Оверлей", Col = 1, On = true,
		Name = "Target HUD", Desc = "Карточка текущей цели Aimbot с HP, дистанцией и оружием",
		Options = {
			{ Id = "hp", Type = "Toggle", Name = "HP", Default = true },
			{ Id = "dist", Type = "Toggle", Name = "Дистанция", Default = true },
			{ Id = "tool", Type = "Toggle", Name = "Оружие", Default = true },
			{ Id = "avatar", Type = "Toggle", Name = "Аватар", Default = true },
		},
		OnToggle = function(on) if targetHud then targetHud.Visible = false end end,
	}
	
	Feature{
		Id = "perfmon", Tab = "Settings", Group = "Оверлей", Col = 1, On = false,
		Name = "Performance Monitor", Desc = "Компактный монитор FPS, frame time, ping, памяти и активных модулей",
		Options = {
			{ Id = "fps", Type = "Toggle", Name = "FPS / frame time", Default = true },
			{ Id = "ping", Type = "Toggle", Name = "Пинг", Default = true },
			{ Id = "mem", Type = "Toggle", Name = "Память клиента", Default = true },
			{ Id = "active", Type = "Toggle", Name = "Активные модули", Default = true },
			{ Id = "budget", Type = "Toggle", Name = "Показывать render budget", Default = true },
			{ Id = "rate", Type = "Slider", Name = "Обновление", Min = 100, Max = 1000, Default = 250, Step = 50, Suffix = "мс" },
		},
		OnToggle = function(on) if perfPanel then perfPanel.Visible = on end end,
	}
	
	Feature{
		Id = "optimizer", Tab = "Settings", Group = "Производительность", Col = 1, NoToggle = true,
		Name = "Render Budget", Desc = "Адаптивно снижает частоту тяжёлых ESP/Radar вычислений, если FPS проседает",
		Options = {
			{ Id = "profile", Type = "Dropdown", Name = "Профиль", List = { "Adaptive", "Smooth", "Balanced", "Performance", "Ultra Low", "Custom" }, Default = "Adaptive" },
			{ Id = "target", Type = "Slider", Name = "Целевой FPS для Adaptive", Min = 30, Max = 144, Default = 60, Step = 1, Suffix = " fps" },
			{ Id = "esphz", Type = "Slider", Name = "Custom: ESP частота", Min = 10, Max = 120, Default = 60, Step = 5, Suffix = " hz" },
			{ Id = "visms", Type = "Slider", Name = "Custom: visibility cache", Min = 40, Max = 600, Default = 110, Step = 10, Suffix = "мс" },
			{ Id = "boxms", Type = "Slider", Name = "Custom: 3D box cache", Min = 50, Max = 1000, Default = 140, Step = 10, Suffix = "мс" },
			{ Id = "radarms", Type = "Slider", Name = "Custom: Radar update", Min = 40, Max = 500, Default = 80, Step = 10, Suffix = "мс" },
			{ Id = "skeldiv", Type = "Slider", Name = "Custom: Skeleton каждый N tick", Min = 1, Max = 6, Default = 1, Step = 1 },
		},
	}
	
	Feature{
		Id = "threats", Tab = "Visuals", Group = "Оверлей", Col = 1, On = false,
		Name = "Threat List", Desc = "Список ближайших живых противников с HP, дистанцией и оружием",
		Options = {
			{ Id = "count", Type = "Slider", Name = "Игроков в списке", Min = 2, Max = 8, Default = 4, Step = 1 },
			{ Id = "range", Type = "Slider", Name = "Дальность", Min = 100, Max = 5000, Default = 1200, Step = 100, Suffix = "st" },
			{ Id = "hp", Type = "Toggle", Name = "Показывать HP", Default = true },
			{ Id = "tool", Type = "Toggle", Name = "Показывать оружие", Default = true },
			{ Id = "visible", Type = "Toggle", Name = "Только видимые", Default = false },
		},
		OnToggle = function(on) if threatPanel then threatPanel.Visible = on end end,
	}
	
	Feature{
		Id = "overlaymgr", Tab = "Settings", Group = "Оверлей", Col = 1, NoToggle = true,
		Name = "Overlay Manager", Desc = "Общие настройки плавающих HUD-панелей",
		Options = {
			{ Id = "lock", Type = "Toggle", Name = "Заблокировать перетаскивание HUD", Default = false },
			{ Id = "snap", Type = "Toggle", Name = "Привязка к сетке 8 px", Default = true },
		},
	}
	
	local function applyLayoutPresetNow(name)
		local vp = VP()
		if name == "Balanced" then
			UICFG.WmX,UICFG.WmY=16,16; UICFG.RadarX,UICFG.RadarY=math.max(vp.X-196,8),54
			UICFG.TargetX,UICFG.TargetY=math.max(vp.X-260,8),math.max(vp.Y-104,8); UICFG.PerfX,UICFG.PerfY=16,math.max(vp.Y-150,8)
			UICFG.ThreatX,UICFG.ThreatY=16,110; UICFG.QuickX,UICFG.QuickY=math.max(vp.X*.5-150,8),math.max(vp.Y-52,8)
		elseif name == "Left Stack" then
			UICFG.WmX,UICFG.WmY=16,16; UICFG.RadarX,UICFG.RadarY=16,60; UICFG.ThreatX,UICFG.ThreatY=16,248
			UICFG.PerfX,UICFG.PerfY=16,420; UICFG.TargetX,UICFG.TargetY=280,16; UICFG.QuickX,UICFG.QuickY=16,math.max(vp.Y-52,8)
		elseif name == "Right Stack" then
			UICFG.WmX,UICFG.WmY=math.max(vp.X-350,8),16; UICFG.RadarX,UICFG.RadarY=math.max(vp.X-196,8),60
			UICFG.ThreatX,UICFG.ThreatY=math.max(vp.X-280,8),248; UICFG.PerfX,UICFG.PerfY=math.max(vp.X-234,8),420
			UICFG.TargetX,UICFG.TargetY=16,16; UICFG.QuickX,UICFG.QuickY=math.max(vp.X-320,8),math.max(vp.Y-52,8)
		elseif name == "Center Bottom" then
			UICFG.WmX,UICFG.WmY=16,16; UICFG.RadarX,UICFG.RadarY=math.max(vp.X-196,8),54
			UICFG.TargetX,UICFG.TargetY=math.max(vp.X*.5-120,8),math.max(vp.Y-120,8); UICFG.PerfX,UICFG.PerfY=16,math.max(vp.Y-150,8)
			UICFG.ThreatX,UICFG.ThreatY=16,110; UICFG.QuickX,UICFG.QuickY=math.max(vp.X*.5-150,8),math.max(vp.Y-54,8)
		elseif name == "Minimal" then
			UICFG.WmX,UICFG.WmY=16,16; UICFG.QuickX,UICFG.QuickY=math.max(vp.X*.5-150,8),math.max(vp.Y-52,8)
		end
		UICFG.LayoutPreset=name
		if applyUI then applyUI() end
		markDirty()
	end
	
	Feature{
		Id = "quickbar", Tab = "Settings", Group = "Оверлей", Col = 1, On = true,
		Name = "Quick Access Bar", Desc = "Плавающая панель избранных модулей для быстрого переключения",
		Options = {
			{ Id = "count", Type = "Slider", Name = "Кнопок", Min = 3, Max = 8, Default = 6, Step = 1 },
			{ Id = "labels", Type = "Toggle", Name = "Показывать подписи", Default = true },
			{ Id = "onlyfav", Type = "Toggle", Name = "Только избранные", Default = true },
		},
		OnToggle = function(on) if quickBar then quickBar.Visible = on and not cleanHudActive() end end,
	}
	
	Feature{
		Id = "hudedit", Tab = "Settings", Group = "Оверлей", Col = 1, On = false,
		Name = "HUD Edit Mode", Desc = "Подсвечивает плавающие панели и помогает расставить их на экране",
		Options = {
			{ Id = "labels", Type = "Toggle", Name = "Показывать названия панелей", Default = true, OnChange=function() if ById.hudedit and ById.hudedit._active and applyHudEditVisuals then applyHudEditVisuals(true) end end },
			{ Id = "pulse", Type = "Toggle", Name = "Акцентная подсветка", Default = true, OnChange=function() if ById.hudedit and ById.hudedit._active and applyHudEditVisuals then applyHudEditVisuals(true) end end },
		},
		OnToggle = function(on) if applyHudEditVisuals then applyHudEditVisuals(on) end end,
	}
	
	Feature{
		Id = "cleanhud", Tab = "Settings", Group = "Приватность", Col = 1, On = false,
		Name = "Clean Capture", Desc = "Временно скрывает HUD-панели, не выключая сами модули",
		Options = {
			{ Id = "menu", Type = "Toggle", Name = "Сворачивать меню при включении", Default = false },
		},
		OnToggle = function(on)
			if on and O("cleanhud","menu") and hideMenu then hideMenu() end
			if quickBar then quickBar.Visible = (not on) and ById.quickbar and ById.quickbar._active end
		end,
	}
	
	Feature{
		Id = "notifications", Tab = "Settings", Group = "Интерфейс", Col = 2, NoToggle = true,
		Name = "Notifications", Desc = "Toast-уведомления и история событий интерфейса",
		Options = {
			{ Id = "toast", Type = "Toggle", Name = "Показывать toast", Default = true },
			{ Id = "duration", Type = "Slider", Name = "Время toast", Min = 1, Max = 8, Default = 3, Step = 1, Suffix = " сек" },
			{ Id = "history", Type = "Slider", Name = "История событий", Min = 10, Max = 100, Default = 50, Step = 5 },
			{ Id = "compact", Type = "Toggle", Name = "Компактные сообщения", Default = false },
		},
	}
	
	Feature{
		Id = "notifcenter", Tab = "Info", Group = "Сессия", Col = 2, NoToggle = true,
		Name = "Notification Center", Desc = "История сообщений hub за текущую сессию",
		Custom = "notifcenter",
	}
	
	Feature{
		Id = "sessiondash", Tab = "Info", Group = "Сводка", Col = 2, NoToggle = true,
		Name = "Session Dashboard", Desc = "FPS min/avg/max, респавны, игроки и состояние интерфейса",
		Custom = "sessiondash",
	}
	
	Feature{
		Id = "placeprofiles", Tab = "Settings", Group = "Конфигурация", Col = 1, NoToggle = true,
		Name = "Place Profiles", Desc = "Отдельные автоматические настройки для каждого PlaceId",
		Options = {
			{ Id = "autoload", Type = "Toggle", Name = "Автозагрузка профиля игры", Default = false },
			{ Id = "autosave", Type = "Toggle", Name = "Автосохранение профиля игры", Default = false },
			{ Id = "save", Type = "Button", Name = "Сохранить профиль этого PlaceId", Style = "accent", Run = function()
				Store.configs[placeProfileName()] = snapshotNow(); writeStore(); flushStore(); Notify("Профиль PlaceId сохранён", "ok")
			end },
			{ Id = "load", Type = "Button", Name = "Загрузить профиль этого PlaceId", Run = function()
				local p=Store.configs[placeProfileName()]; if p then applySnapshot(deepCopy(p)); Notify("Профиль PlaceId загружен", "ok") else Notify("Профиль PlaceId ещё не сохранён", "warn") end
			end },
			{ Id = "delete", Type = "Button", Name = "Удалить профиль этого PlaceId", Style = "danger", Run = function()
				Store.configs[placeProfileName()]=nil; writeStore(); Notify("Профиль PlaceId удалён", "warn")
			end },
		},
	}
	
	Feature{
		Id = "layoutpresets", Tab = "Settings", Group = "Оверлей", Col = 1, NoToggle = true,
		Name = "Layout Presets", Desc = "Быстрая расстановка всех HUD-панелей",
		Options = {
			{ Id = "preset", Type = "Dropdown", Name = "Схема", List = { "Balanced", "Left Stack", "Right Stack", "Center Bottom", "Minimal" }, Default = "Balanced",
			  OnChange = function(v) applyLayoutPresetNow(v); if Notify then Notify("HUD layout: "..v, "ok") end end },
		},
	}
	
	local function applyHudProfile(name)
		local function sw(id, on) if ById[id] then setOn(id, on) end end
		if name == "Full" then
			sw("streamer", false); sw("watermark", true); sw("bindlist", true); sw("radar", true); sw("targethud", true); sw("threats", true); sw("perfmon", false)
		elseif name == "Competitive" then
			sw("streamer", false); sw("watermark", true); sw("bindlist", true); sw("radar", false); sw("targethud", true); sw("threats", false); sw("perfmon", false)
		elseif name == "Streamer" then
			sw("streamer", true); sw("watermark", true); sw("bindlist", true); sw("radar", false); sw("targethud", true); sw("threats", false); sw("perfmon", false)
		elseif name == "Diagnostics" then
			sw("streamer", false); sw("watermark", true); sw("bindlist", true); sw("radar", true); sw("targethud", true); sw("threats", true); sw("perfmon", true); sw("quickbar", true)
			DB.watermark.o.bridge = true
		elseif name == "Minimal" then
			sw("watermark", true); sw("bindlist", false); sw("radar", false); sw("targethud", false); sw("threats", false); sw("perfmon", false)
			DB.watermark.o.user = false; DB.watermark.o.time = false; DB.watermark.o.session = false; DB.watermark.o.active = false
		elseif name == "Clean" then
			sw("watermark", false); sw("bindlist", false); sw("radar", false); sw("targethud", false); sw("threats", false); sw("perfmon", false)
		end
		markDirty()
		if Notify then Notify("HUD profile: " .. name, "ok") end
	end
	
	Feature{
		Id = "hudprofiles", Tab = "Settings", Group = "Интерфейс", Col = 2, NoToggle = true,
		Name = "HUD Profiles", Desc = "Быстрые наборы оверлеев для разных сценариев",
		Options = {
			{ Id = "profile", Type = "Dropdown", Name = "Профиль", List = { "Full", "Competitive", "Streamer", "Diagnostics", "Minimal", "Clean" }, Default = "Full",
			  OnChange = function(v) applyHudProfile(v) end },
		},
	}
	
	Feature{
		Id = "hotkeys", Tab = "Settings", Group = "Интерфейс", Col = 2, NoToggle = true,
		Name = "Hotkey Editor", Desc = "Все бинды модулей в одном месте",
		Custom = "hotkeys",
	}
	
	local afkConn
	Feature{
		Id = "antiafk", Tab = "Settings", Group = "Утилиты", Col = 2, On = false,
		Name = "Anti-AFK", Desc = "Не даёт серверу выкинуть за бездействие",
		Options = {
			{ Id = "notify", Type = "Toggle", Name = "Сообщать о срабатывании", Default = true },
		},
		OnToggle = function(on)
			if afkConn then afkConn:Disconnect() afkConn = nil end
			if not on then return end
			afkConn = LP.Idled:Connect(function()
				local ok = pcall(function()
					local vu = game:GetService("VirtualUser")
					vu:CaptureController()
					vu:ClickButton2(Vector2.new())
				end)
				if ok and O("antiafk", "notify") then
					Notify("anti-afk: активность отправлена", "ok")
				end
			end)
			table.insert(CONNS, afkConn)
		end,
	}
	
	Feature{
		Id = "runtimeguard", Tab = "Settings", Group = "Утилиты", Col = 2, NoToggle = true,
		Name = "Runtime Guard", Desc = "Self-check, quarantine recovery и аварийное восстановление клиентского состояния",
		Options = {
			{ Id = "selfcheck", Type = "Button", Name = "Запустить self-check", Run = function()
				local faults = 0
				for _ in pairs(RUNTIME_ERRORS) do faults += 1 end
				local caps = {
					"file=" .. (RUNTIME_CAPS.FileIO and "ok" or "fallback"),
					"hook=" .. (RUNTIME_CAPS.MetaHook and "available" or "fallback"),
					"clipboard=" .. (RUNTIME_CAPS.Clipboard and "ok" or "off"),
					"camera=" .. (workspace.CurrentCamera and "ok" or "missing"),
					"faults=" .. tostring(faults),
				}
				Notify("Self-check · " .. table.concat(caps, " · "), faults == 0 and "ok" or "warn")
			end },
			{ Id = "clearfaults", Type = "Button", Name = "Очистить quarantine/errors", Run = function()
				table.clear(RUNTIME_ERRORS)
				local n = 0
				for _, f in ipairs(Features) do
					if f._faulted then
						f._faulted, f._faultCount, f._lastError = false, 0, nil
						n += 1
						if f._row then pcall(f._row.refresh) end
					end
				end
				Notify("Runtime quarantine очищен · " .. tostring(n) .. " мод.", "ok")
			end },
			{ Id = "recover", Type = "Button", Name = "Emergency restore (без закрытия UI)", Style = "danger", Run = function()
				for _, f in ipairs(Features) do
					if not f.NoToggle and DB[f.Id] and DB[f.Id].on then setOn(f.Id, false) end
				end
				clearEsp()
				clearHitboxes()
				local h = getHum()
				if h then restoreHumanoid(h) end
				workspace.Gravity = WORLD_BASE.Gravity
				if Camera then Camera.FieldOfView = fovOriginal or START_CAMERA_FOV end
				Notify("Клиентское состояние восстановлено, UI оставлен открытым", "warn")
			end },
		},
	}
	
	local watermark, wmText, bindList, blTitle
	local unloadHub, hideMenu
	
	Feature{
		Id = "watermark", Tab = "Settings", Group = "Оверлей", Col = 1, On = true,
		Name = "Watermark", Desc = "Информационная плашка на экране",
		Options = {
			{ Id = "fps",  Type = "Toggle", Name = "FPS", Default = true },
			{ Id = "ping", Type = "Toggle", Name = "Пинг", Default = true },
			{ Id = "user", Type = "Toggle", Name = "Ник игрока", Default = true },
			{ Id = "time", Type = "Toggle", Name = "Время", Default = true },
			{ Id = "session", Type = "Toggle", Name = "Время сессии", Default = true },
			{ Id = "players", Type = "Toggle", Name = "Игроки онлайн", Default = false },
			{ Id = "active", Type = "Toggle", Name = "Активные модули", Default = true },
			{ Id = "bridge", Type = "Toggle", Name = "Weapon Bridge status", Default = false },
			{ Id = "profile", Type = "Toggle", Name = "Place Profile status", Default = false },
			{ Id = "place", Type = "Toggle", Name = "Place ID", Default = false },
			{ Id = "pos",  Type = "Dropdown", Name = "Быстрая позиция",
			  List = { "Сверху слева", "Сверху справа", "Снизу слева" }, Default = "Сверху слева",
			  OnChange = function(v)
				local vp = workspace.CurrentCamera.ViewportSize
				if v == "Сверху справа" then UICFG.WmX, UICFG.WmY = math.floor(vp.X - 340), 16
				elseif v == "Снизу слева" then UICFG.WmX, UICFG.WmY = 16, math.floor(vp.Y - 60)
				else UICFG.WmX, UICFG.WmY = 16, 16 end
				if applyUI then applyUI() end
			  end },
		},
		OnToggle = function(on) if watermark then watermark.Visible = on end end,
	}
	
	Feature{
		Id = "bindlist", Tab = "Settings", Group = "Оверлей", Col = 1, On = true,
		Name = "Keybind List", Desc = "Список назначенных биндов на экране",
		Options = {
			{ Id = "only", Type = "Toggle", Name = "Только активные", Default = false },
			{ Id = "mode", Type = "Toggle", Name = "Показывать режим", Default = true },
		},
		OnToggle = function(on) if bindList then bindList.Visible = on end end,
	}
	
	Feature{
		Id = "gamemode", Tab = "Info", Group = "Совместимость", Col = 1, NoToggle = true,
		Name = "Game Mode Override", Desc = "Для своего режима: Auto определяет команды сам, Teams использует Roblox Team, FFA считает всех остальных противниками",
		Options = {
			{ Id = "mode", Type = "Dropdown", Name = "Режим игроков", List = { "Auto", "Teams", "FFA" }, Default = "Auto" },
			{ Id = "hint", Type = "Label", Name = "FFA полезен, если игра держит всех в одной Team, но союзников фактически нет" },
		},
	}

	Feature{
		Id = "info", Tab = "Info", Group = "Сводка", Col = 1, NoToggle = true,
		Name = "Сервер и клиент", Desc = "Живые данные о сессии",
		Custom = "info",
	}
	
	Feature{
		Id = "weaponlab", Tab = "Info", Group = "Диагностика", Col = 1, NoToggle = true,
		Name = "Weapon Diagnostics", Desc = "Показывает, что Universal Weapon Bridge распознал в текущей игре",
		Custom = "weaponlab",
	}
	
	Feature{
		Id = "compatdiag", Tab = "Info", Group = "Диагностика", Col = 2, NoToggle = true,
		Name = "Compatibility Diagnostics", Desc = "Показывает spawn guard и какой активный модуль последним менял Humanoid / Camera",
		Custom = "compatdiag",
	}

	Feature{
		Id = "session", Tab = "Info", Group = "Сессия", Col = 2, NoToggle = true,
		Name = "Действия", Desc = "Перезаход и смена сервера",
		Options = {
			{ Id = "b1", Type = "Button", Name = "Перезайти на этот сервер", Style = "accent", Run = function()
				Notify("перезаход...", "warn")
				task.wait(0.4)
				local ok = pcall(function()
					TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)
				end)
				if not ok then
					pcall(function() TeleportService:Teleport(game.PlaceId, LP) end)
				end
			end },
			{ Id = "b2", Type = "Button", Name = "Server Hop (новый сервер)", Run = function()
				Notify("поиск другого сервера...", "warn")
				task.wait(0.4)
				pcall(function() TeleportService:Teleport(game.PlaceId, LP) end)
			end },
		},
	}
	
	Feature{
		Id = "iface", Tab = "Settings", Group = "Интерфейс", Col = 2, NoToggle = true,
		Name = "Интерфейс", Desc = "Клавиша меню, масштаб, эффекты",
		Options = {
			{ Id = "menukey", Type = "MenuKey", Name = "Клавиша открытия меню" },
			{ Id = "scale", Type = "Slider", Name = "Масштаб", Min = 70, Max = 130, Default = 100, Suffix = "%",
			  OnChange = function(v) UICFG.Scale = v / 100 if setScaleLive then setScaleLive() end end },
			{ Id = "trans", Type = "Slider", Name = "Прозрачность окна", Min = 0, Max = 45, Default = 0, Suffix = "%",
			  OnChange = function(v) UICFG.Trans = v / 100 if setTransLive then setTransLive() end end },
			{ Id = "blur", Type = "Toggle", Name = "Размытие фона", Default = true,
			  OnChange = function(v) UICFG.Blur = v if applyUI then applyUI() end end },
			{ Id = "anim", Type = "Toggle", Name = "Анимации", Default = true,
			  OnChange = function(v) UICFG.Animations = v ANIM = v end },
			{ Id = "expand", Type = "Toggle", Name = "Раскрывать настройки при включении", Default = true,
			  OnChange = function(v) UICFG.AutoExpand = v end },
			{ Id = "mouse", Type = "Toggle", Name = "Освобождать курсор в меню", Default = true,
			  OnChange = function(v) UICFG.FreeMouse = v end },
			{ Id = "esc", Type = "Toggle", Name = "ESC переключает hub (кроме меню Roblox)", Default = true,
			  OnChange = function(v) UICFG.EscHide = v end },
			{ Id = "adv", Type = "Toggle", Name = "Показывать расширенные настройки", Default = true,
			  OnChange = function(v)
				UICFG.Advanced = v
				if resetPanels then task.defer(resetPanels) end
			  end },
		},
	}
	
	local PRESETS = {
		Violet     = { "#7C5CFF", "#40CCFF" },
		Cyan       = { "#22D3EE", "#6366F1" },
		Crimson    = { "#FF3B5C", "#FF8A3D" },
		Emerald    = { "#22C55E", "#A3E635" },
		Amber      = { "#F59E0B", "#FF5CA8" },
		Monochrome = { "#E5E7EB", "#8B90A6" },
		Midnight   = { "#6D7CFF", "#9D72FF" },
		Rose       = { "#FF5F8F", "#B967FF" },
		Arctic     = { "#7DE3FF", "#8EA1FF" },
		Lime       = { "#9CF26B", "#39D98A" },
		Gold       = { "#FFC857", "#FF8F3D" },
		Slate      = { "#B8C1D9", "#667085" },
	}
	
	Feature{
		Id = "theme", Tab = "Settings", Group = "Интерфейс", Col = 2, NoToggle = true,
		Name = "Тема", Desc = "Акцентные цвета",
		Options = {
			{ Id = "preset", Type = "Dropdown", Name = "Пресет",
			  List = { "Violet", "Cyan", "Crimson", "Emerald", "Amber", "Monochrome", "Midnight", "Rose", "Arctic", "Lime", "Gold", "Slate" }, Default = "Violet" },
			{ Id = "c1", Type = "Color", Name = "Акцент 1", Default = "#7C5CFF" },
			{ Id = "c2", Type = "Color", Name = "Акцент 2", Default = "#40CCFF" },
		},
	}
	
	Feature{
		Id = "configs", Tab = "Settings", Group = "Конфигурация", Col = 1, NoToggle = true,
		Name = "Конфиги", Desc = "Именованные пресеты настроек",
		Custom = "configs",
	}
	
	Feature{
		Id = "control", Tab = "Settings", Group = "Конфигурация", Col = 1, NoToggle = true,
		Name = "Управление", Desc = "Сброс и выгрузка",
		Options = {
			{ Id = "auto", Type = "Toggle", Name = "Автосохранение", Default = true,
			  OnChange = function(v) UICFG.AutoSave = v end },
			{ Id = "b1", Type = "Button", Name = "Сбросить бинды", Run = function() resetBinds() end },
			{ Id = "b2", Type = "Button", Name = "Сбросить все настройки", Style = "danger", Run = function() resetAll() end },
			{ Id = "bpos", Type = "Button", Name = "Сбросить позиции HUD", Run = function()
				local vp=VP(); UICFG.WmX,UICFG.WmY=16,16; UICFG.FloatX,UICFG.FloatY=math.max(vp.X-72,8),math.max(vp.Y*.5-47,8)
				UICFG.RadarX,UICFG.RadarY=math.max(vp.X-196,8),54; UICFG.TargetX,UICFG.TargetY=math.max(vp.X-260,8),math.max(vp.Y-104,8); UICFG.PerfX,UICFG.PerfY=16,math.max(vp.Y-150,8); UICFG.ThreatX,UICFG.ThreatY=16,110; UICFG.QuickX,UICFG.QuickY=math.max(vp.X*.5-155,8),math.max(vp.Y-52,8)
				applyUI(); markDirty(); Notify("Позиции HUD сброшены", "ok")
			end },
			{ Id = "bstream", Type = "Button", Name = "Переключить Streamer Mode", Style = "accent", Run = function()
				setOn("streamer", not DB.streamer.on); Notify("Streamer Mode " .. (DB.streamer.on and "включён" or "выключен"), DB.streamer.on and "ok" or "warn")
			end },
			{ Id = "panic", Type = "Button", Name = "PANIC — выключить модули", Style = "danger", Run = function()
				for _,ff in ipairs(Features) do if not ff.NoToggle and ff.Id ~= "streamer" and DB[ff.Id].on then setOn(ff.Id,false) end end
				Notify("PANIC: активные модули отключены", "warn"); if hideMenu then hideMenu() end
			end },
			{ Id = "b3", Type = "Button", Name = "Свернуть меню", Run = function() if hideMenu then hideMenu() end end },
			{ Id = "b4", Type = "Button", Name = "Закрыть hub полностью", Style = "danger",
			  Run = function() if unloadHub then unloadHub() end end },
		},
	}
	

	-- UI/runtime lives in a second function scope so its locals do not accumulate
	-- with the feature-registration locals above.
	local function __anaclysm_ui_runtime()
		--==============================================================================
		--                           И Н Т Е Р Ф Е Й С
		--==============================================================================
		Loader.set(58, "построение интерфейса")
		task.wait(0.2)
		
		local PlayerGui = LP:WaitForChild("PlayerGui")
		local UI = {}
		
		local GUI = New("ScreenGui", {
			Name = "anaclysm_hub", ResetOnSpawn = false, IgnoreGuiInset = true,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 2147483647, Parent = PlayerGui,
		})
		
		ESP_FOLDER = New("Folder", { Name = "esp", Parent = GUI })
		
		
		-- GuiButton.Modal — единственный механизм, который перебивает LockCenter
		-- даже если игра переустанавливает его каждый кадр
		UI.modal = New("TextButton", {
			Name = "modalcursor", Text = "", AutoButtonColor = false, Modal = false,
			BackgroundTransparency = 1, TextTransparency = 1, Size = UDim2.fromOffset(1, 1),
			Position = UDim2.fromOffset(0, 0), ZIndex = 1, Visible = true, Active = false, Parent = GUI,
		})
		local blur = New("BlurEffect", { Name = "_an_blur", Size = 0, Parent = Lighting })
		
		-- FOV круг -------------------------------------------------------------
		aimCircle = New("Frame", {
			Name = "fov", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(300, 300), BackgroundTransparency = 1, Visible = false, ZIndex = 2, Parent = GUI,
		})
		round1(aimCircle)
		UI.fovStroke = New("UIStroke", { Thickness = 1.4, Color = Theme.Accent, Transparency = 0.25, Parent = aimCircle })
		
		aimLine = New("Frame", {
			Name = "aimline", AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0,
			BackgroundColor3 = Theme.Accent, Size = UDim2.fromOffset(0, 1), Visible = false, ZIndex = 2, Parent = GUI,
		})
		accent(aimLine, "BackgroundColor3")
		
		-- прицел ---------------------------------------------------------------
		for i = 1, 5 do
			local f = New("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(2, 8), BorderSizePixel = 0, Visible = false,
				BackgroundColor3 = Theme.Accent2, ZIndex = 6, Parent = GUI,
			})
			New("UIStroke", { Thickness = 1, Color = Color3.new(0, 0, 0), Transparency = 0.35, Parent = f })
			if i == 5 then round1(f) end
			crossParts[i] = f
		end
		
		-- watermark ------------------------------------------------------------
		watermark = New("Frame", {
			Name = "watermark", Position = UDim2.new(0, 16, 0, 16), Size = UDim2.fromOffset(10, 30),
			AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Theme.Bg2, BorderSizePixel = 0, Parent = GUI,
		})
		corner(watermark, 9)
		stroke(watermark, Theme.Stroke, 1)
		padding(watermark, 0, 0, 14, 14)
		do
			local a = New("Frame", {
				Size = UDim2.new(0, 3, 0, 15), Position = UDim2.new(0, -9, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
				BorderSizePixel = 0, Parent = watermark,
			})
			corner(a, 2)
			accent(a, "BackgroundColor3")
		end
		wmText = New("TextLabel", {
			BackgroundTransparency = 1, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
			Font = FSB, TextSize = 12, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
			Text = "anaclysm hub", Parent = watermark,
		})
		UI.wmBtn = New("TextButton", {
			Name = "wmdrag", BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
			Size = UDim2.new(1, 28, 1, 0), Position = UDim2.fromOffset(-14, 0), ZIndex = 4, Parent = watermark,
		})
		
		
		-- floating dock удалён: меню возвращается через watermark / MenuKey.

		-- radar ---------------------------------------------------------------
		radarPanel = New("Frame", {
			Name = "radar", Size = UDim2.fromOffset(176, 176), BackgroundColor3 = Theme.Bg2,
			BackgroundTransparency = 0.08, BorderSizePixel = 0, Visible = false, ZIndex = 10, Parent = GUI,
		})
		corner(radarPanel, 14)
		UI.radarStroke = stroke(radarPanel, Theme.Stroke, 1)
		UI.radarTitle = New("TextLabel", {
			Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 14), BackgroundTransparency = 1,
			Font = FB, TextSize = 10, TextColor3 = Theme.Sub, TextXAlignment = Enum.TextXAlignment.Left,
			Text = "RADAR", ZIndex = 12, Parent = radarPanel,
		})
		UI.radarRange = New("TextLabel", {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8), Size = UDim2.fromOffset(70, 14),
			BackgroundTransparency = 1, Font = FSB, TextSize = 9, TextColor3 = Theme.Dim,
			TextXAlignment = Enum.TextXAlignment.Right, Text = "350 st", ZIndex = 12, Parent = radarPanel,
		})
		UI.radarArea = New("Frame", {
			Position = UDim2.fromOffset(8, 28), Size = UDim2.new(1, -16, 1, -36), BackgroundColor3 = Theme.Deep,
			BackgroundTransparency = 0.35, BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 11, Parent = radarPanel,
		})
		corner(UI.radarArea, 10)
		stroke(UI.radarArea, Theme.Stroke, 1, 0.35)
		UI.radarH = New("Frame", { AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromScale(0.5,0.5), Size=UDim2.new(1,-16,0,1), BackgroundColor3=Theme.Stroke, BackgroundTransparency=0.3, BorderSizePixel=0, ZIndex=11, Parent=UI.radarArea })
		UI.radarV = New("Frame", { AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromScale(0.5,0.5), Size=UDim2.new(0,1,1,-16), BackgroundColor3=Theme.Stroke, BackgroundTransparency=0.3, BorderSizePixel=0, ZIndex=11, Parent=UI.radarArea })
		UI.radarSelf = New("Frame", { AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromScale(0.5,0.5), Size=UDim2.fromOffset(7,7), BackgroundColor3=Theme.Accent2, BorderSizePixel=0, ZIndex=14, Parent=UI.radarArea })
		round1(UI.radarSelf)
		UI.radarDrag = New("TextButton", { BackgroundTransparency=1, Text="", AutoButtonColor=false, Size=UDim2.new(1,0,0,26), ZIndex=20, Parent=radarPanel })
		
		-- target HUD ----------------------------------------------------------
		targetHud = New("Frame", {
			Name = "target_hud", Size = UDim2.fromOffset(240, 76), BackgroundColor3 = Theme.Bg2,
			BackgroundTransparency = 0.06, BorderSizePixel = 0, Visible = false, ZIndex = 10, Parent = GUI,
		})
		corner(targetHud, 12)
		UI.targetStroke = stroke(targetHud, Theme.Stroke, 1)
		UI.targetAvatar = New("ImageLabel", {
			Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = Theme.Deep,
			BorderSizePixel = 0, Image = "", ZIndex = 12, Parent = targetHud,
		})
		corner(UI.targetAvatar, 9)
		UI.targetName = New("TextLabel", {
			Position=UDim2.fromOffset(60,8), Size=UDim2.new(1,-70,0,16), BackgroundTransparency=1, Font=FB, TextSize=12,
			TextColor3=Theme.Text, TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd, Text="target", ZIndex=12, Parent=targetHud,
		})
		UI.targetInfo = New("TextLabel", {
			Position=UDim2.fromOffset(60,27), Size=UDim2.new(1,-70,0,14), BackgroundTransparency=1, Font=FM, TextSize=10,
			TextColor3=Theme.Sub, TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd, Text="", ZIndex=12, Parent=targetHud,
		})
		UI.targetHpBg = New("Frame", { Position=UDim2.new(0,60,1,-22), Size=UDim2.new(1,-70,0,7), BackgroundColor3=Theme.Deep, BorderSizePixel=0, ZIndex=12, Parent=targetHud })
		round1(UI.targetHpBg)
		UI.targetHp = New("Frame", { Size=UDim2.fromScale(1,1), BackgroundColor3=Theme.Good, BorderSizePixel=0, ZIndex=13, Parent=UI.targetHpBg })
		round1(UI.targetHp)
		UI.targetDrag = New("TextButton", { BackgroundTransparency=1, Text="", AutoButtonColor=false, Size=UDim2.new(1,0,0,28), ZIndex=20, Parent=targetHud })
		
		-- performance monitor -------------------------------------------------
		perfPanel = New("Frame", {
			Name = "performance_monitor", Size = UDim2.fromOffset(218, 108), BackgroundColor3 = Theme.Bg2,
			BackgroundTransparency = 0.06, BorderSizePixel = 0, Visible = false, ZIndex = 10, Parent = GUI,
		})
		corner(perfPanel, 12)
		UI.perfStroke = stroke(perfPanel, Theme.Stroke, 1)
		New("TextLabel", { Position=UDim2.fromOffset(12,8), Size=UDim2.new(1,-24,0,14), BackgroundTransparency=1,
			Font=FB, TextSize=10, TextColor3=Theme.Sub, TextXAlignment=Enum.TextXAlignment.Left, Text="PERFORMANCE", ZIndex=12, Parent=perfPanel })
		perfText = New("TextLabel", { Position=UDim2.fromOffset(12,28), Size=UDim2.new(1,-24,1,-38), BackgroundTransparency=1,
			Font=FM, TextSize=10, TextColor3=Theme.Text, TextXAlignment=Enum.TextXAlignment.Left, TextYAlignment=Enum.TextYAlignment.Top,
			TextWrapped=false, Text="", ZIndex=12, Parent=perfPanel })
		UI.perfDrag = New("TextButton", { BackgroundTransparency=1, Text="", AutoButtonColor=false, Size=UDim2.new(1,0,0,26), ZIndex=20, Parent=perfPanel })
		
		-- threat list ---------------------------------------------------------
		threatPanel = New("Frame", {
			Name="threats", Position=UDim2.fromOffset(16,110), Size=UDim2.fromOffset(264,154),
			BackgroundColor3=Theme.Bg2, BackgroundTransparency=.04, BorderSizePixel=0, Visible=false, ZIndex=11, Parent=GUI,
		})
		corner(threatPanel,12); UI.threatStroke=stroke(threatPanel,Theme.Stroke,1)
		New("TextLabel", { Position=UDim2.fromOffset(12,7), Size=UDim2.new(1,-24,0,18), BackgroundTransparency=1,
			Font=FB, TextSize=10, TextColor3=Theme.Sub, TextXAlignment=Enum.TextXAlignment.Left, Text="THREAT LIST", ZIndex=12, Parent=threatPanel })
		UI.threatHolder = New("Frame", { Position=UDim2.fromOffset(10,29), Size=UDim2.new(1,-20,1,-38), BackgroundTransparency=1, ZIndex=12, Parent=threatPanel })
		list(UI.threatHolder,3)
		for i=1,8 do
			local row=New("Frame", { Size=UDim2.new(1,0,0,22), BackgroundColor3=Theme.Row, BackgroundTransparency=.48, BorderSizePixel=0, Visible=false, LayoutOrder=i, ZIndex=12, Parent=UI.threatHolder }); corner(row,6)
			local dot=New("Frame", { AnchorPoint=Vector2.new(0,.5), Position=UDim2.new(0,7,.5,0), Size=UDim2.fromOffset(5,5), BackgroundColor3=Theme.Bad, BorderSizePixel=0, ZIndex=13, Parent=row }); round1(dot)
			local name=New("TextLabel", { Position=UDim2.fromOffset(18,0), Size=UDim2.new(.48,-18,1,0), BackgroundTransparency=1, Font=FSB, TextSize=9, TextColor3=Theme.Text, TextXAlignment=Enum.TextXAlignment.Left, Text="", ZIndex=13, Parent=row })
			local info=New("TextLabel", { Position=UDim2.new(.48,0,0,0), Size=UDim2.new(.52,-7,1,0), BackgroundTransparency=1, Font=FM, TextSize=9, TextColor3=Theme.Sub, TextXAlignment=Enum.TextXAlignment.Right, Text="", ZIndex=13, Parent=row })
			threatRows[i]={row=row,dot=dot,name=name,info=info}
		end
		UI.threatDrag = New("TextButton", { BackgroundTransparency=1, Text="", AutoButtonColor=false, Size=UDim2.new(1,0,0,27), ZIndex=20, Parent=threatPanel })
		
		-- quick access bar ----------------------------------------------------
		quickBar = New("Frame", { Name="quick_access", Size=UDim2.fromOffset(310,40), BackgroundColor3=Theme.Bg2, BackgroundTransparency=.05, BorderSizePixel=0, Visible=false, ZIndex=16, Parent=GUI })
		corner(quickBar,11); UI.quickStroke=stroke(quickBar,Theme.Stroke,1)
		quickTitle = New("TextLabel", { Position=UDim2.fromOffset(10,0), Size=UDim2.fromOffset(42,40), BackgroundTransparency=1, Font=FB, TextSize=9, TextColor3=Theme.Dim, Text="QUICK", ZIndex=17, Parent=quickBar })
		UI.quickHolder = New("Frame", { Position=UDim2.fromOffset(50,5), Size=UDim2.new(1,-58,1,-10), BackgroundTransparency=1, ZIndex=17, Parent=quickBar })
		New("UIListLayout", { FillDirection=Enum.FillDirection.Horizontal, Padding=UDim.new(0,4), SortOrder=Enum.SortOrder.LayoutOrder, VerticalAlignment=Enum.VerticalAlignment.Center, Parent=UI.quickHolder })
		for i=1,8 do
			local b=New("TextButton", { Size=UDim2.fromOffset(30,30), BackgroundColor3=Theme.Deep, BorderSizePixel=0, AutoButtonColor=false, Font=FSB, TextSize=9, TextColor3=Theme.Sub, Text="—", Visible=false, LayoutOrder=i, ZIndex=18, Parent=UI.quickHolder })
			corner(b,8); local st=stroke(b,Theme.Stroke,1); quickButtons[i]={b=b,st=st,f=nil}
			b.MouseButton1Click:Connect(function() local q=quickButtons[i]; if q and q.f then setOn(q.f.Id,not DB[q.f.Id].on) end end)
		end
		UI.quickDrag = New("TextButton", { BackgroundTransparency=1,Text="",AutoButtonColor=false,Size=UDim2.fromOffset(50,40),ZIndex=21,Parent=quickBar })
		
		-- список биндов --------------------------------------------------------
		bindList = New("Frame", {
			Name = "binds", Position = UDim2.new(0, 16, 0, 60), Size = UDim2.fromOffset(196, 0),
			AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Theme.Bg2, BorderSizePixel = 0, Parent = GUI,
		})
		corner(bindList, 9)
		stroke(bindList, Theme.Stroke, 1)
		padding(bindList, 9, 9, 12, 12)
		list(bindList, 3)
		blTitle = New("TextLabel", {
			Size = UDim2.new(1, 0, 0, 13), BackgroundTransparency = 1, Font = FB, TextSize = 10,
			TextColor3 = Theme.Dim, TextXAlignment = Enum.TextXAlignment.Left, Text = "БИНДЫ",
			LayoutOrder = -1, Parent = bindList,
		})
		
		-- уведомления ----------------------------------------------------------
		local notifHolder = New("Frame", {
			Name = "notifs", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -18),
			Size = UDim2.fromOffset(268, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = GUI,
		})
		New("UIListLayout", {
			Padding = UDim.new(0, 7), VerticalAlignment = Enum.VerticalAlignment.Bottom,
			HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder, Parent = notifHolder,
		})
		
		function Notify(text, kind)
			local cap = (DB.notifications and O("notifications", "history")) or 50
			table.insert(NOTIF_HISTORY, 1, { t = os.date("%H:%M:%S"), text = tostring(text), kind = kind or "info" })
			while #NOTIF_HISTORY > cap do table.remove(NOTIF_HISTORY) end
			if DB.notifications and not O("notifications", "toast") then return end
			local col = Theme.Accent
			if kind == "ok" then col = Theme.Good
			elseif kind == "warn" then col = Theme.Warn
			elseif kind == "bad" then col = Theme.Bad end
		
			local compactToast = DB.notifications and O("notifications", "compact")
			local toastH = compactToast and 32 or 40
			local f = New("Frame", {
				Size = UDim2.new(1, 0, 0, toastH), BackgroundColor3 = Theme.Card, BorderSizePixel = 0,
				BackgroundTransparency = 1, Parent = notifHolder,
			})
			corner(f, 10)
			local st = stroke(f, Theme.Stroke, 1, 1)
			local bar = New("Frame", {
				Size = UDim2.new(0, 3, 1, -16), Position = UDim2.new(0, 9, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = col, BorderSizePixel = 0, BackgroundTransparency = 1, Parent = f,
			})
			corner(bar, 2)
			local lbl = New("TextLabel", {
				BackgroundTransparency = 1, Position = UDim2.new(0, 22, 0, 0), Size = UDim2.new(1, -32, 1, 0),
				Font = FM, TextSize = compactToast and 10 or 12, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true, Text = text, TextTransparency = 1, Parent = f,
			})
			f.Position = UDim2.new(0, 40, 0, 0)
			tw(f, 0.35, { BackgroundTransparency = 0.02, Position = UDim2.new(0, 0, 0, 0) })
			tw(st, 0.35, { Transparency = 0 })
			tw(bar, 0.35, { BackgroundTransparency = 0 })
			tw(lbl, 0.35, { TextTransparency = 0 })
			local toastDuration = (DB.notifications and O("notifications", "duration")) or 3
			task.delay(toastDuration, function()
				tw(f, 0.35, { BackgroundTransparency = 1, Position = UDim2.new(0, 40, 0, 0) })
				tw(st, 0.3, { Transparency = 1 })
				tw(bar, 0.3, { BackgroundTransparency = 1 })
				tw(lbl, 0.3, { TextTransparency = 1 })
				task.delay(0.45, function() if f then f:Destroy() end end)
			end)
		end
		
		-- поверх системного размытия Roblox (если свойство поддерживается клиентом)
		pcall(function() GUI.OnTopOfCoreBlur = true end)
		
		--============================================================== ОКНО =========
		local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		local MINW, MINH = 660, 440
		if IS_MOBILE then MINW, MINH = 340, 260 end
		
		UI.win = New("CanvasGroup", {
			Name = "window", Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(UICFG.W, UICFG.H),
			BackgroundColor3 = Theme.Bg, BorderSizePixel = 0, Visible = false, ClipsDescendants = false,
			GroupTransparency = 0, Parent = GUI,
		})
		UI.scale = New("UIScale", { Scale = 1, Parent = UI.win })
		corner(UI.win, 16)
		UI.winStroke = stroke(UI.win, Theme.Stroke, 1.4)
		
		-- внешнее свечение
		for i = 1, 3 do
			local g = New("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, i * 12, 1, i * 12), BackgroundColor3 = Theme.Accent,
				BackgroundTransparency = 0.95 + i * 0.015, BorderSizePixel = 0, ZIndex = 0, Parent = UI.win,
			})
			corner(g, 16 + i * 5)
			accent(g, "BackgroundColor3")
		end
		
		--------------------------------------------------------------- ТОП-БАР ------
		UI.top = New("Frame", {
			Name = "topbar", Size = UDim2.new(1, 0, 0, 50), BackgroundColor3 = Theme.Bg2,
			BorderSizePixel = 0, ZIndex = 2, Parent = UI.win,
		})
		corner(UI.top, 16)
		New("Frame", {
			Position = UDim2.new(0, 0, 1, -16), Size = UDim2.new(1, 0, 0, 16),
			BackgroundColor3 = Theme.Bg2, BorderSizePixel = 0, ZIndex = 2, Parent = UI.top,
		})
		New("Frame", {
			Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Theme.Stroke, BorderSizePixel = 0, ZIndex = 3, Parent = UI.top,
		})
		UI.topLine = New("Frame", {
			Size = UDim2.new(1, -44, 0, 2), Position = UDim2.new(0.5, 0, 0, 0), AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 4, Parent = UI.top,
		})
		corner(UI.topLine, 2)
		UI.topGrad = accent(New("UIGradient", { Parent = UI.topLine }), "Color")
		
		do
			local mark = New("Frame", {
				Position = UDim2.new(0, 18, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(24, 24),
				BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 3, Parent = UI.top,
			})
			corner(mark, 8)
			accent(New("UIGradient", { Rotation = 40, Parent = mark }), "Color")
			New("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(8, 8),
				BackgroundColor3 = Theme.Bg2, BorderSizePixel = 0, Rotation = 45, ZIndex = 4, Parent = mark,
			})
			New("TextLabel", {
				Position = UDim2.new(0, 52, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(150, 16),
				BackgroundTransparency = 1, Font = FB, TextSize = 15, TextColor3 = Theme.Text,
				TextXAlignment = Enum.TextXAlignment.Left, Text = "anaclysm hub", ZIndex = 3, Parent = UI.top,
			})
			local chip = New("Frame", {
				Position = UDim2.new(0, 168, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(38, 17),
				BackgroundColor3 = Theme.Row, BorderSizePixel = 0, ZIndex = 3, Parent = UI.top,
			})
			corner(chip, 5)
			stroke(chip, Theme.Stroke, 1)
			New("TextLabel", {
				BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = FSB, TextSize = 10,
				TextColor3 = Theme.Sub, Text = "v5.2.3", ZIndex = 4, Parent = chip,
			})
		end
		
		UI.dragZone = New("TextButton", {
			Name = "drag", BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
			Position = UDim2.new(0, 0, 0, 0), Size = UDim2.new(1, -300, 1, 0), ZIndex = 2, Parent = UI.top,
		})
		
		local function topButton(x, glyph, danger)
			local b = New("Frame", {
				AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, x, 0.5, 0), Size = UDim2.fromOffset(28, 28),
				BackgroundColor3 = Theme.Row, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 3, Parent = UI.top,
			})
			corner(b, 8)
			local st = stroke(b, Theme.Stroke, 1)
			local l = New("TextLabel", {
				BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = FB, TextSize = 13,
				TextColor3 = danger and Theme.Bad or Theme.Sub, Text = glyph, ZIndex = 4, Parent = b,
			})
			local btn = New("TextButton", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = "", ZIndex = 5, Parent = b })
			btn.MouseEnter:Connect(function()
				tw(b, 0.15, { BackgroundTransparency = 0 })
				tw(l, 0.15, { TextColor3 = danger and Theme.Bad or Theme.Text })
				tw(st, 0.15, { Color = danger and Theme.Bad or Theme.Accent, Transparency = 0.3 })
			end)
			btn.MouseLeave:Connect(function()
				tw(b, 0.2, { BackgroundTransparency = 0.35 })
				tw(l, 0.2, { TextColor3 = danger and Theme.Bad or Theme.Sub })
				tw(st, 0.2, { Color = Theme.Stroke, Transparency = 0 })
			end)
			return btn
		end
		
		UI.btnClose = topButton(-16, "X", true)
		UI.btnHide  = topButton(-52, "—", false)
		
		-- карточка игрока в топ-баре
		do
			local card = New("Frame", {
				AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -92, 0.5, 0), Size = UDim2.fromOffset(178, 32),
				BackgroundColor3 = Theme.Row, BackgroundTransparency = 0.4, BorderSizePixel = 0, ZIndex = 3, Parent = UI.top,
			})
			corner(card, 9)
			stroke(card, Theme.Stroke, 1)
			local av = New("ImageLabel", {
				Position = UDim2.new(0, 4, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(24, 24),
				BackgroundColor3 = Theme.Deep, BorderSizePixel = 0, Image = "", ZIndex = 4, Parent = card,
			})
			round1(av)
			local ring = New("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 4, 1, 4),
				BackgroundTransparency = 1, ZIndex = 4, Parent = av,
			})
			round1(ring)
			accent(New("UIStroke", { Thickness = 1.4, Transparency = 0.2, Parent = ring }), "Color")
			UI.userDisplay = New("TextLabel", {
				Position = UDim2.new(0, 34, 0, 4), Size = UDim2.new(1, -40, 0, 12), BackgroundTransparency = 1,
				Font = FSB, TextSize = 12, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd, Text = LP.DisplayName, ZIndex = 4, Parent = card,
			})
			UI.userName = New("TextLabel", {
				Position = UDim2.new(0, 34, 0, 17), Size = UDim2.new(1, -40, 0, 11), BackgroundTransparency = 1,
				Font = FM, TextSize = 10, TextColor3 = Theme.Sub, TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd, Text = "@" .. LP.Name, ZIndex = 4, Parent = card,
			})
			UI.userAvatar = av
			UI.userCard = card
			task.spawn(function()
				local ok, img = pcall(function()
					return Players:GetUserThumbnailAsync(LP.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
				end)
				if ok and img then
					av.Image = img
					av.ImageTransparency = 1
					tw(av, 0.4, { ImageTransparency = 0 })
				end
			end)
		end
		
		--------------------------------------------------------------- САЙДБАР ------
		local SIDE = 186
		UI.side = New("Frame", {
			Name = "sidebar", Position = UDim2.new(0, 0, 0, 50), Size = UDim2.new(0, SIDE, 1, -50),
			BackgroundColor3 = Theme.Bg2, BorderSizePixel = 0, Parent = UI.win,
		})
		corner(UI.side, 16)
		New("Frame", {
			Size = UDim2.new(1, 0, 0, 16), BackgroundColor3 = Theme.Bg2, BorderSizePixel = 0, Parent = UI.side,
		})
		New("Frame", {
			Position = UDim2.new(1, -16, 0, 0), Size = UDim2.new(0, 16, 1, 0),
			BackgroundColor3 = Theme.Bg2, BorderSizePixel = 0, Parent = UI.side,
		})
		New("Frame", {
			Position = UDim2.new(1, -1, 0, 0), Size = UDim2.new(0, 1, 1, 0),
			BackgroundColor3 = Theme.Stroke, BorderSizePixel = 0, Parent = UI.side,
		})
		
		UI.tabHolder = New("Frame", {
			Position = UDim2.new(0, 0, 0, 14), Size = UDim2.new(1, 0, 1, -76), BackgroundTransparency = 1, Parent = UI.side,
		})
		list(UI.tabHolder, 5)
		padding(UI.tabHolder, 0, 0, 13, 13)
		
		UI.statusTxt = New("TextLabel", {
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 30, 1, -16), Size = UDim2.new(1, -46, 0, 13),
			BackgroundTransparency = 1, Font = FM, TextSize = 10, TextColor3 = Theme.Dim,
			TextXAlignment = Enum.TextXAlignment.Left, Text = "", Parent = UI.side,
		})
		UI.statusDot = New("Frame", {
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 19, 1, -20), Size = UDim2.fromOffset(6, 6),
			BackgroundColor3 = Theme.Good, BorderSizePixel = 0, Parent = UI.side,
		})
		round1(UI.statusDot)
		UI.cfgTxt = New("TextLabel", {
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 18, 1, -34), Size = UDim2.new(1, -34, 0, 13),
			BackgroundTransparency = 1, Font = FSB, TextSize = 11, TextColor3 = Theme.Sub,
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = "default", Parent = UI.side,
		})
		
		--------------------------------------------------------------- КОНТЕНТ ------
		UI.content = New("Frame", {
			Name = "content", Position = UDim2.new(0, SIDE, 0, 50), Size = UDim2.new(1, -SIDE, 1, -50),
			BackgroundTransparency = 1, Parent = UI.win,
		})
		UI.hTitle = New("TextLabel", {
			Position = UDim2.new(0, 24, 0, 18), Size = UDim2.new(1, -160, 0, 21), BackgroundTransparency = 1,
			Font = FB, TextSize = 19, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
			Text = "Main", Parent = UI.content,
		})
		UI.hSub = New("TextLabel", {
			Position = UDim2.new(0, 24, 0, 40), Size = UDim2.new(1, -160, 0, 13), BackgroundTransparency = 1,
			Font = FM, TextSize = 11, TextColor3 = Theme.Sub, TextXAlignment = Enum.TextXAlignment.Left,
			Text = "", Parent = UI.content,
		})
		UI.hCount = New("TextLabel", {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 24), Size = UDim2.fromOffset(130, 16),
			BackgroundTransparency = 1, Font = FSB, TextSize = 11, TextColor3 = Theme.Sub,
			TextXAlignment = Enum.TextXAlignment.Right, Text = "", Parent = UI.content,
		})
		New("Frame", {
			Position = UDim2.new(0, 24, 0, 68), Size = UDim2.new(1, -48, 0, 1),
			BackgroundColor3 = Theme.Stroke, BorderSizePixel = 0, Parent = UI.content,
		})
		UI.warn = New("Frame", {
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -4), Size = UDim2.new(1, -48, 0, 20),
			BackgroundColor3 = Color3.fromRGB(48, 20, 27), BorderSizePixel = 0,
			Visible = false, Parent = UI.content,
		})
		corner(UI.warn, 6)
		stroke(UI.warn, Color3.fromRGB(116, 42, 54), 1)
		New("TextLabel", {
			BackgroundTransparency = 1, Size = UDim2.new(1, -16, 1, 0), Position = UDim2.new(0, 8, 0, 0),
			Font = FSB, TextSize = 10, TextColor3 = Theme.Bad, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "конфиги не сохранятся после выхода: положи Script anaclysm_store_server в ServerScriptService",
			Parent = UI.warn,
		})
		
		local applyFeatureFilter, updateGroupFilter, toggleCommandPalette
		local searchFavOnly = false
		local searchGroup = "Все"
		local searchGroups = { "Все" }
		local searchGroupIndex = 1
		
		UI.searchBar = New("Frame", {
			Position = UDim2.new(0, 24, 0, 76), Size = UDim2.new(1, -48, 0, 34), BackgroundColor3 = Theme.Card,
			BackgroundTransparency = 0.18, BorderSizePixel = 0, Parent = UI.content,
		})
		corner(UI.searchBar, 9)
		stroke(UI.searchBar, Theme.Stroke, 1)
		UI.searchBox = New("TextBox", {
			Position=UDim2.fromOffset(11,0), Size=UDim2.new(1,-314,1,0), BackgroundTransparency=1, ClearTextOnFocus=false,
			Font=FM, TextSize=11, TextColor3=Theme.Text, PlaceholderColor3=Theme.Dim, PlaceholderText="Поиск по функциям...",
			Text="", TextXAlignment=Enum.TextXAlignment.Left, Parent=UI.searchBar,
		})
		UI.searchCount = New("TextLabel", { AnchorPoint=Vector2.new(1,.5), Position=UDim2.new(1,-10,.5,0), Size=UDim2.fromOffset(54,16),
			BackgroundTransparency=1, Font=FSB, TextSize=9, TextColor3=Theme.Dim, TextXAlignment=Enum.TextXAlignment.Right, Text="", Parent=UI.searchBar })
		UI.searchFav = New("TextButton", { AnchorPoint=Vector2.new(1,.5), Position=UDim2.new(1,-70,.5,0), Size=UDim2.fromOffset(30,24),
			BackgroundColor3=Theme.Deep, BackgroundTransparency=.15, BorderSizePixel=0, Font=FB, TextSize=13, TextColor3=Theme.Dim, Text="☆", AutoButtonColor=false, Parent=UI.searchBar })
		corner(UI.searchFav,7); stroke(UI.searchFav,Theme.Stroke,1)
		UI.searchGroup = New("TextButton", { AnchorPoint=Vector2.new(1,.5), Position=UDim2.new(1,-108,.5,0), Size=UDim2.fromOffset(112,24),
			BackgroundColor3=Theme.Deep, BackgroundTransparency=.15, BorderSizePixel=0, Font=FSB, TextSize=9, TextColor3=Theme.Sub, Text="Все группы",
			TextTruncate=Enum.TextTruncate.AtEnd, AutoButtonColor=false, Parent=UI.searchBar })
		corner(UI.searchGroup,7); stroke(UI.searchGroup,Theme.Stroke,1)
		UI.cmdHint = New("TextLabel", { AnchorPoint=Vector2.new(1,.5), Position=UDim2.new(1,-226,.5,0), Size=UDim2.fromOffset(76,16), BackgroundTransparency=1,
			Font=FM, TextSize=9, TextColor3=Theme.Dim, TextXAlignment=Enum.TextXAlignment.Right, Text="CTRL+K", Parent=UI.searchBar })
		
		UI.searchBox:GetPropertyChangedSignal("Text"):Connect(function() if applyFeatureFilter then applyFeatureFilter() end end)
		UI.searchFav.MouseButton1Click:Connect(function()
			searchFavOnly = not searchFavOnly
			UI.searchFav.Text = searchFavOnly and "★" or "☆"
			UI.searchFav.TextColor3 = searchFavOnly and Theme.Accent or Theme.Dim
			if applyFeatureFilter then applyFeatureFilter() end
		end)
		UI.searchGroup.MouseButton1Click:Connect(function()
			if #searchGroups == 0 then return end
			searchGroupIndex = (searchGroupIndex % #searchGroups) + 1
			searchGroup = searchGroups[searchGroupIndex]
			UI.searchGroup.Text = searchGroup == "Все" and "Все группы" or searchGroup
			if applyFeatureFilter then applyFeatureFilter() end
		end)
		
		UI.body = New("Frame", {
			Position = UDim2.new(0, 24, 0, 118), Size = UDim2.new(1, -48, 1, -138), BackgroundTransparency = 1, Parent = UI.content,
		})
		
		local TABS = {
			{ id = "Main",     sub = "прицеливание · weapon bridge · быстрые модули" },
			{ id = "Movement", sub = "скорость · прыжок · полёт · third person" },
			{ id = "Visuals",  sub = "ESP + 3D preview · radar · target HUD · overlays" },
			{ id = "Settings", sub = "поиск · избранное · HUD editor · профили · темы" },
			{ id = "Info",     sub = "diagnostics · notification center · session dashboard" },
		}
		
		local activeTab = "Main"
		local pages = {}
		for _, t in ipairs(TABS) do
			local page = New("CanvasGroup", {
				Name = t.id, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
				GroupTransparency = 0, Visible = false, Parent = UI.body,
			})
			local cols = {}
			if IS_MOBILE then
				local sf = New("ScrollingFrame", {
					Position = UDim2.fromOffset(0, 0), Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(),
					AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4,
					ScrollingEnabled = true, ScrollingDirection = Enum.ScrollingDirection.Y,
					ElasticBehavior = Enum.ElasticBehavior.Always,
					ScrollBarImageColor3 = Theme.Stroke, ScrollBarImageTransparency = 0.15, Parent = page,
				})
				list(sf, 11)
				padding(sf, 0, 18, 0, 6)
				cols[1], cols[2] = sf, sf
			else
				for i = 1, 2 do
					local sf = New("ScrollingFrame", {
						Position = UDim2.new(0.5 * (i - 1), (i - 1) * 9, 0, 0), Size = UDim2.new(0.5, -9, 1, 0),
						BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(),
						AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4,
						ScrollingEnabled = true, ScrollingDirection = Enum.ScrollingDirection.Y,
						ElasticBehavior = Enum.ElasticBehavior.Always,
						ScrollBarImageColor3 = Theme.Stroke, ScrollBarImageTransparency = 0.15, Parent = page,
					})
					list(sf, 11)
					padding(sf, 0, 16, 0, 7)
					cols[i] = sf
				end
			end
			pages[t.id] = { frame = page, cols = cols }
		end

		--------------------------------------------------- РЕГУЛЯТОР РАЗМЕРА --------
		UI.grip = New("Frame", {
			Name = "grip", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -3, 1, -3),
			Size = UDim2.fromOffset(18, 18), BackgroundTransparency = 1, ZIndex = 20, Parent = UI.win,
		})
		for i = 1, 3 do
			local l = New("Frame", {
				AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -(i - 1) * 5, 1, 0),
				Size = UDim2.fromOffset(2, 2 + (3 - i) * 5), BackgroundColor3 = Theme.Dim,
				BorderSizePixel = 0, Rotation = 0, ZIndex = 20, Parent = UI.grip,
			})
			corner(l, 1)
		end
		UI.gripBtn = New("TextButton", {
			BackgroundTransparency = 1, Size = UDim2.new(1, 10, 1, 10), Position = UDim2.fromOffset(-10, -10),
			Text = "", AutoButtonColor = false, ZIndex = 21, Parent = UI.grip,
		})
		
		--============================================== ЭЛЕМЕНТЫ УПРАВЛЕНИЯ =========
		local capturing = nil
		local MODES = { "Toggle", "Hold", "Always" }
		
		local function shell(parent, h)
			local f = New("Frame", {
				Size = UDim2.new(1, 0, 0, h), BackgroundColor3 = Theme.Row, BackgroundTransparency = 0.45,
				BorderSizePixel = 0, Parent = parent,
			})
			corner(f, 7)
			padding(f, 0, 0, 9, 9)
			return f
		end
		
		local function cLabel(parent, text, y)
			return New("TextLabel", {
				BackgroundTransparency = 1, Size = UDim2.new(1, -76, 0, 13), Position = UDim2.new(0, 0, 0, y or 0),
				Font = FM, TextSize = 11, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd, Text = text, Parent = parent,
			})
		end
		
		local function cToggle(parent, text, get, set)
			local f = shell(parent, 30)
			local l = cLabel(f, text)
			l.Position = UDim2.new(0, 0, 0.5, 0)
			l.AnchorPoint = Vector2.new(0, 0.5)
			local pill = New("Frame", {
				AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(32, 17),
				BackgroundColor3 = Theme.Deep, BorderSizePixel = 0, Parent = f,
			})
			round1(pill)
			local ps = stroke(pill, Theme.Stroke, 1)
			local knob = New("Frame", {
				AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0), Size = UDim2.fromOffset(11, 11),
				BackgroundColor3 = Theme.Dim, BorderSizePixel = 0, Parent = pill,
			})
			round1(knob)
			local function upd()
				local v = get()
				tw(knob, 0.24, { Position = UDim2.new(0, v and 18 or 3, 0.5, 0),
					BackgroundColor3 = v and Color3.new(1, 1, 1) or Theme.Dim })
				tw(pill, 0.2, { BackgroundColor3 = v and Theme.Accent or Theme.Deep })
				ps.Transparency = v and 1 or 0
			end
			local b = New("TextButton", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = "", Parent = f })
			b.MouseButton1Click:Connect(function() set(not get()) upd() end)
			upd()
			return f
		end
		
		local function cSlider(parent, opt, get, set)
			local f = shell(parent, 42)
			cLabel(f, opt.Name, 7)
			local val = New("TextLabel", {
				AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 7), Size = UDim2.fromOffset(74, 13),
				BackgroundTransparency = 1, Font = FSB, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right,
				Text = "", Parent = f,
			})
			accent(val, "TextColor3")
			local bar = New("Frame", {
				Position = UDim2.new(0, 0, 0, 28), Size = UDim2.new(1, 0, 0, 5), BackgroundColor3 = Theme.Deep,
				BorderSizePixel = 0, Parent = f,
			})
			round1(bar)
			local fill = New("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = bar })
			round1(fill)
			accent(New("UIGradient", { Parent = fill }), "Color")
			local knob = New("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(11, 11),
				BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 2, Parent = bar,
			})
			round1(knob)
			local step = opt.Step or 1
			local function upd()
				local v = get()
				local a = (v - opt.Min) / math.max(opt.Max - opt.Min, 0.0001)
				fill.Size = UDim2.new(a, 0, 1, 0)
				knob.Position = UDim2.new(a, 0, 0.5, 0)
				val.Text = ((step < 1) and string.format("%.1f", v) or tostring(math.floor(v)))
					.. (opt.Suffix and (" " .. opt.Suffix) or "")
			end
			local drag = false
			local function apply(x)
				local a = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
				set(math.clamp(snap(opt.Min + a * (opt.Max - opt.Min), step), opt.Min, opt.Max))
				upd()
			end
			local hit = New("TextButton", { BackgroundTransparency = 1, Text = "", Position = UDim2.new(0, -4, 0, 22), Size = UDim2.new(1, 8, 0, 18), Parent = f })
			hit.InputBegan:Connect(function(i)
				if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
					drag = true
					apply(i.Position.X)
					tw(knob, 0.12, { Size = UDim2.fromOffset(14, 14) })
				end
			end)
			bind(UserInputService.InputChanged, function(i)
				if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
					apply(i.Position.X)
				end
			end)
			bind(UserInputService.InputEnded, function(i)
				if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
					if drag then tw(knob, 0.15, { Size = UDim2.fromOffset(11, 11) }) end
					drag = false
				end
			end)
			upd()
			return f
		end
		
		local function cDropdown(parent, opt, get, set)
			local wrap = New("Frame", {
				Size = UDim2.new(1, 0, 0, 30), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Theme.Row,
				BackgroundTransparency = 0.45, BorderSizePixel = 0, Parent = parent,
			})
			corner(wrap, 7)
			padding(wrap, 0, 6, 9, 9)
			list(wrap, 3)
			local head = New("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 0, Parent = wrap })
			local l = cLabel(head, opt.Name)
			l.Position = UDim2.new(0, 0, 0.5, 0)
			l.AnchorPoint = Vector2.new(0, 0.5)
			l.Size = UDim2.new(0.45, 0, 0, 13)
			local cur = New("TextLabel", {
				AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.new(0.55, -12, 0, 13),
				BackgroundTransparency = 1, Font = FSB, TextSize = 11, TextColor3 = Theme.Sub,
				TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd,
				Text = tostring(get()), Parent = head,
			})
			local arrow = New("TextLabel", {
				AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(10, 12),
				BackgroundTransparency = 1, Font = FB, TextSize = 9, TextColor3 = Theme.Dim, Text = "v", Parent = head,
			})
			local holder = New("Frame", {
				Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
				Visible = false, LayoutOrder = 1, Parent = wrap,
			})
			list(holder, 3)
			local items = {}
			local function upd()
				cur.Text = tostring(get())
				for v, it in pairs(items) do
					local sel = (get() == v)
					it.lbl.TextColor3 = sel and Color3.new(1, 1, 1) or Theme.Sub
					it.f.BackgroundColor3 = sel and Theme.Accent or Theme.Deep
					it.f.BackgroundTransparency = sel and 0.15 or 0.45
				end
			end
			for _, v in ipairs(opt.List) do
				local it = New("Frame", { Size = UDim2.new(1, 0, 0, 25), BackgroundColor3 = Theme.Deep, BackgroundTransparency = 0.45, BorderSizePixel = 0, Parent = holder })
				corner(it, 6)
				local il = New("TextLabel", {
					BackgroundTransparency = 1, Size = UDim2.new(1, -16, 1, 0), Position = UDim2.new(0, 8, 0, 0),
					Font = FM, TextSize = 11, TextColor3 = Theme.Sub, TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd, Text = tostring(v), Parent = it,
				})
				local ib = New("TextButton", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = "", Parent = it })
				ib.MouseButton1Click:Connect(function() set(v) upd() end)
				items[v] = { f = it, lbl = il }
			end
			local open = false
			local hb = New("TextButton", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = "", Parent = head })
			hb.MouseButton1Click:Connect(function()
				open = not open
				holder.Visible = open
				tw(arrow, 0.2, { Rotation = open and 180 or 0, TextColor3 = open and Theme.Accent or Theme.Dim })
			end)
			upd()
			return wrap
		end
		
		local function cKeybind(parent, text, get, set)
			local f = shell(parent, 30)
			local l = cLabel(f, text)
			l.Position = UDim2.new(0, 0, 0.5, 0)
			l.AnchorPoint = Vector2.new(0, 0.5)
			local clear = New("TextButton", {
				AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(20, 19),
				BackgroundColor3 = Theme.Deep, BorderSizePixel = 0, AutoButtonColor = false,
				Font = FB, TextSize = 10, TextColor3 = Theme.Dim, Text = "X", Parent = f,
			})
			corner(clear, 6)
			local clearS = stroke(clear, Theme.Stroke, 1)
			local box = New("Frame", {
				AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -24, 0.5, 0), Size = UDim2.fromOffset(74, 19),
				BackgroundColor3 = Theme.Deep, BorderSizePixel = 0, Parent = f,
			})
			corner(box, 6)
			local bs = stroke(box, Theme.Stroke, 1)
			local kl = New("TextLabel", {
				BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = FSB, TextSize = 10,
				TextColor3 = Theme.Text, Text = keyLabel(get()), Parent = box,
			})
			local function upd()
				local empty = (get() == "" or get() == nil)
				kl.Text = keyLabel(get())
				kl.TextColor3 = empty and Theme.Dim or Theme.Text
				bs.Color = Theme.Stroke
				clear.TextColor3 = empty and Theme.Dim or Theme.Bad
				clearS.Color = Theme.Stroke
			end
			clear.MouseEnter:Connect(function()
				if get() ~= "" then tw(clearS, 0.12, { Color = Theme.Bad, Transparency = 0.35 }) end
			end)
			clear.MouseLeave:Connect(function() tw(clearS, 0.15, { Color = Theme.Stroke, Transparency = 0 }) end)
			clear.MouseButton1Click:Connect(function()
				capturing = nil
				set("")
				upd()
			end)
			local lastCapture = 0
			local b = New("TextButton", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = "", Parent = box })
			b.MouseButton1Click:Connect(function()
				kl.Text = "нажмите..."
				kl.TextColor3 = Theme.Accent
				bs.Color = Theme.Accent
				capturing = { apply = function(n)
					lastCapture = os.clock()
					set(n)
					upd()
				end }
			end)
			b.MouseButton2Click:Connect(function()
				-- ПКМ сразу после назначения — это тот же клик, которым бинд и ставили
				if os.clock() - lastCapture < 0.4 then return end
				set("")
				upd()
			end)
			upd()
			return f
		end
		
		local function cColor(parent, opt, get, set)
			local f = shell(parent, 42)
			cLabel(f, opt.Name, 7)
			local sw = New("Frame", {
				AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 5), Size = UDim2.fromOffset(34, 16),
				BackgroundColor3 = hexToColor(get()), BorderSizePixel = 0, Parent = f,
			})
			corner(sw, 5)
			stroke(sw, Theme.Stroke, 1)
			local bar = New("Frame", {
				Position = UDim2.new(0, 0, 0, 28), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0, Parent = f,
			})
			round1(bar)
			New("UIGradient", {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
					ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
					ColorSequenceKeypoint.new(0.34, Color3.fromRGB(0, 255, 0)),
					ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
					ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
					ColorSequenceKeypoint.new(0.84, Color3.fromRGB(255, 0, 255)),
					ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 255, 255)),
				}), Parent = bar,
			})
			local knob = New("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(10, 10),
				BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 2, Parent = bar,
			})
			round1(knob)
			stroke(knob, Theme.Deep, 1.4)
			local function upd()
				local c = hexToColor(get())
				sw.BackgroundColor3 = c
				knob.Position = UDim2.new(select(1, Color3.toHSV(c)), 0, 0.5, 0)
			end
			local drag = false
			local function apply(x)
				local a = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
				set(colorToHex(a >= 0.99 and Color3.new(1, 1, 1) or Color3.fromHSV(a, 0.85, 1)))
				upd()
			end
			local hit = New("TextButton", { BackgroundTransparency = 1, Text = "", Position = UDim2.new(0, -4, 0, 22), Size = UDim2.new(1, 8, 0, 18), Parent = f })
			hit.InputBegan:Connect(function(i)
				if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
					drag = true
					apply(i.Position.X)
				end
			end)
			bind(UserInputService.InputChanged, function(i)
				if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
					apply(i.Position.X)
				end
			end)
			bind(UserInputService.InputEnded, function(i)
				if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then drag = false end
			end)
			upd()
			return f
		end
		
		local function cButton(parent, name, style, run)
			local b = New("TextButton", {
				Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Theme.Row, BorderSizePixel = 0, AutoButtonColor = false,
				Font = FSB, TextSize = 11, TextColor3 = Theme.Text, Text = name, Parent = parent,
			})
			corner(b, 7)
			local st = stroke(b, Theme.Stroke, 1)
			if style == "accent" then
				accent(b, "BackgroundColor3")
				st.Transparency = 1
				b.TextColor3 = Color3.new(1, 1, 1)
			elseif style == "danger" then
				b.BackgroundColor3 = Color3.fromRGB(46, 20, 27)
				st.Color = Color3.fromRGB(116, 42, 54)
				b.TextColor3 = Theme.Bad
			end
			b.MouseEnter:Connect(function() tw(b, 0.13, { BackgroundTransparency = 0.2 }) end)
			b.MouseLeave:Connect(function() tw(b, 0.16, { BackgroundTransparency = 0 }) end)
			b.MouseButton1Click:Connect(function()
				tw(b, 0.09, { Size = UDim2.new(1, -8, 0, 27) })
				task.delay(0.1, function() tw(b, 0.24, { Size = UDim2.new(1, 0, 0, 30) }) end)
				if run then task.spawn(run) end
			end)
			return b
		end
		
		local function cTextBox(parent, placeholder, onEnter)
			local f = shell(parent, 30)
			local box = New("TextBox", {
				BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Font = FM, TextSize = 11,
				TextColor3 = Theme.Text, PlaceholderText = placeholder, PlaceholderColor3 = Theme.Dim,
				TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, Text = "", Parent = f,
			})
			box.FocusLost:Connect(function(enter)
				if enter and onEnter then onEnter(box.Text) end
			end)
			return box
		end
		
		--=============================================== КАРТЫ, СТРОКИ, ПАНЕЛИ ======
		local function setOpt(f, opt, v)
			DB[f.Id].o[opt.Id] = v
			if opt.OnChange then pcall(opt.OnChange, v) end
			if f.Id == "theme" then
				if opt.Id == "preset" then
					local p = PRESETS[v]
					if p then DB.theme.o.c1, DB.theme.o.c2 = p[1], p[2] end
				end
				UICFG.Accent, UICFG.Accent2 = O("theme", "c1"), O("theme", "c2")
				Theme.Accent, Theme.Accent2 = hexToColor(UICFG.Accent), hexToColor(UICFG.Accent2)
				applyAccent()
				UI.fovStroke.Color = Theme.Accent
			end
			markDirty()
		end
		
		local rebuildConfigList
		
		local function buildConfigPanel(inner)
			local nameBox = cTextBox(inner, "название конфига...", nil)
			cButton(inner, "Сохранить как новый", "accent", function()
				local n = nameBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
				if n == "" then Notify("Введите название конфига", "warn") return end
				saveConfig(n)
				nameBox.Text = ""
				if rebuildConfigList then rebuildConfigList() end
				if UI.cfgTxt then UI.cfgTxt.Text = Store.current end
			end)
			cButton(inner, "Перезаписать текущий", nil, function()
				saveConfig(Store.current)
				if rebuildConfigList then rebuildConfigList() end
			end)
			cButton(inner, "Записать на сервер сейчас", nil, function()
				if not RemoteStore then
					Notify("Серверный модуль не найден, записывать некуда", "bad")
					return
				end
				if flushStore() then
					Notify("Конфиги записаны в DataStore", "ok")
				end
			end)
			cButton(inner, "Проверить хранилище", nil, function()
				if not RemoteStore then
					Notify("Модуль AnaclysmStore отсутствует в ReplicatedStorage", "bad")
					return
				end
				local ok, res = pcall(function() return RemoteStore:InvokeServer("status") end)
				if not ok then
					Notify("Сервер не отвечает на запрос состояния", "bad")
				elseif res == true then
					Notify("DataStore доступен, сохранение между сессиями работает", "ok")
				else
					Notify("DataStore недоступен: " .. tostring(res), "bad")
				end
			end)
		
		
			New("TextLabel", {
				Size = UDim2.new(1, 0, 0, 15), BackgroundTransparency = 1, Font = FB, TextSize = 10,
				TextColor3 = Theme.Dim, TextXAlignment = Enum.TextXAlignment.Left, Text = "СОХРАНЁННЫЕ КОНФИГИ", Parent = inner,
			})
		
			local holder = New("Frame", {
				Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = inner,
			})
			list(holder, 4)
		
			rebuildConfigList = function()
				for _, c in ipairs(holder:GetChildren()) do
					if not c:IsA("UIListLayout") then c:Destroy() end
				end
				local names = {}
				for n in pairs(Store.configs) do
					if not tostring(n):match("^__place_") then table.insert(names, n) end
				end
				table.sort(names)
				if #names == 0 then
					New("TextLabel", {
						Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Font = FM, TextSize = 11,
						TextColor3 = Theme.Dim, TextXAlignment = Enum.TextXAlignment.Left,
						Text = "пока пусто", Parent = holder,
					})
					return
				end
				for _, n in ipairs(names) do
					local row = New("Frame", {
						Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Theme.Row, BackgroundTransparency = 0.45,
						BorderSizePixel = 0, Parent = holder,
					})
					corner(row, 7)
					padding(row, 0, 0, 9, 6)
					local isCur = (Store.current == n)
					local dot = New("Frame", {
						AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(5, 5),
						BackgroundColor3 = isCur and Theme.Accent or Theme.Dim, BorderSizePixel = 0, Parent = row,
					})
					round1(dot)
					New("TextLabel", {
						Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -80, 1, 0), BackgroundTransparency = 1,
						Font = isCur and FSB or FM, TextSize = 11, TextColor3 = isCur and Theme.Text or Theme.Sub,
						TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
						Text = n, Parent = row,
					})
					local load = New("TextButton", {
						AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -28, 0.5, 0), Size = UDim2.fromOffset(56, 20),
						BackgroundColor3 = Theme.Deep, BorderSizePixel = 0, AutoButtonColor = false, Font = FSB,
						TextSize = 10, TextColor3 = Theme.Text, Text = "ЗАГРУЗИТЬ", Parent = row,
					})
					corner(load, 6)
					stroke(load, Theme.Stroke, 1)
					load.MouseButton1Click:Connect(function()
						loadConfig(n)
						if UI.cfgTxt then UI.cfgTxt.Text = Store.current end
						if rebuildConfigList then rebuildConfigList() end
					end)
					local del = New("TextButton", {
						AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(22, 20),
						BackgroundColor3 = Theme.Deep, BorderSizePixel = 0, AutoButtonColor = false, Font = FB,
						TextSize = 10, TextColor3 = Theme.Bad, Text = "X", Parent = row,
					})
					corner(del, 6)
					stroke(del, Theme.Stroke, 1)
					del.MouseButton1Click:Connect(function()
						deleteConfig(n)
						if rebuildConfigList then rebuildConfigList() end
						if UI.cfgTxt then UI.cfgTxt.Text = Store.current end
					end)
				end
			end
			rebuildConfigList()
		end
		
		local function buildInfoPanel(inner)
			local rows = {}
			local function row(label)
				local f = New("Frame", {
					Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = Theme.Row, BackgroundTransparency = 0.5,
					BorderSizePixel = 0, Parent = inner,
				})
				corner(f, 6)
				padding(f, 0, 0, 9, 9)
				New("TextLabel", {
					BackgroundTransparency = 1, Size = UDim2.new(0.5, 0, 1, 0), Font = FM, TextSize = 11,
					TextColor3 = Theme.Sub, TextXAlignment = Enum.TextXAlignment.Left, Text = label, Parent = f,
				})
				local v = New("TextLabel", {
					BackgroundTransparency = 1, Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(0.5, 0, 1, 0),
					Font = FSB, TextSize = 11, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Right,
					TextTruncate = Enum.TextTruncate.AtEnd, Text = "—", Parent = f,
				})
				rows[label] = v
				return v
			end
		
			local platform = "ПК"
			if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
				platform = "Мобильный"
			elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
				platform = "Консоль"
			end
		
			row("Place ID")
			row("Job ID")
			row("Игроков")
			row("Team")
			row("Neutral")
			row("Платформа")
			row("Ник")
			row("User ID")
			row("Возраст акка")
			row("FPS")
			row("Пинг")
			row("Время в сессии")
			row("Хранилище")
			row("File I/O")
			row("Meta hook")
			row("Clipboard")
			row("Runtime faults")
			row("Версия")
		
			local started = os.clock()
			task.spawn(function()
				while inner and inner.Parent do
					local ping = 0
					pcall(function() ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()) end)
					local el = os.clock() - started
					local privateServer = streamerActive() and O("streamer", "server")
					rows["Place ID"].Text = privateServer and "скрыто" or tostring(game.PlaceId)
					rows["Job ID"].Text = privateServer and "скрыто" or ((game.JobId ~= "" and game.JobId:sub(1, 18) .. "…") or "студия")
					rows["Игроков"].Text = #Players:GetPlayers() .. " / " .. Players.MaxPlayers
					rows["Team"].Text = LP.Team and LP.Team.Name or "none"
					rows["Neutral"].Text = tostring(LP.Neutral)
					rows["Платформа"].Text = platform
					rows["Ник"].Text = safePlayerLabel(LP) .. " (" .. safeUserLabel(LP) .. ")"
					rows["User ID"].Text = (streamerActive() and O("streamer", "userid")) and "скрыто" or tostring(LP.UserId)
					rows["Возраст акка"].Text = (streamerActive() and O("streamer", "self")) and "скрыто" or (LP.AccountAge .. " дн.")
					rows["FPS"].Text = tostring(infoFps)
					rows["Пинг"].Text = ping .. " мс"
					rows["Время в сессии"].Text = string.format("%d:%02d", math.floor(el / 60), math.floor(el % 60))
					rows["Хранилище"].Text = RemoteStore and "сервер" or (RUNTIME_CAPS.FileIO and "локально/сессия" or "сессия")
					rows["File I/O"].Text = RUNTIME_CAPS.FileIO and "available" or "fallback"
					rows["Meta hook"].Text = RUNTIME_CAPS.MetaHook and (saHookInstalled and "active" or "available") or "fallback only"
					rows["Clipboard"].Text = RUNTIME_CAPS.Clipboard and "available" or "unavailable"
					local faults = 0
					for _ in pairs(RUNTIME_ERRORS) do faults += 1 end
					rows["Runtime faults"].Text = tostring(faults)
					rows["Версия"].Text = "anaclysm hub v5.2.3"
					task.wait(1)
				end
			end)
		end
		
		local function buildCompatibilityPanel(inner)
			COMPAT_DIAG.panelOpen = true
			local rows = {}
			local function diagRow(label)
				local f = New("Frame", { Size = UDim2.new(1,0,0,25), BackgroundColor3 = Theme.Row, BackgroundTransparency = .5, BorderSizePixel = 0, Parent = inner })
				corner(f,6); padding(f,0,0,8,8)
				New("TextLabel", { BackgroundTransparency=1, Size=UDim2.new(.44,0,1,0), Font=FM, TextSize=10, TextColor3=Theme.Sub, TextXAlignment=Enum.TextXAlignment.Left, Text=label, Parent=f })
				local v = New("TextLabel", { BackgroundTransparency=1, Position=UDim2.new(.44,0,0,0), Size=UDim2.new(.56,0,1,0), Font=FSB, TextSize=10, TextColor3=Theme.Text, TextXAlignment=Enum.TextXAlignment.Right, TextTruncate=Enum.TextTruncate.AtEnd, Text="—", Parent=f })
				rows[label] = v
			end
			for _, label in ipairs({
				"Game mode","Team / Neutral","Character","Humanoid state","HP","WalkSpeed","Jump","AutoRotate","PlatformStand",
				"Gravity","FOV","Camera type","Spawn guard","Last writer","Phase","Changed","Writer age","Last toggle","Last event"
			}) do diagRow(label) end
			cButton(inner, "Очистить trace", "", function()
				COMPAT_DIAG.lastWriter, COMPAT_DIAG.lastPhase, COMPAT_DIAG.lastChanges = "—", "—", "—"
				COMPAT_DIAG.lastAt, COMPAT_DIAG.lastToggleAt = 0, 0
				COMPAT_DIAG.lastToggle, COMPAT_DIAG.lastEvent = "—", "trace cleared"
				table.clear(COMPAT_DIAG.history)
			end)
			cButton(inner, "Emergency restore Humanoid/Camera", "danger", function()
				local h = getHum(); if h then restoreHumanoid(h) end
				workspace.Gravity = WORLD_BASE.Gravity
				if Camera then pcall(function() Camera.FieldOfView = START_CAMERA_FOV end) end
				currentTarget, saCurrentTarget = nil, nil
				COMPAT_DIAG.lastEvent = "manual emergency restore"
				Notify("Базовые Humanoid/Camera параметры восстановлены", "warn")
			end)
			New("TextLabel", { Size=UDim2.new(1,0,0,16), BackgroundTransparency=1, Font=FB, TextSize=9, TextColor3=Theme.Dim, TextXAlignment=Enum.TextXAlignment.Left, Text="RECENT WRITES", Parent=inner })
			local hist = {}
			for i=1,6 do hist[i] = New("TextLabel", { Size=UDim2.new(1,0,0,16), BackgroundTransparency=1, Font=FM, TextSize=9, TextColor3=Theme.Sub, TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd, Text="—", Parent=inner }) end
			task.spawn(function()
				while inner and inner.Parent do
					local h=getHum(); local guard=math.max(0,(COMPAT_DIAG.respawnGuardUntil or 0)-os.clock())
					rows["Game mode"].Text = gameModeOverride()
					rows["Team / Neutral"].Text = (LP.Team and LP.Team.Name or "none") .. " / " .. tostring(LP.Neutral)
					rows["Character"].Text = LP.Character and LP.Character.Name or "none"
					rows["Humanoid state"].Text = h and tostring(h:GetState()):gsub("Enum.HumanoidStateType.","") or "none"
					rows["HP"].Text = h and (math.floor(h.Health).." / "..math.floor(h.MaxHealth)) or "—"
					rows["WalkSpeed"].Text = h and string.format("%.2f",h.WalkSpeed) or "—"
					rows["Jump"].Text = h and string.format("%s %.2f", h.UseJumpPower and "Power" or "Height", h.UseJumpPower and h.JumpPower or h.JumpHeight) or "—"
					rows["AutoRotate"].Text = h and tostring(h.AutoRotate) or "—"
					rows["PlatformStand"].Text = h and tostring(h.PlatformStand) or "—"
					rows["Gravity"].Text = string.format("%.2f",workspace.Gravity)
					rows["FOV"].Text = Camera and string.format("%.2f",Camera.FieldOfView) or "—"
					rows["Camera type"].Text = Camera and tostring(Camera.CameraType):gsub("Enum.CameraType.","") or "—"
					rows["Spawn guard"].Text = guard>0 and string.format("%.1f s",guard) or "ready"
					rows["Last writer"].Text = COMPAT_DIAG.lastWriter or "—"
					rows["Phase"].Text = COMPAT_DIAG.lastPhase or "—"
					rows["Changed"].Text = COMPAT_DIAG.lastChanges or "—"
					rows["Writer age"].Text = (COMPAT_DIAG.lastAt or 0)>0 and string.format("%.2f s",os.clock()-COMPAT_DIAG.lastAt) or "—"
					rows["Last toggle"].Text = COMPAT_DIAG.lastToggle or "—"
					rows["Last event"].Text = COMPAT_DIAG.lastEvent or "—"
					for i=1,6 do hist[i].Text = COMPAT_DIAG.history[i] or "—" end
					task.wait(.20)
				end
				COMPAT_DIAG.panelOpen = false
			end)
		end

		local function buildWeaponLabPanel(inner)
			local rows = {}
			local function labRow(label)
				local f=New("Frame",{Size=UDim2.new(1,0,0,25),BackgroundColor3=Theme.Row,BackgroundTransparency=.5,BorderSizePixel=0,Parent=inner}); corner(f,6); padding(f,0,0,8,8)
				New("TextLabel",{BackgroundTransparency=1,Size=UDim2.new(.42,0,1,0),Font=FM,TextSize=10,TextColor3=Theme.Sub,TextXAlignment=Enum.TextXAlignment.Left,Text=label,Parent=f})
				local v=New("TextLabel",{BackgroundTransparency=1,Position=UDim2.new(.42,0,0,0),Size=UDim2.new(.58,0,1,0),Font=FSB,TextSize=10,TextColor3=Theme.Text,TextXAlignment=Enum.TextXAlignment.Right,TextTruncate=Enum.TextTruncate.AtEnd,Text="—",Parent=f})
				rows[label]=v
			end
			for _,label in ipairs({"Hook","Tool","Auto candidate","Learned remote","Confidence","Signature","Samples","Last call","Path","Budget tier"}) do labRow(label) end
			cButton(inner,"Пересканировать сейчас","accent",function()
				local ch=getChar(); local tool=ch and ch:FindFirstChildOfClass("Tool"); local r,score=detectWeaponRemote(tool,ch)
				WeaponIntel.scanRemote,WeaponIntel.scanScore=r,score or 0
				Notify(r and ("Weapon candidate: "..r.Name) or "Weapon candidate не найден",r and "ok" or "warn")
			end)
			cButton(inner,"Очистить обученную модель","danger",function() weaponResetLearning(); tbRemoteCache=nil; Notify("Weapon model очищена","warn") end)
			cButton(inner,"Скопировать diagnostics","",function()
				local r=WeaponIntel.learnedRemote
				local report=table.concat({
					"anaclysm hub v5.2.3 diagnostics",
					"place="..tostring(game.PlaceId),
					"tool="..tostring((getChar() and getChar():FindFirstChildOfClass("Tool") and getChar():FindFirstChildOfClass("Tool").Name) or "none"),
					"remote="..tostring(r and r.Name or "none"),
					"confidence="..tostring(math.floor(WeaponIntel.learnedConfidence or 0)),
					"signature="..tostring(WeaponIntel.lastSignature or "none"),
					"path="..tostring(WeaponIntel.lastPath or "none"),
					"samples="..tostring(WeaponIntel.samples).." confirmed="..tostring(WeaponIntel.confirmed),
					"budget="..optimizerTier(),
				},"\n")
				local ok = false
				if RUNTIME_CAPS.Clipboard then ok = pcall(function() setclipboard(report) end) end
				Notify(ok and "Diagnostics скопирован" or "Clipboard API недоступен",ok and "ok" or "warn")
			end)
			New("TextLabel",{Size=UDim2.new(1,0,0,16),BackgroundTransparency=1,Font=FB,TextSize=9,TextColor3=Theme.Dim,TextXAlignment=Enum.TextXAlignment.Left,Text="TOP CANDIDATES",Parent=inner})
			local tops={}
			for i=1,5 do
				tops[i]=New("TextLabel",{Size=UDim2.new(1,0,0,16),BackgroundTransparency=1,Font=FM,TextSize=9,TextColor3=Theme.Sub,TextXAlignment=Enum.TextXAlignment.Left,Text="—",Parent=inner})
			end
			task.spawn(function()
				local auto,score,nextScan=nil,0,0
				while inner and inner.Parent do
					local ch=getChar(); local tool=ch and ch:FindFirstChildOfClass("Tool")
					if os.clock() >= nextScan then auto,score=detectWeaponRemote(tool,ch); nextScan=os.clock()+1.25 end
					rows["Hook"].Text=saHookInstalled and "active" or "fallback only"
					rows["Tool"].Text=tool and tool.Name or "none"
					rows["Auto candidate"].Text=auto and (auto.Name.."  ["..tostring(score).."]") or "none"
					rows["Learned remote"].Text=WeaponIntel.learnedRemote and WeaponIntel.learnedRemote.Name or "none"
					rows["Confidence"].Text=tostring(math.floor(WeaponIntel.learnedConfidence or 0)).."% / "..tostring(weaponConfidenceThreshold()).."%"
					rows["Signature"].Text=WeaponIntel.lastSignature or "—"
					rows["Samples"].Text=tostring(WeaponIntel.samples).."  · confirmed "..tostring(WeaponIntel.confirmed)
					rows["Last call"].Text=(weaponLastSeen>0) and string.format("%.1fs ago",os.clock()-weaponLastSeen) or "—"
					rows["Path"].Text=WeaponIntel.lastPath or "—"
					rows["Budget tier"].Text=optimizerTier()
					local list=weaponTopCandidates(5)
					for i=1,5 do
						local e=list[i]
						tops[i].Text=e and string.format("%d. %s   %d%%   x%d",i,e.remote.Name,math.floor(e.rec.confidence or 0),e.rec.count or 0) or "—"
						tops[i].TextColor3=(e and e.remote==WeaponIntel.learnedRemote) and Theme.Accent or Theme.Sub
					end
					task.wait(.25)
				end
			end)
		end
		
		local function buildNotificationCenterPanel(inner)
			cButton(inner, "Очистить историю", "danger", function() table.clear(NOTIF_HISTORY); Notify("История уведомлений очищена", "warn") end)
			local holder=New("Frame",{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1,Parent=inner})
			list(holder,4)
			local lastCount=-1
			local function rebuild()
				for _,c in ipairs(holder:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
				local n=math.min(#NOTIF_HISTORY,30)
				if n==0 then
					New("TextLabel",{Size=UDim2.new(1,0,0,26),BackgroundTransparency=1,Font=FM,TextSize=10,TextColor3=Theme.Dim,TextXAlignment=Enum.TextXAlignment.Left,Text="история пока пустая",Parent=holder})
					return
				end
				for i=1,n do
					local e=NOTIF_HISTORY[i]
					local r=New("Frame",{Size=UDim2.new(1,0,0,32),BackgroundColor3=Theme.Row,BackgroundTransparency=.46,BorderSizePixel=0,Parent=holder}); corner(r,7)
					local col=e.kind=="bad" and Theme.Bad or (e.kind=="warn" and Theme.Warn or (e.kind=="ok" and Theme.Good or Theme.Accent))
					local dot=New("Frame",{AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,8,.5,0),Size=UDim2.fromOffset(5,5),BackgroundColor3=col,BorderSizePixel=0,Parent=r}); round1(dot)
					New("TextLabel",{Position=UDim2.fromOffset(20,3),Size=UDim2.new(1,-75,1,-6),BackgroundTransparency=1,Font=FM,TextSize=9,TextColor3=Theme.Text,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,Text=e.text,Parent=r})
					New("TextLabel",{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-8,.5,0),Size=UDim2.fromOffset(48,13),BackgroundTransparency=1,Font=FM,TextSize=8,TextColor3=Theme.Dim,TextXAlignment=Enum.TextXAlignment.Right,Text=e.t,Parent=r})
				end
			end
			rebuild()
			task.spawn(function() while holder.Parent do if #NOTIF_HISTORY~=lastCount then lastCount=#NOTIF_HISTORY; rebuild() end; task.wait(.5) end end)
		end
		
		local function buildSessionDashboardPanel(inner)
			local rows={}
			local function add(label)
				local f=New("Frame",{Size=UDim2.new(1,0,0,25),BackgroundColor3=Theme.Row,BackgroundTransparency=.5,BorderSizePixel=0,Parent=inner}); corner(f,6); padding(f,0,0,8,8)
				New("TextLabel",{BackgroundTransparency=1,Size=UDim2.new(.52,0,1,0),Font=FM,TextSize=10,TextColor3=Theme.Sub,TextXAlignment=Enum.TextXAlignment.Left,Text=label,Parent=f})
				local v=New("TextLabel",{BackgroundTransparency=1,Position=UDim2.new(.52,0,0,0),Size=UDim2.new(.48,0,1,0),Font=FSB,TextSize=10,TextColor3=Theme.Text,TextXAlignment=Enum.TextXAlignment.Right,Text="—",Parent=f}); rows[label]=v
			end
			for _,k in ipairs({"FPS min / avg / max","Респавны","Пиковые игроки","Избранных модулей","Активных модулей","HUD layout","Render budget","Place profile"}) do add(k) end
			task.spawn(function()
				while inner.Parent do
					local fav,active=0,0
					for _,f in ipairs(Features) do if type(UICFG.Favorites)=="table" and UICFG.Favorites[f.Id] then fav+=1 end; if not f.NoToggle and f._active then active+=1 end end
					local minF=(SESSION_METRICS.minFps==9999) and infoFps or SESSION_METRICS.minFps
					rows["FPS min / avg / max"].Text=string.format("%d / %d / %d",minF,math.floor(SESSION_METRICS.avgFps+.5),SESSION_METRICS.maxFps)
					rows["Респавны"].Text=tostring(SESSION_METRICS.respawns)
					rows["Пиковые игроки"].Text=tostring(SESSION_METRICS.peakPlayers)
					rows["Избранных модулей"].Text=tostring(fav)
					rows["Активных модулей"].Text=tostring(active)
					rows["HUD layout"].Text=UICFG.LayoutPreset or "Balanced"
					rows["Render budget"].Text=optimizerTier()
					rows["Place profile"].Text=Store.configs[placeProfileName()] and "saved" or "none"
					task.wait(.5)
				end
			end)
		end
		
		local function buildESPPreviewPanel(inner)
			local holder = New("Frame", {
				Size = UDim2.new(1, 0, 0, 318), BackgroundColor3 = Theme.Card, BackgroundTransparency = 0.18,
				BorderSizePixel = 0, ClipsDescendants = true, Parent = inner,
			})
			corner(holder, 12)
			stroke(holder, Theme.Stroke, 1)
		
			local title = New("TextLabel", {
				Position=UDim2.fromOffset(12,9), Size=UDim2.new(1,-24,0,16), BackgroundTransparency=1, Font=FB, TextSize=11,
				TextColor3=Theme.Text, TextXAlignment=Enum.TextXAlignment.Left, Text="LIVE TARGET PREVIEW", Parent=holder,
			})
			local hint = New("TextLabel", {
				Position=UDim2.fromOffset(12,27), Size=UDim2.new(1,-24,0,14), BackgroundTransparency=1, Font=FM, TextSize=9,
				TextColor3=Theme.Dim, TextXAlignment=Enum.TextXAlignment.Left, Text="меняй Player ESP — предпросмотр обновляется сразу", Parent=holder,
			})
		
			local stage = New("Frame", {
				Position=UDim2.fromOffset(10,48), Size=UDim2.new(1,-20,1,-58), BackgroundColor3=Theme.Deep,
				BackgroundTransparency=0.12, BorderSizePixel=0, ClipsDescendants=true, Parent=holder,
			})
			corner(stage, 10)
			stroke(stage, Theme.Stroke, 1, 0.25)
		
			local viewport = New("ViewportFrame", {
				Size=UDim2.fromScale(1,1), BackgroundTransparency=1, Ambient=Color3.fromRGB(175,175,195),
				LightColor=Color3.fromRGB(255,255,255), LightDirection=Vector3.new(-1,-1,-1), Parent=stage,
			})
			local world = Instance.new("WorldModel")
			world.Name = "preview_world"
			world.Parent = viewport
			local cam = Instance.new("Camera")
			cam.FieldOfView = 42
			cam.Parent = viewport
			viewport.CurrentCamera = cam
		
			local overlay = New("Frame", { Size=UDim2.fromScale(1,1), BackgroundTransparency=1, ZIndex=5, Parent=stage })
			local box = New("Frame", { AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromScale(0.5,0.52), Size=UDim2.fromScale(0.40,0.62), BackgroundTransparency=1, ZIndex=6, Parent=overlay })
			local boxStroke = stroke(box, Theme.Bad, 2)
			corner(box, 4)
			local glow = New("Frame", { Size=UDim2.new(1,6,1,6), Position=UDim2.fromOffset(-3,-3), BackgroundTransparency=1, ZIndex=5, Parent=box })
			local glowStroke = stroke(glow, Theme.Bad, 4, 0.65)
			corner(glow, 6)
		
			local cornerBars = {}
			for _, def in ipairs(BARS) do
				local b = New("Frame", { Position=def[1], Size=def[2], AnchorPoint=def[3], BorderSizePixel=0, BackgroundColor3=Theme.Bad, ZIndex=8, Parent=box })
				corner(b,1)
				table.insert(cornerBars,b)
			end
			local namePlate = New("Frame", { AnchorPoint=Vector2.new(0.5,1), Position=UDim2.new(0.5,0,0,-7), Size=UDim2.fromOffset(10,18), AutomaticSize=Enum.AutomaticSize.X, BackgroundColor3=Theme.Bg, BackgroundTransparency=0.08, BorderSizePixel=0, ZIndex=9, Parent=box })
			corner(namePlate,5)
			local nameStroke = stroke(namePlate, Theme.Bad, 1, 0.25)
			padding(namePlate,0,0,7,7)
			local nameText = New("TextLabel", { Size=UDim2.new(0,0,1,0), AutomaticSize=Enum.AutomaticSize.X, BackgroundTransparency=1, Font=FSB, TextSize=10, TextColor3=Theme.Text, Text=safePlayerLabel(LP), ZIndex=10, Parent=namePlate })
			local infoText = New("TextLabel", { AnchorPoint=Vector2.new(0.5,0), Position=UDim2.new(0.5,0,1,5), Size=UDim2.fromOffset(110,13), BackgroundTransparency=1, Font=FM, TextSize=9, TextColor3=Theme.Sub, Text="42 st", ZIndex=9, Parent=box })
			local toolText = New("TextLabel", { AnchorPoint=Vector2.new(0.5,0), Position=UDim2.new(0.5,0,1,18), Size=UDim2.fromOffset(140,13), BackgroundTransparency=1, Font=FM, TextSize=9, TextColor3=Theme.Sub, Text="weapon", ZIndex=9, Parent=box })
			local hpBg = New("Frame", { Position=UDim2.new(0,-8,0,0), Size=UDim2.new(0,3,1,0), BackgroundColor3=Theme.Bg, BorderSizePixel=0, ZIndex=8, Parent=box })
			corner(hpBg,2)
			local hp = New("Frame", { AnchorPoint=Vector2.new(0,1), Position=UDim2.new(0,0,1,0), Size=UDim2.fromScale(1,0.74), BackgroundColor3=Theme.Good, BorderSizePixel=0, ZIndex=9, Parent=hpBg })
			corner(hp,2)
			local hpTxt = New("TextLabel", { AnchorPoint=Vector2.new(1,1), Position=UDim2.new(0,-3,0.26,0), Size=UDim2.fromOffset(28,12), BackgroundTransparency=1, Font=FSB, TextSize=9, TextColor3=Theme.Text, Text="74", TextXAlignment=Enum.TextXAlignment.Right, ZIndex=9, Parent=hpBg })
		
			local tracer = New("Frame", { AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromScale(0.5,0.84), Size=UDim2.fromOffset(1,70), BackgroundColor3=Theme.Bad, BorderSizePixel=0, ZIndex=7, Parent=overlay })
		
			local sk = {}
			local function skLine(a,b)
				local d = b-a
				local f = New("Frame", { AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromScale((a.X+b.X)/2,(a.Y+b.Y)/2), Size=UDim2.new(d.Magnitude,0,0,1), BackgroundColor3=Theme.Bad, BorderSizePixel=0, Rotation=math.deg(math.atan2(d.Y,d.X)), Visible=false, ZIndex=8, Parent=overlay })
				table.insert(sk,f)
			end
			local pts = { head=Vector2.new(.5,.30), neck=Vector2.new(.5,.39), hip=Vector2.new(.5,.58), lh=Vector2.new(.36,.43), rh=Vector2.new(.64,.43), le=Vector2.new(.31,.55), re=Vector2.new(.69,.55), lf=Vector2.new(.43,.78), rf=Vector2.new(.57,.78) }
			skLine(pts.head,pts.neck); skLine(pts.neck,pts.hip); skLine(pts.neck,pts.lh); skLine(pts.neck,pts.rh); skLine(pts.lh,pts.le); skLine(pts.rh,pts.re); skLine(pts.hip,pts.lf); skLine(pts.hip,pts.rf)
		
			local clone, cloneSource, originalParts, cage = nil, nil, {}, {}
			local function clearClone()
				for _,e in ipairs(cage) do if e then e:Destroy() end end
				table.clear(cage)
				table.clear(originalParts)
				if clone then clone:Destroy() clone=nil end
			end
			local function edge(cf,size)
				local p=Instance.new("Part")
				p.Anchored=true; p.CanCollide=false; p.CanQuery=false; p.CanTouch=false; p.Material=Enum.Material.Neon
				p.Size=size; p.CFrame=cf; p.Color=Theme.Bad; p.Parent=world; table.insert(cage,p)
			end
			local function buildCage(cf,sz)
				for _,e in ipairs(cage) do if e then e:Destroy() end end; table.clear(cage)
				local t=.045; local hx,hy,hz=sz.X/2,sz.Y/2,sz.Z/2
				for _,y in ipairs({-hy,hy}) do for _,z in ipairs({-hz,hz}) do edge(cf*CFrame.new(0,y,z),Vector3.new(sz.X,t,t)) end end
				for _,x in ipairs({-hx,hx}) do for _,z in ipairs({-hz,hz}) do edge(cf*CFrame.new(x,0,z),Vector3.new(t,sz.Y,t)) end end
				for _,x in ipairs({-hx,hx}) do for _,y in ipairs({-hy,hy}) do edge(cf*CFrame.new(x,y,0),Vector3.new(t,t,sz.Z)) end end
			end
			local function rebuild()
				clearClone()
				local ch=LP.Character
				if not ch then return end
				cloneSource=ch
				local old=ch.Archivable; ch.Archivable=true
				local ok,c=pcall(function() return ch:Clone() end)
				ch.Archivable=old
				if not ok or not c then return end
				clone=c; clone.Name="avatar_preview"
				for _,d in ipairs(clone:GetDescendants()) do
					if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") then d:Destroy()
					elseif d:IsA("BasePart") then
						d.Anchored=true; d.CanCollide=false; d.CanTouch=false; d.CanQuery=false
						d.Transparency=(d.Name=="HumanoidRootPart") and 1 or 0
						d.LocalTransparencyModifier=0
						originalParts[d]={Color=d.Color,Material=d.Material,Transparency=d.Transparency}
					elseif d:IsA("Humanoid") then d.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None end
				end
				clone.Parent=world
				local cf,sz=clone:GetBoundingBox()
				clone:PivotTo(CFrame.new(-cf.Position)*clone:GetPivot())
				cf,sz=clone:GetBoundingBox()
				buildCage(cf,sz+Vector3.new(.12,.12,.12))
				local center=cf.Position+Vector3.new(0,sz.Y*.03,0)
				local dist=math.max(sz.Y*1.55,7.4)
				cam.CFrame=CFrame.lookAt(center+Vector3.new(0,sz.Y*.02,dist),center)
			end
			rebuild()
		
			local spin=0
			task.spawn(function()
				while holder.Parent do
					local panel = holder.Parent and holder.Parent.Parent
					if panel and not panel.Visible then task.wait(0.2) continue end
					if LP.Character ~= cloneSource then rebuild() end
					local ef=ById.esp
					viewport.Visible = not (streamerActive() and O("streamer", "avatar"))
					if ef then
						local col=OC("esp", (O("esp","vis") and not O("esp","pocc")) and "cVis" or "cEnemy")
						box.Visible=O("esp","box") or O("esp","name") or O("esp","dist") or O("esp","hp") or O("esp","tool")
						local style=O("esp","style")
						local corners=O("esp","box") and style~="Полная"
						for _,b in ipairs(cornerBars) do b.Visible=corners; b.BackgroundColor3=col end
						boxStroke.Enabled=O("esp","box") and style~="Углы"
						boxStroke.Color=col; boxStroke.Thickness=O("esp","thick")
						glow.Visible=O("esp","box"); glowStroke.Color=col
						namePlate.Visible=O("esp","name"); nameStroke.Color=col; nameText.Text=safePlayerLabel(LP)
						infoText.Visible=O("esp","dist"); infoText.Text=tostring(O("esp","pdist")).." st"
						local tool=LP.Character and LP.Character:FindFirstChildOfClass("Tool")
						toolText.Visible=O("esp","tool"); toolText.Text=(tool and tool.Name) or "weapon"
						hpBg.Visible=O("esp","hp")
						local ratio=math.clamp(O("esp","php")/100,0.01,1)
						hp.Size=UDim2.new(1,0,ratio,0); hp.BackgroundColor3=Theme.Bad:Lerp(Theme.Good,ratio)
						hpTxt.Visible=O("esp","hptxt") and O("esp","hp"); hpTxt.Text=tostring(math.floor(O("esp","php"))); hpTxt.Position=UDim2.new(0,-3,1-ratio,0)
						tracer.Visible=O("esp","tracer"); tracer.BackgroundColor3=col
						for _,l in ipairs(sk) do l.Visible=O("esp","skel"); l.BackgroundColor3=col end
						for _,e in ipairs(cage) do e.Transparency=O("esp","box3d") and 0.12 or 1; e.Color=col end
						for part,orig in pairs(originalParts) do
							if part and part.Parent then
								if O("esp","chams") then part.Color=col:Lerp(orig.Color,.28); part.Material=Enum.Material.ForceField; part.Transparency=orig.Transparency
								else part.Color=orig.Color; part.Material=orig.Material; part.Transparency=orig.Transparency end
							end
						end
					end
					if clone then spin += 0.00025 * O("esp","pspin"); clone:PivotTo(CFrame.Angles(0,spin,0)*CFrame.new(0,0,0)) end
					task.wait(math.max(perfEspInterval(), 0.05))
				end
				clearClone()
			end)
		end
		
		local function buildHotkeyEditorPanel(inner)
			New("TextLabel", { Size=UDim2.new(1,0,0,28), BackgroundTransparency=1, Font=FM, TextSize=10, TextColor3=Theme.Dim,
				TextWrapped=true, TextXAlignment=Enum.TextXAlignment.Left, Text="Нажми на клавишу справа от функции. ESC очищает бинд.", Parent=inner })
			cButton(inner, "Сбросить все бинды", "danger", function() resetBinds() end)
			for _, ff in ipairs(Features) do
				if not ff.NoToggle and ff.Id ~= "hotkeys" then
					local feature = ff
					cKeybind(inner, feature.Name, function() return DB[feature.Id].key end, function(v)
						DB[feature.Id].key = v
						markDirty()
						if feature._row then feature._row.refresh() end
					end)
				end
			end
		end
		
		-- какие настройки видно в обычном режиме; остальные прячутся под галку
		-- «расширенные настройки», чтобы новичка не заваливало опциями
		local BASIC = {
			aimbot     = { fov = true, smooth = true, part = true, team = true, wall = true, circle = true },
			silentaim  = { fov = true, predict = true, part = true, team = true, wall = true, compat = true },
			trigger    = { delay = true, gap = true, team = true, needtool = true, auto = true },
			rapidfire  = { gap = true, key = true, method = true },
			norecoil   = { power = true },
			weaponbridge = { learn = true, profile = true, confidence = true },
			vmfix      = { power = true },
			hitbox     = { size = true, team = true },
			antiaim    = { mode = true, jit = true, spd = true },
			spinbot    = { mode = true, spd = true },
			speed      = { val = true, shift = true, jump = true, air = true, noslide = true },
			jump       = { val = true, grav = true },
			infjump    = { hold = true },
			bhop       = { need = true, accel = true, max = true },
			fly        = { spd = true, vspd = true },
			noclip     = {},
			ghost      = { step = true, gap = true, vert = true },
			thirdperson= { dist = true, force = true, body = true, hidegun = true },
			fullbright = { bright = true, time = true, fog = true },
			esp        = { box = true, box3d = true, off = true, name = true, dist = true, hp = true, chams = true, skel = true,
			               tracer = true, tc = true, maxd = true, cEnemy = true, cAlly = true },
			radar      = { range = true, size = true, team = true },
			targethud  = { hp = true, dist = true, tool = true },
			streamer   = { alias = true, self = true, players = true, server = true },
			fovchange  = { fov = true },
			crosshair  = { style = true, size = true, col = true },
			tracers    = { src = true, col = true, life = true, thick = true, auto = true, count = true },
			nofog      = {},
			world      = { sat = true, con = true },
			watermark  = { fps = true, ping = true, time = true, user = true, profile = true },
			optimizer  = { profile = true, target = true },
			threats    = { count = true, range = true, hp = true, tool = true },
			quickbar   = { count = true, labels = true, onlyfav = true },
			hudedit    = { labels = true, pulse = true },
			cleanhud   = { menu = true },
			notifications = { toast = true, duration = true },
			placeprofiles = { autoload = true, autosave = true },
			layoutpresets = { preset = true },
			bindlist   = { only = true },
		}
		
		local function optVisible(fid, opt)
			-- все настройки показываются всегда
			if true then return true end
			if UICFG.Advanced then return true end
			if opt.Type == "Button" then return true end
			local t = BASIC[fid]
			if not t then return true end
			return t[opt.Id] == true
		end
		
		local function buildOptions(f, inner)
		
		
			if f.Custom == "configs" then
				buildConfigPanel(inner)
				return
			end
			if f.Custom == "info" then
				buildInfoPanel(inner)
				return
			end
			if f.Custom == "hotkeys" then
				buildHotkeyEditorPanel(inner)
				return
			end
			if f.Custom == "weaponlab" then
				buildWeaponLabPanel(inner)
				return
			end
			if f.Custom == "compatdiag" then
				buildCompatibilityPanel(inner)
				return
			end
			if f.Custom == "notifcenter" then
				buildNotificationCenterPanel(inner)
				return
			end
			if f.Custom == "sessiondash" then
				buildSessionDashboardPanel(inner)
				return
			end
			if f.Id == "esp" then
				buildESPPreviewPanel(inner)
			end
			if not f.NoToggle then
				New("TextLabel", {
					Size = UDim2.new(1, 0, 0, 15), BackgroundTransparency = 1, Font = FB, TextSize = 10,
					TextColor3 = Theme.Dim, TextXAlignment = Enum.TextXAlignment.Left, Text = "БИНД", Parent = inner,
				})
				cKeybind(inner, "Клавиша", function() return DB[f.Id].key end, function(v)
					DB[f.Id].key = v
					markDirty()
					if f._row then f._row.refresh() end
				end)
				cDropdown(inner, { Name = "Режим", List = MODES }, function() return DB[f.Id].mode end, function(v)
					DB[f.Id].mode = v
					syncState(f)
					markDirty()
				end)
			end
			if #f.Options > 0 then
				New("TextLabel", {
					Size = UDim2.new(1, 0, 0, 15), BackgroundTransparency = 1, Font = FB, TextSize = 10,
					TextColor3 = Theme.Dim, TextXAlignment = Enum.TextXAlignment.Left,
					Text = f.NoToggle and "ПАРАМЕТРЫ" or "НАСТРОЙКИ", Parent = inner,
				})
			end
			for _, opt in ipairs(f.Options) do
				if not optVisible(f.Id, opt) then continue end
				local get = function() return DB[f.Id].o[opt.Id] end
				local set = function(v) setOpt(f, opt, v) end
				if opt.Type == "Toggle" then cToggle(inner, opt.Name, get, set)
				elseif opt.Type == "Slider" then cSlider(inner, opt, get, set)
				elseif opt.Type == "Dropdown" then cDropdown(inner, opt, get, set)
				elseif opt.Type == "Color" then cColor(inner, opt, get, set)
				elseif opt.Type == "Keybind" then cKeybind(inner, opt.Name, get, set)
				elseif opt.Type == "MenuKey" then
					cKeybind(inner, opt.Name, function() return UICFG.MenuKey end, function(v)
						UICFG.MenuKey = v
						markDirty()
					end)
				elseif opt.Type == "Text" then
					New("TextLabel", {
						Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1, Font = FM, TextSize = 10,
						TextColor3 = Theme.Dim, TextXAlignment = Enum.TextXAlignment.Left, Text = opt.Name, Parent = inner,
					})
					local box = cTextBox(inner, opt.Placeholder or "", function(v)
						set(v)
					end)
					box.Text = tostring(get() or "")
					box.FocusLost:Connect(function() set(box.Text) end)
				elseif opt.Type == "Label" then
					local lbl = New("TextLabel", {
						Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
						Font = FM, TextSize = 10, TextColor3 = Theme.Dim, TextXAlignment = Enum.TextXAlignment.Left,
						TextWrapped = true, Text = opt.Name or "", Parent = inner,
					})
				elseif opt.Type == "Button" then
					cButton(inner, opt.Name, opt.Style, opt.Run)
				end
			end
		end
		
		local function makeCard(parent, title)
			local card = New("Frame", {
				Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Theme.Card,
				BorderSizePixel = 0, Parent = parent,
			})
			corner(card, 12)
			stroke(card, Theme.Stroke, 1)
			padding(card, 11, 11, 11, 11)
			list(card, 4)
			local h = New("Frame", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, LayoutOrder = 0, Parent = card })
			local d = New("Frame", {
				Position = UDim2.new(0, 2, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(4, 11),
				BorderSizePixel = 0, Parent = h,
			})
			corner(d, 2)
			accent(d, "BackgroundColor3")
			New("TextLabel", {
				Position = UDim2.new(0, 14, 0, 0), Size = UDim2.new(1, -14, 1, 0), BackgroundTransparency = 1,
				Font = FB, TextSize = 12, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
				Text = title, Parent = h,
			})
			return card
		end
		
		local openPanels = {}
		local rowPanels = {}
		
		local function makeRow(card, f, idx)
			local row = New("Frame", {
				Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = Theme.Row, BackgroundTransparency = 1,
				BorderSizePixel = 0, LayoutOrder = idx * 10, Parent = card,
			})
			corner(row, 8)
			local name = New("TextLabel", {
				Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.new(1, -124, 0, 13),
				BackgroundTransparency = 1, Font = FM, TextSize = 12, TextColor3 = Theme.Sub,
				TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = f.Name, Parent = row,
			})
			local badge = New("Frame", {
				AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -74, 0.5, 0), Size = UDim2.fromOffset(46, 17),
				BackgroundColor3 = Theme.Deep, BorderSizePixel = 0, Visible = false, Parent = row,
			})
			corner(badge, 5)
			local badgeS = stroke(badge, Theme.Stroke, 1)
			local badgeT = New("TextLabel", {
				BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = FSB, TextSize = 9,
				TextColor3 = Theme.Sub, Text = "", Parent = badge,
			})
		
			-- кнопка раскрытия настроек
			local chev = New("Frame", {
				AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -46, 0.5, 0), Size = UDim2.fromOffset(22, 22),
				BackgroundColor3 = Theme.Deep, BackgroundTransparency = 0.35, BorderSizePixel = 0, Parent = row,
			})
			corner(chev, 6)
			local chevT = New("TextLabel", {
				BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = FB, TextSize = 9,
				TextColor3 = Theme.Dim, Text = "v", Parent = chev,
			})
			local chevB = New("TextButton", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = "", Parent = chev })
		
			local pill, knob, pillS
			local fav, favT
			if not f.NoToggle then
				fav = New("Frame", { AnchorPoint=Vector2.new(1,.5), Position=UDim2.new(1,-126,.5,0), Size=UDim2.fromOffset(22,22),
					BackgroundColor3=Theme.Deep, BackgroundTransparency=.45, BorderSizePixel=0, Parent=row })
				corner(fav,6)
				favT = New("TextLabel", { BackgroundTransparency=1, Size=UDim2.fromScale(1,1), Font=FB, TextSize=12, TextColor3=Theme.Dim, Text="☆", Parent=fav })
				local favB = New("TextButton", { BackgroundTransparency=1, Size=UDim2.fromScale(1,1), Text="", Parent=fav })
				favB.MouseButton1Click:Connect(function()
					UICFG.Favorites = type(UICFG.Favorites) == "table" and UICFG.Favorites or {}
					if UICFG.Favorites[f.Id] then UICFG.Favorites[f.Id] = nil else UICFG.Favorites[f.Id] = true end
					markDirty(); if f._row then f._row.refresh() end; if applyFeatureFilter then applyFeatureFilter() end
				end)
				name.Size = UDim2.new(1, -180, 0, 13)
				pill = New("Frame", {
					AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(32, 17),
					BackgroundColor3 = Theme.Deep, BorderSizePixel = 0, Parent = row,
				})
				round1(pill)
				pillS = stroke(pill, Theme.Stroke, 1)
				knob = New("Frame", {
					AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0), Size = UDim2.fromOffset(11, 11),
					BackgroundColor3 = Theme.Dim, BorderSizePixel = 0, Parent = pill,
				})
				round1(knob)
			else
				chev.Position = UDim2.new(1, -8, 0.5, 0)
				name.Size = UDim2.new(1, -90, 0, 13)
			end
		
			-- панель настроек под строкой
			local panel = New("ScrollingFrame", {
				Size = UDim2.new(1, 0, 0, 0), BackgroundColor3 = Theme.Deep, BackgroundTransparency = 0.2,
				BorderSizePixel = 0, ClipsDescendants = true, Visible = false, LayoutOrder = idx * 10 + 1, Parent = card,
				ScrollingEnabled = true, ScrollingDirection = Enum.ScrollingDirection.Y,
				ElasticBehavior = Enum.ElasticBehavior.Always, CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 3,
				ScrollBarImageColor3 = Color3.fromRGB(120, 80, 200), ScrollBarImageTransparency = 0.3,
			})
			corner(panel, 8)
			local accentEdge = New("Frame", {
				Size = UDim2.new(0, 2, 1, -12), Position = UDim2.new(0, 0, 0, 6), BorderSizePixel = 0, Parent = panel,
			})
			corner(accentEdge, 1)
			accent(accentEdge, "BackgroundColor3")
			local inner = New("Frame", {
				Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = panel,
			})
			padding(inner, 9, 9, 9, 9)
			local lay = list(inner, 5)
		
			local built, expanded = false, false
			local function contentH() return lay.AbsoluteContentSize.Y + 18 end
		
			lay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
				if expanded then
					local maxH = (f.Id == "esp") and (isMobile and 360 or 455) or (((f.Custom == "hotkeys") or (f.Custom == "notifcenter")) and (isMobile and 300 or 360) or (isMobile and 240 or 220))
					panel.Size = UDim2.new(1, 0, 0, math.min(contentH(), maxH))
				end
			end)
		
			local function setExpanded(state)
				if state == expanded then return end
				expanded = state
				if state then
					if not built then buildOptions(f, inner) built = true end
					panel.Visible = true
					panel.Size = UDim2.new(1, 0, 0, 0)
					task.defer(function()
						if expanded then
							local maxH = (f.Id == "esp") and (isMobile and 360 or 455) or (((f.Custom == "hotkeys") or (f.Custom == "notifcenter")) and (isMobile and 300 or 360) or (isMobile and 240 or 220))
							local h = math.min(contentH(), maxH)
							tw(panel, 0.3, { Size = UDim2.new(1, 0, 0, h) })
						end
					end)
					tw(chevT, 0.25, { Rotation = 180, TextColor3 = Theme.Accent })
					tw(chev, 0.2, { BackgroundTransparency = 0 })
					openPanels[f.Id] = true
				else
					tw(panel, 0.22, { Size = UDim2.new(1, 0, 0, 0) })
					tw(chevT, 0.25, { Rotation = 0, TextColor3 = Theme.Dim })
					tw(chev, 0.2, { BackgroundTransparency = 0.35 })
					task.delay(0.24, function() if not expanded then panel.Visible = false end end)
					openPanels[f.Id] = nil
				end
			end
		
			local function refresh()
				local d = DB[f.Id]
				if pill then
					local on = d.on
					tw(pill, 0.2, { BackgroundColor3 = on and Theme.Accent or Theme.Deep })
					tw(knob, 0.24, { Position = UDim2.new(0, on and 18 or 3, 0.5, 0),
						BackgroundColor3 = on and Color3.new(1, 1, 1) or Theme.Dim })
					pillS.Transparency = on and 1 or 0
					name.TextColor3 = f._active and Theme.Text or (on and Theme.Sub or Theme.Sub)
					name.Font = f._active and FSB or FM
				end
				if favT then
					local isFav = type(UICFG.Favorites) == "table" and UICFG.Favorites[f.Id] == true
					favT.Text = isFav and "★" or "☆"
					favT.TextColor3 = isFav and Theme.Accent or Theme.Dim
				end
				local show = (d.key ~= nil and d.key ~= "")
				badge.Visible = show
				if show then
					badgeT.Text = keyLabel(d.key) .. (d.mode == "Hold" and " ·H" or (d.mode == "Always" and " ·A" or ""))
					badgeT.TextColor3 = f._active and Theme.Accent or Theme.Sub
					badgeS.Color = f._active and Theme.Accent or Theme.Stroke
					badgeS.Transparency = f._active and 0.35 or 0
				end
			end
		
			local hover = New("TextButton", { BackgroundTransparency = 1, Size = UDim2.new(1, f.NoToggle and -46 or -152, 1, 0), Text = "", Parent = row })
			hover.MouseEnter:Connect(function() tw(row, 0.13, { BackgroundTransparency = 0.55 }) end)
			hover.MouseLeave:Connect(function() tw(row, 0.18, { BackgroundTransparency = 1 }) end)
			hover.MouseButton1Click:Connect(function()
				if f.NoToggle then
					setExpanded(not expanded)
				else
					setOn(f.Id, not DB[f.Id].on)
					if DB[f.Id].on then
						if UICFG.AutoExpand then setExpanded(true) end
					else
						setExpanded(false)
					end
				end
			end)
			hover.MouseButton2Click:Connect(function() setExpanded(not expanded) end)
			chevB.MouseButton1Click:Connect(function() setExpanded(not expanded) end)
			if pill then
				local pb = New("TextButton", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = "", Parent = pill })
				pb.MouseButton1Click:Connect(function()
					setOn(f.Id, not DB[f.Id].on)
					if DB[f.Id].on then
						if UICFG.AutoExpand then setExpanded(true) end
					else
						setExpanded(false)
					end
				end)
				pb.MouseButton2Click:Connect(function() setExpanded(not expanded) end)
			end
		
			table.insert(rowPanels, function()
				setExpanded(false)
				if built then
					for _, c in ipairs(inner:GetChildren()) do
						if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then c:Destroy() end
					end
					built = false
				end
			end)
		
			f._row = {
				refresh = refresh, expand = setExpanded, row = row, card = card,
				setVisible = function(v) if not v and expanded then setExpanded(false) end row.Visible = v end,
			}
			refresh()
			return row
		end
		
		function refreshRows()
			for _, f in ipairs(Features) do
				if f._row then f._row.refresh() end
			end
		end
		
		-- после загрузки конфига панели пересобираются, чтобы показывать новые значения
		function resetPanels()
			for _, fn in ipairs(rowPanels) do pcall(fn) end
		end
		
		-- сборка страниц
		for _, t in ipairs(TABS) do
			local made, order = { {}, {} }, { 0, 0 }
			for _, f in ipairs(Features) do
				if f.Tab == t.id then
					local col = f.Col or 1
					local g = f.Group or "Общее"
					if not made[col][g] then
						order[col] += 1
						made[col][g] = { card = makeCard(pages[t.id].cols[col], g), n = 0 }
						made[col][g].card.LayoutOrder = order[col]
					end
					local e = made[col][g]
					e.n += 1
					makeRow(e.card, f, e.n)
				end
			end
		end
		
		local function searchFold(value)
			local out = {}
			local ok = pcall(function()
				for _, cp in utf8.codes(tostring(value or "")) do
					if cp >= 65 and cp <= 90 then cp += 32
					elseif cp >= 1040 and cp <= 1071 then cp += 32
					elseif cp == 1025 then cp = 1105 end
					table.insert(out, utf8.char(cp))
				end
			end)
			return ok and table.concat(out) or string.lower(tostring(value or ""))
		end
		
		updateGroupFilter = function()
			local seen = {}
			searchGroups = { "Все" }
			for _, f in ipairs(Features) do
				if f.Tab == activeTab and not seen[f.Group or "Общее"] then
					seen[f.Group or "Общее"] = true
					table.insert(searchGroups, f.Group or "Общее")
				end
			end
			searchGroup, searchGroupIndex = "Все", 1
			if UI.searchGroup then UI.searchGroup.Text = "Все группы" end
		end
		
		applyFeatureFilter = function()
			local q = searchFold(UI.searchBox and UI.searchBox.Text or "")
			local cards, matched = {}, 0
			for _, f in ipairs(Features) do
				if f._row then
					local inTab = f.Tab == activeTab
					local hay = searchFold((f.Name or "") .. " " .. (f.Desc or "") .. " " .. (f.Group or "") .. " " .. (f.Id or ""))
					local textOk = q == "" or hay:find(q, 1, true) ~= nil
					local favOk = not searchFavOnly or (type(UICFG.Favorites) == "table" and UICFG.Favorites[f.Id] == true)
					local groupOk = searchGroup == "Все" or (f.Group or "Общее") == searchGroup
					local visible = inTab and textOk and favOk and groupOk
					f._row.setVisible(visible)
					cards[f._row.card] = cards[f._row.card] or false
					if visible then cards[f._row.card] = true; matched += 1 end
				end
			end
			for card, visible in pairs(cards) do card.Visible = visible end
			if UI.searchCount then UI.searchCount.Text = tostring(matched) .. " шт." end
		end
		
		--============================================================ ВКЛАДКИ =======
		local function makeIcon(kind, parent)
			local h = New("Frame", {
				Size = UDim2.fromOffset(18, 18), Position = UDim2.new(0, 15, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5), BackgroundTransparency = 1, Parent = parent,
			})
			local parts = {}
			if kind == "Main" then
				local d = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(11, 11), Rotation = 45, BackgroundTransparency = 1, Parent = h })
				corner(d, 2)
				local s = New("UIStroke", { Thickness = 1.6, Parent = d })
				local dot = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(4, 4), BorderSizePixel = 0, Parent = h })
				corner(dot, 2)
				parts = { { s, "Color" }, { dot, "BackgroundColor3" } }
			elseif kind == "Movement" then
				for i = 0, 2 do
					local b = New("Frame", { Position = UDim2.new(0, 0, 0.5, (i - 1) * 5), AnchorPoint = Vector2.new(0, 0.5),
						Size = UDim2.fromOffset(16 - i * 4, 2), BorderSizePixel = 0, Parent = h })
					corner(b, 1)
					table.insert(parts, { b, "BackgroundColor3" })
				end
			elseif kind == "Visuals" then
				local r = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(16, 12), BackgroundTransparency = 1, Parent = h })
				round1(r)
				local s = New("UIStroke", { Thickness = 1.6, Parent = r })
				local dot = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(5, 5), BorderSizePixel = 0, Parent = h })
				round1(dot)
				parts = { { s, "Color" }, { dot, "BackgroundColor3" } }
			elseif kind == "Info" then
				local ring = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(15, 15), BackgroundTransparency = 1, Parent = h })
				round1(ring)
				local s1 = New("UIStroke", { Thickness = 1.6, Parent = ring })
				local bar = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 2),
					Size = UDim2.fromOffset(2, 6), BorderSizePixel = 0, Parent = h })
				corner(bar, 1)
				local dot = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -4),
					Size = UDim2.fromOffset(2, 2), BorderSizePixel = 0, Parent = h })
				corner(dot, 1)
				parts = { { s1, "Color" }, { bar, "BackgroundColor3" }, { dot, "BackgroundColor3" } }
			else
				local sq = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(14, 14), Rotation = 45, BackgroundTransparency = 1, Parent = h })
				corner(sq, 4)
				local s = New("UIStroke", { Thickness = 1.6, Parent = sq })
				local r = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(6, 6), BackgroundTransparency = 1, Parent = h })
				round1(r)
				local s2 = New("UIStroke", { Thickness = 1.6, Parent = r })
				parts = { { s, "Color" }, { s2, "Color" } }
			end
			return parts
		end
		
		local tabBtns = {}
		activeTab = "Main"
		
		local function selectTab(id)
			activeTab = id
			if updateGroupFilter then updateGroupFilter() end
			for tid, b in pairs(tabBtns) do
				local on = (tid == id)
				tw(b.f, 0.2, { BackgroundTransparency = on and 0 or 1 })
				tw(b.l, 0.2, { TextColor3 = on and Theme.Text or Theme.Sub })
				tw(b.bar, 0.28, { Size = UDim2.new(0, 3, 0, on and 18 or 0) }, EASE_SPRING)
				b.l.Font = on and FSB or FM
				for _, p in ipairs(b.icon) do p[1][p[2]] = on and Theme.Accent or Theme.Dim end
			end
			for _, t in ipairs(TABS) do
				local pg = pages[t.id]
				pg.frame.Visible = (t.id == id)
				if t.id == id then
					UI.hTitle.Text = t.id
					UI.hSub.Text = t.sub
					UI.hTitle.Position = UDim2.new(0, 18, 0, 18)
					UI.hSub.Position = UDim2.new(0, 18, 0, 40)
					tw(UI.hTitle, 0.32, { Position = UDim2.new(0, 24, 0, 18) })
					tw(UI.hSub, 0.38, { Position = UDim2.new(0, 24, 0, 40) })
					pg.frame.GroupTransparency = 1
					tw(pg.frame, 0.26, { GroupTransparency = 0 })
					for i, col in ipairs(pg.cols) do
						col.Position = UDim2.new(0.5 * (i - 1), (i - 1) * 9, 0, 12)
						tw(col, 0.34 + i * 0.05, { Position = UDim2.new(0.5 * (i - 1), (i - 1) * 9, 0, 0) })
					end
				else
					pg.frame.GroupTransparency = 0
				end
			end
			if applyFeatureFilter then task.defer(applyFeatureFilter) end
		end
		
		for i, t in ipairs(TABS) do
			local f = New("Frame", {
				Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = Theme.Card, BackgroundTransparency = 1,
				BorderSizePixel = 0, LayoutOrder = i, Parent = UI.tabHolder,
			})
			corner(f, 9)
			local bar = New("Frame", {
				Position = UDim2.new(0, -1, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.new(0, 3, 0, 0),
				BorderSizePixel = 0, Parent = f,
			})
			corner(bar, 2)
			accent(bar, "BackgroundColor3")
			local icon = makeIcon(t.id, f)
			local l = New("TextLabel", {
				Position = UDim2.new(0, 43, 0, 0), Size = UDim2.new(1, -50, 1, 0), BackgroundTransparency = 1,
				Font = FM, TextSize = 12, TextColor3 = Theme.Sub, TextXAlignment = Enum.TextXAlignment.Left,
				Text = t.id, Parent = f,
			})
			local b = New("TextButton", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = "", Parent = f })
			b.MouseEnter:Connect(function() if activeTab ~= t.id then tw(f, 0.13, { BackgroundTransparency = 0.6 }) end end)
			b.MouseLeave:Connect(function() if activeTab ~= t.id then tw(f, 0.18, { BackgroundTransparency = 1 }) end end)
			b.MouseButton1Click:Connect(function() if activeTab ~= t.id then selectTab(t.id) end end)
			tabBtns[t.id] = { f = f, l = l, bar = bar, icon = icon }
		end
		
		-- command palette -----------------------------------------------------
		local commandOpen = false
		local commandMatches = {}
		UI.commandDim = New("TextButton", { Size=UDim2.fromScale(1,1), BackgroundColor3=Color3.new(0,0,0), BackgroundTransparency=.48,
			Text="", AutoButtonColor=false, Visible=false, ZIndex=90, Parent=UI.win })
		UI.command = New("CanvasGroup", { AnchorPoint=Vector2.new(.5,.5), Position=UDim2.fromScale(.5,.48), Size=UDim2.new(.78,0,.72,0),
			BackgroundColor3=Theme.Bg2, BorderSizePixel=0, GroupTransparency=0, Visible=false, ZIndex=100, Parent=UI.win })
		corner(UI.command,14); stroke(UI.command,Theme.Stroke,1.3)
		New("TextLabel", { Position=UDim2.fromOffset(18,13), Size=UDim2.new(1,-36,0,17), BackgroundTransparency=1, Font=FB, TextSize=13,
			TextColor3=Theme.Text, TextXAlignment=Enum.TextXAlignment.Left, Text="COMMAND PALETTE", ZIndex=102, Parent=UI.command })
		UI.commandBox = New("TextBox", { Position=UDim2.fromOffset(14,42), Size=UDim2.new(1,-28,0,36), BackgroundColor3=Theme.Deep, BackgroundTransparency=.08,
			BorderSizePixel=0, ClearTextOnFocus=false, Font=FM, TextSize=12, TextColor3=Theme.Text, PlaceholderColor3=Theme.Dim,
			PlaceholderText="Найти функцию, группу, ID или описание...", Text="", TextXAlignment=Enum.TextXAlignment.Left, ZIndex=102, Parent=UI.command })
		corner(UI.commandBox,9); stroke(UI.commandBox,Theme.Stroke,1); padding(UI.commandBox,0,0,12,12)
		UI.commandList = New("ScrollingFrame", { Position=UDim2.fromOffset(14,88), Size=UDim2.new(1,-28,1,-104), BackgroundTransparency=1, BorderSizePixel=0,
			CanvasSize=UDim2.new(), AutomaticCanvasSize=Enum.AutomaticSize.Y, ScrollBarThickness=3, ScrollBarImageColor3=Theme.Stroke, ZIndex=102, Parent=UI.command })
		list(UI.commandList,5)
		
		local function rebuildCommandPalette()
			for _, c in ipairs(UI.commandList:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
			table.clear(commandMatches)
			local q = searchFold(UI.commandBox.Text)
			local scored = {}
			for _, f in ipairs(Features) do
				local hay = searchFold((f.Name or "") .. " " .. (f.Group or "") .. " " .. (f.Tab or "") .. " " .. (f.Id or "") .. " " .. (f.Desc or ""))
				if q == "" or hay:find(q,1,true) then
					local score = 0
					if searchFold(f.Name or ""):find(q,1,true) == 1 then score += 5 end
					if type(UICFG.Favorites)=="table" and UICFG.Favorites[f.Id] then score += 2 end
					table.insert(scored,{f=f,score=score})
				end
			end
			table.sort(scored,function(a,b) if a.score==b.score then return a.f.Name<b.f.Name end return a.score>b.score end)
			for i,e in ipairs(scored) do
				if i>18 then break end
				local f=e.f; table.insert(commandMatches,f)
				local row=New("Frame",{Size=UDim2.new(1,-4,0,38),BackgroundColor3=Theme.Card,BackgroundTransparency=.32,BorderSizePixel=0,ZIndex=103,Parent=UI.commandList}); corner(row,8)
				New("TextLabel",{Position=UDim2.fromOffset(11,5),Size=UDim2.new(1,-92,0,14),BackgroundTransparency=1,Font=FSB,TextSize=11,TextColor3=Theme.Text,TextXAlignment=Enum.TextXAlignment.Left,Text=f.Name,ZIndex=104,Parent=row})
				New("TextLabel",{Position=UDim2.fromOffset(11,20),Size=UDim2.new(1,-92,0,12),BackgroundTransparency=1,Font=FM,TextSize=9,TextColor3=Theme.Dim,TextXAlignment=Enum.TextXAlignment.Left,Text=(f.Tab or "").."  ·  "..(f.Group or ""),ZIndex=104,Parent=row})
				local state=New("TextLabel",{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-10,.5,0),Size=UDim2.fromOffset(70,18),BackgroundTransparency=1,Font=FSB,TextSize=9,TextColor3=(not f.NoToggle and DB[f.Id].on) and Theme.Good or Theme.Sub,TextXAlignment=Enum.TextXAlignment.Right,Text=f.NoToggle and "OPEN" or (DB[f.Id].on and "ON" or "OFF"),ZIndex=104,Parent=row})
				local b=New("TextButton",{BackgroundTransparency=1,Size=UDim2.fromScale(1,1),Text="",ZIndex=105,Parent=row})
				b.MouseButton1Click:Connect(function()
					UI.searchBox.Text=""; searchFavOnly=false; UI.searchFav.Text="☆"; UI.searchFav.TextColor3=Theme.Dim
					selectTab(f.Tab); task.defer(function() if f._row then f._row.expand(true) end end); toggleCommandPalette(false)
				end)
				b.MouseButton2Click:Connect(function() if not f.NoToggle then setOn(f.Id,not DB[f.Id].on); state.Text=DB[f.Id].on and "ON" or "OFF"; state.TextColor3=DB[f.Id].on and Theme.Good or Theme.Sub end end)
			end
		end
		
		UI.commandBox:GetPropertyChangedSignal("Text"):Connect(rebuildCommandPalette)
		UI.commandDim.MouseButton1Click:Connect(function() if toggleCommandPalette then toggleCommandPalette(false) end end)
		toggleCommandPalette = function(state)
			if state == nil then state = not commandOpen end
			commandOpen = state
			UI.commandDim.Visible = state
			UI.command.Visible = state
			if state then
				UI.commandBox.Text = ""; rebuildCommandPalette(); task.defer(function() UI.commandBox:CaptureFocus() end)
			else
				UI.commandBox:ReleaseFocus()
			end
		end
		
		--=================================================== ПРИМЕНЕНИЕ НАСТРОЕК ====
		local menuOpen = false
		
		function applyUI()
			UI.scale.Scale = UICFG.Scale
			if UICFG.X == 0 and UICFG.Y == 0 then
				local vp = VP()
				UICFG.X = math.floor((vp.X - UICFG.W * UICFG.Scale) / 2)
				UICFG.Y = math.floor((vp.Y - UICFG.H * UICFG.Scale) / 2)
			end
			UI.win.Size = UDim2.fromOffset(UICFG.W, UICFG.H)
			UI.win.Position = UDim2.fromOffset(UICFG.X, UICFG.Y)
			UI.win.BackgroundTransparency = UICFG.Trans
			UI.top.BackgroundTransparency = UICFG.Trans * 0.6
			UI.side.BackgroundTransparency = UICFG.Trans * 0.6
			watermark.AnchorPoint = Vector2.new(0, 0)
			watermark.Position = UDim2.fromOffset(UICFG.WmX, UICFG.WmY)
			local vp = VP()
			if UICFG.FloatX < 0 or UICFG.FloatY < 0 then
				UICFG.FloatX = math.max(vp.X - 72, 8)
				UICFG.FloatY = math.max(vp.Y * 0.5 - 47, 8)
			end
			UICFG.FloatX = math.clamp(UICFG.FloatX, 8, math.max(vp.X - 60, 8))
			UICFG.FloatY = math.clamp(UICFG.FloatY, 8, math.max(vp.Y - 60, 8))
			if UI.floatDock then UI.floatDock.Position = UDim2.fromOffset(UICFG.FloatX, UICFG.FloatY) end
			if radarPanel and UICFG.RadarX >= 0 then radarPanel.Position = UDim2.fromOffset(UICFG.RadarX, UICFG.RadarY) end
			if targetHud and UICFG.TargetX >= 0 then targetHud.Position = UDim2.fromOffset(UICFG.TargetX, UICFG.TargetY) end
			if perfPanel and UICFG.PerfX >= 0 then perfPanel.Position = UDim2.fromOffset(UICFG.PerfX, UICFG.PerfY) end
			if threatPanel and UICFG.ThreatX >= 0 then threatPanel.Position = UDim2.fromOffset(UICFG.ThreatX, UICFG.ThreatY) end
			if UICFG.QuickX < 0 or UICFG.QuickY < 0 then UICFG.QuickX,UICFG.QuickY=math.max(vp.X*.5-155,8),math.max(vp.Y-52,8) end
			UICFG.QuickX=math.clamp(UICFG.QuickX,8,math.max(vp.X-310,8)); UICFG.QuickY=math.clamp(UICFG.QuickY,8,math.max(vp.Y-44,8))
			if quickBar then quickBar.Position=UDim2.fromOffset(UICFG.QuickX,UICFG.QuickY) end
			if UI.searchBox then
				local narrowSearch = UICFG.W < 700
				UI.searchGroup.Visible = not narrowSearch
				UI.cmdHint.Visible = not narrowSearch
				UI.searchCount.Visible = not narrowSearch
				UI.searchFav.Position = narrowSearch and UDim2.new(1,-7,.5,0) or UDim2.new(1,-70,.5,0)
				UI.searchBox.Size = narrowSearch and UDim2.new(1,-54,1,0) or UDim2.new(1,-314,1,0)
			end
			UI.fovStroke.Color = Theme.Accent
			if UI.cfgTxt then UI.cfgTxt.Text = Store.current or "default" end
			if blur then blur.Size = (menuOpen and UICFG.Blur) and 16 or 0 end
		end
		
		-- подгон окна под экран: на телефоне вьюпорт заметно меньше, чем базовые 812x548
		local function fitToViewport(force)
			local vp = VP()
			local maxW, maxH = vp.X - 16, vp.Y - 16
		
			if force then
				UICFG.W = math.clamp(math.floor(math.min(UICFG.W, maxW)), MINW, 1400)
				UICFG.H = math.clamp(math.floor(math.min(UICFG.H, maxH)), MINH, 1000)
			end
		
			local need = math.min(maxW / UICFG.W, maxH / UICFG.H, 1)
			if need < UICFG.Scale then
				UICFG.Scale = math.max(need, 0.45)
				if UI.scale then UI.scale.Scale = UICFG.Scale end
				local sf = ById.iface
				if sf then DB.iface.o.scale = math.floor(UICFG.Scale * 100) end
			end
		
			UICFG.X = math.clamp(UICFG.X, 0, math.max(vp.X - 80, 0))
			UICFG.Y = math.clamp(UICFG.Y, 0, math.max(vp.Y - 60, 0))
			if UICFG.FloatX >= 0 then UICFG.FloatX = math.clamp(UICFG.FloatX, 8, math.max(vp.X - 60, 8)) end
			if UICFG.FloatY >= 0 then UICFG.FloatY = math.clamp(UICFG.FloatY, 8, math.max(vp.Y - 60, 8)) end
			if UICFG.RadarX >= 0 then UICFG.RadarX = math.clamp(UICFG.RadarX, 8, math.max(vp.X - 120, 8)) end
			if UICFG.RadarY >= 0 then UICFG.RadarY = math.clamp(UICFG.RadarY, 8, math.max(vp.Y - 120, 8)) end
			if UICFG.TargetX >= 0 then UICFG.TargetX = math.clamp(UICFG.TargetX, 8, math.max(vp.X - 160, 8)) end
			if UICFG.TargetY >= 0 then UICFG.TargetY = math.clamp(UICFG.TargetY, 8, math.max(vp.Y - 70, 8)) end
			if UICFG.PerfX >= 0 then UICFG.PerfX = math.clamp(UICFG.PerfX, 8, math.max(vp.X - 218, 8)) end
			if UICFG.PerfY >= 0 then UICFG.PerfY = math.clamp(UICFG.PerfY, 8, math.max(vp.Y - 108, 8)) end
			if UI.floatDock and UICFG.FloatX >= 0 then UI.floatDock.Position = UDim2.fromOffset(UICFG.FloatX, UICFG.FloatY) end
			if radarPanel and UICFG.RadarX >= 0 then radarPanel.Position = UDim2.fromOffset(UICFG.RadarX, UICFG.RadarY) end
			if targetHud and UICFG.TargetX >= 0 then targetHud.Position = UDim2.fromOffset(UICFG.TargetX, UICFG.TargetY) end
			if UI.win then
				UI.win.Size = UDim2.fromOffset(UICFG.W, UICFG.H)
				UI.win.Position = UDim2.fromOffset(UICFG.X, UICFG.Y)
			end
			-- на узком окне карточка игрока не помещается рядом с кнопками
			if UI.userCard then
				local narrow = (UICFG.W < 640)
				UI.userCard.Visible = not narrow
				if UI.dragZone then
					UI.dragZone.Size = narrow and UDim2.new(1, -110, 1, 0) or UDim2.new(1, -300, 1, 0)
				end
			end
		end
		
		local scaleQueued, scaleLast = false, 0
		
		-- UIScale тянет окно от левого верхнего угла, поэтому при изменении
		-- удерживаем визуальный центр на месте — иначе окно «уезжает» по экрану
		local function applyScaleNow(step)
			local prev = UI.scale.Scale
			local next_ = UICFG.Scale
			if math.abs(prev - next_) < 0.0015 then
				if prev ~= next_ then UI.scale.Scale = next_ end
				return
			end
			-- плавный подход к целевому значению: слайдер не дёргает окно рывками
			if step then next_ = prev + (next_ - prev) * 0.25 end
		
			local cx = UICFG.X + UICFG.W * prev / 2
			local cy = UICFG.Y + UICFG.H * prev / 2
		
			UI.scale.Scale = next_
		
			local vp = VP()
			UICFG.X = math.floor(math.clamp(cx - UICFG.W * next_ / 2, 0, math.max(vp.X - 80, 0)))
			UICFG.Y = math.floor(math.clamp(cy - UICFG.H * next_ / 2, 0, math.max(vp.Y - 60, 0)))
			UI.win.Position = UDim2.fromOffset(UICFG.X, UICFG.Y)
		end
		
		function setScaleLive()
			scaleQueued = true
		end
		function setTransLive()
			UI.win.BackgroundTransparency = UICFG.Trans
			UI.top.BackgroundTransparency = UICFG.Trans * 0.6
			UI.side.BackgroundTransparency = UICFG.Trans * 0.6
		end
		
		--========================================================= ПЕРЕТАСКИВАНИЕ ===
		do
			local dragging, dStart, wStart = false, nil, nil
			local function begin(i)
				if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
					dragging = true
					dStart = i.Position
					wStart = Vector2.new(UICFG.X, UICFG.Y)
				end
			end
			UI.dragZone.InputBegan:Connect(begin)
			bind(UserInputService.InputChanged, function(i)
				if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
					local d = i.Position - dStart
					UICFG.X = wStart.X + d.X
					UICFG.Y = wStart.Y + d.Y
					UI.win.Position = UDim2.fromOffset(UICFG.X, UICFG.Y)
				end
			end)
			bind(UserInputService.InputEnded, function(i)
				if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
					if dragging then markDirty() end
					dragging = false
				end
			end)
		end
		
		--============================================================ РАЗМЕР ========
		do
			local rs, sStart, sizeStart = false, nil, nil
			UI.gripBtn.MouseEnter:Connect(function()
				for _, c in ipairs(UI.grip:GetChildren()) do
					if c:IsA("Frame") then c.BackgroundColor3 = Theme.Accent end
				end
			end)
			UI.gripBtn.MouseLeave:Connect(function()
				if rs then return end
				for _, c in ipairs(UI.grip:GetChildren()) do
					if c:IsA("Frame") then c.BackgroundColor3 = Theme.Dim end
				end
			end)
			UI.gripBtn.InputBegan:Connect(function(i)
				if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
					rs = true
					sStart = i.Position
					sizeStart = Vector2.new(UICFG.W, UICFG.H)
				end
			end)
			bind(UserInputService.InputChanged, function(i)
				if rs and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
					local d = (i.Position - sStart) / math.max(UICFG.Scale, 0.1)
					local vp = VP()
					UICFG.W = math.clamp(math.floor(sizeStart.X + d.X), MINW, math.floor(vp.X / UICFG.Scale) - 10)
					UICFG.H = math.clamp(math.floor(sizeStart.Y + d.Y), MINH, math.floor(vp.Y / UICFG.Scale) - 10)
					UI.win.Size = UDim2.fromOffset(UICFG.W, UICFG.H)
				end
			end)
			bind(UserInputService.InputEnded, function(i)
				if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
					if rs then markDirty() end
					rs = false
				end
			end)
		end
		
		--=========================================== WATERMARK: ПЕРЕТАСКИВАНИЕ ======
		local showMenu
		do
			local dragging, moved, dStart, wStart = false, false, nil, nil
			UI.wmBtn.InputBegan:Connect(function(i)
				if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
					dragging = true
					moved = false
					dStart = i.Position
					wStart = Vector2.new(UICFG.WmX, UICFG.WmY)
					tw(watermark, 0.12, { BackgroundTransparency = 0.2 })
				end
			end)
			bind(UserInputService.InputChanged, function(i)
				if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
					local d = i.Position - dStart
					if math.abs(d.X) > 4 or math.abs(d.Y) > 4 then moved = true end
					local vp = VP()
					UICFG.WmX = math.clamp(wStart.X + d.X, 0, math.max(vp.X - 140, 0))
					UICFG.WmY = math.clamp(wStart.Y + d.Y, 0, math.max(vp.Y - 40, 0))
					watermark.AnchorPoint = Vector2.new(0, 0)
					watermark.Position = UDim2.fromOffset(UICFG.WmX, UICFG.WmY)
				end
			end)
			bind(UserInputService.InputEnded, function(i)
				if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
					if dragging then
						tw(watermark, 0.15, { BackgroundTransparency = 0 })
						if not moved then
							if menuOpen then
								showMenu(false)
							else
								showMenu(true)
								selectTab("Settings")
								local wf = ById.watermark
								if wf and wf._row then wf._row.expand(true) end
							end
						end
						markDirty()
					end
					dragging = false
				end
			end)
		end
		
		--============================================== ПОКАЗ / СКРЫТИЕ / ВЫХОД =====
		local savedMouse = Enum.MouseBehavior.Default
		local savedCamMode = Enum.CameraMode.Classic
		
		local cursorFreed = false
		
		local function freeCursor(on)
			-- Touch UI must never use Modal cursor capture; it can steal game controls.
			if IS_MOBILE then
				if UI.modal then UI.modal.Modal = false end
				return
			end
			if on then
				if not cursorFreed then
					savedMouse = UserInputService.MouseBehavior
					savedCamMode = LP.CameraMode
					cursorFreed = true
				end
				-- в LockFirstPerson роблокс держит курсор по центру принудительно
				if LP.CameraMode == Enum.CameraMode.LockFirstPerson then
					LP.CameraMode = Enum.CameraMode.Classic
				end
				UI.modal.Modal = true
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
				UserInputService.MouseIconEnabled = true
			else
				UI.modal.Modal = false
				if cursorFreed then
					-- если включён Third Person, не возвращаем LockFirstPerson
					local tp = ById.thirdperson
					if not (tp and tp._active) then
						LP.CameraMode = savedCamMode
					end
					UserInputService.MouseBehavior = savedMouse
					cursorFreed = false
				end
			end
		end
		
		-- игровые скрипты часто возвращают LockCenter каждый кадр: перехватываем
		bind(UserInputService:GetPropertyChangedSignal("MouseBehavior"), function()
			if (not IS_MOBILE) and menuOpen and UICFG.FreeMouse and UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			end
		end)
		bind(LP:GetPropertyChangedSignal("CameraMode"), function()
			if (not IS_MOBILE) and menuOpen and UICFG.FreeMouse and LP.CameraMode == Enum.CameraMode.LockFirstPerson then
				LP.CameraMode = Enum.CameraMode.Classic
			end
		end)
		
		-- финальное удержание после всех игровых скриптов кадра
		RunService:BindToRenderStep("anaclysm_cursor", Enum.RenderPriority.Last.Value + 1, function(dt)
			tpCamera()
			-- в третьем лице доводка выполняется после расстановки камеры,
			-- иначе прицел считается от прошлого положения и уводит мимо
			local ab = ById.aimbot
			if ab._active and ById.thirdperson._active and O("thirdperson", "force") then
				pcall(ab.Step, dt)
				tpCamera()
			end
			vmStabilize()
		
			-- FOV: игра может гнать своё значение твином или своей камерой,
			-- поэтому финальное слово оставляем за собой
			local fv = ById.fovchange
			if fv and fv._active then
				local cam = workspace.CurrentCamera
				if cam and not O("fovchange", "smooth") then
					local t = O("fovchange", "fov")
					if O("fovchange", "sprint") then
						local h = getHum()
						if h and h.MoveDirection.Magnitude > 0 and UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
							t += O("fovchange", "add")
						end
					end
					if math.abs(cam.FieldOfView - t) > 0.01 then cam.FieldOfView = t end
				end
			end
		
			if IS_MOBILE or not menuOpen or not UICFG.FreeMouse then return end
			if UI.modal and not UI.modal.Modal then UI.modal.Modal = true end
			if LP.CameraMode == Enum.CameraMode.LockFirstPerson then
				LP.CameraMode = Enum.CameraMode.Classic
			end
			if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			end
			if not UserInputService.MouseIconEnabled then
				UserInputService.MouseIconEnabled = true
			end
		end)
		
		
		-- floating dock intentionally disabled.

		-- overlay drag helpers -------------------------------------------------
		local function bindOverlayDrag(handle, frame, xKey, yKey, minW, minH)
			local dragging, start, pos = false, nil, nil
			handle.InputBegan:Connect(function(i)
				if ById.overlaymgr and O("overlaymgr","lock") then return end
				if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
					dragging=true; start=i.Position; pos=Vector2.new(UICFG[xKey], UICFG[yKey])
				end
			end)
			bind(UserInputService.InputChanged,function(i)
				if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
					local d=i.Position-start; local vp=VP()
					local nx=math.clamp(pos.X+d.X,8,math.max(vp.X-minW,8))
					local ny=math.clamp(pos.Y+d.Y,8,math.max(vp.Y-minH,8))
					if ById.overlaymgr and O("overlaymgr","snap") then nx=math.floor(nx/8+0.5)*8; ny=math.floor(ny/8+0.5)*8 end
					UICFG[xKey],UICFG[yKey]=nx,ny
					frame.Position=UDim2.fromOffset(nx,ny)
				end
			end)
			bind(UserInputService.InputEnded,function(i)
				if dragging and (i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch) then dragging=false; markDirty() end
			end)
		end
		bindOverlayDrag(UI.radarDrag, radarPanel, "RadarX", "RadarY", 120, 120)
		bindOverlayDrag(UI.targetDrag, targetHud, "TargetX", "TargetY", 160, 70)
		bindOverlayDrag(UI.perfDrag, perfPanel, "PerfX", "PerfY", 218, 108)
		bindOverlayDrag(UI.threatDrag, threatPanel, "ThreatX", "ThreatY", 200, 120)
		bindOverlayDrag(UI.quickDrag, quickBar, "QuickX", "QuickY", 310, 40)
		
		local hudEditLabels = {}
		local function editLabel(frame,name)
			local l=New("TextLabel",{AnchorPoint=Vector2.new(.5,1),Position=UDim2.new(.5,0,0,-4),Size=UDim2.fromOffset(130,16),BackgroundColor3=Theme.Bg2,BackgroundTransparency=.05,BorderSizePixel=0,Font=FB,TextSize=9,TextColor3=Theme.Accent,Text=name,Visible=false,ZIndex=40,Parent=frame}); corner(l,5); table.insert(hudEditLabels,l); return l
		end
		editLabel(radarPanel,"RADAR"); editLabel(targetHud,"TARGET HUD"); editLabel(perfPanel,"PERFORMANCE"); editLabel(threatPanel,"THREAT LIST"); editLabel(quickBar,"QUICK ACCESS")
		applyHudEditVisuals = function(on)
			for _,l in ipairs(hudEditLabels) do l.Visible=on and O("hudedit","labels") end
			local pulse=on and O("hudedit","pulse")
			for _,st in ipairs({UI.radarStroke,UI.targetStroke,UI.perfStroke,UI.threatStroke,UI.quickStroke}) do if st then st.Color=pulse and Theme.Accent or Theme.Stroke; st.Thickness=pulse and 1.5 or 1 end end
		end
		
		local animToken = 0
		
		function showMenu(state)
			if state == menuOpen then return end
			menuOpen = state
			animToken += 1
			local tok = animToken
		
			if state then
				UI.win.Visible = true
				selectTab(activeTab)
				-- восстановить позицию скролла текущей страницы
				task.defer(function()
					local pg = pages and pages[activeTab]
					if pg and pg.scroll and pg._savedScroll then
						pg.scroll.CanvasPosition = pg._savedScroll
					end
				end)
				if UICFG.FreeMouse then freeCursor(true) end
				local tp = ById.thirdperson
				if tp and tp._active then task.defer(function() if tpApply then tpApply() end end) end
				if not ANIM then
					UI.win.GroupTransparency = 0
					UI.winStroke.Transparency = 0
					UI.win.Position = UDim2.fromOffset(UICFG.X, UICFG.Y)
					blur.Size = UICFG.Blur and 16 or 0
					return
				end
				UI.win.GroupTransparency = 1
				UI.winStroke.Transparency = 1
				UI.win.Position = UDim2.fromOffset(UICFG.X, UICFG.Y + 18)
				tw(UI.win, 0.3, {
					GroupTransparency = 0,
					Position = UDim2.fromOffset(UICFG.X, UICFG.Y),
				})
				tw(UI.winStroke, 0.3, { Transparency = 0 })
				tw(blur, 0.34, { Size = UICFG.Blur and 16 or 0 })
			else
				if UICFG.FreeMouse then freeCursor(false) end
				-- сохранить позицию скролла текущей страницы
				local _pg = pages and pages[activeTab]
				if _pg and _pg.scroll then _pg._savedScroll = _pg.scroll.CanvasPosition end
				local tpf = ById.thirdperson
				if tpf and tpf._active then task.defer(function() if tpApply then tpApply() end end) end
				if not ANIM then
					UI.win.Visible = false
					UI.win.GroupTransparency = 0
					UI.winStroke.Transparency = 0
					blur.Size = 0
					return
				end
				tw(UI.win, 0.22, {
					GroupTransparency = 1,
					Position = UDim2.fromOffset(UICFG.X, UICFG.Y + 14),
				})
				tw(UI.winStroke, 0.18, { Transparency = 1 })
				tw(blur, 0.26, { Size = 0 })
				task.delay(0.24, function()
					if tok ~= animToken or menuOpen then return end
					UI.win.Visible = false
					UI.win.GroupTransparency = 0
					UI.winStroke.Transparency = 0
					UI.win.Position = UDim2.fromOffset(UICFG.X, UICFG.Y)
				end)
			end
		end
		
		function hideMenu()
			saveSession()
			flushStore()
			-- Без floating-кнопки watermark остаётся безопасной точкой возврата на touch-устройствах.
			if IS_MOBILE and DB.watermark and not DB.watermark.on then setOn("watermark", true) end
			showMenu(false)
			Notify("Меню свёрнуто · открыть кликом по watermark" .. (IS_MOBILE and "" or (" или " .. keyLabel(UICFG.MenuKey))), "ok")
		end
		
		function unloadHub()
			saveSession()
			flushStore()
			for _, f in ipairs(Features) do
				if f._active and f.OnToggle then pcall(f.OnToggle, false) end
				f._active = false
			end
			clearEsp()
			clearHitboxes()
			if saToolConn then pcall(function() saToolConn:Disconnect() end) saToolConn = nil end
			if recoilConn then pcall(function() recoilConn:Disconnect() end) recoilConn = nil end
			if fovConn then pcall(function() fovConn:Disconnect() end) fovConn = nil end
			if viewportConn then pcall(function() viewportConn:Disconnect() end) viewportConn = nil end
			uninstallSilentHook()
			for _, c in ipairs(CONNS) do pcall(function() c:Disconnect() end) end
			pcall(function() RunService:UnbindFromRenderStep("anaclysm_main") end)
			pcall(function() RunService:UnbindFromRenderStep("anaclysm_cursor") end)
			if UI.modal then UI.modal.Modal = false end
			if blur then blur:Destroy() end
			if ccEffect then ccEffect:Destroy() end
			local h = getHum()
			if h then restoreHumanoid(h) end
			workspace.Gravity = WORLD_BASE.Gravity
			if Camera then Camera.FieldOfView = fovOriginal or START_CAMERA_FOV end
			pcall(function() LP.CameraMode = START_CAMERA_MODE end)
			pcall(function() UserInputService.MouseBehavior = START_MOUSE_BEHAVIOR end)
			pcall(function() UserInputService.MouseIconEnabled = START_MOUSE_ICON end)
			if UICFG.FreeMouse then freeCursor(false) end
			if RUNTIME_MARKER and RUNTIME_MARKER.Parent then pcall(function() RUNTIME_MARKER:Destroy() end) end
			task.delay(0.05, function() if GUI and GUI.Parent then GUI:Destroy() end end)
		end
		
		bind(SHUTDOWN_EVENT.Event, function()
			if unloadHub then unloadHub() end
		end)
		
		do
			-- Roblox system menu no longer hides the hub.
			bind(GuiService.MenuOpened, function()
				if menuOpen and (not IS_MOBILE) and UICFG.FreeMouse then
					task.defer(function() freeCursor(true) end)
				end
			end)
			bind(GuiService.MenuClosed, function()
				if menuOpen and (not IS_MOBILE) and UICFG.FreeMouse then freeCursor(true) end
			end)
		end

		UI.btnHide.MouseButton1Click:Connect(function() hideMenu() end)
		UI.btnClose.MouseButton1Click:Connect(function() unloadHub() end)
		
		-- медленный перелив акцентной полосы
		task.spawn(function()
			local info = TweenInfo.new(4.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
			local t = TweenService:Create(UI.topGrad, info, { Offset = Vector2.new(0.35, 0) })
			UI.topGrad.Offset = Vector2.new(-0.35, 0)
			t:Play()
		end)
		
		Loader.set(80, "регистрация модулей")
		
		--============================================================== ВВОД ========
		bind(UserInputService.InputBegan, function(input, processed)
			local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
			if input.KeyCode == Enum.KeyCode.K and ctrl and not capturing then
				if not menuOpen then showMenu(true) end
				toggleCommandPalette()
				return
			end
			if commandOpen and input.KeyCode == Enum.KeyCode.Return and #commandMatches > 0 and not capturing then
				local f = commandMatches[1]
				if not f.NoToggle then setOn(f.Id, not DB[f.Id].on) else selectTab(f.Tab); task.defer(function() if f._row then f._row.expand(true) end end) end
				rebuildCommandPalette()
				return
			end
			if input.KeyCode == Enum.KeyCode.Escape and commandOpen and not capturing then toggleCommandPalette(false); return end
			if processed and not capturing then return end
			if input.KeyCode == Enum.KeyCode.Escape and not capturing then
				if UICFG.EscHide then showMenu(not menuOpen) end
				return
			end
			if capturing then
				local name
				if input.UserInputType == Enum.UserInputType.Keyboard then
					name = (input.KeyCode == Enum.KeyCode.Escape) and "" or input.KeyCode.Name
				elseif input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.MouseButton2
					or input.UserInputType == Enum.UserInputType.MouseButton3 then
					name = input.UserInputType.Name
				end
				if name ~= nil then
					local c = capturing
					capturing = nil
					c.apply(name)
					markDirty()
				end
				return
			end
		
			if keyMatches(input, UICFG.MenuKey) then
				showMenu(not menuOpen)
				return
			end
		
			for _, f in ipairs(Features) do
				local d = DB[f.Id]
				if not f.NoToggle and d.mode ~= "Hold" and keyMatches(input, d.key) then
					setOn(f.Id, not d.on)
					Notify(f.Name .. (DB[f.Id].on and " — включено" or " — выключено"), DB[f.Id].on and "ok" or "warn")
				end
			end
		end)
		
		-- трассеры по клику мыши: работают и без Tool, и с любой системой оружия
		bind(UserInputService.InputBegan, function(input, processed)
			if processed then return end
			if input.UserInputType ~= Enum.UserInputType.MouseButton1
				and input.UserInputType ~= Enum.UserInputType.Touch then return end
			local f = ById.tracers
			if f and f._active and O("tracers", "src") ~= "Tool.Activated" and fireTracer then
				fireTracer()
			end
		end)
		
		-- Respawn guard: competitive experiences often need a few seconds to finish
		-- their own character/round initialization. During this window we avoid
		-- running movement/camera features that can interfere with spawning.
		local respawnGuardUntil = 0
		local RESPAWN_GUARDED = {
			antiaim=true, spinbot=true, speed=true, jump=true, infjump=true, bhop=true,
			fly=true, noclip=true, ghost=true, thirdperson=true, fovchange=true,
		}
		local function respawnGuardActive(id)
			return os.clock() < respawnGuardUntil and RESPAWN_GUARDED[id] == true
		end

		local function compatSnapshot()
			local h=getHum(); local cam=Camera
			return {
				WalkSpeed=h and math.floor(h.WalkSpeed*100+.5)/100 or nil,
				Jump=h and math.floor(((h.UseJumpPower and h.JumpPower or h.JumpHeight) or 0)*100+.5)/100 or nil,
				AutoRotate=h and h.AutoRotate or nil, PlatformStand=h and h.PlatformStand or nil,
				CameraOffset=h and tostring(h.CameraOffset) or nil, Gravity=math.floor(workspace.Gravity*100+.5)/100,
				FOV=cam and math.floor(cam.FieldOfView*100+.5)/100 or nil, CameraType=cam and tostring(cam.CameraType) or nil,
			}
		end
		local function compatRecord(writer,phase,before,after)
			if not before or not after then return end
			local changes={}
			for k,v in pairs(after) do if before[k]~=v then table.insert(changes,k..":"..tostring(before[k]).."→"..tostring(v)) end end
			if #changes==0 then return end
			COMPAT_DIAG.lastWriter,COMPAT_DIAG.lastPhase,COMPAT_DIAG.lastChanges=writer,phase,table.concat(changes,", ")
			COMPAT_DIAG.lastAt=os.clock()
			table.insert(COMPAT_DIAG.history,1,string.format("%s [%s]  %s",writer,phase,COMPAT_DIAG.lastChanges))
			while #COMPAT_DIAG.history>12 do table.remove(COMPAT_DIAG.history) end
		end

		bind(UserInputService.JumpRequest, function()
			if os.clock() < respawnGuardUntil then return end
			local f = ById.infjump
			if not f._active or not alive() then return end
			local now = os.clock()
			if (now - ijLast) * 1000 < O("infjump", "gap") then return end
			ijLast = now
			getHum():ChangeState(Enum.HumanoidStateType.Jumping)
		end)
		
		--========================================================= ОСНОВНОЙ ЦИКЛ ====
		local fpsAcc, fpsN, fps = 0, 0, 60
		local frameMs = 16.7
		
		RunService:BindToRenderStep("anaclysm_main", Enum.RenderPriority.Camera.Value + 10, function(dt)
			local tpOn = (ById.thirdperson._active and O("thirdperson", "force"))
			for _, f in ipairs(Features) do
				syncState(f, true)
				if tpOn and f.Id == "aimbot" then continue end
				if respawnGuardActive(f.Id) then continue end
				if f.Step and f._active then
					local watch = COMPAT_DIAG.panelOpen or os.clock() < (COMPAT_DIAG.traceUntil or 0)
					local before = watch and compatSnapshot() or nil
					local ok, err = pcall(f.Step, dt)
					if not ok then recordFeatureError(f, "step", err) end
					if before then compatRecord(f.Id,"Step",before,compatSnapshot()) end
				end
			end
		
			local ab = ById.aimbot
			if ab._active and O("aimbot", "circle") then
				local r = aimRadius
				aimCircle.Visible = true
				aimCircle.Size = UDim2.fromOffset(r * 2, r * 2)
				UI.fovStroke.Color = OC("aimbot", "col")
			else
				aimCircle.Visible = false
			end
		
			if ab._active and O("aimbot", "line") and currentTarget and currentTarget.Parent then
				local sp, on = Camera:WorldToViewportPoint(currentTarget.Position)
				if on then
					local vp = VP()
					local from, to = Vector2.new(vp.X / 2, vp.Y / 2), Vector2.new(sp.X, sp.Y)
					local d = to - from
					aimLine.Visible = true
					aimLine.Size = UDim2.fromOffset(d.Magnitude, 1)
					aimLine.Position = UDim2.fromOffset((from.X + to.X) / 2, (from.Y + to.Y) / 2)
					aimLine.Rotation = math.deg(math.atan2(d.Y, d.X))
				else
					aimLine.Visible = false
				end
			else
				aimLine.Visible = false
			end
		
			if menuOpen and UICFG.FreeMouse then
				if LP.CameraMode == Enum.CameraMode.LockFirstPerson then
					LP.CameraMode = Enum.CameraMode.Classic
				end
				if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
					UserInputService.MouseBehavior = Enum.MouseBehavior.Default
				end
				UserInputService.MouseIconEnabled = true
			end
		
			frameMs = frameMs * 0.9 + dt * 1000 * 0.1
			fpsAcc += dt
			fpsN += 1
			if fpsAcc >= 0.5 then
				fps = math.floor(fpsN / fpsAcc + 0.5)
				infoFps = fps
				SESSION_METRICS.minFps = math.min(SESSION_METRICS.minFps, fps)
				SESSION_METRICS.maxFps = math.max(SESSION_METRICS.maxFps, fps)
				SESSION_METRICS.fpsSamples += 1
				SESSION_METRICS.avgFps += (fps - SESSION_METRICS.avgFps) / SESSION_METRICS.fpsSamples
				SESSION_METRICS.peakPlayers = math.max(SESSION_METRICS.peakPlayers, #Players:GetPlayers())
				fpsAcc, fpsN = 0, 0
			end
		end)
		
		-- физическая фаза: выполняется после шага физики, поэтому наши значения
		-- скорости не затираются встроенным управлением персонажа
		bind(RunService.Heartbeat, function(dt)
			if math.abs(UI.scale.Scale - UICFG.Scale) > 0.0015 then
				applyScaleNow(true)
			end
			for _, f in ipairs(Features) do
				if respawnGuardActive(f.Id) then continue end
				if f.Heart and f._active then
					local watch = COMPAT_DIAG.panelOpen or os.clock() < (COMPAT_DIAG.traceUntil or 0)
					local before = watch and compatSnapshot() or nil
					local ok, err = pcall(f.Heart, dt)
					if not ok then recordFeatureError(f, "heart", err) end
					if before then compatRecord(f.Id,"Heart",before,compatSnapshot()) end
				end
			end
		end)
		
		--======================================================= ФОНОВЫЕ ЗАДАЧИ =====
		local _anStartClock = os.clock()
		task.spawn(function()
			while GUI.Parent do
				task.wait(0.25)
				local f = ById.watermark
				watermark.Visible = f._active and not cleanHudActive()
				if f._active then
					local t = { "anaclysm hub" }
					if O("watermark", "user") then table.insert(t, safePlayerLabel(LP)) end
					if O("watermark", "fps") then table.insert(t, fps .. " fps") end
					if O("watermark", "ping") then
						local p = 0
						pcall(function() p = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()) end)
						table.insert(t, p .. " ms")
					end
					if O("watermark", "time") then table.insert(t, os.date("%H:%M:%S")) end
					if O("watermark", "session") then table.insert(t, string.format("%dm", math.floor((os.clock() - _anStartClock) / 60))) end
					if O("watermark", "players") then table.insert(t, #Players:GetPlayers() .. "/" .. Players.MaxPlayers) end
					if O("watermark", "active") then
						local ac=0; for _,ff in ipairs(Features) do if not ff.NoToggle and ff._active then ac += 1 end end
						table.insert(t, ac .. " active")
					end
					if O("watermark", "bridge") then
						local rn = WeaponIntel and WeaponIntel.learnedRemote and WeaponIntel.learnedRemote.Name or "scan"
						local rc = WeaponIntel and math.floor(WeaponIntel.learnedConfidence or 0) or 0
						table.insert(t, "wpn " .. rn .. " " .. rc .. "%")
					end
					if O("watermark", "profile") then table.insert(t, Store.configs[placeProfileName()] and "profile saved" or "profile none") end
					if O("watermark", "place") then table.insert(t, (streamerActive() and O("streamer","server")) and "place hidden" or tostring(game.PlaceId)) end
					wmText.Text = table.concat(t, "  |  ")
				end
				if UI.userDisplay then
					UI.userDisplay.Text = safePlayerLabel(LP)
					UI.userName.Text = safeUserLabel(LP)
					UI.userAvatar.ImageTransparency = (streamerActive() and O("streamer","avatar")) and 1 or 0
				end
			end
		end)
		
		-- Radar / Target HUD share a low-frequency overlay update loop.
		local radarDots = {}
		local targetThumbId = nil
		task.spawn(function()
			while GUI.Parent do
				task.wait(perfRadarInterval())
				local rf=ById.radar
				if rf and rf._active and not cleanHudActive() then
					radarPanel.Visible=true
					local size=O("radar","size")
					radarPanel.Size=UDim2.fromOffset(size,size)
					UI.radarRange.Text=tostring(O("radar","range")).." st"
					local me=getRoot(); local range=O("radar","range")
					if me then
						for _,p in ipairs(Players:GetPlayers()) do
							if p~=LP then
								local ch=p.Character; local root=ch and ch:FindFirstChild("HumanoidRootPart"); local hum=ch and ch:FindFirstChildOfClass("Humanoid")
								local dot=radarDots[p]
								if not dot then
									local f=New("Frame",{AnchorPoint=Vector2.new(.5,.5),Size=UDim2.fromOffset(6,6),BackgroundColor3=Theme.Bad,BorderSizePixel=0,ZIndex=14,Parent=UI.radarArea}); round1(f)
									local n=New("TextLabel",{AnchorPoint=Vector2.new(.5,0),Position=UDim2.new(.5,0,1,2),Size=UDim2.fromOffset(80,12),BackgroundTransparency=1,Font=FM,TextSize=8,TextColor3=Theme.Sub,Text="",Visible=false,ZIndex=14,Parent=f})
									dot={f=f,n=n}; radarDots[p]=dot
								end
								local ok=root and hum and hum.Health>0 and (O("radar","team") or isEnemy(p))
								if ok then
									local rel
									if O("radar","rotate") then rel=me.CFrame:PointToObjectSpace(root.Position) else rel=root.Position-me.Position end
									local x,z=rel.X,rel.Z; local mag=Vector2.new(x,z).Magnitude
									if mag<=range then
										local scale=.44/range
										dot.f.Visible=true; dot.f.Position=UDim2.fromScale(.5+x*scale,.5+z*scale); dot.f.BackgroundColor3=isEnemy(p) and OC("esp","cEnemy") or OC("esp","cAlly")
										dot.n.Visible=O("radar","names"); dot.n.Text=safePlayerLabel(p)
									else dot.f.Visible=false end
								else dot.f.Visible=false end
							end
						end
					end
				else
					radarPanel.Visible=false
					for _,d in pairs(radarDots) do if d.f then d.f.Visible=false end end
				end
		
				local th=ById.targethud
				local targetPart=currentTarget
				local targetPlayer=targetPart and targetPart.Parent and Players:GetPlayerFromCharacter(targetPart.Parent)
				if th and th._active and not cleanHudActive() and targetPlayer and targetPlayer.Character then
					local ch=targetPlayer.Character; local hum=ch:FindFirstChildOfClass("Humanoid"); local root=ch:FindFirstChild("HumanoidRootPart")
					if hum and root and hum.Health>0 then
						targetHud.Visible=true
						UI.targetName.Text=safePlayerLabel(targetPlayer)
						local inf={}
						if O("targethud","dist") then table.insert(inf,math.floor((Camera.CFrame.Position-root.Position).Magnitude).." st") end
						if O("targethud","tool") then local tool=ch:FindFirstChildOfClass("Tool"); if tool then table.insert(inf,tool.Name) end end
						UI.targetInfo.Text=table.concat(inf,"  ·  ")
						local ratio=math.clamp(hum.Health/math.max(hum.MaxHealth,1),0,1)
						UI.targetHpBg.Visible=O("targethud","hp"); UI.targetHp.Size=UDim2.new(ratio,0,1,0); UI.targetHp.BackgroundColor3=Theme.Bad:Lerp(Theme.Good,ratio)
						local hideAvatar=not O("targethud","avatar") or (streamerActive() and O("streamer","avatar"))
						UI.targetAvatar.Visible=not hideAvatar
						if not hideAvatar and targetThumbId~=targetPlayer.UserId then
							targetThumbId=targetPlayer.UserId
							task.spawn(function() local ok,img=pcall(function() return Players:GetUserThumbnailAsync(targetPlayer.UserId,Enum.ThumbnailType.HeadShot,Enum.ThumbnailSize.Size100x100) end); if ok and targetThumbId==targetPlayer.UserId then UI.targetAvatar.Image=img end end)
						end
					else targetHud.Visible=false end
				else targetHud.Visible=false end
			end
		end)
		
		-- threat list has its own low-frequency pass and reuses ESP colors/visibility helpers.
		task.spawn(function()
			while GUI.Parent do
				task.wait(math.max(perfRadarInterval(), 0.10))
				local tf=ById.threats
				if tf and tf._active and not cleanHudActive() then
					threatPanel.Visible=true
					local me=getRoot(); local rows={}
					if me then
						for _,p in ipairs(Players:GetPlayers()) do
							if p~=LP and isEnemy(p) then
								local ch=p.Character; local hum=ch and ch:FindFirstChildOfClass("Humanoid"); local root=ch and ch:FindFirstChild("HumanoidRootPart"); local head=ch and ch:FindFirstChild("Head")
								if hum and root and hum.Health>0 then
									local dist=(me.Position-root.Position).Magnitude
									if dist<=O("threats","range") and (not O("threats","visible") or (head and partVisible(head,ch))) then
										table.insert(rows,{p=p,ch=ch,hum=hum,dist=dist})
									end
								end
							end
						end
					end
					table.sort(rows,function(a,b) return a.dist<b.dist end)
					local count=O("threats","count")
					threatPanel.Size=UDim2.fromOffset(264, math.clamp(38 + count * 25, 96, 238))
					for i=1,8 do
						local r=threatRows[i]; local e=rows[i]
						if r then
							r.row.Visible=(i<=count and e~=nil)
							if e and i<=count then
								r.name.Text=safePlayerLabel(e.p)
								r.dot.BackgroundColor3=OC("esp","cEnemy")
								local info={math.floor(e.dist).." st"}
								if O("threats","hp") then table.insert(info,math.floor(e.hum.Health).." hp") end
								if O("threats","tool") then local t=e.ch:FindFirstChildOfClass("Tool"); if t then table.insert(info,t.Name) end end
								r.info.Text=table.concat(info," · ")
							end
						end
					end
				else
					threatPanel.Visible=false
				end
			end
		end)
		
		-- performance overlay is deliberately low-frequency; it does not add work to every frame.
		task.spawn(function()
			while GUI.Parent do
				local pf = ById.perfmon
				local rate = (pf and O("perfmon", "rate") or 250) / 1000
				task.wait(math.max(rate, 0.1))
				if pf and pf._active and not cleanHudActive() then
					perfPanel.Visible = true
					local lines = {}
					if O("perfmon", "fps") then table.insert(lines, string.format("FPS  %d    FRAME  %.1f ms", infoFps, frameMs)) end
					if O("perfmon", "ping") then local p=0; pcall(function() p=math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()) end); table.insert(lines, "PING  "..p.." ms") end
					if O("perfmon", "mem") then local m=0; pcall(function() m=Stats:GetTotalMemoryUsageMb() end); table.insert(lines, string.format("MEM   %.0f MB", m)) end
					if O("perfmon", "active") then local n=0; for _,ff in ipairs(Features) do if not ff.NoToggle and ff._active then n+=1 end end; table.insert(lines, "MODULES  "..n) end
					if O("perfmon", "budget") then table.insert(lines, "BUDGET  "..optimizerTier().."  · ESP "..math.floor(1/math.max(perfEspInterval(),0.001)).." hz") end
					perfText.Text = table.concat(lines, "\n")
				else
					perfPanel.Visible = false
				end
			end
		end)
		
		task.spawn(function()
			while GUI.Parent do
				task.wait(.20)
				local qf=ById.quickbar
				if qf and qf._active and not cleanHudActive() then
					quickBar.Visible=true
					local listF={}
					for _,f in ipairs(Features) do
						if not f.NoToggle and f.Id~="quickbar" and f.Id~="cleanhud" then
							local fav=type(UICFG.Favorites)=="table" and UICFG.Favorites[f.Id]
							if (not O("quickbar","onlyfav")) or fav then table.insert(listF,f) end
						end
					end
					table.sort(listF,function(a,b)
						local aa=(a._active and 1 or 0)+(type(UICFG.Favorites)=="table" and UICFG.Favorites[a.Id] and 2 or 0)
						local bb=(b._active and 1 or 0)+(type(UICFG.Favorites)=="table" and UICFG.Favorites[b.Id] and 2 or 0)
						if aa==bb then return a.Name<b.Name end return aa>bb
					end)
					local count=O("quickbar","count")
					quickTitle.Visible=O("quickbar","labels")
					UI.quickHolder.Position=UDim2.fromOffset(O("quickbar","labels") and 50 or 6,5)
					UI.quickHolder.Size=UDim2.new(1,O("quickbar","labels") and -58 or -12,1,-10)
					for i=1,8 do
						local q=quickButtons[i]; local f=(i<=count) and listF[i] or nil; q.f=f; q.b.Visible=f~=nil
						if f then
							local short=(f.Name or f.Id):gsub("[^%w]",""):sub(1,3):upper(); q.b.Text=short~="" and short or tostring(i)
							q.b.TextColor3=f._active and Theme.Text or Theme.Sub; q.b.BackgroundColor3=f._active and Theme.Accent or Theme.Deep; q.st.Color=f._active and Theme.Accent2 or Theme.Stroke
						end
					end
				else quickBar.Visible=false end
			end
		end)
		
		task.spawn(function()
			local labels = {}
			while GUI.Parent do
				task.wait(0.3)
				local bl = ById.bindlist
				bindList.Visible = bl._active and not cleanHudActive()
				if bl._active then
					local shown = {}
					for _, f in ipairs(Features) do
						local d = DB[f.Id]
						if not f.NoToggle and d.key ~= "" then
							if not O("bindlist", "only") or f._active then table.insert(shown, f) end
						end
					end
					for i, f in ipairs(shown) do
						local l = labels[i]
						if not l then
							l = New("TextLabel", {
								Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1, Font = FM, TextSize = 11,
								TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = i, Parent = bindList,
							})
							labels[i] = l
						end
						l.Visible = true
						local m = O("bindlist", "mode") and ("  " .. DB[f.Id].mode:lower()) or ""
						l.Text = string.format("%s  [%s]%s", f.Name, keyLabel(DB[f.Id].key), m)
						l.TextColor3 = f._active and Theme.Accent or Theme.Sub
					end
					for i = #shown + 1, #labels do labels[i].Visible = false end
					blTitle.Visible = #shown > 0
					if #shown == 0 then
						blTitle.Visible = true
						blTitle.Text = "БИНДЫ НЕ НАЗНАЧЕНЫ"
					else
						blTitle.Text = "БИНДЫ"
					end
				end
			end
		end)
		
		task.spawn(function()
			local lastFlush = os.clock()
			while GUI.Parent do
				task.wait(3)
				if dirty and UICFG.AutoSave then saveSession() end
				-- раз в полминуты просим сервер записать данные в DataStore
				if RemoteStore and (os.clock() - lastFlush) > 30 then
					lastFlush = os.clock()
					flushStore()
				end
			end
		end)
		
		task.spawn(function()
			while GUI.Parent do
				task.wait(0.4)
				local n, total = 0, 0
				for _, f in ipairs(Features) do
					if not f.NoToggle then
						if f._active then total += 1 end
						if f.Tab == activeTab and f._active then n += 1 end
					end
				end
				if menuOpen then
					UI.hCount.Text = (n > 0) and (n .. " активно на вкладке") or "нет активных"
				end
				UI.statusTxt.Text = total .. " активных модулей"
				UI.statusDot.BackgroundColor3 = (total > 0) and Theme.Good or Theme.Dim
			end
		end)
		
		--==================================================== РЕСПАВН ПЕРСОНАЖА =====
		bind(LP.CharacterAdded, function(char)
			SESSION_METRICS.respawns += 1
			respawnGuardUntil = os.clock() + 3.0
			COMPAT_DIAG.respawnGuardUntil = respawnGuardUntil
			COMPAT_DIAG.traceUntil = os.clock() + 8.0
			COMPAT_DIAG.lastEvent = "CharacterAdded: spawn guard + trace"
			currentTarget = nil
			saCurrentTarget = nil
			tbArmed, tbLastShot = 0, 0
			rfLast, recoilPitch = 0, nil
			table.clear(noclipCache)
			table.clear(speedColl)
			clearHitboxes()
			if flyBV then flyBV:Destroy() flyBV = nil end
			local newHum = char:WaitForChild("Humanoid", 10)
			local newRoot = char:WaitForChild("HumanoidRootPart", 10)
			if newHum then captureHumanoidBase(newHum) end
			-- Do not force-toggle every active feature here. The old behavior could
			-- fight a game's own spawn/round scripts before the character was ready.
			if newHum and newRoot then
				task.delay(3.05, function()
					if LP.Character == char and newHum.Parent and newRoot.Parent then
						captureHumanoidBase(newHum)
					end
				end)
			end
		end)
		
		bind(Players.PlayerRemoving, function(p)
			destroyEsp(p)
			local hb = hitboxParts[p]
			if hb then pcall(function() hb:Destroy() end) end
			hitboxParts[p] = nil
			if radarDots and radarDots[p] then
				pcall(function() radarDots[p].f:Destroy() end)
				radarDots[p] = nil
			end
		end)
		fovConn, viewportConn = nil, nil
		local function hookCamera(cam)
			if fovConn then fovConn:Disconnect() fovConn = nil end
			if viewportConn then viewportConn:Disconnect() viewportConn = nil end
			if not cam then return end
			Camera = cam
			if ById.fovchange and ById.fovchange._active then fovOriginal = cam.FieldOfView end
		
			-- удержание FOV поверх игровых камерных скриптов
			fovConn = cam:GetPropertyChangedSignal("FieldOfView"):Connect(function()
				local f = ById.fovchange
				if not f or not f._active then return end
				if O("fovchange", "smooth") then return end
				local t = O("fovchange", "fov")
				if O("fovchange", "sprint") then
					local h = getHum()
					if h and h.MoveDirection.Magnitude > 0 and UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
						t += O("fovchange", "add")
					end
				end
				if math.abs(cam.FieldOfView - t) > 0.01 then cam.FieldOfView = t end
			end)
		
			viewportConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				task.defer(function()
					if not GUI or not GUI.Parent then return end
					fitToViewport(true)
					if UI.win then
						UI.win.Size = UDim2.fromOffset(UICFG.W, UICFG.H)
						UI.win.Position = UDim2.fromOffset(UICFG.X, UICFG.Y)
					end
				end)
			end)
		end
		hookCamera(Camera)
		
		bind(workspace:GetPropertyChangedSignal("CurrentCamera"), function()
			local cam = workspace.CurrentCamera
			if cam then hookCamera(cam) end
		end)
		
		--============================================================== СТАРТ =======
		readStore()
		if not Store.configs["default"] then
			Store.configs["default"] = snapshotNow()
			Store.current = "default"
		end
		if Store.session then
			applySnapshot(deepCopy(Store.session))
		elseif Store.configs[Store.current] then
			applySnapshot(deepCopy(Store.configs[Store.current]))
		end
		if DB.placeprofiles and O("placeprofiles","autoload") and Store.configs[placeProfileName()] then
			applySnapshot(deepCopy(Store.configs[placeProfileName()]))
		end
		
		UICFG.Scale = O("iface", "scale") / 100
		UICFG.Trans = O("iface", "trans") / 100
		UICFG.Blur = O("iface", "blur")
		UICFG.Animations = O("iface", "anim")
		UICFG.AutoExpand = O("iface", "expand")
		UICFG.FreeMouse = O("iface", "mouse")
		UICFG.EscHide = O("iface", "esc")
		UICFG.Advanced = O("iface", "adv")
		UICFG.AutoSave = O("control", "auto")
		ANIM = UICFG.Animations
		
		do
			local vp = VP()
			if UICFG.X == 0 and UICFG.Y == 0 then
				UICFG.X = math.floor((vp.X - UICFG.W * UICFG.Scale) / 2)
				UICFG.Y = math.floor((vp.Y - UICFG.H * UICFG.Scale) / 2)
			end
			UICFG.X = math.clamp(UICFG.X, 0, math.max(vp.X - 120, 0))
			UICFG.Y = math.clamp(UICFG.Y, 0, math.max(vp.Y - 80, 0))
			UICFG.WmX = math.clamp(UICFG.WmX, 0, math.max(vp.X - 140, 0))
			UICFG.WmY = math.clamp(UICFG.WmY, 0, math.max(vp.Y - 40, 0))
			if UICFG.FloatX >= 0 then UICFG.FloatX = math.clamp(UICFG.FloatX, 8, math.max(vp.X - 60, 8)) end
			if UICFG.FloatY >= 0 then UICFG.FloatY = math.clamp(UICFG.FloatY, 8, math.max(vp.Y - 60, 8)) end
			if UICFG.RadarX < 0 then UICFG.RadarX = math.max(vp.X - 196, 8) end
			if UICFG.RadarY < 0 then UICFG.RadarY = 54 end
			if UICFG.TargetX < 0 then UICFG.TargetX = math.max(vp.X - 260, 8) end
			if UICFG.TargetY < 0 then UICFG.TargetY = math.max(vp.Y - 104, 8) end
			if UICFG.PerfX < 0 then UICFG.PerfX = 16 end
			if UICFG.PerfY < 0 then UICFG.PerfY = math.max(vp.Y - 150, 8) end
			if UICFG.ThreatX < 0 then UICFG.ThreatX = 16 end
			if UICFG.ThreatY < 0 then UICFG.ThreatY = 110 end
		end
		
		Loader.set(92, "применение конфигурации")
		task.wait(0.2)
		
		applyAccent()
		
		if IS_MOBILE then
			local vp = VP()
			-- Mobile-first: almost fullscreen, one column, no 0.75 shrink.
			UICFG.W = math.clamp(math.floor(vp.X * 0.94), MINW, math.max(vp.X - 8, MINW))
			UICFG.H = math.clamp(math.floor(vp.Y * 0.90), MINH, math.max(vp.Y - 8, MINH))
			UICFG.Scale = 1
			UICFG.X = math.floor(math.max((vp.X - UICFG.W) / 2, 4))
			UICFG.Y = math.floor(math.max((vp.Y - UICFG.H) / 2, 4))
			DB.iface.o.scale = 100
			UI.userCard.Visible = false
			UI.side.Size = UDim2.new(0, 132, 1, -50)
			UI.content.Position = UDim2.new(0, 132, 0, 50)
			UI.content.Size = UDim2.new(1, -132, 1, -50)
			UI.searchBox.Size = UDim2.new(1, -52, 1, 0)
			UI.searchFav.Position = UDim2.new(1, -10, .5, 0)
			UI.searchGroup.Visible = false
			UI.cmdHint.Visible = false
			UI.searchCount.Visible = false
			UI.hTitle.TextSize = 17
			UI.hSub.TextSize = 10
		end

		SESSION_METRICS.peakPlayers = #Players:GetPlayers()
		fitToViewport(true)
		applyUI()
		fitToViewport(false)
		refreshRows()
		if radarPanel then radarPanel.Visible = ById.radar and ById.radar._active or false end
		if targetHud then targetHud.Visible = false end
		if perfPanel then perfPanel.Visible = ById.perfmon and ById.perfmon._active or false end
		if threatPanel then threatPanel.Visible = ById.threats and ById.threats._active or false end
		selectTab("Main")
		-- inf expand убран: не сбрасывать activeTab при старте
		Loader.finish()
		showMenu(true)
		
		-- серверный модуль хранения может появиться позже клиента
		task.spawn(function()
			if RemoteStore then return end
			local r = ReplicatedStorage:WaitForChild("AnaclysmStore", 30)
			if not r or not r:IsA("RemoteFunction") then return end
			RemoteStore = r
			if storeLoaded then return end
			if readStore() and (Store.session or Store.configs[Store.current]) then
				applySnapshot(deepCopy(Store.session or Store.configs[Store.current]))
				if UI.cfgTxt then UI.cfgTxt.Text = Store.current end
				Notify("Конфиг загружен с сервера: " .. Store.current, "ok")
			end
		end)
		
		do
			local h = getHum()
			if h then captureHumanoidBase(h) end
		end
		
		task.delay(0.6, function()
			Notify("anaclysm hub v5.2.3 запущен · " .. keyLabel(UICFG.MenuKey), "ok")
			local fallbacks = {}
			if not RUNTIME_CAPS.FileIO then table.insert(fallbacks, "file I/O") end
			if not RUNTIME_CAPS.MetaHook then table.insert(fallbacks, "meta hook") end
			if not RUNTIME_CAPS.Clipboard then table.insert(fallbacks, "clipboard") end
			if #fallbacks > 0 then
				Notify("Self-check: core OK · fallback: " .. table.concat(fallbacks, ", "), "warn")
			else
				Notify("Self-check: core OK · optional capabilities available", "ok")
			end
			if RUNTIME_BOOT.legacyFound then
				Notify("Найден старый экземпляр hub: UI очищен. Для старых v4 и ниже лучше сначала нажимать Close перед повторным запуском.", "warn")
			end
		end)
		
		task.delay(2.5, function()
			if RemoteStore then
				Notify("Конфиги сохраняются между сессиями", "ok")
			else
				Notify("Конфиги живут только до выхода с сервера: не найден серверный скрипт anaclysm_store_server", "warn")
			end
		end)
	end

	__anaclysm_ui_runtime()
end

local __an_ok, __an_err = pcall(__anaclysm_feature_bootstrap)
if not __an_ok then
	warn("[anaclysm] startup failed: " .. tostring(__an_err))
	pcall(function()
		if RUNTIME_MARKER and RUNTIME_MARKER.Parent then RUNTIME_MARKER:Destroy() end
	end)
end

--[[ =========================================================================
  ОПЦИОНАЛЬНО: сохранение конфигов МЕЖДУ СЕССИЯМИ.
  Клиент не имеет доступа к DataStore, поэтому без серверной части конфиги
  живут только до выхода с сервера. Если нужно постоянное хранение — создайте
  Script в ServerScriptService со следующим содержимым (скрипт выше сам его
  подхватит, ничего менять не нужно):

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ds = DataStoreService:GetDataStore("anaclysm_hub_v2")

local rf = Instance.new("RemoteFunction")
rf.Name = "AnaclysmStore"
rf.Parent = ReplicatedStorage

local cache = {}

rf.OnServerInvoke = function(plr, action, payload)
    local key = "cfg_" .. plr.UserId
    if action == "load" then
        if cache[plr.UserId] then return cache[plr.UserId] end
        local ok, res = pcall(function() return ds:GetAsync(key) end)
        if ok and type(res) == "string" then
            cache[plr.UserId] = res
            return res
        end
        return nil
    elseif (action == "save" or action == "flush") and type(payload) == "string" and #payload < 200000 then
        cache[plr.UserId] = payload
        if action == "flush" then
            local ok = pcall(function() ds:SetAsync(key, payload) end)
            return ok
        end
        return true
    end
    return false
end

local function flush(plr)
    local data = cache[plr.UserId]
    if data then
        pcall(function() ds:SetAsync("cfg_" .. plr.UserId, data) end)
    end
end

Players.PlayerRemoving:Connect(function(plr)
    flush(plr)
    cache[plr.UserId] = nil
end)

game:BindToClose(function()
    for _, plr in ipairs(Players:GetPlayers()) do flush(plr) end
end)

task.spawn(function()
    while task.wait(60) do
        for _, plr in ipairs(Players:GetPlayers()) do flush(plr) end
    end
end)
========================================================================= ]]

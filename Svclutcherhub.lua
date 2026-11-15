--[[
    SVCLUTCHER HUB :: SLAP BATTLES  (gerepareerd)
    loadstring(game:HttpGet("YOUR_URL_HERE"))()
]]

local Services = {
	Players = game:GetService("Players"),
	RunService = game:GetService("RunService"),
	UserInputService = game:GetService("UserInputService"),
	ReplicatedStorage = game:GetService("ReplicatedStorage"),
	TeleportService = game:GetService("TeleportService"),
	BadgeService = game:GetService("BadgeService"),
	GuiService = game:GetService("GuiService"),
	HttpService = game:GetService("HttpService"),
	VirtualUser = game:GetService("VirtualUser"),
}

local Players = Services.Players
local RunService = Services.RunService
local UIS = Services.UserInputService
local RS = Services.ReplicatedStorage
local BadgeService = Services.BadgeService
local player = Players.LocalPlayer

local env = type(getgenv) == "function" and getgenv() or _G
if type(env.SVCLUTCHER_Cleanup) == "function" then
	pcall(env.SVCLUTCHER_Cleanup)
end

-- ============================================================
-- HTTP / UI LIB
-- ============================================================
local function httpGet(url)
	if type(game.HttpGetAsync) == "function" then
		local ok, res = pcall(game.HttpGetAsync, game, url)
		if ok and type(res) == "string" then return res end
	end
	if type(game.HttpGet) == "function" then
		local ok, res = pcall(game.HttpGet, game, url)
		if ok and type(res) == "string" then return res end
	end
	if type(request) == "function" then
		local ok, res = pcall(function()
			local r = request({ Url = url, Method = "GET" })
			return r and r.Body
		end)
		if ok and type(res) == "string" then return res end
	end
	return nil
end

local windSource = httpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua")
if not windSource then
	print("[SVCLUTCHER] WindUI kon niet gedownload worden (HTTP geblokkeerd?)")
	return
end
local windChunk, windErr = (type(loadstring) == "function" and loadstring or load)(windSource)
if not windChunk then
	print("[SVCLUTCHER] WindUI compile-fout: " .. tostring(windErr))
	return
end
local windOk, WindUI = pcall(windChunk)
if not windOk or type(WindUI) ~= "table" then
	print("[SVCLUTCHER] WindUI init mislukt: " .. tostring(WindUI))
	return
end

local Muted = false
local function Notify(title, text, dur)
	if Muted then return end
	pcall(function()
		WindUI:Notify({
			Title = tostring(title or "SVCLUTCHER"),
			Content = tostring(text or ""),
			Icon = "bell",
			Duration = dur or 2.5,
		})
	end)
end

-- ============================================================
-- UTIL
-- ============================================================
local function norm(s) return string.lower(tostring(s or "")) end

local function getRoot(p)
	local char = (p or player).Character
	return char and char:FindFirstChild("HumanoidRootPart") or nil
end

local function getHum(p)
	local char = (p or player).Character
	return char and char:FindFirstChildOfClass("Humanoid") or nil
end

local function equippedTool()
	local char = player.Character
	if not char then return nil end
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA("Tool") then return c end
	end
	return nil
end

local function ragdolled(p)
	local char = (p or player).Character
	if not char then return true end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return true end
	for _, key in ipairs({ "Ragdoll", "Ragdolled", "IsRagdolled", "Knocked", "Downed" }) do
		if char:GetAttribute(key) == true then return true end
		local v = char:FindFirstChild(key, true)
		if v and v:IsA("BoolValue") and v.Value then return true end
	end
	local st = hum:GetState()
	return hum.PlatformStand
		or st == Enum.HumanoidStateType.Ragdoll
		or st == Enum.HumanoidStateType.Physics
		or st == Enum.HumanoidStateType.FallingDown
end

local function groundCFrame(pos, exclude)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude or {}
	local hit = workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -80, 0), params)
	if hit then return CFrame.new(hit.Position + Vector3.new(0, 4, 0)) end
	return CFrame.new(pos + Vector3.new(0, 4, 0))
end

local function moveRoot(root, cf)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.CFrame = cf
end

-- remote zoeken: exact, dan case-insensitive, dan substring, met cache
local RemoteCache = {}
local function slapRemote()
	if RemoteCache.Slap and RemoteCache.Slap.Parent then return RemoteCache.Slap end
	for _, name in ipairs({ "Slap", "slap", "SlapRemote", "SlapEvent" }) do
		for _, obj in ipairs(RS:GetDescendants()) do
			if obj:IsA("RemoteEvent") and norm(obj.Name) == norm(name) then
				RemoteCache.Slap = obj
				return obj
			end
		end
	end
	for _, obj in ipairs(RS:GetDescendants()) do
		if obj:IsA("RemoteEvent") and norm(obj.Name):find("slap", 1, true) then
			RemoteCache.Slap = obj
			return obj
		end
	end
	return nil
end

local function validTarget(p)
	if not p or p == player then return nil end
	local char = p.Character
	if not char then return nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health <= 0 then return nil end
	if ragdolled(p) then return nil end
	return root
end

-- ============================================================
-- HITBOX
-- ============================================================
local Combat = { Hitbox = false, Size = 14, Visible = true, Saved = {}, Loop = nil, Aura = false, Range = 20, AuraThread = nil, AutoSlap = false, AutoThread = nil, LastSlap = 0 }

local function restoreRoot(root, saved)
	root.Size = saved.Size
	root.Transparency = saved.Transparency
	root.Color = saved.Color
	root.Material = saved.Material
	root.CanCollide = saved.CanCollide
end

local function applyHitbox(p)
	local root = validTarget(p)
	local saved = Combat.Saved[p]

	if not root then
		if saved then
			local r = getRoot(p)
			if r then restoreRoot(r, saved) end
			Combat.Saved[p] = nil
		end
		return
	end

	if not saved then
		Combat.Saved[p] = {
			Size = root.Size,
			Transparency = root.Transparency,
			Color = root.Color,
			Material = root.Material,
			CanCollide = root.CanCollide,
		}
	end

	local s = Combat.Size
	root.Size = Vector3.new(s, s, s)
	root.Transparency = Combat.Visible and 0.7 or 1
	root.Color = Color3.fromRGB(0, 170, 255)
	root.Material = Enum.Material.Neon
	root.CanCollide = false
end

local function resetHitbox(p)
	local root = getRoot(p)
	local saved = Combat.Saved[p]
	if root and saved then restoreRoot(root, saved) end
	Combat.Saved[p] = nil
end

local function refreshHitboxes()
	if Combat.Hitbox then
		if not Combat.Loop then
			Combat.Loop = RunService.Heartbeat:Connect(function()
				if not Combat.Hitbox then return end
				for _, p in ipairs(Players:GetPlayers()) do
					if p ~= player then applyHitbox(p) end
				end
			end)
		end
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player then applyHitbox(p) end
		end
	else
		if Combat.Loop then Combat.Loop:Disconnect() Combat.Loop = nil end
		for _, p in ipairs(Players:GetPlayers()) do resetHitbox(p) end
	end
end

local function setHitbox(state, silent)
	Combat.Hitbox = state == true
	refreshHitboxes()
	if not silent then Notify("Hitbox", state and "On." or "Off.") end
end

local function setHitboxSize(v)
	Combat.Size = math.clamp(tonumber(v) or 14, 10, 25)
	if Combat.Hitbox then refreshHitboxes() end
end

local function setVisible(v)
	Combat.Visible = v == true
	if Combat.Hitbox then refreshHitboxes() end
end

local function canAura(p)
	local lr, tr = getRoot(player), getRoot(p)
	if not lr or not tr then return nil end
	if ragdolled(player) or ragdolled(p) then return nil end
	if (lr.Position - tr.Position).Magnitude > Combat.Range then return nil end
	return tr
end

local function startAura()
	if Combat.AuraThread then return end
	Combat.AuraThread = task.spawn(function()
		local warned = false
		while Combat.Aura do
			local r = slapRemote()
			if not r then
				if not warned then
					warned = true
					Notify("Slap Aura", "Slap remote niet gevonden.", 3)
				end
			else
				warned = false
				for _, p in ipairs(Players:GetPlayers()) do
					local tr = canAura(p)
					if tr then pcall(function() r:FireServer(tr) end) end
				end
			end
			task.wait(0.4)
		end
		Combat.AuraThread = nil
	end)
end

local function setAura(state, silent)
	Combat.Aura = state == true
	if Combat.Aura then startAura() elseif Combat.AuraThread then Combat.AuraThread = nil end
	if not silent then Notify("Slap Aura", state and "On." or "Off.") end
end

local function startAutoSlap()
	if Combat.AutoThread then return end
	Combat.AutoThread = task.spawn(function()
		while Combat.AutoSlap do
			local tool, root = equippedTool(), getRoot(player)
			if tool and root then
				for _, p in ipairs(Players:GetPlayers()) do
					local tr = validTarget(p)
					if tr and (root.Position - tr.Position).Magnitude <= Combat.Size + 8 then
						if os.clock() - Combat.LastSlap > 0.12 then
							Combat.LastSlap = os.clock()
							pcall(function() tool:Activate() end)
						end
						break
					end
				end
			end
			task.wait(0.1)
		end
		Combat.AutoThread = nil
	end)
end

local function setAutoSlap(state, silent)
	Combat.AutoSlap = state == true
	if Combat.AutoSlap then startAutoSlap() elseif Combat.AutoThread then Combat.AutoThread = nil end
	if not silent then Notify("Auto Slap", state and "On." or "Off.") end
end

-- ============================================================
-- ANTI-RAGDOLL CAGE
-- ============================================================
local Anti = { On = false, Folder = nil, Conn = nil }

local function clearCage()
	if Anti.Folder then Anti.Folder:Destroy() Anti.Folder = nil end
end

local function buildCage()
	clearCage()
	local root = getRoot(player)
	if not root or not Anti.On then return end
	local folder = Instance.new("Folder")
	folder.Name = "SVCCage"
	folder.Parent = workspace
	Anti.Folder = folder
	local c, inner, thick = root.CFrame, 8, 40
	local ow, oh, od = inner + thick * 2, inner + thick * 2, inner + thick * 2
	local function part(rel, size)
		local p = Instance.new("Part")
		p.Name = "SVCCagePart"
		p.Size = size
		p.CFrame = c * rel
		p.Anchored = true
		p.CanCollide = true
		p.CanTouch = false
		p.CanQuery = false
		p.Transparency = 1
		p.Parent = folder
	end
	part(CFrame.new(0, -(inner / 2 + thick / 2), 0), Vector3.new(ow, thick, od))
	part(CFrame.new(0, inner / 2 + thick / 2, 0), Vector3.new(ow, thick, od))
	part(CFrame.new(inner / 2 + thick / 2, 0, 0), Vector3.new(thick, oh, od))
	part(CFrame.new(-(inner / 2 + thick / 2), 0, 0), Vector3.new(thick, oh, od))
	part(CFrame.new(0, 0, inner / 2 + thick / 2), Vector3.new(ow, oh, thick))
	part(CFrame.new(0, 0, -(inner / 2 + thick / 2)), Vector3.new(ow, oh, thick))
end

local function setAnti(state, silent)
	Anti.On = state == true
	if Anti.Conn then Anti.Conn:Disconnect() Anti.Conn = nil end
	clearCage()
	if Anti.On then
		Anti.Conn = RunService.Heartbeat:Connect(function()
			local root = getRoot(player)
			if not root then return end
			local vel = root.AssemblyLinearVelocity
			local fast = Vector3.new(vel.X, 0, vel.Z).Magnitude >= 38
			local should = ragdolled(player) or fast
			if should and not Anti.Folder then buildCage()
			elseif not should and Anti.Folder then clearCage() end
		end)
	end
	if not silent then Notify("Anti-Ragdoll", state and "On." or "Off.") end
end

-- ============================================================
-- MOVEMENT
-- ============================================================
local Move = { InfJump = false, JumpConn = nil, Fly = false, FlyVel = nil, FlyConn = nil, FlySpeed = 60, Noclip = false, NoclipConn = nil, Speed = 16, Jump = 50, AntiFling = false, FlingConn = nil }

local function setInfJump(state, silent)
	Move.InfJump = state == true
	if Move.JumpConn then Move.JumpConn:Disconnect() Move.JumpConn = nil end
	if Move.InfJump then
		Move.JumpConn = UIS.JumpRequest:Connect(function()
			local hum = getHum(player)
			if Move.InfJump and hum and hum.Health > 0 then
				hum:ChangeState(Enum.HumanoidStateType.Jumping)
			end
		end)
	end
	if not silent then Notify("Infinite Jump", state and "On." or "Off.") end
end

local function setFly(state, silent)
	Move.Fly = state == true
	if Move.FlyConn then Move.FlyConn:Disconnect() Move.FlyConn = nil end
	local root = getRoot(player)
	if not root then
		if not silent then Notify("Fly", "Geen karakter.") end
		return
	end
	if Move.Fly then
		local bv = Instance.new("BodyVelocity")
		bv.Name = "SVCFly"
		bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
		bv.Velocity = Vector3.zero
		bv.Parent = root
		Move.FlyVel = bv
		local hum = getHum(player)
		if hum then hum.PlatformStand = true end
		Move.FlyConn = RunService.RenderStepped:Connect(function()
			if not Move.Fly or not Move.FlyVel or not Move.FlyVel.Parent then return end
			local cam = workspace.CurrentCamera
			local dir = Vector3.zero
			if UIS:IsKeyDown(Enum.KeyCode.W) then dir += cam.CFrame.LookVector end
			if UIS:IsKeyDown(Enum.KeyCode.S) then dir -= cam.CFrame.LookVector end
			if UIS:IsKeyDown(Enum.KeyCode.A) then dir -= cam.CFrame.RightVector end
			if UIS:IsKeyDown(Enum.KeyCode.D) then dir += cam.CFrame.RightVector end
			if UIS:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
			if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.yAxis end
			Move.FlyVel.Velocity = dir * Move.FlySpeed
		end)
	else
		if Move.FlyVel then Move.FlyVel:Destroy() Move.FlyVel = nil end
		local hum = getHum(player)
		if hum then hum.PlatformStand = false end
	end
	if not silent then Notify("Fly", state and "On." or "Off.") end
end

local function setNoclip(state, silent)
	Move.Noclip = state == true
	if Move.NoclipConn then Move.NoclipConn:Disconnect() Move.NoclipConn = nil end
	if Move.Noclip then
		Move.NoclipConn = RunService.Stepped:Connect(function()
			local char = player.Character
			if not char then return end
			for _, p in ipairs(char:GetDescendants()) do
				if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
			end
		end)
	else
		local char = player.Character
		if char then
			for _, p in ipairs(char:GetDescendants()) do
				if p:IsA("BasePart") then p.CanCollide = true end
			end
		end
	end
	if not silent then Notify("Noclip", state and "On." or "Off.") end
end

local function applySpeed(v)
	Move.Speed = math.clamp(tonumber(v) or 16, 8, 500)
	local hum = getHum(player)
	if hum then hum.WalkSpeed = Move.Speed end
end

local function applyJump(v)
	Move.Jump = math.clamp(tonumber(v) or 50, 50, 500)
	local hum = getHum(player)
	if hum then
		hum.JumpPower = Move.Jump
		hum.UseJumpPower = true
	end
end

local function setAntiFling(state, silent)
	Move.AntiFling = state == true
	if Move.FlingConn then Move.FlingConn:Disconnect() Move.FlingConn = nil end
	if Move.AntiFling then
		Move.FlingConn = RunService.Heartbeat:Connect(function()
			local root = getRoot(player)
			if not root or Move.Fly then return end
			local v = root.AssemblyLinearVelocity
			if v.Magnitude > 300 then
				root.AssemblyLinearVelocity = v.Unit * 300
			end
		end)
	end
	if not silent then Notify("Anti-Fling", state and "On." or "Off.") end
end

-- ============================================================
-- ESP
-- ============================================================
local ESP = { On = false, Folder = nil, Rows = {} }

local function espFolder()
	if ESP.Folder and ESP.Folder.Parent then return ESP.Folder end
	local parent = player:FindFirstChildOfClass("PlayerGui")
	if not parent then return nil end
	ESP.Folder = Instance.new("Folder")
	ESP.Folder.Name = "SVCEsp"
	ESP.Folder.Parent = parent
	return ESP.Folder
end

local function clearESP(p)
	local row = ESP.Rows[p]
	if not row then return end
	if row.Highlight then row.Highlight:Destroy() end
	if row.Billboard then row.Billboard:Destroy() end
	ESP.Rows[p] = nil
end

local function buildESP(p)
	if p == player then return end
	clearESP(p)
	local char = p.Character
	if not char then return end
	local head = char:FindFirstChild("Head")
	local folder = espFolder()
	if not head or not folder then return end

	local hl = Instance.new("Highlight")
	hl.FillColor = Color3.fromRGB(0, 170, 255)
	hl.OutlineColor = Color3.fromRGB(255, 255, 255)
	hl.FillTransparency = 0.75
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = char

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(300, 120)
	bb.StudsOffset = Vector3.new(0, 5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 5000
	bb.Adornee = head
	bb.Parent = folder

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 24
	label.TextStrokeTransparency = 0.15
	label.RichText = true
	label.Parent = bb

	ESP.Rows[p] = { Highlight = hl, Billboard = bb }

	task.spawn(function()
		while ESP.On and ESP.Rows[p] and bb.Parent do
			local ch = p.Character
			local lh = getHum(p)
			if not ch or not lh or lh.Health <= 0 then
				clearESP(p)
				break
			end
			local slaps = "?"
			local ls = p:FindFirstChild("leaderstats")
			local s = ls and ls:FindFirstChild("Slaps")
			if s then slaps = tostring(s.Value) end
			local glove = "none"
			for _, c in ipairs(ch:GetChildren()) do
				if c:IsA("Tool") then
					glove = c.Name
					break
				end
			end
			label.Text = '<font color="rgb(255,255,255)">' .. p.Name .. '</font>'
				.. '\n<font color="rgb(80,255,120)">HP: ' .. math.floor(lh.Health) .. '</font>'
				.. '\n<font color="rgb(255,215,70)">Slaps: ' .. slaps .. '</font>'
				.. '\n<font color="rgb(120,180,255)">Glove: ' .. glove .. '</font>'
			task.wait(1)
		end
	end)
end

local function setESP(state, silent)
	ESP.On = state == true
	if ESP.On then
		for _, p in ipairs(Players:GetPlayers()) do buildESP(p) end
	else
		for p in pairs(ESP.Rows) do clearESP(p) end
		if ESP.Folder then ESP.Folder:Destroy() ESP.Folder = nil end
	end
	if not silent then Notify("ESP", state and "On." or "Off.") end
end

-- ============================================================
-- SLAP FARM
-- ============================================================
local Farm = { On = false, Thread = nil, Delay = 0.25, Range = 0, Platform = nil, Glove = "", Spm = 0, Samples = {}, Watch = nil }

local function farmPlatform()
	if Farm.Platform and Farm.Platform.Parent then return Farm.Platform end
	local p = Instance.new("Part")
	p.Name = "SVCPlatform"
	p.Size = Vector3.new(4000, 2, 4000)
	p.Position = Vector3.new(0, -120, 0)
	p.Anchored = true
	p.CanCollide = true
	p.CanTouch = false
	p.CanQuery = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = Color3.fromRGB(15, 15, 18)
	p.Transparency = 0.35
	p.Parent = workspace
	Farm.Platform = p
	return p
end

local function equipGlove()
	if Farm.Glove == "" then return end
	local hum = getHum(player)
	local bp = player:FindFirstChild("Backpack")
	if not hum then return end
	local current = equippedTool()
	if current and norm(current.Name) == norm(Farm.Glove) then return end
	for _, c in ipairs((bp and bp:GetChildren()) or {}) do
		if c:IsA("Tool") and norm(c.Name) == norm(Farm.Glove) then
			pcall(function() hum:EquipTool(c) end)
			return
		end
	end
end

local function toPlatform()
	local root = getRoot(player)
	if not root then return end
	farmPlatform()
	moveRoot(root, CFrame.new(Vector3.new(0, -117, 0)))
	task.wait(0.1)
	local hum = getHum(player)
	if hum then
		hum.PlatformStand = false
		hum:ChangeState(Enum.HumanoidStateType.Running)
	end
end

local function startSpmWatch()
	if Farm.Watch then return end
	Farm.Watch = task.spawn(function()
		local last = nil
		while Farm.On do
			local ls = player:FindFirstChild("leaderstats")
			local s = ls and ls:FindFirstChild("Slaps")
			local now = s and s.Value or nil
			if now and last then
				table.insert(Farm.Samples, { t = os.clock(), d = now - last })
				while Farm.Samples[1] and os.clock() - Farm.Samples[1].t > 60 do
					table.remove(Farm.Samples, 1)
				end
				local total = 0
				for _, e in ipairs(Farm.Samples) do total += e.d end
				Farm.Spm = math.floor(total)
			end
			last = now
			task.wait(1)
		end
		Farm.Watch = nil
		Farm.Spm = 0
		Farm.Samples = {}
	end)
end

local function startFarm()
	if Farm.Thread then return end
	if not slapRemote() then
		Notify("Slap Farm", "Slap remote niet gevonden. Hub is mogelijk verouderd.", 4)
	end
	Farm.Thread = task.spawn(function()
		setAnti(true, true)
		setAntiFling(true, true)
		toPlatform()

		while Farm.On do
			local root = getRoot(player)
			if not root then
				task.wait(0.5)
			else
				if root.Position.Y > -110 then toPlatform() end
				equipGlove()

				local r = slapRemote()
				if r then
					for _, p in ipairs(Players:GetPlayers()) do
						local tr = validTarget(p)
						if tr and (Farm.Range == 0 or (root.Position - tr.Position).Magnitude <= Farm.Range) then
							pcall(function() r:FireServer(tr) end)
						end
					end
				end
			end
			task.wait(Farm.Delay)
		end

		Farm.Thread = nil
	end)
	startSpmWatch()
end

local function setFarm(state, silent)
	Farm.On = state == true
	if Farm.On then
		startFarm()
	else
		if Farm.Thread then Farm.Thread = nil end
		if Farm.Watch then Farm.Watch = nil end
		Farm.Spm = 0
		setAnti(false, true)
		setAntiFling(false, true)
		local root = getRoot(player)
		if root then moveRoot(root, groundCFrame(root.Position, { player.Character })) end
	end
	if not silent then
		Notify("Slap Farm", state and "Farming op het verborgen platform." or "Gestopt.")
	end
end

local function setFarmDelay(v)
	Farm.Delay = math.clamp(tonumber(v) or 0.25, 0.05, 1)
end

local function setFarmRange(v)
	Farm.Range = math.clamp(tonumber(v) or 0, 0, 100000)
end

-- ============================================================
-- AUTO REJOIN / HOP
-- ============================================================
local Rejoin = { On = false, Conns = {} }

local function clearRejoin()
	for _, c in ipairs(Rejoin.Conns) do pcall(function() c:Disconnect() end) end
	Rejoin.Conns = {}
end

local function bestServer(place, random)
	local body = httpGet("https://games.roblox.com/v1/games/" .. place .. "/servers/Public?sortOrder=Desc&limit=100")
	if not body then return nil end
	local ok, job = pcall(function()
		local data = Services.HttpService:JSONDecode(body)
		local pool = {}
		for _, s in ipairs(data.data or {}) do
			local playing = tonumber(s.playing) or 0
			if s.id ~= game.JobId and playing < 25 then
				table.insert(pool, s.id)
			end
		end
		if #pool == 0 then return nil end
		if random then return pool[math.random(1, #pool)] end
		return pool[1]
	end)
	if ok and job then return job end
	return nil
end

local function doRejoin(random)
	local place = game.PlaceId
	Notify("Rejoin", "Bezig met rejoinen...")
	local job = bestServer(place, random)
	if job then
		local ok = pcall(function()
			Services.TeleportService:TeleportToPlaceInstance(place, job, player)
		end)
		if ok then return end
	end
	pcall(function() Services.TeleportService:Teleport(place, player) end)
end

local function setRejoin(state, silent)
	Rejoin.On = state == true
	clearRejoin()
	if Rejoin.On then
		local function hook(char)
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if not hum then return end
			table.insert(Rejoin.Conns, hum.Died:Connect(function()
				if Rejoin.On then
					task.wait(0.5)
					doRejoin(false)
				end
			end))
		end
		hook(player.Character)
		table.insert(Rejoin.Conns, player.CharacterAdded:Connect(function(c)
			task.wait(0.3)
			if Rejoin.On then hook(c) end
		end))
		pcall(function()
			table.insert(Rejoin.Conns, Services.GuiService.ErrorMessageChanged:Connect(function()
				if Rejoin.On then doRejoin(false) end
			end))
		end)
	end
	if not silent then Notify("Auto Rejoin", state and "On." or "Off.") end
end

-- ============================================================
-- BADGES
-- ============================================================
local Badges = {
	List = {
		{ "Welcome", 2124743766 },
		{ "You met the owner", 2124760252 },
		{ "you met snow", 2124760875 },
		{ "[REDACTED]", 2124760911 },
		{ "Divine punishment", 2124760917 },
		{ "barzil", 2124775097 },
		{ "The one", 2124807750 },
		{ "Ascend", 2124807752 },
		{ "1 0 0", 2124836270 },
		{ "The Reverse Incident", 2124912059 },
		{ "Clipped Wings", 2147535393 },
		{ "Apostle of Judgement", 4414399146292319 },
		{ "Error glove", 2124760254 },
		{ "ez", 2124760895 },
		{ "court evidence", 2124760907 },
		{ "the touch of midas", 2124760928 },
		{ "really?", 2124760923 },
		{ "WHY", 2124807768 },
		{ "Infected", 2124819262 },
		{ "Jack's will", 2124836318 },
		{ "Evaded", 2124847850 },
		{ "250", 2124854307 },
		{ "To the moon", 2124858899 },
		{ "Lucky Gift", 2124875920 },
		{ "Unphased", 2124886261 },
		{ "Savior", 2124914780 },
		{ "Short fuse", 2124919840 },
		{ "Harbinger of death", 2124925929 },
		{ "Orb of Flight", 2124930374 },
		{ "Firefighter", 2124938910 },
		{ "Sorry to burst your bubble", 2124989121 },
		{ "good job", 2125850245 },
		{ "bob", 2125950512 },
		{ "Death Dodger", 2126334003 },
		{ "Predator", 2126450753 },
		{ "Head Hunter", 2126589561 },
		{ "Anticlimactic End", 2127132894 },
		{ "Brick Master", 2127567042 },
		{ "YOU MONSTER", 2127703232 },
		{ "Island Conqueror", 2127816588 },
		{ "Prolonged Anger", 2127861437 },
		{ "The Golden Slapple", 2128012376 },
		{ "Memento Mori", 2128233612 },
		{ "THE ACCIDENT", 2128557186 },
		{ "Candy King", 2128772719 },
		{ "Witch Brew", 2129002959 },
		{ "Killer", 2129104684 },
		{ "Plate Master", 2129212145 },
		{ "what", 2129474790 },
		{ "01010010 01010101 01001110", 2129568267 },
		{ "Engineer's Gift", 2129648848 },
		{ "EXPOSED", 2129871858 },
		{ "RNGod", 2130031244 },
		{ "DEEP SLUMBER", 2130032297 },
		{ "ULTRAROCK", 2130463063 },
		{ "Insanity", 2132544202 },
		{ "CHAOS", 2133016756 },
		{ "Demonic Ritual", 2136607413 },
		{ "Underkill", 2140855364 },
		{ "Kinetically Charged", 2141386326 },
		{ "GO BERSERK", 2141784233 },
		{ "Incredible Running Man", 2142826462 },
		{ "Boogie With It", 2143034526 },
		{ "Repressed Memories", 2143973603 },
		{ "Blasting Off Again", 2144766764 },
		{ "Ultimate Control", 2145165421 },
		{ "Escape the Abyss", 2145381761 },
		{ "Da Maze Runner", 2146130728 },
		{ "Toolbox", 2146540403 },
		{ "Emissary Of Light", 2147429609 },
		{ "Total Rhythm", 2148234934 },
		{ "See in the dark", 2148480065 },
		{ "Sharp Shooter", 2148934270 },
		{ "Parkour Pwner", 2149637240 },
		{ "The Relic", 2150485950 },
		{ "Catch Emm All", 2151266964 },
		{ "Great Escape", 2152295593 },
		{ "Sweet-Tooth Sovereign", 2152906832 },
		{ "Containment Breach", 2153473254 },
		{ "Gardens And Ghouls", 2153911928 },
		{ "Now You See Me", 2500227230783997 },
		{ "Farmland Fray", 3318257806017965 },
		{ "Yuletime Might", 2895206704788569 },
		{ "Slap Battles: On Ice", 2906002612987222 },
		{ "G-Grandson..?", 3335299217032061 },
		{ "Into the Crypt", 4404799574333856 },
		{ "CERTIFIED ADMIN", 1840188608156642 },
		{ "Stand your ground", 1662954021427606 },
		{ "Easy As Pie", 2628581469266954 },
		{ "It's Finally Over...", 1579276416564374 },
		{ "The Hunt", 128402905805563 },
		{ "Null Piercer", 342573645147372 },
		{ "Friend of the Dark", 490455814138437 },
		{ "Code Breaker", 1962623816699442 },
		{ "Ice Essence", 1286358044443937 },
		{ "Cranking 90's", 4031317971987872 },
		{ "SLAP BATTLES SWEEP", 2236076719770808 },
		{ "Leap of Faith", 1354956782555226 },
		{ "Caution: High Voltage", 187186758930457 },
		{ "UberCharged", 2240434593038483 },
		{ "Nah, I'd win", 4414076328730650 },
		{ "A Guiding Hand", 154204790800271 },
		{ "Bounty Claimed", 3483144763925839 },
		{ "How did we get here?", 2193861648156971 },
		{ "FREE OOG!", 2657379023348335 },
		{ "The Glove", 1223765330375569 },
		{ "Orb of Honor", 4256352459948010 },
		{ "Garden of Erasure", 3199562682373814 },
		{ "Fetch me their Souls", 868768988664040 },
		{ "Shattered Memories", 2035627575374951 },
		{ "Hurt me plenty", 2223110832777636 },
		{ "Fortress of Dreams", 4390302507334168 },
		{ "You're gonna need a bigger glove", 2117833544213343 },
		{ "Snow man left behind", 182408299845710 },
		{ "Insane Minds think Alike", 3726156327470282 },
		{ "Oh! That's a Baseball!", 2460702219299014 },
		{ "Rats, We're Rats, We're the Rats", 2146300368310575 },
		{ "Enlightened", 2090213992277846 },
		{ "Day in the life of a small Game Developer", 1060832194529561 },
		{ "Sword Fighter of The Heights", 1788920058870613 },
		{ "Pillow Fight", 99649310086892 },
		{ "Egging Over It", 2286252038116816 },
		{ "Collect My Pages", 2442504376213257 },
		{ "Captain's Orders", 3096378656988806 },
		{ "Banished", 4342029848828580 },
		{ "Reawoken", 231810132716643 },
		{ "Slappy Wheels", 1294103285471925 },
		{ "Plungering Heights", 3798851936234989 },
		{ "Shattered Reality", 1745844401258079 },
		{ "Dodecacide", 663807976473858 },
		{ "Die Hard", 1605140663413534 },
		{ "Dead or Alive", 1133862849283260 },
		{ "Out of Bounds", 117389283982009 },
		{ "Color Splash", 1035608345203235 },
		{ "Ceramic Panic", 1198780403030188 },
		{ "2000 Ping", 3713925567966983 },
		{ "The Cornfeared", 847759908824783 },
		{ "Bullseye", 65341581701492 },
		{ "Autumnal Conkerer", 1304426038175458 },
		{ "Glass Bones", 659930747853345 },
		{ "Snowball Synergy", 2748677045206815 },
		{ "Minimum Wage", 1698466561019878 },
		{ "Find The Gloves", 1902849233175110 },
		{ "Cleaved in Two", 1778876340809040 },
		{ "Birthday Bash", 217389347032866 },
		{ "Hibernal Snowstopper", 996318649761767 },
		{ "Untimely End", 1239535438142380 },
		{ "Clobbering Time!", 4207775293625676 },
		{ "Easter Hatchastrophe", 2604207010521588 },
		{ "Genuinely how am I still alive", 1662521369541218 },
		{ "Vernal Floralscence", 3964935687406576 },
		{ "Fix my dang 'puter", 1703260768466206 },
		{ "Gum, Gummy, Gone", 3344995751929220 },
		{ "The Door In-between", 2886410353565684 },
		{ "Fatal Frame", 3607811029078582 },
		{ "Order Up!", 3169767311342466 },
		{ "Return to Sender", 998328913122542 },
		{ "Unmasked", 4138993615060923 },
		{ "Banish the Night", 1553597577215698 },
		{ "Estival Heatwaver", 2330016192496771 },
		{ "Infinite Cobblestone Generator", 1416879820741487 },
		{ "S P L A T", 4249463317430741 },
		{ "It's Hip to be Square", 3555494191247249 },
		{ "Salvaged Code", 3561443203465110 },
		{ "Treated to Tricks", 1989422796765183 },
		{ "Project: Facsimile", 3549710749798161 },
		{ "duck", 2124760916 },
		{ "The Lone Orange", 2128220957 },
		{ "Slapping master", 2124760881 },
		{ "The Backrooms", 2124929812 },
		{ "pog", 2124760877 },
	},
	Owned = {},
	Scanning = false,
	Clicking = false,
	ClickThread = nil,
	ClickRange = 250,
	Found = {},
}

local function badgeUrl(id) return "https://www.roblox.com/badges/" .. tostring(id) end

local function hasBadge(id)
	local ok, res = pcall(function() return BadgeService:UserHasBadgeAsync(player.UserId, id) end)
	if ok then return res == true end
	return nil
end

local function checkOne(name, id)
	local res = hasBadge(id)
	if res == nil then
		Notify("Badge", "Rate limited, probeer opnieuw.", 2)
		return
	end
	Badges.Owned[id] = res
	Notify(name, res and "Owned." or "Niet owned.", 2.5)
end

local function checkAll()
	if Badges.Scanning then
		Badges.Scanning = false
		Notify("Badge check", "Gestopt.")
		return
	end
	Badges.Scanning = true
	Notify("Badge check", "Bezig met " .. #Badges.List .. " badges...", 3)
	task.spawn(function()
		local count = 0
		for _, entry in ipairs(Badges.List) do
			if not Badges.Scanning then break end
			local res = hasBadge(entry[2])
			if res ~= nil then
				Badges.Owned[entry[2]] = res
				if res then count += 1 end
			end
			task.wait(0.12)
		end
		Badges.Scanning = false
		Notify("Badge check", "Klaar. Owned: " .. count .. " / " .. #Badges.List, 5)
	end)
end

local function clickables(range)
	local root = getRoot(player)
	if not root then return {} end
	local out = {}
	for _, o in ipairs(workspace:GetDescendants()) do
		if o:IsA("ClickDetector") then
			local part = o.Parent
			if part and part:IsA("BasePart") then
				local d = (root.Position - part.Position).Magnitude
				if d <= range then
					table.insert(out, { cd = o, part = part, dist = d })
				end
			end
		end
	end
	table.sort(out, function(a, b) return a.dist < b.dist end)
	return out
end

-- GEFIXT: '?' was ongeldige syntax en sloopte de hele compile
local function fireCd(cd)
	if not cd then return end
	pcall(function()
		if type(fireclickdetector) == "function" then
			fireclickdetector(cd, 1)
			return
		end
		if type(getconnections) == "function" then
			local fired = false
			for _, c in ipairs(getconnections(cd.MouseClick) or {}) do
				if type(c.Fire) == "function" then
					c:Fire()
					fired = true
				end
			end
			if fired then return end
		end
		if type(cd.FireServer) == "function" then
			cd:FireServer()
		end
	end)
end

local function scanClickables()
	local found = clickables(Badges.ClickRange)
	Badges.Found = found
	Notify("Scanner", #found .. " clickables in bereik.", 3)
	for i = 1, math.min(#found, 6) do
		local f = found[i]
		print(string.format("[SVCLUTCHER] %s - %d studs", f.part:GetFullName(), math.floor(f.dist)))
	end
	return found
end

local function startAutoClick()
	if Badges.ClickThread then return end
	Badges.ClickThread = task.spawn(function()
		while Badges.Clicking do
			local found = clickables(Badges.ClickRange)
			local root = getRoot(player)
			if root and #found > 0 then
				local target = found[1]
				moveRoot(root, groundCFrame(target.part.Position, { player.Character }))
				task.wait(0.2)
				fireCd(target.cd)
				task.wait(0.4)
			else
				task.wait(0.6)
			end
		end
		Badges.ClickThread = nil
	end)
end

local function setAutoClick(state, silent)
	Badges.Clicking = state == true
	if Badges.Clicking then startAutoClick() elseif Badges.ClickThread then Badges.ClickThread = nil end
	if not silent then Notify("Auto Click", state and "On." or "Off.") end
end

-- ============================================================
-- PLAYER LIST / FREEZE
-- ============================================================
local function teleportTo(p)
	local root, tr = getRoot(player), getRoot(p)
	if not root or not tr then
		Notify("Teleport", "Niet beschikbaar.")
		return
	end
	moveRoot(root, groundCFrame(tr.Position, { player.Character, p.Character }))
	local hum = getHum(player)
	if hum then hum.PlatformStand = false end
end

local function nearestPlayer()
	local root = getRoot(player)
	if not root then return nil end
	local best, dist = nil, math.huge
	for _, p in ipairs(Players:GetPlayers()) do
		local tr = validTarget(p)
		if tr then
			local d = (root.Position - tr.Position).Magnitude
			if d < dist then
				best, dist = p, d
			end
		end
	end
	return best
end

local function lowestPlayer()
	local best, hp = nil, math.huge
	for _, p in ipairs(Players:GetPlayers()) do
		local hum = getHum(p)
		if hum and hum.Health > 0 and hum.Health < hp and p ~= player then
			best, hp = p, hum.Health
		end
	end
	return best
end

local Frozen = {}

local function freeze(p)
	local root = getRoot(p)
	if not root then return end
	Frozen[p] = not Frozen[p]
	root.Anchored = Frozen[p]
	Notify("Freeze", p.Name .. (Frozen[p] and " frozen." or " unfrozen."))
end

-- ============================================================
-- SLAP HUD
-- ============================================================
local HUD = { On = false, Gui = nil, Label = nil }

local function setHUD(state, silent)
	HUD.On = state == true
	if not HUD.On then
		if HUD.Gui then HUD.Gui:Destroy() HUD.Gui = nil end
		return
	end
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then return end
	local gui = Instance.new("ScreenGui")
	gui.Name = "SVCHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = pg
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromOffset(260, 34)
	label.Position = UDim2.new(0, 14, 0, 14)
	label.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
	label.BackgroundTransparency = 0.25
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.TextSize = 15
	label.TextColor3 = Color3.fromRGB(57, 255, 20)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = gui
	HUD.Gui, HUD.Label = gui, label

	task.spawn(function()
		while HUD.On and HUD.Gui do
			local ls = player:FindFirstChild("leaderstats")
			local s = ls and ls:FindFirstChild("Slaps")
			label.Text = "  SLAPS: " .. (s and tostring(s.Value) or "?")
				.. (Farm.On and ("   |   " .. Farm.Spm .. "/min") or "")
			task.wait(0.5)
		end
	end)

	if not silent then Notify("HUD", "On.") end
end

-- ============================================================
-- HOOKS
-- ============================================================
Players.PlayerAdded:Connect(function(p)
	if ESP.On then
		task.wait(0.5)
		buildESP(p)
	end
end)

Players.PlayerRemoving:Connect(function(p)
	clearESP(p)
	resetHitbox(p)
	Frozen[p] = nil
end)

player.CharacterAdded:Connect(function()
	task.wait(0.5)
	local hum = getHum(player)
	if hum then
		hum.WalkSpeed = Move.Speed
		hum.JumpPower = Move.Jump
		hum.UseJumpPower = true
	end
	if ESP.On then
		for _, p in ipairs(Players:GetPlayers()) do buildESP(p) end
	end
	if Farm.On then
		task.wait(0.4)
		toPlatform()
	end
end)

-- ============================================================
-- UI
-- ============================================================
local Window = WindUI:CreateWindow({
	Title = "SVCLUTCHER HUB",
	Icon = "terminal",
	Author = "slap battles",
	Folder = "SVCLUTCHER_HUB",
	Size = UDim2.fromOffset(580, 450),
	ToggleKey = Enum.KeyCode.T,
	Transparent = true,
	Theme = "Matrix",
	SideBarWidth = 190,
})

local TabCombat = Window:Tab({ Title = "COMBAT", Icon = "swords" })
local TabFarm = Window:Tab({ Title = "SLAP FARM", Icon = "wheat" })
local TabBadges = Window:Tab({ Title = "BADGES", Icon = "award" })
local TabMove = Window:Tab({ Title = "MOVE", Icon = "map-pin" })
local TabPlayers = Window:Tab({ Title = "PLAYERS", Icon = "users" })
local TabVisuals = Window:Tab({ Title = "VISUALS", Icon = "eye" })
local TabSafety = Window:Tab({ Title = "SAFETY", Icon = "shield" })
local TabSettings = Window:Tab({ Title = "SETTINGS", Icon = "wrench" })

-- COMBAT
TabCombat:Toggle({ Title = "Expand Hitbox", Desc = "Neon kubus op vijandelijke roots", Color = Color3.fromRGB(57, 255, 20), Value = false, Callback = function(v) setHitbox(v == true) end })
TabCombat:Slider({ Title = "Hitbox Size", Step = 1, Value = { Min = 10, Max = 25, Default = 14 }, Callback = function(v) setHitboxSize(v) end })
TabCombat:Toggle({ Title = "Show Hitboxes", Desc = "Zichtbaarheid van de kubus", Color = Color3.fromRGB(57, 255, 20), Value = true, Callback = function(v) setVisible(v == true) end })
TabCombat:Toggle({ Title = "Slap Aura", Desc = "Spamt Remotes.Slap in bereik", Color = Color3.fromRGB(57, 255, 20), Value = false, Callback = function(v) setAura(v == true) end })
TabCombat:Slider({ Title = "Aura Range", Step = 1, Value = { Min = 5, Max = 60, Default = 20 }, Callback = function(v) Combat.Range = math.clamp(v, 5, 60) end })
TabCombat:Toggle({ Title = "Auto Slap", Desc = "Activeert glove bij contact", Color = Color3.fromRGB(57, 255, 20), Value = false, Callback = function(v) setAutoSlap(v == true) end })
TabCombat:Button({ Title = "Teleport to Nearest", Icon = "crosshair", Callback = function()
	local p = nearestPlayer()
	if p then teleportTo(p) else Notify("Teleport", "Niemand gevonden.") end
end })
TabCombat:Button({ Title = "Teleport to Lowest HP", Icon = "heart-pulse", Callback = function()
	local p = lowestPlayer()
	if p then teleportTo(p) else Notify("Teleport", "Niemand gevonden.") end
end })

-- FARM
TabFarm:Toggle({ Title = "Slap Farm", Desc = "Verborgen platform + remote spam", Color = Color3.fromRGB(57, 255, 20), Value = false, Callback = function(v) setFarm(v == true) end })
TabFarm:Slider({ Title = "Tick Delay", Desc = "Lager = meer slaps, meer risico", Step = 0.05, Value = { Min = 0.05, Max = 1, Default = 0.25 }, Callback = setFarmDelay })
TabFarm:Slider({ Title = "Range (0 = hele arena)", Step = 50, Value = { Min = 0, Max = 5000, Default = 0 }, Callback = setFarmRange })
TabFarm:Textbox({ Title = "Auto-Equip Glove", Desc = "Exacte glove-naam, leeg = overslaan", Value = "", Callback = function(v) Farm.Glove = tostring(v or "") end })
TabFarm:Toggle({ Title = "Auto Rejoin on Death", Desc = "Herstart de farm automatisch", Color = Color3.fromRGB(57, 255, 20), Value = false, Callback = function(v) setRejoin(v == true) end })
TabFarm:Button({ Title = "Go to Platform", Icon = "arrow-down", Callback = function() toPlatform() end })
TabFarm:Button({ Title = "Reset Position", Icon = "undo", Callback = function()
	local root = getRoot(player)
	if root then moveRoot(root, groundCFrame(root.Position, { player.Character })) end
end })

-- BADGES
local ownedLabel
local badgeNames = {}
for _, e in ipairs(Badges.List) do table.insert(badgeNames, e[1]) end

TabBadges:Paragraph({ Title = "Badge Tracker", Desc = "Roblox rate-limit checks, reken op ~1 per 0.12s." })
ownedLabel = TabBadges:Paragraph({ Title = "Owned", Desc = "0 / " .. #Badges.List })

local selectedBadge = nil
TabBadges:Dropdown({
	Title = "Select Badge",
	Values = badgeNames,
	Multi = false,
	Callback = function(v)
		selectedBadge = v
	end,
})

TabBadges:Button({ Title = "Check Selected", Icon = "search", Callback = function()
	if not selectedBadge then Notify("Badge", "Kies eerst een badge.") return end
	for _, e in ipairs(Badges.List) do
		if e[1] == selectedBadge then
			checkOne(e[1], e[2])
			return
		end
	end
end })

TabBadges:Button({ Title = "Check All / Stop", Icon = "list-checks", Callback = checkAll })

TabBadges:Button({ Title = "Open Selected On Roblox", Icon = "external-link", Callback = function()
	if not selectedBadge then Notify("Badge", "Kies eerst een badge.") return end
	for _, e in ipairs(Badges.List) do
		if e[1] == selectedBadge then
			pcall(function() setclipboard(badgeUrl(e[2])) end)
			Notify("Badge", "Link gekopieerd: " .. e[1], 3)
			return
		end
	end
end })

TabBadges:Textbox({ Title = "Check Custom Badge ID", Value = "", Callback = function(v)
	local id = tonumber(v)
	if not id then Notify("Badge", "Alleen cijfers.") return end
	checkOne("Badge " .. id, id)
end })

TabBadges:Slider({ Title = "Click Scan Range", Step = 25, Value = { Min = 50, Max = 1000, Default = 250 }, Callback = function(v) Badges.ClickRange = v end })
TabBadges:Button({ Title = "Scan Clickables", Desc = "Toont click detectors in de buurt", Icon = "radar", Callback = scanClickables })
TabBadges:Toggle({ Title = "Auto Click Nearest", Desc = "Teleporteert naar en klikt clickables", Color = Color3.fromRGB(57, 255, 20), Value = false, Callback = function(v) setAutoClick(v == true) end })

task.spawn(function()
	while ownedLabel do
		local n = 0
		for _, e in ipairs(Badges.List) do
			if Badges.Owned[e[2]] == true then n += 1 end
		end
		pcall(function() ownedLabel:Set({ Title = "Owned", Desc = n .. " / " .. #Badges.List }) end)
		task.wait(1.5)
	end
end)

-- MOVE
TabMove:Toggle({ Title = "Infinite Jump", Color = Color3.fromRGB(57, 255, 20), Value = false, Callback = function(v) setInfJump(v == true) end })
TabMove:Toggle({ Title = "Fly", Desc = "WASD + Space / LCTRL", Color = Color3.fromRGB(57, 255, 20), Value = false, Callback = function(v) setFly(v == true) end })
TabMove:Slider({ Title = "Fly Speed", Step = 5, Value = { Min = 10, Max = 300, Default = 60 }, Callback = function(v) Move.FlySpeed = v end })
TabMove:Toggle({ Title = "Noclip", Color = Color3.fromRGB(57, 255, 20), Value = false, Callback = function(v) setNoclip(v == true) end })
TabMove:Slider({ Title = "Walk Speed", Step = 1, Value = { Min = 8, Max = 300, Default = 16 }, Callback = applySpeed })
TabMove:Slider({ Title = "Jump Power", Step = 1, Value = { Min = 50, Max = 300, Default = 50 }, Callback = applyJump })

-- PLAYERS
local PlayerListSection = TabPlayers:Section({ Title = "Players" })
local playerButtons = {}

local function rebuildPlayerList()
	for _, b in ipairs(playerButtons) do pcall(function() b:Destroy() end) end
	playerButtons = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			local hum = getHum(p)
			local btn = PlayerListSection:Button({
				Title = p.Name,
				Desc = hum and ("HP " .. math.floor(hum.Health)) or "",
				Icon = "user",
				Callback = function() teleportTo(p) end,
			})
			table.insert(playerButtons, btn)
		end
	end
end

TabPlayers:Button({ Title = "Refresh List", Icon = "refresh-cw", Callback = rebuildPlayerList })
TabPlayers:Button({ Title = "Freeze Nearest", Icon = "snowflake", Callback = function()
	local p = nearestPlayer()
	if p then freeze(p) else Notify("Freeze", "Niemand gevonden.") end
end })
TabPlayers:Button({ Title = "Unfreeze All", Icon = "sun", Callback = function()
	for p, on in pairs(Frozen) do
		if on then
			local root = getRoot(p)
			if root then root.Anchored = false end
			Frozen[p] = nil
		end
	end
	Notify("Freeze", "Alles losgelaten.")
end })
rebuildPlayerList()
Players.PlayerAdded:Connect(function() task.wait(0.5) rebuildPlayerList() end)
Players.PlayerRemoving:Connect(function() task.wait(0.2) rebuildPlayerList() end)

-- VISUALS
TabVisuals:Toggle({ Title = "Player ESP", Desc = "Naam, HP, slaps, glove", Color = Color3.fromRGB(57, 255, 20), Value = false, Callback = function(v) setESP(v == true) end })
TabVisuals:Toggle({ Title = "Slap HUD", Desc = "Teller met farm-snelheid", Color = Color3.fromRGB(57, 255, 20), Value = false, Callback = function(v) setHUD(v == true) end })

-- SAFETY
TabSafety:Toggle({ Title = "Anti-Ragdoll", Desc = "Onzichtbare kooi bij knockback", Color = Color3.fromRGB(57, 255, 20), Value = false, Callback = function(v) setAnti(v == true) end })
TabSafety:Toggle({ Title = "Anti-Fling", Desc = "Klemt velocity-pieken af", Color = Color3.fromRGB(57, 255, 20), Value = false, Callback = function(v) setAntiFling(v == true) end })
TabSafety:Toggle({ Title = "Auto Rejoin", Color = Color3.fromRGB(57, 255, 20), Value = false, Callback = function(v) setRejoin(v == true) end })

-- SETTINGS
TabSettings:Toggle({ Title = "Mute Notifications", Color = Color3.fromRGB(57, 255, 20), Value = false, Callback = function(v) Muted = v == true end })
TabSettings:Button({ Title = "Server Hop", Icon = "shuffle", Callback = function() doRejoin(true) end })
TabSettings:Button({ Title = "Rejoin", Icon = "rotate-ccw", Callback = function() doRejoin(false) end })
TabSettings:Button({ Title = "Unload Hub", Icon = "trash-2", Callback = function()
	if type(env.SVCLUTCHER_Cleanup) == "function" then env.SVCLUTCHER_Cleanup() end
end })

Notify("SVCLUTCHER", "Geladen. Farm-tab is de moneymaker.", 3)

-- ============================================================
-- CLEANUP
-- ============================================================
env.SVCLUTCHER_Cleanup = function()
	pcall(function() setFarm(false, true) end)
	pcall(function() setHitbox(false, true) end)
	pcall(function() setAura(false, true) end)
	pcall(function() setAutoSlap(false, true) end)
	pcall(function() setESP(false, true) end)
	pcall(function() setAnti(false, true) end)
	pcall(function() setAntiFling(false, true) end)
	pcall(function() setInfJump(false, true) end)
	pcall(function() setFly(false, true) end)
	pcall(function() setNoclip(false, true) end)
	pcall(function() setRejoin(false, true) end)
	pcall(function() setAutoClick(false, true) end)
	pcall(function() setHUD(false, true) end)
	pcall(function() if Farm.Platform then Farm.Platform:Destroy() Farm.Platform = nil end end)
	pcall(function() clearCage() end)
	pcall(function() if Window and Window.Destroy then Window:Destroy() end end)
	env.SVCLUTCHER_HUB = nil
end

env.SVCLUTCHER_HUB = { Window = Window, Farm = Farm, Badges = Badges, Notify = Notify }

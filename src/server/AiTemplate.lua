--[[
    Civilian Ai
    Emskipo
    Sept 16 2023

	Ai for Civilian NPCs. Anything specific to Civilian NPCs
	should be handled here.
	
--]]

--{ SERVICES }--

local PlayerServ = game:GetService("Players")
local RunServ = game:GetService("RunService")
local RepStor = game:GetService("ReplicatedStorage")
local ScriptServ = game:GetService("ServerScriptService")
local TweenServ = game:GetService("TweenService")


--{ REQUIRED }--

local Types
local ToolEm
local MapPaths
local Cortex
local React
local HitBox
local WantedServer


--( MODULE )--

local Ai = {}
Ai.__index = Ai
Ai.ClassName = "CivilianAi"
Ai.IsReady = false

local _ReadyEvent = Instance.new("BindableEvent")
Ai.Ready = _ReadyEvent.Event


--{ TYPE DEF }--

type ToolEm = Types.ToolEm
type Cortex = Types.Cortex
type AgentParams = Types.AgentParams
type BoardTool = Types.BoardTool
type CharDetect = Types.CharDetect
type DetectionDetails = Types.DetectionDetails
type Ai = Types.Ai
type TrickData = Types.TrickData
type WantedServer = Types.WantedServer
--type TrickServer = TrickServer.TrickServer


--{ CONSTANTS }--

local OBJ_LIST = {}--List of instances by CharModelObj

local PATH_COSTS
local NPC_SPAWNS
local SKATE_SHOP_SPAWN
local POLICE_STATION_SPAWN
local PATROL_POINTS = {}


--{ PRIVATE }--

local function OnHitTaken(self: Ai, wepHitBox)
	React.Attacked(self, wepHitBox:GetAttribute("OwnerId"))

	--Did another player hit me?
	local attacker = HitBox.GetOwnerByHitbox(wepHitBox)
	if(attacker and attacker:IsA("Player"))then

		--Get Wanted Obj
		local wantedObj = WantedServer.GetInstance(attacker, true)
		wantedObj:ReportCrime("Violence")
	end
end

local function OnHPChanged(self: Ai, oldHP: number, newHP: number)
	--IF HITPOINTS REACHES ZERO, THE NPC SHOULD BE DESTROYED.
	if(newHP <= 0)then
		self.Cortex:StunNPC()
		task.wait(3)
		self:Destroy()
		return
	end

	local hitbox = HitBox.GetInstance(self.NPC, true)
	if(not(hitbox))then return end
	
	local consciousness = math.min(1, math.max(0, newHP/hitbox.MaxHitPoints))
	if(self.NPC:FindFirstChildWhichIsA("Humanoid"))then
		local maxWalkSpeed = self.NPC.Humanoid:GetAttribute("DefaultSpeed")
		local newSpeed = maxWalkSpeed * consciousness
		newSpeed = math.min(maxWalkSpeed, newSpeed) --no higher than max
		newSpeed = math.max(.2, newSpeed)-- no lower than max-4
		self.NPC.Humanoid.WalkSpeed = newSpeed
		--print("Consciousness:", consciousness)
		--print("Changing walkspeed:", newSpeed)
	end
end

--Handles the Character detected event
--local function OnCharDetected(self: Ai, char: Model, dist: number, timeDetected: number)
local function OnCharDetected(self: Ai, char: Model, details: DetectionDetails)
	if(not(self and char))then return end

    --Check for a player associated with the character
	local player = PlayerServ:GetPlayerFromCharacter(char)
	if(not(player))then return end--Ignore other NPCs (for now)

	--React to detection of the char
	local wantedObj = WantedServer.GetInstance(player)
	if(wantedObj)then
		local wantedLvl, wantedType = wantedObj:GetWantedLvl()
		if(wantedType == "Crime" and wantedLvl > 0)then
			React.MeetUp(self, char, "Crime")
			return
		end
	end
	React.MeetUp(self, char)
end

--Handles the Character lost event
local function OnCharLost(self: Ai, char: Model, details: DetectionDetails)
	if(not(self and char))then return end
end

--Handles the TripEnded Event
local function OnTripEnded(self: Ai, ...)
	self:Disable()
	self:Destroy()
end

local function OnDestReached(self: Ai, ...)
	return
end

--Heartbeat callback function
local function OnHeartbeat(self: Ai, ...)
	--If AI is enabled, then activate it.
	if(self.Enabled)then self:Cognize() end
end

--Connect listeners for common events
local function ConnectEvents(self: Ai)

	self._Conns[#self._Conns+1] = self.Cortex.DestReached:Connect(function(...)
        OnDestReached(self, ...)
	end)

	--Connect to Heartbeat?
	self._Conns[#self._Conns+1] = RunServ.Heartbeat:Connect(function(...)
        OnHeartbeat(self, ...)
	end)

	self._Conns[#self._Conns+1] = self.NPC.Humanoid.Died:Connect(function()
		self:Disable()
	end)

	self._Conns[#self._Conns+1] = self.NPC.Humanoid.Destroying:Connect(function()
		self:Disable()
	end)
end


--{ PUBLIC }--

function Ai.Initialize()
	Types = require(RepStor.SharedData.TypeDict)
	ToolEm = require(RepStor.SharedData.ToolEm)
	MapPaths = require(RepStor.SharedData.MapPaths)
	ToolEm.Echo("Loading: CivilianAi")

	Cortex = require(RepStor.SharedData.Cortex)
	React = require(RepStor.SharedData.Cortex.React)
	HitBox = require(ScriptServ.Server.HitBox)
	WantedServer = require(ScriptServ.Server.WantedServer)
end

function Ai.Run()
	ToolEm.Echo("Running: CivilianAi")

	task.spawn(function()
		PATH_COSTS = MapPaths.GetMapCosts()
		NPC_SPAWNS = game.Workspace:WaitForChild("NPC_Spawns")
		SKATE_SHOP_SPAWN = NPC_SPAWNS:WaitForChild("SkateShop")
		POLICE_STATION_SPAWN = NPC_SPAWNS:WaitForChild("PoliceStation")

		local tmp = NPC_SPAWNS:GetDescendants()
		tmp[#tmp+1] = SKATE_SHOP_SPAWN -- Add in the shop spawn point
		tmp[#tmp+1] = POLICE_STATION_SPAWN -- Add in the station spawn point

		PATROL_POINTS = {}
		for i, point in tmp do
			if(point:IsA("Folder"))then continue end
			PATROL_POINTS[#PATROL_POINTS+1] = point
		end

		--As soon as the systems this needs are ready we can fire the ready event
		ToolEm.AllReadySignal({Cortex, React, HitBox, WantedServer}):Once(function()
			Ai.IsReady = true
			_ReadyEvent:Fire()
		end)
	end)
end

--Creates new Ai instance for the provided NPC Model
function Ai.new(...) return Ai.New(...) end
function Ai.New(NPC: Model): Ai

	--Create new Ai instance
	local new: Ai = {}
	setmetatable(new, Ai)

	new.NPC = NPC
	new.Enabled = false --Enable/Disable this AI

	--Cortex
	new.Cortex = Cortex.New(NPC, {Costs = PATH_COSTS})
	new.Cortex.ShowStatusDisplay = false
	new.Cortex:SetPatrolPoints(PATROL_POINTS)
	--new.Cortex.ShowPathway = true

	NPC.Humanoid.WalkSpeed = 5
	NPC.Humanoid:SetAttribute("DefaultSpeed", 5)
	NPC.Humanoid:SetAttribute("DefaultJumpPower", 50)
	new.Cortex.PointDist = 2

	-- NPC SPECIFIC DATA
	new.FinalDest = nil
	new.CurrentDest = nil
    new.PatrolPoints = {}

	new.Target = nil
	new.EnableDashing = false

	--Events

	--NPC TYPE SPECIFIC ANIMS
	new.Anim = {}

	--Connections
    new._CharConns = {}
	new._Conns = {}

	--Enable Character Detection on this NPC
	new.Cortex:EnableCharDZ(NumberRange.new(25, 50), NumberRange.new(50, 100), NumberRange.new(5))

	--Setup listeners for Character Detection Events
	new._Conns[#new._Conns+1] = new.Cortex.CharDetect.CharDetected:Connect(function(...)
		OnCharDetected(new, ...)
	end)
	new._Conns[#new._Conns+1] = new.Cortex.CharDetect.CharLost:Connect(function(...)
		OnCharLost(new, ...)
	end)

	ConnectEvents(new)

	--Return new instance
	return new
end

--Returns the instance for the specified NPC character
function Ai.GetInstance(char: Model, wait:boolean): Ai?
	if(not(char))then warn("A character must be specified") return end
	if(PlayerServ:GetPlayerFromCharacter(char))then return end --NOT AN NPC!
	if(wait)then
		repeat
			task.wait()
		until OBJ_LIST[char]
	end
	return OBJ_LIST[char]
end

--Returns array of instances used as patrol points
function Ai.GetPatrolPoints(): {Instance}
	return PATROL_POINTS
end


--{ METHODS }--

--Store the instance for outside access later
function Ai.StoreInstance(self: Ai): nil
	if(not(self and self.NPC))then return end
	OBJ_LIST[self.NPC] = self
end

--Enable the Ai
function Ai.Enable(self: Ai)
	self.Enabled = true
	self.Cortex.Enabled = true
end

--Disable the Ai
function Ai.Disable(self: Ai)
	self.Enabled = false
	self.Cortex.Enabled = false
end

--Main Ai method (This is the loop for the Ai)
function Ai.Cognize(self: Ai)
	if(not(self.NPC))then return end
end

--Spawns the NPC at the specified Vector3 or CFrame Position.  
--If parent is not supplied, defaults to Cortex's NPC directory.
function Ai.Spawn(self: Ai, position: (Vector3 | CFrame), parent: Instance)
    self.StartSpot = position
	self.Cortex:Spawn(position, parent)

	local hitbox = HitBox.GetInstance(self.NPC, true)
	if(hitbox)then
		self._Conns[#self._Conns+1] = hitbox.HitTaken:Connect(function(wepHitBox: BasePart)
			OnHitTaken(self, wepHitBox)
		end)

		self._Conns[#self._Conns+1] = hitbox.HitPointsChanged:Connect(function(oldHP: number, newHP: number)
			OnHPChanged(self, oldHP, newHP)
		end)
	end

	self.Cortex:Patrol()
end

--MoveTo the provided point. If finalPos is true then  
--the point will be set as the NPCs final destination.
function Ai.MoveTo(self: Ai, point: (Vector3 | CFrame), finalPos: boolean)
    if(finalPos)then
		self.FinalDest = point
		pcall(function() self.FinalDest.BrickColor = BrickColor.Blue() end)
		self.CurrentDest = self.FinalDest
    else
        self.CurrentDest = point
	end

    self.Cortex:MoveTo(self.CurrentDest)
end


--Destroys the Ai Instance
function Ai.Destroy(self: Ai)

	self.Enabled = false

	--Disconnect General Listeners
	for i = 1, #self._Conns do
		if(self._Conns[i])then
			self._Conns[i]:Disconnect()
			self._Conns[i] = nil
		end
	end

	--Disconnect Char Listeners
	for i = 1, #self._CharConns do
		if(self._CharConns[i])then
			self._CharConns[i]:Disconnect()
			self._CharConns[i] = nil
		end
	end

	if(self.Cortex)then self.Cortex:Destroy() end
	self.Cortex = nil
	self.NPC = nil

	self.FinalDest = nil
	self.CurrentDest = nil
    self.PatrolPoints = {}

	self = nil
end


--( RETURN )--

return Ai
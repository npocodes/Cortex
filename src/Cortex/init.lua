--[[
	NPC Cortex Module [Shared] (STAND ALONE)
	Emskipo
	12/2024

	StandAlone NPC control framework that provides common NPC functionality.
	Simply require(RepStor.Cortex) system into your NPC Ai.
	and create an instance with your NPC.
	
	This framework works on both server and client side.
	NPCs can be spawned on server or spawned on client.
	
	NPCs SPAWNED ON SERVER can be controlled by server or client.
	Move modes will automatically transfer to client control
	when it is appropriate and return to server control afterward
	This is 100% automatic even when your Ai is server side only.
	
	NPC control can be given over totally to client, cortexObj:ServerMode("Off")
	NPC control can be kept solely on server, cortexObj:ServerMode("Control")
	Default auto switching, cortexObj:ServerMode("Listen")
	
	NPCs SPAWNED ON CLIENT can only be controlled by the client
	However these NPCs only exist on the client. They are not replicated
	to other clients or the server. For that functionality spawn NPC on server.

	MOVE MODES:
		-TravelTo(dest)
		-Patrol({destA, destB, ...}) --And back again..
		-Track(target)
		-Follow(target)
		-Chase(target)

	Its also worth mentioning, that the CharDetection can be used on player characters
	to utilize the same targeting detection and events. This can be extremely useful
	for all sorts of scenarios even fighting mechanics

	TODO:
		--ALL MODES WORKING.
		
		- Detection Reactions: This is probably best handled by the unique Ai
--]]


--{ SERVICES }--

local RunServ = game:GetService("RunService")

--Server Only Services
local ServStor
if(not(RunServ:IsClient()))then
	ServStor = game:GetService("ServerStorage")
end
local PlayerServ = game:GetService("Players")
local RepStor = game:GetService("ReplicatedStorage")
local PathServ = game:GetService("PathfindingService")
local PhysicServ = game:GetService("PhysicsService")


--{ REQUIRED }--

local Tool
local CharDetect


--( MODULE )--

local Cortex = {}
Cortex.ClassName = "Cortex"
Cortex.__index = Cortex
Cortex.IsReady = false

local _ReadyEvent = Instance.new("BindableEvent")
Cortex.Ready = _ReadyEvent.Event

local _AddedEvent = Instance.new("BindableEvent")
Cortex.AddedNPC = _AddedEvent.Event
--Ai scripts can use this event to create new Ai instance
--For the added NPC, then use Cortex.GetInstance(model)
--to retrieve the Cortex Instance for this NPC and use it
--in the Ai


--{ TYPE DEF }--

type CharDetect = CharDetect.CharDetect

export type Cortex = {}
export type Point = (Vector3 | CFrame | BasePart)
export type AgentParams = {
	AgentRadius: number,
	AgentHeight: number,
	AgentCanJump: boolean,
	AgentCanClimb: boolean,
	WaypointSpacing: number,
	Costs: {[string]: number}
}

--{ CLASS EVENTS }--


--{ CONSTANTS }--

local OBJ_LIST = {} --List of Cortex Instance by model [Model] = CortexInstance
local LINK
local IS_LINKED = false

local MOVE_MODE = {
	Travel = 1,
	Patrol = 2,
	Track = 3,
	Chase = 4,
	Follow = 5,
}


--local CORTEX_DIR = RepStor:WaitForChild("Cortex")

--NPC Character Billboard Tags (HP, STATUS, ETC..)
local NPC_TAGS = script.Parent:WaitForChild("NPCTags")
local CHAR_TAG = NPC_TAGS:WaitForChild("_CharTag")

local CHAT_TAG = NPC_TAGS:WaitForChild("_ChatTag")
local CHAT_TAG_FRAME_TPL


local INDICATOR_TAG = NPC_TAGS:WaitForChild("_IndicatorTag")
local INDICATOR_TAG_IMG_TPL

local ANIM_SCRIPT = if(RunServ:IsClient())then script.AnimClient else script.AnimServ
local ANIM_EMOTE_ASSETS = script.Parent:WaitForChild("AnimEmoteData"):Clone()

local STUCK_TIMEOUT = 16
local DEFAULT_TRACKING_UPDATE = 5 --Update path every 5 secs
local DEFAULT_TRACKING_TIMEOUT = 60*3 --Three minutes.


-- WAYPOINT TRACER OBJECT
local WAYPOINT_OBJ = Instance.new("Part")
WAYPOINT_OBJ.Name = "Point"
WAYPOINT_OBJ.Shape = Enum.PartType.Ball
WAYPOINT_OBJ.Anchored = true
WAYPOINT_OBJ.CanCollide = false
WAYPOINT_OBJ.CanQuery = false
WAYPOINT_OBJ.CanTouch = false
WAYPOINT_OBJ.Size = Vector3.new(.5,.5,.5)
WAYPOINT_OBJ.BrickColor = BrickColor.White()
WAYPOINT_OBJ.Material = Enum.Material.Neon
WAYPOINT_OBJ.Transparency = 0





--{ PRIVATE FUNCTIONS }--


--Returns two different patrol points, if a startPoint is provided
--then only the destination point (B) will be chosen.
local function PickPatrolRoute(patrolPoints: {Point}, startPoint: Instance?): {A: Instance, B: Instance}

	--Select a start point
	startPoint = startPoint or patrolPoints[math.random(#patrolPoints)]

	local points = {}
	points.A = startPoint
	points.B = points.A --Set equal to A for the moment

	repeat
		points.B = patrolPoints[math.random(#patrolPoints)]
		task.wait()
	until points.B ~= points.A

	return points
end


--{ SYSTEM SETUP }--

--Puts players into the "Characters" directory in workspace
--Adds the player character to Characters collision groups
--And runs itself on the player client
local function SortPlayers()
	PlayerServ.PlayerAdded:Connect(function(player: Player)
		
		player.CharacterAdded:Once(function(char)
			--AUTOMATICALLY RUN SELF ON CLIENT
			local clientScript = script:FindFirstChild("CortexClient"):Clone()
			clientScript.Parent = char
			char.Parent = Tool.CHAR_DIR
			--The script will then move itself to playerscripts
		end)
		
		player.CharacterAdded:Connect(function(char)
			
			char.DescendantAdded:Connect(function(child)
				if(child:IsA("BasePart"))then
					child.CollisionGroup = Tool.CHAR_GROUP_NAME
				end
			end)
			for i, child in char:GetDescendants() do
				if(child:IsA("BasePart"))then
					child.CollisionGroup = Tool.CHAR_GROUP_NAME
				end
			end
		end)
	end)
end

--Replicates cortex instance on client side
local function OnNPCAdded(newNPC: Model)
	
	--Create new Cortex instance for this NPC model
	local newObj = Cortex.New(newNPC, nil, true)
	_AddedEvent:Fire(newNPC)--Fire Off the Added Event for this NPC model

	print("Listening for Control Transfer")
	newNPC:GetAttributeChangedSignal("Owner"):Connect(function()
		
		local owner = newNPC:GetAttribute("Owner") or 0
		print("Owner Changed", owner)
		if(owner == 0)then
			--Server Has Ownership
			print("Releasing Control")
			newObj:Disable()
		end
		newObj._OwnershipEvent:Fire(newNPC:GetAttribute("Owner"))--Owner Changed Event
	end)
end

--Creates NPC, Character, Marker Collision Groups
--and assigns collision between the groups
local function CreateGroups()
	PhysicServ:RegisterCollisionGroup(Tool.NPC_GROUP_NAME)
	PhysicServ:RegisterCollisionGroup(Tool.CHAR_GROUP_NAME)
	PhysicServ:RegisterCollisionGroup(Tool.MARKER_GROUP_NAME)

	--Set the Collision Groups
	PhysicServ:CollisionGroupSetCollidable(Tool.NPC_GROUP_NAME, Tool.NPC_GROUP_NAME, false)
	PhysicServ:CollisionGroupSetCollidable(Tool.NPC_GROUP_NAME, Tool.CHAR_GROUP_NAME, false)
	PhysicServ:CollisionGroupSetCollidable(Tool.MARKER_GROUP_NAME, Tool.NPC_GROUP_NAME, false)
	PhysicServ:CollisionGroupSetCollidable(Tool.MARKER_GROUP_NAME, Tool.CHAR_GROUP_NAME, false)
end

--Receives Event Signals on the Client
local function OnClientEvent(data: {Msg: string, Data: any?})
	if(not(data))then return end --No Data
	if(typeof(data) ~= "table")then return end --Data not a table
	if(data.Msg == "LinkReady")then IS_LINKED = true return end
	
	if(data.Msg == "ControlGiven")then
		if(not(data.Data))then return end--No Msg Data
		local msgData = data.Data
		
		if(not(msgData.NPC))then return end --No NPC
		print("Control Taken")
		local NPC = Cortex.GetInstance(msgData.NPC, true)
		NPC:Enable()
		if(msgData.Mode)then
			if(NPC[msgData.Mode])then
				NPC:EnableCharDZ()
				NPC.CharDetect.Focus = msgData.Focus
				NPC[msgData.Mode](NPC, msgData.Focus.Target) --Starts Mode
				--Mode is automatically stopped when server takes back control
			end
		end
	end
end

--Receives Event Signals on the Server
local function OnServerEvent(player: Player, data: {Msg: string, Data: any?})
	if(not(data))then return end --No Data
	if(typeof(data) ~= "table")then return end --Data not a table
	if(data.Msg == "LinkReady")then IS_LINKED = true return end
	
	if(data.Msg == "ControlReturn")then
		local msgData = data.Data
		if(not(msgData))then return end
		
		if(not(msgData.NPC))then return end--NO NPC specified
		local NPC = Cortex.GetInstance(msgData.NPC, true)
		NPC:TransferControl()--Control To Server
	end
end

--Creates Cortex Link between Server/Client
local function CreateLink()

	if(RunServ:IsClient())then
		LINK = script:FindFirstChild("CortexLink")
		if(not(LINK))then
			local tmpConn = nil
			tmpConn = script.ChildAdded:Connect(function(child)
				if(child.Name == "CortexLink" and child:IsA("RemoteEvent"))then
					LINK = child
				end
			end)
		end
		repeat task.wait() print("waiting for link") until LINK
		LINK:FireServer({Msg = "Link Established"})
		LINK.OnClientEvent:Connect(function(data) OnClientEvent(data) end)
	else
		LINK = Instance.new("RemoteEvent")
		LINK.Name = "CortexLink"
		LINK.OnServerEvent:Connect(function(player, data) OnServerEvent(player, data) end)
		LINK.Parent = script
	end
end



--{ PRIVATE METHODS }--

--Handles moving the character to the current waypoint.  
--**Runs each heartbeat** (If traveling)
local function Trek(self: Cortex, ...)
	if(not(self.Traveling))then return end -- Not Traveling, Traveling Paused
	if(not(self.WatchPoint))then return end -- No Current Waypoint
	if(not(self.Waypoints))then return end --No path to travel
	
	--Handle Jumping if the current waypoint calls for it
	if(self.DoJump)then
		local wp = self.Waypoints[self.WatchPoint.Idx - 1]
		if(not(wp))then return end

		local wpPos = wp.Position
		local npcPos = self.NPC.HumanoidRootPart.Position
		local dist = (wpPos - npcPos).Magnitude
		if(dist >= self.JumpDelayDist)then
			self.DoJump = false
			self.Jumped = true
			self.Humanoid.Jump = true
		end
	end
	
	--Move toward the current waypoint
	self.Humanoid:MoveTo(self.WatchPoint.Position)

	if(self.WatchPoint.Action == Enum.PathWaypointAction.Jump)then
		if(not(self.Jumped))then self.DoJump = true end
	end
	
	--Handle if the character is potentially stuck and cannot reach the current waypoint
	--This is done using a timeout (Potentially problematic if waypoint is too far away..)
	--Perhaps we can account for distance/speed and get a formula for timing, ex: speed*time = distance expected
	STUCK_TIMEOUT = self.Humanoid.WalkSpeed
	if((tick() - self.WatchPoint.StartTime) > STUCK_TIMEOUT)then
		--player must be stuck
		--self.NPC.HumanoidRootPart.CFrame = self.NPC.HumanoidRootPart.CFrame:Lerp(self.WatchPoint.Point.CFrame, .99)
		print("Stuck Correction")
		self.NPC:PivotTo(self.NPC:GetPivot():Lerp(CFrame.new(self.WatchPoint.Position), .99))
	end
end

--Chases the current focus target. Fires TargetCaught or TargetEscaped Events
local function Chase(self: Cortex, target)
	--Between Min/Max, CHASE!
	--Keep track of the chase offset, so the NPC isn't constantly doing zigzags
	local offset = self.NPC:GetAttribute("ChaseOffset")
	if(not(offset))then
		local offsetRange = self.CharDetect.Focus.Range.Min - 2
		offset = CFrame.new(math.random(-offsetRange, offsetRange), 0, math.random(-offsetRange, offsetRange))
		self.NPC:SetAttribute("ChaseOffset", offset)
	end

	local position = (target:GetPivot() * offset).Position
	self.NPC.Humanoid:MoveTo(position)
end

--This event will fire if, at any time during the path’s existence, the path is blocked. 
--Note that this can occur behind a character moving along the path, not just in front of it. -RBLX
local function OnPathBlocked(self: Cortex, wpIdx)
	--HOW ABOUT OBJECT THAT BLOCKED THE PATH ASSHOLES!
	--Custom programming required to detect the blockage.
	--We could probably fire off a spatial query at the location
	--of the waypoint that matches the index we get.

	--HOWEVER... The blockage could be anywhere between the current waypoint and waypoint Idx given

	local diff = wpIdx - self.WatchPoint.Idx
	if(diff > 0)then
		--warn("Path Blocked ahead:", wpIdx, diff)
	elseif(diff < 0)then
		--warn("Path Blocked behind:", wpIdx, diff)
	else
		--warn("Path blocked", wpIdx, diff)
	end
end

--Handles when the end of a waypoint path is reached
local function OnDestReached(self: Cortex)
	
	--Reached current travel destination, Stop Traveling
	self:StopTravel("Dest", true)--Don't do stop moveto
	self._DestReachedEvent:Fire()
end

--Handles waypoint reached events and fires the dest reached  
--event if the waypoint reached is end of the path.
--local function OnWaypointReached(self: Cortex)
local function OnWatchPointReached(self: Cortex)
	local watchPoint = self.WatchPoint
	self.WatchPoint = nil
	
	--Was this the last waypoint in the path?
	if(watchPoint.Idx == #self.Waypoints)then
		
		--WatchPoint is the Last waypoint!
		OnDestReached(self, watchPoint.Idx)
	else
		self._WaypointReachedEvent:Fire(watchPoint.Idx)
		--Set next watchpoint
		--self.WatchPoint.Point.Transparency = 1 --Hide the used waypoint
		if(watchPoint.Point)then
			watchPoint.Point:Destroy() --Remove the waypoint object
		end
		
		--Set the next watchpoint
		self.WatchPoint = self.Waypoints[watchPoint.Idx + 1]
		if(self.WatchPoint.Point)then
			self.WatchPoint.Point.BrickColor = BrickColor.new("Bright green")
		end
		self.WatchPoint.StartTime = tick()
	end
end

--Checks if the current waypoint has been reached
--and if so fires the WaypointReached event
local function WatchWaypoint(self: Cortex, ...)
	if(not(self.WatchPoint))then return end --No WatchPoint
	if(not(self.NPC) or not(self.NPC:FindFirstChild("HumanoidRootPart")))then return end --NPC MISSING

	local dist = (self.NPC.HumanoidRootPart.Position - self.WatchPoint.Position).Magnitude
	if(dist <= self.PointDist)then
		--Reached WatchPoint!!
		
		self.Jumped = false --reset jump flag
		OnWatchPointReached(self, self.WatchPoint)
	else
		--Have not yet reached the current watchpoint
		--Keep on Trekking
		Trek(self)
	end
end



--{ TASK SCHEDULE PRIVATE METHODS }--

--Calls methods and functions that should be run  
--during the stepped event of the task scheduler.  
--**Fires before physics**
local function OnStepped(self: Cortex, ...)
	--NOT YET IMPLEMENTED
	return
end

--Calls methods and functions that should be run  
--during the heartbeat event of the task scheduler.  
--**Fires after physics calcuations**
local function OnHeartbeat(self: Cortex, ...)
	if(not(self.Enabled))then return end
	--print("HeartBeat")
	
	if(self.Traveling)then
		WatchWaypoint(self)--Watch for current way point reached (custom)
		return
	else
		--Not yet doing anything
		return
	end
	
	--[[
	--Lifetime over check
	if(not(self.Chasing))then
		if(self.LifeTime and self.LifeTime <= tick())then
			self.LifeTime = nil --Reset
			self._LifeTimeOverEvent:Fire()
			return
		end
	end

	--Pathing Checks and Methods
	if(self.CharDetect and self.CharDetect.FocusChar)then
	--if(self.FollowTarget)then
		if(self.Chasing)then
			Chase(self)
			return
		elseif(not(self.Tracking))then
			Follow(self)
			return
		end
		Track(self)
	end
	--]]
end



--{ PRIVATE METHODS }--

--When using a target, this monitors the targets existence
--and fires the TargetRemoved event when existence is lost.
local function MonitorTargetLoss(self: Cortex, target, conns)
	--Determine and handle target loss (removed, respawns, etc..)
	
	if(target:IsA("Model"))then
		if(target:FindFirstChildWhichIsA("Humanoid"))then
			--Its a character, is it a player character?
			local targetPlayer = PlayerServ:GetPlayerFromCharacter(target)
			warn("Target is player character")
			if(targetPlayer)then
				conns[#conns+1] = PlayerServ.PlayerRemoving:Connect(function(player: Player)
					--This player target is leaving, cancel tracking on it.
					self._TargetRemovedEvent:Fire(target)
				end)
				conns[#conns+1] = targetPlayer.CharacterAdded:Connect(function(character: Model)
					target = character
				end)
			end
		else
			conns[#conns+1] = target.Destroying:Connect(function()
				self._TargetRemovedEvent:Fire(target)
				--RENAME THIS EVENT, IT HAS SAME EVENT NAME AS CHARDETECT EVENT
				--SINCE THEY ARE IN DIFFERENT CLASSES IT STILL FUNCTIONAL
				--HOWEVER IT CAN CAUSE CONFUSION/LOGIC DEBUG PROBLEMS
			end)
			--Target is a model but its not a humanoid character
			--Track its primary part or pick a random base part
		end
	else
		--Target is not a model
		self._ModeConns[#self._ModeConns+1] = target.Destroying:Connect(function()
			self._TargetRemovedEvent:Fire(target)
		end)
	end
end

--Connects/Disconnects to NPC humanoid events, pathing events and task events
local function Connect(self: Cortex, disable: boolean)

	Tool.CancelConns(self._Conns)
	if(disable)then return end

	print("Connecting")
	self._Conns[#self._Conns+1] = self.NPC.Humanoid.Destroying:Connect(function(...)
		self._DyingEvent:Fire("Destroyed")
	end)

	self._Conns[#self._Conns+1] = self.NPC.Humanoid.Died:Connect(function()
		self._DyingEvent:Fire("Died")
	end)

	self._Conns[#self._Conns+1] = self.Path.Blocked:Connect(function(...)
		OnPathBlocked(self, ...)
	end)

	self._Conns[#self._Conns+1] = self.WaypointReached:Connect(function(wpIdx: number)
		print("Reached Waypoint:", wpIdx)
	end)

	--Stepped Connection
	self._Conns[#self._Conns+1] = RunServ.Stepped:Connect(function(...)
		OnStepped(self, ...)
	end)

	--Heartbeat connection
	self._Conns[#self._Conns+1] = RunServ.Heartbeat:Connect(function(...)
		OnHeartbeat(self, ...)
	end)
end

--Sets the Common Properties for new instances
--These properties are the same for server/client
local function SetProperties(new, ap)
	
	new.PointDist = 2 --Distance from waypoint before its reached.
	new.JumpDelayDist = 2 --Distance away from last waypoint before jumping.
	--(When next waypoint requires a jump action)

	-- PathFinding DATA
	new.AgentParams = ap
	new.Path = new:SetNewPath(ap)
	new.Dest = nil --Current Destination, V3 or CF
	new.FinalDest = nil --Dest we ultimately want to end at.
	new.Waypoints = nil
	new.WatchPoint = nil
	new.CharDetect = nil
	new.NextWaypoints = nil

	-- Move Modes and Travel State
	new.Traveling = false -- If the NPC is following a path or not (used in all modes that use TravelTo)
	new.MakingTravelPlans = false
	new.MoveMode = nil -- Travel, Track, Patrol, Chase, Follow?!?
	new.Stopped = true
	new.LastSpeed = new.NPC.Humanoid.WalkSpeed
	
	--Patrol Points
	new.PatrolPoints = {} --Table of all possible patrol points
	new.PatrolRoute = {} --Array of Patrol Points used in current route
	new.PatrolsCompleted = 0

	-- STATE FLAGS
	--new.ShowStatusDisplay = false
	new.ShowPathway = false
	new.DoJump = false
	new.Jumped = false

	-- CUSTOM PATH EVENTS --
	new._OwnershipEvent = Instance.new("BindableEvent")
	new.OwnershipGiven = new._OwnershipEvent.Event

	new._WaypointReachedEvent = Instance.new("BindableEvent")
	new.WaypointReached = new._WaypointReachedEvent.Event

	new._DestReachedEvent = Instance.new("BindableEvent")
	new.DestReached = new._DestReachedEvent.Event

	new._TripEndedEvent = Instance.new("BindableEvent")
	new.TripEnded = new._TripEndedEvent.Event

	new._NoPathFoundEvent = Instance.new("BindableEvent")
	new.NoPathFound = new._NoPathFoundEvent.Event

	new._TargetRemovedEvent = Instance.new("BindableEvent")
	new.TargetRemoved = new._TargetRemovedEvent.Event

	new._PatrolCompletedEvent = Instance.new("BindableEvent")
	new.PatrolCompleted = new._PatrolCompletedEvent.Event


	-- CUSTOM NPC EVENTS --
	new._DyingEvent = Instance.new("BindableEvent")
	new.Dying = new._DyingEvent.Event

	new._LifeTimeOverEvent = Instance.new("BindableEvent")
	new.LifeTimeOver = new._LifeTimeOverEvent.Event

	--Events are relevant only to Follow/Chase states
	new._CatchEvent = Instance.new("BindableEvent")
	new.TargetCaught = new._CatchEvent.Event

	new._EscapeEvent = Instance.new("BindableEvent")
	new.TargetEscaped = new._EscapeEvent.Event


	--Connections
	new._ModeConns = {
		Patrol = {},
		Track = {},
		Chase = {},
		Follow = {},
	}
	new._Conns = {}
end

--Returns instance of Cortex specifically for Client Side
local function NewClientCortex(NPC: Model, ap: AgentParams, animScript: (LocalScript | ModuleScript)): Cortex
	if(not(NPC) or not(NPC:IsA("Model")))then
		warn("Unable to create new Cortex: Missing NPC Model.")
		--return new
	end

	--Create the new instance
	local new:Cortex = {}
	setmetatable(new, Cortex)
	
	-- NPC DATA
	new.NPC = NPC --The Model Instance
	new.Humanoid = NPC:WaitForChild("Humanoid")
	new.RigType = new.Humanoid.RigType
	new.LifeTime = nil --Lifetime/lifespan of this NPC in seconds
	
	if(not(new.Humanoid:GetAttribute("DefaultSpeed")))then
		new.Humanoid:SetAttribute("DefaultSpeed", new.Humanoid.WalkSpeed)
		new.Humanoid:SetAttribute("DefaultJumpPower", new.Humanoid.JumpPower)
	end
	
	--If the NPC has this attribute, then the server spawned it
	if(not(new.NPC:GetAttribute("CortexNPC")))then
		print("Creating Client Spawned NPC instance.")
		
		--Set the model collision group to default NPC group.
		Tool.SetModelCollisionGroup(NPC, Tool.NPC_GROUP_NAME)
		
		--Client Spawned NPC requires AnimScript Module run from PlayerScripts
		local animScript = animScript or ANIM_SCRIPT:Clone()
		animScript.Parent = PlayerServ.LocalPlayer.PlayerScripts
		animScript = require(animScript)
		task.spawn(function() animScript.Run(new.NPC) end)
		
		new.BubbleChatGui = CHAT_TAG:Clone()
		new.BubbleChatGui.Parent = new.NPC
		new.BubbleChatGui.Adornee = new.NPC.PrimaryPart
		new.BubbleChatGui.Enabled = true

		new.IndicatorGui = INDICATOR_TAG:Clone()
		new.IndicatorGui.Parent = new.NPC
		new.IndicatorGui.Adornee = new.NPC.PrimaryPart
		new.IndicatorGui.Enabled = true
	else
		print("Creating Server Spawned NPC instance.")
		new.BubbleChatGui = new.NPC:WaitForChild(CHAT_TAG.Name)
		new.IndicatorGui = new.NPC:WaitForChild(INDICATOR_TAG.Name)
	end
	
	SetProperties(new, ap)--Same Between Server/Client
	Connect(new)

	--Cache the new Instance
	OBJ_LIST[new.NPC] = new
	
	--Return the new instance
	return new
end



--{ PUBLIC FUNCTIONS }--

--Initializes Cortex Class
function Cortex.Initialize()
	print("Loading: Cortex")

	Tool = require(script.Utility)
	CharDetect = require(script.CharDetect)
end

--Runs/Loads the Cortex Class
function Cortex.Run()
	print("Running: Cortex")
	Cortex.Ready:Once(function()
		warn("Cortex Ready") 
		Cortex.IsReady = true
		
		if(not(RunServ:IsClient()))then return end
		
		
		--We need to monitor spawned NPCs from server
		for i, NPC in Tool.NPC_DIR:GetChildren() do
			if(not(NPC:GetAttribute("CortexNPC")))then return end--Not a Cortex NPC
			warn("Server Added new NPC, picking it up!")
			OnNPCAdded(NPC)
		end
		Tool.NPC_DIR.ChildAdded:Connect(function(newNPC)
			if(not(newNPC:GetAttribute("CortexNPC")))then return end--Not a Cortex NPC
			warn("Server Added new NPC, picking it up!")
			OnNPCAdded(newNPC)
		end)
	end)
	
	task.spawn(function()
		
		if(not(RunServ:IsClient()))then
			SortPlayers()
		end
		
		--Get the proper NPC animation script to use.
		local scriptType = if(not(RunServ:IsClient()))then "Script" else "ModuleScript"
		for i, child in script:GetDescendants() do
			if(child.Name == "AnimateNPC" and child:IsA(scriptType))then
				ANIM_SCRIPT = child:Clone()
			end
		end
		ANIM_SCRIPT.Name = "Animate"
		for i, asset in ANIM_EMOTE_ASSETS:GetChildren() do
			local newAsset = asset:Clone()
			newAsset.Parent = ANIM_SCRIPT
		end
		
		--Get the NPC Character Tags
		CHAR_TAG = CHAR_TAG:Clone()
		
		CHAT_TAG = CHAT_TAG:Clone()
		CHAT_TAG_FRAME_TPL = CHAT_TAG:WaitForChild("_FrameTpl"):Clone()
		CHAT_TAG._FrameTpl:Destroy()
		
		INDICATOR_TAG = INDICATOR_TAG:Clone()
		INDICATOR_TAG_IMG_TPL = INDICATOR_TAG:WaitForChild("_ImageTpl"):Clone()
		INDICATOR_TAG._ImageTpl:Destroy()
		
		Tool.CHAR_DIR = Tool.GetDir(Tool.CHAR_DIR_NAME)
		Tool.NPC_DIR = Tool.GetDir(Tool.NPC_DIR_NAME)
		Tool.MARKER_DIR = Tool.GetDir(Tool.MARKER_DIR_NAME)
		if(not(RunServ:IsClient()))then CreateGroups() end
		CreateLink()

		_ReadyEvent:Fire()
	end)
end

--Creates a new Cortex instance for the provided NPC Model
function Cortex.new(...): Cortex
	return Cortex.New(...)
end

--Creates a new Cortex instance for the provided NPC Model
function Cortex.New(NPC: Model, ap: AgentParams, animScript: any?): Cortex
	if(RunServ:IsClient())then return NewClientCortex(NPC, ap, animScript) end

	if(not(NPC) or not(NPC:IsA("Model")))then
		warn("Unable to create new Cortex: Missing NPC Model.")
		--return new
	end

	--Create the new instance
	local new:Cortex = {}
	setmetatable(new, Cortex)
	
	new.ServerMode = "Listen" --Default mode of the server is to always listen and fire events
	--ServerMode property is ALWAYS nil on client and should be ignored.
	--ServerMode can only be set by the server instance
	
	-- NPC DATA
	new.NPC = NPC --The Model Instance
	new.NPC:SetAttribute("CortexNPC", true)--Mark this NPC as a cortex NPC spawned from server so client can pick it up
	new.NPC:SetAttribute("Owner", 0) --Preset to zero so client can see when its changed

	new.Humanoid = NPC:WaitForChild("Humanoid")
	new.Humanoid:SetAttribute("DefaultSpeed", new.Humanoid.WalkSpeed)
	new.Humanoid:SetAttribute("DefaultJumpPower", new.Humanoid.JumpPower)
	new.RigType = new.Humanoid.RigType --Enum.HumanoidRigType

	new.LifeTime = nil --Lifetime/lifespan of this NPC in seconds

    --Set the model collision group to default NPC group.
    Tool.SetModelCollisionGroup(NPC, Tool.NPC_GROUP_NAME)

	--Use custom anim script if provided, else use default
	animScript = animScript or ANIM_SCRIPT:Clone()
	animScript.Parent = new.NPC

	new.BubbleChatGui = CHAT_TAG:Clone()
	new.BubbleChatGui.Parent = new.NPC

	new.BubbleChatGui.Adornee = new.NPC.PrimaryPart
	new.BubbleChatGui.Enabled = true

	new.IndicatorGui = INDICATOR_TAG:Clone()
	new.IndicatorGui.Parent = new.NPC
	new.IndicatorGui.Adornee = new.NPC.PrimaryPart
	new.IndicatorGui.Enabled = true

	SetProperties(new, ap)--Same Between Server/Client
	Connect(new)

	--Cache the new Instance
	OBJ_LIST[new.NPC] = new
	
	--Return the new instance
	return new
end

--Returns the Cortex instance associated with the NPC model if it exists
function Cortex.GetInstance(NPC: Model, wait: boolean): Cortex
	if(wait)then
		repeat 
			task.wait()
		until OBJ_LIST[NPC]
	end
	return OBJ_LIST[NPC]
end


--Returns a Cortex waypoint obj used for path tracing.
function Cortex.GetWaypointObj(): Part
	return WAYPOINT_OBJ:Clone()
end



--{ PUBLIC METHODS }--

function Cortex.SetSpeed(self: Cortex, speed: number)
	repeat task.wait() until not(self.Stunned)
	self.NPC.Humanoid.WalkSpeed = speed or self.Humanoid:GetAttribute("DefaultSpeed")
	self.LastSpeed = self.NPC.Humanoid.WalkSpeed
end

--Disables cortex instance
function Cortex.Disable(self: Cortex)
	print("Disabling NPC:", self.NPC.Name)
	--Pauses/Stops all events, moves etc..
	self.Enabled = false
	
	--Do this for both server/client or just Client??
	if(RunServ:IsClient())then
		local activeMode = self:GetMoveMode()
		if(activeMode ~= "Travel")then
			self["Stop"..activeMode](self)
		end
	end
	
	Connect(self, true) --Disconnect
	
	if(self.CharDetect)then
		if(not(RunServ:IsClient()))then
			if(self.ServerMode ~= "Off")then return end
		end
		--Only disable CharDetect if ServerMode is "Off"
		--Otherwise we still want to listen to CharDetectEvents
		self.CharDetect.Enabled = false
	end
end

--Re-Enables cortex instance
function Cortex.Enable(self: Cortex)
	print("Enabling NPC:", self.NPC.Name)
	
	--Resumes/Starts all events, moves etc..
	Connect(self)

	self.Enabled = true
	if(self.CharDetect)then
		self.CharDetect.Enabled = true
	end
end

--Returns the name, value of the current move mode
function Cortex.GetMoveMode(self: Cortex): number?
	for name, value in MOVE_MODE do
		if(value == self.MoveMode)then return name, value end
	end
	return --Unknown move mode
end


--{ TRAVEL MODE }--


--Attempts to find a pathway to travel to the provided 
--destination and sets the NPC into Travel Mode.
--**DO NOT CALL EVERY HEARTBEAT** Set Once!
function Cortex.TravelTo(self: Cortex, dest: Point, finalDest: boolean): boolean
	if(self.Traveling or not(self.Stopped))then warn("Already Traveling, Stop Current Travel First!") return end
	self.MakingTravelPlans = true
	print("Making Travel Plans...")
	
	--Covert provided dest point to Vector3 position
	dest = Tool.PointPosition(dest)

	self.Dest = dest --Set new dest
	print("Setting new dest..")
	if(not(self.Dest))then print("NO DEST:", self.NPC.Name) return false end --No Destination
	
	
	if(not(self.Waypoints))then
		local waypoints = self:FindPathway(self.Dest)
		if(not(waypoints) or #waypoints < 1)then
			print("No Waypoints: TravelTo()")
			self.MakingTravelPlans = false
			return
		else
			self:SetPoints(waypoints)
		end
	end

	if(self.ShowPathway)then self:ShowPath(self.Waypoints) end
	self:TravelPath(self.Waypoints)
end

--Sets the first waypoint on the path and begins traveling the path. 
function Cortex.TravelPath(self: Cortex, waypoints:{PathWaypoint})
	if(not(waypoints) or #waypoints < 1)then warn("Must supply Waypoints array.", debug.traceback()) return end
	self.WatchPoint = waypoints[1]
	self.WatchPoint.StartTime = tick()
	self.Stopped = false
	self.Traveling = true
	self.MakingTravelPlans = false
	self:SetStatus("Traveling")
end

--Pauses traveling the path to the current dest
function Cortex.PauseTravel(self: Cortex)
	repeat task.wait() until not(self.MakingTravelPlans)
	self:SetStatus("Pausing")
	self.Traveling = false
	self.Humanoid:MoveTo(self.Humanoid.Parent:GetPivot().Position) --Stop
end

--Resumes traveling the path to the current dest
function Cortex.ResumeTravel(self: Cortex)
	if(self.WatchPoint)then
		--If there isn't a WatchPoint then there was no travel.
		self:SetStatus("Traveling")
		self.WatchPoint.StartTime = tick()
		self.Traveling = true
	else
		self:StopTravel()
	end --Reset the watch point timer
end

--Cancels Traveling and stops the NPC  
--Cannot be Resumed!
function Cortex.StopTravel(self: Cortex, msg: string, finishMove: boolean)
	repeat task.wait() until not(self.MakingTravelPlans)
	self.Traveling = false
	self:ClearWaypoints()
	msg = if(msg)then "Stopping Travel -"..msg else "Stopping Travel"
	self:SetStatus(msg)
	
	self.Stopped = true
	print("Waiting for Instruction")
	if(finishMove)then return end
	self.Humanoid:MoveTo(self.Humanoid.Parent:GetPivot().Position) --Stop
end





--{ PATROL MODE }--

--Makes the NPC Travel back and forth between the specified points  
--**DO NOT CALL EVERY HEARTBEAT** Set Once!
function Cortex.Patrol(self: Cortex, route: table?)
	Tool.CancelConns(self._ModeConns.Patrol)--Clear stale conns
	local conns = self._ModeConns.Patrol
	
	if(not(self:SetPatrolRoute(route)))then
		warn("No Patrol Routes Available. Set Patrol Points or Provide specific route")
		return
	end

	--WHILE PATROLLING ONLY!!! WE NEED TO BE ABLE TO "PAUSE" THIS SWITCH
	--SO THE PATROL CAN BE PAUSED AND RESUMED AS NEEDED.
	conns[#conns+1] = self.DestReached:Connect(function(waypointIdx: number)
		if(not(self.Enabled))then return end
		
		print("Reached A Patrol Destination")
		
		--If Patrol has not been paused/Canceled, then we should proceed to the next Patrol Point
		if(self.Dest == self.PatrolRoute[1])then
			--Full Circle!
			self.PatrolsCompleted += 1
			self._PatrolCompletedEvent:Fire(self.PatrolsCompleted)
			print("Completed", self.PatrolsCompleted, "Patrol Round!")
		end
		
		if(self.MoveMode == MOVE_MODE.Patrol)then
			print("Finding next Patrol Point")
			local nextPatrolPoint
			for i=1, #self.PatrolRoute do
				if(self.Dest == self.PatrolRoute[i])then
					local idx = if (i == #self.PatrolRoute) then 1 else i+1 --Wrap around to first point
					nextPatrolPoint = self.PatrolRoute[idx]
					break
				end
			end
			print("Traveling to next Patrol Point")
			self:TravelTo(nextPatrolPoint)
		else
			--Patrol was paused or canceled?
			warn("Patrol Pause/Cancelled")
		end
	end)

	conns[#conns+1] = self.NoPathFound:Connect(function()
		if(not(self.Enabled))then return end
		print("NO PATH FOUND!")
		self:Patrol()
	end)

	self.MoveMode = MOVE_MODE.Patrol
	warn("Starting Patrol")
	self:TravelTo(self.PatrolRoute[2])--Begin by going to 2nd point
	--First point is usually the spawn/start point.
end

function Cortex.PausePatrol(self: Cortex)
	self.MoveMode = MOVE_MODE.Travel --Set back to Default Travel Mode?
	self:PauseTravel()
end

function Cortex.ResumePatrol(self: Cortex)
	self.MoveMode = MOVE_MODE.Patrol
	self:ResumeTravel()
end

function Cortex.StopPatrol(self: Cortex, msg: string, finishMove: boolean)
	self.MoveMode = MOVE_MODE.Travel --Set back to Default Travel Mode
	self.PatrolsCompleted = 0 --reset
	Tool.CancelConns(self._ModeConns.Patrol)
	msg = if(msg)then "Patrol Stopped: "..msg else "Patrol Stopped"
	self:StopTravel(msg)
end

--Set the table of patrol points to use for patrol routes
function Cortex.SetPatrolPoints(self: Cortex, patrolPoints: {Point})
	if(not(self or patrolPoints))then return end

	for i, point in patrolPoints do
		self.PatrolPoints[i] = Tool.PointPosition(point)
	end
	self.PatrolPoints = patrolPoints
	print("PatrolPoints Set", self.PatrolPoints)
end

--Sets the patrol route to be used when on Patrol  
--If a route is not provided, a random route will be chosen  
--from the patrol points set if any.
function Cortex.SetPatrolRoute(self: Cortex, route: table?)
	if(not(self))then return end
	if(not(route) or #route < 1)then
		--No route specified, use a random route if we can
		if(not(self.PatrolPoints))then warn("No Patrol Points") return false end --No PatrolPoints Set
		if(#self.PatrolPoints < 1)then warn("No Patrol Points") return false end --No PatrolPoints Set

		--Select a random start point
		local point1 = Tool.PointPosition(self.PatrolPoints[math.random(#self.PatrolPoints)])
		print("Selected Random Start Position:", point1)
		
		local point2 = point1

		--Ensure the points are not the same one
		repeat
		point2 = Tool.PointPosition(self.PatrolPoints[math.random(#self.PatrolPoints)])
			task.wait()
		until point2 ~= point1
		print("Selected Random Dest:", point1)
		
		self.PatrolRoute = {point1, point2}
		print("Random Patrol Route Created")
	else
		print("Using Provided Route", route)
		--Route was specified
		for i, point in route do
			self.PatrolRoute[i] = Tool.PointPosition(point)
		end
	end
	return true
end



--{ TRACKING MODE }--

--The Tracking Mode makes the NPC find the specified target  
--wherever in the map the target is and updates path to handle moving target
--Combine with CharDetect for recognition of finding target
function Cortex.Track(self: Cortex, target: (Model | BasePart))
	if(not(self.CharDetect and self.CharDetect.Enabled))then 
		warn("Char Detection has not been activated yet.") 
		return 
	end
	warn("Tracking:", target.Name)
	
	self.CharDetect.Focus.Target = target
	
	--STILL DO FOR LISTEN/CONTROL MODE
	Tool.CancelConns(self._ModeConns.Track)--Clear stale conns
	local conns = self._ModeConns.Track

	--STILL DO FOR LISTEN/CONTROL MODE
	self.MoveMode = MOVE_MODE.Track
	MonitorTargetLoss(self, target, conns)--Use AFTER setting mode

	
	if(not(RunServ:IsClient()))then
		if(self.ServerMode ~= "Control")then
			if(target:IsA("Model"))then
				local player = PlayerServ:GetPlayerFromCharacter(target)
				if(player)then
					self:TransferControl(player, {Mode = "Track", Focus = self.CharDetect.Focus})
					return
				else
					warn("TARGET NOT A PLAYER:", target)
				end
			end
		else
			--Tracking will be handled on server
			warn("Tracking works best with Client control")
		end
	end
	
	
	--ServerMode "Control" only!!
	self:TravelTo(target)
	
	--ServerMode "Control" only!!
	local trackTimer = tick() + DEFAULT_TRACKING_UPDATE
	
	--STILL DO FOR LISTEN MODE (and Off Mode?!?)
	conns[#conns+1] = self.TargetRemoved:Connect(function()
		warn("TARGET WAS REMOVED/DESTROYED")
		self:StopTrack("TARGET WAS REMOVED/DESTROYED")
	end)
	
	--ServerMode "Control" only!!?
	conns[#conns+1] = self.DestReached:Connect(function()
		--If the target no longer exists, we should cancel the tracking
		trackTimer = tick() + DEFAULT_TRACKING_UPDATE --reset timer
		self:TravelTo(target)
	end)
	
	--ServerMode "Control" only!!?
	conns[#conns+1] = self.NoPathFound:Connect(function()
		print("No Path")
	end)
	
	--ServerMode "Control" only!!
	conns[#conns+1] = RunServ.Heartbeat:Connect(function()
		if(trackTimer and trackTimer <= tick())then
			--If the target no longer exists, we should cancel tracking
			self:StopTravel("Update Tracking")
			trackTimer = tick() + DEFAULT_TRACKING_UPDATE
			self:TravelTo(target)
		end
	end)
end

--Cancels the current Track Cycle and stops the NPC
function Cortex.StopTrack(self: Cortex, msg: string)
	--If Server and ServerMode ~= Control, then transfer control back to server?
	if(not(RunServ:IsClient()))then
		if(self.ServerMode ~= "Control")then
			self:TransferControl()
		end
	end
	
	Tool.CancelConns(self._ModeConns.Track)
	self.CharDetect.Focus.Target = nil
	self.MoveMode = MOVE_MODE.Travel --Set back to Default Travel Mode
	msg = if(msg)then "Tracking Stopped: "..msg else "Tracking Stopped"
	self:StopTravel(msg)
end

--There is no pause/resume for tracking, because of the automatic
--updating of the pathfinding. Just Track/StopTrack should be used.
--Resuming to a stale dest doesn't make sense.
--Previous travel will be stopped, cannot be resumed.



--{ CHASE MODE }--

--The Chase mode makes the NPC chase after the specified target  
--When chasing the NPC will attempt to "Catch" the target and the target can "Escape"..
--**DO NOT CALL EVERY HEARTBEAT** Set Once!
function Cortex.Chase(self: Cortex, target: (Model | BasePart))
	if(not(self.CharDetect and self.CharDetect.Enabled))then 
		warn("Char Detection has not been activated yet.") 
		return 
	end
	warn("Chasing:", target.Name)
	
	self.CharDetect.Focus.Target = target
	self.CharDetect.Focus.GraceActive = true --Wether Dectection will use grace periods
	
	self.GainedFirstFocus = false
	Tool.CancelConns(self._ModeConns.Chase)--Clear stale conns
	local conns = self._ModeConns.Chase
	
	if(self.Traveling)then
		self:PauseTravel() --By Pausing, we can pick back up any previous traveling
		--Since this mode doesn't use pathfinding we can just resume it.
	end
	
	self.MoveMode = MOVE_MODE.Chase
	MonitorTargetLoss(self, target, conns)
	
	conns[#conns+1] = self.TargetRemoved:Connect(function()
		warn("THE TARGET HAS BEEN REMOVED/DESTROYED")
		self:StopChase("TARGET REMOVED/DESTROYED")
	end)
	
	conns[#conns+1] = self.CharDetect.TargetFocusLost:Connect(function(char, details)
		--FOCUS LOST!! (ESCAPED!!)
		print("Focus Lost")
		self._EscapeEvent:Fire(target)
	end)
	
	conns[#conns+1] = self.CharDetect.TargetCloseFocus:Connect(function(char, details)
		--CAUGHT THE CHARACTER!!
		print("CloseFocus")
		self._CatchEvent:Fire(target)
	end)
	
	conns[#conns+1] = self.CharDetect.TargetFocusGain:Connect(function(char, details)
		print("Gained Focus")
		self.GainedFirstFocus = true
	end)
	
	if(not(self.CharDetect.DetectionList[target]))then
		local dist = (target:GetPivot().Position - self.NPC:GetPivot().Position).Magnitude
		self.CharDetect.DetectionList[target] = dist --Add to detection list
		self.CharDetect.FocusLostTime = tick() + 15 --Set initially high FocusLostTime
		--So the Gain Focus event will work for first detection, this gives the NPC
		-- 1 min to "catch up" to the target
	end
	
	--For if the target can be caught or lost. If false, then the target cannot be lost
	if(not(RunServ:IsClient()))then
		if(self.ServerMode ~= "Control")then
			if(target:IsA("Model"))then
				local player = PlayerServ:GetPlayerFromCharacter(target)
				if(player)then
					self:TransferControl(player, {Mode = "Chase", Focus = self.CharDetect.Focus})
					return
				else
					warn("TARGET NOT A PLAYER:", target)
				end
			end
		else
			--Tracking will be handled on server
			warn("Chasing works best with Client control")
		end
	end

	--MOVEMENT HANDLING --ONLY SERVER MODE CONTROL
	conns[#conns+1] = self.CharDetect.TargetInFocus:Connect(function(char, details)
		--print("In Focus")
		if(not(self.NPC and self.NPC.Humanoid))then return end
		--Char is in focus, chasing...
		Chase(self, target)
	end)

	--MOVEMENT HANDLING --ONLY SERVER MODE CONTROL
	conns[#conns+1] = self.CharDetect.TargetFocusOut:Connect(function(char, details)
		print("Out of Focus")
		Chase(self, target)
		--Target is out of range but not yet lost!
	end)
end

--Cancels the current Chase cycle and stops the NPC
function Cortex.StopChase(self: Cortex, msg: string)
	if(not(RunServ:IsClient()))then
		if(self.ServerMode ~= "Control")then
			self:TransferControl()
		end
	end
	
	Tool.CancelConns(self._ModeConns.Chase)--Clear conns
	self.CharDetect.Focus.Target = nil
	self.MoveMode = MOVE_MODE.Travel
	self.GainedFirstFocus = false
	self.NPC:SetAttribute("ChaseOffset", nil)
	
	msg = if(msg)then "Chase Stopped: "..msg else "Chase Stopped"
	self:ResumeTravel(msg)
end




--{ FOLLOW MODE }--

--The Follow mode makes the NPC follow the specified target  
--When following, the NPC will stay within the specified range of the target.  
--Automatically cancels any previous MoveTo  
--**DO NOT CALL EVERY HEARTBEAT** Set once!
function Cortex.Follow(self: Cortex, target: (Model | BasePart))
	if(not(self.CharDetect and self.CharDetect.Enabled))then 
		warn("Char Detection has not been activated yet.") 
		return 
	end
	warn("Following:", target.Name)
	
	self.CharDetect.Focus.Target = target
	self.CharDetect.Focus.GraceActive = false --No grace time means target cannot be lost
	
	self.GainedFirstFocus = false
	Tool.CancelConns(self._ModeConns.Follow)--Clear stale conns
	local conns = self._ModeConns.Follow
	
	if(self.Traveling)then
		self:PauseTravel() --By Pausing, we can pick back up any previous traveling
		--Since this mode doesn't use pathfinding we can just resume it.
	end

	self.MoveMode = MOVE_MODE.Follow
	MonitorTargetLoss(self, target, conns)
	
	conns[#conns+1] = self.TargetRemoved:Connect(function()
		warn("THE TARGET HAS BEEN REMOVED/DESTROYED")
		self:StopFollow("TARGET REMOVED/DESTROYED")
	end)	
	
	
	conns[#conns+1] = self.CharDetect.TargetFocusGain:Connect(function(char, details)
		print("Gained Focus")
		self.GainedFirstFocus = true --Should be done whenever the server is involved
		--self.NPC.Humanoid:MoveTo(self.NPC:GetPivot().Position) --Move Closer (SERVER CONTROL ONLY!)
	end)
	
	--If the target hasn't been detected by the NPC yet, then we'll
	--add them to the detection list and give NPC time to catch up
	if(not(self.CharDetect.DetectionList[target]))then
		local dist = (target:GetPivot().Position - self.NPC:GetPivot().Position).Magnitude
		self.CharDetect.DetectionList[target] = dist --Add to detection list
		self.CharDetect.FocusLostTime = tick() + 15 --Set initially high FocusLostTime
		--So the Gain Focus event will work for first detection, this gives the NPC
		-- 1 min to "catch up" to the target
	end
	
	--For if the target can be caught or lost. If false, then the target cannot be lost
	if(not(RunServ:IsClient()))then
		if(self.ServerMode ~= "Control")then
			if(target:IsA("Model"))then
				local player = PlayerServ:GetPlayerFromCharacter(target)
				if(player)then
					self:TransferControl(player, {Mode = "Follow", Focus = self.CharDetect.Focus})
					return
				else
					warn("TARGET NOT A PLAYER:", target)
				end
			end
		else
			--Follow will be handled on server
			warn("Follow works best with Client control")
		end
	end
	
	--ANYTHING PAST THIS POINT IS ONLY DONE IF SERVER IS RUNNING THE MODE (OR IF CALL COMES FROM CLIENT)

	--Not Really needed
	conns[#conns+1] = self.CharDetect.TargetCloseFocus:Connect(function(char, details)
		--CAUGHT THE CHARACTER!!
		print("CloseFocus")
	end)
	
	--Not Really needed
	conns[#conns+1] = self.CharDetect.TargetInFocus:Connect(function(char, details)
		print("In Focus")
	end)
	
	--(SERVER CONTROL ONLY!)
	conns[#conns+1] = self.CharDetect.TargetFocusOut:Connect(function(char, details)
		print("Out of Focus")
		self.NPC.Humanoid:MoveTo(target:GetPivot().Position) --Move Closer 
	end)
	
	conns[#conns+1] = self.CharDetect.TargetFocusGain:Connect(function(char, details)
		--print("Gained Focus")
		--self.GainedFirstFocus = true --Should be done whenever the server is involved
		self.NPC.Humanoid:MoveTo(self.NPC:GetPivot().Position) --Move Closer (SERVER CONTROL ONLY!)
	end)
	
	--Not Really needed
	conns[#conns+1] = self.CharDetect.TargetFocusLost:Connect(function(char, details)
		print("Focus Lost")
	end)

end

--Cancels the current Follow Cycle and stops the NPC
function Cortex.StopFollow(self: Cortex, msg: string)
	if(not(RunServ:IsClient()))then
		if(self.ServerMode ~= "Control")then
			self:TransferControl()
		end
	end
	
	Tool.CancelConns(self._ModeConns.Follow)--Clear conns
	self.CharDetect.Focus.Target = nil
	self.MoveMode = MOVE_MODE.Travel
	self.GainedFirstFocus = false
	self.NPC:SetAttribute("ChaseOffset", nil)

	msg = if(msg)then "Follow Stopped: "..msg else "Follow Stopped"
	self:ResumeTravel(msg)
end









--{ PATH FINDING }--

--Creates a path object using the provided path parameters
function Cortex.SetNewPath(self: Cortex, ap: AgentParams): Path
	if(not(ap))then ap = {} end
	ap.AgentRadius = ap.AgentRadius or 2
	ap.AgentHeight = ap.AgentHeight or 2
	ap.AgentCanJump = ap.AgentCanJump or true
	ap.AgentCanClimb = ap.AgentCanClimb or true
	ap.WaypointSpacing = ap.WaypointSpacing or 16
	--ap.Costs = ap.Costs or {}

	self.Path = PathServ:CreatePath(ap)
	return self.Path
end

--Attempts to locate a pathway from the NPC position to the provided destination position.  
--If a path is found, then the waypoints array is returned.  
function Cortex.FindPathway(self: Cortex, dest: Point, startPoint: Point): {PathWaypoint}?
	
	print("Finding Pathway")
	if(not(dest))then self:SetStatus("No Dest") return end
	dest = Tool.PointPosition(dest)
	startPoint = if(startPoint) then Tool.PointPosition(startPoint) else self.NPC:GetPivot().Position

	--PATH STATUS THAT MAY STILL BE WORKABLE FOR FINDING A PATH!!
	-- ClosestNoPath - Path doesn't exist, but returns a path closest to that dest/point
	-- ClosestOutOfRange - Goal is beyond max distance range, returns path to closest point you can reach within MaxDistance.

	--First compute the path with pathFinding
	local success, pathFound = pcall(function()
		self.Path:ComputeAsync(startPoint, dest)
		if(self.Path.Status == Enum.PathStatus.Success)then return true end
		return false
	end)

	if(success and pathFound)then--This is just saying that the pcall didn't fail!
		--A pathway was found!
		print("Pathway Found")
		return self.Path:GetWaypoints()
	else
		print("No Pathway Found!")
		self:SetStatus(self.Path.Status.Name)
		self._NoPathFoundEvent:Fire(self.Path.Status.Name, startPoint, dest)
	end
end

--Set the waypoints to use
function Cortex.SetPoints(self: Cortex, waypoints:{PathWaypoint})

	self:ClearWaypoints() --Clear stale waypoints
	
	local newPoints = {}
	table.remove(waypoints, 1)--Remove first waypoint.. usually too close.
	
	--Recreate the waypoint table
	for i = 1, #waypoints do
		local newY = (waypoints[i].Position.Y + self.Humanoid.HipHeight + (self.NPC.HumanoidRootPart.Size.Y/2))
		newPoints[i] = {
			Position = Vector3.new(waypoints[i].Position.X, newY, waypoints[i].Position.Z),
			Action = waypoints[i].Action,
			StartTime = nil,
			Idx = i
		}
	end
	self.Waypoints = newPoints
end

--Creates waypoint parts to show the waypoint path provided
function Cortex.ShowPath(self: Cortex, waypoints:{PathWaypoint})
	if(not(waypoints))then warn("Must supply Waypoints array.") return end
	print("Showing Pathway")
	for i = 1, #waypoints do
		local point = WAYPOINT_OBJ:Clone()
		point.Parent = Tool.MARKER_DIR
		point.Position = waypoints[i].Position
		if(waypoints[i].Action == Enum.PathWaypointAction.Jump)then
			point.BrickColor = BrickColor.new("Neon orange")
		end
		self.Waypoints[i].Point = point --add the point obj to the waypoint's data
	end
end

--Destroys the current set of waypoints
function Cortex.ClearWaypoints(self: Cortex)
	self.WatchPoint = nil
	if(self.Waypoints)then
		for i, wp in self.Waypoints do
			if(not(wp))then continue end
			if(wp.Point)then wp.Point:Destroy() end
		end
	end
	self.Waypoints = nil
end



--{ SPAWN AND TELEPORT }--

--Spawns the NPC at the specified Vector3 or CFrame Position
--If parent is not supplied, defaults to NPC directory
--DOES NOT USE TELEPORT METHOD TO ENSURE SAFE SPAWNING
function Cortex.Spawn(self: Cortex, point: Point, parent: Instance?, lifetime: number?): boolean
    if(not(point))then return end
	point = Tool.PointCF(point)

	self.SpawnLocation = point--Remember the spawn cf
	self.NPC:PivotTo(self.SpawnLocation) --This should be a CFrame
	self.NPC.Parent = parent or Tool.NPC_DIR
	Tool.GiveOwnership(nil, self.NPC) --Make the server the owner

	if(lifetime and lifetime > 0)then
		self.LifeTime = tick()+lifetime
	end

    return true
end

--Uses Teleport method to safely spawn the NPC at the provided position
function Cortex.SafeSpawn(self: Cortex, point: Point, lookAt: Vector3?, lifetime: number?, parent: Instance?): boolean
	if(not(point))then warn("SafeSpawn() requires a CFrame.") return end -- No cf given
	point = Tool.PointCF(point)

	--Attempt to relocate the NPC to the provided cf
	local success, spawnCF = self:Teleport(point, lookAt)
	if(not(success))then return end --Unable to safely relocate NPC to cf provided

	self.SpawnLocation = spawnCF--Remember the spawn Position/Location
	self.NPC.Parent = parent or Tool.NPC_DIR
	task.wait()
	Tool.GiveOwnership(self.NPC, PlayerServ.LocalPlayer) --Make the server the owner

	if(lifetime and lifetime > 0)then
		self.LifeTime = tick()+lifetime
	end

    return true
end

--Relocates the NPC within the same "Place" in a safe manner.  
--If a **lookAt** position is provided the NPC will face the lookAt position  
--If **unsafe** is set to true then no checks will be made to ensure safe relocation
--and **lookAt** value (if provided) will not be corrected for unsafe tilting.
function Cortex.Teleport(self: Cortex, point: Point, lookAt: Vector3?, unsafe: boolean?): (boolean, CFrame?)
	if(not(point))then return end
	local pointCF = Tool.PointCF(point)
	print("Checking Teleport Position:", pointCF.Position)
	
	if(not(unsafe))then
		--WE NEED THE SPATIAL CHECK TO IGNORE NON-COLLIDE STUFF
		local overlapParams = OverlapParams.new()
		overlapParams.RespectCanCollide = true
		overlapParams.CollisionGroup = Tool.NPC_GROUP_NAME
		
		local parts = Tool.SpatialCheck(CFrame.new(pointCF.Position), self.NPC:GetExtentsSize(), overlapParams)
		if(#parts > 0)then 
			warn("Teleport Failed: Blocked", parts) 
			--Position Blocked/Inside collidable obj
			
			--Get the largest size axis of the blocking part
			local maxSize = math.max(parts[1].Size.X, parts[1].Size.Y, parts[1].Size.Z)
			
			--Move straight upward this amount and raycast back down toward the blocking part
			--This will give us the surface position regardless of orientation
			local castParams = RaycastParams.new()
			castParams.FilterType = Enum.RaycastFilterType.Include
			castParams:AddToFilter(parts[1]) --Only consider this part in the cast
			
			local result = Tool.GetSurface(CFrame.new(pointCF.Position)*CFrame.new(0,maxSize,0), castParams, maxSize+10)
			if(result)then
				warn("Found Surface Position:", parts[1].Name, result.Position)
				warn("Adjusting Spawn Position for NPC")
				local offset = Vector3.new(0, self.NPC.Humanoid.HipHeight+.6, 0)
				local pointCF = CFrame.lookAlong((result.Position + offset), pointCF.LookVector)
				
				--Now try again
				task.wait()
				return Cortex.Teleport(self, pointCF, lookAt, unsafe)
			else
				warn("Failed to detect blocking part surface position!!")
				return
			end
		else
			--Spatial Check was clear, nothing in the way
			--Find ground surface
			warn("Spawn Area Clear")
			local result = Tool.GetSurface(pointCF, RaycastParams.new(), 100)
			if(result)then
				warn("Surface Located")
			else
				warn("Unable to locate ground surface!")
				return
			end
		end 
	end

	local spawnCF
	if(lookAt)then
		local y = (unsafe) and lookAt.Y or self.NPC:GetPivot().Y --Stop NPC from tilting off their feet
		lookAt = Vector3.new(lookAt.X, y, lookAt.Z)
		spawnCF = CFrame.lookAt(pointCF.Position, lookAt)
	else
		spawnCF = CFrame.new(pointCF.Position) --If CFrame or Instance given without lookAt, then ignore CFrame look vector
	end
	
	self.NPC:PivotTo(spawnCF)
	return true, spawnCF
end





--{ OTHER }--

--Faces the NPC in the direction of the dest provided
function Cortex.TurnToward(self: Cortex, point: Point)
	local targetPos = Tool.PointPosition(point)
	targetPos = Vector3.new(targetPos.X, self.NPC:GetPivot().Position.Y, targetPos.Z)
	local cf = CFrame.lookAt(self.NPC:GetPivot().Position, targetPos)
	self.NPC:PivotTo(cf)
end

--Puts the NPC into a STUNNED state
--This shouldn't completely stop Chase/Follow
--We just the NPC to be stopped
function Cortex.Stun(self: Cortex, release: boolean)
	if(not(release))then
		print("Stunned!")
		self.Stunned = true
		self.NPC.Humanoid.WalkSpeed = 0
		self.NPC.Humanoid.JumpPower = 0
		self:PauseTravel()
		self.CharDetect.DZ.Color = Color3.fromRGB(85, 0, 127)
	else
		self.Stunned = false
		self.NPC.Humanoid.WalkSpeed = self.LastSpeed
		self.NPC.Humanoid.JumpPower = self.NPC.Humanoid:GetAttribute("DefaultJumpPower")
		self:ResumeTravel()
		self.CharDetect.DZ.Color = BrickColor.Blue().Color
	end
end

--Sets the status attribute on the NPC
function Cortex.SetStatus(self: Cortex, status: string)
	if(not(status))then return end
	print("Setting Status:", status)
	self.NPC:SetAttribute("Status", status)
end

--Displays a chat bubble above the NPC with the provided msg.  
--The msg lasts for the lifetime in secs provided.
function Cortex.BubbleChat(self: Cortex, msg: string, lifetime: number?)
	if(not(msg))then return end
	if(not(self.BubbleChatGui))then warn("No BubbleChat Gui Set") return end

	self.BubbleChatGui.Enabled = true
	local newFrame = CHAT_TAG_FRAME_TPL:Clone()
	local zindex = self.BubbleChatGui:GetChildren()
	for i, chatMsg in zindex do
		chatMsg.ZIndex += 1
	end
	--self.BubbleChatGui:ClearAllChildren()

	newFrame.ZIndex = 0
	newFrame.Parent = self.BubbleChatGui

	newFrame.Visible = true
	local label = newFrame:FindFirstChild("_TextLbl", true)
	if(label)then label.Text = msg end
	if(lifetime)then
		task.delay(lifetime+#zindex, function()
			if(not(self.BubbleChatGui))then return end
			if(not(newFrame))then return end
			if(not(self.ShowStatusDisplay))then self.BubbleChatGui.Enabled = false end
			newFrame.Visible = false
			newFrame:Destroy()
		end)
	end
end

--Activates the emote animation specified by name.  
--If it exists (not yet implemented)
function Cortex.Emote(self: Cortex, emoteName)
	--LETS MAKE THIS PLAY THE EMOTE ANIMATION DIRECTLY
	--INSTEAD OF USING humnaoid:PlayEmote()
		
	--self.NPC.Humanoid:PlayEmote(emoteName)
end

--Tweens a pt label in a random direction upward from the NPC to indicate hits
--or rep or xp points of some kinds given or taken by the NPC
function Cortex.IndicatePts(self: Cortex, value: string, textColor: Color3)
	local newLabel = INDICATOR_TAG_IMG_TPL:Clone()._TextLbl
	newLabel.Text = value
	if(textColor)then
		newLabel.TextColor3 = textColor
	end
	newLabel.BackgroundTransparency = 1
	newLabel.TextTransparency = 1
	newLabel.Parent = self.IndicatorGui

	local tweenLbl = game:GetService("TweenService"):Create(newLabel, TweenInfo.new(1), {
		Position = UDim2.fromScale(math.random(0,100)/100, math.random(0,30)/100),
		TextTransparency = 0
	})
	tweenLbl.Completed:Once(function()
		newLabel:Destroy()
	end)
	tweenLbl:Play()
end

--Enables the NPC character detection zone (DZ) 
--Required to detect other characters and to use Certain Modes.
function Cortex.EnableCharDZ(self: Cortex, range: NumberRange, focusRange: NumberRange, gracePeriod: number)
	if(not(self))then return end 
	if(self.CharDetect)then warn("Char Detection already enabled") return end
	self.CharDetect = CharDetect.New(self.NPC, range, focusRange, gracePeriod)
	self.CharDetect.Enabled = true
end

function Cortex.SetServerMode(self: Cortex, mode: ("Off" | "Listen" | "Control"))
	if(not(self))then return end
	if(RunServ:IsClient())then return end
	
	--IF THE SERVER MODE IS "Off" then the server is just handing over control to Client, ClientAi expected to handle it
	--IF THE SERVER MODE IS "Listen" then the server still listens to the CharDetect events but won't handle movement etc..
	--IF THE SERVER MODE IS "Control" then control is never transferred to client, tracking is handled only by the server.
	--IF CALLED FROM CLIENT, SERVERMODE IS IGNORED..	
	self.ServerMode = mode or "Listen" --Default to Listen?
	--If ServerMode is nil, we can assume its the client running something
	--Listen will likely be the most utilized since it offers the ability for events to be handled
	--On both the server and client side. Perhaps for situations where different things should be done.
end

--Transfers ownership and control of NPC between 
--Server/Client Cortex instances
function Cortex.TransferControl(self: Cortex, player: Player, data: any?)
	if(not(self))then return end
	if(RunServ:IsClient())then 
		self:Disable()
		LINK:FireServer({
			Msg = "ControlReturn",
			Data = {NPC = self.NPC}
		})
		return 
	end--Client use automatically disables and sends control back to server
	
	local controlOwner = if(player)then player.Name else "Server"
	print("Transferring Control To", controlOwner)
	if(not(player))then
		Tool.GiveOwnership(self.NPC, nil) --Make the server the owner
		self.NPC:SetAttribute("Owner", 0)
		self:Enable()
		self.Enabled = true
	else
		Tool.GiveOwnership(self.NPC, player) --Make the player the owner
		self.NPC:SetAttribute("Owner", player.UserId)
		self:Disable()
		self.Enabled = false
		data.NPC = self.NPC --Add this NPC model to the data
		LINK:FireClient(player, {
			Msg = "ControlGiven",
			Data = data
		})
	end
end

--Destroys the cortex instance
function Cortex.Destroy(self: Cortex)
	self._DyingEvent:Fire("Self-Destruct")

	Tool.CancelConns(self._Conns)
	Tool.CancelConns(self._ModeConns)

	self.LifeTime = nil

	self.BubbleChatGui = nil
	self.IndicatorGui = nil

	self.PointDist = nil
	self.JumpDelayDist = nil

	if(self.CharDetect)then
		self.CharDetect:Destroy()
	end
	self.CharDetect = nil

	if(self.Path)then self.Path:Destroy() end
	self.Path = nil
	self.AgentParams = nil
	self.Dest = nil
	self.FinalDest = nil
	self.Waypoints = nil
	self.WatchPoint = nil
	self.NextWaypoints = nil

	self.PatrolPoints = nil
	self.PatrolRoute = nil

	self.RigType = nil
	self.Humanoid = nil

	self.ShowStatusDisplay = nil
	self.Traveling = nil
	self.ShowPathway = nil
	self.DoJump = nil
	self.Jumped = nil

	self._WaypointReachedEvent:Destroy()
	self.WaypointReached = nil

	self._DestReachedEvent:Destroy()
	self.DestReached = nil

	self._TripEndedEvent:Destroy()
	self.TripEnded = nil

	self._NoPathFoundEvent:Destroy()
	self.NoPathFound = nil

	self._DyingEvent:Destroy()
	self.Dying = nil

	self._LifeTimeOverEvent:Destroy()
	self.LifeTimeOver = nil

	self._CatchEvent:Destroy()
	self.TargetCaught = nil

	self._EscapeEvent:Destroy()
	self.TargetEscaped = nil

	if(RunServ:IsServer())then
		if(self.NPC)then pcall(function() self.NPC:Destroy() end) end
	end
	self.NPC = nil

	self = nil
end


--( RETURN )--
return Cortex
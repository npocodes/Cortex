--[[
	NPC Cortex Module [Shared]
	Emskipo
	July 25 2023

	THIS MODULE PROVIDES COMMON AI RELATED METHODS --
	MOVEMENT METHODS, SPAWNING, any generalized AI methods.

	Unique "AIs" should "Extend" this module to supply the functionality
	required to make the AI function.

	This module should not perform any functions/methods
	specific to AI types. Only things common to any type of Ai

	TODO:
		--Convert to StandAlone Framework
--]]


--{ SERVICES }--

local RunServ = game:GetService("RunService")

--Server Only Services
local ServStor
if(not(RunServ:IsClient()))then
	ServStor = game:GetService("ServerStorage")
end
local RepStor = game:GetService("ReplicatedStorage")
local PathServ = game:GetService("PathfindingService")


--{ REQUIRED }--

local Common
local Types
local ToolEm
local CharDetect


--( MODULE )--

local Cortex = {}
Cortex.ClassName = "Cortex"
Cortex.__index = Cortex
Cortex.IsReady = false


--{ CLASS EVENTS }--

local _ReadyEvent = Instance.new("BindableEvent")
Cortex.Ready = _ReadyEvent.Event


--{ TYPE DEF }--

type ToolEm = Types.ToolEm
type DetectionDetails = Types.DetectionDetails
type CharDetect = Types.CharDetect
type AgentParams = Types.AgentParams
type Cortex = Types.Cortex

export type Point = (Vector3 | CFrame | BasePart)




--{ CONSTANTS }--

local ANIM_SCRIPT
local NCP_GROUP
local CHAR_TAGS
local STATUS_TAG
local STATUS_TAG_FRAME_TPL

local INDICATOR_TAG
local INDICATOR_TAG_LABEL_TPL

-- WAYPOINT OBJECT
local WAYPOINT_OBJ
local MARKER_DIR
local NPC_DIR


--{ PRIVATE }--

local function CancelConns(connList: {RBXScriptSignal})
	for i, conn in connList do
		if(conn)then
			conn:Disconnect()
			conn = nil
		end
	end
end

--Take a point to be used for positioning purposes and returns the Vector3 value
local function PointPosition(point: Point): Vector3?
	if(not(point))then warn("No Point was provided") return end
	if(typeof(point) == "Vector3")then return point end
	if(typeof(point) == "Instance")then point = point:GetPivot() end
	return point.Position
end

local function PointCF(point: Point): CFrame?
	if(not(point))then warn("No Point was provided") return end
	if(typeof(point) == "CFrame")then return point end
	if(typeof(point) == "Vector3")then return CFrame.new(point) end
	return point:GetPivot()
end

--Handles moving the character to the current waypoint.  
--**Runs each heartbeat** (If traveling)
local function Trek(self: Cortex, ...)
	if(not(self.Traveling) or not(self.WatchPoint))then return end
	if(not(self.Waypoints))then return end

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

	self.Humanoid:MoveTo(self.WatchPoint.Position)

	if(self.WatchPoint.Action == Enum.PathWaypointAction.Jump)then
		if(not(self.Jumped))then self.DoJump = true end
	end

	if((tick() - self.WatchPoint.StartTime) > 5)then
		--player must be stuck
		--self.NPC.HumanoidRootPart.CFrame = self.NPC.HumanoidRootPart.CFrame:Lerp(self.WatchPoint.Point.CFrame, .99)
		self.NPC:PivotTo(self.NPC:GetPivot():Lerp(CFrame.new(self.WatchPoint.Position), .99))
	end
end

local function Follow(self: Cortex, ...)
	--NOT YET IMPLEMENTED
	return
end

--Chases the target specified by FollowTarget. When distance is less than Min range  
--the **TargetCaught** event is fired. When distance is greater than Max range the  
--**TargetEscaped** event is fired.
local function Chase(self: Cortex, ...)
	if(not(self.NPC and self.NPC.Humanoid))then return end

	local target = self.CharDetect.FocusChar
	local followRange = self.CharDetect.FocusRange

	--self:SetStatus("Chasing "..target.Name)
	local dist = (self.NPC:GetPivot().Position - target:GetPivot().Position).Magnitude
	local position = self.NPC:GetPivot().Position

	--Adjust the NPC speed based on dist to the target.
	local distPerc = dist/followRange.Max
	distPerc = math.min(1, distPerc) -- cap at 100%
	distPerc = math.max(0, distPerc) --cap at 0%

	local speed = self.ChaseSpeed.Max * distPerc
	speed = math.max(self.ChaseSpeed.Min, speed) -- Cap at min speed
	speed = math.min(self.ChaseSpeed.Max, speed) -- Cap at max speed

	if(self.Dash)then return end
	self.NPC.Humanoid.WalkSpeed = speed
	--This constant speed update effects dashing..
end

local function Track(self: Cortex, ...)
	self:SetStatus("Tracking "..self.FollowTarget.Name)
	if(not(self.WatchPoint))then return end
	local switchPoint = self.Waypoints[self.WatchPoint.Idx + 1] or self.Waypoints[self.WatchPoint.Idx]
	local newWaypoints = self:FindPathway(self.FollowTarget:GetPivot().Position, switchPoint.Position)
	if(newWaypoints)then
		self.SwitchPoint = switchPoint
		self.NextWaypoints = newWaypoints
	end
end

--Handles waypoint reached events and fires the dest reached  
--event if the waypoint reached is end of the path.
local function OnWaypointReached(self: Cortex, ...)

	if(self.WatchPoint == self.SwitchPoint)then
		self:ClearWaypoints()
		self:SetPoints(self.NextWaypoints)

		self.WatchPoint = nil
		self.SwitchPoint = nil
		self.NextWaypoints = nil
		self:TrekPath(self.Waypoints)

	elseif(self.WatchPoint.Idx == #self.Waypoints)then
		self.Traveling = false
			--Determine if the dest reached was the final dest or not!
		if(self.Dest == self.FinalDest)then
			self._TripEndedEvent:Fire()
			--OnTripEnded(self)--Final Destination has been reached! CONVERTED TO EVENT!
			return
		end
		self._DestReachedEvent:Fire()
	else
		--Set next watchpoint
		--self.WatchPoint.Point.Transparency = 1 --Hide the used waypoint
		if(self.WatchPoint.Point)then
			self.WatchPoint.Point:Destroy() --Remove the waypoint object
		end

		self.WatchPoint = self.Waypoints[self.WatchPoint.Idx + 1]
		if(self.WatchPoint.Point)then
			self.WatchPoint.Point.BrickColor = BrickColor.new("Bright green")
		end
		self.WatchPoint.StartTime = tick()
	end
end

--Checks if the current waypoint has been reached
--and if so fires the WaypointReached event
local function WatchWaypoint(self: Cortex, ...)
	if(not(self.WatchPoint))then return end
	if(not(self.NPC) or not(self.NPC:FindFirstChild("HumanoidRootPart")))then return end

	local dist = (self.NPC.HumanoidRootPart.Position - self.WatchPoint.Position).Magnitude
	if(dist <= self.PointDist)then
		--Waypoint reached!
		self.Jumped = false --reset jump flag
		self._WaypointReachedEvent:Fire(dist)
	end
end

--This event will fire if, at any time during the path’s existence, the path is blocked. 
--Note that this can occur behind a character moving along the path, not just in front of it. -RBLX
local function OnPathBlocked(self: Cortex, wpIdx)
	if(true)then return end
	--HOW ABOUT OBJECT THAT BLOCKED THE PATH ASSHOLES!
	--Custom programming required to detect the blockage.
	--We could probably fire off a spatial query at the location
	--of the waypoint that matches the index we get.

	local diff = wpIdx - self.WatchPoint.Idx
	if(diff > 0)then
		warn("Path Blocked ahead:", wpIdx, diff)
	elseif(diff < 0)then
		warn("Path Blocked behind:", wpIdx, diff)
	else
		warn("Path blocked", wpIdx, diff)
	end
end

--PathUnblocked...

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

--Calls methods and functions that should be run  
--during the stepped event of the task scheduler.  
--**Fires before physics**
local function OnStepped(self: Cortex, ...)
	--Move, if enabled...
	--self:MoveTo()
end

--Calls methods and functions that should be run  
--during the heartbeat event of the task scheduler.  
--**Fires after physics calcuations**
local function OnHeartbeat(self: Cortex, ...)
	if(not(self.Enabled))then return end
	
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

	if(self.Traveling)then
		WatchWaypoint(self)--Watch for current way point reached (custom)
		Trek(self)
	end
end


local function Connect(self: Cortex, disable: boolean)

	if(disable)then
		CancelConns(self._Conns)
		return
	end

	self._Conns[#self._Conns+1] = self.NPC.Humanoid.Destroying:Connect(function(...)
		self._DyingEvent:Fire("Destroyed")
	end)

	self._Conns[#self._Conns+1] = self.NPC.Humanoid.Died:Connect(function()
		self._DyingEvent:Fire("Died")
	end)

	self._Conns[#self._Conns+1] = self.Path.Blocked:Connect(function(...)
        OnPathBlocked(self, ...)
	end)

	self._Conns[#self._Conns+1] = self.WaypointReached:Connect(function(...)
        OnWaypointReached(self, ...)
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


--{ PUBLIC }--

function Cortex.Initialize()
	Common = require(RepStor.SharedData.Common)
	Types = require(RepStor.SharedData.TypeDict)
	ToolEm = require(RepStor.SharedData.ToolEm)
	ToolEm.Echo("Loading: Cortex")

	CharDetect = require(script.CharDetect)
end

function Cortex.Run()
	ToolEm.Echo("Running: Cortex")
	Cortex.Ready:Once(function() ToolEm.Alert("Cortex Ready") end)

	task.spawn(function()
		if(not(RunServ:IsClient()))then
			ANIM_SCRIPT = ServStor:WaitForChild("AnimateNPC"):Clone()
		else
			ANIM_SCRIPT = RepStor:WaitForChild("AnimateNPC"):Clone()
		end
		ANIM_SCRIPT.Name = "Animate"
		
		NCP_GROUP = Common.GetGroupName("NPC")
		CHAR_TAGS = RepStor:WaitForChild("CharTags")
		STATUS_TAG = CHAR_TAGS:WaitForChild("_StatusTag"):Clone()
		STATUS_TAG_FRAME_TPL = STATUS_TAG:WaitForChild("_FrameTpl"):Clone()
		STATUS_TAG._FrameTpl:Destroy()
		
		INDICATOR_TAG = CHAR_TAGS:WaitForChild("_IndicatorTag"):Clone()
		INDICATOR_TAG_LABEL_TPL = INDICATOR_TAG:WaitForChild("_StatusLbl"):Clone()
		INDICATOR_TAG._StatusLbl:Destroy()
		
		-- WAYPOINT OBJECT
		WAYPOINT_OBJ = Instance.new("Part")
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
		
		MARKER_DIR = Common.GetDir("Marker")
		NPC_DIR = Common.GetDir("NPC")

		Cortex.IsReady = true
		_ReadyEvent:Fire()
	end)
end

--Creates a new Cortex instance for the provided NPC Model
function Cortex.new(...): Cortex
	return Cortex.New(...)
end
function Cortex.New(NPC: Model, ap: AgentParams): Cortex

	if(not(NPC) or not(NPC:IsA("Model")))then
		warn("Unable to create new Cortex: Missing NPC Model.")
		--return new
	end

	--Create the new instance
	local new:Cortex = {}
	setmetatable(new, Cortex)

	-- NPC DATA
	new.NPC = NPC --The Model Instance
	new.LifeTime = nil --Lifetime/lifespan of this NPC in seconds

    --Set the model collision group to default NPC group.
    ToolEm.SetModelCollisionGroup(NPC, NCP_GROUP)

	local animScript = ANIM_SCRIPT:Clone()
	animScript.Parent = new.NPC

	new.Humanoid = NPC:WaitForChild("Humanoid")
	new.RigType = new.Humanoid.RigType --Enum.HumanoidRigType

	new.StatusGui = STATUS_TAG:Clone()
	new.StatusGui.Parent = new.NPC
	new.StatusGui.Adornee = new.NPC.PrimaryPart
	new.StatusGui.Enabled = true

	new.IndicatorGui = INDICATOR_TAG:Clone()
	new.IndicatorGui.Parent = new.NPC
	new.IndicatorGui.Adornee = new.NPC.PrimaryPart
	new.IndicatorGui.Enabled = true

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

	--Patrol Points
	new.PatrolPoints = {} --Table of all possible patrol points
	new.PatrolRoute = {} --Array of Patrol Points used in current route

	--Follow Data
	new.FollowTarget = false
	--new.FollowRange = nil
	new.Chasing = false
	new.Tracking = false
	new.OnPatrol = false

	-- STATE FLAGS
	new.ShowStatusDisplay = false
	new.CharacterDetectionEnabled = false
	new.CalculatingPath = false
	new.Traveling = false --whether the NPC is following a path or not
	new.ShowPathway = false
	new.DoJump = false
	new.Jumped = false

	-- CUSTOM PATH EVENTS --
	new._WaypointReachedEvent = Instance.new("BindableEvent")
	new.WaypointReached = new._WaypointReachedEvent.Event

	new._DestReachedEvent = Instance.new("BindableEvent")
	new.DestReached = new._DestReachedEvent.Event

	new._TripEndedEvent = Instance.new("BindableEvent")
	new.TripEnded = new._TripEndedEvent.Event

	new._NoPathFoundEvent = Instance.new("BindableEvent")
	new.NoPathFound = new._NoPathFoundEvent.Event


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
	new._ChaseConns = {}
	new._FollowConns = {}
	new._PatrolConns = {}
	new._Conns = {}

	Connect(new)

	--Return the new instance
	return new
end

--Returns a Cortex waypoint obj used for path tracing.
function Cortex.GetWaypoingObj(): Part
	return WAYPOINT_OBJ:Clone()
end


--{ METHODS }--

--Disables cortex instance
function Cortex.Disable(self: Cortex)
	--Pauses/Stops all events, moves etc..
	CancelConns(self._Conns)
	if(self.CharDetect)then
		self.CharDetect.Enabled = false
	end
end

--Re-Enables cortex instance
function Cortex.Enable(self: Cortex)
	--Resumes/Starts all events, moves etc..
	Connect(self)
	if(self.CharDetect)then
		self.CharDetect.Enabled = true
	end
end


--Custom Movement method for NPCS for following a provided waypoint path.  
function Cortex.TrekPath(self: Cortex, waypoints:{PathWaypoint})
	--if(self.Traveling)then return end
	if(not(waypoints) or #waypoints < 1)then warn("Must supply Waypoints array.", debug.traceback()) return end
	self.WatchPoint = waypoints[1]
	self.WatchPoint.StartTime = tick()
	self.Traveling = true
	self:SetStatus("Traveling")
end







--Makes the character move to the specified destination  
--**DO NOT CALL EVERY HEARTBEAT** Set once!
function Cortex.MoveTo(self: Cortex, dest: Point, finalDest: boolean): boolean

	dest = PointPosition(dest)

	--ADD FINAL DEST CHECK!!

	--Check for a change in destination
	if(self.Dest ~= dest)then
		if(self.Dest)then self:CancelMove(true) end--Cancel Prev MoveTo
		self.Dest = dest --Set new dest
	end
	if(not(self.Dest))then print("NO DEST:", self.NPC.Name) return false end --No Destination


	if(self.Traveling)then
		--Trek(self)
	else
		--Not yet traveling..
		if(not(self.Waypoints))then
			local waypoints = self:FindPathway(self.Dest)
			if(not(waypoints) or #waypoints < 1)then
				return
			else
				self:SetPoints(waypoints)
			end
		end

		if(self.ShowPathway)then self:ShowPath(self.Waypoints) end
		self:TrekPath(self.Waypoints)
	end
end

--Pauses moving to the current dest
function Cortex.PauseMove(self: Cortex)
	self.Traveling = false
	self.Humanoid:MoveTo(self.Humanoid.Parent:GetPivot().Position) --Stop
end

--Resumes moving to the current dest
function Cortex.ResumeMove(self: Cortex)
	if(self.WatchPoint)then self.WatchPoint.StartTime = tick() end --Reset the watch point timer
	self.Traveling = true
end

--Cancels the current MoveTo and stops the NPC  
--Cannot be Resumed!
function Cortex.CancelMove(self: Cortex, noStop: boolean)
	self.Traveling = false
	self:ClearWaypoints()
	if(noStop)then return end

	self:SetStatus("Stopped")
	self.Humanoid:MoveTo(self.Humanoid.Parent:GetPivot().Position) --Stop
end







--Set the table of patrol points to use for patrol routes
function Cortex.SetPatrolPoints(self: Cortex, patrolPoints: {Point})
	if(not(self or patrolPoints))then return end
	for i, point in patrolPoints do
		self.PatrolPoints[i] = PointPosition(point)
	end
	self.PatrolPoints = patrolPoints
end

--Sets the patrol route to be used when on Patrol  
--If a route is not provided, a random route will be chosen  
--from the patrol points set if any.
function Cortex.SetPatrolRoute(self: Cortex, route: table?)
	if(not(self))then return end
	if(not(route) or #route < 1)then
		--No route specified, use a random route if we can
		if(not(self.PatrolPoints or #self.PatrolPoints < 1))then
			return false
		end

		--Select a random start point
		local point1 = PointPosition(self.PatrolPoints[math.random(#self.PatrolPoints)])
		local point2 = point1

		--Ensure the points are not the same one
		repeat
		point2 = PointPosition(self.PatrolPoints[math.random(#self.PatrolPoints)])
			task.wait()
		until point2 ~= point1

		self.PatrolRoute = {point1, point2}
	else
		--Route was specified
		for i, point in route do
			self.PatrolRoute[i] = PointPosition(point)
		end
	end
	return true
end

--Makes the NPC move back and forth between the specified points  
--**DO NOT CALL EVERY HEARTBEAT** Set Once!
function Cortex.Patrol(self: Cortex, route: table?)
	CancelConns(self._PatrolConns)--Clear stale conns

	if(not(self:SetPatrolRoute(route)))then
		warn("No Patrol Routes Available. Set Patrol Points or Provide specific route")
		return
	end

	--WHILE PATROLLING ONLY!!! WE NEED TO BE ABLE TO "PAUSE" THIS SWITCH
	--SO THE PATROL CAN BE PAUSED AND RESUMED AS NEEDED.
	self._PatrolConns[#self._PatrolConns+1] = self.DestReached:Connect(function(...)
		if(not(self.OnPatrol and self.PatrolRoute))then return end

		--Moving to next Patrol Dest
		for i=1, #self.PatrolRoute do
			if(self.Dest == self.PatrolRoute[i])then
				local idx = if (i == #self.PatrolRoute) then 1 else i+1 --Wrap around to first point
				self:MoveTo(self.PatrolRoute[idx])
				return
			end
		end
	end)

	self.NoPathFound:Once(function()
		if(not(self.OnPatrol))then return end
		self:Patrol()
	end)

	self.OnPatrol = true
	self:MoveTo(self.PatrolRoute[2])--Begin by going to 2nd point
	--First point is usually the spawn point.
end









--The Chase cycle makes the NPC chase after the specified target  
--When chasing the NPC will attempt to "Catch" the target and the target can "Escape"..
function Cortex.Chase(self: Cortex, target: (Model | BasePart), range: NumberRange, speed: NumberRange, delay: NumberRange)
	if(not(self.CharDetect))then warn("Char Detection has not been activated yet.") return end

	self:PauseMove()
	self.OnPatrol = false --Pause Patrolling if patrolling
	self.Chasing = true --Set Chasing to true

	speed = (typeof(speed) == "NumberRange") and speed or NumberRange.new(16)
	self.ChaseSpeed = speed

	self.CaughtUp = false
	self.CharDetect.FocusChar = target
	self.CharDetect.FocusRange = range


	--CONNECT TO THE CHAR DETECT FOCUS EVENTS
	self._ChaseConns[#self._ChaseConns+1] = self.CharDetect.CharCloseFocus:Connect(function(char, details)
		--CAUGHT THE CHARACTER!!
		self._CatchEvent:Fire(target)
	end)

	self._ChaseConns[#self._ChaseConns+1] = self.CharDetect.CharInFocus:Connect(function(char, details)
		if(not(self.NPC and self.NPC.Humanoid))then return end
		--Char is in focus, chasing...

		--Between Min/Max, CHASE!
		--Keep track of the chase offset, so the NPC isn't constantly doing zigzags
		local offset = self.NPC:GetAttribute("ChaseOffset")
		if(not(offset))then
			local offsetRange = self.CharDetect.FocusRange.Min - 1
			offset = CFrame.new(math.random(-offsetRange, offsetRange),0,math.random(-offsetRange, offsetRange))
			self.NPC:SetAttribute("ChaseOffset", offset)
		end

		local position = (target:GetPivot() * offset).Position
		self.NPC.Humanoid:MoveTo(position)
	end)

	self._ChaseConns[#self._ChaseConns+1] = self.CharDetect.CharFocusGain:Connect(function(char, details)
		--Regained focus on Char!
		return
	end)

	self._ChaseConns[#self._ChaseConns+1] = self.CharDetect.CharFocusLost:Connect(function(char, details)
		--FOCUS LOST!! (ESCAPED!!)
		self._EscapeEvent:Fire(target)
	end)
end

--Cancels the current Chase cycle and stops the NPC
function Cortex.StopChase(self: Cortex, msg: string)
	CancelConns(self._ChaseConns)--Clear conns

	self.CharDetect.FocusChar = nil
	self.Chasing = false

	self.ChaseSpeed = nil
	self.CaughtUp = false
	self.NPC:SetAttribute("ChaseOffset", nil)

	if(msg)then self:SetStatus(msg) end
	self.Humanoid:MoveTo(self.Humanoid.Parent:GetPivot().Position) --Stop
	self.Humanoid.WalkSpeed = self.Humanoid:GetAttribute("DefaultSpeed") or 16
end






--{ FOLLOW TYPE MOVEMENT METHODS }---

--The Follow cycle makes the NPC follow the specified target  
--When following, the NPC will stay within the specified range of the target.  
--Automatically cancels any previous MoveTo  
--**DO NOT CALL EVERY HEARTBEAT** Set once!
function Cortex.Follow(self: Cortex, target: (Model | BasePart), range: NumberRange)
	if(not(self.CharDetect))then warn("Char Detection has not been activated yet.") return end

	--self:CancelMove(true)
	self:PauseMove()
	self.OnPatrol = false --Pause Patrolling if patrolling

	self.CharDetect.FocusChar = target
	self.CharDetect.FocusRange = range

	self._FollowConns[#self._FollowConns+1] = self.CharDetect.CharCloseFocus:Connect(function(char, details)
		--TOO CLOSE TO CHAR!!
		--self._CatchEvent:Fire(target)
	end)

	self._FollowConns[#self._FollowConns+1] = self.CharDetect.CharInFocus:Connect(function(char, details)
		--Char is in focus, stay put!
		self:TurnToward(char:GetPivot())
	end)

	self._FollowConns[#self._FollowConns+1] = self.CharDetect.CharFocusGain:Connect(function(char, details)
		--Regained focus on Char!
	end)

	self._FollowConns[#self._FollowConns+1] = self.CharDetect.CharFocusOut:Connect(function(char, details)
		--Char is out of focus, move closer!!
		self.NPC.Humanoid:MoveTo(target:GetPivot().Position)
	end)

	self._FollowConns[#self._FollowConns+1] = self.CharDetect.CharFocusLost:Connect(function(char, details)
		--LOST FOCUS ON CHAR!!
		--This should end the follow.. But does this happen
		--in the specific AI or should we do it here?!?
	end)

end

--Cancels the current Follow Cycle and stops the NPC
function Cortex.StopFollow(self: Cortex)

	CancelConns(self._FollowConns)--Clear conns
	self.CharDetect.FocusChar = nil

	self:SetStatus("Stopped")
	self.Humanoid:MoveTo(self.Humanoid.Parent:GetPivot().Position) --Stop
	self.Humanoid.WalkSpeed = self.Humanoid:GetAttribute("DefaultSpeed") or 16
end





--The Track cycle makes the NPC find the specified target  
--wherever in the map the target is.
function Cortex.Track(self: Cortex, target: (Model | BasePart))
	if(not(self.CharDetect))then warn("Char Detection has not been activated yet.") return end

	self:CancelMove(true)
	self.Tracking = true
	self.FollowTarget = target
	self:MoveTo(self.FollowTarget:GetPivot())
end

--Cancels the current Track Cycle and stops the NPC
function Cortex.StopTracking(self: Cortex, msg: string)
end


--Enables the NPC character detection zone (DZ) 
--Required to detect other characters and to use Move Cycle methods.
function Cortex.EnableCharDZ(self: Cortex, range: NumberRange, focusRange: NumberRange, gracePeriod: number)
	if(not(self))then return end
	self.CharDetect = CharDetect.New(self.NPC, range, focusRange, gracePeriod)
	self.CharDetect.Enabled = true
end



--{ UTILITY METHODS }--

--Faces the NPC in the direction of the dest provided
function Cortex.TurnToward(self: Cortex, point: Point)
	local targetPos = PointPosition(point)
	targetPos = Vector3.new(targetPos.X, self.NPC:GetPivot().Position.Y, targetPos.Z)
	local cf = CFrame.lookAt(self.NPC:GetPivot().Position, targetPos)
	self.NPC:PivotTo(cf)
end

--Creates a new status message for the NPC to display.  
--Basically like a chat bubble for NPCs
function Cortex.SetStatus(self: Cortex, status: string, lifetime: number?)
	if(not(status))then return end

	if((self.ShowStatusDisplay or lifetime) and self.StatusGui)then
		self.StatusGui.Enabled = true
		local newFrame = STATUS_TAG_FRAME_TPL:Clone()
		local zindex = self.StatusGui:GetChildren()
		self.StatusGui:ClearAllChildren()
		
		newFrame.ZIndex = #zindex + 1
		newFrame.Parent = self.StatusGui

		newFrame.Visible = true
		local label = newFrame:FindFirstChild("_StatusLbl", true)
		if(label)then label.Text = status end
		if(lifetime)then
			task.delay(lifetime, function()
				if(not(self.StatusGui))then return end
				if(not(newFrame))then return end
				if(not(self.ShowStatusDisplay))then self.StatusGui.Enabled = false end
				newFrame:Destroy()
			end)
		end
	end
end

--Tweens a pt label in a random direction upward from the NPC to indicate hits
--or rep or xp points of some kinds given or taken by the NPC
function Cortex.IndicatePts(self: Cortex, value: string, textColor: Color3)
	local newLabel = INDICATOR_TAG_LABEL_TPL:Clone()
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

--Creates waypoint parts to show the waypoint path provided
function Cortex.ShowPath(self: Cortex, waypoints:{PathWaypoint})
	if(not(waypoints))then warn("Must supply Waypoints array.") return end
	for i = 1, #waypoints do
		local point = WAYPOINT_OBJ:Clone()
		point.Parent = MARKER_DIR
		point.Position = waypoints[i].Position
		if(waypoints[i].Action == Enum.PathWaypointAction.Jump)then
			point.BrickColor = BrickColor.new("Neon orange")
		end
		self.Waypoints[i].Point = point --add the point obj to the waypoint's data
	end
end

--Creates a path object using the provided path parameters
function Cortex.SetNewPath(self: Cortex, ap: AgentParams): Path
	if(not(ap))then ap = {} end
	ap.AgentRadius = ap.AgentRadius or 2
	ap.AgentHeight = ap.AgentHeight or 2
	ap.AgentCanJump = ap.AgentCanJump or true
	ap.WaypointSpacing = ap.WaypointSpacing or 16

	self.Path = PathServ:CreatePath(ap)
	return self.Path
end

--Attempts to locate a pathway from the NPC position to the provided destination position.  
--If a path is found, then the waypoints array is returned.  
function Cortex.FindPathway(self: Cortex, dest: Point, startPoint: Point): {PathWaypoint}?

	if(not(dest))then self:SetStatus("No Dest..") return end
	dest = PointPosition(dest)
	startPoint = if(startPoint) then PointPosition(startPoint) else self.NPC:GetPivot().Position

	--PATH STATUS THAT MAY STILL BE WORKABLE FOR FINDING A PATH!!
	-- ClosestNoPath - Path doesn't exist, but returns a path closest to that dest/point
	-- ClosestOutOfRange - Goal is beyond max distance range, returns path to closest point you can reach within MaxDistance.

	--First compute the path with pathFinding
	local success, msg = pcall(function()
		self.Path:ComputeAsync(startPoint, dest)
		if(self.Path.Status == Enum.PathStatus.Success)then return true end
		return false
	end)

	if(success)then
		--A pathway was found!
		return self.Path:GetWaypoints()
	else
		self:SetStatus(self.Path.Status.Name)
		self._NoPathFoundEvent:Fire(self.Path.Status.Name, startPoint, dest)
	end
end

--Set the waypoints to use
function Cortex.SetPoints(self: Cortex, waypoints:{PathWaypoint})
	--self.Waypoints = nil
	self:ClearWaypoints()
	local newPoints = {}
	table.remove(waypoints, 1)--Remove first waypoint.. usually too close.
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



--Spawns the NPC at the specified Vector3 or CFrame Position
--If parent is not supplied, defaults to Workspace
--DOES NOT USE TELEPORT METHOD TO ENSURE SAFE SPAWNING
function Cortex.Spawn(self: Cortex, point: Point, parent: Instance?, lifetime: number?): boolean
    if(not(point))then return end
	point = PointCF(point)

	self.SpawnLocation = point--Remember the spawn cf
	self.NPC:PivotTo(self.SpawnLocation) --This should be a CFrame
	self.NPC.Parent = parent or NPC_DIR
	ToolEm.GiveOwnership(nil, self.NPC) --Make the server the owner

	if(lifetime and lifetime > 0)then
		self.LifeTime = tick()+lifetime
	end

    return true
end

--Uses Teleport method to safely spawn the NPC at the provided position
function Cortex.SafeSpawn(self: Cortex, point: Point, lookAt: Vector3?, lifetime: number?, parent: Instance?): boolean
	if(not(point))then warn("SafeSpawn() requires a CFrame.") return end -- No cf given
	point = PointCF(point)

	--Attempt to relocate the NPC to the provided cf
	local success, spawnCF = self:Teleport(point, lookAt)
	if(not(success))then return end --Unable to safely relocate NPC to cf provided

	self.SpawnLocation = spawnCF--Remember the spawn Position/Location
	self.NPC.Parent = parent or NPC_DIR
	ToolEm.GiveOwnership(nil, self.NPC) --Make the server the owner

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
	point = PointCF(point)

	if(not(unsafe))then
		local rayCF = CFrame.new(point.Position) * CFrame.Angles(math.rad(-90),0,0)
		local params = RaycastParams.new()
		params.RespectCanCollide = true

		local result = ToolEm.FrameRay(rayCF, 25, params)
		if(result)then
			if(not(result.Distance < 10 and result.Distance >= self.NPC.Humanoid.HipHeight))then
				warn("Teleport Failed: Unsafe Height")
				return false --Not Safe heights
			end
		end
		local parts = ToolEm.SpatialCheck(CFrame.new(point.Position))
		if(#parts > 0)then warn("Teleport Failed: Blocked", parts) return false end --Position Blocked/Inside collidable obj
	end

	local spawnCF
	if(lookAt)then
		local y = (unsafe) and lookAt.Y or self.NPC:GetPivot().Y --Stop NPC from tilting off their feet
		lookAt = Vector3.new(lookAt.X, y, lookAt.Z)
		spawnCF = CFrame.lookAt(point.Position, lookAt)
	else
		spawnCF = CFrame.new(point.Position) --If CFrame or Instance given without lookAt, then ignore CFrame look vector
	end

	self.NPC:PivotTo(spawnCF)
	return true, spawnCF
end

--Puts the NPC into a STUNNED state
function Cortex.StunNPC(self: Cortex)
	self.NPC.Humanoid.WalkSpeed = 0
	self.NPC.Humanoid.JumpPower = 0
	self:CancelMove()
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


--Destroys the cortex instance
function Cortex.Destroy(self: Cortex)
	self._DyingEvent:Fire("Self-Destruct")

	ToolEm.CancelConns(self._Conns)
	ToolEm.CancelConns(self._ChaseConns)
	ToolEm.CancelConns(self._FollowConns)
	ToolEm.CancelConns(self._PatrolConns)

	self.LifeTime = nil

	self.StatusGui = nil
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

	self.Chasing = nil
	self.Tracking = nil
	self.OnPatrol = nil

	self.ShowStatusDisplay = nil
	self.CharacterDetectionEnabled = nil
	self.CalculatingPath = nil
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
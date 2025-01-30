--[[
	UTILITY TOOLS MODULE
	
	This SubClass provides special utility functions for the Cortex Class

--]]

--{ SERVICES }--

local RunServ = game:GetService("RunService")
local PhysicServ = game:GetService("PhysicsService")
local Debris = game:GetService("Debris")




--( MODULE )--

local Tool = {}
Tool.ClassName = "Tool"
Tool.__index = Tool


--COMMON STUFF--

Tool.CHAR_GROUP_NAME = "CHARS"
Tool.CHAR_DIR_NAME = "_CHARACTERS_"
Tool.CHAR_DIR = nil --Created during first runs

Tool.NPC_GROUP_NAME = "NPCS"
Tool.NPC_DIR_NAME = "_NPCS_"
Tool.NPC_DIR = nil --Created during first runs

Tool.MARKER_GROUP_NAME = "MARKERS"
Tool.MARKER_DIR_NAME = "_MARKERS_"
Tool.MARKER_DIR = nil --Created during first runs


--{ PUBLIC FUNCTIONS }--

--Returns the folder/directory associated with the name provided
--If the directory doesn't exist its created if called from server
--If called from client, then yields until the directory exists
function Tool.GetDir(dirName: string, dirParent: Instance?)
	dirParent = dirParent or game.Workspace
	
	local dir
	
	--First lets see if the directory already exists
	dir = game.Workspace:FindFirstChild(dirName, true)
	if(dir)then return dir end --Already exists, we are done

	--Since it doesn't exist, we need to wait for it (client) or create it (server)
	if(RunServ:IsClient())then
		--We will need to wait for the server to create this directory
		local dirConn = nil
		dirConn = game.Workspace.ChildAdded:Connect(function(child)
			if(not(child:IsA("Folder")))then return end --Not a folder
			if(child.Name ~= dirName)then return end --Name mismatch
			dirConn:Disconnect()
			dirConn = nil
			dir = child
		end)
		repeat task.wait() until dir --wait for it
	else
		--This is the server so we'll create the directory
		dir = Instance.new("Folder")
		dir.Parent = game.Workspace
		dir.Name = dirName
	end
	
	return dir
end


--Sets the collision group for the instance provided
function Tool.SetModelCollisionGroup(model: (Model | Folder), groupName: string)
	if(not(model))then warn("No Model Provided", debug.traceback()) return end
	groupName = groupName or "Default"
	
	--If the collision group doesn't exist then try to make it
	if(not(PhysicServ:IsCollisionGroupRegistered(groupName)))then
		PhysicServ:RegisterCollisionGroup(groupName)
	end
	
	--Add the parent instance to the group (if its a basepart)
	if(model:IsA("BasePart"))then model.CollisionGroup = groupName end
	
	--Add any descendant baseparts to the group
	local descendants = model:GetDescendants()
	for i, descendant in descendants do
		if(descendant:IsA("BasePart"))then
			descendant.CollisionGroup = groupName
		end
	end
	
	--Listen for descendants added and add them as well.
	--If the model is destroyed this will automatically be disconnected
	model.DescendantAdded:Connect(function(descendant)
		if(descendant:IsA("BasePart"))then
			descendant.CollisionGroup = groupName
		end
	end)
end

--Assigns Network Owner of the provided instance to the specified player or server if nil
function Tool.GiveOwnership(model: Model, player: Player?)
	if(not(model))then warn("No Model Provided", debug.traceback()) return end
	
	--Add the parent instance to the group (if its a basepart)
	if(model:IsA("BasePart"))then model:SetNetworkOwner(player) end
	
	local part = model:GetDescendants()
	for i = 1, #part do
		pcall(function() part[i]:SetNetworkOwner(player) end)
	end
end

function Tool.GetSurface(cf: CFrame, castParams: RaycastParams, dist: number): FrameRayResult?
	local dist = dist or 25
	local rayCF = CFrame.new(cf.Position) * CFrame.Angles(math.rad(-90), 0, 0)
	return Tool.FrameRay(rayCF, dist, castParams)
end

--Creates a basepart and uses it to check for obstructions at the provided position
--Returns any parts detected within the space.
function Tool.SpatialCheck(cf: CFrame, size: Vector3?, overlapParams: OverlapParams?, lifeTime: number?): table
	local spatialPart = Instance.new("Part")
	spatialPart.Shape = Enum.PartType.Ball
	spatialPart.Anchored = true
	spatialPart.CanCollide = false
	
	local maxSize = math.max(size.X, size.Y, size.Z)
	spatialPart.Size = Vector3.new(maxSize,maxSize,maxSize) --Maybe we should be more specific and grab the size of the HRP
	spatialPart:PivotTo(cf)
	spatialPart.Transparency = 1--.5
	spatialPart.Color = BrickColor.random().Color
	spatialPart.Parent = game.Workspace

	if(not(overlapParams))then
		overlapParams = OverlapParams.new()
		overlapParams.RespectCanCollide = true --This just checks the CanCollide value, not the group based Collisions!!
	end

	local parts = game.Workspace:GetPartsInPart(spatialPart, overlapParams)
	Debris:AddItem(spatialPart, 5)

	return parts
end

function Tool.FrameRay(cf: CFrame, dist: number?, castParams: RaycastParams, trace: boolean?, traceLife: number?): FrameRayResult?

	--Distance in studs to cast the ray. 50 default
	dist = dist or 50

	--Setup the cast parameters
	--castParams.FilterDescendantsInstances = blackList
	local blackList = castParams.FilterDescendantsInstances

	--Cast the Ray and get the results
	local castResult = workspace:Raycast(cf.Position, (cf.LookVector*dist), castParams)

	--Trace the ray?
	if(trace)then
		Tool.TraceVector(cf.Position, cf.LookVector, dist, nil, traceLife)
	end
	if(not(castResult))then return end

	return {
		HitPart = castResult.Instance,
		Material = castResult.Material,
		Position = castResult.Position,
		Normal = castResult.Normal,
		Distance = (cf.Position - castResult.Position).Magnitude,
	}
end

function Tool.TraceVector(startPos: Vector3, dir: Vector3, length: number?, color: Color3?, lifetime: number?)
	if(not(length) or length <= 0) then length = 1 end
	lifetime = lifetime or .1

	local tracer = Tool.NewTracer()
	tracer.Color = color or BrickColor.new("Bright orange").Color
	tracer.Size = Vector3.new(.05, .05, length)

	local lookPos = startPos + (dir * length)
	--Point front face to a position 10units in the direction of the normal from the contact position.
	tracer.CFrame = CFrame.new(startPos:Lerp(lookPos, .5), lookPos)
	tracer.Parent = game.Workspace
	Debris:AddItem(tracer, lifetime)
end

--Returns a new tracer part for displaying rays
function Tool.NewTracer(): BasePart
	local newTracer = Instance.new("Part")
	newTracer.Name = "Tracer"
	newTracer.Shape = Enum.PartType.Block
	newTracer.Anchored = true
	newTracer.CanCollide = false
	newTracer.CanTouch = false
	newTracer.CanQuery = false --This probably makes the folder no longer required
	newTracer.Material = Enum.Material.Neon
	newTracer.Transparency = .5

	return newTracer
end


--Returns a Point as a Vector3
function Tool.PointPosition(point: Point): Vector3?
	if(not(point))then warn("No Point was provided") return end
	if(typeof(point) == "Vector3")then return point end
	if(typeof(point) == "Instance")then point = point:GetPivot() end
	return point.Position
end

--Returns a Point as a CFrame
function Tool.PointCF(point: Point): CFrame?
	if(not(point))then warn("No Point was provided") return end
	if(typeof(point) == "CFrame")then return point end
	if(typeof(point) == "Vector3")then return CFrame.new(point) end
	return point:GetPivot()
end


--Disconnects all connections in the provided connection table
function Tool.CancelConns(connList: {RBXScriptSignal})
	for i, conn in connList do
		if(not(conn))then continue end

		--Handle multi dimensional
		if(typeof(conn) == "table")then 
			task.spawn(function() Tool.CancelConns(conn) end)
			continue
		end

		conn:Disconnect()
		conn = nil
	end
end


--( RETURN )--
return Tool

--[[
    Character Detection Module
    Emskipo
    12/2024

    By default.. Detects characters within the provided parameters
    Specific Targets can be added/removed
    Target do not have to be characters, can be other models/baseparts
--]]

--{ SERVICES }--

local RepStor = game:GetService("ReplicatedStorage")
local RunServ = game:GetService("RunService")
local Players = game:GetService("Players")


--{ REQUIRED }--

local Tool = require(script.Parent.Utility) -- NOT AVAILABLE HERE


--( MODULE )--

local CD = {}
CD.__index = CD


--{ TYPE DEF }--

type FrameRayResult = Tool.FrameRayResult
export type CharDetect = {}


--{ PRIVATE }--

local DZObject = Instance.new("Part")
DZObject.Name = "DZ"
DZObject.Shape = Enum.PartType.Ball --Sphere shape is used to give 360 detection range above/below
DZObject.Massless = true
DZObject.Anchored = false
DZObject.CanCollide = false --The DZ itself won't be detectable
DZObject.CanTouch = false
DZObject.CanQuery = false
DZObject.CastShadow = false
DZObject.EnableFluidForces = false
DZObject.Size = Vector3.new(.5,.5,.5)
DZObject.BrickColor = BrickColor.Blue()
DZObject.Material = Enum.Material.ForceField
DZObject.Transparency = 1

local DEFAULT_RANGE = NumberRange.new(10, 10*2)
local DEFAULT_FOCUS_RANGE = NumberRange.new(DEFAULT_RANGE.Min*2, DEFAULT_RANGE.Max*2)
local DEFAULT_LOS_DISTANCE = 30



--{ FUNCTIONS }--

--Attaches the DetectionZone(DZ) to the NPC model provided
local function AttachDZ(NPC: Model, name: string, color: Color3): Part
    if(not(NPC))then return end
	
	name = name or "DZ"
	
    --Use previously made DZ
	local dz = NPC:FindFirstChild(name)
    if(dz)then return dz end

    --Create a new DZ
	dz = DZObject:Clone()
	dz.Name = name
	dz.Color = color or dz.Color
    local weld = Instance.new("Weld")
    weld.Part0 = NPC.PrimaryPart
    weld.Part1 = dz
    dz.Parent = NPC
    weld.Enabled = true
	weld.Parent = dz

	return dz
end


--Checks if the NPC has LineOfSight on the provided target instance
local function CheckLOS(self: CharDetect, dist: number, target: Instance?): (boolean, FrameRayResult?)
	if(not(target))then warn("CheckLOS: Missing Target") return end
	
	local rayFrame = CFrame.lookAt(self.NPC:GetPivot().Position, target:GetPivot().Position)
	local params = RaycastParams.new()
	dist = dist or DEFAULT_LOS_DISTANCE
	
	--Should we alter LOS to allow "Seeing" a target (CanCollide wall but see through?)
	--Can see, but if CanCollide then can't reach..
	--This would require spatial query and checking each part along LOS
	--Determine if the part has transparency and cancollide to make decision.
	--For now we'll keep LOS as a "can reach" which only requires a raycast
	params.FilterType = Enum.RaycastFilterType.Exclude
	params:AddToFilter(self.NPC)
	params.RespectCanCollide = true 
	params.IgnoreWater = true

    local rayResult: FrameRayResult?
	rayResult = Tool.FrameRay(rayFrame, dist, params, true)
	if(rayResult and rayResult.HitPart)then
		local LOS = false
        if(rayResult.HitPart == target or rayResult.HitPart.Parent == target)then
            LOS = true --ray hit our target
		end
		return LOS, rayResult --what did the ray hit
    end
	return false, "NoHit" --Nothing Hit by ray
end


--Determines if the character detected has gone past the "LostRange" dist.  
--If so, the character is removed from the detected list and the CharLost event is fired.
local function CheckTargetRange(self: CharDetect, ...)
    if(not(self))then return end

    --Cycle through each char/target in the detected list
    for target, orgDist in self.DetectionList do

        --Get distance and line of sight
        local dist = (target:GetPivot().Position - self.NPC:GetPivot().Position).Magnitude
        local hasLOS, rayResult = CheckLOS(self, dist+3, target)

		--Check if this is the target the NPC is focused on
		if(self.Focus.Target and target == self.Focus.Target)then
		--if(self.FocusTarget and target == self.FocusTarget)then
			
			--Check if Focus target is within focus range
			if(dist >= self.Focus.Range.Min and dist <= self.Focus.Range.Max and hasLOS)then
				--if(not(hasLOS))then
				--	continue --Can't see this target, they are not "InFocus"
				--end
			--if(dist >= self.FocusRange.Min and dist <= self.FocusRange.Max)then
				--IN FOCUS RANGE!!
				--SHOULD WE REQUIRE LOS TO GRANT BEING InFocus?
				if(self.FDZ)then
					self.FDZ.Min.Color = Color3.fromRGB(255, 170, 0)
					self.FDZ.Max.Color = Color3.fromRGB(255, 170, 0)
				end
				
				if(self.FocusGraceTime)then self.FocusGraceTime = nil end --Clear the expiration timer
                if(self.FocusLostTime)then
                    --Since the focus lost time is set, the char had left focus range.
                    --They are now back within focus range so we will cancel the lost timer.
                    self.FocusLostTime = nil --Cancel the expiration timer

					--Fire off the Focus Gain event to signal this has happened.
					self._TargetFocusGainEvent:Fire(target, {Distance = dist, DetectionTime = tick(), LOS = hasLOS})
                    continue --Move to next char in detected list
                end
                
				--Focus was never lost, signal the char is still in focus range.
                self._TargetInFocusEvent:Fire(target, {Distance = dist, DetectionTime = tick(), LOS = hasLOS})
                continue --Move to next char in detected list
            end

			--Check if target is CLOSER than min focus range..
			if(dist < self.Focus.Range.Min and hasLOS)then
            --if(dist < self.FocusRange.Min)then
				--CLOSE FOCUS!!
				--if(not(hasLOS))then
				--	print("Can't see target...")
				--	continue --Next target check
				--end
				
				if(self.FDZ)then
					self.FDZ.Min.Color = Color3.fromRGB(85, 255, 0)
				end
                --If the close focus grace/delay timer is not set, then set it.
                if(not(self.FocusGraceTime))then self.FocusGraceTime = tick()+self.Focus.GraceDelay.Min end

                --Check if the grace/delay time is up
                if(self.FocusGraceTime <= tick() or not(self.Focus.GraceActive))then
                   self.FocusGraceTime = nil --Clear the expiration timer

					--The char has been in close focus past the grace/delay signal close focus has happened
					if(self.FDZ)then
						self.FDZ.Min.Color = Color3.fromRGB(85, 255, 0)
					end
                    self._TargetCloseFocusEvent:Fire(target, {Distance = dist, DetectionTime = tick(), LOS = hasLOS})
                end
            else
                --Target was not within focus range and was not in close focus.
                --This means the target is OUT of focus (too far away or noLOS)

                --If the lost focus grace/delay timer is not set, then set it.
                if(not(self.FocusLostTime))then self.FocusLostTime = tick()+self.Focus.GraceDelay.Max end

                --Check if the grace/delay time is up
                if(self.FocusLostTime <= tick())then
                    self.FocusLostTime = nil --Clear the expiration timer

                    --FOCUS LOST!
					--The target has been out of focus past the grace/delay, signal focus lost has happened
					print("Focus Lost")
					if(self.FDZ)then
						self.FDZ.Max.Color = Color3.fromRGB(0, 0, 0)
					end
					
					if(self.Focus.GraceActive)then
						--Only remove from detection list if grace is active
						self.DetectionList[target] = nil --Remove from detection list
					end
                    
					self._TargetFocusLostEvent:Fire(target, {Distance = dist, DetectionTime = tick(), LOS = hasLOS})
                else
                    --OUT OF FOCUS
					--The target is currently out of focus, but the grace/delay is not up so the char has not yet been lost
					print("Out of Focus", (self.FocusLostTime - tick()))
					
					if(self.FDZ)then
						self.FDZ.Max.Color = Color3.fromRGB(255, 0, 0)
					end
                    self._TargetFocusOutEvent:Fire(target, {Distance = dist, DetectionTime = tick(), LOS = hasLOS})
                end
            end
        else
            --Detected Target has gone out of range?
            if(dist >= self.Range.Max or not(hasLOS))then
                --At this point we have lost sight of this target too far away and/or no line of sight
                self.DetectionList[target] = nil
				--self._TargetLostEvent:Fire(target, {Distance = dist, DetectionTime = tick(), IsFocus = false})
				self._TargetLostEvent:Fire(target, {Distance = dist, DetectionTime = tick(), LOS = hasLOS})
            end
        end
    end--Loop
end

--Checks for characters inside the DZ and if found fires the CharDetected Event.
local function DetectTargets(self: CharDetect, ...)
    debug.profilebegin(self.NPC.Name.."DetectChar")
    local part = game.Workspace:GetPartsInPart(self.DZ, self.DZParams)
    if(not(part) or #part < 1)then
		--Nothing Detected
		--print("No Targets")
    else
        for i = 1, #part do
			if(not(self.Humanoid and self.NPC))then break end --Lost Self
			if(part[i] and part[i].Parent)then
				local target = part[i]--The main target that was detected
				
				--Is it part of a humanoid character? 
				--(Since char targets only detected by main children we only need to check parent for humanoid)
                local humanoid = part[i].Parent:FindFirstChildWhichIsA("Humanoid")
                if(humanoid)then
					if(humanoid == self.Humanoid)then continue end --Ignore self
					target = humanoid.Parent --Mark the main target as the Character Model
				end
				
				if(self.DetectionList[target])then continue end --Already found this one
				
				--Calc the distance for later reference
				local dist = (target:GetPivot().Position - self.NPC:GetPivot().Position).Magnitude
				self.DetectionList[target] = dist
                
				local hasLOS, details = CheckLOS(self, dist, target)
				self._TargetDetectedEvent:Fire(target, {Distance = dist, DetectionTime = tick(), LOS = hasLOS, LOSDetails = details})
            end
        end
    end
    debug.profileend()
end

--Heartbeat handler function
local function OnHeartbeat(self: CharDetect, ...)
	--If is enabled, then activate it.
    if(not(self.Enabled))then return end

    DetectTargets(self) --Find Chars/Targets within range
    CheckTargetRange(self) --Lose Chars/Targets out of range
end

--Initializes the DZ detection with player characters and NPCs
local function CompileTargetFilter(self: CharDetect)
    local charDir = Tool.CHAR_DIR
    local charList = charDir:GetChildren()
    for i, char in charList do
		if(char == self.NPC)then continue end--Skip Self
		self:AddCharTarget(char)
        --self.DZParams:AddToFilter(char) --Update Filter
    end

	local npcDir = Tool.NPC_DIR
    local npcList = npcDir:GetChildren()
    for i, npc in npcList do
		if(npc == self.NPC)then continue end--Skip Self
		self:AddCharTarget(npc)
        --self.DZParams:AddToFilter(npc) --Update Filter
    end

	self._Conns[#self._Conns+1] = charDir.ChildAdded:Connect(function(child)
		if(child == self.NPC)then return end--Skip Self
		self:AddCharTarget(child)
        --self.DZParams:AddToFilter(child) --Update Filter
    end)

	self._Conns[#self._Conns+1] = npcDir.ChildAdded:Connect(function(child)
		if(child == self.NPC)then return end--Skip Self
		self:AddCharTarget(child)
        --self.DZParams:AddToFilter(child) --Update Filter
    end)
end


--{ PUBLIC }--

--Creates new instance
function CD.new(...) return CD.New(...) end
function CD.New(NPC: Model, range: NumberRange?, focusRange: NumberRange?, gracePeriod: NumberRange?): CharDetect

	--Create new Ai instance
	local new: CharDetect = {}
	setmetatable(new, CD)
	
	new.NPC = NPC
    new.Humanoid = NPC:FindFirstChild("Humanoid")
	new.Enabled = false --Enable/Disable this CD

    --This range is used for character detection and loss.
    --Char is detected when <= min of the range
    --Char is lost when > Max of the range.
	new.Range = range or DEFAULT_RANGE
    local diameter = new.Range.Min * 2
	
	new.Focus = {
		Range = focusRange or DEFAULT_FOCUS_RANGE,
		Target = nil,
		GraceActive = false,
		GraceDelay = gracePeriod or NumberRange.new(1, 5),
	}
	
    --Focus range is the range used when a focus char is set
    --Typically this is used for move mode methods in cortex (Chase, Follow, Track)
    new.FocusRange = focusRange or DEFAULT_FOCUS_RANGE
    new.FocusTarget = nil --Holds the primary focus character/target (others can be detected, but this one has Priority)
	new.GraceActive = false
	new.FocusGraceDelay = gracePeriod or NumberRange.new(1, 5) --Default to 1 sec for both\
	
	new.FocusGraceTime = nil --Holds a timestamp of when the grace period is over. tick()+FocusGraceDelay.Min
	new.FocusLostTime = nil --Holds a timestamp of when the grace period is over. tick()+FocusGraceDelay.Max
	
    --new.CloseGracePeriod = 1
    --new.LostGracePeriod = gracePeriod or 10 --Grace period in seconds until Focus lost is enforced.
    

    --The DZ is used for initial character detections instead 
    --of constantly polling the distance of every possible character.
    new.DZ = AttachDZ(NPC)
    new.DZ.Size = Vector3.new(diameter, diameter, diameter)
    new.DetectionList = {} --{[CharObj] = dist}
    new.DZParams = OverlapParams.new()
    new.DZParams.FilterType = Enum.RaycastFilterType.Include --Only consider Instances in the filter
	
    --Events
    new._TargetDetectedEvent = Instance.new("BindableEvent")
    new.TargetDetected = new._TargetDetectedEvent.Event --Character: **Model**, Dist: **number**

    new._TargetLostEvent = Instance.new("BindableEvent")
    new.TargetLost = new._TargetLostEvent.Event --Character: **Model**, Dist: **number**

	
	--Target Focus Events
    new._TargetFocusLostEvent = Instance.new("BindableEvent")
    new.TargetFocusLost = new._TargetFocusLostEvent.Event
 
    new._TargetFocusGainEvent = Instance.new("BindableEvent")
    new.TargetFocusGain = new._TargetFocusGainEvent.Event

    new._TargetFocusOutEvent = Instance.new("BindableEvent")
    new.TargetFocusOut = new._TargetFocusOutEvent.Event

    new._TargetCloseFocusEvent = Instance.new("BindableEvent")
    new.TargetCloseFocus = new._TargetCloseFocusEvent.Event

    new._TargetInFocusEvent = Instance.new("BindableEvent")
    new.TargetInFocus = new._TargetInFocusEvent.Event

	--Connections
	new._Conns = {}

	--Connect to Heartbeat?
	--new._Conns[#new._Conns+1] = RunServ.Heartbeat:Connect(function(...)
    --    OnHeartbeat(new, ...)
	--end)
	
	--I believe this was switched over to Stepped to reduce load on Heartbeat
    new._Conns[#new._Conns+1] = RunServ.Stepped:Connect(function(...)
        OnHeartbeat(new, ...)
	end)

    CompileTargetFilter(new)

	--Return new instance
	return new
end


--{ METHODS }--

function CD.ShowRange(self: CharDetect, opt: ("All" | "Detect" | "Focus"))
	opt = if(opt)then opt else "All"
	
	local function ShowFDZ()
		local fdzMin = AttachDZ(self.NPC, "FDZMin", Color3.fromRGB(255, 170, 0))
		local diameter = self.Focus.Range.Min * 2
		fdzMin.Size = Vector3.new(diameter, diameter, diameter)
		fdzMin.Transparency = .5

		local fdzMax = AttachDZ(self.NPC, "FDZMax", Color3.fromRGB(255, 170, 0))
		local diameter = self.Focus.Range.Max * 2
		fdzMax.Size = Vector3.new(diameter, diameter, diameter)
		fdzMax.Transparency = .5

		self.FDZ = {
			Min = fdzMin,
			Max = fdzMax
		}
	end
	
	if(opt == "Detect")then
		self.DZ.Transparency = .5 --Just show the DZ
		if(self.FDZ)then
			self.FDZ.Min:Destroy()
			self.FDZ.Max:Destroy()	
		end
		
	elseif(opt == "Focus")then
		self.DZ.Transparency = 1
		ShowFDZ()
	else
		--Both
		self.DZ.Transparency = .5
		ShowFDZ()
	end
end

function CD.HideRange(self: CharDetect, opt: ("All" | "Detect" | "Focus"))
	self.DZ.Transparency = 1
	if(self.FDZ)then
		self.FDZ.Min:Destroy()
		self.FDZ.Max:Destroy()	
	end
end

--Range to use for general target detection
function CD.SetDetectionRange(self: CharDetect, range: NumberRange)
    if(not(self))then warn("Requires CharDetect Instance") return end
    if(not(range or typeof(range) ~= "NumberRange"))then warn("Range must be a NumberRange") return end
    self.Range = range
end

--Range to use for the Focus Target
function CD.SetFocusRange(self: CharDetect, range: NumberRange)
    if(not(self))then warn("Requires CharDetect Instance") return end
    if(not(range or typeof(range) ~= "NumberRange"))then warn("Range must be a NumberRange") return end
    self.Focus.Range = range
end

function CD.SetFocusGrace(self: CharDetect, range: NumberRange)
	if(not(self))then return end
	if(not(range) or typeof(range) ~= "NumberRange")then return end
	self.Focus.GraceDelay = range
end


--{ ADD/REMOVE TARGETS }--

--Adds a character target to detection (only main parts are added)
function CD.AddCharTarget(self: CharDetect, char: Model)
	if(not(char) or not(char:IsA("Model")))then return end
	--For character targets, we won't add the entire thing
	--This will force us to sift through all the characters decesdants
	--and make detection suck up more resources
	--Instead we will simply add the main children of the character (body parts)
	for i, part in char:GetChildren() do
		if(not(part:IsA("BasePart")))then continue end --Skip anything that isn't a basepart
		self.DZParams:AddToFilter(part)
	end
end

--Removes character target from detection
function CD.RemoveCharTarget(self: CharDetect, char: Model)
	if(not(char) or not(char:IsA("Model")))then return end
	
	local freshFilter = {}
	for i, instance in self.DZParams.FilterDescendantsInstances do
		if(instance:IsDescendantOf(char))then continue end --Skip this instance
		if(instance == char)then continue end--Skip the target to remove
		freshFilter[#freshFilter+1] = instance
	end
	self.DZParams.FilterDescendantsInstances = freshFilter
end

--Adds the specified target to detection
function CD.AddTarget(self: CharDetect, target: Instance)
	if(not(target))then return end
	if(target:IsA("Model"))then
		return self:AddCharTarget(target)
	end
	self.DZParams:AddToFilter(target)
end

--Removes the specified target from detection
function CD.RemoveTarget(self: CharDetect, target: Instance)
	if(not(target))then return end
	if(target:IsA("Model"))then
		return self:RemoveCharTarget(target)
	end
	
	local freshFilter = {}
	for i, instance in self.DZParams.FilterDescendantsInstances do
		if(instance == target)then continue end--Skip the target to remove
		freshFilter[#freshFilter+1] = instance
	end
	self.DZParams.FilterDescendantsInstances = freshFilter
	if(self.DetectionList[target])then
		local dist = self.DetectionList[target]
		self.DetectionList[target] = nil--Clear the target from detection
		self._TargetLostEvent:Fire(target, {Distance = dist, DetectionTime = tick()})
	end
end



--Destroys the Instance
function CD.Destroy(self: CharDetect)

	self.Enabled = false

	--Disconnect Any Listeners
	for i = 1, #self._Conns do
		if(self._Conns[i])then
			self._Conns[i]:Disconnect()
			self._Conns[i] = nil
		end
	end
    self._Conns = nil

    if(self.DZ)then self.DZ:Destroy() end
    self.DZ = nil

    if(self._TargetDetectedEvent)then self._TargetDetectedEvent:Destroy() end
    self._TargetDetectedEvent = nil
    self.CharDetected = nil

    if(self._TargetLostEvent)then self._TargetLostEvent:Destroy() end
    self._TargetLostEvent = nil
    self.CharLost = nil

	self.NPC = nil
	self.Range = nil
    self.Diameter = nil
    self.LostRange = nil
    self.DetectionList = nil
    self.FocusTarget = nil
    self.FocusRange = nil
    self.FocusLostRange = nil
    self.FocusGracePerio = nil
    self.FocusLostTime = nil
	self = nil
end


--( RETURN )--
return CD
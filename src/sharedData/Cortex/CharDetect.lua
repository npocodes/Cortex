--[[
    Character Detection Module
    Emskipo
    July 25 2023

    Detects characters within the provided parameters
--]]

--{ SERVICES }--

local RepStor = game:GetService("ReplicatedStorage")
local RunServ = game:GetService("RunService")
local Players = game:GetService("Players")


--{ REQUIRED }--

local Common = require(RepStor.SharedData.Common)
local Types = require(RepStor.SharedData.TypeDict)
local ToolEm = require(RepStor.SharedData.ToolEm)


--( MODULE )--

local CD = {}
CD.__index = CD


--{ TYPE DEF }--

type FrameRayResult = Types.FrameRayResult
type DetectionDetails = Types.DetectionDetails
type CharDetect = Types.CharDetect


--{ PRIVATE }--

local DZObject = Instance.new("Part")
DZObject.Name = "DZ"
DZObject.Shape = Enum.PartType.Ball
DZObject.Massless = true
DZObject.Anchored = false
DZObject.CanCollide = false
DZObject.CanQuery = true
DZObject.Size = Vector3.new(.5,.5,.5)
DZObject.BrickColor = BrickColor.Blue()
DZObject.Material = Enum.Material.ForceField
DZObject.Transparency = 1

local DEFAULT_RANGE = NumberRange.new(10, 10*2)
local DEFAULT_FOCUS_RANGE = NumberRange.new(DEFAULT_RANGE.Min*2, DEFAULT_RANGE.Max*2)
local DEFAULT_LOS_DISTANCE = 30

--local DZParams = OverlapParams.new()
--DZParams.FilterType = Enum.RaycastFilterType.Include


--{ FUNCTIONS }--

local function AttachDZ(NPC: Model): Part
    if(not(NPC))then return end

    --Use previously made DZ
    local dz = NPC:FindFirstChild("DZ")
    if(dz)then return dz end

    --Create a new DZ
    dz = DZObject:Clone()
    local weld = Instance.new("Weld")
    weld.Part0 = NPC.PrimaryPart
    weld.Part1 = dz
    dz.Parent = NPC
    weld.Enabled = true
    weld.Parent = dz

    return dz
end

local function CheckLOS(self: CharDetect, dist: number, target: Instance?): (boolean, FrameRayResult?)
	if(not(target))then warn("CheckLOS: Missing Target") return end
	local rayFrame = CFrame.lookAt(self.NPC:GetPivot().Position, target:GetPivot().Position)
	local params = RaycastParams.new()
	dist = dist or DEFAULT_LOS_DISTANCE
	params.RespectCanCollide = true
	params.IgnoreWater = true

    local rayResult: FrameRayResult?
	rayResult = ToolEm.FrameRay(rayFrame, dist, params)
    if(rayResult and rayResult.HitPart)then
        if(rayResult.HitPart == target or rayResult.HitPart.Parent == target)then
            return true, rayResult
        end
    end
	return false, nil
end

--Check if Focus Char is within focus range
local function InRange()
end


--Determines if the character detected has gone past the "LostRange" dist.  
--If so, the character is removed from the detected list and the CharLost event is fired.
local function CheckCharRange(self: CharDetect, ...)
    if(not(self))then return end

    --Cycle through each char in the detected char list
    for char, orgDist in self.DetectionList do

        --Get distance and line of sight
        local dist = (char:GetPivot().Position - self.NPC:GetPivot().Position).Magnitude
        local hasLOS, rayResult = CheckLOS(self, dist+3, char)

        --Check if this is the character the NPC is focused on
        if(self.FocusChar and char == self.FocusChar)then

            --Check if Focus Char is within focus range
            if(dist >= self.FocusRange.Min and dist <= self.FocusRange.Max)then
                --WE ARE WITHIN FOCUS RANGE!!
                if(self.FocusLostTime)then
                    --Since the focus lost time is set, the char had left focus range.
                    --They are now back within focus range so we will cancel the lost timer.
                    self.FocusLostTime = nil --Cancel the expiration timer

                    --Fire off the Focus Gain event to signal this has happened.
                    self._CharFocusGainEvent:Fire(char, {Distance = dist, DetectionTime = tick(), LOS = hasLOS})
                    continue --Move to next char in detected list
                end
                
                --Focus was never lost, signal the char is still in focus range.
                self._CharInFocusEvent:Fire(char, {Distance = dist, DetectionTime = tick(), LOS = hasLOS})
                continue --Move to next char in detected list
            end

            --Check if char is CLOSER than min focus range..
            if(dist < self.FocusRange.Min)then
                --CLOSE FOCUS!!
                --If the close focus grace/delay timer is not set, then set it.
                if(not(self.FocusGraceTime))then self.FocusGraceTime = tick()+self.FocusGraceDelay.Min end

                --Check if the grace/delay time is up
                if(self.FocusGraceTime <= tick())then
                    self.FocusGraceTime = nil --Clear the expiration timer

                    --The char has been in close focus past the grace/delay signal close focus has happened
                    self._CharCloseFocusEvent:Fire(char, {Distance = dist, DetectionTime = tick(), LOS = hasLOS})
                end
            else
                --Char was not within focus range and was not in close focus.
                --This means the char is OUT of focus (too far away)

                --If the lost focus grace/delay timer is not set, then set it.
                if(not(self.FocusLostTime))then self.FocusLostTime = tick()+self.FocusGraceDelay.Max end

                --Check if the grace/delay time is up
                if(self.FocusLostTime <= tick())then
                    self.FocusLostTime = nil --Clear the expiration timer

                    --FOCUS LOST!
                    --The char has been out of focus past the grace/delay, signal focus lost has happened
                    self.FocusChar = nil --Clear focus char
                    self.DetectionList[char] = nil --Remove from detection list
                    self._CharFocusLostEvent:Fire(char, {Distance = dist, DetectionTime = tick(), LOS = hasLOS})
                else
                    --OUT OF FOCUS
                    --The char is currently out of focus, but the grace/delay is not up so the char has not yet been lost
                    self._CharFocusOutEvent:Fire(char, {Distance = dist, DetectionTime = tick(), LOS = hasLOS})
                end
            end
        else
            --Detected Char has gone out of range
            if(dist >= self.Range.Max)then
                --At this point we have lost sight of this char
                self.DetectionList[char] = nil
                self._CharLostEvent:Fire(char, {Distance = dist, DetectionTime = tick(), IsFocus = false})
                --self._CharLostEvent:Fire(char, dist, tick(), false)
            end
        end
    end--Loop
end

--Determines if the character detected has gone past the "LostRange" dist.  
--If so, the character is removed from the detected list and the CharLost event is fired.
local function CheckCharRangeORG(self: CharDetect, ...)
    if(not(self))then return end
    for char, orgDist in self.DetectionList do
        local dist = (char:GetPivot().Position - self.NPC:GetPivot().Position).Magnitude
        local hasLOS, rayResult = CheckLOS(self, dist+3, char)

        if(self.FocusChar and char == self.FocusChar)then

            --Check if Focus Char is in range again
            if(self.FocusLostTime and dist <= self.FocusRange.Min)then
                self.FocusLostTime = nil --Cancel the expiration timer
                self._CharFocusGainEvent:Fire(char, {Distance = dist, DetectionTime = tick(), LOS = hasLOS})
                --self._CharFocusGainEvent:Fire(char, dist, tick(), hasLOS)
                continue --NextChar
            end

            --Check for the Grace Period Expiration
            if(self.FocusLostTime)then
                local elapsedTime = tick() - self.FocusLostTime
                if(elapsedTime > self.GracePeriod)then
                    --At this point we have completely lost the focused character
                    --Give up focus and move forward
                    self.DetectionList[char] = nil
                    self.FocusChar = nil
                    self._CharLostEvent:Fire(char, {Distance = dist, DetectionTime = tick(), IsFocus = true})
                    --self._CharLostEvent:Fire(char, dist, tick(), true)
                    continue --Next Char
                end
            end

            --Check if the Focus char has gone out of range
            if(dist >= self.FocusRange.Max)then
                --The Focus Char has gotten too far away...
                --Set the Grace Period timer and fire Focus lost event
                if(not(self.FocusLostTime))then
                    self.FocusLostTime = tick() --Start the Graceperiod timer
                    self._CharFocusLostEvent:Fire(char, {Distance = dist, DetectionTime = tick()})
                    --self._CharFocusLostEvent:Fire(char, dist, tick())
                    --continue
                end
            end
        else
            --Detected Char has gone out of range
            if(dist >= self.Range.Max)then
                --At this point we have lost sight of this char
                self.DetectionList[char] = nil
                self._CharLostEvent:Fire(char, {Distance = dist, DetectionTime = tick(), IsFocus = false})
                --self._CharLostEvent:Fire(char, dist, tick(), false)
            end
        end
    end--Loop
end

--Checks for characters inside the DZ and if found fires the CharDetected Event.
local function DetectCharacters(self: CharDetect, ...)
    debug.profilebegin(self.NPC.Name.."DetectChar")
    local part = game.Workspace:GetPartsInPart(self.DZ, self.DZParams)
    if(not(part) or #part < 1)then
        --Nothing Detected
    else
        for i = 1, #part do
            if(not(self.Humanoid and self.NPC))then break end
            if(part[i] and part[i].Parent)then
                local humanoid = part[i].Parent:FindFirstChildWhichIsA("Humanoid")
                if(not(humanoid))then continue end

                if(humanoid == self.Humanoid)then continue end --This is the NPC
                if(self.DetectionList[humanoid.Parent])then continue end --Already found this one

                local dist = (humanoid.Parent:GetPivot().Position - self.NPC:GetPivot().Position).Magnitude
                self.DetectionList[humanoid.Parent] = dist
                
                local hasLOS = CheckLOS(self, dist, humanoid.Parent)
                self._CharDetectedEvent:Fire(humanoid.Parent, {Distance = dist, DetectionTime = tick(), LOS = hasLOS})
            end
        end
    end
    debug.profileend()
end

--Heartbeat handler function
local function OnHeartbeat(self: CharDetect, ...)
	--If is enabled, then activate it.
    if(not(self.Enabled))then return end

    DetectCharacters(self) --Find Chars within range
    CheckCharRange(self) --Lose Chars out of range
end

local function CompileCharFilter(self: CharDetect)
    local charDir = Common.GetDir("Character")
    local charList = charDir:GetChildren()
    for i, char in charList do
        if(char == self.NPC)then continue end--Skip Self
        self.DZParams:AddToFilter(char) --Update Filter
    end

    local npcDir = Common.GetDir("NPC")
    local npcList = npcDir:GetChildren()
    for i, npc in npcList do
        if(npc == self.NPC)then continue end--Skip Self
        self.DZParams:AddToFilter(npc) --Update Filter
    end

    self._Conns[#self._Conns+1] = charDir.ChildAdded:Connect(function(child)
        self.DZParams:AddToFilter(child) --Update Filter
    end)

    self._Conns[#self._Conns+1] = npcDir.ChildAdded:Connect(function(child)
        self.DZParams:AddToFilter(child) --Update Filter
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

    --Focus range is the range used when a focus char is set
    --Typically this is used for move cycle methods in cortex (Chase, Follow, Track)
    new.FocusRange = focusRange or DEFAULT_FOCUS_RANGE
    new.FocusChar = nil --Holds the primary focus character
    new.FocusGraceDelay = gracePeriod or NumberRange.new(1) --Default to 1 sec for both
    new.FocusGraceTime = nil
    new.FocusLostTime = nil --Holds a timestamp of when the grace period is over.
    --new.CloseGracePeriod = 1
    --new.LostGracePeriod = gracePeriod or 10 --Grace period in seconds until Focus lost is enforced.
    

    --The DZ is used for initial character detections instead 
    --of constantly polling the distance of every possible character.
    new.DZ = AttachDZ(NPC)
    new.DZ.Size = Vector3.new(diameter, diameter, diameter)
    new.DetectionList = {} --{[CharObj] = dist}
    new.DZParams = OverlapParams.new()
    new.DZParams.FilterType = Enum.RaycastFilterType.Include

    --Events
    new._CharDetectedEvent = Instance.new("BindableEvent")
    new.CharDetected = new._CharDetectedEvent.Event --Character: **Model**, Dist: **number**

    new._CharLostEvent = Instance.new("BindableEvent")
    new.CharLost = new._CharLostEvent.Event --Character: **Model**, Dist: **number**


    new._CharFocusLostEvent = Instance.new("BindableEvent")
    new.CharFocusLost = new._CharFocusLostEvent.Event
 
    new._CharFocusGainEvent = Instance.new("BindableEvent")
    new.CharFocusGain = new._CharFocusGainEvent.Event

    new._CharFocusOutEvent = Instance.new("BindableEvent")
    new.CharFocusOut = new._CharFocusOutEvent.Event

    new._CharCloseFocusEvent = Instance.new("BindableEvent")
    new.CharCloseFocus = new._CharCloseFocusEvent.Event

    new._CharInFocusEvent = Instance.new("BindableEvent")
    new.CharInFocus = new._CharInFocusEvent.Event

	--Connections
	new._Conns = {}

	--Connect to Heartbeat?
	--new._Conns[#new._Conns+1] = RunServ.Heartbeat:Connect(function(...)
    --    OnHeartbeat(new, ...)
	--end)

    new._Conns[#new._Conns+1] = RunServ.Stepped:Connect(function(...)
        OnHeartbeat(new, ...)
	end)

    CompileCharFilter(new)

	--Return new instance
	return new
end


--{ METHODS }--

function CD.SetDetectionRange(self: CharDetect, range: NumberRange)
    if(not(self))then warn("Requires CharDetect Instance") return end
    if(not(range or typeof(range) ~= "NumberRange"))then warn("Range must be a NumberRange") return end
    self.Range = range
end

function CD.SetFocusRange(self: CharDetect, range: NumberRange)
    if(not(self))then warn("Requires CharDetect Instance") return end
    if(not(range or typeof(range) ~= "NumberRange"))then warn("Range must be a NumberRange") return end
    self.FocusRange = range
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

    if(self._CharDetectedEvent)then self._CharDetectedEvent:Destroy() end
    self._CharDetectedEvent = nil
    self.CharDetected = nil

    if(self._CharLostEvent)then self._CharLostEvent:Destroy() end
    self._CharLostEvent = nil
    self.CharLost = nil

	self.NPC = nil
	self.Range = nil
    self.Diameter = nil
    self.LostRange = nil
    self.DetectionList = nil
    self.FocusChar = nil
    self.FocusRange = nil
    self.FocusLostRange = nil
    self.FocusGracePerio = nil
    self.FocusLostTime = nil
	self = nil
end


--( RETURN )--

return CD
--[[

	CORTEX - Client-Side testing script

	This script handles running tests on client side usage
	of the Cortex NPC Framework

--]]

local RepStor = game:GetService("ReplicatedStorage")
local PlayerServ = game:GetService("Players")

local Cortex = require(RepStor.Cortex)
local Tool = require(RepStor.Cortex.Utility)

local CLIENT = PlayerServ.LocalPlayer


local function PlayerDetectionTest(playerChar: Model)
	warn("Starting PLAYER Detection Test")
	
	local CharDetect = require(RepStor.Cortex.CharDetect)
	local playerDetect = CharDetect.New(playerChar)
	
	playerDetect.Enabled = true
	playerDetect:ShowRange("Detect")
	playerDetect:AddTarget(game.Workspace.TestPart3)--Non Humanoid target
	
	playerDetect.TargetLost:Connect(function(target, details)
		playerDetect.DZ.Color = Color3.fromRGB(0, 0, 127)
	end)
	
	playerDetect.TargetDetected:Connect(function(target, details) --target, {Distance = dist, DetectionTime = tick(), LOS = hasLOS}
		print(target, "has been detected!", details)
		if(not(details.LOS))then
			print("Can't see target.")
			return
		end
		playerDetect.DZ.Color = Color3.fromRGB(85, 255, 0)
		if(target.Name == "TestPart3")then
			target.Color = Color3.fromRGB(85, 0, 0)
			playerDetect:RemoveTarget(game.Workspace.TestPart3)
			task.wait(3)
			target.Transparency = 1
		end
	end)
end

local function ChaseTest(NPC: Cortex)
	warn("Starting Chasing Test")
	local testCompleted = false
	
	local target = CLIENT.Character or CLIENT.CharacterAdded:Wait()

	NPC:EnableCharDZ()
	--NPC.CharDetect:SetDetectionRange(NumberRange.new(25, 50))
	NPC.CharDetect:SetFocusRange(NumberRange.new(7, 30))
	NPC.CharDetect:ShowRange("Focus")

	NPC.TargetCaught:Connect(function(target)
		warn("CAUGHT:", target.Name)
		NPC:StopChase()
		NPC.CharDetect:HideRange()
		testCompleted = true
	end)

	NPC.TargetEscaped:Connect(function()
		warn(target.Name, "Escaped!!")
		NPC:StopChase()
		NPC.CharDetect:HideRange()
		testCompleted = true
	end)
	
	NPC:SetSpeed()--Default Speed
	NPC:Chase(target)
	repeat task.wait() until testCompleted
end

local function FollowTest(NPC: Cortex)
	warn("Starting Follow Test")

	local target = CLIENT.Character or CLIENT.CharacterAdded:Wait()

	NPC:EnableCharDZ()
	--NPC.CharDetect:SetDetectionRange(NumberRange.new(25, 50))
	NPC.CharDetect:SetFocusRange(NumberRange.new(7, 30))
	NPC.CharDetect:ShowRange("Focus")
	
	NPC:SetSpeed() --Default Speed
	NPC:Follow(target)

	task.wait(15)
	NPC:StopFollow()
	NPC.CharDetect:HideRange()
end

local function TrackingTest(NPC: Cortex)
	warn("Starting Tracking Test")
	local trackingTestActive = true
	
	local target = CLIENT.Character or CLIENT.CharacterAdded:Wait()

	NPC:EnableCharDZ()
	
	NPC:SetSpeed()--Default Speed
	NPC.CharDetect:ShowRange("Detect")
	NPC:Track(target)

	NPC.CharDetect.TargetCloseFocus:Once(function()
		warn("Target Found!!")
		NPC:StopTrack()
		NPC.CharDetect:HideRange()
		trackingTestActive = false
	end)

	repeat task.wait() until not(trackingTestActive)
end

local function DetectionTest(NPC: Cortex)
	warn("Starting Detection Test")
	
	NPC:EnableCharDZ()
	NPC.CharDetect:ShowRange("Detect")
	NPC.CharDetect:AddTarget(game.Workspace.TestPart3)--Non Humanoid target
	NPC.CharDetect.TargetLost:Connect(function(target, details)
		NPC.CharDetect.DZ.Color = Color3.fromRGB(0, 0, 127)
	end)
	NPC.CharDetect.TargetDetected:Connect(function(target, details) --target, {Distance = dist, DetectionTime = tick(), LOS = hasLOS}
		print(target, "has been detected!", details)
		if(not(details.LOS))then
			print("Can't see target.")
			return
		end
		NPC.CharDetect.DZ.Color = Color3.fromRGB(85, 255, 0)
		if(target.Name == "TestPart3")then
			NPC.CharDetect:RemoveTarget(game.Workspace.TestPart3)
		end
	end)
end

local function PatrolTest(NPC: Cortex)
	warn("Starting Patrol Test")
	local patrolTestEnded = false

	NPC:SetPatrolPoints({
		game.Workspace.TestPart,
		game.Workspace.TestPart2
	})

	local patrolConn = nil
	patrolConn = NPC.PatrolCompleted:Connect(function(numRounds)
		print("NPC patrolled", numRounds, "times!")
		if(numRounds == 1)then
			NPC:PausePatrol()
			task.wait(5)
			NPC:ResumePatrol()
		elseif(numRounds == 3)then
			patrolConn:Disconnect()
			NPC:StopPatrol()
			warn("Ending Patrol Test")
			patrolTestEnded = true
		end
	end)
	NPC:SetSpeed(7)--Walk
	NPC:Patrol()
	repeat task.wait() until patrolTestEnded
end

local function TravelTest(NPC: Cortex)
	warn("Starting Travel Test")
	NPC.DestReached:Once(function()

	end)
	
	local destOpts = {
		game.Workspace.TestPart,
		game.Workspace.TestPart2
	}
	local dest = destOpts[math.random(#destOpts)]
	NPC:SetSpeed()--default speed
	NPC:TravelTo(dest)
	task.wait(3)

	NPC:PauseTravel()
	task.wait(5)

	NPC:ResumeTravel()
	task.wait(3)

	NPC:PauseTravel()
	task.wait(5)

	NPC:ResumeTravel()

	NPC.DestReached:Wait()
	warn("Travel Test Completed")
end


local function StartTest(NPC: Cortex)
	TravelTest(NPC)

	task.wait(3)
	PatrolTest(NPC)

	task.wait(3)
	TrackingTest(NPC)

	task.wait(3)
	FollowTest(NPC)

	task.wait(3)
	ChaseTest(NPC)

	warn("NPC COMPLETED TESTING!")
end



local function OnReady()
	
	-- CREATING CLIENT SIDE ONLY NPC
	print("SPAWNING NPC")
	local npcModel = RepStor:WaitForChild("NPC_Models").Rig:Clone()
	npcModel.Name = "ClientRig"
	npcModel.Humanoid.DisplayName = "ClientRig"
	
	local newNPC = Cortex.New(npcModel, {})
	local spawned = newNPC:SafeSpawn(game.Workspace:WaitForChild("SpawnLocation"))

	if(spawned)then
		warn("NPC SPAWNED!!")
		newNPC:Enable()
		newNPC.ShowPathway = true
		
		task.wait(5)
		
		StartTest(newNPC) --Full Testing
		--TravelTest(newNPC)
		--PatrolTest(newNPC)
		--DetectionTest(newNPC)
		--TrackingTest(newNPC)
		--FollowTest(newNPC)
		--ChaseTest(newNPC)
		
	else
		warn("Spawn location not safe. Did not spawn NPC")
	end
	--PlayerDetectionTest(CLIENT.Character)
end

Cortex.Ready:Connect(OnReady)
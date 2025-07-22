--[[

	CORTEX - Server-Side testing script

	This script handles running tests on server side usage
	of the Cortex NPC Framework

--]]

local RepStor = game:GetService("ReplicatedStorage")
local PlayerServ = game:GetService("Players")
local PhysicServ = game:GetService("PhysicsService")

local Cortex = require(RepStor.Cortex)
local Tool = require(RepStor.Cortex.Utility)
-- Cortex = require(RepStor.Cortex)
--local Tool = require(RepStor.Cortex.Utility)


type AgentParams = Cortex.AgentParams

local function PlayerDetectionTest()
	warn("Starting PLAYER Detection Test")
	
	local playerChar
	for i, player in PlayerServ:GetPlayers() do
		if(player.Name == "Emskipo")then
			playerChar = player
			break
		else
			playerChar = player
		end
	end
	PlayerServ.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(char)
			task.wait()
			playerChar = char
		end)
	end)
	repeat task.wait() until playerChar
	
	local CharDetect = require(RepStor.Cortex.CharDetect)
	local playerDetect = CharDetect.New(playerChar)

	playerDetect.Enabled = true
	playerDetect:ShowRange("Detect")
	playerDetect:AddTarget(game.Workspace.TestPart3)--Non Humanoid target

	playerDetect.TargetLost:Connect(function(target, details)
		playerDetect.DZ.Color = Color3.fromRGB(0, 0, 127)
	end)

	playerDetect.TargetDetected:Connect(function(target, details) --target, {Distance = dist, DetectionTime = tick(), LOS = hasLOS}
		if(not(details.LOS))then
			print(target, "is not in LineOfSight", details)
			return
		end
		print(target, "has been detected!", details)
		playerDetect.DZ.Color = Color3.fromRGB(85, 255, 0)
		if(target.Name == "TestPart3")then
			target.Color = Color3.fromRGB(85, 0, 0)
			playerDetect:RemoveTarget(game.Workspace.TestPart3)
			task.wait(3)
			target.Transparency = 1
		end
	end)
end

local function ComboPatrolChaseTest(NPC: Cortex)
	
	local patrolSpeed = 7
	local chaseSpeed = 16
	--Turn on the Char Detection Zone so we can detect players
	NPC:EnableCharDZ()
	
	--Set the Range for focus target (will be used for the chasing range)
	NPC.CharDetect:SetFocusRange(NumberRange.new(7, 30))
	--Min is how close means caught, Max means how far means escape
	
	NPC.CharDetect:SetFocusGrace(NumberRange.new(1, 5))
	--Min gives 1 sec grace for caught, Max Gives 5 secs for escaped
	
	--So if the target is less than 7 studs away for 2 secs, they are caught.
	--If the target is more than 30 studs away for 5 secs, they have escaped.
	
	NPC.CharDetect:ShowRange("Detect") --Reg detection only
	
	--Set the patrol points for the patrol
	NPC:SetPatrolPoints({
		game.Workspace.TestPart,
		game.Workspace.TestPart2
	})
	
	NPC.TargetCaught:Connect(function(target)
		warn("CAUGHT:", target.Name)
		NPC:StopChase()
		NPC.CharDetect:ShowRange("Detect") --Reg detection only
		NPC:SetSpeed(patrolSpeed)
		NPC:ResumePatrol()
	end)

	NPC.TargetEscaped:Connect(function(target)
		warn(target.Name, "Escaped!!")
		NPC:StopChase()
		NPC.CharDetect:ShowRange("Detect") --Reg detection only
		NPC:SetSpeed(patrolSpeed)
		NPC:ResumePatrol()
	end)
	
	NPC.CharDetect.TargetDetected:Connect(function(target)
		if(target.Name == "Emskipo")then
			NPC:PausePatrol()
			NPC.CharDetect:ShowRange("Focus") --Focus detection only
			NPC:SetSpeed(chaseSpeed)
			NPC:Chase(target)
		end
	end)
	
	--Start the Patrol
	NPC:SetSpeed(patrolSpeed)
	NPC:Patrol()
	
	task.wait(5)
	if(NPC:GetMoveMode() ~= "Chase")then
		local target
		local players = PlayerServ:GetPlayers()
		if(not(players))then
			repeat 
				task.wait()
				players = PlayerServ:GetPlayers()
			until players
		end
		target = players[math.random(#players)].Character
		
		NPC:PausePatrol()
		NPC.CharDetect:ShowRange("Focus") --Focus detection only
		NPC:SetSpeed(chaseSpeed)
		NPC:Chase(target)
		repeat
			--DASH MOVE
			task.wait(5)
			warn("DASHING")
			if(NPC:GetMoveMode() == "Chase")then
				NPC:SetSpeed(chaseSpeed+10)
				task.wait(2)
				if(NPC:GetMoveMode() == "Chase")then 
					warn("DASHING STOPPED")
					NPC:SetSpeed(chaseSpeed) 
				end
			end
		until NPC:GetMoveMode() ~= "Chase"
	else
		print(NPC:GetMoveMode())
	end
end

local function ChaseTest(NPC: Cortex)
	warn("Starting Chasing Test")
	local testCompleted = false
	
	local target
	local players = PlayerServ:GetPlayers()
	if(not(players))then
		repeat 
			task.wait()
			players = PlayerServ:GetPlayers()
		until players
	end
	target = players[math.random(#players)].Character

	NPC:EnableCharDZ()
	--NPC.CharDetect:SetDetectionRange(NumberRange.new(25, 50))
	NPC.CharDetect:SetFocusRange(NumberRange.new(7, 30))
	NPC.CharDetect:ShowRange("Focus")

	NPC.TargetCaught:Connect(function(target)
		warn("CAUGHT:", target.Name)

		NPC:BubbleChat("Haha! Caught you "..target.Name.."!!", 3)
		NPC:Emote("laugh")

		NPC:StopChase()
		NPC.CharDetect:HideRange()
		testCompleted = true
	end)

	NPC.TargetEscaped:Connect(function()
		warn(target.Name, "Escaped!!")

		NPC:BubbleChat("You can't run forever!"..target.Name.."!!", 3)
		NPC:Emote("toolslash")--yell?! lol

		NPC:StopChase()
		NPC.CharDetect:HideRange()
		testCompleted = true
	end)
	
	NPC:BubbleChat("I'm going to get you "..target.Name.."!!", 3)
	NPC:Emote("point")

	NPC:SetSpeed()--Default Speed
	NPC:Chase(target)
	repeat task.wait() until testCompleted
end

local function FollowTest(NPC: Cortex)
	warn("Starting Follow Test")

	local target
	local players = PlayerServ:GetPlayers()
	if(not(players))then
		repeat 
			task.wait()
			players = PlayerServ:GetPlayers()
		until players
	end
	target = players[math.random(#players)].Character

	NPC:EnableCharDZ()
	--NPC.CharDetect:SetDetectionRange(NumberRange.new(25, 50))
	NPC.CharDetect:SetFocusRange(NumberRange.new(7, 30))
	NPC.CharDetect:ShowRange("Focus")
	
	NPC:SetSpeed()--Default Speed
	NPC:Follow(target)
	
	task.wait(15)
	NPC:StopFollow()
	NPC.CharDetect:HideRange()
end

local function TrackingTest(NPC: Cortex)
	warn("Starting Tracking Test")
	local trackingTestActive = true
	
	local target
	local players = PlayerServ:GetPlayers()
	if(not(players))then
		repeat 
			task.wait()
			players = PlayerServ:GetPlayers()
		until players
	end
	target = players[math.random(#players)].Character

	
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
			target.Color = Color3.fromRGB(255, 0, 0)
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
	NPC:SetSpeed()--Default Speed
	NPC:TravelTo(game.Workspace.TestPart)
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
	
	--task.wait(3)
	--PatrolTest(NPC)
	
	--task.wait(3)
	--TrackingTest(NPC)
	
	--task.wait(3)
	--FollowTest(NPC)
	
	task.wait(3)
	ChaseTest(NPC)
	
	warn("NPC COMPLETED TESTING!")
end

local function OnReady()

	print("SPAWNING NPC")
	local npcModel = RepStor:WaitForChild("NPC_Models").Rig:Clone()
	npcModel.Name = "ServerRig"
	npcModel.Humanoid.DisplayName = "ServerRig"
	
	local newNPC = Cortex.New(npcModel, {})
	local spawned = newNPC:SafeSpawn(game.Workspace.SpawnLocation)

	if(spawned)then
		
		warn("NPC SPAWNED!!")
		newNPC:Enable()
		newNPC.ShowPathway = true
		--newNPC:SetSpeed(10)
		
		StartTest(newNPC) --Full Testing
		--TravelTest(newNPC)
		--PatrolTest(newNPC)
		--DetectionTest(newNPC)
		--TrackingTest(newNPC)
		--FollowTest(newNPC)
		--ChaseTest(newNPC)
		--ComboPatrolChaseTest(newNPC)

	else
		warn("Spawn location not safe. Did not spawn NPC")
	end
	
	--PlayerDetectionTest()
end

Cortex.Ready:Connect(OnReady)
Cortex.Initialize()
Cortex.Run()
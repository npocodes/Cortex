local RepStor = game:GetService("ReplicatedStorage")
local PlayerServ = game:GetService("Players")
local Cortex = require(RepStor.Cortex)

local CLIENT = PlayerServ.LocalPlayer

if(script.Parent == CLIENT.Character)then
	task.wait()
	script.Parent = CLIENT.PlayerScripts
end

Cortex.Initialize()
Cortex.Run()
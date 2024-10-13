--[[
    NPC REACTIONS
    Emskipo
    Sept 16 2023

	Contains Reaction Methods for NPCs
--]]

--{ SERVICES }--

local PlayerServ = game:GetService("Players")
local RepStor = game:GetService("ReplicatedStorage")
local ScriptServ = game:GetService("ServerScriptService")
local RunServ = game:GetService("RunService")


--{ MODULES }--

local Types
local ToolEm
local Archive


--( MODULE )--

local React = {}
React.__index = React
React.IsReady = false

local _ReadyEvent = Instance.new("BindableEvent")
React.Ready = _ReadyEvent.Event

--{ TYPE DEF }--


type Ai = Types.Ai
type React = Types.React


--{ PRIVATE }--


--Reactions to meet ups
local MeetUpReaction = {}
MeetUpReaction.Default = function(self: Ai, char: Model)
    if(not(self.NPC and char))then return end
    
	--Stop and wave/look to this character
    --self.Cortex:CancelMove()
    self.Cortex:PauseMove()

	self.Cortex:TurnToward(char:GetPivot())

	self.NPC.Humanoid:SetAttribute("Emote", "/emote wave")
    --self.NPC.Humanoid:PlayEmote() --THIS IS FOR CUSTOM MARKETPLACE EMOTES (NOT DEFAULT EMOTES!!)

    local player = PlayerServ:GetPlayerFromCharacter(char)
    local name = if(player)then player.DisplayName else char.Name
	self.Cortex:SetStatus("What's up "..name.."!", 2)

    task.wait(2)
    if(not(self.Cortex))then return end
    self.Cortex:ResumeMove()
    --self:MoveTo(self.CurrentDest)
end

MeetUpReaction.Scared = function(self: Ai, char: Model)
    self.Cortex:SetStatus("Ahhh!", 3)
    self.NPC.Humanoid.WalkSpeed = 16
    local scaredConn = nil
    scaredConn = self.Cortex.CharDetect.CharLost:Connect(function(charLost: Model, details)
        if(charLost == char)then
            scaredConn:Disconnect()
            self.NPC.Humanoid.WalkSpeed = self.NPC.Humanoid:GetAttribute("DefaultSpeed")
        end
    end)
end

local AttackedReaction = {}
AttackedReaction.Default = function(self: Ai, attackerId: (number | string))
    if(not(self.NPC))then return end

    local player = nil
    local playerId = tonumber(attackerId)
    if(playerId)then
        player = PlayerServ:GetPlayerByUserId(playerId)
    end

    if(player)then
        attackerId = player.Name
        self.NPC.Humanoid.WalkSpeed = 16
        local scaredConn = nil
        scaredConn = self.Cortex.CharDetect.CharLost:Connect(function(charLost: Model, details)
            if(charLost == player.Character)then
                scaredConn:Disconnect()
                self.NPC.Humanoid.WalkSpeed = self.NPC.Humanoid:GetAttribute("DefaultSpeed")
            end
        end)
    end
    self.Cortex:SetStatus("OUCH! "..attackerId, 2)
end


--{ PUBLIC }--

--Intialize and Run do not occur within SharedData directory!!
function React.Initialize()
    Types = require(RepStor.SharedData.TypeDict)
    ToolEm = require(RepStor.SharedData.ToolEm)
    ToolEm.Echo("Loading: React")

    if(RunServ:IsServer())then
        Archive = require(ScriptServ.Server.Archive)
    end
end

function React.Run()
	ToolEm.Echo("Running: React")
end

--Creates new instance
function React.new(...) return React.New(...) end
function React.New(Ai: Ai): React

	--Create new React instance
	local new = {}
	setmetatable(new, React)

	--Connections
	new._Conns = {}

	--Return new instance
	return new
end


--{ METHODS }--

--React to meeting up with another character
function React.MeetUp(self: Ai, char: Model, extra: any?)
    if(extra and extra == "Crime")then
        MeetUpReaction.Scared(self, char)
        return
    end

    local chance = math.random(3)
    if(chance ~= 3)then return end
    MeetUpReaction.Default(self, char)
end

function React.Attacked(self: Ai, ownerId: (number | string))
    --local chance = math.random(3)
    --if(chance ~= 3)then return end
    AttackedReaction.Default(self, ownerId)
end


--( RETURN )--
return React
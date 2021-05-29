local require = GLOBAL.require
local math = GLOBAL.math
local TUNING = GLOBAL.TUNING
local FindEntity = GLOBAL.FindEntity
local SpringCombatMod = GLOBAL.SpringCombatMod
local GetClosestInstWithTag = GLOBAL.GetClosestInstWithTag
local WhileNode = GLOBAL.WhileNode
local BehaviourNode = GLOBAL.BehaviourNode
local GetTime = GLOBAL.GetTime
local FindNearbyOcean = GLOBAL.FindNearbyOcean
local FindNearbyLand = GLOBAL.FindNearbyLand
local FindSwimmableOffset = GLOBAL.FindSwimmableOffset
local FindWalkableOffset = GLOBAL.FindWalkableOffset

local smarter_merm = GetModConfigData('ENABLE_SMARTER_MERM')

local function FindEnemyFn(guy, inst)
	if guy.components.combat and
		guy.components.combat:HasTarget() and
		guy.components.combat.target:HasTag('merm')
	then
		return true
	end

	if guy:HasTag('pig') then
		return true
	end

	return false
end

local function CanShareTarget(dude, inst)
	if inst.components.homeseeker and dude.components.homeseeker
		and inst.components.homeseeker.home and dude.components.homeseeker.home
		and inst.components.homeseeker.home == dude.components.homeseeker.home
	then
		return true
	end

	if dude:HasTag('merm') and not dude:HasTag('player') and not
		(dude.components.follower and dude.components.follower.leader and dude.components.follower.leader:HasTag("player"))
	then
		return true
	end

	return false
end

local function OnNewTarget(inst, data)
	local target = data and data.target

	if not target then
		return
	end

	local share_target_dist = inst:HasTag("mermguard") and TUNING.MERM_GUARD_SHARE_TARGET_DIST or TUNING.MERM_SHARE_TARGET_DIST
  local max_target_shares = inst:HasTag("mermguard") and TUNING.MERM_GUARD_MAX_TARGET_SHARES or TUNING.MERM_MAX_TARGET_SHARES
  inst.components.combat:ShareTarget(target, share_target_dist,
  	function(dude)
  		return CanShareTarget(dude, inst)
	  end,
	  max_target_shares)
end

local function SmarterMerm(prefab)
  if not GLOBAL.TheWorld.ismastersim then
    return
  end

  if prefab.components.combat then
  	local oldtargetfn = prefab.components.combat.targetfn
  	local newtargetfn = function(inst)
  		local target = oldtargetfn and oldtargetfn(inst) or nil

  		if target == nil then
  			target = FindEntity(
  				inst,
  				SpringCombatMod(TUNING.MERM_TARGET_DIST),
  				FindEnemyFn,
  				{ "_combat", "_health" },
					{ "merm", "INLIMBO" }
				)
  		end

  		return target
  	end

  	prefab.components.combat.targetfn = newtargetfn
  	prefab:ListenForEvent("newcombattarget", OnNewTarget)
  end
end

if smarter_merm then
	AddPrefabPostInit("merm", SmarterMerm)
	AddPrefabPostInit("mermguard", SmarterMerm)
end

require "behaviours/runaway"
local RunAway = GLOBAL.RunAway

local dodgechance = GetModConfigData('MERM_EPIC_DODGE_CHANCE')

local function DumpBT(bnode, indent)
	local s = ""
	for i=1,indent do
		s = s.."|   "
	end
	s = s..bnode.name
	print(s)
	if bnode.children then
		for i,childnode in ipairs(bnode.children) do
			DumpBT(childnode, indent+1)
		end
	end
end

local AVOID_EPIC_DIST = TUNING.DEERCLOPS_AOE_RANGE + 5
local STOP_AVOID_EPIC_DIST = TUNING.DEERCLOPS_AOE_RANGE + 5

local function FindEpicEnemy(inst)
	return GetClosestInstWithTag({"epic"}, inst, AVOID_EPIC_DIST)
end

local estimated_epic_atk_time = 1

local function IsEpicAttackComing(inst)
	local epic = FindEpicEnemy(inst)
	if epic and epic.components.combat
		and epic.components.combat.areahitdamagepercent ~= nil
		and epic.components.combat.areahitdamagepercent > 0 then
			if epic.components.combat.laststartattacktime ~= nil
				and epic.components.combat.laststartattacktime + estimated_epic_atk_time >= GetTime() then
					return true
			end

			if epic.components.combat:GetCooldown() <= 1 then
				return true
			end
	end

	return false
end

local function BetterMermBrain(brain)
	local should_dodge = nil

	local avoidnode = WhileNode(
		function()
			local coming = IsEpicAttackComing(brain.inst)

			if not coming then
				-- print("NOT COMING, RESET NIL")
				should_dodge = nil
				return coming
			end

			-- First time epic attack coming in a sequence
			if should_dodge == nil then
				should_dodge = math.random() <= dodgechance
				-- print("COMING FIRST TIME, ", should_dodge)
			end

			-- print("COMING SEQUENCE ", should_dodge)

			return coming and should_dodge
		end,
		"AvoidEpicAttack",
		RunAway(
			brain.inst,
			function() return FindEpicEnemy(brain.inst) end,
			AVOID_EPIC_DIST, STOP_AVOID_EPIC_DIST
		)
	)

	local atkindex = nil
	for i, node in ipairs(brain.bt.root.children) do
		if node.name == "Parallel" and node.children[1].name == "AttackMomentarily" then
			atkindex = i
		end
	end

	if atkindex == nil then
		print("Cannot find attack node")
		return
	end

	table.insert(brain.bt.root.children, atkindex, avoidnode)
	-- DumpBT(brain.bt.root, 0)
end

if smarter_merm then
	AddBrainPostInit('mermbrain', BetterMermBrain)
	AddBrainPostInit('mermguardbrain', BetterMermBrain)
end

local easing = require('easing')

local function WurtSanityFn(inst)
	-- Negate moisture sanity loss + a bit gain
	local moisturedelta = -easing.inSine(
		inst.components.moisture:GetMoisture(),
		0,
		TUNING.MOISTURE_SANITY_PENALTY_MAX,
		inst.components.moisture:GetMaxMoisture()
	) + easing.inSine(
		inst.components.moisture:GetMoisture(),
		0,
		TUNING.SANITYAURA_SMALL_TINY,
		inst.components.moisture:GetMaxMoisture()
	)

	local overheatdelta = 0
	if inst.components.temperature:IsOverheating() then
		overheatdelta = -TUNING.SANITYAURA_MED
	end

	return moisturedelta + overheatdelta
end

local function WurtMod(prefab)
	if not GLOBAL.TheWorld.ismastersim then
    	return
  	end

	prefab.components.sanity.custom_rate_fn = WurtSanityFn
	prefab.components.temperature:SetOverheatHurtRate(prefab.components.temperature.hurtrate * 1.25)
	prefab.components.temperature.maxmoisturepenalty = 0
end

local enable = GetModConfigData('ENABLE_WURT_MOD')
if enable then
	AddPrefabPostInit('wurt', WurtMod)
end

local Widget = require "widgets/widget"
local Text = require "widgets/text"
local Image = require "widgets/image"
local NUMBERFONT = GLOBAL.NUMBERFONT
local ANCHOR_MIDDLE = GLOBAL.ANCHOR_MIDDLE

local MermKingStatus = Class(Widget, function(self, owner, name)
	Widget._ctor(self, "MermKingStatus")
    self.owner = owner
	self.name = name

	self:SetScale(1, 1, 1)

	self.hunger_num = self:AddChild(Text(NUMBERFONT, 25))
	self.hunger_num:SetHAlign(ANCHOR_MIDDLE)
	self.hunger_num:SetPosition(3, 10, 0)

	self.health_num = self:AddChild(Text(NUMBERFONT, 25))
	self.health_num:SetHAlign(ANCHOR_MIDDLE)
	self.health_num:SetPosition(3, -10, 0)
end)

local function CalcPosition(status)
  -- Assume that brain always stays in the middle, stomach on the left and heart on the right
  local brainPos = status.brain:GetPosition()
  local stomachPos = status.stomach:GetPosition()
  local heartPos = status.heart:GetPosition()

  local pos = GLOBAL.Vector3(2 * stomachPos.x - brainPos.x, brainPos.y, stomachPos.z)
  return pos
end

local function GetStatusString(value, alive)
	if not alive then
		return 'N/A'
	end

	return GLOBAL.tostring(value)
end

local function StatusPostConstruct(self)
	if self.owner.prefab ~= 'wurt' then
		return
	end

	self.mermking_status = self:AddChild(MermKingStatus(self.owner, 'mermking_status'))

	self.owner.UpdateMermkingStatus = function() 
		local pos = CalcPosition(self)
		self.mermking_status:SetPosition(pos:Get())
		self.mermking_status:SetScale(self.brain:GetLooseScale())

		local hunger = self.owner.mermking_hunger and self.owner.mermking_hunger:value() or 0
		local health = self.owner.mermking_health and self.owner.mermking_health:value() or 0
		local alive = self.owner.mermking_alive and self.owner.mermking_alive:value() or false

		self.mermking_status.hunger_num:SetString(GetStatusString(hunger, alive))
		self.mermking_status.health_num:SetString(GetStatusString(health, alive))
	end
end

AddClassPostConstruct("widgets/statusdisplays", StatusPostConstruct)

local function OnKingHungerDelta(inst)
	if GLOBAL.TheWorld.components.mermkingmanager and GLOBAL.TheWorld.components.mermkingmanager:HasKing() then
		local king = GLOBAL.TheWorld.components.mermkingmanager.king
		inst.mermking_hunger:set(king.components.hunger.current)
	end
end

local function OnKingHealthDelta(inst)
	if GLOBAL.TheWorld.components.mermkingmanager and GLOBAL.TheWorld.components.mermkingmanager:HasKing() then
		local king = GLOBAL.TheWorld.components.mermkingmanager.king
		inst.mermking_health:set(king.components.health.currenthealth)
	end
end

local function OnKingCreated(inst)
	-- kick off
	OnKingHungerDelta(inst)
	OnKingHealthDelta(inst)

	inst:ListenForEvent('hungerdelta', inst._onkinghungerdelta, GLOBAL.TheWorld.components.mermkingmanager.king)
	inst:ListenForEvent('healthdelta', inst._onkinghealthdelta, GLOBAL.TheWorld.components.mermkingmanager.king)
	inst.mermking_alive:set(true)

	inst:ListenForEvent(
		'onremove', 
		function() 
			inst:RemoveEventCallback('hungerdelta', inst._onkinghungerdelta, GLOBAL.TheWorld.components.mermkingmanager.king)
			inst:RemoveEventCallback('healthdelta', inst._onkinghealthdelta, GLOBAL.TheWorld.components.mermkingmanager.king)
		end, 
		GLOBAL.TheWorld.components.mermkingmanager.king
	)
end

local function OnKingDestroyed(inst)
	inst.mermking_alive:set(false)
end

local function onmermkingstatusdirty()
	if GLOBAL.ThePlayer and GLOBAL.ThePlayer.UpdateMermkingStatus then
		GLOBAL.ThePlayer.UpdateMermkingStatus()
	end
end

local function PlayerPostConstruct(inst)
	if inst.prefab ~= 'wurt' then
		return
	end

	inst.mermking_hunger = GLOBAL.net_ushortint(inst.GUID, 'mermking_status.hunger', 'mermkingstatusdirty')
	inst.mermking_health = GLOBAL.net_ushortint(inst.GUID, 'mermking_status.health', 'mermkingstatusdirty')
	inst.mermking_alive = GLOBAL.net_bool(inst.GUID, 'mermking_status.alive', 'mermkingstatusdirty')

	inst.mermking_alive:set(true)

	if GLOBAL.TheWorld.ismastersim then
		inst._onkinghungerdelta = function() OnKingHungerDelta(inst) end
		inst._onkinghealthdelta = function() OnKingHealthDelta(inst) end

		inst:ListenForEvent('onmermkingcreated', function() OnKingCreated(inst) end, GLOBAL.TheWorld)
		inst:ListenForEvent('onmermkingdestroyed', function() OnKingDestroyed(inst) end, GLOBAL.TheWorld)
		inst:DoTaskInTime(0, function()
			if GLOBAL.TheWorld.components.mermkingmanager and GLOBAL.TheWorld.components.mermkingmanager:HasKing() then
				OnKingCreated(inst)
			else
				OnKingDestroyed(inst)
			end
		end)
	end

	if not GLOBAL.TheNet:IsDedicated() then
		inst:ListenForEvent("mermkingstatusdirty", onmermkingstatusdirty)
	end
end

AddPlayerPostInit(PlayerPostConstruct)

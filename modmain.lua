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

AddPrefabPostInit("merm", SmarterMerm)
AddPrefabPostInit("mermguard", SmarterMerm)

require "behaviours/runaway"
local RunAway = GLOBAL.RunAway

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
	local avoidnode = WhileNode(
		function()
			return IsEpicAttackComing(brain.inst)
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

AddBrainPostInit('mermbrain', BetterMermBrain)
AddBrainPostInit('mermguardbrain', BetterMermBrain)

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

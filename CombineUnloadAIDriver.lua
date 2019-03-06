--[[
This file is part of Courseplay (https://github.com/Courseplay/courseplay)
Copyright (C) 2018 Peter Vajko

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

---@class CombineUnloadAIDriver : AIDriver
CombineUnloadAIDriver = CpObject(AIDriver)

CombineUnloadAIDriver.myStates = {
	UNLOADING = {},
	ON_FIELD = {},
	LOOKING_FOR_COMBINE = {},
	FIND_THE_WAY_TO_COMBINE = {},
	DRIVE_WAY_ON_FIELD = {},
	DRIVE_BESIDE_COMBINE = {},
	FIND_THE_WAY_TO_UNLOADCOURSE = {}
}

--- Constructor
function CombineUnloadAIDriver:init(vehicle)
	AIDriver.init(self, vehicle)
	self:initStates(CombineUnloadAIDriver.myStates)
	self.mode = courseplay.MODE_COMBI
	self.state = self.states.UNLOADING
	self:switchFieldState(self.states.LOOKING_FOR_COMBINE)
end

function CombineUnloadAIDriver:start(ix)
	self.vehicle:setCruiseControlMaxSpeed(self.vehicle:getSpeedLimit() or math.huge)
	self:beforeStart()
	AIDriver.start(self, ix)
	self.state = self.states.UNLOADING
	-- due to lack of understanding what exactly isLoaded means and where is it set to false in mode 1,
	-- we just set it to false here so load_tippers() will actually attempt to load the tippers...
	courseplay:setIsLoaded(self.vehicle, false);
end

function CombineUnloadAIDriver:initStates(states)
	for key, state in pairs(states) do
		self.states[key] = state
	end
end

function CombineUnloadAIDriver:isAlignmentCourseNeeded(ix)
	-- never use alignment course for grain transport mode
	return false
end

function CombineUnloadAIDriver:drive(dt)
	self:updateInfoText()
	courseplay:updateFillLevelsAndCapacities(self.vehicle)
	if self.state == self.states.UNLOADING then
		-- make sure we apply the unload offset when needed
		self:updateOffset()
		-- update current waypoint/goal point
		self.ppc:update()
		self:driveUnload(dt)
	elseif self.state == self.states.ON_FIELD then
		self:driveOnField(dt)
	end
end

function CombineUnloadAIDriver:driveOnField(dt)
	local allowedToDrive = false
	local moveForwards = true
	if self.fieldState == self.states.LOOKING_FOR_COMBINE then
		self:stop()
		self.combineToUnload = self:lookForCombines()
		if self.combineToUnload ~= nil then
			self:switchFieldState(self.states.FIND_THE_WAY_TO_COMBINE)
		end
	else
		self:stop()
	
	
	end	
end

function AIDriver:dismiss()
	
	AIDriver.dismiss(self)
end

function CombineUnloadAIDriver:stop()
	local gx, _, gz = self.ppc:getGoalPointLocalPosition()	
	self:driveVehicleToLocalPosition(16, false, true, gx, gz, 0)
end



function CombineUnloadAIDriver:lookForCombines()
	return g_combineManager:giveMeACombineToUnload(self.vehicle)
end


function CombineUnloadAIDriver:getIsCombineTurning(combine)
	local driveableComponent = (combine.getAttacherVehicle and combine:getAttacherVehicle()) or combine
	local aiTurn = driveableComponent.spec_aiVehicle and driveableComponent.spec_aiVehicle.isTurning	
	local cpTurn = driveableComponent.cp.turnStage > 0
	return  aiTurn or cpTurn
end

function CombineUnloadAIDriver:switchFieldState(newState)
	self.fieldState = newState
end
---------------------------------------------------------------------------------------------------------------------------------------------
-- unloading my Tipper into a trigger or at a unload point 


function CombineUnloadAIDriver:driveUnload(dt)
	-- should we give up control so some other code can drive?
	local giveUpControl = false
	-- should we keep driving?
	local allowedToDrive = self:checkLastWaypoint()
	
	if self.vehicle.cp.totalFillLevel ~= nil
		and self.vehicle.cp.tipRefOffset ~= nil
		and self.vehicle.cp.workToolAttached then
		local lx, lz = self:getDirectionToGoalPoint()
		self:searchForTipTriggers(lx, lz)
		allowedToDrive, giveUpControl = self:onUnLoadCourse(allowedToDrive, dt)
	else
		self:debug('Safety check failed')
	end

	-- TODO: clean up the self.allowedToDrives above and use a local copy
	if self.state == self.states.STOPPED or not allowedToDrive then
		self:hold()
	end

	if giveUpControl then
		-- unload_tippers does the driving
		return
	else
		-- collision detection
		self:detectCollision(dt)
		-- we drive the course as usual
		self:driveCourse(dt)
	end
	self:resetSpeed()
end


function CombineUnloadAIDriver:onWaypointChange(newIx)
	self:debug('On waypoint change %d', newIx)
	AIDriver.onWaypointChange(self, newIx)
	if self.course:isLastWaypointIx(newIx) then
		self:debug('Reaching last waypoint')
	end
	-- Close cover after leaving the silo, assuming the silo is at waypoint 1
	if not self:hasTipTrigger() and self.state == self.states.UNLOADING then
		courseplay:openCloseCover(self.vehicle, courseplay.SHOW_COVERS)
	end
	
end

function CombineUnloadAIDriver:checkLastWaypoint()
	local allowedToDrive = true
	if self.ppc:reachedLastWaypoint() then
		courseplay:openCloseCover(self.vehicle, not courseplay.SHOW_COVERS)
		self:changeToField()
	end
	return allowedToDrive
end


function CombineUnloadAIDriver:isAlignmentCourseNeeded(ix)
	-- never use alignment course for grain transport mode
	return false
end


function CombineUnloadAIDriver:changeToUnload()
	self.state = self.states.UNLOADING
end

function CombineUnloadAIDriver:changeToField()
	self.state = self.states.ON_FIELD
end



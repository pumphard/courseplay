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
	FOLLOW_PIPE = {},
	FIND_THE_WAY_TO_UNLOADCOURSE = {}
}

--- Constructor
function CombineUnloadAIDriver:init(vehicle)
	courseplay.debugVehicle(11,vehicle,'CombineUnloadAIDriver:init()')
	AIDriver.init(self, vehicle)
	self:initStates(CombineUnloadAIDriver.myStates)
	self.mode = courseplay.MODE_COMBI
	self.state = self.states.UNLOADING
	self:switchFieldState(self.states.LOOKING_FOR_COMBINE)
end

function CombineUnloadAIDriver:start(ix)
	self.vehicle:setCruiseControlMaxSpeed(self.vehicle:getSpeedLimit() or math.huge)
	self:beforeStart()
	if self.state == self.states.UNLOADING then
		AIDriver.start(self, ix)
	end
	--if AIDriver changed my state and I'm not on the field, change state to Unloading
	if self.state ~= self.states.UNLOADING and self.state ~= self.states.ON_FIELD then
		self.state = self.states.UNLOADING
	end
	self.distanceToObject = 100
end

function CombineUnloadAIDriver:setHudContent(vehicle)
	courseplay.hud:setAIDriverContent(vehicle)
	courseplay.hud:setCombineUnloadAIDriverContent(vehicle)
end

function CombineUnloadAIDriver:setOnTurnAwayCourse(onTurnAwayCourse)
	if self.onTurnAwayCourse ~= onTurnAwayCourse then
		self.onTurnAwayCourse = onTurnAwayCourse
	end
end

function CombineUnloadAIDriver:isAlignmentCourseNeeded(ix)
	return true
end

function CombineUnloadAIDriver:drive(dt)
	self:updateInfoText()
	courseplay:updateFillLevelsAndCapacities(self.vehicle)
	if self.state == self.states.UNLOADING then
		-- make sure we apply the unload offset when needed
		self:updateOffset()
		-- update current waypoint/goal point
		self.ppc:update()
		
		--drive unload has the same functionality as GrainTransportAIDriver on unload course
		self:driveUnload(dt)
	elseif self.state == self.states.ON_FIELD then
		self:driveOnField(dt)
	end
end

function CombineUnloadAIDriver:driveOnField(dt)
	--check all tippers and take the next one with free space on it
	self.currentTipper = self:manageTippers()
	
	-- ask th combine manager to assign me to a combine
	if self.fieldState == self.states.LOOKING_FOR_COMBINE then
		self:stop()
		self.combineToUnload = self:lookForCombines()
		--if combine manager assigned me to a combine, search a way to it
		if self.combineToUnload ~= nil then
			self:switchFieldState(self.states.FIND_THE_WAY_TO_COMBINE)
		end
	elseif self.fieldState == self.states.FIND_THE_WAY_TO_COMBINE then
		---space for searching free way to combine and creating a path to it


		----------------		
		
		--when I have a path ready, drive it
		self:switchFieldState(self.states.DRIVE_WAY_ON_FIELD)
	elseif self.fieldState == self.states.DRIVE_WAY_ON_FIELD then
		--when I'm full, I'm on my way to unload course, otherwise on my way to combine
		--I'm also full when he user clicked "drive now" 
		if self:checkFillLevelsFull() then
			--space for the driving on field part
				--call driveCourse with an temp course done by pathfinding
			
			
			
			----------------------------------------------
			--when I'm ready driving course on field, switch to driving unload course
			self:changeToUnload()
			self.ppc:initialize(1)
			self.distanceToObject = 100
		else
			--space for the driving on field part
				--call driveCourse with an temp course done by pathfinding
			
			
			---------------------------------------------------------------
			--when I arrive at the combine, switch to the follow pipe mode and follow the pipe
			self:switchFieldState(self.states.FOLLOW_PIPE)
		end	
		
		--when turning on chopper switch back to follow  pipe 
		
		
	elseif self.fieldState == self.states.FOLLOW_PIPE then
		--all trailers are full, switch to search an path to unload course 
		if self:checkFillLevelsFull() then
			self:switchFieldState(self.states.FIND_THE_WAY_TO_UNLOADCOURSE)
		else
			--traile has free space, follow pipe
			self:followPipe(dt)
		end
	elseif self.fieldState == self.states.FIND_THE_WAY_TO_UNLOADCOURSE then
		---space for searching free way to unloadCourseStart  and creating a path to it


		----------------		
		
		--when I have a path ready, drive it		
		self:switchFieldState(self.states.DRIVE_WAY_ON_FIELD)
	end	
end

function CombineUnloadAIDriver:followPipe(dt)
	--print("CombineUnloadAIDriver:followPipe(dt)")
	local tx,tz = 0,0
	local trailerZOffset = 0
	local allowedToDrive, speed = false, 0
	local rev = false
	if self.combineToUnload.cp.isChopper then
		tx,tz,trailerZOffset,combineZOffset,driveBehindChopper = self:getChoppersTargetUnloadingCoords()
		
		if not driveBehindChopper then	
			--driving beside the chopper
			allowedToDrive, speed = self:getSpeedBesideChopper(self.combineToUnload,trailerZOffset,combineZOffset)
		else
			--driving behind the chopper
			allowedToDrive, speed = self:getSpeedBehindChopper(self.combineToUnload)
			--if the chopper in front of me is backing up, move a bit backwards to make space
			rev = self.combineToUnload.movingDirection < 0 
			if rev then
				self.distanceToObject = 100
				tx,_,tz = localToWorld(self.vehicle.cp.DirectionNode,0,0,-5)
				speed = self.vehicle.cp.speeds.reverse
			end
			
			if self:getIsCombineTurning(self.combineToUnload) then
				--space for creating the turn on chopper course and switch to drive on field
				
				---------------------------------------
				if not rev then
					self:stop()
					return
				end
			end
		end
	else
		--this is the follow combine part to be done
	end
	--renderText(0.2, 0.105, 0.02, string.format("combine.movingDirection:%s; go reverse: %s",tostring(self.combineToUnload.movingDirection),tostring(rev)));
	
	--drive to the point, it wll never get there
	local ty = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, tx, 0, tz)
	local lx,lz = AIVehicleUtil.getDriveDirection(self.vehicle.cp.DirectionNode, tx, ty, tz);
	--if rev then lx = -lx end	
	self:driveVehicleInDirection(dt, allowedToDrive, not rev, lx, lz, speed)
end

function CombineUnloadAIDriver:checkFillLevelsFull()
	return self.vehicle.cp.totalFillLevelPercent == 100
end

function CombineUnloadAIDriver:manageTippers()
	--print("CombineUnloadAIDriver:manageTippers()")
	for _,workTool in pairs(self.vehicle.cp.workTools) do
		if workTool.cp.fillLevelPercent < 100 then
			return workTool
		end	
	end
end

function CombineUnloadAIDriver:stop()
	local gx, _, gz = self.ppc:getGoalPointLocalPosition()	
	self:driveVehicleToLocalPosition(16, false, true, gx, gz, 0)
end

function CombineUnloadAIDriver:lookForCombines()
	return g_combineManager:giveMeACombineToUnload(self.vehicle)
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
	-- Close cover after leaving the field 
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


function CombineUnloadAIDriver:changeToUnload()
	self.state = self.states.UNLOADING
end

function CombineUnloadAIDriver:changeToField()
	self.state = self.states.ON_FIELD
end



--[[
This file is part of Courseplay (https://github.com/Courseplay/courseplay)
Copyright (C) 2019 Peter Vaiko

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

--[[
Fieldwork AI Driver for plows

]]

---@class PlowAIDriver : FieldworkAIDriver
PlowAIDriver = CpObject(FieldworkAIDriver)

PlowAIDriver.myStates = {
	ROTATING_PLOW = {},
	UNFOLDING_PLOW = {},
}

function PlowAIDriver:init(vehicle)
	courseplay.debugVehicle(11,vehicle,'PlowAIDriver:init()')
	FieldworkAIDriver.init(self, vehicle)
	self:initStates(PlowAIDriver.myStates)
	self.mode = courseplay.MODE_FIELDWORK
	self.plow = FieldworkAIDriver.getImplementWithSpecialization(vehicle, Plow)
	self:setOffsetX()
end

-- When starting work with a plow it first may need to be unfolded and then turned so it is facing to
-- the unworked side, and then can we start working
function PlowAIDriver:startWork()
	self:debug('Starting plow work')

	self:setOffsetX()
	self:startEngineIfNeeded()

	-- this will unfold the plow when necessary
	self.vehicle:raiseAIEvent("onAIStart", "onAIImplementStart")
	self.vehicle:requestActionEventUpdate()

	if self.plow.getIsUnfolded and self.plow:getIsUnfolded() then
		self:debug('Plow already unfolded, now rotating if needed')
		self:rotatePlow()
		self.fieldworkState = self.states.ROTATING_PLOW
	else
		self:debug('Unfolding plow')
		self.fieldworkState = self.states.UNFOLDING_PLOW
	end
end

function PlowAIDriver:driveFieldwork()
	if self.fieldworkState == self.states.ROTATING_PLOW then
		self:setSpeed(0)
		if not self.plow.spec_plow:getIsAnimationPlaying(self.plow.spec_plow.rotationPart.turnAnimation) then
			self:debug('Plow rotation finished, ')
			self:lowerImplements(self.vehicle)
			self.fieldworkState = self.states.WAITING_FOR_LOWER
		end
	elseif self.fieldworkState == self.states.UNFOLDING_PLOW then
		self:setSpeed(0)
		if self.plow.getIsUnfolded and self.plow:getIsUnfolded() then
			if self.plow:getIsPlowRotationAllowed() then
				self:debug('Plow unfolded, now rotating if needed')
				self:rotatePlow()
			end
			self.fieldworkState = self.states.ROTATING_PLOW
		end
	else
		FieldworkAIDriver.driveFieldwork(self)
	end
end

function PlowAIDriver:onWaypointPassed(ix)
	-- readjust the tool offset every now and then. This is necessary as the offset is calculated from the
	-- tractor's direction node which may need to result in incorrect values if the plow is not straight behind
	-- the tractor (which may be the case when starting). When passing waypoints we'll most likely be driving
	-- straight and thus calculating a proper tool offset
	if self.state == self.states.ON_FIELDWORK_COURSE and self.fieldworkState == self.states.WORKING then
		self:setOffsetX()
	end
	FieldworkAIDriver.onWaypointPassed(self, ix)
end

function PlowAIDriver:rotatePlow()
	self:debug('Starting work: check if plow needs to be turned.')
	local ridgeMarker = self.course:getRidgeMarkerState(self.ppc:getCurrentWaypointIx())
	local plowShouldBeOnTheLeft = ridgeMarker == courseplay.RIDGEMARKER_RIGHT
	self:debug('Ridge marker %d, plow should be on the left %s', ridgeMarker, tostring(plowShouldBeOnTheLeft))
	self.plow.spec_plow:setRotationMax(plowShouldBeOnTheLeft)
end

function PlowAIDriver:setOffsetX()
	local aiLeftMarker, aiRightMarker, aiBackMarker = self.plow.spec_plow:getAIMarkers()
	if aiLeftMarker and aiBackMarker and aiRightMarker then
		local leftMarkerDistance, _, _ = localToLocal(aiLeftMarker, self:getDirectionNode(), 0, 0, 0)
		local rightMarkerDistance, _, _ = localToLocal(aiRightMarker, self:getDirectionNode(), 0, 0, 0)
		-- TODO: Fix this offset dependency and copy paste
		self.vehicle.cp.toolOffsetX = (leftMarkerDistance + rightMarkerDistance) / 2
		self.vehicle.cp.totalOffsetX = self.vehicle.cp.laneOffset + self.vehicle.cp.toolOffsetX;
		self:debug('%s: left = %.1f, right = %.1f, setting tool offsetX to %.1f', nameNum(self.plow), leftMarkerDistance, rightMarkerDistance, self.vehicle.cp.toolOffsetX)
	end
end
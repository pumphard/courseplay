local curFile = 'start_stop.lua';

-- starts driving the course
function courseplay:start(self)
	self.cp.TrafficBrake = false
	self.cp.inTraffic = false
	self.currentHelper = g_helperManager:getRandomHelper()
	self.spec_aiVehicle.isActive = true
	self.cp.stopMotorOnLeaveBackup = self.spec_motorized.stopMotorOnLeave;
	self.spec_motorized.stopMotorOnLeave = false;
	self.spec_enterable.disableCharacterOnLeave = false;
	if not CpManager.trafficCollisionIgnoreList[g_currentMission.terrainRootNode] then			-- ???
		CpManager.trafficCollisionIgnoreList[g_currentMission.terrainRootNode] = true;
	end;

	-- TODO: move this to TrafficCollision.lua
	if self:getAINeedsTrafficCollisionBox() then
		local collisionRoot = g_i3DManager:loadSharedI3DFile(AIVehicle.TRAFFIC_COLLISION_BOX_FILENAME, self.baseDirectory, false, true, false)
		if collisionRoot ~= nil and collisionRoot ~= 0 then
			local collision = getChildAt(collisionRoot, 0)
			link(getRootNode(), collision)

			self.spec_aiVehicle.aiTrafficCollision = collision

			delete(collisionRoot)
		end
	end

	if self.setRandomVehicleCharacter ~= nil then
		self:setRandomVehicleCharacter()
	end

    -- Start the reset character timer.
	courseplay:setCustomTimer(self, "resetCharacter", 300);

	if courseplay.isClient then
		return
	end
	self.cp.numWayPoints = #self.Waypoints;
	--self:setCpVar('numWaypoints', #self.Waypoints,courseplay.isClient);
	if self.cp.numWaypoints < 1 then
		return
	end
	courseplay:setEngineState(self, true);
	self.cp.saveFuel = false

	--print_r(self)
	
	--print(tableShow(self.attachedImplements[1],"self.attachedImplements",nil,nil,4))
	--local id = self.attachedImplements[1].object.unloadTrigger.triggerId
	--courseplay:findInTables(g_currentMission ,"g_currentMission", id)
	courseplay.alreadyPrinted = {} 
	--courseplay:printMeThisTable(g_currentMission,0,5,"g_currentMission")
	
	--[[Tommi Todo Whx is this here ???
	if self.cp.orgRpm == nil then
		self.cp.orgRpm = {}
		self.cp.orgRpm[1] = self.spec_motorized.motor.maxRpm
		self.cp.orgRpm[2] = self.spec_motorized.motor.maxRpm
		self.cp.orgRpm[3] = self.spec_motorized.motor.maxRpm
	end]]
	
	self.cpTrafficCollisionIgnoreList = {}
	-- self.CPnumCollidingVehicles = 0;					-- ??? not used anywhere
	self.cp.collidingVehicleId = nil
	self.cp.collidingObjects = {
		all = {};
	};
	
	courseplay:debug(string.format("%s: Start/Stop: deleting \"self.cp.collidingVehicleId\"", nameNum(self)), 3);
	--self.numToolsCollidingVehicles = {};
	self:setIsCourseplayDriving(false);
	courseplay:setIsRecording(self, false);
	courseplay:setRecordingIsPaused(self, false);
	self.cp.calculatedCourseToCombine = false

	courseplay:resetTools(self)
--[[
	--TODO when checking the Collision triggers, check if we still need this
	if self.attachedCutters ~= nil then
]]

	--calculate workwidth for combines in mode7
	if self.cp.mode == 7 then
		courseplay:calculateWorkWidth(self)
	end
	-- set default modeState if not in mode 2 or 3
	if self.cp.mode ~= 2 and self.cp.mode ~= 3 then
		courseplay:setModeState(self, 0);
	end;

	if self.cp.waypointIndex < 1 then
		courseplay:setWaypointIndex(self, 1);
	end

	-- add do working players if not already added
	if self.cp.coursePlayerNum == nil then
		self.cp.coursePlayerNum = CpManager:addToTotalCoursePlayers(self)
	end;
	--add to activeCoursePlayers
	CpManager:addToActiveCoursePlayers(self);

	self.cp.turnTimer = 8000
	
	-- show arrow
	self:setCpVar('distanceCheck',true,courseplay.isClient);
	-- current position
	local ctx, cty, ctz = getWorldTranslation(self.cp.DirectionNode);
	-- position of next waypoint
	local cx, cz = self.Waypoints[self.cp.waypointIndex].cx, self.Waypoints[self.cp.waypointIndex].cz
	-- distance (in any direction)
	local dist = courseplay:distance(ctx, ctz, cx, cz)

	local setLaneNumber = false;
	local isFrontAttached = false;
	local isReversePossible = true;
	local tailerCount = 0;
	for k,workTool in pairs(self.cp.workTools) do    --TODO temporary solution (better would be Tool:getIsAnimationPlaying(animationName))
		if courseplay:isFolding(workTool) then
			if  self.setLowered ~= nil then
				workTool:setLowered(true)
			elseif self.setFoldState ~= nil then
				self:setFoldState(-1, true)
			end
		end;
		--DrivingLine spec: set lane numbers
		if self.cp.mode == 4 and not setLaneNumber and workTool.cp.hasSpecializationDrivingLine and not workTool.manualDrivingLine then
			setLaneNumber = true;
		end;
		if self.cp.mode == 10 then
			local x,y,z = getWorldTranslation(workTool.rootNode)  
			local _,_,tz = worldToLocal(self.cp.DirectionNode,x,y,z)
			if tz > 0 then
				isFrontAttached = true
			end
		end
		if workTool.cp.hasSpecializationTrailer then
			tailerCount = tailerCount + 1
			if tailerCount > 1 then
				isReversePossible = false
			end
		end
				
		if workTool.spec_sprayer ~= nil and self.cp.hasFertilizerSowingMachine then
			workTool.fertilizerEnabled = self.cp.fertilizerEnabled
		end	
		
		if workTool.cp.isSugarCaneAugerWagon then
			isReversePossible = false
		end
		
	end;
	self.cp.isReversePossible = isReversePossible
	self.cp.mode10.levelerIsFrontAttached = isFrontAttached
	
	if self.cp.mode == 10 then 
		if self.cp.mode10.OrigCompactScale == nil then
			self.cp.mode10.OrigCompactScale = self.bunkerSiloCompactingScale
			self.bunkerSiloCompactingScale = self.bunkerSiloCompactingScale*5
		end
	end
		
		
	local mapIconPath = Utils.getFilename('img/mapWaypoint.png', courseplay.path);
	local mapIconHeight = 2 / 1080;
	local mapIconWidth = mapIconHeight / g_screenAspectRatio;

	local numWaitPoints = 0
	local numUnloadPoints = 0
	local numCrossingPoints = 0
	self.cp.waitPoints = {};
	self.cp.unloadPoints = {};
	self.cp.workDistance = 0
	self.cp.mediumWpDistance = 0
	self.cp.mode10.alphaList = {}
	local nearestpoint = dist
	local nearestWpIx = 0
	local curLaneNumber = 1;
	local hasReversing = false;
	local lookForNearestWaypoint = self.cp.startAtPoint == courseplay.START_AT_NEAREST_POINT and (self.cp.modeState == 0 or self.cp.modeState == 99); --or self.cp.modeState == 1

	local lookForNextWaypoint = self.cp.startAtPoint == courseplay.START_AT_NEXT_POINT and (self.cp.modeState == 0 or self.cp.modeState == 99); 
	local nx, _, nz = localDirectionToWorld( self.cp.DirectionNode, 0, 0, 1 )
	local myDirection = math.atan2( nx, nz ) 
	-- one of the remaining waypoints of the course, closest in front of us
	local nextWaypointIx = 1
	local foundNextWaypoint = false
	local distNextWaypoint = math.huge
	-- any waypoint of the course, closest in front of us
	local nearestWaypointInSameDirectionIx = 1
	local foundNearestWaypointInSameDirection = false
	local distNearestWaypointInSameDirection = math.huge


	for i,wp in pairs(self.Waypoints) do
		local cx, cz = wp.cx, wp.cz;

		-- find nearest waypoint regardless of its rotation and direction from us
		if lookForNearestWaypoint or lookForNextWaypoint then
			dist = courseplay:distance(ctx, ctz, cx, cz)
			if dist <= nearestpoint then
				nearestpoint = dist
				nearestWpIx = i
			end;
		end;

		-- find next waypoint 
		if lookForNextWaypoint then
			local _, _, dz = worldToLocal( self.cp.DirectionNode, cx, 0, cz )
			local deltaAngle = math.huge	
			if wp.angle ~= nil then 
				deltaAngle = math.abs( getDeltaAngle( math.rad( wp.angle ), myDirection ))
			end
			-- we don't want to deal with anything closer than 5 m to avoid circling
			-- also, we want the waypoint which points into the direction we are currently heading to
			if dist < 30 and dz > 5 and deltaAngle < math.rad( 45 ) then
				if dist < distNearestWaypointInSameDirection then
					nearestWaypointInSameDirectionIx = i
					distNearestWaypointInSameDirection = dist
					foundNearestWaypointInSameDirection = true
					courseplay:debug(string.format('%s: found waypoint %d anywhere, distance = %.1f, deltaAngle = %.1f', nameNum(self), i, dist, math.deg( deltaAngle )), 12);
				end
				if dist < distNextWaypoint and i >= self.cp.waypointIndex and i <= self.cp.waypointIndex + 10 then
					foundNextWaypoint = true
					distNextWaypoint = dist
					nextWaypointIx = i
					courseplay:debug(string.format('%s: found waypoint %d next, distance = %.1f, deltaAngle = %.1f', nameNum(self), i, dist, math.deg( deltaAngle )), 12);
				end
			end
		end

		if wp.wait then
			numWaitPoints = numWaitPoints + 1;
			self.cp.waitPoints[numWaitPoints] = i;
		end;
		if wp.unload then
			numUnloadPoints = numUnloadPoints + 1;
			self.cp.unloadPoints[numUnloadPoints] = i;
		end;
		if wp.crossing then
			numCrossingPoints = numCrossingPoints + 1;
			self.cp.crossingPoints[numCrossingPoints] = i;
		end;

		-- has reversing part
		if self.cp.mode ~= 9 and wp.rev then
			hasReversing = true;
		end;

		-- specific Workzone
		if self.cp.mode == 4 or self.cp.mode == 6 then
			if numWaitPoints == 1 and (self.cp.startWork == nil or self.cp.startWork == 0) then
				self.cp.startWork = i
			end
			if numWaitPoints > 1 and (self.cp.stopWork == nil or self.cp.stopWork == 0) then
				self.cp.stopWork = i
			end
			if self.cp.startWork and not self.cp.stopWork then
				if i > 1 then
					local dist = courseplay:distance(cx, cz, self.Waypoints[i-1].cx, self.Waypoints[i-1].cz)
					self.cp.workDistance = self.cp.workDistance + dist
					self.cp.mediumWpDistance = self.cp.workDistance/i
				end
			end
			if numUnloadPoints == 1 and (self.cp.heapStart == nil or self.cp.heapStart == 0) then
				self.cp.heapStart = i
				self.cp.makeHeaps = false
			end
			if numUnloadPoints > 1 and (self.cp.heapStop == nil or self.cp.heapStop == 0) then
				self.cp.heapStop = i
				self.cp.makeHeaps = true
			end
		elseif self.cp.mode == 7  then--combineUnloadMode
			if numUnloadPoints == 1 and (self.cp.heapStart == nil or self.cp.heapStart == 0) then
				self.cp.heapStart = i
				self.cp.makeHeaps = false
			end
			if numUnloadPoints > 1 and (self.cp.heapStop == nil or self.cp.heapStop == 0) then
				self.cp.heapStop = i
				self.cp.makeHeaps = true
			end
		--unloading point for transporter
		elseif self.cp.mode == 8 then
			--

		--work points for shovel
		elseif self.cp.mode == 9 then
			--moved to ShovelModeAIDriver
		end;

		-- laneNumber (for seeders)
		if setLaneNumber and wp.generated ~= nil and wp.generated == true then
			if wp.turnEnd ~= nil and wp.turnEnd == true then
				curLaneNumber = curLaneNumber + 1;
				courseplay:debug(string.format('%s: waypoint %d: turnEnd=true -> new curLaneNumber=%d', nameNum(self), i, curLaneNumber), 12);
			end;
			wp.laneNum = curLaneNumber;
		end;
	end; -- END for wp in self.Waypoints
	
	-- modes 4/6 without start and stop point, set them at start and end, for only-on-field-courses
	if (self.cp.mode == 4 or self.cp.mode == 6) then
		if numWaitPoints == 0 or self.cp.startWork == nil then
			self.cp.startWork = 1;
		end;
		if numWaitPoints == 0 or self.cp.stopWork == nil then
			self.cp.stopWork = self.cp.numWaypoints;
		end;
	end;
	self.cp.numWaitPoints = numWaitPoints;
	self.cp.numUnloadPoints = numUnloadPoints;
	self.cp.numCrossingPoints = numCrossingPoints;
	courseplay:debug(string.format("%s: numWaitPoints=%d, waitPoints[1]=%s, numCrossingPoints=%d", nameNum(self), self.cp.numWaitPoints, tostring(self.cp.waitPoints[1]), numCrossingPoints), 12);

	-- set waitTime to 0 if necessary
	if not courseplay:getCanHaveWaitTime(self) and self.cp.waitTime > 0 then
		courseplay:changeWaitTime(self, -self.cp.waitTime);
	end;

  if lookForNextWaypoint then
		if foundNextWaypoint then 
			courseplay:debug(string.format('%s: found next waypoint: %d', nameNum(self), nextWaypointIx ), 12);
			courseplay:safeSetWaypointIndex( self, nextWaypointIx )     
		elseif foundNearestWaypointInSameDirection then
			courseplay:debug(string.format('%s: no next waypoint found, using the closest one in the same direction: %d', nameNum(self), nearestWaypointInSameDirectionIx), 12);
			courseplay:safeSetWaypointIndex( self, nearestWaypointInSameDirectionIx )     
		else
			courseplay:debug(string.format('%s: no next waypoint found, none found in the same direction, falling back to the nearest: %d', 
			                               nameNum(self), nearestWpIx ), 12);
			courseplay:safeSetWaypointIndex( self, nearestWpIx )     
    end
  end
	
	if lookForNearestWaypoint then
		courseplay:safeSetWaypointIndex( self, nearestWpIx )     
	end --END if modeState == 0

	if self.cp.waypointIndex > 2 and self.cp.mode ~= 4 and self.cp.mode ~= 6 and self.cp.mode ~= 8 then
		courseplay:setDriveUnloadNow(self, true);
	elseif self.cp.mode == 4 or self.cp.mode == 6 then
		courseplay:setDriveUnloadNow(self, false);
		self.cp.hasUnloadingRefillingCourse = self.cp.numWaypoints > self.cp.stopWork + 7;
		self.cp.hasTransferCourse = self.cp.startWork > 5
		if  self.Waypoints[self.cp.stopWork].cx == self.Waypoints[self.cp.startWork].cx 
		and self.Waypoints[self.cp.stopWork].cz == self.Waypoints[self.cp.startWork].cz then -- TODO: VERY unsafe, there could be LUA float problems (e.g. 7 + 8 = 15.000000001)
			self.cp.finishWork = self.cp.stopWork-5
		else
			self.cp.finishWork = self.cp.stopWork
		end

		-- NOTE: if we want to start the course but catch one of the last 5 points ("returnToStartPoint"), make sure we get wp 2
		if self.cp.startAtPoint == courseplay.START_AT_NEAREST_POINT and self.cp.finishWork ~= self.cp.stopWork and self.cp.waypointIndex > self.cp.finishWork and self.cp.waypointIndex <= self.cp.stopWork then
			courseplay:setWaypointIndex(self, 2);
		end
		courseplay:debug(string.format("%s: numWaypoints=%d, stopWork=%d, finishWork=%d, hasUnloadingRefillingCourse=%s,hasTransferCourse=%s, waypointIndex=%d", nameNum(self), self.cp.numWaypoints, self.cp.stopWork, self.cp.finishWork, tostring(self.cp.hasUnloadingRefillingCourse),tostring(self.cp.hasTransferCourse), self.cp.waypointIndex), 12);
	elseif self.cp.mode == 8 then
		courseplay:setDriveUnloadNow(self, false);
	end

	if self.cp.startAtPoint == courseplay.START_AT_FIRST_POINT then
		if self.cp.mode == 2 or self.cp.mode == 3 then
			courseplay:setWaypointIndex(self, 3);
			courseplay:setDriveUnloadNow(self, true);
		else
			courseplay:setWaypointIndex(self, 1);
			local distToFirst = courseplay:distanceToPoint( self, self.Waypoints[ 1 ].cx, 0, self.Waypoints[ 1 ].cz )
			if not self.cp.drivingMode:is(DrivingModeSetting.DRIVING_MODE_AIDRIVER) and distToFirst > self.cp.turnDiameter then
				courseplay:startAlignmentCourse( self, self.Waypoints[ 1 ])
			end
		end
	end;

	-- Reset pathfinding for mode 4 and 6 if resuming from a waypoint other than the current one
	if (self.cp.mode == 4 or self.cp.mode == 6) and self.cp.realisticDriving == true and #(self.cp.nextTargets) > 0 and self.cp.startAtPoint ~= courseplay.START_AT_CURRENT_POINT then
		self.cp.nextTargets = {}
		self.cp.isNavigatingPathfinding = false
	end

	courseplay:updateAllTriggers();

	self.cp.aiLightsTypesMaskBackup  = self.spec_lights.aiLightsTypesMask
	self.cp.cruiseControlSpeedBackup = self:getCruiseControlSpeed();

	if self.cp.hasDriveControl then
		local changed = false;
		if self.cp.driveControl.hasFourWD then
			self.cp.driveControl.fourWDBackup = self.driveControl.fourWDandDifferentials.fourWheel;
			if self.cp.driveControl.alwaysUseFourWD and not self.driveControl.fourWDandDifferentials.fourWheel then
				self.driveControl.fourWDandDifferentials.fourWheel = true;
				changed = true;
			end;
		end;
		if self.cp.driveControl.hasHandbrake then
			if self.driveControl.handBrake.isActive == true then
				self.driveControl.handBrake.isActive = false;
				changed = true;
			end;
		end;
		if self.cp.driveControl.hasShuttleMode and self.driveControl.shuttle.isActive then
			if self.driveControl.shuttle.direction < 1.0 then
				self.driveControl.shuttle.direction = 1.0;
				changed = true;
			end;
		end;

		if changed and driveControlInputEvent ~= nil then
			driveControlInputEvent.sendEvent(self);
		end;
	end;
	
	--check Crab Steering mode and set it to default
	if self.crabSteering and (self.crabSteering.state ~= self.crabSteering.aiSteeringModeIndex or self.cp.useCrabSteeringMode ~= nil) then
		local crabSteeringMode = self.cp.useCrabSteeringMode or self.crabSteering.aiSteeringModeIndex;
		self:setCrabSteering(crabSteeringMode);
	end

	-- ok i am near the waypoint, let's go
	self.cp.savedCheckSpeedLimit = self.checkSpeedLimit;
	self.checkSpeedLimit = false
	self.cp.runOnceStartCourse = true;
	self:setIsCourseplayDriving(true);
	courseplay:setIsRecording(self, false);
	self:setCpVar('distanceCheck',false,courseplay.isClient);

	self.cp.totalLength, self.cp.totalLengthOffset = courseplay:getTotalLengthOnWheels(self);

	courseplay:validateCanSwitchMode(self);

	-- deactivate load/add/delete course buttons
	--courseplay.buttons:setActiveEnabled(self, 'page2');

	-- add ingameMap icon
	if CpManager.ingameMapIconActive then
		courseplay:createMapHotspot(self);
	end;

	-- Disable crop destruction if 4Real Module 01 - Crop Destruction mod is installed
	if self.cropDestruction then
		courseplay:disableCropDestruction(self);
	end;

	--More Realistitic Mod. Temp fix until we can fix the breaking problem.
	if self.mrUseMrTransmission and self.mrUseMrTransmission == true then
		self.mrUseMrTransmission = false;
		self.cp.changedMRMod = true;
	end
	if self.cp.drivingMode:get() == DrivingModeSetting.DRIVING_MODE_AIDRIVER then
		local ret_removeLegacyCollisionTriggers = false			-- TODO could be used for further processing / error handling / information to the user
		ret_removeLegacyCollisionTriggers = courseplay:removeLegacyCollisionTriggers(self)
		-- the driver handles the PPC
		-- and another ugly hack here as when settings.lua setAIDriver() is called the bale loader does not seem to be
		-- attached and I don't have the motivation do dig through the legacy code to find out why
		if self.cp.mode == courseplay.MODE_FIELDWORK then
			self.cp.driver:delete()
			self.cp.driver = UnloadableFieldworkAIDriver.create(self)
		end
		self.cp.driver:start(self.cp.waypointIndex)
	else
		if self.cp.driver then
			self.cp.driver:delete()
		end
		-- Initialize pure pursuit controller
		self.cp.ppc = PurePursuitController(self)
		self.cp.ppc:initialize()
		local ret_createLegacyCollisionTriggers = false			-- TODO could be used for further processing / error handling / information to the user
		ret_createLegacyCollisionTriggers = courseplay:createLegacyCollisionTriggers(self)
	end
	--print('startStop 509')

end;

function courseplay:getCanUseCpMode(vehicle)
	-- check engine running state
	if not courseplay:getIsEngineReady(vehicle) then
		return false;
	end;

	local mode = vehicle.cp.mode;

	if (mode == 7 and not vehicle.cp.isCombine and not vehicle.cp.isChopper and not vehicle.cp.isHarvesterSteerable)
	or ((mode == 1 or mode == 2 or mode == 3 or mode == 4 or mode == 8 or mode == 9) and (vehicle.cp.isCombine or vehicle.cp.isChopper or vehicle.cp.isHarvesterSteerable))
	or ((mode ~= 5) and (vehicle.cp.isWoodHarvester or vehicle.cp.isWoodForwarder)) then
		courseplay:setInfoText(vehicle, 'COURSEPLAY_MODE_NOT_SUPPORTED_FOR_VEHICLETYPE');
		print('Not Supported Vehicle Type')
		return false;
	end;


	if mode ~= 5 and mode ~= 7 and not vehicle.cp.workToolAttached then
		if mode == 4 or mode == 6 then
			courseplay:setInfoText(vehicle, 'COURSEPLAY_WRONG_TOOL');
		elseif mode == 9 then
			courseplay:setInfoText(vehicle, 'COURSEPLAY_SHOVEL_NOT_FOUND');
		elseif mode == 10 then
			courseplay:setInfoText(vehicle, 'COURSEPLAY_MODE10_NOBLADE');
		else
			courseplay:setInfoText(vehicle, 'COURSEPLAY_WRONG_TRAILER');
		end;
		return false;
	end;
	
	if mode == 10 and vehicle.cp.mode10.levelerIsFrontAttached then
		courseplay:setInfoText(vehicle, 'COURSEPLAY_MODE10_NOFRONTBLADE');
		return false;
	end

	local minWait, maxWait, minUnload, maxUnload;

	if (mode == 1 and vehicle.cp.hasAugerWagon) or mode == 3 or mode == 8 or mode == 10 then
		minWait, maxWait = 1, 1;
		if  vehicle.cp.hasWaterTrailer then
			maxWait = 10
		end
		if vehicle.cp.numWaitPoints < minWait then
			courseplay:setInfoText(vehicle, string.format("COURSEPLAY_WAITING_POINTS_TOO_FEW;%d",minWait));
			return false;
		elseif vehicle.cp.numWaitPoints > maxWait then
			courseplay:setInfoText(vehicle, string.format('COURSEPLAY_WAITING_POINTS_TOO_MANY;%d',maxWait));
			return false;
		end;
		if mode == 3 then
			maxUnload = 0
			if vehicle.cp.workTools[1] == nil or vehicle.cp.workTools[1].cp == nil or not vehicle.cp.workTools[1].cp.isAugerWagon then
				courseplay:setInfoText(vehicle, 'COURSEPLAY_WRONG_TRAILER');
				return false;
			elseif vehicle.cp.numUnloadPoints > maxUnload then
			courseplay:setInfoText(vehicle, string.format('COURSEPLAY_UNLOADING_POINTS_TOO_MANY;%d',maxUnload));
			return false; 
			end;
		elseif mode == 8 then
			if vehicle.cp.workTools[1] == nil then
				courseplay:setInfoText(vehicle, 'COURSEPLAY_WRONG_TRAILER');
				return false;
			end;
		end;
	elseif mode == 7 then
		-- DELETE ME MODE 7 Crap
		minWait, maxWait = 1, 1;
		if vehicle.cp.numUnloadPoints == 0 and vehicle.cp.numWaitPoints < minWait then
			courseplay:setInfoText(vehicle, string.format("COURSEPLAY_WAITING_POINTS_TOO_FEW;%d",minWait));
			return false;
		elseif vehicle.cp.numWaitPoints > maxWait then
			courseplay:setInfoText(vehicle, string.format('COURSEPLAY_WAITING_POINTS_TOO_MANY;%d',maxWait));
			return false;
		end;
		minUnload, maxUnload = 2, 2;
		if vehicle.cp.numWaitPoints == 0 and vehicle.cp.numUnloadPoints < minUnload then
			courseplay:setInfoText(vehicle, string.format('COURSEPLAY_UNLOADING_POINTS_TOO_FEW;%d',minUnload));
			return false;
		elseif vehicle.cp.numUnloadPoints > maxUnload then
			courseplay:setInfoText(vehicle, string.format('COURSEPLAY_UNLOADING_POINTS_TOO_MANY;%d',maxUnload));
			return false;
		end;
	elseif mode == 4 or mode == 6 then
		if vehicle.cp.startWork == nil or vehicle.cp.stopWork == nil then
			courseplay:setInfoText(vehicle, 'COURSEPLAY_NO_WORK_AREA');
			return false;
		end;
		if mode == 6 then
			maxUnload = 0;
			if vehicle.cp.hasBaleLoader then
				minWait, maxWait = 2, 3;
				if vehicle.cp.numWaitPoints < minWait then
					courseplay:setInfoText(vehicle, string.format('COURSEPLAY_WAITING_POINTS_TOO_FEW;%d',minWait));
					return false;
				elseif vehicle.cp.numWaitPoints > maxWait then
					courseplay:setInfoText(vehicle, string.format('COURSEPLAY_WAITING_POINTS_TOO_MANY;%d',maxWait));
					return false;
				end;																									--TODO: Remove when tippers are supported with 2 unload points
			elseif (vehicle.cp.isCombine or vehicle.cp.isHarvesterSteerable or vehicle.cp.hasHarvesterAttachable) and not vehicle.cp.hasSpecialChopper then
				maxUnload = 2;
			else
				maxUnload = 1;
			end;
			if vehicle.cp.numUnloadPoints > maxUnload then
				courseplay:setInfoText(vehicle, string.format('COURSEPLAY_UNLOADING_POINTS_TOO_MANY;%d',maxUnload));
				return false;
			end;
		end;

	elseif mode == 9 then
		minWait, maxWait = 3, 3;
		if vehicle.cp.numWaitPoints < minWait then
			courseplay:setInfoText(vehicle, string.format('COURSEPLAY_WAITING_POINTS_TOO_FEW;%d',minWait));
			return false;
		elseif vehicle.cp.numWaitPoints > maxWait then
			courseplay:setInfoText(vehicle, string.format('COURSEPLAY_WAITING_POINTS_TOO_MANY;%d',maxWait));
			return false;
		elseif vehicle.cp.shovelStatePositions == nil or vehicle.cp.shovelStatePositions[2] == nil or vehicle.cp.shovelStatePositions[3] == nil or vehicle.cp.shovelStatePositions[4] == nil or vehicle.cp.shovelStatePositions[5] == nil then
			courseplay:setInfoText(vehicle, 'COURSEPLAY_SHOVEL_POSITIONS_MISSING');
			return false;
		elseif vehicle.cp.shovelFillStartPoint == nil or vehicle.cp.shovelFillEndPoint == nil or vehicle.cp.shovelEmptyPoint == nil then
			courseplay:setInfoText(vehicle, 'COURSEPLAY_NO_VALID_COURSE');
			return false;
		end;
	end;

	return true;
end;

-- stops driving the course
function courseplay:stop(self)
	-- Stop AI Driver
	if self.cp.driver then
		self.cp.driver:dismiss()
	end

	local ret2_removeLegacyCollisionTriggers = false				-- TODO could be used for further processing / error handling / information to the user
	ret_removeLegacyCollisionTriggers = courseplay:removeLegacyCollisionTriggers(self)
	self.spec_aiVehicle.isActive = false
	self.spec_motorized.stopMotorOnLeave = self.cp.stopMotorOnLeaveBackup;
	self.spec_enterable.disableCharacterOnLeave = true;

	-- TODO: move this to TrafficCollision.lua
    if self:getAINeedsTrafficCollisionBox() then
        setTranslation(self.spec_aiVehicle.aiTrafficCollision, 0, -1000, 0)
        self.spec_aiVehicle.aiTrafficCollisionRemoveDelay = 200
    end

	if g_currentMission.missionInfo.automaticMotorStartEnabled and self.cp.saveFuel and not self.spec_motorized.isMotorStarted then
		courseplay:setEngineState(self, true);
		self.cp.saveFuel = false;
	end
	if courseplay:getCustomTimerExists(self,'fuelSaveTimer')  then
		--print("reset existing timer")
		courseplay:resetCustomTimer(self,'fuelSaveTimer',true)
	end

	-- Reset the reset character timer.
	courseplay:resetCustomTimer(self, "resetCharacter", true);

	if self.restoreVehicleCharacter ~= nil then
		self:restoreVehicleCharacter()
	end

	courseplay:endAlignmentCourse( self )
--[[ This is FS17 code
	if self.vehicleCharacter ~= nil then
		self.vehicleCharacter:delete();
	end
	if self.isEntered or self.isControlled then
		if self.vehicleCharacter ~= nil then
			----------------------------------
			--- Fix Missing playerIndex and playerColorIndex that some times happens for unknow reasons
			local playerIndex = Utils.getNoNil(self.playerIndex, g_currentMission.missionInfo.playerIndex);
			local playerColorIndex = Utils.getNoNil(self.playerColorIndex, g_currentMission.missionInfo.playerColorIndex);
			--- End Fix
			----------------------------------

			self.vehicleCharacter:loadCharacter(PlayerUtil.playerIndexToDesc[playerIndex].xmlFilename, playerColorIndex)
			self.vehicleCharacter:setCharacterVisibility(not self:getIsEntered())
		end
	end;]]
	self.currentHelper = nil

	--stop special tools
	for _, tool in pairs (self.cp.workTools) do
		--  vehicle, workTool, unfold, lower, turnOn, allowedToDrive, cover, unload, ridgeMarker,forceSpeedLimit)
		courseplay:handleSpecialTools(self, tool, false,   false,  false,   false, false, nil,nil,0);
		if tool.cp.originalCapacities then
			for index,fillUnit in pairs(tool.fillUnits) do
				fillUnit.capacity =  tool.cp.originalCapacities[index]
			end
			tool.cp.originalCapacities = nil
		end
		if tool.fertilizerEnabled ~= nil then
			tool.fertilizerEnabled = nil
		end
	end
	if self.cp.directionNodeToTurnNodeLength ~= nil then
		self.cp.directionNodeToTurnNodeLength = nil
	end

	self.cp.lastInfoText = nil

	if courseplay.isClient then
		return
	end
	
	--mode10 restore original compactingScales
	if self.cp.mode10.OrigCompactScale ~= nil then
		self.bunkerSiloCompactingScale = self.cp.mode10.OrigCompactScale 
		self.cp.mode10.OrigCompactScale = nil
	end
	
	
	-- Enable crop destruction if 4Real Module 01 - Crop Destruction mod is installed
	if self.cropDestruction then
		courseplay:enableCropDestruction(self);
	end;

	-- MR and Real Fill Type Mass mod combatiablity 
	if self.cp.useProgessiveBraking then
		self.cp.mrAccelrator = nil
	end

	if self.cp.hasDriveControl then
		local changed = false;
		if self.cp.driveControl.hasFourWD and self.driveControl.fourWDandDifferentials.fourWheel ~= self.cp.driveControl.fourWDBackup then
			self.driveControl.fourWDandDifferentials.fourWheel = self.cp.driveControl.fourWDBackup;
			self.driveControl.fourWDandDifferentials.diffLockFront = false;
			self.driveControl.fourWDandDifferentials.diffLockBack = false;
			changed = true;
		end;

		if changed and driveControlInputEvent ~= nil then
			driveControlInputEvent.sendEvent(self);
		end;
	end;

	if self.cp.cruiseControlSpeedBackup then
		self.spec_drivable.cruiseControl.speed = self.cp.cruiseControlSpeedBackup; -- NOTE JT: no need to use setter or event function - Drivable's update() checks for changes in the var and calls the event itself
		self.cp.cruiseControlSpeedBackup = nil;
	end; 

	self.spec_lights.aiLightsTypesMask = self.cp.aiLightsTypesMaskBackup
	
	if self.cp.takeOverSteering then
		self.cp.takeOverSteering = false
	end

	courseplay:removeFromVehicleLocalIgnoreList(vehicle, self.cp.activeCombine)
	courseplay:removeFromVehicleLocalIgnoreList(vehicle, self.cp.lastActiveCombine)
	courseplay:releaseCombineStop(self)
	self.cp.BunkerSiloMap = nil
	self.cp.mode9TargetSilo = nil
	self.cp.mode10.lowestAlpha = 99
	
	
	self:setCruiseControlState(Drivable.CRUISECONTROL_STATE_OFF)
	self.spec_drivable.cruiseControl.minSpeed = 1
	self.cp.forcedToStop = false
	self.cp.waitingForTrailerToUnload = false
	courseplay:setIsRecording(self, false);
	courseplay:setRecordingIsPaused(self, false);
	self.cp.isTurning = nil;
	courseplay:clearTurnTargets(self);
	self.cp.aiTurnNoBackward = false
	self.cp.noStopOnEdge = false
	self.cp.fillTrigger = nil;
	self.cp.factoryScriptTrigger = nil;
	self.cp.tipperLoadMode = 0;
	self.cp.hasMachineToFill = false;
	self.cp.unloadOrder = false
	self.cp.isUnloadingStopped = false
	self.cp.foundColli = {}
	self.cp.TrafficBrake = false
	self.cp.inTraffic = false
	self.cp.collidingVehicleId = nil
	self.cp.collidingObjects = {
		all = {};
	};
	self.cp.bypassWaypointsSet = false
	-- deactivate beacon and hazard lights
	if self.beaconLightsActive then
		self:setBeaconLightsVisibility(false);
	end;
	if self.spec_lights.turnLightState and self.spec_lights.turnLightState ~= Lights.TURNLIGHT_OFF then
		self:setTurnLightState(Lights.TURNLIGHT_OFF);
	end;

	-- resetting variables
	--self.cp.ColliHeightSet = nil
	self.cp.tempCollis = {}
	self.checkSpeedLimit = self.cp.savedCheckSpeedLimit;
	courseplay:resetTipTrigger(self);
	self:setIsCourseplayDriving(false);
	self:setCpVar('canDrive',true,courseplay.isClient)
	self:setCpVar('distanceCheck',false,courseplay.isClient);
	if self.cp.checkReverseValdityPrinted then
		self.cp.checkReverseValdityPrinted = false

	end
	self.cp.lastMode8UnloadTriggerId = nil

	self.cp.curSpeed = 0;

	self.spec_motorized.motor.maxRpmOverride = nil;
	self.cp.heapStart = nil
	self.cp.heapStop = nil
	self.cp.startWork = nil
	self.cp.stopWork = nil
	self.cp.hasFinishedWork = nil
	self.cp.turnTimeRecorded = nil;	
	self.cp.hasUnloadingRefillingCourse = false;
	self.cp.hasTransferCourse = false
	courseplay:setStopAtEnd(self, false);
	self.cp.stopAtEndMode1 = false;
	self.cp.isTipping = false;
	self.cp.isUnloaded = false;
	self.cp.prevFillLevelPct = nil;
	self.cp.isInRepairTrigger = nil;
	self.cp.curMapWeightStation = nil;
	courseplay:setSlippingStage(self, 0);
	courseplay:resetCustomTimer(self, 'slippingStage1');
	courseplay:resetCustomTimer(self, 'slippingStage2');

	courseplay:resetCustomTimer(self, 'foldBaleLoader', true);

	self.cp.hasBaleLoader = false;
	self.cp.hasPlow = false;
	self.cp.rotateablePlow = nil;
	self.cp.hasSowingMachine = false;
	self.cp.hasSprayer = false;
	if self.cp.tempToolOffsetX ~= nil then
		courseplay:changeToolOffsetX(self, nil, self.cp.tempToolOffsetX, true);
		self.cp.tempToolOffsetX = nil
	end;
	if self.cp.manualWorkWidth ~= nil then
		courseplay:changeWorkWidth(self, nil, self.cp.manualWorkWidth, true)
		if self.cp.hud.currentPage == courseplay.hud.PAGE_COURSE_GENERATION then
			courseplay.hud:setReloadPageOrder(self, self.cp.hud.currentPage, true);
		end
	end
	
	self.cp.totalLength, self.cp.totalLengthOffset = 0, 0;
	self.cp.numWorkTools = 0;

	self.cp.movingToolsPrimary, self.cp.movingToolsSecondary = nil, nil;
	self.cp.attachedFrontLoader = nil

	courseplay:deleteFixedWorldPosition(self);

	--remove any local and global info texts
	if g_server ~= nil then
		courseplay:setInfoText(self, nil);

		for refIdx,_ in pairs(CpManager.globalInfoText.msgReference) do
			if self.cp.activeGlobalInfoTexts[refIdx] ~= nil then
				CpManager:setGlobalInfoText(self, refIdx, true);
			end;
		end;
	end
	
	-- remove ingame map hotspot
	if CpManager.ingameMapIconActive then
		courseplay:deleteMapHotspot(self);
	end;

	self:requestActionEventUpdate() 
	
	--remove from activeCoursePlayers
	CpManager:removeFromActiveCoursePlayers(self);

	--validation: can switch mode?
	courseplay:validateCanSwitchMode(self);

	-- reactivate load/add/delete course buttons
	--courseplay.buttons:setActiveEnabled(self, 'page2');
end


function courseplay:findVehicleHeights(transformId, x, y, z, distance)
	local startHeight = math.max(self.sizeLength,5)
	local height = startHeight - distance
	local vehicle = false
	--print(string.format("found %s (%s)",tostring(getName(transformId)),tostring(transformId)))
	-- if self.cp.aiTrafficCollisionTrigger == transformId then
	if self.aiTrafficCollisionTrigger == transformId then	
		if self.cp.HeightsFoundColli < height then
			self.cp.HeightsFoundColli = height
		end
	elseif transformId == self.rootNode then
		vehicle = true
	elseif getParent(transformId) == self.rootNode and self.aiTrafficCollisionTrigger ~= transformId then
		vehicle = true
	elseif self.cpTrafficCollisionIgnoreList[transformId] or self.cpTrafficCollisionIgnoreList[getParent(transformId)] then
		vehicle = true
	end

	if vehicle and self.cp.HeightsFound < height then
		self.cp.HeightsFound = height
	end

	return true
end

function courseplay:checkSaveFuel(vehicle,allowedToDrive)
	if (not vehicle.cp.saveFuelOptionActive) 
	or (vehicle.cp.mode == courseplay.MODE_COMBI and vehicle.cp.activeCombine ~= nil)
	or (vehicle.cp.mode == courseplay.MODE_FIELDWORK and ((vehicle.courseplayers ~= nil and #vehicle.courseplayers > 0) or vehicle.cp.convoyActive))
	or ((vehicle.cp.mode == courseplay.MODE_LIQUIDMANURE_TRANSPORT or vehicle.cp.mode == courseplay.MODE_OVERLOADER) and vehicle.Waypoints[vehicle.cp.previousWaypointIndex].wait)
	then
		if vehicle.cp.saveFuel then
			vehicle.cp.saveFuel = false
		end
		courseplay:resetCustomTimer(vehicle,'fuelSaveTimer',true)
		return
	end
	
	if allowedToDrive then
		if courseplay:getCustomTimerExists(vehicle,'fuelSaveTimer')  then 
			--print("reset existing timer")
			courseplay:resetCustomTimer(vehicle,'fuelSaveTimer',true)
		end
		if vehicle.cp.saveFuel then
			--print("reset saveFuel")
			vehicle.cp.saveFuel = false
		end	
	else
		-- set fuel save timer
		if not vehicle.cp.saveFuel then
			if courseplay:timerIsThrough(vehicle,'fuelSaveTimer',false) then
				--print(" timer is throught and not nil")
				--print("set saveFuel")
				vehicle.cp.saveFuel = true
			elseif courseplay:timerIsThrough(vehicle,'fuelSaveTimer') then
				--print(" set timer ")
				courseplay:setCustomTimer(vehicle,'fuelSaveTimer',30)
			end
		end
	end
end

function courseplay:safeSetWaypointIndex( vehicle, newIx )
	for i = newIx, newIx do
		-- don't set it too close to a turn start, 
		if vehicle.Waypoints[ i ] ~= nil and vehicle.Waypoints[ i ].turnStart then
			-- set it to after the turn
			newIx = i + 2
			break
		end	
	end

	if vehicle.cp.waypointIndex > vehicle.cp.numWaypoints then
		courseplay:setWaypointIndex(vehicle, 1);
	else
		courseplay:setWaypointIndex( vehicle, newIx );
	end
end

-- do not remove this comment
-- vim: set noexpandtab:

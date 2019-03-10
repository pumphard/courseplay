-- file for the helper functions of CombineUnloadAIDriver

function CombineUnloadAIDriver:getTargetFillNode(tipper)
	--print("CombineUnloadAIDriver:getTargetFillNode(tipper)")
	local targetPoint;
	for fillUnitIndex, _ in ipairs(tipper.spec_fillUnit.fillUnits) do 
		local freeSpace = tipper:getFillUnitFreeCapacity(fillUnitIndex, tipper.cp.fillType, tipper:getOwnerFarmId())
		if freeSpace > 0 then
			targetPoint = tipper:getFillUnitAutoAimTargetNode(fillUnitIndex)
			local exactFillRootNode = tipper:getFillUnitExactFillRootNode(fillUnitIndex)
			if targetPoint == nil then
				targetPoint = exactFillRootNode
			end
		end
	end
	--print("  -> return targetPoint "..tostring(targetPoint))
	return targetPoint
end

function CombineUnloadAIDriver:getChoppersTargetUnloadingCoords()
	--print("CombineUnloadAIDriver:getTargetUnloadingCoords(vehicle, combine)")
	local vehicle, combine = self.vehicle,self.combineToUnload 
	local sourceRootNode = combine.cp.DirectionNode or combine.rootNode;
	--local _, _, prnToCombineZ = localToLocal(combine.spec_dischargeable.currentRaycastDischargeNode.node,sourceRootNode, 0,0,0);
	local prnToCombineZ = 0
	
	--this is the offset from my directionNode to the trailers fillNode
	local _, _, trailerOffset = localToLocal(self:getTargetFillNode(self.currentTipper),vehicle.cp.DirectionNode, 0, 0, 0);
	local goBehindMe = false
	
	--set the target 5 meter in front of the tractor, it will never get there
	local ttX, _, ttZ = localToWorld(sourceRootNode, vehicle.cp.combineOffset, 0, -trailerOffset + 5);
	
	-- when target is not on field let he tractor drive behind me
	if not courseplay:isField(ttX, ttZ) then
		goBehindMe = true
		--aim for a point some distance behind the directionNode, so it looks better while driving curves
		--TODO: maybe we have to automatise the distance for smaller\bigger choppers
		ttX, _, ttZ = localToWorld(sourceRootNode,0, 0, -3);
	end
		
	--just Debug
	local x, y, z = getWorldTranslation( vehicle.cp.DirectionNode);
	--cpDebug:drawLine(x, y+3 , z, 100, 0, 100, ttX, y+3, ttZ)
	
	--print(" -> return ttX, ttZ : "..tostring(ttX)..", "..tostring(ttZ))
	--return the target coords, the offest DirectionNode->trailer fillNode , and the ZDistance of the pipeRaycatNode -> combines directionNode and whether I have to go bedind the chopper or beside
	return ttX, ttZ, trailerOffset, prnToCombineZ, goBehindMe;
end;

function CombineUnloadAIDriver:getSpeedBesideChopper(combine,trailerZOffset,combineZOffset)
	local allowedToDrive = true
	local speed = self.vehicle.cp.speeds.field
	local sourceRootNode = combine.cp.DirectionNode or combine.rootNode;
	--local raycastNode = combine.spec_dischargeable.currentRaycastDischargeNode.node
	local rNX,rNY,rNZ = getWorldTranslation(sourceRootNode) --local rNX,rNY,rNZ = getWorldTranslation(raycastNode)
	local diffX, _, diffZ = worldToLocal(self.vehicle.cp.DirectionNode,rNX,rNY,rNZ);
	diffZ = diffZ - trailerZOffset + combineZOffset
	if math.abs(diffZ) < 5 and math.abs(diffX) < 2 then
		speed = combine.lastSpeedReal * 3600 + diffZ
	end
	
	renderText(0.2, 0.105, 0.02, string.format("diffZ: %s",tostring(diffZ)));
	
	return allowedToDrive,speed
end

function CombineUnloadAIDriver: getSpeedBehindChopper(chopper)
	local allowedToDrive = true
	local safetyDistance = 2
	local raycastDistance = 10
	local speed = self.vehicle.cp.speeds.field
	--if not self.ownRaycastOffset then
		self:raycastOwnDistance()
	--end	
	self:raycast(raycastDistance)
	local distanceDiff = self.distanceToObject - safetyDistance
	
	if math.abs(distanceDiff) < raycastDistance then
		speed = math.min(speed,chopper.lastSpeedReal * 3600 + distanceDiff)
	end
	renderText(0.2, 0.075, 0.02, string.format("self.distanceToObject: %s, self.ownRaycastOffset:%s",tostring(self.distanceToObject),tostring(self.ownRaycastOffset)));
	return allowedToDrive,speed

end

function CombineUnloadAIDriver:raycastOwnDistance()
	local nx, ny, nz = localDirectionToWorld(self.vehicle.cp.DirectionNode, 0, 0, -1)
	local x, y, z = localToWorld(self.vehicle.cp.DirectionNode, 0, 1, 10)
	--cpDebug:drawLine(x, y, z, 100, 000, 100, x+(nx*10), y+(ny*10), z+(nz*10))
	raycastClosest(x, y, z, nx, ny, nz, 'raycastCallback', 10, self,202042)
end

function CombineUnloadAIDriver:raycast(distance)
	local nx, ny, nz = localDirectionToWorld(self.vehicle.cp.DirectionNode, 0, 0, 1)
	local x, y, z = localToWorld(self.vehicle.cp.DirectionNode, 0, 1.5, self.ownRaycastOffset or 0)
	cpDebug:drawLine(x, y, z, 100, 100, 100, x+(nx*distance), y+(ny*distance), z+(nz*distance))
	raycastClosest(x, y, z, nx, ny, nz, 'raycastCallback', distance, self)
end

function CombineUnloadAIDriver:raycastCallback(hitObjectId, x, y, z, distance, nx, ny, nz, subShapeIndex)
	--print(string.format("raycastCallback: Id:%s, distance:%s",tostring(hitObjectId),tostring(distance)))
	if hitObjectId ~= 0 then
		--print("hitObjectId ~= 0")
		local object = g_currentMission:getNodeObject(hitObjectId)
		--print("object = "..tostring(object))
		if object and (object == self.vehicle  or (object.getAttacherVehicle and object:getAttacherVehicle() == self.vehicle)) then
			self.ownRaycastOffset = 10 - distance
			--print("set ownRaycastOffset to %s"..tostring(self.ownRaycastOffset))
		elseif object and object == self.combineToUnload  then
			self.distanceToObject = distance
		end
	end
	return true
end

function CombineUnloadAIDriver:getIsCombineTurning(combine)
	local driveableComponent = (combine.getAttacherVehicle and combine:getAttacherVehicle()) or combine
	local aiTurn = driveableComponent.spec_aiVehicle and driveableComponent.spec_aiVehicle.isTurning	
	local cpTurn = driveableComponent.cp.turnStage > 0
	return  aiTurn or cpTurn
end






------------------------------------------------
function CombineUnloadAIDriver:calculateCombineOffset(vehicle, combine) --obsolete version to be deleted when all the code is transfered
	local curFile = "mode2.lua";
	local offs = vehicle.cp.combineOffset
	local offsPos = math.abs(vehicle.cp.combineOffset)
	local combineDirNode = combine.cp.DirectionNode or combine.rootNode;
	
	local prnX,prnY,prnZ, prnwX,prnwY,prnwZ, combineToPrnX,combineToPrnY,combineToPrnZ = 0,0,0, 0,0,0, 0,0,0;
	if combine.spec_dischargeable ~= nil then
		prnX, prnY, prnZ = getTranslation(combine.spec_dischargeable.currentRaycastDischargeNode.node)
		prnwX, prnwY, prnwZ = getWorldTranslation(combine.spec_dischargeable.currentRaycastDischargeNode.node)
		combineToPrnX, combineToPrnY, combineToPrnZ = worldToLocal(combineDirNode, prnwX, prnwY, prnwZ)

		if combine.cp.pipeSide == nil then
			courseplay:getCombinesPipeSide(combine)
		end
	end;

	--special tools, special cases
	local specialOffset = courseplay:getSpecialCombineOffset(combine);
	if vehicle.cp.combineOffsetAutoMode and specialOffset then
		offs = specialOffset;
	
	--Sugarbeet Loaders (e.g. Ropa Euro Maus, Holmer Terra Felis) --TODO (Jakob): theoretically not needed, as it's being dealt with in getSpecialCombineOffset()
	elseif vehicle.cp.combineOffsetAutoMode and combine.cp.isSugarBeetLoader then
		local utwX,utwY,utwZ = getWorldTranslation(combine.pipeRaycastNode or combine.unloadingTrigger.node);
		local combineToUtwX,_,combineToUtwZ = worldToLocal(combineDirNode, utwX,utwY,utwZ);
		offs = combineToUtwX;

	--combine // combine_offset is in auto mode, pipe is open
	elseif not combine.cp.isChopper and vehicle.cp.combineOffsetAutoMode and combine.pipeCurrentState == 2 and combine.spec_dischargeable.currentRaycastDischargeNode.node ~= nil then --pipe is open
		local raycastNodeParent = getParent(combine.spec_dischargeable.currentRaycastDischargeNode.node);
		if raycastNodeParent == combine.rootNode then -- pipeRaycastNode is direct child of combine.root
			--safety distance so the trailer doesn't crash into the pipe (sidearm)
			local additionalSafetyDistance = 0;
			if combine.cp.isGrimmeTectron415 then
				additionalSafetyDistance = -0.5;
			end;

			offs = prnX + additionalSafetyDistance;
			--courseplay:debug(string.format("%s(%i): %s @ %s: root > pipeRaycastNode // offs = %f", curFile, debug.getinfo(1).currentline, vehicle.name, combine.name, offs), 4)
		elseif getParent(raycastNodeParent) == combine.rootNode then --pipeRaycastNode is direct child of pipe is direct child of combine.root
			local pipeX, pipeY, pipeZ = getTranslation(raycastNodeParent)
			offs = pipeX - prnZ;
			
			if prnZ == 0 or combine.cp.isGrimmeRootster604 then
				offs = pipeX - prnY;
			end;
			--courseplay:debug(string.format("%s(%i): %s @ %s: root > pipe > pipeRaycastNode // offs = %f", curFile, debug.getinfo(1).currentline, vehicle.name, combine.name, offs), 4)
		elseif combine.pipeRaycastNode ~= nil then --BACKUP pipeRaycastNode isn't direct child of pipe
			offs = combineToPrnX + 0.5;
			--courseplay:debug(string.format("%s(%i): %s @ %s: combineToPrnX // offs = %f", curFile, debug.getinfo(1).currentline, vehicle.name, combine.name, offs), 4)
		elseif combine.cp.lmX ~= nil then --user leftMarker
			offs = combine.cp.lmX + 2.5;
		else --if all else fails
			offs = 8;
		end;

	--combine // combine_offset is in manual mode
	elseif not combine.cp.isChopper and not vehicle.cp.combineOffsetAutoMode and combine.spec_dischargeable.currentRaycastDischargeNode.node ~= nil then
		offs = offsPos * combine.cp.pipeSide;
		--courseplay:debug(string.format("%s(%i): %s @ %s: [manual] offs = offsPos * pipeSide = %s * %s = %s", curFile, debug.getinfo(1).currentline, vehicle.name, combine.name, tostring(offsPos), tostring(combine.cp.pipeSide), tostring(offs)), 4);
	
	--combine // combine_offset is in auto mode
	elseif not combine.cp.isChopper and vehicle.cp.combineOffsetAutoMode and combine.pipeRaycastNode ~= nil then
		offs = offsPos * combine.cp.pipeSide;
		--courseplay:debug(string.format("%s(%i): %s @ %s: [auto] offs = offsPos * pipeSide = %s * %s = %s", curFile, debug.getinfo(1).currentline, vehicle.name, combine.name, tostring(offsPos), tostring(combine.cp.pipeSide), tostring(offs)), 4);

	--chopper // combine_offset is in auto mode
	elseif combine.cp.isChopper and vehicle.cp.combineOffsetAutoMode then
		if combine.cp.lmX ~= nil then
			offs = math.max(combine.cp.lmX + 2.5, 7);
		else
			offs = 8;
		end;
		courseplay:sideToDrive(vehicle, combine, 10);
			
		if vehicle.sideToDrive ~= nil then
			if vehicle.sideToDrive == "left" then
				offs = math.abs(offs);
			elseif vehicle.sideToDrive == "right" then
				offs = math.abs(offs) * -1;
			end;
		end;
	end;
	
	--cornChopper forced side offset
	if combine.cp.isChopper and combine.cp.forcedSide ~= nil then
		if combine.cp.forcedSide == "left" then
			offs = math.abs(offs);
		elseif combine.cp.forcedSide == "right" then
			offs = math.abs(offs) * -1;
		end
		--courseplay:debug(string.format("%s(%i): %s @ %s: cp.forcedSide=%s => offs=%f", curFile, debug.getinfo(1).currentline, vehicle.name, combine.name, combine.cp.forcedSide, offs), 4)
	end

	--refresh for display in HUD and other calculations
	vehicle.cp.combineOffset = offs;
end;

function CombineUnloadAIDriver:calculateVerticalOffset(vehicle, combine)
	local cwX, cwY, cwZ = getWorldTranslation( combine.spec_dischargeable.currentRaycastDischargeNode.node);
	local _, _, prnToCombineZ = worldToLocal(combine.cp.DirectionNode or combine.rootNode, cwX, cwY, cwZ);
	
	return prnToCombineZ;
end;




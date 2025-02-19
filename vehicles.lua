local abs, max, rad, deg, cos, sin, ceil = math.abs, math.max, math.rad, math.deg, math.cos, math.sin, math.ceil;
local _;
local truckAttacherJoint = {};
-- ##### VEHICLE TOOLS ##### --
courseplay.attacherJointNodeRotationList = {};

function courseplay:calculateTurnRadius(type, wheelBase, rotMax, CPRatio)
	local turnRadius = 0;
	CPRatio = CPRatio or 0;

	-- ArticulatedAxis Steering
	if (type == "ASW" or type == "Tool") and CPRatio > 0 and CPRatio < 1  then
		if CPRatio <= 0.5 then
			turnRadius = wheelBase * (1-CPRatio) / sin(rotMax) * (CPRatio * cos(rotMax) + 1 - CPRatio);
		else
			turnRadius = wheelBase * CPRatio / sin(rotMax) * (CPRatio + (1 - CPRatio) * cos(rotMax));
		end;

		-- 4 Wheel Steering
	elseif type == "4WS" then
		turnRadius = wheelBase / (2 * sin(rotMax)) * cos(rotMax);

		-- 2 Wheel Steering
	elseif (type == "2WS" or type == "Tool") then
		turnRadius = wheelBase / sin(rotMax) * cos(rotMax);
	end;

	return turnRadius;
end;

function courseplay:createNewLinkedNode(object, nodeName, linkToNode)
	if not object.cp.notesToDelete then object.cp.notesToDelete = {}; end;

	local node = createTransformGroup(nodeName);
	link(linkToNode, node);
	table.insert(object.cp.notesToDelete, 1, node);

	return node;
end;



function courseplay:disableCropDestruction(vehicle)
	-- Make sure we have the cp table
	if vehicle.cp == nil then vehicle.cp = {}; end;

	-- Disable crop destruction if enabled
	if vehicle.cropDestruction then
		vehicle.cp.cropDestructionIsActiveBackup = vehicle.cropDestruction.isActive;
		vehicle.cropDestruction.isActive = false;
	end;

	-- CHECK ATTACHED IMPLEMENTS
	for _,impl in pairs(vehicle:getAttachedImplements()) do
		courseplay:disableCropDestruction(impl.object);
	end;
end;

function courseplay:enableCropDestruction(vehicle)
	-- Enable crop destruction if backup is set
	if vehicle.cropDestruction and vehicle.cp and vehicle.cp.cropDestructionIsActiveBackup ~= nil then
		vehicle.cropDestruction.isActive = vehicle.cp.cropDestructionIsActiveBackup;
		vehicle.cp.cropDestructionIsActiveBackup = nil;
	end;

	-- CHECK ATTACHED IMPLEMENTS
	for _,impl in pairs(vehicle:getAttachedImplements()) do
		courseplay:enableCropDestruction(impl.object);
	end;
end;

--- courseplay:findJointNodeConnectingToNode(workTool, fromNode, toNode, doReverse)
--	Returns: (node, backtrack, rotLimits)
--		node will return either:		1. The jointNode that connects to the toNode,
--										2. The toNode if no jointNode is found but the fromNode is inside the same component as the toNode
--										3. nil in case none of the above fails.
--		backTrack will return either:	1. A table of all the jointNodes found from fromNode to toNode, if the jointNode that connects to the toNode is found.
--										2: nil if no jointNode is found.
--		rotLimits will return either:	1. A table of all the rotLimits of the componentJoint, found from fromNode to toNode, if the jointNode that connects to the toNode is found.
--										2: nil if no jointNode is found.
function courseplay:findJointNodeConnectingToNode(workTool, fromNode, toNode, doReverse)
	if fromNode == toNode then return toNode; end;

	-- Attempt to find the jointNode by backtracking the compomentJoints.
	for index, component in ipairs(workTool.components) do
		if courseplay:isPartOfNode(fromNode, component.node) then
			if not doReverse then
				for _, joint in ipairs(workTool.componentJoints) do
					if joint.componentIndices[2] == index then
						if workTool.components[joint.componentIndices[1]].node == toNode then
							--          node            backtrack         rotLimits
							return joint.jointNode, {joint.jointNode}, {joint.rotLimit};
						else
							local node, backTrack, rotLimits = courseplay:findJointNodeConnectingToNode(workTool, workTool.components[joint.componentIndices[1]].node, toNode);
							if backTrack then table.insert(backTrack, 1, joint.jointNode); end;
							if rotLimits then table.insert(rotLimits, 1, joint.rotLimit); end;
							return node, backTrack, rotLimits;
						end;
					end;
				end;
			end;

			-- Do Reverse in case not found
			for _, joint in ipairs(workTool.componentJoints) do
				if joint.componentIndices[1] == index then
					if workTool.components[joint.componentIndices[2]].node == toNode then
						--          node            backtrack         rotLimits
						return joint.jointNode, {joint.jointNode}, {joint.rotLimit};
					else
						local node, backTrack, rotLimits = courseplay:findJointNodeConnectingToNode(workTool, workTool.components[joint.componentIndices[2]].node, toNode, true);
						if backTrack then table.insert(backTrack, 1, joint.jointNode); end;
						if rotLimits then table.insert(rotLimits, 1, joint.rotLimit); end;
						return node, backTrack, rotLimits;
					end;
				end;
			end;
		end;
	end;

	-- Last attempt to find the jointNode by getting parent of parent untill hit or the there is no more parents.
	if courseplay:isPartOfNode(fromNode, toNode) then
		return toNode, nil;
	end;

	-- If anything else fails, return nil
	return nil, nil;
end;

function courseplay:getDistances(object)
	if not object.cp.distances then
		cpPrintLine(6);
		local distances = {};

		-- STEERABLES
		if object.cp.DirectionNode then
			-- Finde the front and rear distance from the direction node
			local front, rear = 0, 0;
			local haveRunnedOnce = false
			for _, wheel in ipairs(object:getWheels()) do
				local wdnrxTemp, wdnryTemp, wdnrzTemp = getRotation(wheel.driveNode);
				setRotation(wheel.driveNode, 0, 0, 0);
				local wreprxTemp, wrepryTemp, wreprzTemp = getRotation(wheel.repr);
				setRotation(wheel.repr, 0, 0, 0);
				local xw, yw, zw = getWorldTranslation(wheel.driveNode);
				local _,_,dis = worldToLocal(object.cp.DirectionNode, xw, yw, zw);
				setRotation(wheel.repr, wreprxTemp, wrepryTemp, wreprzTemp);
				setRotation(wheel.driveNode, wdnrxTemp, wdnryTemp, wdnrzTemp);
				if haveRunnedOnce then
					if dis < rear then rear = dis; end;
					if dis > front then front = dis; end;
				else
					rear = dis;
					front = dis;
					haveRunnedOnce = true;
				end;
			end;
			-- Set the wheel offset anddistance
			distances.frontWheelToDirectionNodeOffset = front * -1;
			distances.frontWheelToRearWheel = abs(front - rear);
			courseplay:debug(('%s: frontWheelToDirectionNodeOffset=%.2f, frontWheelToRearWheel=%.2f'):format(nameNum(object), distances.frontWheelToDirectionNodeOffset, distances.frontWheelToRearWheel), 6);

			-- Finde the attacherJoints distance from the direction node
			for _, attacherJoint in ipairs(object.spec_attacherJoints.attacherJoints) do
				local xj, yj, zj = getWorldTranslation(attacherJoint.jointTransform);
				local _,_,dis = worldToLocal(object.cp.DirectionNode, xj, yj, zj);
				if dis < front then
					if not distances.frontWheelToRearTrailerAttacherJoints then
						distances.frontWheelToRearTrailerAttacherJoints = {};
					end;
					distances.frontWheelToRearTrailerAttacherJoints[attacherJoint.jointType] = abs(front - dis);
					courseplay:debug(('%s: frontWheelToRearTrailerAttacherJoints[%d]=%.2f'):format(nameNum(object), attacherJoint.jointType, distances.frontWheelToRearTrailerAttacherJoints[attacherJoint.jointType]), 6);
				end;
			end

			-- Finde the attacherJoints distance from the turning node
			local turningNode = courseplay:getRealTurningNode(object);
			for _, attacherJoint in ipairs(object.spec_attacherJoints.attacherJoints) do
				local xj, yj, zj = getWorldTranslation(attacherJoint.jointTransform);
				local _, _, deltaZ = worldToLocal(object.cp.DirectionNode, xj, yj, zj);

				-- If we are behind the front wheel, then it should be an attacherJoing on the rear
				if deltaZ < front then
					local _,_,dis = worldToLocal(turningNode, xj, yj, zj);
					dis = dis * -1;
					if not distances.turningNodeToRearTrailerAttacherJoints then
						distances.turningNodeToRearTrailerAttacherJoints = {};
					end;
					distances.turningNodeToRearTrailerAttacherJoints[attacherJoint.jointType] = dis;
					courseplay:debug(('%s: turningNodeToRearTrailerAttacherJoints[%d]=%.2f'):format(nameNum(object), attacherJoint.jointType, distances.turningNodeToRearTrailerAttacherJoints[attacherJoint.jointType]), 6);
				end;
			end

		-- IMPLEMENTS OR TRAILERS
		else
			local activeInputAttacherJoint = object:getActiveInputAttacherJoint();
			local node = activeInputAttacherJoint.node;
			local isHookLift = courseplay:isHookLift(object);
			local lastNode = courseplay:getLastComponentNodeWithWheels(object)

			if activeInputAttacherJoint.rootNode ~= lastNode and not isHookLift then
				local tempNode, backTrack, rotLimits = courseplay:findJointNodeConnectingToNode(object, activeInputAttacherJoint.rootNode, lastNode);
				if tempNode and backTrack then
					node = tempNode;
					local nodeLength = 0;
					local isPivoted = false;
					for i = 1, #backTrack do
						if rotLimits ~= nil and rotLimits[i]~= nil and rotLimits[i][2] ~= nil and rotLimits[i][2] > rad(15) then
							isPivoted = true;
						end;

						if i == 1 then
							tempNode = activeInputAttacherJoint.node;
						else
							tempNode = backTrack[i-1];
						end;

						local tmpnx, tmpny, tmpnz = getWorldTranslation(tempNode);
						local _,_,dis = worldToLocal(backTrack[i], tmpnx, tmpny, tmpnz);

						courseplay:debug(('%s: backTrack[%d](node: %s) Length = %.2f'):format(nameNum(object), i, tostring(backTrack[i]), abs(dis)), 6);
						nodeLength = nodeLength + abs(dis);
					end;

					if isPivoted then
						distances.attacherJointToPivot = nodeLength;
						courseplay:debug(('%s: attacherJointToPivot=%.2f'):format(nameNum(object), distances.attacherJointToPivot), 6);
					else
						distances.attacherJointToLastMovingPart = nodeLength;
						courseplay:debug(('%s: attacherJointToLastMovingPart=%.2f'):format(nameNum(object), distances.attacherJointToLastMovingPart), 6);
					end;
				end;
			end;

			-- backup node rotation and set the rotation to 0
			local nodeXTemp, nodeYTemp, nodeZTemp = getRotation(node);
			setRotation(node, 0, 0, 0);

			-- Find the distance from attacherJoint to rear wheel
			local objectWheels = object:getWheels();
			if objectWheels and #objectWheels > 0 and not isHookLift then
				local length = 0;
				for _, wheel in ipairs(objectWheels) do
					if wheel.maxLatStiffnessLoad > 0.5 then
						local nx, ny, nz = getWorldTranslation(wheel.driveNode);
						local _,_,dis = worldToLocal(node, nx, ny, nz);

						if abs(dis) > length then
							length = abs(dis);
						end;
					end;
				end;

				if distances.attacherJointToPivot then
					distances.pivotToRearWheel = length;
					distances.attacherJointToRearWheel = distances.attacherJointToPivot + length;
				elseif distances.attacherJointToLastMovingPart then
					distances.attacherJointToRearWheel = distances.attacherJointToLastMovingPart + length;
				else
					distances.attacherJointToRearWheel = length;
				end;

				courseplay:debug(('%s: attacherJointToRearWheel=%.2f'):format(nameNum(object), distances.attacherJointToRearWheel), 6);
			end;

			-- Finde the attacherJoints distance from the direction node
			for _, attacherJoint in ipairs(object.spec_attacherJoints.attacherJoints) do
				local nx, ny, nz = getWorldTranslation(attacherJoint.jointTransform);
				local _,_,dis = worldToLocal(node, nx, ny, nz);
				dis = dis * -1;

				if dis > 0 then
					if not distances.attacherJointToRearTrailerAttacherJoints then
						distances.attacherJointToRearTrailerAttacherJoints = {};
					end;

					if distances.attacherJointToPivot then
						if not distances.pivotToRearTrailerAttacherJoints then
							distances.pivotToRearTrailerAttacherJoints = {};
						end;
						distances.pivotToRearTrailerAttacherJoints[attacherJoint.jointType] = dis;
						distances.attacherJointToRearTrailerAttacherJoints[attacherJoint.jointType] = distances.attacherJointToPivot + dis;
					elseif distances.attacherJointToLastMovingPart then
						distances.attacherJointToRearTrailerAttacherJoints[attacherJoint.jointType] = distances.attacherJointToLastMovingPart + dis;
					else
						distances.attacherJointToRearTrailerAttacherJoints[attacherJoint.jointType] = dis;
					end;

					courseplay:debug(('%s: attacherJointToRearTrailerAttacherJoints[%d]=%.2f'):format(nameNum(object), attacherJoint.jointType, distances.attacherJointToRearTrailerAttacherJoints[attacherJoint.jointType]), 6);
				end;
			end;

			if distances.attacherJointToRearWheel then
				local turningNode = courseplay:getRealTurningNode(object);
				-- Finde the attacherJoints distance from the turning node
				for _, attacherJoint in ipairs(object.spec_attacherJoints.attacherJoints) do
					local nx, ny, nz = getWorldTranslation(attacherJoint.jointTransform);
					local _,_,dis = worldToLocal(turningNode, nx, ny, nz);
					dis = dis * -1;

					if not distances.turningNodeToTrailerAttacherJoints then
						distances.turningNodeToTrailerAttacherJoints = {};
					end;

					distances.turningNodeToTrailerAttacherJoints[attacherJoint.jointType] = dis;

					courseplay:debug(('%s: turningNodeToTrailerAttacherJoints[%d]=%.2f'):format(nameNum(object), attacherJoint.jointType, distances.turningNodeToTrailerAttacherJoints[attacherJoint.jointType]), 6);
				end;

				-- Finde the attacherJoint/Pivot distance to the turning node
				local nx, ny, nz = getWorldTranslation(node);
				local _,_,dis = worldToLocal(turningNode, nx, ny, nz);
				if distances.attacherJointToLastMovingPart then
					distances.attacherJointOrPivotToTurningNode = distances.attacherJointToLastMovingPart + dis;
				else
					distances.attacherJointOrPivotToTurningNode = dis;
				end;
				courseplay:debug(('%s: attacherJointOrPivotToTurningNode=%.2f'):format(nameNum(object), distances.attacherJointOrPivotToTurningNode), 6);

			end;

			-- restore node rotation from backup.
			setRotation(node, nodeXTemp, nodeYTemp, nodeZTemp);
		end;

		object.cp.distances = distances;
	end;

	return object.cp.distances;
end;

function courseplay:getDirectionNodeToTurnNodeLength(vehicle)
	--- This is in case vehicle is a tool and CP havent been set on it
	if not vehicle.cp then
		vehicle.cp = {};
	end;

	local totalDistance = 0;

	--- If this have not been set before after last stop command, we need to reset it again.
	-- This also prevents from this code to calculate each loop while we are turning and can save CPU usage
	if not vehicle.cp.directionNodeToTurnNodeLength then
		local distances = vehicle.cp.distances;

		for _, imp in ipairs(vehicle:getAttachedImplements()) do
			if courseplay:isRearAttached(vehicle, imp.jointDescIndex) then
				local workTool = imp.object;
				local activeInputAttacherJoint = workTool:getActiveInputAttacherJoint();
				if courseplay:isWheeledWorkTool(workTool) then
					local workToolDistances = workTool.cp.distances;

					if workToolDistances.attacherJointToPivot then
						totalDistance = totalDistance + workToolDistances.attacherJointToPivot;
						courseplay:debug(('getDirectionNodeToTurnNodeLength() -> %s: attacherJointToPivot=%.2fm'):format(nameNum(workTool), workToolDistances.attacherJointToPivot), 14);
					end;

					totalDistance = totalDistance + workToolDistances.attacherJointOrPivotToTurningNode;
					courseplay:debug(('getDirectionNodeToTurnNodeLength() -> %s: attacherJointOrPivotToTurningNode=%.2fm'):format(nameNum(workTool), workToolDistances.attacherJointOrPivotToTurningNode), 14);
					courseplay:debug(('getDirectionNodeToTurnNodeLength() -> %s: attacherJointToTurningNode=%.2fm'):format(nameNum(workTool), totalDistance), 14);
				else
					if not distances.attacherJointOrPivotToTurningNode and distances.attacherJointToRearTrailerAttacherJoints then
						totalDistance = totalDistance + distances.attacherJointToRearTrailerAttacherJoints[activeInputAttacherJoint.jointType];
					end;
					totalDistance = totalDistance + courseplay:getDirectionNodeToTurnNodeLength(workTool);
					--courseplay:debug(('%s: directionNodeToTurnNodeLength=%.2fm'):format(nameNum(workTool), totalDistance), 14);
				end;
				break;
			end;
		end;

		if vehicle.cp.DirectionNode and totalDistance > 0 then
			for _, imp in ipairs(vehicle:getAttachedImplements()) do
				if courseplay:isRearAttached(vehicle, imp.jointDescIndex) then
					local workTool = imp.object;
					local activeInputAttacherJoint = workTool:getActiveInputAttacherJoint();
					totalDistance = totalDistance + distances.turningNodeToRearTrailerAttacherJoints[activeInputAttacherJoint.jointType];
					break;
				end;
			end;
			vehicle.cp.directionNodeToTurnNodeLength = totalDistance;
			courseplay:debug(('getDirectionNodeToTurnNodeLength() -> %s: directionNodeToTurnNodeLength=%.2fm'):format(nameNum(vehicle), totalDistance), 14);
		end;
	end;

	return vehicle.cp.directionNodeToTurnNodeLength or totalDistance;
end;

function courseplay:getRealDollyFrontNode(dolly)
	if dolly.cp.realDollyFrontNode == nil then
		local activeInputAttacherJoint = dolly:getActiveInputAttacherJoint();
		local node, _ = courseplay:findJointNodeConnectingToNode(dolly, activeInputAttacherJoint.rootNode, dolly.rootNode);
		if node then
			-- Trailers without pivote
			if (node == dolly.rootNode and activeInputAttacherJoint.jointType ~= AttacherJoints.JOINTTYPE_IMPLEMENT)
					-- Implements with pivot and wheels that do not lift the wheels from the ground.
					or (node ~= dolly.rootNode and activeInputAttacherJoint.jointType == AttacherJoints.JOINTTYPE_IMPLEMENT and not activeInputAttacherJoint.topReferenceNode) then
				dolly.cp.realDollyFrontNode = courseplay:getRealTurningNode(dolly);
			else
				dolly.cp.realDollyFrontNode = false;
			end;
		end;
	end;

	return dolly.cp.realDollyFrontNode
end;

function courseplay:getRealTrailerDistanceToPivot(workTool)
	-- Attempt to find the pivot node.
	local activeInputAttacherJoint = workTool:getActiveInputAttacherJoint();
	local node, backTrack = courseplay:findJointNodeConnectingToNode(workTool, activeInputAttacherJoint.rootNode, courseplay:getLastComponentNodeWithWheels(workTool));
	if node then
		local x,y,z;
		if node == workTool.rootNode then
			x,y,z = getWorldTranslation(activeInputAttacherJoint.node);
		else
			x,y,z = getWorldTranslation(node);
		end;
		local _,_,tz = worldToLocal(courseplay:getRealTurningNode(workTool), x,y,z);
		return tz;
	else
		return 3;
	end;
end;

function courseplay:getRealTrailerFrontNode(workTool)
	if not workTool.cp.realFrontNode then
		local activeInputAttacherJoint = workTool:getActiveInputAttacherJoint();
		local jointNode, backtrack = courseplay:findJointNodeConnectingToNode(workTool, activeInputAttacherJoint.rootNode, workTool.rootNode);
		if jointNode and backtrack and activeInputAttacherJoint.jointType ~= AttacherJoints.JOINTTYPE_IMPLEMENT then
			local rootNode;
			for _, joint in ipairs(workTool.componentJoints) do
				if joint.jointNode == jointNode and joint.rotLimit~= nil and joint.rotLimit[2] ~= nil and joint.rotLimit[2] > rad(15) then
					rootNode = workTool.components[joint.componentIndices[2]].node;
					break;
				end;
			end;

			if rootNode then
				local node = courseplay:createNewLinkedNode(workTool, "realFrontNode", rootNode);
				local x, y, z = getWorldTranslation(jointNode);
				local _,_,delta = worldToLocal(rootNode, x, y, z);

				setTranslation(node, 0, 0, delta);

				if courseplay:isInvertedToolNode(workTool, node) then
					setRotation(node, 0, rad(180), 0);
				end;

				workTool.cp.realFrontNode = node;
			end;
		end;

		if not workTool.cp.realFrontNode then
			if courseplay:getLastComponentNodeWithWheels(workTool) ~= workTool.rootNode then
				workTool.cp.realFrontNode = courseplay:getRealTurningNode(workTool, workTool.rootNode, "realFrontNode");
			else
				workTool.cp.realFrontNode = courseplay:getRealTurningNode(workTool);
			end;
		end;
	end;

	return workTool.cp.realFrontNode
end;

function courseplay:getRealTurningNode(object, useNode, nodeName)
	if not object.cp.turningNode or useNode then
		local node;  -- Define local value

		local _, y, _ = getWorldTranslation(object.rootNode);
		local minDis, maxDis = 0, 0;
		local minDisRot, maxDisRot = 0, 0;
		local haveStraitWheels, haveTurningWheels = false, false;
		local Distance = 0;

		-- STEERABLES
		if object.cp.DirectionNode then
			-- Giants have provided us with steeringCenterNode, so use it.
			if object.steeringCenterNode then
				-- The steeringCenterNode is already set for us to use.
				node = object.steeringCenterNode;

				-- Check if it's actually an four wheel steering
				if not object.crawlers or #object.crawlers == 0 then
					for index, wheel in ipairs(object:getWheels()) do
						-- Strait wheels
						if wheel.rotMax == 0 and wheel.maxLatStiffness > 0 then
							haveStraitWheels = true;

						-- Turning wheels
						else
							haveTurningWheels = true;
						end;
					end;

					if not haveStraitWheels and haveTurningWheels then
						object.cp.isFourWheelSteering = true;
					end;
				end;
			else
				-- Greate an new linked node.
				node = courseplay:createNewLinkedNode(object, "realTurningNode", object.rootNode);

				-- Find the pivot point on articulated vehicle
				if object.spec_articulatedAxis and object.spec_articulatedAxis.componentJoint then
					local jointNode = object.spec_articulatedAxis.componentJoint.jointNode;
					local x,_,z = getWorldTranslation(jointNode);
					_,_,Distance = worldToLocal(object.rootNode, x, y, z);

				-- Get the distance from root node to the wheels turning point.
				else
					local rotMax = 0;

					-- Sort wheels in turning wheels and strait wheels and find the min and max distance for each set.
					for index, wheel in ipairs(object:getWheels()) do
						local x,_,z = getWorldTranslation(wheel.repr);
						local _,_,dis = worldToLocal(object.rootNode, x, y, z);

						-- Strait wheels
						if wheel.rotMax == 0 and wheel.maxLatStiffness > 0 then
							if haveStraitWheels then
								if dis < minDis then minDis = dis; end;
								if dis > maxDis then maxDis = dis; end;
							else
								minDis = dis;
								maxDis = dis;
								haveStraitWheels = true;
							end;

						-- Turning wheels
						else
							if abs(wheel.rotMax) > rotMax then
								rotMax = abs(wheel.rotMax)
							end;
							if haveTurningWheels then
								if dis < minDisRot then minDisRot = dis; end;
								if dis > maxDisRot then maxDisRot = dis; end;
							else
								minDisRot = dis;
								maxDisRot = dis;
								haveTurningWheels = true;
							end;
						end;
					end;

					-- 2WS: Calculate strait wheel median distance
					if haveStraitWheels then
						if minDis == maxDis then
							Distance = minDis;
						else
							Distance = (minDis + maxDis) * 0.5;
						end;

					-- 4WS: Calculate turning wheel median distance if there are no strait wheels.
					elseif haveTurningWheels then
						object.cp.isFourWheelSteering = true;
						object.cp.fourWheelSteerMaxRot = rotMax;
						if minDisRot == maxDisRot then
							Distance = minDisRot;
						else
							Distance = (minDisRot + maxDisRot) * 0.5;
						end;
					end;
				end;

				if Distance ~= 0 then
					setTranslation(node, 0, 0, Distance);
				end;
			end;

		-- IMPLEMENTS OR TRAILERS
		else
			--local AIReverseNode = object:getAIToolReverserDirectionNode();

			local invert = courseplay:isInvertedToolNode(object) and -1 or 1;
			local steeringAxleScale = 0;

			-- Use useNode or Get the last component node with wheels
			local componentNode = useNode or courseplay:getLastComponentNodeWithWheels(object);

			-- Greate an new linked node based on what component to use or nodeName.
			local transformGroupName = nodeName or "realTurningNode";
			node = courseplay:createNewLinkedNode(object, transformGroupName, componentNode);

			if not useNode and not nodeName then
				--if AIReverseNode then
				--	local x,_,z = getWorldTranslation(AIReverseNode);
				--	local _,_,dis = worldToLocal(componentNode, x, y, z);
				--	Distance = dis * invert;
				--	courseplay:debug(('%s: getRealTurningNode(): Using getAIToolReverserDirectionNode() -> distance = %.2f'):format(nameNum(object), Distance), 6);
				--else
					-- Get the distance from root node to the wheels turning point.
					local objectWheels = object:getWheels();
					if objectWheels and #objectWheels > 0 then
						local steeringAxleScaleMin, steeringAxleScaleMax = 0, 0;

						-- Sort wheels in turning wheels and strait wheels and find the min and max distance for each set.
						for i = 1, #objectWheels do
							if courseplay:isPartOfNode(objectWheels[i].node, componentNode) and objectWheels[i].isLeft ~= nil and objectWheels[i].maxLatStiffnessLoad > 0.5 then
								local x,_,z = getWorldTranslation(objectWheels[i].driveNode);
								local _,_,dis = worldToLocal(componentNode, x, y, z);
								dis = dis * invert;
								courseplay:debug(('%s: getRealTurningNode(): wheel%d distance = %.2f'):format(nameNum(object), i, dis), 6);
								if object.steeringAxleUpdateBackwards == false or object.spec_wheels.wheels[i].steeringAxleScale == 0 then
									if haveStraitWheels then
										if dis < minDis then minDis = dis; end;
										if dis > maxDis then maxDis = dis; end;
									else
										minDis = dis;
										maxDis = dis;
										haveStraitWheels = true;
									end;
								else
									if objectWheels[i].steeringAxleScale < 0 and objectWheels[i].steeringAxleScale < steeringAxleScaleMin then
										steeringAxleScaleMin = object.spec_wheels.wheels[i].steeringAxleScale;
									elseif objectWheels[i].steeringAxleScale > 0 and objectWheels[i].steeringAxleScale > steeringAxleScaleMax then
										steeringAxleScaleMax = objectWheels[i].steeringAxleScale;
									end;
									if haveTurningWheels then
										if dis < minDisRot then minDisRot = dis; end;
										if dis > maxDisRot then maxDisRot = dis; end;
									else
										minDisRot = dis;
										maxDisRot = dis;
										haveTurningWheels = true;
									end;
								end;
							end;
						end;

						-- Calculate strait wheel median distance
						if haveStraitWheels then
							if minDis == maxDis then
								Distance = minDis;
							else
								Distance = (minDis + maxDis) * 0.5;
							end;

							-- Calculate turning wheel median distance if there are no strait wheels.
						elseif haveTurningWheels then
							steeringAxleScale = steeringAxleScaleMin + steeringAxleScaleMax;
							if minDisRot == maxDisRot then
								Distance = minDisRot;
							else
								Distance = (minDisRot + maxDisRot) * 0.5;
							end;
						end;
						courseplay:debug(('%s: getRealTurningNode(): haveStraitWheels=%q, haveTurningWheels=%q, Distance=%2f'):format(nameNum(object), tostring(haveStraitWheels), tostring(haveTurningWheels), Distance), 6);
					end;
				--end;
			else
				local jointNode = courseplay:getPivotJointNode(object);

				if jointNode then
					local x,_,z = getWorldTranslation(jointNode);
					local _,_,dis = worldToLocal(node, x, y, z);
					Distance = dis * invert;
				end;
				courseplay:debug(('%s: getRealTurningNode(): useNode=%q, nodeName=%q, Distance=%2f'):format(nameNum(object), tostring(useNode ~= nil), tostring(transformGroupName), Distance), 6);
			end;

			if object.cp.realTurnNodeOffsetZ and type(object.cp.realTurnNodeOffsetZ) == "number" then
				Distance = Distance + object.cp.realTurnNodeOffsetZ;
				courseplay:debug(('%s: getRealTurningNode(): Special turn node offset set: realTurnNodeOffsetZ=%2f, New Distance=%2f'):format(nameNum(object), object.cp.realTurnNodeOffsetZ, Distance), 6);
			end;

			if Distance ~= 0 then
				setTranslation(node, 0, 0, Distance);
			end;
			if courseplay:isInvertedToolNode(object, node) then
				setRotation(node, 0, rad(180), 0);
			end;

			if not haveStraitWheels and object.steeringAxleUpdateBackwards and steeringAxleScale < 0 then
				local activeInputAttacherJoint = object:getActiveInputAttacherJoint();
				local tempNode, _ = courseplay:findJointNodeConnectingToNode(object, activeInputAttacherJoint.rootNode, componentNode);
				if tempNode then
					local x, y, z;
					if tempNode == object.rootNode then
						x, y, z = getWorldTranslation(activeInputAttacherJoint.node);
					else
						x, y, z = getWorldTranslation(tempNode);
					end;
					local _,_,dis = worldToLocal(node, x, y, z);
					local offset = (dis * abs(steeringAxleScale)) + Distance;
					setTranslation(node, 0, 0, offset);
					object.cp.steeringAxleUpdateBackwards = true;
				end;
			end;
		end;

		if useNode then
		    return node;
		else
			object.cp.turningNode = node;
		end;
	end;

	return object.cp.turningNode;
end;

function courseplay:getPivotJointNode(workTool)
	if workTool.cp.jointNode == nil then
		local componentNode = courseplay:getLastComponentNodeWithWheels(workTool);
		for index, component in ipairs(workTool.components) do
			-- Check if we are in the right component.
			if component.node == componentNode then
				for jointIndex, joint in ipairs(workTool.componentJoints) do
					-- Check if we have the right componentJoint and if it's an pivot joint
					if joint.componentIndices[2] ~= nil and joint.rotLimit~= nil and joint.rotLimit[2]~= nil and joint.componentIndices[2] == index and joint.rotLimit[2] > rad(15) then
						-- Set the joint index and stop the loop.
						workTool.cp.jointNode = workTool.componentJoints[jointIndex].jointNode;
						break;
					end;
				end;
				break;
			end;
		end;

		if not workTool.cp.jointNode or not courseplay:isWheeledWorkTool(workTool) then workTool.cp.jointNode = false end;
	end;

	return workTool.cp.jointNode;
end;

function courseplay:getLastComponentNodeWithWheels(workTool)
	-- Check if there is more than 1 component
	local workToolsWheels = workTool:getWheels();
	if workToolsWheels and #workToolsWheels > 0 and #workTool.components > 1 then
		-- Check if the tool has inverted nodes
		local invert = courseplay:isInvertedToolNode(workTool) and -1 or 1;

		-- Set default node to start from.
		local node = workTool.rootNode;

		-- Loop through all the components.
		for index, component in ipairs(workTool.components) do
			-- Don't use the component that is the rootNode.
			if component.node ~= node then
				-- Loop through all the wheels and see if they are attached to this component.
				for i = 1, #workToolsWheels do
					-- isLeft is only set for real wheels and not dummy wheels, so we can use that to sort out the dummy wheels
					if workToolsWheels[i].isLeft ~= nil and workToolsWheels[i].maxLatStiffnessLoad > 0.5 then
						if courseplay:isPartOfNode(workToolsWheels[i].node, component.node) then
							-- Check if they are linked together
							for _, joint in ipairs(workTool.componentJoints) do
								if joint.componentIndices[2] == index then
									if workTool.components[joint.componentIndices[1]].node == node then
										-- Check if the component is behind the node.
										local xJoint,yJoint,zJoint = getWorldTranslation(joint.jointNode);
										local offset,_,direction = worldToLocal(node, xJoint,yJoint,zJoint);
										--offset check to make sure we are selecting a node that is centered
										if (direction * invert) < 0 and offset == 0 then
											-- Component is hehind, so set the node to the new component node.
											node = component.node;
										end;
									end;
								end;
							end;
							break;
						end;
					end;
				end;
			end;
		end;

		-- Return the found node.
		return node;
	end;

	-- Return default rootNode if none is found.
	return workTool.rootNode
end;

function courseplay:getRealUnloadOrFillNode(workTool)
	if workTool.cp.unloadOrFillNode == nil then
		-- BALELOADERS and STRAWBLOWERS
		if courseplay:isBaleLoader(workTool) or (courseplay:isSpecialBaleLoader(workTool) and workTool.cp.specialUnloadDistance) or workTool.cp.isStrawBlower then
			-- Create the new node and link it to realTurningNode
			local node = courseplay:createNewLinkedNode(workTool, "UnloadOrFillNode", courseplay:getRealTurningNode(workTool));

			-- make sure we set the node distance position
			local Distance = workTool.cp.specialUnloadDistance or -5;
			setTranslation(node, 0, 0, Distance);

			workTool.cp.unloadOrFillNode = node;

			-- NORMAL FILLABLE TRAILERS WITH ALLOW TO BE FILLED FROM THE AIR
		elseif workTool.cp.hasSpecializationTrailer and workTool.cp.hasSpecializationFillable and #workTool.spec_fillUnit.fillUnits > 0 then
			-- Get the current exactFillRootNode.
			local exactFillRootNode = workTool.spec_fillUnit.fillUnits[1].exactFillRootNode; -- TODO: Handle multiply exactFillRootNode for trailers with more than 1 fill plane. (temp fix for now)

			-- Create the new node and link it to exactFillRootNode
			local node = courseplay:createNewLinkedNode(workTool, "UnloadOrFillNode", exactFillRootNode);

			-- Make sure ve set the height position to the same as the realTurningNode
			local x, y, z = getWorldTranslation(courseplay:getRealTurningNode(workTool));
			local _,Height,_ = worldToLocal(exactFillRootNode, x, y, z);
			setTranslation(node, 0, Height, 0);

			if courseplay:isInvertedToolNode(workTool, node) then
				setRotation(node, 0, rad(180), 0);
			end;

			workTool.cp.unloadOrFillNode = node;

			-- NONE OF THE ABOVE
		else
			workTool.cp.unloadOrFillNode = false;
		end;
	end;

	return workTool.cp.unloadOrFillNode;
end;

function courseplay:getHighestToolTurnDiameter(object)
	local turnDiameter = 0;

	-- Tool attached to Steerable
	for _, implement in ipairs(object:getAttachedImplements()) do
		local workTool = implement.object;

		if courseplay:isRearAttached(object, implement.jointDescIndex) then
			local ttr =  courseplay:getToolTurnRadius(workTool);
			turnDiameter = ttr * 2;
			courseplay:debug(('%s: toolTurnDiameter=%.2fm'):format(nameNum(workTool), turnDiameter), 6);

			-- Check rear attached tools for turnDiameters
			if workTool.getAttachedImplements and workTool:getAttachedImplements() ~= {} then
				local ttd = courseplay:getHighestToolTurnDiameter(workTool);
				if ttd > turnDiameter then
					turnDiameter = ttd;
				end;
			end;
		end;
	end;

	return turnDiameter;
end;

function courseplay:getToolTurnRadius(workTool)
	local turnRadius	= 0; -- Default value if none is set

	if workTool.cp.overwriteTurnRadius and type(workTool.cp.overwriteTurnRadius) == "number" then
		turnRadius = workTool.cp.overwriteTurnRadius;
		courseplay:debug(('%s -> TurnRadius: overwriteTurnRadius is set: turnRadius set to %.2fm'):format(nameNum(workTool), turnRadius), 6);
	elseif courseplay:isWheeledWorkTool(workTool) then
		local radiusMultiplier = 1.05; -- Used to add a little bit to the radius, for safer turns.

		local wheelBase		= 0;
		local rotMax		= 0;
		local CPRatio		= 0;
		local type			= "Tool";
		local TR			= 0;
		local frontLength	= 0;
		--attacherJointOrPivotToTurningNode
		local attacherVehicle			= workTool:getAttacherVehicle();
		local workToolDistances			= workTool.cp.distances or courseplay:getDistances(workTool);

		for i, attachedImplement in pairs(attacherVehicle:getAttachedImplements()) do
			if attachedImplement.object == workTool then
				-- Check if AIVehicleUtil can calculate it for us
				--local AIMaxToolRadius = AIVehicleUtil.getMaxToolRadius(attachedImplement) * 0.5;
				--if AIMaxToolRadius > 0 then
				--	if workToolDistances.attacherJointOrPivotToTurningNode > AIMaxToolRadius then
				--		AIMaxToolRadius = workToolDistances.attacherJointOrPivotToTurningNode;
				--	end;
				--	courseplay:debug(('%s -> TurnRadius: AIVehicleUtil.getMaxToolRadius=%.2fm'):format(nameNum(workTool), AIMaxToolRadius), 6);
				--	return AIMaxToolRadius;
				--end;

				-- AIVehicleUtil could not calculate it, so we do it our self.
				rotMax = attachedImplement.upperRotLimit[2];
				break;
			end;
		end;

		local attacherVehicleDistances	= attacherVehicle.cp.distances or courseplay:getDistances(attacherVehicle);

		local activeInputAttacherJoint = workTool:getActiveInputAttacherJoint();

		if deg(rotMax) >= 30 and deg(rotMax) < 90 then
			-- We have turningNodeToRearTrailerAttacherJoints value
			if attacherVehicleDistances.turningNodeToRearTrailerAttacherJoints then
				frontLength = attacherVehicleDistances.turningNodeToRearTrailerAttacherJoints[activeInputAttacherJoint.jointType] or 0;

			-- We have turningNodeToTrailerAttacherJoints value
			elseif attacherVehicleDistances.turningNodeToTrailerAttacherJoints then
				frontLength = attacherVehicleDistances.turningNodeToTrailerAttacherJoints[activeInputAttacherJoint.jointType] or 0;

			-- We have to go backwards to find the real front distance (attacherVehicle dont have wheels and might be a weight or something else)
			else
				frontLength = attacherVehicleDistances.attacherJointToRearTrailerAttacherJoints[activeInputAttacherJoint.jointType] or 0;
				local backTrackVehicle = attacherVehicle;
				local oldBackTrackVehicle;
				while true do
					oldBackTrackVehicle = backTrackVehicle;
					backTrackVehicle = oldBackTrackVehicle.getAttacherVehicle and oldBackTrackVehicle:getAttacherVehicle() or false;
					if backTrackVehicle and backTrackVehicle ~= {} then
						local distances = backTrackVehicle.cp.distances or courseplay:getDistances(backTrackVehicle);
						local jointType = oldBackTrackVehicle.attacherJoint.jointType;
						if distances.turningNodeToRearTrailerAttacherJoints then
							frontLength = frontLength + distances.turningNodeToRearTrailerAttacherJoints[jointType];
							break;
						elseif distances.turningNodeToTrailerAttacherJoints then
							frontLength = frontLength + distances.turningNodeToTrailerAttacherJoints[jointType];
							break;
						else
							frontLength = frontLength + (distances.attacherJointToRearTrailerAttacherJoints[jointType] or 0);
						end;
					else
						break;
					end;
				end;
			end;
			courseplay:debug(('%s -> TurnRadius: rotMax=%d°, frontLength=%.2fm'):format(nameNum(workTool), deg(rotMax), frontLength), 6);

			-- WE ARE A PIVOTED TRAILER / IMPLEMENT
			if workToolDistances.attacherJointToPivot then
				local pivotRotMax = 0;
				local lastNode = courseplay:getLastComponentNodeWithWheels(workTool)
				local _, _, rotLimits = courseplay:findJointNodeConnectingToNode(workTool, activeInputAttacherJoint.rootNode, lastNode);
				if rotLimits then
					for _, rotLimit in pairs(rotLimits) do
						if rotLimit[2] > pivotRotMax and rotLimit[2] > rad(15) then
							pivotRotMax = rotLimit[2];
						end;
					end;
				end;
				courseplay:debug(('%s -> TurnRadius: pivotRotMax=%d° (Pivot trailer/implement)'):format(nameNum(workTool), deg(pivotRotMax)), 6);

				-- We are an implement and should be handled a bit different
				if workTool.spec_attacherJoints and workTool.spec_attacherJoints.attacherJoint and workTool.spec_attacherJoints.attacherJoint.jointType == AttacherJoints.JOINTTYPE_IMPLEMENT then
					-- We have a valid pivotRotMax, so calculate it normally.
					if pivotRotMax > rad(15) then
						frontLength = frontLength + workToolDistances.attacherJointToPivot;
						wheelBase = frontLength + workToolDistances.attacherJointOrPivotToTurningNode;
						CPRatio = courseplay:getCenterPivotRatio(nil, wheelBase, frontLength);
						TR = courseplay:calculateTurnRadius(type, wheelBase, pivotRotMax, CPRatio);

					-- If pivotRotMax is not greater than 15 degrees,
					-- we will then use half of the length from attacherJoint to turningNode as the turnRadius instead.
					else
						TR = ceil((workToolDistances.attacherJointToPivot + workToolDistances.attacherJointOrPivotToTurningNode) / 2 * radiusMultiplier);
					end;
					courseplay:debug(('%s -> TurnRadius: turnRadius=%.2fm (Pivot implement)'):format(nameNum(workTool), TR), 6);

				-- We are an pivoted trailer
				else
					-- We have a valid pivotRotMax, so calculate it normally.
					if pivotRotMax > rad(15) then
						-- Dolly part
						wheelBase = frontLength + workToolDistances.attacherJointToPivot;
						CPRatio = courseplay:getCenterPivotRatio(nil, wheelBase, frontLength);
						local pivotTR = ceil(courseplay:calculateTurnRadius(type, wheelBase, rotMax, CPRatio) * radiusMultiplier);

						-- Trailer part
						wheelBase = workToolDistances.attacherJointOrPivotToTurningNode;
						CPRatio = 0;
						TR = ceil(courseplay:calculateTurnRadius(type, wheelBase, pivotRotMax, CPRatio) * radiusMultiplier);

						-- Take the highest one
						if pivotTR > TR then
							TR = pivotTR;
						end;

					-- If pivotRotMax is not greater than 15 degrees,
					-- we will then use half of the length from attacherJoint to turningNode as the turnRadius instead.
					else
						TR = ceil((workToolDistances.attacherJointToPivot + workToolDistances.attacherJointOrPivotToTurningNode) / 2 * radiusMultiplier);
					end;
					courseplay:debug(('%s -> TurnRadius: turnRadius=%.2fm (Pivot trailer)'):format(nameNum(workTool), TR), 6);
				end;

			-- WE ARE A NORMAL TRAILER OR IMPLEMENT
			else
				wheelBase = frontLength + (workToolDistances.attacherJointOrPivotToTurningNode or 0);
				CPRatio = courseplay:getCenterPivotRatio(nil, wheelBase, frontLength);

				TR = ceil(courseplay:calculateTurnRadius(type, wheelBase, rotMax, CPRatio) * radiusMultiplier);
				courseplay:debug(('%s -> TurnRadius: turnRadius=%.2fm (Normal trailer/implement)'):format(nameNum(workTool), TR), 6);
			end;

			if TR > 0 then
				turnRadius = TR;
			end;
		end;

		-- If we are not an implement then check if half trailer length is bigger than the turnRadius and set it, if it is.
		if ((deg(rotMax) < 30 and deg(rotMax) >= 90) or activeInputAttacherJoint.jointType ~= AttacherJoints.JOINTTYPE_IMPLEMENT) and workToolDistances.attacherJointToRearWheel then
			if (workToolDistances.attacherJointToRearWheel / 2) > turnRadius then
				turnRadius = ceil(workToolDistances.attacherJointToRearWheel / 2 * radiusMultiplier);
				courseplay:debug(('%s -> TurnRadius: Using half tool length = %.2fm'):format(nameNum(workTool), turnRadius), 6);
			end;
		end;
	else
		courseplay:debug(('%s -> TurnRadius: Have no wheels. turnRadius set to 0m'):format(nameNum(workTool)), 6);
	end;

	return turnRadius;
end;

function courseplay:getTotalLengthOnWheels(vehicle)
	courseplay:debug(('%s: getTotalLengthOnWheels()'):format(nameNum(vehicle)), 6);
	local totalLength = 0;
	local directionNodeToFrontWheelOffset;

	if not vehicle.cp.distances or (courseplay.debugChannels[6] ~= nil and courseplay.debugChannels[6] == true) then
		vehicle.cp.distances = courseplay:getDistances(vehicle);
	end;

	-- STEERABLES
	if vehicle.cp.DirectionNode then
		directionNodeToFrontWheelOffset = vehicle.cp.distances.frontWheelToDirectionNodeOffset;

		local _, y, _ = getWorldTranslation(vehicle.cp.DirectionNode);

		local hasRearAttach = false;
		local jointType = 0;

		for _, implement in ipairs(vehicle:getAttachedImplements()) do
			-- Check if it's rear attached
			if courseplay:isRearAttached(vehicle, implement.jointDescIndex) then
				hasRearAttach = true;
				local length, _ = courseplay:getTotalLengthOnWheels(implement.object);
				if length > 0 then
					jointType = implement.object:getActiveInputAttacherJoint().jointType;
					totalLength = length;
				end;
			end;
		end;

		if hasRearAttach and totalLength > 0 and jointType > 0 then
			local length = vehicle.cp.distances.frontWheelToRearTrailerAttacherJoints[jointType];
			if length then
				totalLength = totalLength + length;
			else
				totalLength = 0;
				directionNodeToFrontWheelOffset = 0;
			end;
			courseplay:debug(('%s: hasRearAttach: totalLength=%.2f'):format(nameNum(vehicle), totalLength), 6);
		else
			totalLength = vehicle.cp.distances.frontWheelToRearWheel;
			courseplay:debug(('%s: Using frontWheelToRearWheel=%.2f'):format(nameNum(vehicle), totalLength), 6);
		end;

		cpPrintLine(6);
		courseplay:debug(('%s: totalLength=%.2f, totalLengthOffset=%.2f'):format(nameNum(vehicle), totalLength, directionNodeToFrontWheelOffset), 6);
		cpPrintLine(6);

	-- IMPLEMENTS OR TRAILERS
	else
		--local activeInputAttacherJoint = object:getActiveInputAttacherJoint();
		local _, y, _ = getWorldTranslation(vehicle:getActiveInputAttacherJoint().node);

		local hasRearAttach = false;
		local jointType = 0;

		for _, implement in ipairs(vehicle:getAttachedImplements()) do
			-- Check if it's rear attached
			if courseplay:isRearAttached(vehicle, implement.jointDescIndex) then
				hasRearAttach = true;
				local length, _ = courseplay:getTotalLengthOnWheels(implement.object);
				if length > 0 then
					jointType = implement.object:getActiveInputAttacherJoint().jointType;
					totalLength = length;
				end;
			end;
		end;

		if hasRearAttach and totalLength > 0 and jointType > 0 and vehicle.cp.distances.attacherJointToRearTrailerAttacherJoints then
			local length = vehicle.cp.distances.attacherJointToRearTrailerAttacherJoints[jointType];
			if length then
				totalLength = totalLength + length;
			else
				totalLength = 0;
			end;
			courseplay:debug(('%s: hasRearAttach: totalLength=%.2f'):format(nameNum(vehicle), totalLength), 6);
		elseif vehicle.cp.distances.attacherJointToRearWheel then
			totalLength = vehicle.cp.distances.attacherJointToRearWheel;
			courseplay:debug(('%s: Using attacherJointToRearWheel=%.2f'):format(nameNum(vehicle), totalLength), 6);
		else
			totalLength = 0;
			courseplay:debug(('%s: No length found, returning 0'):format(nameNum(vehicle)), 6);
		end;
	end;

	return totalLength, directionNodeToFrontWheelOffset;
end;

function courseplay:getVehicleTurnRadius(vehicle)
	local radiusMultiplier = 1.05; -- Used to add a little bit to the radius, for safer turns.

	local turnRadius	= 5; -- Default value if none is set
	local wheelBase		= 0;
	local CPRatio		= 0;
	local rotMax		= 0;
	local TR			= 0;
	local steeringType	= "2WS";

	-- Make sure the turning node have been updated (Script will only run once)
	courseplay:getRealTurningNode(vehicle);

	if vehicle.cp.overwriteTurnRadius and type(vehicle.cp.overwriteTurnRadius) == "number" then
		courseplay:debug(('%s -> TurnRadius: overwriteTurnRadius is set: turnRadius set to %.2fm'):format(nameNum(vehicle), vehicle.cp.overwriteTurnRadius), 6);
		return vehicle.cp.overwriteTurnRadius;

	-- Giants have provided us with maxTurningRadius, so use it.
	--elseif vehicle.maxTurningRadius then
	--	courseplay:debug(('%s -> TurnRadius: Useing Giants value: turnRadius set to %.2fm'):format(nameNum(vehicle), vehicle.maxTurningRadius), 6);
	--	return vehicle.maxTurningRadius

	-- We need to calculate it our self.
	else
		-- ArticulatedAxis Steering
		if vehicle.spec_articulatedAxis and vehicle.spec_articulatedAxis.rotMax then
			wheelBase = courseplay:getWheelBase(vehicle);
			CPRatio = courseplay:getCenterPivotRatio(vehicle, wheelBase);
			rotMax = abs(vehicle.spec_articulatedAxis.rotMax);
			steeringType = "ASW";

		-- 4 Wheel Steering
		elseif vehicle.cp.fourWheelSteerMaxRot then
			wheelBase = courseplay:getWheelBase(vehicle);
			rotMax = vehicle.cp.fourWheelSteerMaxRot;
			steeringType = "4WS";

		-- 2 Wheel Steering
		elseif vehicle:getWheels() then
			for _, wheel in ipairs(vehicle:getWheels()) do
				if abs(wheel.rotMax) > rotMax then
					rotMax = abs(wheel.rotMax);
				end;
			end;
			wheelBase = courseplay:getWheelBase(vehicle, true);
		end;
	end;

	TR = ceil(courseplay:calculateTurnRadius(steeringType, wheelBase, rotMax, CPRatio) * radiusMultiplier);

	if TR > 0 then
		if vehicle.maxTurningRadius and vehicle.maxTurningRadius > TR then
			turnRadius = vehicle.maxTurningRadius;
			courseplay:debug(('%s -> TurnRadius: Using Giants maxTurningRadius: %.2fm'):format(nameNum(vehicle), vehicle.maxTurningRadius), 6);
		else
			turnRadius = TR;
			courseplay:debug(('%s -> TurnRadius: (Steering Type: %s) Calculated turnRadius set to %.2fm'):format(nameNum(vehicle), steeringType, turnRadius), 6);
		end;
	end;

	return turnRadius
end;

function courseplay:getVehicleDirectionNodeOffset(vehicle, directionNode)
	local offset = 0;
	local isTruck = false;

	-- Build the truckAttacherJoint list if not already done.
	if #truckAttacherJoint == 0 then
		truckAttacherJoint[AttacherJoints.jointTypeNameToInt["semitrailer"]] = true;
		truckAttacherJoint[AttacherJoints.jointTypeNameToInt["hookLift"]] = true;
		if AttacherJoints.jointTypeNameToInt["terraVariant"] then
			truckAttacherJoint[AttacherJoints.jointTypeNameToInt["terraVariant"]] = true;
		end;
	end;

	-- Make sure we are not some standard combine/crawler/articulated vehicle
	if not ((vehicle.spec_articulatedAxis and vehicle.spec_articulatedAxis.rotMin) or vehicle.cp.hasSpecializationCombine or vehicle.cp.hasSpecializationCrawler or courseplay:isHarvesterSteerable(vehicle)) then
	    local isAllWheelStering = false;
		local haveStraitWheels = false;
		local haveTurningWheels = false;
		local dirNodeOffset = 0;
		local wheelBase = 0;
		local minDis, maxDis = 0, 0;
		local _, y, _ = getWorldTranslation(directionNode);

		-- Check for starit and turning wheels
		for index, wheel in ipairs(vehicle:getWheels()) do
			if wheel.rotMax == 0 and wheel.maxLatStiffness > 0 then
				haveStraitWheels = true;
			else
				haveTurningWheels = true;
			end;
		end;

		-- Check if it's actually an four wheel steering
		if not haveStraitWheels and haveTurningWheels then
			isAllWheelStering = true;
			--print("Is All Wheel Stering");
		end;

		-- Get the distance from the aiVehicleDirectionNode to the front wheels
		for i, wheel in ipairs(vehicle:getWheels()) do
			local x,_,z = getWorldTranslation(wheel.repr);
			local _,_,dis = worldToLocal(directionNode, x, y, z);
			if i > 1 then
				if dis < minDis then minDis = dis; end;
				if dis > maxDis then maxDis = dis; end;
			else
				minDis = dis;
				maxDis = dis;
			end;
		end;

		if isAllWheelStering then
			dirNodeOffset = maxDis + minDis;
		else
			dirNodeOffset = maxDis * 0.75;
		end;
		wheelBase = abs(maxDis) + abs(minDis);
		--print(("wheelBase is %.2fm"):format(wheelBase));

		-- first check for specific attacher joints that normally only trucks have.
		for index, attacherJoint in ipairs(vehicle:getAttacherJoints()) do
			if truckAttacherJoint[attacherJoint.jointType] then
				--print("Is Truck Based on AttacherJoint");
				isTruck = true;
			end;
		end;

		-- If we were not an truck, then check the length, since we could still be an truck based in it's length
		if not isTruck and wheelBase > 3.5 then
			--print("Is Truck Based on Wheelbase");
			isTruck = true;
		end;

		if isTruck and dirNodeOffset > 0.25 then
			offset = dirNodeOffset;
		end;
	end;

	-- If an offset is set in setNameVariable() then apply it
	if vehicle.cp.directionNodeZOffset and vehicle.cp.directionNodeZOffset ~= 0 then
		offset = offset + vehicle.cp.directionNodeZOffset;
	end;

	--if offset ~= 0 then
	--	print(("Offset set to %.2fm"):format(offset));
	--end;

	return offset, isTruck;
end;

function courseplay:getWheelBase(vehicle, fromTurningNode)
	local wheelBase = 0;

	-- 2 Wheel Stering
	if fromTurningNode then
		local turningNode = courseplay:getRealTurningNode(vehicle);
		local _, y, _ = getWorldTranslation(turningNode);
		for _, wheel in ipairs(vehicle:getWheels()) do
			local x, _, z = getWorldTranslation(wheel.repr);
			local _, _, dis = worldToLocal(turningNode, x, y, z);

			if abs(dis) > wheelBase then
				wheelBase = abs(dis);
			end;
		end;

	-- 4 Wheel Steering and ArticulatedAxis Steering
	else
		local minDis, maxDis = 0, 0;
		local _, y, _ = getWorldTranslation(vehicle.rootNode);
		for i, wheel in ipairs(vehicle:getWheels()) do
			local x,_,z = getWorldTranslation(wheel.repr);
			local _,_,dis = worldToLocal(vehicle.rootNode, x, y, z);
			if i > 1 then
				if dis < minDis then minDis = dis; end;
				if dis > maxDis then maxDis = dis; end;
			else
				minDis = dis;
				maxDis = dis;
			end;
		end;

		wheelBase = abs(maxDis - minDis);
	end;

	return wheelBase;
end;

function courseplay:getCenterPivotRatio(vehicle, wheelBase, frontLength)
	if not wheelBase then
		if vehicle then
			wheelBase = courseplay:getWheelBase(vehicle);
		else
			wheelBase = 0;
		end;
	end;

	local distance = 0;
	if frontLength then
		if frontLength > 0 then
			distance = frontLength;
		end;
	else
		local turningNode = courseplay:getRealTurningNode(vehicle);
		local _, y, _ = getWorldTranslation(turningNode);
		for _, wheel in ipairs(vehicle:getWheels()) do
			local x, _, z = getWorldTranslation(wheel.repr);
			local _, _, dis = worldToLocal(turningNode, x, y, z);

			if dis > distance then
				distance = dis;
			end;
		end;
	end;

	local ratio = 0;
	if wheelBase > 0 then
		ratio = 1 / wheelBase * distance;
	end;

	return ratio;
end

function courseplay:isInvertedToolNode(workTool, node)
	-- Only check trailers
	if workTool.cp.DirectionNode then
		return false;
	end;

	return workTool.cp.haveInvertedToolNode and true or false;
end;

function courseplay:isPartOfNode(node, partOfNode)
	-- Check if Node is part of partOfNode and not in a different component
	while node ~= 0 and node ~= nil do
		if node == partOfNode then
			return true;
		else
			node = getParent(node);
		end;
	end;

	return false;
end;

function courseplay:isRearAttached(object, jointDescIndex)
	local turningNode = object.cp.DirectionNode or courseplay:getRealTurningNode(object);
	local x, y, z = localToWorld(turningNode, 0, 0, 50);
	local deltaX, _, _ = worldToLocal(object.spec_attacherJoints.attacherJoints[jointDescIndex].jointTransform, x, y, z);

	if courseplay:isInvertedToolNode(object) then
		deltaX = deltaX * -1;
	end;

	return deltaX < 0;
end;

local allowedJointType = {};
function courseplay:isWheeledWorkTool(workTool)
	if #allowedJointType == 0 then
		local jointTypeList = {"implement", "trailer", "trailerLow", "semitrailer"};
		for _,jointType in ipairs(jointTypeList) do
			local index = AttacherJoints.jointTypeNameToInt[jointType];
			if index then
				table.insert(allowedJointType, index, true);
			end;
		end;
	end;

	local activeInputAttacherJoint = workTool:getActiveInputAttacherJoint();

	if activeInputAttacherJoint and allowedJointType[activeInputAttacherJoint.jointType] and workTool.spec_wheels and workTool.spec_wheels.wheels and #workTool.spec_wheels.wheels > 0 then
		-- Attempt to find the pivot node.
		local node, _ = courseplay:findJointNodeConnectingToNode(workTool, activeInputAttacherJoint.rootNode, workTool.rootNode);
		if node then
			-- Trailers
			if (activeInputAttacherJoint.jointType ~= AttacherJoints.JOINTTYPE_IMPLEMENT)
			-- Implements with pivot and wheels that do not lift the wheels from the ground.
			or (node ~= workTool.rootNode and activeInputAttacherJoint.jointType == AttacherJoints.JOINTTYPE_IMPLEMENT and (not activeInputAttacherJoint.topReferenceNode or workTool.cp.implementWheelAlwaysOnGround))
			then
				return true;
			end;
		end;
	end;

	return false;
end;

function courseplay:setPathVehiclesSpeed(vehicle,dt)
	if vehicle.cp.collidingVehicleId == nil then return end;
	local pathVehicle = g_currentMission.nodeToObject[vehicle.cp.collidingVehicleId];
	--print("update speed")
	if pathVehicle.speedDisplayDt == nil then
		pathVehicle.speedDisplayDt = 0;
		pathVehicle.lastSpeed = 0;
		pathVehicle.lastSpeedReal = 0;
		pathVehicle.movingDirection = 1;
	end;
	pathVehicle.speedDisplayDt = pathVehicle.speedDisplayDt + dt;
	if pathVehicle.speedDisplayDt > 100 then
		local newX, newY, newZ = getWorldTranslation(pathVehicle.rootNode);
		if pathVehicle.lastPosition == nil then
		  pathVehicle.lastPosition = {
			newX,
			newY,
			newZ
		  };
		end;
		local lastMovingDirection = pathVehicle.movingDirection;
		local dx, dy, dz = worldDirectionToLocal(pathVehicle.rootNode, newX - pathVehicle.lastPosition[1], newY - pathVehicle.lastPosition[2], newZ - pathVehicle.lastPosition[3]);
		if dz > 0.001 then
		  pathVehicle.movingDirection = 1;
		elseif dz < -0.001 then
		  pathVehicle.movingDirection = -1;
		else
		  pathVehicle.movingDirection = 0;
		end;
		pathVehicle.lastMovedDistance = MathUtil.vector3Length(dx, dy, dz);
		local lastLastSpeedReal = pathVehicle.lastSpeedReal;
		pathVehicle.lastSpeedReal = pathVehicle.lastMovedDistance * 0.01;
		pathVehicle.lastSpeedAcceleration = (pathVehicle.lastSpeedReal * pathVehicle.movingDirection - lastLastSpeedReal * lastMovingDirection) * 0.01;
		pathVehicle.lastSpeed = pathVehicle.lastSpeed * 0.85 + pathVehicle.lastSpeedReal * 0.15;
		pathVehicle.lastPosition[1], pathVehicle.lastPosition[2], pathVehicle.lastPosition[3] = newX, newY, newZ;
		pathVehicle.speedDisplayDt = pathVehicle.speedDisplayDt - 100;
	end;
end

function courseplay:setAbortWorkWaypoint(vehicle)
	if not vehicle.cp.realisticDriving then
		-- Set abort Work to 10 waypoints back from where we stopped working to align with course when returing
		vehicle.cp.abortWork = vehicle.cp.previousWaypointIndex - 10;
		vehicle.cp.abortWorkExtraMoveBack = 0;

		--- update triggers if in mode 4 in the case that new BiGPacks had been bought
		if vehicle.cp.mode == 4 then
			courseplay:updateAllTriggers();
		end;

		--- Check for turns from the aborkWork WP to where work stopped so we can align with turn to prevent circling and turn alignment issuses
		for i=vehicle.cp.abortWork,vehicle.cp.previousWaypointIndex do
			local minNumWPBeforeTurn = 8;
			local wp = vehicle.Waypoints[i];
			if wp and wp.turnStart then
				--- Invert lane offset if abortWork is before previous turn point (symmetric lane change)
				if vehicle.cp.symmetricLaneChange and vehicle.cp.laneOffset ~= 0 and not vehicle.cp.switchLaneOffset then
					courseplay:debug(string.format('%s: abortWork + %d: turnStart=%s -> change lane offset back to abortWork\'s lane', nameNum(vehicle), i-1, tostring(wp.turnStart and true or false)), 12);
					courseplay:changeLaneOffset(vehicle, nil, vehicle.cp.laneOffset * -1);
					vehicle.cp.switchLaneOffset = true;
				end;

				--- If the turn is less than 8 points ahead of the abortWork waypoint, we set the abortWork further back so we can align better.
				local wpUntilTurn = i - vehicle.cp.abortWork;
				if wpUntilTurn < minNumWPBeforeTurn then
					local extraMoveBack = minNumWPBeforeTurn - wpUntilTurn;
					vehicle.cp.abortWork = vehicle.cp.abortWork - extraMoveBack;
					-- Save the additonal offset waypoints so Mode4/6 logic knows how far to go from when reaching abortWork WP to where stopped worked occurs
					vehicle.cp.abortWorkExtraMoveBack = extraMoveBack;
				end;
			end;
		end;
		-- Set the waypoint index to the first waypoint of the unload course
		courseplay:setWaypointIndex(vehicle, vehicle.cp.stopWork + 1);
		
	else
		-- If were using align point then there is no need for all that extra distance just enough that it straightens back out after turning
		vehicle.cp.abortWork = vehicle.cp.previousWaypointIndex - 2
		--- Set the waypoint to the start of the unload course
		courseplay:setWaypointIndex(vehicle, vehicle.cp.stopWork + 1);
		local tx, tz = vehicle.Waypoints[vehicle.cp.waypointIndex].cx,vehicle.Waypoints[vehicle.cp.waypointIndex].cz
		courseplay.debugVehicle( 9, vehicle, "vehicles 1393")
		if vehicle.cp.isNavigatingPathfinding == false and courseplay:calculateAstarPathToCoords(vehicle, nil, tx, tz, vehicle.cp.turnDiameter*2, true) then
			vehicle.cp.isNavigatingPathfinding = true
			courseplay.debugVehicle( 9, vehicle, "vehicles 1396")
			courseplay:setCurrentTargetFromList(vehicle, 1);
		else
			courseplay:startAlignmentCourse( vehicle, vehicle.Waypoints[vehicle.cp.waypointIndex], true)
		end
	end
	-- Initialize PPC because of the jump in WPs
	vehicle.cp.ppc:initialize()
	courseplay:debug(string.format('%s: abortWork set (%d)', nameNum(vehicle), vehicle.cp.abortWork), 12);
end;

-- vim: set noexpandtab:

function courseplay:getFreeCapacity(vehicle,fillType)
    local freeCapacity = 0;
    for i,fillUnit in pairs(vehicle:getFillUnits()) do
        --if fillType == nil or fillType == FillType.UNKNOWN or fillUnit.fillTypes[fillType] then
            freeCapacity = freeCapacity + vehicle:getFillUnitFreeCapacity(i)
       -- end
    end
    return freeCapacity;
end

function courseplay:getTipTriggerRaycastDirection(vehicle,lx,lz,distance)
	--get raycast direction x and z
	local nx,_, nz = localDirectionToWorld(vehicle.cp.DirectionNode, lx or 0, 0, lz or 1)
	-- get raycast start point in front of vehicle
	local x, y, z = localToWorld(vehicle.cp.DirectionNode, 0, 1, 3)
	--get the raycast direction y to a point 1m below terrain at raycast tip 
	local xt,zt = x+(nx*distance), z+(nz*distance)
	local yt = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, xt, 0, zt);
	local _, ny,_ = courseplay:getWorldDirection(x, y, z, xt, yt-1, zt)
	return x,y,z,nx,ny,nz;
end

function courseplay:isNodeTurnedWrongWay(vehicle,dischargeNode)
	local x,y,z = getWorldTranslation(vehicle.cp.DirectionNode)
	local _,_, nz = worldToLocal(dischargeNode,x,y,z)
	return nz < 0
end

function courseplay:findAiCollisionTrigger(vehicle)
	if vehicle == nil then
		return false;
	end;

	local ret = false
	local index = nil
	
	if vehicle.aiTrafficCollisionTrigger == nil then
		if vehicle.i3dMappings.aiCollisionTrigger then		-- standard colli definition
			index = vehicle.i3dMappings.aiCollisionTrigger
		elseif vehicle.i3dMappings.trafficCollisionTrigger then		-- workaround GIANTS FS19 vehicle
			index = vehicle.i3dMappings.trafficCollisionTrigger
		elseif vehicle.i3dMappings.collisionTrigger then			-- workaround GIANTS FS19 vehicle
			index = vehicle.i3dMappings.collisionTrigger
		elseif vehicle.i3dMappings.aiTrafficTrigger then			-- workaround GIANTS FS19 vehicle
			index = vehicle.i3dMappings.aiTrafficTrigger
		elseif vehicle.i3dMappings.aiCollisionTriggerBig then			-- workaround GIANTS FS19 vehicle K105, K165
			index = vehicle.i3dMappings.aiCollisionTriggerBig
		elseif vehicle.i3dMappings.aiCollisionTriggerSmall then			-- workaround GIANTS FS19 vehicle K105, K165
			index = vehicle.i3dMappings.aiCollisionTriggerSmall
		end
		if index then
			local triggerObject = I3DUtil.indexToObject(vehicle.components, index);
			if triggerObject then
				vehicle.aiTrafficCollisionTrigger = triggerObject;
			end;
		end;
	end;
	
	if vehicle.aiTrafficCollisionTrigger == nil and getNumOfChildren(vehicle.rootNode) > 0 then
		courseplay.debugVehicle( 3, vehicle, "findaiTrafficCollisionTrigger: no aiCollisionTrigger found in vehicle XML - trying alternative")
		if getChild(vehicle.rootNode, "aiCollisionTrigger") ~= 0 then
			vehicle.aiTrafficCollisionTrigger = getChild(vehicle.rootNode, "aiCollisionTrigger");
		else
			for i=0,getNumOfChildren(vehicle.rootNode)-1 do
				local child = getChildAt(vehicle.rootNode, i);
				if getChild(child, "aiCollisionTrigger") ~= 0 then
					vehicle.aiTrafficCollisionTrigger = getChild(child, "aiCollisionTrigger");
					if vehicle.aiTrafficCollisionTrigger then
						break;
					end
				end;
			end;
		end;
	end;

	if vehicle.aiTrafficCollisionTrigger == nil and SpecializationUtil.hasSpecialization(AIVehicle, vehicle.specializations) then
		print(string.format('## Courseplay: aiTrafficCollisionTrigger missing. Traffic collision prevention will not work! vehicle %s', nameNum(vehicle)));
	end;

	if vehicle.aiTrafficCollisionTrigger then
		ret = true;
	end

	return ret;
end

--[[
remove the targetVehicle and all its components and attached implements to the local collision ignore list of the vehicle
]]
function courseplay:removeFromVehicleLocalIgnoreList(vehicle, targetVehicle)
	if vehicle and targetVehicle and vehicle.cpTrafficCollisionIgnoreList then

		vehicle.cpTrafficCollisionIgnoreList[targetVehicle.rootNode] = nil;

		-- TRAFFIC COLLISION IGNORE LIST (components)
		if targetVehicle.components ~= nil then
			courseplay:debug(('%s: removing %q (%q) components to cpTrafficCollisionIgnoreList'):format(nameNum(vehicle), nameNum(targetVehicle), tostring(targetVehicle.cp.xmlFileName)), 3);
			for i,component in pairs(targetVehicle.components) do
				vehicle.cpTrafficCollisionIgnoreList[component.node] = nil;
			end;
		end;
		-- CHECK ATTACHED IMPLEMENTS
		for k,impl in pairs(targetVehicle:getAttachedImplements()) do
			courseplay:removeFromVehicleLocalIgnoreList(vehicle, impl.object);
		end;
	end;
end

--[[
add the targetVehicle and all its components and attached implements to the local collision ignore list of the vehicle
]]
function courseplay:addToVehicleLocalIgnoreList(vehicle, targetVehicle)
	if vehicle and targetVehicle and vehicle.cpTrafficCollisionIgnoreList then

		vehicle.cpTrafficCollisionIgnoreList[targetVehicle.rootNode] = true;

		-- TRAFFIC COLLISION IGNORE LIST (components)
		if targetVehicle.components ~= nil then
			courseplay:debug(('%s: adding %q (%q) components to cpTrafficCollisionIgnoreList'):format(nameNum(vehicle), nameNum(targetVehicle), tostring(targetVehicle.cp.xmlFileName)), 3);
			for i,component in pairs(targetVehicle.components) do
				vehicle.cpTrafficCollisionIgnoreList[component.node] = true;
			end;
		end;
		-- CHECK ATTACHED IMPLEMENTS
		for k,impl in pairs(targetVehicle:getAttachedImplements()) do
			courseplay:addToVehicleLocalIgnoreList(vehicle, impl.object);
		end;
	end;
end
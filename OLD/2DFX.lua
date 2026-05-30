EnumEffect2D = {
	Light = 0x00,
	ParticleEffect = 0x01,
	PedAttractor = 0x03,
	SunGlare = 0x04,
	EnterExit = 0x06,
	StreetSign = 0x07,
	TriggerPoint = 0x08,
	CovePoint = 0x09,
	Escalator = 0x0A
}

ClassesEffect2D = {}
--2DFX
class "Effect2D" { typeID = 0x0253F2F8,
	extend = "Section",
	count = false,
	effects = false,
	methodContinue = {
		read = function(self,readStream)
			self.count = readStream:read(uint32)
			local readSize = 4
			self.effects = {}
			local nextEffect2D
			repeat
				nextEffect2D = Effect2DBase()
				nextEffect2D:read(readStream)
				if not Effect2DIndex[nextEffect2D.entryType] then error("Unsupported 2DFX Entry Type: "..string.format("0x%08X",nextEffect2D.entryType)) end
				recastClass(nextEffect2D,Effect2DIndex[nextEffect2D.entryType])
				nextEffect2D:read(readStream)
				self.effects[#self.effects+1] = nextEffect2D
				readSize = readSize+nextEffect2D:getSize()
			until readSize == self.size
		end,
		write = function(self,writeStream)
			self.count = #self.effects
			writeStream:write(#self.effects,uint32)
			for i=1,#self.effects do
				self.effects[i]:write(writeStream)
			end
		end,
		getSize = function(self)
			local size = 4
			for i=1,#self.effects do
				size = size+self.effects[i]:getSize()
			end
			return 4
		end,
	}
}

EnumEffect2DLightShowMode = {
	Default = 0,
	RandomFlashing = 1,
	RandomFlashingAtWetWeather = 2,
	AnimSpeed4X = 3,
	AnimSpeed2X = 4,
	AnimSpeed1X = 5,
	Unused = 6,
	TrafficLight = 7,
	TrainCrossLight = 8,
	Disabled = 9,
	AtRainOnly = 10,
	On5S_Off5S = 11,
	On6S_Off4S = 11,
	On4S_Off6S = 12,
}

class "Effect2DBase" {
	position = false,
	entryType = false,
	size = false,
	read = function(self,readStream)
		if self.entryType then return true end
		self.position = {readStream:read(float),readStream:read(float),readStream:read(float)}
		self.entryType = readStream:read(uint32)
		self.size = readStream:read(uint32)
	end,
	write = function(self,writeStream)
		writeStream:write(self.position[1],float)
		writeStream:write(self.position[2],float)
		writeStream:write(self.position[3],float)
		writeStream:write(self.entryType,uint32)
		writeStream:write(self.size,uint32)
	end,
	getSize = function(self)
		return 20
	end,
}

class "Effect2DLight" {
	extend = "Effect2DBase",
	size = false,
	color = false,
	coronaFarClip = false,
	pointLightRange = false,
	coronaSize = false,
	shadowSize = false,
	coronaShowMode = false,
	coronaEnableReflection = false,
	coronaFlareType = false,
	shadowColorMultiplier = false,
	flags1 = false,
	--Casted From flags1
	coronaCheckObstacles = false,
	fogType1 = false,
	fogType2 = false,
	noCorona = false,
	onlyShowCoronaFar = false,
	atDay = false,
	atNight = false,
	blinkingType1 = false,
	--
	--Casted From flags2
	coronaOnlyFromBelow = false,
	blinkingType2 = false,
	updateHeightAboveGround = false,
	checkDirection = false,
	blinkingType3 = false,
	--
	coronaSize = false,
	shadowSize = false,
	shadowZDistance = false,
	flags2 = false,
	lookDirectionX = false,
	lookDirectionY = false,
	lookDirectionZ = false,
	methodContinue = {
		read = function(self,readStream)
			self.color = {readStream:read(uint8),readStream:read(uint8),readStream:read(uint8),readStream:read(uint8)}
			self.coronaFarClip = readStream:read(float)
			self.pointLightRange = readStream:read(float)
			self.coronaSize = readStream:read(float)
			self.shadowSize = readStream:read(float)
			self.coronaShowMode = readStream:read(uint8)
			self.coronaEnableReflection = readStream:read(uint8)
			self.coronaFlareType = readStream:read(uint8)
			self.shadowColorMultiplier = readStream:read(uint8)
			self.flags1 = readStream:read(uint8)
			self.coronaTexName = readStream:read(char,24)
			self.shadowTexName = readStream:read(char,24)
			self.shadowZDistance = readStream:read(uint8)
			self.flags2 = readStream:read(uint8)
			if self.size == 80 then
				self.lookDirectionX = readStream:read(uint8)
				self.lookDirectionY = readStream:read(uint8)
				self.lookDirectionZ = readStream:read(uint8)
				readStream:read(uint8)
			end
			readStream:read(uint8)
		end,
		write = function(self,writeStream)
			writeStream:write(self.color[1],uint8)
			writeStream:write(self.color[2],uint8)
			writeStream:write(self.color[3],uint8)
			writeStream:write(self.color[4],uint8)
			writeStream:write(self.coronaFarClip,float)
			writeStream:write(self.pointLightRange,float)
			writeStream:write(self.coronaSize,float)
			writeStream:write(self.shadowSize,float)
			writeStream:write(self.coronaShowMode,uint8)
			writeStream:write(self.coronaEnableReflection,uint8)
			writeStream:write(self.coronaFlareType,uint8)
			writeStream:write(self.shadowColorMultiplier,uint8)
			writeStream:write(self.flags1,uint8)
			writeStream:write(self.coronaTexName,char,24)
			writeStream:write(self.shadowTexName,char,24)
			writeStream:write(self.shadowZDistance,uint8)
			writeStream:write(self.flags2,uint8)
			if self.lookDirectionX and self.lookDirectionY and self.lookDirectionZ then
				writeStream:write(self.lookDirectionX,uint8)
				writeStream:write(self.lookDirectionY,uint8)
				writeStream:write(self.lookDirectionZ,uint8)
				writeStream:write(0,uint8)
			end
			writeStream:write(0,uint8)
		end,
		getSize = function(self)
			if self.lookDirectionX and self.lookDirectionY and self.lookDirectionZ then
				return 80
			else
				return 76
			end
		end,
	},
	getEffect2DSize = function(self)
		if self.lookDirectionX and self.lookDirectionY and self.lookDirectionZ then
			return 80
		else
			return 76
		end
	end,
}

class "Effect2DParticleEffect" {
	extend = "Effect2DBase",
	particleName = false,
	methodContinue = {
		read = function(self,readStream)
			self.particleName = readStream:read(char,24)
		end,
		write = function(self,writeStream)
			writeStream:write(self.particleName,char,24)
		end,
		getSize = function(self)
			return 24
		end,
	},
	getEffect2DSize = function(self)
		return 24
	end,
}

EnumEffect2DPedAttractor = {
	ATM = 0,			-- Ped uses ATM (at day time only)
	Seat = 1,			-- Ped sits (at day time only)
	Stop = 2,			-- Ped stands (at day time only)
	Pizza = 3,			-- Ped stands for few seconds
	Shelter = 4,		-- Ped goes away after spawning, but stands if weather is rainy
	ScriptTrigger = 5,	-- Launches an external script
	LooksAt = 6,		-- Ped looks at object, then goes away
	Scripted = 7,		-- This type is not valid
	Park = 8,			-- Ped lays (at day time only, ped goes away after 6 PM)
	Sit = 9,			-- Ped sits on steps
}

class "Effect2DPedAttractor" {
	extend = "Effect2DBase",
	attractorType = false,
	rotationMatrix = false,
	externalScriptName = false,
	pedExistingProbability = false,
	unused = false,
	methodContinue = {
		read = function(self,readStream)
			self.attractorType = readStream:read(uint32)
			self.rotationMatrix = {
				{readStream:read(float),readStream:read(float),readStream:read(float)},
				{readStream:read(float),readStream:read(float),readStream:read(float)},
				{readStream:read(float),readStream:read(float),readStream:read(float)},
			}
			self.externalScriptName = readStream:read(char,8)
			self.pedExistingProbability = readStream:read(int32)
			self.unused = readStream:read(uint32)
		end,
		write = function(self,writeStream)
			writeStream:write(self.attractorType,uint32)
			writeStream:write(self.rotationMatrix[1][1],float)
			writeStream:write(self.rotationMatrix[1][2],float)
			writeStream:write(self.rotationMatrix[1][3],float)
			writeStream:write(self.rotationMatrix[2][1],float)
			writeStream:write(self.rotationMatrix[2][2],float)
			writeStream:write(self.rotationMatrix[2][3],float)
			writeStream:write(self.rotationMatrix[3][1],float)
			writeStream:write(self.rotationMatrix[3][2],float)
			writeStream:write(self.rotationMatrix[3][3],float)
			writeStream:write(self.externalScriptName,char,8)
			writeStream:write(self.pedExistingProbability,int32)
			writeStream:write(self.unused,uint32)
		end,
		getSize = function(self)
			return 56
		end,
	},
	getEffect2DSize = function(self)
		return 56
	end,
}

class "Effect2DSunGlare" {
	extend = "Effect2DBase",
	getEffect2DSize = function(self)
		return 0
	end,
}

class "Effect2DEnterExit" {
	extend = "Effect2DBase",
	enterAngle = false,
	radiusX = false,
	radiusY = false,
	exitPosition = false,
	exitAngle = false,
	interior = false,
	flags = false,
	interiorName = false,
	skyColor = false,
	methodContinue = {
		read = function(self,readStream)
			self.enterAngle = readStream:read(float)
			self.radiusX = readStream:read(float)
			self.radiusY = readStream:read(float)
			self.exitPosition = {readStream:read(float),readStream:read(float),readStream:read(float)}
			self.exitAngle = readStream:read(float)
			self.interior = readStream:read(int32)
			self.flags = readStream:read(uint32)
			self.interiorName = readStream:read(char,8)
			self.skyColor = {readStream:read(uint8),readStream:read(uint8),readStream:read(uint8),readStream:read(uint8)}
		end,
		write = function(self,writeStream)
			writeStream:read(self.enterAngle,float)
			writeStream:read(self.radiusX,float)
			writeStream:read(self.radiusY,float)
			writeStream:read(self.exitPosition[1],float)
			writeStream:read(self.exitPosition[2],float)
			writeStream:read(self.exitPosition[3],float)
			writeStream:read(self.exitAngle,float)
			writeStream:read(self.interior,int32)
			writeStream:read(self.flags,uint32)
			writeStream:read(self.interiorName,char,8)
			writeStream:read(self.skyColor[1],uint8)
			writeStream:read(self.skyColor[2],uint8)
			writeStream:read(self.skyColor[3],uint8)
			writeStream:read(self.skyColor[4],uint8)
		end,
		getSize = function(self)
			return 48
		end,
	},
	getEffect2DSize = function(self)
		return 48
	end,
}

EnumEffect2DStreetSignLines = {
	LinesX4 = 0,
	LinesX1 = 1,
	LinesX2 = 2,
	LinesX3 = 3,
}
EnumEffect2DStreetSignSymbols = {
	SymbolsX16 = 0,
	SymbolsX2 = 1,
	SymbolsX4 = 2,
	SymbolsX8 = 3,
}
EnumEffect2DStreetSignColors = {
	White = 0,	--0xFFFFFFFF
	Black = 1,	--0xFF000000
	Gray = 2,	--0xFF808080
	Red = 3,	--0xFF0000FF
}
--The lines can start with arrows, such as <, ^ and >; also _ is used instead of a whitespace.
class "Effect2DStreetSign" {
	extend = "Effect2DBase",
	size = false,
	rotation = false,
	flags = false,
	text = false,
	methodContinue = {
		read = function(self,readStream)
			self.size = {readStream:read(float),readStream:read(float)}
			self.rotation = {readStream:read(float),readStream:read(float),readStream:read(float)}
			self.flags = readStream:read(uint16)
			self.text = {
				readStream:read(char,16),
				readStream:read(char,16),
				readStream:read(char,16),
				readStream:read(char,16),
			}
		end,
		write = function(self,writeStream)
			writeStream:write(self.size[1],float)
			writeStream:write(self.size[2],float)
			writeStream:write(self.rotation[1],float)
			writeStream:write(self.rotation[2],float)
			writeStream:write(self.rotation[3],float)
			writeStream:write(self.flags,uint16)
			writeStream:write(self.text[1],char,16)
			writeStream:write(self.text[2],char,16)
			writeStream:write(self.text[3],char,16)
			writeStream:write(self.text[4],char,16)
		end,
		getSize = function(self)
			return 88
		end,
	},
	getEffect2DSize = function(self)
		return 88
	end,
}

class "Effect2DTriggerPoint" {
	extend = "Effect2DBase",
	index = false,
	position = false,
	methodContinue = {
		read = function(self,readStream)
			self.index = readStream:read(uint32)
			self.position = {readStream:read(float),readStream:read(float),readStream:read(float)}
		end,
		write = function(self,writeStream)
			writeStream:write(self.index,uint32)
			writeStream:write(self.position[1],float)
			writeStream:write(self.position[2],float)
			writeStream:write(self.position[3],float)
		end,
		getSize = function(self)
			return 16
		end,
	},
	getEffect2DSize = function(self)
		return 4
	end,
}

class "Effect2DCoverPoint" {
	extend = "Effect2DBase",
	direction = false,
	coverType = false,
	methodContinue = {
		read = function(self,readStream)
			self.coverType = readStream:read(uint32)
			self.direction = {readStream:read(float),readStream:read(float)}
		end,
		write = function(self,writeStream)
			writeStream:write(self.direction[1],float)
			writeStream:write(self.direction[2],float)
			writeStream:write(self.coverType,uint32)
		end,
		getSize = function(self)
			return 12
		end,
	},
	getEffect2DSize = function(self)
		return 12
	end,
}

class "Effect2DEscalator" {
	extend = "Effect2DBase",
	positionBottom = false,		--Bottom of escalator x,y,z
	positionTop = false,		--Top of escalator x,y,z
	positionEnd = false,		--End of escalator x,y,z, Start position is "position"
	direction = false,			--Direction 0:down; 1:up
	methodContinue = {
		read = function(self,readStream)
			self.positionBottom = {readStream:read(float),readStream:read(float),readStream:read(float)}
			self.positionTop = {readStream:read(float),readStream:read(float),readStream:read(float)}
			self.positionEnd = {readStream:read(float),readStream:read(float),readStream:read(float)}
			self.direction = readStream:read(uint32)
		end,
		write = function(self,writeStream)
			writeStream:write(self.positionBottom[1],float)
			writeStream:write(self.positionBottom[2],float)
			writeStream:write(self.positionBottom[3],float)
			writeStream:write(self.positionTop[1],float)
			writeStream:write(self.positionTop[2],float)
			writeStream:write(self.positionTop[3],float)
			writeStream:write(self.positionEnd[1],float)
			writeStream:write(self.positionEnd[2],float)
			writeStream:write(self.positionEnd[3],float)
			writeStream:write(self.direction,uint32)
		end,
		getSize = function(self)
			return 40
		end,
	},
	getEffect2DSize = function(self)
		return 40
	end,
}

Effect2DIndex = {
	[0] = Effect2DLight,
	[1] = Effect2DParticleEffect,
	[3] = Effect2DPedAttractor,
	[4] = Effect2DSunGlare,
	[6] = Effect2DEnterExit,
	[7] = Effect2DStreetSign,
	[8] = Effect2DTriggerPoint,
	[9] = Effect2DCoverPoint,
	[10] = Effect2DEscalator,
}
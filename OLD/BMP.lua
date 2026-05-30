class "BMPHeader" {
	type = 0x4D42,	--[[
			BM = Windows 3.1x, 95, NT, Linux
			BA = OS/2 Bitmap Array
			CI = OS/2 Color Icon
			CP = OS/2 Color Pointer
			IC = OS/2 Icon
			Pt = OS/2 Pointer
		]]
	size = 0,	--Whole File Size
	reserved = 0, 	--Just Reserved
	dataOffset = 0,	--Bitmap Data Offsets from 0
	infoHeader = false,
	read = function(self,readStream)
		self.type = readStream:read(uint16)
		if self.type ~= 0x4D42 then error("Bad argument @BMPHeader, unsupported type 0x"..string.format("%04x",self.type)..". Only 0x4D42 is available" ) end 
		self.size = readStream:read(uint32)
		self.reserved = readStream:read(uint32)
		self.dataOffset = readStream:read(uint32)
		self.infoHeader = BMPInfoHeader()
		self.infoHeader:read(readStream)
	end,
	write = function(self,writeStream)
		writeStream:write(self.type,uint16)
		writeStream:write(self.size,uint32)
		writeStream:write(self.reserved,uint32)
		writeStream:write(self.dataOffset,uint32)
		self.infoHeader:write(writeStream)
	end,
	getSize = function(self)
		return self.infoHeader:getSize()+2+4+4+4
	end,
}

class "BMPInfoHeader" {
	size = 0,	--BMP Info Header size
	width =  0,		--Width in pixels
	height = 0, 	--Height in pixels
	planes = 0, 	--Number of planes
	bitCount = 0,--[[
		1 = Monochrome Bitmap
		4 = 4bit 16 Color Bitmap
		8 = 8bit 256 Color Bitmap
		16 = 16bit RGB High Color
		24 = 24bit RGB True Color
		32 = 32bit ARGB True Color with Alpha
	]]
	compression = 0,	--[[
		0 = None
		1 = RLE 8-bit
		2 = RLE 16-bit
		3 = Bitfields
		4 = JPEG
		5 = PNG
		]]
	sizeImage = 0,	--Image data size (should be multiple of 4), can be 0 if No Compression
	pixelsPerMeterX = 0,	--Horizontal resolution in pixel/meter (2800 is commonly used)
	pixelsPerMeterY = 0,	--Vertical resolution in pixel/meter (2800 is commonly used)
	usedColors = 0,			--How many colors is used in palette
	importantColors = 0,	--Important color, 0 for all
	palette = false,
	read = function(self,readStream)
		self.size = readStream:read(uint32)
		self.width = readStream:read(uint32)
		self.height = readStream:read(uint32)
		self.planes = readStream:read(uint16)
		self.bitCount = readStream:read(uint16)
		self.compression = readStream:read(uint32)
		if self.compression ~= 0 then error("Bad argument @BMPInfoHeader:read, Compressed BMP file is not implemented") end
		self.sizeImage = readStream:read(uint32)
		self.pixelsPerMeterX = readStream:read(uint32)
		self.pixelsPerMeterY = readStream:read(uint32)
		self.usedColors = readStream:read(uint32)
		self.importantColors = readStream:read(uint32)
		self.palette = BMPPalette()
		self.palette:read(readStream,self.usedColors)
	end,
	write = function(self,writeStream)
		self.usedColors = #self.palette.colors
		self.size = self:getSize()
		writeStream:write(self.size,uint32)
		writeStream:write(self.width,uint32)
		writeStream:write(self.height,uint32)
		writeStream:write(self.planes,uint16)
		writeStream:write(self.bitCount,uint16)
		writeStream:write(self.compression,uint32)
		writeStream:write(self.sizeImage,uint32)
		writeStream:write(self.pixelsPerMeterX,uint32)
		writeStream:write(self.pixelsPerMeterY,uint32)
		writeStream:write(self.usedColors,uint32)
		writeStream:write(self.importantColors,uint32)
		self.palette:write(writeStream)
	end,
	getSize = function(self)
		return 4+4+4+2+2+4+4+4+4+4+4+4*self.usedColors
	end,
}

class "BMPPalette" {
	colors = {},
	read = function(self,readStream,colorCount)
		for i=1,colorCount do
			colors[i] = {readStream:read(uint8),readStream:read(uint8),readStream:read(uint8)}
			readStream:read(uint8)	--Unused 0
		end
	end,
	write = function(self,writeStream)
		for i=1,#self.colors do
			writeStream:write(self.colors[i][1],uint8)
			writeStream:write(self.colors[i][2],uint8)
			writeStream:write(self.colors[i][3],uint8)
			writeStream:write(0,uint8)
		end
	end,
	set = function(self,index,r,g,b)
		if not(index >= 1 and index <= #self.colors) then error("Bad argument @BMPPalette:set at argument 1, out of range [1,"..#self.colors.."], got "..index) end
		colors[index][1] = r
		colors[index][2] = g
		colors[index][3] = b
	end,
	add = function(self,r,g,b)
		local newIndex = #self.colors+1
		self.colors[newIndex] = {r or 0,g or 0,b or 0}
		return newIndex
	end,
	getSize = function(self)
		return #self.colors*4
	end,
}

local tableInsert = table.insert
class "PixelData" {
	width = false,
	height = false,
	depth = false,
	dataType = false,
	data = false,
	read = function(self,readStream,size)
		self.dataType = "raw"
		self.data = readStream:read(bytes,size)
	end,
	write = function(self,writeStream)
		if self.dataType ~= "raw" then self:convert("raw") end
		writeStream:write(self.data,bytes,#self.data)
	end,
	getSize = function(self)
		return math.ceil(self.width*self.depth/8/4)*4*self.height
	end,
	addRow = function(self,insertID,fillColor)
		if self.dataType ~= "table" then self:convert("table") end
		self.height = self.height+1
		insertID = insertID or self.height
		fillColor = fillColor or 0xFFFFFFFF
		tableInsert(self.data,insertID or self.height,{})
		for w=1,self.width do
			self.data[insertID][w] = fillColor
		end
		return insertID
	end,
	addColumn = function(self,insertID,fillColor)
		if self.dataType ~= "table" then self:convert("table") end
		self.width = self.width+1
		insertID = insertID or self.width
		fillColor = fillColor or 0xFFFFFFFF
		for h=1,self.height do
			tableInsert(self.data[h],insertID,fillColor)
		end
		return insertID
	end,
	resize = function(self,width,height,resizeType)
		if self.dataType ~= "table" then self:convert("table") end
		local newData = {}
		local oldData = self.data
		local oldW,oldH = self.width,self.height
		if resizeType == "pixel" then
			for h=1,height do
				newData[h] = {}
				for w=1,width do
					local x,y = w/width*oldW,h/height*oldH
					local x,y = x-x%1+((x%1==0) and 0 or 1),y-y%1+((y%1==0) and 0 or 1)
					newData[h][w] = oldData[y][x]
				end
			end
			self.data = newData
			self.width = width
			self.height = height
		elseif resizeType == "mipmap" then
			self.data = newData
			self.width = width
			self.height = height
		end
	end,
	convert = function(self,toType)
		if toType == "raw"  then
			if self.dataType == "raw" then return true end
			self.dataType = "raw"
			local dataTable = self.data
			local writeStream = WriteStream()
			local readType = uint32
			if self.depth == 8 then readType = uint8 end
			if self.depth == 16 then readType = uint16 end
			if self.depth == 24 then readType = uint24 end
			for h=1,self.height do
				local height = self.height-h+1
				local writePos = writeStream.writingPos
				for w=1,self.width do
					writeStream:write(dataTable[height][w],readType)
				end
				local rest = (4-(writeStream.writingPos-writePos))%4
				if rest ~= 0 then
					writeStream:write("\0",bytes,rest)	--padding
				end
			end
			self.data = writeStream:save()
		elseif toType == "table" then
			if self.dataType == "table" then return true end
			self.dataType = "table"
			local dataStr = self.data
			local readStream = ReadStream(dataStr)
			self.data = {nil,nil,nil,nil,nil,nil,nil,nil}
			local readType = uint32
			if self.depth == 8 then readType = uint8 end
			if self.depth == 16 then readType = uint16 end
			if self.depth == 24 then readType = uint24 end
			for h=1,self.height do
				local height = self.height-h+1
				self.data[height] = {nil,nil,nil,nil,nil,nil,nil,nil}
				local readPos = readStream.readingPos
				for w=1,self.width do
					self.data[height][w] = readStream:read(readType)
				end
				local rest = (4-(readStream.readingPos-readPos))%4
				if rest ~= 0 then
					readStream:read(bytes,rest)	--padding
				end
			end
		end
	end
}

class "BMP" {
	header = BMPHeader(),
	infoHeader = BMPInfoHeader(),
	pixels = false,
	read = function(self,readStream)
		self.header:read(readStream)
		readStream.readingPos = self.header.dataOffset+1
		local readBytes = self.header.size-self.header.dataOffset
		self.pixels = PixelData()
		self.pixels.width = self.header.infoHeader.width
		self.pixels.height = self.header.infoHeader.height
		self.pixels.depth = self.header.infoHeader.bitCount
		self.pixels:read(readStream,readBytes)
	end,
	write = function(self,writeStream)
		writeStream = writeStream or WriteStream()
		self.header.infoHeader.width = self.pixels.width
		self.header.infoHeader.height = self.pixels.height
		self.header.infoHeader.bitCount = self.pixels.depth
		self.header.size = self:getSize()
		self.header:write(writeStream)
		self.pixels:write(writeStream)
		return writeStream
	end,
	getSize = function(self)
		return self.header:getSize()+self.pixels:getSize()
	end,
	save = function(self,fileName)
		local writeStream = self:write()
		local file = fileCreate(fileName)
		fileWrite(file,writeStream:save())
		fileClose(file)
	end,
	load = function(self,rawOrPath)
		if type(rawOrPath) ~= "string" then error("Bad argument @BMP:load at argument 1, expect a string got "..type(rawOrPath)) end
		local strToLoad = rawOrPath
		if #rawOrPath <= 1024 and fileExists(rawOrPath) then
			local file = fileOpen(rawOrPath,true)
			strToLoad = fileRead(file,fileGetSize(file))
			fileClose(file)
		end
		local readStream = ReadStream(strToLoad)
		self:read(readStream)
	end,
}
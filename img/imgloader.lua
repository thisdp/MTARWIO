-- img/imgloader.lua — GTA IMG 归档读取器

-- 生成带缓存的文件流
function genFileStream()
    return {
        usingRaw = false,
        file = false,
        cacheSize = 1024 * 1024,
        cachedString = "",
        cachedIndex = false,

        loadFile = function(self, fname)
            if fileExists(fname) then
                self.file = fname
            else
                self.file = fname
                self.usingRaw = true
            end
        end,

        clearCache = function(self)
            self.cachedIndex = false
            self.cachedString = ""
        end,

        cache = function(self, offset)
            local f = fileOpen(self.file)
            fileSetPos(f, offset)
            self.cachedString = fileRead(f, self.cacheSize)
            self.cachedIndex = offset
            fileClose(f)
        end,

        get = function(self, offset, bytes, direct)
            if self.usingRaw then
                return self.file:sub(offset + 1, offset + bytes)
            elseif direct then
                local f = fileOpen(self.file)
                fileSetPos(f, offset)
                local str = fileRead(f, bytes)
                fileClose(f)
                return str
            else
                if not self.cachedIndex then self:cache(offset) end
                local cacheStart = self.cachedIndex
                local cacheEnd = self.cachedIndex + self.cacheSize
                local readStart, readEnd = offset, offset + bytes
                if readStart >= cacheStart then
                    if readStart >= cacheEnd then
                        self:cache(readStart)
                        return self:get(offset, bytes)
                    end
                    if readEnd <= cacheEnd then
                        return self.cachedString:sub(readStart - cacheStart + 1, readEnd - cacheStart)
                    else
                        local str = self.cachedString:sub(readStart - cacheStart + 1)
                        while true do
                            self:cache(self.cachedIndex + self.cacheSize)
                            local newCacheEnd = self.cachedIndex + self.cacheSize
                            if newCacheEnd >= readEnd then
                                str = str .. self.cachedString:sub(1, readEnd - self.cachedIndex)
                                break
                            else
                                str = str .. self.cachedString
                            end
                        end
                        return str
                    end
                else
                    self:cache(readStart)
                    return self:get(offset, bytes)
                end
            end
        end,
    }
end

-- 加载 IMG 容器
function engineLoadIMGContainer(file)
    local fs = genFileStream()
    fs:loadFile(file)

    local imgFile = {
        files = {},
        directory = {},
        directoryNameToIndex = {},
    }

    local pos = 0
    imgFile.version = fs:get(pos, 4)
    pos = pos + 4
    imgFile.entriesCount = 0
    do
        local str = fs:get(pos, 4)
        for i = 1, 4 do
            imgFile.entriesCount = imgFile.entriesCount + str:sub(i, i):byte() * 0x100 ^ (i - 1)
        end
    end
    pos = pos + 4

    for index = 1, imgFile.entriesCount do
        local offset = 0
        do
            local str = fs:get(pos, 4)
            for i = 1, 4 do
                offset = offset + str:sub(i, i):byte() * 0x100 ^ (i - 1)
            end
        end
        pos = pos + 4

        local streamingSize = 0
        do
            local str = fs:get(pos, 2)
            for i = 1, 2 do
                streamingSize = streamingSize + str:sub(i, i):byte() * 0x100 ^ (i - 1)
            end
        end
        pos = pos + 2

        local sizeInArchive = 0
        do
            local str = fs:get(pos, 2)
            for i = 1, 2 do
                sizeInArchive = sizeInArchive + str:sub(i, i):byte() * 0x100 ^ (i - 1)
            end
        end
        pos = pos + 2

        local name = fs:get(pos, 24):gsub("%z.*", "")
        pos = pos + 24

        imgFile.directory[index] = {
            name = name,
            streamingSize = streamingSize * 2048,
            sizeInArchive = sizeInArchive * 2048,
            offset = offset * 2048,
        }
        imgFile.directoryNameToIndex[name] = index
    end

    fs:clearCache()

    imgFile.getFile = function(self, name)
        local idx = imgFile.directoryNameToIndex[name]
        if idx then
            local dir = imgFile.directory[idx]
            return fs:get(dir.offset, dir.streamingSize, true)
        end
        return false
    end

    imgFile.fileExists = function(self, name)
        return imgFile.directoryNameToIndex[name] and true or false
    end

    imgFile.listFiles = function(self)
        local list = {}
        for i = 1, #imgFile.directory do
            list[i] = imgFile.directory[i].name
        end
        return list
    end

    return imgFile
end

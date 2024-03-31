--!native
--!optimize 2
--!nocheck

--[[

	Roblox Video Codec
	Made by iceeburr with 💖 and 🧊
	STILL IN DEVELOPMENT, NOT READY FOR USE!

]]

local videoPlayer = {}

--// Base Functions & Constants \\--

local parallelScheduler = require(script.parallelScheduler):LoadModule(script.worker)

local readu8 = buffer.readu8
local bufcreate = buffer.create
local buftostring = buffer.tostring
local _fromstring = buffer.fromstring
local buflen = buffer.len
local rshift = bit32.rshift
local lshift = bit32.lshift
local band = bit32.band
local bor = bit32.bor

local function combineBytes(high: number, low: number): number
	return bor(low, lshift(high, 8))
end

function _toHex(num: number): string
	return string.format("%X", num)
end

buffer.create(10)

local function DQT(index: number, databuffer: buffer)
	local quant: {} = table.create(66)
	local header = readu8(databuffer, 0)
	quant["p"] = rshift(header, 4)
	quant["i"] = band(header, 0x0F)
	if quant["p"] == 1 then
		for j = 1, 64 do
			quant[j] = combineBytes(readu8(databuffer, j), readu8(databuffer, j + 1))
		end
	else
		for j = 1, 64 do
			quant[j] = readu8(databuffer, j)
		end
	end
	return quant
end

local function SOF0(index: number, databuffer: buffer) end

local function DHT(index: number, databuffer: buffer) end

local function DRI(index: number, databuffer: buffer) end

local function SOS(index: number, databuffer: buffer) end

local procedures = {
	[0xDB] = DQT,
	[0xC0] = SOF0,
	[0xC4] = DHT,
	[0xDD] = DRI,
	[0xDA] = SOS,
}

--// Module API \\--

function videoPlayer.decode(databuffer: buffer): ()
	-- Check for the JPEG signature
	if readu8(databuffer, 0) ~= 0xFF or readu8(databuffer, 1) ~= 0xD8 or readu8(databuffer, 2) ~= 0xFF then
		error("File is not a JPEG")
	end

	-- Decode required data in parallel
	local _jpegData = {}
	local index = 2
	local length = buflen(databuffer) - 2
	while index < length do
		if readu8(databuffer, index) == 0xFF then
			local markerType = readu8(databuffer, index + 1)
			local markerLength = combineBytes(readu8(databuffer, index + 2), readu8(databuffer, index + 3))
			local _result = procedures[markerType](index, databuffer)

			if
				markerType == 0xDB
				or markerType == 0xC0
				or markerType == 0xC4
				or markerType == 0xDD
				or markerType == 0xDA
			then
				local workerData = bufcreate(markerLength - 2)
				buffer.copy(workerData, 0, databuffer, index + 4, markerLength - 2)
				parallelScheduler:ScheduleWork(markerType, buftostring(workerData))
				if markerType == 0xDA then
					break
				end
				index += 2 + markerLength
			elseif markerType == 0xDD then
				index += 4
			else
				index += 2 + markerLength
			end
		else
			warn("--// ERROR DEBUG INFORMATION \\--")
			warn("Index:", index)
			warn("Byte:", readu8(databuffer, index))
			warn("Previous byte:", readu8(databuffer, index - 1))
			warn("Next byte:", readu8(databuffer, index + 1))
			warn("Processed markers:")
			error("Internal error: lost buffer offset.")
		end
	end
end

return videoPlayer

--!native
--!optimize 2

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
local bufcopy = buffer.copy
local _rshift = bit32.rshift
local lshift = bit32.lshift
local _band = bit32.band
local bor = bit32.bor

local function combineBytes(high: number, low: number): number
	return bor(low, lshift(high, 8))
end

function _toHex(num: number): string
	return string.format("%X", num)
end

--// Module API \\--

function videoPlayer.decode(databuffer: buffer): ()
	-- Check for the JPEG signature
	if readu8(databuffer, 0) ~= 0xFF or readu8(databuffer, 1) ~= 0xD8 or readu8(databuffer, 2) ~= 0xFF then
		error("File is not a JPEG")
	end

	-- Decode required data in parallel
	local index = 2
	local processedMarkers = 0
	while index < buflen(databuffer) - 2 do
		if readu8(databuffer, index) == 0xFF then
			local markerType = readu8(databuffer, index + 1)
			local markerLength = combineBytes(readu8(databuffer, index + 2), readu8(databuffer, index + 3))
			if
				markerType == 0xDB
				or markerType == 0xC0
				or markerType == 0xC4
				or markerType == 0xDD
				or markerType == 0xDA
			then
				local workerData = bufcreate(markerLength - 2)
				bufcopy(workerData, 0, databuffer, index + 4, markerLength - 2)
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
			warn("Processed markers:", processedMarkers)
			error("Internal error: lost buffer offset.")
		end
		processedMarkers += 1
	end
	local timenow = os.clock()
	local _results = parallelScheduler:Work()
	print("end time:", os.clock() - timenow)
end

return videoPlayer

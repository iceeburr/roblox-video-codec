--!native
--!optimize 2
--!strict

--[[

	Roblox Video Codec
	Made by iceeburr with 💖 and 🧊
	STILL IN DEVELOPMENT, NOT READY FOR USE!

	--// Short Documentation \\--
	`#`  - function
	`--` - comment
	`->` - value returned by the function

	# require(modulePath) -> rbxvideo
	-- Returns the module.

	# rbxvideo.new(videodata: buffer) -> videostream
	-- Constructs a new videostream from the encoded videodata.

	# videostream.Decode(frame: number) -> pixelData
	-- Decodes the frame at the given position and returns the pixel data ready to be used by an EditableImage.
	
]]

local rbxvideo = {}

--// Simple Typechecking \\--

export type pixelData = { r: number, g: number, b: number, a: number }
export type videostream = { Decode: () -> pixelData }

function rbxvideo.new(videodata: buffer): videostream
	-- Check for the JPEG signature
	if
		buffer.readu8(videodata, 0) ~= 0xFF
		or buffer.readu8(videodata, 1) ~= 0xD8
		or buffer.readu8(videodata, 2) ~= 0xFF
	then
		error("File is not a JPEG")
	end

	--// Base Functions & Constants \\--

	local _parallelScheduler: any = require(script.parallelScheduler):LoadModule(script.worker)

	local readu8 = buffer.readu8
	local buflen = buffer.len
	local rshift = bit32.rshift
	local lshift = bit32.lshift
	local band = bit32.band
	local bor = bit32.bor

	local jpegData: { any } = { {}, {}, {}, {} }

	local function combineBytes(high: number, low: number): number
		return bor(low, lshift(high, 8))
	end

	local function DQT(index: number, length: number): ()
		local quant: {} = table.create(64)
		local header = readu8(videodata, index)
		if rshift(header, 4) == 0 then
			for j = 1, 64 do
				quant[j] = readu8(videodata, index + j)
			end
		else
			warn("Warning - DQT has precision 1 (not tested)")
			for j = 1, 128 do
				quant[j] = combineBytes(readu8(videodata, index + j), readu8(videodata, index + j + 1))
			end
		end
		jpegData[1][band(header, 0x0F) + 1] = quant
	end

	local function SOF0(index: number, length: number): ()
		local frameData: { any } = {
			readu8(videodata, index),
			combineBytes(readu8(videodata, index + 3), readu8(videodata, index + 4)), -- Width (xResolution)
			combineBytes(readu8(videodata, index + 1), readu8(videodata, index + 2)), -- Heigth (yResolution)
			{},
		}
		for i = 0, readu8(videodata, index + 5) - 1 do
			local offset = index + (i * 3)
			local sampleFactor = readu8(videodata, offset + 7)
			frameData[4][i + 1] = {
				bit32.band(bit32.rshift(sampleFactor, 4), 0x0F),
				bit32.band(bit32.rshift(sampleFactor, 4), 0x0F),
				readu8(videodata, offset + 8),
			}
		end
		jpegData[2] = frameData
	end

	local function DHT(index: number, length: number) end

	local function DRI(index: number, length: number): ()
		jpegData[5] = combineBytes(readu8(videodata, index - 2), readu8(videodata, index - 1))
	end

	local function SOS(index: number, length: number) end

	local procedures = {
		[0xDB] = DQT,
		[0xC0] = SOF0,
		[0xC4] = DHT,
		[0xDD] = DRI,
		[0xDA] = SOS,
	}

	--// Module API \\--
	return {
		Decode = function(): any
			local index = 2
			-- Decode Required Data (everything before the entropy-coded image data)
			while index < buflen(videodata) - 2 do
				if readu8(videodata, index) == 0xFF then
					local markerType = readu8(videodata, index + 1)
					local procedure = procedures[markerType]
					if procedure then
						local length = combineBytes(readu8(videodata, index + 2), readu8(videodata, index + 3))
						procedure(index + 4, length - 2)
						if markerType == 0xDA then
							break
						elseif markerType == 0xDD then
							index += 4
							continue
						end
						index += 2 + length
					else
						index += 2 + combineBytes(readu8(videodata, index + 2), readu8(videodata, index + 3))
					end
				else
					error("Internal error: lost buffer offset.")
				end
			end
			return jpegData
		end,
	}
end

return rbxvideo

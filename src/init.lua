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

	local jpegData: { any } = { {}, {}, {}, {}, 0, {} }

	local function combineBytes(high: number, low: number): number
		return bor(low, lshift(high, 8))
	end

	local function DQT(index: number, length: number): ()
		local b = 0
		local quant: any = table.create(64)
		while b < length do
			local header = readu8(videodata, index + b)
			if rshift(header, 4) == 0 then
				for j = 1, 64 do
					quant[j] = readu8(videodata, index + b + j)
				end
			else
				local offset
				for j = 0, 63 do
					offset = index + b + (j * 2)
					quant[j + 1] = combineBytes(readu8(videodata, offset + 1), readu8(videodata, offset + 2))
				end
			end
			b += 65
			table.insert(jpegData[1], { band(header, 0x0F), quant })
		end
	end

	local function SOF0(index: number): ()
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
				band(rshift(sampleFactor, 4), 0x0F),
				band(rshift(sampleFactor, 4), 0x0F),
				readu8(videodata, offset + 8),
			}
		end
		jpegData[2] = frameData
	end

	local function DHT(index: number, length: number): ()
		local tableType = readu8(videodata, index)
		table.insert(jpegData[3], { band(rshift(tableType, 4), 0x0F), band(tableType, 0x0F) })
	end

	local function SOS(index: number): ()
		for i = 0, readu8(videodata, index) - 1 do
			local offset = index + (i * 2)
			local huffmanID = readu8(videodata, offset + 2)
			jpegData[4][i + 1] = { band(rshift(huffmanID, 4), 0x0F), band(huffmanID, 0x0F) }
		end
	end

	local function DRI(index: number): ()
		jpegData[5] = combineBytes(readu8(videodata, index - 2), readu8(videodata, index - 1))
	end

	local procedures = {
		[0xDB] = DQT,
		[0xC0] = SOF0,
		[0xC4] = DHT,
		[0xDA] = SOS,
		[0xDD] = DRI,
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

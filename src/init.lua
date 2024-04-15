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
	--// Base Functions & Constants \\--

	-- Local is faster than global
	local readu8 = buffer.readu8
	local buflen = buffer.len
	local rshift = bit32.rshift
	local lshift = bit32.lshift
	local band = bit32.band
	local bor = bit32.bor
	local tableinsert = table.insert
	local tablecreate = table.create

	-- Check for the JPEG signature
	if readu8(videodata, 0) ~= 0xFF or readu8(videodata, 1) ~= 0xD8 or readu8(videodata, 2) ~= 0xFF then
		error("File is not a JPEG")
	end

	--[[
		Initialize the data structure
		 1 - DQT  | First for Luminance, second for Chrominance
		 2 - SOFn | Precision, Width, Height, Components 
		 3 - DHT  | First for DC, second for AC | First for Luminance, second for Chrominance
		 4 - SOS  | Components
		 5 - DRI
		 6 - Pixel Data
	]]
	local jpegData: { any } = { { {}, {} }, {}, { { {}, {} }, { {}, {} } }, {}, 0, {} }

	-- Don't get mixed up with readu16, they are completely different.
	local function combineBytes(high: number, low: number): number
		return bor(low, lshift(high, 8))
	end

	-- Huffman
	local function BitsFromLength(root: {}, element: number, pos: number): boolean
		if type(root) == "table" then
			if pos == 0 then
				if #root < 2 then
					tableinsert(root, element)
					return true
				end
				return false
			end
			for i = 0, 1 do
				if #root == i then
					tableinsert(root, {})
				end
				if BitsFromLength(root[i + 1], element, pos - 1) == true then
					return true
				end
			end
		end
		return false
	end

	local function ConstructTree(lengths: {}, elements: {}): ()
		local huffmanTable = {}
		local k = 1
		for i = 1, #lengths do
			for _ = 1, lengths[i] do
				BitsFromLength(huffmanTable, elements[k], i - 1)
				k += 1
			end
		end
		return huffmanTable
	end

	-- Quantization table(s)
	local function DQT(index: number, length: number): ()
		local b = 0
		local quant: any = tablecreate(64)
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
			tableinsert(jpegData[1][band(header, 0x0F) + 1], quant)
		end
	end

	-- Start of frame data
	local function SOF0(index: number): ()
		local frameData: { any } = {
			readu8(videodata, index), -- Precision
			combineBytes(readu8(videodata, index + 3), readu8(videodata, index + 4)), -- Width (xResolution)
			combineBytes(readu8(videodata, index + 1), readu8(videodata, index + 2)), -- Heigth (yResolution)
			{}, -- Components
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

	-- Huffman table(s)
	local function DHT(index: number, length: number): ()
		local b = 0
		while b < length do
			local header = readu8(videodata, index + b)
			local lengths = table.create(16)
			local symbols = {}
			for j = 1, 16 do
				lengths[j] = readu8(videodata, index + j + b)
			end
			b += 17
			for _, length in pairs(lengths) do
				for _ = 1, length do
					tableinsert(symbols, readu8(videodata, index + b))
					b += 1
				end
			end
			tableinsert(
				jpegData[3][band(rshift(header, 4), 0x0F) + 1][band(header, 0x0F) + 1],
				ConstructTree(lengths, symbols)
			)
		end
	end

	-- Start of scan
	local function SOS(index: number): ()
		for i = 0, readu8(videodata, index) - 1 do
			local offset = index + (i * 2)
			local huffmanID = readu8(videodata, offset + 2)
			jpegData[4][i + 1] = { band(rshift(huffmanID, 4), 0x0F), band(huffmanID, 0x0F) }
		end

		-- Compressed Image Data
	end

	-- Define restart interval (might be removed)
	local function DRI(index: number): ()
		jpegData[5] = combineBytes(readu8(videodata, index - 2), readu8(videodata, index - 1))
	end

	-- To avoid many nested if statements a simple table is used. The private functions shouldn't return anything anyways.
	local procedures = {
		[0xDB] = DQT,
		[0xC0] = SOF0,
		[0xC4] = DHT,
		[0xDA] = SOS,
		[0xDD] = DRI,
	}

	--// Module API \\--
	return {
		Decode = function(): any -- pixelData
			local index = 2
			-- Decode Required Data (everything before the entropy-coded image data)
			while index < buflen(videodata) - 2 do
				if readu8(videodata, index) == 0xFF then
					local markerType = readu8(videodata, index + 1)
					local procedure = procedures[markerType]
					if procedure then -- Required procedures
						local length = combineBytes(readu8(videodata, index + 2), readu8(videodata, index + 3))
						procedure(index + 4, length - 2)
						if markerType == 0xDA then -- Break if start of scan
							break
						elseif markerType == 0xDD then -- Edge case for DRI
							index += 4
							continue
						end
						index += 2 + length
					else -- Useless markers
						index += 2 + combineBytes(readu8(videodata, index + 2), readu8(videodata, index + 3))
					end
				else
					-- Currently it might glitch out for parameterless markers like SOI and EOI
					error("Internal error: lost buffer offset.")
				end
			end
			return jpegData
			-- return jpegData[6]
		end,
	}
end

return rbxvideo

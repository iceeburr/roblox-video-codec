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
type bitStream = { ReadBit: () -> number, ReadBits: (length: number) -> number, Align: () -> () }

function rbxvideo.new(videodata: buffer): videostream
	--// Base Functions & Constants \\--

	-- Local is faster than global
	local readu8 = buffer.readu8
	local writeu8 = buffer.writeu8
	local buflen = buffer.len
	local bufcreate = buffer.create
	local rshift = bit32.rshift
	local lshift = bit32.lshift
	local band = bit32.band
	local bor = bit32.bor
	local tableinsert = table.insert
	local tablecreate = table.create
	local floor = math.floor
	local pow = math.pow
	local max = math.max
	local sqrt = math.sqrt
	local cos = math.cos
	local _clamp = math.clamp
	local pi = math.pi

	-- Check for the JPEG signature
	if readu8(videodata, 0) ~= 0xFF or readu8(videodata, 1) ~= 0xD8 or readu8(videodata, 2) ~= 0xFF then
		error("File is not a JPEG")
	end

	local previousDCs = { 0, 0, 0, 0 }
	local maxHorizontalSample = 0
	local maxVerticalSample = 0
	local mcus = {}

	-- Create idct LUT
	local idctTable = {}

	local function NormCoeff(n)
		if n == 0 then
			return sqrt(1 / 8)
		else
			return sqrt(2 / 8)
		end
	end

	for i = 0, 7 do
		for j = 0, 7 do
			local grid = {}

			for y = 0, 7 do
				for x = 0, 7 do
					local nn = NormCoeff(j) * cos(j * pi * (x + 0.5) / 8)
					local mm = NormCoeff(i) * cos(i * pi * (y + 0.5) / 8)

					grid[x * 8 + y + 1] = nn * mm
				end
			end

			idctTable[i * 8 + j + 1] = grid
		end
	end

	-- Zigzag LUTs
	local zigzag1D = {
		1,
		2,
		9,
		17,
		10,
		3,
		4,
		11,
		18,
		25,
		33,
		26,
		19,
		12,
		5,
		6,
		13,
		20,
		27,
		34,
		41,
		49,
		42,
		35,
		28,
		21,
		14,
		7,
		8,
		15,
		22,
		29,
		36,
		43,
		50,
		57,
		58,
		51,
		44,
		37,
		30,
		23,
		16,
		24,
		31,
		38,
		45,
		52,
		59,
		60,
		53,
		46,
		39,
		32,
		40,
		47,
		54,
		61,
		62,
		55,
		48,
		56,
		63,
		64,
	}

	--[[
		Initialize the data structure
		 1 - DQT  | First for Luminance, second for Chrominance
		 2 - SOFn | Precision, Width, Height, Components 
		 3 - DHT  | First for DC, second for AC | First for Luminance, second for Chrominance
		 4 - SOS  | Components
		 5 - DRI
		 6 - Pixel Data
		 7 - Temporary Pixel Data
	]]
	local jpegData: { any } = { { {}, {} }, {}, { {}, {} }, {}, 0, {}, {} }

	-- Don't get mixed up with readu16, they are completely different.
	local function combineBytes(high: number, low: number): number
		return bor(low, lshift(high, 8))
	end

	local function DecodeNumber(code: number, bits: number): number
		local l = pow(2, code - 1)

		if bits >= l then
			return bits
		else
			return bits - (2 * l - 1)
		end
	end

	-- Bitstream
	local nextByte = 0
	local nextBit = 0
	local function ReadBit(scanBuffer: buffer): number
		if nextByte >= buflen(scanBuffer) then
			return -1
		end
		local bit = band(rshift(readu8(scanBuffer, nextByte + 1), (7 - nextBit)), 1)
		nextBit = nextBit + 1
		if nextBit == 8 then
			nextBit = 0
			nextByte = nextByte + 1
		end
		return bit
	end
	local function ReadBits(length: number, scanBuffer: buffer): number
		local bits = 0
		for i = 1, length do
			local bit = ReadBit(scanBuffer)
			if bit == -1 then
				bits = -1
				break
			end
			bits = bor(lshift(bits, 1), bit)
		end
		return bits
	end
	local function Align(scanBuffer: buffer): ()
		if nextByte >= buflen(scanBuffer) then
			return
		end
		if nextBit ~= 0 then
			nextBit = 0
			nextByte = nextByte + 1
		end
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

	local function GetNextSymbolFromHuffmanTable(huffmanTable, scanBuffer: buffer)
		local length = 0
		while type(huffmanTable) == "table" do
			huffmanTable = huffmanTable[ReadBit(scanBuffer) + 1]
			length += 1
		end
		return huffmanTable, length
	end

	local function GetCode(huffmanTable, scanBuffer: buffer): any
		while true do
			local result = GetNextSymbolFromHuffmanTable(huffmanTable, scanBuffer)
			if result == nil then
				return -1
			end
			return result
		end
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
			jpegData[1][band(header, 0x0F) + 1] = quant
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

		-- Fill in image with blank data
		for x = 1, frameData[2] do
			jpegData[7][x] = {}

			for y = 1, frameData[3] do
				jpegData[7][x][y] = { 0, 0, 0 }
			end
		end

		-- Create mcus
		local mcuCountX = floor((frameData[2] - 1) / 8)
		local mcuCountY = floor((frameData[3] - 1) / 8)
		local componentCount = readu8(videodata, index + 5)
		for x = 1, mcuCountX + 8 do
			mcus[x] = {}
			for y = 1, mcuCountY + 8 do
				mcus[x][y] = {}
				for i = 1, componentCount do
					mcus[x][y][i] = table.create(64, 0)
				end
			end
		end

		jpegData[6] = tablecreate(frameData[2] * frameData[3] * 4)

		for i = 0, componentCount - 1 do
			local offset = index + (i * 3)
			local sampleFactor = readu8(videodata, offset + 7)
			local horizontalSample = band(rshift(sampleFactor, 4), 0x0F)
			local verticalSample = band(rshift(sampleFactor, 4), 0x0F)
			maxHorizontalSample = max(maxHorizontalSample, horizontalSample)
			maxVerticalSample = max(maxVerticalSample, verticalSample)
			frameData[4][i + 1] = {
				horizontalSample,
				verticalSample,
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
			jpegData[3][band(rshift(header, 4), 0x0F) + 1][band(header, 0x0F) + 1] = ConstructTree(lengths, symbols)
		end
	end

	-- Start of scan
	local function SOS(index: number, length: number): ()
		for i = 0, readu8(videodata, index) - 1 do
			local offset = index + (i * 2)
			local huffmanID = readu8(videodata, offset + 2)
			jpegData[4][i + 1] = { band(rshift(huffmanID, 4), 0x0F), band(huffmanID, 0x0F) }
		end
		index += length + 1

		-- Compressed Image Data
		local scanBuffer = bufcreate(52000) -- temporary
		local pointer = 0
		while index < buflen(videodata) - 2 do
			local byte = readu8(videodata, index)
			if byte == 0xFF then
				local nextByte = readu8(videodata, index + 1)
				if nextByte == 0x00 then
					writeu8(scanBuffer, pointer, byte)
					index += 2
					pointer += 1
					continue
				elseif nextByte >= 0xD0 and nextByte <= 0xD7 then
					index += 2
					continue
				else
					error("Internal error: found invalid 0xFF in scan ")
				end
			else
				writeu8(scanBuffer, pointer, byte)
				index += 1
				pointer += 1
			end
		end

		local mcuCountX = floor((jpegData[2][2] - 1) / 8)
		local mcuCountY = floor((jpegData[2][3] - 1) / 8)
		local restartInterval = jpegData[5]
		local restartCount = restartInterval
		local decodedMCUCount = 0

		local function BaselineDecodeMCUComponent(mcu, component: number)
			-- Decode DC component
			local code = GetCode(jpegData[3][1][jpegData[4][component][1]], scanBuffer)
			local actualID = jpegData[2][4][component][3] + 1
			local prevDC = previousDCs[actualID]

			if prevDC == nil then
				prevDC = 0
			end

			local bits = ReadBits(code, scanBuffer)
			local dccoeff = DecodeNumber(code, bits) + prevDC

			previousDCs[actualID] = dccoeff -- Set previous DC

			mcu[1] = dccoeff

			-- Decode AC components
			local i = 1
			while i < 64 do
				code = GetCode(jpegData[3][2][jpegData[4][component][2]], scanBuffer)
				if code == 0 then
					return
				end
				if code > 16 then -- AC table
					i = i + rshift(code, 4) -- Num zeros which we skip
					code = band(code, 0x0F)
				end
				bits = ReadBits(code, scanBuffer)
				if i < 64 then
					i = i + 1
					local accoeff = DecodeNumber(code, bits)
					mcu[i] = accoeff
				end
			end
		end

		for y = 0, mcuCountY, maxVerticalSample do
			for x = 0, mcuCountX, maxHorizontalSample do
				for i, component in pairs(jpegData[2][4]) do
					local horizontalSample = component[1]
					local verticalSample = component[2]

					for v = 0, verticalSample - 1 do
						for h = 0, horizontalSample - 1 do
							local mcuX = x + h + 1
							local mcuY = y + v + 1

							BaselineDecodeMCUComponent(mcus[mcuX][mcuY][i], i)
						end
					end

					decodedMCUCount = decodedMCUCount + (verticalSample * horizontalSample)
				end

				-- Restart Interval
				if restartInterval ~= 0 then
					restartCount = restartCount - 1

					if restartCount == 0 then
						restartCount = restartInterval

						previousDCs = { 0, 0, 0 }
						Align(scanBuffer)
					end
				end
			end
		end

		local iLimit = (8 * maxVerticalSample) - 1
		local jLimit = (8 * maxHorizontalSample) - 1

		local subtractFromX = 2
		local subtractFromY = 2

		if maxHorizontalSample == 2 then
			subtractFromX = 3
		end
		if maxVerticalSample == 2 then
			subtractFromY = 3
		end

		for i, component in pairs(jpegData[2][4]) do
			local actualID = component[3] + 1
			local componentHorizontalSample = component[1]
			local componentVerticalSample = component[2]
			local quantisationTable = jpegData[1][actualID]
			for y = 0, mcuCountY, maxVerticalSample do
				for x = 0, mcuCountX, maxHorizontalSample do
					for v = 0, componentVerticalSample - 1 do
						for h = 0, componentHorizontalSample - 1 do
							local mcuX = x + h + 1
							local mcuY = y + v + 1

							-- IDCT
							local decodedMCU = tablecreate(64, 0)

							for j, influence in pairs(mcus[mcuX][mcuY][actualID]) do
								if influence == 0 then
									continue
								end

								if j > 64 then
									break
								end

								local zigzagIndex = zigzag1D[j]
								local quantisedInfluence = influence * quantisationTable[j]

								local idctLUT = idctTable[zigzagIndex]

								for k = 1, 64 do
									decodedMCU[k] = decodedMCU[k] + (idctLUT[k] * quantisedInfluence)
								end
							end

							-- Fill in pixel image
							for j = 0, iLimit do
								for k = 0, jLimit do
									local pixelX = (mcuX - 1) * 8 + k + 1
									local pixelY = (mcuY - 1) * 8 + j + 1

									if pixelX <= jpegData[2][2] and pixelY <= jpegData[2][3] then
										jpegData[7][pixelX][pixelY][actualID] = decodedMCU[floor(k / (subtractFromX - componentHorizontalSample)) * 8 + floor(j / (subtractFromY - componentVerticalSample)) + 1]
									end
								end
							end
						end
					end
				end
			end
		end
		local k = 0
		for x = 1, jpegData[2][2] do
			for y = 1, jpegData[2][3] do
				local lum = jpegData[7][x][y][1]
				local cb = jpegData[7][x][y][2]
				local cr = jpegData[7][x][y][3]

				local r = lum + 1.402 * cr + 128
				local g = lum - 0.34414 * cb - 0.71414 * cr + 128
				local b = lum + 1.772 * cb + 128

				--r /= 255 --clamp(r, 0, 255)
				--g /= 255 --clamp(g, 0, 255)
				--b /= 255 --clamp(b, 0, 255)

				local offset = k * 4 + 1
				jpegData[6][offset] = r
				jpegData[6][offset + 1] = g
				jpegData[6][offset + 2] = b
				jpegData[6][offset + 3] = 1
				k += 1
			end
		end
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
		Decode = function(): pixelData
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
			return jpegData[6]
		end,
	}
end

return rbxvideo

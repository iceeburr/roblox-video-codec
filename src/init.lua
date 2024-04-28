--!native
--!optimize 2
--!strict

--[[

	# Roblox Video Codec (RVC)
	*Made by iceeburr with 💖 and 🧊
	STILL IN DEVELOPMENT, NOT READY FOR USE!*

	### --// Short Documentation \\--

	`require(modulePath) -> rbxvideo`
	* Returns the module.

	`rbxvideo.new(VideoData: buffer, DebugVerbosity: boolean?) -> videostream`
	* Constructs a new videostream from the encoded VideoData.

	`videostream.Decode(Frame: number) -> pixelData`
	* Decodes the frame at the given position and returns the pixel data of that frame; ready to be used by an EditableImage.

	*_Warning! Debug mode can create lag, slow down the game and clutter up the output._*
	
	`Debug verbosity: 0 | nil = off; 1 = print; 2 = warn; (only a color change) 3 = test`

]]

--// Simple Typechecking \\--

export type pixelData = {
	R: number,
	G: number,
	B: number,
	A: number,
}

export type videostream = {
	Decode: (Frame: number) -> pixelData,
}

local rbxvideo = {}

-- Create video stream
function rbxvideo.new(VideoData: buffer, DebugVerbosity: number?): videostream
	-- Local is faster than global
	-- Buffers
	local readu8 = buffer.readu8
	local writeu8 = buffer.writeu8
	local buflen = buffer.len
	local bufcreate = buffer.create
	local bufcopy = buffer.copy
	-- Bitwise operations
	local rshift = bit32.rshift
	local lshift = bit32.lshift
	local band = bit32.band
	local bor = bit32.bor
	-- Table operations
	local tableinsert = table.insert
	local tablecreate = table.create
	-- Math operations
	local floor = math.floor
	local pow = math.pow
	local max = math.max
	local sqrt = math.sqrt
	local cos = math.cos
	local clamp = math.clamp
	local round = math.round
	local abs = math.abs
	local random = math.random
	local pi = math.pi
	-- String operations
	local strupper = string.upper
	local strformat = string.format
	-- Miscellaneous
	local type = type
	local osclock = os.clock

	-- For debugging
	local StartTime = osclock()

	-- Video stream data
	local VideoStream = {}
	local VideoDataLength = buflen(VideoData) - 1
	local Index = 0
	local FrameCount = 0
	local MarkerType: number
	-- Resolution
	local Width: number
	local Height: number
	-- Decode data
	local PixelData: {}
	local DCTables: {}
	local ACTables: {}
	local LastDecodedFrame: number

	-- Utility/helper functions
	-- Required as 16-bits are not encoded as unsigned integers in JPEGs
	local function reade16(Buffer: buffer, Offset: number): number
		return bor(readu8(Buffer, Offset + 1), lshift(readu8(Buffer, Offset), 8))
	end

	-- For debugging and error handling
	local sp15 = "===============" -- Seperator 15 spaces
	local sp49 = "=================================================" -- Seperator 49 spaces
	local function ByteToHex(Byte: number): string
		return strupper(strformat("%x", Byte))
	end
	local PrintMethod
	if DebugVerbosity == 1 then PrintMethod = print else PrintMethod = warn end
	DebugVerbosity = DebugVerbosity and DebugVerbosity or 0
	local VideoError = setmetatable({
		["Signature"] = function(): ()
			error(`\nCouldn't find a valid JPEG signature.\nAt index {Index};\nFrame count {FrameCount}.`)
		end,
		["Offset"] = function(): ()
			error(`\nLost buffer offset.\nAt index {Index};\nFrame count {FrameCount};\nByte 0x{ByteToHex(readu8(VideoData, Index))};\nLast marker 0x{ByteToHex(MarkerType)}.`)
		end,
		["QTPrecision"] = function(TableCount: number, Precision: number): ()
			error(`\nQuantization table doesn't have precision of 0.\nAt index {Index};\nFrame count {FrameCount};\nTableID {TableCount};\nPrecision {Precision}.`)
		end,
		["FramePrecision"] = function(Byte: number): ()
			error(`\nFrame doesn't have a precision of 8.\nAt index {Index};\nFrame count {FrameCount};\nByte 0x{ByteToHex(Byte)}.`)
		end,
		["ResolutionMismatch"] = function(FrameWidth: number, FrameHeight: number): ()
			error(`\nFrame {FrameCount} resolution is {FrameWidth}x{FrameHeight}, but it's supposed to be {Width}x{Height}.\nAt index {Index}.`)
		end,
		["ComponentMismatch"] = function(FrameComponentCount: number, ComponentCount: number): ()
			error(`\nFrame {FrameCount} component count is {FrameComponentCount}, but it's supposed to be {ComponentCount}.\nAt index {Index}.`)
		end,
		["InvalidComponents"] = function(ComponentCount: number): ()
			error(`\nFrame {FrameCount} doesn't have 1 or 3 components.\nAt index {Index};\nComponent count {ComponentCount}.`)
		end,
		["BitStreamInvalid0xFF"] = function(Pointer: number, Byte: number): ()
			error(`\nInvalid marker '0x{ByteToHex(Byte)}' found after 0xFF in bitstream.\nAt index {Index};\nAt relative index {Pointer};\nFrame count {FrameCount}.`)
		end,
		["FrameNotFound"] = function(Frame: number): ()
			error(`\nFrame {Frame} not found.`)
		end
	}, {__index = function(Table, SearchIndex)
			return function(...): ()
				PrintMethod(`\nNo valid error type has been provided.\nType {SearchIndex}\nArguments:`, {...})
				error(`Internal error.`)
			end
		end
	})

	-- Matrix manipulation
	-- Zigzag table
	local Zigzag1D: any = {
		1,   2,  9, 17, 10,  3,  4, 11,
		18, 25, 33, 26, 19, 12,  5,  6,
		13, 20, 27, 34, 41, 49, 42, 35,
		28, 21, 14,  7,  8, 15, 22, 29,
		36, 43, 50, 57, 58, 51, 44, 37,
		30, 23, 16, 24, 31, 38, 45, 52,
		59, 60, 53, 46, 39, 32, 40, 47,
		54, 61, 62, 55, 48, 56, 63, 64
	}
	local Zigzag1DBuffer = bufcreate(64)
	for Pointer = 0, 63 do
		writeu8(Zigzag1DBuffer, Pointer, Zigzag1D[Pointer + 1])
	end
	Zigzag1D = function(Index: number): number
		return readu8(Zigzag1DBuffer, Index)
	end

	-- Initialize temporary frame data buffers & counters
	local TempQuantizationBuffer = bufcreate(256)
	local QuantizationCounter = 0

	local TempComponentBuffer = bufcreate(9)
	local ComponentCount = 0
	local MaxHorizontalSample = 0
	local MaxVerticalSample = 0

	local TempDCBuffer = bufcreate(4096)
	local TempACBuffer = bufcreate(4096)
	local DCTableCount = 0
	local ACTableCount = 0
	local DCTableEndIndex = 0
	local ACTableEndIndex = 0

	local TempScanBuffer = bufcreate(65536)
	local ScanLength = 0

	local RestartInterval = 0

	-- Marker functions
	local function DQT(EndIndex: number): ()
		while Index < EndIndex do
			-- Validate that the precision is 8 bit
			if rshift(readu8(VideoData, Index), 4) ~= 0 then VideoError.QTPrecision(QuantizationCounter, rshift(readu8(VideoData, Index), 4)) end    
			local Offset = QuantizationCounter * 64
			for Pointer = 0, 63 do
				writeu8(TempQuantizationBuffer, Pointer + Offset, readu8(VideoData, Index + Zigzag1D(Pointer)))
			end
			Index += 65
			QuantizationCounter += 1
		end
	end
	local function SOF0(): ()
		if readu8(VideoData, Index) ~= 8 then VideoError.FramePrecision(readu8(VideoData, Index)) end
		local xWidth = reade16(VideoData, Index + 3)
		local yHeight = reade16(VideoData, Index + 1)
		if Width or Height then
			if xWidth ~= Width or yHeight ~= Height then
				VideoError.ResolutionMismatch(xWidth, yHeight)
			end
		else
			Width = xWidth
			Height = yHeight
		end
		Index += 5
		ComponentCount = readu8(VideoData, Index)
		for Component = 0, ComponentCount - 1 do
			local SampleFactors = readu8(VideoData, Index + 2)
			MaxHorizontalSample = max(band(rshift(SampleFactors, 4), 0x0F), MaxHorizontalSample)
			MaxVerticalSample = max(band(SampleFactors, 0x0F), MaxVerticalSample)
			local Offset = Component * 3
			writeu8(TempComponentBuffer, Offset, SampleFactors)
			writeu8(TempComponentBuffer, Offset + 1, readu8(VideoData, Index + 3))
			Index += 3
		end
		Index += 1
	end
	local function DHT(EndIndex: number): ()
		while Index < EndIndex do
			local TableID = band(rshift(readu8(VideoData, Index), 4), 0x0F)
			local Length = 16
			for Symbol = 1, 16 do
				Length += readu8(VideoData, Index + Symbol)
			end
			if TableID == 0 then
				bufcopy(TempDCBuffer, DCTableEndIndex, VideoData, Index + 1, Length)
				DCTableCount += 1
				DCTableEndIndex += Length
			elseif TableID == 1 then
				bufcopy(TempACBuffer, ACTableEndIndex, VideoData, Index + 1, Length)
				ACTableCount += 1
				ACTableEndIndex += Length
			else
				VideoError.InvalidHuffmanTableID(TableID)
			end
			Index += Length + 1
		end
	end
	local function SOS(): ()
		local Components = readu8(VideoData, Index)
		if Components ~= 1 and Components ~= 3 then
			VideoError.InvalidComponents(Components)
		elseif Components ~= ComponentCount then
			VideoError.ComponentMismatch(ComponentCount, Components)
		end
		for Component = 0, Components - 1 do
			Index += 2
			writeu8(TempComponentBuffer, (Component * 3) + 2, readu8(VideoData, Index))
		end
		Index += 4
		while ScanLength < buflen(TempScanBuffer) do
			local CurrentByte = readu8(VideoData, Index)
			if CurrentByte == 0xFF then
				local NextByte = readu8(VideoData, Index + 1)
				if NextByte == 0x00 then
					writeu8(TempScanBuffer, ScanLength, CurrentByte)
					ScanLength += 1
					Index += 2
				elseif NextByte >= 0xD0 and NextByte <= 0xD7 then
					-- We don't use restart intervals
					Index += 2
				elseif NextByte == 0xD9 then
					Index += 2
					break -- Reached the end of the file
				else
					VideoError.BitStreamInvalid0xFF(ScanLength, NextByte)
				end
			else
				writeu8(TempScanBuffer, ScanLength, CurrentByte)
				ScanLength += 1
				Index += 1
			end
		end
	end

	-- Initialize the videostream
	while Index < VideoDataLength do -- Loop through frames
		FrameCount += 1
		-- Check for the JPEG signature
		if readu8(VideoData, Index) ~= 0xFF or readu8(VideoData, Index + 1) ~= 0xD8 or readu8(VideoData, Index + 2) ~= 0xFF then
			VideoError.Signature()
		end
		Index += 2 -- Skip SOI
		while true do -- Loop through current frame data
			if readu8(VideoData, Index) == 0xFF then
				MarkerType = readu8(VideoData, Index + 1)
				local Length = reade16(VideoData, Index + 2) - 2
				Index += 4
				-- Decode quantization table(s)
				if MarkerType == 0xDB then
					DQT(Index + Length)
				-- Decode start of frame
				elseif MarkerType == 0xC0 then
					SOF0()
				-- Decode Huffman table(s)
				elseif MarkerType == 0xC4 then
					DHT(Index + Length)
				-- Decode start of scan
				elseif MarkerType == 0xDA then
					SOS()
					break -- We have finished decoding this frame
				-- Edge case for the restart interval
				elseif MarkerType == 0xDD then
					warn("Restart interval markers haven't been tested yet. This message is temporary.")
					RestartInterval = Length + 2 -- Length is already the data
					Index += 4
					continue
				else
					Index += Length
				end
			else
				VideoError.Offset()
			end
		end
		-- Pack frame data into a single buffer
		local FrameData = bufcreate(
			4 +
			(ComponentCount * 3) +
			(QuantizationCounter * 64) +
			DCTableEndIndex +
			ACTableEndIndex +
			ScanLength
		)

		local QuantStart = 4 + (ComponentCount * 3)
		local DCStart = QuantStart + (QuantizationCounter * 64)
		local ACStart = DCStart + DCTableEndIndex
		local ScanStart = ACStart + ACTableEndIndex

		writeu8(FrameData, 0, bor(lshift(MaxHorizontalSample, 4), MaxVerticalSample))
		writeu8(FrameData, 1, bor(lshift(QuantizationCounter, 4), RestartInterval))
		writeu8(FrameData, 2, bor(lshift(DCTableCount, 4), ACTableCount))
		writeu8(FrameData, 3, ComponentCount)
		bufcopy(FrameData, 4, TempComponentBuffer, 0, ComponentCount * 3)
		bufcopy(FrameData, QuantStart, TempQuantizationBuffer, 0, QuantizationCounter * 64)
		bufcopy(FrameData, DCStart, TempDCBuffer, 0, DCTableEndIndex)
		bufcopy(FrameData, ACStart, TempACBuffer, 0, ACTableEndIndex)
		bufcopy(FrameData, ScanStart, TempScanBuffer, 0, ScanLength)
		
		VideoStream[FrameCount] = FrameData

		-- Reset variables (counters)
		-- Buffers are reused so no need to reset them
		QuantizationCounter = 0

		ComponentCount = 0
		MaxHorizontalSample = 0
		MaxVerticalSample = 0

		DCTableCount = 0
		ACTableCount = 0

		ScanLength = 0

		RestartInterval = 0
	end

	-- Ensure we can't write data again
	table.freeze(VideoStream)

	-- Initialize pixel data array
	PixelData = tablecreate(Width * Height * 4, 1)

	if DebugVerbosity > 0 then
		PrintMethod(
			`\n|{sp15} DEBUG INFORMATION {sp15}`,
			`\n| Roblox Video Codec (RVC)`,
			`\n| Made by iceeburr with 💖 and 🧊`,
			`\n| Initialized in {osclock() - StartTime}s!`,
			`\n|{sp49}\n`
		)
	end

	-- Return decode function
	return {
		Decode = function(Frame: number): pixelData
			local FrameStartTime = osclock()
			if LastDecodedFrame == Frame then
				if DebugVerbosity > 0 then
					warn(`Last decoded frame is cached; skipping the decoding process...`)
				end
				return PixelData :: any;
			end
			local FrameData = VideoStream[Frame]
			if not FrameData then VideoError.FrameNotFound(Frame) end

			-- Variables
			local MaxFactors = readu8(FrameData, 0)
			local MaxHorizontalFactor = band(rshift(MaxFactors, 4), 0x0F)
			local MaxVerticalFactor = band(MaxFactors, 0x0F)

			local QTR = readu8(FrameData, 1)
			local QuantizationTableCount = band(rshift(QTR, 4), 0x0F)
			local RestartInterval = band(QTR, 0x0F)

			local HuffmanTableCounts = readu8(FrameData, 2)
			local DCTableCount = band(rshift(HuffmanTableCounts, 4), 0x0F)
			local ACTableCount = band(HuffmanTableCounts, 0x0F)
			local ColorComponentCount = readu8(FrameData, 3)

			local QuantizationTableStart = 4 + (ColorComponentCount * 3)
			local DCTableStart = QuantizationTableStart + (QuantizationTableCount * 64)
			local ACTableStart = DCTableStart + DCTableEndIndex
			local ScanStart = ACTableStart + ACTableEndIndex

			local DCTables = tablecreate(DCTableCount)
			local ACTables = tablecreate(ACTableCount)

			local HuffmanOffset = 0
			for i = 0, DCTableCount - 1 do
				DCTables[i] = {}
				local symbolscounttable = {}
				local symbolstable = {}
				local symbolcount = 0
				for j = 0, 15 do
					local count = readu8(FrameData,  DCTableStart + HuffmanOffset + j)
					symbolcount += count
					symbolscounttable[j] = count
				end
				HuffmanOffset += 16
				for j = 0, symbolcount - 1 do
					symbolstable[j] = readu8(FrameData, DCTableStart + HuffmanOffset + j)
				end
				HuffmanOffset += symbolcount
				DCTables[i][1] = symbolscounttable
				DCTables[i][2] = symbolstable
			end
			HuffmanOffset = 0
			for i = 0, ACTableCount - 1 do
				ACTables[i] = {}
				local symbolscounttable = {}
				local symbolstable = {}
				local symbolcount = 0
				for j = 0, 15 do
					local count = readu8(FrameData,  ACTableStart + HuffmanOffset + j)
					symbolcount += count
					symbolscounttable[j] = count
				end
				HuffmanOffset += 16
				for j = 0, symbolcount - 1 do
					symbolstable[j] = readu8(FrameData, ACTableStart + HuffmanOffset + j)
				end
				HuffmanOffset += symbolcount
				ACTables[i][1] = symbolscounttable
				ACTables[i][2] = symbolstable
			end

			LastDecodedFrame = Frame
			
			-- Debugging
			if DebugVerbosity > 0 then
				local FrameEndTime = osclock()

				-- Memory Usage Approximation
				local ApproximateMemorySize = 128 + (#VideoStream * 16) + (Width * Height * 4 * 16)
				for _, FrameBuffer in pairs(VideoStream) do
					ApproximateMemorySize += buflen(FrameBuffer)
				end
				ApproximateMemorySize = round((ApproximateMemorySize / 1024 / 1024) * 100) / 100
				local OriginalVideoSize = round((VideoDataLength / 1024 / 1024) * 100) / 100

				-- Quantization Tables
				local QuantizationTable = tablecreate(QuantizationTableCount)
				for i = 0, QuantizationTableCount - 1 do
					QuantizationTable[i] = tablecreate(64)
					local CurrentTable = QuantizationTable[i]
					local Offset = i * 64
					for j = 0, 63 do
						CurrentTable[j + 1] = readu8(FrameData, j + Offset + QuantizationTableStart)
					end
				end

				-- Color Components
				local ComponentTable = table.create(ComponentCount)
				for i = 0, ColorComponentCount - 1 do
					ComponentTable[i] = tablecreate(5) :: any
					local CurrentComponent = ComponentTable[i]
					local Offset = i * 3
					local Factors = readu8(FrameData, 4 + Offset)
					CurrentComponent["1 Horizontal Sample"] = band(rshift(Factors, 4), 0x0F)
					CurrentComponent["2 Vertical Sample"] = band(Factors, 0x0F)
					CurrentComponent["3 Quantization Table ID"] = readu8(FrameData, 5 + Offset)
					local HuffmanIDs = readu8(FrameData, 6 + Offset)
					CurrentComponent["4 DC Table ID"] = band(rshift(HuffmanIDs, 4), 0x0F)
					CurrentComponent["5 AC Table ID"] = band(HuffmanIDs, 0x0F)
				end

				-- Error Test
				if DebugVerbosity == 3 then
					PrintMethod(`\n {sp15} ERROR TEST {sp15}`)
					for _, v in pairs(VideoError) do
						task.spawn(function() v(random(1, 256), random(1, 256), random(1, 256), random(1, 256), random(1, 256)) end)
					end
					task.spawn(function() VideoError.UnknownErrorType(random(1, 256), random(1, 256), random(1, 256), random(1, 256), random(1, 256)) end)
					PrintMethod(`\n {sp49}\n`)
				end

				-- Debug Information
				PrintMethod(
				`\n|{sp15} DEBUG INFORMATION {sp15}`,
				`\n| Video Stream:`,
				`\n| Resolution: {Width}x{Height};`,
				`\n| Frame Count: {FrameCount};`,
				`\n| Original Video Size: {OriginalVideoSize} MiB;`,
				`\n| Memory Usage: {ApproximateMemorySize} MiB.`,
				`\n|{sp49}`,
				`\n| Frame {Frame}:`,
				`\n| Quantization Tables:`, QuantizationTable, `;`,
				`\n| DC Tables:`, DCTables, `;`,
				`\n| AC Tables:`, ACTables, `;`,
				`\n| Color Components:`, ComponentTable, `;`,
				`\n| Max Factors: {MaxHorizontalFactor}x{MaxVerticalFactor};`,
				`\n| Decoded In:    {FrameStartTime - FrameEndTime}s;`,
				`\n| Debug Message: {osclock() - FrameEndTime}s;`,
				`\n| Total Time:    {osclock() - FrameStartTime}s.`,
				`\n|{sp49}\n`)
			end
			return PixelData :: any
		end
	}
end

return rbxvideo

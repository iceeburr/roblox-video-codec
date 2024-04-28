--!native
--!optimize 2
--!strict

--[[

	# Roblox Video Codec
	*Made by iceeburr with 💖 and 🧊
	STILL IN DEVELOPMENT, NOT READY FOR USE!*

	### --// Short Documentation \\--

	#### require(modulePath) -> rbxvideo
	*Returns the module.*

	#### rbxvideo.new(VideoData: buffer) -> videostream
	*Constructs a new videostream from the encoded VideoData.*

	#### videostream.Decode(Frame: number, DebugMode: boolean) -> pixelData
	*Decodes the frame at the given position and returns the pixel data of that frame; ready to be used by an EditableImage.
	Don't use debug mode unless you need it. It will print a lot of information about the decoding process which will significantly slow down the module.*
	
]]

--// Simple Typechecking \\--

export type pixelData = {
	R: number,
	G: number,
	B: number,
	A: number,
}

export type videostream = {
	Decode: (Frame: number, DebugMode: boolean) -> pixelData,
}

local rbxvideo = {}

function rbxvideo.new(VideoData: buffer): videostream
	--// Base Functions & Constants \\--

	-- Local is faster than global
	local readu8 = buffer.readu8
	local writeu8 = buffer.writeu8
	local buflen = buffer.len
	local bufcreate = buffer.create
	local bufcopy = buffer.copy

	local rshift = bit32.rshift
	local lshift = bit32.lshift
	local band = bit32.band
	local bor = bit32.bor

	local _tableinsert = table.insert
	local _tablecreate = table.create

	local _floor = math.floor
	local _pow = math.pow
	local max = math.max
	local _sqrt = math.sqrt
	local _cos = math.cos
	local _clamp = math.clamp
	local _pi = math.pi

	local strupper = string.upper
	local strformat = string.format

	local _type = type
	local _osclock = os.clock

	-- Don't get mixed up with readu16, they are completely different.
	local function CombineBytes(high: number, low: number): number
		return bor(low, lshift(high, 8))
	end

	--
	local Index = 0
	local VideoStream = {}
	local Width = 0
	local Height = 0
	local _PixelData
	local _LastDecodedFrame = 0
	local MarkerType

	-- For debugging and error handling
	local bs = "                " -- blank space
	local function ConvertByteToHex(byte: number): string
		return strupper(strformat("%x", byte))
	end
	local VideoError = setmetatable({
		["Signature"] = function(Index: number, Frame: number): ()
			error(`Couldn't find a valid JPEG signature.\n{bs}At index {Index};\n{bs}Frame count {Frame}.`)
		end,
		["Offset"] = function(Index: number, Frame: number, Byte: number): ()
			error(`Lost buffer offset.\n{bs}At index {Index};\n{bs}Frame count {Frame};\n{bs}Byte 0x{ConvertByteToHex(Byte)};\n{bs}Last marker 0x{ConvertByteToHex(MarkerType)}.`)
		end,
		["QTPrecision"] = function(Index: number, Frame: number, TableID: number, Precision: number): ()
			error(`Quantization table doesn't have precision of 0.\n{bs}At index {Index};\n{bs}Frame count {Frame};\n{bs}TableID {TableID};\n{bs}Precision {Precision}.`)
		end,
		["FramePrecision"] = function(Index: number, Frame: number, Byte: number): ()
			error(`Frame doesn't have precision of 8.\n{bs}At index {Index};\n{bs}Frame count {Frame};\n{bs}Byte 0x{ConvertByteToHex(Byte)}.`)
		end,
		["EarlyScan"] = function(Index: number, Frame: number, ComponentCount: number): ()
			error(`Scan marker ran too early; there are {ComponentCount} components.\n{bs}At index {Index};\n{bs}Frame count {Frame}.`)
		end,
		["BitStreamInvalid0xFF"] = function(Index: number, Frame: number, Pointer: number, Byte: number): ()
			error(`Invalid marker '0x{ConvertByteToHex(Byte)}' found after 0xFF in bitstream.\n{bs}At Absolute index {Index};\n{bs}At relative index {Pointer};\n{bs}Frame count {Frame}.`)
		end,
		["ResolutionMismatch"] = function(Index: number, Frame: number, FrameWidth: number, FrameHeight: number, StartingWidth: number, StartingHeight: number): ()
			error(`Frame {Frame} resolution is {FrameWidth}x{FrameHeight}, but it's supposed to be {StartingWidth}x{StartingHeight}.\n{bs}At index {Index}.`)
		end,
		["FrameNotFound"] = function(Frame: number): ()
			error(`Frame not found.\n{bs}At Index {Frame};\n`)
		end
	}, {
		__index = function(Table, SearchIndex)
			return function(...): ()
				warn(`No valid error type has been provided.\n{bs}Type {SearchIndex}\n{bs}Arguments:`, {...})
				error(`Internal error.`)
			end
		end
	})

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
	Zigzag1D = nil

	-- Marker procedures

	local function DQT(Index: number, Length: number, Frame: number): ()
		local QuantizationDataBuffer = VideoStream[Frame][1]
		while Index < Length do

			local Header = readu8(VideoData, Index)
			local TableID = band(Header, 0x0F)
			local Precision = rshift(Header, 4)
			if Precision ~= 0 then VideoError.QTPrecision(Index, Frame, TableID, Precision) end
			local Offset = TableID * 64
			for Pointer = 0, 63 do
				writeu8(QuantizationDataBuffer, Pointer + Offset, readu8(VideoData, Index + readu8(Zigzag1DBuffer, Pointer)))
			end
			Index += 64
			TableCounter += 1
		end
		local OldData = VideoStream[Frame][1]
		local OldDataLength = if OldData == 0 then 0 else buflen(OldData)
		local QuantizationDataBuffer = bufcreate(TableCounter * 64 + OldDataLength)
		if OldData ~= 0 then buffer.copy(QuantizationDataBuffer, 0, OldData) end
		bufcopy(QuantizationDataBuffer, OldDataLength, TemporaryBuffer, 0, TableCounter * 64)
		OldData = QuantizationDataBuffer
	end

	local function SOF0(Index: number, Frame: number): ()
		if readu8(VideoData, Index) ~= 8 then VideoError.Precision(Frame, readu8(VideoData, Index)) end
		local Data = VideoStream[Frame][4]
		local Width = CombineBytes(readu8(VideoData, Index + 3), readu8(VideoData, Index + 4))
		local Height = CombineBytes(readu8(VideoData, Index + 1), readu8(VideoData, Index + 2))
		if Frame == 1 then
			VideoStream.Width = Width
			VideoStream.Height = Height
		elseif Width ~= VideoStream.Width or Height ~= VideoStream.Height then
			VideoError.ResolutionMismatch(Index, Frame, Width, Height, VideoStream.Width, VideoStream.Height)
		end
		Index += 5
		for i = 1, readu8(VideoData, Index) do
			Index += 2
			local SampleFactors = readu8(VideoData, Index)
			local HorizontalSample = band(rshift(SampleFactors, 4), 0x0F)
			local VerticalSample = bit32.band(SampleFactors, 0x0F)
			Data[1] = max(Data[1], HorizontalSample)
			Data[2] = max(Data[2], VerticalSample)
			Index += 1
			local QuantizationTableID = readu8(VideoData, Index)
			QuantizationTableID = QuantizationTableID > 0 and QuantizationTableID + 1 or 1
			Data[3][i] = {
				HorizontalSample,
				VerticalSample,
				QuantizationTableID,
				0, -- DCTableID
				0  -- ACTableID
			}
		end
	end

	local function DHT(Index: number, Length: number, Frame: number): ()
	end

	local function SOS(Index: number, Frame: number): number
		local Components = VideoStream[Frame][4][3]
		local ComponentCount = #Components
		if ComponentCount < 1 then VideoError.EarlyScan(Index, Frame, ComponentCount) end  
		for Component = 1, ComponentCount do
			Index += 2
			local HuffmanIDs = readu8(VideoData, Index)
			local DCTableID = band(rshift(HuffmanIDs, 4), 0x0F)
			local ACTableID = band(HuffmanIDs, 0x0F)
			Components[Component][4] = DCTableID > 0 and DCTableID + 1 or 1
			Components[Component][5] = ACTableID > 0 and ACTableID + 1 or 1
		end
		Index += 4
		local TemporaryBufferPointer = 0
		local TemporaryBuffer = bufcreate(60000) -- For now max frame size is around 50kb
		while true do
			local CurrentByte = readu8(VideoData, Index)
			if CurrentByte == 0xFF then
				local NextByte = readu8(VideoData, Index + 1)
				if NextByte == 0x00 then
					writeu8(TemporaryBuffer, TemporaryBufferPointer, CurrentByte)
					TemporaryBufferPointer += 1
					Index += 2
					continue
				elseif NextByte >= 0xD0 and NextByte <= 0xD7 then
					Index += 2
					continue -- We don't use restart intervals
				elseif NextByte == 0xD9 then
					Index += 2
					break -- Reached the end of the file
				end
				VideoError.BitStreamInvalid0xFF(Index, Frame, TemporaryBufferPointer, NextByte)
			end
			writeu8(TemporaryBuffer, TemporaryBufferPointer, CurrentByte)
			TemporaryBufferPointer += 1
			Index += 1
		end
		local ScanData = bufcreate(TemporaryBufferPointer)
		bufcopy(ScanData, 0, TemporaryBuffer, 0, TemporaryBufferPointer)
		VideoStream[Frame][5] = ScanData
		return Index
	end

	--// Initialize the videostream \\--

	while Index < buflen(VideoData) - 1 do
		-- Initialize frame data
		local FrameData = {
			bufcreate(256), -- 1 Quantization tables
			0, -- 2 DC coefficient tables
			0, -- 3 AC coefficient tables
			0, -- 4 Component data
			   	-- 1 Max horizontal sample
			   	-- 2 Max vertical sample
			   	-- 3 Color components
			0  -- 5 Scan data (buffer)
		}

		FrameCount += 1
		VideoStream[FrameCount] = FrameData
		-- Check for the JPEG signature
		if readu8(VideoData, Index) ~= 0xFF or readu8(VideoData, Index + 1) ~= 0xD8 or readu8(VideoData, Index + 2) ~= 0xFF then
			VideoError.Signature(Index, FrameCount)
		end
		Index += 2 -- Skip SOI
		while true do
			if readu8(VideoData, Index) == 0xFF then
				MarkerType = readu8(VideoData, Index + 1)
				local Length = CombineBytes(readu8(VideoData, Index + 2), readu8(VideoData, Index + 3)) - 2
				Index += 4

				-- Decode quantization table(s)
				if MarkerType == 0xDB then
					DQT(Index, Length, FrameCount)

				-- Decode start of frame
				elseif MarkerType == 0xC0 then
					SOF0(Index, FrameCount)

				-- Decode Huffman table(s)
				elseif MarkerType == 0xC4 then
					DHT(Index, Length, FrameCount)

				-- Decode start of scan
				elseif MarkerType == 0xDA then
					Index = SOS(Index, FrameCount)
					break -- We have finished decoding this frame

				-- Edge case for the restart interval
				elseif MarkerType == 0xDD then
					warn("DRI markers are not tested yet. This message is temporary.")
					FrameData.RestartInterval = Length + 2 -- Length is already the data
					Index += 4
					continue
				end
				Index += Length
			else
				VideoError.Offset(Index, FrameCount, readu8(VideoData, Index))
			end
		end
	end

	--PixelData = tablecreate(VideoStream.Width * VideoStream.Height * 4) :: pixelData

	--// Module API \\--

	return {
		Decode = function(Frame: number, DebugMode: boolean): pixelData
			--if Frame == LastDecodedFrame then return PixelData end

			local Data = VideoStream[Frame]
			if Data then

			else
				VideoError.FrameNotFound(Frame)
			end
			return Data :: any
		end
	}
end

return rbxvideo

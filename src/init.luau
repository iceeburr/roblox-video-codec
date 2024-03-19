--!native
--!optimize 2

--[[

	Fast JPEG decoder
	Made by iceeburr with 💖 and 🧊
	STILL IN DEVELOPMENT, NOT READY FOR USE!

]]

local jpeg = {}

--// Base Functions & Constants \\--

local function COM()
	return 1
end

local markerTypes = {
	--// Frame Types & Extra (SOFn) \\--
	[0xC0] = "unsupported", -- SOF0 Baseline DCT
	[0xC1] = "unsupported", -- SOF1 Extended Sequential DCT
	[0xC2] = "unsupported", -- SOF2 Progressive DCT
	[0xC3] = "unsupported", -- SOF3 Lossless (sequential) libjpeg-unsupported
	[0xC4] = "unsupported", -- DHT define huffman tables
	[0xC5] = "unsupported", -- SOF5 Differential sequential DCT libjpeg-unsupported
	[0xC6] = "unsupported", -- SOF6 Differential progressive DCT libjpeg-unsupported
	[0xC7] = "unsupported", -- SOF7 Differential lossless (sequential) libjpeg-unsupported
	[0xC8] = "unsupported", -- JPG reserved for JPEG extension libjpeg-unsupported
	[0xC9] = "unsupported", -- SOF9 Extended sequential DCT
	[0xCA] = "unsupported", -- SOF10 Progressive DCT
	[0xCB] = "unsupported", -- SOF11 Lossless (sequential) libjpeg-unsupported
	[0xCC] = "unsupported", -- DAC define arithmetic coding conditioning libjpeg-skipped
	[0xCD] = "unsupported", -- SOF13 Differential sequential DCT libjpeg-unsupported
	[0xCE] = "unsupported", -- SOF14 Differential progressive DCT libjpeg-unsupported
	[0xCF] = "unsupported", -- SOF15 Differential lossless (sequential) libjpeg-unsupported

	--// Restart Markers (parameterless) \\--
	-- (restart with modulo 8 count "n")
	[0xD0] = "unsupported", -- RST1*
	[0xD1] = "unsupported", -- RST2*
	[0xD2] = "unsupported", -- RST3*
	[0xD3] = "unsupported", -- RST4*
	[0xD4] = "unsupported", -- RST5*
	[0xD5] = "unsupported", -- RST6*
	[0xD6] = "unsupported", -- RST7*
	[0xD7] = "unsupported", -- RST8*

	--// Delimeters \\--
	[0xD8] = "unsupported", -- SOI (Start of Image)
	[0xD9] = "unsupported", -- EOI (End of Image)
	[0xDA] = "unsupported", -- SOI (Start of Scan)
	[0xDB] = "unsupported", -- DQT (Define Quantization Table)
	[0xDC] = "unsupported", -- DNL (Define Number of Lines) libjpeg-skipped
	[0xDD] = "unsupported", -- DRI (Define Restart Interval)
	[0xDE] = "unsupported", -- DHP (Define Hierarchical Progression)
	[0xDF] = "unsupported", -- EXP (Expand Reference Components)
	[0xFE] = COM, -- COM (Comment)

	--// Application Segments (APPn) \\--
	[0xE0] = "unsupported", -- APP0 JFIF (len >=14) / JFXX (len >= 6) / AVI MJPEG
	[0xE1] = "unsupported", -- APP1 EXIF/XMP/XAP ?
	[0xE2] = "unsupported", -- APP2 FlashPix / ICC
	[0xE3] = "unsupported", -- APP3 Kodak/...
	[0xE4] = "unsupported", -- APP4 FlashPix/...
	[0xE5] = "unsupported", -- APP5 Ricoh...
	[0xE6] = "unsupported", -- APP6 GoPro...
	[0xE7] = "unsupported", -- APP7 Pentax/Qualcomm
	[0xE8] = "unsupported", -- APP8 Spiff
	[0xE9] = "unsupported", -- APP9 MediaJukebox
	[0xEA] = "unsupported", -- APP10 PhotoStudio
	[0xEB] = "unsupported", -- APP11 HDR
	[0xEC] = "unsupported", -- APP12 Photoshop / Save fo web
	[0xED] = "unsupported", -- APP13 Photoshop save as
	[0xEE] = "unsupported", -- APP14 "adobe" (length = 12)
	[0xEF] = "unsupported", -- APP15 GraphicConverter

	--// Extension Data Sections (JPGn) \\--
	[0xF0] = "unsupported", -- JPG0 libjpeg-unsupported
	[0xF1] = "unsupported", -- JPG1 libjpeg-unknown
	[0xF2] = "unsupported", -- JPG2 libjpeg-unknown
	[0xF3] = "unsupported", -- JPG3 libjpeg-unknown
	[0xF4] = "unsupported", -- JPG4 libjpeg-unknown
	[0xF5] = "unsupported", -- JPG5 libjpeg-unknown
	[0xF6] = "unsupported", -- JPG6 libjpeg-unknown
	[0xF7] = "unsupported", -- SOF48 start of frame
	[0xF8] = "unsupported", -- LSE extension parameters
	[0xF9] = "unsupported", -- JPG9 libjpeg-unknown
	[0xFA] = "unsupported", -- JPG10 libjpeg-unknown
	[0xFB] = "unsupported", -- JPG11 libjpeg-unknown
	[0xFC] = "unsupported", -- JPG12 libjpeg-unknown
	[0xFD] = "unsupported", -- JPG13 libjpeg-unsupported
}

--// Module API \\--

function jpeg.decode(databuffer: buffer): ()
	-- Check for the JPEG signature
	if
		buffer.readu8(databuffer, 0) ~= 0xFF
		or buffer.readu8(databuffer, 1) ~= 0xD8
		or buffer.readu8(databuffer, 2) ~= 0xFF
	then
		error("File is not a JPEG")
	end

	-- Process markers
	local position = 4 -- Skip the JPEG signature

	while position < buffer.len(databuffer) do
		local marker = buffer.readu8(databuffer, position)
		local markerLength = buffer.readu16(databuffer, position + 2)

		if markerTypes[marker] then
			if markerTypes[marker] == "unsupported" then
				position = position + markerLength - 2
				continue
			end
			local markerFunction = markerTypes[marker]
			local markerEnd = position + markerLength - 2

			local length = markerFunction(databuffer, position + 2, markerEnd)
			position = position + length
		else
			error("Invalid marker: " .. marker)
		end
	end
end

local unused = 1
return jpeg

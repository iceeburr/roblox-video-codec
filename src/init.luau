--!native
--!optimize 2

--[[

	Fast JPEG decoder
	Made by iceeburr with 💖 and 🧊
	STILL IN DEVELOPMENT, NOT READY FOR USE!

]]

local jpeg = {}

--// Base Functions & Constants \\--

local function UNSUPPORTED()
	print("unsupported")
end

local markerTypes = {
	--// Frame Types & Extra (SOFn) \\--
	[0xC0] = UNSUPPORTED, -- SOF0 Baseline DCT
	[0xC1] = UNSUPPORTED, -- SOF1 Extended Sequential DCT
	[0xC2] = UNSUPPORTED, -- SOF2 Progressive DCT
	[0xC3] = UNSUPPORTED, -- SOF3 Lossless (sequential) libjpeg-unsupported
	[0xC4] = UNSUPPORTED, -- DHT define huffman tables
	[0xC5] = UNSUPPORTED, -- SOF5 Differential sequential DCT libjpeg-unsupported
	[0xC6] = UNSUPPORTED, -- SOF6 Differential progressive DCT libjpeg-unsupported
	[0xC7] = UNSUPPORTED, -- SOF7 Differential lossless (sequential) libjpeg-unsupported
	[0xC8] = UNSUPPORTED, -- JPG reserved for JPEG extension libjpeg-unsupported
	[0xC9] = UNSUPPORTED, -- SOF9 Extended sequential DCT
	[0xCA] = UNSUPPORTED, -- SOF10 Progressive DCT
	[0xCB] = UNSUPPORTED, -- SOF11 Lossless (sequential) libjpeg-unsupported
	[0xCC] = UNSUPPORTED, -- DAC define arithmetic coding conditioning libjpeg-skipped
	[0xCD] = UNSUPPORTED, -- SOF13 Differential sequential DCT libjpeg-unsupported
	[0xCE] = UNSUPPORTED, -- SOF14 Differential progressive DCT libjpeg-unsupported
	[0xCF] = UNSUPPORTED, -- SOF15 Differential lossless (sequential) libjpeg-unsupported

	--// Restart Markers (parameterless) \\--
	-- (restart with modulo 8 count "n")
	[0xD0] = UNSUPPORTED, -- RST1*
	[0xD1] = UNSUPPORTED, -- RST2*
	[0xD2] = UNSUPPORTED, -- RST3*
	[0xD3] = UNSUPPORTED, -- RST4*
	[0xD4] = UNSUPPORTED, -- RST5*
	[0xD5] = UNSUPPORTED, -- RST6*
	[0xD6] = UNSUPPORTED, -- RST7*
	[0xD7] = UNSUPPORTED, -- RST8*

	--// Delimeters \\--
	[0xD8] = UNSUPPORTED, -- SOI (Start of Image)
	[0xD9] = UNSUPPORTED, -- EOI (End of Image)
	[0xDA] = UNSUPPORTED, -- SOI (Start of Scan)
	[0xDB] = UNSUPPORTED, -- DQT (Define Quantization Table)
	[0xDC] = UNSUPPORTED, -- DNL (Define Number of Lines) libjpeg-skipped
	[0xDD] = UNSUPPORTED, -- DRI (Define Restart Interval)
	[0xDE] = UNSUPPORTED, -- DHP (Define Hierarchical Progression)
	[0xDF] = UNSUPPORTED, -- EXP (Expand Reference Components)
	[0xFE] = UNSUPPORTED, -- COM (Comment)

	--// Application Segments (APPn) \\--
	[0xE0] = UNSUPPORTED, -- APP0 JFIF (len >=14) / JFXX (len >= 6) / AVI MJPEG
	[0xE1] = UNSUPPORTED, -- APP1 EXIF/XMP/XAP ?
	[0xE2] = UNSUPPORTED, -- APP2 FlashPix / ICC
	[0xE3] = UNSUPPORTED, -- APP3 Kodak/...
	[0xE4] = UNSUPPORTED, -- APP4 FlashPix/...
	[0xE5] = UNSUPPORTED, -- APP5 Ricoh...
	[0xE6] = UNSUPPORTED, -- APP6 GoPro...
	[0xE7] = UNSUPPORTED, -- APP7 Pentax/Qualcomm
	[0xE8] = UNSUPPORTED, -- APP8 Spiff
	[0xE9] = UNSUPPORTED, -- APP9 MediaJukebox
	[0xEA] = UNSUPPORTED, -- APP10 PhotoStudio
	[0xEB] = UNSUPPORTED, -- APP11 HDR
	[0xEC] = UNSUPPORTED, -- APP12 Photoshop / Save fo web
	[0xED] = UNSUPPORTED, -- APP13 Photoshop save as
	[0xEE] = UNSUPPORTED, -- APP14 "adobe" (length = 12)
	[0xEF] = UNSUPPORTED, -- APP15 GraphicConverter

	--// Extension Data Sections (JPGn) \\--
	[0xF0] = UNSUPPORTED, -- JPG0 libjpeg-unsupported
	[0xF1] = UNSUPPORTED, -- JPG1 libjpeg-unknown
	[0xF2] = UNSUPPORTED, -- JPG2 libjpeg-unknown
	[0xF3] = UNSUPPORTED, -- JPG3 libjpeg-unknown
	[0xF4] = UNSUPPORTED, -- JPG4 libjpeg-unknown
	[0xF5] = UNSUPPORTED, -- JPG5 libjpeg-unknown
	[0xF6] = UNSUPPORTED, -- JPG6 libjpeg-unknown
	[0xF7] = UNSUPPORTED, -- SOF48 start of frame
	[0xF8] = UNSUPPORTED, -- LSE extension parameters
	[0xF9] = UNSUPPORTED, -- JPG9 libjpeg-unknown
	[0xFA] = UNSUPPORTED, -- JPG10 libjpeg-unknown
	[0xFB] = UNSUPPORTED, -- JPG11 libjpeg-unknown
	[0xFC] = UNSUPPORTED, -- JPG12 libjpeg-unknown
	[0xFD] = UNSUPPORTED, -- JPG13 libjpeg-unsupported
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
			if markerTypes[marker] == UNSUPPORTED then
				position = position + markerLength - 2
				continue
			end
			local markerFunction = markerTypes[marker]

			markerFunction()
			position = position + markerLength - 2
		else
			error("Invalid marker: " .. marker)
		end
	end
end

return jpeg

--!native
--!optimize 2
--!nocheck

--// Base Functions & Constants \\--

local readu8 = buffer.readu8
local fromstring = buffer.fromstring
local rshift = bit32.rshift
local lshift = bit32.lshift
local band = bit32.band
local bor = bit32.bor

local function combineBytes(high: number, low: number): number
	return bor(low, lshift(high, 8))
end

--// Decoding Procedures \\--

local function DQT(databuffer: buffer)
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

local function SOF0(databuffer: buffer) end

local procedures = {
	[0xDB] = DQT,
	[0xC0] = SOF0,
}

return function(markerType: number, datastring: string)
	return procedures[markerType] and procedures[markerType](fromstring(datastring))
end

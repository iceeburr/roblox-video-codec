--!native
--!optimize 2

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
	local timenow = os.clock()
	local quant: {} = table.create(65)
	local precision = rshift(readu8(databuffer, 0), 4)
	quant["i"] = band(readu8(databuffer, 0), 0x0F)
	if precision == 1 then
		for j = 1, 32 do
			quant[j] = combineBytes(readu8(databuffer, j), readu8(databuffer, j + 1))
		end
	else
		for j = 1, 64 do
			quant[j] = readu8(databuffer, j)
		end
	end
	print("parallel time:", os.clock() - timenow)
	return quant
end

local procedures = {
	[0xDB] = DQT,
}

return function(markerType: number, datastring: string)
	return procedures[markerType] and procedures[markerType](fromstring(datastring))
end

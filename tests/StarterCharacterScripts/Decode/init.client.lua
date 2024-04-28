--!native
--!optimize 2
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local base64 = require(ReplicatedStorage.Packages.base64)
local rbxvideo = require(ReplicatedStorage.Packages["roblox-video-codec"])
local videodata = base64.decode(buffer.fromstring(script:WaitForChild("video").Value))
local testframecount = 1
local testvideodata = buffer.create(buffer.len(videodata) * testframecount)
for i = 0, testframecount - 1 do
	buffer.copy(testvideodata, i * buffer.len(videodata), videodata)
end
local test = require(ReplicatedStorage.Packages["roblox-video-codec"].test)

local bytes = table.create(buffer.len(videodata))
for i = 1, buffer.len(videodata) do
	bytes[i] = buffer.readu8(videodata, i - 1)
end

local _jpegtest = test.CreateJPEGfromBytes(bytes, true, true, false)

local editableImage = Instance.new("EditableImage")
editableImage.Size = Vector2.new(1024, 576)
editableImage.Parent = game.Workspace.Map.Part.Decal

local videostream = rbxvideo.new(testvideodata, 2)
local thing = videostream.Decode(1)
editableImage:WritePixels(Vector2.zero, editableImage.Size, thing)
--[[
game:GetService("RunService").Heartbeat:Connect(function()
	local timenow = os.clock()
	local _thing = videostream.Decode()
	print(os.clock() - timenow)
end)
]]

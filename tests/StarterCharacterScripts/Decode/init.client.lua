--!native
--!optimize 2
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local base64 = require(ReplicatedStorage.Packages.base64)
local rbxvideo = require(ReplicatedStorage.Packages["roblox-video-codec"])
local videodata = base64.decode(buffer.fromstring(script:WaitForChild("video").Value))
local test = require(ReplicatedStorage.Packages["roblox-video-codec"].test)

local bytes = table.create(buffer.len(videodata))
for i = 1, buffer.len(videodata) do
	bytes[i] = buffer.readu8(videodata, i - 1)
end

local _jpegtest = test.CreateJPEGfromBytes(bytes, true, true, false)

local editableImage = Instance.new("EditableImage")
editableImage.Size = Vector2.new(1024, 576)
editableImage.Parent = game.Workspace.Map.Part.Decal

local videostream = rbxvideo.new(videodata)
task.wait(1)
local timenow = os.clock()
local thing = videostream.Decode()
print(os.clock() - timenow)
print(thing)
--[[
game:GetService("RunService").Heartbeat:Connect(function()
	local timenow = os.clock()
	local _thing = videostream.Decode()
	print(os.clock() - timenow)
end)
]]

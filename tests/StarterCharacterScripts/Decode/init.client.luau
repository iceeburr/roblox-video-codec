--!native
--!optimize 2

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local base64 = require(ReplicatedStorage.Packages.base64)
local robloxvideocodec = require(ReplicatedStorage.Packages["roblox-video-codec"])

local editableImage = Instance.new("EditableImage")
editableImage.Size = Vector2.new(1024, 576)
editableImage.Parent = game.Workspace.Map.Part.Decal

local videobuffer = base64.decode(buffer.fromstring(script:WaitForChild("video").Value))
--robloxvideocodec.decode(videobuffer)

game:GetService("RunService").Heartbeat:Connect(function()
	robloxvideocodec.decode(videobuffer)
end)

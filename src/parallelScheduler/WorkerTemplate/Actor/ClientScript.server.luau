--!native
--!optimize 2
--!nocheck

local SharedTableRegistry = game:GetService("SharedTableRegistry")

local Actor = script.Parent
local _MainActor = Actor.Parent.Parent.Parent
local WorkEvent: BindableEvent = Actor.Parent.WorkEvent
local ResultEvent: BindableEvent = Actor.Parent.ResultEvent

local MaxWorkersObject: IntValue = Actor.Parent.MaxWorkers
local MaxWorkers = MaxWorkersObject.Value
MaxWorkersObject.Changed:Connect(function(Value)
	MaxWorkers = Value
end)

local ModuleId = Actor.Parent.Name
local WorkerId = tonumber(Actor.Name)

local Module = Actor:FindFirstChildWhichIsA("ModuleScript")
local Function = require(Module)

local SharedParamsTable: SharedTable = SharedTableRegistry:GetSharedTable(ModuleId .. ".Params")
local SharedResultsTable: SharedTable = SharedTableRegistry:GetSharedTable(ModuleId .. ".Results")

WorkEvent.Event:ConnectParallel(function()
	--debug.profilebegin("Params Read")
	local WorkerParameters = SharedParamsTable[WorkerId]
	--debug.profileend()

	local TasksPerParamsTable = string.split(WorkerParameters[1], ".")
	local TasksPerParams = #TasksPerParamsTable
	local Index = 1

	local Results = {}

	for i = 1, TasksPerParams do
		local Parameters = {}
		for i = 1, TasksPerParamsTable[i] do
			Index += 1
			Parameters[i] = WorkerParameters[Index]
		end
		table.insert(Parameters, WorkerId + (i - 1) * MaxWorkers)

		--debug.profilebegin("Proccess Function")
		local Result = table.pack(Function(table.unpack(Parameters)))
		--debug.profileend()
		Result = Result.n < 2 and Result[1] or Result
		Results[i] = Result
	end

	--debug.profilebegin("Results Write")
	SharedResultsTable[WorkerId] = Results
	--debug.profileend()

	--debug.profilebegin("Update RemainingTasks")
	local TasksDone = TasksPerParams
	local Value = SharedTable.increment(SharedParamsTable, "RemainingTasks", -TasksDone)
	--debug.profileend()

	if Value - TasksDone == 0 then
		ResultEvent:Fire()
	end
end)

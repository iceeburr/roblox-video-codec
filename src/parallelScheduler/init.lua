--!native
--!optimize 2
--!nocheck

-- // Devhub link // --
-- https://devforum.roblox.com/t/2535929

local SharedTableRegistry = game:GetService("SharedTableRegistry")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local _MainActor = script.Parent

local WorkerModule = {}

local DEFAULT_MAX_WORKERS = RunService:IsClient() and 24 or 48

function WorkerModule:LoadModule(ModuleScript: ModuleScript)
	if not ModuleScript:IsA("ModuleScript") then
		error("AddTask did not receive a module script")
	end

	local Clone: ModuleScript = ModuleScript:Clone()
	local Function = require(Clone)
	if type(Function) ~= "function" then
		error("Module script did not return a function")
	end
	task.delay(0, function()
		Clone:Destroy()
	end)

	-- // ModuleTable // --

	local WorkerFolder = Instance.new("Folder")
	local ModuleId = HttpService:GenerateGUID(false)
	WorkerFolder.Name = ModuleId
	WorkerFolder.Parent = script

	local WorkEvent = Instance.new("BindableEvent", WorkerFolder)
	WorkEvent.Name = "WorkEvent"
	local ResultEvent = Instance.new("BindableEvent", WorkerFolder)
	ResultEvent.Name = "ResultEvent"
	local MaxWorkersObject = Instance.new("IntValue", WorkerFolder)
	MaxWorkersObject.Name = "MaxWorkers"
	MaxWorkersObject.Value = DEFAULT_MAX_WORKERS

	local SharedParamsTable = SharedTable.new()
	SharedTableRegistry:SetSharedTable(ModuleId .. ".Params", SharedParamsTable)

	local SharedResultsTable = SharedTable.new()
	SharedTableRegistry:SetSharedTable(ModuleId .. ".Results", SharedResultsTable)

	local Workers: { number } = {}
	local MaxWorkers = DEFAULT_MAX_WORKERS

	local ModuleTable = {}

	local function InfiniteTables(t, i)
		t[i] = setmetatable({}, { __index = InfiniteTables })
		return t[i]
	end

	local CurrentWork = {
		ParamsTable = setmetatable({}, { __index = InfiniteTables }),
		MaxWorkers = MaxWorkers,
		TableIndex = 0,
	}

	local IsWorking = false

	local Number = 0
	local function GetNextNumber()
		Number += 1
		return Number
	end

	local function _GetCurrentNumber()
		return Number
	end

	local function DecreaseNumber()
		Number -= 1
	end

	local function _SetNumber(NewNumber)
		Number = NewNumber
	end

	local function SharedTableToTable(St: SharedTable)
		local Table = {}
		for i, v in St do
			v = typeof(v) == "SharedTable" and SharedTableToTable(v) or v
			Table[i] = v
		end
		return Table
	end

	local function CreateWorker(MScript: ModuleScript)
		local Worker = script.WorkerTemplate.Actor:Clone()

		local ModuleScriptClone = MScript:Clone()
		ModuleScriptClone.Parent = Worker

		Worker.ServerScript.Enabled = true
		Worker.ClientScript.Enabled = true

		local WorkerId = GetNextNumber()
		Worker.Name = WorkerId

		Workers[WorkerId] = WorkerId

		Worker.Parent = WorkerFolder

		SharedParamsTable[WorkerId] = {}

		return WorkerId
	end

	local function DeleteWorker(WorkerId)
		WorkerFolder[WorkerId]:Destroy()
		Workers[WorkerId] = nil
		DecreaseNumber()
	end

	function ModuleTable:GetStatus(): { ScheduledTasks: number, Workers: number, MaxWorkers: number, IsWorking: boolean }
		return {
			ScheduledTasks = CurrentWork.TableIndex,
			Workers = #Workers,
			MaxWorkers = MaxWorkers,
			IsWorking = IsWorking,
		}
	end

	function ModuleTable:SetMaxWorkers(_MaxWorkers)
		if type(_MaxWorkers) ~= "number" then
			error("Unable to asign MaxWorkers. Number expected, got " .. type(_MaxWorkers))
		end
		if _MaxWorkers ~= math.clamp(math.round(_MaxWorkers), 1, math.huge) then
			error("Unable to asign MaxWorkers. Value must be an integer between 1 and inf")
		end

		task.spawn(function()
			MaxWorkers = _MaxWorkers

			ResultEvent.Event:Wait()
			MaxWorkersObject.Value = _MaxWorkers

			for i, v in ipairs(WorkerFolder:GetChildren()) do
				if not v:IsA("Actor") then
					continue
				end
				local WorkerId = tonumber(v.Name)
				if WorkerId > _MaxWorkers then
					DeleteWorker(WorkerId)
				end
			end
		end)
	end

	function ModuleTable:ScheduleWork(...)
		CurrentWork.TableIndex += 1

		local WorkerTask = math.floor((CurrentWork.TableIndex - 1) / CurrentWork.MaxWorkers)
		local FlooredIndex = CurrentWork.TableIndex - WorkerTask * CurrentWork.MaxWorkers

		local WorkerId = Workers[FlooredIndex] or CreateWorker(ModuleScript)

		CurrentWork.ParamsTable[WorkerId][WorkerTask + 1] = table.pack(...)
	end

	function ModuleTable:Work()
		assert(
			not IsWorking,
			"ModuleTable:Work() was called before the previous tasks were completed. This can cause errors or wrong results. If this was caused because of an error in the ModuleScript, you can ignore it"
		)
		IsWorking = true

		--debug.profilebegin("Clear Tables")
		SharedTable.clear(SharedParamsTable)
		SharedTable.clear(SharedResultsTable)
		--debug.profileend()

		local ActiveWork = CurrentWork
		CurrentWork = {
			ParamsTable = setmetatable({}, { __index = InfiniteTables }),
			MaxWorkers = MaxWorkers,
			TableIndex = 0,
		}

		SharedParamsTable.RemainingTasks = ActiveWork.TableIndex

		for WorkerId, WorkerTasks in ipairs(ActiveWork.ParamsTable) do
			local MergedTable = {} -- {3.4.2.7.3 (#Params per task), Task 1 Params,Task 2 Params, ...}

			local Index = 1
			for i, ParameterTable in ipairs(WorkerTasks) do
				MergedTable[1] = MergedTable[1] and MergedTable[1] .. "." .. ParameterTable.n or ParameterTable.n

				for i, v in ipairs(ParameterTable) do
					Index += 1
					MergedTable[Index] = v
				end
			end
			--debug.profilebegin("Params Write")
			SharedParamsTable[WorkerId] = MergedTable
			--debug.profileend()
		end

		WorkEvent:Fire() -- Single Bindable for every worker

		ResultEvent.Event:Wait()

		local ResultTable = {}

		--debug.profilebegin("Results Read")
		for WorkerId, MergedResults in SharedResultsTable do
			for i, v in MergedResults do
				v = typeof(v) == "SharedTable" and SharedTableToTable(v) or v
				ResultTable[WorkerId + (i - 1) * ActiveWork.MaxWorkers] = v
			end
		end
		--debug.profileend()

		IsWorking = false

		return ResultTable
	end

	function ModuleTable:Destroy()
		SharedTableRegistry:SetSharedTable(ModuleId .. ".Params")
		SharedTableRegistry:SetSharedTable(ModuleId .. ".Results")

		SharedParamsTable = nil
		SharedResultsTable = nil

		WorkerFolder:Destroy()
		Workers = nil
		CurrentWork = nil
		MaxWorkers = nil

		self = nil
	end

	return ModuleTable
end

return WorkerModule

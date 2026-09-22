--!strict
-- Arrays inside DataHandler data. The proxy table is empty, so table.find/insert/remove
-- silently do nothing on it: everything touching a list in the save or session goes through this module.

--[[ Tables ]]--
local DataList = {}

--[[ Handling ]]--
function DataList.IndexOf(list: any, value: any): number?
	for index = 1, #list do
		if list[index] == value then
			return index
		end
	end

	return nil
end

function DataList.Contains(list: any, value: any): boolean
	return DataList.IndexOf(list, value) ~= nil
end

function DataList.Append(list: any, value: any): ()
	list[#list + 1] = value
end

-- Removal by shifting: the tail is cleared last, so no holes are left in the array.
function DataList.RemoveAt(list: any, index: number): any?
	local count = #list
	local value = list[index]
	if not value then
		return nil
	end

	for shift = index, count - 1 do
		list[shift] = list[shift + 1]
	end

	list[count] = nil

	return value
end

function DataList.RemoveValue(list: any, value: any): boolean
	local index = DataList.IndexOf(list, value)
	if not index then
		return false
	end

	DataList.RemoveAt(list, index)

	return true
end

return DataList

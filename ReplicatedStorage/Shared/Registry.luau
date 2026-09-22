local RegistryFactory = {}

--[[
	Query API (read top to bottom):

	1) Start with `registry:Query()` — you get a description of what you want, but nothing
	   has been scanned yet.

	2) Add steps with `Where` (keep some entries) and `Select` (turn each entry into
	   another value). Each step returns a new object so you can keep chaining:
	   `Query():Where(...):Select(...)` — same idea as C# / JavaScript "LINQ" style, but
	   the names are optional to know: `Where` = "filter", `Select` = "map/transform".

	3) Finish with a "terminal" method: `FirstOrDefault`, `ToArray`, `Count`, `Any`, or
	   `All`. That is when the registry is actually looped and the result is returned.

	Shorthands: `Find` and `Values` on the registry skip writing `Query():...` for the
	one common case (first match, or all entries in a list).
]]
export type RegistryQuery<T> = {
	Where: (self: RegistryQuery<T>, f: (T) -> boolean) -> RegistryQuery<T>,
	-- Select changes the element type, which a recursive alias cannot express; the
	-- result is an untyped query whose terminals return `any`.
	Select: (self: RegistryQuery<T>, f: (T) -> any) -> any,
	First: (self: RegistryQuery<T>) -> T?,
	FirstOrDefault: (self: RegistryQuery<T>) -> T?,
	ToArray: (self: RegistryQuery<T>) -> { T },
	Count: (self: RegistryQuery<T>, p: ((T) -> boolean)?) -> number,
	Any: (self: RegistryQuery<T>, p: ((T) -> boolean)?) -> boolean,
	All: (self: RegistryQuery<T>, p: (T) -> boolean) -> boolean,
}

export type Registry<L> = {
	Name: string,
	Content: { [string]: L & { id: string } },
	Get: (self: Registry<L>, id: string) -> L?,
	GetAll: (self: Registry<L>) -> { [string]: L },
	Has: (self: Registry<L>, id: string) -> boolean,
	Query: (self: Registry<L>) -> RegistryQuery<L & { id: string }>,
	Find: (self: Registry<L>, f: (L) -> boolean) -> L?,
	Values: (self: Registry<L>) -> { L },
}

type Oper = { kind: "where" | "map", f: any }
type QueryState = { _reg: any, _ops: { Oper } }

-- Run one entry through a Where/Select pipeline in order; returns (false) if a Where test fails.
local function applyValue(v: any, ops: { Oper }): (boolean, any)
	local x: any = v
	for i = 1, #ops do
		local op = ops[i]
		if op.kind ~= "where" then
			x = op.f(x)
			continue
		end

		if not op.f(x) then
			return false, nil
		end
	end
	return true, x
end

-- Copy-on-write: each chain step gets a new op list so past queries are not mutated.
-- NOTE: `table.create` only reserves capacity; `#` stays 0 until indices are assigned.
-- Always append at `#n + 1`, never `#n`.
local function appendOp(ops: { Oper }, op: Oper): { Oper }
	local n: { Oper } = table.create(#ops + 1)
	for j = 1, #ops do
		n[j] = ops[j]
	end
	n[#n + 1] = op
	return n
end

-- The prototype works on untyped elements; `registry.Query` casts it to `RegistryQuery<T>`
-- so callers get typed chains without the prototype having to prove the generics itself.
local queryProto = {}
queryProto.__index = queryProto

local function chain(state: QueryState, op: Oper): any
	return setmetatable({ _reg = state._reg, _ops = appendOp(state._ops, op) }, queryProto)
end

-- Only keep items where the callback returns true. You can call Where several times; each
-- narrows the set further. Does not run the search yet; chain then end with a terminal.
function queryProto.Where(self: QueryState, f: (any) -> boolean): any
	return chain(self, { kind = "where", f = f })
end

-- Turn each remaining item into something else (same as "map" on an array). After Select,
-- later Where/All/etc. act on the new value type. Defer actual work to a terminal.
function queryProto.Select(self: QueryState, f: (any) -> any): any
	return chain(self, { kind = "map", f = f })
end

-- Terminal: first item that made it through the Where/Select steps, or nil if there
-- is no match. Name matches C# "FirstOrDefault" (get first, or a default of nil); no
-- error is thrown for an empty result.
function queryProto.FirstOrDefault(self: QueryState): any
	for _, e in self._reg.Content do
		local ok, y = applyValue(e, self._ops)
		if ok then
			return y
		end
	end
	return nil
end

-- Same as FirstOrDefault. Here "First" = "first matching item" (or nil if none), not
-- "must exist or throw" like in some C# code.
function queryProto.First(self: QueryState): any
	return queryProto.FirstOrDefault(self)
end

-- Terminal: all items that made it through the steps, in a list. Order matches the
-- underlying `Content` iteration order (hash map order, not a sorted guarantee).
function queryProto.ToArray(self: QueryState): { any }
	local t: { any } = table.create(8)
	for _, e in self._reg.Content do
		local ok, y = applyValue(e, self._ops)
		if ok then
			table.insert(t, y)
		end
	end
	return t
end

-- Terminal: how many items passed the current Where/Select. If you pass a second
-- callback, only items for which *that* returns true are counted (extra filter at the end).
function queryProto.Count(self: QueryState, pred: ((any) -> boolean)?): number
	local c = 0
	for _, e in self._reg.Content do
		local ok, y = applyValue(e, self._ops)
		if ok and (pred == nil or pred(y)) then
			c += 1
		end
	end
	return c
end

-- Terminal: is there at least one match? No extra callback: true if any item survives
-- the current chain. With a callback, true if any surviving item also passes the callback
-- (same idea as adding another Where, but without building a new chain).
function queryProto.Any(self: QueryState, pred: ((any) -> boolean)?): boolean
	for _, e in self._reg.Content do
		local ok, y = applyValue(e, self._ops)
		if ok and (pred == nil or pred(y)) then
			return true
		end
	end
	return false
end

-- Terminal: for every item that the chain keeps (after Where/Select), does the
-- callback return true? If there is nothing in the set (empty list), this returns true.
-- Items removed by a previous Where are ignored, not "failed" by All.
function queryProto.All(self: QueryState, pred: (any) -> boolean): boolean
	for _, e in self._reg.Content do
		local ok, y = applyValue(e, self._ops)
		if ok and not pred(y) then
			return false
		end
	end
	return true
end

-- Build a named table-of-entries: each value gets a string `id` for its key. `methods`
-- can add or override custom functions on the returned object.
function RegistryFactory.Build<L, F>(name: string, content: { [string]: L }, methods: F?)
	local registry: any = {
		Name = name,
		Content = content,
	}

	for id, entry in registry.Content do
		entry.id = id
	end

	-- O(1) item by map key; key is the same as `entry.id` for built entries.
	registry.Get = function(self, id: string)
		return self.Content[id]
	end

	-- The raw map: `[string] = entry`. Useful when the key is what you have.
	registry.GetAll = function(self)
		return self.Content
	end

	-- True if this id exists in the map.
	registry.Has = function(self, id: string)
		return self.Content[id] ~= nil
	end

	-- Start a filter/transform chain; see the module block comment above.
	registry.Query = function(self): RegistryQuery<L & { id: string }>
		return setmetatable({ _reg = self, _ops = {} :: { Oper } }, queryProto) :: any
	end

	-- Shorthand: first item matching the test (same as `Query():Where(f):FirstOrDefault()`).
	registry.Find = function(self, f: (L) -> boolean)
		return self:Query():Where(f):FirstOrDefault()
	end

	-- Shorthand: every entry in a list (same as `Query():ToArray()`; order = Content iteration).
	registry.Values = function(self)
		return self:Query():ToArray()
	end

	if methods ~= nil and typeof(methods) == "table" then
		for key, method in methods do
			registry[key] = method
		end
	end

	return registry :: Registry<L & { id: string }> & F
end

return RegistryFactory

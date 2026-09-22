--!strict
--!optimize 2

--[[

           +++                                                                                      
       ++++++++   ===                                                                               
    ++++++++++   ====                                                  ====                         
     ++++++                                                            ====                         
       +++++     ====     ====== =====  ==== =======      ========     ====        ====             
        +++++    ====    =============  =============    ===========   ====        ====             
         ++++    ====   ====     =====  =====    ====           ====   ====        ====             
         ++++    ====   ====     =====  =====    ====     ==========   ====    =============        
         ++++    ====   ====     =====  =====    ====   ======  ====   ====    =============        
       ++++++    ====   =====   ======  =====    ====  ====     ====   ====        ====    +++++++++
   ++++++++++    ====    =============  =====    ====   ============   ====   ++++ ==== ++++++++++++
  +++++++        ====            =====  ====     ====   + ====  ====   ==== ++++++++  ++++++++      
 +++++                  ==== +++ ==== +++++++++++++++++++++++++++++++++++++++++++++++++++++         
 ++++        +++++++++++ =========== +++++++++++++++++++++++++++++++++++++++      ++++++            
+++++++++++++++++++++++++++                                                         +               
 +++++++++++++++++++++++++                                                                          
      +++++                                                                                         

v3.7.0

An exceptionally fast, lightweight, and elegant open-source signal
library for Luau — with generic types and detailed documentation.


GitHub (repository):
https://github.com/AlexanderLindholt/SignalPlus

GitBook (documentation):
https://alexxander.gitbook.io/SignalPlus

DevForum (topic):
https://devforum.roblox.com/t/3552231


--------------------------------------------------------------------------------
MIT License

Copyright (c) 2025 Alexander Lindholt

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
--------------------------------------------------------------------------------

Forked and edited by: codebykoi

]]

-- Types.
export type Connection<Parameters...> = {
	Signal: Signal<Parameters...>,
	Connected: boolean?,
	Previous: Connection<Parameters...>?,
	Next: Connection<Parameters...>?,
	Callback: (...any) -> (),
	Disconnect: typeof(
		-- Removes the connection from the signal.
		-- <strong>The connection’s data remains.</strong>
		function(connection: Connection<Parameters...>) end
	)
}

export type Signal<Parameters...> = {
	-- Connects a function.
	Connect:
		(signal: Signal<Parameters...>, callback: (Parameters...) -> ()) -> Connection<Parameters...>,

		-- Connects a function, then auto-disconnects after the first call.
	Once:
		(signal: Signal<Parameters...>, callback: (Parameters...) -> ()) -> Connection<Parameters...>, 

		-- Yields the calling thread until the next fire.
	Wait: 
		(signal: Signal<Parameters...>) -> Parameters...,
	
	-- Runs all connected functions and resumes all waiting threads.
	Fire: 
		(signal: Signal<Parameters...>, Parameters...) -> (),

	-- Erases all connections.
	-- <strong>Much faster than calling <code>Disconnect</code> on each.</strong>
	DisconnectAll:
		(signal: Signal<Parameters...>) -> (),

	-- Erases all connections and methods.
	-- <strong>To fully erase, also remove all references to the signal.</strong>
	Destroy: 
		(signal: Signal<Parameters...>) -> (),

	-- Internal properties
	Head: Connection<Parameters...>?,
	Tail: Connection<Parameters...>?,
}
type CreateSignal = <Parameters...>() -> Signal<Parameters...>

-- Spawn function.
local spawnThread = (if script:GetAttribute("Deferred") then task.defer else task.spawn) :: <A...>(thread: thread, A...) -> thread

-- Setup reusable callback threads.
local threads = {}

local function reusableThreadCall(callback, thread, ...)
	callback(...)
	table.insert(threads, thread)
end
local function reusableThread()
	while true do
		reusableThreadCall(coroutine.yield())
	end
end

-- Connection methods.
local function disconnect(connection: Connection<any>)
	-- Verify connection.
	if not connection.Connected then return end
	
	-- Remove connection.
	connection.Connected = nil
	
	local signal = connection.Signal
	local previous = connection.Previous
	local next = connection.Next
	if previous then
		previous.Next = next
	else
		signal.Tail = next
	end
	if next then
		next.Previous = previous
	else
		signal.Head = previous
	end
end

-- Signal methods.
local Signal = {}
Signal.__index = Signal

function Signal.Connect<Params...>(signal: Signal<Params...>, callback: (Params...) -> ()): Connection<Params...>
	-- Linked list head.
	local head = signal.Head
	
	-- Create connection.
	local connection = {
		Signal = signal,
		Previous = head,
		
		Callback = callback,
		
		Connected = true,
		Disconnect = disconnect
	}
	
	-- Add connection.
	if head then
		head.Next = connection :: Connection<Params...>
	else
		signal.Tail = connection :: Connection<Params...>
	end
	signal.Head = connection :: Connection<Params...>
	
	-- Return connection.
	return connection :: any
end
function Signal.Once<Params...>(signal: Signal<Params...>, callback: (Params...) -> ()): Connection<Params...>
	-- Linked list head.
	local head = signal.Head
	
	-- Create connection.
	local connection : Connection<Params...>
	connection = {
		Signal = signal,
		Previous = head,
		
		Callback = function(...)
			-- Verify connection.
			if not connection.Connected then return end
			
			-- Remove connection.
			connection.Connected = false
			
			local previous = connection.Previous
			local next = connection.Next
			if previous then
				previous.Next = next
			else
				signal.Tail = next
			end
			if next then
				next.Previous = previous
			else
				signal.Head = previous
			end
			
			-- Fire callback.
			callback(...)
		end,
		
		Connected = true,
		Disconnect = disconnect
	} :: Connection<Params...>
	
	-- Add connection.
	if head then
		head.Next = connection :: Connection<Params...>
	else
		signal.Tail = connection :: Connection<Params...>
	end
	signal.Head = connection :: Connection<Params...>
	
	-- Return connection.
	return connection :: any
end
function Signal.Wait<Params...>(signal: Signal<Params...>): Params...
	-- Save this thread to resume later.
	local thread = coroutine.running()
	
	-- Linked list head.
	local head = signal.Head
	
	-- Create connection.
	local connection : Connection<Params...>
	connection = {
		Previous = head,
		
		Callback = function(...)
			-- Remove connection.
			connection.Connected = false
			
			local previous = connection.Previous
			local next = connection.Next
			if previous then
				previous.Next = next
			else
				signal.Tail = next
			end
			if next then
				next.Previous = previous
			else
				signal.Head = previous
			end
			
			-- Resume the thread.
			if coroutine.status(thread) == "suspended" then -- To avoid creating new threads.
				task.spawn(thread, ...)
			end
		end
	} :: Connection<Params...>
	
	-- Add connection.
	if head then
		head.Next = connection :: Connection<Params...>
	else
		signal.Tail = connection :: Connection<Params...>
	end
	signal.Head = connection :: Connection<Params...>
	
	-- Yield until the next fire, then return the arguments on resume.
	return coroutine.yield()
end

function Signal.Fire<Params...>(signal: Signal<Params...>, ...: Params...)
	local connection = signal.Tail -- Start from the tail (back) of the list.
	while connection do
		-- Find or create a thread, then run the callback in it.
		local length = #threads
		if length == 0 then
			local thread = coroutine.create(reusableThread)
			coroutine.resume(thread) -- Initialize.
			spawnThread(thread :: any, connection.Callback, thread, ...)
		else
			local thread = threads[length]
			threads[length] = nil -- Remove from free threads list.
			spawnThread(thread :: any, connection.Callback, thread, ...)
		end
		-- Traverse.
		connection = connection.Next
	end
end

function Signal.DisconnectAll<Params...>(signal: Signal<Params...>)
	-- Remove all connections.
	local connection = signal.Tail
	while connection do
		connection.Connected = nil
		connection.Next = nil
		connection.Previous = nil
		-- Traverse.
		connection = connection.Next
	end
	-- Remove signal’s references.
	signal.Tail = nil
	signal.Head = nil
end
function Signal.Destroy<Params...>(signal: Signal<Params...>)
	-- Remove all connections.
	local connection = signal.Tail
	while connection do
		connection.Connected = nil
		connection.Next = nil
		connection.Previous = nil
		-- Traverse.
		connection = connection.Next
	end
	-- Remove signal’s references.
	signal.Tail = nil
	signal.Head = nil
	
	-- Unlink signal methods.
	setmetatable(signal, nil)
end

-- Signal creation function.
local function createSignal<Params...>(): Signal<Params...>
	return setmetatable({}, Signal) :: Signal<Params...>
end

return createSignal :: CreateSignal

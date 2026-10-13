--!strict
-- Names the script behind a ScriptContext.Error report, for analytics.
--
-- The module at the start of the message is where the error was raised ("Path.To.Module:12: ..."),
-- which is more useful than the script the engine blames (often the caller or a library). Only the
-- last name segment survives: messages, line numbers and full paths would multiply the distinct
-- values a dashboard field has to hold.

local ErrorSource = {}

--- Short script name for `message`, falling back to `script`, then to `unknown`. Only letters,
--- digits and underscores remain, cut to `maxLength`.
function ErrorSource.Key(message: string, script: Instance?, maxLength: number, unknown: string): string
	local path = string.match(message, "^([%w_%.]+):%d+:")
	local name = if path then string.match(path, "([%w_]+)$") else nil

	if not name and script then
		name = (string.gsub(script.Name, "[^%w_]", ""))
	end

	if not name or name == "" then
		return unknown
	end

	return string.sub(name, 1, maxLength)
end

return ErrorSource

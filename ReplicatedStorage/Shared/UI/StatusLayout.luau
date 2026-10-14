--!strict
-- Sizes the authored status toast without creating another notification surface, and keeps it off
-- any open page's panel.

--[[ Services ]]
--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

--[[ Modules ]]
--
local Animate = require(script.Parent.Animate)
local Config = require(ReplicatedStorage.Shared.Configs.Notifications)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local TextScale = require(script.Parent.TextScale)
local Theme = require(script.Parent.Theme)

--[[ Tables ]]
--
local StatusLayout = {}

--[[ Private Functions ]]
--
local function prepareArtwork(frame: GuiObject): ()
	local background = frame:FindFirstChild("Background")
	if background and background:IsA("ImageLabel") then
		background.AnchorPoint = Vector2.one / 2
		background.Position = UDim2.fromScale(0.5, 0.5)
		background.Size = UDim2.fromScale(1, 1)
		background.ScaleType = Enum.ScaleType.Stretch
	end

	-- The decorative caption and dashed lines consume space needed by a short toast.
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") and (child.Name == "Lines" or child.Name == "Tag") then
			child.Visible = false
		end
	end
end

local function resolve(dimension: UDim2, size: Vector2): Vector2
	return Vector2.new(
		size.X * dimension.X.Scale + dimension.X.Offset,
		size.Y * dimension.Y.Scale + dimension.Y.Offset
	)
end

local function restingRect(group: GuiObject, includeChildren: boolean): Rect
	local position = group.AbsolutePosition
	local size = group.AbsoluteSize
	local home = group:GetAttribute("HomePosition")
	local parent = group.Parent
	if typeof(home) == "UDim2" and parent and parent:IsA("GuiObject") then
		-- The resting rectangle ignores the group's entrance and press springs.
		size = resolve(group.Size, parent.AbsoluteSize)
		position = parent.AbsolutePosition + resolve(home, parent.AbsoluteSize) - size * group.AnchorPoint
	end
	local minimum, maximum = position, position + size
	if includeChildren then
		-- Currency's boost/Invite row can extend outside the authored group. Use its
		-- direct children's layout properties, not rendered press/pop bounds.
		for _, child in group:GetChildren() do
			if child:IsA("GuiObject") and child.Visible then
				local childSize = resolve(child.Size, size)
				local childMinimum = position + resolve(child.Position, size) - childSize * child.AnchorPoint
				minimum = minimum:Min(childMinimum)
				maximum = maximum:Max(childMinimum + childSize)
			end
		end
	end
	return Rect.new(minimum, maximum)
end

-- Resting bounds of a page's panel with its overhanging art (ribbon tails, close buttons). A clipping
-- container counts as its own frame, so a scrolled list never reaches past it.
local function panelBounds(panel: GuiObject): Rect?
	local minimum, maximum = panel.AbsolutePosition, panel.AbsolutePosition + panel.AbsoluteSize
	local function extend(parent: Instance): ()
		for _, child in parent:GetChildren() do
			if child:IsA("GuiObject") and child.Visible then
				minimum = minimum:Min(child.AbsolutePosition)
				maximum = maximum:Max(child.AbsolutePosition + child.AbsoluteSize)
				if not child.ClipsDescendants then
					extend(child)
				end
			end
		end
	end
	if not panel.ClipsDescendants then
		extend(panel)
	end
	return Animate.AtRest(panel, Rect.new(minimum, maximum))
end

local function openBounds(pages: { [ScreenGui]: GuiObject }): Rect?
	local bounds: Rect? = nil
	for page, panel in pages do
		local rect = if page.Enabled and panel.Visible then panelBounds(panel) else nil
		if rect then
			bounds = if bounds then Rect.new(bounds.Min:Min(rect.Min), bounds.Max:Max(rect.Max)) else rect
		end
	end
	return bounds
end

local function observeGroup(janitor: Janitor.Janitor, group: GuiObject?, update: () -> ()): ()
	if not group then
		return
	end

	janitor:Add(group:GetAttributeChangedSignal("HomePosition"):Connect(update), "Disconnect")
	janitor:Add(group:GetPropertyChangedSignal("Size"):Connect(update), "Disconnect")
	janitor:Add(group:GetPropertyChangedSignal("AnchorPoint"):Connect(update), "Disconnect")
	janitor:Add(group:GetPropertyChangedSignal("Visible"):Connect(update), "Disconnect")

	local parent = group.Parent
	if not parent or not parent:IsA("GuiObject") then
		return
	end

	janitor:Add(parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(update), "Disconnect")
	janitor:Add(parent:GetPropertyChangedSignal("AbsolutePosition"):Connect(update), "Disconnect")
end

local function observeChildren(janitor: Janitor.Janitor, group: GuiObject, update: () -> ()): ()
	local cleanups: { [GuiObject]: () -> () } = {}
	local function added(child: Instance): ()
		if not child:IsA("GuiObject") then
			return
		end
		local owner = Janitor.new()
		cleanups[child] = function(): ()
			owner:Destroy()
		end
		for _, property in { "Position", "Size", "AnchorPoint", "Visible" } do
			owner:Add(child:GetPropertyChangedSignal(property):Connect(update), "Disconnect")
		end
		update()
	end
	janitor:Add(group.ChildAdded:Connect(added), "Disconnect")
	janitor:Add(group.ChildRemoved:Connect(function(child: Instance): ()
		local cleanup = if child:IsA("GuiObject") then cleanups[child] else nil
		if cleanup then
			cleanup()
			cleanups[child :: GuiObject] = nil
		end
		update()
	end), "Disconnect")
	janitor:Add(function(): ()
		for _, cleanup in cleanups do
			cleanup()
		end
		table.clear(cleanups)
	end, true)
	for _, child in group:GetChildren() do
		added(child)
	end
end

--[[ Handling ]]
--
function StatusLayout.Bind(
	screen: ScreenGui,
	frame: GuiObject,
	clock: GuiObject?,
	currency: GuiObject?,
	pages: { [ScreenGui]: GuiObject }
): Janitor.Janitor
	local janitor = Janitor.new()
	local originalDisplayOrder = screen.DisplayOrder
	screen.DisplayOrder = math.max(originalDisplayOrder, Config.DisplayOrder)
	janitor:Add(function(): ()
		screen.DisplayOrder = originalDisplayOrder
	end, true)

	local found = frame:FindFirstChild("Msg")
	local message = if found and found:IsA("TextLabel") then found else nil
	-- The authored cap stays for the usual strip; only a toast narrowed beside a page grows past it.
	local limit = frame:FindFirstChildOfClass("UISizeConstraint")
	local authoredLimit = if limit then limit.MaxSize else Vector2.zero
	if limit then
		janitor:Add(function(): ()
			limit.MaxSize = authoredLimit
		end, true)
	end
	prepareArtwork(frame)

	local alive = true
	janitor:Add(function(): ()
		alive = false
	end, true)
	local update: () -> ()
	local measured, measuredHeight, measuring = "", 0, ""
	-- Wrapped copy height, measured off the caller's thread because the font may still be loading. 0
	-- until it lands; the toast then relayouts.
	local function copyHeight(text: string, font: Font, size: number, width: number): number
		local key = `{text}@{font}@{size}@{width}`
		if measured == key then
			return measuredHeight
		end
		if measuring ~= key then
			measuring = key
			task.spawn(function(): ()
				local params = Instance.new("GetTextBoundsParams")
				params.Text = text
				params.Font = font
				params.Size = size
				params.Width = width
				local ok, bounds = pcall(function(): Vector2
					return TextService:GetTextBoundsAsync(params)
				end)
				if not alive or measuring ~= key then
					return
				end
				if not ok then
					print(`[StatusLayout] Toast copy could not be measured: {bounds}`)
				end
				measuring = ""
				measured = key
				measuredHeight = if ok then bounds.Y else 0
				update()
			end)
		end
		-- A loaded font measures without yielding, inside the spawn above.
		return if measured == key then measuredHeight else 0
	end

	update = function(): ()
		local available = screen.AbsoluteSize
		if available.X <= 0 or available.Y <= 0 then
			return
		end

		local camera = workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else available
		local compact = available.X < Config.CompactWidth or available.Y < Config.CompactHeight
		local layout = if compact then Config.Compact else Config.Wide
		-- Desktops keep the page density's growth (at least 1); smaller screens follow the screen
		-- density (at most 1), so a phone's toast takes about the share of the screen a desktop's does.
		local scale = TextScale.Get(available) * TextScale.Screen(viewport)
		local width = math.min(layout.Width * scale, math.max(1, available.X - Config.EdgePadding * 2))
		local height = layout.Height * scale
		local origin = screen.AbsolutePosition
		local centre = available.X / 2
		local top = layout.Top
		if clock then
			top = math.max(top, math.ceil(restingRect(clock, false).Max.Y - origin.Y + Config.ClockGap))
		end
		if compact and currency and currency.Visible then
			-- Only a Currency group reaching into the toast's column pushes it down (portrait); in
			-- landscape the toast sits beside it, just below the clock.
			local bounds = restingRect(currency, true)
			local reach = width / 2 + Config.ClockGap
			if bounds.Min.X < origin.X + centre + reach and bounds.Max.X > origin.X + centre - reach then
				top = math.max(top, math.ceil(bounds.Max.Y - origin.Y + Config.ClockGap))
			end
		end

		-- An open page's panel is never covered. The HUD leaves while a page is up, so the clock's row
		-- above the panel is free; failing that, below it, then beside it, narrowed and taller.
		local blocked = if frame.Visible then openBounds(pages) else nil
		local beside = false
		if blocked then
			local gap = Config.PanelGap
			local low, high = blocked.Min - origin, blocked.Max - origin
			local across = centre - width / 2 < high.X + gap and centre + width / 2 > low.X - gap
			if across and top < high.Y + gap and top + height > low.Y - gap then
				local leftBand = low.X - gap - Config.EdgePadding
				local rightBand = available.X - Config.EdgePadding - gap - high.X
				local band = math.max(leftBand, rightBand)
				if low.Y - gap - height >= Config.EdgePadding then
					top = low.Y - gap - height
				elseif high.Y + gap + height <= available.Y - Config.EdgePadding then
					top = high.Y + gap
				elseif band >= Config.MinSideWidth * scale then
					beside = true
					width = math.min(width, band)
					centre = if rightBand >= leftBand then high.X + gap + width / 2 else low.X - gap - width / 2
					if message then
						local copy = copyHeight(
							message.Text,
							message.FontFace,
							TextScale.Size(layout.TextSize, scale),
							math.floor(width - layout.TextInset.X * scale)
						)
						height = math.max(height, copy + layout.TextInset.Y * scale)
					end
					top = math.clamp(low.Y, Config.EdgePadding, math.max(Config.EdgePadding, available.Y - height))
				end
			end
		end

		if limit then
			limit.MaxSize =
				if beside then Vector2.new(authoredLimit.X, math.max(authoredLimit.Y, height)) else authoredLimit
		end
		frame.AnchorPoint = Vector2.new(0.5, 0)
		frame.Size = UDim2.fromOffset(width, height)
		Animate.Place(frame, UDim2.fromOffset(centre, top))

		if not message then
			return
		end

		message.AnchorPoint = Vector2.one / 2
		message.Position = UDim2.fromScale(0.5, 0.5)
		message.Size = UDim2.new(1, -layout.TextInset.X * scale, 1, -layout.TextInset.Y * scale)
		message.TextXAlignment = Enum.TextXAlignment.Center
		message.TextYAlignment = Enum.TextYAlignment.Center
		message.TextWrapped = true
		message.TextScaled = true

		local constraint = message:FindFirstChildOfClass("UITextSizeConstraint")
		if constraint then
			TextScale.Bound(constraint, layout.MinTextSize, layout.TextSize, scale)
			constraint.MinTextSize = math.max(constraint.MinTextSize, Theme.ScreenScale.MinTextPixels)
		end
	end

	local cameraJanitor = Janitor.new()
	janitor:Add(cameraJanitor, "Destroy")
	local function bindCamera(): ()
		cameraJanitor:Cleanup()
		local camera = workspace.CurrentCamera
		if camera then
			cameraJanitor:Add(camera:GetPropertyChangedSignal("ViewportSize"):Connect(update), "Disconnect")
		end
		update()
	end

	janitor:Add(screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(update), "Disconnect")
	janitor:Add(screen:GetPropertyChangedSignal("AbsolutePosition"):Connect(update), "Disconnect")
	janitor:Add(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera), "Disconnect")
	-- Placement is settled as the toast appears and again whenever a page opens, closes or refits.
	janitor:Add(frame:GetPropertyChangedSignal("Visible"):Connect(update), "Disconnect")
	if message then
		janitor:Add(message:GetPropertyChangedSignal("Text"):Connect(update), "Disconnect")
	end
	for page, panel in pages do
		janitor:Add(page:GetPropertyChangedSignal("Enabled"):Connect(update), "Disconnect")
		janitor:Add(panel:GetAttributeChangedSignal("LayoutScale"):Connect(update), "Disconnect")
	end
	observeGroup(janitor, clock, update)
	observeGroup(janitor, currency, update)
	if currency then
		observeChildren(janitor, currency, update)
	end
	janitor:LinkToInstance(frame)
	bindCamera()

	return janitor
end

return StatusLayout

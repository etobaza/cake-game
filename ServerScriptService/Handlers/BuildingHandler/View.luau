--!strict
-- Physical view of a building: a placeholder part and the prompt.
-- No state here: the prompt is filled in by the client from the data. There is no floating name
-- label -- the custom prompt plate carries the name and status when the player is near.

--[[ Services ]]--
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ References ]]--
local _Shared = ReplicatedStorage.Shared
local _Configs = _Shared.Configs

--[[ Modules ]]--
local BaseConfig = require(_Configs.Base)
local BuildingsConfig = require(_Configs.Buildings)
local CollisionConfig = require(_Configs.Collision)
local Furniture = require(script.Parent.Furniture)
local TableConfig = require(_Configs.TableMenus)

--[[ Constants ]]--
local PROMPT_DISTANCE = 12
-- Named so a prompt hung on an authored model can be taken back off when the bakery is released.
local PROMPT_NAME = "PropPrompt"
local SEAT_SIZE = Vector3.new(2, 0.2, 2)

--[[ Tables ]]--
local View = {}

--[[ Private Functions ]]--
local function BuildPrompt(part: BasePart, kind: BuildingsConfig.Kind): ()
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.ActionText = "Use"
	prompt.ObjectText = kind.Label
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	-- The stock UI never renders: the client's PromptHandler draws the artist billboard instead.
	prompt.Style = Enum.ProximityPromptStyle.Custom
	-- The client enables the prompt: other players' bases are of no use here.
	prompt.Enabled = false
	prompt.Parent = part
end

--[[ Handling ]]--
-- Makes an authored part behave like one of our props: the client finds it by the tag, reads what
-- it is off the attributes and draws the prompt for it. Used where the artist already modelled the
-- thing and there is nothing for us to build (the dough spills on the kitchen floor).
function View.Dress(
	part: BasePart,
	buildingId: string,
	kindName: string,
	kind: BuildingsConfig.Kind,
	ownerUserId: number
): ()
	part:SetAttribute(BuildingsConfig.IdAttribute, buildingId)
	part:SetAttribute(BuildingsConfig.KindAttribute, kindName)
	part:SetAttribute(BaseConfig.OwnerAttribute, ownerUserId)

	if not part:FindFirstChildOfClass("ProximityPrompt") then
		BuildPrompt(part, kind)
	end

	CollectionService:AddTag(part, BuildingsConfig.Tag)
end

-- Takes all of that back off. The bakery is a live place instance, so a released one has to read
-- exactly as the artist drew it: no tag, no attributes, no prompt of ours.
function View.Undress(part: BasePart): ()
	CollectionService:RemoveTag(part, BuildingsConfig.Tag)
	part:SetAttribute(BuildingsConfig.IdAttribute, nil)
	part:SetAttribute(BuildingsConfig.KindAttribute, nil)
	part:SetAttribute(BaseConfig.OwnerAttribute, nil)

	local prompt = part:FindFirstChild(PROMPT_NAME)
	if prompt then
		prompt:Destroy()
	end
end

-- Stable authored seat indexes survive guest arrival order and the transform into another bakery.
-- Seats belong to the runtime building part, which is destroyed when the claim ends.
function View.AttachSeats(part: BasePart, anchor: Instance, transform: CFrame): boolean
	local complete = true
	for index = 1, TableConfig.SeatCount do
		local attachment = anchor:FindFirstChild(`{TableConfig.SeatAttachment}{index}`)
		if not attachment or not attachment:IsA("Attachment") then
			complete = false
			continue
		end
		local seat = Instance.new("Seat")
		seat.Name = `{TableConfig.SeatName}{index}`
		seat.Size = SEAT_SIZE
		seat.Transparency = 1
		seat.CanCollide = false
		seat.CanQuery = false
		seat.CanTouch = false
		seat.Anchored = true
		seat.CFrame = transform * attachment.WorldCFrame
		seat.Parent = part
	end
	return complete
end

function View.Create(
	buildingId: string,
	kindName: string,
	kind: BuildingsConfig.Kind,
	placement: CFrame,
	ownerUserId: number,
	template: Instance,
	furniture: BuildingsConfig.Furniture?
): BasePart
	local part = Instance.new("Part")
	part.Name = buildingId
	part.Size = kind.Size
	part.Color = kind.Color
	part.Anchored = true
	-- Props are furniture to a guest, not walls: they walk through them instead of getting wedged.
	part.CollisionGroup = CollisionConfig.Groups.Prop
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	-- The building point lies on the floor while the part CFrame is its centre.
	part.CFrame = placement * CFrame.new(0, kind.Size.Y / 2, 0)

	part:SetAttribute(BuildingsConfig.IdAttribute, buildingId)
	part:SetAttribute(BuildingsConfig.KindAttribute, kindName)
	part:SetAttribute(BaseConfig.OwnerAttribute, ownerUserId)

	if kind.Marker then
		part.Transparency = 1
		part.CanCollide = false
		part.CanQuery = false
	else
		BuildPrompt(part, kind)
	end

	-- Hidden keeps the prompt but not the block: the artist's upgrade model carries the look.
	if kind.Hidden then
		part.Transparency = 1
		part.CanCollide = false
		part.CanQuery = false
	end

	-- With real furniture the block is only the anchor: the model carries the look and the collisions.
	-- It is kept out of raycasts too, or the guide would lay its arrow tiles on an invisible box.
	local spec = furniture or kind.Furniture
	if spec then
		part.Transparency = 1
		part.CanCollide = false
		part.CanQuery = false
		Furniture.Attach(part, spec, template)
	end

	CollectionService:AddTag(part, BuildingsConfig.Tag)

	return part
end

return View

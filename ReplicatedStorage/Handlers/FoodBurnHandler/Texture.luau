--!strict
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Configs.FoodBurn)
local FoodBurn = require(ReplicatedStorage.Shared.FoodBurn)

-- Avoid three power operations per palette color on every animated update.
-- Sixteen-bit linear input keeps the sRGB byte result within one quantization step.
local ENCODE_MAX = 65535
local ENCODE = buffer.create(ENCODE_MAX + 1)
for value = 0, ENCODE_MAX do
	buffer.writeu8(ENCODE, value, math.round(FoodBurn.ToSRGB(value / ENCODE_MAX) * 255))
end

local Texture = {}
type ColorEntry = { Original: Color3, Burnt: Color3, Alpha: number }
export type Palette = {
	Size: Vector2,
	Indices: buffer,
	Pixels: buffer,
	Colors: { ColorEntry },
}

function Texture.Read(content: Content, yieldWork: (() -> ())?): Palette
	local source = AssetService:CreateEditableImageAsync(content)
	assert(source, "No editable-image memory for the food texture")
	local size = source.Size
	local factor = math.min(1, Config.TextureSize / math.max(size.X, size.Y))
	local image: EditableImage? = nil
	local ok, result = pcall(function(): Palette
		if factor < 1 then
			size = Vector2.new(math.max(1, math.floor(size.X * factor)), math.max(1, math.floor(size.Y * factor)))
			image = AssetService:CreateEditableImage({ Size = size })
			assert(image, "No editable-image memory for the food palette")
			image:DrawImageTransformed(Vector2.zero, size / source.Size, 0, source, {
				CombineType = Enum.ImageCombineType.Overwrite,
				PivotPoint = Vector2.zero,
			})
		end
		local pixels = (image or source):ReadPixelsBuffer(Vector2.zero, size)
		local indices = buffer.create(buffer.len(pixels))
		local colors: { ColorEntry } = {}
		local lookup: { [number]: number } = {}
		for offset = 0, buffer.len(pixels) - 4, 4 do
			if yieldWork and offset % 16384 == 0 then
				yieldWork()
			end
			local value = buffer.readu32(pixels, offset)
			local cached = lookup[value]
			local index = if cached then cached else #colors + 1
			if not cached then
				local original = Color3.new(
					FoodBurn.ToLinear(buffer.readu8(pixels, offset) / 255),
					FoodBurn.ToLinear(buffer.readu8(pixels, offset + 1) / 255),
					FoodBurn.ToLinear(buffer.readu8(pixels, offset + 2) / 255)
				)
				lookup[value] = index
				colors[index] = {
					Original = original,
					Burnt = FoodBurn.Target(original),
					Alpha = buffer.readu8(pixels, offset + 3),
				}
			end
			buffer.writeu32(indices, offset, index)
		end
		return { Size = size, Indices = indices, Pixels = pixels, Colors = colors }
	end)
	if image then
		image:Destroy()
	end
	source:Destroy()
	if not ok then
		error(result)
	end
	return result
end

function Texture.Render(palette: Palette, fade: number, yieldWork: (() -> ())?): buffer
	if fade == 0 then
		return palette.Pixels
	end
	local colors = buffer.create((#palette.Colors + 1) * 4)
	for index, entry in palette.Colors do
		if yieldWork and index % 2048 == 0 then
			yieldWork()
		end
		local color = entry.Original:Lerp(entry.Burnt, fade)
		local red = buffer.readu8(ENCODE, math.round(color.R * ENCODE_MAX))
		local green = buffer.readu8(ENCODE, math.round(color.G * ENCODE_MAX))
		local blue = buffer.readu8(ENCODE, math.round(color.B * ENCODE_MAX))
		buffer.writeu32(colors, index * 4, red + green * 256 + blue * 65536 + entry.Alpha * 16777216)
	end
	local pixels = buffer.create(buffer.len(palette.Indices))
	for offset = 0, buffer.len(pixels) - 4, 4 do
		if yieldWork and offset % 32768 == 0 then
			yieldWork()
		end
		buffer.writeu32(pixels, offset, buffer.readu32(colors, buffer.readu32(palette.Indices, offset) * 4))
	end
	return pixels
end

return Texture

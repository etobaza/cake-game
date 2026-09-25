--!strict
-- Reads the artist's baked bone poses without publishing new animation assets.
type Sample = { Time: number, Frame: CFrame }
export type Clip = { Duration: number, Tracks: { [string]: { Sample } } }
local Clip = {}

function Clip.Read(sequence: KeyframeSequence): Clip?
	local frames: { Keyframe } = sequence:GetKeyframes() :: any
	table.sort(frames, function(a: Keyframe, b: Keyframe): boolean
		return a.Time < b.Time
	end)
	if #frames < 2 or frames[#frames].Time <= 0 then
		return nil
	end
	local clip: Clip = { Duration = frames[#frames].Time, Tracks = {} }
	for _, frame in frames do
		for _, pose in frame:GetDescendants() do
			if not pose:IsA("Pose") or pose.Weight <= 0 then
				continue
			end
			if pose.EasingStyle ~= Enum.PoseEasingStyle.Linear then
				print(`[AmbientMotionHandler] {sequence.Name} needs baked linear poses`)
				return nil
			end
			local track = clip.Tracks[pose.Name] or {}
			track[#track + 1] = { Time = frame.Time, Frame = pose.CFrame }
			clip.Tracks[pose.Name] = track
		end
	end
	return clip
end

function Clip.Sample(track: { Sample }, time: number): CFrame
	local low, high = 1, #track
	while low < high do
		local middle = math.ceil((low + high) / 2)
		if track[middle].Time <= time then
			low = middle
		else
			high = middle - 1
		end
	end
	local a, b = track[low], track[math.min(low + 1, #track)]
	local span = b.Time - a.Time
	return a.Frame:Lerp(b.Frame, if span > 0 then math.clamp((time - a.Time) / span, 0, 1) else 0)
end

return Clip

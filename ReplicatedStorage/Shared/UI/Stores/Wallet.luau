--!strict
-- The HUD balance trails the coins flying into it. A sale holds back the part of its amount that the
-- replicated cash already contains but no coin has delivered yet, so the counter climbs as coins land.
--
-- Data replication and the sale notification arrive in either order. Each sale records the balance
-- the server reported right after it, so a sale that the cash does not include yet holds nothing and
-- the counter never dips.

--[[ Services ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ Modules ]]--
local Flux = require(ReplicatedStorage.Packages.flux)

--[[ Types ]]--
export type Sale = {
	Amount: number,
	-- Server cash right after this sale was credited.
	Balance: number,
	Landed: number,
	ExpiresAt: number,
}

--[[ Private Variables ]]--
local sales: { Sale } = {}
-- Bumped on every change so computeds reading `Hold` re-run.
local version = Flux(0)

--[[ Tables ]]--
local Wallet = {}

--[[ Private Functions ]]--
local function bump(): ()
	version:set(version:peek() + 1)
end

--[[ Handling ]]--
--- Starts holding `amount`; `balance` is the server cash reported with the sale.
function Wallet.Begin(amount: number, balance: number, seconds: number): Sale
	local sale: Sale = { Amount = amount, Balance = balance, Landed = 0, ExpiresAt = os.clock() + seconds }
	table.insert(sales, sale)
	bump()
	return sale
end

--- Releases `portion` of the sale to the counter, as one coin lands.
function Wallet.Land(sale: Sale, portion: number): ()
	sale.Landed = math.min(sale.Amount, sale.Landed + portion)
	bump()
end

--- Releases whatever the sale still holds.
function Wallet.Finish(sale: Sale): ()
	local index = table.find(sales, sale)
	if index then
		table.remove(sales, index)
		bump()
	end
end

--- Finishes sales whose coins never arrived (a closed HUD, a destroyed overlay).
function Wallet.Expire(now: number): ()
	for index = #sales, 1, -1 do
		if now >= sales[index].ExpiresAt then
			table.remove(sales, index)
			bump()
		end
	end
end

--- The amount to subtract from `cash` while coins are still in the air. Reactive inside Flux.
function Wallet.Hold(cash: number): number
	version()
	local held = 0
	for _, sale in sales do
		-- The part of this sale the replicated cash already contains.
		local included = math.clamp(cash - (sale.Balance - sale.Amount), 0, sale.Amount)
		held += math.max(0, included - sale.Landed)
	end
	return held
end

return Wallet

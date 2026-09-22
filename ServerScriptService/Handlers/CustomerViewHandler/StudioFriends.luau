--!strict
-- Verified through Studio on 2026-09-17. Development fallback for the observed
-- GetFriendsAsync discrepancy between game scripts and Studio commands.
-- Appearance only reads this snapshot in Studio, for the matching account.
type Friend = { UserId: number, Name: string, Key: string, Variant: number? }

return {
	[11124027070] = {
		{ UserId = 2604326842, Name = "Cynx", Key = "user_2604326842" },
		{ UserId = 33640830, Name = "zeworst", Key = "user_33640830" },
		{ UserId = 9328228228, Name = "FLOWED", Key = "user_9328228228" },
		{ UserId = 1432018693, Name = "IIIIIIIIIIII", Key = "user_1432018693" },
		{ UserId = 4977318608, Name = "misat1k", Key = "user_4977318608" },
		{ UserId = 3386576337, Name = "Zerus", Key = "user_3386576337" },
		{ UserId = 4854585156, Name = "ebanat", Key = "user_4854585156" },
		{ UserId = 240912984, Name = "Kaks_Hate", Key = "user_240912984" },
		{ UserId = 485823975, Name = "NOILY1", Key = "user_485823975" },
		{ UserId = 4509480017, Name = "StylizedESO", Key = "user_4509480017" },
		{ UserId = 3577064411, Name = "Vontiemare", Key = "user_3577064411" },
		{ UserId = 6094485421, Name = "ひきづや", Key = "user_6094485421" },
		{ UserId = 311733056, Name = "Xtrair", Key = "user_311733056" },
		{ UserId = 4355090275, Name = "MessorDev", Key = "user_4355090275" },
		{ UserId = 603041710, Name = "Valrus", Key = "user_603041710" },
		{ UserId = 3720499961, Name = "Zenitsu", Key = "user_3720499961" },
		{ UserId = 2366964114, Name = "Funset", Key = "user_2366964114" },
	},
} :: { [number]: { Friend } }

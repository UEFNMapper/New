--!strict
--[[
	ModelAssets : identifiants Roblox des modèles 3D (assets/models/*.glb).
	Rempli AUTOMATIQUEMENT par tools/upload_models.py (Open Cloud), ou à la main après un
	import dans Studio (voir assets/README.md). Un modèle absent = décor de secours (primitives).
	Clé = nom du fichier .glb sans extension ; valeur = ID de l'asset Model.
]]

local ModelAssets: { [string]: number } = {
	-- généré : ne pas éditer à la main entre les deux marqueurs
	-- BEGIN
	AioDrone = 130995608173007,
	AioRadiator = 100473315683288,
	Anga = 75553420446427,
	ArcadeCabinet = 135149158295782,
	BitCoin = 100222133281876,
	CableBraided24 = 86375393114214,
	CableSleeved8 = 118660076016761,
	Capacitor = 109035799869167,
	CapacitorBig = 71643410414831,
	CaseFrame = 87220284320929,
	ChipsetHeatsink = 129985061786477,
	Choke = 128880783306514,
	ChokeRow = 135560336905974,
	Corrupto = 89726505676149,
	CpuChip = 81041057784711,
	CpuCooler = 107547580697296,
	CpuSocket = 132750210182970,
	Desk = 128811058417837,
	DeskLamp = 110673925710291,
	DimmSlot = 132332787336018,
	Dusty = 89491025307755,
	Fan120 = 140226301232073,
	Fan140 = 115924236673150,
	Freezy = 118803965741228,
	GamingChair = 100469060820772,
	GiantCursor = 110976025672563,
	GpuCard = 130176706539121,
	Hand = 103092859748182,
	Headset = 83313504707900,
	IoShield = 86151536420460,
	Keyboard = 76017241297660,
	Lagz = 140562742422267,
	LagzHead = 124078328803592,
	LagzPortalCore = 122226966350172,
	M2Ssd = 123876054067748,
	MicArm = 73299523458673,
	Miniaturiseur = 111607535107362,
	Minor = 137149667906781,
	Monitor = 80445677807058,
	Mouse = 116140452660681,
	Mug = 84691755026707,
	NpuChip = 97903363057469,
	PcieSlot = 129377436594664,
	Pickaxe = 135474481774198,
	Plant = 106407128325014,
	PopUp = 135622184784978,
	Psu = 100351822529314,
	PumpReservoir = 96767696949236,
	RamStick = 133108529774258,
	SataSsd = 122513119748704,
	ShopKiosk = 76323443525353,
	Sparky = 90991455585822,
	Speaker = 88840014052728,
	TerminalConsole = 117851930769782,
	UsbKey = 92725206338226,
	VirusBug = 83291604065355,
	VrmHeatsink = 123372156375782,
	WebcamLight = 106118324737424,
	-- END
}

return table.freeze(ModelAssets)

--!strict
--[[
	RoleService : rôle coop du joueur (Config/Roles), choisi dans le menu (page Rôle) et sauvegardé.
	ChooseRole(id) : id d'un rôle, ou "" pour aucun. L'attribut joueur Role le montre aux autres
	(page Joueurs du menu). Les passifs sont appliqués là où ils comptent : MinigameService (Nettoyeur),
	PuzzleService (Enquêteur), ProgressService (Service) et le client (Technicien, jauges).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Roles = require(Shared.Config.Roles)
local Session = require(script.Parent.Parent.Core.Session)
local Wallet = require(script.Parent.Parent.Core.Wallet)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local RemoteGuard = require(script.Parent.Parent.Security.RemoteGuard)

local RoleService = {}

function RoleService.Choose(session: Session.Session, id: string)
	if id ~= "" and not Roles.IsValid(id) then
		return
	end
	if session.Data.Role == id then
		return
	end
	session.Data.Role = id
	session.Player:SetAttribute("Role", id)
	Wallet.Fx(session, "Role", { Id = id })
	GameEvents.StateChanged:Fire(session.Player)
end

function RoleService.Start()
	Session.Added:Connect(function(session: Session.Session)
		local role = session.Data.Role
		if not Roles.IsValid(role) then
			session.Data.Role = ""
		end
		session.Player:SetAttribute("Role", session.Data.Role)
	end)
	for _, session in Session.All() do
		session.Player:SetAttribute("Role", session.Data.Role)
	end
	RemoteGuard.On("ChooseRole", { Args = { RemoteGuard.String(16) } }, RoleService.Choose)
end

return RoleService

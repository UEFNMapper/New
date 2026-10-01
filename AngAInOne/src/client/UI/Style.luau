--!strict
--[[
	Style : système de style centralisé de l'UI (UI Styling de Roblox).

	- Les tokens (couleurs du Theme) deviennent des attributs d'une StyleSheet "Tokens".
	- Une StyleSheet "Design" dérive des tokens et contient les règles par tag :
	  ".Glass", ".TextTitle", ".RoundM::UICorner", etc.
	- Une StyleLink relie la feuille au ScreenGui : aucune couleur n'est écrite en dur
	  dans les écrans, ils posent seulement des tags.

	Filet de sécurité : si le moteur de style ne s'applique pas (version de Roblox,
	fonctionnalité désactivée…), Style.Verify() le détecte et applique les mêmes
	règles directement aux instances taguées. Le rendu est identique dans les deux cas.

	Seules les propriétés jamais animées passent par les règles (couleurs de fond,
	polices, tailles de texte, coins) : les transparences et tailles animées par
	TweenService restent pilotées par le code, sans conflit.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Config.Theme)

local Style = {}

export type Rule = { Selector: string, Props: { [string]: any } }

local function color(name: string): Color3
	return Color3.fromHex((Theme.Colors :: any)[name])
end

-- Couleur du thème par nom de token (pour les rares couleurs dynamiques gérées en code).
function Style.Color(name: string): Color3
	return color(name)
end

Style.Fonts = table.freeze({
	Display = Font.fromEnum(Enum.Font.BuilderSansExtraBold),
	Regular = Font.fromEnum(Enum.Font.BuilderSans),
	Medium = Font.fromEnum(Enum.Font.BuilderSansMedium),
	Bold = Font.fromEnum(Enum.Font.BuilderSansBold),
	Heavy = Font.fromEnum(Enum.Font.BuilderSansExtraBold),
})

local function text(font: Font, size: number, ink: string?): { [string]: any }
	local props: { [string]: any } = { FontFace = font, TextSize = size }
	if ink then
		props.TextColor3 = `${ink}`
	end
	return props
end

local T = Theme.TextSize
local F = Style.Fonts

-- Règles : tag -> propriétés. "$Nom" = token de couleur.
Style.Rules = {
	{ Selector = ".Glass", Props = { BackgroundColor3 = "$Surface" } },
	{ Selector = ".GlassRaised", Props = { BackgroundColor3 = "$SurfaceRaised" } },
	{ Selector = ".GlassSunken", Props = { BackgroundColor3 = "$SurfaceSunken" } },
	{ Selector = ".Backdrop", Props = { BackgroundColor3 = "$BgDeep" } },
	{ Selector = ".Metal", Props = { BackgroundColor3 = "$MetalLight" } },
	{ Selector = ".MetalDark", Props = { BackgroundColor3 = "$MetalDark" } },
	{ Selector = ".FillBrand", Props = { BackgroundColor3 = "$BrandAnga" } },
	{ Selector = ".FillCyan", Props = { BackgroundColor3 = "$AccentCyan" } },
	{ Selector = ".FillViolet", Props = { BackgroundColor3 = "$AccentViolet" } },
	{ Selector = ".FillGold", Props = { BackgroundColor3 = "$CurrencyBits" } },
	{ Selector = ".FillSuccess", Props = { BackgroundColor3 = "$Success" } },
	{ Selector = ".FillWhite", Props = { BackgroundColor3 = "$TextPrimary" } },
	{ Selector = ".FillAccent", Props = { BackgroundColor3 = "$AppAccent" } },
	{ Selector = ".FillOutline", Props = { BackgroundColor3 = "$Outline" } },

	{ Selector = ".RoundS::UICorner", Props = { CornerRadius = UDim.new(0, Theme.Radius.S) } },
	{ Selector = ".RoundM::UICorner", Props = { CornerRadius = UDim.new(0, Theme.Radius.M) } },
	{ Selector = ".RoundL::UICorner", Props = { CornerRadius = UDim.new(0, Theme.Radius.L) } },
	{ Selector = ".RoundPill::UICorner", Props = { CornerRadius = UDim.new(1, 0) } },

	{ Selector = ".TextHero", Props = text(F.Display, T.Hero, "TextPrimary") },
	{ Selector = ".TextTitle", Props = text(F.Display, T.Title, "TextPrimary") },
	{ Selector = ".TextHeading", Props = text(F.Bold, T.BodyLarge, "TextPrimary") },
	{ Selector = ".TextBody", Props = text(F.Medium, T.Body, "TextPrimary") },
	{ Selector = ".TextMuted", Props = text(F.Medium, T.Body - 2, "TextMuted") },
	{ Selector = ".TextCaption", Props = text(F.Bold, T.Caption, "TextMuted") },
	{ Selector = ".TextNumber", Props = text(F.Heavy, T.Title, "TextPrimary") },
	{ Selector = ".TextBits", Props = text(F.Heavy, T.Title, "CurrencyBits") },
	{ Selector = ".TextChips", Props = text(F.Heavy, T.BodyLarge, "CurrencyChips") },
	{ Selector = ".TextKey", Props = text(F.Heavy, T.Body, "TextPrimary") },
	{ Selector = ".TextKeyDark", Props = text(F.Heavy, T.Body, "BgDeep") },
	{ Selector = ".TextKeySmall", Props = text(F.Heavy, T.Body - 2, "TextPrimary") },
	{ Selector = ".TextKeySmallDark", Props = text(F.Heavy, T.Body - 2, "BgDeep") },
	-- Variantes "Dyn" : police/taille seulement, la couleur est pilotée par le code.
	{ Selector = ".DynHeading", Props = text(F.Bold, T.BodyLarge) },
	{ Selector = ".DynBody", Props = text(F.Medium, T.Body) },
	{ Selector = ".DynCaption", Props = text(F.Bold, T.Caption) },
	{ Selector = ".DynNumber", Props = text(F.Heavy, T.Title) },
	-- Variantes "Font" : police seulement (taille ET couleur pilotées par le code).
	{ Selector = ".FontDisplay", Props = { FontFace = F.Display } },
	{ Selector = ".FontHeavy", Props = { FontFace = F.Heavy } },
	{ Selector = ".FontBold", Props = { FontFace = F.Bold } },
	{ Selector = ".FontMedium", Props = { FontFace = F.Medium } },
} :: { Rule }

local tokensSheet: StyleSheet? = nil
local designSheet: StyleSheet? = nil
local fallback = false
local root: Instance? = nil

local function resolve(value: any): any
	if type(value) == "string" and string.sub(value, 1, 1) == "$" then
		return color(string.sub(value, 2))
	end
	return value
end

local function buildSheets(): StyleSheet
	local tokens = Instance.new("StyleSheet")
	tokens.Name = "Tokens"
	for name, hex in Theme.Colors :: any do
		tokens:SetAttribute(name, Color3.fromHex(hex))
	end
	local design = Instance.new("StyleSheet")
	design.Name = "Design"
	local derive = Instance.new("StyleDerive")
	derive.StyleSheet = tokens
	derive.Parent = design
	for index, rule in Style.Rules do
		local styleRule = Instance.new("StyleRule")
		styleRule.Name = `Rule{index}`
		styleRule.Selector = rule.Selector
		styleRule.Priority = index
		styleRule:SetProperties(rule.Props)
		styleRule.Parent = design
	end
	tokensSheet = tokens
	designSheet = design
	return design
end

-- Applique directement une règle à une instance (mode repli).
local function applyDirect(instance: Instance, rule: Rule)
	local selector = rule.Selector
	local modifier = string.match(selector, "::(%w+)$")
	if modifier then
		local existing = instance:FindFirstChildOfClass(modifier)
		local target = existing or Instance.new(modifier)
		for key, value in rule.Props do
			(target :: any)[key] = resolve(value)
		end
		target.Parent = instance
	else
		for key, value in rule.Props do
			pcall(function()
				(instance :: any)[key] = resolve(value)
			end)
		end
	end
end

local function tagOf(selector: string): string?
	return string.match(selector, "^%.([%w]+)")
end

local function applyAllDirect(instance: Instance)
	for _, rule in Style.Rules do
		local tag = tagOf(rule.Selector)
		if tag and instance:HasTag(tag) then
			applyDirect(instance, rule)
		end
	end
end

-- Relie la feuille de style au ScreenGui racine.
function Style.Mount(screenGui: Instance)
	root = screenGui
	local design = buildSheets()
	-- Feuilles côte à côte (comme dans la documentation) : Tokens <- Design (StyleDerive).
	if tokensSheet then
		tokensSheet.Parent = screenGui
	end
	design.Parent = screenGui
	local link = Instance.new("StyleLink")
	link.StyleSheet = design
	link.Parent = screenGui
end

-- Vérifie que le moteur de style s'applique ; sinon bascule sur le repli direct.
function Style.Verify(screenGui: Instance)
	local probe = Instance.new("Frame")
	probe.Name = "StyleProbe"
	probe.Size = UDim2.fromOffset(1, 1)
	probe.BackgroundTransparency = 1
	CollectionService:AddTag(probe, "Glass")
	probe.Parent = screenGui
	task.wait(0.5)
	local expected = color("Surface")
	-- GetStyled renvoie la valeur issue des StyleRules ; la lecture directe ne les voit pas.
	local okStyled, styled = pcall(function(): any
		return probe:GetStyled("BackgroundColor3")
	end)
	local got: Color3 = if okStyled and typeof(styled) == "Color3" then styled else probe.BackgroundColor3
	probe:Destroy()
	local ok = math.abs(got.R - expected.R) < 0.01
		and math.abs(got.G - expected.G) < 0.01
		and math.abs(got.B - expected.B) < 0.01
	if not ok then
		warn("[Style] Le moteur UI Styling ne s'applique pas : bascule sur le mode direct.")
		fallback = true
		for _, descendant in screenGui:GetDescendants() do
			applyAllDirect(descendant)
		end
		-- Toute UI créée ensuite reçoit aussi les règles (les tags sont posés avant le parentage).
		screenGui.DescendantAdded:Connect(applyAllDirect)
	end
end

-- Applique les règles à une UI hors du ScreenGui racine (SurfaceGui, BillboardGui).
function Style.ApplyTo(instance: Instance)
	applyAllDirect(instance)
	for _, descendant in instance:GetDescendants() do
		applyAllDirect(descendant)
	end
end

function Style.IsFallback(): boolean
	return fallback
end

function Style.Sheets(): (StyleSheet?, StyleSheet?, Instance?)
	return tokensSheet, designSheet, root
end

return Style

--!strict
--[[
	Create : constructeur d'instances déclaratif pour l'UI.

		local label = New("TextLabel", {
			Name = "Title",
			Text = "Bonjour",
			Tag = "TextTitle",          -- tag(s) de style (voir Style.luau)
			Parent = frame,
		}, {
			New("UIPadding", { PaddingLeft = UDim.new(0, 8) }),
		})
]]

local CollectionService = game:GetService("CollectionService")

local Create = {}

function Create.New(className: string, props: { [string]: any }?, children: { any }?): any
	local instance = Instance.new(className)
	local parent: Instance? = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			elseif key == "Tag" then
				if type(value) == "table" then
					for _, tag in value do
						CollectionService:AddTag(instance, tag)
					end
				else
					CollectionService:AddTag(instance, value)
				end
			else
				(instance :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

-- Raccourcis fréquents
function Create.Corner(radius: number): UICorner
	return Create.New("UICorner", { CornerRadius = UDim.new(0, radius) })
end

function Create.Padding(all: number, horizontal: number?): UIPadding
	local h = horizontal or all
	return Create.New("UIPadding", {
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, h),
		PaddingRight = UDim.new(0, h),
	})
end

function Create.List(direction: Enum.FillDirection, padding: number, props: { [string]: any }?): UIListLayout
	local layout = Create.New("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, padding),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	if props then
		for key, value in props do
			(layout :: any)[key] = value
		end
	end
	return layout
end

return table.freeze(Create)

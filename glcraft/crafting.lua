local shlocals = ...
local plan_f=shlocals.plan_f

local recipes_custom={}
local recipes={}
local usages={}
local cg_ctypes={shaped=true,shapeless=true,toolrepair=true}

--function glcraft.register_recipe()
--end
--
--function glcraft.unregister_recipe()
--end

local scan_usages,scan_usages_now,plan_usage_scan

local function scan_recipes()
	shlocals.scan_groups_now()
	recipes={}
	for item,crafts in pairs(minetest.registered_crafts) do
		for recipe,_ in pairs(crafts) do
			recipes[item]=recipes[item] or {}
			recipes[item][recipe]=true
		end
	end
	scan_usages_now(true)
	minetest.safe_file_write(minetest.get_worldpath().."/glcraft_recipes.txt",dump{recipes=recipes,usages=usages})
end
local function scan_ur(recipe)
	shlocals.scan_groups_now()
	local recip=recipe.recipe or {}
	if recipe.type=="toolrepair" then
		recip={recipe.output}
	elseif type(recip)=="string" then
		recip={recip}
	end
	if type(recip[1])=="table" then
		local rr=recip
		recip={}
		for k,v in pairs(rr) do
			for k,v in pairs(v) do
				recip[#recip+1]=v
			end
		end
	end
	for k,v in pairs(recip) do
		v=ItemStack(v):get_name()
		if v~="" then
			if v:sub(1,6)=="group:" then
				local gg=shlocals.item_groups[v:sub(7,-1)]
				if gg then
					for k,v in pairs(gg.list) do
						usages[v]=usages[v] or {}
						usages[v][recipe]=true
					end
				end
			else
				usages[v]=usages[v] or {}
				usages[v][recipe]=true
			end
		end
	end
end
scan_usages = function()
	usages={}
	for item,crafts in pairs(recipes) do
		for recipe,_ in pairs(crafts) do
			scan_ur(recipe)
		end
	end
	for item,crafts in pairs(recipes_custom) do
		for recipe,_ in pairs(crafts) do
			scan_ur(recipe)
		end
	end
end
local plan_recipe_scan,scan_recipes_now = plan_f(scan_recipes)
plan_usage_scan,scan_usages_now = plan_f(scan_usages)
plan_recipe_scan()
minetest.register_craft=plan_recipe_scan(minetest.register_craft)
minetest.clear_craft=plan_recipe_scan(minetest.clear_craft)
shlocals.scan_groups=plan_recipe_scan(shlocals.scan_groups)

local function get_recipe_inputs(recipe)
	local inputs={}
	local rt=recipe.type or "shaped"
	local valid=true
	if rt=="shaped" then
		for k,v in pairs(recipe.recipe) do
			for k,v in pairs(v) do
				table.insert(inputs,v)
			end
		end
	elseif rt=="shapeless" then
		for k,v in pairs(recipe.recipe) do
			table.insert(inputs,v)
		end
	elseif rt=="toolrepair" then
		for n=1,2 do
			table.insert(inputs,ItemStack(recipe.output):get_name())
		end
	else
		valid=false
	end
	return valid and inputs
end

local function check_recipe_input(inp,name)
	local inp=inp
	if inp:sub(1,6)=="group:" then
		local gg=shlocals.item_groups[inp:sub(7,-1)]
		inp=(gg and gg.map[name]) and name or ""
	end
	return name==inp
end

function glcraft.get_craftables(inv,lname)
	local main = inv:get_list(lname or "main")
	local items={}
	local recipes={}
	for _,item in pairs(main) do
		local name=item:get_name()
		if name ~= "" then
			if not items[name] then
				if usages[name] then
					for k,v in pairs(usages[name]) do
						recipes[k]=true
					end
				end
			end
			items[name]=items[name] or 0
			items[name]=items[name]+item:get_count()
		end
	end
	local craftables={}
	for recipe,_ in pairs(recipes) do
		local inputs=get_recipe_inputs(recipe)
		if inputs then
			local items_={}
			for k,v in pairs(items) do
				items_[k]=v
			end
			local sati=true
			for _,inp in pairs(inputs) do
				if inp~="" then
					local satisfied=false
					for name,count in pairs(items_) do
						if check_recipe_input(inp,name) and items_[name]>0 then
							satisfied=true
							items_[name]=items_[name]-1
							break
						end
					end
					if not satisfied then
						sati=false
						break
					end
				end
			end
			if sati then
				local out=ItemStack(recipe.output):get_name()
				craftables[out]=craftables[out] or {}
				table.insert(craftables[out],recipe)
			end
		end
	end
	for k,v in pairs(craftables) do
		table.sort(v,function(a,b) return (a.__reg_order or math.huge) < (b.__reg_order or math.huge) end)
	end
	return craftables
end

function glcraft.craft(inv,ilname,olname,recipe,count,player,pos)
	local pos = pos or player:get_pos()
	local il=inv:get_list(ilname)
	local inputs=get_recipe_inputs(recipe)
	local countz=0
	if inputs then
		for n=1,count do
			local sati=true
			for _,inp in pairs(inputs) do
				if inp~="" then
					local satisfied=false
					for _,item in ipairs(il) do
						local name=item:get_name()
						if name~="" and check_recipe_input(inp,name) then
							item:take_item(1)
							satisfied=true
							break
						end
					end
					if not satisfied then sati=false break end
				end
			end
			if sati then
				inv:set_list(ilname,il)
				countz=countz+1
			else
				break
			end
		end
	end
	for n=1,countz do
		local left=inv:add_item(olname,ItemStack(recipe.output))
		if left:get_count()>0 then
			minetest.item_drop(left,dropper,pos)
		end
	end
	return countz
end

glcraft={}
local shlocals={}

local player_data={}
local item_groups={}
shlocals.player_data=player_data
shlocals.item_groups=item_groups

local W,H=8,4
local SCALING=1
W,H=math.floor(W/SCALING),math.floor(H/SCALING)
local modname=minetest.get_current_modname()
local modpath=minetest.get_modpath(modname)
shlocals.modname=modname
shlocals.modpath=modpath

local function include(path,...)
	local path=path
	if path:sub(1,1)~="/" then
		path=modpath.."/"..path
	end
	local ok,err=loadfile(path)
	assert(ok,err)
	return ok(...)
end
shlocals.include=include

local function scan_groups()
	item_groups={}
	shlocals.item_groups=item_groups
	for name,item in pairs(minetest.registered_items) do
		for group,amount in pairs(item.groups) do
			if (type(amount)=="number" and amount>0) or (type(amount)~="number" and amount) then
				item_groups[group] = item_groups[group] or {list={},map={}}
				item_groups[group].map[name] = true
				table.insert(item_groups[group].list,name)
			end
		end
	end
end
shlocals.scan_groups=scan_groups

local function plan_f(fu)
	local planned=false
	local plan
	plan=function(f)
		if f then
			return function(...)
				plan()
				return f(...)
			end
		end
		if planned then return end
		planned=true
		minetest.after(0,function()
			if planned then
				fu()
				planned=false
			end
		end)
	end
	local now=function(ig)
		if planned or ig then
			fu()
			planned=false
		end
	end
	return plan,now
end
shlocals.plan_f=plan_f

plan_group_scan,scan_groups_now=plan_f(function(...)return shlocals.scan_groups(...) end)
shlocals.plan_group_scan=plan_group_scan
shlocals.scan_groups_now=scan_groups_now
plan_group_scan()
for _,fname in pairs{"register_item","override_item","unregister_item"} do
	minetest[fname]=plan_group_scan(minetest[fname])
end

local esc = minetest.formspec_escape

function glcraft.item_button(data)
	local item=data.item
	local is_gr,tooltip
	local it=ItemStack(item)
	local iname=it:get_name()
	local gggg="group:"
	if iname:sub(1,#gggg)==gggg then
		is_gr=true
		local group=iname:sub(#gggg+1,-1)
		scan_groups_now()
		local its = item_groups[group]
		tooltip = "Any group:"..group
		if its then
			its = its.list
			it:set_name(its[math.random(1,#its)])
		else
			it:set_name("unknown")
		end
	else
		local def = minetest.registered_items[iname]
		local desc = def and (def.description or def.short_description)
		tooltip = desc and desc.."\n"..minetest.colorize("grey",iname) or iname
	end
	item=it:to_string()

	local scaling = data.scaling or 1
	return ("item_image_button[%s,%s;%s,%s;%s;%s;%s]")
	       :format(data.x,data.y,(1*scaling)+0.05,(1*scaling)+0.05,esc(item),esc(data.name),is_gr and "G" or "")..
	       (tooltip and ("tooltip[%s;%s]"):format(esc(data.name),esc(tooltip)) or "")
end

local function itemlist_form(data)
	local form = 
		"image_button[5,4;0.8,0.8;craftguide_prev_icon.png;glcraft_items_prev;]" ..
		"image_button[7.2,4;0.8,0.8;craftguide_next_icon.png;glcraft_items_next;]" ..
		("label[5.8,4.15;%s / %s]"):format(esc(minetest.colorize("yellow",data.page)),data.npages)
	local off=(data.page-1)*(W*H)+1
	for x=0,W-1 do
		for y=0,H-1 do
			local off=off+x+y*W
			local item = data.items[off]
			if item then
				form = form .. glcraft.item_button{
					x=x*SCALING,y=y*SCALING,
					scaling=SCALING,
					item = item,
					name="glcraft_items_item_"..minetest.encode_base64(item) --item
				}
			end
		end
	end
	return form
end

local function display_recipe(recipe,count)
	local count=count or 1
	local out=ItemStack(recipe.output)
	out:set_count(out:get_count()*count)
	out=out:to_string()
	local form="image[3,1;1,1;sfinv_crafting_arrow.png]"..
	glcraft.item_button{
		x=4,y=1,
		item=out,
		name="glcraft_crafts_output"
	}
	local grid={}
	local rt=recipe.type or "shaped"
	if rt=="shapeless" then
		grid=recipe.recipe
	elseif rt=="toolrepair" then
		local out=ItemStack(recipe.output):get_name()
		grid={out,out}
	elseif rt=="shaped" then
		for k,v in ipairs(recipe.recipe) do
			for k,v in ipairs(v) do
				if v~="" then
					table.insert(grid,v)
				end
			end
		end
	end
	local gg=grid
	grid={}
	for k,v in pairs(gg) do
		grid[v]=(grid[v] or 0)+1
	end
	gg,grid=grid,{}
	for k,v in pairs(gg) do
		local is=ItemStack(k)
		is:set_count(v)
		table.insert(grid,is:to_string())
	end
	table.sort(grid)
	gg,grid=grid,{}
	do
		local x,y=1,1
		for k,v in ipairs(gg) do
			grid[y]=grid[y]or{}
			grid[y][x]=v
			x=x+1
			if x>3 then
				x,y=1,y+1
			end
		end
	end
	local hei=#grid
	local wid=#grid[1]
	local offy=-(math.floor(hei/2))
	local offx=-(math.floor(wid-1))
	for y,v in ipairs(grid) do
		for x,v in ipairs(v) do
			if v~="" then
				local v=ItemStack(v)
				v:set_count(v:get_count()*count)
				v=v:to_string()
				form=form..glcraft.item_button{
					x=(2+offx)+(x-1),y=(1+offy)+(y-1),
					item=v,
					name="glcraft_crafts_input_"..x.."_"..y
				}
			end
		end
	end
	return form
end

local function craftlist_form(data)
	local form = 
		(data.count and "button[5,4;3,0.8;glcraft_crafts_craft;Craft]" or
		("image_button[5,4;0.8,0.8;craftguide_prev_icon.png;glcraft_crafts_prev;]" ..
		"image_button[7.2,4;0.8,0.8;craftguide_next_icon.png;glcraft_crafts_next;]" ..
		("label[5.8,4.15;%s / %s]"):format(esc(minetest.colorize("yellow",data.n or "?")),#data.recipes)))..
		("button[0,4;0.8,0.8;glcraft_crafts_back;%s]"):format(data.count and esc("X") or esc("<-"))
		
	if data.n then
		for k,v in ipairs{"1","10","100"} do
			form=form..("button[%s,4;0.9,0.8;glcraft_crafts_craft_%s;+%s]"):format((k-1)*0.7+0.7,v,v)
		end
	end
	if data.count then
		form=form..("label[3,4.15;%s]"):format(data.count)
	end
	if data.recipe then
		form=form.."container[0,0.5]"
		form=form..display_recipe(data.recipe,data.count)
		form=form.."container_end[]"
	end
	return form
	
end

local function get_formspec(player)
	local name = player:get_player_name()
	local data = player_data[name]
	if data.crafts then
		return craftlist_form(data.crafts)
	end
	return itemlist_form(data.items)
end

local function update_itemlist(player,first)
	local name=player:get_player_name()
	local items={}
	local pdata=player_data[name]
	local data=pdata.items or {}
	player_data[name].items=data
	local oldinv=data.oldinv
	local inv=player:get_inventory()
	local invl=dump(inv:get_list("main"))
	if invl~=data.oldinv then
		data.oldinv=invl
		local crafts=glcraft.get_craftables(inv)
		data.crafts=crafts
		for k,v in pairs(crafts) do
			table.insert(items,k)
		end
		if pdata.crafts then
			local data=pdata.crafts
			data.recipes=crafts[data.item] or {}
			if data.recipes[data.n]~=data.recipe then
				data.n=nil
			end
			if not data.n then
				for k,v in pairs(data.recipes) do
					if v==data.recipe then
						data.n=k
					end
				end
			end
		end
		table.sort(items)
		data.items=items
		data.npages=math.max(1,math.ceil(#items/(W*H)))
		data.page=math.min(data.npages,data.page or 1)
		if not first then
			sfinv.set_player_inventory_formspec(player)
		end
	end
end

local function on_receive_fields(player,fields)
	local name=player:get_player_name()
	local data=player_data[name]
	do -- Items list
		local pdata=data
		local data=data.items
		local p=0
		if fields.glcraft_items_prev then
			p=p-1
		end
		if fields.glcraft_items_next then
			p=p+1
		end
		if p~=0 then
			data.page=(data.page+p-1)%data.npages+1
			return true
		end
		local ilb_pre="glcraft_items_item_"
		for k,v in pairs(fields) do
			if k:sub(1,#ilb_pre)==ilb_pre then
				local it=k:sub(#ilb_pre+1,-1)
				it=minetest.decode_base64(it)
				if it then
					local recipes=data.crafts[it]
					if recipes then
						pdata.crafts={n=1,recipe=recipes[1],item=it,recipes=recipes}
						return true
					end
				end
			end
		end
	end
	do -- Craft list 
		local pdata=data
		local data=data.crafts
		if data then
			local p=0
			if fields.glcraft_crafts_prev then
				p=p-1
			end
			if fields.glcraft_crafts_next then
				p=p+1
			end
			if fields.glcraft_crafts_back then
				if data.count then
					data.count=nil
				else
					pdata.crafts=nil
				end
				return true
			end
			if p~=0 then
				if #data.recipes>0 then
					if data.n then
						data.n=(data.n+p-1)%(#data.recipes)+1
						data.recipe=data.recipes[data.n]
					else
						data.n=1
						data.recipe=data.recipes[1]
					end
					return true
				end
			end
			local ilb_pre="glcraft_crafts_craft_"
			for k,v in pairs(fields) do
				if k:sub(1,#ilb_pre)==ilb_pre and data.recipe then
					local num=tonumber(k:sub(#ilb_pre+1,-1)) or 1
					data.count=(data.count or 0)+num
					return true
				end
			end
			if fields.glcraft_crafts_craft and data.recipe and data.count then
				local c=glcraft.craft(player:get_inventory(),"main","main",data.recipe,data.count,player)
				data.count=data.count-c
				if data.count<=0 then
					data.count=nil
				end
				update_itemlist(player)
				return true
			end
		end
	end
end

local function make_data(player)
	local name = player:get_player_name()
	if player_data[name] then return end
	player_data[name] = {}
	update_itemlist(player,true)
end

local function delete_data(player)
	if not player_data[name] then return end
        local name = player:get_player_name()
        player_data[name] = nil
end

minetest.register_on_joinplayer(make_data)
minetest.register_on_leaveplayer(delete_data)
minetest.register_globalstep(function(dt)
	for k,v in pairs(minetest.get_connected_players()) do
		update_itemlist(v)
	end
end)

sfinv.override_page("sfinv:crafting", {
	get = function(self, player, context)
		make_data(player)
		return sfinv.make_formspec(player, context, get_formspec(player), true)
	end,
        on_player_receive_fields = function(self, player, context, fields)
		if on_receive_fields(player,fields) then
			sfinv.set_player_inventory_formspec(player)
		end
        end
})

include(modpath.."/crafting.lua",shlocals)

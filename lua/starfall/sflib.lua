-------------------------------------------------------------------------------
-- The main Starfall library
-------------------------------------------------------------------------------

if SF ~= nil then return end
SF = {}

--jit.off() -- Needed so ops counting will work reliably.
-- Completely and totally useless now.

-- Do a couple of checks for retarded mods that disable the debug table
-- and run it after all addons load
-- Do they actually exist? o_0
--[[
do
	local function zassert(cond, str)
		if not cond then error("STARFALL LOAD ABORT: "..str,0) end
	end

	zassert(debug, "debug table removed")

	-- Check for modified getinfo
	local info = debug.getinfo(0,"S")
	zassert(info, "debug.getinfo modified to return nil")
	zassert(info.what == "C", "debug.getinfo modified")

	-- Check for modified setfenv
	info = debug.getinfo(debug.setfenv, "S")
	zassert(info.what == "C", "debug.setfenv modified")

	-- Check get/setmetatable
	info = debug.getinfo(debug.getmetatable)
	zassert(info.what == "C", "debug.getmetatable modified")
	info = debug.getinfo(debug.setmetatable)
	zassert(info.what == "C", "debug.setmetatable modified")

	-- Lock the debug table
	local olddebug = debug
	debug = setmetatable({}, {
		__index = olddebug,
		__newindex = function(self,k,v) print("Addon tried to modify debug table") end,
		__metatable = "nope.avi",
	})
end
--]]

-- Send files to client
if SERVER then
	AddCSLuaFile("sflib.lua")
	AddCSLuaFile("compiler.lua")
	AddCSLuaFile("instance.lua")
	AddCSLuaFile("libraries.lua")
	AddCSLuaFile("database.lua")
	AddCSLuaFile("preprocessor.lua")
	AddCSLuaFile("permissions/core.lua")
	AddCSLuaFile("editor.lua")
	AddCSLuaFile("callback.lua")
end

-- Load files
include("compiler.lua")
include("instance.lua")
include("libraries.lua")
include("database.lua")
include("preprocessor.lua")
include("permissions/core.lua")
include("editor.lua")

-- Useless
-- SF.defaultquota = CreateConVar("sf_defaultquota", "300000", {FCVAR_ARCHIVE,FCVAR_REPLICATED},
-- 	"The default number of Lua instructions to allow Starfall scripts to execute")
	
local dgetmeta = debug.getmetatable

--- Throws an error like the throw function in builtins
-- @param msg Error message
-- @param level Which level in the stacktrace to blame
-- @param uncatchable Makes this exception uncatchable
function SF.throw (msg, level, uncatchable)
	local info = debug.getinfo(1 + (level or 1), "Sl")
	local filename = info.short_src:match("^SF:(.*)$") or info.short_src
	local err = {
		uncatchable = false,
		file = filename,
		line = info.currentline,
		message = msg,
		uncatchable = uncatchable
	}
	error(err)
end

--- Creates a type that is safe for SF scripts to use. Instances of the type
-- cannot access the type's metatable or metamethods.
-- @param name Name of table
-- @param supermeta The metatable to inheret from
-- @return The table to store normal methods
-- @return The table to store metamethods
SF.Types = {}
function SF.Typedef(name, supermeta)
	local methods, metamethods = {}, {}
	metamethods.__metatable = name
	metamethods.__index = methods
	
	metamethods.__supertypes = {[metamethods] = true}
	
	if supermeta then
		setmetatable(methods, {__index=supermeta.__index})
		metamethods.__supertypes[supermeta] = true
		if supermeta.__supertypes then
			for k,_ in pairs(supermeta.__supertypes) do
				metamethods.__supertypes[k] = true
			end
		end
	end

	SF.Types[name] = metamethods
	return methods, metamethods
end

function SF.GetTypeDef(name)
	return SF.Types[name]
end

-- Include this file after Typedef as this file relies on it.
include("callback.lua")

do
	local env, metatable = SF.Typedef("Environment")
	--- The default environment metatable
	SF.DefaultEnvironmentMT = metatable
	--- The default environment contents
	SF.DefaultEnvironment = env
end

--- A set of all instances that have been created. It has weak keys and values.
-- Instances are put here after initialization.
SF.allInstances = setmetatable({},{__mode="kv"})

--- Calls a script hook on all processors.
function SF.RunScriptHook(hook,...)
	for _,instance in pairs(SF.allInstances) do
		if not instance.error then
			local ok, err = instance:runScriptHook(hook,...)
			if not ok then
				instance.error = 7
				if instance.runOnError then
					instance:runOnError(err)
				end
			end
		end
	end
end

--- Creates a new context. A context is used to define what scripts will have access to.
-- @param env The environment metatable to use for the script. Default is SF.DefaultEnvironmentMT
-- @param directives Additional Preprocessor directives to use. Default is an empty table
-- @param permissions The permissions manager to use. Default is SF.DefaultPermissions
-- @param slice CPU time slice function. Default is returned when calling slice()
-- @param libs Additional (local) libraries for the script to access. Default is an empty table.
SF.CpuTimeQuota = 0.200 -- in seconds
local function get_defaultquota()
	--return SF.defaultquota:GetInt()
	return SF.CpuTimeQuota
end
function SF.CreateContext(env, directives, slice, libs)
	local context = {}
	context.env = env or SF.DefaultEnvironmentMT
	context.directives = directives or {}
	context.slice = slice or get_defaultquota
	context.libs = libs or {}
	return context
end

--- Checks the type of val. Errors if the types don't match
-- @param val The value to be checked.
-- @param typ A string type or metatable.
-- @param level Level at which to error at. 3 is added to this value. Default is 0.
-- @param default A value to return if val is nil.
function SF.CheckType(val, typ, level, default)
	if val == nil and default ~= nil then return default
	elseif type(val) == typ then return val
	else
		local meta = dgetmeta(val)
		if meta == typ or (meta and meta.__supertypes and meta.__supertypes[typ]) then return val end
		
		-- Failed, throw error
		level = (level or 0) + 3
		
		local typname
		if type(typ) == "table" then
			assert(typ.__metatable and type(typ.__metatable) == "string")
			typname = typ.__metatable
		else
			typname = typ
		end
		
		local funcname = debug.getinfo(level-1, "n").name or "<unnamed>"
		local mt = getmetatable(val)
		error("Type mismatch (Expected "..typname..", got "..(type(mt) == "string" and mt or type(val))..") in function "..funcname,level)
	end
end

--- Gets the type of val.
-- @param val The value to be checked.
function SF.GetType(val)
	local mt = dgetmeta(val)
	return (mt and mt.__metatable and type(mt.__metatable) == "string") and mt.__metatable or type(val)
end

-- ------------------------------------------------------------------------- --

local object_wrappers = {}

--- Creates wrap/unwrap functions for sensitive values, by using a lookup table
-- (which is set to have weak keys and values)
-- @param metatable The metatable to assign the wrapped value.
-- @param weakwrapper Make the wrapper weak inside the internal lookup table. Default: True
-- @param weaksensitive Make the sensitive data weak inside the internal lookup table. Default: True
-- @param target_metatable (optional) The metatable of the object that will get
-- 		wrapped by these wrapper functions.  This is required if you want to
-- 		have the object be auto-recognized by the generic SF.WrapObject
--		function.
-- @return The function to wrap sensitive values to a SF-safe table
-- @return The function to unwrap the SF-safe table to the sensitive table
function SF.CreateWrapper(metatable, weakwrapper, weaksensitive, target_metatable)
	local s2sfmode = ""
	local sf2smode = ""
	
	if weakwrapper == nil or weakwrapper then
		sf2smode = "k"
		s2sfmode = "v"
	end
	if weaksensitive then
		sf2smode = sf2smode.."v"
		s2sfmode = s2sfmode.."k"
	end 

	local sensitive2sf = setmetatable({},{__mode=s2sfmode})
	local sf2sensitive = setmetatable({},{__mode=sf2smode})
	
	local function wrap(value)
		if value == nil then return nil end
		if sensitive2sf[value] then return sensitive2sf[value] end
		local tbl = setmetatable({},metatable)
		sensitive2sf[value] = tbl
		sf2sensitive[tbl] = value
		return tbl
	end
	
	local function unwrap(value)
		return sf2sensitive[value]
	end
	
	if target_metatable ~= nil then
		object_wrappers[target_metatable] = wrap
		metatable.__wrap = wrap
	end
	
	metatable.__unwrap = unwrap
	
	return wrap, unwrap
end

--- Helper function for adding custom wrappers
-- @param object_meta metatable of object
-- @param sf_object_meta starfall metatable of object
-- @param wrapper function that wraps object
function SF.AddObjectWrapper(object_meta, sf_object_meta, wrapper)
	sf_object_meta.__wrap = wrapper
	object_wrappers[object_meta] = wrapper
end

--- Helper function for adding custom unwrappers
-- @param object_meta metatable of object
-- @param unwrapper function that unwraps object
function SF.AddObjectUnwrapper(object_meta, unwrapper)
	object_meta.__unwrap = unwrapper
end

--- Wraps the given object so that it is safe to pass into starfall
-- It will wrap it as long as we have the metatable of the object that is
-- getting wrapped.
-- @param object the object needing to get wrapped as it's passed into starfall
-- @return returns nil if the object doesn't have a known wrapper,
-- or returns the wrapped object if it does have a wrapper.
function SF.WrapObject(object)
	local metatable = dgetmeta(object)
	
	local wrap = object_wrappers[metatable]
	return wrap and wrap(object)
end

--- Takes a wrapped starfall object and returns the unwrapped version
-- @param object the wrapped starfall object, should work on any starfall
-- wrapped object.
-- @return the unwrapped starfall object
function SF.UnwrapObject(object)
	local metatable = dgetmeta(object)
	
	if metatable and metatable.__unwrap then
		return metatable.__unwrap(object)
	end
end

local wrappedfunctions = setmetatable({},{__mode="kv"})
local wrappedfunctions2instance = setmetatable({},{__mode="kv"})
--- Wraps the given starfall function so that it may called directly by GMLua
-- @param func The starfall function getting wrapped
-- @param instance The instance the function originated from
-- @return a function That when called will call the wrapped starfall function
function SF.WrapFunction(func, instance)
	if wrappedfunctions[func] then return wrappedfunctions[func] end
	
	local function returned_func(...)
		return SF.Unsanitize(instance:runFunction(func, SF.Sanitize(...)))
	end
	wrappedfunctions[func] = returned_func
	wrappedfunctions2instance[returned_func] = instance
	
	return returned_func
end

--- Gets the instance a wrapped function is bound to
-- @param func Function
-- @return Instance
function SF.WrappedFunctionInstance(func)
	return wrappedfunctions2instance[func]
end

-- A list of safe data types
local safe_types = {
	["number"  ] = true,
	["string"  ] = true,
	["Vector"  ] = true,
	["Color"   ] = true,
	["Angle"   ] = true,
	["Angle"   ] = true,
	["Matrix"  ] = true,
	["boolean" ] = true,
	["nil"     ] = true,
}

--- Sanitizes and returns its argument list.
-- Basic types are returned unchanged. Non-object tables will be
-- recursed into and their keys and values will be sanitized. Object
-- types will be wrapped if a wrapper is available. When a wrapper is
-- not available objects will be replaced with nil, so as to prevent
-- any possiblitiy of leakage. Functions will always be replaced with
-- nil as there is no way to verify that they are safe.
function SF.Sanitize(...)
	-- Sanitize ALL the things.
	local return_list = {}
	local args = {...}
	
	for key, value in pairs(args) do
		local typ = type(value)
		if safe_types[ typ ] then
			return_list[key] = value
		elseif (typ == "table" or typ == "Entity" or typ == "Player" or typ == "NPC") and SF.WrapObject(value) then
			return_list[key] = SF.WrapObject(value)
		elseif typ == "table" then
			local tbl = {}
			for k,v in pairs(value) do
				tbl[SF.Sanitize(k)] = SF.Sanitize(v)
			end
			return_list[key] = tbl
		else 
			return_list[key] = nil
		end
	end
	
	return unpack(return_list)
end

--- Takes output from starfall and does it's best to make the output
-- fully usable outside of starfall environment
function SF.Unsanitize(...)
	local return_list = {}
	
	local args = {...}
	
	for key, value in pairs(args) do
		local typ = type(value)
		if typ == "table" and SF.UnwrapObject(value) then
			return_list[key] = SF.UnwrapObject(value)
		elseif typ == "table" then
			return_list[key] = {}

			for k,v in pairs(value) do
				return_list[key][SF.Unsanitize(k)] = SF.Unsanitize(v)
			end
		else
			return_list[key] = value
		end
	end

	return unpack(return_list)
end

-- ------------------------------------------------------------------------- --

local function isnan(n)
	return n ~= n
end

-- Taken from E2Lib

-- This function clamps the position before moving the entity
local minx, miny, minz = -16384, -16384, -16384
local maxx, maxy, maxz = 16384, 16384, 16384
local clamp = math.Clamp
local function clampPos(pos)
	pos.x = clamp(pos.x, minx, maxx)
	pos.y = clamp(pos.y, miny, maxy)
	pos.z = clamp(pos.z, minz, maxz)
	return pos
end

function SF.setPos(ent, pos)
	if isnan(pos.x) or isnan(pos.y) or isnan(pos.z) then return end
	return ent:SetPos(clampPos(pos))
end

local huge, abs = math.huge, math.abs
function SF.setAng(ent, ang)
	if isnan(ang.pitch) or isnan(ang.yaw) or isnan(ang.roll) then return end
	if abs(ang.pitch) == huge or abs(ang.yaw) == huge or abs(ang.roll) == huge then return false end -- SetAngles'ing inf crashes the server
	return ent:SetAngles(ang)
end

-- ------------------------------------------------------------------------- --

local serialize_replace_regex = "[\"\n]"
local serialize_replace_tbl = {["\n"] = "�", ['"'] = "�"}
--- Serializes an instance's code in a format compatible with the duplicator library
-- @param sources The table of filename = source entries. Ususally instance.source
-- @param mainfile The main filename. Usually instance.mainfile
function SF.SerializeCode(sources, mainfile)
	local rt = {source = {}}
	for filename, source in pairs(sources) do
		rt.source[filename] = string.gsub(source, serialize_replace_regex, serialize_replace_tbl)
	end
	rt.mainfile = mainfile
	return rt
end

local deserialize_replace_regex = "[��]"
local deserialize_replace_tbl = {["�"] = "\n", ['�'] = '"'}
--- Deserializes an instance's code.
-- @return The table of filename = source entries
-- @return The main filename
function SF.DeserializeCode(tbl)
	local sources = {}
	for filename, source in pairs(tbl.source) do
		sources[filename] = string.gsub(source, deserialize_replace_regex, deserialize_replace_tbl)
	end
	return sources, tbl.mainfile
end

-- ------------------------------------------------------------------------- --

file.CreateDir("sf_cache/")
SF_UPLOAD_ERROR = 0
SF_UPLOAD_INIT = 1
SF_UPLOAD_CRC = 2
SF_UPLOAD_DATA = 3
SF_UPLOAD_HEAD = 4
SF_UPLOAD_END = 5

if SERVER then
	util.AddNetworkString("starfall_requpload")
	util.AddNetworkString("starfall_upload")
	
	local uploaddata = {}
	
	function SF.ResetUploads()
		uploaddata = {}
	end

	local function make_path(ply, path)
		local path = util.CRC(path:gsub("starfall/", ""))
		local plyid = ply:SteamID():gsub(":","_")
		file.CreateDir("sf_cache/" .. plyid)
		return string.format("sf_cache/%s/%s.txt", plyid, path)
	end
	
	local function check_cached(ply, path, crc)
		local path = make_path(ply, path)
		if not file.Exists(path, "DATA") then
			return false
		end
		
		local fdata = file.Read(path, "DATA")
		if util.CRC(fdata) ~= crc then
			return false
		end
		return true, fdata
	end
	
	function SF.RequestCode(ply, callback)
		if uploaddata[ply] then return false end
		
		net.Start("starfall_requpload")
		net.WriteInt(SF_UPLOAD_INIT, 8)
		net.Send(ply)

		uploaddata[ply] = {
			files={},
			mainfile = nil,
			needHeader=true,
			callback = callback,
		}
		return true
	end
	
	net.Receive("starfall_upload", function(len, ply)
		local updata = uploaddata[ply]
		if not updata then
			ErrorNoHalt("SF: Player "..ply:GetName().." tried to upload code without being requested (expect this message multiple times)\n")
			return
		end
		
		local action = net.ReadInt(8)
		if action == SF_UPLOAD_ERROR then
			updata.callback(nil, nil)
			uploaddata[ply] = nil
		elseif action == SF_UPLOAD_CRC then
			local file_list = {}
			while net.ReadBit() > 0 do
				local fname = net.ReadString()
				local fcrc = net.ReadString()
				local chk, fdata = check_cached(ply, fname, fcrc)
				if not chk then
					file_list[#file_list + 1] = fname
					--print("Cache miss/expired for: "..fname)
				else
					updata.files[fname] = fdata
					--print("Got cache entry for: "..fname)
				end
			end
			net.Start("starfall_requpload")
			net.WriteInt(SF_UPLOAD_DATA, 8)
			for _, fname in ipairs(file_list) do
				net.WriteBit(true)
				net.WriteString(fname)
				--print("Request file: "..fname)
			end
			net.WriteBit(false)
			net.Send(ply)
		elseif action == SF_UPLOAD_HEAD then
			updata.mainfile = net.ReadString()
			--print("Main file: " .. updata.mainfile)
			updata.needHeader = nil
		elseif action == SF_UPLOAD_DATA then
			local filename = net.ReadString()
			local filedata = net.ReadString()
			local current_file = updata.files[filename]
			if not current_file then
				updata.files[filename] = {filedata}
			else
				current_file[#current_file + 1] = filedata
			end
		elseif action == SF_UPLOAD_END then
			for key, val in pairs(updata.files) do
				if type(val) == "table" then
					updata.files[key] = table.concat(val)
					if key ~= "generic" then
						local cache_path = make_path(ply, key)
						file.Write(cache_path, updata.files[key])
						--print("Write cache for: "..key.." as "..cache_path)
					end
				end
			end
			updata.callback(updata.mainfile, updata.files)
			uploaddata[ply] = nil
		end
	end)
else
	local inc_table = nil
	net.Receive("starfall_requpload", function()
		local action = net.ReadInt(8)
		if action == SF_UPLOAD_INIT then
			local ok, files = SF.Editor.BuildIncludesTable()
			if ok then
				inc_table = files
				net.Start("starfall_upload")
				net.WriteInt(SF_UPLOAD_CRC, 8)
				for key, val in pairs(inc_table.files) do
					net.WriteBit(true)
					net.WriteString(key)
					net.WriteString(util.CRC(val))
				end
				net.WriteBit(false)
				net.SendToServer()
			else
				net.Start("starfall_upload")
				net.WriteInt(SF_UPLOAD_ERROR, 8)
				net.SendToServer()
			end
		elseif action == SF_UPLOAD_DATA then
			local file_list = {}
			while net.ReadBit() > 0 do
				local fname = net.ReadString()
				file_list[#file_list + 1] = fname
				--print("Server requested for: "..fname)
			end
			net.Start("starfall_upload")
			net.WriteInt(SF_UPLOAD_HEAD, 8)
			net.WriteString(inc_table.mainfile)
			net.SendToServer()
			for _, fname in ipairs(file_list) do
				local fdata, offset = inc_table.files[fname], 1
				repeat
					net.Start("starfall_upload")
					net.WriteInt(SF_UPLOAD_DATA, 8)
					net.WriteString(fname)
					local data = fdata:sub(offset, offset+64000)
					net.WriteString(data)
					net.SendToServer()
					offset = offset + #data + 1
				until offset > #fdata
			end
			net.Start("starfall_upload")
			net.WriteInt(SF_UPLOAD_END, 8)
			net.SendToServer()
		end
	end)
end

-- ------------------------------------------------------------------------- --

if SERVER then
	local l
	MsgN("-SF - Loading Libraries")

	MsgN("- Loading shared libraries")
	l = file.Find("starfall/libs_sh/*.lua", "LUA")
	for _,filename in pairs(l) do
		print("-  Loading "..filename)
		include("starfall/libs_sh/"..filename)
		AddCSLuaFile("starfall/libs_sh/"..filename)
	end
	MsgN("- End loading shared libraries")
	
	MsgN("- Loading SF server-side libraries")
	l = file.Find("starfall/libs_sv/*.lua", "LUA")
	for _,filename in pairs(l) do
		print("-  Loading "..filename)
		include("starfall/libs_sv/"..filename)
	end
	MsgN("- End loading server-side libraries")

	
	MsgN("- Adding client-side libraries to send list")
	l = file.Find("starfall/libs_cl/*.lua", "LUA")
	for _,filename in pairs(l) do
		print("-  Adding "..filename)
		AddCSLuaFile("starfall/libs_cl/"..filename)
	end
	MsgN("- End loading client-side libraries")
	
	MsgN("-End Loading SF Libraries")
else
	local l
	MsgN("-SF - Loading Libraries")

	MsgN("- Loading shared libraries")
	l = file.Find("starfall/libs_sh/*.lua", "LUA")
	for _,filename in pairs(l) do
		print("-  Loading "..filename)
		include("starfall/libs_sh/"..filename)
	end
	MsgN("- End loading shared libraries")
	
	MsgN("- Loading client-side libraries")
	l = file.Find("starfall/libs_cl/*.lua", "LUA")
	for _,filename in pairs(l) do
		print("-  Loading "..filename)
		include("starfall/libs_cl/"..filename)
	end
	MsgN("- End loading client-side libraries")

	
	MsgN("-End Loading SF Libraries")
end

SF.Libraries.CallHook("postload")

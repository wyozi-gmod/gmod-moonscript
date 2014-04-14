
AddCSLuaFile('cl_init.lua')
AddCSLuaFile('shared.lua')
include('shared.lua')

include("starfall/SFLib.lua")
assert(SF, "Starfall didn't load correctly!")

ENT.WireDebugName = "Starfall Processor"
ENT.OverlayDelay = 0

local context = SF.CreateContext()

function ENT:UpdateState(state)
	if self.name then
		self:SetOverlayText("Starfall Processor\n"..self.name.."\n"..state)
	else
		self:SetOverlayText("Starfall Processor\n"..state)
	end
end

function ENT:Initialize()
	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	
	---[[
	self.Inputs = WireLib.CreateInputs(self, {})
	self.Outputs = WireLib.CreateOutputs(self, {})
	--]]
	
	self:UpdateState("Inactive (No code)")
	local clr = self:GetColor()
	self:SetColor(Color(255, 0, 0, clr.a))
end

function ENT:Compile(codetbl, mainfile)
	if self.instance then
		self:runScriptHook("last")
		self.instance:deinitialize() 
	end
	
	local ok, instance = SF.Compiler.Compile(codetbl,context,mainfile,self.owner)
	if not ok then self:Error(instance) return end
	
	instance.runOnError = function(inst,...) self:Error(...) end
	
	self.instance = instance
	instance.data.entity = self
	
	local ok, msg = instance:initialize()
	if not ok then
		self:Error(msg)
		return
	end
	
	if not self.instance then return end

	self.name = nil

	if self.instance.ppdata.scriptnames and self.instance.mainfile and self.instance.ppdata.scriptnames[self.instance.mainfile] then
		self.name = tostring(self.instance.ppdata.scriptnames[self.instance.mainfile])
	end

	if not self.name or string.len(self.name) <= 0 then
		self.name = "generic"
	end

	self:UpdateState("(None)")
	local clr = self:GetColor()
	self:SetColor(Color(255, 255, 255, clr.a))
end

function ENT:Error(msg, traceback)
	if type( msg ) == "table" then
		if msg.message then
			local line = msg.line
			local file = msg.file

			msg = ( file and ( file .. ":" ) or "" ) .. ( line and ( line .. ": " ) or "" ) .. msg.message
		end
	end
	ErrorNoHalt( "Processor of " .. self.owner:Nick() .. " errored: " .. tostring( msg ) .. "\n" )
	if traceback then
		print(traceback)
	end
	WireLib.ClientError(msg, self.owner)
	
	if self.instance then
		self.instance:deinitialize()
		self.instance = nil
	end
	
	self:UpdateState("Inactive (Error)")
	local clr = self:GetColor()
	self:SetColor(Color(255, 0, 0, clr.a))
end

function ENT:Think()
	self.BaseClass.Think(self)
	
	if self.instance and not self.instance.error then
		--self:UpdateState(tostring(self.instance.ops).." ops, "..tostring(math.floor(self.instance.ops / self.instance.context.ops * 100)).."%")
		self:UpdateState( tostring( self.instance.ops ) .. " ops, " .. tostring( math.floor( self.instance.ops / self.instance.context.ops() * 100 ) ) .. "%" )

		self.instance:resetOps()
		self:runScriptHook("think")
	end

	self:NextThink(CurTime())
	return true
end

function ENT:OnRemove()
	if not self.instance then return end
	self:runScriptHook("last")
	self.instance:deinitialize()
	self.instance = nil
end

---[[
function ENT:TriggerInput(key, value)
	local instance = SF.instance
	SF.instance = nil
	self:runScriptHook("input", key, SF.Wire.InputConverters[self.Inputs[key].Type](value))
	SF.instance = instance
end

function ENT:ReadCell(address)
	local instance = SF.instance
	SF.instance = nil
	local res =  tonumber(self:runScriptHookForResult("readcell",address)) or 0
	SF.instance = instance
	return res
end

function ENT:WriteCell(address, data)
	local instance = SF.instance
	SF.instance = nil
	self:runScriptHook("writecell",address,data)
	SF.instance = instance
end
--]]

function ENT:runScriptHook(hook, ...)
	if self.instance and not self.instance.error and self.instance.hooks[hook:lower()] then
		local ok, rt = self.instance:runScriptHook(hook, ...)
		if not ok then self:Error(rt) end
	end
end

function ENT:runScriptHookForResult(hook,...)
	if self.instance and not self.instance.error and self.instance.hooks[hook:lower()] then
		local ok, rt = self.instance:runScriptHookForResult(hook, ...)
		if not ok then self:Error(rt)
		else return rt end
	end
end

function ENT:OnRestore()
end
include('shared.lua')

ENT.RenderGroup = RENDERGROUP_OPAQUE

include("starfall/SFLib.lua")
assert(SF, "Starfall didn't load correctly!")
local libs = SF.Libraries.CreateLocalTbl{"render"}
local Context = SF.CreateContext(nil, nil, nil, libs)

surface.CreateFont("Starfall_ErrorFontBig", {
	font = "Arial",
	size = 40,
	weight = 400,
})

net.Receive("starfall_remote_link", function()
	local ply = net.ReadEntity()
	local ent = net.ReadEntity()
	local ply2 = SF.Entities.Wrap(ply)
	local status = (net.ReadBit() > 0)
	if status then
		local old = ply.SFRemote_Link
		if IsValid(old) then
			old:runScriptHook("link", ply2, false)
		end
		ply.SFRemote_Link = ent
		ent:runScriptHook("link", ply2, true)
	else
		ply.SFRemote_Link = nil
		ent:runScriptHook("link", ply2, false)
	end
end)

net.Receive("starfall_remote_input", function()
	local screen = net.ReadEntity()
	local mode = (net.ReadBit() > 0)
	if mode then
		local mkey = net.ReadUInt(8)
		screen:runScriptHook("click", mkey)
	end
end)

function ENT:SetContextBase()
	self.SFContext = Context
end

function ENT:SetRenderFunc(data)
	function self.renderfunc()
		if self.instance then
			data.render.isRendering = true
			self:runScriptHook("render")
			data.render.isRendering = nil
			
		elseif self.error then
			surface.SetTexture(0)
			surface.SetDrawColor(0, 0, 0, 140)
			surface.DrawRect(0, 0, ScrW(), ScrH())
			
			draw.DrawText("Error occurred in Starfall Remote:", "Starfall_ErrorFontBig", 32, 16, Color(0, 255, 255, 255))
			draw.DrawText(tostring(self.error.msg), "Starfall_ErrorFontBig", 16, 80, Color(255, 0, 0, 255))
			if self.error.source and self.error.line then
				draw.DrawText("Line: "..tostring(self.error.line), "Starfall_ErrorFontBig", 16, ScrH()-16*7, Color(255, 255, 255, 255))
				draw.DrawText("Source: "..self.error.source, "Starfall_ErrorFontBig", 16, ScrH()-16*5, Color(255, 255, 255, 255))
			end
			self.renderfunc = nil
		end
	end
end

function ENT:Initialize()
	self:SetContextBase()
	self.files = {}
	net.Start("starfall_screen_download")
	net.WriteInt(SF_UPLOAD_INIT, 8)
	net.WriteEntity(self)
	net.SendToServer()
end

function ENT:OnRemove()
	local vtab = self:GetTable()
	timer.Simple(0.1, function()
		if IsValid(self) then return end
		if not vtab.instance then return end
		if not vtab.instance.error then
			vtab:runScriptHook("last")
		end
		vtab.instance:deinitialize()
	end)
end

function ENT:Think()
	self:NextThink(CurTime())
	self.WasFrameDrawn = false
	
	if self.instance and not self.instance.error then
		self.instance:resetOps()
		self:runScriptHook("think")
	end
end

function ENT:SetViewPort(x, y, w, h)
	local inst = self.instance
	if not inst then return end
	local vp = inst.data.render.viewport
	vp.x, vp.y, vp.w, vp.h = x, y, w, h
end

function ENT:DrawScreen()
	if not self.WasFrameDrawn and self.renderfunc then
		local ok, err = xpcall(self.renderfunc, debug.traceback)
		if not ok then WireLib.ErrorNoHalt(err) end
		self.WasFrameDrawn = true
	end
end

function ENT:Draw()
	--self.BaseClass.BaseClass.Draw(self)
	self:DrawModel()
	Wire_Render(self)
end
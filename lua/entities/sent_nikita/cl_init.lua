-- cl_init.lua  (CLIENT)  –  NIKITA missile
-- Renders the 6x scaled model + rockettrail + orange dynamic light.
-- Also draws a red targeting line from the missile to its target.

include("shared.lua")

function ENT:Initialize()
    -- Render bounds scaled up to match the 6x model
    self:SetRenderBounds(
        Vector(-60, -60, -60),
        Vector( 60,  60,  60)
    )

    -- Rockettrail particle (same as vanilla RPG)
    self._thrusterPart = CreateParticleSystem(self, "rockettrail", PATTACH_POINT_FOLLOW, 0)
    if IsValid(self._thrusterPart) then
        self._thrusterPart:SetOwner(self)
    end

    -- Dynamic light – slightly larger/brighter than orbital RPG to match scale
    self._dynLight = DynamicLight(self:EntIndex())
    if self._dynLight then
        self._dynLight.style      = 0
        self._dynLight.r          = 255
        self._dynLight.g          = 100
        self._dynLight.b          = 10
        self._dynLight.brightness = 3
        self._dynLight.size       = 160    -- larger glow for bigger missile
        self._dynLight.decay      = 0
        self._dynLight.dietime    = CurTime() + 9999
    end
end

function ENT:Draw()
    self:DrawModel()

    -- Keep dynamic light alive
    if self._dynLight then
        self._dynLight.pos     = self:GetPos()
        self._dynLight.dietime = CurTime() + 0.05
    end

    -- Draw a faint red line toward the current target for visual feedback
    local idx = self:GetTargetEntIndex()
    if idx ~= 0 then
        local target = ents.GetByIndex(idx)
        if IsValid(target) then
            render.DrawLine(
                self:GetPos(),
                target:WorldSpaceCenter(),
                Color(255, 40, 40, 80),
                true
            )
        end
    end
end

function ENT:OnRemove()
    if IsValid(self._thrusterPart) then
        self._thrusterPart:StopEmission()
    end
end

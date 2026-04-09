-- cl_init.lua  (CLIENT)  --  NIKITA missile
-- Renders the 10x scaled model + rockettrail + orange dynamic light.
-- Faint red targeting line toward current target.

include("shared.lua")

function ENT:Initialize()
    self:SetRenderBounds(
        Vector(-120, -120, -120),
        Vector( 120,  120,  120)
    )

    -- Vanilla rockettrail
    self._thrusterPart = CreateParticleSystem(self, "rockettrail", PATTACH_POINT_FOLLOW, 0)
    if IsValid(self._thrusterPart) then
        self._thrusterPart:SetOwner(self)
    end

    -- Dynamic light -- bigger to match 10x scale
    self._dynLight = DynamicLight(self:EntIndex())
    if self._dynLight then
        self._dynLight.style      = 0
        self._dynLight.r          = 255
        self._dynLight.g          = 100
        self._dynLight.b          = 10
        self._dynLight.brightness = 4
        self._dynLight.size       = 280
        self._dynLight.decay      = 0
        self._dynLight.dietime    = CurTime() + 9999
    end
end

function ENT:Draw()
    self:DrawModel()

    if self._dynLight then
        self._dynLight.pos     = self:GetPos()
        self._dynLight.dietime = CurTime() + 0.05
    end

    -- Red targeting line
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

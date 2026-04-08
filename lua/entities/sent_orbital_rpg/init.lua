-- init.lua  (SERVER)
-- Handles physics, movement, damage, and vanilla RPG effects.

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

-- =========================================================================
-- Configuration
-- =========================================================================
local SPEED          = 400    -- units/s  (vanilla RPG ~1200 – intentionally slower)
local ORBIT_RADIUS_A = 48     -- ellipse semi-major axis  (side-to-side)
local ORBIT_RADIUS_B = 28     -- ellipse semi-minor axis  (up-down)
local ORBIT_SPEED    = 4.5    -- radians/s  (how fast it circles)
local LIFETIME       = 12     -- seconds before self-removal
local DAMAGE         = 100
local BLAST_RADIUS   = 200

-- =========================================================================
-- Spawn  (called by the firing weapon / admin command)
-- =========================================================================
function ENT:Initialize()
    self:SetModel("models/weapons/w_missile.mdl")
    self:SetMoveType(MOVETYPE_NOCLIP)  -- we drive position manually
    self:SetSolid(SOLID_BBOX)
    self:SetCollisionBounds(Vector(-8, -8, -8), Vector(8, 8, 8))
    self:SetCollisionGroup(COLLISION_GROUP_PROJECTILE)
    self:DrawShadow(false)

    -- Store birth state into networked vars so the client can mirror the math
    local now = CurTime()
    self:SetBirthTime(now)
    self:SetSpawnPos(self:GetPos())
    self:SetSpawnDir(self:GetForward())

    -- Cached for Think performance
    self._birthTime  = now
    self._origin     = self:GetPos()
    self._forward    = self:GetForward()
    -- Build a stable right / up orthonormal basis from the launch direction
    local fwd        = self._forward
    local right      = fwd:Cross(Vector(0, 0, 1))
    if right:LengthSqr() < 0.001 then
        right = fwd:Cross(Vector(0, 1, 0))
    end
    right:Normalize()
    local up         = right:Cross(fwd)
    up:Normalize()
    self._right  = right
    self._up     = up

    -- Safety timer
    timer.Simple(LIFETIME, function()
        if IsValid(self) then self:Remove() end
    end)
end

-- =========================================================================
-- Think  – runs every tick
-- =========================================================================
function ENT:Think()
    local t      = CurTime() - self._birthTime
    local phase  = t * ORBIT_SPEED

    -- Centre-line position (straight ahead at SPEED)
    local centre = self._origin + self._forward * (SPEED * t)

    -- Elliptical offset around the centre-line
    local offset = self._right * (ORBIT_RADIUS_A * math.cos(phase))
                 + self._up    * (ORBIT_RADIUS_B * math.sin(phase))

    local newPos = centre + offset

    -- Aim the missile along its instantaneous velocity direction
    -- (derivative of position w.r.t. time)
    local vel = self._forward * SPEED
              + self._right   * (-ORBIT_RADIUS_A * ORBIT_SPEED * math.sin(phase))
              + self._up      * ( ORBIT_RADIUS_B * ORBIT_SPEED * math.cos(phase))
    local velDir = vel:GetNormalized()

    -- Collision trace before we commit to the new position
    local tr = util.TraceLine({
        start  = self:GetPos(),
        endpos = newPos,
        filter = { self, self:GetOwner() },
        mask   = MASK_SHOT,
    })

    if tr.Hit then
        self:Explode(tr.HitPos, tr.HitNormal, tr.Entity)
        return
    end

    self:SetPos(newPos)
    self:SetAngles(velDir:Angle())
    self:NextThink(CurTime())  -- think every tick
    return true
end

-- =========================================================================
-- Touch  (catches brush geometry misses from the trace)
-- =========================================================================
function ENT:Touch(other)
    if IsValid(other) and other ~= self:GetOwner() then
        self:Explode(self:GetPos(), Vector(0, 0, 1), other)
    end
end

-- =========================================================================
-- Explode
-- =========================================================================
function ENT:Explode(pos, normal, hitEnt)
    -- Vanilla RPG explosion effect
    local effectData = EffectData()
    effectData:SetOrigin(pos)
    effectData:SetNormal(normal)
    effectData:SetScale(1)
    util.Effect("Explosion", effectData, true, true)

    -- Damage
    local dmgInfo = DamageInfo()
    dmgInfo:SetDamage(DAMAGE)
    dmgInfo:SetDamageType(DMG_BLAST)
    dmgInfo:SetAttacker(IsValid(self:GetOwner()) and self:GetOwner() or game.GetWorld())
    dmgInfo:SetInflictor(self)
    dmgInfo:SetReportedPosition(pos)

    util.BlastDamage(self, IsValid(self:GetOwner()) and self:GetOwner() or self, pos, BLAST_RADIUS, DAMAGE)

    -- Decal
    util.Decal("Scorch", pos + normal, pos - normal)

    self:Remove()
end

-- =========================================================================
-- Convenience launcher  (call from a SWEP or console command)
-- =========================================================================
function SWEP_FireOrbitalRPG(owner, eyePos, eyeAng)
    local missile = ents.Create("sent_orbital_rpg")
    if not IsValid(missile) then return end
    missile:SetPos(eyePos)
    missile:SetAngles(eyeAng)
    missile:SetOwner(owner)
    missile:Spawn()
    missile:Activate()
    return missile
end

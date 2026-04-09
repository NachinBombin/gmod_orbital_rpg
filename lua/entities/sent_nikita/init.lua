-- init.lua  (SERVER)  --  NIKITA missile
-- Slow homing missile. Destructible (10 HP). 10x scaled model + hitbox.
--
-- TARGET POLICY:
--   The missile does ZERO auto-targeting. The target entity must be
--   assigned by the launcher via SWEP_FireNikita(owner, pos, ang, target).
--   If no target is provided the missile flies straight and dumb.
--   This entity is designed to be fired by NPCs; the NPC's AI picks the target.

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- =========================================================================
-- Configuration
-- =========================================================================
local SPEED          = 200
local TURN_SPEED     = 120       -- degrees/s max steering
local SCALE          = 10
local HP             = 10
local LIFETIME       = 30
local DAMAGE         = 120
local BLAST_RADIUS   = 220
local HITBOX         = 8 * SCALE
local THINK_INTERVAL = 0.015     -- ~66 Hz fixed interval, never 0

-- =========================================================================
-- Safe normalise helper
-- =========================================================================
local function SafeNorm(v, fallback)
    if v:LengthSqr() < 0.0001 then return fallback end
    return v:GetNormalized()
end

-- =========================================================================
-- Initialize
-- =========================================================================
function ENT:Initialize()
    self:SetModel("models/weapons/w_missile.mdl")
    self:SetModelScale(SCALE, 0)
    self:SetMoveType(MOVETYPE_NOCLIP)
    self:SetSolid(SOLID_BBOX)
    self:SetCollisionBounds(
        Vector(-HITBOX, -HITBOX, -HITBOX),
        Vector( HITBOX,  HITBOX,  HITBOX)
    )
    self:SetCollisionGroup(COLLISION_GROUP_PROJECTILE)
    self:DrawShadow(false)

    self:SetMaxHealth(HP)
    self:SetHealth(HP)
    self:SetTakeDamageType(DAMAGE_YES)

    -- Travel direction starts as launch forward.
    -- Updated each tick as the missile steers.
    self._currentDir = SafeNorm(self:GetForward(), Vector(1, 0, 0))

    -- _target is intentionally NIL here.
    -- It is set externally by SWEP_FireNikita AFTER Spawn()+Activate().
    self._target = nil

    self._lastThink = CurTime()
    self:NextThink(CurTime() + THINK_INTERVAL)

    timer.Simple(LIFETIME, function()
        if IsValid(self) then self:Remove() end
    end)
end

-- =========================================================================
-- SetTarget  --  called by the launcher after Activate()
-- =========================================================================
function ENT:SetTarget(ent)
    if IsValid(ent) then
        self._target = ent
        self:SetTargetEntIndex(ent:EntIndex())
    end
end

-- =========================================================================
-- Think
-- =========================================================================
function ENT:Think()
    local now = CurTime()
    local dt  = now - (self._lastThink or now)
    if dt <= 0 then
        self:NextThink(now + THINK_INTERVAL)
        return true
    end
    self._lastThink = now

    -- Re-validate cached target handle
    if not IsValid(self._target) then
        local idx = self:GetTargetEntIndex()
        if idx ~= 0 then
            local ent = ents.GetByIndex(idx)
            -- Only accept the entity if it is NOT the missile's own owner
            if IsValid(ent) and ent ~= self:GetOwner() then
                self._target = ent
            else
                -- Bad index stored somehow -- clear it
                self:SetTargetEntIndex(0)
            end
        end
    end

    -- Steer toward target if valid; otherwise fly straight
    local desiredDir = self._currentDir
    if IsValid(self._target) then
        local toTarget = self._target:WorldSpaceCenter() - self:GetPos()
        desiredDir = SafeNorm(toTarget, self._currentDir)
    end

    -- Angle-clamp: rotate at most TURN_SPEED * dt degrees per tick
    local dot       = math.Clamp(self._currentDir:Dot(desiredDir), -1, 1)
    local angleDiff = math.deg(math.acos(dot))
    local maxAngle  = TURN_SPEED * dt

    local newDir
    if angleDiff < 0.01 or angleDiff <= maxAngle then
        newDir = desiredDir
    else
        newDir = LerpVector(maxAngle / angleDiff, self._currentDir, desiredDir)
    end
    self._currentDir = SafeNorm(newDir, self._currentDir)

    local newPos = self:GetPos() + self._currentDir * (SPEED * dt)

    -- Geometry collision
    local tr = util.TraceLine({
        start  = self:GetPos(),
        endpos = newPos,
        filter = { self, self:GetOwner() },
        mask   = MASK_SHOT,
    })
    if tr.Hit then
        self:Explode(tr.HitPos, tr.HitNormal)
        return
    end

    -- Proximity detonation
    if IsValid(self._target) then
        if self:GetPos():Distance(self._target:WorldSpaceCenter()) < HITBOX + 20 then
            self:Explode(self:GetPos(), Vector(0, 0, 1))
            return
        end
    end

    self:SetPos(newPos)
    self:SetAngles(self._currentDir:Angle())
    self:NextThink(now + THINK_INTERVAL)
    return true
end

-- =========================================================================
-- OnTakeDamage  --  interceptable
-- =========================================================================
function ENT:OnTakeDamage(dmgInfo)
    self:SetHealth(self:Health() - dmgInfo:GetDamage())
    if self:Health() <= 0 then
        self:SetIntercepted(true)
        self:Explode(self:GetPos(), Vector(0, 0, 1))
    end
end

-- =========================================================================
-- Touch
-- =========================================================================
function ENT:Touch(other)
    if IsValid(other) and other ~= self:GetOwner() then
        self:Explode(self:GetPos(), Vector(0, 0, 1))
    end
end

-- =========================================================================
-- Explode
-- =========================================================================
function ENT:Explode(pos, normal)
    if self._exploded then return end
    self._exploded = true

    local n = normal or Vector(0, 0, 1)
    local effectData = EffectData()
    effectData:SetOrigin(pos)
    effectData:SetNormal(n)
    effectData:SetScale(1)
    util.Effect("Explosion", effectData, true, true)

    util.BlastDamage(
        self,
        IsValid(self:GetOwner()) and self:GetOwner() or self,
        pos, BLAST_RADIUS, DAMAGE
    )

    util.Decal("Scorch", pos + n, pos - n)
    self:Remove()
end

-- =========================================================================
-- Launcher helper
--
-- Usage (from NPC AI or SWEP):
--   SWEP_FireNikita(npc, npc:GetShootPos(), npc:GetShootPos():Angle(), target)
--
-- 'target' is the entity the missile should chase.
-- Pass nil / no argument for a dumb straight-flying missile.
-- =========================================================================
function SWEP_FireNikita(owner, eyePos, eyeAng, target)
    local missile = ents.Create("sent_nikita")
    if not IsValid(missile) then return end
    missile:SetPos(eyePos)
    missile:SetAngles(eyeAng)
    missile:SetOwner(owner)
    missile:Spawn()
    missile:Activate()
    -- Assign target AFTER activation so networked vars are ready
    if IsValid(target) then
        missile:SetTarget(target)
    end
    return missile
end

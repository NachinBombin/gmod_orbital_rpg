-- init.lua  (SERVER)  –  NIKITA missile
-- Slow, homing, destructible. 6x scaled model + hitbox.
-- Locks onto the closest enemy player/NPC at launch and chases them.

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- =========================================================================
-- Configuration
-- =========================================================================
local SPEED          = 200     -- units/s  (crawl)
local TURN_RATE      = 1.8     -- lerp factor for homing (higher = snappier)
local SCALE          = 6       -- visual + collision scale multiplier
local HP             = 10      -- missile health before it detonates early
local LIFETIME       = 30      -- seconds before self-removal
local DAMAGE         = 120
local BLAST_RADIUS   = 220
local HITBOX         = 8 * SCALE  -- base bbox half-extent * scale
local ACQUIRE_RADIUS = 4000    -- units: how far to search for a target at launch

-- =========================================================================
-- Helpers
-- =========================================================================
local function FindClosestTarget(origin, owner)
    local best, bestDist = nil, math.huge

    -- Check players
    for _, ply in ipairs(player.GetAll()) do
        if ply == owner then continue end
        if not ply:Alive() then continue end
        local d = origin:DistToSqr(ply:GetPos())
        if d < bestDist and d < ACQUIRE_RADIUS * ACQUIRE_RADIUS then
            best, bestDist = ply, d
        end
    end

    -- Check NPCs
    for _, npc in ipairs(ents.FindInSphere(origin, ACQUIRE_RADIUS)) do
        if not IsValid(npc) then continue end
        if not npc:IsNPC() then continue end
        local d = origin:DistToSqr(npc:GetPos())
        if d < bestDist then
            best, bestDist = npc, d
        end
    end

    return best
end

-- =========================================================================
-- Initialize
-- =========================================================================
function ENT:Initialize()
    self:SetModel("models/weapons/w_missile.mdl")
    self:SetModelScale(SCALE, 0)       -- 6x the visual model
    self:SetMoveType(MOVETYPE_NOCLIP)  -- manual movement
    self:SetSolid(SOLID_BBOX)
    self:SetCollisionBounds(
        Vector(-HITBOX, -HITBOX, -HITBOX),
        Vector( HITBOX,  HITBOX,  HITBOX)
    )
    self:SetCollisionGroup(COLLISION_GROUP_PROJECTILE)
    self:DrawShadow(false)

    -- Health
    self:SetMaxHealth(HP)
    self:SetHealth(HP)
    self:SetTakeDamageType(DAMAGE_YES)

    -- Acquire target at spawn
    local target = FindClosestTarget(self:GetPos(), self:GetOwner())
    if IsValid(target) then
        self:SetTargetEntIndex(target:EntIndex())
        self._target = target
    else
        self._target = nil
        self:SetTargetEntIndex(0)
    end

    -- Cached heading (used when no target)
    self._forward = self:GetForward()
    self._fixedAngle = self:GetAngles()

    -- Safety timer
    timer.Simple(LIFETIME, function()
        if IsValid(self) then self:Remove() end
    end)
end

-- =========================================================================
-- Think  –  homing movement
-- =========================================================================
function ENT:Think()
    local dt = FrameTime()

    -- Refresh target reference if needed
    if not IsValid(self._target) then
        local idx = self:GetTargetEntIndex()
        if idx ~= 0 then
            self._target = ents.GetByIndex(idx)
        end
    end

    -- Determine desired direction
    local desiredDir
    if IsValid(self._target) then
        local targetPos = self._target:WorldSpaceCenter()
        desiredDir = (targetPos - self:GetPos()):GetNormalized()
    else
        desiredDir = self._forward
    end

    -- Smoothly steer toward target
    local currentDir = self:GetForward()
    local newDir     = LerpVector(math.Clamp(TURN_RATE * dt, 0, 1), currentDir, desiredDir)
    newDir:Normalize()

    local newPos = self:GetPos() + newDir * (SPEED * dt)

    -- Collision trace
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

    -- Check if we've reached the target (close enough)
    if IsValid(self._target) then
        local dist = self:GetPos():Distance(self._target:WorldSpaceCenter())
        if dist < HITBOX + 16 then
            self:Explode(self:GetPos(), Vector(0, 0, 1))
            return
        end
    end

    self:SetPos(newPos)
    -- Face the direction of travel
    self:SetAngles(newDir:Angle())
    self:NextThink(CurTime())
    return true
end

-- =========================================================================
-- OnTakeDamage  –  10 HP, dies early if shot
-- =========================================================================
function ENT:OnTakeDamage(dmgInfo)
    self:SetHealth(self:Health() - dmgInfo:GetDamage())
    if self:Health() <= 0 then
        -- Intercepted! Explode at current position
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
    local effectData = EffectData()
    effectData:SetOrigin(pos)
    effectData:SetNormal(normal)
    effectData:SetScale(1)
    util.Effect("Explosion", effectData, true, true)

    util.BlastDamage(
        self,
        IsValid(self:GetOwner()) and self:GetOwner() or self,
        pos, BLAST_RADIUS, DAMAGE
    )

    util.Decal("Scorch", pos + normal, pos - normal)

    self:Remove()
end

-- =========================================================================
-- Launcher helper
-- =========================================================================
function SWEP_FireNikita(owner, eyePos, eyeAng)
    local missile = ents.Create("sent_nikita")
    if not IsValid(missile) then return end
    missile:SetPos(eyePos)
    missile:SetAngles(eyeAng)
    missile:SetOwner(owner)
    missile:Spawn()
    missile:Activate()
    return missile
end

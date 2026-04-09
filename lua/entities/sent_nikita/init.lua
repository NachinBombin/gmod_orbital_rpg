-- init.lua  (SERVER)  --  NIKITA missile
-- Slow homing missile. Destructible (10 HP). 10x scaled model + hitbox.
-- Movement is driven by CurTime() delta, NOT FrameTime(), to avoid
-- zero-dt crashes on server ticks.

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- =========================================================================
-- Configuration
-- =========================================================================
local SPEED          = 200      -- units/s  (crawl)
local TURN_SPEED     = 120      -- degrees/s  max steering angle change
local SCALE          = 10       -- visual + collision scale
local HP             = 10       -- missile health before early detonation
local LIFETIME       = 30       -- seconds before self-removal
local DAMAGE         = 120
local BLAST_RADIUS   = 220
local HITBOX         = 8 * SCALE
local ACQUIRE_RADIUS = 4000
local THINK_INTERVAL = 0.015    -- ~66 Hz  (never 0)

-- =========================================================================
-- Helpers
-- =========================================================================
local function FindClosestTarget(origin, owner)
    local best, bestDist = nil, math.huge
    for _, ply in ipairs(player.GetAll()) do
        if ply == owner then continue end
        if not ply:Alive() then continue end
        local d = origin:DistToSqr(ply:GetPos())
        if d < bestDist and d < ACQUIRE_RADIUS * ACQUIRE_RADIUS then
            best, bestDist = ply, d
        end
    end
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

-- Safely normalise a vector; returns fallback if near-zero
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
    -- SetTakeDamageType is provided by base_entity (now our base in shared.lua)
    if self.SetTakeDamageType then
        self:SetTakeDamageType(DAMAGE_YES)
    end

    -- Store the launch forward as the initial travel direction
    self._currentDir = self:GetForward():GetNormalized()

    -- Acquire target
    local target = FindClosestTarget(self:GetPos(), self:GetOwner())
    if IsValid(target) then
        self:SetTargetEntIndex(target:EntIndex())
        self._target = target
    else
        self._target = nil
        self:SetTargetEntIndex(0)
    end

    -- Timestamp for delta calculation
    self._lastThink = CurTime()

    self:NextThink(CurTime() + THINK_INTERVAL)

    timer.Simple(LIFETIME, function()
        if IsValid(self) then self:Remove() end
    end)
end

-- =========================================================================
-- Think  --  CurTime-based delta, no FrameTime()
-- =========================================================================
function ENT:Think()
    -- Guard: _lastThink must exist (set in Initialize)
    if not self._lastThink then
        self._lastThink = CurTime()
        self:NextThink(CurTime() + THINK_INTERVAL)
        return true
    end

    local now = CurTime()
    local dt  = now - self._lastThink

    if dt <= 0 then
        self:NextThink(now + THINK_INTERVAL)
        return true
    end
    self._lastThink = now

    -- Refresh target handle from index if lost
    if not IsValid(self._target) then
        local idx = self:GetTargetEntIndex()
        if idx ~= 0 then
            self._target = ents.GetByIndex(idx)
        end
    end

    -- Desired direction toward target (or keep current)
    local desiredDir = self._currentDir
    if IsValid(self._target) then
        local toTarget = self._target:WorldSpaceCenter() - self:GetPos()
        desiredDir = SafeNorm(toTarget, self._currentDir)
    end

    -- Angle-clamp steering
    local maxAngle  = TURN_SPEED * dt
    local angleDiff = math.deg(math.acos(math.Clamp(self._currentDir:Dot(desiredDir), -1, 1)))

    local newDir
    if angleDiff <= maxAngle or angleDiff < 0.01 then
        newDir = desiredDir
    else
        local t  = maxAngle / angleDiff
        newDir   = LerpVector(t, self._currentDir, desiredDir)
    end
    newDir = SafeNorm(newDir, self._currentDir)
    self._currentDir = newDir

    local newPos = self:GetPos() + newDir * (SPEED * dt)

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

    if IsValid(self._target) then
        if self:GetPos():Distance(self._target:WorldSpaceCenter()) < HITBOX + 20 then
            self:Explode(self:GetPos(), Vector(0, 0, 1))
            return
        end
    end

    self:SetPos(newPos)
    self:SetAngles(newDir:Angle())
    self:NextThink(now + THINK_INTERVAL)
    return true
end

-- =========================================================================
-- OnTakeDamage
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

    local effectData = EffectData()
    effectData:SetOrigin(pos)
    effectData:SetNormal(normal or Vector(0, 0, 1))
    effectData:SetScale(1)
    util.Effect("Explosion", effectData, true, true)

    util.BlastDamage(
        self,
        IsValid(self:GetOwner()) and self:GetOwner() or self,
        pos, BLAST_RADIUS, DAMAGE
    )

    util.Decal("Scorch", pos + (normal or Vector(0, 0, 1)), pos - (normal or Vector(0, 0, 1)))

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

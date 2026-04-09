-- shared.lua  --  NIKITA missile
-- Slow homing missile. Destructible (10 HP). 10x scale.

ENT.Type           = "anim"
ENT.Base           = "base_entity"  -- base_entity provides SetOwner, GetOwner, SetTakeDamageType
ENT.PrintName      = "NIKITA"
ENT.Author         = "NachinBombin"
ENT.Spawnable      = false
ENT.AdminSpawnable = false

function ENT:SetupDataTables()
    -- The entity index of the current target (0 = none)
    self:NetworkVar("Int",   0, "TargetEntIndex")
    -- Whether the missile has been destroyed (intercepted)
    self:NetworkVar("Bool",  0, "Intercepted")
end

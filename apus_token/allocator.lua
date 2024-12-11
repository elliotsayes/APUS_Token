local Allocator = { _version = "0.0.1" }

local Utils = require(".utils")
local bint = require(".bint")(256)
local BintUtils = require("utils.bint_utils")

--[[
    Function: compute
    Calculates and distributes rewards to users based on their deposits and the total reward pool.

    Parameters:
        deposits (table): A list of user deposit records, each containing a User, Mint, and optionally Reward.
        reward (string): The total reward pool to be distributed, in the smallest denomination.

    Returns:
        table: The updated list of deposit records with assigned rewards.
]]
function Allocator:compute(deposits, reward)
    -- Calculate the total minted amount from all deposits
    local totalMint = Utils.reduce(function(acc, r)
        return BintUtils.add(acc, r.Mint)
    end, "0", deposits)

    -- Initialize the remaining reward pool
    local left = reward

    -- Assign rewards to each deposit based on their proportion of the total mint
    Utils.map(function(r)
        -- Calculate the reward for the current deposit
        r.Reward = BintUtils.toBalanceValue(bint(reward) * bint(r.Mint) // bint(totalMint))
        -- Subtract the assigned reward from the remaining pool
        left = BintUtils.subtract(left, r.Reward)
        return r
    end, deposits)

    if left == reward then
        -- TODO No ao minted
        return
    end

    if bint(left) > 0 then
        deposits[1].Reward = BintUtils.add(deposits[1].Reward, left)
    end

    return deposits
end

return Allocator

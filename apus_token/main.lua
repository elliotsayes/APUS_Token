-- Initialization Script for Minting and Handlers

-- Import necessary modules
local sqlite3 = require('lsqlite3')
local json = require('json')
local Utils = require('.utils')
local BintUtils = require('utils.bint_utils')
local EthAddressUtils = require('utils.eth_address')

-- Initialize in-memory SQLite database or reuse existing one
MintDb = MintDb or sqlite3.open_memory()

-- Initialize Database Admin with MintDb
DbAdmin = DbAdmin or require('utils.db_admin').new(MintDb)

-- Initialize Data Access Layer for Deposits
Deposits = require('dal.deposits').new(DbAdmin)

-- Import core modules
Mint = require("mint")
Token = require('token')
Allocator = require('allocator')
Distributor = require('distributor')

AO_MINT_PROCESS = "LPK-D_3gZkXtia6ywwU1wRwgFOZ-eLFRMP9pfAFRfuw"
APUS_STATS_PROCESS = "zmr4sqL_fQjjvHoUJDkT8eqCiLFEM3RV5M96Wd59ffU"

-- Function to verify if a message is a mint report from AO Mint Process
local function isMintReportFromAOMint(msg)
  return msg.Action == "Report.Mint" and msg.From == AO_MINT_PROCESS
end

-- Handler for AO Mint Report
Handlers.add("AO-Mint-Report", isMintReportFromAOMint, function(msg)
  -- Filter reports where the recipient matches the current process ID
  local reports = Utils.filter(function(r)
    return r.Recipient == ao.id
  end, msg.Data)
  -- Update message data with filtered reports and forward to APUS_STATS_PROCESS
  msg.Data = reports
  msg.forward(APUS_STATS_PROCESS)
  -- Batch update the Mint records
  Mint.batchUpdate(reports)
end)

-- Handler for testing AO Mint Reports
Handlers.add("AO-Mint-Report-test", "Report.Mint", function(msg)
  -- Decode JSON data from the message
  local reports = json.decode(msg.Data)

  -- Filter reports for the current process ID
  local reportList = Utils.filter(function(r)
    return r.Recipient == ao.id
  end, reports)
  -- print(reportList)
  -- Batch update the Mint records with the filtered list
  Mint.batchUpdate(reportList)
end)

-- Cron job handler to trigger minting process (MODE = "ON")
Handlers.add("Cron", "Cron", Mint.mint)

-- Handler for Mint Backup process (MODE = "OFF")
Handlers.add("Mint.Backup", "Mint.Backup", Mint.mintBackUp)

-- Handler to update user's recipient wallet
Handlers.add("User.Update-Recipient", "User.Update-Recipient", function(msg)
  local user = msg.From
  local recipient = msg.Recipient
  -- Bind the user's wallet to the recipient address
  Distributor.bindingWallet(user, recipient)
  -- Reply to the user confirming the binding
  msg.reply({ Data = "Successfully binded" })
end)

-- Handler to retrieve user's recipient wallet
Handlers.add("User.Get-Recipient", "User.Get-Recipient", function(msg)
  local user = msg.User or msg.From
  msg.reply({ Data = Distributor.getWallet(user) })
end)

-- Handler to get user's balance
Handlers.add("User.Balance", "User.Balance", function(msg)
  local user = msg.Recipient
  assert(user ~= nil, "Recipient required")
  -- Convert user address to checksum format
  user = EthAddressUtils.toChecksumAddress(user)
  -- Retrieve deposit record for the user
  local record = Deposits:getByUser(user) or {}
  local recipient = record.Recipient
  local res = Balances[user] or "0"
  if not recipient then
    -- If no recipient, reply with the user's balance
    msg.reply({ Data = res })
    return
  else
    -- If recipient exists, add balances and reply
    msg.reply({ Data = BintUtils.add(res, Balances[recipient] or "0") })
  end
end)

-- No token transfers...
-- Handlers.add('token.transfer', Handlers.utils.hasMatchingTag("Action", "Transfer"), token.transfer)
-- Handlers for various token actions
Handlers.add("token.info", Handlers.utils.hasMatchingTag("Action", "Info"), Token.info)
Handlers.add("token.balance", Handlers.utils.hasMatchingTag("Action", "Balance"), Token.balance)
Handlers.add("token.balances", Handlers.utils.hasMatchingTag("Action", "Balances"), Token.balances)
Handlers.add("token.totalSupply", Handlers.utils.hasMatchingTag("Action", "Total-Supply"), Token.totalSupply)
Handlers.add("token.burn", Handlers.utils.hasMatchingTag("Action", "Burn"), Token.burn)
Handlers.add("token.mintedSupply", Handlers.utils.hasMatchingTag("Action", "Minted-Supply"), Token.mintedSupply)

-- Initialization flag to prevent re-initialization
Initialized = Initialized or false
-- Immediately Invoked Function Expression (IIFE) for initialization logic
(function()
  if Initialized == false then
    Initialized = true
  else
    print("Already Initialized. Skip Initialization.")
    return
  end
  print("Initializing ...")
  -- Subscribe Mint Report From AO Mint Process
  Send({ Target = AO_MINT_PROCESS, Action = "Recipient.Subscribe-Report", ["Report-To"] = ao.id })
end)()

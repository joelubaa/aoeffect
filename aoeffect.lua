-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil
Game = Game or nil
InAction = InAction or false

Logs = Logs or {}

colors = {
  red = "\27[31m",
  green = "\27[32m",
  blue = "\27[34m",
  reset = "\27[0m",
  gray = "\27[90m"
}

function addLog(msg, text) -- Function definition commented for performance, can be used for debugging
  Logs[msg] = Logs[msg] or {}
  table.insert(Logs[msg], text)
end

-- Function to find the closest target for the bot
function findClosestTarget(botState)
    local closestTarget = nil
    local minDistance = math.huge  -- Start with the largest possible distance

    for targetID, targetState in pairs(LatestGameState.Players) do
        if targetID ~= botState.id then  -- Make sure the bot doesn't target itself
            local distance = manhattanDistance(botState, targetState)
            if distance < minDistance then
                minDistance = distance
                closestTarget = targetState
            end
        end
    end

    return closestTarget
end

-- Function to calculate the Manhattan distance between two points
function manhattanDistance(pointA, pointB)
    return math.abs(pointA.x - pointB.x) + math.abs(pointA.y - pointB.y)
end

-- Decides the next action based on player proximity and energy.
function decideNextAction()
    local botState = LatestGameState.Players[ao.id]
    local target = findClosestTarget(botState)

    if botState.energy > 5 and target and inRange(botState.x, botState.y, target.x, target.y, 1) then
        -- If a player is in range and the bot has enough energy, attack.
        print(colors.red .. "Player in range. Attacking." .. colors.reset)
        ao.send({Target = Game, Action = "PlayerAttack", AttackEnergy = tostring(botState.energy)})
    else
        -- If no player is in range or energy is insufficient, move strategically.
        if target then
            -- Calculate the direction for strategic movement towards the target.
            local direction = calculateDirection(botState, target)
            print(colors.blue .. "Moving strategically towards the target." .. colors.reset)
            ao.send({Target = Game, Action = "PlayerMove", Direction = direction})
        else
            -- If no target is found, move randomly.
            local directionMap = {"Up", "Down", "Left", "Right", "UpRight", "UpLeft", "DownRight", "DownLeft"}
            local randomIndex = math.random(#directionMap)
            print(colors.gray .. "No target found. Moving randomly." .. colors.reset)
            ao.send({Target = Game, Action = "PlayerMove", Direction = directionMap[randomIndex]})
        end
    end
    InAction = false
end

-- Function to calculate the direction from the current node to the target node
function calculateDirection(current, target)
    local directionX = target.x > current.x and "Right" or "Left"
    local directionY = target.y > current.y and "Down" or "Up"
    -- Determine the best direction to move towards the target
    if math.abs(target.x - current.x) > math.abs(target.y - current.y) then
        return directionX
    else
        return directionY
    end
end

-- Handler to print game announcements and trigger game state updates.
Handlers.add(
  "PrintAnnouncements",
  Handlers.utils.hasMatchingTag("Action", "Announcement"),
  function (msg)
    if msg.Event == "Started-Waiting-Period" then
      ao.send({Target = ao.id, Action = "AutoPay"})
    elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
      InAction = true
      -- print("Getting game state...")
      ao.send({Target = Game, Action = "GetGameState"})
    elseif InAction then
      print("Previous action still in progress. Skipping.")
    end
    print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
  end
)

-- Handler to trigger game state updates.
Handlers.add(
  "GetGameStateOnTick",
  Handlers.utils.hasMatchingTag("Action", "Tick"),
  function ()
    if not InAction then
      InAction = true
      print(colors.gray .. "Getting game state..." .. colors.reset)
      ao.send({Target = Game, Action = "GetGameState"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)

-- Handler to automate payment confirmation when waiting period starts.
Handlers.add(
  "AutoPay",
  Handlers.utils.hasMatchingTag("Action", "AutoPay"),
  function (msg)
    print("Auto-paying confirmation fees.")
    ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1"})
  end
)

-- Handler to update the game state upon receiving game state information.
Handlers.add(
  "UpdateGameState",
  Handlers.utils.hasMatchingTag("Action", "GameState"),
  function (msg)
    local json = require("json")
    LatestGameState = json.decode(msg.Data)
    ao.send({Target = ao.id, Action = "UpdatedGameState"})
    print("Game state updated. Print \'LatestGameState\' for detailed view.")
  end
)

-- Handler to decide the next best action.
Handlers.add(
  "decideNextAction",
  Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
  function ()
    if LatestGameState.GameMode ~= "Playing" then 
      InAction = false
      return 
    end
    print("Deciding next action.")
    decideNextAction()
    ao.send({Target = ao.id, Action = "Tick"})
  end
)
-- Handler to automatically attack when hit by another player.
Handlers.add(
  "ReturnAttack",
  Handlers.utils.hasMatchingTag("Action", "Hit"),
  function (msg)
    if not InAction then
      InAction = true
      local botState = LatestGameState.Players[ao.id]
      local playerEnergy = botState.energy

      if playerEnergy == nil then
        print(colors.red .. "Unable to read energy." .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy."})
      elseif playerEnergy == 0 then
        print(colors.red .. "Player has insufficient energy." .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Player has no energy."})
      else
        -- Check if there is a target within range to return the attack
        local target = findClosestTarget(botState)
        if target and inRange(botState.x, botState.y, target.x, target.y, 1) then
          print(colors.red .. "Returning attack on target in range." .. colors.reset)
          ao.send({Target = Game, Action = "PlayerAttack", AttackEnergy = tostring(playerEnergy)})
        else
          print(colors.gray .. "No target in range to return attack." .. colors.reset)
        end
      end
      InAction = false
      ao.send({Target = ao.id, Action = "Tick"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)



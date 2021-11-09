local output    = require('agda.output')
local state     = require('agda.state')
local utilities = require('agda.utilities')

local function handle (_, data)
  output.unlock()
  local message = vim.fn.json_decode(
    string.sub(data, 1, 5) == 'JSON>' and string.sub(data, 6) or data
  )

  -- print(vim.inspect(message))
  if message.kind == 'DisplayInfo' then
    if message.info.kind == 'AllGoalsWarnings' then
      utilities.update_pos_to_byte()
      output.clear()
      state.goals = {}

      output.set_height(#message.info.visibleGoals)
      for _, g in ipairs(message.info.visibleGoals) do
        local from = utilities.pos_to_line_left(g.constraintObj.range[1].start.pos)
        local to = utilities.pos_to_line_left(g.constraintObj.range[1]['end'].pos)
        local fromId = vim.api.nvim_buf_set_extmark(
          state.code_buf, state.namespace, from.line - 1, from.left, {}
        )
        local toId = vim.api.nvim_buf_set_extmark(
          state.code_buf, state.namespace,
          to.line - 1, to.left,
          {
            hl_group = 'agdakeyword', -- TODO this doesn't seem to work
            virt_text_pos = 'overlay',
            virt_text = {{'?' .. g.constraintObj.id}},
            right_gravity = false,
          }
        )
        table.insert(state.goals, {
          id = g.constraintObj.id,
          type = g.type,
          range = g.constraintObj.range[1],
          marks = {
            from = fromId,
            to = toId,
          },
          location = {
            from = { top = from.line - 1, left = from.left },
            to = { top = to.line - 1, left = to.left },
          },
        })

        utilities.update_goal_locations()
      end

      output.print_goals(state.goals)

    elseif message.info.kind == 'GoalSpecific' then
      output.clear()

      output.buf_print('Goal: ' .. message.info.goalInfo.type)
      if (#message.info.goalInfo.entries == 0) then
        output.set_height(1)
      else
        output.set_height(#message.info.goalInfo.entries + 3)
        output.buf_print('-----')
        output.buf_print('Context:')

        for _, e in ipairs(message.info.goalInfo.entries) do
          output.buf_print('  ' .. e.reifiedName .. ' : ' .. e.binding)
        end
      end
      vim.api.nvim_win_set_cursor(state.output_win, { 1, 1 })

    elseif message.info.kind == 'Context' then
      output.clear()
      output.set_height(#message.info.context)

      for _, c in ipairs(message.info.context) do
        -- set_lines(i - 1, i - 1, { c.reifiedName .. ' : ' .. c.binding })
        output.buf_print(c.reifiedName .. ' : ' .. c.binding)
      end

    elseif message.info.kind == 'Version' then
      output.set_lines(0, -1, { 'Agda version:', message.info.version })
      output.set_height(2)

    elseif message.info.kind == 'Error' then
      -- print('Error: ' .. message.info.error.message)
      output.clear()
      local lines = output.buf_print(message.info.error.message)
      output.set_height(lines)
      vim.api.nvim_win_set_cursor(state.output_win, { 1, 1 })

    end

  elseif message.kind == 'MakeCase' then
    vim.api.nvim_buf_set_lines(state.code_buf,
      message.interactionPoint.range[1].start.line - 1,
      message.interactionPoint.range[1]['end'].line,
      false, message.clauses)

    return true -- the file needs to be reloaded

  elseif message.kind == 'GiveAction' then
    utilities.update_pos_to_byte()
    utilities.update_goal_locations()
    local goal = state.goals[message.interactionPoint.id + 1]
    -- local range = message.interactionPoint.range[1]
    -- local from = utilities.pos_to_line_left(range.start.pos)
    -- local to = utilities.pos_to_line_left(range['end'].pos)
    local from = goal.location.from
    local to = goal.location.to

    vim.api.nvim_buf_set_text(
      state.code_buf,
      from.top, from.left, to.top, to.left,
      { message.giveResult.str }
    )

    vim.api.nvim_buf_del_extmark(
      state.code_buf, state.namespace,
      state.goals[message.interactionPoint.id + 1].marks.from
    )
    vim.api.nvim_buf_del_extmark(
      state.code_buf, state.namespace,
      state.goals[message.interactionPoint.id + 1].marks.to
    )

    return true -- the file needs to be reloaded

  elseif message.kind == 'HighlightingInfo' then
    utilities.update_pos_to_byte()

    for _, hl in ipairs(message.info.payload) do
      if #hl.atoms ~= 0 then -- TODO why is this sometimes empty? 🤔
        local from = utilities.pos_to_line_left(hl.range[1])
        local to = utilities.pos_to_line_left(hl.range[2])
        vim.api.nvim_buf_add_highlight(
          state.code_buf, state.namespace, 'agda' .. hl.atoms[1], from.line - 1, from.left, to.left
        )
      end
    end

  elseif message.kind == 'ClearHighlighting' then
    vim.api.nvim_buf_clear_namespace(state.code_buf, state.namespace, 0, -1)

  elseif message.kind == 'RunningInfo' then
    print(message.message)

  -- else
  --   print(vim.inspect(message))

  end

  output.lock()
end

return {
  handle = handle
}
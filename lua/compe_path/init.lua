local compe = require'compe'

-- TODO: ' or " or ` is valid as filename
local NAME_PATTERN = [[\%([^/\\:\*?<>'"`\|]\)]]
local DIRNAME_REGEX = vim.regex(([[\%(/PAT\+\)*\ze/PAT*$]]):gsub('PAT', NAME_PATTERN))

local Source = {}

--- get_metadata
Source.get_metadata = function(_)
  return {
    sort = false,
    priority = 10000,
  }
end

--- determine
Source.determine = function(_, context)
  return compe.helper.determine(context, {
    keyword_pattern = ([[/\zs%s*$]]):format(NAME_PATTERN),
    trigger_characters = { '/', '.' }
  })
end

--- complete
Source.complete = function(self, args)
  local dirname = self:_dirname(args.context)
  if not dirname then
    return args.abort()
  end

  local stat = self:_stat(dirname)
  if not stat then
    return args.abort()
  end

  self:_candidates(args.input:sub(1, 1) == '.', dirname, function(err, candidates)
    if err then
      return args.abort()
    end
    table.sort(candidates, function(item1, item2)
      return self:_compare(item1, item2)
    end)

    args.callback({
      items = candidates,
    })
  end)
end

--- _dirname
Source._dirname = function(self, context)
  local s, e = DIRNAME_REGEX:match_str(context.before_line)
  if not s then
    return nil
  end

  local dirname = string.sub(context.before_line, s + 1, e)
  local prefix = string.sub(context.before_line, 1, s + 1)

  local buf_dirname = vim.fn.expand(('#%d:p:h'):format(context.bufnr))
  if prefix:match('%../$') then
    return vim.fn.resolve(buf_dirname .. '/../' .. dirname)
  elseif prefix:match('%./$') then
    return vim.fn.resolve(buf_dirname .. '/' .. dirname)
  elseif prefix:match('~/$') then
    return vim.fn.expand('~/' .. dirname)
  elseif prefix:match('/$') then
    local accept = true
    -- Ignore HTML closing tags
    accept = accept and not prefix:match('</$')
    -- Ignore math calculation
    accept = accept and not prefix:match('[%d%)]%s*/$')
    -- Ignore / comment
    accept = accept and (not prefix:match('^[%s/]*$') or not self:_is_slash_comment())
    -- Ignore URL scheme
    accept = accept and not prefix:match('%a+:/$') and not prefix:match('%a+://$')
    if accept then
      return vim.fn.resolve('/' .. dirname)
    end
  end
  return nil
end

Source._stat = function(_, path)
  local stat = vim.loop.fs_stat(path)
  if stat then
    return stat
  end
  return nil
end

Source._candidates = function(_, include_hidden, dirname, callback)
  local fs, err = vim.loop.fs_scandir(dirname)
  if err then
    return callback(err, nil)
  end

  local items = {}

  while true do
    local name, type, e = vim.loop.fs_scandir_next(fs)
    if e then
      return callback(type, nil)
    end
    if not name then
      break
    end

    local accept = false
    accept = accept or include_hidden
    accept = accept or name:sub(1, 1) ~= '.'

    -- Create items
    if accept then
      if type == 'directory' then
        table.insert(items, {
            word = name,
            abbr = '/' .. name,
            menu = '[Dir]'
          })
      else
        table.insert(items, {
            word = name,
            abbr = name,
            menu = '[File]'
          })
      end
    end
  end
  callback(nil, items)
end

--- _compare
Source._compare = function(_, item1, item2)
  if item1.menu == '[Dir]' and item2.menu ~= '[Dir]' then
    return true
  elseif item1.menu ~= '[Dir]' and item2.menu == '[Dir]' then
    return false
  end
  return item1.word < item2.word
end

--- _is_slash_comment
Source._is_slash_comment = function(_)
  local commentstring = vim.fn.getbufvar('%', '&commentstring') or ''
  local no_filetype = vim.fn.getbufvar('%', '&filetype') == ''
  local is_slash_comment = false
  is_slash_comment = is_slash_comment or commentstring:match('/%*')
  is_slash_comment = is_slash_comment or commentstring:match('//')
  return is_slash_comment and not no_filetype
end

return Source


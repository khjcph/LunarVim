local M = {}

local Log = require "lvim.core.log"

local function git_cmd(opts)
  local plenary_loaded, Job = pcall(require, "plenary.job")
  if not plenary_loaded then
    vim.cmd "packadd plenary.nvim"
  end

  opts = opts or {}
  opts.cwd = opts.cwd or get_lvim_base_dir()

  local stderr = {}
  local stdout, ret = Job
    :new({
      command = "git",
      args = opts.args,
      cwd = opts.cwd,
      on_stderr = function(_, data)
        table.insert(stderr, data)
      end,
    })
    :sync()

  if not vim.tbl_isempty(stderr) then
    Log:debug(stderr)
  end

  if not vim.tbl_isempty(stdout) then
    Log:debug(stdout)
  end

  return ret, stdout
end

local function safe_deep_fetch()
  local ret, result = git_cmd { args = { "rev-parse", "--is-shallow-repository" } }
  if ret ~= 0 then
    Log:error "Git fetch failed! Check the log for further information"
    return
  end
  -- git fetch --unshallow will cause an error on a a complete clone
  local fetch_mode = result[1] == "true" and "--unshallow" or "--all"
  ret = git_cmd { args = { "fetch", fetch_mode } }
  if ret ~= 0 then
    Log:error "Git fetch failed! Check the log for further information"
    return
  end
  return true
end

---pulls the latest changes from github
function M.update_base_lvim()
  Log:info "Checking for updates"

  local ret = git_cmd { args = { "fetch" } }
  if ret ~= 0 then
    Log:error "Update failed! Check the log for further information"
    return
  end

  ret = git_cmd { args = { "diff", "--quiet", "@{upstream}" } }
  if ret == 0 then
    Log:info "LunarVim is already up-to-date"
    return
  end

  ret = git_cmd { args = { "merge", "--ff-only", "--progress" } }
  if ret ~= 0 then
    Log:error "Update failed! Please pull the changes manually instead."
    return
  end
end

---Switch Lunarvim to the specified development branch
---@param branch string
function M.switch_lvim_branch(branch)
  if not safe_deep_fetch() then
    return
  end
  local ret = git_cmd { args = { "switch", branch } }
  if ret ~= 0 then
    Log:error "Unable to switch branches! Check the log for further information"
    return
  end
end

---Get the current Lunarvim development branch
---@return string|nil
function M.get_lvim_branch()
  local ret, branch = git_cmd { args = { "branch", "--show-current" } }
  if ret ~= 0 or (not branch or branch[1] == "") then
    Log:error "Unable to retrieve the name of the current branch. Check the log for further information"
    return
  end
  return branch[1]
end

---Get currently checked-out tag of Lunarvim
---@param type string can be "short"
---@return string|nil
function M.get_lvim_tag(type)
  type = type or ""
  local ret, results = git_cmd { args = { "describe", "--tags" } }
  local lvim_full_ver = results[1] or ""

  if ret ~= 0 or string.match(lvim_full_ver, "%d") == nil then
    Log:error "Unable to retrieve current tag. Check the log for further information"
    return nil
  end
  if type == "short" then
    return vim.fn.split(lvim_full_ver, "-")[1]
  else
    return string.sub(lvim_full_ver, 1, #lvim_full_ver - 1)
  end
end

---Get the commit hash of currently checked-out commit of Lunarvim
---@param type string can be "short"
---@return string|nil
function M.get_lvim_version(type)
  type = type or ""
  local branch = M.get_lvim_branch()
  if branch == "master" then
    return M.get_lvim_tag(type)
  end
  local ret, log_results = git_cmd { args = { "log", "--pretty=format:%h", "-1" } }
  local abbrev_version = log_results[1] or ""
  if ret ~= 0 or string.match(abbrev_version, "%d") == nil then
    Log:error "Unable to retrieve current version. Check the log for further information"
    return nil
  end
  if type == "short" then
    return abbrev_version
  end
  return branch .. "-" .. abbrev_version
end

return M

#!/usr/bin/env -S nvim -l

-- 在仓库根目录运行。完整 matcher.get 基准，不含配置构建和 UI 绘制。
vim.opt.swapfile=false
vim.opt.shadafile='NONE'
vim.opt.runtimepath:prepend(vim.uv.cwd())
local match=require('flash-any.match')
local codetable=require('flash-any.match.codetable')
local literal=require('flash-any.match.literal')
local count=tonumber(arg[1] or '100')
assert(count and count>=2 and count%1==0,'character count must be an integer >= 2')
local text=('甲'):rep(count)
local patterns,codes={},{}
for i=1,20 do patterns[i]=('a'):rep(i) end
for i=1,10 do codes[i]=patterns[i] end
vim.api.nvim_buf_set_lines(0,0,-1,false,{text})
local sources={{name='literal',matcher=literal.matcher},{data={['甲']=codes},matcher=codetable.full_code}}
local opts={from={1,0},to={1,0}}
local function state(pattern,labels)
 local obj={value=pattern}
 obj.pattern=function() return obj.value end
 if labels then obj.labels=function() return labels end end
 return obj
end
local function get(obj) return match.get(0,obj,opts,sources) end
local result=get(state(patterns[20]))
assert(#result==count-1)
for i,item in ipairs(result) do
 assert(item.pos[2]==math.max(0,i-19)*3 and item.end_pos[2]==i*3)
 if count>2 then assert(item.next.a) else assert(not item.next.a) end
end
io.write('PARAMS chars='..count..' codes=1..10*a input=20*a mode=full_code matches='..#result .. '\n')
io.write('ENV '..vim.version().major..'.'..vim.version().minor..'.'..vim.version().patch..' '..jit.version .. '\n')
local sink
local function measure(name,fn)
 for _=1,20 do sink=fn() end
 local n=1
 while true do
  collectgarbage('collect')
  local start=vim.uv.hrtime()
  for _=1,n do sink=fn() end
  if vim.uv.hrtime()-start>=40000000 then break end
  n=n*2
 end
 local samples={}
 for _=1,7 do
  collectgarbage('collect')
  local start=vim.uv.hrtime()
  for _=1,n do sink=fn() end
  samples[#samples+1]=(vim.uv.hrtime()-start)/n/1e6
 end
 table.sort(samples)
 io.write(string.format('RESULT %s median=%.6f min=%.6f max=%.6f ms/op n=%d',name,samples[4],samples[1],samples[7],n) .. '\n')
end
measure('fresh-20',function() return get(state(patterns[20])) end)
local repeated=state(patterns[20])
get(repeated)
measure('same-pattern-cache',function() return get(repeated) end)
measure('type-1-through-20',function()
 local obj=state('')
 for _,pattern in ipairs(patterns) do obj.value=pattern; sink=get(obj) end
 return sink
end)
-- Prepare all independent 19-byte states outside the timed section.
do
 for _=1,20 do local obj=state(patterns[19]);get(obj);obj.value=patterns[20];sink=get(obj) end
 local samples={}
 local n=64
 for _=1,7 do
  local states={}
  for i=1,n do states[i]=state(patterns[19]);get(states[i]);states[i].value=patterns[20] end
  collectgarbage('collect')
  local start=vim.uv.hrtime()
  for _,obj in ipairs(states) do sink=get(obj) end
  samples[#samples+1]=(vim.uv.hrtime()-start)/n/1e6
 end
 table.sort(samples)
 io.write(string.format('RESULT append-19-to-20 median=%.6f min=%.6f max=%.6f ms/op n=%d',samples[4],samples[1],samples[7],n) .. '\n')
end
local labels={}
for char in ('asdfghjklqwertyuiopzxcvbnm'):gmatch('.') do labels[#labels+1]=char end
measure('fresh-20-with-labels',function() return get(state(patterns[20],labels)) end)
collectgarbage('collect')
local memory=collectgarbage('count')
local retained=state(patterns[20])
local retained_result=get(retained)
collectgarbage('collect')
io.write(string.format('RETAINED %.3f KiB matches=%d',collectgarbage('count')-memory,#retained_result) .. '\n')
assert(sink)

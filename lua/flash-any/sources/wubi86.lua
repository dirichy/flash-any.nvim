return function(opts)
  assert(not opts.scheme, "scheme is only supported by the pinyin source")
  return {
    data = require("flash-any.table").load("wubi86", { extra = require("flash-any.tables.punctuation") }),
    matcher = "full_code",
  }
end

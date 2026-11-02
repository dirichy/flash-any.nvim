return function(opts)
  assert(not opts.scheme, "scheme is only supported by the pinyin source")
  return {
    scope = "unicode",
    codetable = "unicode",
    matcher = "prefix",
    fallback = true,
  }
end

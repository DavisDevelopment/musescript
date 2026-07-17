// Named bags + pairs composed onto the portfolio (orders handled automatically).

strategy BagPairSleeve {
  param topN = 4
  param look = 13
  param hedgeScale = 0.25

  onBar {
    scores = dict_new()
    for (sym in symbols()) {
      when sym_available(sym): dict_set(scores, sym, mom_of(sym, look))
    }
    core = bag_equal(scan_top(scores, topN), "mom-core")
    // mild dollar-neutral overlay on the two highest-momentum names when present
    tops = scan_top(scores, 2)
    hedge = bag("hedge")
    when bag_size(bag_equal(tops)) >= 2:
      hedge = bag_pair(tops[0], tops[1], hedgeScale, "hedge")
    book = bag_norm(bag_add(core, hedge, "book"))
    portfolio_apply(book)
  }
}

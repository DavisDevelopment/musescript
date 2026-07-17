// Computed bags rematerialize each bar from panel momentum (or graph / fund fields).

strategy ComputedMomBag {
  param topN = 3
  param look = 8

  onBar {
    // Recipe bag: equal-weight top-N by mom(look) over the panel universe
    tops = bag_rank_mom(topN, look, "mom-tops")
    portfolio_apply(tops)
  }
}

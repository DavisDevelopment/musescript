
strategy ComputedBag {
  param topN = 3
  param look = 5
  onBar {
    portfolio_apply(bag_rank_mom(topN, look, "tops"))
  }
}

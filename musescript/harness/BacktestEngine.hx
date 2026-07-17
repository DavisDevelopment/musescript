package musescript.harness;

import musescript.runtime.IterDriver;

class BacktestEngine {
	public var orders:OrderSim;
	public var chart:ChartSink;

	public function new(?orders:OrderSim, ?chart:ChartSink) {
		this.orders = orders != null ? orders : new OrderSim();
		this.chart = chart != null ? chart : new ChartSink();
	}

	public function run(feed:BarFeed, onBar:Bar->Void):BacktestResult {
		feed.reset();
		IterDriver.each(feed, function(item) {
			var bar:Bar = cast item;
			// In causal mode, execute bar t-1 signals at bar t open before exposing
			// any of bar t's OHLCV values to the strategy.
			orders.beginBar(bar.open, bar.index);
			onBar(bar);
			orders.mark(bar.close);
		});
		var rets = Metrics.returnsFromEquity(orders.equity);
		return {
			equity: orders.equity,
			returns: rets,
			trades: orders.trades,
			sharpe: Metrics.sharpe(rets),
			maxDrawdown: Metrics.maxDrawdown(orders.equity),
			winRate: Metrics.winRate(orders.wins, orders.trades),
			finalEquity: orders.equity.length > 0 ? orders.equity[orders.equity.length - 1] : orders.cash
		};
	}
}

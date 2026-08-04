package musescript.tests;

class TestPortfolioPanelMain {
	public static function main() {
		var runner = new utest.Runner();
		runner.addCase(new TestPortfolioPanel());
		utest.ui.Report.create(runner);
		runner.run();
	}
}

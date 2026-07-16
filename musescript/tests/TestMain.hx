package musescript.tests;

import utest.Runner;
import utest.ui.Report;
import utest.Assert;
import utest.Test;

import musescript.MuseScript;
import musescript.parse.MuseParser;
import musescript.interp.MuseInterp;
import musescript.runtime.CallFrame;
import musescript.runtime.CallStack;
import musescript.runtime.FnClosure;
import musescript.runtime.IndicatorInstance;
import musescript.runtime.PatternMatcher;
import musescript.runtime.MuseIters;
import musescript.runtime.IterDriver;
import musescript.runtime.Generator;
import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.Stmt;
import musescript.ast.Expr;
import musescript.ast.Const;
import musescript.ast.MatchArm;
import musescript.ast.FnKind;
import musescript.ast.OrderKind;
import musescript.ast.ParamOpts;
import musescript.ast.Pattern;
import musescript.harness.HarnessContext;
import musescript.harness.LiveHarness;
import musescript.harness.BarFeed;
import musescript.harness.PlanRunner;
import musescript.harness.EventLog;
import musescript.builtins.TradeBuiltins;
import musescript.checker.MuseChecker;
import musescript.plan.MusePlanner;
import musescript.plan.MuseIR;
import musescript.compile.MuseCompiler;
import musescript.compile.GeneratorLower;
import musescript.compile.JsBackend;
import musescript.compile.HaxeBackend;

class TestMain {
	static function main() {
		var runner = new Runner();
		runner.addCase(new TestParse());
		runner.addCase(new TestCallStack());
		runner.addCase(new TestPattern());
		runner.addCase(new TestIter());
		runner.addCase(new TestBacktest());
		runner.addCase(new TestOptimize());
		runner.addCase(new TestTradeBuiltins());
		runner.addCase(new TestPlanner());
		runner.addCase(new TestChecker());
		runner.addCase(new TestCompiler());
		runner.addCase(new TestGenerator());
		runner.addCase(new TestGeneratorLower());
		runner.addCase(new TestTailCall());
		runner.addCase(new TestPrinter());
		runner.addCase(new TestEmit());
		runner.addCase(new TestScan());
		runner.addCase(new TestMathCompile());
		runner.addCase(new TestIndicator());
		runner.addCase(new TestOnTick());
		runner.addCase(new TestTypes());
		runner.addCase(new TestTypedSurface());
		runner.addCase(new TestMetaTier());
		Report.create(runner);
		runner.run();
	}
}

class TestParse extends Test {
	public function testRawRun() {
		var e = MuseScript.run("1 + 2");
		Assert.notNull(e);
	}

	public function testProgram() {
		var prog = new MuseParser().parse("@strategy(\"x\") @on(bar) { var a = 1; }");
		Assert.isTrue(prog.decls.length >= 1);
	}

	public function testIndicatorDecl() {
		var prog = new MuseParser().parse('@indicator("rsi") function(src, len) { return src; }');
		Assert.equals(1, prog.decls.length);
		switch (prog.decls[0]) {
			case IndicatorDecl(name, args, _):
				Assert.equals("rsi", name);
				Assert.equals(2, args.length);
				Assert.equals("src", args[0]);
				Assert.equals("len", args[1]);
			default:
				Assert.fail("expected IndicatorDecl");
		}
	}

	public function testRichMatchPatterns() {
		var e = new MuseParser().parseExpr('@match(1) [(x: Int) => x, @if(x > 0) x => x, _ => 0]');
		switch (e) {
			case EMatch(_, arms):
				Assert.equals(3, arms.length);
				switch (arms[0].pattern) {
					case PatTyped(n, t):
						Assert.equals("x", n);
						Assert.equals("Int", t);
					default:
						Assert.fail("expected PatTyped on first arm");
				}
				Assert.notNull(arms[1].guard);
				switch (arms[1].pattern) {
					case PatBind(n): Assert.equals("x", n);
					default: Assert.fail("expected PatBind on guarded arm");
				}
				Assert.isTrue(arms[2].pattern.match(PatWild));
			default:
				Assert.fail("expected EMatch");
		}
		var e2 = new MuseParser().parseExpr('@match([1,2,3]) [@rest(tail) [a, b] => tail]');
		switch (e2) {
			case EMatch(_, arms):
				Assert.equals(1, arms.length);
				switch (arms[0].pattern) {
					case PatArr(items, rest):
						Assert.equals("tail", rest);
						Assert.equals(2, items.length);
					default:
						Assert.fail("expected PatArr with rest");
				}
			default:
				Assert.fail("expected EMatch with PatArr rest");
		}
	}

	public function testArrayIndexVsLookback() {
		var prog = new MuseParser().parse('{
			@strategy("idx")
			@on(bar) {
				var xs = [1, 2, 3];
				var a = xs[0];
				var prev = close[1];
			}
		}');
		switch (prog.stmts[0]) {
			case OnBar(body):
				switch (body[1]) {
					case Assign(name, EArray(EIdent("xs"), _)):
						Assert.equals("a", name);
					default:
						Assert.fail("xs[0] should lower to EArray");
				}
				switch (body[2]) {
					case Assign(name, ELookback(EBarField("close"), _)):
						Assert.equals("prev", name);
					default:
						Assert.fail("close[1] should lower to ELookback");
				}
			default:
				Assert.fail("expected OnBar");
		}
	}

	public function testCallResultLookback() {
		var prog = new MuseParser().parse('{
			@strategy("clb")
			@on(bar) {
				var xs = [1, 2, 3];
				var a = xs[1];
				var prevMa = sma("close", 3)[1];
				var prevRsi = rsi(close, 14)[1];
			}
		}');
		switch (prog.stmts[0]) {
			case OnBar(body):
				switch (body[1]) {
					case Assign(_, EArray(EIdent("xs"), _)):
					default:
						Assert.fail("xs[1] should stay EArray");
				}
				switch (body[2]) {
					case Assign(name, ELookback(ECall(EIdent("sma"), _), _)):
						Assert.equals("prevMa", name);
					default:
						Assert.fail("sma(...)[1] should lower to ELookback(ECall)");
				}
				switch (body[3]) {
					case Assign(name, ELookback(ECall(EIdent("rsi"), _), _)):
						Assert.equals("prevRsi", name);
					default:
						Assert.fail("rsi(...)[1] should lower to ELookback(ECall)");
				}
			default:
				Assert.fail("expected OnBar");
		}

		var harness = new HarnessContext();
		harness.series.set("close", [1.0, 2.0, 3.0, 4.0, 5.0]);
		var interp = new MuseInterp(harness);
		// SMA(3) now = (3+4+5)/3 = 4; as-of [1] = (2+3+4)/3 = 3
		var now = TradeBuiltins.sma(harness, "close", 3);
		Assert.equals(4.0, now);
		var prev = interp.evalExpr(new MuseParser().parseExpr('sma("close", 3)[1]'));
		Assert.equals(3.0, prev);
		// Series restored after lookback
		Assert.equals(5, harness.series.get("close").length);
		Assert.equals(4.0, TradeBuiltins.sma(harness, "close", 3));
	}

	public function testTypedArrayIndexVsLookback() {
		var prog = new MuseParser().parse('strategy TypedIndex {
			onBar {
				xs = [10, 20, 30]
				first = xs[0]
				prev = close[1]
				ma = sma(close, 3)
				prevMa = ma[1]
				tape = ohlcv_window(2)
				tapeFirst = tape[0]
			}
		}');
		var body = switch (prog.decls[0]) {
			case StrategyDecl(_, body): switch (body[0]) {
				case OnBar(stmts): stmts;
				default: [];
			};
			default: [];
		};
		Assert.isTrue(switch (body[1]) {
			case Assign("first", EArray(EIdent("xs"), _)): true;
			default: false;
		});
		Assert.isTrue(switch (body[2]) {
			case Assign("prev", ELookback(EBarField("close"), _)): true;
			default: false;
		});
		Assert.isTrue(switch (body[4]) {
			case Assign("prevMa", ELookback(EIdent("ma"), _)): true;
			default: false;
		});
		Assert.isTrue(switch (body[6]) {
			case Assign("tapeFirst", EArray(EIdent("tape"), _)): true;
			default: false;
		});
	}
}

class TestCallStack extends Test {
	public function testReentrancy() {
		var stack = new CallStack();
		var outer = new CallFrame(null, "outer");
		outer.define("x", 1);
		stack.push(outer);
		var inner = new CallFrame(outer, "inner");
		inner.define("x", 2);
		stack.push(inner);
		Assert.equals(2, stack.resolve("x").value);
		stack.pop();
		Assert.equals(1, stack.resolve("x").value);
	}

	public function testFibRecursive() {
		var harness = new HarnessContext();
		var interp = new MuseInterp(harness);
		var fib = new FnClosure(["n"], EIf(
			EBinop("<=", EIdent("n"), EConst(CInt(1))),
			EIdent("n"),
			EBinop("+",
				ECall(EIdent("fib"), [EBinop("-", EIdent("n"), EConst(CInt(1)))]),
				ECall(EIdent("fib"), [EBinop("-", EIdent("n"), EConst(CInt(2)))])
			)
		), null, "fib", Normal);
		interp.globals.set("fib", fib);
		var r = interp.callClosure(fib, [8]);
		Assert.equals(21, r);
	}
}

class TestPattern extends Test {
	public function testBindAndGuard() {
		var m = new PatternMatcher();
		var arms:Array<MatchArm> = [
			{ pattern: PatBind("x"), guard: EBinop(">", EIdent("x"), EConst(CInt(5))), body: EConst(CString("big")) },
			{ pattern: PatWild, body: EConst(CString("small")) }
		];
		var harness = new HarnessContext();
		var interp = new MuseInterp(harness);
		var r = interp.evalExpr(EMatch(EConst(CInt(9)), arms));
		Assert.equals("big", r);
		r = interp.evalExpr(EMatch(EConst(CInt(2)), arms));
		Assert.equals("small", r);
	}

	public function testTagAndObj() {
		var m = new PatternMatcher();
		var bindings = new Map<String, Dynamic>();
		var ok = m.tryPattern(PatTag("Filled", [PatObj([
			{ name: "qty", pat: PatBind("q") }
		])]), { kind: "Filled", qty: 10 }, bindings);
		Assert.isTrue(ok);
		Assert.equals(10, bindings.get("q"));
	}

	public function testNestedPatGuard() {
		var arms:Array<MatchArm> = [
			{
				pattern: PatGuard(PatBind("x"), EBinop(">", EIdent("x"), EConst(CInt(0)))),
				body: EConst(CString("pos"))
			},
			{ pattern: PatWild, body: EConst(CString("non")) }
		];
		var harness = new HarnessContext();
		var interp = new MuseInterp(harness);
		Assert.equals("pos", interp.evalExpr(EMatch(EConst(CInt(3)), arms)));
		Assert.equals("non", interp.evalExpr(EMatch(EConst(CInt(-1)), arms)));
	}
}

class TestIter extends Test {
	public function testArrayAndDriver() {
		var it = MuseIters.from([1, 2, 3]);
		var sum = 0;
		IterDriver.each(it, function(v) sum += cast v);
		Assert.equals(6, sum);
	}

	public function testEventLogIsMuseIter() {
		var log = new EventLog([{ kind: "A" }, { kind: "B" }]);
		var n = 0;
		IterDriver.each(log, function(_) n++);
		Assert.equals(2, n);
	}

	public function testDropReduceRangeEnumerate() {
		var dropped = MuseIters.toArray(IterDriver.drop(MuseIters.from([1, 2, 3, 4]), 2));
		Assert.equals(2, dropped.length);
		Assert.equals(3, dropped[0]);
		Assert.equals(4, dropped[1]);

		var sum = IterDriver.reduce(MuseIters.from([1, 2, 3]), 0, function(a, b) return (a : Float) + (b : Float));
		Assert.equals(6, sum);

		var idxs = MuseIters.toArray(IterDriver.range(2, 5));
		Assert.equals(3, idxs.length);
		Assert.equals(2, idxs[0]);
		Assert.equals(4, idxs[2]);

		var en = MuseIters.toArray(IterDriver.enumerate(MuseIters.from(["a", "b"])));
		Assert.equals(2, en.length);
		Assert.equals(0, Reflect.field(en[0], "i"));
		Assert.equals("a", Reflect.field(en[0], "v"));
		Assert.equals(1, Reflect.field(en[1], "i"));
	}

	public function testAnyAllFindSumCount() {
		var xs = [1, 2, 3, 4];
		Assert.isTrue(IterDriver.any(MuseIters.from(xs), function(v) return (v : Int) > 3));
		Assert.isFalse(IterDriver.any(MuseIters.from(xs), function(v) return (v : Int) > 10));

		Assert.isTrue(IterDriver.all(MuseIters.from(xs), function(v) return (v : Int) > 0));
		Assert.isFalse(IterDriver.all(MuseIters.from(xs), function(v) return (v : Int) < 3));
		Assert.isTrue(IterDriver.all(MuseIters.from([]), function(_) return false));

		Assert.equals(3, IterDriver.find(MuseIters.from(xs), function(v) return (v : Int) >= 3));
		Assert.equals(null, IterDriver.find(MuseIters.from(xs), function(v) return (v : Int) > 10));

		Assert.equals(10.0, IterDriver.sum(MuseIters.from(xs)));
		Assert.equals(0.0, IterDriver.sum(MuseIters.from([])));

		Assert.equals(4, IterDriver.count(MuseIters.from(xs)));
		Assert.equals(0, IterDriver.count(MuseIters.from([])));
	}

	public function testTradeBuiltinsAnyAllFindSumCount() {
		var vars = new Map<String, Dynamic>();
		TradeBuiltins.install(vars, new HarnessContext());
		Assert.isTrue(vars.get("any")([1, 2, 3], function(v) return (v : Int) == 2));
		Assert.isTrue(vars.get("all")([2, 4, 6], function(v) return (v : Int) % 2 == 0));
		Assert.equals(4, vars.get("find")([1, 4, 9], function(v) return (v : Int) > 3));
		Assert.equals(6.0, vars.get("sum")([1, 2, 3]));
		Assert.equals(3, vars.get("count")([10, 20, 30]));
	}

	public function testMinMaxAvg() {
		var xs = [1, 5, 3, 2];
		Assert.equals(1.0, IterDriver.min(MuseIters.from(xs)));
		Assert.equals(5.0, IterDriver.max(MuseIters.from(xs)));
		Assert.equals(2.75, IterDriver.avg(MuseIters.from(xs)));

		Assert.isTrue(Math.isNaN(IterDriver.min(MuseIters.from([]))));
		Assert.isTrue(Math.isNaN(IterDriver.max(MuseIters.from([]))));
		Assert.isTrue(Math.isNaN(IterDriver.avg(MuseIters.from([]))));

		var vars = new Map<String, Dynamic>();
		TradeBuiltins.install(vars, new HarnessContext());
		Assert.equals(1.0, vars.get("min")([1, 5, 3, 2]));
		Assert.equals(5.0, vars.get("max")([1, 5, 3, 2]));
		Assert.equals(2.75, vars.get("avg")([1, 5, 3, 2]));
		Assert.isTrue(Math.isNaN(vars.get("min")([])));
		Assert.isTrue(Math.isNaN(vars.get("max")([])));
		Assert.isTrue(Math.isNaN(vars.get("avg")([])));
	}

	public function testDuckNextObjectIter() {
		var items = [10, 20, 30];
		var i = 0;
		var duck:Dynamic = {
			next: function() {
				if (i >= items.length) return { done: true, value: null };
				return { done: false, value: items[i++] };
			}
		};
		var it = MuseIters.from(duck);
		Assert.isTrue(Std.isOfType(it, musescript.runtime.ObjectIter));
		var vals = MuseIters.toArray(it);
		Assert.equals(3, vals.length);
		Assert.equals(10, vals[0]);
		Assert.equals(20, vals[1]);
		Assert.equals(30, vals[2]);
	}

	public function testDuckNextNullIsDone() {
		var duck:Dynamic = { next: function() return null };
		var vals = MuseIters.toArray(MuseIters.from(duck));
		Assert.equals(0, vals.length);
	}

	public function testFlatMap() {
		var out = MuseIters.toArray(IterDriver.flatMap(MuseIters.from([1, 2, 3]), function(v) {
			return [v, (v : Int) * 10];
		}));
		Assert.equals(6, out.length);
		Assert.equals(1, out[0]);
		Assert.equals(10, out[1]);
		Assert.equals(2, out[2]);
		Assert.equals(20, out[3]);
		Assert.equals(3, out[4]);
		Assert.equals(30, out[5]);

		var empty = MuseIters.toArray(IterDriver.flatMap(MuseIters.from([]), function(_) return [0]));
		Assert.equals(0, empty.length);

		var nested = MuseIters.toArray(IterDriver.flatMap(MuseIters.from([[1, 2], [3]]), function(v) return v));
		Assert.equals(3, nested.length);
		Assert.equals(1, nested[0]);
		Assert.equals(2, nested[1]);
		Assert.equals(3, nested[2]);

		var skipped = MuseIters.toArray(IterDriver.flatMap(MuseIters.from([1, 2, 3]), function(v) {
			return (v : Int) == 2 ? [] : [v];
		}));
		Assert.equals(2, skipped.length);
		Assert.equals(1, skipped[0]);
		Assert.equals(3, skipped[1]);

		var vars = new Map<String, Dynamic>();
		TradeBuiltins.install(vars, new HarnessContext());
		var built = MuseIters.toArray(vars.get("flatMap")([1, 2], function(v) return [v, v]));
		Assert.equals(4, built.length);
		Assert.equals(1, built[0]);
		Assert.equals(1, built[1]);
		Assert.equals(2, built[2]);
		Assert.equals(2, built[3]);
	}

	public function testTakeWhile() {
		var xs = [1, 2, 3, 4, 1];
		var taken = MuseIters.toArray(IterDriver.takeWhile(MuseIters.from(xs), function(v) return (v : Int) < 4));
		Assert.equals(3, taken.length);
		Assert.equals(1, taken[0]);
		Assert.equals(2, taken[1]);
		Assert.equals(3, taken[2]);

		var none = MuseIters.toArray(IterDriver.takeWhile(MuseIters.from(xs), function(v) return (v : Int) > 10));
		Assert.equals(0, none.length);

		var all = MuseIters.toArray(IterDriver.takeWhile(MuseIters.from([1, 2]), function(_) return true));
		Assert.equals(2, all.length);
		Assert.equals(1, all[0]);
		Assert.equals(2, all[1]);

		var empty = MuseIters.toArray(IterDriver.takeWhile(MuseIters.from([]), function(_) return true));
		Assert.equals(0, empty.length);

		var vars = new Map<String, Dynamic>();
		TradeBuiltins.install(vars, new HarnessContext());
		var built = MuseIters.toArray(vars.get("takeWhile")([5, 6, 7, 1], function(v) return (v : Int) >= 5));
		Assert.equals(3, built.length);
		Assert.equals(5, built[0]);
		Assert.equals(6, built[1]);
		Assert.equals(7, built[2]);
	}

	public function testZipWith() {
		var sums = MuseIters.toArray(IterDriver.zipWith(
			MuseIters.from([1, 2, 3]),
			MuseIters.from([10, 20, 30]),
			function(a, b) return (a : Int) + (b : Int)
		));
		Assert.equals(3, sums.length);
		Assert.equals(11, sums[0]);
		Assert.equals(22, sums[1]);
		Assert.equals(33, sums[2]);

		// stops at shorter stream
		var short = MuseIters.toArray(IterDriver.zipWith(
			MuseIters.from([1, 2, 3, 4]),
			MuseIters.from([10, 20]),
			function(a, b) return [a, b]
		));
		Assert.equals(2, short.length);
		Assert.equals(1, short[0][0]);
		Assert.equals(10, short[0][1]);
		Assert.equals(2, short[1][0]);
		Assert.equals(20, short[1][1]);

		var empty = MuseIters.toArray(IterDriver.zipWith(
			MuseIters.from([]),
			MuseIters.from([1]),
			function(a, b) return a
		));
		Assert.equals(0, empty.length);

		Assert.isTrue(Std.isOfType(
			new musescript.runtime.ZipIter(MuseIters.from([1]), MuseIters.from([2]), function(a, b) return a),
			musescript.runtime.ZipIter
		));

		var vars = new Map<String, Dynamic>();
		TradeBuiltins.install(vars, new HarnessContext());
		var built = MuseIters.toArray(vars.get("zipWith")([1, 2], ["a", "b", "c"], function(x, y) return '$x$y'));
		Assert.equals(2, built.length);
		Assert.equals("1a", built[0]);
		Assert.equals("2b", built[1]);

		// array zip remains materializing pairs; zipWith sits beside it
		var zipped = MuseIters.toArray(vars.get("zip")([1, 2, 3], [7, 8]));
		Assert.equals(2, zipped.length);
		Assert.equals(1, zipped[0][0]);
		Assert.equals(7, zipped[0][1]);

		// streaming MuseIter inputs (not array materialization)
		var sa = new musescript.runtime.StreamIter();
		sa.push(1);
		sa.push(2);
		sa.push(3);
		sa.end();
		var sb = new musescript.runtime.StreamIter();
		sb.push(100);
		sb.push(200);
		sb.end();
		var streamed = MuseIters.toArray(IterDriver.zipWith(sa, sb, function(a, b) return (a : Int) + (b : Int)));
		Assert.equals(2, streamed.length);
		Assert.equals(101, streamed[0]);
		Assert.equals(202, streamed[1]);
	}

	public function testZipWithJsBackend() {
		var harness = new HarnessContext();
		var api = JsBackend.createApi(harness);
		var out:Dynamic = api.invoke("zipWith", ([
			[1, 2, 3],
			[10, 20],
			function(a, b) return (a : Int) * (b : Int)
		] : Array<Dynamic>));
		var vals = MuseIters.toArray(out);
		Assert.equals(2, vals.length);
		Assert.equals(10, vals[0]);
		Assert.equals(40, vals[1]);
	}
}

class TestBacktest extends Test {
	public function testSmaCross() {
		var source = '
			@strategy("t")
			@param("fast", 5)
			@param("slow", 20)
			@on(bar) {
				var a = sma(close, fast);
				var b = sma(close, slow);
				if (crossover(a, b)) long();
				if (crossunder(a, b)) flat();
			}
		';
		var harness = new HarnessContext();
		harness.params.register("fast", 5);
		harness.params.register("slow", 20);
		var prog = new MuseParser().parse(source);
		var interp = new MuseInterp(harness);
		var result = interp.runBacktest(prog, BarFeed.synthetic(150, 3));
		Assert.isTrue(result.equity.length > 0);
		Assert.isTrue(result.finalEquity != null);
	}
}

class TestTradeBuiltins extends Test {
	public function testWindowsAndPortableStrings() {
		var harness = new HarnessContext();
		harness.series.set("open", [10.0, 11.0, 12.0, 13.0]);
		harness.series.set("high", [11.0, 12.0, 13.0, 14.0]);
		harness.series.set("low", [9.0, 10.0, 11.0, 12.0]);
		harness.series.set("close", [10.5, 11.5, 12.5, 13.5]);
		harness.series.set("volume", [100.0, 110.0, 120.0, 130.0]);

		var closeWindow = TradeBuiltins.window(harness, "close", 3);
		Assert.same([11.5, 12.5, 13.5], closeWindow);
		var packed = TradeBuiltins.ohlcvWindow(harness, 2);
		Assert.equals(10, packed.length);
		Assert.same([12.0, 13.0, 11.0, 12.5, 120.0], packed.slice(0, 5));
		Assert.same([13.0, 14.0, 12.0, 13.5, 130.0], packed.slice(5, 10));
		Assert.equals(0, TradeBuiltins.window(harness, "close", 0).length);

		// Bar-field sugar must retain series identity — not silently fall back to close.
		Assert.same([12.0, 13.0, 14.0], TradeBuiltins.window(harness, "high", 3));
		Assert.same([9.0, 10.0, 11.0, 12.0], TradeBuiltins.window(harness, "low", 4));

		var harnessBars = new HarnessContext();
		Reflect.setField(harnessBars, "feed", BarFeed.synthetic(5, 9));
		var prog = new MuseParser().parse('strategy HighWindow {
			onBar {
				hs = window(high, 3)
				cs = window(close, 3)
				when hs[2] != cs[2]: long()
			}
		}');
		var r = new MuseInterp(harnessBars).runBacktest(prog, BarFeed.synthetic(5, 9));
		Assert.isTrue(r.trades > 0);

		Assert.equals(4, TradeBuiltins.strLen("muse"));
		Assert.equals("use", TradeBuiltins.strSlice("musescript", 1, 4));
		Assert.equals("script", TradeBuiltins.strSlice("musescript", -6));
		Assert.isTrue(TradeBuiltins.strContains("musescript", "script"));
		Assert.equals("musescript", TradeBuiltins.strConcat("muse", "script"));
		Assert.equals(12.5, TradeBuiltins.strToFloat(" 12.5 "));
		Assert.isTrue(Math.isNaN(TradeBuiltins.strToFloat("nope")));
		Assert.isTrue(Math.isNaN(TradeBuiltins.strToFloat("12.5px")));
	}

	public function testCrossoverSlots() {
		TradeBuiltins.resetCrossState();
		TradeBuiltins.beginBar();
		Assert.isFalse(TradeBuiltins.crossover(1, 2));
		Assert.isFalse(TradeBuiltins.crossover(3, 4));

		TradeBuiltins.beginBar();
		Assert.isTrue(TradeBuiltins.crossover(3, 1));
		Assert.isFalse(TradeBuiltins.crossover(1, 3));
	}

	public function testCrossunderSlots() {
		TradeBuiltins.resetCrossState();
		TradeBuiltins.beginBar();
		Assert.isFalse(TradeBuiltins.crossunder(2, 1));

		TradeBuiltins.beginBar();
		Assert.isTrue(TradeBuiltins.crossunder(1, 3));
	}

	public function testRisingFalling() {
		TradeBuiltins.resetCrossState();
		TradeBuiltins.beginBar();
		Assert.isFalse(TradeBuiltins.rising(1, 2));
		TradeBuiltins.beginBar();
		Assert.isFalse(TradeBuiltins.rising(2, 2));
		TradeBuiltins.beginBar();
		Assert.isTrue(TradeBuiltins.rising(3, 2));
		TradeBuiltins.beginBar();
		Assert.isFalse(TradeBuiltins.rising(2, 2));

		TradeBuiltins.resetCrossState();
		TradeBuiltins.beginBar();
		Assert.isFalse(TradeBuiltins.falling(3, 2));
		TradeBuiltins.beginBar();
		Assert.isFalse(TradeBuiltins.falling(2, 2));
		TradeBuiltins.beginBar();
		Assert.isTrue(TradeBuiltins.falling(1, 2));
		TradeBuiltins.beginBar();
		Assert.isFalse(TradeBuiltins.falling(2, 2));
	}

	public function testNaNReturnsFalse() {
		TradeBuiltins.resetCrossState();
		TradeBuiltins.beginBar();
		Assert.isFalse(TradeBuiltins.crossover(Math.NaN, 1));
		Assert.isFalse(TradeBuiltins.rising(Math.NaN, 1));
		Assert.isFalse(TradeBuiltins.falling(Math.NaN, 1));
	}

	public function testBbandsMacdStochVwap() {
		var harness = new HarnessContext();
		var closes:Array<Float> = [10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20];
		var highs:Array<Float> = [for (c in closes) c + 1];
		var lows:Array<Float> = [for (c in closes) c - 1];
		var vols:Array<Float> = [for (_ in closes) 100.0];
		harness.series.set("close", closes);
		harness.series.set("high", highs);
		harness.series.set("low", lows);
		harness.series.set("volume", vols);

		var bb:Dynamic = TradeBuiltins.bbands(harness, "close", 5, 2.0);
		Assert.isTrue(Math.isFinite(bb.mid));
		Assert.isTrue(bb.upper > bb.mid);
		Assert.isTrue(bb.lower < bb.mid);

		var md:Dynamic = TradeBuiltins.macd(harness, "close", 3, 5, 2);
		Assert.isTrue(Math.isFinite(md.macd));
		Assert.isTrue(Math.isFinite(md.signal));
		Assert.isTrue(Math.isFinite(md.hist));

		var st:Dynamic = TradeBuiltins.stoch(harness, 5, 3, 3);
		Assert.isTrue(Math.isFinite(st.k));
		Assert.isTrue(st.k >= 0 && st.k <= 100);

		var vw = TradeBuiltins.vwap(harness);
		Assert.isTrue(Math.isFinite(vw));
		Assert.isTrue(vw > 10 && vw < 21);
	}

	public function testNaNz() {
		Assert.isTrue(TradeBuiltins.na(null));
		Assert.isTrue(TradeBuiltins.na(Math.NaN));
		Assert.isFalse(TradeBuiltins.na(0));
		Assert.isFalse(TradeBuiltins.na(1.5));
		Assert.equals(0.0, TradeBuiltins.nz(null));
		Assert.equals(0.0, TradeBuiltins.nz(Math.NaN));
		Assert.equals(7.0, TradeBuiltins.nz(Math.NaN, 7));
		Assert.equals(3.0, TradeBuiltins.nz(3.0));
		Assert.equals(3.0, TradeBuiltins.nz(3.0, 9));
	}

	public function testMomRoc() {
		var harness = new HarnessContext();
		harness.series.set("close", [10.0, 12.0, 15.0, 20.0]);
		Assert.equals(TradeBuiltins.change(harness, "close", 2), TradeBuiltins.mom(harness, "close", 2));
		Assert.equals(5.0, TradeBuiltins.mom(harness, "close", 1));
		var roc = TradeBuiltins.roc(harness, "close", 1);
		Assert.equals(TradeBuiltins.pctChange(harness, "close", 1) * 100, roc);
		Assert.isTrue(Math.abs(roc - 100.0 / 3.0) < 1e-9);
	}

	public function testStdevWmaRma() {
		var harness = new HarnessContext();
		var closes:Array<Float> = [2, 4, 4, 4, 5, 5, 7, 9];
		harness.series.set("close", closes);

		var sd = TradeBuiltins.stdev(harness, "close", 4);
		// last 4: 5,5,7,9 mean=6.5; pop var = (2.25+2.25+0.25+6.25)/4 = 2.75
		Assert.isTrue(Math.abs(sd - Math.sqrt(2.75)) < 1e-9);
		var bb:Dynamic = TradeBuiltins.bbands(harness, "close", 4, 1.0);
		Assert.isTrue(Math.abs((bb.upper - bb.mid) - sd) < 1e-9);

		harness.series.set("close", [1.0, 2.0, 3.0, 4.0]);
		// WMA(4): (1*1+2*2+3*3+4*4)/(1+2+3+4) = 30/10 = 3
		Assert.isTrue(Math.abs(TradeBuiltins.wma(harness, "close", 4) - 3.0) < 1e-9);

		harness.series.set("close", [1.0, 2.0, 3.0, 4.0, 5.0]);
		// RMA len=3: seed SMA(1,2,3)=2; then α=1/3: r4=1/3*4+2/3*2=8/3; r5=1/3*5+2/3*(8/3)=31/9
		Assert.isTrue(Math.abs(TradeBuiltins.rma(harness, "close", 3) - 31.0 / 9.0) < 1e-9);
		harness.series.set("close", [10.0, 20.0]);
		// short series: EMA-like α=1/3 from 10 → 20
		Assert.isTrue(Math.abs(TradeBuiltins.rma(harness, "close", 3) - ((1.0 / 3) * 20 + (2.0 / 3) * 10)) < 1e-9);
	}

	public function testHl2Hlc3Ohlc4() {
		var harness = new HarnessContext();
		harness.series.set("open", [1.0, 10.0]);
		harness.series.set("high", [2.0, 20.0]);
		harness.series.set("low", [0.0, 8.0]);
		harness.series.set("close", [1.5, 15.0]);
		Assert.equals(14.0, TradeBuiltins.hl2(harness)); // (20+8)/2
		Assert.equals(43.0 / 3.0, TradeBuiltins.hlc3(harness)); // (20+8+15)/3
		Assert.equals(53.0 / 4.0, TradeBuiltins.ohlc4(harness)); // (10+20+8+15)/4
		Assert.isTrue(Math.isNaN(TradeBuiltins.hl2(new HarnessContext())));
	}
}

class TestOptimize extends Test {
	public function testGridSharpe() {
		var source = '
			@strategy("t")
			@param("fast", 10)
			@param("slow", 30)
			@macro("d") {
				tune(fast, slow);
				optimize(sharpe);
			}
			@on(bar) {
				var a = sma("close", fast);
				var b = sma("close", slow);
				if (crossover(a, b)) long();
				if (crossunder(a, b)) flat();
			}
		';
		var harness = new HarnessContext();
		harness.params.register("fast", 10, 5, 15, 5, "grid");
		harness.params.register("slow", 30, 25, 35, 5, "grid");
		var prog = new MuseParser().parse(source);
		var plan = new MusePlanner().plan(prog);
		var opt = new PlanRunner(harness).bindProgram(prog, BarFeed.synthetic(120, 9)).optimize(plan, "sharpe");
		Assert.isTrue(opt.trials > 0);
		Assert.isTrue(Math.isFinite(opt.bestMetric));
		Assert.isTrue(opt.bestParams.exists("fast"));
		Assert.isTrue(opt.bestParams.exists("slow"));
	}
}

class TestPlanner extends Test {
	public function testMacroPlan() {
		var source = '
			@macro("d") {
				sample(universe, 10);
				tune(fast);
				optimize(sharpe);
			}
		';
		var plan = new MusePlanner().plan(new MuseParser().parse(source));
		Assert.isTrue(plan.steps.length >= 2);
		Assert.isTrue(MuseIR.toJson(plan).indexOf("SymbolSet") >= 0);
	}

	public function testDiscoveryExtraction() {
		var source = '
			@macro("discover") {
				sample(universe, 22);
				llm.suggestEncodings(features, 5);
				pickBest(encodings, function(enc) {
					return ensemble(enc, 100);
				});
				tune(learningRate, maxDepth);
				optimize(sharpe);
				distill(best);
			}
		';
		var json = MuseIR.toJson(new MusePlanner().plan(new MuseParser().parse(source)));
		Assert.isTrue(json.indexOf("learningRate") >= 0);
		Assert.isTrue(json.indexOf("maxDepth") >= 0);
		Assert.isTrue(json.indexOf("features") >= 0);
		Assert.isTrue(json.indexOf("encodings") >= 0);
		Assert.isTrue(json.indexOf("best") >= 0);
		Assert.isTrue(json.indexOf("DecisionTreeEnsemble") >= 0);
		Assert.isTrue(json.indexOf("\"trees\":100") >= 0 || json.indexOf("\"trees\": 100") >= 0);
	}

	public function testOptimizeOverArray() {
		var source = '
			@macro("d") {
				optimize(sharpe, [fast, slow]);
			}
		';
		var json = MuseIR.toJson(new MusePlanner().plan(new MuseParser().parse(source)));
		Assert.isTrue(json.indexOf("fast") >= 0);
		Assert.isTrue(json.indexOf("slow") >= 0);
	}
}

class TestChecker extends Test {
	public function testLookahead() {
		var prog = new MuseParser().parse("@on(bar) { var x = close[-1]; }");
		var errs = new MuseChecker().check(prog);
		Assert.isTrue(hasError(errs, "Negative lookback"));
	}

	public function testGeneratorYieldNested() {
		var body = EBlock([
			EVar("i", EIdent("start")),
			EWhile(
				EBinop("<", EIdent("i"), EIdent("stop")),
				EBlock([
					EYield(EIdent("i")),
					EBinop("=", EIdent("i"), EBinop("+", EIdent("i"), EConst(CInt(1))))
				])
			)
		]);
		var prog:MuseProgram = {
			decls: [FnDecl("range", ["start", "stop"], body, Generator)],
			stmts: []
		};
		var errs = new MuseChecker().check(prog);
		Assert.isFalse(hasWarning(errs, "generator function has no yield"));
	}

	public function testYieldOutsideGenerator() {
		var prog:MuseProgram = {
			decls: [],
			stmts: [OnBar([Yield(EConst(CInt(1)))])]
		};
		var errs = new MuseChecker().check(prog);
		Assert.isTrue(hasWarning(errs, "yield outside generator function"));
	}

	public function testUnreachableMatchArm() {
		var prog:MuseProgram = {
			decls: [],
			stmts: [ExprStmt(EMatch(EConst(CInt(1)), [
				{ pattern: PatWild, body: EConst(CInt(0)) },
				{ pattern: PatLit(CInt(1)), body: EConst(CInt(1)) }
			]))]
		};
		var errs = new MuseChecker().check(prog);
		Assert.isTrue(hasWarning(errs, "unreachable"));
	}

	function hasError(errs:Array<String>, needle:String):Bool {
		for (e in errs)
			if (e.indexOf("error:") == 0 && e.indexOf(needle) >= 0) return true;
		return false;
	}

	function hasWarning(errs:Array<String>, needle:String):Bool {
		for (e in errs)
			if (e.indexOf("warning:") == 0 && e.indexOf(needle) >= 0) return true;
		return false;
	}
}

class TestCompiler extends Test {
	public function testCompileJs() {
		var prog = new MuseParser().parse("@strategy(\"c\") @on(bar) { var x = close; }");
		var fn = MuseCompiler.compile(prog, { target: "js" });
		Assert.notNull(fn);
		var harness = new HarnessContext();
		var r = fn({ feed: BarFeed.synthetic(50, 1) });
		Assert.notNull(r);
	}

	public function testCompileWasmHelloBar() {
		var prog = new MuseParser().parse('{
			@strategy("ma_cross")
			@param("fast", 10)
			@param("slow", 30)
			@on(bar) {
				var maFast = sma("close", fast);
				var maSlow = sma("close", slow);
				if (crossover(maFast, maSlow)) long();
				if (crossunder(maFast, maSlow)) flat();
				plot(maFast, "fast");
				plot(maSlow, "slow");
			}
		}');
		var wat = musescript.compile.StrategyWasmBackend.emitWat(prog);
		Assert.notNull(wat);
		Assert.isTrue(wat.indexOf('(memory (export "memory")') >= 0);
		Assert.isTrue(wat.indexOf("push_bar") >= 0);
		Assert.isTrue(wat.indexOf("configure_tape") >= 0);
		Assert.isTrue(wat.indexOf("call $sma") >= 0);
		Assert.isTrue(wat.indexOf('(import "env" "sma"') < 0);
		Assert.isTrue(wat.indexOf('(import "env" "crossover"') < 0);
		Assert.isTrue(wat.indexOf("on_bar") >= 0);
		#if (js || python)
		if (musescript.compile.StrategyWasmBackend.hostReady()) {
			var harness = new HarnessContext();
			harness.params.register("fast", 10);
			harness.params.register("slow", 30);
			Reflect.setField(harness, "feed", BarFeed.synthetic(80, 3));
			var fn = MuseCompiler.compile(prog, { target: "wasm" });
			var r = fn(harness);
			Assert.notNull(r);
			// parity vs interp
			TradeBuiltins.resetCrossState();
			var hi = new HarnessContext();
			hi.params.register("fast", 10);
			hi.params.register("slow", 30);
			var ri = new MuseInterp(hi).runBacktest(prog, BarFeed.synthetic(80, 3));
			Assert.equals(ri.trades, r.trades);
			Assert.isTrue(Math.abs(ri.finalEquity - r.finalEquity) < 1e-6);
		}
		#end
	}

	public function testCompileWasmKestrelDenseFeaturePrelude() {
		var prog = new MuseParser().parse('
			strategy kestrel_dense {
				indicator ordinary = externalParam;
				feature graphSignal = graph_metric("supply", "degree");
				onBar {
					when treeSignal > ordinary: long();
				}
				feature treeSignal = tree_value("logic");
				onBar {
					when graphSignal < -1: flat();
				}
			}
		');
		var emitted = new musescript.compile.StrategyWasmEmitter().emitOnBar(prog);
		Assert.notNull(emitted);
		Assert.isTrue(emitted.strings.indexOf("externalParam") >= 0);
		var slots = musescript.kestrel.KestrelWasmArtifact.featureSlots(emitted.strings);
		Assert.equals(2, slots.length);
		Assert.equals(0, slots[0].id);
		Assert.equals("graph:supply:degree", slots[0].key);
		Assert.equals(1, slots[1].id);
		Assert.equals("tree:logic:value", slots[1].key);
		// Both assignments execute once per bar even though one is declared after
		// onBar and the strategy has two onBar blocks.
		Assert.equals(2, emitted.wat.split("call $feature_at").length - 1);
		Assert.isTrue(emitted.wat.indexOf("i32.const 0\n    call $feature_at") >= 0);
		Assert.isTrue(emitted.wat.indexOf("i32.const 1\n    call $feature_at") >= 0);
		#if (js || python)
		if (musescript.compile.StrategyWasmBackend.hostReady()) {
			var feed = BarFeed.synthetic(3, 7);
			var ctx:Dynamic = {
				feed: feed,
				kestrelFeatureTapes: [
					[-2.0, -2.0, -2.0], // graphSignal => flat
					[1.0, 1.0, 1.0]    // treeSignal => long
				]
			};
			var fn = musescript.compile.StrategyWasmBackend.compile(prog);
			var r = fn(ctx);
			Assert.equals(6, r.trades);
		}
		#end
	}

	public function testCompileWasmRejectsRuntimeVectorsAndStrings() {
		var vectors = new MuseParser().parse('{
			@strategy("vector")
			@on(bar) {
				var xs = window("close", 3);
				if (xs[0] > 0) long();
			}
		}');
		Assert.isNull(musescript.compile.StrategyWasmBackend.emitWat(vectors));

		var strings = new MuseParser().parse('{
			@strategy("strings")
			@on(bar) {
				if (str_contains("muse", "use")) long();
			}
		}');
		Assert.isNull(musescript.compile.StrategyWasmBackend.emitWat(strings));
	}

	public function testCompileWasmVwapClamp() {
		var prog = new MuseParser().parse('{
			@strategy("vwap_clamp")
			@on(bar) {
				var v = vwap();
				var c = clamp(close, 0, 100);
				var r = close % 10;
				plot(v, "vwap");
				plot(c, "clamped");
				plot(r, "rem");
			}
		}');
		var wat = musescript.compile.StrategyWasmBackend.emitWat(prog);
		Assert.notNull(wat);
		Assert.isTrue(wat.indexOf("call $vwap") >= 0);
		Assert.isTrue(wat.indexOf('(import "env" "vwap"') < 0);
		Assert.isTrue(wat.indexOf("f64.min") >= 0);
		Assert.isTrue(wat.indexOf("f64.max") >= 0);
		Assert.isTrue(wat.indexOf("f64.trunc") >= 0);
		#if (js || python)
		if (musescript.compile.StrategyWasmBackend.hostReady()) {
			var harness = new HarnessContext();
			Reflect.setField(harness, "feed", BarFeed.synthetic(40, 2));
			var fn = MuseCompiler.compile(prog, { target: "wasm" });
			var r = fn(harness);
			Assert.notNull(r);
		}
		#end
	}

	public function testCompileWasmMomRocStdevWmaRma() {
		var prog = new MuseParser().parse('{
			@strategy("pine_scalars")
			@on(bar) {
				var m = mom(close, 10);
				var r = roc(close, 10);
				var s = stdev(close, 14);
				var w = wma(close, 9);
				var a = rma(close, 14);
				plot(m, "mom");
				plot(r, "roc");
				plot(s, "stdev");
				plot(w, "wma");
				plot(a, "rma");
			}
		}');
		var wat = musescript.compile.StrategyWasmBackend.emitWat(prog);
		Assert.notNull(wat);
		Assert.isTrue(wat.indexOf("call $mom") >= 0);
		Assert.isTrue(wat.indexOf("call $roc") >= 0);
		Assert.isTrue(wat.indexOf("call $stdev") >= 0);
		Assert.isTrue(wat.indexOf("call $wma") >= 0);
		Assert.isTrue(wat.indexOf("call $rma") >= 0);
		Assert.isTrue(wat.indexOf('(import "env" "mom"') < 0);
		#if (js || python)
		if (musescript.compile.StrategyWasmBackend.hostReady()) {
			var harness = new HarnessContext();
			Reflect.setField(harness, "feed", BarFeed.synthetic(40, 2));
			var fn = MuseCompiler.compile(prog, { target: "wasm" });
			var out = fn(harness);
			Assert.notNull(out);
		}
		#end
	}

	public function testCompileWasmNativeMath() {
		var prog = new MuseParser().parse('{
			@strategy("native_math")
			@on(bar) {
				var a = abs(close - open);
				var s = Math.sqrt(close);
				var f = floor(close);
				var c = ceil(close);
				var lo = min(close, open);
				var hi = max(close, open);
				var z = nz(close, 0);
				plot(a, "abs");
				plot(s, "sqrt");
				plot(f, "floor");
				plot(c, "ceil");
				plot(lo, "min");
				plot(hi, "max");
				plot(z, "nz");
			}
		}');
		var wat = musescript.compile.StrategyWasmBackend.emitWat(prog);
		Assert.notNull(wat);
		Assert.isTrue(wat.indexOf("f64.abs") >= 0);
		Assert.isTrue(wat.indexOf("f64.sqrt") >= 0);
		Assert.isTrue(wat.indexOf("f64.floor") >= 0);
		Assert.isTrue(wat.indexOf("f64.ceil") >= 0);
		Assert.isTrue(wat.indexOf("f64.min") >= 0);
		Assert.isTrue(wat.indexOf("f64.max") >= 0);
		Assert.isTrue(wat.indexOf("select") >= 0);
		Assert.isTrue(wat.indexOf('(import "env" "abs"') < 0);
		Assert.isTrue(wat.indexOf('(import "env" "sqrt"') < 0);
		#if (js || python)
		if (musescript.compile.StrategyWasmBackend.hostReady()) {
			var harness = new HarnessContext();
			Reflect.setField(harness, "feed", BarFeed.synthetic(40, 2));
			var fn = MuseCompiler.compile(prog, { target: "wasm" });
			var r = fn(harness);
			Assert.notNull(r);
		}
		#end
	}

	/** Bare close[1] emits lookback; call base refuses (no silent close). ὁ ψευδὴς close κλέπτει τὴν ἀλήθειαν. */
	public function testCompileWasmLookbackSeriesOnly() {
		var bare = new MuseParser().parse('{
			@strategy("lb_bare")
			@on(bar) {
				var p = close[1];
				if (p > open) long();
			}
		}');
		var wat = musescript.compile.StrategyWasmBackend.emitWat(bare);
		Assert.notNull(wat);
		Assert.isTrue(wat.indexOf("lookback_ohlcv") >= 0);
		Assert.isTrue(wat.indexOf('(import "env" "lookback"') < 0);
		Assert.isTrue(wat.indexOf('(memory (export "memory")') >= 0);

		var callLb = new MuseParser().parse('{
			@strategy("lb_call")
			@on(bar) {
				var p = sma(close, 14)[1];
				if (p > close) long();
			}
		}');
		Assert.isNull(musescript.compile.StrategyWasmBackend.emitWat(callLb));
	}

	/** Streaming vs preloaded modes must agree. */
	public function testCompileWasmDualModeParity() {
		var prog = new MuseParser().parse('{
			@strategy("dual")
			@param("fast", 5)
			@param("slow", 15)
			@on(bar) {
				var maFast = sma("close", fast);
				var maSlow = sma("close", slow);
				if (crossover(maFast, maSlow)) long();
				if (crossunder(maFast, maSlow)) flat();
			}
		}');
		#if (js || python)
		if (musescript.compile.StrategyWasmBackend.hostReady()) {
			var feed = BarFeed.synthetic(120, 7);
			musescript.compile.StrategyWasmBackend.preferPreloaded = true;
			var h1 = new HarnessContext();
			h1.params.register("fast", 5);
			h1.params.register("slow", 15);
			Reflect.setField(h1, "feed", feed);
			var r1 = MuseCompiler.compile(prog, { target: "wasm" })(h1);

			musescript.compile.StrategyWasmBackend.preferPreloaded = false;
			var h2 = new HarnessContext();
			h2.params.register("fast", 5);
			h2.params.register("slow", 15);
			Reflect.setField(h2, "feed", BarFeed.synthetic(120, 7));
			var r2 = MuseCompiler.compile(prog, { target: "wasm" })(h2);
			musescript.compile.StrategyWasmBackend.preferPreloaded = true;

			Assert.equals(r1.trades, r2.trades);
			Assert.isTrue(Math.abs(r1.finalEquity - r2.finalEquity) < 1e-6);
		}
		#end
	}

	/** StrategyWasm na / round opcodes. γράφω εἰς σίδηρον ἵνα ἡ ἀλήθεια μὴ ῥέῃ. */
	public function testCompileWasmNaRound() {
		var prog = new MuseParser().parse('{
			@strategy("na_round")
			@on(bar) {
				var n = na(close);
				var r = round(close);
				plot(n, "na");
				plot(r, "round");
			}
		}');
		var wat = musescript.compile.StrategyWasmBackend.emitWat(prog);
		Assert.notNull(wat);
		Assert.isTrue(wat.indexOf("f64.ne") >= 0);
		Assert.isTrue(wat.indexOf("select") >= 0);
		Assert.isTrue(wat.indexOf("f64.nearest") >= 0);
		Assert.isTrue(wat.indexOf('(import "env" "na"') < 0);
		Assert.isTrue(wat.indexOf('(import "env" "round"') < 0);
		#if (js || python)
		if (musescript.compile.StrategyWasmBackend.hostReady()) {
			var harness = new HarnessContext();
			Reflect.setField(harness, "feed", BarFeed.synthetic(40, 2));
			var fn = MuseCompiler.compile(prog, { target: "wasm" });
			var out = fn(harness);
			Assert.notNull(out);
		}
		#end
	}

	/** StrategyWasm chart décor HostABI. χρῶμα καὶ γραμμὴ καὶ σχῆμα ἐπὶ τοῦ πίνακος. */
	public function testCompileWasmChartDecor() {
		var prog = new MuseParser().parse('{
			@strategy("chart_decor")
			@on(bar) {
				plot(close, "cl");
				plotshape("mark");
				hline(50, "mid");
				bgcolor("red");
			}
		}');
		var wat = musescript.compile.StrategyWasmBackend.emitWat(prog);
		Assert.notNull(wat);
		Assert.isTrue(wat.indexOf('(import "env" "plot"') >= 0);
		Assert.isTrue(wat.indexOf('(import "env" "plotshape"') >= 0);
		Assert.isTrue(wat.indexOf('(import "env" "hline"') >= 0);
		Assert.isTrue(wat.indexOf('(import "env" "bgcolor"') >= 0);
		Assert.isTrue(wat.indexOf("call $plotshape") >= 0);
		Assert.isTrue(wat.indexOf("call $hline") >= 0);
		Assert.isTrue(wat.indexOf("call $bgcolor") >= 0);
		#if (js || python)
		if (musescript.compile.StrategyWasmBackend.hostReady()) {
			var harness = new HarnessContext();
			Reflect.setField(harness, "feed", BarFeed.synthetic(20, 1));
			var fn = MuseCompiler.compile(prog, { target: "wasm" });
			var r = fn(harness);
			Assert.notNull(r);
			var kinds = [for (c in harness.chart.commands) c.kind];
			Assert.isTrue(kinds.indexOf("plot") >= 0);
			Assert.isTrue(kinds.indexOf("plotshape") >= 0);
			Assert.isTrue(kinds.indexOf("hline") >= 0);
			Assert.isTrue(kinds.indexOf("bgcolor") >= 0);
		}
		#end
	}
}

class TestGenerator extends Test {
	public function testYieldRange() {
		var harness = new HarnessContext();
		var interp = new MuseInterp(harness);
		var body = EBlock([
			EVar("i", EIdent("from")),
			EWhile(
				EBinop("<", EIdent("i"), EIdent("to")),
				EBlock([
					EYield(EIdent("i")),
					EBinop("=", EIdent("i"), EBinop("+", EIdent("i"), EConst(CInt(1))))
				])
			)
		]);
		var fn = new FnClosure(["from", "to"], body, null, "range", Generator);
		var gen = interp.callValue(fn, [1, 4]);
		Assert.isTrue(gen != null && Reflect.isFunction(Reflect.field(gen, "next")));
		var vals = MuseIters.toArray(cast gen);
		Assert.equals(3, vals.length);
		Assert.equals(1, vals[0]);
		Assert.equals(3, vals[2]);
	}

	public function testFromValues() {
		var vals = MuseIters.toArray(musescript.runtime.Generator.fromValues([10, 20, 30]));
		Assert.equals(3, vals.length);
		Assert.equals(10, vals[0]);
		Assert.equals(30, vals[2]);
	}

	public function testSteppedYieldAndDelegate() {
		var step = 0;
		var gen = new Generator();
		gen.pauseAfterYield = true;
		gen.evalBody = function(g:Generator) {
			switch (step++) {
				case 0: g.pushYield(1);
				case 1: g.delegateTo(musescript.runtime.Generator.fromValues([2, 3]));
				case 2: g.pushYield(4);
				default: return null;
			}
			return null;
		};
		var vals = MuseIters.toArray(gen);
		Assert.equals(4, vals.length);
		Assert.equals(1, vals[0]);
		Assert.equals(2, vals[1]);
		Assert.equals(3, vals[2]);
		Assert.equals(4, vals[3]);
	}
}

class TestGeneratorLower extends Test {
	public function testIdentityNoGenerators() {
		var factBody = EIf(
			EBinop("<=", EIdent("n"), EConst(CInt(1))),
			EIdent("acc"),
			EReturn(ECall(EIdent("fact"), [
				EBinop("-", EIdent("n"), EConst(CInt(1))),
				EBinop("*", EIdent("acc"), EIdent("n"))
			]))
		);
		var prog:MuseProgram = {
			decls: [FnDecl("fact", ["n", "acc"], factBody, Normal)],
			stmts: []
		};
		Assert.isTrue(GeneratorLower.lower(prog) == prog);
	}

	public function testLowerRangeWhileYield() {
		var body = EBlock([
			EVar("i", EIdent("start")),
			EWhile(
				EBinop("<", EIdent("i"), EIdent("stop")),
				EBlock([
					EYield(EIdent("i")),
					EBinop("=", EIdent("i"), EBinop("+", EIdent("i"), EConst(CInt(1))))
				])
			)
		]);
		var prog:MuseProgram = {
			decls: [FnDecl("range", ["start", "stop"], body, Generator)],
			stmts: []
		};
		prog = GeneratorLower.lower(prog);
		var lowered = switch (prog.decls[0]) {
			case FnDecl(_, _, b, kind):
				Assert.equals(Normal, kind);
				b;
			default: null;
		};
		Assert.notNull(lowered);
		Assert.isTrue(!containsYield(lowered));

		var harness = new HarnessContext();
		var interp = new MuseInterp(harness);
		interp.registerDeclPublic(prog.decls[0]);
		var fn = interp.globals.get("range");
		var gen = interp.callValue(fn, [1, 4]);
		var nextFn = Reflect.field(gen, "next");
		Assert.isTrue(Std.isOfType(nextFn, FnClosure));
		var vals = drainDoneValue(interp, gen);
		Assert.equals(3, vals.length);
		Assert.equals(1, vals[0]);
		Assert.equals(3, vals[2]);
	}

	public function testLowerSequentialYields() {
		var body = EBlock([
			EYield(EConst(CInt(10))),
			EYield(EConst(CInt(20)))
		]);
		var prog:MuseProgram = {
			decls: [FnDecl("pairs", [], body, Generator)],
			stmts: []
		};
		prog = GeneratorLower.lower(prog);
		Assert.isTrue(!containsYield(switch (prog.decls[0]) {
			case FnDecl(_, _, b, _): b;
			default: null;
		}));
		var harness = new HarnessContext();
		var interp = new MuseInterp(harness);
		interp.registerDeclPublic(prog.decls[0]);
		var gen = interp.callValue(interp.globals.get("pairs"), []);
		var vals = drainDoneValue(interp, gen);
		Assert.equals(2, vals.length);
		Assert.equals(10, vals[0]);
		Assert.equals(20, vals[1]);
	}

	public function testLowerYieldStarAsForYield() {
		var body = EBlock([
			EYieldStar(EArrayDecl([
				EConst(CInt(1)),
				EConst(CInt(2)),
				EConst(CInt(3))
			]))
		]);
		var prog:MuseProgram = {
			decls: [FnDecl("spread", [], body, Generator)],
			stmts: []
		};
		prog = GeneratorLower.lower(prog);
		var kind = switch (prog.decls[0]) {
			case FnDecl(_, _, b, k):
				Assert.isTrue(!containsYield(b));
				k;
			default: null;
		};
		Assert.equals(Normal, kind);
		var harness = new HarnessContext();
		var interp = new MuseInterp(harness);
		interp.registerDeclPublic(prog.decls[0]);
		var vals = drainDoneValue(interp, interp.callValue(interp.globals.get("spread"), []));
		Assert.equals(3, vals.length);
		Assert.equals(1, vals[0]);
		Assert.equals(3, vals[2]);
	}

	public function testLowerYieldStarOfVar() {
		var body = EBlock([
			EVar("xs", EArrayDecl([EConst(CInt(7)), EConst(CInt(8))])),
			EYieldStar(EIdent("xs"))
		]);
		var prog:MuseProgram = {
			decls: [FnDecl("fromVar", [], body, Generator)],
			stmts: []
		};
		prog = GeneratorLower.lower(prog);
		Assert.isTrue(!containsYield(switch (prog.decls[0]) {
			case FnDecl(_, _, b, _): b;
			default: null;
		}));
		var harness = new HarnessContext();
		var interp = new MuseInterp(harness);
		interp.registerDeclPublic(prog.decls[0]);
		var vals = drainDoneValue(interp, interp.callValue(interp.globals.get("fromVar"), []));
		Assert.equals(2, vals.length);
		Assert.equals(7, vals[0]);
		Assert.equals(8, vals[1]);
	}

	public function testLowerYieldThenYieldStar() {
		var body = EBlock([
			EVar("xs", EArrayDecl([EConst(CInt(2)), EConst(CInt(3))])),
			EYield(EConst(CInt(1))),
			EYieldStar(EIdent("xs"))
		]);
		var prog:MuseProgram = {
			decls: [FnDecl("prefixThenStar", [], body, Generator)],
			stmts: []
		};
		prog = GeneratorLower.lower(prog);
		var kind = switch (prog.decls[0]) {
			case FnDecl(_, _, b, k):
				Assert.isTrue(!containsYield(b));
				k;
			default: null;
		};
		Assert.equals(Normal, kind);
		var harness = new HarnessContext();
		var interp = new MuseInterp(harness);
		interp.registerDeclPublic(prog.decls[0]);
		var vals = drainDoneValue(interp, interp.callValue(interp.globals.get("prefixThenStar"), []));
		Assert.equals(3, vals.length);
		Assert.equals(1, vals[0]);
		Assert.equals(2, vals[1]);
		Assert.equals(3, vals[2]);
	}

	public function testLowerLiteralForThenYield() {
		// yield* [10, 20] expands to for; literal for expands to seq; trailing yield joins
		var body = EBlock([
			EYieldStar(EArrayDecl([EConst(CInt(10)), EConst(CInt(20))])),
			EYield(EConst(CInt(30)))
		]);
		var prog:MuseProgram = {
			decls: [FnDecl("starThenYield", [], body, Generator)],
			stmts: []
		};
		prog = GeneratorLower.lower(prog);
		Assert.equals(Normal, switch (prog.decls[0]) {
			case FnDecl(_, _, b, k):
				Assert.isTrue(!containsYield(b));
				k;
			default: null;
		});
		var harness = new HarnessContext();
		var interp = new MuseInterp(harness);
		interp.registerDeclPublic(prog.decls[0]);
		var vals = drainDoneValue(interp, interp.callValue(interp.globals.get("starThenYield"), []));
		Assert.equals(3, vals.length);
		Assert.equals(10, vals[0]);
		Assert.equals(20, vals[1]);
		Assert.equals(30, vals[2]);
	}

	public function testLowerForThenTrailingYield() {
		// dynamic for-in then trailing yield (not literal — true exit-to-seq path)
		var body = EBlock([
			EVar("xs", EArrayDecl([EConst(CInt(1)), EConst(CInt(2))])),
			EFor("n", EIdent("xs"), EBlock([EYield(EIdent("n"))])),
			EYield(EConst(CInt(99)))
		]);
		var prog:MuseProgram = {
			decls: [FnDecl("forThenTail", [], body, Generator)],
			stmts: []
		};
		prog = GeneratorLower.lower(prog);
		Assert.equals(Normal, switch (prog.decls[0]) {
			case FnDecl(_, _, b, k):
				Assert.isTrue(!containsYield(b));
				k;
			default: null;
		});
		var harness = new HarnessContext();
		var interp = new MuseInterp(harness);
		interp.registerDeclPublic(prog.decls[0]);
		var vals = drainDoneValue(interp, interp.callValue(interp.globals.get("forThenTail"), []));
		Assert.equals(3, vals.length);
		Assert.equals(1, vals[0]);
		Assert.equals(2, vals[1]);
		Assert.equals(99, vals[2]);
	}

	public function testLowerYieldStarVarThenTrailingYield() {
		var body = EBlock([
			EVar("xs", EArrayDecl([EConst(CInt(10)), EConst(CInt(20))])),
			EYieldStar(EIdent("xs")),
			EYield(EConst(CInt(30)))
		]);
		var prog:MuseProgram = {
			decls: [FnDecl("starVarThenTail", [], body, Generator)],
			stmts: []
		};
		prog = GeneratorLower.lower(prog);
		Assert.equals(Normal, switch (prog.decls[0]) {
			case FnDecl(_, _, b, k):
				Assert.isTrue(!containsYield(b));
				k;
			default: null;
		});
		var harness = new HarnessContext();
		var interp = new MuseInterp(harness);
		interp.registerDeclPublic(prog.decls[0]);
		var vals = drainDoneValue(interp, interp.callValue(interp.globals.get("starVarThenTail"), []));
		Assert.equals(3, vals.length);
		Assert.equals(10, vals[0]);
		Assert.equals(20, vals[1]);
		Assert.equals(30, vals[2]);
	}

	public function testLowerYieldThenForThenTrailingYield() {
		var body = EBlock([
			EVar("xs", EArrayDecl([EConst(CInt(2)), EConst(CInt(3))])),
			EYield(EConst(CInt(1))),
			EFor("n", EIdent("xs"), EBlock([EYield(EIdent("n"))])),
			EYield(EConst(CInt(4)))
		]);
		var prog:MuseProgram = {
			decls: [FnDecl("prefixLoopTail", [], body, Generator)],
			stmts: []
		};
		prog = GeneratorLower.lower(prog);
		Assert.equals(Normal, switch (prog.decls[0]) {
			case FnDecl(_, _, b, k):
				Assert.isTrue(!containsYield(b));
				k;
			default: null;
		});
		var harness = new HarnessContext();
		var interp = new MuseInterp(harness);
		interp.registerDeclPublic(prog.decls[0]);
		var vals = drainDoneValue(interp, interp.callValue(interp.globals.get("prefixLoopTail"), []));
		Assert.equals(4, vals.length);
		Assert.equals(1, vals[0]);
		Assert.equals(2, vals[1]);
		Assert.equals(3, vals[2]);
		Assert.equals(4, vals[3]);
	}

	static function containsYield(e:Expr):Bool {
		if (e == null) return false;
		return switch (e) {
			case EYield(_) | EYieldStar(_): true;
			case EBlock(es): for (x in es) if (containsYield(x)) return true; false;
			case EIf(_, a, b): containsYield(a) || (b != null && containsYield(b));
			case EWhile(_, a) | EFor(_, _, a) | EFunction(_, a, _, _): containsYield(a);
			default: false;
		};
	}

	static function drainDoneValue(interp:MuseInterp, gen:Dynamic):Array<Dynamic> {
		var out:Array<Dynamic> = [];
		var next = Reflect.field(gen, "next");
		while (true) {
			var r:Dynamic = interp.callValue(next, []);
			if (r == null || Reflect.field(r, "done")) break;
			out.push(Reflect.field(r, "value"));
		}
		return out;
	}
}

class TestTailCall extends Test {
	public function testFactRewritten() {
		var factBody = EIf(
			EBinop("<=", EIdent("n"), EConst(CInt(1))),
			EIdent("acc"),
			EReturn(ECall(EIdent("fact"), [
				EBinop("-", EIdent("n"), EConst(CInt(1))),
				EBinop("*", EIdent("acc"), EIdent("n"))
			]))
		);
		var prog:MuseProgram = {
			decls: [FnDecl("fact", ["n", "acc"], factBody, Normal)],
			stmts: []
		};
		prog = musescript.compile.TailCallPass.transform(prog);
		var body = switch (prog.decls[0]) {
			case FnDecl(_, _, b, _): b;
			default: factBody;
		};
		Assert.isTrue(!Type.enumEq(body, factBody));
		var harness = new HarnessContext();
		var interp = new MuseInterp(harness);
		var fact = new FnClosure(["n", "acc"], body, null, "fact", Normal);
		Assert.equals(3628800, interp.callClosure(fact, [10, 1]));
	}
}

class TestPrinter extends Test {
	public function testPrintStrategy() {
		var prog = new MuseParser().parse('{ @strategy("x") @on(bar) { var a = 1; } }');
		var out = new musescript.compile.MusePrinter().printProgram(prog);
		Assert.isTrue(out.indexOf("strategy") >= 0);
		Assert.isTrue(out.indexOf("onBar") >= 0 || out.indexOf("on bar") >= 0);
	}
}

class TestEmit extends Test {
	public function testCompiledWindowAndStringBuiltins() {
		#if js
		var prog = new MuseParser().parse('{
			@strategy("portable")
			@on(bar) {
				var xs = window("close", 3);
				var highs = window(high, 3);
				var packed = ohlcv_window(2);
				var label = str_concat("muse", "script");
				if (count(xs) == 3 && count(highs) == 3 && highs[2] != xs[2]
					&& count(packed) == 10
					&& str_contains(label, "script")
					&& str_slice(label, 0, 4) == "muse") long();
			}
		}');
		var harness = new HarnessContext();
		Reflect.setField(harness, "feed", BarFeed.synthetic(6, 4));
		var ex = MuseCompiler.compileEx(prog, { target: "js", strict: true });
		var result = ex.fn(harness);
		Assert.equals("js", ex.backend);
		Assert.isTrue(result.trades > 0);
		#end
		Assert.isTrue(true);
	}

	public function testEmitOnBar() {
		var prog = new MuseParser().parse('{
			@strategy("e")
			@param("fast", 10)
			@on(bar) {
				var ma = sma("close", fast);
				if (ma > close) long();
			}
		}');
		var src = musescript.compile.JsBackend.emitSource(prog);
		Assert.notNull(src);
		Assert.isTrue(src.indexOf("api.invoke") >= 0);
		Assert.isTrue(src.indexOf("sma") >= 0);
	}

	public function testEmitArraysObjectsForIn() {
		var prog = new MuseParser().parse('{
			@strategy("rich")
			@on(bar) {
				var xs = [1, 2, 3];
				var cfg = { threshold: 0.5, label: "x" };
				var sum = 0;
				for (v in xs) {
					sum = sum + v;
				}
				var ch = change("close", 1);
				var hi = highest("high", 5);
				if (sum > cfg.threshold && ch > 0) long();
				plot(hi, cfg.label);
			}
		}');
		var src = musescript.compile.JsBackend.emitSource(prog);
		Assert.notNull(src);
		Assert.isTrue(src.indexOf("[1,2,3]") >= 0 || src.indexOf("[1, 2, 3]") >= 0);
		Assert.isTrue(src.indexOf("threshold") >= 0);
		Assert.isTrue(src.indexOf("api.iter") >= 0);
		Assert.isTrue(src.indexOf("change") >= 0);
		Assert.isTrue(src.indexOf("highest") >= 0);
	}

	public function testEmitLookbackAndFunction() {
		var prog = new MuseParser().parse('{
			@strategy("lb")
			@on(bar) {
				var prev = close[1];
				var scale = function(x) { return x * 2; };
				var v = scale(prev);
				if (v > close) flat();
			}
		}');
		var src = musescript.compile.JsBackend.emitSource(prog);
		Assert.notNull(src);
		Assert.isTrue(src.indexOf("api.lookback") >= 0);
		Assert.isTrue(src.indexOf("function") >= 0);
	}

	public function testEmitMatch() {
		var prog = new MuseParser().parse('{
			@strategy("m")
			@on(bar) {
				var side = @match(1) [1 => "buy", _ => "sell"];
				if (side == "buy") long();
			}
		}');
		var src = musescript.compile.JsBackend.emitSource(prog);
		Assert.notNull(src);
		Assert.isTrue(src.indexOf("if(") >= 0);
	}

	public function testEmitMatchFor() {
		var arms:Array<MatchArm> = [
			{ pattern: PatLit(CInt(1)), body: ECall(EIdent("long"), []) },
			{ pattern: PatWild, body: ECall(EIdent("flat"), []) }
		];
		var prog:MuseProgram = {
			decls: [StrategyDecl("mf", [OnBar([
				MatchFor("x", EArrayDecl([EConst(CInt(1)), EConst(CInt(2))]), arms)
			])])],
			stmts: []
		};
		var src = JsBackend.emitSource(prog);
		Assert.notNull(src);
		Assert.isTrue(src.indexOf("api.iter") >= 0);
	}

	public function testCompileExStrict() {
		#if js
		var prog = new MuseParser().parse('{
			@strategy("ma")
			@param("fast", 10)
			@on(bar) {
				var ma = sma("close", fast);
				if (ma > close) long();
			}
		}');
		var ex = MuseCompiler.compileEx(prog, { target: "js", strict: true });
		Assert.isTrue(ex.emitted);
		Assert.equals("js", ex.backend);
		#else
		Assert.isTrue(true); // JS-host eval only
		#end
	}

	public function testEmitIndicators() {
		var prog = new MuseParser().parse('{
			@indicator("muse_sma") function(len) {
				if (bar_index + 1 < len) return null;
				return close;
			}
			@strategy("s")
			@on(bar) {
				var v = muse_sma(10);
				if (v != null && v > close) long();
			}
		}');
		var inds = new musescript.compile.JsEmitter().emitIndicators(prog);
		Assert.equals(1, inds.length);
		Assert.equals("muse_sma", inds[0].name);
		Assert.isTrue(inds[0].src.indexOf("return") >= 0);
		Assert.isTrue(inds[0].src.indexOf("if(") >= 0 || inds[0].src.indexOf("if (") >= 0);
		var src = musescript.compile.JsBackend.emitSource(prog);
		Assert.notNull(src);
		Assert.isTrue(src.indexOf("muse_sma") >= 0);
	}

	#if js
	public function testCompiledIndicatorSuiteSmoke() {
		var prog = new MuseParser().parse(musescript.examples.IndicatorSuite.SOURCE);
		Assert.notNull(JsBackend.emitSource(prog));
		var inds = new musescript.compile.JsEmitter().emitIndicators(prog);
		Assert.isTrue(inds.length >= 10);
		var harness = new HarnessContext();
		harness.params.register("fast", 10);
		harness.params.register("slow", 30);
		harness.params.register("rsiLen", 14);
		harness.params.register("atrLen", 14);
		Reflect.setField(harness, "feed", BarFeed.synthetic(60, 5));
		var fn = MuseCompiler.compile(prog, { target: "js" });
		var r = fn(harness);
		Assert.notNull(r);
		Assert.isTrue(harness.chart.commands.length > 0);
	}
	#end

	public function testEmitYieldStillUnsupported() {
		var prog:MuseProgram = {
			decls: [StrategyDecl("y", [OnBar([Yield(EBarField("close"))])])],
			stmts: []
		};
		var src = musescript.compile.JsBackend.emitSource(prog);
		Assert.isNull(src);
	}

	public function testEmitOnTick() {
		var prog = new MuseParser().parse('{
			@strategy("t")
			@on(tick) {
				var p = price;
				if (p > 100 && size > 0) long();
			}
		}');
		var tickSrc = JsBackend.emitTickSource(prog);
		Assert.notNull(tickSrc);
		Assert.isTrue(tickSrc.indexOf("function(api)") >= 0);
		Assert.isTrue(tickSrc.indexOf('api.get("price")') >= 0);
		Assert.isTrue(tickSrc.indexOf('api.get("size")') >= 0);
		var src = JsBackend.emitSource(prog);
		Assert.notNull(src);
		Assert.isTrue(src.indexOf('api.get("price")') >= 0);
	}

	public function testEmitOnBarAndOnTickSiblings() {
		var prog = new MuseParser().parse('{
			@strategy("both")
			@on(bar) {
				if (close > open) long();
			}
			@on(tick) {
				if (price > 0) flat();
			}
		}');
		Assert.notNull(JsBackend.emitTickSource(prog));
		var src = JsBackend.emitSource(prog);
		Assert.notNull(src);
		Assert.isTrue(src.indexOf('api.bar("close")') >= 0 || src.indexOf("close") >= 0);
		Assert.isTrue(src.indexOf('api.get("price")') >= 0);
		// Two function(api) blobs: bar + tick
		var first = src.indexOf("function(api)");
		Assert.isTrue(first >= 0);
		Assert.isTrue(src.indexOf("function(api)", first + 1) >= 0);
	}

	public function testEmitNestedOnTickStillUnsupported() {
		var prog:MuseProgram = {
			decls: [StrategyDecl("bad", [OnBar([OnTick([ExprStmt(EIdent("price"))])])])],
			stmts: []
		};
		Assert.isNull(JsBackend.emitSource(prog));
		Assert.isNull(JsBackend.emitTickSource(prog));
	}

	public function testEmitOnEvent() {
		var prog = new MuseParser().parse('{
			@strategy("ev")
			@on(orderFlow) {
				var k = kind;
				if (k == "Filled" && size > 0) note(price);
			}
		}');
		var eventSrc = JsBackend.emitEventSource(prog);
		Assert.notNull(eventSrc);
		Assert.isTrue(eventSrc.indexOf("function(api)") >= 0);
		Assert.isTrue(eventSrc.indexOf('api.get("__stream")==="orderFlow"') >= 0);
		Assert.isTrue(eventSrc.indexOf('api.get("kind")') >= 0);
		Assert.isTrue(eventSrc.indexOf('api.get("price")') >= 0);
		var src = JsBackend.emitSource(prog);
		Assert.notNull(src);
		Assert.isTrue(src.indexOf('api.get("kind")') >= 0);
	}

	public function testEmitNestedOnEventStillUnsupported() {
		var prog:MuseProgram = {
			decls: [StrategyDecl("bad", [OnBar([OnEvent("orderFlow", [ExprStmt(EIdent("kind"))])])])],
			stmts: []
		};
		Assert.isNull(JsBackend.emitSource(prog));
		Assert.isNull(JsBackend.emitEventSource(prog));
	}
}

class TestScan extends Test {
	public function testScanSum() {
		var it = musescript.runtime.IterDriver.scan(MuseIters.from([1, 2, 3]), 0, function(a, b) return a + b);
		var vals = MuseIters.toArray(it);
		Assert.equals(3, vals.length);
		Assert.equals(6, vals[2]);
	}
}

class TestIndicator extends Test {
	public function testDeclCreatesInstance() {
		var harness = new HarnessContext();
		var interp = new MuseInterp(harness);
		var body = EBlock([
			EBinop("=",
				EField(EIdent("state"), "n"),
				EBinop("+",
					EIf(EBinop("!=", EField(EIdent("state"), "n"), EConst(CNull)),
						EField(EIdent("state"), "n"),
						EConst(CInt(0))
					),
					EConst(CInt(1))
				)
			),
			EField(EIdent("state"), "n")
		]);
		interp.registerDeclPublic(IndicatorDecl("ctr", [], body));
		var inst = interp.globals.get("ctr");
		Assert.isTrue(Std.isOfType(inst, IndicatorInstance));
		Assert.equals(inst, harness.indicators.get("ctr"));
		Assert.equals(1, interp.callValue(inst, []));
		Assert.equals(2, interp.callValue(inst, []));
		Assert.equals(2, (cast inst : IndicatorInstance).getState("n"));
	}

	public function testBacktestStillWorks() {
		var harness = new HarnessContext();
		var prog:MuseProgram = {
			decls: [IndicatorDecl("emaLike", ["src"], ECall(EIdent("sma"), [EIdent("src"), EConst(CInt(3))]))],
			stmts: [OnBar([ExprStmt(ECall(EIdent("emaLike"), [EBarField("close")]))])]
		};
		var interp = new MuseInterp(harness);
		var result = interp.runBacktest(prog, BarFeed.synthetic(20, 2));
		Assert.isTrue(result.equity.length > 0);
	}
}

class TestOnTick extends Test {
	public function testDispatchTicksBindsPrice() {
		var harness = new LiveHarness();
		var ticks:Array<Dynamic> = [
			{ price: 100.0, size: 10, ts: 1 },
			{ price: 101.5, size: 5, ts: 2 }
		];
		harness.start();
		harness.publishTicks(ticks);
		harness.stop();
		harness.pump();

		var seen:Array<Float> = [];
		var interp = new MuseInterp(harness);
		interp.globals.set("note", function(px:Float) seen.push(px));
		interp.executeProgram({
			decls: [],
			stmts: [OnTick([ExprStmt(ECall(EIdent("note"), [EIdent("price")]))])]
		});
		interp.dispatchTicks();
		Assert.equals(2, seen.length);
		Assert.equals(100.0, seen[0]);
		Assert.equals(101.5, seen[1]);
	}

	public function testDispatchTicksWithIter() {
		var harness = new HarnessContext();
		var log = new EventLog([
			{ px: 50.0, qty: 1 },
			{ px: 51.0, qty: 2 }
		]);
		log.reset();

		var sum = 0.0;
		var interp = new MuseInterp(harness);
		interp.globals.set("add", function(px:Float) sum += px);
		interp.executeProgram({
			decls: [],
			stmts: [OnTick([ExprStmt(ECall(EIdent("add"), [EIdent("price")]))])]
		});
		interp.dispatchTicks(log);
		Assert.equals(101.0, sum);
	}

	public function testEmitOnTickSourceBindsPrice() {
		var prog = new MuseParser().parse('{
			@strategy("tick_emit")
			@on(tick) {
				note(price);
			}
		}');
		var tickSrc = JsBackend.emitTickSource(prog);
		Assert.notNull(tickSrc);
		Assert.isTrue(tickSrc.indexOf('api.get("price")') >= 0);
		Assert.isTrue(tickSrc.indexOf("function(api)") >= 0);
		var combined = JsBackend.emitSource(prog);
		Assert.notNull(combined);
		Assert.isTrue(combined.indexOf('api.get("price")') >= 0);
	}

	#if js
	public function testCompileExposesOnTick() {
		var prog = new MuseParser().parse('{
			@strategy("tick_js")
			@on(tick) {
				note(price);
				note(size);
			}
		}');
		JsBackend.compile(prog);
		Assert.equals("js", JsBackend.lastBackend);
		Assert.notNull(JsBackend.lastOnTick);
		var seen:Array<Float> = [];
		var harness = new HarnessContext();
		var api = JsBackend.createApi(harness);
		Reflect.field(api, "set")("note", function(v:Float) seen.push(v));
		JsBackend.dispatchTicks(api, [
			{ price: 100.0, size: 10 },
			{ px: 101.5, qty: 5 }
		]);
		Assert.equals(4, seen.length);
		Assert.equals(100.0, seen[0]);
		Assert.equals(10.0, seen[1]);
		Assert.equals(101.5, seen[2]);
		Assert.equals(5.0, seen[3]);
	}

	public function testCompileExposesOnEvent() {
		var prog = new MuseParser().parse('{
			@strategy("ev_js")
			@on(orderFlow) {
				note(kind);
				note(price);
			}
		}');
		JsBackend.compile(prog);
		Assert.equals("js", JsBackend.lastBackend);
		Assert.notNull(JsBackend.lastOnEvent);
		var seen:Array<Dynamic> = [];
		var harness = new HarnessContext();
		var api = JsBackend.createApi(harness);
		Reflect.field(api, "set")("note", function(v:Dynamic) seen.push(v));
		JsBackend.dispatchEvents(api, "orderFlow", [
			{ kind: "Filled", px: 100.0, qty: 50 },
			{ kind: "Rejected", px: 102.0, reason: "limit" }
		]);
		Assert.equals(4, seen.length);
		Assert.equals("Filled", seen[0]);
		Assert.equals(100.0, seen[1]);
		Assert.equals("Rejected", seen[2]);
		Assert.equals(102.0, seen[3]);
		// Wrong stream — stream filter skips body
		seen = [];
		JsBackend.dispatchEvents(api, "other", [{ kind: "Filled", px: 1.0 }]);
		Assert.equals(0, seen.length);
	}
	#end
}

class TestMathCompile extends Test {
	static var src = '{
		function polySum(n) {
			var acc = 0.0;
			var i = 0;
			while (i < n) {
				var x = i * 0.001;
				acc = acc + (x * x) - x;
				i = i + 1;
			}
			return acc;
		}
	}';

	public function testMathOnlyDetect() {
		var prog = new MuseParser().parse(src);
		var fns = musescript.compile.MathOnly.extract(prog);
		Assert.equals(1, fns.length);
		Assert.equals("polySum", fns[0].name);
	}

	public function testEmitJsAndPy() {
		var prog = new MuseParser().parse(src);
		var js = musescript.compile.MathCompiler.emit(prog, "polySum", { target: "js" });
		var py = musescript.compile.MathCompiler.emit(prog, "polySum", { target: "python" });
		var wat = musescript.compile.MathCompiler.emit(prog, "polySum", { target: "wasm" });
		Assert.notNull(js);
		Assert.notNull(py);
		Assert.notNull(wat);
		Assert.isTrue(js.indexOf("function polySum") >= 0);
		Assert.isTrue(py.indexOf("def polySum") >= 0);
		Assert.isTrue(wat.indexOf("(module") >= 0);
	}

	public function testHostCompile() {
		var prog = new MuseParser().parse(src);
		#if js
		var fn = musescript.compile.MathCompiler.compile(prog, "polySum", { target: "js" });
		Assert.notNull(fn);
		Assert.equals(fn([0]), 0);
		#elseif python
		var py = musescript.compile.MathCompiler.compile(prog, "polySum", { target: "python" });
		Assert.notNull(py);
		Assert.equals(py([0]), 0);
		var nb = musescript.compile.MathCompiler.compile(prog, "polySum", { target: "numba" });
		Assert.notNull(nb);
		Assert.equals(nb([0]), 0);
		var wasm = musescript.compile.MathCompiler.compile(prog, "polySum", { target: "wasm" });
		Assert.notNull(wasm);
		Assert.equals(wasm([0]), 0);
		#end
	}

	/** Math WasmEmitter % / nz / clamp opcodes — parity with StrategyWasm. ἴσον τὸ δίκαιον. */
	public function testMathWasmModNzClamp() {
		var prog = new MuseParser().parse('{
			function mathExtras(x, lo, hi) {
				var r = x % 10.0;
				var z = nz(x, 0.0);
				var c = clamp(x, lo, hi);
				return r + z + c;
			}
		}');
		var wat = musescript.compile.MathCompiler.emit(prog, "mathExtras", { target: "wasm" });
		Assert.notNull(wat);
		Assert.isTrue(wat.indexOf("f64.trunc") >= 0);
		Assert.isTrue(wat.indexOf("f64.min") >= 0);
		Assert.isTrue(wat.indexOf("f64.max") >= 0);
		Assert.isTrue(wat.indexOf("select") >= 0);
		Assert.isTrue(wat.indexOf('(import "env" "nz"') < 0);
		Assert.isTrue(wat.indexOf('(import "env" "clamp"') < 0);
	}

	public function testVolumeProfileMutableOutputAbi() {
		var source = sys.io.File.getContent("kernels/volume_profile_v1.ms");
		var prog = new MuseParser().parse(source, "kernels/volume_profile_v1.ms");
		var wat = musescript.compile.MathCompiler.emit(prog, "volume_profile_v1", { target: "wasm" });
		var js = musescript.compile.MathCompiler.emit(prog, "volume_profile_v1", { target: "js" });
		Assert.notNull(wat);
		Assert.notNull(js);
		Assert.isTrue(wat.indexOf('(memory (export "memory")') >= 0);
		Assert.isTrue(wat.indexOf("(param $output__base i32) (param $output__len i32)") >= 0);
		Assert.isTrue(wat.indexOf("f64.store") >= 0);
		Assert.isTrue(wat.indexOf('(export "volume_profile_v1"') >= 0);
		Assert.isTrue(js.indexOf("output[bin] = 0") >= 0);
	}
}

class TestTypes extends Test {
	public function testArgSwapCaught() {
		var errs = MuseScript.check('{
			@strategy("x")
			@param("fast", 10)
			@on(bar) { var x = sma(fast, "close"); }
		}');
		Assert.isTrue(hasErr(errs, "expected Series"));
	}

	public function testValueTypedSeriesOk() {
		var errs = MuseScript.check('{
			@strategy("x")
			@param("fast", 8)
			@on(bar) {
				var x = sma(close, fast);
			}
		}');
		Assert.isFalse(hasErr(errs, "expected Series"));
		Assert.isFalse(hasErr(errs, "expected Window"));
	}

	public function testNestedSeriesTypesOk() {
		var prog = MuseScript.lower('{
			@strategy("x")
			@on(bar) { var y = sma(ema(close, 8), 21); }
		}');
		var errs = new MuseChecker().check(prog);
		Assert.isFalse(hasErr(errs, "expected Series"));
	}

	public function testWhenRequiresBool() {
		var prog = new MuseParser().parse('strategy X {
			onBar { when 1: long(); }
		}');
		var errs = new MuseChecker().check(prog);
		Assert.isTrue(hasErr(errs, "Bool"));
	}

	public function testTypeOfApi() {
		var tc = new musescript.checker.TypeChecker();
		Assert.isTrue(tc.canAssign(musescript.types.MuseType.TPrice, musescript.types.MuseType.TScalar));
		Assert.isFalse(tc.canAssign(musescript.types.MuseType.TBool, musescript.types.MuseType.TSeries));
		Assert.isTrue(Type.enumEq(tc.typeOf(EConst(CString("muse"))), musescript.types.MuseType.TString));
		Assert.isTrue(Type.enumEq(
			tc.typeOf(EArrayDecl([EConst(CFloat(1.0)), EConst(CFloat(2.0))])),
			musescript.types.MuseType.TVector
		));
		Assert.isTrue(Type.enumEq(
			tc.typeOf(EArray(EArrayDecl([EConst(CFloat(1.0))]), EConst(CInt(0)))),
			musescript.types.MuseType.TScalar
		));
	}

	public function testWindowAndStringSignatures() {
		var errs = MuseScript.check('strategy TypedBuiltins {
			onBar {
				xs = window(close, 3)
				x = xs[0]
				bars = ohlcv_window(2)
				open0 = bars[0]
				label = str_concat("muse", "script")
				part = str_slice(label, 0, 4)
				when str_contains(part, "muse") && str_len(label) > 0: long()
			}
		}');
		Assert.isFalse(hasErr(errs, "Vector"));
		Assert.isFalse(hasErr(errs, "String"));
		Assert.isFalse(hasErr(errs, "expected"));
	}

	public function testRuntimeBuiltinsHaveTypedSignatures() {
		var vars:Map<String, Dynamic> = new Map();
		TradeBuiltins.install(vars, new HarnessContext());
		for (name => value in vars) {
			if (Reflect.isFunction(value))
				Assert.notNull(musescript.types.BuiltinSigs.get(name), 'missing BuiltinSig for $name');
		}
	}

	public function testWindowLadderReject() {
		var errs = MuseScript.check('{
			@strategy("x")
			@on(bar) { var x = sma("close", 7); }
		}');
		Assert.isTrue(hasErr(errs, "Fib ladder") || hasErr(errs, "Window"));
	}

	function hasErr(errs:Array<String>, needle:String):Bool {
		for (e in errs) if (e.indexOf("error:") == 0 && e.indexOf(needle) >= 0) return true;
		return false;
	}
}

class TestTypedSurface extends Test {
	public function testParseStrategySurface() {
		var src = '
strategy MaCross {
  param fast: Window = 10
  param slow: Window = 21
  maFast = sma(close, fast)
  maSlow = sma(close, slow)
  onBar {
    when crossover(maFast, maSlow): long()
    when crossunder(maFast, maSlow): flat()
  }
}';
		var prog = new MuseParser().parse(src);
		Assert.isTrue(prog.decls.length >= 3); // params + strategy
		var hasStrat = false;
		for (d in prog.decls) switch (d) {
			case StrategyDecl("MaCross", _): hasStrat = true;
			default:
		}
		Assert.isTrue(hasStrat);
	}

	public function testPipeSugar() {
		var prog = new MuseParser().parse('strategy P {
			onBar { x = close |> sma(10); }
		}');
		var printed = new musescript.compile.MusePrinter().printProgram(prog);
		Assert.isTrue(printed.indexOf("sma") >= 0);
	}

	public function testModuleUse() {
		var src = '
module Guard(pct: Scalar = 0.05) {
  onBar { when close < 0: flat(); }
}
strategy S {
  use Guard(pct = 0.05)
  onBar { when crossover(sma(close, 8), sma(close, 21)): long(); }
}';
		var prog = MuseScript.lower(src);
		var hasUse = false;
		for (d in prog.decls) switch (d) {
			case StrategyDecl(_, body):
				for (s in body) switch (s) {
					case Use(_, _): hasUse = true;
					default:
				}
			default:
		}
		Assert.isFalse(hasUse); // expanded away
	}

	public function testFormatRoundTrip() {
		var src = 'strategy T { param n: Window = 8\nonBar { when true: long() } }';
		var fmt = MuseScript.format(src);
		Assert.isTrue(fmt.indexOf("strategy T") >= 0);
		var again = MuseScript.parse(fmt);
		Assert.notNull(again);
	}

	public function testLegacyStillParses() {
		var prog = new MuseParser().parse('{
			@strategy("ma_cross")
			@param("fast", 10)
			@on(bar) { var x = sma("close", fast); }
		}');
		Assert.isTrue(prog.decls.length >= 1);
	}
}

class TestMetaTier extends Test {
	public function testTemplateExpand() {
		var src = '
template goldenCross(fast: Window, slow: Window) -> Bool {
  crossover(sma(close, fast), sma(close, slow))
}
strategy X {
  onBar { when goldenCross(8, 21): long() }
}';
		var prog = MuseScript.lower(src);
		var printer = new musescript.compile.MusePrinter();
		var out = printer.printProgram(prog);
		Assert.isTrue(out.indexOf("crossover") >= 0);
		Assert.isTrue(out.indexOf("goldenCross") < 0);
	}

	public function testTemplateDepthBound() {
		var threw = false;
		try {
			var src = '
template boom(x: Scalar) -> Scalar { boom(x) }
strategy X { onBar { y = boom(1) } }
';
			MuseScript.lower(src);
		} catch (_:Dynamic) {
			threw = true;
		}
		Assert.isTrue(threw);
	}

	public function testPipelineParses() {
		var prog = new MuseParser().parse('pipeline discover {
  sample(u, 10);
  optimize(sharpe);
}');
		var hasMacro = false;
		for (d in prog.decls) switch (d) {
			case MacroDecl(_, _): hasMacro = true;
			default:
		}
		Assert.isTrue(hasMacro);
	}

	public function testPaletteExport() {
		var p:Dynamic = MuseScript.palette();
		Assert.equals("musegene.palette/1", Reflect.field(p, "schema"));
	}
}

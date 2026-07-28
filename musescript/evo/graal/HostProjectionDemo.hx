package musescript.evo.graal;

import musescript.evo.Fitness;
import musescript.evo.HostProjectionDemoCore;
import musescript.evo.HostProjectionDemoCore.HostProjDemoResult;
import musescript.evo.ProjectionProvider;
import musescript.evo.StrategyGenome;
import musescript.evo.graal.SwingExterns.JFrame;
import musescript.evo.graal.SwingExterns.JPanel;
import musescript.evo.graal.SwingExterns.Dimension;
import musescript.evo.graal.SwingExterns.Color;
import musescript.evo.graal.SwingExterns.BasicStroke;
import musescript.evo.graal.SwingExterns.Font;
import musescript.evo.graal.SwingExterns.RenderingHints;
import musescript.evo.graal.SwingExterns.Graphics;
import musescript.evo.graal.SwingExterns.Graphics2D;
import musescript.evo.graal.SwingExterns.BorderLayout;
import musescript.evo.graal.SwingExterns.FlowLayout;
import musescript.evo.graal.SwingExterns.LayoutPanel;
import musescript.evo.graal.SwingExterns.JButton;
import musescript.evo.graal.SwingExterns.JLabel;
import musescript.evo.graal.SwingExterns.ActionFn;
import musescript.ew.EwForecastHost;
import musescript.ew.ForecastCloud;
import musescript.harness.Bar;

/**
 * JVM GUI viz demo for EW host projections — same SwingExterns stack as
 * `EvoDashboardWindow` / `CorpusEvoRun --gui` (the project's jvm-gui-viz path).
 *
 * Unlike a one-shot snapshot, the window streams bars through LatticeForecastHost /
 * McmcForecastHost (`onBar` → `cloudAt`), reveals close + cloud band + projection
 * columns + equity in lockstep, then auto-loops — so it feels alive like CorpusEvoRun.
 *
 * Launch (from repo root, after `haxe build-host-proj-demo.hxml`):
 *
 * ```powershell
 * $env:JAVA_HOME = "C:\Users\epiki\graalvm\graalvm-community-25.1.3"  # or your Graal/JDK
 * $JAVA = Join-Path $env:JAVA_HOME "bin\java.exe"
 * $CP = (Get-Content graal\cp.txt -Raw).Trim()
 * & $JAVA --sun-misc-unsafe-memory-access=allow -cp "$CP;build\jvm\host-proj-demo.jar" `
 *   musescript.evo.graal.HostProjectionDemo --host mcmc
 * ```
 *
 * Flags: `--host lattice|mcmc` (default lattice), `--headless` (print only, no window).
 */
class HostProjectionDemo {
	static function main() {
		var hostKind = argStr("--host", "lattice");
		if (hostKind != "lattice" && hostKind != "mcmc") hostKind = "lattice";
		var headless = argFlag("--headless");

		var r = HostProjectionDemoCore.run(hostKind);
		HostProjectionDemoCore.printResult(r);

		if (headless) {
			Sys.exit(r.ok && Math.isFinite(r.projScore) ? 0 : 1);
			return;
		}

		var win = new HostProjGui("EW Host Projection Demo — " + hostKind);
		win.beginLive(hostKind);
		// Drive animation from the main thread (same pattern as CorpusEvoRun → dashboard.update).
		while (win.isOpen()) {
			win.tick();
			Sys.sleep(0.04);
		}
	}

	static function argFlag(name:String):Bool {
		var args = Sys.args();
		for (a in args) if (a == name) return true;
		return false;
	}

	static function argStr(name:String, dflt:String):String {
		var args = Sys.args();
		var i = 0;
		while (i < args.length - 1) {
			if (args[i] == name) return args[i + 1];
			i++;
		}
		return dflt;
	}
}

/**
 * Live host-projection dashboard: streams bars, paints price/cloud/columns/equity, auto-replays.
 */
class HostProjGui {
	var frame:JFrame;
	var panel:HostProjChart;
	var status:JLabel;
	var pauseBtn:JButton;
	var open:Bool = true;
	var playing:Bool = true;
	var hostKind:String = "lattice";

	var bars:Array<Bar> = [];
	var clouds:Array<ForecastCloud> = [];
	var colP50:Array<Float> = [];
	var colSpread:Array<Float> = [];
	var colEntropy:Array<Float> = [];
	var equity:Array<Float> = [];
	var host:Null<EwForecastHost> = null;
	var provider:Null<ProjectionProvider> = null;
	var genome:Null<StrategyGenome> = null;
	var cursor:Int = 0;
	var pass:Int = 0;
	var holdFrames:Int = 0;
	var sharpe:Float = Math.NaN;
	var trades:Int = 0;
	var projScore:Float = Math.NaN;
	var finalEquity:Float = Math.NaN;

	public function new(title:String) {
		panel = new HostProjChart();
		panel.setPreferredSize(new Dimension(1000, 640));

		status = new JLabel("…");
		pauseBtn = new JButton("Pause");
		pauseBtn.addActionListener(new ActionFn(function() {
			playing = !playing;
			pauseBtn.setText(playing ? "Pause" : "Resume");
		}));
		var rerun = new JButton("Re-run");
		rerun.addActionListener(new ActionFn(function() {
			beginLive(hostKind);
		}));

		// No-arg FlowLayout + setAlignment — avoids Haxe Integer boxing NoSuchMethodError
		// on FlowLayout(int) under Graal/JDK 21+.
		var flow = new FlowLayout();
		flow.setAlignment(FlowLayout.LEFT);
		var controls = new LayoutPanel(flow);
		controls.add(pauseBtn);
		controls.add(rerun);
		controls.add(status);

		var root = new LayoutPanel(new BorderLayout());
		root.add(panel, BorderLayout.CENTER);
		root.add(controls, BorderLayout.SOUTH);

		frame = new JFrame(title);
		frame.setDefaultCloseOperation(JFrame.DISPOSE_ON_CLOSE);
		frame.add(root);
		frame.setSize(1020, 720);
		frame.setLocationRelativeTo(null);
		frame.setVisible(true);
	}

	public function beginLive(kind:String):Void {
		hostKind = kind;
		pass++;
		bars = HostProjectionDemoCore.syntheticBars(80);
		var graph = HostProjectionDemoCore.seededGraph();
		host = HostProjectionDemoCore.makeHost(hostKind, graph);
		provider = new ProjectionProvider(host);
		genome = HostProjectionDemoCore.demoGenome(hostKind);
		clouds = [];
		colP50 = [];
		colSpread = [];
		colEntropy = [];
		equity = [];
		cursor = 0;
		holdFrames = 0;
		sharpe = Math.NaN;
		trades = 0;
		projScore = Math.NaN;
		finalEquity = Math.NaN;
		playing = true;
		pauseBtn.setText("Pause");
		panel.hostKind = hostKind;
		panel.setFrame(bars, clouds, colP50, colSpread, colEntropy, equity, 0, pass);
		panel.repaint();
		setStatus('pass=$pass  streaming $hostKind …');
	}

	public function tick():Void {
		if (!playing) return;
		if (host == null || bars.length == 0) return;

		if (cursor < bars.length) {
			var i = cursor;
			host.onBar(bars[i], i);
			var c = host.cloudAt(i);
			clouds.push(c);
			colP50.push(ProjectionProvider.cloudField(c, "p50"));
			colSpread.push(ProjectionProvider.cloudField(c, "spread"));
			colEntropy.push(ProjectionProvider.cloudField(c, "entropy"));
			cursor++;
			panel.setFrame(bars, clouds, colP50, colSpread, colEntropy, equity, cursor, pass);
			panel.repaint();
			var mid = Math.isFinite(c.priceMid) ? fmt(c.priceMid) : "n/a";
			var spr = Math.isFinite(c.spread) ? fmt(c.spread) : "n/a";
			var ent = Math.isFinite(c.countEntropy) ? fmt(c.countEntropy) : "n/a";
			setStatus('pass=$pass  bar ${cursor}/${bars.length}  mid=$mid  spread=$spr  entropy=$ent  samples=${c.samples}');
			return;
		}

		if (equity.length == 0) {
			finishPassEval();
			panel.setFrame(bars, clouds, colP50, colSpread, colEntropy, equity, cursor, pass);
			panel.repaint();
			setStatus('pass=$pass  done  projScore=${fmt(projScore)}  sharpe=${fmt(sharpe)}  trades=$trades  equity=${fmt(finalEquity)}');
			holdFrames = 0;
			return;
		}

		holdFrames++;
		if (holdFrames > 45) beginLive(hostKind);
	}

	function finishPassEval():Void {
		if (provider == null || genome == null) return;
		provider.bindClouds(clouds, bars);
		var prev = Fitness.projectionProvider;
		Fitness.projectionProvider = provider;
		var fr = Fitness.evaluate(genome, bars, "js");
		Fitness.attachProjectionScore(fr, genome, bars, provider);
		Fitness.projectionProvider = prev;
		sharpe = fr.sharpe;
		trades = fr.trades;
		projScore = fr.projScore;
		finalEquity = fr.finalEquity;
		equity = fr.equity != null ? fr.equity : [];
	}

	public function setStatus(msg:String):Void status.setText(msg);

	public function isOpen():Bool {
		try {
			return untyped frame.isDisplayable();
		} catch (_:Dynamic) {
			return false;
		}
	}

	static function fmt(x:Float):String {
		if (!Math.isFinite(x)) return "n/a";
		return Std.string(Math.round(x * 1000) / 1000);
	}
}

/**
 * Three-row chart: (1) close + ForecastCloud band / mid / invalidate with playhead,
 * (2) projection columns p50 / spread / entropy, (3) equity curve after the pass eval.
 */
private class HostProjChart extends JPanel {
	public var hostKind:String = "lattice";
	var bars:Array<Bar> = [];
	var clouds:Array<ForecastCloud> = [];
	var colP50:Array<Float> = [];
	var colSpread:Array<Float> = [];
	var colEntropy:Array<Float> = [];
	var equity:Array<Float> = [];
	var reveal:Int = 0;
	var pass:Int = 0;

	static var COL_BG = new Color(252, 252, 251);
	static var COL_TEXT = new Color(11, 11, 11);
	static var COL_MUTED = new Color(82, 81, 78);
	static var COL_CLOSE = new Color(42, 120, 214);
	static var COL_BAND = new Color(180, 200, 220);
	static var COL_MID = new Color(235, 104, 52);
	static var COL_INV = new Color(180, 60, 60);
	static var COL_GRID = new Color(226, 224, 216);
	static var COL_P50 = new Color(42, 120, 214);
	static var COL_SPREAD = new Color(235, 104, 52);
	static var COL_ENT = new Color(27, 175, 122);
	static var COL_EQ = new Color(74, 58, 167);
	static var COL_PLAY = new Color(180, 60, 60);

	public function new() {
		super();
		setBackground(COL_BG);
	}

	public function setFrame(
		b:Array<Bar>, c:Array<ForecastCloud>,
		p50:Array<Float>, spr:Array<Float>, ent:Array<Float>,
		eq:Array<Float>, rev:Int, p:Int
	):Void {
		bars = b;
		clouds = c;
		colP50 = p50;
		colSpread = spr;
		colEntropy = ent;
		equity = eq;
		reveal = rev;
		pass = p;
	}

	override public function paintComponent(g:Graphics):Void {
		super.paintComponent(g);
		var g2:Graphics2D = cast g;
		g2.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);

		var W = 1000, H = 640;
		g2.setColor(COL_BG);
		g2.fillRect(0, 0, W, H);

		var padL = 56, padR = 20;
		var priceTop = 36, priceH = 280;
		var colTop = priceTop + priceH + 28, colH = 110;
		var eqTop = colTop + colH + 28, eqH = 110;

		g2.setColor(COL_TEXT);
		g2.setFont(new Font("SansSerif", Font.BOLD, 15));
		g2.drawString("EW host projection — " + hostKind + "  (pass " + pass + ")", padL, 22);

		var nShow = reveal < 2 ? reveal : reveal;
		if (bars.length < 2 || nShow < 2) {
			g2.setColor(COL_MUTED);
			g2.setFont(new Font("SansSerif", Font.PLAIN, 13));
			g2.drawString("Streaming bars through host…", padL, 60);
			return;
		}

		var n = nShow > bars.length ? bars.length : nShow;
		var nCloud = clouds.length < n ? clouds.length : n;

		// --- price + cloud ---
		var lo = Math.POSITIVE_INFINITY;
		var hi = Math.NEGATIVE_INFINITY;
		for (i in 0...n) {
			var b = bars[i];
			if (b.low < lo) lo = b.low;
			if (b.high > hi) hi = b.high;
		}
		for (i in 0...nCloud) {
			var c = clouds[i];
			if (Math.isFinite(c.priceLo) && c.priceLo < lo) lo = c.priceLo;
			if (Math.isFinite(c.priceHi) && c.priceHi > hi) hi = c.priceHi;
			if (Math.isFinite(c.invalidatePrice)) {
				if (c.invalidatePrice < lo) lo = c.invalidatePrice;
				if (c.invalidatePrice > hi) hi = c.invalidatePrice;
			}
		}
		if (!(hi > lo)) { lo = 0; hi = 1; }
		var span = hi - lo;
		lo -= span * 0.05;
		hi += span * 0.05;
		span = hi - lo;
		var plotW = W - padL - padR;
		var xDen = bars.length > 1 ? bars.length - 1 : 1;

		function xOf(i:Int):Int return padL + Std.int(i / xDen * plotW);
		function yPrice(px:Float):Int return priceTop + Std.int((hi - px) / span * priceH);

		drawGrid(g2, padL, priceTop, plotW, priceH, hi, span);
		g2.setColor(COL_BAND);
		for (i in 0...nCloud) {
			var c = clouds[i];
			if (!(Math.isFinite(c.priceLo) && Math.isFinite(c.priceHi))) continue;
			var y1 = yPrice(c.priceHi);
			var y2 = yPrice(c.priceLo);
			if (y2 < y1) { var t = y1; y1 = y2; y2 = t; }
			g2.fillRect(xOf(i), y1, 3, Std.int(Math.max(1, y2 - y1)));
		}
		g2.setColor(COL_CLOSE);
		g2.setStroke(new BasicStroke(1.5));
		for (i in 1...n)
			g2.drawLine(xOf(i - 1), yPrice(bars[i - 1].close), xOf(i), yPrice(bars[i].close));

		var last:ForecastCloud = null;
		var li = nCloud - 1;
		while (li >= 0) {
			if (clouds[li].samples > 0 && Math.isFinite(clouds[li].priceMid)) {
				last = clouds[li];
				break;
			}
			li--;
		}
		if (last != null) {
			if (Math.isFinite(last.priceMid)) {
				g2.setColor(COL_MID);
				var ym = yPrice(last.priceMid);
				g2.drawLine(padL, ym, padL + plotW, ym);
			}
			if (Math.isFinite(last.invalidatePrice)) {
				g2.setColor(COL_INV);
				var yi = yPrice(last.invalidatePrice);
				g2.drawLine(padL, yi, padL + plotW, yi);
			}
		}
		// Playhead
		var px = xOf(n - 1);
		g2.setColor(COL_PLAY);
		g2.setStroke(new BasicStroke(1.0));
		g2.drawLine(px, priceTop, px, priceTop + priceH);
		g2.setFont(new Font("SansSerif", Font.PLAIN, 11));
		g2.setColor(COL_MUTED);
		g2.drawString("close · band · mid · invalidate", padL, priceTop + priceH + 16);

		// --- projection columns ---
		g2.setColor(COL_TEXT);
		g2.setFont(new Font("SansSerif", Font.BOLD, 12));
		g2.drawString("Projection columns (p50 / spread / entropy)", padL, colTop - 6);
		var third = Std.int(plotW / 3);
		drawSpark(g2, colP50, nCloud, padL, colTop, third - 8, colH, COL_P50, "p50");
		drawSpark(g2, colSpread, nCloud, padL + third, colTop, third - 8, colH, COL_SPREAD, "spread");
		drawSpark(g2, colEntropy, nCloud, padL + 2 * third, colTop, third - 8, colH, COL_ENT, "entropy");

		// --- equity ---
		g2.setColor(COL_TEXT);
		g2.setFont(new Font("SansSerif", Font.BOLD, 12));
		g2.drawString(equity.length > 0 ? "Strategy equity (after host decorate + Fitness)" : "Strategy equity — evaluating at end of pass…", padL, eqTop - 6);
		if (equity.length > 1) {
			var eqN = equity.length < n ? equity.length : n;
			drawSpark(g2, equity, eqN, padL, eqTop, plotW, eqH, COL_EQ, "equity");
		} else {
			g2.setColor(COL_MUTED);
			g2.setFont(new Font("SansSerif", Font.PLAIN, 11));
			g2.drawString("Waiting for full tape + Fitness.evaluate…", padL, eqTop + 24);
		}
	}

	function drawGrid(g2:Graphics2D, x:Int, y:Int, w:Int, h:Int, hi:Float, span:Float):Void {
		g2.setColor(COL_GRID);
		for (gi in 0...5) {
			var yy = y + Std.int(gi / 4.0 * h);
			g2.drawLine(x, yy, x + w, yy);
			g2.setColor(COL_MUTED);
			g2.setFont(new Font("SansSerif", Font.PLAIN, 10));
			g2.drawString(Std.string(Math.round((hi - gi / 4.0 * span) * 10) / 10), 8, yy + 4);
			g2.setColor(COL_GRID);
		}
	}

	function drawSpark(
		g2:Graphics2D, series:Array<Float>, n:Int,
		x:Int, y:Int, w:Int, h:Int, col:Color, label:String
	):Void {
		g2.setColor(COL_MUTED);
		g2.setFont(new Font("SansSerif", Font.PLAIN, 10));
		g2.drawString(label, x, y + 12);
		if (n < 2) return;
		var lo = Math.POSITIVE_INFINITY;
		var hi = Math.NEGATIVE_INFINITY;
		var count = 0;
		for (i in 0...n) {
			var v = series[i];
			if (!Math.isFinite(v)) continue;
			count++;
			if (v < lo) lo = v;
			if (v > hi) hi = v;
		}
		if (count < 2 || !(hi > lo)) {
			if (count >= 1 && Math.isFinite(lo)) { hi = lo + 1; }
			else return;
		}
		var span = hi - lo;
		if (span <= 0) span = 1;
		function yy(v:Float):Int return y + 16 + Std.int((hi - v) / span * (h - 20));
		function xx(i:Int):Int return x + Std.int(i / (n - 1) * w);
		g2.setColor(col);
		g2.setStroke(new BasicStroke(1.4));
		var prevI = -1;
		var prevV = Math.NaN;
		for (i in 0...n) {
			var v = series[i];
			if (!Math.isFinite(v)) continue;
			if (prevI >= 0)
				g2.drawLine(xx(prevI), yy(prevV), xx(i), yy(v));
			prevI = i;
			prevV = v;
		}
	}
}

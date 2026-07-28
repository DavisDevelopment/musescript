package musescript.evo.graal;

import musescript.evo.HostProjectionDemoCore;
import musescript.evo.HostProjectionDemoCore.HostProjDemoResult;
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
import musescript.harness.Bar;
import musescript.ew.ForecastCloud;

/**
 * JVM GUI viz demo for EW host projections — same SwingExterns stack as
 * `EvoDashboardWindow` / `CorpusEvoRun --gui` (the project's jvm-gui-viz path).
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
		win.setResult(r);
		win.setStatus(statusLine(r));
		// Keep JVM process alive while the window is open (same pattern as CorpusEvoRun --gui).
		while (win.isOpen()) Sys.sleep(0.25);
	}

	static function statusLine(r:HostProjDemoResult):String {
		return 'projScore=${fmt(r.projScore)}  sharpe=${fmt(r.sharpe)}  trades=${r.trades}  '
			+ 'entropy=${fmt(r.cloudEntropy)}  spread=${fmt(r.cloudSpread)}  inv=${fmt(r.cloudInv)}';
	}

	static function fmt(x:Float):String {
		if (!Math.isFinite(x)) return "n/a";
		return Std.string(Math.round(x * 1000) / 1000);
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
 * Fixed-layout chart panel (same SwingExterns / paintComponent style as EvoDashboardWindow).
 * Shows close + ForecastCloud band / mid / invalidate for the demo tape.
 */
class HostProjGui {
	var frame:JFrame;
	var panel:HostProjChart;
	var status:JLabel;
	var open:Bool = true;

	public function new(title:String) {
		panel = new HostProjChart();
		panel.setPreferredSize(new Dimension(960, 480));

		status = new JLabel("…");
		var rerun = new JButton("Re-run");
		rerun.addActionListener(new ActionFn(function() {
			var r = HostProjectionDemoCore.run(panel.hostKind);
			setResult(r);
			setStatus('projScore=${r.projScore} sharpe=${r.sharpe} trades=${r.trades}');
		}));

		var controls = new LayoutPanel(new FlowLayout(FlowLayout.LEFT));
		controls.add(rerun);
		controls.add(status);

		var root = new LayoutPanel(new BorderLayout());
		root.add(panel, BorderLayout.CENTER);
		root.add(controls, BorderLayout.SOUTH);

		frame = new JFrame(title);
		frame.setDefaultCloseOperation(JFrame.DISPOSE_ON_CLOSE);
		frame.add(root);
		frame.setSize(980, 560);
		frame.setLocationRelativeTo(null);
		frame.setVisible(true);
	}

	public function setResult(r:HostProjDemoResult):Void {
		panel.hostKind = r.hostKind;
		panel.setData(r.bars, r.clouds);
		panel.repaint();
	}

	public function setStatus(msg:String):Void status.setText(msg);

	public function isOpen():Bool {
		// DISPOSE_ON_CLOSE: treat as closed once the frame is no longer displayable.
		try {
			return untyped frame.isDisplayable();
		} catch (_:Dynamic) {
			return false;
		}
	}
}

private class HostProjChart extends JPanel {
	public var hostKind:String = "lattice";
	var bars:Array<Bar> = [];
	var clouds:Array<ForecastCloud> = [];

	static var COL_BG = new Color(252, 252, 251);
	static var COL_TEXT = new Color(11, 11, 11);
	static var COL_MUTED = new Color(82, 81, 78);
	static var COL_CLOSE = new Color(42, 120, 214);
	static var COL_BAND = new Color(180, 200, 220);
	static var COL_MID = new Color(235, 104, 52);
	static var COL_INV = new Color(180, 60, 60);
	static var COL_GRID = new Color(226, 224, 216);

	public function new() {
		super();
		setBackground(COL_BG);
	}

	public function setData(b:Array<Bar>, c:Array<ForecastCloud>):Void {
		bars = b;
		clouds = c;
	}

	override public function paintComponent(g:Graphics):Void {
		super.paintComponent(g);
		var g2:Graphics2D = cast g;
		g2.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);

		// Fixed layout like EvoDashboardWindow (preferred size 960x480).
		var padL = 56, padR = 20, padT = 40, padB = 40;
		var plotW = 960 - padL - padR;
		var plotH = 480 - padT - padB;

		g2.setColor(COL_BG);
		g2.fillRect(0, 0, 980, 520);

		g2.setColor(COL_TEXT);
		g2.setFont(new Font("SansSerif", Font.BOLD, 16));
		g2.drawString("EW host projection cloud (" + hostKind + ")", padL, 24);

		if (bars.length < 2) {
			g2.setColor(COL_MUTED);
			g2.drawString("No tape", padL, 60);
			return;
		}

		var lo = Math.POSITIVE_INFINITY;
		var hi = Math.NEGATIVE_INFINITY;
		for (b in bars) {
			if (b.low < lo) lo = b.low;
			if (b.high > hi) hi = b.high;
		}
		var n = bars.length < clouds.length ? bars.length : clouds.length;
		for (i in 0...n) {
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

		function xOf(i:Int):Int return padL + Std.int(i / (bars.length - 1) * plotW);
		function yOf(px:Float):Int return padT + Std.int((hi - px) / span * plotH);

		g2.setColor(COL_GRID);
		for (gi in 0...5) {
			var yy = padT + Std.int(gi / 4.0 * plotH);
			g2.drawLine(padL, yy, padL + plotW, yy);
			g2.setColor(COL_MUTED);
			g2.setFont(new Font("SansSerif", Font.PLAIN, 11));
			g2.drawString(Std.string(Math.round((hi - gi / 4.0 * span) * 10) / 10), 8, yy + 4);
			g2.setColor(COL_GRID);
		}

		g2.setColor(COL_BAND);
		for (i in 0...n) {
			var c = clouds[i];
			if (!(Math.isFinite(c.priceLo) && Math.isFinite(c.priceHi))) continue;
			var y1 = yOf(c.priceHi);
			var y2 = yOf(c.priceLo);
			if (y2 < y1) { var t = y1; y1 = y2; y2 = t; }
			g2.fillRect(xOf(i), y1, 2, Std.int(Math.max(1, y2 - y1)));
		}

		g2.setColor(COL_CLOSE);
		g2.setStroke(new BasicStroke(1.5));
		for (i in 1...bars.length)
			g2.drawLine(xOf(i - 1), yOf(bars[i - 1].close), xOf(i), yOf(bars[i].close));

		var last:ForecastCloud = null;
		var li = n - 1;
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
				var ym = yOf(last.priceMid);
				g2.drawLine(padL, ym, padL + plotW, ym);
			}
			if (Math.isFinite(last.invalidatePrice)) {
				g2.setColor(COL_INV);
				var yi = yOf(last.invalidatePrice);
				g2.drawLine(padL, yi, padL + plotW, yi);
			}
		}

		g2.setColor(COL_MUTED);
		g2.setFont(new Font("SansSerif", Font.PLAIN, 11));
		var ent = last != null && Math.isFinite(last.countEntropy)
			? Std.string(Math.round(last.countEntropy * 100) / 100) : "n/a";
		g2.drawString("close · band · mid · invalidate   | entropy=" + ent, padL, padT + plotH + 28);
	}
}

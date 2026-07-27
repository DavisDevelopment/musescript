package musescript.evo.graal;

import musescript.evo.graal.SwingExterns.JFrame;
import musescript.evo.graal.SwingExterns.JPanel;
import musescript.evo.graal.SwingExterns.JComponent;
import musescript.evo.graal.SwingExterns.Dimension;
import musescript.evo.graal.SwingExterns.Color;
import musescript.evo.graal.SwingExterns.BasicStroke;
import musescript.evo.graal.SwingExterns.Font;
import musescript.evo.graal.SwingExterns.RenderingHints;
import musescript.evo.graal.SwingExterns.Graphics;
import musescript.evo.graal.SwingExterns.Graphics2D;
import musescript.evo.graal.SwingExterns.BorderLayout;
import musescript.evo.graal.SwingExterns.LayoutPanel;
import musescript.evo.graal.SwingExterns.JButton;
import musescript.evo.graal.SwingExterns.JLabel;
import musescript.evo.graal.SwingExterns.ActionFn;

/**
 * A native Swing window CorpusEvoRun updates directly, once per generation -- genuinely live
 * (the JVM process's own GUI thread repaints it), no artifact polling/republishing workaround
 * needed. Off by default (`--gui`); every existing headless run is completely unaffected.
 *
 * Four panels, 2x2: (1) best/mean fitness trajectory across generations, (2) MAP-Elites niches
 * occupied over generations, (3) the CURRENT generation's full population fitness distribution
 * (every genome, sorted -- not just best/mean) so a single generation's shape is visible, and
 * (4) the MAP-Elites niche grid itself (48 cells, colored by fitness) refreshed every generation.
 * (3)/(4) are the "per-agent" detail: individual genome identity isn't stable/meaningful across
 * generations in a GA (crossover/mutation constantly replace population members), so per-agent
 * detail is shown as a per-GENERATION snapshot of the whole population/archive instead of trying
 * to track one genome's history across time.
 *
 * Every panel carries axis gridlines + numeric labels and a color-swatch legend -- this is a
 * read-once dashboard for a human watching a run progress, not a self-explanatory encoding.
 *
 * Deliberately NOT EDT-safe (Swing calls are normally required to happen on the Event Dispatch
 * Thread via SwingUtilities.invokeLater) -- this is a short-lived internal dev-tool window
 * updated from CorpusEvoRun's single main thread, not a production GUI app serving concurrent
 * event sources, so the usual EDT-safety machinery would be pure overhead here.
 */
class EvoDashboardWindow {
	var frame:JFrame;
	var panel:EvoChartPanel;
	var pauseBtn:JButton;
	var pauseStatusLabel:JLabel;
	/** Mutated only by `pauseBtn`'s own click handler (EDT), read by the main evolution thread in
	 * `isPaused`/`waitForResume` -- see that doc comment for why a plain poll, not a Deque
	 * handoff. Off by default: the run behaves exactly as it always has (charts-only, never
	 * blocking) unless this specific button is clicked, which is the whole point -- pausing is a
	 * deliberate, at-will human action, never a standing mode. */
	var paused:Bool = false;

	public function new(title:String, ?competePanels:Bool = false) {
		panel = new EvoChartPanel();
		panel.competeEnabled = competePanels;
		panel.setPreferredSize(new Dimension(1160, competePanels ? 1400 : 900));

		pauseBtn = new JButton("Pause");
		pauseBtn.addActionListener(new ActionFn(togglePause));
		pauseStatusLabel = new JLabel("running -- click Pause to intervene (edit/select from the population) at the next generation boundary");

		var controls = new LayoutPanel(new BorderLayout());
		controls.add(pauseBtn, BorderLayout.WEST);
		controls.add(pauseStatusLabel, BorderLayout.CENTER);

		var root = new LayoutPanel(new BorderLayout());
		root.add(panel, BorderLayout.CENTER);
		root.add(controls, BorderLayout.SOUTH);

		frame = new JFrame(title);
		frame.setDefaultCloseOperation(JFrame.DISPOSE_ON_CLOSE);
		frame.add(root);
		frame.setSize(1180, competePanels ? 1480 : 980);
		frame.setLocationRelativeTo(null);
		frame.setVisible(true);
	}

	function togglePause():Void {
		paused = !paused;
		pauseBtn.setText(paused ? "Resume" : "Pause");
		pauseStatusLabel.setText(paused
			? "pausing at the next generation boundary -- population/editor window will open"
			: "running -- click Pause to intervene (edit/select from the population) at the next generation boundary");
	}

	/** Read by CorpusEvoRun's main thread at each generation boundary. */
	public function isPaused():Bool return paused;

	/** Blocks the CALLING (main evolution) thread until `paused` flips back to false -- see
	 * HumanLoopWindow's identical `waitForResume` doc comment for why this is a plain poll. */
	public function waitForResume():Void {
		while (paused) Sys.sleep(0.2);
	}

	/** `popFitness`: every valid genome's fitness THIS generation (unsorted, panel sorts it).
	 * `nicheCells`: parallel arrays of `key` ("tradeFreq_hold_bias") and `fitness` for every
	 * OCCUPIED MAP-Elites cell this generation -- from `EliteArchive.summary()`.
	 * `isPerf`: raw (pre-parsimony) Sharpe per unique genome this generation (in-sample).
	 * `oosPerf`: same, out-of-sample, but only on generations CorpusEvoRun actually re-sampled
	 * OOS for (see its `--gui-oos-every` doc comment) -- pass `null` on skipped generations and
	 * the panel keeps showing the last real sample rather than going blank.
	 * `isBenchmark`/`oosBenchmark`: buy-and-hold Sharpe on the same tape/cost, computed once. */
	public function update(gen:Int, best:Float, mean:Float, niches:Int, champion:String,
			popFitness:Array<Float>, nicheKeys:Array<String>, nicheFitness:Array<Float>,
			isPerf:Array<Float>, oosPerf:Null<Array<Float>>, isBenchmark:Float, oosBenchmark:Float):Void {
		panel.push(gen, best, mean, niches, champion, popFitness, nicheKeys, nicheFitness,
			isPerf, oosPerf, isBenchmark, oosBenchmark);
		panel.repaint();
	}

	/** Rivalry / Foundry / deme strip — gen-boundary only; no-op when compete panels are off. */
	public function updateCompete(state:CompeteVizState):Void {
		if (!panel.competeEnabled) return;
		panel.pushCompete(state);
		panel.repaint();
	}

	public function close():Void frame.dispose();
}

private class EvoChartPanel extends JPanel {
	var gens:Array<Int> = [];
	var bests:Array<Float> = [];
	var means:Array<Float> = [];
	var nichesHist:Array<Int> = [];
	var champion:String = "";
	var niches:Int = 0;
	var gen:Int = 0;
	var best:Float = 0;
	var mean:Float = 0;
	var popFitness:Array<Float> = [];
	var nicheKeys:Array<String> = [];
	var nicheFitness:Array<Float> = [];
	var isPerf:Array<Float> = [];
	var oosPerf:Array<Float> = [];
	var oosSampledAtGen:Int = -1;
	var isBenchmark:Float = 0;
	var oosBenchmark:Float = 0;
	public var competeEnabled:Bool = false;
	var compete:CompeteVizState = CompeteVizState.empty();

	static inline var TOTAL_CELLS = 48; // 4 (tradeFreq) x 4 (hold) x 3 (bias) -- see MapElites.hx
	static var TRADEFREQ_LABELS = ["rare", "occasional", "frequent", "scalper"];
	static var HOLD_LABELS = ["very-short", "swing", "position", "long-hold"];
	static var BIAS_LABELS = ["short", "mixed", "long"];

	// Palette (dataviz skill's validated default -- categorical slots 1/2/3, light-mode hex)
	static var COL_TEXT = new Color(11, 11, 11);
	static var COL_MUTED = new Color(82, 81, 78);
	static var COL_BORDER = new Color(226, 224, 216);
	static var COL_BEST = new Color(42, 120, 214);   // slot 1 blue
	static var COL_MEAN = new Color(235, 104, 52);   // slot 2 orange
	static var COL_NICHE = new Color(27, 175, 122);  // slot 3 aqua
	static var COL_POP = new Color(74, 58, 167);     // slot 7 violet
	static var COL_OOS = new Color(233, 196, 106);   // slot 4-ish yellow/gold, distinct from IS blue
	static var COL_ARENA = new Color(180, 60, 60);

	public function new() {
		super();
		setBackground(new Color(252, 252, 251));
	}

	public function push(g:Int, b:Float, m:Float, n:Int, champ:String,
			pf:Array<Float>, nk:Array<String>, nf:Array<Float>,
			ip:Array<Float>, op:Null<Array<Float>>, isB:Float, oosB:Float):Void {
		gen = g; best = b; mean = m; niches = n; champion = champ;
		popFitness = pf; nicheKeys = nk; nicheFitness = nf;
		isPerf = ip; isBenchmark = isB; oosBenchmark = oosB;
		if (op != null) { oosPerf = op; oosSampledAtGen = g; }
		gens.push(g);
		bests.push(b);
		means.push(m);
		nichesHist.push(n);
	}

	public function pushCompete(state:CompeteVizState):Void {
		compete = state;
	}

	override public function paintComponent(g:Graphics):Void {
		super.paintComponent(g);
		var g2:Graphics2D = cast g;
		g2.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);

		g2.setColor(COL_TEXT);
		g2.setFont(new Font("SansSerif", Font.BOLD, 17));
		g2.drawString("MuseGene Evolution -- Live", 16, 26);
		g2.setFont(new Font("SansSerif", Font.PLAIN, 12));
		g2.setColor(COL_MUTED);
		var modeBadge = competeEnabled ? '  |  mode ${compete.mode}' : "";
		var pulseBadge = (competeEnabled && compete.arenaPulse != null && compete.arenaPulse.length > 0)
			? '  |  ${compete.arenaPulse}' : "";
		g2.drawString('generation $gen  |  best fitness ${fmt(best)}  |  mean fitness ${fmt(mean)}  |  niches $niches / $TOTAL_CELLS  |  champion "$champion"$modeBadge$pulseBadge', 16, 47);

		// Row 1: three equal columns (fitness | niches | perf-vs-benchmark), all "beside" each
		// other rather than stacked. Row 2: two wider columns (pop distribution | niche grid)
		// spanning the SAME total width as row 1's three columns combined, so both rows line up.
		var rowH = competeEnabled ? 300 : 380;
		var colW3 = 360, gap = 16;
		var x1 = 16, x2 = x1 + colW3 + gap, x3 = x2 + colW3 + gap;
		var totalW = colW3 * 3 + gap * 2;
		var colW2 = Std.int((totalW - gap) / 2);
		var y1 = 66, y2 = 66 + rowH + 24;

		lineChart(g2, x1, y1, colW3, rowH,
			[{series: bests, color: COL_BEST, label: "Best fitness"}, {series: means, color: COL_MEAN, label: "Mean fitness"}],
			"Fitness over generations", "generation", "fitness");
		lineChart(g2, x2, y1, colW3, rowH,
			[{series: [for (n in nichesHist) (n : Float)], color: COL_NICHE, label: "Niches occupied"}],
			"Behavioral diversity over generations", "generation", "niches (of " + TOTAL_CELLS + ")");
		perfVsBenchmark(g2, x3, y1, colW3, rowH);
		popDistribution(g2, x1, y2, colW2, rowH);
		nicheGrid(g2, x1 + colW2 + gap, y2, colW2, rowH);

		if (competeEnabled) {
			var y3 = y2 + rowH + 24;
			var rowH3 = 200;
			competeDemeStrip(g2, x1, y3, colW2, rowH3);
			competeArenaPanel(g2, x1 + colW2 + gap, y3, colW2, rowH3);
			var y4 = y3 + rowH3 + 24;
			var rowH4 = 180;
			competeMarketPanel(g2, x1, y4, colW2, rowH4);
			competeMetaPanel(g2, x1 + colW2 + gap, y4, colW2, rowH4);
		}
	}

	function competeDemeStrip(g2:Graphics2D, x:Int, y:Int, w:Int, h:Int):Void {
		panelTitle(g2, x, y + 2, 'Archipelago demes (n=${compete.demes.length})');
		legend(g2, x, y + 20, [
			{color: COL_BEST, label: "deme best"},
			{color: COL_MEAN, label: "deme mean"},
		]);
		var padL = 36, padR = 10, padT = 40, padB = 28;
		var plotX = x + padL, plotY = y + padT;
		var plotW = w - padL - padR, plotH = h - padT - padB;
		if (compete.demes.length == 0) {
			g2.setColor(COL_MUTED);
			g2.setFont(new Font("SansSerif", Font.PLAIN, 12));
			g2.drawString("no deme stats yet", plotX + 8, plotY + Std.int(plotH / 2));
			return;
		}
		var vals = [for (d in compete.demes) d.best];
		for (d in compete.demes) vals.push(d.mean);
		var yMin = vals[0], yMax = vals[0];
		for (v in vals) { if (v < yMin) yMin = v; if (v > yMax) yMax = v; }
		if (yMax == yMin) { yMin -= 1; yMax += 1; }
		var n = compete.demes.length;
		var barW = Math.max(4, (plotW / n) * 0.35);
		for (i in 0...n) {
			var d = compete.demes[i];
			var cx = plotX + Std.int((i + 0.5) / n * plotW);
			var by = plotY + plotH - Std.int(((d.best - yMin) / (yMax - yMin)) * plotH);
			var my = plotY + plotH - Std.int(((d.mean - yMin) / (yMax - yMin)) * plotH);
			g2.setColor(COL_BEST);
			g2.fillRect(cx - Std.int(barW), by, Std.int(barW), plotY + plotH - by);
			g2.setColor(COL_MEAN);
			g2.fillRect(cx + 1, my, Std.int(barW), plotY + plotH - my);
			g2.setColor(COL_MUTED);
			g2.setFont(new Font("SansSerif", Font.PLAIN, 9));
			g2.drawString('d${d.id}', cx - 6, y + h - 6);
		}
		if (compete.migratePulse || compete.immigrantMarkers > 0) {
			g2.setColor(COL_ARENA);
			g2.setFont(new Font("SansSerif", Font.PLAIN, 11));
			var mark = compete.immigrantMarkers > 0
				? 'immigrant markers ×${compete.immigrantMarkers}'
				: "migrate pulse";
			g2.drawString(mark, plotX + 4, plotY + 14);
		}
	}

	function competeArenaPanel(g2:Graphics2D, x:Int, y:Int, w:Int, h:Int):Void {
		panelTitle(g2, x, y + 2, "Rivalry arena / Foundry");
		g2.setFont(new Font("SansSerif", Font.PLAIN, 11));
		g2.setColor(COL_MUTED);
		var line1 = 'arena gen ${compete.arenaGen}  |  cohort ${compete.cohort}  |  faults ${compete.faults}'
			+ '  |  responses nudge=${compete.responseNudge} mate=${compete.responseMate}'
			+ '  |  rivalry-w ${fmt2(compete.rivalryWeight)}';
		g2.drawString(line1, x, y + 22);
		var padL = 36, padR = 10, padT = 48, padB = 40;
		var plotX = x + padL, plotY = y + padT;
		var plotW = w - padL - padR, plotH = h - padT - padB - 36;
		if (compete.mode == "ARENA" && compete.arenaPulse != null && compete.arenaPulse.length > 0
				&& compete.wealthRaw.length == 0) {
			g2.setColor(COL_ARENA);
			g2.setFont(new Font("SansSerif", Font.BOLD, 13));
			g2.drawString(compete.arenaPulse, plotX + 8, plotY + Std.int(plotH / 2));
		} else if (compete.wealthRaw.length == 0) {
			g2.setColor(COL_MUTED);
			g2.drawString("waiting for arena (every --arena-every gens)...", plotX + 8, plotY + Std.int(plotH / 2));
		} else {
			var sorted = compete.wealthRaw.copy();
			sorted.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
			var yMin = sorted[0], yMax = sorted[sorted.length - 1];
			if (yMax == yMin) { yMin -= 1; yMax += 1; }
			var n = sorted.length;
			var barW = Math.max(1, plotW / n);
			g2.setColor(COL_ARENA);
			for (i in 0...n) {
				var v = sorted[i];
				var bx = plotX + Std.int(i * barW);
				var by = plotY + plotH - Std.int(((v - yMin) / (yMax - yMin)) * plotH);
				g2.fillRect(bx, by, Std.int(Math.max(1, barW)), plotY + plotH - by);
			}
			g2.setColor(COL_MUTED);
			g2.setFont(new Font("SansSerif", Font.PLAIN, 10));
			g2.drawString("arena MTM wealth (sorted)", plotX, y + h - 40);
		}
		g2.setColor(COL_MUTED);
		g2.setFont(new Font("SansSerif", Font.PLAIN, 10));
		var fe = compete.foundryEvents;
		var fnote = fe.length == 0 ? "foundry: (idle)" :
			'foundry: ${fe[fe.length - 1].phase} @gen ${fe[fe.length - 1].gen} — ${fe[fe.length - 1].note}';
		g2.drawString(fnote.length > 90 ? fnote.substr(0, 87) + "..." : fnote, x, y + h - 18);
	}

	/** Market-choice bars when `--compete-symbols` / SymbolSelector routed individuals this gen. */
	function competeMarketPanel(g2:Graphics2D, x:Int, y:Int, w:Int, h:Int):Void {
		panelTitle(g2, x, y + 2, "Market choices (--compete-symbols)");
		var padL = 36, padR = 10, padT = 36, padB = 28;
		var plotX = x + padL, plotY = y + padT;
		var plotW = w - padL - padR, plotH = h - padT - padB;
		var counts = compete.marketChoices;
		if (counts == null || counts.length == 0) {
			g2.setColor(COL_MUTED);
			g2.setFont(new Font("SansSerif", Font.PLAIN, 12));
			g2.drawString("no SymbolSelector routing this run", plotX + 8, plotY + Std.int(plotH / 2));
			return;
		}
		var yMax = 1.0;
		for (c in counts) if (c > yMax) yMax = c;
		var n = counts.length;
		var barW = Math.max(8, (plotW / n) * 0.55);
		for (i in 0...n) {
			var c = counts[i];
			var cx = plotX + Std.int((i + 0.5) / n * plotW);
			var bh = Std.int((c / yMax) * plotH);
			var by = plotY + plotH - bh;
			g2.setColor(COL_NICHE);
			g2.fillRect(cx - Std.int(barW / 2), by, Std.int(barW), bh);
			g2.setColor(COL_MUTED);
			g2.setFont(new Font("SansSerif", Font.PLAIN, 10));
			g2.drawString('m$i=$c', cx - 14, y + h - 8);
		}
	}

	/** Veteran pool / POET keep-reject / immigrant markers — gen-boundary POD only. */
	function competeMetaPanel(g2:Graphics2D, x:Int, y:Int, w:Int, h:Int):Void {
		panelTitle(g2, x, y + 2, "Veterans / Poet / Immigrants");
		g2.setFont(new Font("SansSerif", Font.PLAIN, 12));
		g2.setColor(COL_TEXT);
		var lines = [
			compete.veteranCap > 0 || compete.veteranN > 0
				? 'veterans ${compete.veteranN}/${compete.veteranCap}  netInv ${fmt2(compete.veteranNetInv)}'
				: "veterans: (sequential-tape off)",
			'poet kept=${compete.poetKept}  rejected=${compete.poetRejected}',
			compete.immigrantMarkers > 0 || compete.migratePulse
				? 'immigrants: ${compete.immigrantMarkers} swapped (deme migrate)'
				: "immigrants: (no deme migrate this gen)"
		];
		var ly = y + 40;
		for (line in lines) {
			g2.drawString(line, x + 12, ly);
			ly += 28;
		}
		if (compete.mode == "FOUNDRY" && compete.arenaPulse != null && compete.arenaPulse.length > 0) {
			g2.setColor(COL_ARENA);
			g2.setFont(new Font("SansSerif", Font.BOLD, 12));
			g2.drawString(compete.arenaPulse, x + 12, ly + 8);
		}
	}

	/** Every evaluated genome's raw Sharpe this generation, in- and out-of-sample, against the
	 * buy-and-hold benchmark for the same tape/cost -- "is the population actually beating just
	 * holding the underlying" at a glance. IS is sorted low->high and refreshed every generation
	 * (free -- already computed for selection); OOS is sorted independently and only refreshed
	 * every `--gui-oos-every` generations (real backtests, not free -- see CorpusEvoRun's doc
	 * comment), so its title always states which generation it was actually sampled at. */
	function perfVsBenchmark(g2:Graphics2D, x:Int, y:Int, w:Int, h:Int):Void {
		var oosLabel = oosSampledAtGen >= 0 ? 'OOS Sharpe (sampled gen $oosSampledAtGen)' : "OOS Sharpe (not sampled yet)";
		panelTitle(g2, x, y + 2, "Genome perf. vs buy-and-hold");
		var legendBottom = legendStacked(g2, x, y + 20, [
			{color: COL_POP, label: "IS genome Sharpe (this gen)"},
			{color: COL_OOS, label: oosLabel},
			{color: COL_BEST, label: "IS benchmark"},
			{color: COL_MEAN, label: "OOS benchmark"},
		]);

		var padL = 44, padR = 10, padB = 34;
		var padT = (legendBottom - y) + 8;
		var plotX = x + padL, plotY = y + padT;
		var plotW = w - padL - padR, plotH = h - padT - padB;

		if (isPerf.length == 0) {
			g2.setColor(COL_MUTED);
			g2.setFont(new Font("SansSerif", Font.PLAIN, 12));
			g2.drawString("waiting for data...", plotX + 8, plotY + Std.int(plotH / 2));
			return;
		}

		var isSorted = isPerf.copy();
		isSorted.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		var oosSorted = oosPerf.copy();
		oosSorted.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));

		var all = isSorted.copy();
		for (v in oosSorted) all.push(v);
		all.push(isBenchmark);
		all.push(oosBenchmark);
		var yMin = all[0], yMax = all[0];
		for (v in all) { if (v < yMin) yMin = v; if (v > yMax) yMax = v; }
		if (yMax == yMin) { yMin -= 1; yMax += 1; }
		var pad = (yMax - yMin) * 0.08;
		yMin -= pad; yMax += pad;

		g2.setFont(new Font("SansSerif", Font.PLAIN, 10));
		var gridN = 4;
		for (i in 0...gridN + 1) {
			var gy = plotY + Std.int((i / gridN) * plotH);
			var val = yMax - (i / gridN) * (yMax - yMin);
			g2.setColor(COL_BORDER);
			g2.drawLine(plotX, gy, plotX + plotW, gy);
			g2.setColor(COL_MUTED);
			g2.drawString(fmt2(val), x + 2, gy + 4);
		}
		g2.setColor(COL_MUTED);
		g2.drawString("genomes sorted by Sharpe, low -> high", plotX + Std.int(plotW / 2) - 78, y + h - 2);

		function plotDots(series:Array<Float>, color:Color):Void {
			g2.setColor(color);
			var n = series.length;
			if (n == 0) return;
			for (i in 0...n) {
				var px = plotX + Std.int((n == 1 ? 0.5 : i / (n - 1)) * plotW);
				var py = plotY + plotH - Std.int(((series[i] - yMin) / (yMax - yMin)) * plotH);
				g2.fillRect(px - 2, py - 2, 4, 4);
			}
		}
		plotDots(isSorted, COL_POP);
		plotDots(oosSorted, COL_OOS);

		function benchmarkLine(v:Float, color:Color):Void {
			var by = plotY + plotH - Std.int(((v - yMin) / (yMax - yMin)) * plotH);
			g2.setColor(color);
			g2.setStroke(new BasicStroke(1.5));
			g2.drawLine(plotX, by, plotX + plotW, by);
		}
		benchmarkLine(isBenchmark, COL_BEST);
		benchmarkLine(oosBenchmark, COL_MEAN);

		g2.setColor(COL_BORDER);
		g2.drawLine(plotX, plotY, plotX, plotY + plotH);
		g2.drawLine(plotX, plotY + plotH, plotX + plotW, plotY + plotH);
	}

	// ── shared chrome ──────────────────────────────────────────────────────────────────────

	function panelTitle(g2:Graphics2D, x:Int, y:Int, title:String):Void {
		g2.setColor(COL_TEXT);
		g2.setFont(new Font("SansSerif", Font.BOLD, 13));
		g2.drawString(title, x, y);
	}

	function legend(g2:Graphics2D, x:Int, y:Int, entries:Array<{color:Color, label:String}>):Void {
		g2.setFont(new Font("SansSerif", Font.PLAIN, 11));
		var cx = x;
		for (e in entries) {
			g2.setColor(e.color);
			g2.fillRect(cx, y - 9, 10, 10);
			g2.setColor(COL_MUTED);
			g2.drawString(e.label, cx + 14, y);
			cx += 16 + textWidthEstimate(e.label) + 18;
		}
	}

	/** One entry per line -- for narrower panels/longer labels where the horizontal `legend()`
	 * would overflow the column width. Returns the y just past the last line, so the caller can
	 * continue laying out content below it. */
	function legendStacked(g2:Graphics2D, x:Int, y:Int, entries:Array<{color:Color, label:String}>):Int {
		g2.setFont(new Font("SansSerif", Font.PLAIN, 10));
		var cy = y;
		for (e in entries) {
			g2.setColor(e.color);
			g2.fillRect(x, cy - 8, 9, 9);
			g2.setColor(COL_MUTED);
			g2.drawString(e.label, x + 13, cy);
			cy += 13;
		}
		return cy;
	}

	/** No FontMetrics extern declared (kept the Swing surface minimal) -- a fixed per-character
	 * estimate is plenty precise for legend spacing at this font size. */
	function textWidthEstimate(s:String):Int return s.length * 6;

	function fmt(v:Float):String {
		var m = 10000.0;
		return Std.string(Math.ffloor(v * m + 0.5) / m);
	}

	function fmt2(v:Float):String {
		var m = 100.0;
		return Std.string(Math.ffloor(v * m + 0.5) / m);
	}

	// ── line chart (fitness trajectory / niches-over-time) ────────────────────────────────

	function lineChart(g2:Graphics2D, x:Int, y:Int, w:Int, h:Int,
			series:Array<{series:Array<Float>, color:Color, label:String}>,
			title:String, xAxisLabel:String, yAxisLabel:String):Void {
		panelTitle(g2, x, y + 2, title);
		legend(g2, x, y + 20, [for (s in series) {color: s.color, label: s.label}]);

		var padL = 52, padR = 10, padT = 34, padB = 34;
		var plotX = x + padL, plotY = y + padT;
		var plotW = w - padL - padR, plotH = h - padT - padB;

		var any = series.length > 0 ? series[0].series : [];
		if (any.length < 2) {
			g2.setColor(COL_MUTED);
			g2.setFont(new Font("SansSerif", Font.PLAIN, 12));
			g2.drawString("waiting for data...", plotX + 8, plotY + Std.int(plotH / 2));
			return;
		}

		var all:Array<Float> = [];
		for (s in series) for (v in s.series) all.push(v);
		var yMin = all[0], yMax = all[0];
		for (v in all) { if (v < yMin) yMin = v; if (v > yMax) yMax = v; }
		if (yMax == yMin) { yMin -= 1; yMax += 1; }
		var pad = (yMax - yMin) * 0.08;
		yMin -= pad; yMax += pad;

		// Y gridlines + value labels
		g2.setFont(new Font("SansSerif", Font.PLAIN, 10));
		var gridN = 4;
		for (i in 0...gridN + 1) {
			var gy = plotY + Std.int((i / gridN) * plotH);
			var val = yMax - (i / gridN) * (yMax - yMin);
			g2.setColor(COL_BORDER);
			g2.drawLine(plotX, gy, plotX + plotW, gy);
			g2.setColor(COL_MUTED);
			g2.drawString(fmt2(val), x + 2, gy + 4);
		}
		// X ticks (generation numbers)
		var n = any.length;
		var xTicks = Std.int(Math.min(6, n));
		for (i in 0...xTicks) {
			var idx = Std.int(i * (n - 1) / Math.max(1, xTicks - 1));
			var gx = plotX + Std.int((idx / (n - 1)) * plotW);
			g2.setColor(COL_MUTED);
			g2.drawString(Std.string(gens[idx]), gx - 4, plotY + plotH + 14);
		}
		g2.setColor(COL_MUTED);
		g2.drawString(xAxisLabel, plotX + Std.int(plotW / 2) - 24, y + h - 2);

		g2.setColor(COL_BORDER);
		g2.drawLine(plotX, plotY, plotX, plotY + plotH);
		g2.drawLine(plotX, plotY + plotH, plotX + plotW, plotY + plotH);

		g2.setStroke(new BasicStroke(2));
		for (s in series) drawLine(g2, plotX, plotY, plotW, plotH, s.series, yMin, yMax, s.color);

		// Value-at-latest-point label, directly on the line (selective direct label, not one
		// per point) -- makes the CURRENT number readable without cross-referencing the legend.
		g2.setFont(new Font("SansSerif", Font.PLAIN, 11));
		for (s in series) {
			var v = s.series[s.series.length - 1];
			var py = plotY + plotH - Std.int(((v - yMin) / (yMax - yMin)) * plotH);
			g2.setColor(s.color);
			g2.drawString(fmt(v), plotX + plotW - 44, py - 6);
		}
	}

	function drawLine(g2:Graphics2D, x:Int, y:Int, w:Int, h:Int, series:Array<Float>, yMin:Float, yMax:Float, color:Color):Void {
		g2.setColor(color);
		var n = series.length;
		var prevX = 0, prevY = 0;
		for (i in 0...n) {
			var px = x + Std.int((i / (n - 1)) * w);
			var py = y + h - Std.int(((series[i] - yMin) / (yMax - yMin)) * h);
			if (i > 0) g2.drawLine(prevX, prevY, px, py);
			prevX = px; prevY = py;
		}
	}

	// ── population fitness distribution (sorted bar strip, this generation) ───────────────

	function popDistribution(g2:Graphics2D, x:Int, y:Int, w:Int, h:Int):Void {
		panelTitle(g2, x, y + 2, 'Population fitness this generation (n=${popFitness.length})');
		legend(g2, x, y + 20, [{color: COL_POP, label: "genome fitness (sorted)"}]);

		var padL = 52, padR = 10, padT = 34, padB = 34;
		var plotX = x + padL, plotY = y + padT;
		var plotW = w - padL - padR, plotH = h - padT - padB;

		if (popFitness.length == 0) {
			g2.setColor(COL_MUTED);
			g2.setFont(new Font("SansSerif", Font.PLAIN, 12));
			g2.drawString("waiting for data...", plotX + 8, plotY + Std.int(plotH / 2));
			return;
		}
		var sorted = popFitness.copy();
		sorted.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		var yMin = sorted[0], yMax = sorted[sorted.length - 1];
		if (yMax == yMin) { yMin -= 1; yMax += 1; }
		var pad = (yMax - yMin) * 0.08;
		yMin -= pad; yMax += pad;

		g2.setFont(new Font("SansSerif", Font.PLAIN, 10));
		var gridN = 4;
		for (i in 0...gridN + 1) {
			var gy = plotY + Std.int((i / gridN) * plotH);
			var val = yMax - (i / gridN) * (yMax - yMin);
			g2.setColor(COL_BORDER);
			g2.drawLine(plotX, gy, plotX + plotW, gy);
			g2.setColor(COL_MUTED);
			g2.drawString(fmt2(val), x + 2, gy + 4);
		}
		g2.setColor(COL_MUTED);
		g2.drawString("genomes, sorted by fitness (low -> high)", plotX + Std.int(plotW / 2) - 90, y + h - 2);

		var zeroY = plotY + plotH - Std.int(((0.0 - yMin) / (yMax - yMin)) * plotH);
		g2.setColor(new Color(200, 198, 190));
		g2.drawLine(plotX, zeroY, plotX + plotW, zeroY);
		g2.setColor(COL_MUTED);
		g2.drawString("0", plotX + plotW + 2, zeroY + 4);

		var n = sorted.length;
		var barW = Math.max(1, plotW / n);
		g2.setColor(COL_POP);
		for (i in 0...n) {
			var v = sorted[i];
			var bx = plotX + Std.int(i * barW);
			var by1 = plotY + plotH - Std.int(((v - yMin) / (yMax - yMin)) * plotH);
			var top2 = Std.int(Math.min(by1, zeroY));
			var height = Std.int(Math.max(1, Math.abs(zeroY - by1)));
			g2.fillRect(bx, top2, Std.int(Math.max(1, barW)), height);
		}

		// Median marker -- a single, meaningful summary stat direct-labeled on the chart.
		var median = sorted[Std.int(n / 2)];
		var medY = plotY + plotH - Std.int(((median - yMin) / (yMax - yMin)) * plotH);
		g2.setColor(COL_TEXT);
		g2.drawLine(plotX, medY, plotX + plotW, medY);
		g2.setFont(new Font("SansSerif", Font.PLAIN, 10));
		g2.drawString('median ${fmt2(median)}', plotX + 4, medY - 3);

		g2.setColor(COL_BORDER);
		g2.drawLine(plotX, plotY, plotX, plotY + plotH);
		g2.drawLine(plotX, plotY + plotH, plotX + plotW, plotY + plotH);
	}

	// ── MAP-Elites niche grid (48 cells: 4 tradeFreq x 4 hold x 3 bias) ────────────────────

	function nicheGrid(g2:Graphics2D, x:Int, y:Int, w:Int, h:Int):Void {
		panelTitle(g2, x, y + 2, 'MAP-Elites behavioral niches (${nicheKeys.length} / $TOTAL_CELLS occupied)');

		var padL = 68, padR = 78, padT = 30, padB = 40;
		var plotX = x + padL, plotY = y + padT;
		var plotW = w - padL - padR, plotH = h - padT - padB;
		var cols = 12, rows = 4; // 4 tradeFreq rows x (4 hold x 3 bias, flattened) columns
		var cellW = plotW / cols, cellH = plotH / rows;

		var byKey = new Map<String, Float>();
		for (i in 0...nicheKeys.length) byKey.set(nicheKeys[i], nicheFitness[i]);
		var minF = 0.0, maxF = 0.0;
		var first = true;
		for (v in nicheFitness) {
			if (first) { minF = v; maxF = v; first = false; }
			if (v < minF) minF = v;
			if (v > maxF) maxF = v;
		}
		if (maxF == minF) { minF -= 1; maxF += 1; }

		for (tf in 0...4) {
			for (hold in 0...4) {
				for (bias in 0...3) {
					var col = hold * 3 + bias;
					var key = '${tf}_${hold}_${bias}';
					var cx = plotX + Std.int(col * cellW);
					var cy = plotY + Std.int(tf * cellH);
					var cw = Std.int(cellW) - 2, ch = Std.int(cellH) - 2;
					if (byKey.exists(key)) {
						var f = byKey.get(key);
						var t = (f - minF) / (maxF - minF);
						g2.setColor(sequentialBlue(t));
						g2.fillRect(cx, cy, cw, ch);
					} else {
						g2.setColor(new Color(240, 239, 235));
						g2.fillRect(cx, cy, cw, ch);
					}
				}
			}
		}

		// Row labels (trade frequency, left side)
		g2.setFont(new Font("SansSerif", Font.PLAIN, 10));
		g2.setColor(COL_MUTED);
		for (tf in 0...4) {
			var ty = plotY + Std.int((tf + 0.5) * cellH) + 4;
			g2.drawString(TRADEFREQ_LABELS[tf], x, ty);
		}
		g2.setFont(new Font("SansSerif", Font.PLAIN, 9));
		g2.drawString("trade freq.", x, plotY - 10);

		// Column group labels (hold period, spanning 3 bias columns each) + bias sub-labels
		for (hold in 0...4) {
			var groupX = plotX + Std.int((hold * 3 + 1.5) * cellW);
			g2.setColor(COL_MUTED);
			g2.setFont(new Font("SansSerif", Font.PLAIN, 10));
			g2.drawString(HOLD_LABELS[hold], groupX - 20, plotY + plotH + 14);
		}
		g2.setFont(new Font("SansSerif", Font.PLAIN, 8));
		for (hold in 0...4) {
			for (bias in 0...3) {
				var col = hold * 3 + bias;
				var bx = plotX + Std.int((col + 0.5) * cellW) - 6;
				g2.setColor(COL_MUTED);
				g2.drawString(BIAS_LABELS[bias], bx, plotY + plotH + 26);
			}
		}
		g2.setFont(new Font("SansSerif", Font.PLAIN, 9));
		g2.drawString("hold period (bias: short/mixed/long within each)", plotX, plotY + plotH + 38);

		// Vertical color-scale legend to the right: gradient swatches + min/max fitness labels
		var legendX = plotX + plotW + 14;
		var legendSteps = 20;
		for (i in 0...legendSteps) {
			var t = 1 - i / (legendSteps - 1);
			g2.setColor(sequentialBlue(t));
			g2.fillRect(legendX, plotY + Std.int(i / legendSteps * plotH), 16, Std.int(plotH / legendSteps) + 1);
		}
		g2.setColor(COL_BORDER);
		g2.drawLine(legendX, plotY, legendX + 16, plotY);
		g2.drawLine(legendX, plotY + plotH, legendX + 16, plotY + plotH);
		g2.setColor(COL_MUTED);
		g2.setFont(new Font("SansSerif", Font.PLAIN, 9));
		g2.drawString(fmt2(maxF), legendX + 20, plotY + 8);
		g2.drawString(fmt2(minF), legendX + 20, plotY + plotH);
		g2.drawString("fitness", legendX - 2, plotY - 4);
		g2.setColor(new Color(240, 239, 235));
		g2.fillRect(legendX, plotY + plotH + 12, 12, 10);
		g2.setColor(COL_MUTED);
		g2.drawString("empty", legendX + 16, plotY + plotH + 20);
	}

	/** Sequential single-hue ramp (light -> dark blue), grayscale/CVD-safe by construction --
	 * matches the dataviz skill's "sequential = one hue, light->dark" rule. */
	function sequentialBlue(t:Float):Color {
		var tt = Math.max(0, Math.min(1, t));
		var r = Std.int(222 - tt * 180);
		var gC = Std.int(236 - tt * 116);
		var b = Std.int(250 - tt * 36);
		return new Color(Std.int(Math.max(0, Math.min(255, r))), Std.int(Math.max(0, Math.min(255, gC))), Std.int(Math.max(0, Math.min(255, b))));
	}
}

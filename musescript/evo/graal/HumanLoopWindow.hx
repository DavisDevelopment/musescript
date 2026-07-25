package musescript.evo.graal;

import sys.thread.Deque;
import musescript.harness.Bar;
import musescript.evo.StrategyGenome;
import musescript.evo.Variation;
import musescript.evo.Fitness;
import musescript.evo.CorpusSeed;
import musescript.evo.Expand;
import musescript.evo.graal.SwingExterns;

/**
 * Human-in-the-loop POPULATION BROWSER + EDITOR -- the intervention surface that opens (or comes
 * to front) when `EvoDashboardWindow`'s own Pause button is clicked. The charted dashboard is the
 * PRIMARY, always-on window for a live run; this window is purely for what happens once paused:
 * browse the current population's scores, pick or hand-edit a genome, generate 10 mutate/
 * crossover candidates from it, and queue one for injection. Pausing/resuming itself lives on
 * `EvoDashboardWindow`, not here -- see its `isPaused`/`waitForResume`.
 *
 * THIS IS A PRACTICE RUN for the same interaction model landing in the main app/IDE later --
 * Swing here, something web-based (Monaco/CodeMirror + a real UI) there -- so the three pieces
 * that actually matter are kept cleanly separated from the Swing rendering: (1) the population
 * browser -> editor content flow, (2) N-candidate generation via `Variation.pointMutate`/
 * `subtreeCrossover`, (3) edit-source -> `CorpusSeed.translateSource` -> injection queue. Porting
 * this to a different front end later means replacing this file's Swing half, not re-deriving
 * the control-loop logic.
 *
 * Threading contract, mirroring CorpusEvoRun's existing worker-pool Deque usage: `injectQueue`
 * carries human-edited genomes from the Swing EDT (button click) to the main evolution thread
 * (`drainInjections`, non-blocking) -- no direction needs to flow the other way, since pause/
 * resume is EvoDashboardWindow's responsibility now.
 */
class HumanLoopWindow {
	var frame:JFrame;
	var popList:JList;
	var popModel:DefaultListModel;
	var variantList:JList;
	var variantModel:DefaultListModel;
	var editor:JTextPane;
	var statusLabel:JLabel;

	var population:Array<StrategyGenome> = [];
	var popFitness:Array<Float> = [];
	var variants:Array<StrategyGenome> = [];
	var selectedIdx:Int = -1;

	var variation:Variation;
	var bars:Array<Bar>;
	var costBps:Float;
	var allowedIndicators:Map<String, Bool>;

	var injectQueue:Deque<StrategyGenome> = new Deque();

	static var COL_TEXT = new Color(11, 11, 11);
	static var COL_MUTED = new Color(82, 81, 78);
	static var COL_KEYWORD = new Color(42, 120, 214);   // dataviz slot 1 blue
	static var COL_STRING = new Color(27, 175, 122);    // slot 3 aqua
	static var COL_NUMBER = new Color(235, 104, 52);    // slot 2 orange
	static var COL_COMMENT = new Color(150, 148, 140);
	static var COL_OK = new Color(27, 135, 92);
	static var COL_ERR = new Color(191, 55, 45);

	static var KEYWORDS = ["strategy", "onBar", "when", "if", "else", "indicator", "function",
		"template", "module", "use", "long", "short", "flat", "close", "position", "true", "false",
		"param", "state", "return", "var", "evolve"];

	public function new(title:String, variation:Variation, bars:Array<Bar>, costBps:Float, allowedIndicators:Map<String, Bool>) {
		this.variation = variation;
		this.bars = bars;
		this.costBps = costBps;
		this.allowedIndicators = allowedIndicators;

		popModel = new DefaultListModel();
		popList = new JList(popModel);
		popList.setPreferredSize(new Dimension(340, 640));
		popList.addListSelectionListener(new ListSelectFn(onPopSelect));

		variantModel = new DefaultListModel();
		variantList = new JList(variantModel);
		variantList.setPreferredSize(new Dimension(300, 260));
		variantList.addListSelectionListener(new ListSelectFn(onVariantSelect));

		editor = new JTextPane();
		editor.setFont(new Font("Monospaced", Font.PLAIN, 13));
		// Must NOT call setCharacterAttributes synchronously from inside insertUpdate/removeUpdate
		// -- the document is still holding its own notification lock at that point, and re-entering
		// a mutation throws `IllegalStateException: Attempt to mutate in notification` (confirmed
		// via HumanLoopSmokeTest, hitting this on the very first population selection). Deferred via
		// SwingUtilities.invokeLater so the highlight pass runs AFTER the current edit fully
		// completes, same fix Swing's own docs recommend for this exact situation.
		editor.getStyledDocument().addDocumentListener(new DocumentFn(function() SwingUtilities.invokeLater(new RunnableFn(highlight))));

		var genBtn = new JButton("Generate 10 Variants (5 mutate + 5 crossover)");
		genBtn.addActionListener(new ActionFn(onGenerateVariants));

		var applyBtn = new JButton("Apply Edit -> Queue for Injection");
		applyBtn.addActionListener(new ActionFn(onApplyEdit));

		statusLabel = new JLabel(" ");

		// BoxLayout needs its target Container passed at construction, so `controls` is built bare
		// first and given the layout as a second step (setLayout), not via LayoutPanel's
		// layout-in-constructor form the way `root` below uses BorderLayout.
		var controls = new LayoutPanel();
		controls.setLayout(new BoxLayout(controls, BoxLayout.Y_AXIS));
		controls.add(genBtn);
		controls.add(new JScrollPane(variantList));
		controls.add(applyBtn);
		controls.add(statusLabel);

		var root = new LayoutPanel(new BorderLayout());
		root.add(new JScrollPane(popList), BorderLayout.WEST);
		root.add(new JScrollPane(editor), BorderLayout.CENTER);
		root.add(controls, BorderLayout.EAST);

		frame = new JFrame(title);
		// HIDE_ON_CLOSE (not DISPOSE_ON_CLOSE): the dashboard's Pause button re-shows this SAME
		// frame instance on every subsequent pause via `show()` -- disposing it on close would tear
		// down its native peer, and Swing frames aren't guaranteed re-showable after that.
		frame.setDefaultCloseOperation(JFrame.HIDE_ON_CLOSE);
		frame.add(root);
		frame.setSize(1400, 760);
		frame.setLocationRelativeTo(null);
		// Hidden until CorpusEvoRun's first pause calls `show()` -- see this class's doc comment:
		// the dashboard is the primary, always-visible window; this one only demands attention once
		// there's actually something to intervene on.
		frame.setVisible(false);
	}

	// ---- population <-> editor -------------------------------------------------------------

	/** Called by CorpusEvoRun once per generation (same cadence as EvoDashboardWindow.update) --
	 * refreshes the browsable population list. Does NOT touch the editor/selection so a human
	 * mid-edit isn't interrupted by the next generation landing. */
	public function setPopulation(pop:Array<StrategyGenome>, fitness:Array<Float>):Void {
		population = pop;
		popFitness = fitness;
		popModel.clear();
		for (i in 0...pop.length) {
			var f = fitness[i];
			var fstr = (f == Fitness.NEG_INF || Math.isNaN(f)) ? "invalid" : fmtF(f);
			popModel.addElement('#$i  ${pop[i].name}  fitness=$fstr');
		}
	}

	function onPopSelect(e:ListSelectionEvent):Void {
		if (e.getValueIsAdjusting()) return;
		var idx = popList.getSelectedIndex();
		if (idx < 0 || idx >= population.length) return;
		selectedIdx = idx;
		loadIntoEditor(population[idx]);
		variantModel.clear();
		variants = [];
		setStatus("selected #" + idx + " -- edit directly, or Generate 10 Variants", false);
	}

	function onVariantSelect(e:ListSelectionEvent):Void {
		if (e.getValueIsAdjusting()) return;
		var idx = variantList.getSelectedIndex();
		if (idx < 0 || idx >= variants.length) return;
		loadIntoEditor(variants[idx]);
		setStatus("loaded variant #" + idx + " into the editor -- edit further, or Apply", false);
	}

	function loadIntoEditor(g:StrategyGenome):Void {
		editor.setText(Expand.expand(g));
		highlight();
	}

	// ---- candidate generation ---------------------------------------------------------------

	/**
	 * 5 point-mutations + 5 crossovers (against a random OTHER population member, when one
	 * exists) of the currently-selected genome, each scored on the SAME in-sample tape/cost the
	 * run itself uses -- a real fitness number next to each candidate, not a guess. Selecting one
	 * loads it into the editor for further hand-editing before Apply, same as picking straight
	 * from the population list.
	 */
	function onGenerateVariants():Void {
		if (selectedIdx < 0 || selectedIdx >= population.length) {
			setStatus("select a genome from the population list first", true);
			return;
		}
		var base = population[selectedIdx];
		variants = [];
		variantModel.clear();
		for (i in 0...5) {
			var m = variation.pointMutate(base);
			variants.push(m);
			variantModel.addElement('mutate #$i  ${scoreLabel(m)}');
		}
		var donorAvailable = population.length > 1;
		for (i in 0...5) {
			var donor = donorAvailable ? pickOtherIndex(selectedIdx) : selectedIdx;
			var c = variation.subtreeCrossover(base, population[donor]);
			variants.push(c);
			variantModel.addElement('cross #$i w/ ${population[donor].name}  ${scoreLabel(c)}');
		}
		setStatus("generated 10 variants -- select one to preview/edit", false);
	}

	function pickOtherIndex(exclude:Int):Int {
		if (population.length <= 1) return exclude;
		var idx = Std.int(Math.random() * population.length);
		var guard = 0;
		while (idx == exclude && guard < 20) { idx = Std.int(Math.random() * population.length); guard++; }
		return idx;
	}

	function scoreLabel(g:StrategyGenome):String {
		var fr = Fitness.evaluate(g, bars, "js", false, costBps);
		return "fitness=" + (fr.ok && fr.trades >= 1 && !Math.isNaN(fr.sharpe) ? fmtF(fr.sharpe) : "invalid");
	}

	// ---- apply edit -> inject -----------------------------------------------------------------

	/**
	 * Reverse-compiles whatever's CURRENTLY in the editor (hand-edited, a picked variant, or an
	 * untouched population member) back into a `StrategyGenome` via `CorpusSeed.translateSource`
	 * -- the same closed-GP-grammar translator every other seed path uses, so a failure here
	 * means "outside the grammar" (onPosition exits, multi-output field access, etc.), not a real
	 * crash. Success queues the genome for `drainInjections` to pick up at the NEXT generation
	 * boundary -- never applied synchronously, so an in-flight generation's own fitness/popG
	 * arrays are never touched mid-computation.
	 */
	function onApplyEdit():Void {
		var src = editor.getText();
		var res = CorpusSeed.translateSource(src, allowedIndicators);
		if (res.genome == null) {
			setStatus('translate failed: ${res.error}', true);
			return;
		}
		injectQueue.add(res.genome);
		setStatus('queued for injection (${scoreLabel(res.genome)}) -- lands in the next generation', false);
	}

	// ---- CorpusEvoRun-facing control surface -------------------------------------------------

	/** Non-blocking drain -- CorpusEvoRun calls this once per generation boundary, right after
	 * `engine.step` produces the next population, and splices whatever comes back into a handful
	 * of (non-elite) slots. Empty on every generation nobody clicked Apply. */
	public function drainInjections():Array<StrategyGenome> {
		var out:Array<StrategyGenome> = [];
		while (true) {
			var g = injectQueue.pop(false);
			if (g == null) break;
			out.push(g);
		}
		return out;
	}

	/** Brings this window to front -- called by CorpusEvoRun the moment `EvoDashboardWindow.
	 * isPaused()` goes true, so the editor only demands attention once there's actually
	 * something to intervene on. Safe to call repeatedly (every generation the run stays
	 * paused); `setVisible(true)` on an already-visible frame is a harmless no-op. */
	public function show():Void frame.setVisible(true);

	function setStatus(msg:String, isError:Bool):Void {
		statusLabel.setText(msg);
		statusLabel.setForeground(isError ? COL_ERR : COL_OK);
	}

	// ---- syntax highlighting (hand-rolled lexer -- keywords/strings/numbers/comments) --------

	function highlight():Void {
		var doc = editor.getStyledDocument();
		var text = editor.getText();
		var n = text.length;
		var normal = new SimpleAttributeSet();
		StyleConstants.setForeground(normal, COL_TEXT);
		doc.setCharacterAttributes(0, n, normal, true);

		var i = 0;
		while (i < n) {
			var c = text.charAt(i);
			if (c == "/" && i + 1 < n && text.charAt(i + 1) == "/") {
				var start = i;
				while (i < n && text.charAt(i) != "\n") i++;
				paint(doc, start, i - start, COL_COMMENT);
			} else if (c == "/" && i + 1 < n && text.charAt(i + 1) == "*") {
				var start = i;
				i += 2;
				while (i < n - 1 && !(text.charAt(i) == "*" && text.charAt(i + 1) == "/")) i++;
				i = Std.int(Math.min(n, i + 2));
				paint(doc, start, i - start, COL_COMMENT);
			} else if (c == '"') {
				var start = i;
				i++;
				while (i < n && text.charAt(i) != '"') i++;
				if (i < n) i++;
				paint(doc, start, i - start, COL_STRING);
			} else if (isDigit(c)) {
				var start = i;
				while (i < n && (isDigit(text.charAt(i)) || text.charAt(i) == ".")) i++;
				paint(doc, start, i - start, COL_NUMBER);
			} else if (isAlpha(c)) {
				var start = i;
				while (i < n && (isAlpha(text.charAt(i)) || isDigit(text.charAt(i)) || text.charAt(i) == "_")) i++;
				var word = text.substring(start, i);
				if (KEYWORDS.indexOf(word) >= 0) paint(doc, start, i - start, COL_KEYWORD);
			} else {
				i++;
			}
		}
	}

	function paint(doc:StyledDocument, offset:Int, len:Int, color:Color):Void {
		if (len <= 0) return;
		var attr = new SimpleAttributeSet();
		StyleConstants.setForeground(attr, color);
		doc.setCharacterAttributes(offset, len, attr, false);
	}

	static function isDigit(c:String):Bool return c.length == 1 && c.charCodeAt(0) >= "0".code && c.charCodeAt(0) <= "9".code;
	static function isAlpha(c:String):Bool {
		if (c.length != 1) return false;
		var code = c.charCodeAt(0);
		return (code >= "a".code && code <= "z".code) || (code >= "A".code && code <= "Z".code);
	}

	function fmtF(v:Float):String {
		var m = 10000.0;
		return Std.string(Math.ffloor(v * m + 0.5) / m);
	}

	public function close():Void frame.dispose();
}

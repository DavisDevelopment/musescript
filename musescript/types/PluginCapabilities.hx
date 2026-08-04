package musescript.types;

import musescript.ast.Decl;
import musescript.ast.Expr;
import musescript.ast.MuseProgram;
import musescript.ast.OrderKind;
import musescript.ast.Stmt;
import musescript.builtins.MuseHost;

/**
 * Engine-level capability table for widget / plugin programs.
 *
 * Pattern matches `BuiltinSigs.isPaletteOnly`: a small classified table of
 * names + a query API. Full strategies ignore this table; plugin entrypoints
 * (`MuseRuntime.checkWidget` / `runWidget`, `MuseInterp.executePlugin`) audit
 * a lowered program before run.
 *
 * Capability classes:
 *   - compute  — default, always allowed for plugin kinds
 *   - chart    — plot / plotshape / hline / bgcolor (+ muse.chart.*) + muse.diag emitters
 *   - panel    — display helpers (`log`)
 *   - scanner  — scan_top / scan_bottom (kind reserved; currently denied)
 *   - orders   — long/short/flat/close/buy/sell_all/rebalance/portfolio mutate
 *   - io_fs    — filesystem / db flats (`fs_*`, `db_*`); always deny plugins
 *   - io_net   — http flats (`http_*`); always deny plugins
 *   - denied   — Reflect / eval / Sys / File / fetch host-escape aliases (never)
 */
class PluginCapabilities {
	/** Named buckets for table rows / error messages. */
	public static inline var CAP_COMPUTE = "compute";
	public static inline var CAP_CHART = "chart";
	public static inline var CAP_PANEL = "panel";
	public static inline var CAP_SCANNER = "scanner";
	public static inline var CAP_ORDERS = "orders";
	public static inline var CAP_IO_FS = "io_fs";
	public static inline var CAP_IO_NET = "io_net";
	public static inline var CAP_DENIED = "denied";

	static var classOf:Map<String, String>;
	static var kindAllows:Map<String, Map<String, Bool>>;

	/** Capability class for a flat builtin / verb name (unknown → compute). */
	public static function capabilityOf(name:String):String {
		ensure();
		if (name == null || name == "") return CAP_COMPUTE;
		// portfolio_* is always an order/portfolio surface for plugins.
		if (StringTools.startsWith(name, "portfolio_")) return CAP_ORDERS;
		// Future / stub IO flats — classified even before MuseHost install.
		if (StringTools.startsWith(name, "fs_") || StringTools.startsWith(name, "db_"))
			return CAP_IO_FS;
		if (name == "pd_read_csv") return CAP_IO_FS;
		if (StringTools.startsWith(name, "http_")) return CAP_IO_NET;
		var c = classOf.get(name);
		return c != null ? c : CAP_COMPUTE;
	}

	/** True when `kind` may invoke the named flat builtin. */
	public static function allows(kind:PluginKind, name:String):Bool {
		ensure();
		var cap = capabilityOf(name);
		if (cap == CAP_DENIED || cap == CAP_ORDERS || cap == CAP_IO_FS || cap == CAP_IO_NET)
			return false;
		var allow = kindAllows.get(kind);
		return allow != null && allow.exists(cap);
	}

	/** True when this name is permanently forbidden for every plugin kind. */
	public static function isAlwaysDenied(name:String):Bool {
		var c = capabilityOf(name);
		return c == CAP_DENIED || c == CAP_ORDERS || c == CAP_IO_FS || c == CAP_IO_NET;
	}

	/**
	 * Audit a (preferably MuseHost-lowered) program. Returns
	 * `{ ok, kind, violations:[{name, capability, where}], error? }`.
	 */
	public static function audit(prog:MuseProgram, kind:PluginKind):Dynamic {
		ensure();
		var violations:Array<Dynamic> = [];
		var seen = new Map<String, Bool>();

		function note(name:String, where:String):Void {
			var cap = capabilityOf(name);
			if (allows(kind, name)) return;
			var key = '$cap|$name|$where';
			if (seen.exists(key)) return;
			seen.set(key, true);
			violations.push({
				name: name,
				capability: cap,
				where: where,
				message: 'plugin kind "${kind.label()}" denies capability "$cap" ($name)'
			});
		}

		function walkExpr(e:Expr, where:String):Void {
			if (e == null) return;
			switch (e) {
				case ECall(callee, args):
					var resolved = resolveCallee(callee);
					if (resolved != null) note(resolved, where);
					walkExpr(callee, where);
					for (a in args) walkExpr(a, where);
				case EBlock(es):
					for (x in es) walkExpr(x, where);
				case EField(inner, _):
					walkExpr(inner, where);
				case EBinop(_, a, b):
					walkExpr(a, where);
					walkExpr(b, where);
				case EUnop(_, _, a) | ELookback(a, _) | EArray(a, _) | EParent(a)
					| EReturn(a) | EVar(_, a) | EMeta(_, _, a) | EYield(a) | EYieldStar(a):
					if (a != null) walkExpr(a, where);
				case EIf(c, a, b):
					walkExpr(c, where);
					walkExpr(a, where);
					if (b != null) walkExpr(b, where);
				case EWhile(c, body) | EFor(_, c, body):
					walkExpr(c, where);
					walkExpr(body, where);
				case EFunction(_, body, _, _):
					walkExpr(body, where);
				case EArrayDecl(vs):
					for (v in vs) walkExpr(v, where);
				case EObject(fs):
					for (f in fs) walkExpr(f.e, where);
				case ETernary(c, a, b):
					walkExpr(c, where);
					walkExpr(a, where);
					walkExpr(b, where);
				case EMatch(scrut, arms):
					walkExpr(scrut, where);
					for (arm in arms) {
						if (arm.guard != null) walkExpr(arm.guard, where);
						walkExpr(arm.body, where);
					}
				case ENew(_, args) | ESuper(_, args):
					for (a in args) walkExpr(a, where);
				case EIdent(name):
					// Bare Reflect / Sys as values still count as banned surfaces.
					if (isAlwaysDenied(name) && (capabilityOf(name) == CAP_DENIED))
						note(name, where);
				default:
			}
		}

		function walkStmts(ss:Array<Stmt>, where:String):Void {
			if (ss == null) return;
			for (s in ss) {
				if (s == null) continue;
				switch (s) {
					case OnBar(body): walkStmts(body, where + "/onBar");
					case OnPosition(body): walkStmts(body, where + "/onPosition");
					case OnTick(body): walkStmts(body, where + "/onTick");
					case OnEvent(_, body): walkStmts(body, where + "/onEvent");
					case Block(body): walkStmts(body, where);
					case When(cond, body):
						walkExpr(cond, where);
						walkStmts(body, where);
					case ForIn(_, iter, body):
						walkExpr(iter, where);
						walkStmts(body, where);
					case MatchFor(_, iter, arms):
						walkExpr(iter, where);
						for (arm in arms) {
							if (arm.guard != null) walkExpr(arm.guard, where);
							walkExpr(arm.body, where);
						}
					case ExprStmt(e) | Assign(_, e) | Return(e) | Yield(e) | YieldStar(e):
						if (e != null) walkExpr(e, where);
					case Order(kind, args):
						note(orderKindName(kind), where + "/order");
						for (a in args) walkExpr(a, where);
					case Use(_, args):
						for (a in args) walkExpr(a.value, where);
				}
			}
		}

		function walkDecl(d:Decl):Void {
			switch (d) {
				case StrategyDecl(name, body):
					walkStmts(body, 'strategy:$name');
				case IndicatorDecl(name, _, body):
					walkExpr(body, 'indicator:$name');
				case ParamDecl(_, def, _):
					if (def != null) walkExpr(def, "param");
				case FnDecl(name, _, body, _):
					walkExpr(body, name != null ? 'fn:$name' : "fn");
				case MacroDecl(name, body):
					walkStmts(body, 'macro:$name');
				case ModuleDecl(name, params, body):
					for (p in params) if (p.def != null) walkExpr(p.def, 'module:$name');
					walkStmts(body, 'module:$name');
				case TemplateDecl(name, _, _, body):
					walkExpr(body, 'template:$name');
				case StmtTemplateDecl(name, _, body):
					walkStmts(body, 'stmtTemplate:$name');
				case EnumDecl(_, _):
				case ClassDecl(name, _, fields, methods, ctor):
					for (f in fields) if (f.def != null) walkExpr(f.def, 'class:$name');
					for (m in methods) walkExpr(m.body, 'class:$name.${m.name}');
					if (ctor != null) walkExpr(ctor.body, 'class:$name.ctor');
			}
		}

		if (prog != null) {
			for (d in prog.decls) walkDecl(d);
			walkStmts(prog.stmts, "toplevel");
		}

		if (violations.length == 0)
			return { ok: true, kind: kind.label(), violations: violations };

		var first = violations[0];
		var msg = Reflect.field(first, "message");
		if (violations.length > 1)
			msg = msg + ' (+${violations.length - 1} more)';
		return {
			ok: false,
			kind: kind.label(),
			violations: violations,
			error: msg
		};
	}

	/** Documented kind × capability matrix for hosts / Studio. */
	public static function tableJson():Dynamic {
		ensure();
		var kinds:Array<Dynamic> = [];
		for (k in PluginKind.all()) {
			var allow = kindAllows.get(k);
			kinds.push({
				kind: k.label(),
				allows: [for (c in allow.keys()) c],
				notes: switch (k) {
					case PluginKind.Compute:
						"read-only compute (default)";
					case PluginKind.Chart:
						"compute + plot/chart commands";
					case PluginKind.Panel:
						"compute + plot + log display helpers";
					case PluginKind.Scanner:
						"reserved — scanner builtins still denied until a consumer ships";
				}
			});
		}
		var classified:Array<Dynamic> = [];
		for (name => cap in classOf)
			classified.push({ name: name, capability: cap });
		classified.sort(function(a, b) {
			var an:String = Reflect.field(a, "name");
			var bn:String = Reflect.field(b, "name");
			return Reflect.compare(an, bn);
		});
		return {
			schema: "musescript.plugin-kinds/2",
			alwaysDenied: [CAP_ORDERS, CAP_IO_FS, CAP_IO_NET, CAP_DENIED],
			kinds: kinds,
			builtins: classified
		};
	}

	/** Resolve `foo(...)` / `muse.chart.plot(...)` to a flat builtin name. */
	public static function resolveCallee(e:Expr):Null<String> {
		if (e == null) return null;
		return switch (e) {
			case EIdent(name): name;
			case EParent(inner): resolveCallee(inner);
			case EField(EIdent("muse"), ns):
				// muse.orders / muse.chart as a value — treat ns itself.
				null;
			case EField(EField(EIdent("muse"), ns), method):
				var flat = MuseHost.resolveFlat(ns, method);
				flat != null ? flat : 'muse.$ns.$method';
			case EField(EIdent(recv), method):
				// Bare namespace helpers rarely appear; map known order aliases.
				if (recv == "orders" || recv == "portfolio" || recv == "chart") {
					var flat = MuseHost.resolveFlat(recv, method);
					if (flat != null) return flat;
				}
				null;
			default: null;
		};
	}

	static function orderKindName(k:OrderKind):String {
		return switch (k) {
			case Long: "long";
			case Short: "short";
			case Flat: "flat";
			case Close: "close";
		};
	}

	static function ensure():Void {
		if (classOf != null) return;
		classOf = new Map();

		mark(CAP_ORDERS, [
			"long", "short", "flat", "close",
			"buy", "sell", "sell_all",
			"rebalance_equal", "target_weight",
			"orders_cancel_all",
			"portfolio_long", "portfolio_short", "portfolio_flat",
			"portfolio_orders_pending", "portfolio_orders_cancel_all",
			"portfolio_apply", "portfolio_add", "portfolio_sub", "portfolio_mask",
			"portfolio_bag", "portfolio_equity", "portfolio_cash", "portfolio_unrealized"
		]);
		mark(CAP_CHART, [
			"plot", "plotshape", "hline", "bgcolor",
			"diag_kiss", "diag_underwater", "diag_pack"
		]);
		// Pure series helpers stay compute (default); emitters above need CAP_CHART.
		mark(CAP_PANEL, ["log"]);
		mark(CAP_SCANNER, ["scan_top", "scan_bottom"]);
		mark(CAP_IO_FS, [
			"fs_read_text", "fs_write_text", "fs_append_text", "fs_exists",
			"fs_is_dir", "fs_is_file", "fs_list", "fs_mkdir", "fs_read_bytes",
			"pd_read_csv",
			"db_open", "db_query", "db_exec", "db_close"
		]);
		mark(CAP_IO_NET, ["http_request", "http_get", "http_post"]);
		mark(CAP_DENIED, [
			"Reflect", "reflect", "eval", "__js__",
			"Sys", "File", "FileSystem", "Http", "http",
			"fetch", "XMLHttpRequest", "require", "process"
		]);

		kindAllows = new Map();
		kindAllows.set(PluginKind.Compute, caps([CAP_COMPUTE]));
		kindAllows.set(PluginKind.Chart, caps([CAP_COMPUTE, CAP_CHART, CAP_PANEL]));
		kindAllows.set(PluginKind.Panel, caps([CAP_COMPUTE, CAP_CHART, CAP_PANEL]));
		// Scanner kind reserved: only compute for now (scanner cap not granted).
		kindAllows.set(PluginKind.Scanner, caps([CAP_COMPUTE]));
	}

	static function mark(cap:String, names:Array<String>):Void {
		for (n in names) classOf.set(n, cap);
	}

	static function caps(list:Array<String>):Map<String, Bool> {
		var m = new Map<String, Bool>();
		for (c in list) m.set(c, true);
		return m;
	}
}

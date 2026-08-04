package musescript.io;

/**
 * Thrown when gated filesystem / network / db ops run without a host IoGrant
 * (default offline backtest / fitness: grants are null).
 *
 * Plug-in kinds never receive grants — `PluginCapabilities` denies `io_fs` /
 * `io_net` at audit time before this can fire.
 */
class IoDenied {
	public var op:String;
	public var message:String;

	public function new(op:String, ?detail:String) {
		this.op = op == null ? "" : op;
		this.message = detail != null && detail.length > 0
			? 'IoDenied: $op — $detail'
			: 'IoDenied: $op (no IO grant; host must pass opts.grants)';
	}

	public function toString():String return message;

	public static inline function isPresent(?grants:Null<IoGrant>):Bool {
		return grants != null;
	}

	public static function require(op:String, ?grants:Null<IoGrant>):IoGrant {
		if (grants == null) throw new IoDenied(op);
		return grants;
	}

	public static function requireFs(op:String, ?grants:Null<IoGrant>):Dynamic {
		var g = require(op, grants);
		if (g.fs == null || g.fs.roots == null || g.fs.roots.length == 0)
			throw new IoDenied(op, "fs grant missing roots");
		return g.fs;
	}

	public static function requireNet(op:String, ?grants:Null<IoGrant>):NetGrant {
		var g = require(op, grants);
		if (g.net == null)
			throw new IoDenied(op, "net grant missing");
		var hosts = g.net.allow_hosts;
		if (hosts == null || hosts.length == 0)
			throw new IoDenied(op, "net grant missing allow_hosts");
		return g.net;
	}
}

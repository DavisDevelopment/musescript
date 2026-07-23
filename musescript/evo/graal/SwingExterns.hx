package musescript.evo.graal;

/** Minimal hand-declared externs for the handful of java.awt/javax.swing classes
 * EvoDashboardWindow needs -- same `@:native` extern-declaration convention this package
 * already uses for GraalVM's polyglot API (see Polyglot.hx). Only the members actually used
 * are declared; nothing here claims to be a complete Swing binding. */

@:native("java.awt.Component")
extern class Component {}

@:native("javax.swing.JFrame")
extern class JFrame {
	function new(title:String);
	function setSize(w:Int, h:Int):Void;
	function setDefaultCloseOperation(op:Int):Void;
	function add(c:Component):Component;
	function setVisible(v:Bool):Void;
	function setLocationRelativeTo(c:Component):Void;
	function dispose():Void;
	static var DISPOSE_ON_CLOSE(default, never):Int;
}

@:native("javax.swing.JComponent")
extern class JComponent extends Component {
	function repaint():Void;
}

@:native("javax.swing.JPanel")
extern class JPanel extends JComponent {
	function new();
	function setBackground(c:Color):Void;
	function setPreferredSize(d:Dimension):Void;
	function paintComponent(g:Graphics):Void;
}

@:native("java.awt.Dimension")
extern class Dimension {
	function new(w:Int, h:Int);
}

@:native("java.awt.Color")
extern class Color {
	function new(r:Int, g:Int, b:Int);
	static var WHITE(default, never):Color;
	static var BLACK(default, never):Color;
}

@:native("java.awt.Stroke")
extern interface Stroke {}

@:native("java.awt.BasicStroke")
extern class BasicStroke implements Stroke {
	function new(width:Single);
}

@:native("java.awt.Font")
extern class Font {
	function new(name:String, style:Int, size:Int);
	static var BOLD(default, never):Int;
	static var PLAIN(default, never):Int;
}

@:native("java.awt.RenderingHints$Key")
extern class RenderingHintsKey {}

@:native("java.awt.RenderingHints")
extern class RenderingHints {
	function new(key:RenderingHintsKey, value:Dynamic);
	static var KEY_ANTIALIASING(default, never):RenderingHintsKey;
	static var VALUE_ANTIALIAS_ON(default, never):Dynamic;
}

@:native("java.awt.Graphics")
extern class Graphics {
	function setColor(c:Color):Void;
	function drawLine(x1:Int, y1:Int, x2:Int, y2:Int):Void;
	function drawString(s:String, x:Int, y:Int):Void;
	function fillRect(x:Int, y:Int, w:Int, h:Int):Void;
	function setFont(f:Font):Void;
}

@:native("java.awt.Graphics2D")
extern class Graphics2D extends Graphics {
	function setStroke(s:Stroke):Void;
	function setRenderingHint(key:RenderingHintsKey, value:Dynamic):Void;
}

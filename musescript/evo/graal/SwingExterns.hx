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
	static var HIDE_ON_CLOSE(default, never):Int;
}

@:native("javax.swing.JComponent")
extern class JComponent extends Component {
	function repaint():Void;
	function setPreferredSize(d:Dimension):Void;
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
	@:overload function new(r:Int, g:Int, b:Int);
	@:overload function new(r:Int, g:Int, b:Int, a:Int);
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
	function drawRect(x:Int, y:Int, w:Int, h:Int):Void;
	function fillPolygon(p:Polygon):Void;
	function setFont(f:Font):Void;
}

@:native("java.awt.Polygon")
extern class Polygon {
	function new();
	function addPoint(x:Int, y:Int):Void;
}

@:native("java.awt.Graphics2D")
extern class Graphics2D extends Graphics {
	function setStroke(s:Stroke):Void;
	function setRenderingHint(key:RenderingHintsKey, value:Dynamic):Void;
}

// ---- additions for HumanLoopWindow: layout, lists, text editing, buttons ----------------

/** Real interface every AWT layout manager implements -- see this file's header note on why
 * Java-target extern CONSTRUCTOR/METHOD parameters need to match the real erased bytecode
 * signature exactly (a `Dynamic`/`Object`-typed param here would link as `setLayout(Object)`,
 * which doesn't exist on the real `Container` -- confirmed the hard way via a `NoSuchMethodError`
 * on the analogous `JList(DefaultListModel)` vs real `JList(ListModel)` mismatch). */
@:native("java.awt.LayoutManager")
extern interface LayoutManager {}

@:native("java.awt.BorderLayout")
extern class BorderLayout implements LayoutManager {
	function new();
	static var NORTH(default, never):String;
	static var SOUTH(default, never):String;
	static var EAST(default, never):String;
	static var WEST(default, never):String;
	static var CENTER(default, never):String;
}

@:native("java.awt.FlowLayout")
extern class FlowLayout implements LayoutManager {
	function new();
	function setAlignment(align:Int):Void;
	static var LEFT(default, never):Int;
}

@:native("javax.swing.BoxLayout")
extern class BoxLayout implements LayoutManager {
	function new(target:Container, axis:Int);
	static var Y_AXIS(default, never):Int;
	static var X_AXIS(default, never):Int;
}

@:native("java.awt.Container")
extern class Container extends Component {
	function setLayout(l:LayoutManager):Void;
	@:overload(function(c:Component, constraints:Dynamic):Void {})
	function add(c:Component):Component;
	function remove(c:Component):Void;
	function removeAll():Void;
	function revalidate():Void;
}

@:native("javax.swing.JPanel")
extern class LayoutPanel extends Container {
	@:overload(function(layout:LayoutManager):Void {})
	function new();
}

@:native("javax.swing.JLabel")
extern class JLabel extends JComponent {
	function new(?text:String);
	function setText(s:String):Void;
	function setForeground(c:Color):Void;
}

@:native("javax.swing.JButton")
extern class JButton extends JComponent {
	function new(text:String);
	function addActionListener(l:ActionListener):Void;
	function setEnabled(v:Bool):Void;
	function setText(s:String):Void;
}

@:native("javax.swing.JCheckBox")
extern class JCheckBox extends JComponent {
	function new(text:String);
	function isSelected():Bool;
	function addActionListener(l:ActionListener):Void;
}

@:native("javax.swing.JScrollPane")
extern class JScrollPane extends JComponent {
	function new(view:Component);
}

@:native("javax.swing.JSplitPane")
extern class JSplitPane extends JComponent {
	function new(orientation:Int, left:Component, right:Component);
	function setDividerLocation(loc:Int):Void;
	function setResizeWeight(w:Single):Void;
	static var HORIZONTAL_SPLIT(default, never):Int;
	static var VERTICAL_SPLIT(default, never):Int;
}

@:native("java.lang.Runnable")
extern interface Runnable {
	function run():Void;
}

class RunnableFn implements Runnable {
	var fn:Void->Void;
	public function new(fn:Void->Void) this.fn = fn;
	public function run():Void fn();
}

@:native("javax.swing.SwingUtilities")
extern class SwingUtilities {
	static function invokeLater(r:Runnable):Void;
}

@:native("java.awt.event.ActionEvent")
extern class ActionEvent {}

@:native("java.awt.event.ActionListener")
extern interface ActionListener {
	function actionPerformed(e:ActionEvent):Void;
}

/** Small concrete adapter -- Haxe classes CAN implement extern Java interfaces directly (this
 * compiles to a real .class implementing java.awt.event.ActionListener), so a plain Haxe closure
 * becomes a valid Swing listener without needing an anonymous-class extern trick. Same pattern
 * used below for list-selection and document-change listeners. */
class ActionFn implements ActionListener {
	var fn:Void->Void;
	public function new(fn:Void->Void) this.fn = fn;
	public function actionPerformed(e:ActionEvent):Void fn();
}

@:native("javax.swing.ListModel")
extern interface ListModel {}

/** `DefaultListModel implements ListModel` for real (its actual Java superclass is
 * `AbstractListModel<E>`, which implements `ListModel<E>` -- declared here as a direct
 * `implements` since only the interface, not the abstract base, has methods this file needs). A
 * constructor's declared PARAMETER TYPE has to match the real erased bytecode signature exactly
 * (unlike ordinary method calls, Haxe's Java target doesn't do call-site widening for `new`) --
 * `JList`'s real constructor takes `ListModel`, not `DefaultListModel`, so passing a
 * `DefaultListModel` typed as `DefaultListModel` at that call site linked as
 * `NoSuchMethodError: JList.<init>(DefaultListModel)` at runtime (compiles fine, since Haxe never
 * verifies externs against real bytecode -- only surfaces when the JVM actually resolves the
 * call). */
@:native("javax.swing.DefaultListModel")
extern class DefaultListModel implements ListModel {
	function new();
	function addElement(o:Dynamic):Void;
	function clear():Void;
	function getSize():Int;
}

@:native("javax.swing.event.ListSelectionEvent")
extern class ListSelectionEvent {
	function getValueIsAdjusting():Bool;
}

@:native("javax.swing.event.ListSelectionListener")
extern interface ListSelectionListener {
	function valueChanged(e:ListSelectionEvent):Void;
}

class ListSelectFn implements ListSelectionListener {
	var fn:ListSelectionEvent->Void;
	public function new(fn:ListSelectionEvent->Void) this.fn = fn;
	public function valueChanged(e:ListSelectionEvent):Void fn(e);
}

@:native("javax.swing.JList")
extern class JList extends JComponent {
	function new(model:ListModel);
	function getSelectedIndex():Int;
	function setSelectedIndex(i:Int):Void;
	function addListSelectionListener(l:ListSelectionListener):Void;
}

@:native("javax.swing.text.Document")
extern interface Document {
	function getLength():Int;
	function addDocumentListener(l:DocumentListener):Void;
}

@:native("javax.swing.event.DocumentEvent")
extern class DocumentEvent {}

@:native("javax.swing.event.DocumentListener")
extern interface DocumentListener {
	function insertUpdate(e:DocumentEvent):Void;
	function removeUpdate(e:DocumentEvent):Void;
	function changedUpdate(e:DocumentEvent):Void;
}

/** All three callbacks route through ONE handler -- this editor's highlighter doesn't care
 * whether text was inserted, removed, or an attribute changed, it just re-tokenizes on any
 * content edit (see HumanLoopWindow's debounce discussion for why re-tokenizing from
 * `changedUpdate` specifically is guarded against re-entrancy). */
class DocumentFn implements DocumentListener {
	var fn:Void->Void;
	public function new(fn:Void->Void) this.fn = fn;
	public function insertUpdate(e:DocumentEvent):Void fn();
	public function removeUpdate(e:DocumentEvent):Void fn();
	public function changedUpdate(e:DocumentEvent):Void {}
}

@:native("javax.swing.text.AttributeSet")
extern interface AttributeSet {}

@:native("javax.swing.text.MutableAttributeSet")
extern interface MutableAttributeSet extends AttributeSet {}

@:native("javax.swing.text.SimpleAttributeSet")
extern class SimpleAttributeSet implements MutableAttributeSet {
	function new();
}

@:native("javax.swing.text.StyleConstants")
extern class StyleConstants {
	static function setForeground(a:MutableAttributeSet, c:Color):Void;
	static function setBold(a:MutableAttributeSet, b:Bool):Void;
	static function setItalic(a:MutableAttributeSet, b:Bool):Void;
}

@:native("javax.swing.text.StyledDocument")
extern interface StyledDocument extends Document {
	function setCharacterAttributes(offset:Int, length:Int, s:AttributeSet, replace:Bool):Void;
	function getText(offset:Int, length:Int):String;
}

@:native("javax.swing.JTextPane")
extern class JTextPane extends JComponent {
	function new();
	function setText(s:String):Void;
	function getText():String;
	function getStyledDocument():StyledDocument;
	function setFont(f:Font):Void;
	function setCaretPosition(p:Int):Void;
}


import 'package:nocterm/nocterm.dart';
import 'package:nocterm/src/components/render_paragraph.dart';
import 'package:nocterm/src/components/render_text.dart';
import 'package:nocterm/src/framework/terminal_canvas.dart';
import 'package:test/test.dart';

/// The bindings hand the root the SAME constraints object while the
/// terminal size holds, so a frame with nothing dirty lays out nothing.
/// Before, a fresh `BoxConstraints.tight` every frame defeated the
/// `identical` skip in `RenderObject.layout` and re-ran every
/// `performLayout` in the tree on every frame.
///
/// Everything that used to be refreshed only by that per-frame relayout
/// now has to ask for layout itself; the groups below pin each of those.
void main() {
  group('root constraints are reused', () {
    test('a frame with nothing dirty lays out nothing', () async {
      await testNocterm('idle frames', (tester) async {
        var layouts = 0;
        await tester.pumpComponent(
          _Counter(onLayout: () => layouts++, child: const Text('hello')),
        );
        expect(layouts, 1);

        await tester.pump();
        await tester.pump();
        await tester.pump();
        expect(layouts, 1, reason: 'no frame had anything dirty');
        expect(tester.terminalState.containsText('hello'), isTrue);
      });
    });

    test('a paint-only change repaints without a layout', () async {
      await testNocterm('paint only', (tester) async {
        var layouts = 0;
        await tester.pumpComponent(
          _Counter(onLayout: () => layouts++, child: const _Tint()),
        );
        expect(layouts, 1);

        tester.findState<_TintState>().flip();
        await tester.pump();
        expect(layouts, 1);
        final cell = tester.terminalState.getCellAt(0, 0);
        expect(cell?.style.color, Colors.red);
      });
    });

    test('a dirty descendant still lays out from the root', () async {
      await testNocterm('dirty descendant', (tester) async {
        var layouts = 0;
        await tester.pumpComponent(
          _Counter(onLayout: () => layouts++, child: const _Label()),
        );
        tester.findState<_LabelState>().set('changed');
        await tester.pump();
        expect(layouts, 2);
        expect(tester.terminalState.containsText('changed'), isTrue);
      });
    });
  });

  group('layout-time builders ask for layout on update', () {
    test('a LayoutBuilder runs the builder its parent rebuilt with',
        () async {
      await testNocterm('layout builder', (tester) async {
        await tester.pumpComponent(const _BuilderHost());
        expect(tester.terminalState.containsText('value 0'), isTrue);

        tester.findState<_BuilderHostState>().bump();
        await tester.pump();
        expect(tester.terminalState.containsText('value 1'), isTrue);
      });
    });

    test('a ListView rebuilds its items when its parent rebuilds', () async {
      await testNocterm('list view', (tester) async {
        await tester.pumpComponent(const _ListHost());
        expect(tester.terminalState.containsText('> 0'), isTrue);

        tester.findState<_ListHostState>().select(2);
        await tester.pump();
        expect(tester.terminalState.containsText('> 2'), isTrue);
        expect(tester.terminalState.containsText('> 0'), isFalse);
      });
    });

    test('a builder nested in a builder settles', () async {
      await testNocterm('nested builders', (tester) async {
        await tester.pumpComponent(const _NestedHost());
        tester.findState<_NestedHostState>().bump();
        await tester.pump();
        expect(tester.terminalState.containsText('inner 1'), isTrue);
        // The inner update happens inside the outer's layout. It must not
        // leave work that re-creates itself: one follow-up frame (the
        // inner Text's own setter marks up to the root, as it always did)
        // and then nothing is scheduled.
        await tester.pump();
        expect(NoctermTestBinding.instance.hasScheduledFrame, isFalse);
        expect(tester.terminalState.containsText('inner 1'), isTrue);
      });
    });
  });

  group('text layout is memoised on its inputs', () {
    test('RenderParagraph keeps its layout under equal constraints', () {
      final p = RenderParagraph(text: const TextSpan(text: 'hello world'));
      p.layout(const BoxConstraints(maxWidth: 20, maxHeight: 5));
      final first = p.selectableLayout;

      // A NEW constraints object with the same width: what every relayout
      // from the root hands a paragraph whose text did not change.
      p.markNeedsLayout();
      p.layout(const BoxConstraints(minWidth: 3, maxWidth: 20, maxHeight: 9));
      expect(identical(p.selectableLayout, first), isTrue);
      expect(p.size, const Size(11, 1));

      p.layout(const BoxConstraints(maxWidth: 5, maxHeight: 5));
      expect(identical(p.selectableLayout, first), isFalse);
      expect(p.selectableLayout!.lines, ['hello', 'world']);

      // A change of STYLE alone keeps the text layout.
      final plain = p.selectableLayout;
      p.text = const TextSpan(
        text: 'hello world',
        style: TextStyle(color: Colors.red),
      );
      p.layout(const BoxConstraints(maxWidth: 5, maxHeight: 5));
      expect(identical(p.selectableLayout, plain), isTrue);

      final narrow = p.selectableLayout;
      p.text = const TextSpan(text: 'bye');
      p.layout(const BoxConstraints(maxWidth: 5, maxHeight: 5));
      expect(identical(p.selectableLayout, narrow), isFalse);
      expect(p.selectableLayout!.lines, ['bye']);

      final bye = p.selectableLayout;
      p.maxLines = 1;
      p.layout(const BoxConstraints(maxWidth: 5, maxHeight: 5));
      expect(identical(p.selectableLayout, bye), isFalse);
    });

    test('RenderText keeps its layout under equal constraints', () {
      final t = RenderText(text: 'hello world');
      t.layout(const BoxConstraints(maxWidth: 20, maxHeight: 5));
      final first = t.selectableLayout;

      t.markNeedsLayout();
      t.layout(const BoxConstraints(maxWidth: 20, maxHeight: 5));
      expect(identical(t.selectableLayout, first), isTrue);

      t.softWrap = false;
      t.layout(const BoxConstraints(maxWidth: 20, maxHeight: 5));
      expect(identical(t.selectableLayout, first), isFalse);

      final nowrap = t.selectableLayout;
      t.text = 'other';
      t.layout(const BoxConstraints(maxWidth: 20, maxHeight: 5));
      expect(identical(t.selectableLayout, nowrap), isFalse);
      expect(t.selectableLayout!.lines, ['other']);
    });
  });
}

class _Counter extends SingleChildRenderObjectComponent {
  const _Counter({required this.onLayout, super.child});

  final void Function() onLayout;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _CountingBox(onLayout);
}

class _CountingBox extends RenderObject
    with RenderObjectWithChildMixin<RenderObject> {
  _CountingBox(this.onLayout);

  final void Function() onLayout;

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! BoxParentData) {
      child.parentData = BoxParentData();
    }
  }

  @override
  void performLayout() {
    onLayout();
    child!.layout(constraints, parentUsesSize: true);
    size = constraints.constrain(child!.size);
  }

  @override
  void paint(TerminalCanvas canvas, Offset offset) {
    super.paint(canvas, offset);
    child!.paintWithContext(canvas, offset);
  }
}

class _Tint extends StatefulComponent {
  const _Tint();

  @override
  State<_Tint> createState() => _TintState();
}

class _TintState extends State<_Tint> {
  bool _red = false;

  void flip() => setState(() => _red = !_red);

  @override
  Component build(BuildContext context) => Text(
        'tint',
        style: TextStyle(color: _red ? Colors.red : Colors.green),
      );
}

class _Label extends StatefulComponent {
  const _Label();

  @override
  State<_Label> createState() => _LabelState();
}

class _LabelState extends State<_Label> {
  String _text = 'original';

  void set(String value) => setState(() => _text = value);

  @override
  Component build(BuildContext context) => Text(_text);
}

class _BuilderHost extends StatefulComponent {
  const _BuilderHost();

  @override
  State<_BuilderHost> createState() => _BuilderHostState();
}

class _BuilderHostState extends State<_BuilderHost> {
  int _value = 0;

  void bump() => setState(() => _value++);

  @override
  Component build(BuildContext context) {
    final value = _value;
    return LayoutBuilder(
      builder: (context, constraints) => Text('value $value'),
    );
  }
}

class _ListHost extends StatefulComponent {
  const _ListHost();

  @override
  State<_ListHost> createState() => _ListHostState();
}

class _ListHostState extends State<_ListHost> {
  int _selected = 0;

  void select(int index) => setState(() => _selected = index);

  @override
  Component build(BuildContext context) {
    final selected = _selected;
    return ListView.builder(
      itemCount: 5,
      lazy: true,
      itemBuilder: (context, i) => Text(i == selected ? '> $i' : '  $i'),
    );
  }
}

class _NestedHost extends StatefulComponent {
  const _NestedHost();

  @override
  State<_NestedHost> createState() => _NestedHostState();
}

class _NestedHostState extends State<_NestedHost> {
  int _value = 0;

  void bump() => setState(() => _value++);

  @override
  Component build(BuildContext context) {
    final value = _value;
    return LayoutBuilder(
      builder: (context, outer) => LayoutBuilder(
        builder: (context, inner) => Text('inner $value'),
      ),
    );
  }
}

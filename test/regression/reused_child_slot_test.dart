import 'package:nocterm/nocterm.dart';
import 'package:nocterm/src/components/render_flex.dart';
import 'package:test/test.dart';

/// Regression tests for a reused child that moves among its siblings.
///
/// `Element.updateChild` updated an element whose component could be
/// updated (`Component.canUpdate`) without first moving it to its new
/// slot when the slot changed. An element reused at a different index
/// therefore kept its stale `IndexedSlot`:
///
/// * its render object was never moved in the parent's child list, and
/// * a proxy (`Expanded`, `Flexible`, `Positioned`) that replaced its
///   child passed the stale slot to the new child, which was inserted at
///   the start (stale previous sibling `null`) or appended at the end
///   (stale previous sibling no longer a child).
///
/// `ContainerRenderObjectMixin.insert`/`move` silently appended when
/// `after` was not one of its children, which hid the bug; they now
/// assert.
///
/// Every case rebuilds IN PLACE through `setState`. Re-pumping a new root
/// component would not exercise `updateChildren` the same way.
void main() {
  group('a reused child that changes index moves to its new slot', () {
    test(
        'Row [Expanded(A), B, C] -> [D, E, Expanded(spacer), B, C] lays the '
        'spacer out between E and B', () async {
      await testNocterm('expanded shifts right', (tester) async {
        await tester.pumpComponent(const _Switcher(builders: [
          _expandedFirst,
          _spacerInMiddle,
        ]));
        final state = tester.findState<_SwitcherState>();

        expect(_line(tester), '${'AAAA'.padRight(24)}BBBB  ');
        expect(_layout(state), [
          ('RenderText', 0),
          ('RenderText', 24),
          ('RenderText', 28),
        ]);

        // Switch back and forth: the first switch reuses the Expanded at
        // a shifted index with a stale previous sibling of `null`, every
        // later switch with a stale previous sibling that is defunct.
        for (var round = 0; round < 3; round++) {
          state.select(1);
          await tester.pump();
          expect(
            _layout(state),
            [
              ('RenderConstrainedBox', 0), // D: SizedBox(width: 6)
              ('RenderText', 6), // E
              ('RenderConstrainedBox', 10), // the spacer, flex 1
              ('RenderText', 24), // B
              ('RenderText', 28), // C
            ],
            reason: 'round $round: render children in component order',
          );
          expect(_line(tester), '${'DD    EEEE'.padRight(24)}BBBB  ',
              reason: 'round $round');

          state.select(0);
          await tester.pump();
          expect(
            _layout(state),
            [
              ('RenderText', 0),
              ('RenderText', 24),
              ('RenderText', 28),
            ],
            reason: 'round $round: back to the first layout',
          );
          expect(_line(tester), '${'AAAA'.padRight(24)}BBBB  ',
              reason: 'round $round');
        }
      }, size: const Size(30, 1));
    });

    test(
        'an Expanded whose child changes type while its index shifts left '
        'keeps its place before its sibling', () async {
      await testNocterm('expanded shifts left', (tester) async {
        await tester.pumpComponent(const _Switcher(builders: [
          _expandedThird,
          _expandedFirstNewChild,
        ]));
        final state = tester.findState<_SwitcherState>();
        expect(_line(tester), '${'PPQQOLD'.padRight(29)}Z');

        state.select(1);
        await tester.pump();
        expect(_layout(state), [
          ('RenderConstrainedBox', 0), // Expanded(SizedBox(child: NEW))
          ('RenderText', 29), // Z
        ]);
        expect(_line(tester), '${'NEW'.padRight(29)}Z');

        state.select(0);
        await tester.pump();
        expect(_line(tester), '${'PPQQOLD'.padRight(29)}Z');
        expect(_layout(state), [
          ('RenderText', 0),
          ('RenderText', 2),
          ('RenderText', 4),
          ('RenderText', 29),
        ]);
      }, size: const Size(30, 1));
    });

    test('a keyed reorder moves the render objects', () async {
      await testNocterm('keyed reorder', (tester) async {
        await tester.pumpComponent(const _Switcher(builders: [
          _keyedAbc,
          _keyedCab,
        ]));
        final state = tester.findState<_SwitcherState>();
        expect(_line(tester), 'A1B22C333 ');

        state.select(1);
        await tester.pump();
        expect(_line(tester), 'C333A1B22 ');
        expect(_layout(state), [
          ('RenderText', 0),
          ('RenderText', 4),
          ('RenderText', 6),
        ]);

        state.select(0);
        await tester.pump();
        expect(_line(tester), 'A1B22C333 ');
      }, size: const Size(10, 1));
    });

    test(
        'a keyed reorder of components without their own render object '
        'moves the render objects beneath them', () async {
      await testNocterm('keyed wrapper reorder', (tester) async {
        await tester.pumpComponent(const _Switcher(builders: [
          _keyedWrappersAbc,
          _keyedWrappersCab,
        ]));
        final state = tester.findState<_SwitcherState>();
        expect(_line(tester), '[a][bb][ccc] ');

        state.select(1);
        await tester.pump();
        expect(_line(tester), '[ccc][a][bb] ');

        state.select(0);
        await tester.pump();
        expect(_line(tester), '[a][bb][ccc] ');
      }, size: const Size(13, 1));
    });

    test('CONTROL: an unkeyed reorder draws the new order', () async {
      await testNocterm('unkeyed reorder', (tester) async {
        await tester.pumpComponent(const _Switcher(builders: [
          _unkeyedAbc,
          _unkeyedCab,
        ]));
        final state = tester.findState<_SwitcherState>();
        expect(_line(tester), 'A1B22C333 ');

        state.select(1);
        await tester.pump();
        expect(_line(tester), 'C333A1B22 ');

        state.select(0);
        await tester.pump();
        expect(_line(tester), 'A1B22C333 ');
      }, size: const Size(10, 1));
    });
  });

  group('ContainerRenderObjectMixin', () {
    RenderFlex flex() => RenderFlex(
          direction: Axis.horizontal,
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          textDirection: TextDirection.ltr,
          verticalDirection: VerticalDirection.down,
        );
    RenderConstrainedBox box() => RenderConstrainedBox(
          additionalConstraints: const BoxConstraints(),
        );

    test('insert asserts when `after` is not one of its children', () {
      final parent = flex();
      final a = box();
      parent.insert(a);
      expect(
        () => parent.insert(box(), after: box()),
        throwsA(isA<AssertionError>()),
      );
    });

    test('move asserts when `after` is not one of its children', () {
      final parent = flex();
      final a = box();
      final b = box();
      parent.insert(a);
      parent.insert(b, after: a);
      expect(
        () => parent.move(a, after: box()),
        throwsA(isA<AssertionError>()),
      );
    });

    test('CONTROL: insert and move place a child after `after`, or first', () {
      final parent = flex();
      final a = box();
      final b = box();
      final c = box();
      parent.insert(a);
      parent.insert(c, after: a);
      parent.insert(b, after: a);
      expect(parent.children, [a, b, c]);
      parent.move(a, after: c);
      expect(parent.children, [b, c, a]);
      parent.move(a);
      expect(parent.children, [a, b, c]);
    });
  });
}

// ---------------------------------------------------------------------------
// Layouts
// ---------------------------------------------------------------------------

Component _expandedFirst() => Row(children: [
      Expanded(child: Text('AAAA')),
      Text('BBBB'),
      Text('  '),
    ]);

Component _spacerInMiddle() => Row(children: [
      SizedBox(width: 6, child: Text('DD')),
      Text('EEEE'),
      Expanded(child: SizedBox()),
      Text('BBBB'),
      Text('  '),
    ]);

Component _expandedThird() => Row(children: [
      Text('PP'),
      Text('QQ'),
      Expanded(child: Text('OLD')),
      Text('Z'),
    ]);

Component _expandedFirstNewChild() => Row(children: [
      Expanded(child: SizedBox(child: Text('NEW'))),
      Text('Z'),
    ]);

Component _keyedAbc() => Row(children: [
      Text('A1', key: const ValueKey('a')),
      Text('B22', key: const ValueKey('b')),
      Text('C333', key: const ValueKey('c')),
    ]);

Component _keyedCab() => Row(children: [
      Text('C333', key: const ValueKey('c')),
      Text('A1', key: const ValueKey('a')),
      Text('B22', key: const ValueKey('b')),
    ]);

Component _keyedWrappersAbc() => Row(children: [
      _Bracketed('a', key: const ValueKey('a')),
      _Bracketed('bb', key: const ValueKey('b')),
      _Bracketed('ccc', key: const ValueKey('c')),
    ]);

Component _keyedWrappersCab() => Row(children: [
      _Bracketed('ccc', key: const ValueKey('c')),
      _Bracketed('a', key: const ValueKey('a')),
      _Bracketed('bb', key: const ValueKey('b')),
    ]);

Component _unkeyedAbc() => Row(children: [
      Text('A1'),
      Text('B22'),
      Text('C333'),
    ]);

Component _unkeyedCab() => Row(children: [
      Text('C333'),
      Text('A1'),
      Text('B22'),
    ]);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// The first line the tester drew.
String _line(NoctermTester tester) =>
    tester.terminalState.getText().split('\n').first;

/// The [RenderFlex] under [state], as (render type, x offset) per child in
/// child-list order.
List<(String, int)> _layout(State state) {
  RenderFlex? flex;
  void visit(Element element) {
    if (flex != null) return;
    if (element is RenderObjectElement && element.renderObject is RenderFlex) {
      flex = element.renderObject as RenderFlex;
      return;
    }
    element.visitChildren(visit);
  }

  visit(state.context as Element);
  return [
    for (final child in flex!.children)
      (
        child.runtimeType.toString(),
        (child.parentData as BoxParentData).offset.dx.round(),
      ),
  ];
}

/// Builds whichever of [builders] is selected; [select] switches in place.
class _Switcher extends StatefulComponent {
  const _Switcher({required this.builders});

  final List<Component Function()> builders;

  @override
  State<_Switcher> createState() => _SwitcherState();
}

class _SwitcherState extends State<_Switcher> {
  int _selected = 0;

  void select(int index) => setState(() => _selected = index);

  @override
  Component build(BuildContext context) => component.builders[_selected]();
}

/// A component with no render object of its own: `[label]`.
class _Bracketed extends StatelessComponent {
  const _Bracketed(this.label, {super.key});

  final String label;

  @override
  Component build(BuildContext context) => Text('[$label]');
}

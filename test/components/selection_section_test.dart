import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart' hide isEmpty;

/// Rows of a text | sidebar split, each drawn as ONE line of text the way a
/// split view composes them: 10 columns of text, ` │ `, then the sidebar.
const _splitRows = [
  'alpha one  │ side A',
  'bravo two  │ side B',
  'charlie 3  │ side C',
];

/// Band 0: the text columns. Band 1: the sidebar, from column 13 on.
const _bands = [SelectionBand(0, 10), SelectionBand(13)];

const _selection = Colors.blue;

Future<void> _drag(
  NoctermTester tester,
  (int, int) from,
  (int, int) to,
) async {
  await tester.press(from.$1, from.$2);
  await tester.sendMouseEvent(MouseEvent(
    button: MouseButton.left,
    x: to.$1,
    y: to.$2,
    pressed: true,
    isMotion: true,
  ));
  await tester.release(to.$1, to.$2);
}

bool _highlighted(NoctermTester tester, int x, int y) =>
    tester.terminalState.getCellAt(x, y)?.style.backgroundColor == _selection;

Component _area({
  required Component child,
  required void Function(String) onCompleted,
}) =>
    Container(
      width: 30,
      height: 8,
      child: SelectionArea(
        selectionColor: _selection,
        onSelectionCompleted: onCompleted,
        child: child,
      ),
    );

Component _splitSection({List<SelectionBand>? columns = _bands}) =>
    SelectionSection(
      columns: columns,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in _splitRows)
            RichText(text: TextSpan(text: row), softWrap: false),
        ],
      ),
    );

void main() {
  group('SelectionSection columns', () {
    test('a drag in the text band copies only text-band columns', () async {
      await testNocterm('text band', (tester) async {
        String? completed;
        await tester.pumpComponent(_area(
          onCompleted: (t) => completed = t,
          child: _splitSection(),
        ));

        await _drag(tester, (0, 0), (5, 2));

        expect(completed, 'alpha one \nbravo two \ncharl');
        expect(completed, isNot(contains('│')));
        expect(completed, isNot(contains('side')));
      });
    });

    test('a drag in the sidebar band copies only sidebar columns', () async {
      await testNocterm('sidebar band', (tester) async {
        String? completed;
        await tester.pumpComponent(_area(
          onCompleted: (t) => completed = t,
          child: _splitSection(),
        ));

        await _drag(tester, (13, 0), (19, 1));

        expect(completed, 'side A\nside B');
      });
    });

    test('a drag that wanders into the other band stays in its own',
        () async {
      await testNocterm('clamped to band', (tester) async {
        String? completed;
        await tester.pumpComponent(_area(
          onCompleted: (t) => completed = t,
          child: _splitSection(),
        ));

        // Press in the text, end far right in the sidebar of row 1.
        await _drag(tester, (6, 0), (19, 1));
        expect(completed, 'one \nbravo two ');

        // Press in the sidebar, end at the far left of row 2.
        await _drag(tester, (15, 0), (0, 2));
        expect(completed, 'de A\nside B');
      });
    });

    test('a press on the separator joins the nearest band', () async {
      await testNocterm('press in gap', (tester) async {
        String? completed;
        await tester.pumpComponent(_area(
          onCompleted: (t) => completed = t,
          child: _splitSection(),
        ));

        // Column 10 is the blank before the `│`: nearest the text band,
        // which ends there.
        await _drag(tester, (10, 0), (3, 1));
        expect(completed, 'bra');

        // Column 12 is the blank after it: nearest the sidebar.
        await _drag(tester, (12, 0), (17, 0));
        expect(completed, 'side');
      });
    });

    test('highlight is painted only inside the band', () async {
      await testNocterm('highlight clipped', (tester) async {
        await tester.pumpComponent(_area(
          onCompleted: (_) {},
          child: _splitSection(),
        ));

        await _drag(tester, (0, 0), (10, 2));

        for (var y = 0; y < 3; y++) {
          expect(_highlighted(tester, 0, y), isTrue, reason: 'row $y text');
          expect(_highlighted(tester, 9, y), isTrue, reason: 'row $y text');
          for (var x = 10; x < 19; x++) {
            expect(_highlighted(tester, x, y), isFalse,
                reason: 'row $y column $x is outside the text band');
          }
        }
      });
    });

    test('without columns, a section row is selected across its width',
        () async {
      await testNocterm('no columns', (tester) async {
        String? completed;
        await tester.pumpComponent(_area(
          onCompleted: (t) => completed = t,
          child: _splitSection(columns: null),
        ));

        await _drag(tester, (0, 0), (19, 0));
        expect(completed, 'alpha one  │ side A');
      });
    });

    test('side-by-side selectables read top to bottom within a band',
        () async {
      await testNocterm('no interleave', (tester) async {
        String? completed;
        await tester.pumpComponent(_area(
          onCompleted: (t) => completed = t,
          child: SelectionSection(
            columns: const [SelectionBand(0, 10), SelectionBand(11)],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < 3; i++)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 10, child: Text('left $i')),
                      const Text('│'),
                      Text('right $i'),
                    ],
                  ),
              ],
            ),
          ),
        ));

        await _drag(tester, (0, 0), (9, 2));
        expect(completed, 'left 0\nleft 1\nleft 2');

        await _drag(tester, (11, 0), (25, 2));
        expect(completed, 'right 0\nright 1\nright 2');
      });
    });
  });

  group('SelectionSection boundary', () {
    Component stacked() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            SelectionSection(child: Text('Title bar')),
            SelectionSection(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text('body one'), Text('body two')],
              ),
            ),
            SelectionSection(child: Text('status line')),
          ],
        );

    test('a drag from the title bar does not reach the body', () async {
      await testNocterm('title clamps', (tester) async {
        String? completed;
        await tester.pumpComponent(_area(
          onCompleted: (t) => completed = t,
          child: stacked(),
        ));

        await _drag(tester, (0, 0), (5, 2));
        expect(completed, 'Title bar');
      });
    });

    test('a drag from the status line does not reach the body', () async {
      await testNocterm('status clamps', (tester) async {
        String? completed;
        await tester.pumpComponent(_area(
          onCompleted: (t) => completed = t,
          child: stacked(),
        ));

        await _drag(tester, (6, 3), (0, 1));
        expect(completed, 'status');
      });
    });

    test('a drag in the body stays in the body', () async {
      await testNocterm('body clamps', (tester) async {
        String? completed;
        await tester.pumpComponent(_area(
          onCompleted: (t) => completed = t,
          child: stacked(),
        ));

        await _drag(tester, (5, 1), (3, 6));
        expect(completed, 'one\nbody two');
      });
    });

    test('a press on blank space in a section anchors only in it', () async {
      await testNocterm('late anchor', (tester) async {
        String? completed;
        await tester.pumpComponent(_area(
          onCompleted: (t) => completed = t,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              SelectionSection(
                child: SizedBox(width: 30, height: 1),
              ),
              SelectionSection(child: Text('elsewhere')),
            ],
          ),
        ));

        await _drag(tester, (2, 0), (6, 1));
        expect(completed, '');
      });
    });
  });

  group('SelectionColumns', () {
    Component page() => SelectionSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: const TextSpan(text: 'A heading wider than text'),
                softWrap: false,
              ),
              for (final row in _splitRows)
                SelectionColumns(
                  columns: _bands,
                  child: RichText(text: TextSpan(text: row), softWrap: false),
                ),
            ],
          ),
        );

    test('a drag from the full-width header continues in band 0', () async {
      await testNocterm('header to text', (tester) async {
        String? completed;
        await tester.pumpComponent(_area(
          onCompleted: (t) => completed = t,
          child: page(),
        ));

        await _drag(tester, (2, 0), (19, 2));
        expect(completed, 'heading wider than text\nalpha one \nbravo two ');
      });
    });

    test('a drag in band 1 never reaches the unsplit header', () async {
      await testNocterm('sidebar to header', (tester) async {
        String? completed;
        await tester.pumpComponent(_area(
          onCompleted: (t) => completed = t,
          child: page(),
        ));

        // Press on the last row's final `C`, drag to the header's start.
        await _drag(tester, (18, 3), (0, 0));
        expect(completed, 'side A\nside B\nside ');
      });
    });
  });

  group('SelectionSection group', () {
    /// Two titled sections stacked in ONE list, each row its own item.
    Component listOfGroups({bool grouped = true}) {
      const rows = [
        ('notes', '── Notes ──'),
        ('notes', 'note one'),
        ('notes', 'note two'),
        ('agenda', '── Agenda ──'),
        ('agenda', 'agenda one'),
        ('agenda', 'agenda two'),
      ];
      return ListView.builder(
        itemCount: rows.length,
        itemBuilder: (context, i) {
          final (group, text) = rows[i];
          final row = Text(text);
          return grouped ? SelectionSection(group: group, child: row) : row;
        },
      );
    }

    test('a drag in one group of a list never reaches the next', () async {
      await testNocterm('list group down', (tester) async {
        String? completed;
        await tester.pumpComponent(_area(
          onCompleted: (t) => completed = t,
          child: listOfGroups(),
        ));

        await _drag(tester, (5, 1), (6, 5));
        expect(completed, 'one\nnote two');
      });
    });

    test('a drag up from the second group stays in it', () async {
      await testNocterm('list group up', (tester) async {
        String? completed;
        await tester.pumpComponent(_area(
          onCompleted: (t) => completed = t,
          child: listOfGroups(),
        ));

        await _drag(tester, (6, 5), (0, 0));
        expect(completed, '── Agenda ──\nagenda one\nagenda');
      });
    });

    test('without groups the same drag runs through the whole list',
        () async {
      await testNocterm('list ungrouped', (tester) async {
        String? completed;
        await tester.pumpComponent(_area(
          onCompleted: (t) => completed = t,
          child: listOfGroups(grouped: false),
        ));

        await _drag(tester, (5, 1), (6, 5));
        expect(completed, contains('Agenda'));
      });
    });

    test('groups bound a drag outside any viewport too', () async {
      await testNocterm('column group', (tester) async {
        String? completed;
        await tester.pumpComponent(_area(
          onCompleted: (t) => completed = t,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              SelectionSection(group: 1, child: Text('first a')),
              SelectionSection(group: 1, child: Text('first b')),
              SelectionSection(group: 2, child: Text('second a')),
            ],
          ),
        ));

        await _drag(tester, (0, 0), (5, 2));
        expect(completed, 'first a\nfirst b');
      });
    });

    test('a press on blank space of a grouped row anchors in its group',
        () async {
      await testNocterm('group late anchor', (tester) async {
        String? completed;
        await tester.pumpComponent(_area(
          onCompleted: (t) => completed = t,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              SelectionSection(group: 'a', child: Text('top')),
              SelectionSection(
                group: 'a',
                child: SizedBox(width: 30, height: 1),
              ),
              SelectionSection(group: 'b', child: Text('other group')),
            ],
          ),
        ));

        // Press on the blank row of group a, drag down into group b, then
        // back up to the first row: only group a can take the anchor.
        await tester.press(10, 1);
        await tester.sendMouseEvent(const MouseEvent(
          button: MouseButton.left,
          x: 5,
          y: 2,
          pressed: true,
          isMotion: true,
        ));
        await tester.sendMouseEvent(const MouseEvent(
          button: MouseButton.left,
          x: 1,
          y: 0,
          pressed: true,
          isMotion: true,
        ));
        await tester.release(1, 0);
        expect(completed, 'op');
      });
    });
  });

  group('clips bound a selection', () {
    /// A header over a 3-row ClipRect window onto five rows, scrolled by
    /// painting the rows two cells above the window: rows 0 and 1 are cut
    /// off (and row 1 sits under the header's row).
    Component window() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('header'),
            SizedBox(
              width: 20,
              height: 3,
              child: SelectionSection(
                child: ClipRect(
                  child: Stack(
                    children: [
                      Positioned(
                        top: -2,
                        left: 0,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < 5; i++) Text('row $i'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );

    test('a drag up out of a ClipRect window copies no hidden row',
        () async {
      await testNocterm('clip rect rows', (tester) async {
        String? completed;
        await tester.pumpComponent(_area(
          onCompleted: (t) => completed = t,
          child: window(),
        ));

        // Press in `row 3` (screen row 2), drag up over the header.
        await _drag(tester, (4, 2), (0, 0));
        expect(completed, 'row 2\nrow ');
      });
    });

    test('a press on the header never anchors on a row hidden under it',
        () async {
      await testNocterm('clip rect anchor', (tester) async {
        String? completed;
        await tester.pumpComponent(_area(
          onCompleted: (t) => completed = t,
          child: window(),
        ));

        await _drag(tester, (1, 0), (5, 0));
        expect(completed, 'eade');
      });
    });

    test('columns a clip cuts off are not copied', () async {
      await testNocterm('clip rect columns', (tester) async {
        String? completed;
        await tester.pumpComponent(_area(
          onCompleted: (t) => completed = t,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 6,
              height: 2,
              child: ClipRect(
                child: Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: -3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            text: const TextSpan(text: 'abcdefghijkl'),
                            softWrap: false,
                          ),
                          RichText(
                            text: const TextSpan(text: 'ABCDEFGHIJKL'),
                            softWrap: false,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ));

        // Screen column 0 shows `d`; the window is six columns wide.
        await _drag(tester, (0, 0), (2, 1));
        expect(completed, 'defghi\nDE');
      });
    });
  });
}

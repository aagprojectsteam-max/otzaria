// Regression test: אחרי עדכון ספרייה שדורש reconcile רצו שני מסלולי אינדוקס
// חופפים על אותו רענון — ReconcileIndex (כל ספר שטביעת אצבעו השתנתה) ומיד
// אחריו ReindexChangedBooks על אותם ספרים, כ-12,000 פעולות במקום ~6,000.
//
// ⚠️ הטסט *משקף* את שרשרת ה-listeners מ-main_window_screen.dart ואינו מריץ
// אותה: בניית המסך האמיתי דורשת תשתית כבדה. כל שינוי בלוגיקה שם — לעדכן כאן.

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';

class MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class MockLibraryUpdateBloc
    extends MockBloc<LibraryUpdateEvent, LibraryUpdateState>
    implements LibraryUpdateBloc {}

class MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

/// חיקוי של שרשרת ה-listeners: עדכון ספרייה → reloadCompleted → changed → new,
/// באותו סדר קינון שבמסך האמיתי (החיצוני נרשם ראשון ולכן נורה ראשון).
class _TestWidget extends StatefulWidget {
  final List<Object> capturedEvents;

  const _TestWidget({required this.capturedEvents});

  @override
  State<_TestWidget> createState() => _TestWidgetState();
}

class _TestWidgetState extends State<_TestWidget> {
  bool _indexAfterLibraryReload = false;
  bool _reconcileAfterLibraryReload = false;
  LibraryState? _refreshCoveredByStartIndexing;
  LibraryState? _refreshCoveredByReconcile;

  void _indexAfterDbUpdateIfNeeded(BuildContext context, LibraryState state) {
    if (!_indexAfterLibraryReload) {
      _reconcileAfterLibraryReload = false;
      return;
    }
    _indexAfterLibraryReload = false;
    final reconcile = _reconcileAfterLibraryReload;
    _reconcileAfterLibraryReload = false;
    if (!context.read<SettingsBloc>().state.autoUpdateIndex) return;
    widget.capturedEvents.add(StartIndexing(state.library!));
    _refreshCoveredByStartIndexing = state;
    if (reconcile) {
      widget.capturedEvents.add(ReconcileIndex(state.library!));
      _refreshCoveredByReconcile = state;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<LibraryUpdateBloc, LibraryUpdateState>(
          listenWhen: LibraryUpdateState.hasRefreshRelevantChange,
          listener: (context, state) {
            if ((state.status == LibraryUpdateStatus.completed ||
                    state.status == LibraryUpdateStatus.error) &&
                state.hasUpdate) {
              _indexAfterLibraryReload = true;
              _reconcileAfterLibraryReload =
                  state.isFullDownloadPlan || state.requiresFullIndexRefresh;
            }
          },
        ),
        BlocListener<LibraryBloc, LibraryState>(
          listenWhen: LibraryState.reloadCompleted,
          listener: _indexAfterDbUpdateIfNeeded,
        ),
        BlocListener<LibraryBloc, LibraryState>(
          listenWhen: (previous, current) =>
              current.changedBooksToIndex != null &&
              current.changedBooksToIndex!.isNotEmpty,
          listener: (context, state) {
            if (identical(state, _refreshCoveredByReconcile)) return;
            if (context.read<SettingsBloc>().state.autoUpdateIndex) {
              widget.capturedEvents.add(
                ReindexChangedBooks(state.changedBooksToIndex!, state.library!),
              );
            }
          },
        ),
        BlocListener<LibraryBloc, LibraryState>(
          listenWhen: (previous, current) =>
              current.newBooksToIndex != null &&
              current.newBooksToIndex!.isNotEmpty,
          listener: (context, state) {
            if (identical(state, _refreshCoveredByStartIndexing)) return;
            if (context.read<SettingsBloc>().state.autoUpdateIndex) {
              widget.capturedEvents.add(
                IndexSpecificBooks(state.newBooksToIndex!, state.library!),
              );
            } else {
              widget.capturedEvents.add(CheckIndexStatus(state.library!));
            }
          },
        ),
      ],
      child: const SizedBox.shrink(),
    );
  }
}

Library _emptyLibrary() => Library(categories: []);

LibraryState _refreshedState({
  bool withChanged = true,
  bool withNew = true,
}) {
  final library = _emptyLibrary();
  return LibraryState(
    library: library,
    isLoading: false,
    changedBooksToIndex: withChanged ? [TextBook(title: 'ספר שהשתנה')] : null,
    newBooksToIndex: withNew ? [TextBook(title: 'ספר חדש')] : null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('דה-דופליקציה של מסלולי האינדוקס באותו רענון', () {
    late MockLibraryBloc libraryBloc;
    late MockLibraryUpdateBloc libraryUpdateBloc;
    late MockSettingsBloc settingsBloc;
    late StreamController<LibraryState> libraryStates;
    late StreamController<LibraryUpdateState> updateStates;
    late List<Object> capturedEvents;

    setUp(() {
      libraryStates = StreamController<LibraryState>.broadcast();
      updateStates = StreamController<LibraryUpdateState>.broadcast();
      libraryBloc = MockLibraryBloc();
      libraryUpdateBloc = MockLibraryUpdateBloc();
      settingsBloc = MockSettingsBloc();
      capturedEvents = [];

      // isLoading: true — reloadCompleted דורש מעבר מטעינה לסיום.
      whenListen(
        libraryBloc,
        libraryStates.stream,
        initialState: LibraryState(library: _emptyLibrary(), isLoading: true),
      );
      whenListen(
        libraryUpdateBloc,
        updateStates.stream,
        initialState: const LibraryUpdateState(),
      );
    });

    tearDown(() {
      libraryStates.close();
      updateStates.close();
    });

    Future<void> pump(WidgetTester tester, {required bool autoUpdate}) async {
      whenListen(
        settingsBloc,
        const Stream<SettingsState>.empty(),
        initialState: SettingsState.initial().copyWith(
          autoUpdateIndex: autoUpdate,
        ),
      );
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<LibraryBloc>.value(value: libraryBloc),
            BlocProvider<LibraryUpdateBloc>.value(value: libraryUpdateBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: MaterialApp(
            home: _TestWidget(capturedEvents: capturedEvents),
          ),
        ),
      );
    }

    Future<void> emitUpdateCompleted(
      WidgetTester tester, {
      required bool requiresFullIndexRefresh,
    }) async {
      updateStates.add(
        LibraryUpdateState(
          status: LibraryUpdateStatus.completed,
          hasUpdate: true,
          changedBookIds: const {1, 2},
          requiresFullIndexRefresh: requiresFullIndexRefresh,
        ),
      );
      await tester.pump();
    }

    testWidgets(
      'reconcile באותו רענון — רק StartIndexing ו-ReconcileIndex, בלי מסלול שני',
      (tester) async {
        await pump(tester, autoUpdate: true);
        await emitUpdateCompleted(tester, requiresFullIndexRefresh: true);

        libraryStates.add(_refreshedState());
        await tester.pump();

        expect(capturedEvents, hasLength(2));
        expect(capturedEvents[0], isA<StartIndexing>());
        expect(capturedEvents[1], isA<ReconcileIndex>());
        expect(
          capturedEvents.whereType<ReindexChangedBooks>(),
          isEmpty,
          reason: 'ReconcileIndex כבר מאנדקס מחדש כל ספר שהשתנה',
        );
        expect(
          capturedEvents.whereType<IndexSpecificBooks>(),
          isEmpty,
          reason: 'StartIndexing כבר מכסה את הספרים החדשים',
        );
      },
    );

    testWidgets('בלי reconcile — ReindexChangedBooks כן מוזרם כרגיל', (
      tester,
    ) async {
      await pump(tester, autoUpdate: true);
      await emitUpdateCompleted(tester, requiresFullIndexRefresh: false);

      libraryStates.add(_refreshedState());
      await tester.pump();

      expect(
        capturedEvents.whereType<ReconcileIndex>(),
        isEmpty,
        reason: 'עדכון דלתא רגיל אינו מריץ reconcile',
      );
      expect(
        capturedEvents.whereType<ReindexChangedBooks>(),
        hasLength(1),
        reason:
            'StartIndexing מדלג על ספרים קיימים — השונים חייבים מסלול משלהם',
      );
    });

    testWidgets('רענון ללא עדכון ספרייה — רק ReindexChangedBooks', (
      tester,
    ) async {
      await pump(tester, autoUpdate: true);

      libraryStates.add(_refreshedState(withNew: false));
      await tester.pump();

      expect(capturedEvents, hasLength(1));
      expect(capturedEvents.single, isA<ReindexChangedBooks>());
    });

    testWidgets('אינדוקס אוטומטי כבוי — אין אינדוקס, רק CheckIndexStatus', (
      tester,
    ) async {
      await pump(tester, autoUpdate: false);
      await emitUpdateCompleted(tester, requiresFullIndexRefresh: true);

      libraryStates.add(_refreshedState());
      await tester.pump();

      expect(capturedEvents.whereType<IndexingWorkEvent>(), isEmpty);
      expect(capturedEvents.whereType<CheckIndexStatus>(), hasLength(1));
    });
  });
}

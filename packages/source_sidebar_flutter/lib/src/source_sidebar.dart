import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shipglows_flutter_zoom/shipglows_flutter_zoom.dart';

import 'source_category.dart';
import 'grouped_section_header.dart';
import 'source_move_destination.dart';
import 'source_sidebar_item.dart';
import 'source_sidebar_shortcuts.dart';
import 'source_sidebar_style.dart';
import 'source_workspace_actions.dart';

class SourceSidebar extends StatefulWidget {
  const SourceSidebar({
    required this.items,
    required this.onSelected,
    super.key,
    this.title = 'Sources',
    this.selectedId,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.errorMessage,
    this.emptyMessage = 'No sources to review.',
    this.style = const SourceSidebarStyle(),
    this.onRefresh,
    this.refreshTooltip = 'Refresh sources',
    this.onLoadMore,
    this.onOpenLibrary,
    this.onIngest,
    this.onMarkSeen,
    this.onArchive,
    this.onDelete,
    this.onOpenExternal,
    this.onMove,
    this.moveDestinations = const <SourceMoveDestination>[],
    this.laterDestinationId,
    this.categories = const <SourceCategory>[],
    this.shortcuts = const SourceSidebarShortcuts(),
    this.topBarActions = const <Widget>[],
    this.accounts = const <SourceAccount>[],
    this.currentAccountId,
    this.onAccountSelected,
    this.onSummarize,
    this.projectDestinations = const <SourceProjectDestination>[],
    this.onDistribute,
    this.onActionError,
    this.navigationHeader,
    this.itemSectionIds = const <String, String>{},
    this.sectionLabels = const <String, String>{},
    this.sectionEmptyMessages = const <String, String>{},
    this.sectionKeys = const <String, GlobalKey>{},
    this.readerFooter,
    this.readerBody,
    this.searchHint,
  });

  final String title;
  final List<SourceSidebarItem> items;
  final String? selectedId;
  final ValueChanged<String?> onSelected;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? errorMessage;
  final String emptyMessage;
  final SourceSidebarStyle style;
  final Future<void> Function()? onRefresh;
  final String refreshTooltip;
  final Future<void> Function()? onLoadMore;
  final Future<void> Function()? onOpenLibrary;
  final SourceItemCallback? onIngest;
  final SourceItemCallback? onMarkSeen;
  final SourceItemCallback? onArchive;
  final SourceItemCallback? onDelete;
  final SourceItemCallback? onOpenExternal;
  final SourceMoveCallback? onMove;
  final List<SourceMoveDestination> moveDestinations;
  final String? laterDestinationId;
  final List<SourceCategory> categories;
  final SourceSidebarShortcuts shortcuts;
  final List<Widget> topBarActions;
  final List<SourceAccount> accounts;
  final String? currentAccountId;
  final SourceAccountCallback? onAccountSelected;
  final SourceSummaryCallback? onSummarize;
  final List<SourceProjectDestination> projectDestinations;
  final SourceDistributionCallback? onDistribute;
  final SourceActionErrorCallback? onActionError;

  /// Host navigation inserted above the existing filters on every layout.
  final Widget? navigationHeader;

  /// Optional ordered groups sharing the same source rows and reader.
  /// Items without a known mapping belong to the first declared section.
  final Map<String, String> itemSectionIds;
  final Map<String, String> sectionLabels;
  final Map<String, String> sectionEmptyMessages;
  final Map<String, GlobalKey> sectionKeys;

  /// Contextual actions/composer in the existing reader's scroll surface.
  final Widget? readerFooter;

  /// Host-supplied enriched content replacing the default plain text body.
  final Widget? readerBody;

  /// Search scope label supplied by hosts backed by paged data.
  final String? searchHint;

  @override
  State<SourceSidebar> createState() => _SourceSidebarState();
}

class _SourceSidebarState extends State<SourceSidebar> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _workspaceFocus = FocusNode(debugLabel: 'Source sidebar workspace');
  final _listScrollController = ScrollController();
  final _readerScrollController = ScrollController();
  final _rowKeys = <String, GlobalKey>{};
  final _rowFocusNodes = <String, FocusNode>{};
  String _query = '';
  String _filterId = _FilterId.inbox;
  String? _pendingAction;
  String? _activeId;
  final _collapsedSections = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _workspaceFocus.dispose();
    _listScrollController.dispose();
    _readerScrollController.dispose();
    for (final node in _rowFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SourceSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.laterDestinationId == null && _filterId == _FilterId.later) {
      _filterId = _FilterId.inbox;
    }
    if (widget.selectedId == null && oldWidget.selectedId != null) {
      _activeId = oldWidget.selectedId;
      _restoreWorkspaceFocus();
    }
    if (_activeId != null &&
        !widget.items.any((item) => item.id == _activeId)) {
      _activeId = null;
    }
    final itemIds = widget.items.map((item) => item.id).toSet();
    final removedIds = _rowFocusNodes.keys
        .where((id) => !itemIds.contains(id))
        .toList(growable: false);
    for (final id in removedIds) {
      _rowFocusNodes.remove(id)?.dispose();
      _rowKeys.remove(id);
    }
  }

  SourceSidebarColors get _colors =>
      widget.style.colors ??
      SourceSidebarColors.fromColorScheme(Theme.of(context).colorScheme);

  Map<String, SourceCategory> get _categoryById => {
    for (final category in widget.categories) category.id: category,
  };

  SourceCategory _categoryFor(String id) {
    return _categoryById[id] ??
        SourceCategory(
          id: id,
          name: id,
          color: _colors.focus.withValues(
            alpha: widget.style.categoryFallbackOpacity,
          ),
          icon: Icons.label_outline,
        );
  }

  List<SourceSidebarItem> get _visibleItems {
    final query = _query.trim().toLowerCase();
    final visible = widget.items
        .where((item) {
          final matchesQuery =
              query.isEmpty ||
              item.title.toLowerCase().contains(query) ||
              item.authorOrPublisher.toLowerCase().contains(query) ||
              item.summary.toLowerCase().contains(query) ||
              item.tags.any(
                (tag) =>
                    tag.toLowerCase().contains(query) ||
                    _categoryFor(tag).name.toLowerCase().contains(query),
              );
          if (!matchesQuery) return false;
          return switch (_filterId) {
            _FilterId.inbox =>
              item.location != 'archive' &&
                  (widget.laterDestinationId == null ||
                      item.location != widget.laterDestinationId),
            _FilterId.unread => !item.seen && item.location != 'archive',
            _FilterId.processed =>
              item.processingState == SourceProcessingState.processed,
            _FilterId.archive => item.location == 'archive',
            _FilterId.later =>
              widget.laterDestinationId != null &&
                  item.location == widget.laterDestinationId,
            _ =>
              _filterId.startsWith(_FilterId.tagPrefix)
                  ? item.tags.contains(
                      _filterId.substring(_FilterId.tagPrefix.length),
                    )
                  : true,
          };
        })
        .toList(growable: false);
    if (widget.sectionLabels.isEmpty) return visible;
    return [
      for (final section in widget.sectionLabels.keys)
        ...visible.where((item) => _sectionFor(item.id) == section),
    ];
  }

  String _sectionFor(String itemId) {
    final section = widget.itemSectionIds[itemId];
    return widget.sectionLabels.containsKey(section)
        ? section!
        : widget.sectionLabels.keys.first;
  }

  SourceSidebarItem? get _selectedItem {
    final selectedId = widget.selectedId;
    if (selectedId == null) return null;
    for (final item in widget.items) {
      if (item.id == selectedId) return item;
    }
    return null;
  }

  List<String> get _tags {
    final counts = <String, int>{};
    for (final item in widget.items) {
      for (final tag in item.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final tags = counts.keys.toList()
      ..sort((a, b) {
        final countOrder = counts[b]!.compareTo(counts[a]!);
        return countOrder == 0 ? a.compareTo(b) : countOrder;
      });
    return tags.take(6).toList(growable: false);
  }

  double _navigationWidth(BuildContext context) {
    final entries = <(String, int)>[
      ('Inbox', _countFor(_FilterId.inbox)),
      ('Unread', _countFor(_FilterId.unread)),
      ('Processed', _countFor(_FilterId.processed)),
      if (widget.laterDestinationId != null)
        ('Later', _countFor(_FilterId.later)),
      ('Archived', _countFor(_FilterId.archive)),
      for (final tag in _tags)
        (_categoryFor(tag).name, _countFor('${_FilterId.tagPrefix}$tag')),
    ];
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontSize: (Theme.of(context).textTheme.bodyMedium?.fontSize ?? 14) * 1.5,
    );
    final scaler = MediaQuery.textScalerOf(context);
    double measure(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: textStyle),
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout();
      return painter.width;
    }

    final widest = entries.fold<double>(0, (current, entry) {
      final countWidth = entry.$2 == 0
          ? 0
          : widget.style.gapLarge + measure('${entry.$2}');
      return math.max(current, measure(entry.$1) + countWidth);
    });
    final chrome = 36 + widget.style.actionIconSize + widget.style.gapLarge;
    return (widest + chrome)
        .clamp(
          216,
          MediaQuery.sizeOf(context).width - widget.style.gapLarge * 2,
        )
        .toDouble();
  }

  int _countFor(String filterId) {
    return switch (filterId) {
      _FilterId.inbox =>
        widget.items
            .where(
              (item) =>
                  item.location != 'archive' &&
                  (widget.laterDestinationId == null ||
                      item.location != widget.laterDestinationId),
            )
            .length,
      _FilterId.unread =>
        widget.items
            .where((item) => !item.seen && item.location != 'archive')
            .length,
      _FilterId.processed =>
        widget.items
            .where(
              (item) => item.processingState == SourceProcessingState.processed,
            )
            .length,
      _FilterId.archive =>
        widget.items.where((item) => item.location == 'archive').length,
      _FilterId.later =>
        widget.laterDestinationId == null
            ? 0
            : widget.items
                  .where((item) => item.location == widget.laterDestinationId)
                  .length,
      _ =>
        filterId.startsWith(_FilterId.tagPrefix)
            ? widget.items
                  .where(
                    (item) => item.tags.contains(
                      filterId.substring(_FilterId.tagPrefix.length),
                    ),
                  )
                  .length
            : 0,
    };
  }

  String get _filterLabel {
    return switch (_filterId) {
      _FilterId.inbox => 'Inbox',
      _FilterId.unread => 'Unread',
      _FilterId.processed => 'Processed',
      _FilterId.archive => 'Archived',
      _FilterId.later => 'Later',
      _ =>
        _filterId.startsWith(_FilterId.tagPrefix)
            ? _categoryFor(_filterId.substring(_FilterId.tagPrefix.length)).name
            : 'Sources',
    };
  }

  void _selectFilter(String id) {
    setState(() {
      _filterId = id;
      _activeId = null;
    });
    widget.onSelected(null);
  }

  void _moveSelection(int delta) {
    if (_isEditingText) return;
    final items = _visibleItems;
    if (items.isEmpty) return;
    final readerOpen = _selectedItem != null;
    final currentId = readerOpen ? widget.selectedId : _activeId;
    final current = items.indexWhere((item) => item.id == currentId);
    final next = current < 0
        ? 0
        : (current + delta).clamp(0, items.length - 1).toInt();
    if (readerOpen) {
      widget.onSelected(items[next].id);
    } else {
      setState(() => _activeId = items[next].id);
      _focusActiveRow();
      _ensureActiveVisible();
    }
  }

  bool get _isEditingText {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    return focusContext.widget is EditableText ||
        focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  SourceSidebarItem? get _actionItem {
    final selected = _selectedItem;
    if (selected != null) return selected;
    final activeId = _activeId;
    if (activeId == null) return null;
    for (final item in _visibleItems) {
      if (item.id == activeId) return item;
    }
    return null;
  }

  void _openActive() {
    if (_isEditingText) return;
    final item =
        _actionItem ?? (_visibleItems.isEmpty ? null : _visibleItems.first);
    if (item != null) widget.onSelected(item.id);
  }

  void _closeReader() {
    if (_selectedItem == null) return;
    _activeId = widget.selectedId;
    widget.onSelected(null);
    _restoreWorkspaceFocus();
  }

  void _restoreWorkspaceFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_selectedItem == null) {
        final visibleItems = _visibleItems;
        final activeIsVisible = visibleItems.any(
          (item) => item.id == _activeId,
        );
        if (!activeIsVisible) {
          setState(() {
            _activeId = visibleItems.isEmpty ? null : visibleItems.first.id;
          });
        }
      }
      final rowFocus = _rowFocusNodes[_activeId];
      if (rowFocus?.context != null) {
        rowFocus!.requestFocus();
      } else {
        _workspaceFocus.requestFocus();
      }
      _ensureActiveVisible();
    });
  }

  void _ensureActiveVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final rowContext = _rowKeys[_activeId]?.currentContext;
      if (rowContext != null && rowContext.mounted) {
        Scrollable.ensureVisible(
          rowContext,
          alignment: 0.5,
          duration: widget.style.keyboardScrollDuration,
        );
        return;
      }
      if (!_listScrollController.hasClients) return;
      final index = _visibleItems.indexWhere((item) => item.id == _activeId);
      if (index < 0) return;
      var estimatedOffset =
          index * (widget.style.denseRowHeight + widget.style.dividerThickness);
      if (widget.sectionLabels.isNotEmpty) {
        final sectionIndex = widget.sectionLabels.keys.toList().indexOf(
          _sectionFor(_activeId!),
        );
        estimatedOffset +=
            (sectionIndex + 1) * widget.style.toolbarHeight +
            sectionIndex * widget.style.gap4XLarge;
      }
      _listScrollController.animateTo(
        estimatedOffset
            .clamp(0, _listScrollController.position.maxScrollExtent)
            .toDouble(),
        duration: widget.style.keyboardScrollDuration,
        curve: Curves.easeOut,
      );
    });
  }

  void _focusActiveRow() {
    final rowFocus = _rowFocusNodes[_activeId];
    if (rowFocus?.context != null) {
      rowFocus!.requestFocus();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _rowFocusNodes[_activeId]?.requestFocus();
    });
  }

  Future<void> _runAction(
    String name,
    SourceSidebarItem item,
    SourceItemCallback callback,
  ) async {
    if (_pendingAction != null) return;
    setState(() => _pendingAction = name);
    try {
      await callback(item);
    } catch (error) {
      widget.onActionError?.call(error);
    } finally {
      if (mounted) {
        setState(() => _pendingAction = null);
        _restoreWorkspaceFocus();
      }
    }
  }

  void _scrollReader(double amount) {
    if (_selectedItem == null || !_readerScrollController.hasClients) return;
    final position = _readerScrollController.position;
    _readerScrollController.animateTo(
      (position.pixels + amount).clamp(0.0, position.maxScrollExtent),
      duration: widget.style.keyboardScrollDuration,
      curve: Curves.easeOut,
    );
  }

  void _scrollReaderBoundary(bool end) {
    if (_selectedItem == null || !_readerScrollController.hasClients) return;
    _readerScrollController.animateTo(
      end ? _readerScrollController.position.maxScrollExtent : 0,
      duration: widget.style.keyboardScrollDuration,
      curve: Curves.easeOut,
    );
  }

  Future<void> _switchAccount(int delta) async {
    if (_pendingAction != null ||
        widget.onAccountSelected == null ||
        widget.accounts.isEmpty) {
      return;
    }
    final current = widget.accounts.indexWhere(
      (account) => account.id == widget.currentAccountId,
    );
    final next = (current < 0 ? 0 : current + delta).clamp(
      0,
      widget.accounts.length - 1,
    );
    await _selectAccount(widget.accounts[next]);
  }

  Future<void> _selectAccount(SourceAccount account) async {
    if (_pendingAction != null || widget.onAccountSelected == null) return;
    setState(() => _pendingAction = 'account:${account.id}');
    try {
      await widget.onAccountSelected!(account);
    } catch (error) {
      widget.onActionError?.call(error);
    } finally {
      if (mounted) {
        setState(() {
          _pendingAction = null;
          _activeId = null;
        });
        _restoreWorkspaceFocus();
      }
    }
  }

  Future<void> _showAccountChooser() async {
    if (widget.onAccountSelected == null || widget.accounts.isEmpty) return;
    final account = await showDialog<SourceAccount>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose account'),
        children: widget.accounts
            .map(
              (account) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, account),
                child: Row(
                  children: [
                    Icon(
                      account.id == widget.currentAccountId
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    SizedBox(width: widget.style.gapMedium),
                    Expanded(child: Text(account.label)),
                  ],
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
    if (account != null) {
      await _selectAccount(account);
    } else {
      _restoreWorkspaceFocus();
    }
  }

  Future<void> _showDistributionChooser(SourceSidebarItem item) async {
    if (widget.onDistribute == null || widget.projectDestinations.isEmpty) {
      return;
    }
    final selected = <String>{};
    final result = await showDialog<List<SourceProjectDestination>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Send to projects'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: widget.projectDestinations
                  .map(
                    (project) => CheckboxListTile(
                      value: selected.contains(project.id),
                      title: Text(project.label),
                      onChanged: (checked) => setDialogState(
                        () => checked == true
                            ? selected.add(project.id)
                            : selected.remove(project.id),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(
                      context,
                      widget.projectDestinations
                          .where((project) => selected.contains(project.id))
                          .toList(growable: false),
                    ),
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );
    if (result == null || result.isEmpty) {
      _restoreWorkspaceFocus();
      return;
    }
    if (_pendingAction != null) return;
    setState(() => _pendingAction = 'distribute');
    try {
      await widget.onDistribute!(item, result);
    } catch (error) {
      widget.onActionError?.call(error);
    } finally {
      if (mounted) {
        setState(() => _pendingAction = null);
        _restoreWorkspaceFocus();
      }
    }
  }

  Future<void> _confirmDelete(SourceSidebarItem item) async {
    final callback = widget.onDelete;
    if (callback == null || _pendingAction != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this source?'),
        content: Text(
          '“${item.title}” will be removed from the shared source library.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _runAction('delete', item, callback);
    } else {
      _restoreWorkspaceFocus();
    }
  }

  Future<void> _showMoveChooser(SourceSidebarItem item) async {
    final callback = widget.onMove;
    if (callback == null || widget.moveDestinations.isEmpty) return;
    final destination = await showDialog<SourceMoveDestination>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Move source'),
        children: widget.moveDestinations
            .map(
              (destination) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, destination),
                child: Text(destination.label),
              ),
            )
            .toList(growable: false),
      ),
    );
    if (destination != null) {
      await _runMove(item, destination, callback);
    } else {
      _restoreWorkspaceFocus();
    }
  }

  Future<void> _runMove(
    SourceSidebarItem item,
    SourceMoveDestination destination,
    SourceMoveCallback callback,
  ) async {
    if (_pendingAction != null) return;
    setState(() => _pendingAction = 'move:${destination.id}');
    try {
      await callback(item, destination);
    } finally {
      if (mounted) {
        setState(() => _pendingAction = null);
        _restoreWorkspaceFocus();
      }
    }
  }

  void _moveToLater() {
    if (_isEditingText || widget.onMove == null) return;
    final item = _actionItem;
    final laterId = widget.laterDestinationId;
    if (item == null || laterId == null) return;
    for (final destination in widget.moveDestinations) {
      if (destination.id == laterId) {
        _runMove(item, destination, widget.onMove!);
        return;
      }
    }
  }

  void _archiveActive() {
    if (_isEditingText || widget.onArchive == null) return;
    final item = _actionItem;
    if (item != null) _runAction('archive', item, widget.onArchive!);
  }

  void _deleteActive() {
    if (_isEditingText) return;
    final item = _actionItem;
    if (item != null) _confirmDelete(item);
  }

  void _showMoveForActive() {
    if (_isEditingText) return;
    final item = _actionItem;
    if (item != null) _showMoveChooser(item);
  }

  Future<void> _showKeyboardHelp() async {
    if (_isEditingText) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keyboard shortcuts'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [..._helpRows, const Text('Tab / Shift+Tab  Move focus')],
          ),
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    _restoreWorkspaceFocus();
  }

  List<Widget> get _helpRows {
    final rows = <Widget>[];
    void add(List<ShortcutActivator> bindings, String label) {
      if (bindings.isEmpty) return;
      rows.add(Text('${_formatBindings(bindings)}  $label'));
    }

    add(widget.shortcuts.next, 'Next source');
    add(widget.shortcuts.previous, 'Previous source');
    add(widget.shortcuts.open, 'Open source');
    add(widget.shortcuts.focusSearch, 'Search');
    add(widget.shortcuts.back, 'Back to list');
    if (widget.onArchive != null) {
      add(widget.shortcuts.archive, 'Archive');
    }
    if (widget.onDelete != null) {
      add(widget.shortcuts.delete, 'Delete with confirmation');
    }
    if (widget.onMove != null && widget.moveDestinations.isNotEmpty) {
      add(widget.shortcuts.move, 'Move…');
    }
    final laterId = widget.laterDestinationId;
    final canMoveToLater =
        widget.onMove != null &&
        laterId != null &&
        widget.moveDestinations.any((destination) => destination.id == laterId);
    if (canMoveToLater) {
      add(widget.shortcuts.moveToLater, 'Move to Later');
    }
    if (_selectedItem != null) {
      add(widget.shortcuts.readerLineDown, 'Read down one line');
      add(widget.shortcuts.readerLineUp, 'Read up one line');
      add(widget.shortcuts.readerPageDown, 'Read next page');
      add(widget.shortcuts.readerPageUp, 'Read previous page');
      add(widget.shortcuts.readerStart, 'Start of message');
      add(widget.shortcuts.readerEnd, 'End of message');
    }
    if (widget.onAccountSelected != null && widget.accounts.isNotEmpty) {
      add(widget.shortcuts.nextAccount, 'Next account');
      add(widget.shortcuts.previousAccount, 'Previous account');
      add(widget.shortcuts.chooseAccount, 'Choose account');
    }
    if (widget.onSummarize != null) {
      add(widget.shortcuts.summarize, 'Summarize');
    }
    if (widget.onDistribute != null && widget.projectDestinations.isNotEmpty) {
      add(widget.shortcuts.distribute, 'Send to projects');
    }
    if (widget.onIngest != null) {
      add(widget.shortcuts.ingest, 'Send to project');
    }
    add(widget.shortcuts.resetZoom, 'Reset zoom');
    add(widget.shortcuts.help, 'Show this help');
    return rows;
  }

  String _formatBindings(List<ShortcutActivator> bindings) {
    return bindings.map(_formatBinding).join(' / ');
  }

  String _formatBinding(ShortcutActivator binding) {
    if (binding is! SingleActivator) return binding.toString();
    final parts = <String>[
      if (binding.control) 'Ctrl',
      if (binding.meta) '⌘',
      if (binding.alt) 'Alt',
      if (binding.shift) 'Shift',
    ];
    final trigger = binding.trigger;
    final key = switch (trigger) {
      LogicalKeyboardKey.arrowDown => '↓',
      LogicalKeyboardKey.arrowUp => '↑',
      LogicalKeyboardKey.enter => 'Enter',
      LogicalKeyboardKey.escape => 'Escape',
      LogicalKeyboardKey.slash when binding.shift => '?',
      _ => trigger.keyLabel.toUpperCase(),
    };
    if (key == '?' && parts.isNotEmpty && parts.last == 'Shift') {
      parts.removeLast();
    }
    parts.add(key);
    return parts.join('+');
  }

  Map<ShortcutActivator, Intent> get _shortcutMap {
    final shortcuts = <ShortcutActivator, Intent>{};
    void bind(List<ShortcutActivator> activators, Intent intent) {
      for (final activator in activators) {
        shortcuts[activator] = intent;
      }
    }

    bind(widget.shortcuts.next, const _NextSourceIntent());
    bind(widget.shortcuts.previous, const _PreviousSourceIntent());
    for (final activator in widget.shortcuts.open) {
      final isNativeEnter =
          activator is SingleActivator &&
          activator.trigger == LogicalKeyboardKey.enter &&
          !activator.control &&
          !activator.meta &&
          !activator.alt &&
          !activator.shift;
      shortcuts[activator] = isNativeEnter
          ? const _OpenSourceFromWorkspaceIntent()
          : const _OpenSourceIntent();
    }
    bind(widget.shortcuts.focusSearch, const _FocusSearchIntent());
    bind(widget.shortcuts.back, const _CloseReaderIntent());
    bind(widget.shortcuts.archive, const _ArchiveSourceIntent());
    bind(widget.shortcuts.delete, const _DeleteSourceIntent());
    bind(widget.shortcuts.move, const _MoveSourceIntent());
    bind(widget.shortcuts.moveToLater, const _MoveToLaterIntent());
    bind(widget.shortcuts.readerLineDown, const _ReaderLineDownIntent());
    bind(widget.shortcuts.readerLineUp, const _ReaderLineUpIntent());
    bind(widget.shortcuts.readerPageDown, const _ReaderPageDownIntent());
    bind(widget.shortcuts.readerPageUp, const _ReaderPageUpIntent());
    bind(widget.shortcuts.readerStart, const _ReaderStartIntent());
    bind(widget.shortcuts.readerEnd, const _ReaderEndIntent());
    bind(widget.shortcuts.nextAccount, const _NextAccountIntent());
    bind(widget.shortcuts.previousAccount, const _PreviousAccountIntent());
    bind(widget.shortcuts.chooseAccount, const _ChooseAccountIntent());
    bind(widget.shortcuts.summarize, const _SummarizeIntent());
    bind(widget.shortcuts.distribute, const _DistributeIntent());
    bind(widget.shortcuts.ingest, const _IngestIntent());
    bind(widget.shortcuts.help, const _KeyboardHelpIntent());
    return shortcuts;
  }

  Future<void> _showNavigationSheet() async {
    final panelWidth = _navigationWidth(context);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Fermer la navigation',
      barrierColor: Colors.black54,
      pageBuilder: (dialogContext, _, _) => Align(
        alignment: Alignment.centerLeft,
        child: SafeArea(
          child: SizedBox(
            width: panelWidth,
            child: _NavigationPane(
              navigationHeader: widget.navigationHeader,
              title: widget.title,
              style: widget.style,
              colors: _colors,
              selectedFilterId: _filterId,
              showLater: widget.laterDestinationId != null,
              tags: _tags,
              categoryFor: _categoryFor,
              countFor: _countFor,
              onOpenLibrary: widget.onOpenLibrary,
              onFilterSelected: (id) {
                Navigator.pop(dialogContext);
                _selectFilter(id);
              },
            ),
          ),
        ),
      ),
    );
    _restoreWorkspaceFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: _shortcutMap,
      child: Actions(
        actions: {
          _NextSourceIntent: _GuardedAction<_NextSourceIntent>(
            canInvoke: () => !_isEditingText,
            onInvoke: (_) => _moveSelection(1),
          ),
          _PreviousSourceIntent: _GuardedAction<_PreviousSourceIntent>(
            canInvoke: () => !_isEditingText,
            onInvoke: (_) => _moveSelection(-1),
          ),
          _FocusSearchIntent: _GuardedAction<_FocusSearchIntent>(
            canInvoke: () => !_isEditingText,
            onInvoke: (_) => _searchFocus.requestFocus(),
          ),
          _CloseReaderIntent: _GuardedAction<_CloseReaderIntent>(
            canInvoke: () => !_isEditingText,
            onInvoke: (_) => _closeReader(),
          ),
          _OpenSourceIntent: _GuardedAction<_OpenSourceIntent>(
            canInvoke: () => !_isEditingText,
            onInvoke: (_) => _openActive(),
          ),
          _OpenSourceFromWorkspaceIntent: _WorkspaceOpenAction(
            isWorkspaceFocused: () => _workspaceFocus.hasPrimaryFocus,
            onOpen: _openActive,
          ),
          _ArchiveSourceIntent: _GuardedAction<_ArchiveSourceIntent>(
            canInvoke: () => !_isEditingText,
            onInvoke: (_) => _archiveActive(),
          ),
          _DeleteSourceIntent: _GuardedAction<_DeleteSourceIntent>(
            canInvoke: () => !_isEditingText,
            onInvoke: (_) => _deleteActive(),
          ),
          _MoveSourceIntent: _GuardedAction<_MoveSourceIntent>(
            canInvoke: () => !_isEditingText,
            onInvoke: (_) => _showMoveForActive(),
          ),
          _MoveToLaterIntent: _GuardedAction<_MoveToLaterIntent>(
            canInvoke: () => !_isEditingText,
            onInvoke: (_) => _moveToLater(),
          ),
          _KeyboardHelpIntent: _GuardedAction<_KeyboardHelpIntent>(
            canInvoke: () => !_isEditingText,
            onInvoke: (_) => _showKeyboardHelp(),
          ),
          _ReaderLineDownIntent: CallbackAction(
            onInvoke: (_) => _scrollReader(48),
          ),
          _ReaderLineUpIntent: CallbackAction(
            onInvoke: (_) => _scrollReader(-48),
          ),
          _ReaderPageDownIntent: CallbackAction(
            onInvoke: (_) => _scrollReader(
              _readerScrollController.hasClients
                  ? _readerScrollController.position.viewportDimension * .85
                  : 0,
            ),
          ),
          _ReaderPageUpIntent: CallbackAction(
            onInvoke: (_) => _scrollReader(
              _readerScrollController.hasClients
                  ? -_readerScrollController.position.viewportDimension * .85
                  : 0,
            ),
          ),
          _ReaderStartIntent: CallbackAction(
            onInvoke: (_) => _scrollReaderBoundary(false),
          ),
          _ReaderEndIntent: CallbackAction(
            onInvoke: (_) => _scrollReaderBoundary(true),
          ),
          _NextAccountIntent: CallbackAction(
            onInvoke: (_) => _switchAccount(1),
          ),
          _PreviousAccountIntent: CallbackAction(
            onInvoke: (_) => _switchAccount(-1),
          ),
          _ChooseAccountIntent: _GuardedAction<_ChooseAccountIntent>(
            canInvoke: () =>
                !_isEditingText && widget.onAccountSelected != null,
            onInvoke: (_) => _showAccountChooser(),
          ),
          _SummarizeIntent: _GuardedAction<_SummarizeIntent>(
            canInvoke: () => !_isEditingText && widget.onSummarize != null,
            onInvoke: (_) {
              final item = _actionItem;
              if (item != null && widget.onSummarize != null) {
                _runAction('summary', item, widget.onSummarize!);
              }
              return null;
            },
          ),
          _DistributeIntent: _GuardedAction<_DistributeIntent>(
            canInvoke: () =>
                !_isEditingText &&
                widget.onDistribute != null &&
                widget.projectDestinations.isNotEmpty,
            onInvoke: (_) {
              final item = _actionItem;
              if (item != null) {
                _showDistributionChooser(item);
              }
              return null;
            },
          ),
          _IngestIntent: _GuardedAction<_IngestIntent>(
            canInvoke: () => !_isEditingText && widget.onIngest != null,
            onInvoke: (_) {
              final item = _actionItem;
              if (item != null && widget.onIngest != null) {
                _runAction('ingest', item, widget.onIngest!);
              }
              return null;
            },
          ),
        },
        child: FlutterZoomViewport(
          initialZoom: widget.style.initialZoom,
          minimumZoom: widget.style.minimumZoom,
          maximumZoom: widget.style.maximumZoom,
          zoomStep: widget.style.zoomStep,
          resetShortcuts: widget.shortcuts.resetZoom,
          child: Focus(
            focusNode: _workspaceFocus,
            autofocus: true,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact =
                    constraints.maxWidth < widget.style.compactBreakpoint;
                final showNavigation =
                    constraints.maxWidth >= widget.style.navigationBreakpoint;
                final navigationWidth = _navigationWidth(context);
                return Material(
                  color: _colors.canvas,
                  child: Column(
                    children: [
                      _TopBar(
                        grouped: widget.sectionLabels.isNotEmpty,
                        title: widget.title,
                        compact: !showNavigation,
                        style: widget.style,
                        colors: _colors,
                        searchController: _searchController,
                        searchFocus: _searchFocus,
                        searchHint: widget.searchHint,
                        onSearchChanged: (query) =>
                            setState(() => _query = query),
                        onMenu: _showNavigationSheet,
                        onRefresh: widget.onRefresh,
                        refreshTooltip: widget.refreshTooltip,
                        isLoading: widget.isLoading,
                        actions: widget.topBarActions,
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            if (showNavigation)
                              SizedBox(
                                width: navigationWidth,
                                child: _NavigationPane(
                                  navigationHeader: widget.navigationHeader,
                                  title: widget.title,
                                  style: widget.style,
                                  colors: _colors,
                                  selectedFilterId: _filterId,
                                  showLater: widget.laterDestinationId != null,
                                  tags: _tags,
                                  categoryFor: _categoryFor,
                                  countFor: _countFor,
                                  onOpenLibrary: widget.onOpenLibrary,
                                  onFilterSelected: _selectFilter,
                                ),
                              ),
                            Expanded(
                              child: _selectedItem == null
                                  ? _SourceInbox(
                                      itemSectionIds: widget.itemSectionIds,
                                      sectionLabels: widget.sectionLabels,
                                      sectionEmptyMessages:
                                          widget.sectionEmptyMessages,
                                      sectionKeys: widget.sectionKeys,
                                      collapsedSections: _collapsedSections,
                                      items: _visibleItems,
                                      selectedId: _activeId,
                                      filterLabel: _filterLabel,
                                      isLoading: widget.isLoading,
                                      isLoadingMore: widget.isLoadingMore,
                                      hasMore: widget.hasMore,
                                      errorMessage: widget.errorMessage,
                                      emptyMessage: widget.emptyMessage,
                                      compact: compact,
                                      style: widget.style,
                                      colors: _colors,
                                      categoryFor: _categoryFor,
                                      onSelected: widget.onSelected,
                                      rowKeys: _rowKeys,
                                      rowFocusNodes: _rowFocusNodes,
                                      scrollController: _listScrollController,
                                      onActiveChanged: (id) =>
                                          setState(() => _activeId = id),
                                      onSectionToggled: (section) => setState(
                                        () =>
                                            _collapsedSections.contains(section)
                                            ? _collapsedSections.remove(section)
                                            : _collapsedSections.add(section),
                                      ),
                                      onRefresh: widget.onRefresh,
                                      refreshTooltip: widget.refreshTooltip,
                                      onLoadMore: widget.onLoadMore,
                                    )
                                  : _ReaderPane(
                                      readerFooter: widget.readerFooter,
                                      readerBody: widget.readerBody,
                                      item: _selectedItem!,
                                      items: _visibleItems,
                                      style: widget.style,
                                      colors: _colors,
                                      categoryFor: _categoryFor,
                                      pendingAction: _pendingAction,
                                      scrollController: _readerScrollController,
                                      onBack: _closeReader,
                                      onPrevious: () => _moveSelection(-1),
                                      onNext: () => _moveSelection(1),
                                      onIngest: widget.onIngest == null
                                          ? null
                                          : () => _runAction(
                                              'ingest',
                                              _selectedItem!,
                                              widget.onIngest!,
                                            ),
                                      onMarkSeen: widget.onMarkSeen == null
                                          ? null
                                          : () => _runAction(
                                              'seen',
                                              _selectedItem!,
                                              widget.onMarkSeen!,
                                            ),
                                      onArchive: widget.onArchive == null
                                          ? null
                                          : () => _runAction(
                                              'archive',
                                              _selectedItem!,
                                              widget.onArchive!,
                                            ),
                                      onOpenExternal:
                                          widget.onOpenExternal == null
                                          ? null
                                          : () => _runAction(
                                              'open',
                                              _selectedItem!,
                                              widget.onOpenExternal!,
                                            ),
                                      onDelete: widget.onDelete == null
                                          ? null
                                          : () =>
                                                _confirmDelete(_selectedItem!),
                                      onMove:
                                          widget.onMove == null ||
                                              widget.moveDestinations.isEmpty
                                          ? null
                                          : () => _showMoveChooser(
                                              _selectedItem!,
                                            ),
                                      onSummarize: widget.onSummarize == null
                                          ? null
                                          : () => _runAction(
                                              'summary',
                                              _selectedItem!,
                                              widget.onSummarize!,
                                            ),
                                      onDistribute:
                                          widget.onDistribute == null ||
                                              widget.projectDestinations.isEmpty
                                          ? null
                                          : () => _showDistributionChooser(
                                              _selectedItem!,
                                            ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                      if (compact)
                        _MobileNavigationBar(
                          selectedFilterId: _filterId,
                          showLater: widget.laterDestinationId != null,
                          onFilterSelected: _selectFilter,
                          onMore: _showNavigationSheet,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    this.grouped = false,
    this.searchHint,
    required this.title,
    required this.compact,
    required this.style,
    required this.colors,
    required this.searchController,
    required this.searchFocus,
    required this.onSearchChanged,
    required this.onMenu,
    required this.onRefresh,
    required this.refreshTooltip,
    required this.isLoading,
    required this.actions,
  });

  final String title;
  final bool grouped;
  final String? searchHint;
  final bool compact;
  final SourceSidebarStyle style;
  final SourceSidebarColors colors;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onMenu;
  final Future<void> Function()? onRefresh;
  final String refreshTooltip;
  final bool isLoading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final identity = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (compact)
          IconButton(
            tooltip: 'Source filters',
            onPressed: onMenu,
            icon: const Icon(Icons.menu),
          ),
        Icon(
          grouped ? Icons.mail_outline : Icons.auto_stories_outlined,
          color: colors.focus,
        ),
        SizedBox(width: style.identityGap),
        Flexible(
          child: Text(
            title,
            maxLines: grouped ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style:
                (grouped
                        ? Theme.of(context).textTheme.titleMedium
                        : Theme.of(context).textTheme.titleLarge)
                    ?.copyWith(
                      color: colors.mutedForeground,
                      fontWeight: FontWeight.w400,
                    ),
          ),
        ),
      ],
    );

    final search = _SourceSearch(
      hint: searchHint ?? (grouped ? 'Search emails' : 'Search sources'),
      controller: searchController,
      focusNode: searchFocus,
      style: style,
      colors: colors,
      onChanged: onSearchChanged,
    );

    final refresh = IconButton(
      tooltip: refreshTooltip,
      onPressed: isLoading ? null : onRefresh,
      icon: isLoading
          ? SizedBox.square(
              dimension: style.actionIconSize,
              child: const CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh),
    );

    if (compact) {
      return ColoredBox(
        color: colors.surface,
        child: Padding(
          padding: style.searchPadding,
          child: Column(
            children: [
              SizedBox(
                height: style.topBarHeight,
                child: Row(
                  children: [
                    Expanded(child: identity),
                    refresh,
                  ],
                ),
              ),
              if (actions.isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: style.gapSmall,
                    runSpacing: style.gapSmall,
                    children: actions,
                  ),
                ),
              Padding(
                padding: EdgeInsets.only(bottom: style.gapMedium),
                child: search,
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      height: style.topBarHeight,
      color: colors.surface,
      padding: style.searchPadding,
      child: Row(
        children: [
          SizedBox(width: style.navigationWidth - 16, child: identity),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: style.searchMaxWidth),
                child: search,
              ),
            ),
          ),
          refresh,
          ...actions,
        ],
      ),
    );
  }
}

class _SourceSearch extends StatelessWidget {
  const _SourceSearch({
    this.hint = 'Search sources',
    required this.controller,
    required this.focusNode,
    required this.style,
    required this.colors,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final FocusNode focusNode;
  final SourceSidebarStyle style;
  final SourceSidebarColors colors;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
                icon: const Icon(Icons.close),
              ),
        filled: true,
        fillColor: colors.searchSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(style.searchRadius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(style.searchRadius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(style.searchRadius),
          borderSide: BorderSide(color: colors.focus),
        ),
      ),
    );
  }
}

class _MobileNavigationBar extends StatelessWidget {
  const _MobileNavigationBar({
    required this.selectedFilterId,
    required this.showLater,
    required this.onFilterSelected,
    required this.onMore,
  });

  final String selectedFilterId;
  final bool showLater;
  final ValueChanged<String> onFilterSelected;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.inbox_outlined),
        selectedIcon: Icon(Icons.inbox),
        label: 'Inbox',
      ),
      const NavigationDestination(
        icon: Icon(Icons.mark_email_unread_outlined),
        selectedIcon: Icon(Icons.mark_email_unread),
        label: 'Non lus',
      ),
      const NavigationDestination(
        icon: Icon(Icons.task_alt_outlined),
        selectedIcon: Icon(Icons.task_alt),
        label: 'Traités',
      ),
      if (showLater)
        const NavigationDestination(
          icon: Icon(Icons.schedule_outlined),
          selectedIcon: Icon(Icons.schedule),
          label: 'Plus tard',
        ),
      const NavigationDestination(
        icon: Icon(Icons.menu_outlined),
        selectedIcon: Icon(Icons.menu),
        label: 'Menu',
      ),
    ];
    final filters = [
      _FilterId.inbox,
      _FilterId.unread,
      _FilterId.processed,
      if (showLater) _FilterId.later,
    ];
    final selectedIndex = filters.indexOf(selectedFilterId);
    return NavigationBar(
      selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
      onDestinationSelected: (index) {
        if (index == destinations.length - 1) {
          onMore();
          return;
        }
        onFilterSelected(filters[index]);
      },
      destinations: destinations,
    );
  }
}

class _NavigationPane extends StatelessWidget {
  const _NavigationPane({
    this.navigationHeader,
    required this.title,
    required this.style,
    required this.colors,
    required this.selectedFilterId,
    required this.showLater,
    required this.tags,
    required this.categoryFor,
    required this.countFor,
    required this.onOpenLibrary,
    required this.onFilterSelected,
  });

  final String title;
  final Widget? navigationHeader;
  final SourceSidebarStyle style;
  final SourceSidebarColors colors;
  final String selectedFilterId;
  final bool showLater;
  final List<String> tags;
  final SourceCategory Function(String) categoryFor;
  final int Function(String) countFor;
  final Future<void> Function()? onOpenLibrary;
  final ValueChanged<String> onFilterSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.canvas,
      child: ListView(
        padding: style.navigationPadding,
        children: [
          if (navigationHeader != null) ...[
            navigationHeader!,
            SizedBox(height: style.gapLarge),
          ],
          if (onOpenLibrary != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primaryActionSurface,
                  foregroundColor: colors.primaryActionForeground,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      style.primaryActionRadius,
                    ),
                  ),
                ),
                onPressed: onOpenLibrary,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open library'),
              ),
            ),
            SizedBox(height: style.gapLarge),
          ],
          _NavigationSectionHeading(
            label: 'Statuts',
            icon: Icons.filter_list_outlined,
            style: style,
            colors: colors,
          ),
          _NavigationItem(
            label: 'Inbox',
            icon: Icons.inbox_outlined,
            count: countFor(_FilterId.inbox),
            selected: selectedFilterId == _FilterId.inbox,
            style: style,
            colors: colors,
            onTap: () => onFilterSelected(_FilterId.inbox),
          ),
          _NavigationItem(
            label: 'Unread',
            icon: Icons.mark_email_unread_outlined,
            count: countFor(_FilterId.unread),
            selected: selectedFilterId == _FilterId.unread,
            style: style,
            colors: colors,
            onTap: () => onFilterSelected(_FilterId.unread),
          ),
          _NavigationItem(
            label: 'Processed',
            icon: Icons.task_alt_outlined,
            count: countFor(_FilterId.processed),
            selected: selectedFilterId == _FilterId.processed,
            style: style,
            colors: colors,
            onTap: () => onFilterSelected(_FilterId.processed),
          ),
          if (showLater)
            _NavigationItem(
              label: 'Later',
              icon: Icons.schedule_outlined,
              count: countFor(_FilterId.later),
              selected: selectedFilterId == _FilterId.later,
              style: style,
              colors: colors,
              onTap: () => onFilterSelected(_FilterId.later),
            ),
          _NavigationItem(
            label: 'Archived',
            icon: Icons.archive_outlined,
            count: countFor(_FilterId.archive),
            selected: selectedFilterId == _FilterId.archive,
            style: style,
            colors: colors,
            onTap: () => onFilterSelected(_FilterId.archive),
          ),
          if (tags.isNotEmpty) ...[
            SizedBox(height: style.gapLarge),
            ..._categorySection(
              context,
              label: 'Projets',
              icon: Icons.account_tree_outlined,
              categoryIds: tags.where(
                (tag) => categoryFor(tag).kind == SourceCategoryKind.project,
              ),
            ),
            ..._categorySection(
              context,
              label: 'Tags',
              icon: Icons.sell_outlined,
              categoryIds: tags.where(
                (tag) => categoryFor(tag).kind == SourceCategoryKind.tag,
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _categorySection(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Iterable<String> categoryIds,
  }) {
    final ids = categoryIds.toList(growable: false);
    if (ids.isEmpty) return const [];
    return [
      _NavigationSectionHeading(
        label: label,
        icon: icon,
        style: style,
        colors: colors,
        topInset: style.gapLarge,
      ),
      ...ids.map((tag) {
        final id = '${_FilterId.tagPrefix}$tag';
        final category = categoryFor(tag);
        return _NavigationItem(
          label: category.name,
          icon: category.icon,
          iconColor: category.color,
          count: countFor(id),
          selected: selectedFilterId == id,
          style: style,
          colors: colors,
          onTap: () => onFilterSelected(id),
        );
      }),
    ];
  }
}

class _NavigationSectionHeading extends StatelessWidget {
  const _NavigationSectionHeading({
    required this.label,
    required this.icon,
    required this.style,
    required this.colors,
    this.topInset = 0,
  });

  final String label;
  final IconData icon;
  final SourceSidebarStyle style;
  final SourceSidebarColors colors;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    final baseStyle = Theme.of(context).textTheme.bodyMedium;
    return Container(
      margin: EdgeInsets.fromLTRB(18, topInset, 18, style.gapSmall),
      padding: EdgeInsets.symmetric(
        horizontal: style.gapMedium,
        vertical: style.gapSmall,
      ),
      decoration: BoxDecoration(
        color: colors.searchSurface,
        borderRadius: BorderRadius.circular(style.navigationItemRadius),
      ),
      child: Row(
        children: [
          Icon(icon, size: style.actionIconSize, color: colors.mutedForeground),
          SizedBox(width: style.identityGap),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: baseStyle?.copyWith(
                color: colors.foreground,
                fontSize: (baseStyle.fontSize ?? 14) * 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.label,
    required this.icon,
    required this.count,
    required this.selected,
    required this.style,
    required this.colors,
    required this.onTap,
    this.iconColor,
  });

  final String label;
  final IconData icon;
  final int count;
  final bool selected;
  final SourceSidebarStyle style;
  final SourceSidebarColors colors;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? colors.selectedSurface
            : colors.canvas.withValues(alpha: 0),
        borderRadius: BorderRadius.horizontal(
          right: Radius.circular(style.navigationItemRadius),
        ),
        child: InkWell(
          focusColor: colors.focus.withValues(alpha: style.focusOverlayOpacity),
          borderRadius: BorderRadius.horizontal(
            right: Radius.circular(style.navigationItemRadius),
          ),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: style.actionIconSize, color: iconColor),
                SizedBox(width: style.gapLarge),
                Flexible(
                  fit: FlexFit.loose,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize:
                          (Theme.of(context).textTheme.bodyMedium?.fontSize ??
                              14) *
                          1.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (count > 0)
                  Padding(
                    padding: EdgeInsets.only(left: style.gapLarge),
                    child: Text(
                      '$count',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize:
                            (Theme.of(context).textTheme.bodyMedium?.fontSize ??
                                14) *
                            1.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceInbox extends StatelessWidget {
  const _SourceInbox({
    this.itemSectionIds = const {},
    this.sectionLabels = const {},
    this.sectionEmptyMessages = const {},
    this.sectionKeys = const {},
    this.collapsedSections = const {},
    required this.items,
    required this.selectedId,
    required this.filterLabel,
    required this.isLoading,
    required this.isLoadingMore,
    required this.hasMore,
    required this.errorMessage,
    required this.emptyMessage,
    required this.compact,
    required this.style,
    required this.colors,
    required this.categoryFor,
    required this.onSelected,
    required this.rowKeys,
    required this.rowFocusNodes,
    required this.scrollController,
    required this.onActiveChanged,
    required this.onSectionToggled,
    required this.onRefresh,
    required this.refreshTooltip,
    required this.onLoadMore,
  });

  final List<SourceSidebarItem> items;
  final Map<String, String> itemSectionIds;
  final Map<String, String> sectionLabels;
  final Map<String, String> sectionEmptyMessages;
  final Map<String, GlobalKey> sectionKeys;
  final Set<String> collapsedSections;
  final String? selectedId;
  final String filterLabel;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? errorMessage;
  final String emptyMessage;
  final bool compact;
  final SourceSidebarStyle style;
  final SourceSidebarColors colors;
  final SourceCategory Function(String) categoryFor;
  final ValueChanged<String?> onSelected;
  final Map<String, GlobalKey> rowKeys;
  final Map<String, FocusNode> rowFocusNodes;
  final ScrollController scrollController;
  final ValueChanged<String> onActiveChanged;
  final ValueChanged<String> onSectionToggled;
  final Future<void> Function()? onRefresh;
  final String refreshTooltip;
  final Future<void> Function()? onLoadMore;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.surface,
      child: Column(
        children: [
          if (sectionLabels.isEmpty)
            Container(
              height: style.toolbarHeight,
              padding: style.toolbarPadding,
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors.divider)),
              ),
              child: Row(
                children: [
                  Text(
                    filterLabel,
                    style: Theme.of(
                      context,
                    ).textTheme.titleSmall?.copyWith(color: colors.foreground),
                  ),
                  SizedBox(width: style.gapSmall),
                  Text(
                    '${items.length}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.mutedForeground,
                    ),
                  ),
                  const Spacer(),
                  if (!compact)
                    Text(
                      'J/K to navigate',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                  IconButton(
                    tooltip: refreshTooltip,
                    onPressed: isLoading ? null : onRefresh,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _groupedBody(BuildContext context) {
    final groups = {
      for (final id in sectionLabels.keys) id: <SourceSidebarItem>[],
    };
    for (final item in items) {
      final section = itemSectionIds[item.id];
      (groups[section] ?? groups.values.first).add(item);
    }
    return CustomScrollView(
      controller: scrollController,
      slivers: [
        if (isLoading)
          const SliverToBoxAdapter(child: LinearProgressIndicator()),
        if (errorMessage != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: style.contentPadding,
              child: _MessageState(
                icon: Icons.cloud_off_outlined,
                message: errorMessage!,
                style: style,
                actionLabel: onRefresh == null ? null : 'Try again',
                onAction: onRefresh,
              ),
            ),
          ),
        for (final section in sectionLabels.entries) ...[
          SliverToBoxAdapter(
            child: GroupedSectionHeader(
              key: sectionKeys[section.key],
              sectionId: section.key,
              label: section.value,
              isFirst: section.key == sectionLabels.keys.first,
              collapsed: collapsedSections.contains(section.key),
              unreadCount: groups[section.key]!
                  .where((item) => !item.seen)
                  .length,
              totalCount: groups[section.key]!.length,
              style: style,
              colors: colors,
              onTap: () => onSectionToggled(section.key),
            ),
          ),
          if (!collapsedSections.contains(section.key) &&
              groups[section.key]!.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: style.contentPadding,
                child: Text(
                  sectionEmptyMessages[section.key] ??
                      'Aucun email à afficher.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.mutedForeground,
                  ),
                ),
              ),
            )
          else if (!collapsedSections.contains(section.key))
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                if (index.isOdd) {
                  return Divider(
                    height: style.dividerThickness,
                    color: colors.divider,
                  );
                }
                final item = groups[section.key]![index ~/ 2];
                return _DenseSourceRow(
                  key: rowKeys.putIfAbsent(item.id, () => GlobalKey()),
                  item: item,
                  sectionId: section.key,
                  compact: compact,
                  selected: item.id == selectedId,
                  style: style,
                  colors: colors,
                  categoryFor: categoryFor,
                  focusNode: rowFocusNodes.putIfAbsent(
                    item.id,
                    () => FocusNode(debugLabel: 'Source row ${item.id}'),
                  ),
                  onTap: () => onSelected(item.id),
                  onFocus: () => onActiveChanged(item.id),
                );
              }, childCount: groups[section.key]!.length * 2 - 1),
            ),
        ],
        if (hasMore)
          SliverToBoxAdapter(
            child: Padding(
              padding: style.contentPadding,
              child: OutlinedButton(
                onPressed: isLoadingMore ? null : onLoadMore,
                child: isLoadingMore
                    ? SizedBox.square(
                        dimension: style.actionIconSize,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Load more'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _body(BuildContext context) {
    if (sectionLabels.isNotEmpty) return _groupedBody(context);
    if (isLoading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (errorMessage != null && items.isEmpty) {
      return _MessageState(
        icon: Icons.cloud_off_outlined,
        message: errorMessage!,
        style: style,
        actionLabel: onRefresh == null ? null : 'Try again',
        onAction: onRefresh,
      );
    }
    if (items.isEmpty) {
      return _MessageState(
        icon: Icons.inbox_outlined,
        message: emptyMessage,
        style: style,
      );
    }
    return ListView.separated(
      controller: scrollController,
      itemCount: items.length + (hasMore ? 1 : 0),
      separatorBuilder: (_, _) =>
          Divider(height: style.dividerThickness, color: colors.divider),
      itemBuilder: (context, index) {
        if (index == items.length) {
          return Padding(
            padding: style.contentPadding,
            child: OutlinedButton(
              onPressed: isLoadingMore ? null : onLoadMore,
              child: isLoadingMore
                  ? SizedBox.square(
                      dimension: style.actionIconSize,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Load more'),
            ),
          );
        }
        final item = items[index];
        return _DenseSourceRow(
          key: rowKeys.putIfAbsent(item.id, () => GlobalKey()),
          item: item,
          compact: compact,
          selected: item.id == selectedId,
          style: style,
          colors: colors,
          categoryFor: categoryFor,
          focusNode: rowFocusNodes.putIfAbsent(
            item.id,
            () => FocusNode(debugLabel: 'Source row ${item.id}'),
          ),
          onTap: () => onSelected(item.id),
          onFocus: () => onActiveChanged(item.id),
        );
      },
    );
  }
}

class _DenseSourceRow extends StatelessWidget {
  const _DenseSourceRow({
    super.key,
    required this.item,
    this.sectionId,
    required this.compact,
    required this.selected,
    required this.style,
    required this.colors,
    required this.categoryFor,
    required this.focusNode,
    required this.onTap,
    required this.onFocus,
  });

  final SourceSidebarItem item;
  final String? sectionId;
  final bool compact;
  final bool selected;
  final SourceSidebarStyle style;
  final SourceSidebarColors colors;
  final SourceCategory Function(String) categoryFor;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final VoidCallback onFocus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sectionBackground = sectionId == null
        ? null
        : groupedSectionAppearance(scheme, sectionId!).background;
    final attentionBackground = switch (item.attention) {
      SourceSidebarAttention.readyToSend => sectionBackground,
      SourceSidebarAttention.needsReview => scheme.errorContainer,
      SourceSidebarAttention.none => null,
    };
    final signalBackground =
        item.signalKind == SourceSidebarSignalKind.urgency &&
            item.signalStrength >= 0.85
        ? scheme.errorContainer
        : sectionBackground;
    final background = attentionBackground != null
        ? Color.alphaBlend(
            attentionBackground.withValues(
              alpha: item.attention == SourceSidebarAttention.needsReview
                  ? 0.68
                  : 0.58,
            ),
            colors.surface,
          )
        : item.signalStrength > 0 && signalBackground != null
        ? Color.alphaBlend(
            signalBackground.withValues(
              alpha: 0.12 + (item.signalStrength * 0.62),
            ),
            colors.surface,
          )
        : sectionBackground == null
        ? (selected
              ? colors.selectedSurface
              : item.seen
              ? colors.surface
              : colors.unreadSurface)
        : Color.alphaBlend(
            sectionBackground.withValues(
              alpha: selected
                  ? 0.62
                  : item.seen
                  ? 0.10
                  : 0.48,
            ),
            colors.surface,
          );
    final titleWeight = item.seen ? FontWeight.w500 : FontWeight.w700;

    return Semantics(
      selected: selected,
      button: true,
      label:
          '${item.title}, ${item.authorOrPublisher}${item.attention.semanticLabel.isEmpty ? '' : ', ${item.attention.semanticLabel}'}${item.signalStrength >= 0.85 ? ', ${item.signalKind == SourceSidebarSignalKind.urgency ? 'urgent' : 'très pertinent'}' : ''}',
      child: Material(
        color: background,
        child: InkWell(
          focusNode: focusNode,
          focusColor: colors.focus.withValues(alpha: style.focusOverlayOpacity),
          onFocusChange: (focused) {
            if (focused) onFocus();
          },
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: style.denseRowHeight),
            child: Padding(
              padding: style.rowPadding,
              child: compact
                  ? _compactContent(context, titleWeight)
                  : _wideContent(context, titleWeight),
            ),
          ),
        ),
      ),
    );
  }

  Widget _compactContent(BuildContext context, FontWeight titleWeight) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.authorOrPublisher,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: titleWeight,
                        color: colors.foreground,
                      ),
                    ),
                  ),
                  if (item.tags.isNotEmpty)
                    SizedBox(
                      width:
                          style.categoryIndicatorSize * 3 + style.tagDotGap * 3,
                      child: _CategoryIndicators(
                        categoryIds: item.tags,
                        categoryFor: categoryFor,
                        style: style,
                      ),
                    ),
                  Text(
                    _dateLabel(item.publishedAt),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.mutedForeground,
                    ),
                  ),
                  if (item.attention != SourceSidebarAttention.none) ...[
                    SizedBox(width: style.gapSmall),
                    Tooltip(
                      message: item.attention.semanticLabel,
                      child: Icon(
                        item.attention == SourceSidebarAttention.needsReview
                            ? Icons.priority_high_rounded
                            : Icons.schedule_send_outlined,
                        size: style.actionIconSize,
                        color:
                            item.attention == SourceSidebarAttention.needsReview
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.tertiary,
                      ),
                    ),
                  ],
                ],
              ),
              SizedBox(height: style.denseTextGap),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: titleWeight,
                  color: colors.foreground,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _wideContent(BuildContext context, FontWeight titleWeight) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(
            item.authorOrPublisher,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: titleWeight,
              color: colors.foreground,
            ),
          ),
        ),
        SizedBox(width: style.gapLarge),
        Expanded(
          flex: 6,
          child: Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: titleWeight,
              color: colors.foreground,
            ),
          ),
        ),
        if (item.attention != SourceSidebarAttention.none)
          Tooltip(
            message: item.attention.semanticLabel,
            child: Padding(
              padding: EdgeInsets.only(right: style.gapSmall),
              child: Icon(
                item.attention == SourceSidebarAttention.needsReview
                    ? Icons.priority_high_rounded
                    : Icons.schedule_send_outlined,
                size: style.actionIconSize,
                color: item.attention == SourceSidebarAttention.needsReview
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.tertiary,
              ),
            ),
          ),
        Expanded(
          flex: 2,
          child: item.tags.isEmpty
              ? const SizedBox.shrink()
              : _CategoryIndicators(
                  categoryIds: item.tags,
                  categoryFor: categoryFor,
                  style: style,
                ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            _dateLabel(item.publishedAt),
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.mutedForeground,
              fontWeight: titleWeight,
            ),
          ),
        ),
      ],
    );
  }
}

class _CategoryIndicators extends StatelessWidget {
  const _CategoryIndicators({
    required this.categoryIds,
    required this.categoryFor,
    required this.style,
  });

  final List<String> categoryIds;
  final SourceCategory Function(String) categoryFor;
  final SourceSidebarStyle style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: categoryIds
          .take(3)
          .map((id) {
            final category = categoryFor(id);
            return Tooltip(
              message: category.name,
              child: Semantics(
                label: 'Category ${category.name}',
                child: Padding(
                  padding: EdgeInsets.only(left: style.tagDotGap),
                  child: Icon(
                    category.icon,
                    size: style.categoryIndicatorSize,
                    color: category.color,
                  ),
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

class _ReaderPane extends StatelessWidget {
  const _ReaderPane({
    this.readerFooter,
    this.readerBody,
    required this.item,
    required this.items,
    required this.style,
    required this.colors,
    required this.categoryFor,
    required this.pendingAction,
    required this.scrollController,
    required this.onBack,
    required this.onPrevious,
    required this.onNext,
    this.onIngest,
    this.onMarkSeen,
    this.onArchive,
    this.onDelete,
    this.onOpenExternal,
    this.onMove,
    this.onSummarize,
    this.onDistribute,
  });

  final SourceSidebarItem item;
  final Widget? readerFooter;
  final Widget? readerBody;
  final List<SourceSidebarItem> items;
  final SourceSidebarStyle style;
  final SourceSidebarColors colors;
  final SourceCategory Function(String) categoryFor;
  final String? pendingAction;
  final ScrollController scrollController;
  final VoidCallback onBack;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback? onIngest;
  final VoidCallback? onMarkSeen;
  final VoidCallback? onArchive;
  final VoidCallback? onDelete;
  final VoidCallback? onOpenExternal;
  final VoidCallback? onMove;
  final VoidCallback? onSummarize;
  final VoidCallback? onDistribute;

  @override
  Widget build(BuildContext context) {
    final busy =
        pendingAction != null ||
        item.processingState == SourceProcessingState.processing;
    final index = items.indexWhere((candidate) => candidate.id == item.id);
    return Material(
      color: colors.surface,
      child: Column(
        children: [
          Container(
            height: style.toolbarHeight,
            padding: style.toolbarPadding,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.divider)),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 520;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _ActionIcon(
                      tooltip: 'Back to list',
                      icon: Icons.arrow_back,
                      onPressed: onBack,
                    ),
                    _ActionIcon(
                      tooltip: 'Archive source',
                      icon: Icons.archive_outlined,
                      onPressed: busy ? null : onArchive,
                    ),
                    _ActionIcon(
                      tooltip: 'Delete source',
                      icon: Icons.delete_outline,
                      color: colors.danger,
                      onPressed: busy ? null : onDelete,
                    ),
                    if (onMove != null)
                      _ActionIcon(
                        tooltip: 'Move source',
                        icon: Icons.drive_file_move_outline,
                        onPressed: busy ? null : onMove,
                      ),
                    if (onSummarize != null)
                      _ActionIcon(
                        tooltip: 'Summarize source',
                        icon: Icons.summarize_outlined,
                        onPressed: busy ? null : onSummarize,
                      ),
                    if (onDistribute != null)
                      _ActionIcon(
                        tooltip: 'Send to projects',
                        icon: Icons.call_split_outlined,
                        onPressed: busy ? null : onDistribute,
                      ),
                    if (!narrow)
                      _ActionIcon(
                        tooltip: 'Mark as seen',
                        icon: Icons.mark_email_read_outlined,
                        onPressed: busy ? null : onMarkSeen,
                      ),
                    if (!narrow)
                      _ActionIcon(
                        tooltip: 'Open in source library',
                        icon: Icons.open_in_new,
                        onPressed: busy ? null : onOpenExternal,
                      ),
                    if (narrow &&
                        (onMarkSeen != null || onOpenExternal != null))
                      PopupMenuButton<String>(
                        tooltip: 'More source actions',
                        enabled: !busy,
                        onSelected: (action) {
                          if (action == 'seen') onMarkSeen?.call();
                          if (action == 'open') onOpenExternal?.call();
                        },
                        itemBuilder: (context) => [
                          if (onMarkSeen != null)
                            const PopupMenuItem(
                              value: 'seen',
                              child: Text('Mark as seen'),
                            ),
                          if (onOpenExternal != null)
                            const PopupMenuItem(
                              value: 'open',
                              child: Text('Open in source library'),
                            ),
                        ],
                      ),
                    if (index >= 0)
                      Text(
                        '${index + 1} of ${items.length}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.mutedForeground,
                        ),
                      ),
                    _ActionIcon(
                      tooltip: 'Previous source',
                      icon: Icons.chevron_left,
                      onPressed: index <= 0 ? null : onPrevious,
                    ),
                    _ActionIcon(
                      tooltip: 'Next source',
                      icon: Icons.chevron_right,
                      onPressed: index < 0 || index >= items.length - 1
                          ? null
                          : onNext,
                    ),
                  ],
                );
              },
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: scrollController,
              padding: style.contentPadding,
              child: Center(
                child: SelectionArea(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: style.readerMaxWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                item.title,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(
                                      color: colors.foreground,
                                      fontWeight: FontWeight.w400,
                                    ),
                              ),
                            ),
                            if (busy)
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: SizedBox.square(
                                  dimension: style.actionIconSize,
                                  child: const CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: style.gap2XLarge),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              backgroundColor: colors.searchSurface,
                              foregroundColor: colors.foreground,
                              child: Text(_initials(item.authorOrPublisher)),
                            ),
                            SizedBox(width: style.gapMedium),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.authorOrPublisher,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(color: colors.foreground),
                                  ),
                                  SizedBox(height: style.authorMetadataGap),
                                  Text(
                                    '${item.sourceType} · ${_dateLabel(item.publishedAt)}',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: colors.mutedForeground,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (item.tags.isNotEmpty) ...[
                          SizedBox(height: style.gapExtraLarge),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: item.tags
                                .map((id) {
                                  final category = categoryFor(id);
                                  return Semantics(
                                    label: 'Category ${category.name}',
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: category.color.withValues(
                                          alpha: style
                                              .categoryChipBackgroundOpacity,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          style.tagRadius,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            category.icon,
                                            size: style.categoryChipIconSize,
                                            color: category.color,
                                          ),
                                          SizedBox(width: style.tagDotGap),
                                          Text(
                                            category.name,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  color: colors.foreground,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                })
                                .toList(growable: false),
                          ),
                        ],
                        SizedBox(height: style.gap3XLarge),
                        readerBody ??
                            Text(
                              item.content,
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    color: colors.foreground,
                                    height: style.readerLineHeight,
                                  ),
                            ),
                        if (readerFooter != null) ...[
                          SizedBox(height: style.gap3XLarge),
                          readerFooter!,
                        ],
                        SizedBox(height: style.gap4XLarge),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.color,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, color: color),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.message,
    required this.style,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final SourceSidebarStyle style;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: Theme.of(context).colorScheme.outline),
          SizedBox(height: style.gapMedium),
          Text(message, textAlign: TextAlign.center),
          if (actionLabel != null && onAction != null) ...[
            SizedBox(height: style.gapMedium),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

abstract final class _FilterId {
  static const inbox = 'inbox';
  static const unread = 'unread';
  static const processed = 'processed';
  static const archive = 'archive';
  static const later = 'later';
  static const tagPrefix = 'tag:';
}

String _dateLabel(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}';
}

String _initials(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2);
  final initials = parts.map((part) => part[0].toUpperCase()).join();
  return initials.isEmpty ? '?' : initials;
}

class _NextSourceIntent extends Intent {
  const _NextSourceIntent();
}

class _PreviousSourceIntent extends Intent {
  const _PreviousSourceIntent();
}

class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

class _CloseReaderIntent extends Intent {
  const _CloseReaderIntent();
}

class _OpenSourceIntent extends Intent {
  const _OpenSourceIntent();
}

class _OpenSourceFromWorkspaceIntent extends Intent {
  const _OpenSourceFromWorkspaceIntent();
}

class _WorkspaceOpenAction extends Action<_OpenSourceFromWorkspaceIntent> {
  _WorkspaceOpenAction({
    required this.isWorkspaceFocused,
    required this.onOpen,
  });

  final bool Function() isWorkspaceFocused;
  final VoidCallback onOpen;

  @override
  bool isEnabled(_OpenSourceFromWorkspaceIntent intent) {
    return isWorkspaceFocused();
  }

  @override
  Object? invoke(_OpenSourceFromWorkspaceIntent intent) {
    onOpen();
    return null;
  }
}

class _GuardedAction<T extends Intent> extends Action<T> {
  _GuardedAction({required this.canInvoke, required this.onInvoke});

  final bool Function() canInvoke;
  final Object? Function(T intent) onInvoke;

  @override
  bool isEnabled(T intent) => canInvoke();

  @override
  Object? invoke(T intent) => onInvoke(intent);
}

class _ArchiveSourceIntent extends Intent {
  const _ArchiveSourceIntent();
}

class _DeleteSourceIntent extends Intent {
  const _DeleteSourceIntent();
}

class _MoveSourceIntent extends Intent {
  const _MoveSourceIntent();
}

class _MoveToLaterIntent extends Intent {
  const _MoveToLaterIntent();
}

class _KeyboardHelpIntent extends Intent {
  const _KeyboardHelpIntent();
}

class _ReaderLineDownIntent extends Intent {
  const _ReaderLineDownIntent();
}

class _ReaderLineUpIntent extends Intent {
  const _ReaderLineUpIntent();
}

class _ReaderPageDownIntent extends Intent {
  const _ReaderPageDownIntent();
}

class _ReaderPageUpIntent extends Intent {
  const _ReaderPageUpIntent();
}

class _ReaderStartIntent extends Intent {
  const _ReaderStartIntent();
}

class _ReaderEndIntent extends Intent {
  const _ReaderEndIntent();
}

class _NextAccountIntent extends Intent {
  const _NextAccountIntent();
}

class _PreviousAccountIntent extends Intent {
  const _PreviousAccountIntent();
}

class _ChooseAccountIntent extends Intent {
  const _ChooseAccountIntent();
}

class _SummarizeIntent extends Intent {
  const _SummarizeIntent();
}

class _DistributeIntent extends Intent {
  const _DistributeIntent();
}

class _IngestIntent extends Intent {
  const _IngestIntent();
}

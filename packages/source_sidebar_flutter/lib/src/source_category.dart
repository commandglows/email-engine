import 'package:flutter/material.dart';

enum SourceCategoryKind { project, tag }

/// Host-owned visual definition for a category referenced by
/// `SourceSidebarItem.tags`.
///
/// The sidebar keeps accepting tag identifiers on source items for backwards
/// compatibility. Matching identifiers are presented with this category's
/// name, color, and icon.
@immutable
class SourceCategory {
  const SourceCategory({
    required this.id,
    required this.name,
    required this.color,
    required this.icon,
    this.kind = SourceCategoryKind.tag,
  }) : assert(id != ''),
       assert(name != '');

  final String id;
  final String name;
  final Color color;
  final IconData icon;
  final SourceCategoryKind kind;
}

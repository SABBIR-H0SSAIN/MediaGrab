import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/widgets/brand_artwork.dart';
import '../providers/library_provider.dart';

/// Horizontal bar containing polished M3 filter chips for media categories and platforms:
/// All, Videos, Audio, YouTube, Facebook, Instagram.
class FilterChipsBar extends ConsumerWidget {
  const FilterChipsBar({super.key, this.selectedFilter, this.onFilterSelected});

  /// Optional override for the selected filter.
  final LibraryFilter? selectedFilter;

  /// Optional callback invoked when a filter is chosen.
  final ValueChanged<LibraryFilter>? onFilterSelected;

  Widget? _buildFilterIcon(
    LibraryFilter filter,
    ThemeData theme,
    bool isSelected,
  ) {
    switch (filter) {
      case LibraryFilter.all:
        return null;
      case LibraryFilter.videos:
        return Icon(
          Icons.play_arrow_outlined,
          size: 16,
          color:
              isSelected
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurfaceVariant,
        );
      case LibraryFilter.audio:
        return Icon(
          Icons.music_note_outlined,
          size: 16,
          color:
              isSelected
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurfaceVariant,
        );
      case LibraryFilter.youtube:
        return const PlatformLogo(platform: 'youtube', size: 18);
      case LibraryFilter.facebook:
        return const PlatformLogo(platform: 'facebook', size: 18);
      case LibraryFilter.instagram:
        return const PlatformLogo(platform: 'instagram', size: 18);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currentFilter = selectedFilter ?? ref.watch(libraryFilterProvider);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children:
            LibraryFilter.values.map((filter) {
              final isSelected = currentFilter == filter;
              final icon = _buildFilterIcon(filter, theme, isSelected);

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  avatar: icon,
                  label: Text(filter.displayName),
                  selected: isSelected,
                  showCheckmark: false,
                  checkmarkColor: theme.colorScheme.onPrimary,
                  selectedColor: theme.colorScheme.primary,
                  backgroundColor: theme.colorScheme.surfaceContainerLow,
                  side: BorderSide(
                    color:
                        isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant,
                    width: .5,
                  ),
                  labelStyle: TextStyle(
                    color:
                        isSelected
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurfaceVariant,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  onSelected: (selected) {
                    if (onFilterSelected != null) {
                      onFilterSelected!(filter);
                    } else {
                      ref.read(libraryFilterProvider.notifier).state = filter;
                    }
                  },
                ),
              );
            }).toList(),
      ),
    );
  }
}

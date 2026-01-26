import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/reference.dart';
import '../providers/references_provider.dart';

/// Reference selector widget with search and filtering
class ReferenceSelector extends StatefulWidget {
  final Reference? selectedReference;
  final ValueChanged<Reference?> onChanged;
  final bool showFilters;
  
  const ReferenceSelector({
    super.key,
    this.selectedReference,
    required this.onChanged,
    this.showFilters = false,
  });

  @override
  State<ReferenceSelector> createState() => _ReferenceSelectorState();
}

class _ReferenceSelectorState extends State<ReferenceSelector> {
  final _searchController = TextEditingController();
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ReferencesProvider>(
      builder: (context, refsProvider, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search field
            if (widget.showFilters) ...[
              TextField(
                controller: _searchController,
                onChanged: (value) => refsProvider.setSearchQuery(value),
                decoration: InputDecoration(
                  hintText: 'Rechercher une référence...',
                  prefixIcon: const Icon(Icons.search, size: 22),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            refsProvider.setSearchQuery('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: AppColors.surfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              
              const SizedBox(height: 12),
              
              // Filter chips
              Wrap(
                spacing: 8,
                children: [
                  _FilterChip(
                    label: 'Composants',
                    isSelected: refsProvider.showComponents,
                    onSelected: refsProvider.toggleComponents,
                  ),
                  _FilterChip(
                    label: 'Semi-finis',
                    isSelected: refsProvider.showSemiFinal,
                    onSelected: refsProvider.toggleSemiFinal,
                  ),
                  _FilterChip(
                    label: 'Produits finis',
                    isSelected: refsProvider.showFinal,
                    onSelected: refsProvider.toggleFinal,
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
            ],
            
            // Dropdown
            DropdownButtonFormField<Reference>(
              value: widget.selectedReference,
              decoration: InputDecoration(
                labelText: 'Référence',
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              items: [
                const DropdownMenuItem<Reference>(
                  value: null,
                  child: Text('- Choisir référence -'),
                ),
                ...refsProvider.filteredReferences.map((ref) => DropdownMenuItem<Reference>(
                  value: ref,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          ref.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getTypeColor(ref.referenceType).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          ref.typeLabel,
                          style: TextStyle(
                            fontSize: 10,
                            color: _getTypeColor(ref.referenceType),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
              ],
              onChanged: widget.onChanged,
              isExpanded: true,
            ),
          ],
        );
      },
    );
  }
  
  Color _getTypeColor(int type) {
    switch (type) {
      case 0:
        return AppColors.statusNeutral;
      case 1:
        return AppColors.warning;
      case 2:
        return AppColors.success;
      default:
        return AppColors.textSecondary;
    }
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Function(bool) onSelected;
  
  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: isSelected ? Colors.white : AppColors.textSecondary,
        ),
      ),
      selected: isSelected,
      onSelected: onSelected,
      backgroundColor: AppColors.surfaceVariant,
      selectedColor: AppColors.primary,
      checkmarkColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide.none,
    );
  }
}

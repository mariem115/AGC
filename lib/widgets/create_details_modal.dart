import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/draft_item.dart';
import '../models/reference.dart';
import '../providers/references_provider.dart';

/// Modal for creating/editing media details
class CreateDetailsModal extends StatefulWidget {
  final String imagePath;
  final bool isVideo;
  final DraftItem? existingDraft;
  final Function(DraftItem) onSaveDraft;
  final Function(DraftItem) onSaveFinal;

  const CreateDetailsModal({
    super.key,
    required this.imagePath,
    required this.isVideo,
    this.existingDraft,
    required this.onSaveDraft,
    required this.onSaveFinal,
  });

  @override
  State<CreateDetailsModal> createState() => _CreateDetailsModalState();
}

class _CreateDetailsModalState extends State<CreateDetailsModal> {
  final _searchController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _filterIconKey = GlobalKey();
  final _overlayPortalController = OverlayPortalController();
  
  // Filter states
  bool _filterComponents = true;
  bool _filterSemiFinis = true;
  bool _filterProduitsFinis = true;
  bool _showFilterDropdown = false;
  
  // Selected values
  Reference? _selectedReference;
  int _qualityStatus = 6; // Default to Neutre
  
  // Validation
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadExistingDraftData();
    // Fetch fresh references when modal opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchAndRestoreReference();
    });
  }
  
  /// Fetch fresh references and restore selected reference from draft
  Future<void> _fetchAndRestoreReference() async {
    final refsProvider = context.read<ReferencesProvider>();
    await refsProvider.fetchReferences();
    
    // After fetching, try to restore the selected reference from draft
    if (widget.existingDraft?.referenceId != null && _selectedReference == null) {
      _tryRestoreReference();
    }
  }
  
  /// Try to find and restore the selected reference from draft
  void _tryRestoreReference() {
    if (widget.existingDraft?.referenceId != null) {
      final refs = context.read<ReferencesProvider>().allReferences;
      try {
        final found = refs.firstWhere((r) => r.id == widget.existingDraft!.referenceId);
        setState(() {
          _selectedReference = found;
        });
      } catch (_) {
        // Reference not found in list
      }
    }
  }
  
  /// Toggle filter dropdown visibility
  void _toggleFilterDropdown() {
    setState(() {
      _showFilterDropdown = !_showFilterDropdown;
    });
  }
  
  /// Close filter dropdown
  void _closeFilterDropdown() {
    if (_showFilterDropdown) {
      setState(() {
        _showFilterDropdown = false;
      });
    }
  }
  
  /// Get count of active filters for badge display
  int get _activeFilterCount {
    int count = 0;
    if (_filterComponents) count++;
    if (_filterSemiFinis) count++;
    if (_filterProduitsFinis) count++;
    return count;
  }

  /// Load existing draft data into form fields (called once on init)
  /// This restores: description, quality status, and attempts to find reference
  void _loadExistingDraftData() {
    if (widget.existingDraft != null) {
      final draft = widget.existingDraft!;
      _descriptionController.text = draft.description ?? '';
      _qualityStatus = draft.qualityStatus;
      
      // Try to find the reference from cached list first
      // (will be re-attempted after fresh fetch)
      if (draft.referenceId != null) {
        final refs = context.read<ReferencesProvider>().allReferences;
        try {
          _selectedReference = refs.firstWhere((r) => r.id == draft.referenceId);
        } catch (_) {
          // Reference not found in cached list, will retry after fetch
        }
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  List<Reference> _getFilteredReferences() {
    final refs = context.watch<ReferencesProvider>().allReferences;
    final searchQuery = _searchController.text.toLowerCase();
    
    return refs.where((ref) {
      // Filter by type
      final matchesType = (_filterComponents && ref.isComponent) ||
          (_filterSemiFinis && ref.isSemiFinal) ||
          (_filterProduitsFinis && ref.isFinal);
      
      // Filter by search (search in name, displayName, and designation)
      final matchesSearch = searchQuery.isEmpty ||
          ref.name.toLowerCase().contains(searchQuery) ||
          ref.displayName.toLowerCase().contains(searchQuery) ||
          (ref.designation?.toLowerCase().contains(searchQuery) ?? false);
      
      return matchesType && matchesSearch;
    }).toList();
  }

  DraftItem _buildDraftItem() {
    final now = DateTime.now();
    return DraftItem(
      id: widget.existingDraft?.id,
      filePath: widget.imagePath,
      isVideo: widget.isVideo,
      referenceId: _selectedReference?.id,
      referenceName: _selectedReference?.name,
      referenceType: _selectedReference?.referenceType,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      qualityStatus: _qualityStatus,
      createdAt: widget.existingDraft?.createdAt ?? now,
      updatedAt: now,
      isDraft: true,
    );
  }

  void _saveDraft() {
    if (_isSaving) return;
    
    setState(() => _isSaving = true);
    final draft = _buildDraftItem();
    widget.onSaveDraft(draft);
  }

  /// Validate form fields for final save
  /// Returns error message if validation fails, null if valid
  String? _validateForm() {
    if (_selectedReference == null) {
      return 'Veuillez sélectionner une référence';
    }
    // Quality is always selected (default is Neutre=6), but check anyway
    if (_qualityStatus != 4 && _qualityStatus != 5 && _qualityStatus != 6) {
      return 'Veuillez sélectionner une qualité';
    }
    return null; // Valid
  }
  
  /// Show validation error dialog
  void _showValidationError(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 24),
            SizedBox(width: 8),
            Text(
              'Champs requis',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(fontFamily: 'Poppins'),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Compris'),
          ),
        ],
      ),
    );
  }
  
  void _saveFinal() {
    if (_isSaving) return;
    
    // Validate required fields
    final validationError = _validateForm();
    if (validationError != null) {
      _showValidationError(validationError);
      return;
    }
    
    _doSaveFinal();
  }

  void _doSaveFinal() {
    setState(() => _isSaving = true);
    final draft = _buildDraftItem().copyWith(isDraft: false);
    widget.onSaveFinal(draft);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.existingDraft != null ? 'Modifier Détails' : 'Créer Détails',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.surfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          
          // Content
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                bottom: bottomPadding + 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search input with filter icon
                  _buildSearchBarWithFilter(),
                  
                  const SizedBox(height: 20),
                  
                  // Reference dropdown
                  const Text(
                    'Références',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildReferenceDropdown(),
                  
                  const SizedBox(height: 20),
                  
                  // Description textarea
                  const Text(
                    'Description',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descriptionController,
                    maxLength: 500,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Ajouter une description...',
                      filled: true,
                      fillColor: AppColors.surfaceVariant,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Quality radio options
                  const Text(
                    'Qualité',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildQualityOptions(),
                  
                  const SizedBox(height: 24),
                  
                  // Action buttons
                  _buildActionButtons(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build search bar with filter icon that shows dropdown on click
  Widget _buildSearchBarWithFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search input with filter icon
        TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Rechercher par nom',
            prefixIcon: const Icon(Icons.search_rounded, size: 22),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Clear button (when text is present)
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 20),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                    },
                  ),
                // Filter icon with badge showing active filter count
                Stack(
                  children: [
                    IconButton(
                      key: _filterIconKey,
                      icon: Icon(
                        Icons.filter_list_rounded,
                        size: 22,
                        color: _showFilterDropdown 
                            ? AppColors.primary 
                            : AppColors.textSecondary,
                      ),
                      onPressed: _toggleFilterDropdown,
                    ),
                    // Badge showing count of active filters (only if not all selected)
                    if (_activeFilterCount < 3 && _activeFilterCount > 0)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '$_activeFilterCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            filled: true,
            fillColor: AppColors.surfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
        
        // Filter dropdown (shown when _showFilterDropdown is true)
        if (_showFilterDropdown)
          TapRegion(
            onTapOutside: (_) => _closeFilterDropdown(),
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: AppColors.border, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Filtrer par type',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _FilterCheckbox(
                        label: 'Composants',
                        value: _filterComponents,
                        onChanged: (v) => setState(() => _filterComponents = v ?? true),
                      ),
                      _FilterCheckbox(
                        label: 'Semi-Finis',
                        value: _filterSemiFinis,
                        onChanged: (v) => setState(() => _filterSemiFinis = v ?? true),
                      ),
                      _FilterCheckbox(
                        label: 'Produits Finis',
                        value: _filterProduitsFinis,
                        onChanged: (v) => setState(() => _filterProduitsFinis = v ?? true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildReferenceDropdown() {
    final filteredRefs = _getFilteredReferences();
    final refsProvider = context.watch<ReferencesProvider>();
    
    // Show loading indicator while fetching references
    if (refsProvider.isLoading) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text(
              'Chargement des références...',
              style: TextStyle(fontFamily: 'Poppins', color: AppColors.textLight),
            ),
          ],
        ),
      );
    }
    
    // Show error if fetching failed
    if (refsProvider.error != null && filteredRefs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                refsProvider.error!,
                style: const TextStyle(fontFamily: 'Poppins', color: AppColors.error, fontSize: 12),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: () => refsProvider.fetchReferences(),
            ),
          ],
        ),
      );
    }
    
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonFormField<Reference>(
        value: _selectedReference,
        isExpanded: true,
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: InputBorder.none,
        ),
        hint: const Text(
          '- Sélectionner une référence -',
          style: TextStyle(fontFamily: 'Poppins', color: AppColors.textLight),
        ),
        items: [
          const DropdownMenuItem<Reference>(
            value: null,
            child: Text(
              '- Aucune référence -',
              style: TextStyle(fontFamily: 'Poppins', color: AppColors.textLight),
            ),
          ),
          ...filteredRefs.map((ref) => DropdownMenuItem<Reference>(
            value: ref,
            child: Text(
              ref.displayName, // Use displayName: "name (designation)"
              style: const TextStyle(fontFamily: 'Poppins'),
              overflow: TextOverflow.ellipsis,
            ),
          )),
        ],
        onChanged: (value) {
          setState(() => _selectedReference = value);
        },
      ),
    );
  }

  Widget _buildQualityOptions() {
    return Row(
      children: [
        _QualityRadio(
          label: 'Bonne',
          value: 4,
          groupValue: _qualityStatus,
          color: AppColors.statusOK,
          onChanged: (v) => setState(() => _qualityStatus = v!),
        ),
        const SizedBox(width: 8),
        _QualityRadio(
          label: 'Mauvaise',
          value: 5,
          groupValue: _qualityStatus,
          color: AppColors.statusNOK,
          onChanged: (v) => setState(() => _qualityStatus = v!),
        ),
        const SizedBox(width: 8),
        _QualityRadio(
          label: 'Neutre',
          value: 6,
          groupValue: _qualityStatus,
          color: AppColors.statusNeutral,
          onChanged: (v) => setState(() => _qualityStatus = v!),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _isSaving ? null : _saveDraft,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Sauv. Brouillon',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: _isSaving ? null : _saveFinal,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Text(
                    'Sauvegarder',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600),
                  ),
          ),
        ),
      ],
    );
  }
}

class _FilterCheckbox extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool?> onChanged;

  const _FilterCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: value ? AppColors.primary.withValues(alpha: 0.1) : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: value ? AppColors.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              size: 20,
              color: value ? AppColors.primary : AppColors.textLight,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: value ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QualityRadio extends StatelessWidget {
  final String label;
  final int value;
  final int groupValue;
  final Color color;
  final ValueChanged<int?> onChanged;

  const _QualityRadio({
    required this.label,
    required this.value,
    required this.groupValue,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == groupValue;
    
    return Expanded(
      child: InkWell(
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color : color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? color : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 18,
                color: isSelected ? Colors.white : color,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

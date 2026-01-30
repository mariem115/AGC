import 'dart:async';

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
  // Note: _overlayPortalController reserved for future use with OverlayPortal widget
  
  // PERFORMANCE: Debounce timer for search input
  // Prevents excessive filtering operations while user is typing.
  // Instead of filtering on every keystroke (h, he, hel, hell, hello = 5 operations),
  // we wait 300ms after the user stops typing, then filter once.
  Timer? _debounceTimer;
  
  // PERFORMANCE: Local search query that updates after debounce
  // This separates the text field value from the actual filter query,
  // so the UI responds instantly but filtering is delayed.
  String _debouncedSearchQuery = '';
  
  // Filter states
  bool _filterComponents = true;
  bool _filterSemiFinis = true;
  bool _filterProduitsFinis = true;
  bool _showFilterDropdown = false;
  
  // PERFORMANCE: Track if reference list is expanded
  // Using an expandable list instead of DropdownButtonFormField
  // allows us to use ListView.builder for lazy loading
  bool _isReferenceListExpanded = false;
  
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
  
  /// PERFORMANCE: Debounced search handler
  /// 
  /// Instead of updating the filter immediately on every keystroke,
  /// this method waits 300ms after the user stops typing.
  /// 
  /// Example: Typing "hello" quickly
  /// - Without debounce: 5 filter operations (h, he, hel, hell, hello)
  /// - With debounce: 1 filter operation (hello, after 300ms pause)
  /// 
  /// This reduces CPU usage and makes the UI feel more responsive.
  void _onSearchChanged(String value) {
    // Cancel any existing timer (user is still typing)
    _debounceTimer?.cancel();
    
    // Start a new 300ms timer
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      // This only runs if user hasn't typed for 300ms
      if (mounted) {
        setState(() {
          _debouncedSearchQuery = value;
        });
      }
    });
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
    // PERFORMANCE: Cancel debounce timer to prevent memory leaks
    // If the widget is disposed while a timer is pending, we must cancel it
    _debounceTimer?.cancel();
    _searchController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  List<Reference> _getFilteredReferences() {
    final refs = context.watch<ReferencesProvider>().allReferences;
    // PERFORMANCE: Use debounced search query instead of reading directly from controller
    // This means filtering only runs when the debounce timer completes,
    // not on every keystroke, significantly reducing CPU usage while typing.
    final searchQuery = _debouncedSearchQuery.toLowerCase();
    
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
    
    // Extract primitive values explicitly to avoid serialization issues
    // This prevents _Namespace errors by ensuring only int/String values are used
    final int? refId = _selectedReference?.id;
    final String? refName = _selectedReference?.name;
    final int? refType = _selectedReference?.referenceType;
    
    return DraftItem(
      id: widget.existingDraft?.id,
      filePath: widget.imagePath,
      isVideo: widget.isVideo,
      referenceId: refId,
      referenceName: refName,
      referenceType: refType,
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
    // Suppressed for demo - validation logic remains
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
                  
                  // Reference selector (lazy-loaded list for performance)
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
                  _buildReferenceSelector(),
                  
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
          // PERFORMANCE: Use debounced handler instead of immediate setState
          // This prevents filtering on every keystroke, reducing CPU usage
          onChanged: _onSearchChanged,
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
                      // When clearing, update immediately (no debounce needed)
                      _debounceTimer?.cancel();
                      _searchController.clear();
                      setState(() {
                        _debouncedSearchQuery = '';
                      });
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

  /// PERFORMANCE IMPROVEMENT: Replaced DropdownButtonFormField with custom expandable list
  /// 
  /// Why this is faster:
  /// - DropdownButtonFormField creates ALL items in memory at once (1000 refs = 1000 widgets)
  /// - ListView.builder only creates widgets for VISIBLE items (~10-15 at a time)
  /// - This reduces memory usage and prevents crashes with large datasets
  Widget _buildReferenceSelector() {
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
    
    // Show error if fetching failed - suppressed for demo
    if (refsProvider.error != null && filteredRefs.isEmpty) {
      // Suppressed for demo - show empty state instead
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Aucune référence disponible',
                style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }
    
    return Column(
      children: [
        // Tappable selection field (shows current selection)
        _buildSelectionField(filteredRefs.length),
        
        // Expandable list of references (only visible when expanded)
        // PERFORMANCE: AnimatedContainer + ListView.builder = smooth & efficient
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: _isReferenceListExpanded ? 200 : 0,
          child: _isReferenceListExpanded
              ? _buildLazyReferenceList(filteredRefs)
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
  
  /// Tappable field showing current selection
  Widget _buildSelectionField(int totalCount) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isReferenceListExpanded = !_isReferenceListExpanded;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: _isReferenceListExpanded
              ? Border.all(color: AppColors.primary, width: 1.5)
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _selectedReference?.displayName ?? '- Sélectionner une référence -',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: _selectedReference != null
                      ? AppColors.textPrimary
                      : AppColors.textLight,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Show count badge
            if (totalCount > 0)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$totalCount',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            // Dropdown arrow
            AnimatedRotation(
              turns: _isReferenceListExpanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  /// PERFORMANCE: ListView.builder creates items LAZILY (only visible ones)
  /// This is the key optimization - instead of 1000 widgets, only ~10 are created
  Widget _buildLazyReferenceList(List<Reference> filteredRefs) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ListView.builder(
          padding: EdgeInsets.zero,
          // PERFORMANCE: itemCount tells Flutter exactly how many items exist
          // but only visible items are actually built
          itemCount: filteredRefs.length + 1, // +1 for "none" option
          itemBuilder: (context, index) {
            // First item is always "no selection" option
            if (index == 0) {
              return _buildReferenceListItem(
                null,
                '- Aucune référence -',
                isSelected: _selectedReference == null,
              );
            }
            
            // Remaining items are actual references
            // PERFORMANCE: This builder is only called for VISIBLE items
            final ref = filteredRefs[index - 1];
            return _buildReferenceListItem(
              ref,
              ref.displayName,
              isSelected: _selectedReference?.id == ref.id,
              referenceType: ref.referenceType,
            );
          },
        ),
      ),
    );
  }
  
  /// Single item in the reference list
  Widget _buildReferenceListItem(
    Reference? ref,
    String displayText, {
    required bool isSelected,
    int? referenceType,
  }) {
    return InkWell(
      onTap: () {
        setState(() {
          _selectedReference = ref;
          _isReferenceListExpanded = false; // Close list after selection
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.08) : null,
          border: Border(
            bottom: BorderSide(
              color: AppColors.border.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            // Selection indicator
            if (isSelected)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
              ),
            // Reference name
            Expanded(
              child: Text(
                displayText,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: ref == null ? AppColors.textLight : AppColors.textPrimary,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Type badge (for actual references)
            if (referenceType != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _getTypeColor(referenceType).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _getTypeLabel(referenceType),
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: _getTypeColor(referenceType),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  /// Get color for reference type badge
  Color _getTypeColor(int type) {
    switch (type) {
      case 1:
        return AppColors.primary;
      case 2:
        return AppColors.warning;
      case 3:
        return AppColors.success;
      default:
        return AppColors.textSecondary;
    }
  }
  
  /// Get label for reference type badge
  String _getTypeLabel(int type) {
    switch (type) {
      case 1:
        return 'Comp.';
      case 2:
        return 'Semi';
      case 3:
        return 'Fini';
      default:
        return '?';
    }
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

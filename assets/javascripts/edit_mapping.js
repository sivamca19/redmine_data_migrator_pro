document.addEventListener('DOMContentLoaded', function() {
  // Handle mapping type changes
  document.querySelectorAll('.mapping-type-select').forEach(function(select) {
    select.addEventListener('change', function() {
      var row = this.closest('.field-mapping-row');
      var targetCell = row.querySelector('.target-field');
      var selectedType = this.value;

      // Hide all options
      targetCell.querySelectorAll('.manual-mapping-options, .auto-detect-info, .ignore-info').forEach(function(el) {
        el.style.display = 'none';
      });

      // Show relevant options
      if (selectedType === 'manual') {
        targetCell.querySelector('.manual-mapping-options').style.display = 'block';
        // Show standard field options by default
        var manualTypeSelect = targetCell.querySelector('.manual-type-select');
        updateManualFieldOptions(targetCell, manualTypeSelect.value);
      } else if (selectedType === 'auto') {
        targetCell.querySelector('.auto-detect-info').style.display = 'block';
      } else if (selectedType === 'ignore') {
        targetCell.querySelector('.ignore-info').style.display = 'block';
      }
    });
  });

  // Handle manual type sub-selection
  document.addEventListener('change', function(e) {
    if (e.target.classList.contains('manual-type-select')) {
      var targetCell = e.target.closest('.target-field');
      updateManualFieldOptions(targetCell, e.target.value);
    }
  });

  function updateManualFieldOptions(targetCell, manualType) {
    // Hide both sub-options
    var standardOptions = targetCell.querySelector('.standard-field-options');
    var customOptions = targetCell.querySelector('.custom-field-options');

    if (standardOptions) standardOptions.style.display = 'none';
    if (customOptions) customOptions.style.display = 'none';

    // Show selected option
    if (manualType === 'standard' && standardOptions) {
      standardOptions.style.display = 'block';
    } else if (manualType === 'custom' && customOptions) {
      customOptions.style.display = 'block';
    }
  }

  // Initialize manual field options for already selected rows
  document.querySelectorAll('.manual-type-select').forEach(function(select) {
    var targetCell = select.closest('.target-field');
    updateManualFieldOptions(targetCell, select.value);
  });
});
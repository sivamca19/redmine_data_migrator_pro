// External Asset Configurations JavaScript
$(document).ready(function() {
  initializeEventHandlers();
  initializeForm();
});

function initializeEventHandlers() {
  // System type selector change handler
  $('.system-type-selector').on('change', function() {
    loadCredentialFields($(this).val());
  });

  // Advanced settings toggle
  $('.toggle-advanced').on('click', toggleAdvancedSettings);

  // Test connection handler
  $(document).on('click', '.test-connection-btn', handleTestConnection);
}

function toggleAdvancedSettings(e) {
  e.preventDefault();
  var $advanced = $('.advanced-section');
  var $link = $(this);

  if ($advanced.is(':visible')) {
    $advanced.slideUp();
    $link.text('Show Advanced Settings');
  } else {
    $advanced.slideDown();
    $link.text('Hide Advanced Settings');
  }
}

function handleTestConnection(e) {
  e.preventDefault();
  var $btn = $(this);
  var originalText = $btn.text();

  // Disable button and show loading
  $btn.prop('disabled', true).text('Testing...');
  clearPreviousResults();

  $.ajax({
    url: $btn.attr('href'),
    type: 'GET',
    dataType: 'json',
    success: function(response) {
      handleTestConnectionResponse(response, $btn, originalText);
    },
    error: function(xhr) {
      handleTestConnectionError(xhr, $btn, originalText);
    }
  });
}

function clearPreviousResults() {
  $('#connection-test-result').hide();
  $('.test-connection-result').removeClass('success error').text('');
}

function loadCredentialFields(systemType) {
  var $container = $('.system-specific-fields');

  if (!systemType) {
    $container.empty();
    return;
  }

  showLoadingState($container);

  $.ajax({
    url: '/external_asset_configs/system_fields',
    type: 'GET',
    data: {
      system_type: systemType,
      config_id: $container.data('config-id'),
      persisted: $container.data('persisted')
    },
    success: function(html) {
      $container.html(html);
      updateRequiredFields(systemType);
    },
    error: function(xhr) {
      showErrorState($container, 'Failed to load credential fields. Please try again.');
      console.error('Failed to load credential fields:', xhr.responseText || xhr.statusText);
    }
  });
}

function showLoadingState($container) {
  $container.html('<p class="loading">Loading credential fields...</p>');
}

function showErrorState($container, message) {
  $container.html('<p class="error">' + message + '</p>');
}

function updateRequiredFields(systemType) {
  // Remove all required attributes first
  $('.system-specific-fields input').removeAttr('required');

  // Check if this is a new configuration
  var isNewConfig = $('.box.tabular').data('config-mode') === 'new';

  // Only add required attributes for new configurations
  if (!isNewConfig) {
    return; // Don't make fields required when editing existing configurations
  }

  // Add required attributes based on system type for new configs only
  switch(systemType) {
    case 'jira':
      $('.system-specific-fields input[name$="[email]"]').attr('required', 'required');
      $('.system-specific-fields input[name$="[api_token]"]').attr('required', 'required');
      break;
    case 'clickup':
      $('.system-specific-fields input[name$="[api_key]"]').attr('required', 'required');
      break;
    case 'asana':
      $('.system-specific-fields input[name$="[api_token]"]').attr('required', 'required');
      break;
    case 'trello':
      $('.system-specific-fields input[name$="[api_key]"]').attr('required', 'required');
      $('.system-specific-fields input[name$="[api_token]"]').attr('required', 'required');
      break;
    case 'monday':
      $('.system-specific-fields input[name$="[api_key]"]').attr('required', 'required');
      break;
  }
}

function handleTestConnectionResponse(response, $btn, originalText) {
  $btn.prop('disabled', false).text(originalText);

  if (response.success) {
    showConnectionResult('success', response.message);
    $('.test-connection-result').addClass('success').text('✓ Connected');

    // Show success animation
    $btn.addClass('test-success');
    setTimeout(function() {
      $btn.removeClass('test-success');
    }, 2000);

    // Update any credential status indicators
    updateCredentialStatus(true);
  } else {
    showConnectionResult('error', response.message);
    $('.test-connection-result').addClass('error').text('✗ Failed');

    // Show error animation
    $btn.addClass('test-error');
    setTimeout(function() {
      $btn.removeClass('test-error');
    }, 2000);
  }
}

function handleTestConnectionError(xhr, $btn, originalText) {
  $btn.prop('disabled', false).text(originalText);

  var message = 'Connection test failed';
  if (xhr.responseJSON && xhr.responseJSON.message) {
    message = xhr.responseJSON.message;
  } else if (xhr.statusText) {
    message += ': ' + xhr.statusText;
  }

  showConnectionResult('error', message);
  $('.test-connection-result').addClass('error').text('✗ Failed');
}

function showConnectionResult(type, message) {
  var $result = $('#connection-test-result');

  $result.removeClass('notice error warning')
         .addClass(type === 'success' ? 'notice' : 'error')
         .text(message)
         .show();

  // Auto-hide after 5 seconds
  setTimeout(function() {
    $result.fadeOut();
  }, 5000);
}

function initializeForm() {
  // Load appropriate credential fields based on initial system type
  var initialSystemType = $('.system-type-selector').val();
  if (initialSystemType) {
    loadCredentialFields(initialSystemType);
  }

  // Set up form validation
  setupFormValidation();
}

function setupFormValidation() {
  // Custom validation for Base URL format
  $('input[name$="[base_url]"]').on('blur', function() {
    var $input = $(this);
    var url = $input.val();

    if (url && !isValidUrl(url)) {
      $input.addClass('error');
      showValidationMessage($input, 'Please enter a valid URL starting with http:// or https://');
    } else {
      $input.removeClass('error');
      hideValidationMessage($input);
    }
  });
}

function isValidUrl(string) {
  try {
    var url = new URL(string);
    return url.protocol === 'http:' || url.protocol === 'https:';
  } catch (_) {
    return false;
  }
}

function showValidationMessage($input, message) {
  hideValidationMessage($input);
  $input.after('<span class="validation-error" style="color: #D9534F; font-size: 11px; margin-left: 5px;">' + message + '</span>');
}

function hideValidationMessage($input) {
  $input.siblings('.validation-error').remove();
}

function updateCredentialStatus(connected) {
  // Update credential status in show view
  var $credentialStatus = $('.attribute .value .icon');
  if ($credentialStatus.length) {
    if (connected) {
      $credentialStatus.removeClass('icon-warning').addClass('icon-ok').text('Configured & Connected');
    }
  }

  // Update any status indicators in listing pages
  $('.missing-credentials').each(function() {
    if (connected) {
      $(this).removeClass('missing-credentials').text('Configured');
    }
  });
}

// Auto-generate configuration name based on system type and URL
$(document).on('change', '.system-type-selector, input[name$="[base_url]"]', function() {
  var $nameField = $('input[name$="[name]"]');

  // Only auto-generate if name field is empty
  if ($nameField.val() === '') {
    var systemType = $('.system-type-selector').val();
    var baseUrl = $('input[name$="[base_url]"]').val();

    if (systemType && baseUrl) {
      try {
        var url = new URL(baseUrl);
        var hostname = url.hostname;
        var suggestedName = systemType.charAt(0).toUpperCase() + systemType.slice(1) + ' - ' + hostname;
        $nameField.val(suggestedName);
      } catch (e) {
        // Invalid URL, skip auto-generation
      }
    }
  }
});
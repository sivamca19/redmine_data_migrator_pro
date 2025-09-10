// Data Migrator Plugin JavaScript

$(document).ready(function() {

  // File upload drag and drop
  var fileUploadArea = $('.file-upload-area');
  var fileInput = $('#data_migration_file');

  if (fileUploadArea.length && fileInput.length) {
    // Drag and drop events
    fileUploadArea.on('dragover dragenter', function(e) {
      e.preventDefault();
      e.stopPropagation();
      $(this).addClass('dragover');
    });

    fileUploadArea.on('dragleave dragend', function(e) {
      e.preventDefault();
      e.stopPropagation();
      $(this).removeClass('dragover');
    });

    fileUploadArea.on('drop', function(e) {
      e.preventDefault();
      e.stopPropagation();
      $(this).removeClass('dragover');

      var files = e.originalEvent.dataTransfer.files;
      if (files.length > 0) {
        fileInput[0].files = files;
        updateFileInfo(files[0]);
      }
    });

    // File input change event
    fileInput.on('change', function() {
      var files = this.files;
      if (files.length > 0) {
        updateFileInfo(files[0]);
      }
    });
  }

  // Update file information display
  function updateFileInfo(file) {
    var info = '<strong>' + file.name + '</strong><br>';
    info += 'Size: ' + formatFileSize(file.size) + '<br>';
    info += 'Type: ' + file.type;

    $('.file-info').html(info);
  }

  // Format file size
  function formatFileSize(bytes) {
    if (bytes === 0) return '0 Bytes';
    var k = 1024;
    var sizes = ['Bytes', 'KB', 'MB', 'GB'];
    var i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  }

  // Auto-refresh processing status
  if ($('.status-processing').length > 0) {
    var refreshInterval = setInterval(function() {
      // Check if we're still on the same page
      if ($('.status-processing').length === 0) {
        clearInterval(refreshInterval);
        return;
      }

      // Reload the page to update status
      location.reload();
    }, 10000); // Refresh every 10 seconds
  }

  // Field mapping assistance
  $('.field-mapping-select').each(function() {
    var select = $(this);
    var header = select.data('header');

    if (header) {
      // Auto-suggest mapping based on header name
      autoSuggestMapping(select, header);
    }
  });

  // Auto-suggest field mapping
  function autoSuggestMapping(select, header) {
    var headerLower = header.toLowerCase();
    var options = select.find('option');

    var mappings = {
      'subject': ['subject', 'title', 'name', 'summary'],
      'description': ['description', 'details', 'notes', 'body'],
      'status': ['status', 'state'],
      'priority': ['priority', 'importance'],
      'assignee': ['assignee', 'assigned', 'owner'],
      'reporter': ['reporter', 'creator', 'author'],
      'tracker': ['tracker', 'type', 'kind'],
      'due_date': ['due', 'deadline', 'target'],
      'created_on': ['created', 'start'],
      'updated_on': ['updated', 'modified']
    };

    options.each(function() {
      var option = $(this);
      var value = option.val();

      if (mappings[value]) {
        var keywords = mappings[value];
        for (var i = 0; i < keywords.length; i++) {
          if (headerLower.includes(keywords[i])) {
            select.val(value);
            return;
          }
        }
      }
    });
  }

  // Form validation
  $('#migration-form').on('submit', function(e) {
    var fileInput = $('#data_migration_file');
    var sourceType = $('#data_migration_source_type');

    if (!fileInput.val()) {
      alert('Please select a file to upload.');
      e.preventDefault();
      return false;
    }

    if (!sourceType.val()) {
      alert('Please select a source system.');
      e.preventDefault();
      return false;
    }

    // Check file size (50MB limit)
    var file = fileInput[0].files[0];
    if (file && file.size > 50 * 1024 * 1024) {
      alert('File size must be less than 50MB.');
      e.preventDefault();
      return false;
    }

    // Check file extension
    var allowedExtensions = ['.csv', '.xls', '.xlsx'];
    var fileName = file.name.toLowerCase();
    var isValidExtension = allowedExtensions.some(function(ext) {
      return fileName.endsWith(ext);
    });

    if (!isValidExtension) {
      alert('Please upload a CSV, XLS, or XLSX file.');
      e.preventDefault();
      return false;
    }
  });

  // Processing form validation
  $('#processing-form').on('submit', function(e) {
    var projectId = $('#project_id');

    if (!projectId.val()) {
      alert('Please select a project.');
      e.preventDefault();
      return false;
    }

    // Confirm processing start
    var confirmed = confirm('Are you sure you want to start processing this migration? This action cannot be undone.');
    if (!confirmed) {
      e.preventDefault();
      return false;
    }
  });

  // Toggle field mapping details
  $('.field-mapping-toggle').on('click', function(e) {
    e.preventDefault();
    var target = $(this).data('target');
    $(target).toggle();

    var text = $(this).text();
    $(this).text(text === 'Show Details' ? 'Hide Details' : 'Show Details');
  });

  // Copy error details to clipboard
  $('.copy-error').on('click', function(e) {
    e.preventDefault();
    var errorText = $(this).siblings('.error-details').text();

    // Create temporary textarea to copy text
    var temp = $('<textarea>');
    $('body').append(temp);
    temp.val(errorText).select();
    document.execCommand('copy');
    temp.remove();

    // Show feedback
    var button = $(this);
    var originalText = button.text();
    button.text('Copied!').addClass('copied');

    setTimeout(function() {
      button.text(originalText).removeClass('copied');
    }, 2000);
  });

});
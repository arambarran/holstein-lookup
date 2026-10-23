/* Keep Shiny's file transport; handle drops once, across the whole upload area. */
(function () {
  'use strict';

  function setSetupBusy(message) {
    const fields = document.getElementById('setup-fields');
    fields.disabled = message.busy;
    document.getElementById('run').disabled = !message.canRun;

    const column = document.getElementById('id_column');
    if (column.selectize) {
      if (message.busy || !message.hasUpload) column.selectize.disable();
      else column.selectize.enable();
    }

    fields.querySelectorAll('a').forEach(function (link) {
      link.setAttribute('aria-disabled', String(message.busy));
      link.tabIndex = message.busy ? -1 : 0;
    });
    const browse = fields.querySelector('.btn-file');
    browse.setAttribute('aria-disabled', String(message.busy));
    browse.tabIndex = message.busy ? -1 : 0;
  }

  function fileError(files) {
    if (files.length !== 1) return 'Choose one CSV file at a time.';
    if (!/\.csv$/i.test(files[0].name)) return 'Please choose a .csv file.';
    if (files[0].size > 25 * 1024 * 1024) return 'The file exceeds the 25 MB limit.';
    return '';
  }

  function showFileError(message) {
    document.getElementById('upload-error').textContent = message;
    document.querySelector('.upload-area').classList.toggle('has-error', Boolean(message));
  }

  function acceptDroppedFile(event) {
    event.preventDefault();
    event.stopPropagation();
    event.currentTarget.classList.remove('is-dragging');
    const fields = document.getElementById('setup-fields');
    if (fields.disabled || !event.dataTransfer.files.length) return;

    const files = event.dataTransfer.files;
    const error = fileError(files);
    showFileError(error);
    if (error) return;
    const input = document.getElementById('csv');
    input.files = files;
    // A real change event also runs our validation before Shiny starts transport.
    input.dispatchEvent(new Event('change', { bubbles: true }));
  }

  $(document).on('shiny:connected', function () {
    Shiny.addCustomMessageHandler('lookupBusy', setSetupBusy);
  });

  $(function () {
    const area = document.querySelector('.upload-area');
    const input = document.getElementById('csv');
    const browse = area.querySelector('.btn-file');
    browse.setAttribute('role', 'button');
    browse.setAttribute('aria-label', 'Choose CSV file');
    browse.tabIndex = 0;
    browse.addEventListener('keydown', function (event) {
      if (event.key !== 'Enter' && event.key !== ' ') return;
      event.preventDefault();
      if (!document.getElementById('setup-fields').disabled) input.click();
    });
    input.setAttribute('aria-describedby', 'upload-error');
    input.tabIndex = -1;
    input.setAttribute('aria-hidden', 'true');
    area.querySelector('input[type="text"]').setAttribute('aria-label', 'Selected CSV file');
    input.addEventListener('change', function (event) {
      if (!input.files.length) return;
      const error = fileError(input.files);
      showFileError(error);
      if (error) {
        event.stopImmediatePropagation();
        input.value = '';
        return;
      }
      // Prevent running the previous file while its replacement is uploading.
      document.getElementById('run').disabled = true;
    }, true);

    ['dragenter', 'dragover'].forEach(function (eventName) {
      area.addEventListener(eventName, function (event) {
        event.preventDefault();
        event.stopPropagation();
        if (!document.getElementById('setup-fields').disabled) {
          area.classList.add('is-dragging');
        }
      }, true);
    });
    area.addEventListener('dragleave', function (event) {
      if (!area.contains(event.relatedTarget)) area.classList.remove('is-dragging');
    });
    // Capture prevents Shiny's nested input-group handler uploading the same drop.
    area.addEventListener('drop', acceptDroppedFile, true);

    document.addEventListener('click', function (event) {
      const picker = document.querySelector('.column-picker');
      if (!picker.contains(event.target)) picker.open = false;
    });
    document.addEventListener('keydown', function (event) {
      const picker = document.querySelector('.column-picker');
      if (event.key === 'Escape' && picker.open) {
        picker.open = false;
        picker.querySelector('summary').focus();
      }
    });
  });
}());

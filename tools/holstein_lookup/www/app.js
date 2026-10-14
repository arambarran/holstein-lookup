/* Browser-only behavior: lock setup during a run and accept dropped CSV files. */
(function () {
  'use strict';

  function setSetupBusy(message) {
    const fields = document.getElementById('setup-fields');
    fields.disabled = message.busy;

    fields.querySelectorAll('select').forEach(function (select) {
      if (!select.selectize) return;
      if (message.busy) select.selectize.disable();
      else select.selectize.enable();
    });

    fields.querySelectorAll('a').forEach(function (link) {
      link.setAttribute('aria-disabled', String(message.busy));
      link.tabIndex = message.busy ? -1 : 0;
    });
  }

  function acceptDroppedFile(event) {
    event.preventDefault();
    event.stopPropagation();
    event.currentTarget.classList.remove('is-dragging');

    const busy = document.getElementById('setup-fields').disabled;
    if (busy || !event.dataTransfer.files.length) return;

    const transfer = new DataTransfer();
    transfer.items.add(event.dataTransfer.files[0]);
    const input = document.getElementById('csv');
    input.files = transfer.files;
    $(input).trigger('change');
  }

  $(document).on('shiny:connected', function () {
    Shiny.addCustomMessageHandler('lookupBusy', setSetupBusy);
  });

  $(function () {
    const area = document.querySelector('.upload-area');
    ['dragenter', 'dragover'].forEach(function (eventName) {
      area.addEventListener(eventName, function (event) {
        event.preventDefault();
        if (!document.getElementById('setup-fields').disabled) {
          area.classList.add('is-dragging');
        }
      });
    });
    area.addEventListener('dragleave', function () {
      area.classList.remove('is-dragging');
    });
    area.addEventListener('drop', acceptDroppedFile);
  });
}());

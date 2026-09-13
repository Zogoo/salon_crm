import { Component, input } from '@angular/core';

/**
 * A Material Symbol. Icons are decorative here — every one sits next to a text
 * label, so it is hidden from screen readers rather than read out twice.
 */
@Component({
  selector: 'ui-icon',
  template: `<span class="material-symbols-outlined" aria-hidden="true">{{ name() }}</span>`,
  styles: `
    :host {
      display: inline-flex;
    }
    .material-symbols-outlined {
      font-variation-settings:
        'FILL' var(--fill, 0),
        'wght' 400,
        'GRAD' 0,
        'opsz' 24;
      // The icon *is* a ligature, so it must not be disabled by a reset.
      font-feature-settings: 'liga';
      // Reserve the glyph's box so layout does not shift when the font lands.
      min-width: var(--size, 20px);
      text-align: center;
      font-size: var(--size, 20px);
      line-height: 1;
      user-select: none;
    }
  `,
})
export class UiIcon {
  readonly name = input.required<string>();
}

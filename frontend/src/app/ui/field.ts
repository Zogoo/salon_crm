import { Component, input } from '@angular/core';

/**
 * Label, control, hint and error in one place (M3 text field).
 *
 * The hint is the "don't make me guess" slot: it says what the field expects
 * *before* the reader gets it wrong, rather than only correcting them after.
 */
@Component({
  selector: 'ui-field',
  template: `
    <label class="field">
      <span class="field__label">
        {{ label() }}
        @if (optional()) {
          <span class="field__optional">optional</span>
        }
      </span>
      <ng-content />
      @if (error()) {
        <span class="field__error" role="alert">{{ error() }}</span>
      } @else if (hint()) {
        <span class="field__hint">{{ hint() }}</span>
      }
    </label>
  `,
  styleUrl: './field.scss',
})
export class UiField {
  readonly label = input.required<string>();
  readonly hint = input<string | undefined>(undefined);
  readonly error = input<string | undefined>(undefined);
  readonly optional = input(false);
}

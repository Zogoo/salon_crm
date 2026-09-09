import { Component, computed, input } from '@angular/core';

import { UiIcon } from './icon';

export type ButtonVariant = 'filled' | 'tonal' | 'outlined' | 'text' | 'danger';

/**
 * The one button in the app (M3 common buttons).
 *
 * Variants carry meaning, so a screen picks by intent rather than by colour:
 * `filled` is the single primary action on a view, `tonal` a secondary one,
 * `outlined`/`text` are low emphasis, and `danger` is destructive.
 */
@Component({
  selector: 'ui-button',
  imports: [UiIcon],
  template: `
    <button
      [type]="type()"
      [class]="classes()"
      [disabled]="disabled()"
      [attr.aria-label]="ariaLabel() || null"
    >
      @if (icon()) { <ui-icon [name]="icon()!" /> }
      <span class="label"><ng-content /></span>
    </button>
  `,
  styleUrl: './button.scss',
})
export class UiButton {
  readonly variant = input<ButtonVariant>('filled');
  readonly icon = input<string | undefined>(undefined);
  readonly type = input<'button' | 'submit'>('button');
  readonly disabled = input(false);
  readonly full = input(false);
  readonly ariaLabel = input<string | undefined>(undefined);

  protected readonly classes = computed(() => `btn btn--${this.variant()}${this.full() ? ' btn--full' : ''}`);
}

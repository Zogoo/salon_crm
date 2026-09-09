import { Component, input } from '@angular/core';

export type ChipTone = 'neutral' | 'success' | 'error' | 'warning' | 'info';

/** A short status word — a booking's state, a shift's, a card's. */
@Component({
  selector: 'ui-chip',
  template: `<span [class]="'chip chip--' + tone()"><ng-content /></span>`,
  styles: `
    @use '../../styles/tokens' as *;

    .chip {
      @include type-label-md;
      display: inline-flex;
      align-items: center;
      padding: var(--sp-1) var(--sp-3);
      border-radius: var(--md-shape-sm);
      white-space: nowrap;
      text-transform: capitalize;
    }
    .chip--neutral { background: var(--md-surface-container-high); color: var(--md-on-surface-variant); }
    .chip--success { background: var(--md-success-container); color: var(--md-on-success-container); }
    .chip--error { background: var(--md-error-container); color: var(--md-on-error-container); }
    .chip--warning { background: var(--md-warning-container); color: var(--md-on-warning-container); }
    .chip--info { background: var(--md-secondary-container); color: var(--md-on-secondary-container); }
  `,
})
export class UiChip {
  readonly tone = input<ChipTone>('neutral');
}

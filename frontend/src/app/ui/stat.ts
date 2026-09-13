import { Component, input } from '@angular/core';

/**
 * A single number with its label. Used for the dashboard tiles and the report
 * summaries, which were previously two different sets of markup for the same
 * idea.
 *
 * `hint` exists because a bare number invites the wrong reading — "Fees owed"
 * next to "$18.00" says nothing about whether that money has been collected.
 */
@Component({
  selector: 'ui-stat',
  template: `
    <p class="stat__label">{{ label() }}</p>
    <p class="stat__value">{{ value() }}</p>
    @if (hint()) {
      <p class="stat__hint">{{ hint() }}</p>
    }
  `,
  styles: `
    @use '../../styles/tokens' as *;

    :host {
      display: flex;
      flex-direction: column;
      gap: var(--sp-1);
      padding: var(--sp-4);
      background: var(--md-surface-container-lowest);
      border: 1px solid var(--md-outline-variant);
      border-radius: var(--md-shape-md);
      min-width: 0;
    }
    :host([tone='primary']) {
      background: var(--md-primary-container);
      border-color: transparent;
      color: var(--md-on-primary-container);
    }
    .stat__label {
      @include type-label-md;
      text-transform: uppercase;
      color: var(--md-on-surface-variant);
      :host([tone='primary']) & {
        color: inherit;
      }
    }
    .stat__value {
      @include type-headline-sm;
      font-variant-numeric: tabular-nums;
    }
    .stat__hint {
      @include type-body-sm;
      color: var(--md-on-surface-variant);
      :host([tone='primary']) & {
        color: inherit;
      }
    }
  `,
})
export class UiStat {
  readonly label = input.required<string>();
  readonly value = input.required<string | number>();
  readonly hint = input<string | undefined>(undefined);
}

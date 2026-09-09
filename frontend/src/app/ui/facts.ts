import { Component, input } from '@angular/core';

export interface Fact {
  label: string;
  value: string | number | null | undefined;
  /** Says how to read the number when the label alone would mislead. */
  hint?: string;
}

/**
 * Label-and-value pairs. Every screen was building its own definition list;
 * this is that list, with the empty case handled once (an absent value reads
 * as "—" rather than as a blank that looks like a bug).
 */
@Component({
  selector: 'ui-facts',
  template: `
    <dl class="facts">
      @for (f of items(); track f.label) {
        <div>
          <dt>{{ f.label }}</dt>
          <dd>{{ f.value ?? '—' }}</dd>
          @if (f.hint) { <p class="facts__hint">{{ f.hint }}</p> }
        </div>
      }
    </dl>
  `,
  styles: `
    @use '../../styles/tokens' as *;

    .facts {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(9rem, 1fr));
      gap: var(--sp-3);
      margin: 0;
    }
    dt { @include type-label-md; text-transform: uppercase; color: var(--md-on-surface-variant); }
    dd { @include type-body-md; margin: 0; }
    .facts__hint { @include type-body-sm; color: var(--md-on-surface-variant); margin-top: var(--sp-1); }
  `,
})
export class UiFacts {
  readonly items = input.required<Fact[]>();
}

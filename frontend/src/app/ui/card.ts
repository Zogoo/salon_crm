import { Component, input } from '@angular/core';

/**
 * An M3 surface. Optional heading so the common "titled panel" case does not
 * make every screen hand-roll the same header markup.
 */
@Component({
  selector: 'ui-card',
  template: `
    @if (heading()) {
      <header class="card__head">
        <div>
          <h2 class="card__title">{{ heading() }}</h2>
          @if (sub()) { <p class="card__sub">{{ sub() }}</p> }
        </div>
        <ng-content select="[cardAction]" />
      </header>
    }
    <div class="card__body"><ng-content /></div>
  `,
  styles: `
    @use '../../styles/tokens' as *;

    :host {
      display: flex;
      flex-direction: column;
      gap: var(--sp-4);
      padding: var(--sp-4);
      background: var(--md-surface-container-lowest);
      border: 1px solid var(--md-outline-variant);
      border-radius: var(--md-shape-md);
    }
    @include medium-up { :host { padding: var(--sp-5); } }

    .card__head {
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
      gap: var(--sp-3);
      flex-wrap: wrap;
    }
    .card__title { @include type-title-md; }
    .card__sub {
      @include type-body-sm;
      color: var(--md-on-surface-variant);
      margin-top: var(--sp-1);
      max-width: 60ch;
    }
    .card__body { display: flex; flex-direction: column; gap: var(--sp-4); }
  `,
})
export class UiCard {
  readonly heading = input<string | undefined>(undefined);
  readonly sub = input<string | undefined>(undefined);
}

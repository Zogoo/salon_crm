import { Component, input } from '@angular/core';

/**
 * Every screen's outer frame: title, one line saying what the screen is for,
 * an actions slot, and the content.
 *
 * The subtitle is not decoration. A console like this is used by people who
 * were trained once, months ago; a screen that states its own purpose is the
 * cheapest way to stop them guessing.
 */
@Component({
  selector: 'ui-page',
  template: `
    <header class="page__head">
      <div class="page__titles">
        <h1 class="page__title">{{ title() }}</h1>
        @if (sub()) {
          <p class="page__sub">{{ sub() }}</p>
        }
      </div>
      <div class="page__actions"><ng-content select="[pageActions]" /></div>
    </header>
    <div class="page__body"><ng-content /></div>
  `,
  styles: `
    @use '../../styles/tokens' as *;

    :host {
      display: flex;
      flex-direction: column;
      gap: var(--sp-5);
    }

    .page__head {
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
      gap: var(--sp-4);
      flex-wrap: wrap;
    }
    .page__title {
      @include type-headline-sm;
    }
    .page__sub {
      @include type-body-md;
      color: var(--md-on-surface-variant);
      margin-top: var(--sp-1);
      max-width: 70ch;
    }
    .page__actions {
      display: flex;
      gap: var(--sp-2);
      flex-wrap: wrap;
    }

    .page__body {
      display: flex;
      flex-direction: column;
      gap: var(--sp-4);
    }
  `,
})
export class UiPage {
  readonly title = input.required<string>();
  readonly sub = input<string | undefined>(undefined);
}

import { Component, computed, input } from '@angular/core';

import { UiIcon } from './icon';

export type BannerTone = 'error' | 'success' | 'info' | 'warning';

/**
 * Feedback after an action, and the only place the app renders an error.
 *
 * A banner always says what happened in plain words — the API's `code` is for
 * branching, never for reading, so callers pass a sentence.
 */
@Component({
  selector: 'ui-banner',
  imports: [UiIcon],
  template: `
    <div [class]="'banner banner--' + tone()" [attr.role]="tone() === 'error' ? 'alert' : 'status'">
      <ui-icon [name]="iconName()" />
      <p class="banner__text"><ng-content /></p>
    </div>
  `,
  styles: `
    @use '../../styles/tokens' as *;

    .banner {
      display: flex;
      gap: var(--sp-3);
      align-items: flex-start;
      padding: var(--sp-3) var(--sp-4);
      border-radius: var(--md-shape-sm);
    }
    .banner__text {
      @include type-body-md;
    }
    .banner--error {
      background: var(--md-error-container);
      color: var(--md-on-error-container);
    }
    .banner--success {
      background: var(--md-success-container);
      color: var(--md-on-success-container);
    }
    .banner--warning {
      background: var(--md-warning-container);
      color: var(--md-on-warning-container);
    }
    .banner--info {
      background: var(--md-secondary-container);
      color: var(--md-on-secondary-container);
    }
  `,
})
export class UiBanner {
  readonly tone = input<BannerTone>('info');

  protected readonly iconName = computed(
    () =>
      ({ error: 'error', success: 'check_circle', warning: 'warning', info: 'info' })[this.tone()],
  );
}
